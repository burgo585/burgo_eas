import sys
sys.stdout.reconfigure(encoding='utf-8')
import MetaTrader5 as mt5
import pandas as pd
import numpy as np

# 1. Connect to MT5 and fetch EURUSD H4 bars
if not mt5.initialize():
    print("Failed to initialize MT5")
    sys.exit(1)

symbol = "EURUSD"
timeframe = mt5.TIMEFRAME_H4
bars_count = 5000

rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, bars_count)
sym_info = mt5.symbol_info(symbol)
account_info = mt5.account_info()
mt5.shutdown()

if rates is None or len(rates) == 0:
    print("No rates returned")
    sys.exit(1)

df = pd.DataFrame(rates)
df['time'] = pd.to_datetime(df['time'], unit='s')
df.sort_values('time', inplace=True)
df.reset_index(drop=True, inplace=True)

# 2. Broker Specifications
point = sym_info.point
digits = sym_info.digits
spread_points = sym_info.spread
spread_val = spread_points * point
swap_long = sym_info.swap_long
swap_short = sym_info.swap_short
contract_size = sym_info.trade_contract_size
commission_per_lot = 6.0  # US$ 6.00 round turn ECN
slippage_points = 2
slippage_val = slippage_points * point

print(f"Loaded {len(df)} bars of {symbol} H4 from {df['time'].iloc[0]} to {df['time'].iloc[-1]}")
print(f"Broker Specs: spread={spread_points} pts, point={point}, swap_long={swap_long}, swap_short={swap_short}, contract_size={contract_size}")

# 3. Calculate Indicators with STRICT .shift(1) (closed bars only)
# EMA 70
df['ema70'] = df['close'].ewm(span=70, adjust=False).mean().shift(1)
df['ema70_prev'] = df['ema70'].shift(1)

# Slow Stochastic (8, 3, 3)
low8 = df['low'].rolling(8).min()
high8 = df['high'].rolling(8).max()
fast_k = 100.0 * (df['close'] - low8) / (high8 - low8 + 1e-10)
# Slow %K is SMA 3 of fast %K
df['stoch_k'] = fast_k.rolling(3).mean().shift(1)
df['stoch_d'] = df['stoch_k'].rolling(3).mean().shift(1)

# Shifted OHLC for closed bars
# bar 1 (shift 1) = Candle 3 of pattern
# bar 2 (shift 2) = Candle 2 of pattern (Fundo)
# bar 3 (shift 3) = Candle 1 of pattern
df['high_1'] = df['high'].shift(1)
df['low_1'] = df['low'].shift(1)
df['close_1'] = df['close'].shift(1)
df['time_1'] = df['time'].shift(1)

df['high_2'] = df['high'].shift(2)
df['low_2'] = df['low'].shift(2)

df['high_3'] = df['high'].shift(3)
df['low_3'] = df['low'].shift(3)

# Swing Lookback for Target (High of preceding 20 bars)
df['swing_high_target'] = df['high'].shift(3).rolling(20).max()
df['swing_low_target'] = df['low'].shift(3).rolling(20).min()

# Setup 1-2-3 Buy Signals
cond_ema_buy = (df['ema70'] > df['ema70_prev']) & (df['close_1'] >= df['ema70'])
# Stoch was oversold (< 20) in the last 6 bars
df['stoch_oversold'] = (df['stoch_k'] < 20.0).rolling(6).max() == 1.0

cond_123_buy = (df['low_2'] < df['low_3']) & (df['low_1'] > df['low_2'])

df['buy_signal'] = cond_ema_buy & df['stoch_oversold'] & cond_123_buy

# Setup 1-2-3 Sell Signals (Symmetric)
cond_ema_sell = (df['ema70'] < df['ema70_prev']) & (df['close_1'] <= df['ema70'])
df['stoch_overbought'] = (df['stoch_k'] > 80.0).rolling(6).max() == 1.0
cond_123_sell = (df['high_2'] > df['high_3']) & (df['high_1'] < df['high_2'])

df['sell_signal'] = cond_ema_sell & df['stoch_overbought'] & cond_123_sell

