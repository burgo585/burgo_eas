import os
import sys
import pandas as pd
import numpy as np
import polars as pl

BASE_DIR = r"C:\Users\Vini_Burgo\Documents\burgo_eas\Pesquisa_e_Estudos\testes_microestrutura"
M15_PATH = os.path.join(BASE_DIR, "xauusd_m15_xm_real_ticks.parquet")

POINT = 0.01
TICK_VAL = 1.0
COMM_PER_LOT = 6.00
SLIPPAGE_PTS = 10
SWAP_LONG = -40.0
SWAP_SHORT = 15.0

df_pl = pl.read_parquet(M15_PATH)
df = df_pl.to_pandas()
df.set_index("time", inplace=True)
df.sort_index(inplace=True)

# Indicadores shift(1)
df["ema9"] = df["close"].ewm(span=9, adjust=False).mean().shift(1)
df["ema21"] = df["close"].ewm(span=21, adjust=False).mean().shift(1)
df["ema200"] = df["close"].ewm(span=200, adjust=False).mean().shift(1)
tr = np.maximum(df["high"] - df["low"], np.maximum((df["high"] - df["close"].shift(1)).abs(), (df["low"] - df["close"].shift(1)).abs()))
df["atr"] = tr.rolling(14).mean().shift(1)
df["prev_open"] = df["open"].shift(1)
df["prev_high"] = df["high"].shift(1)
df["prev_low"] = df["low"].shift(1)
df["prev_close"] = df["close"].shift(1)
df.dropna(inplace=True)

