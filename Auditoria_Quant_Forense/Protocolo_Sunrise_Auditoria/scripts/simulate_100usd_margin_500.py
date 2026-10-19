import MetaTrader5 as mt5
import pandas as pd
import numpy as np
import datetime
from run_xauusd_tests import get_xauusd_data

df = get_xauusd_data()
df['ema200'] = df['close'].ewm(span=200, adjust=False).mean()

def run_detailed_margin_sim(df, 
                            balance_init=100.0,
                            initial_lot=0.01,
                            target_side=3.0,
                            target_global=15.0,
                            base_dist_pts=300,
                            lot_mult=1.2,
                            max_martingale=3,
                            max_orders=4,
                            use_atr=True,
                            atr_mult=1.5,
                            use_trailing=True,
                            trailing_start=5.0,
                            trailing_drop_pct=10.0,
                            trade_direction="BUY_ONLY",
                            leverage=500.0,
                            stop_out_pct=20.0, # 20% stop-out level
                            margin_call_pct=50.0, # 50% margin call
                            spread_usd=0.20):

    contract_size = 100.0
    point = 0.01
    base_dist = base_dist_pts * point
    trailing_drop = trailing_drop_pct / 100.0
    stop_out_ratio = stop_out_pct / 100.0
    margin_call_ratio = margin_call_pct / 100.0
    
    balance = balance_init
    peak_equity = balance
    min_equity = balance
    min_equity_time = None
    
    max_margin_used = 0.0
    min_free_margin = balance_init
    min_margin_level = 999999.0
    margin_call_triggered = False
    margin_call_count = 0
    
    max_dd_usd = 0.0
    max_dd_pct = 0.0
    
    buy_positions = []
    sell_positions = []
    
    max_buy_profit = 0.0
    max_sell_profit = 0.0
    max_global_profit = 0.0
    
    total_trades = 0
    winning_trades = 0
    recycled_orders = 0
    stopped_out = False
    stop_out_date = None
    stop_out_price = 0.0
    
    def norm_lot(vol):
        return max(0.01, round(vol, 2))

    for row in df.itertuples():
        o, h, l, c = row.open, row.high, row.low, row.close
        atr = row.atr
        ema = row.ema200
        bar_time = row.time
        
        if use_atr:
            dist = atr * atr_mult
            min_dist = base_dist / 2.0
            dyn_dist = max(min_dist, dist)
        else:
            dyn_dist = base_dist
            
        price_steps = [o, l, h, c] if c >= o else [o, h, l, c]
        
        for price in price_steps:
            ask = price + (spread_usd / 2.0)
            bid = price - (spread_usd / 2.0)
            
            buy_profit = sum((bid - pos['price']) * pos['volume'] * contract_size for pos in buy_positions)
            sell_profit = sum((pos['price'] - ask) * pos['volume'] * contract_size for pos in sell_positions)
            total_floating = buy_profit + sell_profit
            
            equity = balance + total_floating
            if equity < min_equity:
                min_equity = equity
                min_equity_time = bar_time
                
            if equity > peak_equity:
                peak_equity = equity
                
            dd = peak_equity - equity
            if dd > max_dd_usd:
                max_dd_usd = dd
                max_dd_pct = (max_dd_usd / peak_equity) * 100.0
                
            # Cálculo Rigoroso de Margem no XAUUSD
            total_buy_lots = sum(p['volume'] for p in buy_positions)
            total_sell_lots = sum(p['volume'] for p in sell_positions)
            # Na maioria das corretoras ECN/MT5: margem é calculada pelo maior lado (hedging) ou soma
            # Para máxima segurança, consideramos o total de lotes abertos:
            total_lots = max(total_buy_lots, total_sell_lots) if (total_buy_lots > 0 and total_sell_lots > 0) else (total_buy_lots + total_sell_lots)
            margin_used = (total_lots * contract_size * price) / leverage if total_lots > 0 else 0.0
            
            if margin_used > max_margin_used:
                max_margin_used = margin_used
                
            free_margin = equity - margin_used
            if free_margin < min_free_margin:
                min_free_margin = free_margin
                
            if margin_used > 0:
                margin_level = (equity / margin_used) * 100.0
                if margin_level < min_margin_level:
                    min_margin_level = margin_level
                    
                if margin_level <= margin_call_pct:
                    margin_call_triggered = True
                    margin_call_count += 1
                    
                if equity <= 0 or (margin_level <= stop_out_pct):
                    stopped_out = True
                    stop_out_date = bar_time
                    stop_out_price = price
                    balance = max(0.0, equity)
                    buy_positions.clear()
                    sell_positions.clear()
                    break

            if stopped_out:
                break
                
            # 1. FECHAMENTO GLOBAL
            if not use_trailing:
                if total_floating >= target_global:
                    balance += total_floating
                    total_trades += (len(buy_positions) + len(sell_positions))
                    winning_trades += (len(buy_positions) + len(sell_positions))
                    buy_positions.clear()
                    sell_positions.clear()
                    max_global_profit = 0.0
                    continue
            else:
                if total_floating >= target_global:
                    if total_floating > max_global_profit:
                        max_global_profit = total_floating
                if max_global_profit >= target_global:
                    if (max_global_profit - total_floating) >= (max_global_profit * trailing_drop):
                        balance += total_floating
                        total_trades += (len(buy_positions) + len(sell_positions))
                        winning_trades += (len(buy_positions) + len(sell_positions))
                        buy_positions.clear()
                        sell_positions.clear()
                        max_global_profit = 0.0
                        continue

            # 2. RECICLAGEM ATIVA
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
                    recycled_orders += 1
                    buy_positions.clear()
                    sell_positions.pop(best_cand_idx)
                    max_buy_profit = 0.0
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
                    recycled_orders += 1
                    sell_positions.clear()
                    buy_positions.pop(best_cand_idx)
                    max_sell_profit = 0.0
                    continue

            # 3. FECHAMENTO INDIVIDUAL / TRAILING
            if not use_trailing:
                if buy_profit >= target_side:
                    balance += buy_profit
                    total_trades += len(buy_positions)
                    winning_trades += len(buy_positions)
                    buy_positions.clear()
                    max_buy_profit = 0.0
                    continue
                if sell_profit >= target_side:
                    balance += sell_profit
                    total_trades += len(sell_positions)
                    winning_trades += len(sell_positions)
                    sell_positions.clear()
                    max_sell_profit = 0.0
                    continue
            else:
                start_side = trailing_start if trailing_start > 0 else target_side
                if buy_profit >= start_side:
                    if buy_profit > max_buy_profit:
                        max_buy_profit = buy_profit
                if max_buy_profit >= start_side:
                    if (max_buy_profit - buy_profit) >= (max_buy_profit * trailing_drop):
                        balance += buy_profit
                        total_trades += len(buy_positions)
                        winning_trades += len(buy_positions)
                        buy_positions.clear()
                        max_buy_profit = 0.0
                        continue

                if sell_profit >= start_side:
                    if sell_profit > max_sell_profit:
                        max_sell_profit = sell_profit
                if max_sell_profit >= start_side:
                    if (max_sell_profit - sell_profit) >= (max_sell_profit * trailing_drop):
                        balance += sell_profit
                        total_trades += len(sell_positions)
                        winning_trades += len(sell_positions)
                        sell_positions.clear()
                        max_sell_profit = 0.0
                        continue

            # 4. MOTOR DE GIRO E GRADE
            allow_buy = True
            allow_sell = True
            if trade_direction == "BUY_ONLY":
                allow_sell = False
            elif trade_direction == "EMA_BOTH":
                allow_buy = (ask >= ema)
                allow_sell = (bid <= ema)
                
            if len(buy_positions) == 0 and allow_buy:
                buy_positions.append({'price': ask, 'volume': norm_lot(initial_lot)})
            if len(sell_positions) == 0 and allow_sell:
                sell_positions.append({'price': bid, 'volume': norm_lot(initial_lot)})
                
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
    total_profit_usd = final_balance - balance_init
    total_profit_pct = (total_profit_usd / balance_init) * 100.0

    return {
        'BancaInicial': balance_init,
        'SaldoFinal': round(final_balance, 2),
        'LucroUSD': round(total_profit_usd, 2),
        'LucroPct': round(total_profit_pct, 2),
        'MaxDD_USD': round(max_dd_usd, 2),
        'MaxDD_Pct': round(max_dd_pct, 2),
        'MinEquity': round(min_equity, 2),
        'MinEquityTime': str(min_equity_time),
        'PeakEquity': round(peak_equity, 2),
        'MaxMarginUsed': round(max_margin_used, 2),
        'MinFreeMargin': round(min_free_margin, 2),
        'MinMarginLevelPct': round(min_margin_level, 2) if min_margin_level < 999999 else 0.0,
        'MarginCallTriggered': margin_call_triggered,
        'StopOut': stopped_out,
        'StopOutDate': str(stop_out_date) if stop_out_date else "Nenhum",
        'Trades': total_trades,
        'Recicladas': recycled_orders
    }

