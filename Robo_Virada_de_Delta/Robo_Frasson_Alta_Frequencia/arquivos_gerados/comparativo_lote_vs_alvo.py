import yfinance as yf
import pandas as pd
import numpy as np

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

# Definir 4 Cenários de Teste:
# Cenario 1: Movimento Curto Atual (TP1=0.5x, TP2=1.2x) com Lote Padrão (0.10)
# Cenario 2: Movimento Curto Atual (TP1=0.5x, TP2=1.2x) com Lote Alavancado (0.35)
# Cenario 3: Movimento Maior Estrutural (TP1=1.0x, TP2=2.2x) com Lote Padrão (0.15)
# Cenario 4: Movimento Maior Estrutural (TP1=1.2x, TP2=2.5x) com Lote Confortável (0.20)

cenarios = [
    {"nome": "Cenário 1: Movimento Curto (0.5x ATR) + Lote 0.10", "lot": 0.10, "tp1_m": 0.5, "tp2_m": 1.2, "sl_m": 0.75, "part_r": 0.80},
    {"nome": "Cenário 2: Movimento Curto (0.5x ATR) + Lote Alavancado 0.35", "lot": 0.35, "tp1_m": 0.5, "tp2_m": 1.2, "sl_m": 0.75, "part_r": 0.80},
    {"nome": "Cenário 3: Movimento Maior (1.0x ATR / $4.50+) + Lote 0.15", "lot": 0.15, "tp1_m": 1.0, "tp2_m": 2.2, "sl_m": 1.10, "part_r": 0.70},
    {"nome": "Cenário 4: Movimento Maior (1.2x ATR / $5.50+) + Lote 0.20", "lot": 0.20, "tp1_m": 1.2, "tp2_m": 2.5, "sl_m": 1.20, "part_r": 0.65},
    {"nome": "Cenário 5: Movimento Intermediário (0.8x ATR / $3.80+) + Lote 0.18", "lot": 0.18, "tp1_m": 0.8, "tp2_m": 2.0, "sl_m": 1.00, "part_r": 0.70},
]

f_center = np.roll(ma_14, 5)
f_upper = f_center + 2.2 * np.roll(atr_14, 5)
f_lower = f_center - 2.2 * np.roll(atr_14, 5)

spread_slip = 0.18 # Spread e slippage médio

resultados = []

for c in cenarios:
    lot = c['lot']
    unit_mult = 100.0 * lot
    fee_per_trade = 6.0 * lot # VT Markets Raw ECN ($6/lote round-turn)
    tp1_m = c['tp1_m']
    tp2_m = c['tp2_m']
    sl_m = c['sl_m']
    part_r = c['part_r']
    rem_r = 1.0 - part_r
    
    trades = []
    tp1_gains_usd = []
    full_gains_usd = []
    losses_usd = []
    
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
                    pnl_tp1 = abs(tp1_price - entry_price) * unit_mult * part_r - (fee_per_trade * part_r)
                    accum_pnl += pnl_tp1
                    tp1_gains_usd.append(pnl_tp1)
                    sl_price = entry_price # BE
                    
            sl_trig = (pos_type == 1 and c_low <= sl_price) or (pos_type == -1 and c_high >= sl_price)
            if sl_trig:
                ratio = rem_r if tp1_hit else 1.0
                pnl_pts = (sl_price - entry_price) if pos_type == 1 else (entry_price - sl_price)
                pnl_rem = pnl_pts * unit_mult * ratio - (fee_per_trade * ratio)
                total_pos = accum_pnl + pnl_rem
                trades.append(total_pos)
                if total_pos <= 0:
                    losses_usd.append(total_pos)
                in_pos = False
                continue
                
            tp2_trig = (pos_type == 1 and c_high >= tp2_price) or (pos_type == -1 and c_low <= tp2_price)
            if tp2_trig:
                ratio = rem_r if tp1_hit else 1.0
                pnl_pts = (tp2_price - entry_price) if pos_type == 1 else (entry_price - tp2_price)
                pnl_rem = pnl_pts * unit_mult * ratio - (fee_per_trade * ratio)
                total_pos = accum_pnl + pnl_rem
                trades.append(total_pos)
                full_gains_usd.append(total_pos)
                in_pos = False
                continue
        else:
            if trades_today >= 4:
                continue
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
            
            # Gatilho Híbrido (Pullback na Central OU Rejeição nos Extremos)
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
    t_per_day = len(t_s) / unique_days
    
    cum = t_s.cumsum()
    peak = cum.cummax()
    dd = (peak - cum).max()
    
    # Médias financeiras reais por trade
    avg_win = wins.mean() if len(wins) > 0 else 0
    avg_loss = abs(losses.mean()) if len(losses) > 0 else 0
    avg_tp1 = np.mean(tp1_gains_usd) if len(tp1_gains_usd) > 0 else 0
    
    resultados.append({
        'nome': c['nome'],
        'lot': lot,
        'alvo1_pts': f"{tp1_m}x ATR (~${tp1_m*4.5:.2f})",
        'alvo2_pts': f"{tp2_m}x ATR (~${tp2_m*4.5:.2f})",
        'stop_pts': f"{sl_m}x ATR (~${sl_m*4.5:.2f})",
        'trades_dia': round(t_per_day, 2),
        'total_trades': len(t_s),
        'win_rate': round(wr, 2),
        'profit_factor': round(pf, 2),
        'ganho_medio_win': round(avg_win, 2),
        'lucro_parcial_tp1': round(avg_tp1, 2),
        'perda_media_loss': round(avg_loss, 2),
        'max_dd_usd': round(dd, 2),
        'max_dd_pct': round((dd / 10000.0) * 100, 2),
        'net_60d_usd': round(net, 2),
        'proj_2y_usd': round((net / unique_days) * 504.0, 2)
    })

import json
print(json.dumps(resultados, indent=2))
