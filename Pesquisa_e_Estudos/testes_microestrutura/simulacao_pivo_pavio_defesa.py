import os
import sys
import numpy as np
import pandas as pd
import polars as pl

BASE_DIR = r"C:\Users\Vini_Burgo\Documents\burgo_eas\Pesquisa_e_Estudos\testes_microestrutura"
M15_PATH = os.path.join(BASE_DIR, "xauusd_m15_xm_real_ticks.parquet")

POINT = 0.01
TICK_VAL = 1.0
COMM_PER_LOT = 0.0  # XM Ultra Low
SLIPPAGE = 0.10

df_pl = pl.read_parquet(M15_PATH)
df = df_pl.to_pandas()
df.set_index("time", inplace=True)
df.sort_index(inplace=True)

# Indicadores shift(1)
df["ema21"] = df["close"].ewm(span=21, adjust=False).mean().shift(1)
df["ema50"] = df["close"].ewm(span=50, adjust=False).mean().shift(1)
df["ema200"] = df["close"].ewm(span=200, adjust=False).mean().shift(1)

# Barras anteriores
df["o1"] = df["open"].shift(1)
df["h1"] = df["high"].shift(1)
df["l1"] = df["low"].shift(1)
df["c1"] = df["close"].shift(1)

df["o2"] = df["open"].shift(2)
df["h2"] = df["high"].shift(2)
df["l2"] = df["low"].shift(2)
df["c2"] = df["close"].shift(2)

df.dropna(inplace=True)

