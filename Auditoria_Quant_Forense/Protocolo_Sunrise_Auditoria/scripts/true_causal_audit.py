import pandas as pd
import numpy as np
from run_xauusd_tests import get_xauusd_data

df = get_xauusd_data()
high_low = df['high'] - df['low']
high_close = (df['high'] - df['close'].shift()).abs()
low_close = (df['low'] - df['close'].shift()).abs()
tr = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
df['atr_clean'] = tr.rolling(window=14).mean().shift(1).bfill()
df['ema200_clean'] = df['close'].ewm(span=200, adjust=False).mean().shift(1).bfill()

def run_True_Causal_Sim(df_sub,
                        mode="BUY_ONLY",
                        base_dist_pts=300,
                        initial_lot=0.01,
                        lot_mult=1.2,
                        max_martingale=3,
                        max_orders=4,
                        target_side=3.0,
                        target_global=15.0,
                        apply_real_costs=True,
                        conservative_green_bar=True):
    """
    Simulador Estritamente Causal (Sem viagem no tempo dentro da barra):
    - Em vela de BAIXA (c < o): Caminho temporal físico: Open -> High -> Low -> Close.
      * Ordens de compra já abertas ANTES da queda podem bater TP no High inicial.
      * Ordens de grade abertas DURANTE a queda para o Low NUNCA podem fechar no High (que já passou!), só podem ser avaliadas no Close!
    - Em vela de ALTA (c >= o):
      * Se conservative_green_bar=True (Pior Caso / Sem Viés Otimista): Caminho Open -> High -> Low -> Close (evita comprar o fundo do pavio Low e vender no topo High dentro da mesma vela de 15m).
      * Se conservative_green_bar=False: Caminho Open -> Low -> High -> Close, mas preenchendo a grade no trigger_price exato e limitando o TP a $3.00.
    """
    balance = 100.0
    peak_equity = 100.0
    min_equity = 100.0
    max_dd_usd = 0.0
    max_dd_pct = 0.0
    
    contract_size = 100.0
    point = 0.01
    base_dist = base_dist_pts * point
    leverage = 500.0
    stop_out_pct = 20.0
    
    commission_per_lot = 6.00 if apply_real_costs else 0.0
    slippage_usd = 0.10 if apply_real_costs else 0.0
    swap_long_pts = -77.44 if apply_real_costs else 0.0
    swap_short_pts = 36.70 if apply_real_costs else 0.0
    
    buy_positions = []
    sell_positions = []
    
    total_trades = 0
    recycled_orders = 0
    total_swap = 0.0
    total_comm = 0.0
    stopped_out = False
    stop_out_date = None
    last_day = None

    def norm_lot(vol):
        return max(0.01, round(vol, 2))

    def eval_step(price_bid, bar_spread, dyn_dist, ema, allow_new_giro, bar_time):
        nonlocal balance, peak_equity, min_equity, max_dd_usd, max_dd_pct
        nonlocal total_trades, recycled_orders, total_comm, stopped_out, stop_out_date

        bid = price_bid
        ask = price_bid + bar_spread

        # 1. Abre ordens de grade se o preço rompeu níveis (em sequência causal ao longo do movimento)
        while len(buy_positions) > 0 and len(buy_positions) < max_orders:
            lowest_buy = min(p['price'] for p in buy_positions)
            trigger_ask = lowest_buy - dyn_dist
            if ask <= trigger_ask:
                last_vol = [p['volume'] for p in buy_positions if p['price'] == lowest_buy][0]
                next_lot = norm_lot(last_vol * lot_mult) if len(buy_positions) < max_martingale else last_vol
                fill_p = max(ask, trigger_ask) + slippage_usd
                comm = next_lot * commission_per_lot
                total_comm += comm
                buy_positions.append({'price': fill_p, 'volume': next_lot, 'swap': 0.0, 'comm': -comm})
            else:
                break

        while len(sell_positions) > 0 and len(sell_positions) < max_orders:
            highest_sell = max(p['price'] for p in sell_positions)
            trigger_bid = highest_sell + dyn_dist
            if bid >= trigger_bid:
                last_vol = [p['volume'] for p in sell_positions if p['price'] == highest_sell][0]
                next_lot = norm_lot(last_vol * lot_mult) if len(sell_positions) < max_martingale else last_vol
                fill_p = min(bid, trigger_bid) - slippage_usd
                comm = next_lot * commission_per_lot
                total_comm += comm
                sell_positions.append({'price': fill_p, 'volume': next_lot, 'swap': 0.0, 'comm': -comm})
            else:
                break

        # 2. Avalia Lucro Flutuante e Equidade neste ponto exato do tempo
        buy_p = sum(((bid - slippage_usd - p['price']) * p['volume'] * contract_size) + p['swap'] + p['comm'] for p in buy_positions)
        sell_p = sum(((p['price'] - (ask + slippage_usd)) * p['volume'] * contract_size) + p['swap'] + p['comm'] for p in sell_positions)
        tot_float = buy_p + sell_p
        eq = balance + tot_float

        if eq < min_equity:
            min_equity = eq
        if eq > peak_equity:
            peak_equity = eq
        dd = peak_equity - eq
        if dd > max_dd_usd:
            max_dd_usd = dd
            max_dd_pct = (max_dd_usd / peak_equity) * 100.0

        # 3. Verifica Stop-Out (20% Nível de Margem)
        tot_b_lots = sum(p['volume'] for p in buy_positions)
        tot_s_lots = sum(p['volume'] for p in sell_positions)
        tot_lots = max(tot_b_lots, tot_s_lots) if (tot_b_lots > 0 and tot_s_lots > 0) else (tot_b_lots + tot_s_lots)
        margin_used = (tot_lots * contract_size * bid) / leverage if tot_lots > 0 else 0.0

        if margin_used > 0:
            if eq <= 0 or (eq / margin_used) * 100.0 <= stop_out_pct:
                stopped_out = True
                stop_out_date = bar_time
                balance = max(0.0, eq)
                buy_positions.clear()
                sell_positions.clear()
                return

        # 4. Fechamento Global (Limitado ao target_global exato, sem teletransporte de pavio)
        if tot_float >= target_global and (len(buy_positions) + len(sell_positions)) > 0:
            balance += target_global
            total_trades += len(buy_positions) + len(sell_positions)
            buy_positions.clear()
            sell_positions.clear()
            if balance > peak_equity: peak_equity = balance
            return

        # 5. Reciclagem Ativa
        if buy_p >= target_side and len(sell_positions) > 0:
            best_idx = -1
            best_loss = 0.0
            for idx, sp in enumerate(sell_positions):
                pl = ((sp['price'] - (ask + slippage_usd)) * sp['volume'] * contract_size) + sp['swap'] + sp['comm']
                if pl < 0 and target_side >= abs(pl):
                    if best_idx == -1 or abs(pl) > abs(best_loss):
                        best_idx = idx
                        best_loss = pl
            if best_idx != -1:
                balance += target_side + best_loss
                total_trades += len(buy_positions) + 1
                recycled_orders += 1
                buy_positions.clear()
                sell_positions.pop(best_idx)
                if balance > peak_equity: peak_equity = balance
                return

        if sell_p >= target_side and len(buy_positions) > 0:
            best_idx = -1
            best_loss = 0.0
            for idx, bp in enumerate(buy_positions):
                pl = ((bid - slippage_usd - bp['price']) * bp['volume'] * contract_size) + bp['swap'] + bp['comm']
                if pl < 0 and target_side >= abs(pl):
                    if best_idx == -1 or abs(pl) > abs(best_loss):
                        best_idx = idx
                        best_loss = pl
            if best_idx != -1:
                balance += target_side + best_loss
                total_trades += len(sell_positions) + 1
                recycled_orders += 1
                sell_positions.clear()
                buy_positions.pop(best_idx)
                if balance > peak_equity: peak_equity = balance
                return

        # 6. Fechamento de Lado (Limitado a target_side = $3.00)
        if buy_p >= target_side and len(buy_positions) > 0:
            balance += target_side
            total_trades += len(buy_positions)
            buy_positions.clear()
            if balance > peak_equity: peak_equity = balance

        if sell_p >= target_side and len(sell_positions) > 0:
            balance += target_side
            total_trades += len(sell_positions)
            sell_positions.clear()
            if balance > peak_equity: peak_equity = balance

        # 7. Abertura de Giro Inicial (apenas quando permitido)
        if allow_new_giro:
            can_buy = True if mode == "BUY_ONLY" else (True if mode == "BOTH_OPEN" else (ask >= ema))
            can_sell = False if mode == "BUY_ONLY" else (True if mode == "BOTH_OPEN" else (bid <= ema))
            if len(buy_positions) == 0 and can_buy:
                comm = initial_lot * commission_per_lot
                total_comm += comm
                buy_positions.append({'price': ask + slippage_usd, 'volume': initial_lot, 'swap': 0.0, 'comm': -comm})
            if len(sell_positions) == 0 and can_sell:
                comm = initial_lot * commission_per_lot
                total_comm += comm
                sell_positions.append({'price': bid - slippage_usd, 'volume': initial_lot, 'swap': 0.0, 'comm': -comm})

    for row in df_sub.itertuples():
        o, h, l, c = row.open, row.high, row.low, row.close
        bar_time = row.time
        atr = row.atr_clean
        ema = row.ema200_clean
        bar_spread = max(0.20, row.spread * point) if apply_real_costs else 0.20
        dyn_dist = max(base_dist / 2.0, atr * 1.5)

        # Rollover de Swap Diário
        cur_day = bar_time.date()
        if last_day is not None and cur_day != last_day and apply_real_costs:
            mult_swap = 3.0 if last_day.weekday() == 2 else 1.0
            for bp in buy_positions:
                sw = (swap_long_pts * point * contract_size) * bp['volume'] * mult_swap
                bp['swap'] += sw
                total_swap += sw
            for sp in sell_positions:
                sw = (swap_short_pts * point * contract_size) * sp['volume'] * mult_swap
                sp['swap'] += sw
                total_swap += sw
        last_day = cur_day

        # Sequência temporal física dos 4 pontos da barra M15:
        if c < o:
            # Vela de baixa: Open -> High -> Low -> Close (NUNCA volta ao High depois do Low!)
            seq = [(o, True), (h, False), (l, False), (c, True)]
        else:
            # Vela de alta:
            if conservative_green_bar:
                # Sem viés de comprar no fundo do pavio e fechar no topo da mesma vela:
                seq = [(o, True), (h, False), (l, False), (c, True)]
            else:
                seq = [(o, True), (l, False), (h, False), (c, True)]

        for p_val, allow_giro in seq:
            eval_step(p_val, bar_spread, dyn_dist, ema, allow_giro, bar_time)
            if stopped_out:
                break
        if stopped_out:
            break

    final_floating = sum(((c - p['price']) * p['volume'] * contract_size) + p['swap'] + p['comm'] for p in buy_positions) + \
                     sum(((p['price'] - c) * p['volume'] * contract_size) + p['swap'] + p['comm'] for p in sell_positions)
    final_eq = balance + final_floating
    return {
        'SaldoFinal': round(final_eq, 2),
        'LucroUSD': round(final_eq - 100.0, 2),
        'MaxDD_USD': round(max_dd_usd, 2),
        'MaxDD_Pct': round(max_dd_pct, 2),
        'MinEquity': round(min_equity, 2),
        'PeakEquity': round(peak_equity, 2),
        'StopOut': stopped_out,
        'StopOutDate': str(stop_out_date) if stop_out_date else "Nenhum",
        'Trades': total_trades,
        'Recicladas': recycled_orders,
        'SwapUSD': round(total_swap, 2),
        'CommUSD': round(-total_comm, 2)
    }

