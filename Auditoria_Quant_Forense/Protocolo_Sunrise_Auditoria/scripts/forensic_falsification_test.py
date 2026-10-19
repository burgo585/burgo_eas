import datetime
import numpy as np
import pandas as pd
import MetaTrader5 as mt5

if not mt5.initialize(path=r"C:\MetaTrader\terminal64.exe"):
    raise RuntimeError("MT5 init failed")

utc_from = datetime.datetime(2024, 1, 1)
utc_to = datetime.datetime(2026, 10, 19, 23, 59)
rates = mt5.copy_rates_range("XAUUSD-ECN", mt5.TIMEFRAME_M15, utc_from, utc_to)
mt5.shutdown()

df = pd.DataFrame(rates)
df['time'] = pd.to_datetime(df['time'], unit='s')

# Indicadores SEM shift (com lookahead, como estava nos scripts anteriores)
high_low = df['high'] - df['low']
high_close = (df['high'] - df['close'].shift()).abs()
low_close = (df['low'] - df['close'].shift()).abs()
tr = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
df['atr_leaky'] = tr.rolling(window=14).mean().bfill()
df['ema200_leaky'] = df['close'].ewm(span=200, adjust=False).mean()

# Indicadores CORRETOS (shift(1) = barra anterior fechada, sem lookahead)
df['atr_clean'] = df['atr_leaky'].shift(1).bfill()
df['ema200_clean'] = df['ema200_leaky'].shift(1).bfill()


