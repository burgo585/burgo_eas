import datetime
import numpy as np
import pandas as pd
from run_xauusd_tests import get_xauusd_data

# Carrega os dados históricos reais do MT5
df = get_xauusd_data()
df['ema200'] = df['close'].ewm(span=200, adjust=False).mean()

def run_simulation(df_subset, base_dist=800, lot_mult=1.2, max_orders=4, target_side=4.0, target_global=25.0, mode='EMA_BOTH', spread=0.20):
    balance = 2000.0
    peak_equity = balance
    max_dd_usd = 0.0
    max_dd_pct = 0.0
    
    contract_size = 100.0
    point = 0.01
    base_distance = base_dist * point
    
    buy_positions = []
    sell_positions = []
    
    total_trades = 0
    winning_trades = 0
    recycled = 0

    def norm_lot(vol):
        return max(0.01, round(vol, 2))

    for row in df_subset.itertuples():
        o, h, l, c = row.open, row.high, row.low, row.close
        atr = row.atr
        ema = row.ema200
        dyn_dist = max(base_distance / 2.0, atr * 1.5)

        for price in ([o, l, h, c] if c >= o else [o, h, l, c]):
            ask = price + (spread / 2.0)
            bid = price - (spread / 2.0)

            buy_profit = sum((bid - pos['price']) * pos['volume'] * contract_size for pos in buy_positions)
            sell_profit = sum((pos['price'] - ask) * pos['volume'] * contract_size for pos in sell_positions)
            total_floating = buy_profit + sell_profit

            equity = balance + total_floating
            if equity > peak_equity:
                peak_equity = equity
            dd = peak_equity - equity
            if dd > max_dd_usd:
                max_dd_usd = dd
                max_dd_pct = (max_dd_usd / peak_equity) * 100.0

            # Global Target
            if total_floating >= target_global:
                balance += total_floating
                total_trades += len(buy_positions) + len(sell_positions)
                winning_trades += len(buy_positions) + len(sell_positions)
                buy_positions.clear()
                sell_positions.clear()
                continue

            # Reciclagem
            if buy_profit >= target_side and len(sell_positions) > 0:
                best_cand_idx = -1
                best_cand_loss = 0.0
                for idx, sp in enumerate(sell_positions):
                    p_loss = (sp['price'] - ask) * sp['volume'] * contract_size
                    if p_loss < 0 and buy_profit >= abs(p_loss):
                        if best_cand_idx == -1 or abs(p_loss) > abs(best_cand_loss):
                            best_cand_idx = idx
                            best_cand_loss = p_loss
                if best_cand_idx != -1:
                    balance += buy_profit + best_cand_loss
                    total_trades += len(buy_positions) + 1
                    winning_trades += len(buy_positions)
                    recycled += 1
                    buy_positions.clear()
                    sell_positions.pop(best_cand_idx)
                    continue

            if sell_profit >= target_side and len(buy_positions) > 0:
                best_cand_idx = -1
                best_cand_loss = 0.0
                for idx, bp in enumerate(buy_positions):
                    p_loss = (bid - bp['price']) * bp['volume'] * contract_size
                    if p_loss < 0 and sell_profit >= abs(p_loss):
                        if best_cand_idx == -1 or abs(p_loss) > abs(best_cand_loss):
                            best_cand_idx = idx
                            best_cand_loss = p_loss
                if best_cand_idx != -1:
                    balance += sell_profit + best_cand_loss
                    total_trades += len(sell_positions) + 1
                    winning_trades += len(sell_positions)
                    recycled += 1
                    sell_positions.clear()
                    buy_positions.pop(best_cand_idx)
                    continue

            # Side Target
            if buy_profit >= target_side:
                balance += buy_profit
                total_trades += len(buy_positions)
                winning_trades += len(buy_positions)
                buy_positions.clear()
                continue
            if sell_profit >= target_side:
                balance += sell_profit
                total_trades += len(sell_positions)
                winning_trades += len(sell_positions)
                sell_positions.clear()
                continue

            # Condições de Entrada por Modo
            if mode == 'BUY_ONLY':
                can_buy = True
                can_sell = False
            elif mode == 'EMA_BOTH':
                can_buy = (price >= ema)
                can_sell = (price <= ema)
            else:
                can_buy = True
                can_sell = True

            if len(buy_positions) == 0 and can_buy:
                buy_positions.append({'price': ask, 'volume': 0.01})
            if len(sell_positions) == 0 and can_sell:
                sell_positions.append({'price': bid, 'volume': 0.01})

            # Grade Controlada
            if len(buy_positions) > 0 and len(buy_positions) < max_orders:
                lowest_buy = min(p['price'] for p in buy_positions)
                if ask < (lowest_buy - dyn_dist):
                    last_vol = [p['volume'] for p in buy_positions if p['price'] == lowest_buy][0]
                    next_lot = norm_lot(last_vol * lot_mult)
                    buy_positions.append({'price': ask, 'volume': next_lot})

            if len(sell_positions) > 0 and len(sell_positions) < max_orders:
                highest_sell = max(p['price'] for p in sell_positions)
                if bid > (highest_sell + dyn_dist):
                    last_vol = [p['volume'] for p in sell_positions if p['price'] == highest_sell][0]
                    next_lot = norm_lot(last_vol * lot_mult)
                    sell_positions.append({'price': bid, 'volume': next_lot})

    final_floating = sum((c - pos['price']) * pos['volume'] * contract_size for pos in buy_positions) + \
                     sum((pos['price'] - c) * pos['volume'] * contract_size for pos in sell_positions)
    final_balance = balance + final_floating
    profit_usd = final_balance - 2000.0
    profit_pct = (profit_usd / 2000.0) * 100.0

    return {
        'ProfitUSD': round(profit_usd, 2),
        'ProfitPct': round(profit_pct, 2),
        'MaxDD_Pct': round(max_dd_pct, 2),
        'Trades': total_trades,
        'WinRate': round((winning_trades / total_trades * 100.0), 1) if total_trades > 0 else 0.0,
        'Recycled': recycled
    }