print("================================================================================")
print("RESULTADO DO MOTOR ESTRITAMENTE CAUSAL (SEM VIAGEM NO TEMPO HIGH->LOW->HIGH)")
print("================================================================================")

configs = [
    ("1. EMA 200 Ambas (Dist 300 - Imagem 2)", "EMA_BOTH", 300),
    ("2. EMA 200 Ambas (Dist 600 - Alegação $18.831)", "EMA_BOTH", 600),
    ("3.EMA 200 Ambas (Dist 800 - Alegação $13k+)", "EMA_BOTH", 800),
    ("4. Buy-Only (Dist 300 - Imagem 1 - Alegação $37.397)", "BUY_ONLY", 300),
    ("5. Buy-Only (Dist 600)", "BUY_ONLY", 600),
    ("6. Modo Original Sem Filtro (Dist 150, Max 4 ordens)", "BOTH_OPEN", 150),
]

for label, m_code, d_pts in configs:
    r_opt = run_True_Causal_Sim(df, mode=m_code, base_dist_pts=d_pts, apply_real_costs=False, conservative_green_bar=False)
    r_real = run_True_Causal_Sim(df, mode=m_code, base_dist_pts=d_pts, apply_real_costs=True, conservative_green_bar=True)
    print(f"\n>>> {label} <<<")
    print(f"  [Causal s/ Custos (O->L->H->C em alta)] Saldo: ${r_opt['SaldoFinal']:>8} | MaxDD: ${r_opt['MaxDD_USD']:>7} ({r_opt['MaxDD_Pct']:>5}%) | StopOut: {r_opt['StopOut']} ({r_opt['StopOutDate']}) | Trades: {r_opt['Trades']}")
    print(f"  [Causal Realista c/ Custos + S/ Viés]   Saldo: ${r_real['SaldoFinal']:>8} | MaxDD: ${r_real['MaxDD_USD']:>7} ({r_real['MaxDD_Pct']:>5}%) | StopOut: {r_real['StopOut']} ({r_real['StopOutDate']}) | Trades: {r_real['Trades']} | Swap: ${r_real['SwapUSD']} | Comm: ${r_real['CommUSD']}")


print("\n================================================================================")
print("TESTE DE SOBREVIVÊNCIA EM 32 DATAS DE INÍCIO MENSAIS ($100 INICIAIS) - BUY-ONLY")
print("================================================================================")
months = pd.date_range('2024-02-01', '2026-09-01', freq='MS')
blown = 0
tot = 0
for m in months:
    sub = df[df['time'] >= m]
    if len(sub) < 100:
        continue
    tot += 1
    r = run_True_Causal_Sim(sub, mode="BUY_ONLY", base_dist_pts=300, apply_real_costs=True, conservative_green_bar=True)
    if r['StopOut']:
        blown += 1
    print(f"  Início {m.strftime('%Y-%m')} | Saldo Final: ${r['SaldoFinal']:>7} | StopOut: {str(r['StopOut']):5s} ({r['StopOutDate']}) | MaxDD: ${r['MaxDD_USD']:>7} ({r['MaxDD_Pct']:>5}%)")

print(f"\nTAXA REAL DE FALÊNCIA (STOP-OUT) PARA CONTA DE $100: {blown}/{tot} meses ({blown/tot*100:.1f}%)")
