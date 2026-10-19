import datetime
import pandas as pd
import numpy as np
from run_xauusd_tests import get_xauusd_data

df = get_xauusd_data()

class TimedBacktestEngine:
    def __init__(self, df, initial_balance=2000.0, spread_usd=0.20):
        self.df = df
        self.initial_balance = initial_balance
        self.spread = spread_usd
        self.point = 0.01
        self.contract_size = 100.0

    def run(self, params):
        initial_lot     = params.get('InitialLot', 0.01)
        target_side     = params.get('TargetSideUSD', 2.00)
        target_global   = params.get('TargetGlobalUSD', 20.00)
        base_distance   = params.get('BaseDistance', 600) * self.point
        lot_multiplier  = params.get('LotMultiplier', 1.2)
        max_martingale  = params.get('MaxMartingale', 3)
        max_orders      = params.get('MaxTotalOrders', 3)
        use_atr         = params.get('UseATR', True)
        atr_mult        = params.get('ATRMultiplier', 1.5)
        use_trailing    = params.get('UseTrailingStop', True)
        trailing_start  = params.get('TrailingStartUSD', 4.00)
        trailing_drop   = params.get('TrailingDropPct', 15.0) / 100.0
        
        start_time_str  = params.get('StartTime', '00:00')
        end_time_str    = params.get('EndTime', '23:59')
        
        s_h, s_m = map(int, start_time_str.split(':'))
        e_h, e_m = map(int, end_time_str.split(':'))
        start_mins = s_h * 60 + s_m
        end_mins = e_h * 60 + e_m

        balance = self.initial_balance
        peak_equity = balance
        max_dd_usd = 0.0
        max_dd_pct = 0.0

        buy_positions = []
        sell_positions = []

        max_buy_profit = 0.0
        max_sell_profit = 0.0
        max_global_profit = 0.0

        total_trades = 0
        winning_trades = 0
        recycled_orders = 0

        def norm_lot(vol):
            return max(0.01, round(vol, 2))

        for row in self.df.itertuples():
            o, h, l, c = row.open, row.high, row.low, row.close
            atr = row.atr
            bar_time = row.time
            cur_mins = bar_time.hour * 60 + bar_time.minute
            
            if start_mins <= end_mins:
                is_trading_time = (cur_mins >= start_mins and cur_mins <= end_mins)
            else:
                is_trading_time = (cur_mins >= start_mins or cur_mins <= end_mins)

            dyn_dist = max(base_distance / 2.0, atr * atr_mult) if use_atr else base_distance

            price_steps = [o, l, h, c] if c >= o else [o, h, l, c]

            for price in price_steps:
                ask = price + (self.spread / 2.0)
                bid = price - (self.spread / 2.0)

                buy_profit = sum((bid - pos['price']) * pos['volume'] * self.contract_size for pos in buy_positions)
                sell_profit = sum((pos['price'] - ask) * pos['volume'] * self.contract_size for pos in sell_positions)
                total_floating = buy_profit + sell_profit

                equity = balance + total_floating
                if equity > peak_equity:
                    peak_equity = equity
                dd_usd = peak_equity - equity
                if dd_usd > max_dd_usd:
                    max_dd_usd = dd_usd
                    max_dd_pct = (max_dd_usd / peak_equity) * 100.0

                # 1. Reset Global / Fechamento Global
                if not use_trailing:
                    if total_floating >= target_global:
                        balance += total_floating
                        total_trades += len(buy_positions) + len(sell_positions)
                        winning_trades += (len(buy_positions) + len(sell_positions))
                        buy_positions.clear()
                        sell_positions.clear()
                        max_global_profit = 0.0
                        continue
                else:
                    if total_floating >= target_global:
                        if total_floating > max_global_profit:
                            max_global_profit = total_floating
                    if max_global_profit >= target_global:
                        if (max_global_profit - total_floating) >= (max_global_profit * trailing_drop):
                            balance += total_floating
                            total_trades += len(buy_positions) + len(sell_positions)
                            winning_trades += (len(buy_positions) + len(sell_positions))
                            buy_positions.clear()
                            sell_positions.clear()
                            max_global_profit = 0.0
                            continue

                # 2. Reciclagem Ativa
                if buy_profit >= target_side and len(sell_positions) > 0:
                    best_cand_idx = -1
                    best_cand_loss = 0.0
                    for idx, sp in enumerate(sell_positions):
                        p_loss = (sp['price'] - ask) * sp['volume'] * self.contract_size
                        if p_loss < 0 and buy_profit >= abs(p_loss):
                            if best_cand_idx == -1 or abs(p_loss) > abs(best_cand_loss):
                                best_cand_idx = idx
                                best_cand_loss = p_loss
                    if best_cand_idx != -1:
                        balance += buy_profit + best_cand_loss
                        total_trades += len(buy_positions) + 1
                        winning_trades += len(buy_positions)
                        recycled_orders += 1
                        buy_positions.clear()
                        sell_positions.pop(best_cand_idx)
                        max_buy_profit = 0.0
                        continue

                if sell_profit >= target_side and len(buy_positions) > 0:
                    best_cand_idx = -1
                    best_cand_loss = 0.0
                    for idx, bp in enumerate(buy_positions):
                        p_loss = (bid - bp['price']) * bp['volume'] * self.contract_size
                        if p_loss < 0 and sell_profit >= abs(p_loss):
                            if best_cand_idx == -1 or abs(p_loss) > abs(best_cand_loss):
                                best_cand_idx = idx
                                best_cand_loss = p_loss
                    if best_cand_idx != -1:
                        balance += sell_profit + best_cand_loss
                        total_trades += len(sell_positions) + 1
                        winning_trades += len(sell_positions)
                        recycled_orders += 1
                        sell_positions.clear()
                        buy_positions.pop(best_cand_idx)
                        max_sell_profit = 0.0
                        continue

                # 3. Fechamento de Lado / Trailing Stop Individual
                if not use_trailing:
                    if buy_profit >= target_side:
                        balance += buy_profit
                        total_trades += len(buy_positions)
                        winning_trades += len(buy_positions)
                        buy_positions.clear()
                        max_buy_profit = 0.0
                        continue
                    if sell_profit >= target_side:
                        balance += sell_profit
                        total_trades += len(sell_positions)
                        winning_trades += len(sell_positions)
                        sell_positions.clear()
                        max_sell_profit = 0.0
                        continue
                else:
                    start_side = trailing_start if trailing_start > 0 else target_side
                    if buy_profit >= start_side:
                        if buy_profit > max_buy_profit:
                            max_buy_profit = buy_profit
                    if max_buy_profit >= start_side:
                        if (max_buy_profit - buy_profit) >= (max_buy_profit * trailing_drop):
                            balance += buy_profit
                            total_trades += len(buy_positions)
                            winning_trades += len(buy_positions)
                            buy_positions.clear()
                            max_buy_profit = 0.0
                            continue

                    if sell_profit >= start_side:
                        if sell_profit > max_sell_profit:
                            max_sell_profit = sell_profit
                    if max_sell_profit >= start_side:
                        if (max_sell_profit - sell_profit) >= (max_sell_profit * trailing_drop):
                            balance += sell_profit
                            total_trades += len(sell_positions)
                            winning_trades += len(sell_positions)
                            sell_positions.clear()
                            max_sell_profit = 0.0
                            continue

                # 4. Aberturas de novas ordens (Giro e Grade) restritas a is_trading_time
                if is_trading_time:
                    if len(buy_positions) == 0:
                        buy_positions.append({'price': ask, 'volume': norm_lot(initial_lot)})
                    if len(sell_positions) == 0:
                        sell_positions.append({'price': bid, 'volume': norm_lot(initial_lot)})

                    if len(buy_positions) > 0 and len(buy_positions) < max_orders:
                        lowest_buy = min(p['price'] for p in buy_positions)
                        if ask < (lowest_buy - dyn_dist):
                            last_vol = [p['volume'] for p in buy_positions if p['price'] == lowest_buy][0]
                            next_lot = norm_lot(last_vol * lot_multiplier) if len(buy_positions) < max_martingale else last_vol
                            buy_positions.append({'price': ask, 'volume': next_lot})

                    if len(sell_positions) > 0 and len(sell_positions) < max_orders:
                        highest_sell = max(p['price'] for p in sell_positions)
                        if bid > (highest_sell + dyn_dist):
                            last_vol = [p['volume'] for p in sell_positions if p['price'] == highest_sell][0]
                            next_lot = norm_lot(last_vol * lot_multiplier) if len(sell_positions) < max_martingale else last_vol
                            sell_positions.append({'price': bid, 'volume': next_lot})

        final_floating = sum((c - pos['price']) * pos['volume'] * self.contract_size for pos in buy_positions) + \
                         sum((pos['price'] - c) * pos['volume'] * self.contract_size for pos in sell_positions)
        final_balance = balance + final_floating
        total_profit_usd = final_balance - self.initial_balance
        total_profit_pct = (total_profit_usd / self.initial_balance) * 100.0

        return {
            'ProfitUSD': round(total_profit_usd, 2),
            'ProfitPct': round(total_profit_pct, 2),
            'MaxDD_USD': round(max_dd_usd, 2),
            'MaxDD_Pct': round(max_dd_pct, 2),
            'Recycled': recycled_orders,
            'TotalTrades': total_trades,
            'RecoveryFactor': round(total_profit_usd / max_dd_usd, 2) if max_dd_usd > 0 else 0.0
        }

