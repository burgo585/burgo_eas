import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from datetime import datetime

def calculate_atr(df, period=14):
    high = df['high'].values
    low = df['low'].values
    close = df['close'].values
    n = len(df)
    tr = np.zeros(n)
    tr[0] = high[0] - low[0]
    for i in range(1, n):
        tr[i] = max(high[i] - low[i], abs(high[i] - close[i-1]), abs(low[i] - close[i-1]))
    atr = pd.Series(tr).rolling(window=period).mean().values
    return atr

class BurgoScalperSim:
    def __init__(self, df, timeframe_name, initial_lot=0.02, target_side=2.00, target_global=20.00,
                 base_dist_pts=600, lot_mult=1.5, max_martingale=8, max_orders=15,
                 use_atr=True, atr_mult=1.5, use_trailing=True, trailing_start=2.00, trailing_drop_pct=10.0,
                 mode="corrected"):
        self.df = df
        self.tf_name = timeframe_name
        self.initial_lot = initial_lot
        self.target_side = target_side
        self.target_global = target_global
        self.base_dist_pts = base_dist_pts
        self.lot_mult = lot_mult
        self.max_martingale = max_martingale
        self.max_orders = max_orders
        self.use_atr = use_atr
        self.atr_mult = atr_mult
        self.use_trailing = use_trailing
        self.trailing_start = trailing_start
        self.trailing_drop_pct = trailing_drop_pct
        self.mode = mode # 'corrected' vs 'original'
        
        # 1 lot on XAUUSD = 100 oz. 1 point = $0.01. So 1 lot per point = $1.00.
        # Profit ($) = (ClosePrice - OpenPrice) * Volume * 100
        self.contract_size = 100.0

    def run(self, initial_balance=10000.0):
        balance = initial_balance
        peak_balance = initial_balance
        equity = initial_balance
        peak_equity = initial_balance
        max_drawdown_usd = 0.0
        max_drawdown_pct = 0.0
        
        positions = [] # list of dicts: {'type': 'BUY'/'SELL', 'lot': float, 'price': float, 'ticket': int}
        ticket_seq = 1
        
        trades_history = []
        max_buy_profit = 0.0
        max_sell_profit = 0.0
        max_global_profit = 0.0
        max_active_orders = 0
        
        atr_values = calculate_atr(self.df, period=14)
        
        for idx in range(14, len(self.df)):
            row = self.df.iloc[idx]
            o = row['open']
            h = row['high']
            l = row['low']
            c = row['close']
            atr = atr_values[idx] if not np.isnan(atr_values[idx]) else 1.0
            
            # Dynamic distance
            if self.use_atr:
                dist = max(atr * self.atr_mult, (self.base_dist_pts / 2.0) * 0.01)
            else:
                dist = self.base_dist_pts * 0.01

            # Intra-bar simulation: simulate path open -> high/low -> close
            # To be realistic, if close > open, assume path: open -> low -> high -> close
            # If close < open, assume path: open -> high -> low -> close
            if c >= o:
                sub_ticks = [o, l, h, c]
            else:
                sub_ticks = [o, h, l, c]
                
            for cur_price in sub_ticks:
                spread = row['spread'] * 0.01
                ask = cur_price + spread / 2.0
                bid = cur_price - spread / 2.0
                
                # Calculate profits
                buy_positions = [p for p in positions if p['type'] == 'BUY']
                sell_positions = [p for p in positions if p['type'] == 'SELL']
                
                buy_profit = sum((bid - p['price']) * p['lot'] * self.contract_size for p in buy_positions)
                sell_profit = sum((p['price'] - ask) * p['lot'] * self.contract_size for p in sell_positions)
                total_floating = buy_profit + sell_profit
                
                equity = balance + total_floating
                if equity > peak_equity:
                    peak_equity = equity
                dd_usd = peak_equity - equity
                dd_pct = (dd_usd / peak_equity) * 100.0 if peak_equity > 0 else 0
                if dd_usd > max_drawdown_usd:
                    max_drawdown_usd = dd_usd
                if dd_pct > max_drawdown_pct:
                    max_drawdown_pct = dd_pct
                
                if len(positions) > max_active_orders:
                    max_active_orders = len(positions)
                    
                # 1. Global close
                if not self.use_trailing and total_floating >= self.target_global:
                    balance += total_floating
                    for p in positions:
                        trades_history.append({'pnl': (bid - p['price']) * p['lot'] * self.contract_size if p['type'] == 'BUY' else (p['price'] - ask) * p['lot'] * self.contract_size})
                    positions = []
                    max_buy_profit = 0
                    max_sell_profit = 0
                    max_global_profit = 0
                    continue
                    
                # 2. Recycling logic
                if buy_profit >= self.target_side and len(sell_positions) > 0:
                    if self.mode == "original":
                        # Original bug: breaks at first index, only checks index 0
                        first_sell = sell_positions[0]
                        p_sell = (first_sell['price'] - ask) * first_sell['lot'] * self.contract_size
                        if buy_profit > abs(p_sell) and p_sell < 0:
                            # Close that sell and close all buys
                            balance += buy_profit + p_sell
                            trades_history.append({'pnl': p_sell})
                            for bp in buy_positions:
                                trades_history.append({'pnl': (bid - bp['price']) * bp['lot'] * self.contract_size})
                            positions = [p for p in positions if p['ticket'] != first_sell['ticket'] and p['type'] != 'BUY']
                            max_buy_profit = 0
                            continue
                    else: # Corrected recycling
                        # Finds best viable losing sell order that fits within buy_profit
                        best_sell = None
                        best_loss = 0
                        for sp in sell_positions:
                            p_sell = (sp['price'] - ask) * sp['lot'] * self.contract_size
                            if p_sell < 0 and buy_profit > abs(p_sell):
                                if best_sell is None or abs(p_sell) > abs(best_loss):
                                    best_sell = sp
                                    best_loss = p_sell
                        if best_sell is not None:
                            balance += buy_profit + best_loss
                            trades_history.append({'pnl': best_loss})
                            for bp in buy_positions:
                                trades_history.append({'pnl': (bid - bp['price']) * bp['lot'] * self.contract_size})
                            positions = [p for p in positions if p['ticket'] != best_sell['ticket'] and p['type'] != 'BUY']
                            max_buy_profit = 0
                            continue
                            
                if sell_profit >= self.target_side and len(buy_positions) > 0:
                    if self.mode == "original":
                        first_buy = buy_positions[0]
                        p_buy = (bid - first_buy['price']) * first_buy['lot'] * self.contract_size
                        if sell_profit > abs(p_buy) and p_buy < 0:
                            balance += sell_profit + p_buy
                            trades_history.append({'pnl': p_buy})
                            for sp in sell_positions:
                                trades_history.append({'pnl': (sp['price'] - ask) * sp['lot'] * self.contract_size})
                            positions = [p for p in positions if p['ticket'] != first_buy['ticket'] and p['type'] != 'SELL']
                            max_sell_profit = 0
                            continue
                    else: # Corrected recycling
                        best_buy = None
                        best_loss = 0
                        for bp in buy_positions:
                            p_buy = (bid - bp['price']) * bp['lot'] * self.contract_size
                            if p_buy < 0 and sell_profit > abs(p_buy):
                                if best_buy is None or abs(p_buy) > abs(best_loss):
                                    best_buy = bp
                                    best_loss = p_buy
                        if best_buy is not None:
                            balance += sell_profit + best_loss
                            trades_history.append({'pnl': best_loss})
                            for sp in sell_positions:
                                trades_history.append({'pnl': (sp['price'] - ask) * sp['lot'] * self.contract_size})
                            positions = [p for p in positions if p['ticket'] != best_buy['ticket'] and p['type'] != 'SELL']
                            max_sell_profit = 0
                            continue

                # 3. Normal Giro entries (when side is empty)
                buy_positions = [p for p in positions if p['type'] == 'BUY']
                sell_positions = [p for p in positions if p['type'] == 'SELL']
                
                if len(buy_positions) == 0:
                    positions.append({'type': 'BUY', 'lot': self.initial_lot, 'price': ask, 'ticket': ticket_seq})
                    ticket_seq += 1
                    max_buy_profit = 0
                    
                if len(sell_positions) == 0:
                    positions.append({'type': 'SELL', 'lot': self.initial_lot, 'price': bid, 'ticket': ticket_seq})
                    ticket_seq += 1
                    max_sell_profit = 0

                # Recompute profits after entries
                buy_positions = [p for p in positions if p['type'] == 'BUY']
                sell_positions = [p for p in positions if p['type'] == 'SELL']
                buy_profit = sum((bid - p['price']) * p['lot'] * self.contract_size for p in buy_positions)
                sell_profit = sum((p['price'] - ask) * p['lot'] * self.contract_size for p in sell_positions)
                total_floating = buy_profit + sell_profit

                # 4. Trailing Stop or Fixed Target
                if not self.use_trailing:
                    if buy_profit >= self.target_side:
                        balance += buy_profit
                        for p in buy_positions:
                            trades_history.append({'pnl': (bid - p['price']) * p['lot'] * self.contract_size})
                        positions = [p for p in positions if p['type'] != 'BUY']
                        max_buy_profit = 0
                    if sell_profit >= self.target_side:
                        balance += sell_profit
                        for p in sell_positions:
                            trades_history.append({'pnl': (p['price'] - ask) * p['lot'] * self.contract_size})
                        positions = [p for p in positions if p['type'] != 'SELL']
                        max_sell_profit = 0
                else:
                    # Trailing Compra
                    if buy_profit >= self.target_side:
                        if buy_profit > max_buy_profit:
                            max_buy_profit = buy_profit
                        drop = max_buy_profit * (self.trailing_drop_pct / 100.0)
                        if (max_buy_profit - buy_profit) >= drop:
                            balance += buy_profit
                            for p in buy_positions:
                                trades_history.append({'pnl': (bid - p['price']) * p['lot'] * self.contract_size})
                            positions = [p for p in positions if p['type'] != 'BUY']
                            max_buy_profit = 0
                    elif self.mode == "original":
                        # Original bug: resets to 0 if buy_profit < target_side
                        max_buy_profit = 0
                    else:
                        # Corrected: if already was in trailing and drops below floor, close with target profit
                        if max_buy_profit > 0:
                            balance += buy_profit
                            for p in buy_positions:
                                trades_history.append({'pnl': (bid - p['price']) * p['lot'] * self.contract_size})
                            positions = [p for p in positions if p['type'] != 'BUY']
                            max_buy_profit = 0

                    # Trailing Venda
                    if sell_profit >= self.target_side:
                        if sell_profit > max_sell_profit:
                            max_sell_profit = sell_profit
                        drop = max_sell_profit * (self.trailing_drop_pct / 100.0)
                        if (max_sell_profit - sell_profit) >= drop:
                            balance += sell_profit
                            for p in sell_positions:
                                trades_history.append({'pnl': (p['price'] - ask) * p['lot'] * self.contract_size})
                            positions = [p for p in positions if p['type'] != 'SELL']
                            max_sell_profit = 0
                    elif self.mode == "original":
                        max_sell_profit = 0
                    else:
                        if max_sell_profit > 0:
                            balance += sell_profit
                            for p in sell_positions:
                                trades_history.append({'pnl': (p['price'] - ask) * p['lot'] * self.contract_size})
                            positions = [p for p in positions if p['type'] != 'SELL']
                            max_sell_profit = 0

                # 5. Grid entries (Martingale)
                buy_positions = [p for p in positions if p['type'] == 'BUY']
                sell_positions = [p for p in positions if p['type'] == 'SELL']
                
                if len(buy_positions) > 0 and len(buy_positions) < self.max_orders:
                    lowest_buy = min(buy_positions, key=lambda x: x['price'])
                    if ask < (lowest_buy['price'] - dist):
                        last_lot = lowest_buy['lot']
                        next_lot = round(last_lot * self.lot_mult, 2) if len(buy_positions) < self.max_martingale else last_lot
                        positions.append({'type': 'BUY', 'lot': next_lot, 'price': ask, 'ticket': ticket_seq})
                        ticket_seq += 1
                        
                if len(sell_positions) > 0 and len(sell_positions) < self.max_orders:
                    highest_sell = max(sell_positions, key=lambda x: x['price'])
                    if bid > (highest_sell['price'] + dist):
                        last_lot = highest_sell['lot']
                        next_lot = round(last_lot * self.lot_mult, 2) if len(sell_positions) < self.max_martingale else last_lot
                        positions.append({'type': 'SELL', 'lot': next_lot, 'price': bid, 'ticket': ticket_seq})
                        ticket_seq += 1

        # End of test: close remaining positions
        for p in positions:
            pnl = (c - p['price']) * p['lot'] * self.contract_size if p['type'] == 'BUY' else (p['price'] - c) * p['lot'] * self.contract_size
            balance += pnl
            trades_history.append({'pnl': pnl})
            
        total_trades = len(trades_history)
        wins = sum(1 for t in trades_history if t['pnl'] > 0)
        losses = sum(1 for t in trades_history if t['pnl'] < 0)
        win_rate = (wins / total_trades * 100.0) if total_trades > 0 else 0.0
        net_profit = balance - initial_balance
        gross_profit = sum(t['pnl'] for t in trades_history if t['pnl'] > 0)
        gross_loss = abs(sum(t['pnl'] for t in trades_history if t['pnl'] < 0))
        profit_factor = (gross_profit / gross_loss) if gross_loss > 0 else (999.0 if gross_profit > 0 else 0)
        
        return {
            'timeframe': self.tf_name,
            'mode': self.mode,
            'initial_balance': initial_balance,
            'final_balance': round(balance, 2),
            'net_profit': round(net_profit, 2),
            'profit_pct': round((net_profit / initial_balance) * 100.0, 2),
            'max_drawdown_usd': round(max_drawdown_usd, 2),
            'max_drawdown_pct': round(max_drawdown_pct, 2),
            'total_trades': total_trades,
            'win_rate': round(win_rate, 2),
            'profit_factor': round(profit_factor, 2),
            'max_orders': max_active_orders
        }

