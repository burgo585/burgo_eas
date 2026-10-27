import sys
import os
import pandas as pd
import numpy as np

# Re-executar com InpMaxSpreadPts = 70.0 no M5 e M15
with open(r'C:\Users\Vini_Burgo\OneDrive\Documents\Robo\Marcus\GOLD_202312201206_202610260330ticksXM.csv', 'rb') as f:
    file_size = os.path.getsize(r'C:\Users\Vini_Burgo\OneDrive\Documents\Robo\Marcus\GOLD_202312201206_202610260330ticksXM.csv')
    offset = max(0, file_size - 150 * 1024 * 1024)
    f.seek(offset)
    f.readline()
    df_raw = pd.read_csv(f, sep='\t', names=['DATE', 'TIME', 'BID', 'ASK', 'LAST', 'VOLUME', 'FLAGS'])

df_raw['DATETIME'] = pd.to_datetime(df_raw['DATE'] + ' ' + df_raw['TIME'])
df_oct = df_raw[(df_raw['DATETIME'] >= '2026-10-01') & (df_raw['DATETIME'] <= '2026-10-26 23:59:59')].copy()
df_oct.set_index('DATETIME', inplace=True)

def sim_oct(tf='5min', name='M5', max_spread=70.0, rr=2.0):
    bars_bid = df_oct['BID'].resample(tf).ohlc().dropna()
    bars_ask = df_oct['ASK'].resample(tf).ohlc().dropna()
    bars = bars_bid.copy()
    bars['spread'] = (bars_ask['close'] - bars_bid['close']).round(2)
    
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
    
    balance = 5000.0
    initial_balance = 5000.0
    max_equity = initial_balance
    max_dd = 0.0
    
    point = 0.01
    tick_val = 1.0
    comm = 6.0
    slip = 0.10
    trades = []
    in_pos = False
    pos_type = None
    entry_p = 0.0
    sl_p = 0.0
    tp_p = 0.0
    lot = 0.0
    
    for i in range(1, len(bars)):
        row = bars.iloc[i]
        prev = bars.iloc[i-1]
        
        if in_pos:
            if pos_type == 'BUY':
                hit_sl = (row['low'] <= sl_p)
                hit_tp = (row['high'] >= tp_p)
                if hit_sl and hit_tp: hit_tp = False
                if hit_sl:
                    exit_p = sl_p - slip
                    pnl = ((exit_p - entry_p)/point) * lot * tick_val - (lot * comm)
                    balance += pnl
                    trades.append({'res': 'SL', 'pnl': pnl})
                    in_pos = False
                elif hit_tp:
                    exit_p = tp_p - slip
                    pnl = ((exit_p - entry_p)/point) * lot * tick_val - (lot * comm)
                    balance += pnl
                    trades.append({'res': 'TP', 'pnl': pnl})
                    in_pos = False
            elif pos_type == 'SELL':
                hit_sl = (row['high'] >= sl_p)
                hit_tp = (row['low'] <= tp_p)
                if hit_sl and hit_tp: hit_tp = False
                if hit_sl:
                    exit_p = sl_p + slip
                    pnl = ((entry_p - exit_p)/point) * lot * tick_val - (lot * comm)
                    balance += pnl
                    trades.append({'res': 'SL', 'pnl': pnl})
                    in_pos = False
                elif hit_tp:
                    exit_p = tp_p + slip
                    pnl = ((entry_p - exit_p)/point) * lot * tick_val - (lot * comm)
                    balance += pnl
                    trades.append({'res': 'TP', 'pnl': pnl})
                    in_pos = False
                    
            if balance > max_equity: max_equity = balance
            dd = max_equity - balance
            if dd > max_dd: max_dd = dd
            
        if not in_pos:
            cur_spread = row['spread'] / point
            if cur_spread <= max_spread:
                atr_pts = row['atr'] / point
                sl_pts = max(30.0, atr_pts * 1.5)
                tp_pts = sl_pts * rr
                risk_usd = balance * 0.01
                lot = max(0.01, round(risk_usd / (sl_pts * tick_val), 2))
                
                if prev['ema9'] > prev['ema21'] and prev['close'] > prev['ema9'] and prev['low'] <= prev['ema9']:
                    pos_type = 'BUY'
                    entry_p = row['open'] + row['spread']
                    sl_p = entry_p - (sl_pts * point)
                    tp_p = entry_p + (tp_pts * point)
                    in_pos = True
                elif prev['ema9'] < prev['ema21'] and prev['close'] < prev['ema9'] and prev['high'] >= prev['ema9']:
                    pos_type = 'SELL'
                    entry_p = row['open']
                    sl_p = entry_p + (sl_pts * point) + row['spread']
                    tp_p = entry_p - (tp_pts * point)
                    in_pos = True
                    
    df_t = pd.DataFrame(trades)
    if len(df_t) == 0:
        print(f"[{name}] Sem trades.")
        return
    wins = len(df_t[df_t['res'] == 'TP'])
    wr = (wins / len(df_t)) * 100
    pnl = balance - initial_balance
    gp = df_t[df_t['pnl'] > 0]['pnl'].sum()
    gl = abs(df_t[df_t['pnl'] < 0]['pnl'].sum())
    pf = (gp / gl) if gl > 0 else 999.0
    print(f"[{name} - SpreadMax {max_spread} pts - RR {rr}] Trades: {len(df_t)} | WinRate: {wr:.1f}% | PnL: ${pnl:+.2f} | PF: {pf:.2f} | MaxDD: ${max_dd:.2f} ({(max_dd/initial_balance)*100:.1f}%)")

print("--- COMPARAÇÃO EM OUTUBRO/2026 (XM TICKS REAIS) ---")
sim_oct('5min', 'M5', max_spread=70.0, rr=2.0)
sim_oct('15min', 'M15', max_spread=70.0, rr=2.0)
sim_oct('15min', 'M15', max_spread=70.0, rr=1.5)
