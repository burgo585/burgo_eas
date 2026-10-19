import pandas as pd
from run_xauusd_tests import get_xauusd_data

df = get_xauusd_data()

# Verifica quantas vezes no histórico o Ouro caiu mais de $28.50 a partir de uma máxima local
# (Com 4 ordens de 0.01 lote abertas nos primeiros $9 de queda, uma queda adicional de $21 gera -$96.80 de perda flutuante + $16 de margem = Stop-Out de uma banca de $100!)
df['rolling_high_5d'] = df['high'].rolling(window=4*24*5, min_periods=1).max()
df['drop_from_5d_high'] = df['rolling_high_5d'] - df['low']

severe_drops = df[df['drop_from_5d_high'] >= 30.0]
distinct_months = severe_drops['time'].dt.to_period('M').unique()

print(f"Total de barras M15 com queda >= $30.00 a partir do topo de 5 dias: {len(severe_drops)} barras")
print(f"Total de meses distintos com choques de liquidação (> $30 de queda): {len(distinct_months)} de {df['time'].dt.to_period('M').nunique()} meses ({len(distinct_months)/df['time'].dt.to_period('M').nunique()*100:.1f}%)")

print("\nMaiores quedas de 5 dias (que liquidam instantaneamente uma conta de $100 com 0.04 lotes):")
top_drops = df.loc[df.groupby(df['time'].dt.to_period('M'))['drop_from_5d_high'].idxmax()]
for r in top_drops.itertuples():
    loss_004 = max(0.0, (r.drop_from_5d_high - 4.5) * 4.0)
    status = "LIQUIDA CONTA $100 (STOP-OUT)" if loss_004 >= 95.0 else "Sobrevive"
    print(f"  Mês {str(r.time)[:7]} | Data: {r.time} | Topo 5d: ${r.rolling_high_5d:.2f} -> Fundo: ${r.low:.2f} | Queda: -${r.drop_from_5d_high:.2f}/oz | Perda Flutuante (0.04 lote): -${loss_004:.2f} | {status}")
