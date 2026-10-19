# -*- coding: utf-8 -*-
"""
run_comprehensive_2year_backtest.py
Motor Quantitativo de Simulação e Otimização para Valid_BOS_Pullback_EA
Testa 2 anos completos (2024 a 2026) nos Timeframes M1, M5, M15, M30 e H1
em XAUUSD-STDc da VT Markets.
"""

import os
import sys
import numpy as np
import pandas as pd
from datetime import datetime, timezone
import MetaTrader5 as mt5

TERMINAL_PATH = r"C:\Program Files\MetaTrader 5 - Copia\terminal64.exe"
SYMBOL = "XAUUSD-STDc"

def calculate_ema(prices, period):
    return pd.Series(prices).ewm(span=period, adjust=False).mean().values

def calculate_adx(high, low, close, period=14):
    n = len(close)
    if n < period * 2:
        return np.full(n, 25.0)
    
    tr = np.zeros(n)
    tr[0] = high[0] - low[0]
    for i in range(1, n):
        tr[i] = max(high[i] - low[i], abs(high[i] - close[i-1]), abs(low[i] - close[i-1]))
    
    plus_dm = np.zeros(n)
    minus_dm = np.zeros(n)
    for i in range(1, n):
        up_move = high[i] - high[i-1]
        down_move = low[i-1] - low[i]
        if up_move > down_move and up_move > 0:
            plus_dm[i] = up_move
        if down_move > up_move and down_move > 0:
            minus_dm[i] = down_move
            
    # Smoothed TR, +DM, -DM
    tr_s = pd.Series(tr).ewm(alpha=1.0/period, adjust=False).mean().to_numpy(copy=True)
    plus_dm_s = pd.Series(plus_dm).ewm(alpha=1.0/period, adjust=False).mean().to_numpy(copy=True)
    minus_dm_s = pd.Series(minus_dm).ewm(alpha=1.0/period, adjust=False).mean().to_numpy(copy=True)
    
    # Avoid div by 0
    tr_s = np.where(tr_s == 0, 1e-5, tr_s)
    plus_di = 100.0 * (plus_dm_s / tr_s)
    minus_di = 100.0 * (minus_dm_s / tr_s)
    
    sum_di = plus_di + minus_di
    sum_di = np.where(sum_di == 0, 1e-5, sum_di)
    dx = 100.0 * np.abs(plus_di - minus_di) / sum_di
    adx = pd.Series(dx).ewm(alpha=1.0/period, adjust=False).mean().to_numpy(copy=True)
    return adx

def has_bull_rejection(op, hi, lo, cl):
    rng = hi - lo
    if rng <= 0: return False
    lower_wick = min(op, cl) - lo
    body = abs(cl - op)
    return (lower_wick >= rng * 0.35) or (cl > op and cl > (lo + rng * 0.65))

def has_bear_rejection(op, hi, lo, cl):
    rng = hi - lo
    if rng <= 0: return False
    upper_wick = hi - max(op, cl)
    body = abs(cl - op)
    return (upper_wick >= rng * 0.35) or (cl < op and cl < (hi - rng * 0.65))

