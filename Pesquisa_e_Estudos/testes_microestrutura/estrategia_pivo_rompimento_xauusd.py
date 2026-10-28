import os
import sys
import numpy as np
import pandas as pd
import polars as pl

BASE_DIR = r"C:\Users\Vini_Burgo\Documents\burgo_eas\Pesquisa_e_Estudos\testes_microestrutura"
M15_PATH = os.path.join(BASE_DIR, "xauusd_m15_xm_real_ticks.parquet")
M5_PATH  = os.path.join(BASE_DIR, "xauusd_m5_xm_real_ticks.parquet")

POINT = 0.01
TICK_VAL = 1.0
COMM_PER_LOT = 0.00   # XM Ultra Low Standard tem ZERO comissao no Ouro!
SLIPPAGE_PTS = 10     # $0.10 slippage
SWAP_LONG = -20.0     # Swap reduzido na Ultra Low
SWAP_SHORT = 8.0

print("=== CARREGANDO DATASET DE TICKS REAIS XM PARA ESTRATEGIA DE PIVOS & ROMPIMENTO DE PAVIO ===")
df_pl = pl.read_parquet(M15_PATH)
df = df_pl.to_pandas()
df.set_index("time", inplace=True)
df.sort_index(inplace=True)

# Indicadores Macro com shift(1) estrito
df["ema50"] = df["close"].ewm(span=50, adjust=False).mean().shift(1)
df["ema200"] = df["close"].ewm(span=200, adjust=False).mean().shift(1)
df["ema21"] = df["close"].ewm(span=21, adjust=False).mean().shift(1)

# Precos das barras anteriores para formacao de pivôs
df["h1"] = df["high"].shift(1)
df["l1"] = df["low"].shift(1)
df["c1"] = df["close"].shift(1)
df["o1"] = df["open"].shift(1)

df["h2"] = df["high"].shift(2)
df["l2"] = df["low"].shift(2)
df["c2"] = df["close"].shift(2)

df["h3"] = df["high"].shift(3)
df["l3"] = df["low"].shift(3)

# ATR para protecao minima
tr = np.maximum(df["high"] - df["low"], np.maximum((df["high"] - df["close"].shift(1)).abs(), (df["low"] - df["close"].shift(1)).abs()))
df["atr"] = tr.rolling(14).mean().shift(1)

df.dropna(inplace=True)

