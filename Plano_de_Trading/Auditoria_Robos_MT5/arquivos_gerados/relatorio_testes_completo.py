import pandas as pd
import numpy as np

# Load real M15 Gold data
df = pd.read_csv('Robos mt5/XAUUSD-STDc_M15_202403120415_202610022345.csv', sep='\t')
df['close'] = df['<CLOSE>']
df['open'] = df['<OPEN>']
df['high'] = df['<HIGH>']
df['low'] = df['<LOW>']
df['volume'] = df['<TICKVOL>']
df['spread'] = df['<SPREAD>'] * 0.01

df['ema50'] = df['close'].ewm(span=50, adjust=False).mean()
df['ema200'] = df['close'].ewm(span=200, adjust=False).mean()

# Volume filter (PVSRA-like)
df['avg_vol'] = df['volume'].rolling(10).mean()
df['has_vol'] = df['volume'] >= 1.2 * df['avg_vol']

prev_close = df['close'].shift(1)
tr = pd.concat([
    df['high'] - df['low'],
    (df['high'] - prev_close).abs(),
    (df['low'] - prev_close).abs()
], axis=1).max(axis=1)
df['atr14'] = tr.rolling(14).mean()

# -------------------------------------------------------------
# Backtest V40
# -------------------------------------------------------------
initial_balance = 1000.0
balance = initial_balance
trades = []
active_cycle = None

base_lot = 0.04
lot2 = 0.02
lot3 = 0.01
pyramid_step = 8.00 # $8.00 = 800 pts
trail_drop_pct = 0.15 # 15% drop from max profit
min_profit_to_trail = 25.0 # $25.00 min profit to activate trail

equity_curve = [initial_balance]

for i in range(205, len(df)):
    row = df.iloc[i]
    c_close = row['close']
    c_open = row['open']
    c_high = row['high']
    c_low = row['low']
    spread = row['spread']
    atr = row['atr14'] if not np.isnan(row['atr14']) else 6.0
    
    if active_cycle is not None:
        direction = active_cycle['direction']
        orders = active_cycle['orders']
        
        # Check Stop Loss
        sl_hit = False
        for o in orders:
            if direction == 1 and c_low <= o['sl']:
                sl_hit = True; break
            elif direction == -1 and c_high >= o['sl']:
                sl_hit = True; break
        
        if sl_hit:
            cycle_pnl = sum((o['sl'] - o['entry_price'] - spread if direction==1 else o['entry_price'] - o['sl'] - spread) * o['lot'] * 100.0 for o in orders)
            balance += cycle_pnl
            trades.append({
                'direction': 'BUY' if direction==1 else 'SELL',
                'pnl': cycle_pnl,
                'orders': len(orders),
                'reason': 'STOP_LOSS'
            })
            active_cycle = None
            equity_curve.append(balance)
            continue
            
        adv = (c_high - active_cycle['entry_ref']) if direction == 1 else (active_cycle['entry_ref'] - c_low)
        
        # Level 2 entry + Breakeven on Order 1
        if len(orders) == 1 and adv >= pyramid_step:
            orders[0]['sl'] = orders[0]['entry_price'] + (0.20 if direction == 1 else -0.20)
            entry_2 = active_cycle['entry_ref'] + (pyramid_step if direction==1 else -pyramid_step)
            orders.append({'lot': lot2, 'entry_price': entry_2, 'sl': orders[0]['sl']})
            
        # Level 3 entry + Lock profit on Orders 1 & 2
        elif len(orders) == 2 and adv >= (2 * pyramid_step):
            entry_2 = orders[1]['entry_price']
            orders[0]['sl'] = entry_2
            orders[1]['sl'] = entry_2
            entry_3 = active_cycle['entry_ref'] + (2 * pyramid_step if direction==1 else -2 * pyramid_step)
            orders.append({'lot': lot3, 'entry_price': entry_3, 'sl': entry_2})
            
        float_p = sum((c_close - o['entry_price'] - spread if direction==1 else o['entry_price'] - c_close - spread) * o['lot'] * 100.0 for o in orders)
        if float_p > active_cycle['max_profit']:
            active_cycle['max_profit'] = float_p
            
        # Trailing Profit Drop exit
        if active_cycle['max_profit'] >= min_profit_to_trail:
            if float_p <= active_cycle['max_profit'] * (1.0 - trail_drop_pct):
                balance += float_p
                trades.append({
                    'direction': 'BUY' if direction==1 else 'SELL',
                    'pnl': float_p,
                    'orders': len(orders),
                    'reason': 'TRAILING_PROFIT_DROP'
                })
                active_cycle = None
                equity_curve.append(balance)
                continue
                
        # Trend Inversion exit
        if (direction == 1 and c_close < row['ema50']) or (direction == -1 and c_close > row['ema50']):
            balance += float_p
            trades.append({
                'direction': 'BUY' if direction==1 else 'SELL',
                'pnl': float_p,
                'orders': len(orders),
                'reason': 'TREND_INVERSION'
            })
            active_cycle = None
            equity_curve.append(balance)
            continue
            
        equity_curve.append(balance + float_p)
    else:
        ema50 = row['ema50']
        ema200 = row['ema200']
        has_vol = row['has_vol']
        if has_vol and c_close > ema50 and ema50 > ema200 and c_close > c_open:
            sl = c_close - (1.5 * atr)
            active_cycle = {'direction': 1, 'entry_ref': c_close, 'max_profit': 0.0, 'orders': [{'lot': base_lot, 'entry_price': c_close, 'sl': sl}]}
        elif has_vol and c_close < ema50 and ema50 < ema200 and c_close < c_open:
            sl = c_close + (1.5 * atr)
            active_cycle = {'direction': -1, 'entry_ref': c_close, 'max_profit': 0.0, 'orders': [{'lot': base_lot, 'entry_price': c_close, 'sl': sl}]}
        equity_curve.append(balance)

tdf = pd.DataFrame(trades)
wins = tdf[tdf['pnl'] > 0]
losses = tdf[tdf['pnl'] < 0]

eq_s = pd.Series(equity_curve)
peak = eq_s.cummax()
dd = (peak - eq_s) / peak * 100.0

print('RELATORIO_FINAL_START')
print(f'SALDO_INICIAL: {initial_balance:.2f}')
print(f'SALDO_FINAL: {balance:.2f}')
print(f'LUCRO_LIQUIDO: {balance - initial_balance:.2f}')
print(f'TOTAL_TRADES: {len(tdf)}')
print(f'WINS: {len(wins)}')
print(f'LOSSES: {len(losses)}')
print(f'WIN_RATE: {len(wins)/len(tdf)*100:.2f}')
print(f'PROFIT_FACTOR: {wins["pnl"].sum()/abs(losses["pnl"].sum()):.2f}')
print(f'GANHO_MEDIO: {wins["pnl"].mean():.2f}')
print(f'PERDA_MEDIA: {abs(losses["pnl"].mean()):.2f}')
print(f'PAYOFF: {wins["pnl"].mean()/abs(losses["pnl"].mean()):.2f}')
print(f'MAX_DRAWDOWN: {dd.max():.2f}')
print('MOTIVOS_SAIDA:')
print(tdf['reason'].value_counts().to_dict())
print('ORDENS_POR_CICLO:')
print(tdf['orders'].value_counts().to_dict())
print('RELATORIO_FINAL_END')
