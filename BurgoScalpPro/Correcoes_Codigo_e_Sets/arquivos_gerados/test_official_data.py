import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from datetime import datetime

def run_multiyear_analysis():
    mt5.initialize(path='C:\\MetaTrader\\terminal64.exe')
    symbol = 'XAUUSD-ECN'
    
    print("=" * 90)
    print("TESTE DE DADOS OFICIAIS DA CORRETORA (VT MARKETS) - 2024 A 2026")
    print(f"Ativo: {symbol} | Histórico Real Completo do Servidor")
    print("=" * 90)
    
    # 1. Carregar Histórico Real Máximo Disponível no Servidor
    # No M15 temos mais de 62.000 barras (desde Fev/2024 = ~2.7 anos)
    # No M5 e M1 vamos carregar a profundidade máxima oficial
    tfs = [
        ('15 Minutos (M15)', mt5.TIMEFRAME_M15, 62000),
        ('5 Minutos (M5)', mt5.TIMEFRAME_M5, 50000),
        ('1 Minuto (M1)', mt5.TIMEFRAME_M1, 50000)
    ]
    
    results = []
    
    for tf_name, tf_const, n_bars in tfs:
        print(f"\nCarregando histórico oficial de {n_bars} barras para {tf_name}...")
        dt = datetime(2026, 10, 14)
        rates = mt5.copy_rates_from(symbol, tf_const, dt, n_bars)
        if rates is None or len(rates) == 0:
            print(f"Erro ao obter dados: {mt5.last_error()}")
            continue
            
        df = pd.DataFrame(rates)
        start_dt = datetime.fromtimestamp(df['time'].iloc[0])
        end_dt = datetime.fromtimestamp(df['time'].iloc[-1])
        days = (end_dt - start_dt).days
        years = round(days / 365.25, 2)
        print(f"-> Dados carregados: {len(df)} barras")
        print(f"-> Período: {start_dt.strftime('%d/%m/%Y')} até {end_dt.strftime('%d/%m/%Y')} ({days} dias / ~{years} anos)")
        
        # Calcular EMA 200 no timeframe para filtro de tendência
        df['ema200'] = df['close'].ewm(span=200, adjust=False).mean()
        
        # Calcular ATR 14
        high = df['high'].values
        low = df['low'].values
        close = df['close'].values
        tr = np.zeros(len(df))
        tr[0] = high[0] - low[0]
        for i in range(1, len(df)):
            tr[i] = max(high[i] - low[i], abs(high[i] - close[i-1]), abs(low[i] - close[i-1]))
        df['atr14'] = pd.Series(tr).rolling(14).mean().fillna(1.0).values
        
        # Simulações:
        # Modo 1: V39 Sem Controle de Drawdown (Padrão: Grade 15 ordens, mult 1.5, sem trava de perda, sem filtro)
        # Modo 2: V39 COM Controle Ativo de Drawdown:
        #         - Trava Máxima de Drawdown: Fecha tudo se perda flutuante atingir 10% da conta ($1000)
        #         - Filtro de Tendência EMA 200: Só compra acima da média, só vende abaixo da média
        #         - Espaçamento progressivo de grade (distância aumenta 20% a cada nível)
        #         - Limite seguro de ordens: Máx 6 ordens, mult 1.2x
        
        for modo in ['Sem Controle (Original)', 'Com Controle Ativo de Drawdown']:
            res = simulate(df, modo, initial_balance=10000.0, tf_name=tf_name)
            res['timeframe'] = tf_name
            res['years'] = years
            res['bars'] = len(df)
            results.append(res)
            
            print(f"[{modo}] Lucro: ${res['net_profit']} ({res['profit_pct']}%) | DD Máx: ${res['max_dd_usd']} ({res['max_dd_pct']}%) | Cesta Máx: {res['max_orders']} ordens | Trades: {res['total_trades']}")
            
    mt5.shutdown()
    
    res_df = pd.DataFrame(results)
    res_df.to_csv("resultado_oficial_2_a_3_anos.csv", index=False)
    print("\n" + "=" * 90)
    print("RELATÓRIO COMPARATIVO CONSOLIDADO - 2 A 3 ANOS DE DADOS OFICIAIS")
    print("=" * 90)
    cols = ['timeframe', 'years', 'modo', 'net_profit', 'profit_pct', 'max_dd_usd', 'max_dd_pct', 'max_orders', 'total_trades', 'win_rate']
    print(res_df[cols].to_string())

