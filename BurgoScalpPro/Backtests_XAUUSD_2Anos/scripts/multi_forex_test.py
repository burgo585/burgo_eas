import MetaTrader5 as mt5
import pandas as pd
import numpy as np
import datetime

# We can import run_simulation from backtest_simulation
from backtest_simulation import run_simulation

pairs = ['EURUSD', 'AUDUSD', 'USDCAD']
results = []

for p in pairs:
    print(f"\n--- Testing {p} (Trend Filter ON) ---")
    res_on, _ = run_simulation(use_trend_filter=True, symbol=p)
    if res_on:
        results.append(res_on)
        print(f"Result {p} TF ON: Profit=${res_on['net_profit']} ({res_on['profit_pct']}%), DD=${res_on['max_drawdown_usd']} ({res_on['max_drawdown_pct']}%), PF={res_on['profit_factor']}, WinRate={res_on['win_rate']}%")

    print(f"\n--- Testing {p} (Trend Filter OFF) ---")
    res_off, _ = run_simulation(use_trend_filter=False, symbol=p)
    if res_off:
        results.append(res_off)
        print(f"Result {p} TF OFF: Profit=${res_off['net_profit']} ({res_off['profit_pct']}%), DD=${res_off['max_drawdown_usd']} ({res_off['max_drawdown_pct']}%), PF={res_off['profit_factor']}, WinRate={res_off['win_rate']}%")

df_res = pd.DataFrame(results)
print("\n=== SUMMARY TABLE ===")
cols = ['symbol', 'use_trend_filter', 'net_profit', 'profit_pct', 'max_drawdown_pct', 'profit_factor', 'win_rate', 'total_trades', 'basket_sl_count']
print(df_res[cols].to_string(index=False))