def run_all_tests():
    mt5.initialize()
    symbol = 'XAUUSD-ECN'
    timeframes = [
        ('1 Minuto (M1)', mt5.TIMEFRAME_M1, 25000),
        ('5 Minutos (M5)', mt5.TIMEFRAME_M5, 15000),
        ('15 Minutos (M15)', mt5.TIMEFRAME_M15, 8000)
    ]
    
    results = []
    print("=" * 80)
    print("INICIANDO TESTES DO BURGO SCALPE PRO NO XAUUSD (M1, M5, M15)")
    print("=" * 80)
    
    for tf_name, tf_const, n_bars in timeframes:
        print(f"\nBaixando {n_bars} barras de {symbol} em {tf_name}...")
        rates = mt5.copy_rates_from_pos(symbol, tf_const, 0, n_bars)
        if rates is None or len(rates) == 0:
            print(f"Erro ao obter dados para {tf_name}: {mt5.last_error()}")
            continue
        df = pd.DataFrame(rates)
        start_date = datetime.fromtimestamp(df['time'].iloc[0]).strftime('%d/%m/%Y')
        end_date = datetime.fromtimestamp(df['time'].iloc[-1]).strftime('%d/%m/%Y')
        print(f"Período: {start_date} até {end_date} ({len(df)} barras)")
        
        # 1. Teste Código Original (com as falhas de escrita/reciclagem)
        sim_orig = BurgoScalperSim(df, tf_name, mode="original")
        res_orig = sim_orig.run()
        results.append(res_orig)
        
        # 2. Teste Código Corrigido
        sim_corr = BurgoScalperSim(df, tf_name, mode="corrected")
        res_corr = sim_corr.run()
        results.append(res_corr)
        
        print(f"\n--- RESULTADO {tf_name} ---")
        print(f"[ORIGINAL COM ERROS] Lucro: ${res_orig['net_profit']} ({res_orig['profit_pct']}%) | Drawdown Máx: ${res_orig['max_drawdown_usd']} ({res_orig['max_drawdown_pct']}%) | Cesta Máx: {res_orig['max_orders']} ordens | PF: {res_orig['profit_factor']}")
        print(f"[CORRIGIDO / V39.1 ] Lucro: ${res_corr['net_profit']} ({res_corr['profit_pct']}%) | Drawdown Máx: ${res_corr['max_drawdown_usd']} ({res_corr['max_drawdown_pct']}%) | Cesta Máx: {res_corr['max_orders']} ordens | PF: {res_corr['profit_factor']}")
        
    mt5.shutdown()
    
    res_df = pd.DataFrame(results)
    res_df.to_csv("resultado_testes_xauusd.csv", index=False)
    print("\n" + "=" * 80)
    print("TABELA RESUMO CONSOLIDADA")
    print("=" * 80)
    print(res_df.to_string())

if __name__ == "__main__":
    run_all_tests()
