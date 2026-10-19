import os
import pandas as pd
import numpy as np

def run_backtest():
    csv_path = 'Robos mt5/XAUUSD-STDc_M15_202403120415_202610022345.csv'
    df = pd.read_csv(csv_path, sep='\t')
    
    # Calculate indicators
    df['close'] = df['<CLOSE>']
    df['open'] = df['<OPEN>']
    df['high'] = df['<HIGH>']
    df['low'] = df['<LOW>']
    df['spread'] = df['<SPREAD>'] * 0.01 # convert to dollars
    
    df['ema50'] = df['close'].ewm(span=50, adjust=False).mean()
    df['ema200'] = df['close'].ewm(span=200, adjust=False).mean()
    
    prev_close = df['close'].shift(1)
    tr = pd.concat([
        df['high'] - df['low'],
        (df['high'] - prev_close).abs(),
        (df['low'] - prev_close).abs()
    ], axis=1).max(axis=1)
    df['atr14'] = tr.rolling(14).mean()
    
    # -------------------------------------------------------------
    # SIMULATION: V40 - TREND PYRAMIDING (ESCALONAMENTO DECRESCENTE)
    # -------------------------------------------------------------
    initial_balance = 1000.0
    balance_v40 = initial_balance
    equity_v40 = [initial_balance]
    trades_v40 = []
    
    active_cycle = None # dict with cycle info
    
    # Start after warm up
    start_bar = 205
    n_bars = len(df)
    
    base_lot = 0.06
    lot2 = 0.04
    lot3 = 0.02
    pyramid_step = 6.00 # $6.00 = 600 points
    trail_drop_pct = 0.15 # 15% drop from max profit
    min_profit_to_trail = 20.0 # $20.00
    
    for i in range(start_bar, n_bars):
        row = df.iloc[i]
        curr_open = row['open']
        curr_high = row['high']
        curr_low = row['low']
        curr_close = row['close']
        curr_spread = row['spread']
        atr = row['atr14'] if not np.isnan(row['atr14']) else 6.0
        
        # 1. Check active cycle management
        if active_cycle is not None:
            direction = active_cycle['direction'] # 1 for Buy, -1 for Sell
            orders = active_cycle['orders']
            
            # Check Stop Loss on existing orders
            sl_hit = False
            for ord_info in orders:
                sl = ord_info['sl']
                if direction == 1 and curr_low <= sl:
                    sl_hit = True
                    break
                elif direction == -1 and curr_high >= sl:
                    sl_hit = True
                    break
            
            if sl_hit:
                # Close all orders at SL
                cycle_pnl = 0.0
                for ord_info in orders:
                    exit_price = ord_info['sl']
                    if direction == 1:
                        pnl = (exit_price - ord_info['entry_price'] - curr_spread) * ord_info['lot'] * 100.0
                    else:
                        pnl = (ord_info['entry_price'] - exit_price - curr_spread) * ord_info['lot'] * 100.0
                    cycle_pnl += pnl
                
                balance_v40 += cycle_pnl
                trades_v40.append({
                    'type': 'BUY' if direction == 1 else 'SELL',
                    'orders_count': len(orders),
                    'pnl': cycle_pnl,
                    'reason': 'SL_HIT',
                    'balance': balance_v40
                })
                active_cycle = None
                equity_v40.append(balance_v40)
                continue
            
            # Calculate current floating profit at bar high/low/close
            # Check if new pyramid orders should be added
            highest_advance = 0.0
            if direction == 1:
                highest_advance = curr_high - active_cycle['entry_ref']
            else:
                highest_advance = active_cycle['entry_ref'] - curr_low
            
            # Check Level 2 addition
            if len(orders) == 1 and highest_advance >= pyramid_step:
                # Move Order 1 SL to Breakeven (+ spread)
                orders[0]['sl'] = orders[0]['entry_price'] + (0.18 if direction == 1 else -0.18)
                # Add Order 2
                entry_2 = active_cycle['entry_ref'] + (pyramid_step if direction == 1 else -pyramid_step)
                orders.append({
                    'lot': lot2,
                    'entry_price': entry_2,
                    'sl': orders[0]['sl']
                })
            
            # Check Level 3 addition
            elif len(orders) == 2 and highest_advance >= (2 * pyramid_step):
                # Lock profit: move SLs of Order 1 & 2 to Entry of Order 2
                entry_2 = orders[1]['entry_price']
                orders[0]['sl'] = entry_2
                orders[1]['sl'] = entry_2
                # Add Order 3
                entry_3 = active_cycle['entry_ref'] + (2 * pyramid_step if direction == 1 else -2 * pyramid_step)
                orders.append({
                    'lot': lot3,
                    'entry_price': entry_3,
                    'sl': entry_2
                })
            
            # Calculate floating profit at high and at close
            # Floating at Close
            float_close = 0.0
            for ord_info in orders:
                if direction == 1:
                    pnl = (curr_close - ord_info['entry_price'] - curr_spread) * ord_info['lot'] * 100.0
                else:
                    pnl = (ord_info['entry_price'] - curr_close - curr_spread) * ord_info['lot'] * 100.0
                float_close += pnl
            
            # Track max profit
            if float_close > active_cycle['max_profit']:
                active_cycle['max_profit'] = float_close
            
            # Check Trailing Drop Exit
            max_p = active_cycle['max_profit']
            if max_p >= min_profit_to_trail:
                drop_threshold = max_p * (1.0 - trail_drop_pct)
                if float_close <= drop_threshold:
                    # Trailing trigger! Close all orders
                    balance_v40 += float_close
                    trades_v40.append({
                        'type': 'BUY' if direction == 1 else 'SELL',
                        'orders_count': len(orders),
                        'pnl': float_close,
                        'reason': 'TRAILING_DROP_EXIT',
                        'balance': balance_v40
                    })
                    active_cycle = None
                    equity_v40.append(balance_v40)
                    continue
            
            # Check Trend Inversion Exit (Price cross EMA 50 opposite)
            if (direction == 1 and curr_close < row['ema50']) or (direction == -1 and curr_close > row['ema50']):
                balance_v40 += float_close
                trades_v40.append({
                    'type': 'BUY' if direction == 1 else 'SELL',
                    'orders_count': len(orders),
                    'pnl': float_close,
                    'reason': 'TREND_INVERSION_EXIT',
                    'balance': balance_v40
                })
                active_cycle = None
                equity_v40.append(balance_v40)
                continue
            
            equity_v40.append(balance_v40 + float_close)
        
        else:
            # Look for new trend entry signal
            # Buy signal: Close > EMA50 > EMA200 and Green candle
            # Sell signal: Close < EMA50 < EMA200 and Red candle
            ema50 = row['ema50']
            ema200 = row['ema200']
            
            if curr_close > ema50 and ema50 > ema200 and curr_close > curr_open:
                initial_sl = curr_close - (1.5 * atr)
                active_cycle = {
                    'direction': 1,
                    'entry_ref': curr_close,
                    'max_profit': 0.0,
                    'orders': [{
                        'lot': base_lot,
                        'entry_price': curr_close,
                        'sl': initial_sl
                    }]
                }
            elif curr_close < ema50 and ema50 < ema200 and curr_close < curr_open:
                initial_sl = curr_close + (1.5 * atr)
                active_cycle = {
                    'direction': -1,
                    'entry_ref': curr_close,
                    'max_profit': 0.0,
                    'orders': [{
                        'lot': base_lot,
                        'entry_price': curr_close,
                        'sl': initial_sl
                    }]
                }
            
            equity_v40.append(balance_v40)
            
    # Calculate statistics
    trades_df = pd.DataFrame(trades_v40)
    print('====================================================================')
    print('RESULTADO QUANTITATIVO - BURGO SCALPE PRO V40 (PIRAMIDAÇÃO A FAVOR)')
    print('====================================================================')
    print(f'Saldo Inicial: ${initial_balance:.2f}')
    print(f'Saldo Final:   ${balance_v40:.2f}')
    net_profit = balance_v40 - initial_balance
    print(f'Lucro Liquido: ${net_profit:.2f} ({net_profit/initial_balance*100:.2f}%)')
    
    if len(trades_df) > 0:
        wins = trades_df[trades_df['pnl'] > 0]
        losses = trades_df[trades_df['pnl'] < 0]
        total_trades = len(trades_df)
        win_rate = (len(wins) / total_trades) * 100.0
        
        gross_profit = wins['pnl'].sum()
        gross_loss = abs(losses['pnl'].sum())
        profit_factor = (gross_profit / gross_loss) if gross_loss > 0 else 999.0
        
        avg_win = wins['pnl'].mean() if len(wins) > 0 else 0.0
        avg_loss = abs(losses['pnl'].mean()) if len(losses) > 0 else 0.0
        payoff = (avg_win / avg_loss) if avg_loss > 0 else 0.0
        
        # Max drawdown
        eq_series = pd.Series(equity_v40)
        peak = eq_series.cummax()
        dd = (peak - eq_series) / peak * 100.0
        max_dd = dd.max()
        
        print(f'Total de Ciclos Operados: {total_trades}')
        print(f'Taxa de Acerto (Win Rate): {win_rate:.2f}% ({len(wins)} V / {len(losses)} D)')
        print(f'Lucro Bruto:   ${gross_profit:.2f}')
        print(f'Prejuizo Bruto: ${gross_loss:.2f}')
        print(f'Fator de Lucro (Profit Factor): {profit_factor:.2f}')
        print(f'Ganho Medio (Win):   ${avg_win:.2f}')
        print(f'Perda Media (Loss):  ${avg_loss:.2f}')
        print(f'Relacao Payoff (Ganho/Perda): {payoff:.2f}:1')
        print(f'Drawdown Maximo da Curva: {max_dd:.2f}%')
        print('\nDistribuicao de Saidas por Motivo:')
        print(trades_df['reason'].value_counts())
        print('\nDistribuicao de Quantidade de Ordens por Ciclo:')
        print(trades_df['orders_count'].value_counts())

if __name__ == '__main__':
    run_backtest()
