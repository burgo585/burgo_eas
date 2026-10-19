import pandas as pd
import numpy as np

def load_and_prepare_data(filepath='data/BTCUSD_M15.parquet'):
    df = pd.read_parquet(filepath)
    df['datetime'] = pd.to_datetime(df['datetime'])
    df.sort_values('datetime', inplace=True)
    df.reset_index(drop=True, inplace=True)

    # Indicadores
    df['ema_50'] = df['close'].ewm(span=50, adjust=False).mean()
    df['ema_200'] = df['close'].ewm(span=200, adjust=False).mean()
    tr = pd.concat([
        df['high'] - df['low'],
        (df['high'] - df['close'].shift(1)).abs(),
        (df['low'] - df['close'].shift(1)).abs()
    ], axis=1).max(axis=1)
    df['atr'] = tr.rolling(14).mean()

    avg_vol = df['tick_volume'].rolling(10).mean()
    c_spread = (df['close'] - df['open']).abs()
    avg_c_spread = c_spread.rolling(10).mean()
    df['pvsra'] = 0
    df.loc[df['tick_volume'] >= 1.5 * avg_vol, 'pvsra'] = 1
    df.loc[(df['tick_volume'] >= 2.0 * avg_vol) | ((df['tick_volume'] * c_spread) >= 2.0 * avg_vol * avg_c_spread), 'pvsra'] = 2

    return df

