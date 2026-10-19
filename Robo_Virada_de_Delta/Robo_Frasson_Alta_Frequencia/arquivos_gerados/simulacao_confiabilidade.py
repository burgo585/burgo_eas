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

# Vamos testar a matriz de decisão solicitada pelo usuário:
# Opção A: Apenas Aumentar Lote no Movimento Curto (0.5x ATR com Lote 0.25 e 0.35)
# Opção B: Apenas Aumentar Movimento mantendo Lote Conservador (Alvo 1.0x ATR e 1.2x ATR com Lote 0.10)
# Opção C: A Solução Mais Confiável (Movimento Equilibrado 0.8x a 1.0x ATR + Lote Calibrado 0.20 para $10k)
# Opção D: Modelo Sniper com Alvo Longo (1.0x e 2.5x ATR) + Lote 0.20

testes = [
    {
        "id": "A1",
        "desc": "Opção A: Aumentar Lote p/ 0.25 (Movimento Curto 0.5x ATR)",
        "lot": 0.25, "tp1_m": 0.5, "tp2_m": 1.2, "sl_m": 0.75, "part_r": 0.80, "trig": "hybrid"
    },
    {
        "id": "A2",
        "desc": "Opção A: Aumentar Lote p/ 0.35 (Movimento Curto 0.5x ATR)",
        "lot": 0.35, "tp1_m": 0.5, "tp2_m": 1.2, "sl_m": 0.75, "part_r": 0.80, "trig": "hybrid"
    },
    {
        "id": "B1",
        "desc": "Opção B: Aumentar Movimento p/ 1.0x ATR ($4.50) com Lote 0.10",
        "lot": 0.10, "tp1_m": 1.0, "tp2_m": 2.2, "sl_m": 1.10, "part_r": 0.70, "trig": "hybrid"
    },
    {
        "id": "B2",
        "desc": "Opção B: Aumentar Movimento p/ 1.2x ATR ($5.50) com Lote 0.10",
        "lot": 0.10, "tp1_m": 1.2, "tp2_m": 2.5, "sl_m": 1.20, "part_r": 0.65, "trig": "hybrid"
    },
    {
        "id": "C_IDEAL",
        "desc": "Opção C (RECOMENDADA): Movimento Calibrado (0.75x ATR / $3.40+) + Lote 0.20",
        "lot": 0.20, "tp1_m": 0.75, "tp2_m": 1.80, "sl_m": 0.90, "part_r": 0.70, "trig": "hybrid"
    },
    {
        "id": "D_SNIPER",
        "desc": "Opção D (SNIPER): Movimento Amplo ($4.50 a $11.00) + Rejeição + Lote 0.20",
        "lot": 0.20, "tp1_m": 1.00, "tp2_m": 2.50, "sl_m": 1.20, "part_r": 0.70, "trig": "reversal_trend"
    }
]

f_center = np.roll(ma_14, 5)
f_upper = f_center + 2.2 * np.roll(atr_14, 5)
f_lower = f_center - 2.2 * np.roll(atr_14, 5)

f_center_snip = np.roll(ma_14, 2)
f_upper_snip = f_center_snip + 2.0 * np.roll(atr_14, 2)
f_lower_snip = f_center_snip - 2.0 * np.roll(atr_14, 2)

spread_slip = 0.18

res_list = []

for t in testes:
    lot = t['lot']
    unit_mult = 100.0 * lot
    fee_per_trade = 6.0 * lot
    tp1_m = t['tp1_m']
    tp2_m = t['tp2_m']
    sl_m = t['sl_m']
    part_r = t['part_r']
    rem_r = 1.0 - part_r
    trig_mode = t['trig']
    
    trades = []
    tp1_dollars = []
    tp2_dollars = []
    losses_dollars = []
    
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
    
    fc_arr = f_center_snip if trig_mode == "reversal_trend" else f_center
    fu_arr = f_upper_snip if trig_mode == "reversal_trend" else f_upper
    fl_arr = f_lower_snip if trig_mode == "reversal_trend" else f_lower
    
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
                    tp1_dollars.append(pnl_tp1)
                    sl_price = entry_price
                    
            sl_trig = (pos_type == 1 and c_low <= sl_price) or (pos_type == -1 and c_high >= sl_price)
            if sl_trig:
                ratio = rem_r if tp1_hit else 1.0
                pnl_pts = (sl_price - entry_price) if pos_type == 1 else (entry_price - sl_price)
                pnl_rem = pnl_pts * unit_mult * ratio - (fee_per_trade * ratio)
                total_pos = accum_pnl + pnl_rem
                trades.append(total_pos)
                if total_pos <= 0:
                    losses_dollars.append(total_pos)
                in_pos = False
                continue
                
            tp2_trig = (pos_type == 1 and c_high >= tp2_price) or (pos_type == -1 and c_low <= tp2_price)
            if tp2_trig:
                ratio = rem_r if tp1_hit else 1.0
                pnl_pts = (tp2_price - entry_price) if pos_type == 1 else (entry_price - tp2_price)
                pnl_rem = pnl_pts * unit_mult * ratio - (fee_per_trade * ratio)
                total_pos = accum_pnl + pnl_rem
                trades.append(total_pos)
                tp2_dollars.append(total_pos)
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
            fc = fc_arr[prev_i]
            fu = fu_arr[prev_i]
            fl = fl_arr[prev_i]
            p_close = closes[prev_i]
            p_open = opens[prev_i]
            
            uptrend = p_close > ema_50[prev_i]
            downtrend = p_close < ema_50[prev_i]
            
            buy_sig = False
            sell_sig = False
            
            if trig_mode == "hybrid":
                if uptrend and ((lows[prev_i] <= fc and p_close > fc) or (lows[prev_i] <= fl and lw >= 0.25)) and p_close > p_open and v_ok:
                    buy_sig = True
                elif downtrend and ((highs[prev_i] >= fc and p_close < fc) or (highs[prev_i] >= fu and uw >= 0.25)) and p_close < p_open and v_ok:
                    sell_sig = True
            elif trig_mode == "reversal_trend":
                if uptrend and lows[prev_i] <= fl and lw >= 0.30 and p_close > p_open and v_ok:
                    buy_sig = True
                elif downtrend and highs[prev_i] >= fu and uw >= 0.30 and p_close < p_open and v_ok:
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
    
    res_list.append({
        "id": t['id'],
        "desc": t['desc'],
        "lote": lot,
        "alvo1_usd": round(np.mean(tp1_dollars), 2) if len(tp1_dollars) > 0 else 0,
        "lucro_medio_vencedor": round(wins.mean(), 2) if len(wins) > 0 else 0,
        "perda_media_perdedor": round(abs(losses.mean()), 2) if len(losses) > 0 else 0,
        "win_rate": round(wr, 2),
        "profit_factor": round(pf, 2),
        "frequencia_dia": round(t_per_day, 2),
        "drawdown_usd": round(dd, 2),
        "drawdown_pct": round((dd / 10000.0) * 100, 2),
        "lucro_liquido_60d": round(net, 2),
        "lucro_proj_2_anos": round((net / unique_days) * 504.0, 2)
    })

import json
print(json.dumps(res_list, indent=2))