def testar_estrategia(
    name,
    rr=2.0,
    use_be=True,
    be_r=1.0,           # move para 0x0 apos andar 1R
    max_daily_loss=6.0,  # trava $6 no dia (~2 stops)
    daily_target=12.0,   # meta $12 no dia (+4%)
    wick_ratio=0.25,     # pavio deve ser pelo menos 25% da barra
    min_sl_pts=120.0,
    max_sl_pts=350.0
):
    balance = 300.0
    initial_balance = 300.0
    max_equity = balance
    max_dd = 0.0
    lot = 0.01
    
    trades = []
    in_pos = False
    pos_type = None
    entry_p = 0.0
    sl_p = 0.0
    tp_p = 0.0
    risk_p = 0.0
    be_triggered = False
    
    cur_day = None
    day_pnl = 0.0
    day_locked = False
    
    times = df.index
    opens = df["open"].values
    highs = df["high"].values
    lows = df["low"].values
    spreads = df["spread_mean"].values
    ema21s = df["ema21"].values
    ema50s = df["ema50"].values
    ema200s = df["ema200"].values
    
    o1s = df["o1"].values
    h1s = df["h1"].values
    l1s = df["l1"].values
    c1s = df["c1"].values
    
    o2s = df["o2"].values
    h2s = df["h2"].values
    l2s = df["l2"].values
    c2s = df["c2"].values
    
    hours = times.hour
    
    for i in range(len(df)):
        cur_t = times[i]
        b_open = opens[i]
        b_high = highs[i]
        b_low = lows[i]
        cur_spread = spreads[i]
        
        # Reset diario
        if cur_day != cur_t.date():
            cur_day = cur_t.date()
            day_pnl = 0.0
            day_locked = False
            
        # Gestao da posicao aberta (Defesa da Boleta)
        if in_pos:
            # Defesa de Break-Even apos andar 1R a favor
            if use_be and not be_triggered:
                if pos_type == "BUY":
                    if (b_high - entry_p) >= (risk_p * be_r):
                        sl_p = entry_p + (cur_spread * 0.5) # trava no zero a zero
                        be_triggered = True
                elif pos_type == "SELL":
                    if (entry_p - b_low) >= (risk_p * be_r):
                        sl_p = entry_p - (cur_spread * 0.5)
                        be_triggered = True
                        
            # Saida
            if pos_type == "BUY":
                hit_sl = (b_low <= sl_p)
                hit_tp = (b_high >= tp_p)
                if hit_sl and hit_tp: hit_tp = False
                if hit_sl:
                    exit_p = sl_p - (SLIPPAGE * POINT)
                    pnl = ((exit_p - entry_p) / POINT) * lot * TICK_VAL
                    balance += pnl
                    day_pnl += pnl
                    trades.append({"res": "SL", "pnl": pnl, "bal": balance})
                    in_pos = False
                elif hit_tp:
                    exit_p = tp_p - (SLIPPAGE * POINT)
                    pnl = ((exit_p - entry_p) / POINT) * lot * TICK_VAL
                    balance += pnl
                    day_pnl += pnl
                    trades.append({"res": "TP", "pnl": pnl, "bal": balance})
                    in_pos = False
                    
            elif pos_type == "SELL":
                hit_sl = (b_high >= sl_p)
                hit_tp = (b_low <= tp_p)
                if hit_sl and hit_tp: hit_tp = False
                if hit_sl:
                    exit_p = sl_p + (SLIPPAGE * POINT)
                    pnl = ((entry_p - exit_p) / POINT) * lot * TICK_VAL
                    balance += pnl
                    day_pnl += pnl
                    trades.append({"res": "SL", "pnl": pnl, "bal": balance})
                    in_pos = False
                elif hit_tp:
                    exit_p = tp_p + (SLIPPAGE * POINT)
                    pnl = ((entry_p - exit_p) / POINT) * lot * TICK_VAL
                    balance += pnl
                    day_pnl += pnl
                    trades.append({"res": "TP", "pnl": pnl, "bal": balance})
                    in_pos = False
                    
            if balance > max_equity: max_equity = balance
            dd = max_equity - balance
            if dd > max_dd: max_dd = dd
            
            # Guardiao de Capital Diário
            if max_daily_loss > 0 and day_pnl <= -max_daily_loss: day_locked = True
            if daily_target > 0 and day_pnl >= daily_target: day_locked = True
            if balance <= 30.0: break
            
        # Gatilho de Entrada: Tendencia + Pivo + Rompimento de Pavio
        if not in_pos and balance > 30.0 and not day_locked:
            if max_daily_loss > 0 and day_pnl <= -max_daily_loss: continue
            if daily_target > 0 and day_pnl >= daily_target: continue
            
            # Sessao Londres / NY
            h = hours[i]
            if h < 7 or h >= 18: continue
            
            cur_ema200 = ema200s[i]
            cur_ema50  = ema50s[i]
            cur_ema21  = ema21s[i]
            
            c1 = c1s[i]
            o1 = o1s[i]
            h1 = h1s[i]
            l1 = l1s[i]
            
            c2 = c2s[i]
            o2 = o2s[i]
            h2 = h2s[i]
            l2 = l2s[i]
            rng1 = h1 - l1
            if rng1 <= 0.0: continue
            
            # 1. Filtro de Tendência Alinhada (EMA50 > EMA200 e Preço > EMA200)
            trend_bull = (c1 > cur_ema200) and (cur_ema50 > cur_ema200)
            trend_bear = (c1 < cur_ema200) and (cur_ema50 < cur_ema200)
            
            # 2. Formação do Pivô com Rejeição por Pavio
            # Compra:
            # - O preço recuou até a região da EMA21 ou EMA50 (l1 <= cur_ema21 ou l2 <= cur_ema21)
            # - A barra anterior rejeitou o fundo deixando pavio inferior
            lower_wick = min(o1, c1) - l1
            is_bull_pivo = trend_bull and (l1 <= cur_ema21 or l2 <= cur_ema21) and (lower_wick >= rng1 * wick_ratio) and (c1 > o1)
            
            # Venda:
            # - O preço repiquou até a EMA21 ou EMA50 (h1 >= cur_ema21 ou h2 >= cur_ema21)
            # - A barra anterior rejeitou o topo deixando pavio superior
            upper_wick = h1 - max(o1, c1)
            is_bear_pivo = trend_bear and (h1 >= cur_ema21 or h2 >= cur_ema21) and (upper_wick >= rng1 * wick_ratio) and (c1 < o1)
            
            # 3. Rompimento do Pavio do Pivô (Wick Breakout):
            # Na barra atual de abertura, se o preço ultrapassa a máxima/mínima do pavio anterior
            if is_bull_pivo:
                entry_p = b_open + cur_spread
                # Stop loss posicionado exatamente abaixo do pavio do pivô
                sl_pts = (entry_p - l1) / POINT + 10.0
                if sl_pts >= min_sl_pts and sl_pts <= max_sl_pts:
                    pos_type = "BUY"
                    sl_p = entry_p - (sl_pts * POINT)
                    tp_p = entry_p + (sl_pts * POINT * rr)
                    risk_p = sl_pts * POINT
                    be_triggered = False
                    in_pos = True
                    
            elif is_bear_pivo:
                entry_p = b_open
                sl_pts = (h1 - entry_p) / POINT + 10.0 + (cur_spread / POINT)
                if sl_pts >= min_sl_pts and sl_pts <= max_sl_pts:
                    pos_type = "SELL"
                    sl_p = entry_p + (sl_pts * POINT)
                    tp_p = entry_p - (sl_pts * POINT * rr)
                    risk_p = sl_pts * POINT
                    be_triggered = False
                    in_pos = True
                    
    df_t = pd.DataFrame(trades)
    if len(df_t) == 0:
        print(f"[{name}] Sem trades.")
        return
    wins = len(df_t[df_t["res"] == "TP"])
    wr = (wins / len(df_t)) * 100.0
    pnl = balance - initial_balance
    gp = df_t[df_t["pnl"] > 0]["pnl"].sum()
    gl = abs(df_t[df_t["pnl"] < 0]["pnl"].sum())
    pf = (gp / gl) if gl > 0 else 999.0
    print(f"[{name}] Trades: {len(df_t):4d} | WinRate: {wr:4.1f}% | PnL: ${pnl:+7.2f} ({(pnl/initial_balance)*100:+5.1f}%) | PF: {pf:4.2f} | MaxDD: ${max_dd:5.2f} ({(max_dd/initial_balance)*100:4.1f}%) | Saldo Final: ${balance:.2f}")

