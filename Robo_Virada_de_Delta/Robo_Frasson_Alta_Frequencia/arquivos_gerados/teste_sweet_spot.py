import yfinance as yf
import pandas as pd
import numpy as np

df_raw = yf.download('GC=F', period='60d', interval='5m', progress=False)
if isinstance(df_raw.columns, pd.MultiIndex):
    df_raw.columns = [col[0] for col in df_raw.columns]
df_raw = df_raw.dropna()

active_mask = (df_raw.index.hour >= 7) & (df_raw.index.hour <= 18)
df_active = df_raw[active_mask].copy()

opens = df_active['Open'].values
highs = df_active['High'].values
lows = df_active['Low'].values
closes = df_active['Close'].values
volumes = df_active['Volume'].values
dates = df_active.index.date
unique_days = len(np.unique(dates))
n_bars = len(closes)

tr = np.maximum(highs - lows, np.maximum(np.abs(highs - np.roll(closes, 1)), np.abs(lows - np.roll(closes, 1))))
tr[0] = highs[0] - lows[0]
atr_14 = pd.Series(tr).rolling(14).mean().values
ma_14 = pd.Series(closes).rolling(14).mean().values
ema_50 = pd.Series(closes).ewm(span=50).mean().values
vol_ma10 = pd.Series(volumes).rolling(10).mean().values

bar_range = highs - lows
l_wick = np.minimum(opens, closes) - lows
u_wick = highs - np.maximum(opens, closes)

f_center = np.roll(ma_14, 5)
f_upper = f_center + 2.2 * np.roll(atr_14, 5)
f_lower = f_center - 2.2 * np.roll(atr_14, 5)
spread_slip = 0.18

# Testar TP1 de 0.50x, 0.55x, 0.60x, 0.65x, 0.70x com Lote 0.25
lot = 0.25
unit_mult = 100.0 * lot
fee = 6.0 * lot

for tp1_m in [0.50, 0.55, 0.60, 0.65, 0.70]:
    tp2_m = tp1_m * 2.4
    sl_m = tp1_m * 1.4
    part_r = 0.75
    rem_r = 0.25
    
    trades = []
    in_pos = False
    pos_type = 0
    entry_price = 0.0
    sl_price = 0.0
    tp1_price = 0.0
    tp2_price = 0.0
    tp1_hit = False
    accum_pnl = 0.0
    cur_day = None
    trades_today = 0
    
    for i in range(200, n_bars):
        d = dates[i]
        if d != cur_day:
            cur_day = d
            trades_today = 0
            
        c_high = highs[i]
        c_low = lows[i]
        c_open = opens[i]
        prev_i = i - 1
        cur_atr = atr_14[prev_i]
        if np.isnan(cur_atr) or cur_atr <= 0: continue
        
        if in_pos:
            if not tp1_hit:
                if (pos_type == 1 and c_high >= tp1_price) or (pos_type == -1 and c_low <= tp1_price):
                    tp1_hit = True
                    pnl_tp1 = abs(tp1_price - entry_price) * unit_mult * part_r - (fee * part_r)
                    accum_pnl += pnl_tp1
                    # Trava de lucro de 0.15x ATR no BE da 2a ordem
                    lock_pts = 0.15 * cur_atr
                    sl_price = (entry_price + lock_pts) if pos_type == 1 else (entry_price - lock_pts)
                    
            sl_trig = (pos_type == 1 and c_low <= sl_price) or (pos_type == -1 and c_high >= sl_price)
            if sl_trig:
                ratio = rem_r if tp1_hit else 1.0
                pnl_pts = (sl_price - entry_price) if pos_type == 1 else (entry_price - sl_price)
                pnl_rem = pnl_pts * unit_mult * ratio - (fee * ratio)
                trades.append(accum_pnl + pnl_rem)
                in_pos = False
                continue
                
            tp2_trig = (pos_type == 1 and c_high >= tp2_price) or (pos_type == -1 and c_low <= tp2_price)
            if tp2_trig:
                ratio = rem_r if tp1_hit else 1.0
                pnl_pts = (tp2_price - entry_price) if pos_type == 1 else (entry_price - tp2_price)
                pnl_rem = pnl_pts * unit_mult * ratio - (fee * ratio)
                trades.append(accum_pnl + pnl_rem)
                in_pos = False
                continue
        else:
            if trades_today >= 4: continue
            br = bar_range[prev_i]
            if br <= 0: continue
            lw = l_wick[prev_i] / br
            uw = u_wick[prev_i] / br
            v_ok = volumes[prev_i] >= (1.15 * vol_ma10[prev_i])
            fc = f_center[prev_i]
            fu = f_upper[prev_i]
            fl = f_lower[prev_i]
            p_close = closes[prev_i]
            p_open = opens[prev_i]
            uptrend = p_close > ema_50[prev_i]
            downtrend = p_close < ema_50[prev_i]
            
            buy_sig = False
            sell_sig = False
            if uptrend and ((lows[prev_i] <= fc and p_close > fc) or (lows[prev_i] <= fl and lw >= 0.25)) and p_close > p_open and v_ok:
                buy_sig = True
            elif downtrend and ((highs[prev_i] >= fc and p_close < fc) or (highs[prev_i] >= fu and uw >= 0.25)) and p_close < p_open and v_ok:
                sell_sig = True
                
            if buy_sig:
                in_pos = True
                pos_type = 1
                entry_price = c_open + spread_slip
                sl_price = entry_price - (sl_m * cur_atr)
                tp1_price = entry_price + (tp1_m * cur_atr)
                tp2_price = entry_price + (tp2_m * cur_atr)
                tp1_hit = False
                accum_pnl = 0.0
                trades_today += 1
            elif sell_sig:
                in_pos = True
                pos_type = -1
                entry_price = c_open - spread_slip
                sl_price = entry_price + (sl_m * cur_atr)
                tp1_price = entry_price - (tp1_m * cur_atr)
                tp2_price = entry_price - (tp2_m * cur_atr)
                tp1_hit = False
                accum_pnl = 0.0
                trades_today += 1

    t_s = pd.Series(trades)
    wins = t_s[t_s > 0]
    losses = t_s[t_s <= 0]
    wr = len(wins) / len(t_s) * 100
    pf = wins.sum() / abs(losses.sum()) if len(losses) > 0 else 0
    net = t_s.sum()
    t_day = len(t_s) / unique_days
    cum = t_s.cumsum()
    dd = (cum.cummax() - cum).max()
    avg_win = wins.mean() if len(wins) > 0 else 0
    
    print(f"TP1={tp1_m:.2f}x ATR (~${tp1_m*4.5:.2f}) | WR: {wr:.1f}% | PF: {pf:.2f} | Ganho Médio Win: ${avg_win:.2f} | Net 60d: ${net:.2f} | Proj 2A: ${net/unique_days*504:.2f} | MaxDD: ${dd:.2f} ({dd/100:.1f}%)")