def test_config(
    name,
    use_ema200=True,
    fresh_cross_only=False,
    max_daily_loss=10.0,
    daily_profit_target=20.0,
    max_trades_day=2,
    fixed_sl_pts=0,      # 0 = usa ATR
    atr_mult=1.5,
    rr=2.0,
    hours_filter=(7, 20) # Londres/NY
):
    balance = 300.0
    initial_balance = 300.0
    max_equity = balance
    max_dd_usd = 0.0
    lot = 0.01
    
    trades = []
    in_pos = False
    pos_type = None
    entry_p = 0.0
    entry_time = None
    sl_p = 0.0
    tp_p = 0.0
    cur_vol = 0.01
    accum_swap = 0.0
    
    cur_day = None
    day_pnl = 0.0
    day_trades = 0
    day_locked = False
    
    # Tracking de cruzamento para fresh_cross_only
    last_cross_dir = None
    already_traded_this_cross = False
    
    n_bars = len(df)
    times = df.index
    opens = df["open"].values
    highs = df["high"].values
    lows = df["low"].values
    closes = df["close"].values
    spread_means = df["spread_mean"].values
    atrs = df["atr"].values
    ema9s = df["ema9"].values
    ema21s = df["ema21"].values
    ema200s = df["ema200"].values
    prev_opens = df["prev_open"].values
    prev_highs = df["prev_high"].values
    prev_lows = df["prev_low"].values
    prev_closes = df["prev_close"].values
    hours = times.hour
    
    for i in range(n_bars):
        cur_t = times[i]
        b_open = opens[i]
        b_high = highs[i]
        b_low = lows[i]
        b_close = closes[i]
        cur_spread = spread_means[i]
        
        # Reset diario
        if cur_day != cur_t.date():
            cur_day = cur_t.date()
            day_pnl = 0.0
            day_trades = 0
            day_locked = False
            
        # Gestao de posicao aberta
        if in_pos:
            if cur_t.date() != entry_time.date():
                mult_swap = 3.0 if entry_time.weekday() == 2 else 1.0
                daily_rate = SWAP_LONG if pos_type == "BUY" else SWAP_SHORT
                accum_swap += (cur_vol * daily_rate * mult_swap)
                entry_time = cur_t
                
            if pos_type == "BUY":
                hit_sl = (b_low <= sl_p)
                hit_tp = (b_high >= tp_p)
                if hit_sl and hit_tp: hit_tp = False
                if hit_sl:
                    exit_p = sl_p - (SLIPPAGE_PTS * POINT)
                    pnl = ((exit_p - entry_p) / POINT) * cur_vol * TICK_VAL - (cur_vol * COMM_PER_LOT) + accum_swap
                    balance += pnl
                    day_pnl += pnl
                    day_trades += 1
                    trades.append({"res": "SL", "pnl": pnl, "bal": balance})
                    in_pos = False
                elif hit_tp:
                    exit_p = tp_p - (SLIPPAGE_PTS * POINT)
                    pnl = ((exit_p - entry_p) / POINT) * cur_vol * TICK_VAL - (cur_vol * COMM_PER_LOT) + accum_swap
                    balance += pnl
                    day_pnl += pnl
                    day_trades += 1
                    trades.append({"res": "TP", "pnl": pnl, "bal": balance})
                    in_pos = False
                    
            elif pos_type == "SELL":
                hit_sl = (b_high >= sl_p)
                hit_tp = (b_low <= tp_p)
                if hit_sl and hit_tp: hit_tp = False
                if hit_sl:
                    exit_p = sl_p + (SLIPPAGE_PTS * POINT)
                    pnl = ((entry_p - exit_p) / POINT) * cur_vol * TICK_VAL - (cur_vol * COMM_PER_LOT) + accum_swap
                    balance += pnl
                    day_pnl += pnl
                    day_trades += 1
                    trades.append({"res": "SL", "pnl": pnl, "bal": balance})
                    in_pos = False
                elif hit_tp:
                    exit_p = tp_p + (SLIPPAGE_PTS * POINT)
                    pnl = ((entry_p - exit_p) / POINT) * cur_vol * TICK_VAL - (cur_vol * COMM_PER_LOT) + accum_swap
                    balance += pnl
                    day_pnl += pnl
                    day_trades += 1
                    trades.append({"res": "TP", "pnl": pnl, "bal": balance})
                    in_pos = False
                    
            if balance > max_equity: max_equity = balance
            dd = max_equity - balance
            if dd > max_dd_usd: max_dd_usd = dd
            
            # Checar trava diaria
            if max_daily_loss > 0 and day_pnl <= -max_daily_loss:
                day_locked = True
            if daily_profit_target > 0 and day_pnl >= daily_profit_target:
                day_locked = True
            if max_trades_day > 0 and day_trades >= max_trades_day:
                day_locked = True
                
            if balance <= 30.0: # Stop out real da corretora XM
                break
                
        # Checagem de entrada
        if not in_pos and balance > 30.0 and not day_locked:
            if max_daily_loss > 0 and day_pnl <= -max_daily_loss: continue
            if daily_profit_target > 0 and day_pnl >= daily_profit_target: continue
            if max_trades_day > 0 and day_trades >= max_trades_day: continue
            
            h = hours[i]
            if hours_filter and (h < hours_filter[0] or h >= hours_filter[1]):
                continue
                
            fast_ema = ema9s[i]
            slow_ema = ema21s[i]
            macro_ema = ema200s[i]
            p_open = prev_opens[i]
            p_high = prev_highs[i]
            p_low = prev_lows[i]
            p_close = prev_closes[i]
            
            # Checagem de cruzamento
            current_cross = "BULL" if fast_ema > slow_ema else "BEAR"
            if current_cross != last_cross_dir:
                last_cross_dir = current_cross
                already_traded_this_cross = False
                
            if fresh_cross_only and already_traded_this_cross:
                continue
                
            buy_pullback = (fast_ema > slow_ema) and (p_low <= fast_ema) and (p_close > fast_ema)
            buy_cross    = (fast_ema > slow_ema) and (p_open <= fast_ema) and (p_close > fast_ema)
            buy_signal   = buy_pullback or buy_cross
            
            sell_pullback = (fast_ema < slow_ema) and (p_high >= fast_ema) and (p_close < fast_ema)
            sell_cross    = (fast_ema < slow_ema) and (p_open >= fast_ema) and (p_close < fast_ema)
            sell_signal   = sell_pullback or sell_cross
            
            if use_ema200:
                if buy_signal and p_close < macro_ema: buy_signal = False
                if sell_signal and p_close > macro_ema: sell_signal = False
                
            if buy_signal or sell_signal:
                if (cur_spread / POINT) > 70.0: continue
                
                if fixed_sl_pts > 0:
                    sl_pts = fixed_sl_pts
                else:
                    sl_pts = max(30.0, (atrs[i] / POINT) * atr_mult)
                tp_pts = sl_pts * rr
                
                accum_swap = 0.0
                entry_time = cur_t
                already_traded_this_cross = True
                
                if buy_signal:
                    pos_type = "BUY"
                    entry_p = b_open + cur_spread
                    sl_p = entry_p - (sl_pts * POINT)
                    tp_p = entry_p + (tp_pts * POINT)
                    in_pos = True
                elif sell_signal:
                    pos_type = "SELL"
                    entry_p = b_open
                    sl_p = entry_p + (sl_pts * POINT) + cur_spread
                    tp_p = entry_p - (tp_pts * POINT)
                    in_pos = True
                    
    df_t = pd.DataFrame(trades)
    if len(df_t) == 0:
        print(f"[{name}] 0 trades.")
        return
    wins = len(df_t[df_t["res"] == "TP"])
    wr = (wins / len(df_t)) * 100.0
    pnl = balance - initial_balance
    gp = df_t[df_t["pnl"] > 0]["pnl"].sum()
    gl = abs(df_t[df_t["pnl"] < 0]["pnl"].sum())
    pf = (gp / gl) if gl > 0 else 999.0
    print(f"[{name}] Trades: {len(df_t):4d} | WinRate: {wr:4.1f}% | PnL: ${pnl:+8.2f} ({(pnl/initial_balance)*100:+6.1f}%) | PF: {pf:4.2f} | MaxDD: ${max_dd_usd:6.2f} ({(max_dd_usd/initial_balance)*100:4.1f}%) | Saldo Final: ${balance:.2f}")