print("================================================================================")
print("  SIMULAÇÃO COM SALDO DE $100.00 E ALAVANCAGEM 1:500 (XAUUSD - 2.6 ANOS REAIS)  ")
print("================================================================================")

# 1. Configuração Imagem 1: Apenas Compras com Trailing Stop (Start $5, Drop 10%)
c1 = run_detailed_margin_sim(df, balance_init=100.0, initial_lot=0.01, target_side=3.0, target_global=15.0,
                             base_dist_pts=300, lot_mult=1.2, max_martingale=3, max_orders=4,
                             use_atr=True, atr_mult=1.5, use_trailing=True, trailing_start=5.0, trailing_drop_pct=10.0,
                             trade_direction="BUY_ONLY", leverage=500.0)

print("\n--- 1. CONFIGURAÇÃO IMAGEM 1: APENAS COMPRAS (COM TRAILING STOP) ---")
for k, v in c1.items():
    print(f"  {k}: {v}")

# 2. Configuração Imagem 1: Apenas Compras com TP Fixo de $3.00 (Sem Trailing Stop)
c2 = run_detailed_margin_sim(df, balance_init=100.0, initial_lot=0.01, target_side=3.0, target_global=15.0,
                             base_dist_pts=300, lot_mult=1.2, max_martingale=3, max_orders=4,
                             use_atr=True, atr_mult=1.5, use_trailing=False,
                             trade_direction="BUY_ONLY", leverage=500.0)

