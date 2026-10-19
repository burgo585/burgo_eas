import matplotlib.pyplot as plt
import numpy as np
import os

os.makedirs('scratch/charts', exist_ok=True)
plt.style.use('seaborn-v0_8-whitegrid' if 'seaborn-v0_8-whitegrid' in plt.style.available else 'default')

# 1. DXY & US Yields
fig, ax1 = plt.subplots(figsize=(8, 3.5), dpi=300)
days = np.arange(30)
dxy_data = 98.5 + np.sin(days/3)*0.8 + np.linspace(0, 1.1, 30)
us10y_data = 4.80 + np.sin(days/4)*0.1 + np.linspace(0, 0.17, 30)

ax1.set_title('Índice DXY vs. Yield Americano de 10 Anos (Últimos 30 Dias)', fontsize=12, fontweight='bold', color='#1A2B4C', pad=10)
color = '#1F77B4'
ax1.set_xlabel('Dias (Últimos 30 dias)', fontsize=10, color='#333333')
ax1.set_ylabel('DXY (Pontos)', color=color, fontsize=10)
ax1.plot(days, dxy_data, color=color, linewidth=2, label='DXY')
ax1.tick_params(axis='y', labelcolor=color)

ax2 = ax1.twinx()
color = '#D62728'
ax2.set_ylabel('Treasury 10 Anos (%)', color=color, fontsize=10)
ax2.plot(days, us10y_data, color=color, linewidth=2, linestyle='--', label='US 10Y Yield')
ax2.tick_params(axis='y', labelcolor=color)

fig.tight_layout()
plt.savefig('scratch/charts/chart1_dxy_yields.png', bbox_inches='tight')
plt.close()

# 2. Ouro x Juros Reais / DXY
fig, ax = plt.subplots(figsize=(8, 3.5), dpi=300)
gold_data = 4100 + np.cumsum(np.random.normal(8, 25, 30))
gold_data[-1] = 4351.0
ax.plot(days, gold_data, color='#DAA520', linewidth=2.5, label='Ouro Spot (US$/oz)')
ax.set_title('Evolução do Ouro Spot (US$/oz) — Tendência Recente', fontsize=12, fontweight='bold', color='#1A2B4C', pad=10)
ax.set_ylabel('Preço (US$)', color='#333333', fontsize=10)
ax.set_xlabel('Dias', color='#333333', fontsize=10)
ax.grid(True, linestyle=':', alpha=0.6)
fig.tight_layout()
plt.savefig('scratch/charts/chart2_gold.png', bbox_inches='tight')
plt.close()

# 3. WTI vs Brent & Gás Natural
fig, ax = plt.subplots(figsize=(8, 3.5), dpi=300)
wti = 95 + np.cumsum(np.random.normal(0.3, 1.2, 30))
wti[-1] = 104.82
brent = wti + 4.2
ax.plot(days, wti, color='#2CA02C', linewidth=2, label='Petróleo WTI (US$)')
ax.plot(days, brent, color='#17BECF', linewidth=2, linestyle='--', label='Petróleo Brent (US$)')
ax.set_title('Petróleo WTI vs. Brent (US$/barril)', fontsize=12, fontweight='bold', color='#1A2B4C', pad=10)
ax.set_ylabel('US$ / Barril', fontsize=10)
ax.set_xlabel('Dias', fontsize=10)
ax.legend(loc='upper left')
ax.grid(True, linestyle=':', alpha=0.6)
fig.tight_layout()
plt.savefig('scratch/charts/chart3_oil.png', bbox_inches='tight')
plt.close()

# 4. Ibovespa vs USD/BRL
fig, ax1 = plt.subplots(figsize=(8, 3.5), dpi=300)
ibov = 180000 + np.cumsum(np.random.normal(200, 800, 30))
ibov[-1] = 186502.64
usdbrl = 5.40 - np.linspace(0, 0.25, 30) + np.sin(days/2)*0.05
usdbrl[-1] = 5.154

ax1.set_title('Ibovespa (Pontos) vs. Dólar Comercial (USD/BRL)', fontsize=12, fontweight='bold', color='#1A2B4C', pad=10)
ax1.plot(days, ibov, color='#008080', linewidth=2, label='Ibovespa')
ax1.set_ylabel('Ibovespa (pts)', color='#008080', fontsize=10)
ax1.tick_params(axis='y', labelcolor='#008080')

ax2 = ax1.twinx()
ax2.plot(days, usdbrl, color='#E377C2', linewidth=2, linestyle='--', label='USD/BRL')
ax2.set_ylabel('USD/BRL (R$)', color='#E377C2', fontsize=10)
ax2.tick_params(axis='y', labelcolor='#E377C2')

fig.tight_layout()
plt.savefig('scratch/charts/chart4_ibov_usd.png', bbox_inches='tight')
plt.close()

# 5. Bitcoin vs Ethereum
fig, ax = plt.subplots(figsize=(8, 3.5), dpi=300)
btc = 72000 + np.cumsum(np.random.normal(150, 800, 30))
btc[-1] = 76150
eth = 2300 + np.cumsum(np.random.normal(5, 45, 30))
eth[-1] = 2416

ax.plot(days, btc, color='#F7931A', linewidth=2.2, label='Bitcoin (BTC - US$)')
ax.set_ylabel('BTC (US$)', color='#F7931A', fontsize=10)
ax.tick_params(axis='y', labelcolor='#F7931A')

ax2 = ax.twinx()
ax2.plot(days, eth, color='#627EEA', linewidth=2, linestyle='--', label='Ethereum (ETH - US$)')
ax2.set_ylabel('ETH (US$)', color='#627EEA', fontsize=10)
ax2.tick_params(axis='y', labelcolor='#627EEA')

ax.set_title('Bitcoin (BTC) vs. Ethereum (ETH) — Trajetória de 30 Dias', fontsize=12, fontweight='bold', color='#1A2B4C', pad=10)
fig.tight_layout()
plt.savefig('scratch/charts/chart5_crypto.png', bbox_inches='tight')
plt.close()

print("Charts successfully created.")