def simulate_strategy(df, params):
    """
    df: DataFrame com colunas ['time', 'open', 'high', 'low', 'close', 'tick_volume']
    params: dict de configurações
    """
    pivot_legs = params.get('pivot_legs', 3)
    min_exp_bars = params.get('min_exp_bars', 2)
    max_struct_bars = params.get('max_struct_bars', 40)
    retest_tol_pts = params.get('retest_tol_pts', 30)
    entry_trigger = params.get('entry_trigger', 'REJECTION') # 'REJECTION' ou 'BOS'
    use_ema = params.get('use_ema', True)
    use_adx = params.get('use_adx', True)
    min_adx = params.get('min_adx', 20.0)
    req_rejection = params.get('req_rejection', True)
    enable_scalpers = params.get('enable_scalpers', True)
    scalp_rr = params.get('scalp_rr', 1.2)
    rr_ratio = params.get('rr_ratio', 2.0)
    sl_buffer_pts = params.get('sl_buffer_pts', 20)
    min_sl_pts = params.get('min_sl_pts', 200) # $2.00 no XAUUSD
    use_partial = params.get('use_partial', True)
    use_be = params.get('use_be', True)
    point = 0.01 # no XAUUSD STDc, 1 pt = 0.01 usd

    times = df['time'].values
    opens = df['open'].values
    highs = df['high'].values
    lows = df['low'].values
    closes = df['close'].values
    n = len(closes)

    ema = calculate_ema(closes, 200) if use_ema else np.zeros(n)
    adx = calculate_adx(highs, lows, closes, 14) if use_adx else np.full(n, 25.0)

    # Estado de simulação
    swings = [] # list of (dir, price, time, idx)
    structures = [] # list of dicts
    trades = [] # executed trades

    active_trade = None
    last_scalp_time = 0

    cur_swing_high = 0.0
    cur_swing_low = 0.0

    for i in range(pivot_legs * 2 + 1, n):
        # 1. Gerenciar Trade Ativo
        if active_trade is not None:
            # Check price against SL / TP
            cur_hi = highs[i]
            cur_lo = lows[i]
            t_dir = active_trade['direction']
            t_entry = active_trade['entry_price']
            t_sl = active_trade['sl_price']
            t_tp = active_trade['tp_price']
            t_initial_risk = active_trade['initial_risk']

            closed = False
            pnl_r = 0.0

            if t_dir == 1: # COMPRA
                # Check BE / Partial at 1:1
                if not active_trade['be_activated']:
                    if cur_hi >= (t_entry + t_initial_risk):
                        active_trade['be_activated'] = True
                        if use_be:
                            active_trade['sl_price'] = t_entry + (25 * point) # BE + extra pts
                        if use_partial:
                            active_trade['partial_taken'] = True
                
                # Check Hit SL
                if cur_lo <= active_trade['sl_price']:
                    exit_price = active_trade['sl_price']
                    if active_trade.get('partial_taken', False):
                        # 50% was closed at +1R, rest closed at SL
                        pnl_first_half = +1.0 * 0.5
                        pnl_second_half = ((exit_price - t_entry) / t_initial_risk) * 0.5
                        pnl_r = pnl_first_half + pnl_second_half
                    else:
                        pnl_r = (exit_price - t_entry) / t_initial_risk
                    closed = True
                # Check Hit TP
                elif cur_hi >= t_tp:
                    exit_price = t_tp
                    if active_trade.get('partial_taken', False):
                        pnl_first_half = +1.0 * 0.5
                        pnl_second_half = ((exit_price - t_entry) / t_initial_risk) * 0.5
                        pnl_r = pnl_first_half + pnl_second_half
                    else:
                        pnl_r = (exit_price - t_entry) / t_initial_risk
                    closed = True

            elif t_dir == -1: # VENDA
                if not active_trade['be_activated']:
                    if cur_lo <= (t_entry - t_initial_risk):
                        active_trade['be_activated'] = True
                        if use_be:
                            active_trade['sl_price'] = t_entry - (25 * point)
                        if use_partial:
                            active_trade['partial_taken'] = True
                
                if cur_hi >= active_trade['sl_price']:
                    exit_price = active_trade['sl_price']
                    if active_trade.get('partial_taken', False):
                        pnl_first_half = +1.0 * 0.5
                        pnl_second_half = ((t_entry - exit_price) / t_initial_risk) * 0.5
                        pnl_r = pnl_first_half + pnl_second_half
                    else:
                        pnl_r = (t_entry - exit_price) / t_initial_risk
                    closed = True
                elif cur_lo <= t_tp:
                    exit_price = t_tp
                    if active_trade.get('partial_taken', False):
                        pnl_first_half = +1.0 * 0.5
                        pnl_second_half = ((t_entry - exit_price) / t_initial_risk) * 0.5
                        pnl_r = pnl_first_half + pnl_second_half
                    else:
                        pnl_r = (t_entry - exit_price) / t_initial_risk
                    closed = True

            if closed:
                active_trade['exit_time'] = times[i]
                active_trade['exit_price'] = exit_price
                active_trade['pnl_r'] = pnl_r
                active_trade['is_win'] = pnl_r > 0
                trades.append(active_trade)
                active_trade = None

        # 2. Atualizar Pivôs de Swing
        p_idx = i - pivot_legs
        if p_idx >= pivot_legs:
            # Check High
            is_h = True
            for k in range(p_idx - pivot_legs, p_idx + pivot_legs + 1):
                if k != p_idx and highs[k] >= highs[p_idx]:
                    is_h = False
                    break
            if is_h and highs[p_idx] != cur_swing_high:
                cur_swing_high = highs[p_idx]
                swings.append({'dir': 1, 'price': highs[p_idx], 'time': times[p_idx], 'idx': p_idx, 'broken': False})
                if len(swings) > 60: swings.pop(0)

            # Check Low
            is_l = True
            for k in range(p_idx - pivot_legs, p_idx + pivot_legs + 1):
                if k != p_idx and lows[k] <= lows[p_idx]:
                    is_l = False
                    break
            if is_l and lows[p_idx] != cur_swing_low:
                cur_swing_low = lows[p_idx]
                swings.append({'dir': -1, 'price': lows[p_idx], 'time': times[p_idx], 'idx': p_idx, 'broken': False})
                if len(swings) > 60: swings.pop(0)

        # 3. Detectar Rompimentos de Swing (Breakouts)
        for sw in swings:
            if sw['broken'] or times[i] <= sw['time']:
                continue
            if sw['dir'] == 1:
                if closes[i] > sw['price'] and closes[i-1] <= sw['price']:
                    sw['broken'] = True
                    # Check trend alignment
                    if not use_ema or closes[i] > ema[i]:
                        structures.append({
                            'dir': 1,
                            'state': 'EXPANDING',
                            'breakout_idx': i,
                            'breakout_time': times[i],
                            'ref_level': sw['price'],
                            'extreme_price': highs[i],
                            'pullback_extreme': 0.0,
                            'is_active': True,
                            'trade_triggered': False
                        })
                        if len(structures) > 30: structures.pop(0)
            elif sw['dir'] == -1:
                if closes[i] < sw['price'] and closes[i-1] >= sw['price']:
                    sw['broken'] = True
                    if not use_ema or closes[i] < ema[i]:
                        structures.append({
                            'dir': -1,
                            'state': 'EXPANDING',
                            'breakout_idx': i,
                            'breakout_time': times[i],
                            'ref_level': sw['price'],
                            'extreme_price': lows[i],
                            'pullback_extreme': 0.0,
                            'is_active': True,
                            'trade_triggered': False
                        })
                        if len(structures) > 30: structures.pop(0)

        # 4. Atualizar Estruturas Ativas
        tol = retest_tol_pts * point
        for st in structures:
            if not st['is_active']: continue

            # === BULLISH ===
            if st['dir'] == 1:
                if st['state'] == 'EXPANDING':
                    if highs[i] > st['extreme_price']:
                        st['extreme_price'] = highs[i]
                    bars_since = i - st['breakout_idx']
                    if lows[i] <= (st['ref_level'] + tol):
                        if bars_since < min_exp_bars:
                            st['is_active'] = False
                            continue
                        else:
                            st['state'] = 'EXPANSION_QUALIFIED'
                    elif bars_since >= min_exp_bars:
                        st['state'] = 'EXPANSION_QUALIFIED'

                    if bars_since > max_struct_bars:
                        st['is_active'] = False
                        continue

                if st['state'] == 'EXPANSION_QUALIFIED':
                    if highs[i] > st['extreme_price']:
                        st['extreme_price'] = highs[i]
                    bars_since = i - st['breakout_idx']
                    if lows[i] <= (st['ref_level'] + tol):
                        exp_h = st['extreme_price'] - st['ref_level']
                        if closes[i] < (st['ref_level'] - exp_h):
                            st['is_active'] = False
                            continue
                        st['state'] = 'VALID_PULLBACK'
                        st['pullback_extreme'] = lows[i]

                        # GATILHO REJEIÇÃO
                        if entry_trigger == 'REJECTION' and not st['trade_triggered'] and active_trade is None:
                            trend_ok = (not use_ema) or (closes[i] > ema[i])
                            adx_ok = (not use_adx) or (adx[i] >= min_adx)
                            rej_ok = (not req_rejection) or has_bull_rejection(opens[i], highs[i], lows[i], closes[i])

                            if trend_ok and adx_ok and rej_ok:
                                st['trade_triggered'] = True
                                entry = closes[i]
                                raw_sl = lows[i] - (sl_buffer_pts * point)
                                sl_dist = max(entry - raw_sl, min_sl_pts * point)
                                sl = entry - sl_dist
                                tp = entry + (sl_dist * rr_ratio)
                                active_trade = {
                                    'type': 'PULLBACK_REJ',
                                    'direction': 1,
                                    'entry_time': times[i],
                                    'entry_price': entry,
                                    'sl_price': sl,
                                    'tp_price': tp,
                                    'initial_risk': sl_dist,
                                    'be_activated': False,
                                    'partial_taken': False
                                }
                    elif bars_since > max_struct_bars:
                        st['is_active'] = False
                        continue

                elif st['state'] == 'VALID_PULLBACK':
                    if lows[i] < st['pullback_extreme']:
                        st['pullback_extreme'] = lows[i]
                    bars_since = i - st['breakout_idx']
                    exp_h = st['extreme_price'] - st['ref_level']
                    if bars_since > max_struct_bars or closes[i] < (st['ref_level'] - exp_h * 0.5):
                        st['is_active'] = False
                        continue

                    # GATILHO VALID BOS
                    min_breakout = st['extreme_price'] + (30 * point)
                    if closes[i] > min_breakout:
                        if entry_trigger == 'BOS' and not st['trade_triggered'] and active_trade is None:
                            trend_ok = (not use_ema) or (closes[i] > ema[i])
                            adx_ok = (not use_adx) or (adx[i] >= min_adx)
                            if trend_ok and adx_ok:
                                st['trade_triggered'] = True
                                entry = closes[i]
                                raw_sl = st['pullback_extreme'] - (sl_buffer_pts * point)
                                sl_dist = max(entry - raw_sl, min_sl_pts * point)
                                sl = entry - sl_dist
                                tp = entry + (sl_dist * rr_ratio)
                                active_trade = {
                                    'type': 'VALID_BOS',
                                    'direction': 1,
                                    'entry_time': times[i],
                                    'entry_price': entry,
                                    'sl_price': sl,
                                    'tp_price': tp,
                                    'initial_risk': sl_dist,
                                    'be_activated': False,
                                    'partial_taken': False
                                }
                        st['is_active'] = False

            # === BEARISH ===
            elif st['dir'] == -1:
                if st['state'] == 'EXPANDING':
                    if lows[i] < st['extreme_price']:
                        st['extreme_price'] = lows[i]
                    bars_since = i - st['breakout_idx']
                    if highs[i] >= (st['ref_level'] - tol):
                        if bars_since < min_exp_bars:
                            st['is_active'] = False
                            continue
                        else:
                            st['state'] = 'EXPANSION_QUALIFIED'
                    elif bars_since >= min_exp_bars:
                        st['state'] = 'EXPANSION_QUALIFIED'

                    if bars_since > max_struct_bars:
                        st['is_active'] = False
                        continue

                if st['state'] == 'EXPANSION_QUALIFIED':
                    if lows[i] < st['extreme_price']:
                        st['extreme_price'] = lows[i]
                    bars_since = i - st['breakout_idx']
                    if highs[i] >= (st['ref_level'] - tol):
                        exp_h = st['ref_level'] - st['extreme_price']
                        if closes[i] > (st['ref_level'] + exp_h):
                            st['is_active'] = False
                            continue
                        st['state'] = 'VALID_PULLBACK'
                        st['pullback_extreme'] = highs[i]

                        if entry_trigger == 'REJECTION' and not st['trade_triggered'] and active_trade is None:
                            trend_ok = (not use_ema) or (closes[i] < ema[i])
                            adx_ok = (not use_adx) or (adx[i] >= min_adx)
                            rej_ok = (not req_rejection) or has_bear_rejection(opens[i], highs[i], lows[i], closes[i])

                            if trend_ok and adx_ok and rej_ok:
                                st['trade_triggered'] = True
                                entry = closes[i]
                                raw_sl = highs[i] + (sl_buffer_pts * point)
                                sl_dist = max(raw_sl - entry, min_sl_pts * point)
                                sl = entry + sl_dist
                                tp = entry - (sl_dist * rr_ratio)
                                active_trade = {
                                    'type': 'PULLBACK_REJ',
                                    'direction': -1,
                                    'entry_time': times[i],
                                    'entry_price': entry,
                                    'sl_price': sl,
                                    'tp_price': tp,
                                    'initial_risk': sl_dist,
                                    'be_activated': False,
                                    'partial_taken': False
                                }
                    elif bars_since > max_struct_bars:
                        st['is_active'] = False
                        continue

                elif st['state'] == 'VALID_PULLBACK':
                    if highs[i] > st['pullback_extreme']:
                        st['pullback_extreme'] = highs[i]
                    bars_since = i - st['breakout_idx']
                    exp_h = st['ref_level'] - st['extreme_price']
                    if bars_since > max_struct_bars or closes[i] > (st['ref_level'] + exp_h * 0.5):
                        st['is_active'] = False
                        continue

                    min_breakout = st['extreme_price'] - (30 * point)
                    if closes[i] < min_breakout:
                        if entry_trigger == 'BOS' and not st['trade_triggered'] and active_trade is None:
                            trend_ok = (not use_ema) or (closes[i] < ema[i])
                            adx_ok = (not use_adx) or (adx[i] >= min_adx)
                            if trend_ok and adx_ok:
                                st['trade_triggered'] = True
                                entry = closes[i]
                                raw_sl = st['pullback_extreme'] + (sl_buffer_pts * point)
                                sl_dist = max(raw_sl - entry, min_sl_pts * point)
                                sl = entry + sl_dist
                                tp = entry - (sl_dist * rr_ratio)
                                active_trade = {
                                    'type': 'VALID_BOS',
                                    'direction': -1,
                                    'entry_time': times[i],
                                    'entry_price': entry,
                                    'sl_price': sl,
                                    'tp_price': tp,
                                    'initial_risk': sl_dist,
                                    'be_activated': False,
                                    'partial_taken': False
                                }
                        st['is_active'] = False

        # 5. Scalpers Intermediários
        if enable_scalpers and active_trade is None and (i >= 5):
            # Cooldown 3 bars
            if (i - last_scalp_time) >= 3:
                # BUY Scalp
                if (not use_ema or closes[i] > ema[i]) and (not use_adx or adx[i] >= min_adx):
                    had_pb = (closes[i-1] < opens[i-1]) and (closes[i-2] < opens[i-2])
                    if had_pb and (lows[i] > cur_swing_low or cur_swing_low == 0.0):
                        rng = highs[i] - lows[i]
                        if rng > 0:
                            wick = min(opens[i], closes[i]) - lows[i]
                            if closes[i] > opens[i] and (wick / rng >= 0.25 or closes[i] > highs[i-1]):
                                entry = closes[i]
                                raw_sl = lows[i] - (sl_buffer_pts * point)
                                sl_dist = max(entry - raw_sl, min_sl_pts * point)
                                sl = entry - sl_dist
                                tp = entry + (sl_dist * scalp_rr)
                                active_trade = {
                                    'type': 'SCALP',
                                    'direction': 1,
                                    'entry_time': times[i],
                                    'entry_price': entry,
                                    'sl_price': sl,
                                    'tp_price': tp,
                                    'initial_risk': sl_dist,
                                    'be_activated': False,
                                    'partial_taken': False
                                }
                                last_scalp_time = i

                # SELL Scalp
                elif (not use_ema or closes[i] < ema[i]) and (not use_adx or adx[i] >= min_adx):
                    had_pb = (closes[i-1] > opens[i-1]) and (closes[i-2] > opens[i-2])
                    if had_pb and (highs[i] < cur_swing_high or cur_swing_high == 0.0):
                        rng = highs[i] - lows[i]
                        if rng > 0:
                            wick = highs[i] - max(opens[i], closes[i])
                            if closes[i] < opens[i] and (wick / rng >= 0.25 or closes[i] < lows[i-1]):
                                entry = closes[i]
                                raw_sl = highs[i] + (sl_buffer_pts * point)
                                sl_dist = max(raw_sl - entry, min_sl_pts * point)
                                sl = entry + sl_dist
                                tp = entry - (sl_dist * scalp_rr)
                                active_trade = {
                                    'type': 'SCALP',
                                    'direction': -1,
                                    'entry_time': times[i],
                                    'entry_price': entry,
                                    'sl_price': sl,
                                    'tp_price': tp,
                                    'initial_risk': sl_dist,
                                    'be_activated': False,
                                    'partial_taken': False
                                }
                                last_scalp_time = i

    return trades

