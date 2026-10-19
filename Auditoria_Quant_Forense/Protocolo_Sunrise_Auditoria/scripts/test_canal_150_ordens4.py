import datetime
import pandas as pd
import numpy as np
from run_xauusd_tests import get_xauusd_data
from test_canal_200 import run_simulation_custom

df = get_xauusd_data()
df['ema200'] = df['close'].ewm(span=200, adjust=False).mean()

print("=== TESTES COM CANAL DE 150 PONTOS E MÁXIMO 4 ORDENS (XAUUSD - 2.6 ANOS) ===\n")

# 1. Modo Original (Sem filtro) com Banca de $100
# Lote 0.02, Mult 1.5, Max 4 ordens, Dist 150 ($1.50)
t1 = run_simulation_custom(df, balance_init=100.0, base_dist=150, initial_lot=0.02, lot_mult=1.5, max_martingale=4, max_orders=4, target_side=2.0, target_global=20.0, use_atr=False, mode='ORIGINAL')
print("1. Modo Original com $100 (Dist 150, Max 4 ordens, Lote 0.02, Mult 1.5):")
print(t1)

# 2. Modo Original (Sem filtro) com Banca de $2.000
t2 = run_simulation_custom(df, balance_init=2000.0, base_dist=150, initial_lot=0.02, lot_mult=1.5, max_martingale=4, max_orders=4, target_side=2.0, target_global=20.0, use_atr=False, mode='ORIGINAL')
print("\n2. Modo Original com $2.000 (Dist 150, Max 4 ordens, Lote 0.02, Mult 1.5):")
print(t2)

# 3. Modo com Filtro EMA 200 (Lote 0.01, Mult 1.15, Max 4 ordens, Dist 150) com $100
t3 = run_simulation_custom(df, balance_init=100.0, base_dist=150, initial_lot=0.01, lot_mult=1.15, max_martingale=4, max_orders=4, target_side=2.0, target_global=15.0, use_atr=False, mode='EMA_BOTH')
print("\n3. Modo Filtro EMA 200 com $100 (Dist 150, Max 4 ordens, Lote 0.01, Mult 1.15):")
print(t3)

# 4. Modo Apenas Compra (Buy-Only) com $100 (Lote 0.01, Mult 1.15, Max 4 ordens, Dist 150)
t4 = run_simulation_custom(df, balance_init=100.0, base_dist=150, initial_lot=0.01, lot_mult=1.15, max_martingale=4, max_orders=4, target_side=2.0, target_global=15.0, use_atr=False, mode='BUY_ONLY')
print("\n4. Modo Apenas Compra com $100 (Dist 150, Max 4 ordens, Lote 0.01, Mult 1.15):")
print(t4)

# 5. Modo Filtro EMA 200 com $2.000 (Lote 0.02, Mult 1.2, Max 4 ordens, Dist 150)
t5 = run_simulation_custom(df, balance_init=2000.0, base_dist=150, initial_lot=0.02, lot_mult=1.2, max_martingale=4, max_orders=4, target_side=2.5, target_global=20.0, use_atr=False, mode='EMA_BOTH')
print("\n5. Modo Filtro EMA 200 com $2.000 (Dist 150, Max 4 ordens, Lote 0.02, Mult 1.2):")
print(t5)

# 6. Modo Apenas Compra com $2.000 (Lote 0.02, Mult 1.2, Max 4 ordens, Dist 150)
t6 = run_simulation_custom(df, balance_init=2000.0, base_dist=150, initial_lot=0.02, lot_mult=1.2, max_martingale=4, max_orders=4, target_side=2.5, target_global=20.0, use_atr=False, mode='BUY_ONLY')
print("\n6. Modo Apenas Compra com $2.000 (Dist 150, Max 4 ordens, Lote 0.02, Mult 1.2):")
print(t6)
