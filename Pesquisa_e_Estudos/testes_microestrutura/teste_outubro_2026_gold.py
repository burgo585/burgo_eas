# -*- coding: utf-8 -*-
"""
Teste Causal Forense - Outubro de 2026 (2026.10.01 a 2026.10.26)
Simula a BoletaScalpingAuto no ativo GOLD (XM Global) com Ticks Reais.
"""
import sys
import os
import pandas as pd
import numpy as np

sys.path.append(r'C:\Users\Vini_Burgo\.gemini\config\skills\quant-forensic-auditor\scripts')
from xm_ticks_reader import load_xm_ticks, get_dataset_info

info = get_dataset_info('GOLD')
gold_path = info['file_path']

print("Buscando ticks de Outubro de 2026 no arquivo oficial XM...")
# Como o arquivo tem 8.39 GB e Outubro de 2026 está no FINAL do arquivo,
# vamos ler os chunks do final ou buscar onde 2026-10 começa!

# Vamos verificar a cauda do arquivo
file_size = os.path.getsize(gold_path)
print(f"Tamanho total: {file_size / (1024**3):.2f} GB")

# Ler os últimos 200MB do arquivo (ticks de Outubro de 2026)
with open(gold_path, 'rb') as f:
    # Ler os últimos 150MB
    offset = max(0, file_size - 150 * 1024 * 1024)
    f.seek(offset)
    # Descartar a primeira linha incompleta
    f.readline()
    df_raw = pd.read_csv(f, sep='\t', names=['DATE', 'TIME', 'BID', 'ASK', 'LAST', 'VOLUME', 'FLAGS'])

print(f"Lidos {len(df_raw):,} ticks do final do arquivo.")
df_raw['DATETIME'] = pd.to_datetime(df_raw['DATE'] + ' ' + df_raw['TIME'])
print(f"Intervalo dos ticks: {df_raw['DATETIME'].min()} ate {df_raw['DATETIME'].max()}")

# Filtrar para Outubro de 2026
df_oct = df_raw[(df_raw['DATETIME'] >= '2026-10-01') & (df_raw['DATETIME'] <= '2026-10-26 23:59:59')].copy()
print(f"Ticks em Outubro de 2026: {len(df_oct):,}")
df_oct.set_index('DATETIME', inplace=True)

# Análise de Spread de Outubro de 2026
df_oct['SPREAD_USD'] = (df_oct['ASK'] - df_oct['BID']).round(2)
df_oct['SPREAD_PTS'] = (df_oct['SPREAD_USD'] * 100).round(1)

spread_mean = df_oct['SPREAD_USD'].mean()
spread_median = df_oct['SPREAD_USD'].median()
spread_p95 = df_oct['SPREAD_USD'].quantile(0.95)

print("\n--- SPREAD DO OURO NA XM EM OUTUBRO/2026 ---")
print(f"Spread Medio: ${spread_mean:.2f} ({spread_mean*100:.1f} pts)")
print(f"Spread Mediano: ${spread_median:.2f} ({spread_median*100:.1f} pts)")
print(f"Spread 95%: ${spread_p95:.2f} ({spread_p95*100:.1f} pts)")

# Gerar Barras M5 de Outubro de 2026
bars_bid = df_oct['BID'].resample('5min').ohlc().dropna()
bars_ask = df_oct['ASK'].resample('5min').ohlc().dropna()
bars = bars_bid.copy()
bars['spread'] = (bars_ask['close'] - bars_bid['close']).round(2)

print(f"\nTotal de Barras M5 formadas em Outubro/2026: {len(bars):,}")

# Simulação das Regras da BoletaScalpingAuto
# Indicadores causais com .shift(1)
tr = np.maximum(
    bars['high'] - bars['low'],
    np.maximum(
        (bars['high'] - bars['close'].shift(1)).abs(),
        (bars['low'] - bars['close'].shift(1)).abs()
    )
)
bars['atr'] = tr.rolling(14).mean().shift(1)
bars['ema9'] = bars['close'].ewm(span=9, adjust=False).mean().shift(1)
bars['ema21'] = bars['close'].ewm(span=21, adjust=False).mean().shift(1)
bars = bars.dropna().copy()

initial_balance = 5000.0 # Conforme o teste do usuario
balance = initial_balance
max_equity = initial_balance
max_dd_usd = 0.0

point = 0.01
tick_val = 1.0 # $1 por ponto para 1.0 lote
commission_per_lot = 6.0
slippage_usd = 0.10
max_spread_pts = 50.0

trades = []
in_pos = False
pos_type = None
entry_price = 0.0
sl_price = 0.0
tp_price = 0.0
lot = 0.0

