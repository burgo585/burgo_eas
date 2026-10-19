import asyncio
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

from test_tv import fetch_tradingview_bars

def backtest_gold_pullback_momentum(df, timeframe="15"):
    """
    Estratégia Institucional de Alto Lucro para XAUUSD:
    - Tendência Clara: EMA 20 > EMA 50 (Alta) ou EMA 20 < EMA 50 (Baixa)
    - Distância saudável da EMA 200 (evita topos históricos esticados)
    - Pullback: Preço toca ou aproxima-se da EMA 20 / EMA 50
    - Gatilho: Candle de Rejeição / Retomada (Martelo, Engolfo, Barra de Força)
    - Filtro de Horário Nobre: 07:00 às 18:00 UTC (Sessão de Londres e NY)
    - Gestão: Risco fixo de 2% por trade com Relação Risco:Retorno de 2.0 a 3.0
    """
    n = len(df)
    c = df["close"].values
    o = df["open"].values
    h = df["high"].values
    l = df["low"].values
    v = df["volume"].values
    
    # Indicadores
    df["ema20"] = df["close"].ewm(span=20).mean()
    df["ema50"] = df["close"].ewm(span=50).mean()
    df["ema200"] = df["close"].ewm(span=200).mean()
    
    # ATR (14)
    tr = np.maximum(h[1:] - l[1:], np.maximum(np.abs(h[1:] - c[:-1]), np.abs(l[1:] - c[:-1])))
    tr = np.insert(tr, 0, h[0] - l[0])
    df["atr"] = pd.Series(tr).rolling(14).mean().bfill()
    
    ema20 = df["ema20"].values
    ema50 = df["ema50"].values
    ema200 = df["ema200"].values
    atr = df["atr"].values
    
    trades = []
    spread = 0.25 # USD
    
    for i in range(50, n - 20):
        t = df["time"].iloc[i]
        hour = t.hour
        # Apenas sessões líquidas (Londres + NY)
        if hour < 7 or hour > 17:
            continue
            
        cur_atr = atr[i]
        if cur_atr < 1.0: # Volatilidade mínima necessária
            continue
            
        buy_setup = False
        sell_setup = False
        
        # 1. SETUP DE COMPRA:
        # Tendência estabelecida
        if (ema20[i] > ema50[i]) and (c[i] > ema200[i]):
            # Recuo (Pullback): a mínima do candle tocou a região da EMA20 ou EMA50
            pullback_zone = (l[i] <= ema20[i] * 1.002)
            # Rejeição de compra: fechou no terço superior do candle OU engolfo
            closed_strong = (c[i] > o[i]) and (c[i] >= h[i] - 0.3 * (h[i] - l[i]))
            engulfing = (c[i] > o[i]) and (c[i-1] < o[i-1]) and (c[i] > h[i-1])
            
            if pullback_zone and (closed_strong or engulfing):
                buy_setup = True
                
        # 2. SETUP DE VENDA:
        if (ema20[i] < ema50[i]) and (c[i] < ema200[i]):
            pullback_zone = (h[i] >= ema20[i] * 0.998)
            closed_weak = (c[i] < o[i]) and (c[i] <= l[i] + 0.3 * (h[i] - l[i]))
            engulfing = (c[i] < o[i]) and (c[i-1] > o[i-1]) and (c[i] < l[i-1])
            
            if pullback_zone and (closed_weak or engulfing):
                sell_setup = True
                
        if not buy_setup and not sell_setup:
            continue
            
        direction = "BUY" if buy_setup else "SELL"
        entry_price = o[i+1]
        
        if direction == "BUY":
            entry_price += (spread / 2.0)
            sl = min(l[i], l[i-1]) - (0.3 * cur_atr)
            risk = entry_price - sl
            if risk < 1.0 or risk > 15.0:
                continue
            # Risco:Retorno de 2.0x
            tp = entry_price + (risk * 2.2)
        else:
            entry_price -= (spread / 2.0)
            sl = max(h[i], h[i-1]) + (0.3 * cur_atr)
            risk = sl - entry_price
            if risk < 1.0 or risk > 15.0:
                continue
            tp = entry_price - (risk * 2.2)
            
        # Avaliar saída
        outcome = None
        exit_r = 0.0
        current_sl = sl
        
        for k in range(i+1, min(i+80, n)):
            bar_h = h[k]
            bar_l = l[k]
            
            if direction == "BUY":
                # Break-Even inteligente quando atinge 1.0R
                if bar_h >= entry_price + risk:
                    current_sl = max(current_sl, entry_price + 0.15)
                    
                if bar_l <= current_sl:
                    if current_sl > entry_price:
                        outcome = "BE_WIN"
                        exit_r = 0.1
                    else:
                        outcome = "LOSS"
                        exit_r = -1.0
                    break
                elif bar_h >= tp:
                    outcome = "WIN"
                    exit_r = 2.2
                    break
            else:
                if bar_l <= entry_price - risk:
                    current_sl = min(current_sl, entry_price - 0.15)
                    
                if bar_h >= current_sl:
                    if current_sl < entry_price:
                        outcome = "BE_WIN"
                        exit_r = 0.1
                    else:
                        outcome = "LOSS"
                        exit_r = -1.0
                    break
                elif bar_l <= tp:
                    outcome = "WIN"
                    exit_r = 2.2
                    break
                    
        if outcome is not None:
            trades.append({
                "time": t,
                "direction": direction,
                "outcome": outcome,
                "exit_r": exit_r
            })
            
    tdf = pd.DataFrame(trades)
    return tdf

def calc_stats(tdf, initial=10000.0, risk_pct=2.0):
    if tdf.empty:
        return {"trades": 0, "win_rate": 0, "pf": 0, "net_pct": 0, "max_dd": 0, "curve": [initial]}
    wins = tdf[tdf["exit_r"] > 0]
    losses = tdf[tdf["exit_r"] < 0]
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
    return {
        "trades": total,
        "win_rate": round(win_rate, 2),
        "pf": round(pf, 2),
        "net_pct": round(net_pct, 2),
        "max_dd": round(max_dd, 2),
        "curve": curve,
        "final_bal": round(bal, 2)
    }

async def main():
    print("=== TESTANDO ESTRATÉGIA DE PULLBACK INSTITUCIONAL (OURO ALTA RENTABILIDADE) ===")
    df_m15 = await fetch_tradingview_bars("OANDA:XAUUSD", "15", 3000)
    df_m30 = await fetch_tradingview_bars("OANDA:XAUUSD", "30", 3000)
    df_h1 = await fetch_tradingview_bars("OANDA:XAUUSD", "60", 3000)
    
    for name, df in [("M15 (15 Minutos)", df_m15), ("M30 (30 Minutos)", df_m30), ("H1 (1 Hora)", df_h1)]:
        tdf = backtest_gold_pullback_momentum(df)
        stats = calc_stats(tdf)
        print(f"\n--- TIMEFRAME: {name} ---")
        print(f"Total de Trades: {stats['trades']} | Taxa de Acerto: {stats['win_rate']}%")
        print(f"Fator de Lucro (Profit Factor): {stats['pf']}")
        print(f"Retorno Líquido: {stats['net_pct']:+.2f}% ($10.000 -> ${stats['final_bal']})")
        print(f"Rebaixamento Máximo (Drawdown): {stats['max_dd']}%")

if __name__ == "__main__":
    asyncio.run(main())