def run_Causal_Audit_Sim(df,
                         mode="EMA_BOTH",
                         base_dist_pts=600,
                         initial_lot=0.01,
                         lot_mult=1.2,
                         max_martingale=3,
                         max_orders=4,
                         target_side=3.0,
                         target_global=15.0,
                         fix_lookahead=True,
                         fix_wick_tp=True,
                         fix_grid_fill=True,
                         adverse_intrabar=True,
                         apply_real_costs=True,
                         lag_1bar=False):
    balance_init = 100.0
    balance = balance_init
    peak_equity = balance
    min_equity = balance
    max_dd_usd = 0.0
    max_dd_pct = 0.0
    
    contract_size = 100.0
    point = 0.01
    base_dist = base_dist_pts * point
    leverage = 500.0
    stop_out_pct = 20.0
    
    # Custos reais do XAUUSD-ECN (VTMarkets-Demo + padrão ECN)
    commission_per_lot = 6.00 if apply_real_costs else 0.0  # $6.00 por lote padrão round-turn ($0.06 por 0.01 lote)
    slippage_usd = 0.10 if apply_real_costs else 0.0        # 10 pontos ($0.10) de slippage de execução no Ouro
    swap_long_pts = -77.44 if apply_real_costs else 0.0     # -77.44 pontos/lote/noite ($0.7744 por 0.01 lote)
    swap_short_pts = 36.70 if apply_real_costs else 0.0     # +36.70 pontos/lote/noite
    
    buy_positions = []
    sell_positions = []
    
    total_trades = 0
    recycled_orders = 0
    total_commission_paid = 0.0
    total_swap_paid = 0.0
    stopped_out = False
    stop_out_date = None
    
    last_day = None
    pending_buy_signal = False
    pending_sell_signal = False
    
    def norm_lot(vol):
        return max(0.01, round(vol, 2))

    for row in df.itertuples():
        o, h, l, c = row.open, row.high, row.low, row.close
        bar_time = row.time
        atr = row.atr_clean if fix_lookahead else row.atr_leaky
        ema = row.ema200_clean if fix_lookahead else row.ema200_leaky
        
        # Spread real da barra (mínimo $0.20, mais alargamento real se houver)
        bar_spread = max(0.20, row.spread * point) if apply_real_costs else 0.20
        
        dyn_dist = max(base_dist / 2.0, atr * 1.5)
        
        # Cobrança de Swap Diário na virada de dia (00:00 servidor)
        cur_day = bar_time.date()
        if last_day is not None and cur_day != last_day and apply_real_costs:
            # Quarta-feira para Quinta-feira cobra Swap Triplo (rollover3days = 3)
            mult_swap = 3.0 if last_day.weekday() == 2 else 1.0
            for bp in buy_positions:
                sw = (swap_long_pts * point * contract_size) * bp['volume'] * mult_swap
                bp['swap'] = bp.get('swap', 0.0) + sw
                total_swap_paid += sw
            for sp in sell_positions:
                sw = (swap_short_pts * point * contract_size) * sp['volume'] * mult_swap
                sp['swap'] = sp.get('swap', 0.0) + sw
                total_swap_paid += sw
        last_day = cur_day

        # Se usarmos o modo ingênuo antigo:
        if not fix_grid_fill and not fix_wick_tp and not adverse_intrabar:
            price_steps = [o, l, h, c] if c >= o else [o, h, l, c]
        else:
            # Discretização densa da barra em passos de $0.25 para capturar cada gatilho exato de grade, TP e Stop-Out
            # Pior caso conservador: testa a excursão adversa antes da favorável
            if adverse_intrabar:
                # Se tem mais compras do que vendas, vai ao Low antes do High para testar Stop-Out real antes de dar TP
                if sum(p['volume'] for p in buy_positions) >= sum(p['volume'] for p in sell_positions):
                    legs = [(o, l), (l, h), (h, c)]
                else:
                    legs = [(o, h), (h, l), (l, c)]
            else:
                legs = [(o, l), (l, h), (h, c)] if c >= o else [(o, h), (h, l), (l, c)]
                
            price_steps = []
            for p_start, p_end in legs:
                dist_leg = abs(p_end - p_start)
                n_steps = max(2, int(dist_leg / 0.50) + 1)
                price_steps.extend(np.linspace(p_start, p_end, n_steps))

        for price in price_steps:
            if fix_grid_fill:
                # Barras do MT5 são BID! Ask = Bid + Spread
                bid = price
                ask = price + bar_spread
            else:
                ask = price + (bar_spread / 2.0)
                bid = price - (bar_spread / 2.0)

            # 1. Se fix_grid_fill está ativo, abre TODAS as ordens de grade cujos níveis foram rompidos ANTES de medir o drawdown no fundo!
            if fix_grid_fill:
                while len(buy_positions) > 0 and len(buy_positions) < max_orders:
                    lowest_buy = min(p['price'] for p in buy_positions)
                    trigger_ask = lowest_buy - dyn_dist
                    if ask <= trigger_ask:
                        last_vol = [p['volume'] for p in buy_positions if p['price'] == lowest_buy][0]
                        next_lot = norm_lot(last_vol * lot_mult) if len(buy_positions) < max_martingale else last_vol
                        fill_price = max(ask, trigger_ask) + slippage_usd
                        comm = next_lot * commission_per_lot
                        total_commission_paid += comm
                        buy_positions.append({'price': fill_price, 'volume': next_lot, 'swap': 0.0, 'comm': -comm})
                    else:
                        break

                while len(sell_positions) > 0 and len(sell_positions) < max_orders:
                    highest_sell = max(p['price'] for p in sell_positions)
                    trigger_bid = highest_sell + dyn_dist
                    if bid >= trigger_bid:
                        last_vol = [p['volume'] for p in sell_positions if p['price'] == highest_sell][0]
                        next_lot = norm_lot(last_vol * lot_mult) if len(sell_positions) < max_martingale else last_vol
                        fill_price = min(bid, trigger_bid) - slippage_usd
                        comm = next_lot * commission_per_lot
                        total_commission_paid += comm
                        sell_positions.append({'price': fill_price, 'volume': next_lot, 'swap': 0.0, 'comm': -comm})
                    else:
                        break

            # Calcula lucro flutuante (incluindo swap e comissão acumulados nas posições abertas, igual ao MQL5!)
            buy_profit = sum(((bid - slippage_usd - pos['price']) * pos['volume'] * contract_size) + pos.get('swap', 0.0) + pos.get('comm', 0.0) for pos in buy_positions)
            sell_profit = sum(((pos['price'] - (ask + slippage_usd)) * pos['volume'] * contract_size) + pos.get('swap', 0.0) + pos.get('comm', 0.0) for pos in sell_positions)
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

            # Verificação de Stop Out (20% Margin Level)
            tot_buy_lots = sum(p['volume'] for p in buy_positions)
            tot_sell_lots = sum(p['volume'] for p in sell_positions)
            tot_lots = max(tot_buy_lots, tot_sell_lots) if (tot_buy_lots > 0 and tot_sell_lots > 0) else (tot_buy_lots + tot_sell_lots)
            margin_used = (tot_lots * contract_size * price) / leverage if tot_lots > 0 else 0.0

            if margin_used > 0:
                margin_level = (equity / margin_used) * 100.0
                if equity <= 0 or margin_level <= stop_out_pct:
                    stopped_out = True
                    stop_out_date = bar_time
                    balance = max(0.0, equity)
                    buy_positions.clear()
                    sell_positions.clear()
                    break

            # Fechamento Global
            if total_floating >= target_global:
                realized = target_global if fix_wick_tp else total_floating
                balance += realized
                total_trades += len(buy_positions) + len(sell_positions)
                buy_positions.clear()
                sell_positions.clear()
                continue

            # Reciclagem Ativa
            if buy_profit >= target_side and len(sell_positions) > 0:
                capped_buy_p = target_side if fix_wick_tp else buy_profit
                best_cand_idx = -1
                best_cand_loss = 0.0
                for idx, sp in enumerate(sell_positions):
                    p_loss = ((sp['price'] - (ask + slippage_usd)) * sp['volume'] * contract_size) + sp.get('swap', 0.0) + sp.get('comm', 0.0)
                    if p_loss < 0 and capped_buy_p >= abs(p_loss):
                        if best_cand_idx == -1 or abs(p_loss) > abs(best_cand_loss):
                            best_cand_idx = idx
                            best_cand_loss = p_loss
                if best_cand_idx != -1:
                    balance += capped_buy_p + best_cand_loss
                    total_trades += len(buy_positions) + 1
                    recycled_orders += 1
                    buy_positions.clear()
                    sell_positions.pop(best_cand_idx)
                    continue

            if sell_profit >= target_side and len(buy_positions) > 0:
                capped_sell_p = target_side if fix_wick_tp else sell_profit
                best_cand_idx = -1
                best_cand_loss = 0.0
                for idx, bp in enumerate(buy_positions):
                    p_loss = ((bid - slippage_usd - bp['price']) * bp['volume'] * contract_size) + bp.get('swap', 0.0) + bp.get('comm', 0.0)
                    if p_loss < 0 and capped_sell_p >= abs(p_loss):
                        if best_cand_idx == -1 or abs(p_loss) > abs(best_cand_loss):
                            best_cand_idx = idx
                            best_cand_loss = p_loss
                if best_cand_idx != -1:
                    balance += capped_sell_p + best_cand_loss
                    total_trades += len(sell_positions) + 1
                    recycled_orders += 1
                    sell_positions.clear()
                    buy_positions.pop(best_cand_idx)
                    continue

            # Fechamento de Lado
            if buy_profit >= target_side:
                realized = target_side if fix_wick_tp else buy_profit
                balance += realized
                total_trades += len(buy_positions)
                buy_positions.clear()
                continue

            if sell_profit >= target_side:
                realized = target_side if fix_wick_tp else sell_profit
                balance += realized
                total_trades += len(sell_positions)
                sell_positions.clear()
                continue

            # Abertura de Giro Inicial
            if mode == "BUY_ONLY":
                can_buy, can_sell = True, False
            elif mode == "EMA_BOTH":
                can_buy = (ask >= ema)
                can_sell = (bid <= ema)
            else:
                can_buy, can_sell = True, True

            if lag_1bar:
                # Só abre na abertura da barra se o sinal estava ativo na barra anterior
                if price == price_steps[0]:
                    if len(buy_positions) == 0 and pending_buy_signal:
                        comm = initial_lot * commission_per_lot
                        total_commission_paid += comm
                        buy_positions.append({'price': ask + slippage_usd, 'volume': initial_lot, 'swap': 0.0, 'comm': -comm})
                    if len(sell_positions) == 0 and pending_sell_signal:
                        comm = initial_lot * commission_per_lot
                        total_commission_paid += comm
                        sell_positions.append({'price': bid - slippage_usd, 'volume': initial_lot, 'swap': 0.0, 'comm': -comm})
            else:
                if len(buy_positions) == 0 and can_buy:
                    comm = initial_lot * commission_per_lot
                    total_commission_paid += comm
                    buy_positions.append({'price': ask + slippage_usd, 'volume': initial_lot, 'swap': 0.0, 'comm': -comm})
                if len(sell_positions) == 0 and can_sell:
                    comm = initial_lot * commission_per_lot
                    total_commission_paid += comm
                    sell_positions.append({'price': bid - slippage_usd, 'volume': initial_lot, 'swap': 0.0, 'comm': -comm})

            # Se fix_grid_fill for False (comportamento antigo bugado):
            if not fix_grid_fill:
                if len(buy_positions) > 0 and len(buy_positions) < max_orders:
                    lowest_buy = min(p['price'] for p in buy_positions)
                    if ask < (lowest_buy - dyn_dist):
                        last_vol = [p['volume'] for p in buy_positions if p['price'] == lowest_buy][0]
                        next_lot = norm_lot(last_vol * lot_mult) if len(buy_positions) < max_martingale else last_vol
                        buy_positions.append({'price': ask, 'volume': next_lot, 'swap': 0.0, 'comm': 0.0})

                if len(sell_positions) > 0 and len(sell_positions) < max_orders:
                    highest_sell = max(p['price'] for p in sell_positions)
                    if bid > (highest_sell + dyn_dist):
                        last_vol = [p['volume'] for p in sell_positions if p['price'] == highest_sell][0]
                        next_lot = norm_lot(last_vol * lot_mult) if len(sell_positions) < max_martingale else last_vol
                        sell_positions.append({'price': bid, 'volume': next_lot, 'swap': 0.0, 'comm': 0.0})

        pending_buy_signal = (c >= ema) if mode == "EMA_BOTH" else True
        pending_sell_signal = (c <= ema) if mode == "EMA_BOTH" else (False if mode == "BUY_ONLY" else True)

        if stopped_out:
            break

    final_floating = sum(((c - pos['price']) * pos['volume'] * contract_size) + pos.get('swap', 0.0) + pos.get('comm', 0.0) for pos in buy_positions) + \
                     sum(((pos['price'] - c) * pos['volume'] * contract_size) + pos.get('swap', 0.0) + pos.get('comm', 0.0) for pos in sell_positions)
    final_balance = balance + final_floating

    return {
        'SaldoFinal': round(final_balance, 2),
        'LucroUSD': round(final_balance - balance_init, 2),
        'MaxDD_USD': round(max_dd_usd, 2),
        'MaxDD_Pct': round(max_dd_pct, 2),
        'MinEquity': round(min_equity, 2),
        'StopOut': stopped_out,
        'StopOutDate': str(stop_out_date) if stop_out_date else "Nenhum",
        'Trades': total_trades,
        'Recicladas': recycled_orders,
        'SwapPagoUSD': round(total_swap_paid, 2),
        'ComissaoPagaUSD': round(-total_commission_paid, 2)
    }