for i in range(1, len(bars)):
    row = bars.iloc[i]
    prev = bars.iloc[i-1]
    
    # Avaliar saída se posicionado
    if in_pos:
        if pos_type == 'BUY':
            hit_sl = (row['low'] <= sl_price)
            hit_tp = (row['high'] >= tp_price)
            if hit_sl and hit_tp: hit_tp = False # Conservador
            
            if hit_sl:
                exit_price = sl_price - slippage_usd
                pts = (exit_price - entry_price) / point
                pnl = pts * (lot * tick_val) - (lot * commission_per_lot)
                balance += pnl
                trades.append({'type': 'BUY', 'res': 'SL', 'pnl': pnl, 'lot': lot, 'time': row.name})
                in_pos = False
            elif hit_tp:
                exit_price = tp_price - slippage_usd
                pts = (exit_price - entry_price) / point
                pnl = pts * (lot * tick_val) - (lot * commission_per_lot)
                balance += pnl
                trades.append({'type': 'BUY', 'res': 'TP', 'pnl': pnl, 'lot': lot, 'time': row.name})
                in_pos = False
                
        elif pos_type == 'SELL':
            hit_sl = (row['high'] >= sl_price)
            hit_tp = (row['low'] <= tp_price)
            if hit_sl and hit_tp: hit_tp = False
            
            if hit_sl:
                exit_price = sl_price + slippage_usd
                pts = (entry_price - exit_price) / point
                pnl = pts * (lot * tick_val) - (lot * commission_per_lot)
                balance += pnl
                trades.append({'type': 'SELL', 'res': 'SL', 'pnl': pnl, 'lot': lot, 'time': row.name})
                in_pos = False
            elif hit_tp:
                exit_price = tp_price + slippage_usd
                pts = (entry_price - exit_price) / point
                pnl = pts * (lot * tick_val) - (lot * commission_per_lot)
                balance += pnl
                trades.append({'type': 'SELL', 'res': 'TP', 'pnl': pnl, 'lot': lot, 'time': row.name})
                in_pos = False
                
        if balance > max_equity:
            max_equity = balance
        dd = max_equity - balance
        if dd > max_dd_usd:
            max_dd_usd = dd
            
    # Avaliar entrada se não posicionado
    if not in_pos:
        # Filtro de spread
        cur_spread_pts = (row['spread'] / point)
        if cur_spread_pts <= max_spread_pts:
            atr_pts = (row['atr'] / point)
            sl_pts = max(30.0, atr_pts * 1.5)
            tp_pts = sl_pts * 2.0 # R:R 1:2
            
            # Risco 1% de $5000 = $50
            risk_usd = balance * 0.01
            lot_calc = risk_usd / (sl_pts * tick_val)
            lot = max(0.01, round(lot_calc, 2))
            
            # Sinal Compra
            if prev['ema9'] > prev['ema21'] and prev['close'] > prev['ema9'] and prev['low'] <= prev['ema9']:
                pos_type = 'BUY'
                entry_price = row['open'] + row['spread']
                sl_price = entry_price - (sl_pts * point)
                tp_price = entry_price + (tp_pts * point)
                in_pos = True
            elif prev['ema9'] < prev['ema21'] and prev['close'] < prev['ema9'] and prev['high'] >= prev['ema9']:
                pos_type = 'SELL'
                entry_price = row['open']
                sl_price = entry_price + (sl_pts * point) + row['spread']
                tp_price = entry_price - (tp_pts * point)
                in_pos = True

df_res = pd.DataFrame(trades)
print(f"\n--- RESULTADO DA SIMULAÇÃO FORENSE EM OUTUBRO/2026 (GOLD M5) ---")
print(f"Saldo Inicial: ${initial_balance:.2f} USD")
print(f"Saldo Final: ${balance:.2f} USD (Resultado Líquido: ${balance - initial_balance:+.2f} USD)")
print(f"Total de Operações: {len(df_res)}")

if len(df_res) > 0:
    wins = len(df_res[df_res['res'] == 'TP'])
    losses = len(df_res[df_res['res'] == 'SL'])
    win_rate = (wins / len(df_res)) * 100
    gross_profit = df_res[df_res['pnl'] > 0]['pnl'].sum()
    gross_loss = abs(df_res[df_res['pnl'] < 0]['pnl'].sum())
    pf = (gross_profit / gross_loss) if gross_loss > 0 else 999.0
    
    print(f"Operações Vencedoras: {wins} ({win_rate:.1f}%) | Perdedoras: {losses}")
    print(f"Fator de Lucro (Profit Factor): {pf:.2f}")
    print(f"Maior Rebaixamento (Drawdown): ${max_dd_usd:.2f} ({(max_dd_usd/initial_balance)*100:.1f}%)")
    print(f"\nPrimeiras 5 Operações:")
    print(df_res.head(5).to_string(index=False))