def simulate(df, modo, initial_balance=10000.0, tf_name=""):
    balance = initial_balance
    equity = initial_balance
    peak_equity = initial_balance
    max_dd_usd = 0.0
    max_dd_pct = 0.0
    
    positions = []
    ticket_seq = 1
    trades = []
    max_orders_seen = 0
    
    # Parâmetros conforme modo
    if modo == 'Sem Controle (Original)':
        use_trend_filter = False
        use_max_dd_stop = False
        max_dd_limit_usd = 999999
        max_allowed_orders = 15
        lot_mult = 1.5
        base_dist = 6.00 # 600 pts
        progressive_spacing = False
    else: # Com Controle Ativo de Drawdown
        use_trend_filter = True
        use_max_dd_stop = True
        max_dd_limit_usd = 1000.0 # Trava dura: Drawdown máximo de 10% da banca inicial
        max_allowed_orders = 6    # Limite rigoroso de cesta
        lot_mult = 1.25           # Multiplicador suave
        base_dist = 12.00         # 1200 pts de distância base no ouro ($12)
        progressive_spacing = True
        
    contract_size = 100.0
    target_side = 3.00 if modo != 'Sem Controle (Original)' else 2.00
    
    for idx in range(200, len(df)):
        row = df.iloc[idx]
        o, h, l, c = row['open'], row['high'], row['low'], row['close']
        atr = row['atr14']
        ema = row['ema200']
        spread = max(row['spread'] * 0.01, 0.15)
        
        # Sequência intra-barra
        sub_ticks = [o, l, h, c] if c >= o else [o, h, l, c]
        
        for price in sub_ticks:
            ask = price + spread / 2.0
            bid = price - spread / 2.0
            
            buys = [p for p in positions if p['type'] == 'BUY']
            sells = [p for p in positions if p['type'] == 'SELL']
            
            buy_pnl = sum((bid - p['price']) * p['lot'] * contract_size for p in buys)
            sell_pnl = sum((p['price'] - ask) * p['lot'] * contract_size for p in sells)
            total_floating = buy_pnl + sell_pnl
            
            equity = balance + total_floating
            if equity > peak_equity:
                peak_equity = equity
            dd = peak_equity - equity
            dd_pct = (dd / peak_equity * 100.0) if peak_equity > 0 else 0
            if dd > max_dd_usd:
                max_dd_usd = dd
            if dd_pct > max_dd_pct:
                max_dd_pct = dd_pct
                
            if len(positions) > max_orders_seen:
                max_orders_seen = len(positions)
                
            # 1. TRAVA DE DRAWDOWN MÁXIMO (CIRCUIT BREAKER)
            if use_max_dd_stop and total_floating <= -max_dd_limit_usd:
                # Estanca o prejuízo imediatamente, preservando 90% da conta!
                balance += total_floating
                for p in positions:
                    pnl = (bid - p['price']) * p['lot'] * contract_size if p['type'] == 'BUY' else (p['price'] - ask) * p['lot'] * contract_size
                    trades.append({'pnl': pnl})
                positions = []
                continue
                
            # 2. Reciclagem ativa
            if buy_pnl >= target_side and len(sells) > 0:
                # Encontra perda viável
                best_s = None
                best_loss = 0
                for sp in sells:
                    p = (sp['price'] - ask) * sp['lot'] * contract_size
                    if p < 0 and buy_pnl > abs(p):
                        if best_s is None or abs(p) > abs(best_loss):
                            best_s = sp
                            best_loss = p
                if best_s is not None:
                    balance += buy_pnl + best_loss
                    trades.append({'pnl': best_loss})
                    for bp in buys:
                        trades.append({'pnl': (bid - bp['price']) * bp['lot'] * contract_size})
                    positions = [p for p in positions if p['ticket'] != best_s['ticket'] and p['type'] != 'BUY']
                    continue
                    
            if sell_pnl >= target_side and len(buys) > 0:
                best_b = None
                best_loss = 0
                for bp in buys:
                    p = (bid - bp['price']) * bp['lot'] * contract_size
                    if p < 0 and sell_pnl > abs(p):
                        if best_b is None or abs(p) > abs(best_loss):
                            best_b = bp
                            best_loss = p
                if best_b is not None:
                    balance += sell_pnl + best_loss
                    trades.append({'pnl': best_loss})
                    for sp in sells:
                        trades.append({'pnl': (sp['price'] - ask) * sp['lot'] * contract_size})
                    positions = [p for p in positions if p['ticket'] != best_b['ticket'] and p['type'] != 'SELL']
                    continue
                    
            # 3. Take profit / Fechamento de lado lucrativo
            buys = [p for p in positions if p['type'] == 'BUY']
            sells = [p for p in positions if p['type'] == 'SELL']
            buy_pnl = sum((bid - p['price']) * p['lot'] * contract_size for p in buys)
            sell_pnl = sum((p['price'] - ask) * p['lot'] * contract_size for p in sells)
            
            if buy_pnl >= target_side:
                balance += buy_pnl
                for bp in buys:
                    trades.append({'pnl': (bid - bp['price']) * bp['lot'] * contract_size})
                positions = [p for p in positions if p['type'] != 'BUY']
                
            if sell_pnl >= target_side:
                balance += sell_pnl
                for sp in sells:
                    trades.append({'pnl': (sp['price'] - ask) * sp['lot'] * contract_size})
                positions = [p for p in positions if p['type'] != 'SELL']

            # 4. Abertura de Giros Iniciais (Respeitando Filtro de Tendência)
            buys = [p for p in positions if p['type'] == 'BUY']
            sells = [p for p in positions if p['type'] == 'SELL']
            
            can_buy = True
            can_sell = True
            if use_trend_filter:
                # Se preço acima da EMA 200: só compra
                # Se preço abaixo da EMA 200: só vende
                if price < ema:
                    can_buy = False
                if price > ema:
                    can_sell = False
                    
            if len(buys) == 0 and can_buy:
                positions.append({'type': 'BUY', 'lot': 0.02, 'price': ask, 'ticket': ticket_seq})
                ticket_seq += 1
                
            if len(sells) == 0 and can_sell:
                positions.append({'type': 'SELL', 'lot': 0.02, 'price': bid, 'ticket': ticket_seq})
                ticket_seq += 1
                
            # 5. Grade (Martingale com Controle de Distância e Cesta)
            buys = [p for p in positions if p['type'] == 'BUY']
            sells = [p for p in positions if p['type'] == 'SELL']
            
            # Distância base
            cur_dist = max(base_dist, atr * 1.5)
            
            if len(buys) > 0 and len(buys) < max_allowed_orders:
                lowest_buy = min(buys, key=lambda x: x['price'])
                req_dist = cur_dist * (1.0 + len(buys) * 0.20) if progressive_spacing else cur_dist
                if ask < (lowest_buy['price'] - req_dist):
                    last_lot = lowest_buy['lot']
                    next_lot = round(last_lot * lot_mult, 2)
                    positions.append({'type': 'BUY', 'lot': next_lot, 'price': ask, 'ticket': ticket_seq})
                    ticket_seq += 1
                    
            if len(sells) > 0 and len(sells) < max_allowed_orders:
                highest_sell = max(sells, key=lambda x: x['price'])
                req_dist = cur_dist * (1.0 + len(sells) * 0.20) if progressive_spacing else cur_dist
                if bid > (highest_sell['price'] + req_dist):
                    last_lot = highest_sell['lot']
                    next_lot = round(last_lot * lot_mult, 2)
                    positions.append({'type': 'SELL', 'lot': next_lot, 'price': bid, 'ticket': ticket_seq})
                    ticket_seq += 1

    # Fechar posições restantes
    for p in positions:
        pnl = (c - p['price']) * p['lot'] * contract_size if p['type'] == 'BUY' else (p['price'] - c) * p['lot'] * contract_size
        balance += pnl
        trades.append({'pnl': pnl})
        
    tot_trades = len(trades)
    wins = sum(1 for t in trades if t['pnl'] > 0)
    win_rate = round(wins / tot_trades * 100.0, 2) if tot_trades > 0 else 0.0
    net_profit = round(balance - initial_balance, 2)
    profit_pct = round((net_profit / initial_balance) * 100.0, 2)
    
    return {
        'modo': modo,
        'final_balance': round(balance, 2),
        'net_profit': net_profit,
        'profit_pct': profit_pct,
        'max_dd_usd': round(max_dd_usd, 2),
        'max_dd_pct': round(max_dd_pct, 2),
        'total_trades': tot_trades,
        'win_rate': win_rate,
        'max_orders': max_orders_seen
    }

if __name__ == '__main__':
    run_multiyear_analysis()