def simulate_engine(df, mode='baseline', be_trigger_atr=1.0, partial_pct=0.5, partial_trigger_atr=1.0,
                    initial_capital=1000.0, risk_pct=1.0, sl_atr_mult=1.5, tp_atr_mult=3.0,
                    session_filter=True, max_spread_drag_pct=5.0):
    """
    Simulação quantitativa exaustiva barra a barra:
    mode:
      - 'baseline': SL fixo 1.5 ATR, TP fixo 3.0 ATR
      - 'breakeven_only': Ao atingir be_trigger_atr, SL é movido para entry_price + spread
      - 'partial_and_be': Ao atingir partial_trigger_atr, realiza partial_pct e move SL para entry_price + spread
    """
    n = len(df)
    opens = df['open'].values
    highs = df['high'].values
    lows = df['low'].values
    closes = df['close'].values
    spreads = df['spread'].values * 0.01  # Spread em USD
    atrs = df['atr'].values
    pvsras = df['pvsra'].values
    ema_50s = df['ema_50'].values
    ema_200s = df['ema_200'].values
    dates = pd.to_datetime(df['datetime'].values)
    hours = dates.hour.values
    dows = dates.dayofweek.values

    balance = initial_capital
    trades = []
    
    in_pos = False
    pos_type = 0 # 1=Buy, -1=Sell
    lot_size = 0.0
    active_lot = 0.0
    entry_p = 0.0
    curr_sl = 0.0
    curr_tp = 0.0
    be_active = False
    partial_done = False
    partial_profit = 0.0
    entry_idx = 0
    
    equity_curve = [initial_capital]

    for i in range(200, n - 1):
        if in_pos:
            h = highs[i]
            l = lows[i]
            c = closes[i]
            atr_entry = atrs[entry_idx - 1]
            
            # 1. VERIFICAR SE GATILHO DE BREAKEVEN / PARCIAL FOI ATINGIDO NA BARRA
            if mode in ['breakeven_only', 'partial_and_be']:
                if pos_type == 1: # Compra
                    favorable_dist = h - entry_p
                    # Checa Parcial
                    if mode == 'partial_and_be' and not partial_done:
                        if favorable_dist >= (partial_trigger_atr * atr_entry):
                            partial_lot = active_lot * partial_pct
                            # Preço realizado na parcial: gatilho
                            realized_p = entry_p + (partial_trigger_atr * atr_entry)
                            partial_profit = (realized_p - entry_p) * partial_lot
                            balance += partial_profit
                            active_lot -= partial_lot
                            partial_done = True
                            # Automaticamente ativa breakeven após a parcial
                            curr_sl = entry_p + spreads[entry_idx]
                            be_active = True

                    # Checa Breakeven Puro
                    elif mode == 'breakeven_only' and not be_active:
                        if favorable_dist >= (be_trigger_atr * atr_entry):
                            curr_sl = entry_p + spreads[entry_idx]
                            be_active = True

                elif pos_type == -1: # Venda
                    favorable_dist = entry_p - l
                    # Checa Parcial
                    if mode == 'partial_and_be' and not partial_done:
                        if favorable_dist >= (partial_trigger_atr * atr_entry):
                            partial_lot = active_lot * partial_pct
                            realized_p = entry_p - (partial_trigger_atr * atr_entry)
                            partial_profit = (entry_p - realized_p) * partial_lot
                            balance += partial_profit
                            active_lot -= partial_lot
                            partial_done = True
                            curr_sl = entry_p - spreads[entry_idx]
                            be_active = True

                    # Checa Breakeven Puro
                    elif mode == 'breakeven_only' and not be_active:
                        if favorable_dist >= (be_trigger_atr * atr_entry):
                            curr_sl = entry_p - spreads[entry_idx]
                            be_active = True

            # 2. VERIFICAR SAÍDA (SL / TP)
            exit_trade = False
            exit_p = 0.0
            outcome = ""

            if pos_type == 1:
                hit_sl = l <= curr_sl
                hit_tp = h >= curr_tp

                if hit_sl and hit_tp:
                    exit_p = curr_sl
                    outcome = "BE" if be_active else "SL"
                    exit_trade = True
                elif hit_sl:
                    exit_p = curr_sl
                    outcome = "BE" if be_active else "SL"
                    exit_trade = True
                elif hit_tp:
                    exit_p = curr_tp
                    outcome = "TP"
                    exit_trade = True

            elif pos_type == -1:
                hit_sl = h >= curr_sl
                hit_tp = l <= curr_tp

                if hit_sl and hit_tp:
                    exit_p = curr_sl
                    outcome = "BE" if be_active else "SL"
                    exit_trade = True
                elif hit_sl:
                    exit_p = curr_sl
                    outcome = "BE" if be_active else "SL"
                    exit_trade = True
                elif hit_tp:
                    exit_p = curr_tp
                    outcome = "TP"
                    exit_trade = True

            if exit_trade:
                rem_pnl = (exit_p - entry_p) * active_lot if pos_type == 1 else (entry_p - exit_p) * active_lot
                total_trade_pnl = partial_profit + rem_pnl
                balance += rem_pnl # partial_profit já foi adicionado ao balance
                
                trades.append({
                    'entry_date': dates[entry_idx],
                    'exit_date': dates[i],
                    'type': 'BUY' if pos_type == 1 else 'SELL',
                    'outcome': outcome,
                    'pnl': total_trade_pnl,
                    'balance': balance,
                    'partial_done': partial_done,
                    'be_active': be_active,
                    'duration_bars': i - entry_idx
                })

                in_pos = False
                pos_type = 0
                partial_profit = 0.0

        equity_curve.append(balance)

        # 3. NOVO SINAL (Apenas desposicionado)
        if not in_pos and not np.isnan(atrs[i]) and atrs[i] > 0:
            if session_filter:
                is_london = (8 <= hours[i] < 12)
                is_ny = (15 <= hours[i] < 19)
                is_weekday = (dows[i] < 5)
                if not ((is_london or is_ny) and is_weekday):
                    continue

            c, o = closes[i], opens[i]
            vol_ok = pvsras[i] in [1, 2]
            buy_sig = (c > ema_200s[i]) and (ema_50s[i] > ema_200s[i]) and vol_ok and (c > o)
            sell_sig = (c < ema_200s[i]) and (ema_50s[i] < ema_200s[i]) and vol_ok and (c < o)

            if buy_sig or sell_sig:
                next_o = opens[i+1]
                spread = spreads[i+1]
                sl_dist = atrs[i] * sl_atr_mult
                tp_dist = sl_dist * (tp_atr_mult / sl_atr_mult)

                # Trava Spread Drag
                if (spread / tp_dist) * 100.0 > max_spread_drag_pct:
                    continue

                risk_usd = balance * (risk_pct / 100.0)
                raw_lot = risk_usd / sl_dist
                lot_size = max(0.01, min(100.0, np.floor(raw_lot / 0.01) * 0.01))
                active_lot = lot_size

                pos_type = 1 if buy_sig else -1
                entry_idx = i + 1

                if pos_type == 1:
                    entry_p = next_o + spread
                    curr_sl = entry_p - sl_dist
                    curr_tp = entry_p + tp_dist
                else:
                    entry_p = next_o
                    curr_sl = entry_p + sl_dist + spread
                    curr_tp = entry_p - tp_dist

                be_active = False
                partial_done = False
                partial_profit = 0.0
                in_pos = True

    df_trades = pd.DataFrame(trades)
    df_equity = pd.DataFrame({'equity': equity_curve})
    return df_trades, df_equity