engine = TimedBacktestEngine(df, initial_balance=2000.0)

# Testes de Horários (Sessões) e Dinâmica
session_tests = [
    # Sessão Asiática / Madrugada (Horário de consolidação com menor volatilidade direcional)
    {'name': 'Asiática (00:00 - 06:00) / Dist 800 / Mult 1.2 / Max 3', 'StartTime': '00:00', 'EndTime': '06:00', 'BaseDistance': 800, 'LotMultiplier': 1.2, 'MaxTotalOrders': 3, 'TargetSideUSD': 3.0, 'TargetGlobalUSD': 15.0},
    {'name': 'Asiática (22:00 - 05:00) / Dist 1000 / Mult 1.1 / Max 3', 'StartTime': '22:00', 'EndTime': '05:00', 'BaseDistance': 1000, 'LotMultiplier': 1.1, 'MaxTotalOrders': 3, 'TargetSideUSD': 4.0, 'TargetGlobalUSD': 20.0},
    {'name': 'Asiática (01:00 - 07:00) / Dist 1200 / Mult 1.0 (Fixo) / Max 3', 'StartTime': '01:00', 'EndTime': '07:00', 'BaseDistance': 1200, 'LotMultiplier': 1.0, 'MaxTotalOrders': 3, 'TargetSideUSD': 4.0, 'TargetGlobalUSD': 20.0},
    
    # Horário Comercial Europeu / Londrino (08:00 - 12:00)
    {'name': 'Londres (08:00 - 12:00) / Dist 1200 / Mult 1.2 / Max 3', 'StartTime': '08:00', 'EndTime': '12:00', 'BaseDistance': 1200, 'LotMultiplier': 1.2, 'MaxTotalOrders': 3, 'TargetSideUSD': 5.0, 'TargetGlobalUSD': 25.0},
    
    # Final do Dia de NY (18:00 - 23:00)
    {'name': 'Fechamento NY (18:00 - 23:00) / Dist 700 / Mult 1.2 / Max 3', 'StartTime': '18:00', 'EndTime': '23:00', 'BaseDistance': 700, 'LotMultiplier': 1.2, 'MaxTotalOrders': 3, 'TargetSideUSD': 3.0, 'TargetGlobalUSD': 15.0},

    # 24H com Grade Ultra-Curta (Max 2 ordens)
    {'name': '24h / Max 2 Ordens / Dist 800 / Mult 1.2 / Alvo $3', 'StartTime': '00:00', 'EndTime': '23:59', 'BaseDistance': 800, 'LotMultiplier': 1.2, 'MaxTotalOrders': 2, 'TargetSideUSD': 3.0, 'TargetGlobalUSD': 15.0},
    {'name': '24h / Max 2 Ordens / Dist 1000 / Mult 1.0 (Fixo) / Alvo $4', 'StartTime': '00:00', 'EndTime': '23:59', 'BaseDistance': 1000, 'LotMultiplier': 1.0, 'MaxTotalOrders': 2, 'TargetSideUSD': 4.0, 'TargetGlobalUSD': 20.0},
    {'name': '24h / Max 2 Ordens / Dist 1500 / Mult 1.0 (Fixo) / Alvo $5', 'StartTime': '00:00', 'EndTime': '23:59', 'BaseDistance': 1500, 'LotMultiplier': 1.0, 'MaxTotalOrders': 2, 'TargetSideUSD': 5.0, 'TargetGlobalUSD': 25.0},
]

