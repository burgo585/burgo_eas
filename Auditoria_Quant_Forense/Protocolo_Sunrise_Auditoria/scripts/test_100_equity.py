import datetime
import pandas as pd
import numpy as np
from run_xauusd_tests import get_xauusd_data

df = get_xauusd_data()
df['ema200'] = df['close'].ewm(span=200, adjust=False).mean()

def run_100usd_test(df, mode='EMA_BOTH', base_dist=800, lot_mult=1.15, max_orders=3, target_side=2.5, target_global=15.0, initial_lot=0.01):
    initial_balance = 100.0
    balance = initial_balance
    peak_equity = balance
    min_equity = balance
    max_dd_usd = 0.0
    max_dd_pct = 0.0
    
    contract_size = 100.0
    point = 0.01
    base_distance = base_dist * point
    spread = 0.20
    leverage = 500.0
    stop_out_level = 0.20 # 20% margin level
    
    buy_positions = []
    sell_positions = []
    
    total_trades = 0
    winning_trades = 0
    recycled = 0
    stopped_out = False
    stop_out_date = None
    equity_history = []

    def norm_lot(vol):
        return max(0.01, round(vol, 2))

    for row in df.itertuples():
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
            if equity < min_equity:
                min_equity = equity
            if equity > peak_equity:
                peak_equity = equity
            
            dd = peak_equity - equity
            if dd > max_dd_usd:
                max_dd_usd = dd
                max_dd_pct = (max_dd_usd / peak_equity) * 100.0

            # Verificação de Margem e Stop Out
            total_lots = sum(p['volume'] for p in buy_positions) + sum(p['volume'] for p in sell_positions)
            margin_used = (total_lots * contract_size * price) / leverage if total_lots > 0 else 0.0
            
            if margin_used > 0:
                margin_level = (equity / margin_used)
                if equity <= 0 or margin_level <= stop_out_level:
                    stopped_out = True
                    stop_out_date = row.time
                    balance = max(0.0, equity)
                    buy_positions.clear()
                    sell_positions.clear()
                    break

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

            # Fechamento de Lado
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

            # Filtros de Entrada
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
                buy_positions.append({'price': ask, 'volume': initial_lot})
            if len(sell_positions) == 0 and can_sell:
                sell_positions.append({'price': bid, 'volume': initial_lot})

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

        if stopped_out:
            break

    final_floating = sum((c - pos['price']) * pos['volume'] * contract_size for pos in buy_positions) + \
                     sum((pos['price'] - c) * pos['volume'] * contract_size for pos in sell_positions)
    final_balance = balance + final_floating

    return {
        'InitialBalance': 100.0,
        'FinalBalance': round(final_balance, 2),
        'ProfitUSD': round(final_balance - 100.0, 2),
        'ProfitPct': round(((final_balance - 100.0) / 100.0) * 100.0, 2),
        'PeakEquity': round(peak_equity, 2),
        'MinEquity': round(min_equity, 2),
        'MaxDD_USD': round(max_dd_usd, 2),
        'MaxDD_Pct': round(max_dd_pct, 2),
        'StoppedOut': stopped_out,
        'StopOutDate': str(stop_out_date) if stop_out_date else None,
        'Trades': total_trades
    }

print("=== TESTE COM BANCA DE $100 DÓLARES NO XAUUSD (2.6 ANOS) ===\n")

# Cenário A: Configuração Original (Dist 600, Mult 1.5, Max 15 ordens, Sem filtro)
res_orig = run_100usd_test(df, mode='ORIGINAL', base_dist=600, lot_mult=1.5, max_orders=15, target_side=2.0, target_global=20.0, initial_lot=0.02)
print("1. Configuração Original (0.02 lot, sem filtro, grid 15):")
print(res_orig)

# Cenário B: Modo EMA 200 Conservador (Dist 800, Mult 1.15, Max 2 ordens, Alvo $2.5)
res_ema_safe = run_100usd_test(df, mode='EMA_BOTH', base_dist=800, lot_mult=1.1, max_orders=2, target_side=2.5, target_global=12.0, initial_lot=0.01)
print("\n2. Modo EMA 200 Ultra Conservador (0.01 lot, Max 2 ordens, Dist 800):")
print(res_ema_safe)

# Cenário C: Modo EMA 200 com Lote Fixo 0.01 (Sem Martingale, Max 2 ordens)
res_ema_fixo = run_100usd_test(df, mode='EMA_BOTH', base_dist=1000, lot_mult=1.0, max_orders=2, target_side=3.0, target_global=15.0, initial_lot=0.01)
print("\n3. Modo EMA 200 Lote Fixo 0.01 (Sem Martingale, Max 2 ordens, Dist 1000):")
print(res_ema_fixo)

# Cenário D: Modo Apenas Compra (Buy-Only) Seguro (Max 2 ordens, Dist 1000, Lote 0.01)
res_buy_safe = run_100usd_test(df, mode='BUY_ONLY', base_dist=1000, lot_mult=1.0, max_orders=2, target_side=3.0, target_global=15.0, initial_lot=0.01)
print("\n4. Modo Apenas Compra Seguro (0.01 lot fixo, Max 2 ordens, Dist 1000):")
print(res_buy_safe)

# Cenário E: Modo Apenas Compra com Grade 3 (Dist 1200, Mult 1.1, Max 3)
res_buy_grid3 = run_100usd_test(df, mode='BUY_ONLY', base_dist=1200, lot_mult=1.1, max_orders=3, target_side=3.5, target_global=20.0, initial_lot=0.01)
print("\n5. Modo Apenas Compra Grade 3 (0.01 lot, Max 3 ordens, Dist 1200):")
print(res_buy_grid3)
