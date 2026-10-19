from simulate_xauusd_2years import load_data, run_backtest
import pandas as pd
import datetime

pkg = load_data()

print("\n--- TEST: Com InpUseTrailingStop = False (Fechamento Fixo por Alvo $5) ---")
# Modify run_backtest to allow use_trailing=False
def test_fixed_tp(use_trailing=False, target_side=5.0, target_global=10.0, use_tf=False):
    df_m15 = pkg['df_m15']
    h1_map = pkg['h1_map']
    point = pkg['point']
    spread = pkg['spread_pts'] * point
    contract_size = pkg['contract_size']
    initial_lot = 0.02
    max_total_orders = 10
    max_allowed_lot = 1.50
    base_dist = 500 * point
    max_martingale = 6
    lot_multiplier = 1.5
    max_loss_usd = 80.0

    balance = 1000.00
    peak_balance = 1000.00
    max_drawdown_usd = 0.0

    positions = []
    ticket_counter = 1
    trade_history = []
    basket_sl_count = 0
    recycle_count = 0
    max_buy_orders = 0
    max_sell_orders = 0
    monthly_pnl = {}

    def calc_lot(last_lot, total_orders):
        if total_orders >= max_martingale: return last_lot
        step = 0.01
        nxt = last_lot * lot_multiplier
        norm = round(round(nxt / step) * step, 2)
        if norm <= last_lot: norm = round(last_lot + step, 2)
        if norm > max_allowed_lot: norm = max_allowed_lot
        return norm

    def get_pos_profit(pos, cur_bid, cur_ask):
        diff = (cur_bid - pos['price']) if pos['type'] == 'BUY' else (pos['price'] - cur_ask)
        return diff * pos['lot'] * contract_size

    for idx in range(20, len(df_m15)):
        row = df_m15.iloc[idx]
        dt = row['datetime']
        o, h, l, c = row['open'], row['high'], row['low'], row['close']

        prev_atr = df_m15['atr14'].iloc[idx-1]
        if pd.isna(prev_atr) or prev_atr <= 0: prev_atr = base_dist
        cur_dist = prev_atr * 1.5
        if cur_dist < base_dist * 0.8: cur_dist = base_dist * 0.8

        h1_t = row['h1_time']
        prev_h1_t = h1_t - datetime.timedelta(hours=1)
        h1_info = h1_map.get(prev_h1_t, {})
        ema_val = h1_info.get('ema200', None)
        h1_close = h1_info.get('close', None)

        trend_dir = 0
        if use_tf and ema_val is not None and h1_close is not None:
            if h1_close > ema_val: trend_dir = 1
            elif h1_close < ema_val: trend_dir = -1

        is_trading_time = True
        if dt.weekday() == 4 and dt.hour >= 17:
            is_trading_time = False
        else:
            mins = dt.hour * 60 + dt.minute
            if not (240 <= mins <= 1080):
                is_trading_time = False

        if c >= o:
            price_sequence = [(o, 'open'), (l, 'low'), (h, 'high'), (c, 'close')]
        else:
            price_sequence = [(o, 'open'), (h, 'high'), (l, 'low'), (c, 'close')]

        for p_val, step_type in price_sequence:
            cur_bid = p_val
            cur_ask = cur_bid + spread

            buy_positions = [p for p in positions if p['type'] == 'BUY']
            sell_positions = [p for p in positions if p['type'] == 'SELL']

            buy_profit = sum(get_pos_profit(p, cur_bid, cur_ask) for p in buy_positions)
            sell_profit = sum(get_pos_profit(p, cur_bid, cur_ask) for p in sell_positions)
            total_floating = buy_profit + sell_profit

            cur_equity = balance + total_floating
            dd = peak_balance - cur_equity
            if dd > max_drawdown_usd: max_drawdown_usd = dd

            # Basket SL
            if total_floating <= -abs(max_loss_usd):
                basket_sl_count += 1
                for p in positions:
                    prof = get_pos_profit(p, cur_bid, cur_ask)
                    balance += prof
                    trade_history.append({'time': dt, 'profit': prof, 'type': p['type'], 'reason': 'BASKET_SL'})
                    m_key = dt.strftime('%Y-%m')
                    monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + prof
                positions = []
                if balance > peak_balance: peak_balance = balance
                break

            # Global Target
            if total_floating >= target_global:
                for p in positions:
                    prof = get_pos_profit(p, cur_bid, cur_ask)
                    balance += prof
                    trade_history.append({'time': dt, 'profit': prof, 'type': p['type'], 'reason': 'GLOBAL_TP'})
                    m_key = dt.strftime('%Y-%m')
                    monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + prof
                positions = []
                if balance > peak_balance: peak_balance = balance
                break

            # Recycling
            if len(buy_positions) > 0 and len(sell_positions) > 0:
                if buy_profit >= target_side:
                    worst_sell = min(sell_positions, key=lambda p: get_pos_profit(p, cur_bid, cur_ask))
                    w_loss = get_pos_profit(worst_sell, cur_bid, cur_ask)
                    if buy_profit > abs(w_loss):
                        recycle_count += 1
                        balance += w_loss
                        trade_history.append({'time': dt, 'profit': w_loss, 'type': worst_sell['type'], 'reason': 'RECYCLE_SELL'})
                        positions = [p for p in positions if p['ticket'] != worst_sell['ticket']]
                        for p in buy_positions:
                            prof = get_pos_profit(p, cur_bid, cur_ask)
                            balance += prof
                            trade_history.append({'time': dt, 'profit': prof, 'type': p['type'], 'reason': 'RECYCLE_BUY_CLOSE'})
                        positions = [p for p in positions if p not in buy_positions]
                        buy_positions = []
                        m_key = dt.strftime('%Y-%m')
                        monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + (buy_profit + w_loss)

                elif sell_profit >= target_side and len(buy_positions) > 0:
                    worst_buy = min(buy_positions, key=lambda p: get_pos_profit(p, cur_bid, cur_ask))
                    w_loss = get_pos_profit(worst_buy, cur_bid, cur_ask)
                    if sell_profit > abs(w_loss):
                        recycle_count += 1
                        balance += w_loss
                        trade_history.append({'time': dt, 'profit': w_loss, 'type': worst_buy['type'], 'reason': 'RECYCLE_BUY'})
                        positions = [p for p in positions if p['ticket'] != worst_buy['ticket']]
                        for p in sell_positions:
                            prof = get_pos_profit(p, cur_bid, cur_ask)
                            balance += prof
                            trade_history.append({'time': dt, 'profit': prof, 'type': p['type'], 'reason': 'RECYCLE_SELL_CLOSE'})
                        positions = [p for p in positions if p not in sell_positions]
                        sell_positions = []
                        m_key = dt.strftime('%Y-%m')
                        monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + (sell_profit + w_loss)

            # Fixed Take Profit (if not trailing)
            if not use_trailing:
                if buy_profit >= target_side and len(buy_positions) > 0:
                    for p in buy_positions:
                        prof = get_pos_profit(p, cur_bid, cur_ask)
                        balance += prof
                        trade_history.append({'time': dt, 'profit': prof, 'type': p['type'], 'reason': 'BUY_TP'})
                        m_key = dt.strftime('%Y-%m')
                        monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + prof
                    positions = [p for p in positions if p not in buy_positions]
                    buy_positions = []

                if sell_profit >= target_side and len(sell_positions) > 0:
                    for p in sell_positions:
                        prof = get_pos_profit(p, cur_bid, cur_ask)
                        balance += prof
                        trade_history.append({'time': dt, 'profit': prof, 'type': p['type'], 'reason': 'SELL_TP'})
                        m_key = dt.strftime('%Y-%m')
                        monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + prof
                    positions = [p for p in positions if p not in sell_positions]
                    sell_positions = []

            if balance > peak_balance: peak_balance = balance

            # Grid Additions
            if is_trading_time:
                if len(buy_positions) > 0 and len(buy_positions) < max_total_orders:
                    lowest_buy = min(p['price'] for p in buy_positions)
                    if cur_ask < (lowest_buy - cur_dist):
                        lowest_pos = [p for p in buy_positions if p['price'] == lowest_buy][0]
                        nxt_lot = calc_lot(lowest_pos['lot'], len(buy_positions))
                        ticket_counter += 1
                        positions.append({'type': 'BUY', 'lot': nxt_lot, 'price': cur_ask, 'ticket': ticket_counter, 'time': dt})
                        buy_positions.append(positions[-1])

                if len(sell_positions) > 0 and len(sell_positions) < max_total_orders:
                    highest_sell = max(p['price'] for p in sell_positions)
                    if cur_bid > (highest_sell + cur_dist):
                        highest_pos = [p for p in sell_positions if p['price'] == highest_sell][0]
                        nxt_lot = calc_lot(highest_pos['lot'], len(sell_positions))
                        ticket_counter += 1
                        positions.append({'type': 'SELL', 'lot': nxt_lot, 'price': cur_bid, 'ticket': ticket_counter, 'time': dt})
                        sell_positions.append(positions[-1])

        # New Giro Entries at Open
        if is_trading_time:
            buy_positions = [p for p in positions if p['type'] == 'BUY']
            sell_positions = [p for p in positions if p['type'] == 'SELL']
            if len(buy_positions) == 0 and (trend_dir >= 0):
                ticket_counter += 1
                positions.append({'type': 'BUY', 'lot': initial_lot, 'price': o + spread, 'ticket': ticket_counter, 'time': dt})
            if len(sell_positions) == 0 and (trend_dir <= 0):
                ticket_counter += 1
                positions.append({'type': 'SELL', 'lot': initial_lot, 'price': o, 'ticket': ticket_counter, 'time': dt})

    df_tr = pd.DataFrame(trade_history)
    wins = df_tr[df_tr['profit'] > 0]
    losses = df_tr[df_tr['profit'] < 0]
    win_rate = (len(wins) / len(df_tr) * 100.0) if len(df_tr) > 0 else 0
    gross_profit = wins['profit'].sum() if len(wins) > 0 else 0
    gross_loss = abs(losses['profit'].sum()) if len(losses) > 0 else 0
    pf = (gross_profit / gross_loss) if gross_loss > 0 else 0

    print(f"Resultado Fixo: Saldo={balance:.2f}, Lucro={balance-1000:.2f}, WinRate={win_rate:.2f}%, PF={pf:.2f}, Trades={len(df_tr)}, StopsCesta={basket_sl_count}, Reciclagens={recycle_count}")

test_fixed_tp(use_trailing=False, target_side=5.0, target_global=10.0, use_tf=False)
test_fixed_tp(use_trailing=False, target_side=5.0, target_global=10.0, use_tf=True)
test_fixed_tp(use_trailing=False, target_side=10.0, target_global=25.0, use_tf=False)
test_fixed_tp(use_trailing=False, target_side=10.0, target_global=25.0, use_tf=True)
