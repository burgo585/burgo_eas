import MetaTrader5 as mt5
import pandas as pd
import numpy as np
import datetime
import math

def run_simulation(use_trend_filter=True, symbol="EURUSD"):
    if not mt5.initialize(path=r"C:\Program Files\MetaTrader 5\terminal64.exe"):
        print("Failed to initialize MT5:", mt5.last_error())
        return None

    symbol_info = mt5.symbol_info(symbol)
    if symbol_info is None:
        print(f"Symbol {symbol} not found")
        mt5.shutdown()
        return None

    point = symbol_info.point
    digits = symbol_info.digits
    spread_pts = symbol_info.spread
    contract_size = symbol_info.trade_contract_size

    # Fetch M15 bars
    rates_m15 = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_M15, 0, 10000)
    # Fetch H1 bars
    rates_h1 = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_H1, 0, 4000)
    # Fetch M1 bars for accurate price movement
    rates_m1 = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_M1, 0, 80000)
    mt5.shutdown()

    df_m15 = pd.DataFrame(rates_m15)
    df_m15['datetime'] = pd.to_datetime(df_m15['time'], unit='s')
    
    # Calculate ATR(14) on M15
    high_low = df_m15['high'] - df_m15['low']
    high_close = (df_m15['high'] - df_m15['close'].shift()).abs()
    low_close = (df_m15['low'] - df_m15['close'].shift()).abs()
    tr = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
    df_m15['atr14'] = tr.rolling(window=14).mean()

    # Calculate EMA(200) on H1
    df_h1 = pd.DataFrame(rates_h1)
    df_h1['datetime'] = pd.to_datetime(df_h1['time'], unit='s')
    df_h1['ema200'] = df_h1['close'].ewm(span=200, adjust=False).mean()

    df_m1 = pd.DataFrame(rates_m1)
    df_m1['datetime'] = pd.to_datetime(df_m1['time'], unit='s')
    df_m1 = df_m1.sort_values('datetime').reset_index(drop=True)

    print(f"Loaded {len(df_m1)} M1 bars from {df_m1['datetime'].iloc[0]} to {df_m1['datetime'].iloc[-1]}")

    # Map M15 ATR and H1 EMA to M1 bars
    # M15 time bucket: floor to 15 min
    df_m1['m15_time'] = df_m1['datetime'].dt.floor('15min')
    m15_map = df_m15.set_index('datetime')[['atr14', 'close']].to_dict('index')
    
    # H1 time bucket: floor to 1 hour
    df_m1['h1_time'] = df_m1['datetime'].dt.floor('1h')
    h1_map = df_h1.set_index('datetime')[['ema200', 'close']].to_dict('index')

    # Simulation parameters (From User Print & Request)
    initial_lot = 0.02
    target_side_usd = 5.00
    target_global_usd = 10.00
    base_dist_pts = 500
    base_distance = base_dist_pts * point
    lot_multiplier = 1.5
    max_martingale = 6
    max_total_orders = 10
    max_allowed_lot = 1.50
    use_max_loss_usd = True
    max_loss_usd = 80.00

    use_atr = True
    atr_multiplier = 1.5

    use_trailing = True
    trailing_start_usd = 5.00
    trailing_drop_pct = 10.0

    start_time_hour, start_time_min = 4, 0
    end_time_hour, end_time_min = 18, 0
    friday_filter = True

    # State
    balance = 1000.00
    equity = 1000.00
    peak_balance = 1000.00
    max_drawdown_usd = 0.0
    max_drawdown_pct = 0.0

    positions = [] # list of dicts: {'type': 'BUY'/'SELL', 'lot': float, 'price': float, 'ticket': int, 'time': dt, 'is_hedge': bool}
    ticket_counter = 1

    max_global_profit = 0.0
    max_buy_profit = 0.0
    max_sell_profit = 0.0

    trade_history = []
    daily_stats = {}
    basket_sl_count = 0
    recycle_count = 0
    hedge_opened_count = 0
    hedge_tp_count = 0
    max_buy_orders_reached = 0
    max_sell_orders_reached = 0

    def calc_lot(last_lot, total_orders):
        if total_orders >= max_martingale:
            return last_lot
        step = 0.01
        nxt = last_lot * lot_multiplier
        norm = round(round(nxt / step) * step, 2)
        if norm <= last_lot:
            norm = round(last_lot + step, 2)
        if norm > max_allowed_lot:
            norm = max_allowed_lot
        return norm

    def get_pos_profit(pos, cur_bid, cur_ask):
        if pos['type'] == 'BUY':
            diff = cur_bid - pos['price']
        else:
            diff = pos['price'] - cur_ask
        return diff * pos['lot'] * contract_size

    # Loop over M1 bars
    for i in range(200, len(df_m1)):
        row = df_m1.iloc[i]
        dt = row['datetime']
        bid = row['close']
        ask = bid + (spread_pts * point)

        # Look up previous M15 ATR
        m15_t = row['m15_time']
        prev_m15_t = m15_t - datetime.timedelta(minutes=15)
        atr_val = m15_map.get(prev_m15_t, {}).get('atr14', base_distance)
        if pd.isna(atr_val) or atr_val <= 0:
            atr_val = base_distance

        # Dynamic distance
        if use_atr:
            cur_dist = atr_val * atr_multiplier
            if cur_dist < base_distance * 0.8:
                cur_dist = base_distance * 0.8
        else:
            cur_dist = base_distance

        # Trend EMA on H1
        h1_t = row['h1_time']
        prev_h1_t = h1_t - datetime.timedelta(hours=1)
        h1_info = h1_map.get(prev_h1_t, {})
        ema_val = h1_info.get('ema200', None)
        h1_close = h1_info.get('close', None)

        trend_dir = 0
        if use_trend_filter and ema_val is not None and h1_close is not None:
            if h1_close > ema_val:
                trend_dir = 1
            elif h1_close < ema_val:
                trend_dir = -1

        # Trading Time Check
        is_trading_time = True
        if friday_filter and dt.weekday() == 4 and dt.hour >= 17:
            is_trading_time = False
        else:
            cur_mins = dt.hour * 60 + dt.minute
            start_mins = start_time_hour * 60 + start_time_min
            end_mins = end_time_hour * 60 + end_time_min
            if not (start_mins <= cur_mins <= end_mins):
                is_trading_time = False

        # Calculate floating profits
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
            max_drawdown_pct = (dd_usd / peak_balance) * 100.0

        # 1. Stop Loss Financeiro da Cesta
        if use_max_loss_usd and total_floating <= -abs(max_loss_usd):
            basket_sl_count += 1
            for p in positions:
                p_prof = get_pos_profit(p, bid, ask)
                balance += p_prof
                trade_history.append({'time': dt, 'type': p['type'], 'lot': p['lot'], 'profit': p_prof, 'reason': 'BASKET_SL'})
            positions = []
            max_global_profit = 0.0
            max_buy_profit = 0.0
            max_sell_profit = 0.0
            if balance > peak_balance:
                peak_balance = balance
            continue

        # 2. Hedge Take Profit (Independent)
        if len(hedge_positions) > 0 and hedge_profit >= 8.00:
            hedge_tp_count += 1
            for hp in hedge_positions:
                p_prof = get_pos_profit(hp, bid, ask)
                balance += p_prof
                trade_history.append({'time': dt, 'type': hp['type'], 'lot': hp['lot'], 'profit': p_prof, 'reason': 'HEDGE_TP'})
            positions = [p for p in positions if not p['is_hedge']]
            hedge_positions = []
            hedge_profit = 0.0
            total_floating = buy_profit + sell_profit

        # 3. Hedge Trigger
        total_buy = len(buy_positions)
        total_sell = len(sell_positions)
        total_buy_vol = sum(p['lot'] for p in buy_positions)
        total_sell_vol = sum(p['lot'] for p in sell_positions)

        if total_buy > max_buy_orders_reached:
            max_buy_orders_reached = total_buy
        if total_sell > max_sell_orders_reached:
            max_sell_orders_reached = total_sell

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

        # 4. Trailing Stop Execution
        closed_any = False
        if use_trailing:
            # Global Trailing
            if total_floating >= target_global_usd:
                if total_floating > max_global_profit:
                    max_global_profit = total_floating
                drop = max_global_profit * (trailing_drop_pct / 100.0)
                if (max_global_profit - total_floating >= drop) or (total_floating <= target_global_usd * 0.9):
                    for p in positions:
                        p_prof = get_pos_profit(p, bid, ask)
                        balance += p_prof
                        trade_history.append({'time': dt, 'type': p['type'], 'lot': p['lot'], 'profit': p_prof, 'reason': 'GLOBAL_TRAILING'})
                    positions = []
                    max_global_profit = 0.0
                    max_buy_profit = 0.0
                    max_sell_profit = 0.0
                    closed_any = True
            
            # Buy Trailing
            if not closed_any and len(buy_positions) > 0:
                if buy_profit >= trailing_start_usd:
                    if buy_profit > max_buy_profit:
                        max_buy_profit = buy_profit
                    drop = max_buy_profit * (trailing_drop_pct / 100.0)
                    if (max_buy_profit - buy_profit >= drop) or (buy_profit <= trailing_start_usd * 0.85):
                        for p in buy_positions:
                            p_prof = get_pos_profit(p, bid, ask)
                            balance += p_prof
                            trade_history.append({'time': dt, 'type': p['type'], 'lot': p['lot'], 'profit': p_prof, 'reason': 'BUY_TRAILING'})
                        positions = [p for p in positions if p not in buy_positions]
                        max_buy_profit = 0.0
                        buy_positions = []
                elif buy_profit < trailing_start_usd * 0.5:
                    max_buy_profit = 0.0

            # Sell Trailing
            if not closed_any and len(sell_positions) > 0:
                if sell_profit >= trailing_start_usd:
                    if sell_profit > max_sell_profit:
                        max_sell_profit = sell_profit
                    drop = max_sell_profit * (trailing_drop_pct / 100.0)
                    if (max_sell_profit - sell_profit >= drop) or (sell_profit <= trailing_start_usd * 0.85):
                        for p in sell_positions:
                            p_prof = get_pos_profit(p, bid, ask)
                            balance += p_prof
                            trade_history.append({'time': dt, 'type': p['type'], 'lot': p['lot'], 'profit': p_prof, 'reason': 'SELL_TRAILING'})
                        positions = [p for p in positions if p not in sell_positions]
                        max_sell_profit = 0.0
                        sell_positions = []
                elif sell_profit < trailing_start_usd * 0.5:
                    max_sell_profit = 0.0

        # 5. Recycling (Reciclagem Ativa)
        if len(buy_positions) > 0 and len(sell_positions) > 0:
            if buy_profit >= target_side_usd:
                # Find worst sell
                worst_sell = min(sell_positions, key=lambda p: get_pos_profit(p, bid, ask))
                worst_loss = get_pos_profit(worst_sell, bid, ask)
                if buy_profit > abs(worst_loss):
                    recycle_count += 1
                    # Close worst sell
                    balance += worst_loss
                    trade_history.append({'time': dt, 'type': worst_sell['type'], 'lot': worst_sell['lot'], 'profit': worst_loss, 'reason': 'RECYCLE_SELL'})
                    positions.remove(worst_sell)
                    # Close all buys
                    for p in buy_positions:
                        p_prof = get_pos_profit(p, bid, ask)
                        balance += p_prof
                        trade_history.append({'time': dt, 'type': p['type'], 'lot': p['lot'], 'profit': p_prof, 'reason': 'RECYCLE_BUY_CLOSE'})
                    positions = [p for p in positions if p not in buy_positions]
                    buy_positions = []

            elif sell_profit >= target_side_usd and len(buy_positions) > 0:
                worst_buy = min(buy_positions, key=lambda p: get_pos_profit(p, bid, ask))
                worst_loss = get_pos_profit(worst_buy, bid, ask)
                if sell_profit > abs(worst_loss):
                    recycle_count += 1
                    balance += worst_loss
                    trade_history.append({'time': dt, 'type': worst_buy['type'], 'lot': worst_buy['lot'], 'profit': worst_loss, 'reason': 'RECYCLE_BUY'})
                    positions.remove(worst_buy)
                    for p in sell_positions:
                        p_prof = get_pos_profit(p, bid, ask)
                        balance += p_prof
                        trade_history.append({'time': dt, 'type': p['type'], 'lot': p['lot'], 'profit': p_prof, 'reason': 'RECYCLE_SELL_CLOSE'})
                    positions = [p for p in positions if p not in sell_positions]
                    sell_positions = []

        # If both sides are closed, close remaining hedge
        buy_positions = [p for p in positions if p['type'] == 'BUY' and not p['is_hedge']]
        sell_positions = [p for p in positions if p['type'] == 'SELL' and not p['is_hedge']]
        hedge_positions = [p for p in positions if p['is_hedge']]
        if len(buy_positions) == 0 and len(sell_positions) == 0 and len(hedge_positions) > 0:
            for p in hedge_positions:
                p_prof = get_pos_profit(p, bid, ask)
                balance += p_prof
                trade_history.append({'time': dt, 'type': p['type'], 'lot': p['lot'], 'profit': p_prof, 'reason': 'HEDGE_CLEAN'})
            positions = []

        if balance > peak_balance:
            peak_balance = balance

        # 6. New Entries & Grid Progression
        if is_trading_time:
            buy_positions = [p for p in positions if p['type'] == 'BUY' and not p['is_hedge']]
            sell_positions = [p for p in positions if p['type'] == 'SELL' and not p['is_hedge']]

            # Giro inicial
            if len(buy_positions) == 0 and (trend_dir >= 0):
                ticket_counter += 1
                positions.append({'type': 'BUY', 'lot': initial_lot, 'price': ask, 'ticket': ticket_counter, 'time': dt, 'is_hedge': False})

            if len(sell_positions) == 0 and (trend_dir <= 0):
                ticket_counter += 1
                positions.append({'type': 'SELL', 'lot': initial_lot, 'price': bid, 'ticket': ticket_counter, 'time': dt, 'is_hedge': False})

            # Grid Buy
            if len(buy_positions) > 0 and len(buy_positions) < max_total_orders:
                lowest_buy = min(p['price'] for p in buy_positions)
                if ask < (lowest_buy - cur_dist):
                    # Last buy lot is the lot at lowest price
                    lowest_pos = [p for p in buy_positions if p['price'] == lowest_buy][0]
                    next_lot = calc_lot(lowest_pos['lot'], len(buy_positions))
                    ticket_counter += 1
                    positions.append({'type': 'BUY', 'lot': next_lot, 'price': ask, 'ticket': ticket_counter, 'time': dt, 'is_hedge': False})

            # Grid Sell
            if len(sell_positions) > 0 and len(sell_positions) < max_total_orders:
                highest_sell = max(p['price'] for p in sell_positions)
                if bid > (highest_sell + cur_dist):
                    highest_pos = [p for p in sell_positions if p['price'] == highest_sell][0]
                    next_lot = calc_lot(highest_pos['lot'], len(sell_positions))
                    ticket_counter += 1
                    positions.append({'type': 'SELL', 'lot': next_lot, 'price': bid, 'ticket': ticket_counter, 'time': dt, 'is_hedge': False})

    # Close any open positions at the end of simulation
    last_row = df_m1.iloc[-1]
    final_bid = last_row['close']
    final_ask = final_bid + (spread_pts * point)
    for p in positions:
        p_prof = get_pos_profit(p, final_bid, final_ask)
        balance += p_prof
        trade_history.append({'time': last_row['datetime'], 'type': p['type'], 'lot': p['lot'], 'profit': p_prof, 'reason': 'END_SIM'})

    # Summary Statistics
    df_trades = pd.DataFrame(trade_history)
    wins = df_trades[df_trades['profit'] > 0]
    losses = df_trades[df_trades['profit'] < 0]
    win_rate = (len(wins) / len(df_trades) * 100.0) if len(df_trades) > 0 else 0
    gross_profit = wins['profit'].sum() if len(wins) > 0 else 0
    gross_loss = abs(losses['profit'].sum()) if len(losses) > 0 else 0
    profit_factor = (gross_profit / gross_loss) if gross_loss > 0 else (999.0 if gross_profit > 0 else 0)

    result = {
        'symbol': symbol,
        'use_trend_filter': use_trend_filter,
        'start_date': str(df_m1['datetime'].iloc[0]),
        'end_date': str(df_m1['datetime'].iloc[-1]),
        'initial_balance': 1000.00,
        'final_balance': round(balance, 2),
        'net_profit': round(balance - 1000.00, 2),
        'profit_pct': round(((balance - 1000.00) / 1000.00) * 100.0, 2),
        'max_drawdown_usd': round(max_drawdown_usd, 2),
        'max_drawdown_pct': round(max_drawdown_pct, 2),
        'total_trades': len(df_trades),
        'win_trades': len(wins),
        'loss_trades': len(losses),
        'win_rate': round(win_rate, 2),
        'gross_profit': round(gross_profit, 2),
        'gross_loss': round(gross_loss, 2),
        'profit_factor': round(profit_factor, 2),
        'basket_sl_count': basket_sl_count,
        'recycle_count': recycle_count,
        'hedge_opened_count': hedge_opened_count,
        'hedge_tp_count': hedge_tp_count,
        'max_buy_orders_reached': max_buy_orders_reached,
        'max_sell_orders_reached': max_sell_orders_reached,
    }
    return result, df_trades

if __name__ == '__main__':
    print("=== EXECUTING TEST 1: TREND FILTER ON (EMA 200 H1) ===")
    res_tf_on, df_tf_on = run_simulation(use_trend_filter=True, symbol="EURUSD")
    for k, v in res_tf_on.items():
        print(f"  {k}: {v}")

    print("\n=== EXECUTING TEST 2: TREND FILTER OFF (PURE BIDIRECTIONAL AS IN SCREENSHOT) ===")
    res_tf_off, df_tf_off = run_simulation(use_trend_filter=False, symbol="EURUSD")
    for k, v in res_tf_off.items():
        print(f"  {k}: {v}")