def simular_pivos(
    df,
    initial_balance=300.0,
    lot=0.01,
    rr_target=2.0,
    max_daily_loss=8.0,      # Guardiao: trava dia se perder $8 (~2 stops)
    daily_profit_target=16.0, # Guardiao: trava dia no lucro
    use_structural_be=True,   # Move SL para 0x0 apos andar 1R
    use_ema200_filter=True,
    hours_filter=(7, 19)      # Londres e Nova York
):
    balance = initial_balance
    max_equity = balance
    max_dd_usd = 0.0
    
    trades = []
    in_pos = False
    pos_type = None
    entry_p = 0.0
    sl_p = 0.0
    tp_p = 0.0
    risk_pts = 0.0
    entry_time = None
    accum_swap = 0.0
    be_moved = False
    
    cur_day = None
    day_pnl = 0.0
    day_locked = False
    
    times = df.index
    opens = df["open"].values
    highs = df["high"].values
    lows = df["low"].values
    closes = df["close"].values
    spread_means = df["spread_mean"].values
    ema50s = df["ema50"].values
    ema200s = df["ema200"].values
    ema21s = df["ema21"].values
    atrs = df["atr"].values
    
    h1s = df["h1"].values
    l1s = df["l1"].values
    c1s = df["c1"].values
    o1s = df["o1"].values
    h2s = df["h2"].values
    l2s = df["l2"].values
    h3s = df["h3"].values
    l3s = df["l3"].values
    hours = times.hour
    
    n = len(df)
    
    for i in range(n):
        cur_t = times[i]
        b_open = opens[i]
        b_high = highs[i]
        b_low = lows[i]
        cur_spread = spread_means[i]
        
        # Reset diario
        if cur_day != cur_t.date():
            cur_day = cur_t.date()
            day_pnl = 0.0
            day_locked = False
            
        # Gestao de posicao aberta (Defesa ativa)
        if in_pos:
            # Rollover noturno
            if cur_t.date() != entry_time.date():
                mult_swap = 3.0 if entry_time.weekday() == 2 else 1.0
                rate = SWAP_LONG if pos_type == "BUY" else SWAP_SHORT
                accum_swap += (lot * rate * mult_swap)
                entry_time = cur_t
                
            # Defesa Estrutural: Move SL para o 0x0 apenas quando o trade ja andou 1.0x o Risco (1R)
            if use_structural_be and not be_moved:
                if pos_type == "BUY":
                    if (b_high - entry_p) >= (risk_pts * POINT * 1.0):
                        sl_p = entry_p + (cur_spread * 0.5) # Zero a zero com taxa coberta
                        be_moved = True
                elif pos_type == "SELL":
                    if (entry_p - b_low) >= (risk_pts * POINT * 1.0):
                        sl_p = entry_p - (cur_spread * 0.5)
                        be_moved = True
                        
            # Saida da Posicao
            if pos_type == "BUY":
                hit_sl = (b_low <= sl_p)
                hit_tp = (b_high >= tp_p)
                if hit_sl and hit_tp: hit_tp = False # Conservador Sunrise
                
                if hit_sl:
                    exit_p = sl_p - (SLIPPAGE_PTS * POINT)
                    pnl = ((exit_p - entry_p) / POINT) * lot * TICK_VAL - (lot * COMM_PER_LOT) + accum_swap
                    balance += pnl
                    day_pnl += pnl
                    trades.append({"time": cur_t, "type": "BUY", "res": "SL", "pnl": pnl, "bal": balance})
                    in_pos = False
                elif hit_tp:
                    exit_p = tp_p - (SLIPPAGE_PTS * POINT)
                    pnl = ((exit_p - entry_p) / POINT) * lot * TICK_VAL - (lot * COMM_PER_LOT) + accum_swap
                    balance += pnl
                    day_pnl += pnl
                    trades.append({"time": cur_t, "type": "BUY", "res": "TP", "pnl": pnl, "bal": balance})
                    in_pos = False
                    
            elif pos_type == "SELL":
                hit_sl = (b_high >= sl_p)
                hit_tp = (b_low <= tp_p)
                if hit_sl and hit_tp: hit_tp = False # Conservador
                
                if hit_sl:
                    exit_p = sl_p + (SLIPPAGE_PTS * POINT)
                    pnl = ((entry_p - exit_p) / POINT) * lot * TICK_VAL - (lot * COMM_PER_LOT) + accum_swap
                    balance += pnl
                    day_pnl += pnl
                    trades.append({"time": cur_t, "type": "SELL", "res": "SL", "pnl": pnl, "bal": balance})
                    in_pos = False
                elif hit_tp:
                    exit_p = tp_p + (SLIPPAGE_PTS * POINT)
                    pnl = ((entry_p - exit_p) / POINT) * lot * TICK_VAL - (lot * COMM_PER_LOT) + accum_swap
                    balance += pnl
                    day_pnl += pnl
                    trades.append({"time": cur_t, "type": "SELL", "res": "TP", "pnl": pnl, "bal": balance})
                    in_pos = False
                    
            if balance > max_equity: max_equity = balance
            dd = max_equity - balance
            if dd > max_dd_usd: max_dd_usd = dd
            
            # Guardiao de Capital
            if max_daily_loss > 0 and day_pnl <= -max_daily_loss: day_locked = True
            if daily_profit_target > 0 and day_pnl >= daily_profit_target: day_locked = True
            
            if balance <= 30.0: break # Stop out
            
        # Gatilho de Entrada: Pivo + Rompimento de Pavio + Tendencia
        if not in_pos and balance > 30.0 and not day_locked:
            if max_daily_loss > 0 and day_pnl <= -max_daily_loss: continue
            if daily_profit_target > 0 and day_pnl >= daily_profit_target: continue
            
            h = hours[i]
            if hours_filter and (h < hours_filter[0] or h >= hours_filter[1]):
                continue
                
            cur_ema50 = ema50s[i]
            cur_ema200 = ema200s[i]
            cur_ema21 = ema21s[i]
            
            prev_h1 = h1s[i]
            prev_l1 = l1s[i]
            prev_c1 = c1s[i]
            prev_o1 = o1s[i]
            
            prev_h2 = h2s[i]
            prev_l2 = l2s[i]
            
            prev_h3 = h3s[i]
            prev_l3 = l3s[i]
            
            # 1. Filtro de Tendencia Macro
            trend_bull = (prev_c1 > cur_ema200) and (cur_ema50 > cur_ema200) if use_ema200_filter else (cur_ema21 > cur_ema50)
            trend_bear = (prev_c1 < cur_ema200) and (cur_ema50 < cur_ema200) if use_ema200_filter else (cur_ema21 < cur_ema50)
            
            # 2. Formacao de Pivo de Alta e Rompimento de Pavio (Compra):
            # Condicao A: Ocorreu uma retracao em direcao a EMA 21 ou EMA 50 (fundo em V: l2 < l3 e l2 < l1)
            # Condicao B: A barra anterior deixou pavio inferior ou fechou compradora (c1 > o1)
            # Condicao C: O preco atual na abertura rompeu a maxima do pavio anterior (b_open >= prev_h1 ou rompimento de h2)
            is_pivot_low = (prev_l2 <= prev_l3) and (prev_l1 >= prev_l2)
            wick_break_buy = (prev_c1 > prev_o1) and (prev_c1 > cur_ema21) and is_pivot_low
            
            # 3. Formacao de Pivo de Baixa e Rompimento de Pavio (Venda):
            is_pivot_high = (prev_h2 >= prev_h3) and (prev_h1 <= prev_h2)
            wick_break_sell = (prev_c1 < prev_o1) and (prev_c1 < cur_ema21) and is_pivot_high
            
            buy_signal = trend_bull and wick_break_buy
            sell_signal = trend_bear and wick_break_sell
            
            if buy_signal or sell_signal:
                if (cur_spread / POINT) > 60.0: continue
                
                accum_swap = 0.0
                be_moved = False
                entry_time = cur_t
                
                if buy_signal:
                    pos_type = "BUY"
                    entry_p = b_open + cur_spread
                    # Stop técnico abaixo do fundo do pivô (prev_l2) com margem de segurança
                    sl_dist_pts = max(150.0, (entry_p - prev_l2) / POINT + 15.0)
                    if sl_dist_pts > 450.0: sl_dist_pts = 450.0 # Teto maximo de risco para $300
                    
                    sl_p = entry_p - (sl_dist_pts * POINT)
                    tp_p = entry_p + (sl_dist_pts * POINT * rr_target)
                    risk_pts = sl_dist_pts
                    in_pos = True
                    
                elif sell_signal:
                    pos_type = "SELL"
                    entry_p = b_open
                    # Stop técnico acima do topo do pivô (prev_h2) com margem de segurança
                    sl_dist_pts = max(150.0, (prev_h2 - entry_p) / POINT + 15.0 + (cur_spread / POINT))
                    if sl_dist_pts > 450.0: sl_dist_pts = 450.0
                    
                    sl_p = entry_p + (sl_dist_pts * POINT)
                    tp_p = entry_p - (sl_dist_pts * POINT * rr_target)
                    risk_pts = sl_dist_pts
                    in_pos = True

    df_t = pd.DataFrame(trades)
    return {
        "initial_balance": initial_balance,
        "final_balance": balance,
        "net_pnl": balance - initial_balance,
        "ret_pct": ((balance - initial_balance) / initial_balance) * 100.0,
        "max_dd_usd": max_dd_usd,
        "max_dd_pct": (max_dd_usd / initial_balance) * 100.0,
        "total_trades": len(df_t),
        "trades": df_t
    }

