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


# Vamos corrigir também a reentrada múltipla dentro da mesma perna OHLC (em M15 OHLC você não sabe quantas vezes o preço oscilou, 
# mas se reabrir imediatamente no meio da mesma perna sintética L->H você está transformando um TP fixo de $3 em captura total da vela High-Low em fatias de $3!)
def run_Strict_Single_Fill_Per_Bar(df_sub, mode="BUY_ONLY", base_dist_pts=300, apply_real_costs=True):
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
    total_swap = 0.0
    total_comm = 0.0
    stopped_out = False
    stop_out_date = None
    last_day = None

    for row in df_sub.itertuples():
        o, h, l, c = row.open, row.high, row.low, row.close
        bar_time = row.time
        atr = row.atr_clean
        ema = row.ema200_clean
        bar_spread = max(0.20, row.spread * point) if apply_real_costs else 0.20
        dyn_dist = max(base_dist / 2.0, atr * 1.5)

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

        # 1. Na abertura da barra (Open): abre Giro inicial se cesto estiver vazio
        ask_o = o + bar_spread
        bid_o = o
        can_buy = True if mode == "BUY_ONLY" else (ask_o >= ema)
        can_sell = False if mode == "BUY_ONLY" else (bid_o <= ema)

        if len(buy_positions) == 0 and can_buy:
            comm = 0.01 * commission_per_lot
            total_comm += comm
            buy_positions.append({'price': ask_o + slippage_usd, 'volume': 0.01, 'swap': 0.0, 'comm': -comm})
        if len(sell_positions) == 0 and can_sell:
            comm = 0.01 * commission_per_lot
            total_comm += comm
            sell_positions.append({'price': bid_o - slippage_usd, 'volume': 0.01, 'swap': 0.0, 'comm': -comm})

        # 2. Excursão Adversa Primeiro (Low para Compras, High para Vendas) -> Aciona níveis de grade e verifica Stop-Out
        ask_l = l + bar_spread
        bid_l = l
        while len(buy_positions) > 0 and len(buy_positions) < 4:
            lowest_buy = min(p['price'] for p in buy_positions)
            trigger_ask = lowest_buy - dyn_dist
            if ask_l <= trigger_ask:
                fill_p = min(ask_o, trigger_ask) + slippage_usd
                comm = 0.01 * commission_per_lot
                total_comm += comm
                buy_positions.append({'price': fill_p, 'volume': 0.01, 'swap': 0.0, 'comm': -comm})
            else:
                break

        bid_h = h
        ask_h = h + bar_spread
        while len(sell_positions) > 0 and len(sell_positions) < 4:
            highest_sell = max(p['price'] for p in sell_positions)
            trigger_bid = highest_sell + dyn_dist
            if bid_h >= trigger_bid:
                fill_p = max(bid_o, trigger_bid) - slippage_usd
                comm = 0.01 * commission_per_lot
                total_comm += comm
                sell_positions.append({'price': fill_p, 'volume': 0.01, 'swap': 0.0, 'comm': -comm})
            else:
                break

        # Avalia pior Equity intrabarra (no fundo L para compras e topo H para vendas)
        worst_buy_p = sum(((bid_l - slippage_usd - p['price']) * p['volume'] * contract_size) + p['swap'] + p['comm'] for p in buy_positions)
        worst_sell_p = sum(((p['price'] - (ask_h + slippage_usd)) * p['volume'] * contract_size) + p['swap'] + p['comm'] for p in sell_positions)
        worst_floating = worst_buy_p + worst_sell_p
        worst_equity = balance + worst_floating

        if worst_equity < min_equity:
            min_equity = worst_equity
        dd = peak_equity - worst_equity
        if dd > max_dd_usd:
            max_dd_usd = dd
            max_dd_pct = (max_dd_usd / peak_equity) * 100.0

        tot_lots = max(sum(p['volume'] for p in buy_positions), sum(p['volume'] for p in sell_positions))
        margin_used = (tot_lots * contract_size * l) / leverage if tot_lots > 0 else 0.0
        if margin_used > 0:
            if worst_equity <= 0 or (worst_equity / margin_used) * 100.0 <= stop_out_pct:
                stopped_out = True
                stop_out_date = bar_time
                balance = max(0.0, worst_equity)
                buy_positions.clear()
                sell_positions.clear()
                break

        # 3. Excursão Favorável (High para Compras, Low para Vendas) -> Verifica se atingiu Take Profit ($3.00)
        best_buy_p = sum(((bid_h - slippage_usd - p['price']) * p['volume'] * contract_size) + p['swap'] + p['comm'] for p in buy_positions)
        if best_buy_p >= 3.0 and len(buy_positions) > 0:
            balance += 3.0
            total_trades += len(buy_positions)
            buy_positions.clear()

        best_sell_p = sum(((p['price'] - (ask_l + slippage_usd)) * p['volume'] * contract_size) + p['swap'] + p['comm'] for p in sell_positions)
        if best_sell_p >= 3.0 and len(sell_positions) > 0:
            balance += 3.0
            total_trades += len(sell_positions)
            sell_positions.clear()

        if balance > peak_equity:
            peak_equity = balance

    final_floating = sum(((c - p['price']) * p['volume'] * contract_size) + p['swap'] + p['comm'] for p in buy_positions) + \
                     sum(((p['price'] - c) * p['volume'] * contract_size) + p['swap'] + p['comm'] for p in sell_positions)
    final_eq = balance + final_floating
    return {
        'SaldoFinal': round(final_eq, 2),
        'LucroUSD': round(final_eq - 100.0, 2),
        'MaxDD_USD': round(max_dd_usd, 2),
        'MaxDD_Pct': round(max_dd_pct, 2),
        'MinEquity': round(min_equity, 2),
        'StopOut': stopped_out,
        'StopOutDate': str(stop_out_date) if stop_out_date else "Nenhum",
        'Trades': total_trades,
        'SwapUSD': round(total_swap, 2),
        'CommUSD': round(-total_comm, 2)
    }

