import os
import sys
import numpy as np
import pandas as pd
import polars as pl
from datetime import datetime

# Definir caminhos
BASE_DIR = r"C:\Users\Vini_Burgo\Documents\burgo_eas\Pesquisa_e_Estudos\testes_microestrutura"
M5_PATH  = os.path.join(BASE_DIR, "xauusd_m5_xm_real_ticks.parquet")
M15_PATH = os.path.join(BASE_DIR, "xauusd_m15_xm_real_ticks.parquet")

POINT = 0.01
TICK_VAL = 1.0  # $1.00 por ponto para 1 lote standard (100 oz de ouro)
COMM_PER_LOT = 6.00  # $6.00 por lote standard round-turn ($0.06 por 0.01 lot)
SLIPPAGE_PTS = 10  # 10 pontos = $0.10 slippage no ouro
SWAP_LONG_PER_LOT_DAY = -40.0  # Custo noturno XM em compra
SWAP_SHORT_PER_LOT_DAY = 15.0  # Custo/credito noturno XM em venda

def load_and_prepare(tf="M15"):
    fpath = M15_PATH if tf == "M15" else M5_PATH
    print(f"Carregando dataset de {tf}: {fpath}...")
    df_pl = pl.read_parquet(fpath)
    df = df_pl.to_pandas()
    df.set_index("time", inplace=True)
    df.sort_index(inplace=True)
    
    # Calculo causal estrito (shift=1): nenhum indicador le a barra atual
    prev_close = df["close"].shift(1)
    tr = np.maximum(
        df["high"] - df["low"],
        np.maximum(
            (df["high"] - prev_close).abs(),
            (df["low"] - prev_close).abs()
        )
    )
    df["atr"] = tr.rolling(14).mean().shift(1)
    df["ema9"] = df["close"].ewm(span=9, adjust=False).mean().shift(1)
    df["ema21"] = df["close"].ewm(span=21, adjust=False).mean().shift(1)
    
    # Deslocamento causal dos precos anteriores para gatilhos de pullback/cross
    df["prev_open"] = df["open"].shift(1)
    df["prev_high"] = df["high"].shift(1)
    df["prev_low"] = df["low"].shift(1)
    df["prev_close"] = prev_close
    
    df.dropna(inplace=True)
    return df

