import MetaTrader5 as mt5
import pandas as pd
import numpy as np
import datetime
from simulate_user_image_config import run_exact_ea_sim, df

print("=== VERIFICANDO DADOS M1 NO MT5 ===")
if mt5.initialize(r"C:\MetaTrader\terminal64.exe"):
    rates_m1 = mt5.copy_rates_from_pos("XAUUSD-ECN", mt5.TIMEFRAME_M1, 0, 100000)
    if rates_m1 is not None and len(rates_m1) > 0:
        print(f"Obtidas {len(rates_m1)} barras de M1 do MT5!")
        df_m1 = pd.DataFrame(rates_m1)
        df_m1['time'] = pd.to_datetime(df_m1['time'], unit='s')
        print(f"Período M1: {df_m1['time'].iloc[0]} até {df_m1['time'].iloc[-1]}")
    else:
        print("M1 não retornou dados suficientes, usaremos o histórico completo de 2.6 anos de M15.")
    mt5.shutdown()

print("\n=== SIMULANDO: AMBAS AS DIREÇÕES COM FILTRO EMA 200 ===")
print("Parâmetros:")
print("  Modo: Ambas Direções com Filtro EMA 200 (EMA_BOTH)")
print("  Período EMA: 200")
print("  Lote Inicial: 0.01")
print("  Alvo Giro: $3.00 | Alvo Global: $15.00")
print("  Distância Base: 300 pontos ($3.00)")
print("  Multiplicador: 1.2 | Limite Aumento: 3 | Max Ordens: 4")
print("  Usar ATR: True (Período 14, Mult 1.5)")
print("  Trailing Stop: True (Start $5.0, Drop 10.0%)")
print("  Horário: 24h (00:00 - 23:59)\n")

# 1. Simulação Exata da Imagem ($100)
res_ema_100 = run_exact_ea_sim(df, balance_init=100.0,
                               initial_lot=0.01,
                               target_side=3.0,
                               target_global=15.0,
                               base_dist_pts=300,
                               lot_mult=1.2,
                               max_martingale=3,
                               max_orders=4,
                               use_atr=True,
                               atr_mult=1.5,
                               use_trailing=True,
                               trailing_start=5.0,
                               trailing_drop_pct=10.0,
                               trade_direction="EMA_BOTH")

print("[1. RESULTADO COM BANCA DE $100 (Configuração Exata da Imagem)]:")
for k, v in res_ema_100.items():
    print(f"  {k}: {v}")

# 2. Simulação Exata da Imagem ($2.000)
res_ema_2000 = run_exact_ea_sim(df, balance_init=2000.0,
                                initial_lot=0.01,
                                target_side=3.0,
                                target_global=15.0,
                                base_dist_pts=300,
                                lot_mult=1.2,
                                max_martingale=3,
                                max_orders=4,
                                use_atr=True,
                                atr_mult=1.5,
                                use_trailing=True,
                                trailing_start=5.0,
                                trailing_drop_pct=10.0,
                                trade_direction="EMA_BOTH")

print("\n[2. RESULTADO COM BANCA DE $2.000 (Lote 0.01)]:")
for k, v in res_ema_2000.items():
    print(f"  {k}: {v}")

# 3. Com TP Fixo de $3.00 (Sem Trailing Stop) para $100
res_ema_100_notrail = run_exact_ea_sim(df, balance_init=100.0,
                                       initial_lot=0.01,
                                       target_side=3.0,
                                       target_global=15.0,
                                       base_dist_pts=300,
                                       lot_mult=1.2,
                                       max_martingale=3,
                                       max_orders=4,
                                       use_atr=True,
                                       atr_mult=1.5,
                                       use_trailing=False,
                                       trade_direction="EMA_BOTH")

print("\n[3. RESULTADO COM BANCA DE $100 (TP Fixo de $3.00 / Sem Trailing)]:")
for k, v in res_ema_100_notrail.items():
    print(f"  {k}: {v}")

# 4. Com TP Fixo de $3.00 (Sem Trailing Stop) para $2.000
res_ema_2000_notrail = run_exact_ea_sim(df, balance_init=2000.0,
                                        initial_lot=0.01,
                                        target_side=3.0,
                                        target_global=15.0,
                                        base_dist_pts=300,
                                        lot_mult=1.2,
                                        max_martingale=3,
                                        max_orders=4,
                                        use_atr=True,
                                       atr_mult=1.5,
                                       use_trailing=False,
                                       trade_direction="EMA_BOTH")

print("\n[4. RESULTADO COM BANCA DE $2.000 (TP Fixo de $3.00 / Sem Trailing)]:")
for k, v in res_ema_2000_notrail.items():
    print(f"  {k}: {v}")
