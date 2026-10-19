import datetime
import pandas as pd
import numpy as np
from run_xauusd_tests import get_xauusd_data, BacktestEngine

df = get_xauusd_data()
engine = BacktestEngine(df, initial_balance=2000.0)

# Bateria de testes exploratórios aprofundados
exploratory_configs = [
    # 1. Sem Martingale (Multiplicador 1.0 = Lote Fixo 0.01)
    {'name': 'Lote Fixo 0.01 / Dist 1500 / Alvo $5', 'InitialLot': 0.01, 'BaseDistance': 1500, 'LotMultiplier': 1.0, 'TargetSideUSD': 5.0, 'TargetGlobalUSD': 30.0, 'MaxTotalOrders': 6, 'ATRMultiplier': 2.0},
    {'name': 'Lote Fixo 0.01 / Dist 2000 / Alvo $8', 'InitialLot': 0.01, 'BaseDistance': 2000, 'LotMultiplier': 1.0, 'TargetSideUSD': 8.0, 'TargetGlobalUSD': 40.0, 'MaxTotalOrders': 6, 'ATRMultiplier': 2.5},
    {'name': 'Lote Fixo 0.01 / Dist 2500 / Alvo $10', 'InitialLot': 0.01, 'BaseDistance': 2500, 'LotMultiplier': 1.0, 'TargetSideUSD': 10.0, 'TargetGlobalUSD': 50.0, 'MaxTotalOrders': 5, 'ATRMultiplier': 3.0},
    
    # 2. Martingale Suave (1.1 a 1.2) com Distâncias Maiores ($15 a $30)
    {'name': 'Mult 1.15 / Dist 1500 / Alvo $5 / Max 5 Ordens', 'InitialLot': 0.01, 'BaseDistance': 1500, 'LotMultiplier': 1.15, 'TargetSideUSD': 5.0, 'TargetGlobalUSD': 30.0, 'MaxTotalOrders': 5, 'ATRMultiplier': 2.0},
    {'name': 'Mult 1.2 / Dist 2000 / Alvo $8 / Max 5 Ordens', 'InitialLot': 0.01, 'BaseDistance': 2000, 'LotMultiplier': 1.2, 'TargetSideUSD': 8.0, 'TargetGlobalUSD': 40.0, 'MaxTotalOrders': 5, 'ATRMultiplier': 2.5},
    {'name': 'Mult 1.2 / Dist 2500 / Alvo $10 / Max 4 Ordens', 'InitialLot': 0.01, 'BaseDistance': 2500, 'LotMultiplier': 1.2, 'TargetSideUSD': 10.0, 'TargetGlobalUSD': 50.0, 'MaxTotalOrders': 4, 'ATRMultiplier': 3.0},

    # 3. Grade Curta com Saída Rápida (Max 3 ou 4 ordens)
    {'name': 'Max 3 Ordens / Dist 1000 / Mult 1.3 / Alvo $3', 'InitialLot': 0.01, 'BaseDistance': 1000, 'LotMultiplier': 1.3, 'TargetSideUSD': 3.0, 'TargetGlobalUSD': 20.0, 'MaxTotalOrders': 3, 'ATRMultiplier': 1.8},
    {'name': 'Max 4 Ordens / Dist 1200 / Mult 1.25 / Alvo $4', 'InitialLot': 0.01, 'BaseDistance': 1200, 'LotMultiplier': 1.25, 'TargetSideUSD': 4.0, 'TargetGlobalUSD': 25.0, 'MaxTotalOrders': 4, 'ATRMultiplier': 2.0},
    
    # 4. Trailing Stop Focado no Giro
    {'name': 'Mult 1.2 / Dist 1800 / Alvo $6 / Trailing 15%', 'InitialLot': 0.01, 'BaseDistance': 1800, 'LotMultiplier': 1.2, 'TargetSideUSD': 6.0, 'TrailingStartUSD': 8.0, 'TrailingDropPct': 15.0, 'TargetGlobalUSD': 40.0, 'MaxTotalOrders': 5, 'ATRMultiplier': 2.2},
    {'name': 'Mult 1.1 / Dist 2200 / Alvo $8 / Trailing 20%', 'InitialLot': 0.01, 'BaseDistance': 2200, 'LotMultiplier': 1.1, 'TargetSideUSD': 8.0, 'TrailingStartUSD': 12.0, 'TrailingDropPct': 20.0, 'TargetGlobalUSD': 50.0, 'MaxTotalOrders': 5, 'ATRMultiplier': 2.5},
]

results = []
base_cfg = {
    'InitialLot': 0.01,
    'TargetSideUSD': 2.00,
    'TargetGlobalUSD': 20.00,
    'BaseDistance': 600,
    'LotMultiplier': 1.5,
    'MaxMartingale': 8,
    'MaxTotalOrders': 15,
    'UseATR': True,
    'ATRMultiplier': 1.5,
    'UseTrailingStop': True,
    'TrailingStartUSD': 5.00,
    'TrailingDropPct': 10.0
}

print("Executando simulações de preservação de capital e alta performance...")
for test in exploratory_configs:
    cfg = base_cfg.copy()
    cfg.update(test)
    name = cfg.pop('name')
    res = engine.run(cfg)
    res['Name'] = name
    results.append(res)
    print(f"[{name}] Lucro: ${res['ProfitUSD']} ({res['ProfitPct']}%) | MaxDD: {res['MaxDD_Pct']}% (${res['MaxDD_USD']}) | Reciclagens: {res['Recycled']}")

df_res = pd.DataFrame(results)
df_res = df_res.sort_values(by='ProfitPct', ascending=False)
print("\n=== RANKING DE CONFIGURAÇÕES TESTADAS ===")
print(df_res[['Name', 'ProfitUSD', 'ProfitPct', 'MaxDD_Pct', 'RecoveryFactor', 'Recycled']].to_string(index=False))
