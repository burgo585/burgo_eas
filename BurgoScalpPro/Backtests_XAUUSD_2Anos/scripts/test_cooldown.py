import MetaTrader5 as mt5
import pandas as pd
import datetime

def load_data():
    if not mt5.initialize(path=r"C:\Program Files\MetaTrader 5\terminal64.exe"):
        print("MT5 init failed")
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

    hl = df_m15['high'] - df_m15['low']
    hc = (df_m15['high'] - df_m15['close'].shift()).abs()
    lc = (df_m15['low'] - df_m15['close'].shift()).abs()
    tr = pd.concat([hl, hc, lc], axis=1).max(axis=1)
    df_m15['atr14'] = tr.rolling(window=14).mean()

    df_h1 = pd.DataFrame(rates_h1)
    df_h1['datetime'] = pd.to_datetime(df_h1['time'], unit='s')
    df_h1['ema200'] = df_h1['close'].ewm(span=200, adjust=False).mean()

    df_m15['h1_time'] = df_m15['datetime'].dt.floor('1h')
    h1_map = df_h1.set_index('datetime')[['ema200', 'close']].to_dict('index')

    return {
        'df_m15': df_m15,
        'h1_map': h1_map,
        'point': info.point,
        'spread_pts': info.spread,
        'contract_size': info.trade_contract_size
    }

