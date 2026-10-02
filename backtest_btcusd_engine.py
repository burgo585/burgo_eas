import os
import argparse
import numpy as np
import pandas as pd
from datetime import datetime

# ==============================================================================
# MOTOR DE BACKTEST ORIENTADO A ORDENS E RISCO REALISTA
# ==============================================================================

def prepare_indicators(df, atr_period=14, lookback_pvsra=10, ema_fast=50, ema_slow=200):
    df = df.copy()
    if 'datetime' in df.columns:
        df['datetime'] = pd.to_datetime(df['datetime'])
        df.sort_values('datetime', inplace=True)
        df.reset_index(drop=True, inplace=True)

    # Médias Móveis
    df['ema_fast'] = df['close'].ewm(span=ema_fast, adjust=False).mean()
    df['ema_slow'] = df['close'].ewm(span=ema_slow, adjust=False).mean()

    # ATR (True Range)
    prev_close = df['close'].shift(1)
    tr1 = df['high'] - df['low']
    tr2 = (df['high'] - prev_close).abs()
    tr3 = (df['low'] - prev_close).abs()
    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    df['atr'] = tr.rolling(atr_period).mean()

    # PVSRA
    avg_vol = df['tick_volume'].rolling(lookback_pvsra).mean()
    candle_spread = (df['close'] - df['open']).abs()
    avg_spread = candle_spread.rolling(lookback_pvsra).mean()

    cond_climax = (df['tick_volume'] >= 2.0 * avg_vol) | ((df['tick_volume'] * candle_spread) >= (2.0 * avg_vol * avg_spread))
    cond_high = df['tick_volume'] >= 1.5 * avg_vol

    df['pvsra'] = 0  # Normal
    df.loc[cond_high, 'pvsra'] = 1   # High
    df.loc[cond_climax, 'pvsra'] = 2 # Climax

    return df

