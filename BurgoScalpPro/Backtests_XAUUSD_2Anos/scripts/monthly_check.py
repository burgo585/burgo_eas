import pandas as pd
from simulate_xauusd_2years import load_data, run_backtest

pkg = load_data()
r2 = run_backtest(pkg, use_trend_filter=False, base_dist_pts=500, target_side=5.0, target_global=10.0, max_loss_usd=80.0)

print("\n=== MONTHLY BREAKDOWN (TEST 2 - PURO GRID BI-DIRECIONAL) ===")
months = sorted(r2['monthly_pnl'].keys())
cum = 1000.0
for m in months:
    pnl = r2['monthly_pnl'][m]
    cum += pnl
    print(f"Mês {m}: PnL = ${pnl:8.2f} | Saldo Acumulado = ${cum:9.2f}")