def simulate_engine(
    df,
    initial_balance=5000.0,
    risk_pct=1.0,
    rr=2.0,
    atr_mult=1.5,
    max_spread_pts=70.0,
    use_partial=False,
    partial_pts=150,
    partial_pct=50.0,
    partial_move_be=False,
    use_be=False,
    be_pts=100,
    trade_only_london_ny=False
):
    balance = initial_balance
    equity = balance
    max_equity = balance
    max_dd_usd = 0.0
    max_dd_pct = 0.0
    
    trades = []
    in_pos = False
    pos_type = None
    entry_p = 0.0
    entry_time = None
    sl_p = 0.0
    tp_p = 0.0
    lot = 0.0
    cur_vol = 0.0
    partial_executed = False
    accum_swap = 0.0
    total_swap_paid = 0.0
    total_comm_paid = 0.0
    
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
    prev_opens = df["prev_open"].values
    prev_highs = df["prev_high"].values
    prev_lows = df["prev_low"].values
    prev_closes = df["prev_close"].values
    hours = times.hour
    days = times.dayofweek
    
    for i in range(n_bars):
        cur_t = times[i]
        b_open = opens[i]
        b_high = highs[i]
        b_low = lows[i]
        b_close = closes[i]
        cur_spread = spread_means[i]
        cur_spread_pts = cur_spread / POINT
        
        # Gestao da posicao aberta
        if in_pos:
            # Checar rollover/swap se mudou de dia
            if cur_t.date() != entry_time.date():
                n_days = (cur_t.date() - entry_time.date()).days
                # Quarta-feira = triplo
                mult_swap = 3.0 if entry_time.weekday() == 2 else 1.0
                daily_rate = SWAP_LONG_PER_LOT_DAY if pos_type == "BUY" else SWAP_SHORT_PER_LOT_DAY
                swap_cost = cur_vol * daily_rate * mult_swap
                accum_swap += swap_cost
                entry_time = cur_t  # reseta para proxima contagem
            
            # Avaliacao de Parcial
            if use_partial and not partial_executed:
                if pos_type == "BUY":
                    if ((b_high - entry_p) / POINT) >= partial_pts:
                        p_vol = round(cur_vol * (partial_pct / 100.0), 2)
                        p_vol = max(0.01, min(p_vol, cur_vol))
                        p_pnl = ((partial_pts * POINT) / POINT) * p_vol * TICK_VAL - (p_vol * COMM_PER_LOT)
                        balance += p_pnl
                        total_comm_paid += (p_vol * COMM_PER_LOT)
                        cur_vol = round(cur_vol - p_vol, 2)
                        partial_executed = True
                        if partial_move_be and sl_p < entry_p:
                            sl_p = entry_p
                elif pos_type == "SELL":
                    if ((entry_p - b_low) / POINT) >= partial_pts:
                        p_vol = round(cur_vol * (partial_pct / 100.0), 2)
                        p_vol = max(0.01, min(p_vol, cur_vol))
                        p_pnl = ((partial_pts * POINT) / POINT) * p_vol * TICK_VAL - (p_vol * COMM_PER_LOT)
                        balance += p_pnl
                        total_comm_paid += (p_vol * COMM_PER_LOT)
                        cur_vol = round(cur_vol - p_vol, 2)
                        partial_executed = True
                        if partial_move_be and (sl_p == 0.0 or sl_p > entry_p):
                            sl_p = entry_p
            
            # Avaliacao de Break-Even independente
            if use_be and not partial_executed:
                if pos_type == "BUY":
                    if ((b_high - entry_p) / POINT) >= be_pts and sl_p < entry_p:
                        sl_p = entry_p
                elif pos_type == "SELL":
                    if ((entry_p - b_low) / POINT) >= be_pts and (sl_p == 0.0 or sl_p > entry_p):
                        sl_p = entry_p
            
            # Avaliacao de Saida (SL vs TP) com Regra Conservadora Sunrise:
            # Se a vela tocou tanto SL quanto TP, SL executa primeiro!
            if pos_type == "BUY":
                hit_sl = (b_low <= sl_p)
                hit_tp = (b_high >= tp_p)
                if hit_sl and hit_tp:
                    hit_tp = False  # Sem ilusao de teletransporte para o topo
                
                if hit_sl:
                    exit_p = sl_p - (SLIPPAGE_PTS * POINT)
                    pnl = ((exit_p - entry_p) / POINT) * cur_vol * TICK_VAL - (cur_vol * COMM_PER_LOT) + accum_swap
                    balance += pnl
                    total_comm_paid += (cur_vol * COMM_PER_LOT)
                    total_swap_paid += accum_swap
                    trades.append({"time": cur_t, "type": "BUY", "res": "SL", "pnl": pnl, "vol": cur_vol, "bal": balance})
                    in_pos = False
                elif hit_tp:
                    exit_p = tp_p - (SLIPPAGE_PTS * POINT)
                    pnl = ((exit_p - entry_p) / POINT) * cur_vol * TICK_VAL - (cur_vol * COMM_PER_LOT) + accum_swap
                    balance += pnl
                    total_comm_paid += (cur_vol * COMM_PER_LOT)
                    total_swap_paid += accum_swap
                    trades.append({"time": cur_t, "type": "BUY", "res": "TP", "pnl": pnl, "vol": cur_vol, "bal": balance})
                    in_pos = False
                    
            elif pos_type == "SELL":
                hit_sl = (b_high >= sl_p)
                hit_tp = (b_low <= tp_p)
                if hit_sl and hit_tp:
                    hit_tp = False  # Sem ilusao
                
                if hit_sl:
                    exit_p = sl_p + (SLIPPAGE_PTS * POINT)
                    pnl = ((entry_p - exit_p) / POINT) * cur_vol * TICK_VAL - (cur_vol * COMM_PER_LOT) + accum_swap
                    balance += pnl
                    total_comm_paid += (cur_vol * COMM_PER_LOT)
                    total_swap_paid += accum_swap
                    trades.append({"time": cur_t, "type": "SELL", "res": "SL", "pnl": pnl, "vol": cur_vol, "bal": balance})
                    in_pos = False
                elif hit_tp:
                    exit_p = tp_p + (SLIPPAGE_PTS * POINT)
                    pnl = ((entry_p - exit_p) / POINT) * cur_vol * TICK_VAL - (cur_vol * COMM_PER_LOT) + accum_swap
                    balance += pnl
                    total_comm_paid += (cur_vol * COMM_PER_LOT)
                    total_swap_paid += accum_swap
                    trades.append({"time": cur_t, "type": "SELL", "res": "TP", "pnl": pnl, "vol": cur_vol, "bal": balance})
                    in_pos = False
            
            # Rebaixamento flutuante / stop out
            if balance > max_equity:
                max_equity = balance
            dd = max_equity - balance
            if dd > max_dd_usd:
                max_dd_usd = dd
                max_dd_pct = (dd / max_equity) * 100.0 if max_equity > 0 else 0.0
            
            # Se quebrou a banca
            if balance <= 50.0:  # Margem minima/Stop-Out
                trades.append({"time": cur_t, "type": pos_type, "res": "STOP_OUT", "pnl": -balance, "vol": cur_vol, "bal": 0.0})
                balance = 0.0
                break
        
        # Checagem de Novo Sinal na Abertura da Barra
        if not in_pos and balance > 50.0:
            if cur_spread_pts > max_spread_pts:
                continue
                
            if trade_only_london_ny:
                h = hours[i]
                if h < 7 or h >= 20:
                    continue
            
            fast_ema = ema9s[i]
            slow_ema = ema21s[i]
            p_open = prev_opens[i]
            p_high = prev_highs[i]
            p_low = prev_lows[i]
            p_close = prev_closes[i]
            
            buy_pullback = (fast_ema > slow_ema) and (p_low <= fast_ema) and (p_close > fast_ema)
            buy_cross    = (fast_ema > slow_ema) and (p_open <= fast_ema) and (p_close > fast_ema)
            buy_signal   = buy_pullback or buy_cross
            
            sell_pullback = (fast_ema < slow_ema) and (p_high >= fast_ema) and (p_close < fast_ema)
            sell_cross    = (fast_ema < slow_ema) and (p_open >= fast_ema) and (p_close < fast_ema)
            sell_signal   = sell_pullback or sell_cross
            
            if buy_signal or sell_signal:
                cur_atr = atrs[i]
                atr_pts = cur_atr / POINT
                sl_pts = max(30.0, atr_pts * atr_mult)
                tp_pts = max(10.0, sl_pts * rr)
                
                risk_money = balance * (risk_pct / 100.0)
                lot = round(risk_money / (sl_pts * TICK_VAL), 2)
                lot = max(0.01, min(lot, 50.0))  # limite de seguranca
                cur_vol = lot
                accum_swap = 0.0
                partial_executed = False
                entry_time = cur_t
                
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
    return {
        "initial_balance": initial_balance,
        "final_balance": balance,
        "net_pnl": balance - initial_balance,
        "ret_pct": ((balance - initial_balance) / initial_balance) * 100.0,
        "max_dd_usd": max_dd_usd,
        "max_dd_pct": max_dd_pct,
        "total_trades": len(df_t),
        "total_comm": total_comm_paid,
        "total_swap": total_swap_paid,
        "trades": df_t
    }