def run_simulation(df, rr_ratio=2.0, atr_multiplier=1.5, risk_percent=1.0, initial_balance=10000.0, point_value=0.01, session_filter=False, max_spread_drag_pct=5.0):
    """
    Executa simulação barra a barra sem viés de antecipação (lookahead bias).
    Entrada na abertura da barra t+1 após o sinal fechado na barra t.
    Inclui validações de segurança Sunrise GuardRail:
      - Trava de Spread Drag (< 5% do alvo de TP)
      - Filtro de Janela Institucional de Liquidez (Londres e NY nos dias úteis)
    """
    n = len(df)
    opens = df['open'].values
    highs = df['high'].values
    lows = df['low'].values
    closes = df['close'].values
    spreads = df['spread'].values * point_value  # Spread em USD
    atrs = df['atr'].values
    pvsras = df['pvsra'].values
    ema_fasts = df['ema_fast'].values
    ema_slows = df['ema_slow'].values
    dates = df['datetime'].values if 'datetime' in df.columns else np.arange(n)
    
    # Horas e dias para filtro institucional
    dt_series = pd.to_datetime(dates)
    hours = dt_series.hour.values
    dows = dt_series.dayofweek.values

    trades = []
    in_position = False
    pos_type = 0  # 1 = Buy, -1 = Sell
    entry_price = 0.0
    sl_price = 0.0
    tp_price = 0.0
    entry_idx = 0
    trade_risk_amount = 0.0
    balance = initial_balance
    equity_curve = [initial_balance]
    equity_dates = [dates[0]]

    # Começa após estabilização dos indicadores (200 barras)
    for i in range(200, n - 1):
        # 1. GERENCIAMENTO DE POSIÇÃO ATIVA
        if in_position:
            h = highs[i]
            l = lows[i]
            c = closes[i]
            exit_trade = False
            exit_price = 0.0
            outcome = ""

            if pos_type == 1: # Compra
                hit_sl = l <= sl_price
                hit_tp = h >= tp_price

                if hit_sl and hit_tp:
                    exit_price = sl_price
                    outcome = "SL"
                    exit_trade = True
                elif hit_sl:
                    exit_price = sl_price
                    outcome = "SL"
                    exit_trade = True
                elif hit_tp:
                    exit_price = tp_price
                    outcome = "TP"
                    exit_trade = True

            elif pos_type == -1: # Venda
                hit_sl = h >= sl_price
                hit_tp = l <= tp_price

                if hit_sl and hit_tp:
                    exit_price = sl_price
                    outcome = "SL"
                    exit_trade = True
                elif hit_sl:
                    exit_price = sl_price
                    outcome = "SL"
                    exit_trade = True
                elif hit_tp:
                    exit_price = tp_price
                    outcome = "TP"
                    exit_trade = True

            if exit_trade:
                # Cálculo do PnL
                if pos_type == 1:
                    price_diff = exit_price - entry_price
                    r_multiple = price_diff / (entry_price - sl_price) if (entry_price - sl_price) > 0 else 0
                else:
                    price_diff = entry_price - exit_price
                    r_multiple = price_diff / (sl_price - entry_price) if (sl_price - entry_price) > 0 else 0

                pnl = r_multiple * trade_risk_amount
                balance += pnl

                trades.append({
                    'entry_idx': entry_idx,
                    'exit_idx': i,
                    'entry_date': dates[entry_idx],
                    'exit_date': dates[i],
                    'type': 'BUY' if pos_type == 1 else 'SELL',
                    'entry_price': entry_price,
                    'exit_price': exit_price,
                    'sl': sl_price,
                    'tp': tp_price,
                    'outcome': outcome,
                    'r_multiple': r_multiple,
                    'pnl': pnl,
                    'balance': balance,
                    'duration_bars': i - entry_idx
                })

                in_position = False
                pos_type = 0

        # Atualiza curva de patrimônio
        equity_curve.append(balance)
        equity_dates.append(dates[i])

        # 2. VERIFICAÇÃO DE NOVO SINAL (Apenas se desposicionado)
        if not in_position and not np.isnan(atrs[i]) and atrs[i] > 0:
            # Trava GuardRail 1: Sessão Institucional (Londres 8-12h e NY 15-19h em dias úteis)
            if session_filter:
                is_london = (8 <= hours[i] < 12)
                is_ny = (15 <= hours[i] < 19)
                is_weekday = (dows[i] < 5)
                if not ((is_london or is_ny) and is_weekday):
                    continue

            c = closes[i]
            o = opens[i]
            pvsra = pvsras[i]
            trend_up = (c > ema_slows[i]) and (ema_fasts[i] > ema_slows[i])
            trend_down = (c < ema_slows[i]) and (ema_fasts[i] < ema_slows[i])
            volume_trigger = (pvsra in [1, 2])

            buy_signal = trend_up and volume_trigger and (c > o)
            sell_signal = trend_down and volume_trigger and (c < o)

            if buy_signal or sell_signal:
                next_open = opens[i + 1]
                spread = spreads[i + 1]
                atr = atrs[i]

                sl_distance = atr * atr_multiplier
                if sl_distance <= 0:
                    continue

                tp_distance = sl_distance * rr_ratio

                # Trava GuardRail 2: Spread Drag
                spread_drag_pct = (spread / tp_distance) * 100.0
                if max_spread_drag_pct is not None and spread_drag_pct > max_spread_drag_pct:
                    # Bloqueado pelo GuardRail por canibalização de lucro
                    continue

                pos_type = 1 if buy_signal else -1
                entry_idx = i + 1
                trade_risk_amount = balance * (risk_percent / 100.0)

                if pos_type == 1:
                    entry_price = next_open + spread # Paga spread na compra
                    sl_price = entry_price - sl_distance
                    tp_price = entry_price + tp_distance
                else:
                    entry_price = next_open          # Venda entra no bid
                    sl_price = entry_price + sl_distance + spread
                    tp_price = entry_price - tp_distance

                in_position = True

    df_trades = pd.DataFrame(trades)
    df_equity = pd.DataFrame({'datetime': equity_dates, 'equity': equity_curve})

    return df_trades, df_equity

