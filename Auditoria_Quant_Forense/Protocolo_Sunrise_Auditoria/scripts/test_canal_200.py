import datetime
import pandas as pd
import numpy as np
from run_xauusd_tests import get_xauusd_data

df = get_xauusd_data()
df['ema200'] = df['close'].ewm(span=200, adjust=False).mean()

def run_simulation_custom(df, balance_init=100.0, base_dist=200, initial_lot=0.02, lot_mult=1.5, max_martingale=8, max_orders=15, target_side=2.0, target_global=20.0, use_atr=True, use_trailing=True, mode='ORIGINAL'):
    balance = balance_init
    peak_equity = balance
    min_equity = balance
    max_dd_usd = 0.0
    max_dd_pct = 0.0
    
    contract_size = 100.0
    point = 0.01
    base_distance = base_dist * point # 200 * 0.01 = $2.00
    spread = 0.20
    leverage = 500.0
    stop_out_level = 0.20
    
    buy_positions = []
    sell_positions = []
    
    total_trades = 0
    winning_trades = 0
    recycled = 0
    stopped_out = False
    stop_out_date = None

    def norm_lot(vol):
        return max(0.01, round(vol, 2))

    for row in df.itertuples():
        o, h, l, c = row.open, row.high, row.low, row.close
        atr = row.atr
        ema = row.ema200
        
        if use_atr:
            dyn_dist = max(base_distance / 2.0, atr * 1.5)
        else:
            dyn_dist = base_distance # Canal estritamente fixo de 200 pontos ($2.00)

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

            # Verificação de Stop Out
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
            if not use_trailing:
                if total_floating >= target_global:
                    balance += total_floating
                    total_trades += len(buy_positions) + len(sell_positions)
                    winning_trades += len(buy_positions) + len(sell_positions)
                    buy_positions.clear()
                    sell_positions.clear()
                    continue
            else:
                # Trailing global simplificado
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

            # Modo de Entrada
            if mode == 'BUY_ONLY':
                can_buy = True
                can_sell = False
            elif mode == 'EMA_BOTH':
                can_buy = (price >= ema)
                can_sell = (price <= ema)
            else: # ORIGINAL
                can_buy = True
                can_sell = True

            if len(buy_positions) == 0 and can_buy:
                buy_positions.append({'price': ask, 'volume': initial_lot})
            if len(sell_positions) == 0 and can_sell:
                sell_positions.append({'price': bid, 'volume': initial_lot})

            # Grade Controlada com Canal de 200 pontos
            if len(buy_positions) > 0 and len(buy_positions) < max_orders:
                lowest_buy = min(p['price'] for p in buy_positions)
                if ask < (lowest_buy - dyn_dist):
                    last_vol = [p['volume'] for p in buy_positions if p['price'] == lowest_buy][0]
                    next_lot = norm_lot(last_vol * lot_mult) if len(buy_positions) < max_martingale else last_vol
                    buy_positions.append({'price': ask, 'volume': next_lot})

            if len(sell_positions) > 0 and len(sell_positions) < max_orders:
                highest_sell = max(p['price'] for p in sell_positions)
                if bid > (highest_sell + dyn_dist):
                    last_vol = [p['volume'] for p in sell_positions if p['price'] == highest_sell][0]
                    next_lot = norm_lot(last_vol * lot_mult) if len(sell_positions) < max_martingale else last_vol
                    sell_positions.append({'price': bid, 'volume': next_lot})

        if stopped_out:
            break

    final_floating = sum((c - pos['price']) * pos['volume'] * contract_size for pos in buy_positions) + \
                     sum((pos['price'] - c) * pos['volume'] * contract_size for pos in sell_positions)
    final_balance = balance + final_floating

    return {
        'BancaInicial': balance_init,
        'SaldoFinal': round(final_balance, 2),
        'LucroUSD': round(final_balance - balance_init, 2),
        'LucroPct': round(((final_balance - balance_init) / balance_init) * 100.0, 2),
        'MaxDD_USD': round(max_dd_usd, 2),
        'MaxDD_Pct': round(max_dd_pct, 2),
        'MinEquity': round(min_equity, 2),
        'PeakEquity': round(peak_equity, 2),
        'StopOut': stopped_out,
        'StopOutDate': str(stop_out_date) if stop_out_date else 'Nenhum',
        'Trades': total_trades,
        'Recicladas': recycled
    }

print("=== TESTES COM CANAL DE 200 PONTOS (XAUUSD - 2.6 ANOS) ===\n")

# 1. Parâmetros Originais Exatos (0.02 lot, Mult 1.5, Max 15 ordens, Sem filtro, Dist 200) com $100
t1 = run_simulation_custom(df, balance_init=100.0, base_dist=200, initial_lot=0.02, lot_mult=1.5, max_martingale=8, max_orders=15, target_side=2.0, target_global=20.0, use_atr=True, mode='ORIGINAL')
print("1. Original com $100 de Banca (Distância 200, Lote 0.02, Mult 1.5, Max 15):")
print(t1)

# 2. Parâmetros Originais Exatos com $2.000 de Banca
t2 = run_simulation_custom(df, balance_init=2000.0, base_dist=200, initial_lot=0.02, lot_mult=1.5, max_martingale=8, max_orders=15, target_side=2.0, target_global=20.0, use_atr=True, mode='ORIGINAL')
print("\n2. Original com $2.000 de Banca (Distância 200, Lote 0.02, Mult 1.5, Max 15):")
print(t2)

# 3. Canal de 200 PONTOS FIXOS (UseATR = False) no Original com $100
t3 = run_simulation_custom(df, balance_init=100.0, base_dist=200, initial_lot=0.02, lot_mult=1.5, max_martingale=8, max_orders=15, target_side=2.0, target_global=20.0, use_atr=False, mode='ORIGINAL')
print("\n3. Canal Fixo de 200 Pontos Sem ATR (UseATR=False) com $100 de Banca:")
print(t3)

# 4. Canal de 200 Pontos com Filtro de Tendência EMA 200 com $100
t4 = run_simulation_custom(df, balance_init=100.0, base_dist=200, initial_lot=0.01, lot_mult=1.2, max_martingale=3, max_orders=3, target_side=2.0, target_global=15.0, use_atr=False, mode='EMA_BOTH')
print("\n4. Canal Fixo de 200 Pontos com Filtro EMA 200 (Lote 0.01, Max 3) com $100:")
print(t4)

# 5. Canal de 200 Pontos Apenas Compra (Buy-Only) com $100
t5 = run_simulation_custom(df, balance_init=100.0, base_dist=200, initial_lot=0.01, lot_mult=1.2, max_martingale=3, max_orders=3, target_side=2.0, target_global=15.0, use_atr=False, mode='BUY_ONLY')
print("\n5. Canal Fixo de 200 Pontos Apenas Compra (Buy-Only) com $100:")
print(t5)

# 6. Canal de 200 Pontos Apenas Compra com $2.000
t6 = run_simulation_custom(df, balance_init=2000.0, base_dist=200, initial_lot=0.02, lot_mult=1.25, max_martingale=4, max_orders=4, target_side=3.0, target_global=20.0, use_atr=False, mode='BUY_ONLY')
print("\n6. Canal Fixo de 200 Pontos Apenas Compra com $2.000:")
print(t6)
