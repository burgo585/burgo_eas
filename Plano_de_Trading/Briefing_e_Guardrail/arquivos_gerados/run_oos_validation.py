import pandas as pd
import numpy as np

def run_is_oos():
    df = pd.read_parquet('data/BTCUSD_M15.parquet')

    # Indicadores
    df['ema_50'] = df['close'].ewm(span=50, adjust=False).mean()
    df['ema_200'] = df['close'].ewm(span=200, adjust=False).mean()
    tr = pd.concat([df['high'] - df['low'], (df['high'] - df['close'].shift(1)).abs(), (df['low'] - df['close'].shift(1)).abs()], axis=1).max(axis=1)
    df['atr'] = tr.rolling(14).mean()

    avg_vol = df['tick_volume'].rolling(10).mean()
    c_spread = (df['close'] - df['open']).abs()
    avg_c_spread = c_spread.rolling(10).mean()
    df['pvsra'] = 0
    df.loc[df['tick_volume'] >= 1.5 * avg_vol, 'pvsra'] = 1
    df.loc[(df['tick_volume'] >= 2.0 * avg_vol) | ((df['tick_volume'] * c_spread) >= 2.0 * avg_vol * avg_c_spread), 'pvsra'] = 2

    split_date = pd.to_datetime('2026-01-01 00:00:00+00:00')

    def run_simulation(df_sub, label, initial_capital=1000.0):
        opens = df_sub['open'].values
        highs = df_sub['high'].values
        lows = df_sub['low'].values
        closes = df_sub['close'].values
        spreads = df_sub['spread'].values * 0.01
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
        equity_curve = [initial_capital]
        total_swap = 0.0
        total_spread = 0.0

        for i in range(200, len(df_sub) - 1):
            if in_pos:
                h, l = highs[i], lows[i]
                exit_trade = False
                exit_p = 0.0
                if pos_type == 1:
                    if l <= sl_p: exit_p = sl_p; exit_trade = True
                    elif h >= tp_p: exit_p = tp_p; exit_trade = True
                else:
                    if h >= sl_p: exit_p = sl_p; exit_trade = True
                    elif l <= tp_p: exit_p = tp_p; exit_trade = True

                if exit_trade:
                    gross = (exit_p - entry_p)*lot_size if pos_type == 1 else (entry_p - exit_p)*lot_size
                    swap = 0.0
                    if pos_type == 1:
                        e_date, x_date = dates[entry_idx], dates[i]
                        for r in pd.date_range(e_date.floor('D') + pd.Timedelta(hours=21), x_date, freq='1D'):
                            if e_date < r <= x_date:
                                days = 3 if r.dayofweek == 4 else 1
                                swap += (lot_size * entry_p * (0.20 / 360.0)) * days
                    balance += (gross - swap)
                    total_swap += swap
                    trades.append({
                        'net_pnl': gross - swap,
                        'gross': gross,
                        'swap': swap,
                        'balance': balance,
                        'duration': i - entry_idx
                    })
                    in_pos = False

            equity_curve.append(balance)

            if not in_pos and not np.isnan(atrs[i]) and atrs[i] > 0:
                if not (((8 <= hours[i] < 12) or (15 <= hours[i] < 19)) and dows[i] < 5):
                    continue
                c, o = closes[i], opens[i]
                vol_ok = pvsras[i] in [1, 2]
                buy_sig = (c > ema_200s[i]) and (ema_50s[i] > ema_200s[i]) and vol_ok and (c > o)
                sell_sig = (c < ema_200s[i]) and (ema_50s[i] < ema_200s[i]) and vol_ok and (c < o)
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
                    in_pos = True

        tdf = pd.DataFrame(trades)
        eq = pd.Series(equity_curve)
        peak = eq.cummax()
        dd = (eq - peak) / peak * 100
        max_dd = abs(dd.min())
        ret_pct = ((balance - initial_capital) / initial_capital) * 100

        wins = tdf[tdf['net_pnl'] > 0]
        losses = tdf[tdf['net_pnl'] <= 0]
        wr = (len(wins)/len(tdf))*100 if len(tdf) > 0 else 0
        pf = wins['net_pnl'].sum() / abs(losses['net_pnl'].sum()) if len(losses) > 0 else np.nan

        returns = eq.pct_change().dropna()
        sharpe = (returns.mean() / returns.std()) * np.sqrt(252 * 24 * 4) if returns.std() > 0 else 0

        d_min = df_sub['datetime'].min().strftime('%Y-%m-%d')
        d_max = df_sub['datetime'].max().strftime('%Y-%m-%d')
        print(f"================================================================")
        print(f"=== {label} ===")
        print(f"================================================================")
        print(f"Barras Analisadas:      {len(df_sub):,} | Período: {d_min} até {d_max}")
        print(f"Total de Trades:        {len(tdf):,}")
        print(f"Win Rate (Payoff 2:1):  {wr:.2f}%")
        print(f"Profit Factor Líquido:  {pf:.2f}")
        print(f"Capital:                ${initial_capital:,.2f} -> ${balance:,.2f} ({ret_pct:+.2f}%)")
        print(f"Drawdown Máximo:        {max_dd:.2f}%")
        print(f"Sharpe Ratio:           {sharpe:.2f}")
        print(f"Spread Pago:            ${total_spread:,.2f}")
        print(f"Swap Overnight Pago:    ${total_swap:,.2f}\n")

    df_is = df[df['datetime'] < split_date].copy().reset_index(drop=True)
    df_oos = df[df['datetime'] >= split_date].copy().reset_index(drop=True)

    run_simulation(df_is, "IN-SAMPLE (2024 - 2025: Treino / Descoberta)")
    run_simulation(df_oos, "OUT-OF-SAMPLE (2026: Teste Cego / Validação Real)")

if __name__ == '__main__':
    run_is_oos()