# 4. Strictly Causal Backtest Function
def run_simulation(start_idx=0, initial_balance=1000.0, risk_pct=1.0, allow_sell=True):
    balance = initial_balance
    equity = initial_balance
    peak_equity = initial_balance
    max_dd_usd = 0.0
    max_dd_pct = 0.0
    
    total_trades = 0
    wins = 0
    losses = 0
    total_commission = 0.0
    total_swap = 0.0
    total_gross_profit = 0.0
    total_gross_loss = 0.0
    
    position = None # {type, entry_price, sl, tp, lot, entry_time, risk_dist}
    stop_out = False
    
    for i in range(start_idx, len(df)):
        row = df.iloc[i]
        
        # Check current open position against current bar's OHLC
        if position is not None:
            # Swap daily / 4-hour accrual
            # 1 day = 6 bars H4. For simplicity: swap per bar = swap / 6
            # In EURUSD: 1 lot swap in USD = swap_pts * point * contract_size
            bar_swap = (swap_long if position['type'] == 'BUY' else swap_short) * point * contract_size * position['lot'] / 6.0
            total_swap += bar_swap
            balance += bar_swap # swap added/deducted
            
            p_type = position['type']
            lot = position['lot']
            sl = position['sl']
            tp = position['tp']
            entry = position['entry_price']
            
            # Causal intrabar resolution:
            # For BUY:
            # Worst case / conservative check: Did it hit SL first?
            # In candle i: Low is checked for SL; High is checked for TP.
            hit_sl = False
            hit_tp = False
            
            if p_type == 'BUY':
                if row['low'] <= sl:
                    hit_sl = True
                elif row['high'] >= tp:
                    hit_tp = True
                    
                # Realize trade
                if hit_sl:
                    # Executed at SL - slippage
                    exit_price = sl - slippage_val
                    pnl = (exit_price - entry) * contract_size * lot
                    balance += pnl
                    total_gross_loss += abs(pnl)
                    losses += 1
                    total_trades += 1
                    position = None
                elif hit_tp:
                    # Executed strictly at TP (NO teleportation to High!)
                    exit_price = tp
                    pnl = (exit_price - entry) * contract_size * lot
                    balance += pnl
                    total_gross_profit += pnl
                    wins += 1
                    total_trades += 1
                    position = None
                else:
                    # Floating equity calculation
                    curr_price = row['close']
                    floating_pnl = (curr_price - entry) * contract_size * lot
                    curr_equity = balance + floating_pnl
                    if curr_equity > peak_equity:
                        peak_equity = curr_equity
                    dd_usd = peak_equity - curr_equity
                    if dd_usd > max_dd_usd:
                        max_dd_usd = dd_usd
                        max_dd_pct = (max_dd_usd / peak_equity) * 100.0
                    if curr_equity <= 0 or balance <= 0:
                        stop_out = True
                        break
                        
            elif p_type == 'SELL':
                if row['high'] >= sl:
                    hit_sl = True
                elif row['low'] <= tp:
                    hit_tp = True
                    
                if hit_sl:
                    exit_price = sl + slippage_val
                    pnl = (entry - exit_price) * contract_size * lot
                    balance += pnl
                    total_gross_loss += abs(pnl)
                    losses += 1
                    total_trades += 1
                    position = None
                elif hit_tp:
                    exit_price = tp
                    pnl = (entry - exit_price) * contract_size * lot
                    balance += pnl
                    total_gross_profit += pnl
                    wins += 1
                    total_trades += 1
                    position = None
                else:
                    curr_price = row['close']
                    floating_pnl = (entry - curr_price) * contract_size * lot
                    curr_equity = balance + floating_pnl
                    if curr_equity > peak_equity:
                        peak_equity = curr_equity
                    dd_usd = peak_equity - curr_equity
                    if dd_usd > max_dd_usd:
                        max_dd_usd = dd_usd
                        max_dd_pct = (max_dd_usd / peak_equity) * 100.0
                    if curr_equity <= 0 or balance <= 0:
                        stop_out = True
                        break

        # Check for new entry if no position is open
        if position is None and not stop_out:
            if row['buy_signal']:
                trigger_price = row['high_1']
                sl_price = row['low_2'] - (50 * point)
                tp_price = row['swing_high_target']
                
                risk_dist = trigger_price - sl_price
                reward_dist = tp_price - trigger_price
                
                # Check R:R >= 1.0 and valid geometry
                if risk_dist > 0 and reward_dist / risk_dist >= 1.0:
                    # In candle i, does price break above trigger_price?
                    if row['high'] >= trigger_price:
                        # Entry occurs at trigger_price + spread + slippage
                        entry_price = trigger_price + spread_val + slippage_val
                        # Lot size calculation based on risk %
                        risk_usd = balance * (risk_pct / 100.0)
                        lot = risk_usd / (risk_dist * contract_size)
                        lot = max(0.01, min(10.0, round(lot, 2)))
                        comm = lot * commission_per_lot
                        total_commission += comm
                        balance -= comm
                        
                        position = {
                            'type': 'BUY',
                            'entry_price': entry_price,
                            'sl': sl_price,
                            'tp': tp_price,
                            'lot': lot,
                            'entry_time': row['time'],
                            'risk_dist': risk_dist
                        }
                        
            elif allow_sell and row['sell_signal']:
                trigger_price = row['low_1']
                sl_price = row['high_2'] + (50 * point)
                tp_price = row['swing_low_target']
                
                risk_dist = sl_price - trigger_price
                reward_dist = trigger_price - tp_price
                
                if risk_dist > 0 and reward_dist / risk_dist >= 1.0:
                    if row['low'] <= trigger_price:
                        entry_price = trigger_price - slippage_val
                        risk_usd = balance * (risk_pct / 100.0)
                        lot = risk_usd / (risk_dist * contract_size)
                        lot = max(0.01, min(10.0, round(lot, 2)))
                        comm = lot * commission_per_lot
                        total_commission += comm
                        balance -= comm
                        
                        position = {
                            'type': 'SELL',
                            'entry_price': entry_price,
                            'sl': sl_price,
                            'tp': tp_price,
                            'lot': lot,
                            'entry_time': row['time'],
                            'risk_dist': risk_dist
                        }
                        
    # End of run metrics
    win_rate = (wins / total_trades * 100.0) if total_trades > 0 else 0.0
    profit_factor = (total_gross_profit / total_gross_loss) if total_gross_loss > 0 else 999.0
    net_profit = balance - initial_balance
    
    return {
        'initial_balance': initial_balance,
        'final_balance': balance,
        'net_profit': net_profit,
        'total_trades': total_trades,
        'wins': wins,
        'losses': losses,
        'win_rate': win_rate,
        'profit_factor': profit_factor,
        'max_dd_usd': max_dd_usd,
        'max_dd_pct': max_dd_pct,
        'total_commission': total_commission,
        'total_swap': total_swap,
        'stop_out': stop_out
    }

