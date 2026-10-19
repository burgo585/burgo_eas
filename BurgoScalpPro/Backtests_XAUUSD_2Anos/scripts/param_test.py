import pandas as pd
from fast_multi_test import fetch_data, simulate

data = fetch_data(['EURUSD'])
if not data:
    exit(1)

eur = data['EURUSD']

experiments = [
    {'name': 'Print Exato (Target $5, Dist 500, TF ON)', 'tf': True, 'dist': 500, 'ts': 5.0, 'tg': 10.0},
    {'name': 'Print Exato (Target $5, Dist 500, TF OFF)', 'tf': False, 'dist': 500, 'ts': 5.0, 'tg': 10.0},
    {'name': 'Target Rápido $3 (Giro mais veloz, TF ON)', 'tf': True, 'dist': 500, 'ts': 3.0, 'tg': 10.0},
    {'name': 'Target $4 (Código V43 Original, TF ON)', 'tf': True, 'dist': 500, 'ts': 4.0, 'tg': 10.0},
    {'name': 'Distância 600 pts (60 pips mais espaçado, TF ON)', 'tf': True, 'dist': 600, 'ts': 5.0, 'tg': 10.0},
    {'name': 'Distância 700 pts (70 pips seguro, TF ON)', 'tf': True, 'dist': 700, 'ts': 5.0, 'tg': 10.0},
]

results = []
for exp in experiments:
    res = simulate('EURUSD', eur, use_trend_filter=exp['tf'], base_dist_pts=exp['dist'], target_side=exp['ts'], target_global=exp['tg'])
    res['experiment'] = exp['name']
    results.append(res)

df = pd.DataFrame(results)
cols = ['experiment', 'net_profit', 'profit_pct', 'max_drawdown_pct', 'profit_factor', 'win_rate', 'total_trades', 'basket_sl_count', 'recycle_count']
print("\n" + df[cols].to_string(index=False))