print("=== INICIANDO AUDITORIA CIENTÍFICA DE OVERFITTING NO XAUUSD ===\n")

# TESTE 1: IN-SAMPLE (TREINO) VS OUT-OF-SAMPLE (TESTE CEGO)
# Split 55% / 45%:
# In-Sample: 20/02/2024 até 31/03/2025 (~13.5 meses)
# Out-of-Sample: 01/04/2025 até 19/10/2026 (~18.5 meses)
split_date = pd.to_datetime('2025-04-01')
df_is = df[df['time'] < split_date].copy()
df_oos = df[df['time'] >= split_date].copy()

print(f"Período In-Sample (IS): {df_is['time'].iloc[0].date()} a {df_is['time'].iloc[-1].date()} ({len(df_is)} barras)")
print(f"Período Out-of-Sample (OOS): {df_oos['time'].iloc[0].date()} a {df_oos['time'].iloc[-1].date()} ({len(df_oos)} barras)\n")

for mode_name, m in [('Filtro EMA 200 (Ambos os Lados)', 'EMA_BOTH'), ('Apenas Compras (Buy-Only)', 'BUY_ONLY')]:
    res_is = run_simulation(df_is, base_dist=800, lot_mult=1.2, max_orders=4, target_side=4.0, target_global=25.0, mode=m)
    res_oos = run_simulation(df_oos, base_dist=800, lot_mult=1.2, max_orders=4, target_side=4.0, target_global=25.0, mode=m)
    
    # Anualização para calcular WFE (Walk-Forward Efficiency)
    days_is = (df_is['time'].iloc[-1] - df_is['time'].iloc[0]).days
    days_oos = (df_oos['time'].iloc[-1] - df_oos['time'].iloc[0]).days
    
    ann_is = (res_is['ProfitPct'] / days_is) * 365.0
    ann_oos = (res_oos['ProfitPct'] / days_oos) * 365.0
    wfe = (ann_oos / ann_is) * 100.0 if ann_is > 0 else 0.0

    print(f"--- TESTE SPLIT: {mode_name} ---")
    print(f"  [IN-SAMPLE]       Lucro: +${res_is['ProfitUSD']} (+{res_is['ProfitPct']}%) | MaxDD: {res_is['MaxDD_Pct']}% | Trades: {res_is['Trades']}")
    print(f"  [OUT-OF-SAMPLE]   Lucro: +${res_oos['ProfitUSD']} (+{res_oos['ProfitPct']}%) | MaxDD: {res_oos['MaxDD_Pct']}% | Trades: {res_oos['Trades']}")
    print(f"  Eficiência Walk-Forward (WFE): {wfe:.1f}% (Valores acima de 50% indicam ausência de overfitting)\n")

# TESTE 2: ANÁLISE DE SENSIBILIDADE / PLANALTO DE PARÂMETROS (PLATEAU ANALYSIS)
# Variação em torno de BaseDistance (600, 700, 800, 900, 1000) e LotMultiplier (1.15, 1.20, 1.25)
print("--- TESTE 2: ANÁLISE DE PLANALTO DE PARÂMETROS (SENSIBILIDADE) ---")
plateau_results = []
for dist in [600, 700, 800, 900, 1000]:
    for mult in [1.15, 1.20, 1.25]:
        res = run_simulation(df, base_dist=dist, lot_mult=mult, max_orders=4, target_side=4.0, mode='EMA_BOTH')
        plateau_results.append({'Dist': dist, 'Mult': mult, 'ProfitPct': res['ProfitPct'], 'MaxDD_Pct': res['MaxDD_Pct']})

df_plateau = pd.DataFrame(plateau_results)
mean_profit = df_plateau['ProfitPct'].mean()
std_profit = df_plateau['ProfitPct'].std()
cv_profit = (std_profit / mean_profit) * 100.0

print(f"Média de Lucro no Planalto: +{mean_profit:.2f}% | Desvio Padrão: {std_profit:.2f}%")
print(f"Coeficiente de Variação (CV): {cv_profit:.2f}% (Variação baixa comprova que o resultado não depende de um valor isolado)\n")

# TESTE 3: TESTE DE ESTRESSE DE CUSTOS (SPREAD x1.0, x2.0, x3.0)
print("--- TESTE 3: ESTRESSE DE SPREAD E SLIPPAGE ---")
for s_label, s_val in [('Spread Normal ($0.20)', 0.20), ('Spread Dobrado ($0.40)', 0.40), ('Spread Triplicado ($0.60)', 0.60)]:
    res_stress = run_simulation(df, base_dist=800, lot_mult=1.2, max_orders=4, target_side=4.0, mode='EMA_BOTH', spread=s_val)
    print(f"  {s_label}: Lucro: +${res_stress['ProfitUSD']} (+{res_stress['ProfitPct']}%) | MaxDD: {res_stress['MaxDD_Pct']}%")
