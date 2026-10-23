import sys
import datetime
import pandas as pd
import numpy as np

sys.path.append(r'C:\Users\Vini_Burgo\.gemini\config\skills\quant-forensic-auditor\scripts')
from mt5_causal_backtester import load_mt5_data_and_specs, CausalGridBacktester

print("========================================================================")
print("  AUDITORIA FORENSE CAUSAL XM GLOBAL STANDARD - BANCA $200 (2024-2026)  ")
print("========================================================================")

# 1. TESTE GOLD
df_gold, specs_gold = load_mt5_data_and_specs(
    symbol='GOLD',
    utc_from=datetime.datetime(2024, 1, 1),
    utc_to=datetime.datetime(2026, 10, 23),
    mt5_path=r'C:\MetaTrader\terminal64.exe'
)
engine_gold = CausalGridBacktester(df_gold, specs_gold, commission_per_lot=0.0, min_spread_usd=0.53, stop_out_pct=20.0)

# 2. TESTE BTCUSD
df_btc, specs_btc = load_mt5_data_and_specs(
    symbol='BTCUSD',
    utc_from=datetime.datetime(2024, 1, 1),
    utc_to=datetime.datetime(2026, 10, 23),
    mt5_path=r'C:\MetaTrader\terminal64.exe'
)
engine_btc = CausalGridBacktester(df_btc, specs_btc, commission_per_lot=0.0, min_spread_usd=40.0, stop_out_pct=20.0)

configs = [
    ("GOLD: Setup Original $200 (Both Open, Dist 200, Mult 1.35, Max 12, Lot 0.02)", engine_gold, {
        'BalanceInit': 200.0, 'Mode': 'BOTH_OPEN', 'InitialLot': 0.02, 'TargetSideUSD': 2.0, 'TargetGlobalUSD': 20.0,
        'BaseDistancePts': 200, 'LotMultiplier': 1.35, 'MaxMartingale': 6, 'MaxTotalOrders': 12,
        'UseATR': True, 'ATRMultiplier': 1.5, 'UseTrailingStop': False
    }),
    ("GOLD: Setup Protegido $200 (EMA200, Dist 500, Mult 1.1, Max 3, Lot 0.01)", engine_gold, {
        'BalanceInit': 200.0, 'Mode': 'EMA_BOTH', 'InitialLot': 0.01, 'TargetSideUSD': 2.5, 'TargetGlobalUSD': 10.0,
        'BaseDistancePts': 500, 'LotMultiplier': 1.1, 'MaxMartingale': 2, 'MaxTotalOrders': 3,
        'UseATR': True, 'ATRMultiplier': 1.5, 'UseTrailingStop': False
    }),
    ("BTCUSD: Setup Descalibrado $200 (Dist 200 pts / $2.00, Max 12, Lot 0.01)", engine_btc, {
        'BalanceInit': 200.0, 'Mode': 'BOTH_OPEN', 'InitialLot': 0.01, 'TargetSideUSD': 2.0, 'TargetGlobalUSD': 20.0,
        'BaseDistancePts': 200, 'LotMultiplier': 1.35, 'MaxMartingale': 6, 'MaxTotalOrders': 12,
        'UseATR': True, 'ATRMultiplier': 1.5, 'UseTrailingStop': False
    }),
    ("BTCUSD: Setup Calibrado $200 (Buy-Only EMA200, Dist 50000 pts / $500, Max 3, Lot 0.01)", engine_btc, {
        'BalanceInit': 200.0, 'Mode': 'BUY_ONLY', 'InitialLot': 0.01, 'TargetSideUSD': 5.0, 'TargetGlobalUSD': 15.0,
        'BaseDistancePts': 50000, 'LotMultiplier': 1.0, 'MaxMartingale': 1, 'MaxTotalOrders': 3,
        'UseATR': True, 'ATRMultiplier': 1.5, 'UseTrailingStop': False
    })
]

for title, eng, cfg in configs:
    res = eng.run_with_rolling_ruin(cfg)
    print(f">>> {title}")
    print(f"    PnL Jan/24-Out/26: ${res['NetProfitUSD']:,.2f} | Saldo Final: ${res['FinalEquity']:,.2f} | StopOut Jan/24: {res['StopOut']} ({res['StopOutDate']})")
    print(f"    TAXA DE FALENCIA (30+ Meses): {res['RollingMonthsBlown']}/{res['RollingMonthsTested']} meses ({res['RiskOfRuinPct']}%)")
    print(f"    Pior Drawdown Flutuante: -${res['MaxDD_USD']:,.2f} ({res['MaxDD_Pct']:.1f}%) | Swap Pago: ${res['SwapPaidUSD']:,.2f}")
    print(f"    Banca Minima p/ Sobreviver: ${res['MinRecommendedCapitalUSD']:,.2f}\n")
