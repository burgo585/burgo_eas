import asyncio
import numpy as np
import pandas as pd
from test_tv import fetch_tradingview_bars

async def grid_search_gold():
    df = await fetch_tradingview_bars("OANDA:XAUUSD", "15", 3000)
    c, o, h, l, v = df["close"].values, df["open"].values, df["high"].values, df["low"].values, df["volume"].values
    
    # Indicadores
    df["ema20"] = df["close"].ewm(span=20).mean()
    df["ema50"] = df["close"].ewm(span=50).mean()
    df["ema200"] = df["close"].ewm(span=200).mean()
    df["vol_avg"] = df["volume"].rolling(20).mean()
    
    ema20 = df["ema20"].values
    ema50 = df["ema50"].values
    ema200 = df["ema200"].values
    vol_avg = df["vol_avg"].values
    
    # Detectar Candlesticks de Alta Convicção
    body = np.abs(c - o)
    span = h - l
    span = np.where(span == 0, 0.0001, span)
    
    # 1. Engolfos
    bull_engulf = (c > o) & (c > np.roll(h, 1)) & (np.roll(c, 1) < np.roll(o, 1))
    bear_engulf = (c < o) & (c < np.roll(l, 1)) & (np.roll(c, 1) > np.roll(o, 1))
    
    # 2. Martelo (rejeição)
    lower_wick = np.minimum(o, c) - l
    hammer = (c > o) & (lower_wick >= 1.8 * body) & (c < ema50) # exaustão de fundo
    
    # 3. Enforcado
    upper_wick = h - np.maximum(o, c)
    hanging_man = (c < o) & (lower_wick >= 1.8 * body) & (c > ema50)
    
    # Testar grade de parâmetros
    results = []
    
    for rr in [1.2, 1.5, 1.8, 2.0, 2.5]:
        for sl_mult in [1.0, 1.5, 2.0]: # multiplicador de folga do stop
            for use_be in [False, True]:
                trades = []
                for i in range(50, len(df) - 30):
                    hour = df["time"].iloc[i].hour
                    if hour < 7 or hour > 18:
                        continue
                        
                    # Volume confirmation
                    if v[i] < 1.1 * vol_avg[i]:
                        continue
                        
                    buy_sig = (bull_engulf[i] and c[i] > ema50[i]) or (hammer[i] and c[i] > ema200[i])
                    sell_sig = (bear_engulf[i] and c[i] < ema50[i])
                    
                    if not buy_sig and not sell_sig:
                        continue
                        
                    dir_trade = "BUY" if buy_sig else "SELL"
                    entry = o[i+1]
                    
                    if dir_trade == "BUY":
                        base_sl = l[i]
                        risk = (entry - base_sl) * sl_mult
                        if risk < 1.0 or risk > 12.0:
                            continue
                        sl = entry - risk
                        tp = entry + (risk * rr)
                    else:
                        base_sl = h[i]
                        risk = (base_sl - entry) * sl_mult
                        if risk < 1.0 or risk > 12.0:
                            continue
                        sl = entry + risk
                        tp = entry - (risk * rr)
                        
                    curr_sl = sl
                    outcome = None
                    exit_r = 0.0
                    
                    for k in range(i+1, min(i+100, len(df))):
                        bh, bl = h[k], l[k]
                        if dir_trade == "BUY":
                            if use_be and bh >= entry + (risk * 1.2):
                                curr_sl = max(curr_sl, entry + 0.10)
                            if bl <= curr_sl:
                                exit_r = 0.05 if curr_sl > entry else -1.0
                                break
                            elif bh >= tp:
                                exit_r = rr
                                break
                        else:
                            if use_be and bl <= entry - (risk * 1.2):
                                curr_sl = min(curr_sl, entry - 0.10)
                            if bh >= curr_sl:
                                exit_r = 0.05 if curr_sl < entry else -1.0
                                break
                            elif bl <= tp:
                                exit_r = rr
                                break
                                
                    trades.append(exit_r)
                    
                if len(trades) >= 20:
                    trades = np.array(trades)
                    wins = trades[trades > 0]
                    losses = trades[trades <= 0]
                    wr = len(wins) / len(trades) * 100.0
                    gp = wins.sum()
                    gl = abs(losses.sum())
                    pf = (gp / gl) if gl > 0 else 99.0
                    
                    # Simulação de Lucro Líquido
                    bal = 10000.0
                    peak = bal
                    max_dd = 0.0
                    for r in trades:
                        bal += bal * 0.02 * r # 2% risco por trade
                        if bal > peak: peak = bal
                        dd = (peak - bal) / peak * 100.0
                        if dd > max_dd: max_dd = dd
                    net = (bal - 10000.0) / 10000.0 * 100.0
                    
                    results.append({
                        "rr": rr, "sl_mult": sl_mult, "use_be": use_be,
                        "trades": len(trades), "wr": round(wr, 1),
                        "pf": round(pf, 2), "net_pct": round(net, 1),
                        "max_dd": round(max_dd, 1)
                    })
                    
    rdf = pd.DataFrame(results).sort_values("net_pct", ascending=False)
    print("=== TOP 10 CONFIGURAÇÕES MAIS LUCRATIVAS EM XAUUSD ===")
    print(rdf.head(10).to_string(index=False))

if __name__ == "__main__":
    asyncio.run(grid_search_gold())
