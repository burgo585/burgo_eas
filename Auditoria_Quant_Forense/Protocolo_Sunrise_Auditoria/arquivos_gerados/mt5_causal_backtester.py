import argparse
import datetime
import numpy as np
import pandas as pd
import MetaTrader5 as mt5

def load_mt5_data_and_specs(symbol="XAUUSD-ECN", timeframe=mt5.TIMEFRAME_M15,
                            utc_from=datetime.datetime(2024, 1, 1),
                            utc_to=datetime.datetime(2026, 10, 19, 23, 59),
                            mt5_path=r"C:\MetaTrader\terminal64.exe"):
    if not mt5.initialize(path=mt5_path):
        raise RuntimeError(f"Falha ao inicializar MT5: {mt5.last_error()}")

    mt5.symbol_select(symbol, True)
    sym_info = mt5.symbol_info(symbol)
    acc_info = mt5.account_info()

    if sym_info is None:
        mt5.shutdown()
        raise RuntimeError(f"Símbolo {symbol} não encontrado no MT5.")

    specs = {
        "symbol": sym_info.name,
        "point": sym_info.point,
        "digits": sym_info.digits,
        "contract_size": sym_info.trade_contract_size,
        "swap_long_pts": sym_info.swap_long,
        "swap_short_pts": sym_info.swap_short,
        "swap_rollover3days": sym_info.swap_rollover3days, # 3 = Quarta-feira
        "current_spread_pts": sym_info.spread,
        "leverage": float(acc_info.leverage) if acc_info and acc_info.leverage > 0 else 500.0,
        "server": acc_info.server if acc_info else "Unknown"
    }

    rates = mt5.copy_rates_range(symbol, timeframe, utc_from, utc_to)
    mt5.shutdown()

    if rates is None or len(rates) == 0:
        raise RuntimeError("Nenhuma barra histórica retornada pelo MT5.")

    df = pd.DataFrame(rates)
    df['time'] = pd.to_datetime(df['time'], unit='s')

    # Cálculo ESTRITAMENTE CAUSAL dos indicadores com .shift(1) (barra anterior fechada!)
    high_low = df['high'] - df['low']
    high_close = (df['high'] - df['close'].shift(1)).abs()
    low_close = (df['low'] - df['close'].shift(1)).abs()
    tr = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)

    df['atr14_clean'] = tr.rolling(window=14).mean().shift(1).bfill()
    df['ema200_clean'] = df['close'].ewm(span=200, adjust=False).mean().shift(1).bfill()

    return df, specs