# 5. Full 3-Year Baseline Simulation (BUY ONLY vs BUY & SELL)
res_buy_only = run_simulation(start_idx=100, initial_balance=1000.0, risk_pct=1.0, allow_sell=False)
full_res = run_simulation(start_idx=100, initial_balance=1000.0, risk_pct=1.0, allow_sell=True)

print("\n=== COMPARATIVO: BUY ONLY (FIEL AO VÍDEO) vs COMPRA E VENDA ===")
print(f"Modo BUY ONLY (Original Stormer):")
print(f"  Lucro Líquido: ${res_buy_only['net_profit']:.2f} | Trades: {res_buy_only['total_trades']} | Win Rate: {res_buy_only['win_rate']:.1f}% ({res_buy_only['wins']}W/{res_buy_only['losses']}L)")
print(f"  Fator de Lucro (PF): {res_buy_only['profit_factor']:.2f} | Max DD: -${res_buy_only['max_dd_usd']:.2f} ({res_buy_only['max_dd_pct']:.2f}%)")
print(f"  Swap + Comissões: -${res_buy_only['total_commission'] - res_buy_only['total_swap']:.2f}")

print(f"\nModo BIDIRECIONAL (Compra e Venda):")
print(f"  Lucro Líquido: ${full_res['net_profit']:.2f} | Trades: {full_res['total_trades']} | Win Rate: {full_res['win_rate']:.1f}% ({full_res['wins']}W/{full_res['losses']}L)")
print(f"  Fator de Lucro (PF): {full_res['profit_factor']:.2f} | Max DD: -${full_res['max_dd_usd']:.2f} ({full_res['max_dd_pct']:.2f}%)")
print(f"  Swap + Comissões: -${full_res['total_commission'] - full_res['total_swap']:.2f}")


# 6. Rolling 30+ Monthly Start-Date Falsification Test (Risk of Ruin)
# Find the start of every month in the dataset
df['year_month'] = df['time'].dt.to_period('M')
unique_months = df['year_month'].unique()
print(f"\n=== ROLLING MONTHLY START-DATE FALSIFICATION ({len(unique_months)} MONTHS) ===")

bankruptcies = 0
tested_months = 0
worst_dd_across_all = 0.0
worst_dd_pct_across_all = 0.0

for ym in unique_months:
    # First index of month
    m_idx = df[df['year_month'] == ym].index[0]
    if m_idx < 100 or m_idx >= len(df) - 100:
        continue
    m_res = run_simulation(start_idx=m_idx, initial_balance=500.0, risk_pct=1.0)
    tested_months += 1
    if m_res['stop_out']:
        bankruptcies += 1
    if m_res['max_dd_usd'] > worst_dd_across_all:
        worst_dd_across_all = m_res['max_dd_usd']
        worst_dd_pct_across_all = m_res['max_dd_pct']

risk_of_ruin = (bankruptcies / tested_months * 100.0) if tested_months > 0 else 0.0
print(f"Tested Months: {tested_months}")
print(f"Bankruptcies: {bankruptcies} / {tested_months} ({risk_of_ruin:.1f}%)")
print(f"Worst Historical Floating Drawdown: -${worst_dd_across_all:.2f} ({worst_dd_pct_across_all:.2f}%)")
min_capital_recommended = worst_dd_across_all * 2.5 # Safety factor of 2.5x
print(f"Minimum Realistic Capital Recommended: ${min_capital_recommended:.2f}")
