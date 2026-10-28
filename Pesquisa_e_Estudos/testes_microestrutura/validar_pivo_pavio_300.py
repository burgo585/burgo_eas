import os
import polars as pl
import pandas as pd
import numpy as np

sys_path = r"C:\Users\Vini_Burgo\Documents\burgo_eas\Pesquisa_e_Estudos\testes_microestrutura"
M15_PATH = os.path.join(sys_path, "xauusd_m15_xm_real_ticks.parquet")

df_pl = pl.read_parquet(M15_PATH)
df = df_pl.to_pandas()
df.set_index("time", inplace=True)
df.sort_index(inplace=True)

POINT = 0.01
TICK_VAL = 1.0
COMM_PER_LOT = 0.0  # Ultra Low: Zero comissao
SLIPPAGE = 0.10
SWAP_LONG = -20.0
SWAP_SHORT = 8.0

# Indicadores com shift(1) estrito
df["ema9"] = df["close"].ewm(span=9, adjust=False).mean().shift(1)
df["ema21"] = df["close"].ewm(span=21, adjust=False).mean().shift(1)
df["ema50"] = df["close"].ewm(span=50, adjust=False).mean().shift(1)
df["ema200"] = df["close"].ewm(span=200, adjust=False).mean().shift(1)

# ATR(14) shift(1)
tr = np.maximum(df["high"] - df["low"], np.maximum((df["high"] - df["close"].shift(1)).abs(), (df["low"] - df["close"].shift(1)).abs()))
df["atr"] = tr.rolling(14).mean().shift(1)

# Barras anteriores
df["p_open"] = df["open"].shift(1)
df["p_high"] = df["high"].shift(1)
df["p_low"] = df["low"].shift(1)
df["p_close"] = df["close"].shift(1)

df["p2_low"] = df["low"].shift(2)
df["p2_high"] = df["high"].shift(2)

df.dropna(inplace=True)