class CausalGridBacktester:
    def __init__(self, df, specs, commission_per_lot=6.00, slippage_usd=0.10, min_spread_usd=0.20, stop_out_pct=20.0):
        self.df = df
        self.specs = specs
        self.point = specs['point']
        self.contract_size = specs['contract_size']
        self.swap_long_pts = specs['swap_long_pts']
        self.swap_short_pts = specs['swap_short_pts']
        self.rollover_3day = specs['swap_rollover3days'] - 1 # 0=Seg, 1=Ter, 2=Qua
        self.commission_per_lot = commission_per_lot
        self.slippage_usd = slippage_usd
        self.min_spread_usd = min_spread_usd
        self.stop_out_pct = stop_out_pct

    def run_single(self, df_sub, params):
        balance_init   = float(params.get('BalanceInit', 100.0))
        leverage       = float(params.get('Leverage', self.specs['leverage']))
        mode           = params.get('Mode', 'BUY_ONLY') # 'BUY_ONLY', 'EMA_BOTH', 'BOTH_OPEN'
        initial_lot    = float(params.get('InitialLot', 0.01))
        target_side    = float(params.get('TargetSideUSD', 3.0))
        target_global  = float(params.get('TargetGlobalUSD', 15.0))
        base_dist      = float(params.get('BaseDistancePts', 300)) * self.point
        lot_mult       = float(params.get('LotMultiplier', 1.2))
        max_martingale = int(params.get('MaxMartingale', 3))
        max_orders     = int(params.get('MaxTotalOrders', 4))
        use_atr        = bool(params.get('UseATR', True))
        atr_mult       = float(params.get('ATRMultiplier', 1.5))
        use_trailing   = bool(params.get('UseTrailingStop', False))
        trailing_start = float(params.get('TrailingStartUSD', 5.0))
        trailing_drop  = float(params.get('TrailingDropPct', 10.0)) / 100.0
        start_time_str = params.get('StartTime', '00:00')
        end_time_str   = params.get('EndTime', '23:59')

        sh, sm = map(int, start_time_str.split(':'))
        eh, em = map(int, end_time_str.split(':'))
        start_mins, end_mins = sh * 60 + sm, eh * 60 + em

        balance = balance_init
        peak_equity = balance_init
        min_equity = balance_init
        max_dd_usd = 0.0
        max_dd_pct = 0.0
        max_single_basket_loss = 0.0
        max_margin_used = 0.0

        buy_positions = []
        sell_positions = []
        max_buy_profit = 0.0
        max_sell_profit = 0.0
        max_global_profit = 0.0

        total_trades = 0
        recycled_orders = 0
        total_swap_usd = 0.0
        total_comm_usd = 0.0
        stopped_out = False
        stop_out_date = None
        last_day = None

        def norm_lot(vol):
            return max(0.01, round(vol, 2))

        def eval_point(price_bid, bar_spread, dyn_dist, ema, allow_new_giro, bar_time):
            nonlocal balance, peak_equity, min_equity, max_dd_usd, max_dd_pct, max_single_basket_loss, max_margin_used
            nonlocal max_buy_profit, max_sell_profit, max_global_profit
            nonlocal total_trades, recycled_orders, total_comm_usd, stopped_out, stop_out_date

            bid = price_bid
            ask = price_bid + bar_spread

            # 1. Preenchimento Causal de Grade (todas as ordens rompidas no movimento, sem comprar no fundo do pavio)
            if allow_new_giro or len(buy_positions) > 0 or len(sell_positions) > 0:
                while len(buy_positions) > 0 and len(buy_positions) < max_orders:
                    lowest_buy = min(p['price'] for p in buy_positions)
                    trigger_ask = lowest_buy - dyn_dist
                    if ask <= trigger_ask:
                        last_vol = [p['volume'] for p in buy_positions if p['price'] == lowest_buy][0]
                        next_lot = norm_lot(last_vol * lot_mult) if len(buy_positions) < max_martingale else last_vol
                        fill_p = max(ask, trigger_ask) + self.slippage_usd
                        comm = next_lot * self.commission_per_lot
                        total_comm_usd += comm
                        buy_positions.append({'price': fill_p, 'volume': next_lot, 'swap': 0.0, 'comm': -comm})
                    else:
                        break

                while len(sell_positions) > 0 and len(sell_positions) < max_orders:
                    highest_sell = max(p['price'] for p in sell_positions)
                    trigger_bid = highest_sell + dyn_dist
                    if bid >= trigger_bid:
                        last_vol = [p['volume'] for p in sell_positions if p['price'] == highest_sell][0]
                        next_lot = norm_lot(last_vol * lot_mult) if len(sell_positions) < max_martingale else last_vol
                        fill_p = min(bid, trigger_bid) - self.slippage_usd
                        comm = next_lot * self.commission_per_lot
                        total_comm_usd += comm
                        sell_positions.append({'price': fill_p, 'volume': next_lot, 'swap': 0.0, 'comm': -comm})
                    else:
                        break

            # 2. Cálculo do Lucro Flutuante Real (incluindo Swap e Comissões)
            buy_p = sum(((bid - self.slippage_usd - p['price']) * p['volume'] * self.contract_size) + p['swap'] + p['comm'] for p in buy_positions)
            sell_p = sum(((p['price'] - (ask + self.slippage_usd)) * p['volume'] * self.contract_size) + p['swap'] + p['comm'] for p in sell_positions)
            tot_float = buy_p + sell_p

            if tot_float < -max_single_basket_loss:
                max_single_basket_loss = abs(tot_float)

            eq = balance + tot_float
            if eq < min_equity:
                min_equity = eq
            if eq > peak_equity:
                peak_equity = eq
            dd = peak_equity - eq
            if dd > max_dd_usd:
                max_dd_usd = dd
                max_dd_pct = (max_dd_usd / peak_equity) * 100.0

            # 3. Verificação Rigorosa de Margem e Stop-Out (20%)
            tot_b_lots = sum(p['volume'] for p in buy_positions)
            tot_s_lots = sum(p['volume'] for p in sell_positions)
            tot_lots = max(tot_b_lots, tot_s_lots) if (tot_b_lots > 0 and tot_s_lots > 0) else (tot_b_lots + tot_s_lots)
            margin_used = (tot_lots * self.contract_size * bid) / leverage if tot_lots > 0 else 0.0
            if margin_used > max_margin_used:
                max_margin_used = margin_used

            if margin_used > 0:
                margin_level = (eq / margin_used) * 100.0
                if eq <= 0 or margin_level <= self.stop_out_pct:
                    stopped_out = True
                    stop_out_date = bar_time
                    balance = max(0.0, eq)
                    buy_positions.clear()
                    sell_positions.clear()
                    return

            if len(buy_positions) == 0: max_buy_profit = 0.0
            if len(sell_positions) == 0: max_sell_profit = 0.0
            if len(buy_positions) == 0 and len(sell_positions) == 0: max_global_profit = 0.0

            # 4. Fechamento Global (Estritamente travado sem teletransporte de pavio)
            if not use_trailing:
                if tot_float >= target_global and (len(buy_positions) + len(sell_positions)) > 0:
                    balance += target_global
                    total_trades += len(buy_positions) + len(sell_positions)
                    buy_positions.clear()
                    sell_positions.clear()
                    max_global_profit = 0.0
                    if balance > peak_equity: peak_equity = balance
                    return
            else:
                if tot_float >= target_global:
                    # Sem inflar para o topo do pavio: trava o pico de trailing em um avanço realista
                    capped_global = min(tot_float, target_global * 1.15)
                    if capped_global > max_global_profit:
                        max_global_profit = capped_global
                if max_global_profit >= target_global:
                    if (max_global_profit - tot_float) >= (max_global_profit * trailing_drop):
                        realized = max_global_profit * (1.0 - trailing_drop)
                        balance += realized
                        total_trades += len(buy_positions) + len(sell_positions)
                        buy_positions.clear()
                        sell_positions.clear()
                        max_global_profit = 0.0
                        if balance > peak_equity: peak_equity = balance
                        return

            # 5. Reciclagem Ativa (Lucro de um lado travado em target_side amortizando a maior perda cabível do outro)
            if buy_p >= target_side and len(sell_positions) > 0:
                best_idx = -1
                best_loss = 0.0
                for idx, sp in enumerate(sell_positions):
                    pl = ((sp['price'] - (ask + self.slippage_usd)) * sp['volume'] * self.contract_size) + sp['swap'] + sp['comm']
                    if pl < 0 and target_side >= abs(pl):
                        if best_idx == -1 or abs(pl) > abs(best_loss):
                            best_idx = idx
                            best_loss = pl
                if best_idx != -1:
                    balance += target_side + best_loss
                    total_trades += len(buy_positions) + 1
                    recycled_orders += 1
                    buy_positions.clear()
                    sell_positions.pop(best_idx)
                    max_buy_profit = 0.0
                    if balance > peak_equity: peak_equity = balance
                    return

            if sell_p >= target_side and len(buy_positions) > 0:
                best_idx = -1
                best_loss = 0.0
                for idx, bp in enumerate(buy_positions):
                    pl = ((bid - self.slippage_usd - bp['price']) * bp['volume'] * self.contract_size) + bp['swap'] + bp['comm']
                    if pl < 0 and target_side >= abs(pl):
                        if best_idx == -1 or abs(pl) > abs(best_loss):
                            best_idx = idx
                            best_loss = pl
                if best_idx != -1:
                    balance += target_side + best_loss
                    total_trades += len(sell_positions) + 1
                    recycled_orders += 1
                    sell_positions.clear()
                    buy_positions.pop(best_idx)
                    max_sell_profit = 0.0
                    if balance > peak_equity: peak_equity = balance
                    return

            # 6. Fechamento Individual de Lado (Com ou Sem Trailing Stop, sem teletransporte de pavio)
            if not use_trailing:
                if buy_p >= target_side and len(buy_positions) > 0:
                    balance += target_side
                    total_trades += len(buy_positions)
                    buy_positions.clear()
                    max_buy_profit = 0.0
                    if balance > peak_equity: peak_equity = balance
                if sell_p >= target_side and len(sell_positions) > 0:
                    balance += target_side
                    total_trades += len(sell_positions)
                    sell_positions.clear()
                    max_sell_profit = 0.0
                    if balance > peak_equity: peak_equity = balance
            else:
                start_usd = trailing_start if trailing_start > 0 else target_side
                if buy_p >= start_usd and len(buy_positions) > 0:
                    capped_b = min(buy_p, start_usd * 1.15)
                    if capped_b > max_buy_profit:
                        max_buy_profit = capped_b
                if max_buy_profit >= start_usd and len(buy_positions) > 0:
                    if (max_buy_profit - buy_p) >= (max_buy_profit * trailing_drop):
                        balance += max_buy_profit * (1.0 - trailing_drop)
                        total_trades += len(buy_positions)
                        buy_positions.clear()
                        max_buy_profit = 0.0
                        if balance > peak_equity: peak_equity = balance

                if sell_p >= start_usd and len(sell_positions) > 0:
                    capped_s = min(sell_p, start_usd * 1.15)
                    if capped_s > max_sell_profit:
                        max_sell_profit = capped_s
                if max_sell_profit >= start_usd and len(sell_positions) > 0:
                    if (max_sell_profit - sell_p) >= (max_sell_profit * trailing_drop):
                        balance += max_sell_profit * (1.0 - trailing_drop)
                        total_trades += len(sell_positions)
                        sell_positions.clear()
                        max_sell_profit = 0.0
                        if balance > peak_equity: peak_equity = balance

            # 7. Abertura de Giro Inicial (Somente dentro do horário operacional e se permitido no ponto da barra)
            if allow_new_giro:
                can_buy = True if mode == "BUY_ONLY" else (True if mode == "BOTH_OPEN" else (ask >= ema))
                can_sell = False if mode == "BUY_ONLY" else (True if mode == "BOTH_OPEN" else (bid <= ema))
                if len(buy_positions) == 0 and can_buy:
                    lot0 = norm_lot(initial_lot)
                    comm = lot0 * self.commission_per_lot
                    total_comm_usd += comm
                    buy_positions.append({'price': ask + self.slippage_usd, 'volume': lot0, 'swap': 0.0, 'comm': -comm})
                if len(sell_positions) == 0 and can_sell:
                    lot0 = norm_lot(initial_lot)
                    comm = lot0 * self.commission_per_lot
                    total_comm_usd += comm
                    sell_positions.append({'price': bid - self.slippage_usd, 'volume': lot0, 'swap': 0.0, 'comm': -comm})

        for row in df_sub.itertuples():
            o, h, l, c = row.open, row.high, row.low, row.close
            bar_time = row.time
            atr = row.atr14_clean
            ema = row.ema200_clean
            bar_spread = max(self.min_spread_usd, row.spread * self.point)
            dyn_dist = max(base_dist / 2.0, atr * atr_mult) if use_atr else base_dist

            cur_mins = bar_time.hour * 60 + bar_time.minute
            in_hours = (cur_mins >= start_mins and cur_mins <= end_mins) if start_mins <= end_mins else (cur_mins >= start_mins or cur_mins <= end_mins)

            # Cobrança de Swap Diário na virada de dia (com triplo na Quarta-feira)
            cur_day = bar_time.date()
            if last_day is not None and cur_day != last_day:
                mult_sw = 3.0 if last_day.weekday() == self.rollover_3day else 1.0
                for bp in buy_positions:
                    sw = (self.swap_long_pts * self.point * self.contract_size) * bp['volume'] * mult_sw
                    bp['swap'] += sw
                    total_swap_usd += sw
                for sp in sell_positions:
                    sw = (self.swap_short_pts * self.point * self.contract_size) * sp['volume'] * mult_sw
                    sp['swap'] += sw
                    total_swap_usd += sw
            last_day = cur_day

            # Caminho estritamente causal e conservador: Open -> High -> Low -> Close
            # (Impede que compras abertas no Low fechem no High passado da mesma barra!)
            seq = [(o, in_hours), (h, False), (l, False), (c, in_hours)]
            for p_val, allow_g in seq:
                eval_point(p_val, bar_spread, dyn_dist, ema, allow_g, bar_time)
                if stopped_out:
                    break
            if stopped_out:
                break

        final_floating = sum(((c - p['price']) * p['volume'] * self.contract_size) + p['swap'] + p['comm'] for p in buy_positions) + \
                         sum(((p['price'] - c) * p['volume'] * self.contract_size) + p['swap'] + p['comm'] for p in sell_positions)
        final_eq = balance + final_floating
        min_recommended_capital = round(max_single_basket_loss * 1.25 + max_margin_used, 2)

        return {
            'BalanceInit': balance_init,
            'FinalEquity': round(final_eq, 2),
            'NetProfitUSD': round(final_eq - balance_init, 2),
            'NetProfitPct': round(((final_eq - balance_init) / balance_init) * 100.0, 2),
            'MaxDD_USD': round(max_dd_usd, 2),
            'MaxDD_Pct': round(max_dd_pct, 2),
            'MinEquity': round(min_equity, 2),
            'PeakEquity': round(peak_equity, 2),
            'StopOut': stopped_out,
            'StopOutDate': str(stop_out_date) if stop_out_date else "Nenhum",
            'Trades': total_trades,
            'Recycled': recycled_orders,
            'SwapPaidUSD': round(total_swap_usd, 2),
            'CommPaidUSD': round(-total_comm_usd, 2),
            'MinRecommendedCapitalUSD': min_recommended_capital
        }

    def run_with_rolling_ruin(self, params):
        full_res = self.run_single(self.df, params)
        months = pd.date_range('2024-02-01', '2026-09-01', freq='MS')
        blown = 0
        tot = 0
        worst_basket = full_res['MinRecommendedCapitalUSD']
        for m in months:
            sub = self.df[self.df['time'] >= m]
            if len(sub) < 100:
                continue
            tot += 1
            r = self.run_single(sub, params)
            if r['StopOut']:
                blown += 1
            if r['MinRecommendedCapitalUSD'] > worst_basket:
                worst_basket = r['MinRecommendedCapitalUSD']

        full_res['RollingMonthsTested'] = tot
        full_res['RollingMonthsBlown'] = blown
        full_res['RiskOfRuinPct'] = round((blown / tot) * 100.0, 1) if tot > 0 else 0.0
        full_res['MinRecommendedCapitalUSD'] = worst_basket
        return full_res


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Motor Oficial de Backtest Causal & Risco de Ruína (Protocolo Sunrise)")
    parser.add_argument("--suite-burgo-v40", action="store_true", help="Executa a bateria completa auditada do projeto Burgo V40")
    args = parser.parse_args()

    df, specs = load_mt5_data_and_specs()
    engine = CausalGridBacktester(df, specs)

    print("==========================================================================================")
    print("  LAUDO OFICIAL DO MOTOR CAUSAL & RISCO DE RUÍNA (PROTOCOLO SUNRISE - XAUUSD 2024-2026)  ")
    print("==========================================================================================")
    print(f"Ativo: {specs['symbol']} | Servidor: {specs['server']} | Alavancagem: 1:{int(specs['leverage'])}")
    print(f"Swap Long Real: {specs['swap_long_pts']} pts/lote/noite | Swap Short Real: +{specs['swap_short_pts']} pts/lote/noite (3x Quarta)")
    print("Fricção Aplicada: Spread Real MT5 (mín $0.20) + Comissão ECN ($6.00/lote) + Slippage ($0.10) + Shift(1) Estrito\n")

    suite = [
        ("1. Seu Arquivo .set Original (Dist 150, Max 8, Lote 0.02, 01h-04h) [$100]", {
            'BalanceInit': 100.0, 'Mode': 'BOTH_OPEN', 'InitialLot': 0.02, 'TargetSideUSD': 3.0, 'TargetGlobalUSD': 6.0,
            'BaseDistancePts': 150, 'LotMultiplier': 1.2, 'MaxMartingale': 4, 'MaxTotalOrders': 8,
            'UseATR': True, 'ATRMultiplier': 1.5, 'UseTrailingStop': True, 'TrailingStartUSD': 5.0, 'TrailingDropPct': 15.0,
            'StartTime': '01:00', 'EndTime': '04:00'
        }),
        ("2. Canal de 200 Pontos (Modo Original Sem Filtro, Max 15, Lote 0.02) [$100]", {
            'BalanceInit': 100.0, 'Mode': 'BOTH_OPEN', 'InitialLot': 0.02, 'TargetSideUSD': 2.0, 'TargetGlobalUSD': 20.0,
            'BaseDistancePts': 200, 'LotMultiplier': 1.5, 'MaxMartingale': 8, 'MaxTotalOrders': 15,
            'UseATR': False, 'UseTrailingStop': False
        }),
        ("3. Canal de 150 Pontos e 4 Ordens (Modo Original Sem Filtro, Lote 0.02) [$100]", {
            'BalanceInit': 100.0, 'Mode': 'BOTH_OPEN', 'InitialLot': 0.02, 'TargetSideUSD': 2.0, 'TargetGlobalUSD': 20.0,
            'BaseDistancePts': 150, 'LotMultiplier': 1.5, 'MaxMartingale': 4, 'MaxTotalOrders': 4,
            'UseATR': False, 'UseTrailingStop': False
        }),
        ("4. Canal de 150 Pontos e 4 Ordens (Modo Original Sem Filtro, Lote 0.02) [$2.000]", {
            'BalanceInit': 2000.0, 'Mode': 'BOTH_OPEN', 'InitialLot': 0.02, 'TargetSideUSD': 2.0, 'TargetGlobalUSD': 20.0,
            'BaseDistancePts': 150, 'LotMultiplier': 1.5, 'MaxMartingale': 4, 'MaxTotalOrders': 4,
            'UseATR': False, 'UseTrailingStop': False
        }),
        ("5. Imagem 1: Apenas Compras / Buy-Only (Dist 300, Lote 0.01, Max 4, c/ Trailing) [$100]", {
            'BalanceInit': 100.0, 'Mode': 'BUY_ONLY', 'InitialLot': 0.01, 'TargetSideUSD': 3.0, 'TargetGlobalUSD': 15.0,
            'BaseDistancePts': 300, 'LotMultiplier': 1.2, 'MaxMartingale': 3, 'MaxTotalOrders': 4,
            'UseATR': True, 'ATRMultiplier': 1.5, 'UseTrailingStop': True, 'TrailingStartUSD': 5.0, 'TrailingDropPct': 10.0
        }),
        ("6. Imagem 1 c/ TP Fixo $3.00: Apenas Compras / Buy-Only (Dist 300, Lote 0.01, Max 4) [$100]", {
            'BalanceInit': 100.0, 'Mode': 'BUY_ONLY', 'InitialLot': 0.01, 'TargetSideUSD': 3.0, 'TargetGlobalUSD': 15.0,
            'BaseDistancePts': 300, 'LotMultiplier': 1.2, 'MaxMartingale': 3, 'MaxTotalOrders': 4,
            'UseATR': True, 'ATRMultiplier': 1.5, 'UseTrailingStop': False
        }),
        ("7. Imagem 2: Ambas Direções c/ EMA 200 (Dist 300, Lote 0.01, Max 4, c/ Trailing) [$100]", {
            'BalanceInit': 100.0, 'Mode': 'EMA_BOTH', 'InitialLot': 0.01, 'TargetSideUSD': 3.0, 'TargetGlobalUSD': 15.0,
            'BaseDistancePts': 300, 'LotMultiplier': 1.2, 'MaxMartingale': 3, 'MaxTotalOrders': 4,
            'UseATR': True, 'ATRMultiplier': 1.5, 'UseTrailingStop': True, 'TrailingStartUSD': 5.0, 'TrailingDropPct': 10.0
        }),
        ("8. Imagem 2 c/ Dist 600 e TP Fixo $3.00: Ambas Direções c/ EMA 200 [$100]", {
            'BalanceInit': 100.0, 'Mode': 'EMA_BOTH', 'InitialLot': 0.01, 'TargetSideUSD': 3.0, 'TargetGlobalUSD': 15.0,
            'BaseDistancePts': 600, 'LotMultiplier': 1.2, 'MaxMartingale': 3, 'MaxTotalOrders': 4,
            'UseATR': True, 'ATRMultiplier': 1.5, 'UseTrailingStop': False
        }),
    ]

    for title, cfg in suite:
        res = engine.run_with_rolling_ruin(cfg)
        print(f">>> {title}")
        print(f"    Saldo Final (Início Fev/24): ${res['FinalEquity']:>8.2f} (Lucro: ${res['NetProfitUSD']:>8.2f}) | Stop-Out Fev/24: {res['StopOut']} ({res['StopOutDate']})")
        print(f"    TAXA DE FALÊNCIA EM MESES ALEATÓRIOS (Risk of Ruin): {res['RollingMonthsBlown']}/{res['RollingMonthsTested']} meses ({res['RiskOfRuinPct']}%)")
        print(f"    Pior Rebaixamento Flutuante Real (MaxDD): -${res['MaxDD_USD']:.2f} ({res['MaxDD_Pct']:.2f}%) | Custos (Swap+Comm): ${res['SwapPaidUSD'] + res['CommPaidUSD']:.2f}")
        print(f"    Banca Mínima Realista p/ Não Quebrar no Pior Choque: ${res['MinRecommendedCapitalUSD']:,.2f}\n")
