# -*- coding: utf-8 -*-
"""
Auditoria Forense de Microestrutura - XAUUSD (XM Global Ticks)
Avalia a viabilidade da Boleta Scalping em diferentes tempos gráficos (M1, M5, M15, M30, H1).
"""
import sys
import os
import pandas as pd
import numpy as np

sys.path.append(r'C:\Users\Vini_Burgo\.gemini\config\skills\quant-forensic-auditor\scripts')
from xm_ticks_reader import load_xm_ticks

def run_forensic_audit():
    print("Iniciando carregamento de 350.000 ticks de XAUUSD (XM Global)...")
    df_ticks = load_xm_ticks(symbol="GOLD", max_ticks=350000)
    df_ticks.columns = [c.strip().replace('<', '').replace('>', '') for c in df_ticks.columns]
    df_ticks['DATETIME'] = pd.to_datetime(df_ticks['DATE'] + ' ' + df_ticks['TIME'])
    df_ticks.set_index('DATETIME', inplace=True)
    
    df_ticks['SPREAD_USD'] = (df_ticks['ASK'] - df_ticks['BID']).round(2)
    spread_mean = df_ticks['SPREAD_USD'].mean()
    spread_p95 = df_ticks['SPREAD_USD'].quantile(0.95)
    
    print(f"Spread Médio XM: ${spread_mean:.2f} ({spread_mean*100:.1f} pts) | P95: ${spread_p95:.2f} ({spread_p95*100:.1f} pts)")
    
    timeframes = [('1min', 'M1'), ('5min', 'M5'), ('15min', 'M15'), ('30min', 'M30'), ('60min', 'H1')]
    results = []
    
    for tf_str, tf_name in timeframes:
        bars = df_ticks['BID'].resample(tf_str).ohlc().dropna()
        tr = np.maximum(
            bars['high'] - bars['low'],
            np.maximum(
                (bars['high'] - bars['close'].shift(1)).abs(),
                (bars['low'] - bars['close'].shift(1)).abs()
            )
        )
        atr = tr.rolling(14).mean().shift(1).dropna()
        atr_pts = atr.mean() * 100.0
        sl_pts = atr_pts * 1.5
        spread_friction = (spread_mean * 100.0 / sl_pts) * 100.0
        
        results.append({
            'Tempo Gráfico': tf_name,
            'Barras': len(bars),
            'ATR 14 Médio ($)': round(atr.mean(), 2),
            'ATR 14 (pts)': round(atr_pts, 1),
            'Stop Loss (1.5x ATR pts)': round(sl_pts, 1),
            'Fricção Spread/SL (%)': round(spread_friction, 1)
        })
        
    df_res = pd.DataFrame(results)
    return df_res

if __name__ == '__main__':
    res = run_forensic_audit()
    print("\n" + res.to_string(index=False))
