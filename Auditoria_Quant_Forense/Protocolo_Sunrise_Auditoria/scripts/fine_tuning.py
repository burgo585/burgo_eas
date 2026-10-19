import pandas as pd
from trend_test import run_trend_test, df

# Grade de otimização completa
grid = []
for dist in [600, 800, 1000, 1200]:
    for mult in [1.15, 1.25, 1.35]:
        for max_ord in [3, 4, 5]:
            for target in [3.0, 4.0, 5.0]:
                for mode in ['EMA_BOTH', 'BUY_ONLY']:
                    grid.append({
                        'dist': dist,
                        'mult': mult,
                        'max_ord': max_ord,
                        'target': target,
                        'mode': mode
                    })

print(f"Testando {len(grid)} combinações quantitativas...")
results = []
for p in grid:
    allow_sell = (p['mode'] == 'EMA_BOTH')
    use_ema = True
    res = run_trend_test(
        df,
        allow_sell=allow_sell,
        use_ema=use_ema,
        base_dist=p['dist'],
        lot_mult=p['mult'],
        max_orders=p['max_ord'],
        target_side=p['target'],
        target_global=p['target'] * 6.0
    )
    res['Dist'] = p['dist']
    res['Mult'] = p['mult']
    res['MaxOrd'] = p['max_ord']
    res['Target'] = p['target']
    res['Mode'] = p['mode']
    results.append(res)

df_all = pd.DataFrame(results)

# Melhores por Lucro
top_profit = df_all.sort_values(by='ProfitPct', ascending=False).head(5)
print("\n=== TOP 5 MAIORES LUCROS (%) NO XAUUSD ===")
print(top_profit[['Mode', 'Dist', 'Mult', 'MaxOrd', 'Target', 'ProfitUSD', 'ProfitPct', 'MaxDD_Pct', 'Trades']].to_string(index=False))

# Melhores por Razão Sharpe/Retorno sobre Risco (Lucro / MaxDD)
df_all['Ret_DD'] = df_all['ProfitUSD'] / df_all['MaxDD_USD']
top_safety = df_all.sort_values(by='Ret_DD', ascending=False).head(5)
print("\n=== TOP 5 MAIOR EFICIÊNCIA (RETORNO / RISCO) ===")
print(top_safety[['Mode', 'Dist', 'Mult', 'MaxOrd', 'Target', 'ProfitUSD', 'ProfitPct', 'MaxDD_Pct', 'Ret_DD']].to_string(index=False))