def print_result(res, title):
    t = res["trades"]
    if len(t) == 0:
        print(f"[{title}] Sem trades.")
        return
    wins = len(t[t["pnl"] > 0])
    losses = len(t[t["pnl"] < 0])
    wr = (wins / len(t)) * 100.0
    gp = t[t["pnl"] > 0]["pnl"].sum()
    gl = abs(t[t["pnl"] < 0]["pnl"].sum())
    pf = (gp / gl) if gl > 0 else 999.0
    
    print(f"\n=================================================================")
    print(f" {title} ")
    print(f"=================================================================")
    print(f"Saldo Inicial:      US$ {res['initial_balance']:,.2f}")
    print(f"Saldo Final:        US$ {res['final_balance']:,.2f}")
    print(f"Lucro Liquido:      US$ {res['net_pnl']:+,.2f} ({res['ret_pct']:+.1f}%)")
    print(f"Total de Trades:    {res['total_trades']} (Wins: {wins} | Losses: {losses})")
    print(f"Taxa de Acerto:     {wr:.1f}%")
    print(f"Profit Factor (PF): {pf:.2f}")
    print(f"Pior Drawdown:      US$ {res['max_dd_usd']:,.2f} ({res['max_dd_pct']:.1f}%)")
    print(f"=================================================================")

if __name__ == "__main__":
    # Testar variacoes de Risco:Retorno e Defesa Estrutural
    print("\n--- TESTE 1: PIVOS + ROMPIMENTO DE PAVIO (RR 1:2.0 - COM DEFESA E GUARDIAO) ---")
    res1 = simular_pivos(df, initial_balance=300.0, rr_target=2.0, max_daily_loss=8.0, use_structural_be=True)
    print_result(res1, "PIVOS & PAVIO - RR 1:2.0 - DEFESA BE 1R & GUARDAO $8")
    
    print("\n--- TESTE 2: PIVOS + ROMPIMENTO DE PAVIO (RR 1:1.5 - COM DEFESA E GUARDIAO) ---")
    res2 = simular_pivos(df, initial_balance=300.0, rr_target=1.5, max_daily_loss=6.0, use_structural_be=True)
    print_result(res2, "PIVOS & PAVIO - RR 1:1.5 - DEFESA BE 1R & GUARDAO $6")

    print("\n--- TESTE 3: PIVOS + ROMPIMENTO DE PAVIO (RR 1:2.0 - SEM BE, STOP FIXO NO PIVO) ---")
    res3 = simular_pivos(df, initial_balance=300.0, rr_target=2.0, max_daily_loss=8.0, use_structural_be=False)
    print_result(res3, "PIVOS & PAVIO - RR 1:2.0 - SEM BE (DEIXA CORRER ATE TP/SL)")
