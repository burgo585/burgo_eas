import pandas as pd
import numpy as np

def run_comparison():
    df = pd.read_parquet('data/BTCUSD_M15.parquet')

    # Indicadores padrão da estratégia
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

    split_date = pd.to_datetime('2026-01-01 00:00:00+00:00')

    def execute_backtest(df_sub, enable_breakeven=False, be_trigger_atr=1.5, allow_buy=True, allow_sell=True, initial_capital=1000.0):
        opens = df_sub['open'].values
        highs = df_sub['high'].values
        lows = df_sub['low'].values
        closes = df_sub['close'].values
        spreads = df_sub['spread'].values * 0.01  # Spread em USD
        atrs = df_sub['atr'].values
        pvsras = df_sub['pvsra'].values
        ema_50s = df_sub['ema_50'].values
        ema_200s = df_sub['ema_200'].values
        dates = pd.to_datetime(df_sub['datetime'].values)
        hours = dates.hour.values
        dows = dates.dayofweek.values

        balance = initial_capital
        trades = []
        in_pos = False
        pos_type = 0
        lot_size = 0.0
        entry_idx = 0
        entry_p, sl_p, tp_p = 0.0, 0.0, 0.0
        be_active = False
        equity_curve = [initial_capital]
        total_swap = 0.0
        total_spread = 0.0

        for i in range(200, len(df_sub) - 1):
            if in_pos:
                h, l = highs[i], lows[i]
                atr_entry = atrs[entry_idx - 1]

                # Checa acionamento de Breakeven se ativado
                if enable_breakeven and not be_active:
                    if pos_type == 1:
                        if (h - entry_p) >= (be_trigger_atr * atr_entry):
                            sl_p = entry_p + spreads[entry_idx]
                            be_active = True
                    elif pos_type == -1:
                        if (entry_p - l) >= (be_trigger_atr * atr_entry):
                            sl_p = entry_p - spreads[entry_idx]
                            be_active = True

                exit_trade = False
                exit_p = 0.0
                outcome = ""

                if pos_type == 1:
                    if l <= sl_p and h >= tp_p:
                        exit_p = sl_p; outcome = "BE" if be_active else "SL"; exit_trade = True
                    elif l <= sl_p:
                        exit_p = sl_p; outcome = "BE" if be_active else "SL"; exit_trade = True
                    elif h >= tp_p:
                        exit_p = tp_p; outcome = "TP"; exit_trade = True
                else:
                    if h >= sl_p and l <= tp_p:
                        exit_p = sl_p; outcome = "BE" if be_active else "SL"; exit_trade = True
                    elif h >= sl_p:
                        exit_p = sl_p; outcome = "BE" if be_active else "SL"; exit_trade = True
                    elif l <= tp_p:
                        exit_p = tp_p; outcome = "TP"; exit_trade = True

                if exit_trade:
                    gross = (exit_p - entry_p) * lot_size if pos_type == 1 else (entry_p - exit_p) * lot_size
                    swap = 0.0
                    if pos_type == 1:
                        e_date, x_date = dates[entry_idx], dates[i]
                        for r in pd.date_range(e_date.floor('D') + pd.Timedelta(hours=21), x_date, freq='1D'):
                            if e_date < r <= x_date:
                                days = 3 if r.dayofweek == 4 else 1
                                swap += (lot_size * entry_p * (0.20 / 360.0)) * days

                    net_pnl = gross - swap
                    balance += net_pnl
                    total_swap += swap
                    trades.append({
                        'outcome': outcome,
                        'net_pnl': net_pnl,
                        'gross': gross,
                        'swap': swap,
                        'balance': balance,
                        'duration': i - entry_idx
                    })
                    in_pos = False

            equity_curve.append(balance)

            # Novo sinal
            if not in_pos and not np.isnan(atrs[i]) and atrs[i] > 0:
                # Sessão de Londres e NY
                if not (((8 <= hours[i] < 12) or (15 <= hours[i] < 19)) and dows[i] < 5):
                    continue

                c, o = closes[i], opens[i]
                vol_ok = pvsras[i] in [1, 2]
                buy_sig = (c > ema_200s[i]) and (ema_50s[i] > ema_200s[i]) and vol_ok and (c > o)
                sell_sig = (c < ema_200s[i]) and (ema_50s[i] < ema_200s[i]) and vol_ok and (c < o)

                # Aplica as chaves modulares de permissão de direção
                if buy_sig and not allow_buy:
                    buy_sig = False
                if sell_sig and not allow_sell:
                    sell_sig = False

                if buy_sig or sell_sig:
                    next_o = opens[i+1]
                    spread = spreads[i+1]
                    sl_dist = atrs[i] * 1.5
                    tp_dist = sl_dist * 2.0
                    
                    if (spread / tp_dist) * 100.0 > 5.0:
                        continue
                    
                    risk_usd = balance * 0.01
                    raw_lot = risk_usd / sl_dist
                    lot_size = max(0.01, min(100.0, np.floor(raw_lot / 0.01) * 0.01))
                    total_spread += (spread * lot_size)
                    pos_type = 1 if buy_sig else -1
                    entry_idx = i + 1

                    if pos_type == 1:
                        entry_p = next_o + spread
                        sl_p = entry_p - sl_dist
                        tp_p = entry_p + tp_dist
                    else:
                        entry_p = next_o
                        sl_p = entry_p + sl_dist + spread
                        tp_p = entry_p - tp_dist

                    be_active = False
                    in_pos = True

        tdf = pd.DataFrame(trades)
        eq = pd.Series(equity_curve)
        peak = eq.cummax()
        dd = (eq - peak) / peak * 100
        max_dd = abs(dd.min())
        ret_pct = ((balance - initial_capital) / initial_capital) * 100

        wins = tdf[tdf['net_pnl'] > 0]
        losses = tdf[tdf['net_pnl'] < 0]
        breakevens = tdf[tdf['outcome'] == 'BE']
        tps = tdf[tdf['outcome'] == 'TP']
        sls = tdf[tdf['outcome'] == 'SL']
        
        wr = (len(wins) / len(tdf)) * 100 if len(tdf) > 0 else 0
        pf = wins['net_pnl'].sum() / abs(losses['net_pnl'].sum()) if len(losses) > 0 else np.nan
        returns = eq.pct_change().dropna()
        sharpe = (returns.mean() / returns.std()) * np.sqrt(252 * 24 * 4) if returns.std() > 0 else 0

        return {
            'total_trades': len(tdf),
            'win_rate': wr,
            'profit_factor': pf,
            'initial_capital': initial_capital,
            'final_balance': balance,
            'return_pct': ret_pct,
            'max_dd': max_dd,
            'sharpe': sharpe,
            'spread_paid': total_spread,
            'swap_paid': total_swap,
            'tp_count': len(tps),
            'be_count': len(breakevens),
            'sl_count': len(sls)
        }

    df_is = df[df['datetime'] < split_date].copy().reset_index(drop=True)
    df_oos = df[df['datetime'] >= split_date].copy().reset_index(drop=True)

    configs = [
        ("1. PROGRAMAÇÃO ORIGINAL (Baseline - Sem BE, Compra+Venda)", False, 1.5, True, True),
        ("2. COM A LINHA DE BREAKEVEN (ENABLE_BREAKEVEN = True @ 1.5 ATR)", True, 1.5, True, True),
        ("3. COM A LINHA DE BREAKEVEN (ENABLE_BREAKEVEN = True @ 1.0 ATR)", True, 1.0, True, True),
        ("4. APENAS COMPRA (ALLOW_SELL = False)", False, 1.5, True, False),
        ("5. APENAS VENDA (ALLOW_BUY = False)", False, 1.5, False, True),
    ]

    for label_sub, subset in [("PERÍODO COMPLETO (2024 - 2026)", df), ("IN-SAMPLE (2024 - 2025)", df_is), ("OUT-OF-SAMPLE (2026 CEGO)", df_oos)]:
        print(f"\n{'='*105}")
        print(f"=== {label_sub} ===")
        print(f"{'='*105}")
        print(f"{'Configuração':<52} | {'Trades':<6} | {'Win Rate':<8} | {'PF':<5} | {'Max DD':<7} | {'Retorno %':<10} | {'Saldo Final':<10}")
        print(f"{'-'*105}")
        for name, be_on, be_trig, a_buy, a_sell in configs:
            res = execute_backtest(subset, enable_breakeven=be_on, be_trigger_atr=be_trig, allow_buy=a_buy, allow_sell=a_sell)
            print(f"{name:<52} | {res['total_trades']:<6} | {res['win_rate']:<7.2f}% | {res['profit_factor']:<5.2f} | {res['max_dd']:<6.2f}% | {res['return_pct']:<+9.2f}% | ${res['final_balance']:<9.2f}")
    print(f"{'='*105}\n")

if __name__ == '__main__':
    run_comparison()
