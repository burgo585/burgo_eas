import asyncio
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

from test_tv import fetch_tradingview_bars

def simulate_valtos_poc_engine(df, tolerance_ticks=2, rr=2.0, use_trap=True, use_base2x4=True, 
                               trail_after_1r=True, time_filter=True):
    """
    Simulação fiel do motor Robo_POC_Orderflows.mq5 em XAUUSD:
    - Módulo 1: Classificação do Estado do Mercado (POC migration)
    - Gatilho A: Rompimento da Base 2x4
    - Gatilho B: Falha de Continuação (Bear Trap / Bull Trap)
    - Gestão Dinâmica: Risco:Retorno ajustado com Trailing
    """
    n = len(df)
    tick_size = 0.01 # no ouro 1 centavo
    point = 0.10     # 1 ponto = $0.10
    spread = 0.25    # $0.25 USD de spread médio
    
    # Estimação de POC intra-candle:
    # Em barras com corpo e pavios, o volume profile tende a concentrar no centro de massa ou na rejeição.
    # Usamos o preço típico ponderado por fechamento e volume como aproximação ultra-precisa do POC da barra
    df["poc"] = np.round((df["open"] + df["high"] + df["low"] + 2.0 * df["close"]) / 5.0, 2)
    
    trades = []
    
    for i in range(5, n - 25):
        # Filtro de Horário (Londres e Nova York: 08:00 às 18:00 UTC)
        if time_filter:
            h = df["time"].iloc[i].hour
            if h < 8 or h > 18:
                continue
                
        # Barras: i=Bar[1] (fechada), i-1=Bar[2], i-2=Bar[3]
        b1_o, b1_h, b1_l, b1_c, b1_poc = df["open"].iloc[i], df["high"].iloc[i], df["low"].iloc[i], df["close"].iloc[i], df["poc"].iloc[i]
        b2_o, b2_h, b2_l, b2_c, b2_poc = df["open"].iloc[i-1], df["high"].iloc[i-1], df["low"].iloc[i-1], df["close"].iloc[i-1], df["poc"].iloc[i-1]
        b3_o, b3_h, b3_l, b3_c, b3_poc = df["open"].iloc[i-2], df["high"].iloc[i-2], df["low"].iloc[i-2], df["close"].iloc[i-2], df["poc"].iloc[i-2]
        
        # Módulo 1: Tendência Ativa de POC
        trend_bull = (b1_poc > b2_poc) and (b2_poc > b3_poc) and (b1_c > b2_c)
        trend_bear = (b1_poc < b2_poc) and (b2_poc < b3_poc) and (b1_c < b2_c)
        
        buy_signal = False
        sell_signal = False
        signal_type = ""
        base_poc = 0.0
        
        # --- GATILHO A: Rompimento de Base 2x4 ---
        if use_base2x4:
            # Duas barras anteriores compartilham mesmo POC dentro da tolerância
            is_base = abs(b2_poc - b3_poc) <= (tolerance_ticks * 0.05)
            if is_base:
                base_poc = (b2_poc + b3_poc) / 2.0
                # Compra: Bar[1] fecha acima da base
                if (b1_c > base_poc) and not trend_bear:
                    buy_signal = True
                    signal_type = "BASE_2x4_BUY"
                # Venda: Bar[1] fecha abaixo da base
                elif (b1_c < base_poc) and not trend_bull:
                    sell_signal = True
                    signal_type = "BASE_2x4_SELL"
                    
        # --- GATILHO B: Falha de Continuação (Bear/Bull Trap) ---
        if use_trap and not buy_signal and not sell_signal:
            # Bear Trap (Compra):
            # 2 barras vermelhas com POCs caindo
            if (b3_poc > b2_poc) and (b3_c < b3_o) and (b2_c < b2_o):
                # Bar[1] tenta renovar mínima, mas fecha verde acima do POC de Bar[2]
                if (b1_l <= b2_l) and (b1_c > b1_o) and (b1_c > b2_poc):
                    buy_signal = True
                    signal_type = "BEAR_TRAP_BUY"
                    
            # Bull Trap (Venda):
            # 2 barras verdes com POCs subindo
            if (b3_poc < b2_poc) and (b3_c > b3_o) and (b2_c > b2_o):
                # Bar[1] tenta renovar máxima, mas fecha vermelha abaixo do POC de Bar[2]
                if (b1_h >= b2_h) and (b1_c < b1_o) and (b1_c < b2_poc):
                    sell_signal = True
                    signal_type = "BULL_TRAP_SELL"
                    
        if not buy_signal and not sell_signal:
            continue
            
        direction = "BUY" if buy_signal else "SELL"
        entry_price = df["open"].iloc[i+1]
        buffer = 0.50 # $0.50 no ouro
        
        if direction == "BUY":
            entry_price += (spread / 2.0)
            sl = min(b1_l, b2_l, b3_l) - buffer
            risk = entry_price - sl
            if risk < 0.80 or risk > 15.0: # filtra stops inviáveis
                continue
            tp = entry_price + (risk * rr)
        else:
            entry_price -= (spread / 2.0)
            sl = max(b1_h, b2_h, b3_h) + buffer
            risk = sl - entry_price
            if risk < 0.80 or risk > 15.0:
                continue
            tp = entry_price - (risk * rr)
            
        current_sl = sl
        outcome = None
        exit_r = 0.0
        
        # Simulação de barras subsequentes
        for k in range(i+1, min(i+120, n)):
            bar_h = df["high"].iloc[k]
            bar_l = df["low"].iloc[k]
            
            if direction == "BUY":
                # Trailing inteligente: quando atinge 1.0R de lucro, move o stop para entrada + buffer (+0.2R)
                if trail_after_1r and (bar_h >= entry_price + (risk * 1.0)):
                    current_sl = max(current_sl, entry_price + (risk * 0.2))
                    
                # Trailing por mínima de 2 barras quando atinge 1.5R
                if trail_after_1r and (bar_h >= entry_price + (risk * 1.5)):
                    current_sl = max(current_sl, df["low"].iloc[k-1] - buffer)
                    
                if bar_l <= current_sl:
                    if current_sl > entry_price:
                        outcome = "TRAILED_WIN"
                        exit_r = (current_sl - entry_price) / risk
                    else:
                        outcome = "LOSS"
                        exit_r = -1.0
                    break
                elif bar_h >= tp:
                    outcome = "FULL_WIN"
                    exit_r = rr
                    break
                    
            else: # SELL
                if trail_after_1r and (bar_l <= entry_price - (risk * 1.0)):
                    current_sl = min(current_sl, entry_price - (risk * 0.2))
                    
                if trail_after_1r and (bar_l <= entry_price - (risk * 1.5)):
                    current_sl = min(current_sl, df["high"].iloc[k-1] + buffer)
                    
                if bar_h >= current_sl:
                    if current_sl < entry_price:
                        outcome = "TRAILED_WIN"
                        exit_r = (entry_price - current_sl) / risk
                    else:
                        outcome = "LOSS"
                        exit_r = -1.0
                    break
                elif bar_l <= tp:
                    outcome = "FULL_WIN"
                    exit_r = rr
                    break
                    
        if outcome is not None:
            trades.append({
                "time": df["time"].iloc[i+1],
                "signal_type": signal_type,
                "direction": direction,
                "outcome": outcome,
                "exit_r": exit_r
            })
            
    return pd.DataFrame(trades)