def evaluate_metrics(df_trades, df_equity, initial_capital=1000.0):
    if df_trades.empty:
        return {
            'trades': 0, 'win_rate': 0.0, 'profit_factor': 0.0,
            'total_return': 0.0, 'max_dd': 0.0, 'final_balance': initial_capital,
            'tp_count': 0, 'be_count': 0, 'sl_count': 0
        }

    total = len(df_trades)
    wins = df_trades[df_trades['pnl'] > 0]
    losses = df_trades[df_trades['pnl'] < 0]
    breakevens = df_trades[df_trades['pnl'] == 0]

    gross_win = wins['pnl'].sum() if not wins.empty else 0.0
    gross_loss = abs(losses['pnl'].sum()) if not losses.empty else 1e-6
    pf = gross_win / gross_loss

    final_bal = df_equity['equity'].iloc[-1]
    ret_pct = ((final_bal - initial_capital) / initial_capital) * 100.0

    df_equity['peak'] = df_equity['equity'].cummax()
    df_equity['dd'] = (df_equity['equity'] - df_equity['peak']) / df_equity['peak'] * 100.0
    max_dd = abs(df_equity['dd'].min())

    tp_c = (df_trades['outcome'] == 'TP').sum()
    be_c = (df_trades['outcome'] == 'BE').sum()
    sl_c = (df_trades['outcome'] == 'SL').sum()

    return {
        'trades': total,
        'win_rate': (len(wins) / total) * 100.0,
        'profit_factor': pf,
        'total_return': ret_pct,
        'max_dd': max_dd,
        'final_balance': final_bal,
        'tp_count': tp_c,
        'be_count': be_c,
        'sl_count': sl_c
    }

if __name__ == '__main__':
    print("Preparando dados M15...")
    df = load_and_prepare_data('data/BTCUSD_M15.parquet')
    print(f"Dados carregados: {len(df):,} barras.")

    split_date = pd.to_datetime('2026-01-01 00:00:00+00:00')
    df_is = df[df['datetime'] < split_date].copy()
    df_oos = df[df['datetime'] >= split_date].copy()

    scenarios = [
        ('1. BASELINE (Sem BE, Sem Parcial - Sistema Atual)', 'baseline', 0.0, 0.0, 0.0),
        ('2. BREAKEVEN Puro em +0.75x ATR', 'breakeven_only', 0.75, 0.0, 0.0),
        ('3. BREAKEVEN Puro em +1.00x ATR', 'breakeven_only', 1.00, 0.0, 0.0),
        ('4. BREAKEVEN Puro em +1.25x ATR', 'breakeven_only', 1.25, 0.0, 0.0),
        ('5. BREAKEVEN Puro em +1.50x ATR (1:1 Risco)', 'breakeven_only', 1.50, 0.0, 0.0),
        ('6. PARCIAL 50% em +1.00x ATR + BE', 'partial_and_be', 1.00, 0.5, 1.00),
        ('7. PARCIAL 50% em +1.50x ATR (1:1) + BE', 'partial_and_be', 1.50, 0.5, 1.50),
        ('8. PARCIAL 33% em +1.00x ATR + BE', 'partial_and_be', 1.00, 0.33, 1.00),
    ]

    print("\n" + "="*95)
    print("TESTE EXAUSTIVO COMPLETO: PERÍODO TOTAL (2024 - 2026)")
    print("="*95)
    print(f"{'Cenário':<42} | {'Trades':<6} | {'Win%':<6} | {'PF':<5} | {'MaxDD%':<6} | {'Retorno%':<8} | {'TP':<4} | {'BE':<4} | {'SL':<4}")
    print("-"*95)

    all_results = []
    for name, mode, be_trig, part_pct, part_trig in scenarios:
        tr, eq = simulate_engine(df, mode=mode, be_trigger_atr=be_trig, partial_pct=part_pct, partial_trigger_atr=part_trig)
        m = evaluate_metrics(tr, eq)
        print(f"{name:<42} | {m['trades']:<6} | {m['win_rate']:<5.1f}% | {m['profit_factor']:<5.2f} | {m['max_dd']:<5.1f}% | {m['total_return']:<+7.1f}% | {m['tp_count']:<4} | {m['be_count']:<4} | {m['sl_count']:<4}")
        all_results.append((name, m))

    print("\n" + "="*95)
    print("TESTE OUT-OF-SAMPLE (2026 - DADOS NUNCA VISTOS / TESTE CEGO)")
    print("="*95)
    print(f"{'Cenário':<42} | {'Trades':<6} | {'Win%':<6} | {'PF':<5} | {'MaxDD%':<6} | {'Retorno%':<8} | {'TP':<4} | {'BE':<4} | {'SL':<4}")
    print("-"*95)

    oos_results = []
    for name, mode, be_trig, part_pct, part_trig in scenarios:
        tr_oos, eq_oos = simulate_engine(df_oos, mode=mode, be_trigger_atr=be_trig, partial_pct=part_pct, partial_trigger_atr=part_trig)
        m_oos = evaluate_metrics(tr_oos, eq_oos)
        print(f"{name:<42} | {m_oos['trades']:<6} | {m_oos['win_rate']:<5.1f}% | {m_oos['profit_factor']:<5.2f} | {m_oos['max_dd']:<5.1f}% | {m_oos['total_return']:<+7.1f}% | {m_oos['tp_count']:<4} | {m_oos['be_count']:<4} | {m_oos['sl_count']:<4}")
        oos_results.append((name, m_oos))
    print("="*95)
