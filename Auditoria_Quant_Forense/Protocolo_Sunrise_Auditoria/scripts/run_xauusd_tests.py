import datetime
import numpy as np
import pandas as pd
import MetaTrader5 as mt5

def get_xauusd_data():
    if not mt5.initialize(path='C:/MetaTrader/terminal64.exe'):
        raise RuntimeError(f"MT5 initialize failed: {mt5.last_error()}")
    
    symbol = 'XAUUSD-ECN'
    mt5.symbol_select(symbol, True)
    
    # 2+ anos de dados (de 01/01/2024 até hoje)
    utc_from = datetime.datetime(2024, 1, 1)
    utc_to = datetime.datetime(2026, 10, 19, 23, 59)
    
    rates = mt5.copy_rates_range(symbol, mt5.TIMEFRAME_M15, utc_from, utc_to)
    mt5.shutdown()
    
    if rates is None or len(rates) == 0:
        raise RuntimeError("No rates returned from MT5")
        
    df = pd.DataFrame(rates)
    df['time'] = pd.to_datetime(df['time'], unit='s')
    
    # Calcula ATR(14)
    high_low = df['high'] - df['low']
    high_close = (df['high'] - df['close'].shift()).abs()
    low_close = (df['low'] - df['close'].shift()).abs()
    tr = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
    df['atr'] = tr.rolling(window=14).mean()
    df['atr'] = df['atr'].bfill()
    
    return df

class BacktestEngine:
    def __init__(self, df, initial_balance=2000.0, spread_usd=0.20):
        self.df = df
        self.initial_balance = initial_balance
        self.spread = spread_usd # $0.20 de spread típico no XAUUSD
        self.point = 0.01
        self.contract_size = 100.0

    def run(self, params):
        initial_lot     = params.get('InitialLot', 0.02)
        target_side     = params.get('TargetSideUSD', 2.00)
        target_global   = params.get('TargetGlobalUSD', 20.00)
        base_distance   = params.get('BaseDistance', 600) * self.point # em dólares de cotação
        lot_multiplier  = params.get('LotMultiplier', 1.5)
        max_martingale  = params.get('MaxMartingale', 8)
        max_orders      = params.get('MaxTotalOrders', 15)
        use_atr         = params.get('UseATR', True)
        atr_mult        = params.get('ATRMultiplier', 1.5)
        use_trailing    = params.get('UseTrailingStop', True)
        trailing_start  = params.get('TrailingStartUSD', 5.00)
        trailing_drop   = params.get('TrailingDropPct', 10.0) / 100.0

        balance = self.initial_balance
        peak_equity = balance
        max_dd_usd = 0.0
        max_dd_pct = 0.0

        buy_positions = []  # dict: {price, volume, time}
        sell_positions = []

        max_buy_profit = 0.0
        max_sell_profit = 0.0
        max_global_profit = 0.0

        total_trades = 0
        winning_trades = 0
        recycled_orders = 0

        # Normalizador de lote MT5 para Ouro (min 0.01, step 0.01)
        def norm_lot(vol):
            return max(0.01, round(vol, 2))

        # Loop barra a barra (M15)
        for row in self.df.itertuples():
            o, h, l, c = row.open, row.high, row.low, row.close
            atr = row.atr
            
            # Distância dinâmica
            if use_atr:
                dyn_dist = max(base_distance / 2.0, atr * atr_mult)
            else:
                dyn_dist = base_distance

            # Simulação intrabar (Open -> Low -> High -> Close se verde; Open -> High -> Low -> Close se vermelho)
            if c >= o:
                price_steps = [o, l, h, c]
            else:
                price_steps = [o, h, l, c]

            for price in price_steps:
                ask = price + (self.spread / 2.0)
                bid = price - (self.spread / 2.0)

                # 1. Scanner de lucros
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

                # 2. Reset Global / Fechamento Global
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

                # 3. Reciclagem Ativa
                if buy_profit >= target_side and len(sell_positions) > 0:
                    # Encontra a melhor ordem perdedora de venda coberta pelo lucro
                    best_cand_idx = -1
                    best_cand_loss = 0.0
                    for idx, sp in enumerate(sell_positions):
                        p_loss = (sp['price'] - ask) * sp['volume'] * self.contract_size
                        if p_loss < 0 and buy_profit >= abs(p_loss):
                            if best_cand_idx == -1 or abs(p_loss) > abs(best_cand_loss):
                                best_cand_idx = idx
                                best_cand_loss = p_loss
                    if best_cand_idx != -1:
                        # Fecha a ordem de venda perdedora e todo o lado de compra
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

                # 4. Fechamento de Lado / Trailing Stop Individual
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

                # 5. Motor de Giro (Abertura quando zerado)
                if len(buy_positions) == 0:
                    buy_positions.append({'price': ask, 'volume': norm_lot(initial_lot)})
                if len(sell_positions) == 0:
                    sell_positions.append({'price': bid, 'volume': norm_lot(initial_lot)})

                # 6. Grade Controlada (Martingale com Limite)
                if len(buy_positions) > 0 and len(buy_positions) < max_orders:
                    lowest_buy = min(p['price'] for p in buy_positions)
                    if ask < (lowest_buy - dyn_dist):
                        last_vol = [p['volume'] for p in buy_positions if p['price'] == lowest_buy][0]
                        if len(buy_positions) < max_martingale:
                            next_lot = norm_lot(last_vol * lot_multiplier)
                        else:
                            next_lot = last_vol
                        buy_positions.append({'price': ask, 'volume': next_lot})

                if len(sell_positions) > 0 and len(sell_positions) < max_orders:
                    highest_sell = max(p['price'] for p in sell_positions)
                    if bid > (highest_sell + dyn_dist):
                        last_vol = [p['volume'] for p in sell_positions if p['price'] == highest_sell][0]
                        if len(sell_positions) < max_martingale:
                            next_lot = norm_lot(last_vol * lot_multiplier)
                        else:
                            next_lot = last_vol
                        sell_positions.append({'price': bid, 'volume': next_lot})

        # Fechamento final de posições abertas no último candle
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
            'RecoveryFactor': round(total_profit_usd / max_dd_usd, 2) if max_dd_usd > 0 else 999.0
        }