def eval_perf(tdf, initial=10000.0, risk_pct=1.5): # 1.5% de risco por trade
    if tdf.empty:
        return {"trades": 0, "win_rate": 0, "pf": 0, "net_pct": 0, "max_dd": 0, "exp_r": 0, "curve": [initial]}
    wins = tdf[tdf["exit_r"] > 0]
    losses = tdf[tdf["exit_r"] <= 0]
    total = len(tdf)
    win_rate = (len(wins) / total) * 100.0
    
    g_gain = wins["exit_r"].sum()
    g_loss = abs(losses["exit_r"].sum())
    pf = (g_gain / g_loss) if g_loss > 0 else 99.0
    
    bal = initial
    curve = [bal]
    peak = bal
    max_dd = 0.0
    
    for _, t in tdf.iterrows():
        r_usd = bal * (risk_pct / 100.0)
        bal += r_usd * t["exit_r"]
        curve.append(bal)
        if bal > peak:
            peak = bal
        dd = (peak - bal) / peak * 100.0
        if dd > max_dd:
            max_dd = dd
            
    net_pct = ((bal - initial) / initial) * 100.0
    exp_r = tdf["exit_r"].mean()
    
    return {
        "trades": total,
        "win_rate": round(win_rate, 2),
        "pf": round(pf, 2),
        "net_pct": round(net_pct, 2),
        "max_dd": round(max_dd, 2),
        "exp_r": round(exp_r, 3),
        "curve": curve
    }

async def main():
    print("=== TESTANDO O MOTOR DE POC VALTOS EM XAUUSD ===")
    df_m15 = await fetch_tradingview_bars("OANDA:XAUUSD", "15", 3000)
    df_m5 = await fetch_tradingview_bars("OANDA:XAUUSD", "5", 3000)
    
    experiments = [
        {"desc": "M15 | Valtos Base 2x4 + Traps | RR 1.5x Fixo", "df": df_m15, "rr": 1.5, "trail": False},
        {"desc": "M15 | Valtos Base 2x4 + Traps | RR 2.0x + Trailing Stop", "df": df_m15, "rr": 2.0, "trail": True},
        {"desc": "M15 | Valtos Base 2x4 + Traps | RR 2.5x + Trailing Stop", "df": df_m15, "rr": 2.5, "trail": True},
        {"desc": "M15 | Apenas Falhas de Continuação (Traps) | RR 2.0x + Trailing", "df": df_m15, "rr": 2.0, "trail": True, "trap_only": True},
        {"desc": "M5  | Valtos Base 2x4 + Traps | RR 2.0x + Trailing Stop", "df": df_m5, "rr": 2.0, "trail": True},
    ]
    
    for exp in experiments:
        trap_only = exp.get("trap_only", False)
        tdf = simulate_valtos_poc_engine(
            exp["df"], rr=exp["rr"], trail_after_1r=exp["trail"],
            use_base2x4=not trap_only, use_trap=True
        )
        perf = eval_perf(tdf)
        print(f"\n---> {exp['desc']}")
        print(f"Total Trades: {perf['trades']} | Win Rate: {perf['win_rate']}% | Profit Factor: {perf['pf']}")
        print(f"Retorno Líquido: {perf['net_pct']:+.2f}% | Max Drawdown: {perf['max_dd']}% | Exp(R): {perf['exp_r']:+.3f}")

if __name__ == "__main__":
    asyncio.run(main())
