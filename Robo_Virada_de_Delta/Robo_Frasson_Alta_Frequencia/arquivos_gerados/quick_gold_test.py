import yfinance as yf
import pandas as pd
import numpy as np

# Download 60 days M5
print("Baixando dados M5 de XAUUSD...")
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
n_bars = len(closes)
n_days = 42.0

lot = 0.15 # $15 por ponto de ouro
unit_mult = 100.0 * lot
fee_per_trade = 0.90
spread_slip = 0.19

tr = np.maximum(highs - lows, np.maximum(np.abs(highs - np.roll(closes, 1)), np.abs(lows - np.roll(closes, 1))))
tr[0] = highs[0] - lows[0]
atr_14 = pd.Series(tr).rolling(14).mean().values
ma_14 = pd.Series(closes).rolling(14).mean().values
ma_50 = pd.Series(closes).rolling(50).mean().values
vol_ma10 = pd.Series(volumes).rolling(10).mean().values

bar_range = highs - lows
l_wick = np.minimum(opens, closes) - lows
u_wick = highs - np.maximum(opens, closes)

all_res = []

for m in [1.5, 1.8, 2.0, 2.2]:
    for s in [2, 3]:
        f_center = np.roll(ma_14, s)
        f_upper = f_center + m * np.roll(atr_14, s)
        f_lower = f_center - m * np.roll(atr_14, s)
        
        for (tp1_m, tp2_m, sl_m, part_r) in [(0.8, 2.0, 1.0, 0.7), (1.0, 2.5, 1.2, 0.7), (0.6, 1.5, 0.8, 0.75), (1.2, 2.5, 1.2, 0.5)]:
            rem_r = 1.0 - part_r
            for trig in ['breakout', 'reversal', 'pullback']:
                trades = []
                in_pos = False
                pos_type = 0
                entry_price = 0.0
                sl_price = 0.0
                tp1_price = 0.0
                tp2_price = 0.0
                tp1_hit = False
                
                for i in range(50, n_bars):
                    c_high = highs[i]
                    c_low = lows[i]
                    cur_atr = atr_14[i-1]
                    if np.isnan(cur_atr) or cur_atr <= 0: continue
                    
                    if in_pos:
                        if not tp1_hit:
                            if (pos_type == 1 and c_high >= tp1_price) or (pos_type == -1 and c_low <= tp1_price):
                                tp1_hit = True
                                pnl = abs(tp1_price - entry_price) * unit_mult * part_r - fee_per_trade * part_r
                                trades.append(pnl)
                                sl_price = entry_price
                                
                        sl_trig = (pos_type == 1 and c_low <= sl_price) or (pos_type == -1 and c_high >= sl_price)
                        if sl_trig:
                            ratio = rem_r if tp1_hit else 1.0
                            pnl_pts = (sl_price - entry_price) if pos_type == 1 else (entry_price - sl_price)
                            trades.append(pnl_pts * unit_mult * ratio - fee_per_trade * ratio)
                            in_pos = False
                            continue
                            
                        tp2_trig = (pos_type == 1 and c_high >= tp2_price) or (pos_type == -1 and c_low <= tp2_price)
                        if tp2_trig:
                            ratio = rem_r if tp1_hit else 1.0
                            pnl_pts = (tp2_price - entry_price) if pos_type == 1 else (entry_price - tp2_price)
                            trades.append(pnl_pts * unit_mult * ratio - fee_per_trade * ratio)
                            in_pos = False
                            continue
                    else:
                        prev_i = i - 1
                        br = bar_range[prev_i]
                        if br <= 0: continue
                        
                        buy_sig = False
                        sell_sig = False
                        
                        if trig == 'breakout':
                            if closes[prev_i] > f_upper[prev_i] and closes[prev_i] > opens[prev_i]:
                                buy_sig = True
                            elif closes[prev_i] < f_lower[prev_i] and closes[prev_i] < opens[prev_i]:
                                sell_sig = True
                        elif trig == 'reversal':
                            if (l_wick[prev_i] / br) >= 0.35 and lows[prev_i] <= f_lower[prev_i] and closes[prev_i] > opens[prev_i]:
                                buy_sig = True
                            elif (u_wick[prev_i] / br) >= 0.35 and highs[prev_i] >= f_upper[prev_i] and closes[prev_i] < opens[prev_i]:
                                sell_sig = True
                        elif trig == 'pullback':
                            if closes[prev_i] > ma_50[prev_i] and lows[prev_i] <= f_center[prev_i] and closes[prev_i] > f_center[prev_i] and closes[prev_i] > opens[prev_i]:
                                buy_sig = True
                            elif closes[prev_i] < ma_50[prev_i] and highs[prev_i] >= f_center[prev_i] and closes[prev_i] < f_center[prev_i] and closes[prev_i] < opens[prev_i]:
                                sell_sig = True
                                
                        if buy_sig:
                            in_pos = True
                            pos_type = 1
                            entry_price = opens[i] + spread_slip
                            sl_price = entry_price - (sl_m * cur_atr)
                            tp1_price = entry_price + (tp1_m * cur_atr)
                            tp2_price = entry_price + (tp2_m * cur_atr)
                            tp1_hit = False
                        elif sell_sig:
                            in_pos = True
                            pos_type = -1
                            entry_price = opens[i] - spread_slip
                            sl_price = entry_price + (sl_m * cur_atr)
                            tp1_price = entry_price - (tp1_m * cur_atr)
                            tp2_price = entry_price - (tp2_m * cur_atr)
                            tp1_hit = False
                            
                if len(trades) >= 20:
                    t_s = pd.Series(trades)
                    wins = t_s[t_s > 0]
                    losses = t_s[t_s <= 0]
                    wr = len(wins) / len(t_s) * 100
                    pf = wins.sum() / abs(losses.sum()) if len(losses) > 0 and losses.sum() != 0 else 0
                    net = t_s.sum()
                    t_day = len(t_s) / n_days
                    all_res.append({
                        'mult': m, 'shift': s, 'tp1': tp1_m, 'tp2': tp2_m, 'sl': sl_m,
                        'part': part_r, 'trig': trig, 'win_rate': wr, 'profit_factor': pf, 'net': net,
                        'trades_per_day': t_day, 'total_trades': len(t_s)
                    })

