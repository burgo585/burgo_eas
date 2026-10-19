import datetime
import pandas as pd
import numpy as np
from run_xauusd_tests import get_xauusd_data

df = get_xauusd_data()
df['ema200'] = df['close'].ewm(span=200, adjust=False).mean()

def run_exact_ea_sim(df, balance_init=100.0, 
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
                     spread_usd=0.20):
    
    contract_size = 100.0
    point = 0.01
    base_dist = base_dist_pts * point # 300 * 0.01 = $3.00
    trailing_drop = trailing_drop_pct / 100.0
    stop_out_level = 0.20 # 20% margem
    
    balance = balance_init
    peak_equity = balance
    min_equity = balance
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
    
    def norm_lot(vol):
        return max(0.01, round(vol, 2))

    for row in df.itertuples():
        o, h, l, c = row.open, row.high, row.low, row.close
        atr = row.atr
        ema = row.ema200
        
        # Distância dinâmica conforme o EA V40:
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
            if equity > peak_equity:
                peak_equity = equity
                
            dd = peak_equity - equity
            if dd > max_dd_usd:
                max_dd_usd = dd
                max_dd_pct = (max_dd_usd / peak_equity) * 100.0
                
            # Checagem de Stop Out / Margem
            tot_lots = sum(p['volume'] for p in buy_positions) + sum(p['volume'] for p in sell_positions)
            margin_used = (tot_lots * contract_size * price) / leverage if tot_lots > 0 else 0.0
            if margin_used > 0:
                mlvl = equity / margin_used
                if equity <= 0 or mlvl <= stop_out_level:
                    stopped_out = True
                    stop_out_date = row.time
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

            # 2. RECICLAGEM ATIVA (se houver posições em ambos os lados)
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

            # 3. FECHAMENTO INDIVIDUAL / TRAILING POR LADO
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
                # Trailing Buy
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
                # Trailing Sell
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
            elif trade_direction == "BOTH_OPEN":
                pass
                
            # Giro
            if len(buy_positions) == 0 and allow_buy:
                buy_positions.append({'price': ask, 'volume': norm_lot(initial_lot)})
            if len(sell_positions) == 0 and allow_sell:
                sell_positions.append({'price': bid, 'volume': norm_lot(initial_lot)})
                
            # Grade Buy
            if len(buy_positions) > 0 and len(buy_positions) < max_orders:
                lowest_buy = min(p['price'] for p in buy_positions)
                if ask < (lowest_buy - dyn_dist):
                    last_vol = [p['volume'] for p in buy_positions if p['price'] == lowest_buy][0]
                    next_lot = norm_lot(last_vol * lot_mult) if len(buy_positions) < max_martingale else last_vol
                    buy_positions.append({'price': ask, 'volume': next_lot})

            # Grade Sell
            if len(sell_positions) > 0 and len(sell_positions) < max_orders:
                highest_sell = max(p['price'] for p in sell_positions)
                if bid > (highest_sell + dyn_dist):
                    last_vol = [p['volume'] for p in sell_positions if p['price'] == highest_sell][0]
                    next_lot = norm_lot(last_vol * lot_mult) if len(sell_positions) < max_martingale else last_vol
                    sell_positions.append({'price': bid, 'volume': next_lot})

        if stopped_out:
            break

    # Fechamento final das posições abertas no último candle
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
        'PeakEquity': round(peak_equity, 2),
        'StopOut': stopped_out,
        'StopOutDate': str(stop_out_date) if stop_out_date else "Nenhum",
        'Trades': total_trades,
        'Recicladas': recycled_orders
    }

print("=== SIMULANDO A CONFIGURAÇÃO DA IMAGEM (XAUUSD - 2.6 ANOS / FEV 2024 - OUT 2026) ===")
print("Parâmetros:")
print("  Modo Direcional: Apenas Compras (BUY_ONLY)")
print("  Lote Inicial: 0.01")
print("  Alvo Giro (p/ limpeza): $3.00")
print("  Alvo Global: $15.00")
print("  Distância Base: 300 pontos ($3.00)")
print("  Multiplicador: 1.2")
print("  Limite Aumento (Max Martingale): 3")
print("  Máximo Ordens: 4")
print("  Usar ATR: True (Período 14, Mult 1.5)")
print("  Trailing Stop: True (Start $5.00, Drop 10%)")
print("  Horário: 00:00 às 23:59 (24h)\n")

# 1. Simulação com Banca de $100
res_100 = run_exact_ea_sim(df, balance_init=100.0,
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
                           trade_direction="BUY_ONLY")

print("[1. RESULTADO COM BANCA DE $100]:")
for k, v in res_100.items():
    print(f"  {k}: {v}")

# 2. Simulação com Banca de $2.000
res_2000 = run_exact_ea_sim(df, balance_init=2000.0,
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
                            trade_direction="BUY_ONLY")

print("\n[2. RESULTADO COM BANCA DE $2.000 (Lote 0.01)]:")
for k, v in res_2000.items():
    print(f"  {k}: {v}")

# 3. Simulação com Banca de $2.000 escalada para Lote 0.02
res_2000_002 = run_exact_ea_sim(df, balance_init=2000.0,
                                initial_lot=0.02,
                                target_side=6.0,
                                target_global=30.0,
                                base_dist_pts=300,
                                lot_mult=1.2,
                                max_martingale=3,
                                max_orders=4,
                                use_atr=True,
                                atr_mult=1.5,
                                use_trailing=True,
                                trailing_start=10.0,
                                trailing_drop_pct=10.0,
                                trade_direction="BUY_ONLY")

print("\n[3. RESULTADO COM BANCA DE $2.000 (Lote 0.02 Proporcional)]:")
for k, v in res_2000_002.items():
    print(f"  {k}: {v}")

# 4. Comparação: E se desativar o Trailing Stop (TP Fixo em $3.00)?
res_100_notrail = run_exact_ea_sim(df, balance_init=100.0,
                                   initial_lot=0.01,
                                   target_side=3.0,
                                   target_global=15.0,
                                   base_dist_pts=300,
                                   lot_mult=1.2,
                                   max_martingale=3,
                                   max_orders=4,
                                   use_atr=True,
                                   atr_mult=1.5,
                                   use_trailing=False,
                                   trade_direction="BUY_ONLY")

print("\n[4. COMPARAÇÃO COM $100: SEM TRAILING STOP (TP Fixo de $3.00)]:")
for k, v in res_100_notrail.items():
    print(f"  {k}: {v}")
