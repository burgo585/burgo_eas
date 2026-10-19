import MetaTrader5 as mt5
import pandas as pd
import numpy as np
import datetime

def load_data():
    if not mt5.initialize(path=r"C:\Program Files\MetaTrader 5\terminal64.exe"):
        print("MT5 init failed:", mt5.last_error())
        return None
    sym = 'XAUUSD-VIP'
    mt5.symbol_select(sym, True)
    info = mt5.symbol_info(sym)

    start_dt = datetime.datetime(2024, 10, 11)
    end_dt = datetime.datetime(2026, 10, 11)
    rates_m15 = mt5.copy_rates_range(sym, mt5.TIMEFRAME_M15, start_dt, end_dt)
    rates_h1 = mt5.copy_rates_range(sym, mt5.TIMEFRAME_H1, start_dt - datetime.timedelta(days=60), end_dt)
    mt5.shutdown()

    df_m15 = pd.DataFrame(rates_m15)
    df_m15['datetime'] = pd.to_datetime(df_m15['time'], unit='s')

    # ATR(14) on M15
    hl = df_m15['high'] - df_m15['low']
    hc = (df_m15['high'] - df_m15['close'].shift()).abs()
    lc = (df_m15['low'] - df_m15['close'].shift()).abs()
    tr = pd.concat([hl, hc, lc], axis=1).max(axis=1)
    df_m15['atr14'] = tr.rolling(window=14).mean()

    # EMA 200 on H1
    df_h1 = pd.DataFrame(rates_h1)
    df_h1['datetime'] = pd.to_datetime(df_h1['time'], unit='s')
    df_h1['ema200'] = df_h1['close'].ewm(span=200, adjust=False).mean()

    # Align H1 to M15
    df_m15['h1_time'] = df_m15['datetime'].dt.floor('1h')
    h1_map = df_h1.set_index('datetime')[['ema200', 'close']].to_dict('index')

    return {
        'df_m15': df_m15,
        'h1_map': h1_map,
        'point': info.point,
        'spread_pts': info.spread,
        'contract_size': info.trade_contract_size
    }

