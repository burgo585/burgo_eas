import pandas as pd
import numpy as np

def sim():
    df = pd.read_csv('BTCXAU_M15_202610020100_202610021845.csv', sep='\t')
    df.columns = [c.replace('<', '').replace('>', '').lower() for c in df.columns]

    entry_1600 = 20.57575 # Abertura da vela das 16:00
    entry_1615 = 20.65720 # Abertura da vela das 16:15 (após confirmação da barra das 16:00)
    atr = 0.06668
    sl_dist = atr * 1.5   # 0.10002
    tp_dist = sl_dist * 2.0 # 0.20004

    print("==================================================================")
    print("ANÁLISE DE ENTRADA ÀS 16:00 (ABERTURA DA BARRA)")
    print("==================================================================")
    print(f"Preço de Entrada: {entry_1600:.5f}")
    print(f"Stop Loss (1.5x ATR): {entry_1600 - sl_dist:.5f} (-{sl_dist:.5f})")
    print(f"Take Profit Fixo (2:1): {entry_1600 + tp_dist:.5f} (+{tp_dist:.5f})")
    
    subset = df[df['time'] >= '16:00:00'].copy()
    
    tp_hit = False
    sl_hit = False
    
    for idx, r in subset.iterrows():
        t = r['time']
        h = r['high']
        l = r['low']
        c = r['close']
        
        # Checa TP/SL
        lucro_max = h - entry_1600
        lucro_min = l - entry_1600
        
        status = ""
        if h >= (entry_1600 + tp_dist) and not tp_hit:
            status = "🎯 [TAKE PROFIT ATINGIDO!]"
            tp_hit = True
        if l <= (entry_1600 - sl_dist) and not sl_hit:
            status = "🛑 [STOP LOSS ATINGIDO!]"
            sl_hit = True
            
        print(f"{t} | H:{h:.5f} L:{l:.5f} C:{c:.5f} | Oscilação: {lucro_min:+.5f} até {lucro_max:+.5f} {status}")

    max_high = subset['high'].max()
    print(f"\nMáxima absoluta atingida: {max_high:.5f} (Lucro Máximo Teórico: +{max_high - entry_1600:.5f} pts)")

if __name__ == '__main__':
    sim()