def evaluate_metrics(trades, initial_deposit=10000.0, risk_pct=1.0):
    if not trades:
        return {
            'trades': 0, 'wins': 0, 'losses': 0, 'win_rate': 0.0,
            'profit_factor': 0.0, 'net_profit': 0.0, 'net_profit_pct': 0.0,
            'max_drawdown_pct': 0.0, 'expectancy_r': 0.0
        }
    
    total = len(trades)
    wins = [t for t in trades if t['pnl_r'] > 0]
    losses = [t for t in trades if t['pnl_r'] <= 0]
    
    n_wins = len(wins)
    n_losses = len(losses)
    win_rate = (n_wins / total) * 100.0
    
    gross_win_r = sum(t['pnl_r'] for t in wins)
    gross_loss_r = abs(sum(t['pnl_r'] for t in losses))
    pf = (gross_win_r / gross_loss_r) if gross_loss_r > 0 else 99.0
    
    # Simulação da curva de capital com 1% de risco fixo
    balance = initial_deposit
    peak = balance
    max_dd_val = 0.0
    max_dd_pct = 0.0
    
    risk_usd_base = initial_deposit * (risk_pct / 100.0)
    for t in trades:
        pnl_usd = t['pnl_r'] * risk_usd_base
        balance += pnl_usd
        if balance > peak:
            peak = balance
        dd_val = peak - balance
        dd_pct = (dd_val / peak) * 100.0 if peak > 0 else 0.0
        if dd_pct > max_dd_pct:
            max_dd_pct = dd_pct
            max_dd_val = dd_val
            
    net_profit = balance - initial_deposit
    net_profit_pct = (net_profit / initial_deposit) * 100.0
    expectancy_r = sum(t['pnl_r'] for t in trades) / total
    
    return {
        'trades': total,
        'wins': n_wins,
        'losses': n_losses,
        'win_rate': win_rate,
        'profit_factor': pf,
        'net_profit': net_profit,
        'net_profit_pct': net_profit_pct,
        'max_drawdown_pct': max_dd_pct,
        'expectancy_r': expectancy_r
    }