def run_backtest(data_pkg, use_trend_filter=True, base_dist_pts=500, target_side=5.0, target_global=10.0,
                 max_loss_usd=80.0, atr_multiplier=1.5, lot_multiplier=1.5, max_martingale=6):
    df_m15 = data_pkg['df_m15']
    h1_map = data_pkg['h1_map']
    point = data_pkg['point']
    spread = data_pkg['spread_pts'] * point
    contract_size = data_pkg['contract_size']

    initial_lot = 0.02
    max_total_orders = 10
    max_allowed_lot = 1.50
    base_dist = base_dist_pts * point
    trailing_drop_pct = 10.0

    balance = 1000.00
    peak_balance = 1000.00
    max_drawdown_usd = 0.0
    max_drawdown_pct = 0.0

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

    # Iterate M15 bars
    for idx in range(20, len(df_m15)):
        row = df_m15.iloc[idx]
        dt = row['datetime']
        o, h, l, c = row['open'], row['high'], row['low'], row['close']

        # ATR lookup (from previous closed bar)
        prev_atr = df_m15['atr14'].iloc[idx-1]
        if pd.isna(prev_atr) or prev_atr <= 0:
            prev_atr = base_dist
        cur_dist = prev_atr * atr_multiplier
        if cur_dist < base_dist * 0.8:
            cur_dist = base_dist * 0.8

        # Trend EMA lookup
        h1_t = row['h1_time']
        prev_h1_t = h1_t - datetime.timedelta(hours=1)
        h1_info = h1_map.get(prev_h1_t, {})
        ema_val = h1_info.get('ema200', None)
        h1_close = h1_info.get('close', None)

        trend_dir = 0
        if use_trend_filter and ema_val is not None and h1_close is not None:
            if h1_close > ema_val: trend_dir = 1
            elif h1_close < ema_val: trend_dir = -1

        # Trading Time Check
        is_trading_time = True
        if dt.weekday() == 4 and dt.hour >= 17:
            is_trading_time = False
        else:
            mins = dt.hour * 60 + dt.minute
            if not (240 <= mins <= 1080): # 04:00 to 18:00
                is_trading_time = False

        # Intra-bar price sequence
        if c >= o:
            price_sequence = [(o, 'open'), (l, 'low'), (h, 'high'), (c, 'close')]
        else:
            price_sequence = [(o, 'open'), (h, 'high'), (l, 'low'), (c, 'close')]

        for p_val, step_type in price_sequence:
            cur_bid = p_val
            cur_ask = cur_bid + spread

            buy_positions = [p for p in positions if p['type'] == 'BUY' and not p['is_hedge']]
            sell_positions = [p for p in positions if p['type'] == 'SELL' and not p['is_hedge']]
            hedge_positions = [p for p in positions if p['is_hedge']]

            buy_profit = sum(get_pos_profit(p, cur_bid, cur_ask) for p in buy_positions)
            sell_profit = sum(get_pos_profit(p, cur_bid, cur_ask) for p in sell_positions)
            hedge_profit = sum(get_pos_profit(p, cur_bid, cur_ask) for p in hedge_positions)
            total_floating = buy_profit + sell_profit + hedge_profit

            cur_equity = balance + total_floating
            dd = peak_balance - cur_equity
            if dd > max_drawdown_usd:
                max_drawdown_usd = dd
                max_drawdown_pct = (dd / peak_balance) * 100.0

            # 1. Basket Stop Loss
            if total_floating <= -abs(max_loss_usd):
                basket_sl_count += 1
                for p in positions:
                    prof = get_pos_profit(p, cur_bid, cur_ask)
                    balance += prof
                    trade_history.append({'time': dt, 'profit': prof, 'type': p['type'], 'lot': p['lot'], 'reason': 'BASKET_SL'})
                    m_key = dt.strftime('%Y-%m')
                    monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + prof
                positions = []
                max_global_profit = 0.0
                max_buy_profit = 0.0
                max_sell_profit = 0.0
                if balance > peak_balance: peak_balance = balance
                break # cesta zerada

            # 2. Independent Hedge Take Profit
            if len(hedge_positions) > 0 and hedge_profit >= 8.00:
                hedge_tp_count += 1
                for hp in hedge_positions:
                    prof = get_pos_profit(hp, cur_bid, cur_ask)
                    balance += prof
                    trade_history.append({'time': dt, 'profit': prof, 'type': hp['type'], 'lot': hp['lot'], 'reason': 'HEDGE_TP'})
                    m_key = dt.strftime('%Y-%m')
                    monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + prof
                positions = [p for p in positions if not p['is_hedge']]
                hedge_positions = []
                total_floating = buy_profit + sell_profit

            # 3. Hedge Defense Trigger
            total_buy = len(buy_positions)
            total_sell = len(sell_positions)
            if total_buy > max_buy_orders: max_buy_orders = total_buy
            if total_sell > max_sell_orders: max_sell_orders = total_sell
            total_buy_vol = sum(p['lot'] for p in buy_positions)
            total_sell_vol = sum(p['lot'] for p in sell_positions)

            if total_sell >= 5 and len(hedge_positions) == 0:
                h_lot = round(min(max_allowed_lot, total_sell_vol * 0.8), 2)
                if h_lot < 0.01: h_lot = 0.01
                ticket_counter += 1
                positions.append({'type': 'BUY', 'lot': h_lot, 'price': cur_ask, 'ticket': ticket_counter, 'time': dt, 'is_hedge': True})
                hedge_opened_count += 1

            if total_buy >= 5 and len(hedge_positions) == 0:
                h_lot = round(min(max_allowed_lot, total_buy_vol * 0.8), 2)
                if h_lot < 0.01: h_lot = 0.01
                ticket_counter += 1
                positions.append({'type': 'SELL', 'lot': h_lot, 'price': cur_bid, 'ticket': ticket_counter, 'time': dt, 'is_hedge': True})
                hedge_opened_count += 1

            # 4. Trailing Stops
            closed_basket = False
            # Global Trailing
            if total_floating >= target_global:
                if total_floating > max_global_profit: max_global_profit = total_floating
                drop = max_global_profit * (trailing_drop_pct / 100.0)
                if (max_global_profit - total_floating >= drop) or (total_floating <= target_global * 0.9):
                    for p in positions:
                        prof = get_pos_profit(p, cur_bid, cur_ask)
                        balance += prof
                        trade_history.append({'time': dt, 'profit': prof, 'type': p['type'], 'lot': p['lot'], 'reason': 'GLOBAL_TRAILING'})
                        m_key = dt.strftime('%Y-%m')
                        monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + prof
                    positions = []
                    max_global_profit = 0.0
                    max_buy_profit = 0.0
                    max_sell_profit = 0.0
                    closed_basket = True

            # Buy Trailing
            if not closed_basket and len(buy_positions) > 0:
                if buy_profit >= target_side or max_buy_profit > 0:
                    if buy_profit > max_buy_profit: max_buy_profit = buy_profit
                    drop = max_buy_profit * (trailing_drop_pct / 100.0)
                    if (max_buy_profit - buy_profit >= drop) or (buy_profit <= target_side * 0.85):
                        for p in buy_positions:
                            prof = get_pos_profit(p, cur_bid, cur_ask)
                            balance += prof
                            trade_history.append({'time': dt, 'profit': prof, 'type': p['type'], 'lot': p['lot'], 'reason': 'BUY_TRAILING'})
                            m_key = dt.strftime('%Y-%m')
                            monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + prof
                        positions = [p for p in positions if p not in buy_positions]
                        max_buy_profit = 0.0
                        buy_positions = []
            if len(buy_positions) == 0:
                max_buy_profit = 0.0

            # Sell Trailing
            if not closed_basket and len(sell_positions) > 0:
                if sell_profit >= target_side or max_sell_profit > 0:
                    if sell_profit > max_sell_profit: max_sell_profit = sell_profit
                    drop = max_sell_profit * (trailing_drop_pct / 100.0)
                    if (max_sell_profit - sell_profit >= drop) or (sell_profit <= target_side * 0.85):
                        for p in sell_positions:
                            prof = get_pos_profit(p, cur_bid, cur_ask)
                            balance += prof
                            trade_history.append({'time': dt, 'profit': prof, 'type': p['type'], 'lot': p['lot'], 'reason': 'SELL_TRAILING'})
                            m_key = dt.strftime('%Y-%m')
                            monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + prof
                        positions = [p for p in positions if p not in sell_positions]
                        max_sell_profit = 0.0
                        sell_positions = []
            if len(sell_positions) == 0:
                max_sell_profit = 0.0

            # 5. Recycling
            if len(buy_positions) > 0 and len(sell_positions) > 0:
                if buy_profit >= target_side:
                    worst_sell = min(sell_positions, key=lambda p: get_pos_profit(p, cur_bid, cur_ask))
                    w_loss = get_pos_profit(worst_sell, cur_bid, cur_ask)
                    if buy_profit > abs(w_loss):
                        recycle_count += 1
                        balance += w_loss
                        trade_history.append({'time': dt, 'profit': w_loss, 'type': worst_sell['type'], 'lot': worst_sell['lot'], 'reason': 'RECYCLE_SELL'})
                        positions = [p for p in positions if p['ticket'] != worst_sell['ticket']]
                        for p in buy_positions:
                            prof = get_pos_profit(p, cur_bid, cur_ask)
                            balance += prof
                            trade_history.append({'time': dt, 'profit': prof, 'type': p['type'], 'lot': p['lot'], 'reason': 'RECYCLE_BUY_CLOSE'})
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
                        trade_history.append({'time': dt, 'profit': w_loss, 'type': worst_buy['type'], 'lot': worst_buy['lot'], 'reason': 'RECYCLE_BUY'})
                        positions = [p for p in positions if p['ticket'] != worst_buy['ticket']]
                        for p in sell_positions:
                            prof = get_pos_profit(p, cur_bid, cur_ask)
                            balance += prof
                            trade_history.append({'time': dt, 'profit': prof, 'type': p['type'], 'lot': p['lot'], 'reason': 'RECYCLE_SELL_CLOSE'})
                        positions = [p for p in positions if p not in sell_positions]
                        sell_positions = []
                        m_key = dt.strftime('%Y-%m')
                        monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + (sell_profit + w_loss)

            # Close dangling hedges if grids empty
            buy_positions = [p for p in positions if p['type'] == 'BUY' and not p['is_hedge']]
            sell_positions = [p for p in positions if p['type'] == 'SELL' and not p['is_hedge']]
            hedge_positions = [p for p in positions if p['is_hedge']]
            if len(buy_positions) == 0 and len(sell_positions) == 0 and len(hedge_positions) > 0:
                for p in hedge_positions:
                    prof = get_pos_profit(p, cur_bid, cur_ask)
                    balance += prof
                    trade_history.append({'time': dt, 'profit': prof, 'type': p['type'], 'lot': p['lot'], 'reason': 'HEDGE_CLEAN'})
                    m_key = dt.strftime('%Y-%m')
                    monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + prof
                positions = []

            if balance > peak_balance: peak_balance = balance

            # 6. Grid Addition (during bar movement)
            if is_trading_time:
                # Buy grid additions
                if len(buy_positions) > 0 and len(buy_positions) < max_total_orders:
                    lowest_buy = min(p['price'] for p in buy_positions)
                    if cur_ask < (lowest_buy - cur_dist):
                        lowest_pos = [p for p in buy_positions if p['price'] == lowest_buy][0]
                        nxt_lot = calc_lot(lowest_pos['lot'], len(buy_positions))
                        ticket_counter += 1
                        positions.append({'type': 'BUY', 'lot': nxt_lot, 'price': cur_ask, 'ticket': ticket_counter, 'time': dt, 'is_hedge': False})
                        buy_positions.append(positions[-1])

                # Sell grid additions
                if len(sell_positions) > 0 and len(sell_positions) < max_total_orders:
                    highest_sell = max(p['price'] for p in sell_positions)
                    if cur_bid > (highest_sell + cur_dist):
                        highest_pos = [p for p in sell_positions if p['price'] == highest_sell][0]
                        nxt_lot = calc_lot(highest_pos['lot'], len(sell_positions))
                        ticket_counter += 1
                        positions.append({'type': 'SELL', 'lot': nxt_lot, 'price': cur_bid, 'ticket': ticket_counter, 'time': dt, 'is_hedge': False})
                        sell_positions.append(positions[-1])

        # 7. Initial Giro Entry at Bar Open
        if is_trading_time:
            open_bid = o
            open_ask = open_bid + spread
            buy_positions = [p for p in positions if p['type'] == 'BUY' and not p['is_hedge']]
            sell_positions = [p for p in positions if p['type'] == 'SELL' and not p['is_hedge']]

            if len(buy_positions) == 0 and (trend_dir >= 0):
                ticket_counter += 1
                positions.append({'type': 'BUY', 'lot': initial_lot, 'price': open_ask, 'ticket': ticket_counter, 'time': dt, 'is_hedge': False})

            if len(sell_positions) == 0 and (trend_dir <= 0):
                ticket_counter += 1
                positions.append({'type': 'SELL', 'lot': initial_lot, 'price': open_bid, 'ticket': ticket_counter, 'time': dt, 'is_hedge': False})

    # Close remaining at the end
    last_row = df_m15.iloc[-1]
    final_bid = last_row['close']
    final_ask = final_bid + spread
    for p in positions:
        prof = get_pos_profit(p, final_bid, final_ask)
        balance += prof
        trade_history.append({'time': last_row['datetime'], 'profit': prof, 'type': p['type'], 'lot': p['lot'], 'reason': 'END_SIM'})

    df_tr = pd.DataFrame(trade_history)
    wins = df_tr[df_tr['profit'] > 0]
    losses = df_tr[df_tr['profit'] < 0]
    win_rate = (len(wins) / len(df_tr) * 100.0) if len(df_tr) > 0 else 0
    gross_profit = wins['profit'].sum() if len(wins) > 0 else 0
    gross_loss = abs(losses['profit'].sum()) if len(losses) > 0 else 0
    profit_factor = (gross_profit / gross_loss) if gross_loss > 0 else (999.0 if gross_profit > 0 else 0)

    return {
        'use_trend_filter': use_trend_filter,
        'base_dist_pts': base_dist_pts,
        'target_side': target_side,
        'target_global': target_global,
        'max_loss_usd': max_loss_usd,
        'initial_balance': 1000.00,
        'final_balance': round(balance, 2),
        'net_profit': round(balance - 1000.00, 2),
        'profit_pct': round(((balance - 1000.00) / 1000.00) * 100.0, 2),
        'max_drawdown_usd': round(max_drawdown_usd, 2),
        'max_drawdown_pct': round(max_drawdown_pct, 2),
        'total_trades': len(df_tr),
        'win_trades': len(wins),
        'loss_trades': len(losses),
        'win_rate': round(win_rate, 2),
        'profit_factor': round(profit_factor, 2),
        'basket_sl_count': basket_sl_count,
        'recycle_count': recycle_count,
        'hedge_opened_count': hedge_opened_count,
        'hedge_tp_count': hedge_tp_count,
        'max_buy_orders': max_buy_orders,
        'max_sell_orders': max_sell_orders,
        'monthly_pnl': monthly_pnl
    }

