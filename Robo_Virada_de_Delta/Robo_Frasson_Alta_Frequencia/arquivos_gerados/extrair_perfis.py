import json
import pandas as pd

with open(r'c:\Robo Virada de Delta\Robo_Frasson_Alta_Frequencia_PRO\Testes_Quantitativos\all_results_xauusd.json') as f:
    data = json.load(f)

df = pd.DataFrame(data)

print(f"Total de simulacoes carregadas: {len(df)}")

# Categoria 1: Alta Frequencia (>= 2.0 trades/dia) com Maior Win Rate
cat1 = df[df['trades_per_day'] >= 2.0].sort_values(by=['win_rate', 'net_60d_usd'], ascending=False)

print("\n" + "="*80)
print("CATEGORIA 1: ALTA FREQUENCIA (>= 2.0 trades/dia) - RANKING WIN RATE:")
print("="*80)
for idx, r in cat1.head(5).iterrows():
    print(f"WR: {r['win_rate']}% | Trades/dia: {r['trades_per_day']} | Net 60d: ${r['net_60d_usd']} | Proj 2A: ${r['proj_2y_usd']} | MaxDD: ${r['max_dd_usd']}")
    print(f"   Gatilho: {r['trigger']} | P={r['frasson_period']} S={r['shift']} M={r['multiplier']} | TP1={r['tp1_mult']}x ({int(r['partial_ratio']*100)}%) TP2={r['tp2_mult']}x SL={r['sl_mult']}x\n")

# Categoria 2: Frequencia Moderada (1.0 a 2.0 trades/dia) com Maior Win Rate
cat2 = df[(df['trades_per_day'] >= 1.0) & (df['trades_per_day'] < 2.0)].sort_values(by=['win_rate', 'net_60d_usd'], ascending=False)
print("="*80)
print("CATEGORIA 2: FREQUENCIA EQUILIBRADA (1.0 a 2.0 trades/dia) - RANKING WIN RATE:")
print("="*80)
for idx, r in cat2.head(5).iterrows():
    print(f"WR: {r['win_rate']}% | Trades/dia: {r['trades_per_day']} | Net 60d: ${r['net_60d_usd']} | Proj 2A: ${r['proj_2y_usd']} | MaxDD: ${r['max_dd_usd']}")
    print(f"   Gatilho: {r['trigger']} | P={r['frasson_period']} S={r['shift']} M={r['multiplier']} | TP1={r['tp1_mult']}x ({int(r['partial_ratio']*100)}%) TP2={r['tp2_mult']}x SL={r['sl_mult']}x\n")

# Categoria 3: Sniper / Ultra Assertivo (Maior Win Rate Absoluto)
cat3 = df[df['profit_factor'] >= 1.5].sort_values(by=['win_rate', 'net_60d_usd'], ascending=False)
print("="*80)
print("CATEGORIA 3: SNIPER / ULTRA ASSERTIVO (WR Absoluto):")
print("="*80)
for idx, r in cat3.head(5).iterrows():
    print(f"WR: {r['win_rate']}% | Trades/dia: {r['trades_per_day']} | Net 60d: ${r['net_60d_usd']} | Proj 2A: ${r['proj_2y_usd']} | MaxDD: ${r['max_dd_usd']}")
    print(f"   Gatilho: {r['trigger']} | P={r['frasson_period']} S={r['shift']} M={r['multiplier']} | TP1={r['tp1_mult']}x ({int(r['partial_ratio']*100)}%) TP2={r['tp2_mult']}x SL={r['sl_mult']}x\n")