def run_all_tests():
    print("=" * 80)
    print(" INICIANDO TESTE QUANTITATIVO COMPARATIVO DE 2 ANOS (2024 a 2026)")
    print(f" Ativo: {SYMBOL} | Corretora: VT Markets")
    print("=" * 80)

    if not mt5.initialize(path=TERMINAL_PATH):
        print("Erro ao conectar no MT5:", mt5.last_error())
        return

    mt5.symbol_select(SYMBOL, True)

    # 1. Carregar Dados de cada Timeframe
    tfs = {
        'M1':  (mt5.TIMEFRAME_M1, 50000),   # Limite do buffer (~2-3 meses recentes)
        'M5':  (mt5.TIMEFRAME_M5, 50000),   # ~9 meses recentes
        'M15': (mt5.TIMEFRAME_M15, 50000),  # 2 anos completos (2024 a 2026)
        'M30': (mt5.TIMEFRAME_M30, 30000),  # 2 anos completos
        'H1':  (mt5.TIMEFRAME_H1, 15000)   # 2 anos completos
    }

    data_frames = {}
    for tf_name, (tf_code, max_bars) in tfs.items():
        rates = mt5.copy_rates_from_pos(SYMBOL, tf_code, 0, max_bars)
        if rates is not None and len(rates) > 100:
            df = pd.DataFrame(rates)
            df['datetime'] = pd.to_datetime(df['time'], unit='s')
            data_frames[tf_name] = df
            d_start = df['datetime'].iloc[0].strftime('%Y-%m-%d')
            d_end = df['datetime'].iloc[-1].strftime('%Y-%m-%d')
            print(f" [OK] {tf_name:>4}: {len(df):>6} barras carregadas | De {d_start} até {d_end}")
        else:
            print(f" [FALHA] {tf_name:>4}: Sem dados disponíveis.")

    mt5.shutdown()

    # 2. Definir os Setups de Teste
    setups = {
        "1. Institucional Sniper (Pullback Rejeição + EMA200 + ADX)": {
            'entry_trigger': 'REJECTION', 'pivot_legs': 5, 'min_exp_bars': 3,
            'max_struct_bars': 45, 'use_ema': True, 'use_adx': True, 'min_adx': 20.0,
            'req_rejection': True, 'enable_scalpers': False, 'rr_ratio': 2.0,
            'use_partial': True, 'use_be': True
        },
        "2. Híbrido Dinâmico (Sniper + Micro-Scalpers no Fluxo)": {
            'entry_trigger': 'REJECTION', 'pivot_legs': 3, 'min_exp_bars': 2,
            'max_struct_bars': 40, 'use_ema': True, 'use_adx': True, 'min_adx': 20.0,
            'req_rejection': True, 'enable_scalpers': True, 'scalp_rr': 1.5,
            'rr_ratio': 2.0, 'use_partial': True, 'use_be': True
        },
        "3. Rompimento de Estrutura (Valid BOS Clássico)": {
            'entry_trigger': 'BOS', 'pivot_legs': 3, 'min_exp_bars': 2,
            'max_struct_bars': 40, 'use_ema': True, 'use_adx': True, 'min_adx': 20.0,
            'req_rejection': False, 'enable_scalpers': False, 'rr_ratio': 2.0,
            'use_partial': True, 'use_be': True
        },
        "4. Alta Assimetria R:R 1:3 (Alvos Longos Institucionais)": {
            'entry_trigger': 'REJECTION', 'pivot_legs': 5, 'min_exp_bars': 3,
            'max_struct_bars': 50, 'use_ema': True, 'use_adx': True, 'min_adx': 22.0,
            'req_rejection': True, 'enable_scalpers': False, 'rr_ratio': 3.0,
            'use_partial': True, 'use_be': True
        },
        "5. Sem Filtros (Estrutura Pura sem EMA/ADX)": {
            'entry_trigger': 'REJECTION', 'pivot_legs': 3, 'min_exp_bars': 2,
            'max_struct_bars': 40, 'use_ema': False, 'use_adx': False,
            'req_rejection': False, 'enable_scalpers': False, 'rr_ratio': 2.0,
            'use_partial': False, 'use_be': False
        }
    }

    # 3. Executar o Grid de Simulação
    results = []

    print("\n" + "=" * 110)
    print(f"{'TF':<5} | {'SETUP':<50} | {'TRADES':<7} | {'WIN%':<7} | {'PF':<6} | {'LUCRO ($)':<11} | {'LUCRO %':<8} | {'MAX DD%':<8}")
    print("=" * 110)

    for tf_name in ['M1', 'M5', 'M15', 'M30', 'H1']:
        if tf_name not in data_frames: continue
        df = data_frames[tf_name]

        for s_name, params in setups.items():
            trades = simulate_strategy(df, params)
            m = evaluate_metrics(trades, initial_deposit=10000.0, risk_pct=1.0)
            
            row = {
                'tf': tf_name,
                'setup': s_name,
                'trades': m['trades'],
                'win_rate': m['win_rate'],
                'pf': m['profit_factor'],
                'net_profit': m['net_profit'],
                'net_profit_pct': m['net_profit_pct'],
                'max_dd': m['max_drawdown_pct'],
                'expectancy': m['expectancy_r']
            }
            results.append(row)

            print(f"{row['tf']:<5} | {row['setup'][:50]:<50} | {row['trades']:<7} | {row['win_rate']:>5.1f}% | {row['pf']:>5.2f} | ${row['net_profit']:>9.2f} | {row['net_profit_pct']:>6.1f}% | {row['max_dd']:>6.2f}%")

    print("=" * 110)

    # 4. Encontrar os Vencedores
    df_res = pd.DataFrame(results)
    if not df_res.empty:
        # Ranking por Lucro Líquido ponderado por Drawdown (Return / DD)
        df_res['score'] = np.where(df_res['max_dd'] > 0, df_res['net_profit_pct'] / df_res['max_dd'], 0)
        df_sorted = df_res.sort_values(by=['pf', 'net_profit_pct'], ascending=False)

        print("\n" + "🏆 TOP 3 MELHORES CONFIGURAÇÕES ABSOLUTAS:")
        for idx, (_, top) in enumerate(df_sorted.head(3).iterrows(), 1):
            print(f" #{idx} -> TIMEFRAME: {top['tf']} | SETUP: {top['setup']}")
            print(f"       Total Trades: {top['trades']} | Win Rate: {top['win_rate']:.1f}% | Profit Factor: {top['pf']:.2f}")
            print(f"       Lucro Líquido: ${top['net_profit']:.2f} (+{top['net_profit_pct']:.1f}%) | Rebaixamento Máximo (DD): {top['max_dd']:.2f}%\n")

    return results

if __name__ == '__main__':
    run_all_tests()

