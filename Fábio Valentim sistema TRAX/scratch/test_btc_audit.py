import sys
import datetime
import pandas as pd
import numpy as np

sys.path.append(r'C:\Users\Vini_Burgo\.gemini\config\skills\quant-forensic-auditor\scripts')
from mt5_causal_backtester import load_mt5_data_and_specs, CausalGridBacktester

df_btc, specs_btc = load_mt5_data_and_specs(
    symbol='BTCUSD',
    utc_from=datetime.datetime(2024, 1, 1),
    utc_to=datetime.datetime(2026, 10, 23),
    mt5_path=r'C:\MetaTrader\terminal64.exe'
)

# No BTCUSD da XM: Spread medio = 4000 pts ($40.00), contract_size = 1.0
engine_btc = CausalGridBacktester(df_btc, specs_btc, commission_per_lot=0.0, min_spread_usd=40.0, stop_out_pct=20.0)

configs_btc = [
    ('1. BTCUSD Simetrico (Dist 200 pts / $2.00, Mult 1.35, Max 12, Lot 0.01) [$200]', {
        'BalanceInit': 200.0, 'Mode': 'BOTH_OPEN', 'InitialLot': 0.01, 'TargetSideUSD': 2.0, 'TargetGlobalUSD': 20.0,
        'BaseDistancePts': 200, 'LotMultiplier': 1.35, 'MaxMartingale': 6, 'MaxTotalOrders': 12,
        'UseATR': True, 'ATRMultiplier': 1.5, 'UseTrailingStop': False
    }),
    ('2. BTCUSD Canal Proporcional $500 (Dist 50000 pts, Mult 1.2, Max 4, Lot 0.01) [$200]', {
        'BalanceInit': 200.0, 'Mode': 'BOTH_OPEN', 'InitialLot': 0.01, 'TargetSideUSD': 5.0, 'TargetGlobalUSD': 20.0,
        'BaseDistancePts': 50000, 'LotMultiplier': 1.2, 'MaxMartingale': 3, 'MaxTotalOrders': 4,
        'UseATR': True, 'ATRMultiplier': 1.5, 'UseTrailingStop': False
    }),
    ('3. BTCUSD Buy-Only c/ EMA 200 (Dist 50000 pts / $500, Max 3, Lot 0.01) [$200]', {
        'BalanceInit': 200.0, 'Mode': 'BUY_ONLY', 'InitialLot': 0.01, 'TargetSideUSD': 5.0, 'TargetGlobalUSD': 15.0,
        'BaseDistancePts': 50000, 'LotMultiplier': 1.0, 'MaxMartingale': 1, 'MaxTotalOrders': 3,
        'UseATR': True, 'ATRMultiplier': 1.5, 'UseTrailingStop': False
    }),
    ('4. BTCUSD Buy-Only Canal Largo $1000 (Dist 100000 pts, Max 2, Lot 0.01) [$200]', {
        'BalanceInit': 200.0, 'Mode': 'BUY_ONLY', 'InitialLot': 0.01, 'TargetSideUSD': 10.0, 'TargetGlobalUSD': 20.0,
        'BaseDistancePts': 100000, 'LotMultiplier': 1.0, 'MaxMartingale': 1, 'MaxTotalOrders': 2,
        'UseATR': True, 'ATRMultiplier': 1.5, 'UseTrailingStop': False
    })
]

print("========================================================================")
print("  AUDITORIA FORENSE CAUSAL - BTCUSD NA XM GLOBAL (BANCA $200 | 1:500)   ")
print("========================================================================")

for name, cfg in configs_btc:
    res = engine_btc.run_with_rolling_ruin(cfg)
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