def simular_pivo_pavio_ultra_low(
    initial_balance=300.0,
    lot=0.01,
    rr=2.0,
    max_daily_loss=8.0,      # Trava do Guardiao de Capital: max 2 stops/dia
    daily_target=16.0,       # Meta diaria: 5.3% ao dia
    use_ema200=True,
    hours_filter=(7, 18)     # Londres e Nova York
):
    balance = initial_balance
    max_equity = balance
    max_dd = 0.0
    
    trades = []
    in_pos = False
    pos_type = None
    entry_p = 0.0
    sl_p = 0.0
    tp_p = 0.0
    entry_time = None
    accum_swap = 0.0
    
    cur_day = None
    day_pnl = 0.0
    day_locked = False
    
    times = df.index
    opens = df["open"].values
    highs = df["high"].values
    lows = df["low"].values
    spreads = df["spread_mean"].values
    ema9s = df["ema9"].values
    ema21s = df["ema21"].values
    ema50s = df["ema50"].values
    ema200s = df["ema200"].values
    atrs = df["atr"].values
    
    p_opens = df["p_open"].values
    p_highs = df["p_high"].values
    p_lows = df["p_low"].values
    p_closes = df["p_close"].values
    p2_lows = df["p2_low"].values
    p2_highs = df["p2_high"].values
    
    hours = times.hour
    
    for i in range(len(df)):
        cur_t = times[i]
        b_open = opens[i]
        b_high = highs[i]
        b_low = lows[i]
        cur_spread = spreads[i]
        
        # Reset diario do Guardiao
        if cur_day != cur_t.date():
            cur_day = cur_t.date()
            day_pnl = 0.0
            day_locked = False
            
        # Gestao de posicao aberta (Defesa da Boleta)
        if in_pos:
            if cur_t.date() != entry_time.date():
                mult_swap = 3.0 if entry_time.weekday() == 2 else 1.0
                rate = SWAP_LONG if pos_type == "BUY" else SWAP_SHORT
                accum_swap += (lot * rate * mult_swap)
                entry_time = cur_t
                
            if pos_type == "BUY":
                hit_sl = (b_low <= sl_p)
                hit_tp = (b_high >= tp_p)
                if hit_sl and hit_tp: hit_tp = False
                if hit_sl:
                    exit_p = sl_p - (SLIPPAGE * POINT)
                    pnl = ((exit_p - entry_p) / POINT) * lot * TICK_VAL + accum_swap
                    balance += pnl
                    day_pnl += pnl
                    trades.append({"time": cur_t, "type": "BUY", "res": "SL", "pnl": pnl, "bal": balance})
                    in_pos = False
                elif hit_tp:
                    exit_p = tp_p - (SLIPPAGE * POINT)
                    pnl = ((exit_p - entry_p) / POINT) * lot * TICK_VAL + accum_swap
                    balance += pnl
                    day_pnl += pnl
                    trades.append({"time": cur_t, "type": "BUY", "res": "TP", "pnl": pnl, "bal": balance})
                    in_pos = False
                    
            elif pos_type == "SELL":
                hit_sl = (b_high >= sl_p)
                hit_tp = (b_low <= tp_p)
                if hit_sl and hit_tp: hit_tp = False
                if hit_sl:
                    exit_p = sl_p + (SLIPPAGE * POINT)
                    pnl = ((entry_p - exit_p) / POINT) * lot * TICK_VAL + accum_swap
                    balance += pnl
                    day_pnl += pnl
                    trades.append({"time": cur_t, "type": "SELL", "res": "SL", "pnl": pnl, "bal": balance})
                    in_pos = False
                elif hit_tp:
                    exit_p = tp_p + (SLIPPAGE * POINT)
                    pnl = ((entry_p - exit_p) / POINT) * lot * TICK_VAL + accum_swap
                    balance += pnl
                    day_pnl += pnl
                    trades.append({"time": cur_t, "type": "SELL", "res": "TP", "pnl": pnl, "bal": balance})
                    in_pos = False
                    
            if balance > max_equity: max_equity = balance
            dd = max_equity - balance
            if dd > max_dd: max_dd = dd
            
            # Disparo da Trava Diaria da Boleta
            if max_daily_loss > 0 and day_pnl <= -max_daily_loss: day_locked = True
            if daily_target > 0 and day_pnl >= daily_target: day_locked = True
            if balance <= 30.0: break # Stop out
            
        # Gatilho: Pivo + Pavio + Tendencia (Price Action Institucional)
        if not in_pos and balance > 30.0 and not day_locked:
            h = hours[i]
            if hours_filter and (h < hours_filter[0] or h >= hours_filter[1]):
                continue
                
            cur_ema200 = ema200s[i]
            cur_ema50  = ema50s[i]
            cur_ema21  = ema21s[i]
            cur_ema9   = ema9s[i]
            
            p_c = p_closes[i]
            p_o = p_opens[i]
            p_h = p_highs[i]
            p_l = p_lows[i]
            
            # 1. Seguir a Tendencia
            trend_bull = (p_c > cur_ema200) and (cur_ema50 > cur_ema200) if use_ema200 else (cur_ema9 > cur_ema21)
            trend_bear = (p_c < cur_ema200) and (cur_ema50 < cur_ema200) if use_ema200 else (cur_ema9 < cur_ema21)
            
            # 2. Formacao de Pivo e Rompimento de Pavio
            # Compra:
            # - Preco recuou na EMA21 ou EMA50 (p_l <= cur_ema21 ou p2_lows[i] <= cur_ema21)
            # - Deixou pavio inferior de rejeicao: min(p_o, p_c) - p_l > 0.20 * (p_h - p_l)
            # - Rompimento: a barra atual rompe o topo do pavio da barra anterior
            bar_rng = p_h - p_l
            lower_wick = min(p_o, p_c) - p_l
            upper_wick = p_h - max(p_o, p_c)
            
            pivo_buy = trend_bull and (p_l <= cur_ema21 or p2_lows[i] <= cur_ema21) and (lower_wick >= 0.20 * bar_rng) and (p_c > p_o)
            pivo_sell = trend_bear and (p_h >= cur_ema21 or p2_highs[i] >= cur_ema21) and (upper_wick >= 0.20 * bar_rng) and (p_c < p_o)
            
            if pivo_buy:
                if (cur_spread / POINT) > 60.0: continue
                entry_p = b_open + cur_spread
                # Stop loss estrutural no fundo do pivô
                sl_pts = max(150.0, (entry_p - p_l) / POINT + 15.0)
                if sl_pts > 450.0: sl_pts = 450.0 # Teto maximo para $300
                
                pos_type = "BUY"
                sl_p = entry_p - (sl_pts * POINT)
                tp_p = entry_p + (sl_pts * POINT * rr)
                accum_swap = 0.0
                entry_time = cur_t
                in_pos = True
                
            elif pivo_sell:
                if (cur_spread / POINT) > 60.0: continue
                entry_p = b_open
                sl_pts = max(150.0, (p_h - entry_p) / POINT + 15.0 + (cur_spread / POINT))
                if sl_pts > 450.0: sl_pts = 450.0
                
                pos_type = "SELL"
                sl_p = entry_p + (sl_pts * POINT)
                tp_p = entry_p - (sl_pts * POINT * rr)
                accum_swap = 0.0
                entry_time = cur_t
                in_pos = True
                
    df_t = pd.DataFrame(trades)
    return {
        "initial_balance": initial_balance,
        "final_balance": balance,
        "net_pnl": balance - initial_balance,
        "ret_pct": ((balance - initial_balance) / initial_balance) * 100.0,
        "max_dd": max_dd,
        "max_dd_pct": (max_dd / initial_balance) * 100.0,
        "total_trades": len(df_t),
        "trades": df_t
    }

print("Executando simulacao completa nos 34 meses...")
res = simular_pivo_pavio_ultra_low(initial_balance=300.0, rr=2.0, max_daily_loss=8.0, daily_target=16.0)
t = res["trades"]
wins = len(t[t["pnl"] > 0])
losses = len(t[t["pnl"] < 0])
wr = (wins / len(t)) * 100.0 if len(t) > 0 else 0.0
gp = t[t["pnl"] > 0]["pnl"].sum()
gl = abs(t[t["pnl"] < 0]["pnl"].sum())
pf = (gp / gl) if gl > 0 else 999.0

print(f"Saldo Inicial:  US$ {res['initial_balance']:.2f}")
print(f"Saldo Final:    US$ {res['final_balance']:.2f}")
print(f"Lucro Liquido:  US$ {res['net_pnl']:+.2f} ({res['ret_pct']:+.1f}%)")
print(f"Total Trades:   {res['total_trades']} (Wins: {wins} | Losses: {losses})")
print(f"Win Rate:       {wr:.1f}%")
print(f"Profit Factor:  {pf:.2f}")
print(f"Pior Drawdown:  US$ {res['max_dd']:.2f} ({res['max_dd_pct']:.1f}%)")