if __name__ == '__main__':
    print("Loading 2 years of XAUUSD data...")
    pkg = load_data()
    if not pkg:
        exit(1)

    print("\n--- TEST 1: Configuração do Print (Target $5, Dist 500, Filtro EMA 200 ON) ---")
    r1 = run_backtest(pkg, use_trend_filter=True, base_dist_pts=500, target_side=5.0, target_global=10.0, max_loss_usd=80.0)
    for k, v in r1.items():
        if k != 'monthly_pnl':
            print(f"  {k}: {v}")

    print("\n--- TEST 2: Configuração do Print (Target $5, Dist 500, SEM Filtro / Puro Grid) ---")
    r2 = run_backtest(pkg, use_trend_filter=False, base_dist_pts=500, target_side=5.0, target_global=10.0, max_loss_usd=80.0)
    for k, v in r2.items():
        if k != 'monthly_pnl':
            print(f"  {k}: {v}")

    print("\n--- TEST 3: Configuração Especial Ouro V43 (Target $5, Dist 800 pts / $8 Ouro, TF ON) ---")
    r3 = run_backtest(pkg, use_trend_filter=True, base_dist_pts=800, target_side=5.0, target_global=10.0, max_loss_usd=80.0)
    for k, v in r3.items():
        if k != 'monthly_pnl':
            print(f"  {k}: {v}")
