import yfinance as yf
import pandas as pd
import numpy as np
import json
from run_refined_tests import calculate_metrics, simulate_strategy, evaluate_summary

def test_nas100_optimizations():
    print("\n==================== OTIMIZANDO NAS100 (NQ=F) ====================")
    
    # 1. Testar M15 (60 dias)
    df_m15 = yf.download('NQ=F', period='60d', interval='15m', progress=False)
    if isinstance(df_m15.columns, pd.MultiIndex):
        df_m15.columns = [col[0] for col in df_m15.columns]
    df_m15 = df_m15.dropna()
    df_m15 = calculate_metrics(df_m15)
    
    # 2. Testar M5 apenas na Sessão de Nova York (13:30 às 20:00 UTC)
    df_m5 = yf.download('NQ=F', period='60d', interval='5m', progress=False)
    if isinstance(df_m5.columns, pd.MultiIndex):
        df_m5.columns = [col[0] for col in df_m5.columns]
    df_m5 = df_m5.dropna()
    df_m5 = calculate_metrics(df_m5)
    
    # Filtro de sessao NY
    df_m5_ny = df_m5.between_time('13:30', '20:00').copy()
    
    tests = [
        ("NAS100_M15_Rev_Confirmada_1.4R", df_m15, 'REVERSAL_CONFIRMED', 1.4, True, 'FULL'),
        ("NAS100_M15_BOS_Pullback_1.6R", df_m15, 'BOS_PULLBACK', 1.6, True, 'FULL'),
        ("NAS100_M15_Hibrido_Parcial_70_30", df_m15, 'HYBRID_TOTAL', 1.4, True, 'PARTIAL_TRAILING'),
        ("NAS100_M5_Sessao_NY_Rev_1.4R", df_m5_ny, 'REVERSAL_CONFIRMED', 1.4, True, 'FULL'),
        ("NAS100_M5_Sessao_NY_Hibrido_Parcial", df_m5_ny, 'HYBRID_TOTAL', 1.4, True, 'PARTIAL_TRAILING'),
    ]
    
    results = []
    for label, d, m, rr, tf, em in tests:
        t = simulate_strategy(d, mode=m, rr_target=rr, use_trend_filter=tf, exit_mode=em)
        s = evaluate_summary(t, label)
        results.append(s)
        print(f"{label:<36} | Trades: {s['Trades']:<3} | WinRate: {s['WinRate (%)']:>5}% | PF: {s['Profit Factor']:>5} | Pts: {s['Pontos Total']:>8} | MaxDD: {s['Max DD']:>6} | Sharpe: {s['Sharpe']:>5}")

if __name__ == '__main__':
    test_nas100_optimizations()
