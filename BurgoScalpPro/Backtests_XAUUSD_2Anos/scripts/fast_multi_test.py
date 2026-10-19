import MetaTrader5 as mt5
import pandas as pd
import numpy as np
import datetime

def fetch_data(symbols):
    if not mt5.initialize(path=r"C:\Program Files\MetaTrader 5\terminal64.exe"):
        print("Failed to initialize MT5:", mt5.last_error())
        return None
    data = {}
    for sym in symbols:
        info = mt5.symbol_info(sym)
        if not info:
            continue
        m15 = mt5.copy_rates_from_pos(sym, mt5.TIMEFRAME_M15, 0, 10000)
        h1 = mt5.copy_rates_from_pos(sym, mt5.TIMEFRAME_H1, 0, 4000)
        m1 = mt5.copy_rates_from_pos(sym, mt5.TIMEFRAME_M1, 0, 80000)
        data[sym] = {
            'point': info.point,
            'spread': info.spread,
            'contract_size': info.trade_contract_size,
            'm15': m15,
            'h1': h1,
            'm1': m1
        }
    mt5.shutdown()
    return data

def simulate(sym, sym_data, use_trend_filter=True, base_dist_pts=500, target_side=5.0, target_global=10.0):
    point = sym_data['point']
    spread_pts = sym_data['spread']
    contract_size = sym_data['contract_size']

    df_m15 = pd.DataFrame(sym_data['m15'])
    df_m15['datetime'] = pd.to_datetime(df_m15['time'], unit='s')
    high_low = df_m15['high'] - df_m15['low']
    high_close = (df_m15['high'] - df_m15['close'].shift()).abs()
    low_close = (df_m15['low'] - df_m15['close'].shift()).abs()
    tr = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
    df_m15['atr14'] = tr.rolling(window=14).mean()

    df_h1 = pd.DataFrame(sym_data['h1'])
    df_h1['datetime'] = pd.to_datetime(df_h1['time'], unit='s')
    df_h1['ema200'] = df_h1['close'].ewm(span=200, adjust=False).mean()

    df_m1 = pd.DataFrame(sym_data['m1'])
    df_m1['datetime'] = pd.to_datetime(df_m1['time'], unit='s')
    df_m1 = df_m1.sort_values('datetime').reset_index(drop=True)

    df_m1['m15_time'] = df_m1['datetime'].dt.floor('15min')
    m15_map = df_m15.set_index('datetime')[['atr14', 'close']].to_dict('index')

    df_m1['h1_time'] = df_m1['datetime'].dt.floor('1h')
    h1_map = df_h1.set_index('datetime')[['ema200', 'close']].to_dict('index')

    initial_lot = 0.02
    target_side_usd = target_side
    target_global_usd = target_global
    base_distance = base_dist_pts * point
    lot_multiplier = 1.5
    max_martingale = 6
    max_total_orders = 10
    max_allowed_lot = 1.50
    use_max_loss_usd = True
    max_loss_usd = 80.00
    atr_multiplier = 1.5
    use_trailing = True
    trailing_start_usd = 5.00
    trailing_drop_pct = 10.0
    start_time_hour, start_time_min = 4, 0
    end_time_hour, end_time_min = 18, 0
    friday_filter = True

    balance = 1000.00
    peak_balance = 1000.00
    max_drawdown_usd = 0.0

    positions = []
    ticket_counter = 1
    max_global_profit = 0.0
    max_buy_profit = 0.0
    max_sell_profit = 0.0
    trade_history = []
    basket_sl_count = 0
    recycle_count = 0
    hedge_opened_count = 0
    hedge_tp_count = 0
    max_buy_orders_reached = 0
    max_sell_orders_reached = 0

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

    # Convert m1 rows to tuples for speed
    records = df_m1[['datetime', 'close', 'm15_time', 'h1_time']].to_records(index=False)

    for r in records[200:]:
        dt = pd.to_datetime(r['datetime'])
        bid = float(r['close'])
        ask = bid + (spread_pts * point)

        m15_t = pd.to_datetime(r['m15_time'])
        prev_m15_t = m15_t - datetime.timedelta(minutes=15)
        atr_val = m15_map.get(prev_m15_t, {}).get('atr14', base_distance)
        if atr_val is None or np.isnan(atr_val) or atr_val <= 0:
            atr_val = base_distance

        cur_dist = atr_val * atr_multiplier
        if cur_dist < base_distance * 0.8:
            cur_dist = base_distance * 0.8

        h1_t = pd.to_datetime(r['h1_time'])
        prev_h1_t = h1_t - datetime.timedelta(hours=1)
        h1_info = h1_map.get(prev_h1_t, {})
        ema_val = h1_info.get('ema200', None)
        h1_close = h1_info.get('close', None)

        trend_dir = 0
        if use_trend_filter and ema_val is not None and h1_close is not None:
            if h1_close > ema_val: trend_dir = 1
            elif h1_close < ema_val: trend_dir = -1

        is_trading_time = True
        if friday_filter and dt.weekday() == 4 and dt.hour >= 17:
            is_trading_time = False
        else:
            cur_mins = dt.hour * 60 + dt.minute
            start_mins = start_time_hour * 60 + start_time_min
            end_mins = end_time_hour * 60 + end_time_min
            if not (start_mins <= cur_mins <= end_mins):
                is_trading_time = False

        buy_positions = [p for p in positions if p['type'] == 'BUY' and not p['is_hedge']]
        sell_positions = [p for p in positions if p['type'] == 'SELL' and not p['is_hedge']]
        hedge_positions = [p for p in positions if p['is_hedge']]

        buy_profit = sum(get_pos_profit(p, bid, ask) for p in buy_positions)
        sell_profit = sum(get_pos_profit(p, bid, ask) for p in sell_positions)
        hedge_profit = sum(get_pos_profit(p, bid, ask) for p in hedge_positions)
        total_floating = buy_profit + sell_profit + hedge_profit

        cur_equity = balance + total_floating
        dd_usd = peak_balance - cur_equity
        if dd_usd > max_drawdown_usd:
            max_drawdown_usd = dd_usd

        # Basket SL
        if use_max_loss_usd and total_floating <= -abs(max_loss_usd):
            basket_sl_count += 1
            for p in positions:
                p_prof = get_pos_profit(p, bid, ask)
                balance += p_prof
                trade_history.append({'time': dt, 'profit': p_prof, 'reason': 'BASKET_SL'})
            positions = []
            max_global_profit = 0.0
            max_buy_profit = 0.0
            max_sell_profit = 0.0
            if balance > peak_balance: peak_balance = balance
            continue

        # Hedge TP
        if len(hedge_positions) > 0 and hedge_profit >= 8.00:
            hedge_tp_count += 1
            for hp in hedge_positions:
                p_prof = get_pos_profit(hp, bid, ask)
                balance += p_prof
                trade_history.append({'time': dt, 'profit': p_prof, 'reason': 'HEDGE_TP'})
            positions = [p for p in positions if not p['is_hedge']]
            hedge_positions = []
            total_floating = buy_profit + sell_profit

        # Hedge Trigger
        total_buy = len(buy_positions)
        total_sell = len(sell_positions)
        total_buy_vol = sum(p['lot'] for p in buy_positions)
        total_sell_vol = sum(p['lot'] for p in sell_positions)
        if total_buy > max_buy_orders_reached: max_buy_orders_reached = total_buy
        if total_sell > max_sell_orders_reached: max_sell_orders_reached = total_sell

        if total_sell >= 5 and len(hedge_positions) == 0:
            h_lot = round(min(max_allowed_lot, total_sell_vol * 0.8), 2)
            if h_lot < 0.01: h_lot = 0.01
            ticket_counter += 1
            positions.append({'type': 'BUY', 'lot': h_lot, 'price': ask, 'ticket': ticket_counter, 'time': dt, 'is_hedge': True})
            hedge_opened_count += 1

        if total_buy >= 5 and len(hedge_positions) == 0:
            h_lot = round(min(max_allowed_lot, total_buy_vol * 0.8), 2)
            if h_lot < 0.01: h_lot = 0.01
            ticket_counter += 1
            positions.append({'type': 'SELL', 'lot': h_lot, 'price': bid, 'ticket': ticket_counter, 'time': dt, 'is_hedge': True})
            hedge_opened_count += 1

        # Trailing
        closed_any = False
        if use_trailing:
            if total_floating >= target_global_usd:
                if total_floating > max_global_profit: max_global_profit = total_floating
                drop = max_global_profit * (trailing_drop_pct / 100.0)
                if (max_global_profit - total_floating >= drop) or (total_floating <= target_global_usd * 0.9):
                    for p in positions:
                        p_prof = get_pos_profit(p, bid, ask)
                        balance += p_prof
                        trade_history.append({'time': dt, 'profit': p_prof, 'reason': 'GLOBAL_TRAILING'})
                    positions = []
                    max_global_profit = 0.0
                    max_buy_profit = 0.0
                    max_sell_profit = 0.0
                    closed_any = True

            if not closed_any and len(buy_positions) > 0:
                if buy_profit >= trailing_start_usd:
                    if buy_profit > max_buy_profit: max_buy_profit = buy_profit
                    drop = max_buy_profit * (trailing_drop_pct / 100.0)
                    if (max_buy_profit - buy_profit >= drop) or (buy_profit <= trailing_start_usd * 0.85):
                        for p in buy_positions:
                            p_prof = get_pos_profit(p, bid, ask)
                            balance += p_prof
                            trade_history.append({'time': dt, 'profit': p_prof, 'reason': 'BUY_TRAILING'})
                        positions = [p for p in positions if p not in buy_positions]
                        max_buy_profit = 0.0
                        buy_positions = []
                elif buy_profit < trailing_start_usd * 0.5:
                    max_buy_profit = 0.0

            if not closed_any and len(sell_positions) > 0:
                if sell_profit >= trailing_start_usd:
                    if sell_profit > max_sell_profit: max_sell_profit = sell_profit
                    drop = max_sell_profit * (trailing_drop_pct / 100.0)
                    if (max_sell_profit - sell_profit >= drop) or (sell_profit <= trailing_start_usd * 0.85):
                        for p in sell_positions:
                            p_prof = get_pos_profit(p, bid, ask)
                            balance += p_prof
                            trade_history.append({'time': dt, 'profit': p_prof, 'reason': 'SELL_TRAILING'})
                        positions = [p for p in positions if p not in sell_positions]
                        max_sell_profit = 0.0
                        sell_positions = []
                elif sell_profit < trailing_start_usd * 0.5:
                    max_sell_profit = 0.0

        # Recycling
        if len(buy_positions) > 0 and len(sell_positions) > 0:
            if buy_profit >= target_side_usd:
                worst_sell = min(sell_positions, key=lambda p: get_pos_profit(p, bid, ask))
                worst_loss = get_pos_profit(worst_sell, bid, ask)
                if buy_profit > abs(worst_loss):
                    recycle_count += 1
                    balance += worst_loss
                    trade_history.append({'time': dt, 'profit': worst_loss, 'reason': 'RECYCLE_SELL'})
                    positions.remove(worst_sell)
                    for p in buy_positions:
                        p_prof = get_pos_profit(p, bid, ask)
                        balance += p_prof
                        trade_history.append({'time': dt, 'profit': p_prof, 'reason': 'RECYCLE_BUY_CLOSE'})
                    positions = [p for p in positions if p not in buy_positions]
                    buy_positions = []
            elif sell_profit >= target_side_usd and len(buy_positions) > 0:
                worst_buy = min(buy_positions, key=lambda p: get_pos_profit(p, bid, ask))
                worst_loss = get_pos_profit(worst_buy, bid, ask)
                if sell_profit > abs(worst_loss):
                    recycle_count += 1
                    balance += worst_loss
                    trade_history.append({'time': dt, 'profit': worst_loss, 'reason': 'RECYCLE_BUY'})
                    positions.remove(worst_buy)
                    for p in sell_positions:
                        p_prof = get_pos_profit(p, bid, ask)
                        balance += p_prof
                        trade_history.append({'time': dt, 'profit': p_prof, 'reason': 'RECYCLE_SELL_CLOSE'})
                    positions = [p for p in positions if p not in sell_positions]
                    sell_positions = []

        buy_positions = [p for p in positions if p['type'] == 'BUY' and not p['is_hedge']]
        sell_positions = [p for p in positions if p['type'] == 'SELL' and not p['is_hedge']]
        hedge_positions = [p for p in positions if p['is_hedge']]
        if len(buy_positions) == 0 and len(sell_positions) == 0 and len(hedge_positions) > 0:
            for p in hedge_positions:
                p_prof = get_pos_profit(p, bid, ask)
                balance += p_prof
                trade_history.append({'time': dt, 'profit': p_prof, 'reason': 'HEDGE_CLEAN'})
            positions = []

        if balance > peak_balance: peak_balance = balance

        # Entries
        if is_trading_time:
            buy_positions = [p for p in positions if p['type'] == 'BUY' and not p['is_hedge']]
            sell_positions = [p for p in positions if p['type'] == 'SELL' and not p['is_hedge']]
            if len(buy_positions) == 0 and (trend_dir >= 0):
                ticket_counter += 1
                positions.append({'type': 'BUY', 'lot': initial_lot, 'price': ask, 'ticket': ticket_counter, 'time': dt, 'is_hedge': False})
            if len(sell_positions) == 0 and (trend_dir <= 0):
                ticket_counter += 1
                positions.append({'type': 'SELL', 'lot': initial_lot, 'price': bid, 'ticket': ticket_counter, 'time': dt, 'is_hedge': False})

            if len(buy_positions) > 0 and len(buy_positions) < max_total_orders:
                lowest_buy = min(p['price'] for p in buy_positions)
                if ask < (lowest_buy - cur_dist):
                    lowest_pos = [p for p in buy_positions if p['price'] == lowest_buy][0]
                    next_lot = calc_lot(lowest_pos['lot'], len(buy_positions))
                    ticket_counter += 1
                    positions.append({'type': 'BUY', 'lot': next_lot, 'price': ask, 'ticket': ticket_counter, 'time': dt, 'is_hedge': False})

            if len(sell_positions) > 0 and len(sell_positions) < max_total_orders:
                highest_sell = max(p['price'] for p in sell_positions)
                if bid > (highest_sell + cur_dist):
                    highest_pos = [p for p in sell_positions if p['price'] == highest_sell][0]
                    next_lot = calc_lot(highest_pos['lot'], len(sell_positions))
                    ticket_counter += 1
                    positions.append({'type': 'SELL', 'lot': next_lot, 'price': bid, 'ticket': ticket_counter, 'time': dt, 'is_hedge': False})

    # End simulation
    last_r = records[-1]
    final_bid = float(last_r['close'])
    final_ask = final_bid + (spread_pts * point)
    for p in positions:
        p_prof = get_pos_profit(p, final_bid, final_ask)
        balance += p_prof
        trade_history.append({'time': pd.to_datetime(last_r['datetime']), 'profit': p_prof, 'reason': 'END_SIM'})

    df_tr = pd.DataFrame(trade_history)
    wins = df_tr[df_tr['profit'] > 0]
    losses = df_tr[df_tr['profit'] < 0]
    win_rate = (len(wins) / len(df_tr) * 100.0) if len(df_tr) > 0 else 0
    gross_profit = wins['profit'].sum() if len(wins) > 0 else 0
    gross_loss = abs(losses['profit'].sum()) if len(losses) > 0 else 0
    profit_factor = (gross_profit / gross_loss) if gross_loss > 0 else (999.0 if gross_profit > 0 else 0)

    return {
        'symbol': sym,
        'use_trend_filter': use_trend_filter,
        'base_dist_pts': base_dist_pts,
        'target_side': target_side,
        'target_global': target_global,
        'net_profit': round(balance - 1000.00, 2),
        'profit_pct': round(((balance - 1000.00) / 1000.00) * 100.0, 2),
        'max_drawdown_usd': round(max_drawdown_usd, 2),
        'max_drawdown_pct': round((max_drawdown_usd / 1000.00) * 100.0, 2),
        'total_trades': len(df_tr),
        'win_rate': round(win_rate, 2),
        'profit_factor': round(profit_factor, 2),
        'basket_sl_count': basket_sl_count,
        'recycle_count': recycle_count,
        'max_buy_orders': max_buy_orders_reached,
        'max_sell_orders': max_sell_orders_reached
    }

if __name__ == '__main__':
    symbols = ['EURUSD', 'AUDUSD', 'USDCAD']
    data = fetch_data(symbols)
    if not data:
        exit(1)
    
    results = []
    for s in symbols:
        if s in data:
            print(f"Running {s} TF ON...")
            r_on = simulate(s, data[s], use_trend_filter=True)
            results.append(r_on)
            print(f"Running {s} TF OFF...")
            r_off = simulate(s, data[s], use_trend_filter=False)
            results.append(r_off)

    df_res = pd.DataFrame(results)
    print("\n" + df_res.to_string(index=False))