print("=== AUDITORIA DE REBAIXAMENTO PARA BANCA DE $300 (LOTE 0.01) ===")
# 0. Base Original
test_config("0. Original (Sem Filtros)", use_ema200=False, fresh_cross_only=False, max_daily_loss=0, daily_profit_target=0, max_trades_day=0)

# 1. Filtro Macro EMA 200 (Tendencia Principal)
test_config("1. Com EMA 200", use_ema200=True, fresh_cross_only=False, max_daily_loss=0, daily_profit_target=0, max_trades_day=0)

# 2. Apenas 1 Trade por Cruzamento (Sem overtrading em consolidacao)
test_config("2. 1 Trade por Cruzamento", use_ema200=False, fresh_cross_only=True, max_daily_loss=0, daily_profit_target=0, max_trades_day=0)

# 3. EMA 200 + 1 Trade por Cruzamento
test_config("3. EMA 200 + 1 Trade/Cruzamento", use_ema200=True, fresh_cross_only=True, max_daily_loss=0, daily_profit_target=0, max_trades_day=0)

# 4. EMA 200 + 1 Trade/Cruzamento + Guardiao Diario (Max Loss $8.00 = ~2 stops)
test_config("4. EMA200 + 1 Trade/Cruz + Trava Dia $8", use_ema200=True, fresh_cross_only=True, max_daily_loss=8.0, daily_profit_target=16.0, max_trades_day=2)

# 5. EMA 200 + 1 Trade/Cruz + Trava Dia $6.00 + Max 1 trade/dia
test_config("5. EMA200 + 1 Trade/Cruz + Max 1 trade/dia", use_ema200=True, fresh_cross_only=True, max_daily_loss=6.0, daily_profit_target=12.0, max_trades_day=1)

# 6. Stop Fixo Curto (200 pts = $2.00) e TP (400 pts = $4.00) + EMA200
test_config("6. Stop 200pts/TP 400pts + EMA200 + 1/Cruz", use_ema200=True, fresh_cross_only=True, max_daily_loss=6.0, daily_profit_target=12.0, max_trades_day=2, fixed_sl_pts=200, rr=2.0)