def run_simulation(data_pkg, cooldown_mins=60, max_daily_loss=160.0, use_tf=False, target_side=5.0, target_global=10.0):
    df_m15 = data_pkg['df_m15']
    h1_map = data_pkg['h1_map']
    point = data_pkg['point']
    spread = data_pkg['spread_pts'] * point
    contract_size = data_pkg['contract_size']

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
    cooldown_until = None
    daily_loss_tracker = {}
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
        d_key = dt.strftime('%Y-%m-%d')

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

        # Intra-bar simulation
        price_sequence = [(o, 'open'), (l, 'low'), (h, 'high'), (c, 'close')] if c >= o else [(o, 'open'), (h, 'high'), (l, 'low'), (c, 'close')]

        for p_val, step_type in price_sequence:
            cur_bid = p_val
            cur_ask = cur_bid + spread

            buy_positions = [p for p in positions if p['type'] == 'BUY']
            sell_positions = [p for p in positions if p['type'] == 'SELL']

            buy_profit = sum(get_pos_profit(p, cur_bid, cur_ask) for p in buy_positions)
            sell_profit = sum(get_pos_profit(p, cur_bid, cur_ask) for p in sell_positions)
            total_floating = buy_profit + sell_profit

            cur_equity = balance + total_floating
            if cur_equity > peak_balance: peak_balance = cur_equity
            dd = peak_balance - cur_equity
            if dd > max_drawdown_usd: max_drawdown_usd = dd

            # 1. Stop Loss da Cesta
            if total_floating <= -abs(max_loss_usd):
                basket_sl_count += 1
                for p in positions:
                    prf = get_pos_profit(p, cur_bid, cur_ask)
                    balance += prf
                    m_key = dt.strftime('%Y-%m')
                    monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + prf
                    daily_loss_tracker[d_key] = daily_loss_tracker.get(d_key, 0.0) + prf
                    trade_history.append({'profit': prf, 'time': dt, 'reason': 'BASKET_SL'})
                positions = []
                # Aciona Cooldown
                if cooldown_mins > 0:
                    cooldown_until = dt + datetime.timedelta(minutes=cooldown_mins)
                continue

            # 2. Alvo Global Fixo
            if total_floating >= target_global:
                for p in positions:
                    prf = get_pos_profit(p, cur_bid, cur_ask)
                    balance += prf
                    m_key = dt.strftime('%Y-%m')
                    monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + prf
                    daily_loss_tracker[d_key] = daily_loss_tracker.get(d_key, 0.0) + prf
                    trade_history.append({'profit': prf, 'time': dt, 'reason': 'GLOBAL_TP'})
                positions = []
                continue

            # 3. Reciclagem Buy
            if buy_profit >= target_side and len(sell_positions) > 0:
                worst_sell = min(sell_positions, key=lambda p: get_pos_profit(p, cur_bid, cur_ask))
                worst_loss = get_pos_profit(worst_sell, cur_bid, cur_ask)
                if buy_profit + worst_loss > 0:
                    recycle_count += 1
                    for p in buy_positions:
                        prf = get_pos_profit(p, cur_bid, cur_ask)
                        balance += prf
                        m_key = dt.strftime('%Y-%m')
                        monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + prf
                        daily_loss_tracker[d_key] = daily_loss_tracker.get(d_key, 0.0) + prf
                        trade_history.append({'profit': prf, 'time': dt, 'reason': 'RECYCLE_WIN'})
                    balance += worst_loss
                    m_key = dt.strftime('%Y-%m')
                    monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + worst_loss
                    daily_loss_tracker[d_key] = daily_loss_tracker.get(d_key, 0.0) + worst_loss
                    trade_history.append({'profit': worst_loss, 'time': dt, 'reason': 'RECYCLE_LOSS'})
                    positions = [p for p in positions if p['ticket'] not in [bp['ticket'] for bp in buy_positions] and p['ticket'] != worst_sell['ticket']]
                    continue

            # 4. Reciclagem Sell
            if sell_profit >= target_side and len(buy_positions) > 0:
                worst_buy = min(buy_positions, key=lambda p: get_pos_profit(p, cur_bid, cur_ask))
                worst_loss = get_pos_profit(worst_buy, cur_bid, cur_ask)
                if sell_profit + worst_loss > 0:
                    recycle_count += 1
                    for p in sell_positions:
                        prf = get_pos_profit(p, cur_bid, cur_ask)
                        balance += prf
                        m_key = dt.strftime('%Y-%m')
                        monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + prf
                        daily_loss_tracker[d_key] = daily_loss_tracker.get(d_key, 0.0) + prf
                        trade_history.append({'profit': prf, 'time': dt, 'reason': 'RECYCLE_WIN'})
                    balance += worst_loss
                    m_key = dt.strftime('%Y-%m')
                    monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + worst_loss
                    daily_loss_tracker[d_key] = daily_loss_tracker.get(d_key, 0.0) + worst_loss
                    trade_history.append({'profit': worst_loss, 'time': dt, 'reason': 'RECYCLE_LOSS'})
                    positions = [p for p in positions if p['ticket'] not in [sp['ticket'] for sp in sell_positions] and p['ticket'] != worst_buy['ticket']]
                    continue

            # 5. Fechamento por Alvo do Lado
            if buy_profit >= target_side:
                for p in buy_positions:
                    prf = get_pos_profit(p, cur_bid, cur_ask)
                    balance += prf
                    m_key = dt.strftime('%Y-%m')
                    monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + prf
                    daily_loss_tracker[d_key] = daily_loss_tracker.get(d_key, 0.0) + prf
                    trade_history.append({'profit': prf, 'time': dt, 'reason': 'SIDE_TP'})
                positions = [p for p in positions if p['type'] != 'BUY']
                continue

            if sell_profit >= target_side:
                for p in sell_positions:
                    prf = get_pos_profit(p, cur_bid, cur_ask)
                    balance += prf
                    m_key = dt.strftime('%Y-%m')
                    monthly_pnl[m_key] = monthly_pnl.get(m_key, 0.0) + prf
                    daily_loss_tracker[d_key] = daily_loss_tracker.get(d_key, 0.0) + prf
                    trade_history.append({'profit': prf, 'time': dt, 'reason': 'SIDE_TP'})
                positions = [p for p in positions if p['type'] != 'SELL']
                continue

            # 6. Ordens de Grid
            if is_trading_time:
                buy_positions = [p for p in positions if p['type'] == 'BUY']
                sell_positions = [p for p in positions if p['type'] == 'SELL']
                if len(buy_positions) > 0 and len(buy_positions) < max_total_orders:
                    lowest_buy = min(p['price'] for p in buy_positions)
                    if cur_ask < (lowest_buy - cur_dist):
                        lowest_pos = [p for p in buy_positions if p['price'] == lowest_buy][0]
                        nxt_lot = calc_lot(lowest_pos['lot'], len(buy_positions))
                        ticket_counter += 1
                        positions.append({'type': 'BUY', 'lot': nxt_lot, 'price': cur_ask, 'ticket': ticket_counter, 'time': dt})
                if len(sell_positions) > 0 and len(sell_positions) < max_total_orders:
                    highest_sell = max(p['price'] for p in sell_positions)
                    if cur_bid > (highest_sell + cur_dist):
                        highest_pos = [p for p in sell_positions if p['price'] == highest_sell][0]
                        nxt_lot = calc_lot(highest_pos['lot'], len(sell_positions))
                        ticket_counter += 1
                        positions.append({'type': 'SELL', 'lot': nxt_lot, 'price': cur_bid, 'ticket': ticket_counter, 'time': dt})

        # 7. Novos Giros (Apenas se não estiver em Cooldown e não tiver estourado o Hard Stop diário)
        in_cooldown = (cooldown_until is not None and dt < cooldown_until)
        hit_daily_stop = (max_daily_loss > 0 and daily_loss_tracker.get(d_key, 0.0) <= -abs(max_daily_loss))

        if is_trading_time and not in_cooldown and not hit_daily_stop:
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

    print(f"\n--- Cooldown: {cooldown_mins}m, HardStop Diário: ${max_daily_loss}, Filtro Tendência: {use_tf} ---")
    print(f"Saldo Final: ${balance:.2f} | Lucro Líquido: ${balance-1000:.2f} | PF: {pf:.2f} | WinRate: {win_rate:.2f}% | Max DD: ${max_drawdown_usd:.2f} | Stops Cesta: {basket_sl_count} | Reciclagens: {recycle_count}")
    return balance

if __name__ == '__main__':
    pkg = load_data()
    # Teste 1: Cooldown 60 min, HardStop Diário $160 (2 cestas), Sem Filtro Tendência
    run_simulation(pkg, cooldown_mins=60, max_daily_loss=160.0, use_tf=False)
    # Teste 2: Cooldown 30 min, HardStop Diário $160, Sem Filtro Tendência
    run_simulation(pkg, cooldown_mins=30, max_daily_loss=160.0, use_tf=False)
    # Teste 3: Cooldown 60 min, HardStop Diário $160, COM Filtro Tendência EMA 200
    run_simulation(pkg, cooldown_mins=60, max_daily_loss=160.0, use_tf=True)
    # Teste 4: SEM Cooldown e SEM HardStop (O que quebrou no MT5)
    run_simulation(pkg, cooldown_mins=0, max_daily_loss=0.0, use_tf=False)
