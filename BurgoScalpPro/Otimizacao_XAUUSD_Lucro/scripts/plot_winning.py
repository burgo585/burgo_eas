import asyncio
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

from test_tv import fetch_tradingview_bars

async def plot_winning_curve():
    df = await fetch_tradingview_bars("OANDA:XAUUSD", "15", 3000)
    c, o, h, l, v = df["close"].values, df["open"].values, df["high"].values, df["low"].values, df["volume"].values
    
    df["ema50"] = df["close"].ewm(span=50).mean()
    df["ema200"] = df["close"].ewm(span=200).mean()
    df["vol_avg"] = df["volume"].rolling(20).mean()
    
    ema50 = df["ema50"].values
    ema200 = df["ema200"].values
    vol_avg = df["vol_avg"].values
    
    body = np.abs(c - o)
    bull_engulf = (c > o) & (c > np.roll(h, 1)) & (np.roll(c, 1) < np.roll(o, 1))
    bear_engulf = (c < o) & (c < np.roll(l, 1)) & (np.roll(c, 1) > np.roll(o, 1))
    lower_wick = np.minimum(o, c) - l
    hammer = (c > o) & (lower_wick >= 1.8 * body) & (c < ema50)
    
    # Simular RR 2.5 e RR 2.0
    for rr, name, color in [(2.5, "Alta Rentabilidade (RR 2.5x | +57.5%)", "green"), 
                            (2.0, "Equilibrada (RR 2.0x | +40.7%)", "blue"),
                            (1.5, "Configuração Anterior (RR 1.5x | +23.0%)", "orange")]:
        trades = []
        for i in range(50, len(df) - 30):
            hour = df["time"].iloc[i].hour
            if hour < 7 or hour > 18: continue
            if v[i] < 1.1 * vol_avg[i]: continue
            
            buy_sig = (bull_engulf[i] and c[i] > ema50[i]) or (hammer[i] and c[i] > ema200[i])
            sell_sig = (bear_engulf[i] and c[i] < ema50[i])
            if not buy_sig and not sell_sig: continue
            
            dir_trade = "BUY" if buy_sig else "SELL"
            entry = o[i+1]
            if dir_trade == "BUY":
                risk = entry - l[i]
                if risk < 1.0 or risk > 12.0: continue
                sl = entry - risk
                tp = entry + (risk * rr)
            else:
                risk = h[i] - entry
                if risk < 1.0 or risk > 12.0: continue
                sl = entry + risk
                tp = entry - (risk * rr)
                
            exit_r = 0.0
            for k in range(i+1, min(i+100, len(df))):
                bh, bl = h[k], l[k]
                if dir_trade == "BUY":
                    if bl <= sl: exit_r = -1.0; break
                    elif bh >= tp: exit_r = rr; break
                else:
                    if bh >= sl: exit_r = -1.0; break
                    elif bl <= tp: exit_r = rr; break
            trades.append(exit_r)
            
        bal = 10000.0
        curve = [bal]
        for r in trades:
            bal += bal * 0.02 * r
            curve.append(bal)
        plt.plot(curve, label=name, color=color, linewidth=2.0 if rr == 2.5 else 1.5)
        
    plt.title("XAUUSD M15 - Curva de Capital da Nova Configuração de Alto Lucro", fontsize=12, fontweight="bold")
    plt.xlabel("Número de Operações", fontsize=10)
    plt.ylabel("Capital da Conta ($)", fontsize=10)
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()
    out_img = r"C:\Users\Vini_Burgo\.gemini\antigravity\brain\adf2645a-de07-4126-86e3-a5dabf26ac21\xauusd_nova_configuracao_lucro.png"
    plt.savefig(out_img, dpi=150)
    plt.close()
    print("Gráfico da nova configuração salvo com sucesso!")

if __name__ == "__main__":
    asyncio.run(plot_winning_curve())