print("=== SIMULAÇÃO ESTRITAMENTE CAUSAL (SEM MÚLTIPLOS SCALPS POR VELA DE 15 MIN) ===")
for m_name, m_code, d_pts in [
    ("Buy-Only (Dist 300) - Início Fev/2024", "BUY_ONLY", 300),
    ("Buy-Only (Dist 600) - Início Fev/2024", "BUY_ONLY", 600),
    ("EMA 200 Ambas (Dist 600) - Início Fev/2024", "EMA_BOTH", 600),
]:
    res = run_Strict_Single_Fill_Per_Bar(df, mode=m_code, base_dist_pts=d_pts, apply_real_costs=True)
    print(f"  {m_name:42s} => Saldo Final: ${res['SaldoFinal']:>8} | MaxDD: ${res['MaxDD_USD']:>7} ({res['MaxDD_Pct']:>5}%) | MinEq: ${res['MinEquity']:>6} | StopOut: {res['StopOut']} ({res['StopOutDate']}) | Trades: {res['Trades']} | Swap: ${res['SwapUSD']} | Comm: ${res['CommUSD']}")

print("\n=== TESTE DE SOBREVIVÊNCIA POR MÊS DE PARTIDA ($100 INICIAIS EM CADA MÊS) - BUY_ONLY (Dist 300) ===")
months = pd.date_range('2024-02-01', '2026-09-01', freq='MS')
survived_count = 0
blown_count = 0
for m in months:
    sub = df[df['time'] >= m]
    if len(sub) < 100: continue
    r = run_Strict_Single_Fill_Per_Bar(sub, mode="BUY_ONLY", base_dist_pts=300, apply_real_costs=True)
    if r['StopOut']:
        blown_count += 1
    else:
        survived_count += 1
    print(f"  Início {m.strftime('%Y-%m')} | Saldo Final: ${r['SaldoFinal']:>7} | StopOut: {str(r['StopOut']):5s} ({r['StopOutDate']}) | MaxDD: ${r['MaxDD_USD']:>7}")

print(f"\nResumo Janelas Mensais ($100 iniciais): Quebraram (Stop-Out) = {blown_count}/{blown_count+survived_count} ({blown_count/(blown_count+survived_count)*100:.1f}%) | Sobreviveram = {survived_count}/{blown_count+survived_count}")