def compute_metrics(df_trades, df_equity, initial_balance=10000.0):
    if df_trades.empty:
        return {"total_trades": 0}

    total_trades = len(df_trades)
    wins = df_trades[df_trades['pnl'] > 0]
    losses = df_trades[df_trades['pnl'] <= 0]

    win_rate = (len(wins) / total_trades) * 100.0
    final_balance = df_equity['equity'].iloc[-1]
    total_net_profit = final_balance - initial_balance
    total_return_pct = (total_net_profit / initial_balance) * 100.0

    gross_profit = wins['pnl'].sum() if not wins.empty else 0.0
    gross_loss = abs(losses['pnl'].sum()) if not losses.empty else 1.0
    profit_factor = gross_profit / gross_loss if gross_loss > 0 else np.nan

    avg_win = wins['pnl'].mean() if not wins.empty else 0.0
    avg_loss = abs(losses['pnl'].mean()) if not losses.empty else 0.0
    payoff_ratio = avg_win / avg_loss if avg_loss > 0 else np.nan

    # Drawdown Máximo
    df_equity['peak'] = df_equity['equity'].cummax()
    df_equity['drawdown'] = (df_equity['equity'] - df_equity['peak']) / df_equity['peak'] * 100.0
    max_drawdown = abs(df_equity['drawdown'].min())

    # Sharpe Ratio (diário aproximado)
    returns = df_equity['equity'].pct_change().dropna()
    sharpe = (returns.mean() / returns.std()) * np.sqrt(252 * 24 * 4) if returns.std() > 0 else 0.0 # Anualizado para M15

    return {
        "total_trades": total_trades,
        "win_rate": win_rate,
        "total_return_pct": total_return_pct,
        "profit_factor": profit_factor,
        "payoff_ratio": payoff_ratio,
        "max_drawdown": max_drawdown,
        "sharpe_ratio": sharpe,
        "avg_duration_bars": df_trades['duration_bars'].mean(),
        "final_balance": final_balance
    }

def main():
    parser = argparse.ArgumentParser(description="Motor de Backtest Institucional BTCUSD")
    parser.add_argument("--file", type=str, default="data/BTCUSD_M15.parquet", help="Caminho do arquivo parquet")
    parser.add_argument("--risk", type=float, default=1.0, help="Risco percentual por trade")
    parser.add_argument("--atr_mult", type=float, default=1.5, help="Multiplicador de ATR para Stop Loss")
    args = parser.parse_args()

    if not os.path.exists(args.file):
        print(f"Arquivo não encontrado: {args.file}")
        return

    print(f"Carregando: {args.file}...")
    df = pd.read_parquet(args.file)
    print(f"Total de barras: {len(df):,}")

    df_ind = prepare_indicators(df)

    print("\n" + "="*70)
    print(f"{'TESTE QUANTITATIVO: OTIMIZAÇÃO DE PAYOFF / RISK-TO-REWARD':^70}")
    print("="*70)
    print(f"{'R:R':<6} | {'Trades':<8} | {'Win Rate':<10} | {'Profit Fact':<12} | {'Max DD':<10} | {'Retorno Total':<14}")
    print("-"*70)

    results = []
    for rr in [1.5, 2.0, 2.5, 3.0]:
        df_trades, df_equity = run_simulation(df_ind, rr_ratio=rr, atr_multiplier=args.atr_mult, risk_percent=args.risk)
        metrics = compute_metrics(df_trades, df_equity)
        metrics['rr'] = rr
        results.append((metrics, df_trades, df_equity))
        print(f"1:{rr:<4.1f} | {metrics['total_trades']:<8} | {metrics['win_rate']:<9.2f}% | {metrics['profit_factor']:<12.2f} | {metrics['max_drawdown']:<9.2f}% | {metrics['total_return_pct']:<+13.2f}%")

    print("="*70)

if __name__ == "__main__":
    main()
