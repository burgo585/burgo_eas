import datetime
import pandas as pd
import numpy as np
from run_xauusd_tests import get_xauusd_data
from run_sessions_test import TimedBacktestEngine

df = get_xauusd_data()

# Carrega exatamente os parâmetros do arquivo do usuário:
# C:\Users\Vini_Burgo\AppData\Roaming\MetaQuotes\Terminal\5A1174AE1007A2760EEEF72EC2A459D5\MQL5\Profiles\Tester\Burgo Scalpe Pro.set
user_set_params = {
    'InitialLot': 0.02,
    'TargetSideUSD': 3.0,
    'TargetGlobalUSD': 6.0,
    'BaseDistance': 150,
    'LotMultiplier': 1.2,
    'MaxMartingale': 4,
    'MaxTotalOrders': 8,
    'UseATR': True,
    'ATRMultiplier': 1.5,
    'UseTrailingStop': True,
    'TrailingStartUSD': 5.0,
    'TrailingDropPct': 15.0,
    'StartTime': '01:00',
    'EndTime': '04:00'
}

engine_2000 = TimedBacktestEngine(df, initial_balance=2000.0)
engine_100 = TimedBacktestEngine(df, initial_balance=100.0)

print("=== TESTANDO EXATAMENTE O SEU ARQUIVO 'Burgo Scalpe Pro.set' ENCONTRADO NA PASTA ===")
print("Parâmetros do arquivo:")
for k, v in user_set_params.items():
    print(f"  {k} = {v}")

res_2000 = engine_2000.run(user_set_params)
print("\n[Resultado com Banca de $2.000 (Seu Set Exato)]:")
print(res_2000)

res_100 = engine_100.run(user_set_params)
print("\n[Resultado com Banca de $100 (Seu Set Exato)]:")
print(res_100)

# E testando com MaxTotalOrders = 4 (como você perguntou) mantendo o horário 01:00 às 04:00
user_set_4ord = user_set_params.copy()
user_set_4ord['MaxTotalOrders'] = 4

print("\n=== TESTANDO SEU SET COM 'MaxTotalOrders = 4' (Horário 01:00 às 04:00) ===")
res_4ord_2000 = engine_2000.run(user_set_4ord)
print("[Resultado com Banca de $2.000 / Max 4 ordens]:", res_4ord_2000)

res_4ord_100 = engine_100.run(user_set_4ord)
print("[Resultado com Banca de $100 / Max 4 ordens]:", res_4ord_100)

# E com lote 0.01 para a banca de $100
user_set_4ord_001 = user_set_4ord.copy()
user_set_4ord_001['InitialLot'] = 0.01
res_4ord_100_001 = engine_100.run(user_set_4ord_001)
print("[Resultado com Banca de $100 / Max 4 ordens / Lote 0.01]:", res_4ord_100_001)