print("=== AUDITORIA: PIVO + ROMPIMENTO DE PAVIO + TENDENCIA + DEFESA ATIVA ===")
# 1. Sem BE, R:R 1:2.0
testar_estrategia("1. Sem BE | RR 2.0 | Trava $6", rr=2.0, use_be=False, max_daily_loss=6.0, daily_target=12.0)

# 2. Com BE em 1R, R:R 1:2.0
testar_estrategia("2. Com BE 1R | RR 2.0 | Trava $6", rr=2.0, use_be=True, be_r=1.0, max_daily_loss=6.0, daily_target=12.0)

# 3. Com BE em 1R, R:R 1:1.5
testar_estrategia("3. Com BE 1R | RR 1.5 | Trava $6", rr=1.5, use_be=True, be_r=1.0, max_daily_loss=6.0, daily_target=10.0)

# 4. Sem BE, R:R 1:1.5
testar_estrategia("4. Sem BE | RR 1.5 | Trava $6", rr=1.5, use_be=False, max_daily_loss=6.0, daily_target=10.0)

# 5. Sem Trava Diaria (Livre), RR 2.0
testar_estrategia("5. Livre (Sem Trava) | RR 2.0", rr=2.0, use_be=False, max_daily_loss=0, daily_target=0)

# 6. Trava Severa $4.00 (1 Stop/dia), RR 2.5
testar_estrategia("6. Trava $4 (1 Stop/dia) | RR 2.5", rr=2.5, use_be=False, max_daily_loss=4.0, daily_target=10.0)