if __name__ == '__main__':
    print("Obtendo dados históricos do XAUUSD-ECN via MT5...")
    df = get_xauusd_data()
    print(f"Dados carregados: {len(df)} barras de {df['time'].iloc[0].date()} a {df['time'].iloc[-1].date()}")
    
    engine = BacktestEngine(df, initial_balance=2000.0)
    
    # 1. Teste da Configuração Padrão Original
    cfg_padrao = {
        'InitialLot': 0.02,
        'TargetSideUSD': 2.00,
        'TargetGlobalUSD': 20.00,
        'BaseDistance': 600,
        'LotMultiplier': 1.5,
        'MaxMartingale': 8,
        'MaxTotalOrders': 15,
        'UseATR': True,
        'ATRMultiplier': 1.5,
        'UseTrailingStop': True,
        'TrailingStartUSD': 5.00,
        'TrailingDropPct': 10.0
    }
    
    res_padrao = engine.run(cfg_padrao)
    print("\n=== RESULTADO CONFIGURAÇÃO PADRÃO (V39/V40 Original) ===")
    print(res_padrao)

    # 2. Grade de Otimização para Ouro (XAUUSD)
    # No ouro, testamos espaçamentos adaptados à sua volatilidade real:
    # Distâncias de 500, 600, 800, 1000, 1200 pontos ($5 a $12)
    # Alvos de giro de $2.00, $3.00, $4.00, $5.00
    # Multiplicador de Martingale: 1.3, 1.4, 1.5
    # Alvo Global: $20, $30, $50
    test_grid = [
        # Variações de Distância Base
        {'name': 'Dist 800 / Mult 1.4 / Alvo $3', 'BaseDistance': 800, 'LotMultiplier': 1.4, 'TargetSideUSD': 3.0, 'TargetGlobalUSD': 30.0, 'ATRMultiplier': 1.8},
        {'name': 'Dist 1000 / Mult 1.4 / Alvo $4', 'BaseDistance': 1000, 'LotMultiplier': 1.4, 'TargetSideUSD': 4.0, 'TargetGlobalUSD': 35.0, 'ATRMultiplier': 2.0},
        {'name': 'Dist 600 / Mult 1.35 / Alvo $2.5', 'BaseDistance': 600, 'LotMultiplier': 1.35, 'TargetSideUSD': 2.5, 'TargetGlobalUSD': 25.0, 'ATRMultiplier': 1.5},
        {'name': 'Dist 1200 / Mult 1.5 / Alvo $5 (Ultra Seguro)', 'BaseDistance': 1200, 'LotMultiplier': 1.5, 'TargetSideUSD': 5.0, 'TargetGlobalUSD': 50.0, 'ATRMultiplier': 2.2},
        {'name': 'Dist 500 / Mult 1.3 / Alvo $2 (Scalp Rápido)', 'BaseDistance': 500, 'LotMultiplier': 1.3, 'TargetSideUSD': 2.0, 'TargetGlobalUSD': 20.0, 'ATRMultiplier': 1.3},
        {'name': 'Dist 700 / Mult 1.45 / Alvo $3.5 (Equilibrado)', 'BaseDistance': 700, 'LotMultiplier': 1.45, 'TargetSideUSD': 3.5, 'TargetGlobalUSD': 30.0, 'ATRMultiplier': 1.6},
        {'name': 'Dist 850 / Mult 1.38 / Alvo $4 (Alto Rendimento)', 'BaseDistance': 850, 'LotMultiplier': 1.38, 'TargetSideUSD': 4.0, 'TargetGlobalUSD': 40.0, 'ATRMultiplier': 1.8},
        {'name': 'Dist 600 / Mult 1.5 / Sem Trailing (TP Fixo $3)', 'BaseDistance': 600, 'LotMultiplier': 1.5, 'TargetSideUSD': 3.0, 'TargetGlobalUSD': 25.0, 'UseTrailingStop': False},
        {'name': 'Dist 750 / Mult 1.4 / Trailing Drop 15%', 'BaseDistance': 750, 'LotMultiplier': 1.4, 'TargetSideUSD': 3.0, 'TrailingDropPct': 15.0, 'TargetGlobalUSD': 30.0},
    ]

    print("\n=== EXECUTANDO OTIMIZAÇÃO (PERÍODO: FEV/2024 A OUT/2026 - 2.6 ANOS) ===")
    results = []
    for test in test_grid:
        cfg = cfg_padrao.copy()
        cfg.update(test)
        name = cfg.pop('name')
        res = engine.run(cfg)
        res['Name'] = name
        res['BaseDist'] = cfg['BaseDistance']
        res['Mult'] = cfg['LotMultiplier']
        res['TargetSide'] = cfg['TargetSideUSD']
        res['TargetGlobal'] = cfg['TargetGlobalUSD']
        results.append(res)
        print(f"[{name}] Lucro: ${res['ProfitUSD']} ({res['ProfitPct']}%) | MaxDD: {res['MaxDD_Pct']}% (${res['MaxDD_USD']}) | Fator Rec: {res['RecoveryFactor']} | Reciclagens: {res['Recycled']}")

    df_res = pd.DataFrame(results)
    df_res = df_res.sort_values(by='ProfitPct', ascending=False)
    print("\n=== RANKING DE LUCRATIVIDADE NO XAUUSD (2.6 ANOS) ===")
    print(df_res[['Name', 'ProfitUSD', 'ProfitPct', 'MaxDD_Pct', 'RecoveryFactor', 'Recycled']].to_string(index=False))
