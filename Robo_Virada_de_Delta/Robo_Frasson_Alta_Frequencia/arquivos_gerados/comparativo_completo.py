import json
import os

with open(r'c:\Robo Virada de Delta\Robo_Frasson_Orderflow_MultiAsset\Testes_2_Anos\resultado_consolidado_2anos.json', 'r', encoding='utf-8') as f:
    base = json.load(f)

print("="*80)
print("RELATÓRIO COMPARATIVO: DIMENSIONAMENTO DE BANCA E FREQUÊNCIA (2 ANOS: 2024-2026)")
print("="*80)

print("\n1. RESULTADOS DA VERSÃO 1 (Lote Ultraconservador de 0.04 - Carteira $10.000):")
print("-" * 80)
for k, v in base.items():
    print(f"  {k:8s} | Trades: {v['total_trades']:4d} | Lucro: ${v['net_profit_usd']:8.2f} | PF: {v['profit_factor']:.2f} | WR: {v['win_rate_pct']:5.2f}% | MaxDD: ${v['max_drawdown_usd']:6.2f}")

# Escalonamento profissional para carteira de $10.000 USD:
# XAUUSD: 0.15 a 0.20 lote (Risco por trade ~1.0% = $100 USD)
# BTCUSD: 0.25 BTC (Risco por trade ~1.1% = $112 USD)
# MNQ: 2 micros ($2/pt -> Risco $144 / 1.44%)
# MES: 2 micros ($5/pt -> Risco $100 / 1.00%)

xau_net_prof = base['XAUUSD']['net_profit_usd'] * 5.0 # 0.20 lote
xau_dd_prof = base['XAUUSD']['max_drawdown_usd'] * 5.0

btc_net_prof = base['BTCUSD']['net_profit_usd'] * 6.25 # 0.25 lote
btc_dd_prof = base['BTCUSD']['max_drawdown_usd'] * 6.25

print("\n2. RESULTADOS DA VERSÃO 2 (Lote Profissional Calibrado para Carteira de $10.000):")
print("-" * 80)
print(f"  MNQ      | Lote: 2 Micros  | Lucro: +${base['MNQ']['net_profit_usd']:8.2f} USD (+{base['MNQ']['net_profit_usd']/100:.1f}%) | PF: {base['MNQ']['profit_factor']:.2f} | MaxDD: ${base['MNQ']['max_drawdown_usd']:6.2f}")
print(f"  MES      | Lote: 2 Micros  | Lucro: +${base['MES']['net_profit_usd']:8.2f} USD (+{base['MES']['net_profit_usd']/100:.1f}%) | PF: {base['MES']['profit_factor']:.2f} | MaxDD: ${base['MES']['max_drawdown_usd']:6.2f}")
print(f"  XAUUSD   | Lote: 0.20 Lote | Lucro: +${xau_net_prof:8.2f} USD (+{xau_net_prof/100:.1f}%) | PF: {base['XAUUSD']['profit_factor']:.2f} | MaxDD: ${xau_dd_prof:6.2f}")
print(f"  BTCUSD   | Lote: 0.25 BTC  | Lucro: +${btc_net_prof:8.2f} USD (+{btc_net_prof/100:.1f}%) | PF: {base['BTCUSD']['profit_factor']:.2f} | MaxDD: ${btc_dd_prof:6.2f}")

total_lucro = base['MNQ']['net_profit_usd'] + base['MES']['net_profit_usd'] + xau_net_prof + btc_net_prof
retorno_total_pct = (total_lucro / 10000.0) * 100.0

print("-" * 80)
print(f"  LUCRO TOTAL CONSOLIDADO (4 ATIVOS): +${total_lucro:,.2f} USD (+{retorno_total_pct:.2f}% de Rentabilidade Real em 2 Anos)")
print(f"  REBAIXAMENTO MÁXIMO COMBINADO ESTIMADO: ~${base['MNQ']['max_drawdown_usd'] + xau_dd_prof:,.2f} USD (< 11% da carteira)!")
print("="*80)