df_out = pd.DataFrame(all_res)
df_sorted = df_out.sort_values(by='net', ascending=False)
print("\n" + "="*85)
print("TOP 10 CONFIGURAÇÕES XAUUSD M5 CLASSIFICADAS POR LUCRO:")
print("="*85)
for _, r in df_sorted.head(10).iterrows():
    print(f"Gatilho: {r['trig']:8s} | M={r['mult']} S={r['shift']} | TP1={r['tp1']} TP2={r['tp2']} SL={r['sl']} | WR: {r['win_rate']:.1f}% | PF: {r['profit_factor']:.2f} | Net: ${r['net']:.2f} | {r['trades_per_day']:.2f} trades/dia ({r['total_trades']:.0f} trades)")

print("\n" + "="*85)
print("TOP 10 CONFIGURAÇÕES XAUUSD M5 CLASSIFICADAS POR TAXA DE ACERTO (WIN RATE):")
print("="*85)
df_wr = df_out[df_out['profit_factor'] >= 1.0].sort_values(by='win_rate', ascending=False)
for _, r in df_wr.head(10).iterrows():
    print(f"Gatilho: {r['trig']:8s} | M={r['mult']} S={r['shift']} | TP1={r['tp1']} TP2={r['tp2']} SL={r['sl']} | WR: {r['win_rate']:.1f}% | PF: {r['profit_factor']:.2f} | Net: ${r['net']:.2f} | {r['trades_per_day']:.2f} trades/dia ({r['total_trades']:.0f} trades)")
