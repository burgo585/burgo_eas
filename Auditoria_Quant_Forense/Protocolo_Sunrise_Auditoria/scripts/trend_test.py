import datetime
import pandas as pd
import numpy as np
from run_xauusd_tests import get_xauusd_data

df = get_xauusd_data()

# Adiciona Média Móvel Exponencial EMA 200 no M15
df['ema200'] = df['close'].ewm(span=200, adjust=False).mean()

def run_trend_test(df, allow_sell=False, use_ema=True, base_dist=800, lot_mult=1.3, max_orders=5, target_side=5.0, target_global=30.0):
    balance = 2000.0
    peak_equity = balance
    max_dd_usd = 0.0
    max_dd_pct = 0.0
    
    spread = 0.20
    contract_size = 100.0
    point = 0.01
    base_distance = base_dist * point
    
    buy_positions = []
    sell_positions = []
    
    total_trades = 0
    recycled = 0

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
                    recycled += 1
                    buy_positions.clear()
                    sell_positions.pop(best_cand_idx)
                    continue

            # Side Target
            if buy_profit >= target_side:
                balance += buy_profit
                total_trades += len(buy_positions)
                buy_positions.clear()
                continue
            if sell_profit >= target_side:
                balance += sell_profit
                total_trades += len(sell_positions)
                sell_positions.clear()
                continue

            # Motor de Giro filtrado por Tendência
            # Se preço > EMA 200: Permite Compra
            # Se preço < EMA 200: Permite Venda
            can_buy = (price >= ema) if use_ema else True
            can_sell = (price <= ema) if (use_ema and allow_sell) else allow_sell

            if len(buy_positions) == 0 and can_buy:
                buy_positions.append({'price': ask, 'volume': 0.01})
            if len(sell_positions) == 0 and can_sell:
                sell_positions.append({'price': bid, 'volume': 0.01})

            # Grade
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
        'MaxDD_USD': round(max_dd_usd, 2),
        'MaxDD_Pct': round(max_dd_pct, 2),
        'Trades': total_trades,
        'Recycled': recycled
    }

print("=== TESTE COM FILTRO DIRECIONAL DE TENDÊNCIA NO XAUUSD (2.6 ANOS) ===")
# 1. Apenas Compras (Buy-Only) a favor da super-alta do Ouro
res_buy_only = run_trend_test(df, allow_sell=False, use_ema=False, base_dist=800, lot_mult=1.2, max_orders=4, target_side=4.0)
print("1. Apenas Compra (Sem Venda contra o rali):", res_buy_only)

# 2. Compra com Filtro EMA 200
res_ema_buy = run_trend_test(df, allow_sell=False, use_ema=True, base_dist=1000, lot_mult=1.25, max_orders=5, target_side=5.0)
print("2. Apenas Compra com Filtro EMA 200:", res_ema_buy)

# 3. Ambas direções filtradas por EMA 200 (Compra se > EMA, Venda se < EMA)
res_ema_both = run_trend_test(df, allow_sell=True, use_ema=True, base_dist=1200, lot_mult=1.2, max_orders=4, target_side=5.0)
print("3. Ambas direções filtradas por EMA 200:", res_ema_both)