def print_summary(res, title="RESULTADO"):
    t = res["trades"]
    if len(t) == 0:
        print(f"[{title}] Sem trades.")
        return
    wins = len(t[t["pnl"] > 0])
    losses = len(t[t["pnl"] < 0])
    wr = (wins / len(t)) * 100.0 if len(t) > 0 else 0.0
    gp = t[t["pnl"] > 0]["pnl"].sum()
    gl = abs(t[t["pnl"] < 0]["pnl"].sum())
    pf = (gp / gl) if gl > 0 else 999.0
    
    print(f"\n=======================================================")
    print(f" {title} ")
    print(f"=======================================================")
    print(f"Saldo Inicial:      US$ {res['initial_balance']:,.2f}")
    print(f"Saldo Final:        US$ {res['final_balance']:,.2f}")
    print(f"Lucro Liquido Real: US$ {res['net_pnl']:+,.2f} ({res['ret_pct']:+.1f}%)")
    print(f"Total de Trades:    {res['total_trades']} (Wins: {wins} | Losses: {losses})")
    print(f"Taxa de Acerto:     {wr:.1f}%")
    print(f"Profit Factor (PF): {pf:.2f}")
    print(f"Pior Drawdown:      US$ {res['max_dd_usd']:,.2f} ({res['max_dd_pct']:.1f}%)")
    print(f"Comissoes Pagas:    US$ {res['total_comm']:,.2f}")
    print(f"Swap Total Pago:    US$ {res['total_swap']:,.2f}")
    print(f"=======================================================")