print("\n--- 2. CONFIGURAÇÃO IMAGEM 1: APENAS COMPRAS (COM TP FIXO $3.00 / SEM TRAILING) ---")
for k, v in c2.items():
    print(f"  {k}: {v}")

# 3. Configuração Imagem 2: Ambas Direções com EMA 200 (COM TRAILING STOP)
c3 = run_detailed_margin_sim(df, balance_init=100.0, initial_lot=0.01, target_side=3.0, target_global=15.0,
                             base_dist_pts=300, lot_mult=1.2, max_martingale=3, max_orders=4,
                             use_atr=True, atr_mult=1.5, use_trailing=True, trailing_start=5.0, trailing_drop_pct=10.0,
                             trade_direction="EMA_BOTH", leverage=500.0)

print("\n--- 3. CONFIGURAÇÃO IMAGEM 2: AMBAS DIREÇÕES COM EMA 200 (COM TRAILING STOP) ---")
for k, v in c3.items():
    print(f"  {k}: {v}")

# 4. Configuração Imagem 2: Ambas Direções com EMA 200 (COM TP FIXO $3.00)
c4 = run_detailed_margin_sim(df, balance_init=100.0, initial_lot=0.01, target_side=3.0, target_global=15.0,
                             base_dist_pts=300, lot_mult=1.2, max_martingale=3, max_orders=4,
                             use_atr=True, atr_mult=1.5, use_trailing=False,
                             trade_direction="EMA_BOTH", leverage=500.0)

print("\n--- 4. CONFIGURAÇÃO IMAGEM 2: AMBAS DIREÇÕES COM EMA 200 (COM TP FIXO $3.00) ---")
for k, v in c4.items():
    print(f"  {k}: {v}")

# 5. OTIMIZADA PARA $100 COM ALAVANCAGEM 1:500: Ambas Direções com Distância Base 600 pts ($6.00) e TP Fixo $3.00
c5 = run_detailed_margin_sim(df, balance_init=100.0, initial_lot=0.01, target_side=3.0, target_global=15.0,
                             base_dist_pts=600, lot_mult=1.2, max_martingale=3, max_orders=4,
                             use_atr=True, atr_mult=1.5, use_trailing=False,
                             trade_direction="EMA_BOTH", leverage=500.0)

print("\n--- 5. OTIMIZAÇÃO DE MARGEM PARA $100: AMBAS DIREÇÕES COM DISTÂNCIA 600 PONTOS ($6.00) ---")
for k, v in c5.items():
    print(f"  {k}: {v}")
