# -*- coding: utf-8 -*-
"""
Simulador Causal das Regras de Gestão e Proteção da Boleta Scalping (XAUUSD)
"""
import sys
import os
import pandas as pd
import numpy as np

sys.path.append(r'C:\Users\Vini_Burgo\.gemini\config\skills\quant-forensic-auditor\scripts')
from xm_ticks_reader import load_xm_ticks

def simulate_boleta_rules(tf_str='15min', tf_name='M15', rr_ratio=2.0, risk_usd=10.0):
    df_ticks = load_xm_ticks(symbol="GOLD", max_ticks=350000)
    df_ticks.columns = [c.strip().replace('<', '').replace('>', '') for c in df_ticks.columns]
    df_ticks['DATETIME'] = pd.to_datetime(df_ticks['DATE'] + ' ' + df_ticks['TIME'])
    df_ticks.set_index('DATETIME', inplace=True)
    
    bars = df_ticks['BID'].resample(tf_str).ohlc().dropna()
    bars_ask = df_ticks['ASK'].resample(tf_str).ohlc().dropna()
    bars['ask_close'] = bars_ask['close']
    bars['spread'] = (bars_ask['close'] - bars['close']).round(2)
    
    tr = np.maximum(
        bars['high'] - bars['low'],
        np.maximum(
            (bars['high'] - bars['close'].shift(1)).abs(),
            (bars['low'] - bars['close'].shift(1)).abs()
        )
    )
    bars['atr'] = tr.rolling(14).mean().shift(1)
    bars['ema9'] = bars['close'].ewm(span=9, adjust=False).mean().shift(1)
    bars['ema21'] = bars['close'].ewm(span=21, adjust=False).mean().shift(1)
    
    bars = bars.dropna().copy()
    
    initial_balance = 1000.0
    balance = initial_balance
    max_equity = initial_balance
    max_dd_usd = 0.0
    
    trades = []
    in_pos = False
    pos_type = None
    entry_price = 0.0
    sl_price = 0.0
    tp_price = 0.0
    lot = 0.0
    
    point = 0.01
    tick_val = 1.0 # $1.00 por ponto no XAUUSD para 1.0 lote padrão
    commission_per_lot = 6.0
    slippage_usd = 0.10
    
    for i in range(1, len(bars)):
        row = bars.iloc[i]
        prev = bars.iloc[i-1]
        
        if in_pos:
            if pos_type == 'BUY':
                hit_sl = (row['low'] <= sl_price)
                hit_tp = (row['high'] >= tp_price)
                if hit_sl and hit_tp:
                    hit_tp = False
                    
                if hit_sl:
                    exit_price = sl_price - slippage_usd
                    pts_diff = (exit_price - entry_price) / point
                    pnl_raw = pts_diff * (lot * tick_val)
                    comm = lot * commission_per_lot
                    pnl_net = pnl_raw - comm
                    balance += pnl_net
                    trades.append({'type': 'BUY', 'res': 'SL', 'pnl': pnl_net})
                    in_pos = False
                elif hit_tp:
                    exit_price = tp_price - slippage_usd
                    pts_diff = (exit_price - entry_price) / point
                    pnl_raw = pts_diff * (lot * tick_val)
                    comm = lot * commission_per_lot
                    pnl_net = pnl_raw - comm
                    balance += pnl_net
                    trades.append({'type': 'BUY', 'res': 'TP', 'pnl': pnl_net})
                    in_pos = False
                    
            elif pos_type == 'SELL':
                hit_sl = (row['high'] >= sl_price)
                hit_tp = (row['low'] <= tp_price)
                if hit_sl and hit_tp:
                    hit_tp = False
                    
                if hit_sl:
                    exit_price = sl_price + slippage_usd
                    pts_diff = (entry_price - exit_price) / point
                    pnl_raw = pts_diff * (lot * tick_val)
                    comm = lot * commission_per_lot
                    pnl_net = pnl_raw - comm
                    balance += pnl_net
                    trades.append({'type': 'SELL', 'res': 'SL', 'pnl': pnl_net})
                    in_pos = False
                elif hit_tp:
                    exit_price = tp_price + slippage_usd
                    pts_diff = (entry_price - exit_price) / point
                    pnl_raw = pts_diff * (lot * tick_val)
                    comm = lot * commission_per_lot
                    pnl_net = pnl_raw - comm
                    balance += pnl_net
                    trades.append({'type': 'SELL', 'res': 'TP', 'pnl': pnl_net})
                    in_pos = False
                    
            if balance > max_equity:
                max_equity = balance
            dd = max_equity - balance
            if dd > max_dd_usd:
                max_dd_usd = dd
                
        if not in_pos:
            if prev['ema9'] > prev['ema21'] and prev['close'] > prev['ema9'] and prev['low'] <= prev['ema9']:
                pos_type = 'BUY'
                entry_price = row['open'] + row['spread']
                atr_pts = (row['atr'] / point)
                sl_pts = max(30.0, atr_pts * 1.5)
                tp_pts = sl_pts * rr_ratio
                lot_calc = risk_usd / (sl_pts * tick_val)
                lot = max(0.01, round(lot_calc, 2))
                sl_price = entry_price - (sl_pts * point)
                tp_price = entry_price + (tp_pts * point)
                in_pos = True
                
            elif prev['ema9'] < prev['ema21'] and prev['close'] < prev['ema9'] and prev['high'] >= prev['ema9']:
                pos_type = 'SELL'
                entry_price = row['open']
                atr_pts = (row['atr'] / point)
                sl_pts = max(30.0, atr_pts * 1.5)
                tp_pts = sl_pts * rr_ratio
                lot_calc = risk_usd / (sl_pts * tick_val)
                lot = max(0.01, round(lot_calc, 2))
                sl_price = entry_price + (sl_pts * point) + row['spread']
                tp_price = entry_price - (tp_pts * point)
                in_pos = True

    df_t = pd.DataFrame(trades)
    total_trades = len(df_t)
    if total_trades == 0:
        return {'tf': tf_name, 'rr': rr_ratio, 'trades': 0, 'win_rate': 0, 'net_pnl': 0, 'pf': 0, 'max_dd': 0}
        
    wins = len(df_t[df_t['res'] == 'TP'])
    losses = len(df_t[df_t['res'] == 'SL'])
    win_rate = (wins / total_trades) * 100.0
    net_pnl = balance - initial_balance
    pf = (df_t[df_t['pnl'] > 0]['pnl'].sum() / abs(df_t[df_t['pnl'] < 0]['pnl'].sum())) if losses > 0 else 999.0
    
    return {
        'tf': tf_name,
        'rr': rr_ratio,
        'trades': total_trades,
        'win_rate': round(win_rate, 1),
        'net_pnl': round(net_pnl, 2),
        'pf': round(pf, 2),
        'max_dd_usd': round(max_dd_usd, 2),
        'max_dd_pct': round((max_dd_usd / initial_balance) * 100.0, 1)
    }

if __name__ == '__main__':
    for tf, name in [('1min', 'M1'), ('5min', 'M5'), ('15min', 'M15'), ('30min', 'M30')]:
        r = simulate_boleta_rules(tf_str=tf, tf_name=name, rr_ratio=2.0)
        print(f"[{name} - R:R 1:2] Trades: {r['trades']} | WinRate: {r['win_rate']}% | PnL: ${r['net_pnl']:+} | PF: {r['pf']} | MaxDD: ${r['max_dd_usd']} ({r['max_dd_pct']}%)")