def run_monthly_falsification(df, initial_balance=5000.0, rr=2.0, tf_name="M15", trade_only_london_ny=False):
    print(f"\n>>> TESTE DE FALSIFICACAO EM 34 MESES DE PARTIDA (RISK OF RUIN) - {tf_name} RR 1:{rr} <<<")
    # Gerar lista de meses
    dates = df.index
    months = pd.date_range(start="2024-01-01", end="2026-10-01", freq="MS")
    
    results = []
    ruined_count = 0
    profit_count = 0
    loss_count = 0
    
    for m in months:
        m_str = m.strftime("%Y-%m")
        # Filtrar fatia do mes
        df_sub = df[df.index.strftime("%Y-%m") == m_str]
        if len(df_sub) == 0:
            continue
            
        res = simulate_engine(
            df_sub,
            initial_balance=initial_balance,
            risk_pct=1.0,
            rr=rr,
            atr_mult=1.5,
            max_spread_pts=70.0,
            trade_only_london_ny=trade_only_london_ny
        )
        
        t = res["trades"]
        n_t = len(t)
        net = res["net_pnl"]
        dd = res["max_dd_usd"]
        dd_p = res["max_dd_pct"]
        
        is_ruin = res["final_balance"] <= 50.0
        if is_ruin:
            ruined_count += 1
            status = "STOP-OUT / QUEBRA"
        elif net > 0:
            profit_count += 1
            status = "LUCRO"
        else:
            loss_count += 1
            status = "PREJUIZO"
            
        results.append({
            "mes": m_str,
            "status": status,
            "trades": n_t,
            "net": net,
            "dd": dd,
            "dd_p": dd_p
        })
        print(f"  [{m_str}] Trades: {n_t:3d} | Net: ${net:+7.2f} | MaxDD: ${dd:6.2f} ({dd_p:4.1f}%) | {status}")
        
    total_months = len(results)
    ruin_pct = (ruined_count / total_months) * 100.0 if total_months > 0 else 0.0
    profit_pct = (profit_count / total_months) * 100.0 if total_months > 0 else 0.0
    
    print(f"\n--- PAINEL DE RISCO DE RUINA ({tf_name}) ---")
    print(f"Total de Meses Testados: {total_months}")
    print(f"Meses Lucrativos:        {profit_count} ({profit_pct:.1f}%)")
    print(f"Meses Negativos:         {loss_count} ({(loss_count/total_months)*100:.1f}%)")
    print(f"Taxa de Falencia/Ruin:   {ruined_count} ({ruin_pct:.1f}%)")
    return results

if __name__ == "__main__":
    print("================================================================================")
    print(" AUDITORIA QUANTITATIVA FORENSE - AUTO SCALPER XAUUSD (XM GLOBAL TICKS REAIS)")
    print("================================================================================")
    
    # 1. Carregar M15
    df_m15 = load_and_prepare("M15")
    
    # 2. Teste M15 - Historico Completo (34 Meses: Dez/2023 a Out/2026)
    print("\n--- 1. TESTE HISTORICO COMPLETO 34 MESES (M15 - RR 1:2.0 - 24H) ---")
    res_m15_24h = simulate_engine(df_m15, initial_balance=5000.0, rr=2.0, trade_only_london_ny=False)
    print_summary(res_m15_24h, "M15 - 34 MESES - RR 1:2.0 - 24H")
    
    # 3. Teste M15 - Horario Londres/NY (07h as 20h)
    print("\n--- 2. TESTE HISTORICO COMPLETO 34 MESES (M15 - RR 1:2.0 - LONDRES/NY 07h-20h) ---")
    res_m15_lny = simulate_engine(df_m15, initial_balance=5000.0, rr=2.0, trade_only_london_ny=True)
    print_summary(res_m15_lny, "M15 - 34 MESES - RR 1:2.0 - LONDRES/NY")
    
    # 4. Teste M15 - RR 1:1.5
    print("\n--- 3. TESTE HISTORICO COMPLETO 34 MESES (M15 - RR 1:1.5 - LONDRES/NY) ---")
    res_m15_rr15 = simulate_engine(df_m15, initial_balance=5000.0, rr=1.5, trade_only_london_ny=True)
    print_summary(res_m15_rr15, "M15 - 34 MESES - RR 1:1.5 - LONDRES/NY")
    
    # 5. Teste M15 - Com Parcial de 50% aos 150 pts + Mover SL para BE
    print("\n--- 4. TESTE HISTORICO COMPLETO 34 MESES (M15 - PARCIAL 50% + BE) ---")
    res_m15_parcial = simulate_engine(
        df_m15,
        initial_balance=5000.0,
        rr=2.0,
        use_partial=True,
        partial_pts=150,
        partial_pct=50.0,
        partial_move_be=True,
        trade_only_london_ny=True
    )
    print_summary(res_m15_parcial, "M15 - 34 MESES - COM PARCIAL 50% & BE")
    
    # 6. Carregar M5 e Testar M5
    df_m5 = load_and_prepare("M5")
    print("\n--- 5. TESTE HISTORICO COMPLETO 34 MESES (M5 - RR 1:2.0 - LONDRES/NY) ---")
    res_m5 = simulate_engine(df_m5, initial_balance=5000.0, rr=2.0, trade_only_london_ny=True)
    print_summary(res_m5, "M5 - 34 MESES - RR 1:2.0 - LONDRES/NY")
    
    # 7. Teste de Falsificacao Mensal (34 Meses de Partida) no melhor setup (M15 Londres/NY)
    run_monthly_falsification(df_m15, initial_balance=5000.0, rr=2.0, tf_name="M15", trade_only_london_ny=True)