results = []
print("Testando sessões operacionais e grades de baixo risco...")
for test in session_tests:
    cfg = {
        'InitialLot': 0.01,
        'TargetSideUSD': 3.00,
        'TargetGlobalUSD': 20.00,
        'BaseDistance': 800,
        'LotMultiplier': 1.2,
        'MaxMartingale': 2,
        'MaxTotalOrders': 2,
        'UseATR': True,
        'ATRMultiplier': 1.5,
        'UseTrailingStop': True,
        'TrailingStartUSD': 4.00,
        'TrailingDropPct': 15.0
    }
    cfg.update(test)
    name = cfg.pop('name')
    res = engine.run(cfg)
    res['Name'] = name
    results.append(res)
    print(f"[{name}] Lucro: ${res['ProfitUSD']} ({res['ProfitPct']}%) | MaxDD: {res['MaxDD_Pct']}% (${res['MaxDD_USD']}) | Fator Rec: {res['RecoveryFactor']}")

df_res = pd.DataFrame(results).sort_values(by='ProfitPct', ascending=False)
print("\n=== RANKING SESSÕES E GRADES CURTAS ===")
print(df_res[['Name', 'ProfitUSD', 'ProfitPct', 'MaxDD_Pct', 'RecoveryFactor']].to_string(index=False))
