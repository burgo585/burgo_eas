import sys
import datetime
import pandas as pd
import numpy as np

sys.path.append(r'C:\Users\Vini_Burgo\.gemini\config\skills\quant-forensic-auditor\scripts')
from mt5_causal_backtester import load_mt5_data_and_specs, CausalGridBacktester

df_gold, specs_gold = load_mt5_data_and_specs(
    symbol='GOLD',
    utc_from=datetime.datetime(2024, 1, 1),
    utc_to=datetime.datetime(2026, 10, 23),
    mt5_path=r'C:\MetaTrader\terminal64.exe'
)

# Na XM Standard: comissao e zero embutida no spread (spread medio medido = 53 pts / $0.53)
engine_gold = CausalGridBacktester(df_gold, specs_gold, commission_per_lot=0.0, min_spread_usd=0.53, stop_out_pct=20.0)

configs_gold = [
    ('1. V40 Atual (Both Open, Dist 200, Mult 1.35, Max 12, Lot 0.02) [$200]', {
        'BalanceInit': 200.0, 'Mode': 'BOTH_OPEN', 'InitialLot': 0.02, 'TargetSideUSD': 2.0, 'TargetGlobalUSD': 20.0,
        'BaseDistancePts': 200, 'LotMultiplier': 1.35, 'MaxMartingale': 6, 'MaxTotalOrders': 12,
        'UseATR': True, 'ATRMultiplier': 1.5, 'UseTrailingStop': True, 'TrailingStartUSD': 1.5, 'TrailingDropPct': 10.0
    }),
    ('2. V40 Adaptado p/ $200 (Both Open, Dist 200, Mult 1.2, Max 4, Lot 0.01) [$200]', {
        'BalanceInit': 200.0, 'Mode': 'BOTH_OPEN', 'InitialLot': 0.01, 'TargetSideUSD': 2.0, 'TargetGlobalUSD': 10.0,
        'BaseDistancePts': 200, 'LotMultiplier': 1.2, 'MaxMartingale': 3, 'MaxTotalOrders': 4,
        'UseATR': True, 'ATRMultiplier': 1.5, 'UseTrailingStop': False
    }),
    ('3. Canal 400 pts c/ EMA 200 (Dist 400, Mult 1.2, Max 4, Lot 0.01) [$200]', {
        'BalanceInit': 200.0, 'Mode': 'EMA_BOTH', 'InitialLot': 0.01, 'TargetSideUSD': 2.5, 'TargetGlobalUSD': 10.0,
        'BaseDistancePts': 400, 'LotMultiplier': 1.2, 'MaxMartingale': 3, 'MaxTotalOrders': 4,
        'UseATR': True, 'ATRMultiplier': 1.5, 'UseTrailingStop': False
    }),
    ('4. Buy-Only Gold Institucional (Dist 400, Mult 1.1, Max 3, Lot 0.01) [$200]', {
        'BalanceInit': 200.0, 'Mode': 'BUY_ONLY', 'InitialLot': 0.01, 'TargetSideUSD': 2.0, 'TargetGlobalUSD': 8.0,
        'BaseDistancePts': 400, 'LotMultiplier': 1.1, 'MaxMartingale': 2, 'MaxTotalOrders': 3,
        'UseATR': True, 'ATRMultiplier': 1.5, 'UseTrailingStop': False
    }),
    ('5. Buy-Only Gold Conservador (Dist 600, Mult 1.0, Max 3, Lot 0.01) [$200]', {
        'BalanceInit': 200.0, 'Mode': 'BUY_ONLY', 'InitialLot': 0.01, 'TargetSideUSD': 3.0, 'TargetGlobalUSD': 10.0,
        'BaseDistancePts': 600, 'LotMultiplier': 1.0, 'MaxMartingale': 1, 'MaxTotalOrders': 3,
        'UseATR': True, 'ATRMultiplier': 1.5, 'UseTrailingStop': False
    })
]

print("========================================================================")
print("  AUDITORIA FORENSE CAUSAL - GOLD NA XM GLOBAL (BANCA $200 | 1:500)     ")
print("========================================================================")

for name, cfg in configs_gold:
    res = engine_gold.run_with_rolling_ruin(cfg)
    pnl = res['NetProfitUSD']
    fin = res['FinalEquity']
    so = res['StopOut']
    so_dt = res['StopOutDate']
    blown = res['RollingMonthsBlown']
    tot = res['RollingMonthsTested']
    pct_ruin = res['RiskOfRuinPct']
    max_dd = res['MaxDD_USD']
    max_dd_pct = res['MaxDD_Pct']
    swap = res['SwapPaidUSD']
    min_cap = res['MinRecommendedCapitalUSD']
    
    print(f">>> {name}")
    print(f"    PnL Jan/24-Out/26: ${pnl:,.2f} | Saldo Final: ${fin:,.2f} | StopOut Jan/24: {so} ({so_dt})")
    print(f"    TAXA DE FALENCIA (30+ Meses): {blown}/{tot} meses ({pct_ruin}%)")
    print(f"    Pior Drawdown Flutuante: -${max_dd:,.2f} ({max_dd_pct:.1f}%) | Swap: ${swap:,.2f}")
    print(f"    Banca Minima p/ Sobreviver: ${min_cap:,.2f}\n")