print("================================================================================")
print("ETAPA 5: TESTE DE FALSIFICAÇÃO PASSO A PASSO (DESMONTANDO A ILUSÃO DE BACKTEST)")
print("================================================================================")

for mode_label, mode_val, dist_val in [
    ("MODO 1: Ambas Direções + EMA 200 (Dist 600 - Alegação $100 -> $18.831)", "EMA_BOTH", 600),
    ("MODO 2: Apenas Compras / Buy-Only (Dist 300 - Alegação $100 -> $37.397)", "BUY_ONLY", 300),
    ("MODO 3: Apenas Compras / Buy-Only (Dist 600)", "BUY_ONLY", 600)
]:
    print(f"\n>>> {mode_label} <<<")
    # 0. Simulador Original Ingênuo (Ilusão de Backtest)
    s0 = run_Causal_Audit_Sim(df, mode=mode_val, base_dist_pts=dist_val,
                              fix_lookahead=False, fix_wick_tp=False, fix_grid_fill=False, adverse_intrabar=False, apply_real_costs=False, lag_1bar=False)
    print(f"  [0. Simulador Original Ingênuo]            Saldo: ${s0['SaldoFinal']:>9} | MaxDD: ${s0['MaxDD_USD']:>7} ({s0['MaxDD_Pct']:>5}%) | MinEq: ${s0['MinEquity']:>6} | StopOut: {s0['StopOut']} ({s0['StopOutDate']}) | Trades: {s0['Trades']}")

    # 1. Corrigindo APENAS o Teletransporte de TP para a Máxima do Pavio (fix_wick_tp=True)
    s1 = run_Causal_Audit_Sim(df, mode=mode_val, base_dist_pts=dist_val,
                              fix_lookahead=False, fix_wick_tp=True, fix_grid_fill=False, adverse_intrabar=False, apply_real_costs=False, lag_1bar=False)
    print(f"  [1. + Fix Teletransporte TP no Pavio]      Saldo: ${s1['SaldoFinal']:>9} | MaxDD: ${s1['MaxDD_USD']:>7} ({s1['MaxDD_Pct']:>5}%) | MinEq: ${s1['MinEquity']:>6} | StopOut: {s1['StopOut']} ({s1['StopOutDate']}) | Trades: {s1['Trades']}")

    # 2. Corrigindo TAMBÉM o Preenchimento da Grade e Ordem Intrabarra (fix_grid_fill=True, adverse_intrabar=True)
    s2 = run_Causal_Audit_Sim(df, mode=mode_val, base_dist_pts=dist_val,
                              fix_lookahead=True, fix_wick_tp=True, fix_grid_fill=True, adverse_intrabar=True, apply_real_costs=False, lag_1bar=False)
    print(f"  [2. + Fix Grade Real + Sem Lookahead]      Saldo: ${s2['SaldoFinal']:>9} | MaxDD: ${s2['MaxDD_USD']:>7} ({s2['MaxDD_Pct']:>5}%) | MinEq: ${s2['MinEquity']:>6} | StopOut: {s2['StopOut']} ({s2['StopOutDate']}) | Trades: {s2['Trades']}")

    # 3. Adicionando Custos Reais (Swap MT5 -77.44 pts, Comissão $6/lot, Slippage $0.10) + Lag 1 Barra
    s3 = run_Causal_Audit_Sim(df, mode=mode_val, base_dist_pts=dist_val,
                              fix_lookahead=True, fix_wick_tp=True, fix_grid_fill=True, adverse_intrabar=True, apply_real_costs=True, lag_1bar=True)
    print(f"  [3. + Fricção Real (Swap+Comm+Slip+Lag)]   Saldo: ${s3['SaldoFinal']:>9} | MaxDD: ${s3['MaxDD_USD']:>7} ({s3['MaxDD_Pct']:>5}%) | MinEq: ${s3['MinEquity']:>6} | StopOut: {s3['StopOut']} ({s3['StopOutDate']}) | Trades: {s3['Trades']} | Swap: ${s3['SwapPagoUSD']} | Comm: ${s3['ComissaoPagaUSD']}")
