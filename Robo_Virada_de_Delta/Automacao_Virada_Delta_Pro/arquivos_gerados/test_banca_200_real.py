"""
=============================================================================
AUDITORIA QUANTITATIVA FORENSE - PROTOCOLO SUNRISE & MT5 CAUSAL
Teste de Desempenho com Banca Real de $200.00 USD em Dados Reais do MT5
Ativos: GOLD (XAUUSD) e BTCUSD
Terminal: XM Global Limited (MetaTrader 5)
=============================================================================
"""

import sys
import os
import json
import numpy as np
import pandas as pd
import MetaTrader5 as mt5

def get_real_mt5_data(symbol, max_bars=40000):
    if not mt5.initialize():
        raise RuntimeError(f"Falha ao conectar no MetaTrader 5: {mt5.last_error()}")
    
    sym_info = mt5.symbol_info(symbol)
    if sym_info is None:
        raise ValueError(f"Símbolo {symbol} não encontrado no MT5.")
    
    mt5.symbol_select(symbol, True)
    
    rates = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_M5, 0, max_bars)
    if rates is None or len(rates) == 0:
        raise ValueError(f"Não foi possível obter dados para {symbol}.")
    
    df = pd.DataFrame(rates)
    df['time'] = pd.to_datetime(df['time'], unit='s')
    df.set_index('time', inplace=True)
    df.rename(columns={'open': 'Open', 'high': 'High', 'low': 'Low', 'close': 'Close', 'tick_volume': 'Volume'}, inplace=True)
    
    specs = {
        'symbol': symbol,
        'contract_size': sym_info.trade_contract_size,
        'digits': sym_info.digits,
        'point': sym_info.point,
        'tick_size': sym_info.trade_tick_size if sym_info.trade_tick_size > 0 else sym_info.point,
        'tick_value': sym_info.trade_tick_value,
        'spread_points': sym_info.spread,
        'spread_price': sym_info.spread * sym_info.point,
        'swap_long': sym_info.swap_long,
        'swap_short': sym_info.swap_short,
        'swap_3days': sym_info.swap_rollover3days,
        'min_lot': sym_info.volume_min,
        'lot_step': sym_info.volume_step,
        'leverage': 500.0 # Alavancagem da conta XM
    }
    
    return df, specs

def calculate_indicators(df):
    close = df['Close']
    high = df['High']
    low = df['Low']
    vol = df['Volume']
    
    # Médias Dragon e Tendência
    df['EMA_200'] = close.ewm(span=200, adjust=False).mean().shift(1)
    df['Dragon_Mid'] = close.ewm(span=34, adjust=False).mean().shift(1)
    df['Dragon_High'] = high.ewm(span=34, adjust=False).mean().shift(1)
    df['Dragon_Low'] = low.ewm(span=34, adjust=False).mean().shift(1)
    
    # ATR 14 Causal (shift 1)
    tr1 = high - low
    tr2 = (high - close.shift(1)).abs()
    tr3 = (low - close.shift(1)).abs()
    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    df['ATR'] = tr.rolling(14).mean().shift(1).bfill()
    
    # PVSRA (shift 1)
    vol_sma = vol.rolling(10).mean().shift(1)
    spread = high - low
    spread_vol = spread * vol
    spread_vol_max = spread_vol.rolling(10).max().shift(1)
    
    df['Climax'] = ((vol.shift(1) >= 2.0 * vol_sma) | (spread_vol.shift(1) >= spread_vol_max))
    df['Rising'] = ((vol.shift(1) >= 1.5 * vol_sma) & (~df['Climax']))
    
    # Deformação Elástica Delta_t no candle anterior fechado
    df['Delta_t'] = (close.shift(1) - df['Dragon_Mid']) / df['ATR']
    
    # Rejeição de pavio no candle anterior fechado
    c1 = close.shift(1)
    o1 = df['Open'].shift(1)
    h1 = high.shift(1)
    l1 = low.shift(1)
    body1 = (c1 - o1).abs()
    spread1 = h1 - l1
    
    df['Bear_Rejection'] = ((h1 - np.maximum(o1, c1)) >= 1.0 * body1) & (c1 < h1 - 0.4 * spread1)
    df['Bull_Rejection'] = ((np.minimum(o1, c1) - l1) >= 1.0 * body1) & (c1 > l1 + 0.4 * spread1)
    
    # Hurst rápido (40 barras, shift 1)
    log_rets = np.log(close / close.shift(1))
    r_max = log_rets.rolling(40).max()
    r_min = log_rets.rolling(40).min()
    r_std = log_rets.rolling(40).std()
    rs = (r_max - r_min) / (r_std + 1e-9)
    df['Hurst'] = (np.log(rs.clip(lower=1.1)) / np.log(40)).shift(1).fillna(0.50)
    
    # Rolling Volume Profile 24h (288 barras de M5)
    n = len(df)
    c_vals = close.values
    v_vals = vol.values
    poc_arr = np.zeros(n)
    vah_arr = np.zeros(n)
    val_arr = np.zeros(n)
    
    win = 288
    for i in range(win, n, 24):
        cw = c_vals[i-win:i]
        vw = v_vals[i-win:i]
        if vw.sum() == 0:
            vw = np.ones_like(cw)
        bins = np.linspace(cw.min(), cw.max(), 35)
        b_idx = np.digitize(cw, bins) - 1
        vol_bins = np.zeros(len(bins))
        for b, v in zip(b_idx, vw):
            if 0 <= b < len(bins):
                vol_bins[b] += v
        
        p_idx = np.argmax(vol_bins)
        last_poc = bins[p_idx]
        
        target_v = vol_bins.sum() * 0.70
        cum_v = vol_bins[p_idx]
        l_idx = p_idx
        h_idx = p_idx
        while cum_v < target_v and (l_idx > 0 or h_idx < len(bins)-1):
            va = vol_bins[h_idx+1] if h_idx+1 < len(bins) else 0
            vb = vol_bins[l_idx-1] if l_idx-1 >= 0 else 0
            if va >= vb and h_idx+1 < len(bins):
                h_idx += 1
                cum_v += va
            elif l_idx-1 >= 0:
                l_idx -= 1
                cum_v += vb
            else:
                break
        last_vah = bins[h_idx]
        last_val = bins[l_idx]
        
        end = min(i+24, n)
        poc_arr[i:end] = last_poc
        vah_arr[i:end] = last_vah
        val_arr[i:end] = last_val
    
    df['POC'] = pd.Series(poc_arr, index=df.index).shift(1).bfill()
    df['VAH'] = pd.Series(vah_arr, index=df.index).shift(1).bfill()
    df['VAL'] = pd.Series(val_arr, index=df.index).shift(1).bfill()
    
    return df.dropna()

def simulate_banca_200(df, specs, strategy_mode='hybrid', session_filter=False):
    initial_balance = 200.0
    balance = initial_balance
    equity = initial_balance
    peak_equity = initial_balance
    max_dd_usd = 0.0
    max_dd_pct = 0.0
    
    pos = None
    trades = []
    daily_start_equity = initial_balance
    current_day = None
    
    spread = specs['spread_price']
    slippage = specs['tick_size']
    commission_per_001 = 0.06 # $6 por lote padrão round turn -> $0.06 por 0.01 lot
    contract_size = specs['contract_size']
    leverage = specs['leverage']
    lot = 0.01 # Lote fixo 0.01
    
    dates = df.index
    opens = df['Open'].values
    highs = df['High'].values
    lows = df['Low'].values
    closes = df['Close'].values
    
    delta_ts = df['Delta_t'].values
    hursts = df['Hurst'].values
    climaxes = df['Climax'].values
    risings = df['Rising'].values
    bear_rejs = df['Bear_Rejection'].values
    bull_rejs = df['Bull_Rejection'].values
    atrs = df['ATR'].values
    pocs = df['POC'].values
    vahs = df['VAH'].values
    vals = df['VAL'].values
    ema200s = df['EMA_200'].values
    
    total_bars = len(df)
    
    for i in range(total_bars):
        t = dates[i]
        o = opens[i]
        h = highs[i]
        l = lows[i]
        c = closes[i]
        
        day = t.date()
        if day != current_day:
            daily_start_equity = equity
            current_day = day
        
        # 1. Gerenciar posição aberta existente
        if pos is not None:
            if t.hour == 0 and t.minute == 0:
                is_wednesday = (t.weekday() == 2)
                multiplier = 3 if is_wednesday else 1
                swap_rate = specs['swap_long'] if pos['type'] == 'BUY' else specs['swap_short']
                swap_cost = (swap_rate * lot * multiplier) / 100.0
                balance += swap_cost
            
            hit_sl = False
            hit_tp = False
            exit_price = 0.0
            
            if pos['type'] == 'BUY':
                margin_req = (pos['entry'] * contract_size * lot) / leverage
                adverse_p = l
                worst_loss = (adverse_p - pos['entry']) * contract_size * lot
                cur_floating_eq = balance + worst_loss
                margin_level = (cur_floating_eq / margin_req) * 100.0 if margin_req > 0 else 9999.0
                
                if margin_level <= 20.0 or cur_floating_eq <= 0:
                    exit_price = adverse_p
                    pnl = (exit_price - pos['entry']) * contract_size * lot - commission_per_001
                    balance += pnl
                    trades.append({'type': 'BUY', 'entry': pos['entry'], 'exit': exit_price, 'pnl': pnl, 'reason': 'STOP_OUT', 'entry_time': pos['time'], 'exit_time': t})
                    pos = None
                    equity = balance
                    break
                
                if l <= pos['sl']:
                    hit_sl = True
                    exit_price = pos['sl'] - slippage
                elif h >= pos['tp']:
                    hit_tp = True
                    exit_price = pos['tp'] - slippage
                
                if not hit_sl and not hit_tp:
                    if h >= pos['target_be_trigger'] and not pos['moved_be']:
                        pos['sl'] = pos['entry'] + spread
                        pos['moved_be'] = True
                
                if hit_sl or hit_tp:
                    pnl = (exit_price - pos['entry']) * contract_size * lot - commission_per_001
                    balance += pnl
                    reason = 'TAKE_PROFIT' if hit_tp else ('BREAKEVEN' if pos['moved_be'] and exit_price >= pos['entry'] else 'STOP_LOSS')
                    trades.append({'type': 'BUY', 'entry': pos['entry'], 'exit': exit_price, 'pnl': pnl, 'reason': reason, 'entry_time': pos['time'], 'exit_time': t})
                    pos = None
                    
            elif pos['type'] == 'SELL':
                margin_req = (pos['entry'] * contract_size * lot) / leverage
                adverse_p = h
                worst_loss = (pos['entry'] - adverse_p) * contract_size * lot
                cur_floating_eq = balance + worst_loss
                margin_level = (cur_floating_eq / margin_req) * 100.0 if margin_req > 0 else 9999.0
                
                if margin_level <= 20.0 or cur_floating_eq <= 0:
                    exit_price = adverse_p
                    pnl = (pos['entry'] - exit_price) * contract_size * lot - commission_per_001
                    balance += pnl
                    trades.append({'type': 'SELL', 'entry': pos['entry'], 'exit': exit_price, 'pnl': pnl, 'reason': 'STOP_OUT', 'entry_time': pos['time'], 'exit_time': t})
                    pos = None
                    equity = balance
                    break
                
                if h >= pos['sl']:
                    hit_sl = True
                    exit_price = pos['sl'] + slippage
                elif l <= pos['tp']:
                    hit_tp = True
                    exit_price = pos['tp'] + slippage
                
                if not hit_sl and not hit_tp:
                    if l <= pos['target_be_trigger'] and not pos['moved_be']:
                        pos['sl'] = pos['entry'] - spread
                        pos['moved_be'] = True
                        
                if hit_sl or hit_tp:
                    pnl = (pos['entry'] - exit_price) * contract_size * lot - commission_per_001
                    balance += pnl
                    reason = 'TAKE_PROFIT' if hit_tp else ('BREAKEVEN' if pos['moved_be'] and exit_price <= pos['entry'] else 'STOP_LOSS')
                    trades.append({'type': 'SELL', 'entry': pos['entry'], 'exit': exit_price, 'pnl': pnl, 'reason': reason, 'entry_time': pos['time'], 'exit_time': t})
                    pos = None
        
        if pos is not None:
            floating_pnl = ((c - pos['entry']) if pos['type'] == 'BUY' else (pos['entry'] - c)) * contract_size * lot
            equity = balance + floating_pnl
        else:
            equity = balance
            
        if equity > peak_equity:
            peak_equity = equity
        dd_usd = peak_equity - equity
        dd_pct = (dd_usd / peak_equity) * 100.0 if peak_equity > 0 else 0.0
        if dd_usd > max_dd_usd: max_dd_usd = dd_usd
        if dd_pct > max_dd_pct: max_dd_pct = dd_pct
        
        if equity <= 0:
            break
            
        # 2. Novas entradas
        if pos is None:
            daily_dd = (daily_start_equity - equity) / daily_start_equity * 100.0
            if daily_dd >= 3.5:
                continue
                
            if session_filter:
                cur_min = t.hour * 60 + t.minute
                if not (810 <= cur_min <= 1200):
                    continue
            
            d_t = delta_ts[i]
            hurst = hursts[i]
            climax = climaxes[i]
            rising = risings[i]
            bear_rej = bear_rejs[i]
            bull_rej = bull_rejs[i]
            atr = atrs[i]
            poc = pocs[i]
            vah = vahs[i]
            val = vals[i]
            ema200 = ema200s[i]
            
            c1 = df['Close'].iloc[i-1] if i > 0 else o
            h1 = df['High'].iloc[i-1] if i > 0 else h
            l1 = df['Low'].iloc[i-1] if i > 0 else l
            
            if strategy_mode in ['hybrid', 'reversal']:
                if d_t >= 2.0 and (climax or rising or c1 >= vah) and bear_rej and hurst <= 0.57:
                    if c1 <= ema200 or d_t >= 2.3 or climax:
                        entry_price = o - spread/2.0 - slippage
                        sl_price = h1 + (0.25 * atr)
                        dist_sl = sl_price - entry_price
                        target_barrier = poc if poc < entry_price else (entry_price - 1.5 * dist_sl)
                        tp_price = entry_price - 0.80 * (entry_price - target_barrier)
                        
                        headroom = (entry_price - target_barrier) / (dist_sl + 1e-9)
                        if headroom >= 1.5 and dist_sl > 0:
                            pos = {
                                'type': 'SELL',
                                'entry': entry_price,
                                'sl': sl_price,
                                'tp': tp_price,
                                'target_be_trigger': entry_price - 0.50 * (entry_price - tp_price),
                                'moved_be': False,
                                'time': t
                            }
                            continue
                            
                if d_t <= -2.0 and (climax or rising or c1 <= val) and bull_rej and hurst <= 0.57:
                    if c1 >= ema200 or d_t <= -2.3 or climax:
                        entry_price = o + spread/2.0 + slippage
                        sl_price = l1 - (0.25 * atr)
                        dist_sl = entry_price - sl_price
                        target_barrier = poc if poc > entry_price else (entry_price + 1.5 * dist_sl)
                        tp_price = entry_price + 0.80 * (target_barrier - entry_price)
                        
                        headroom = (target_barrier - entry_price) / (dist_sl + 1e-9)
                        if headroom >= 1.5 and dist_sl > 0:
                            pos = {
                                'type': 'BUY',
                                'entry': entry_price,
                                'sl': sl_price,
                                'tp': tp_price,
                                'target_be_trigger': entry_price + 0.50 * (tp_price - entry_price),
                                'moved_be': False,
                                'time': t
                            }
                            continue
            
            if strategy_mode in ['hybrid', 'bos']:
                if c1 > ema200 and l1 <= vah and c1 > vah and hurst > 0.57:
                    entry_price = o + spread/2.0 + slippage
                    sl_price = vah - (0.80 * atr)
                    dist_sl = entry_price - sl_price
                    if dist_sl > 0:
                        tp_price = entry_price + 1.6 * dist_sl
                        pos = {
                            'type': 'BUY',
                            'entry': entry_price,
                            'sl': sl_price,
                            'tp': tp_price,
                            'target_be_trigger': entry_price + 0.50 * (tp_price - entry_price),
                            'moved_be': False,
                            'time': t
                        }
                        continue
                        
                if c1 < ema200 and h1 >= val and c1 < val and hurst > 0.57:
                    entry_price = o - spread/2.0 - slippage
                    sl_price = val + (0.80 * atr)
                    dist_sl = sl_price - entry_price
                    if dist_sl > 0:
                        tp_price = entry_price - 1.6 * dist_sl
                        pos = {
                            'type': 'SELL',
                            'entry': entry_price,
                            'sl': sl_price,
                            'tp': tp_price,
                            'target_be_trigger': entry_price - 0.50 * (entry_price - tp_price),
                            'moved_be': False,
                            'time': t
                        }
                        continue

    df_trades = pd.DataFrame(trades)
    total_trades = len(df_trades)
    if total_trades > 0:
        wins = df_trades[df_trades['pnl'] > 0]
        losses = df_trades[df_trades['pnl'] < 0]
        win_rate = (len(wins) / total_trades) * 100.0
        gross_profit = wins['pnl'].sum() if len(wins) > 0 else 0.0
        gross_loss = abs(losses['pnl'].sum()) if len(losses) > 0 else 0.0
        net_profit = df_trades['pnl'].sum()
        profit_factor = (gross_profit / gross_loss) if gross_loss > 0 else 99.0
        stop_outs = len(df_trades[df_trades['reason'] == 'STOP_OUT'])
        breakevens = len(df_trades[df_trades['reason'] == 'BREAKEVEN'])
    else:
        win_rate = 0.0
        gross_profit = 0.0
        gross_loss = 0.0
        net_profit = 0.0
        profit_factor = 0.0
        stop_outs = 0
        breakevens = 0
        
    return {
        'initial_balance': initial_balance,
        'final_balance': round(balance, 2),
        'net_profit_usd': round(balance - initial_balance, 2),
        'net_profit_pct': round(((balance - initial_balance) / initial_balance) * 100.0, 2),
        'max_dd_usd': round(max_dd_usd, 2),
        'max_dd_pct': round(max_dd_pct, 2),
        'total_trades': total_trades,
        'win_rate': round(win_rate, 2),
        'profit_factor': round(profit_factor, 2),
        'stop_outs': stop_outs,
        'breakevens': breakevens,
        'survived': balance > 0 and stop_outs == 0
    }

def run_rolling_stress_test(df, specs, strategy_mode='hybrid', session_filter=False):
    df_months = df.resample('MS').first()
    month_starts = df_months.index
    
    monthly_results = []
    
    for start_date in month_starts:
        sub_df = df.loc[start_date:]
        if len(sub_df) < 288 * 10:
            continue
        res = simulate_banca_200(sub_df, specs, strategy_mode=strategy_mode, session_filter=session_filter)
        res['start_date'] = str(start_date.date())
        monthly_results.append(res)
        
    df_res = pd.DataFrame(monthly_results)
    total_runs = len(df_res)
    ruined_runs = len(df_res[~df_res['survived']])
    risk_of_ruin = (ruined_runs / total_runs * 100.0) if total_runs > 0 else 0.0
    
    avg_profit = df_res['net_profit_usd'].mean() if total_runs > 0 else 0.0
    max_dd = df_res['max_dd_usd'].max() if total_runs > 0 else 0.0
    
    return {
        'total_monthly_starts': total_runs,
        'ruined_starts': ruined_runs,
        'risk_of_ruin_pct': round(risk_of_ruin, 2),
        'avg_profit_usd': round(avg_profit, 2),
        'worst_dd_usd': round(max_dd, 2),
        'monthly_details': monthly_results
    }

if __name__ == '__main__':
    print("Iniciando auditoria quantitativa em dados reais do MT5 para banca de $200.00...")
    
    # 1. GOLD (XAUUSD)
    print("\n=======================================================")
    print("1. CARREGANDO DADOS REAIS DE GOLD (XAUUSD) DO TERMINAL")
    print("=======================================================")
    df_gold, specs_gold = get_real_mt5_data('GOLD', max_bars=45000)
    print(f"Barras carregadas: {len(df_gold)} M5 barras de {df_gold.index[0]} ate {df_gold.index[-1]}")
    print(f"Spread: {specs_gold['spread_points']} pts (${specs_gold['spread_price']:.2f}) | Contrato: {specs_gold['contract_size']} oz")
    
    df_gold_ind = calculate_indicators(df_gold)
    
    gold_full_res = simulate_banca_200(df_gold_ind, specs_gold, strategy_mode='hybrid')
    print("Resultado Global GOLD ($200):", json.dumps(gold_full_res, indent=2))
    
    gold_ruin_test = run_rolling_stress_test(df_gold_ind, specs_gold, strategy_mode='hybrid')
    print("Stress Test GOLD (Risco de Ruina):", json.dumps(gold_ruin_test, indent=2))
    
    # 2. BTCUSD (Bitcoin)
    print("\n=======================================================")
    print("2. CARREGANDO DADOS REAIS DE BTCUSD DO TERMINAL")
    print("=======================================================")
    df_btc, specs_btc = get_real_mt5_data('BTCUSD', max_bars=45000)
    print(f"Barras carregadas: {len(df_btc)} M5 barras de {df_btc.index[0]} ate {df_btc.index[-1]}")
    print(f"Spread: {specs_btc['spread_points']} pts (${specs_btc['spread_price']:.2f}) | Contrato: {specs_btc['contract_size']} BTC")
    
    df_btc_ind = calculate_indicators(df_btc)
    
    btc_full_res = simulate_banca_200(df_btc_ind, specs_btc, strategy_mode='hybrid')
    print("Resultado Global BTCUSD ($200):", json.dumps(btc_full_res, indent=2))
    
    btc_ruin_test = run_rolling_stress_test(df_btc_ind, specs_btc, strategy_mode='hybrid')
    print("Stress Test BTCUSD (Risco de Ruina):", json.dumps(btc_ruin_test, indent=2))
    
    out_file = r'c:\Robo Virada de Delta\Automacao_Virada_Delta\testes_estrategia\resultado_banca_200_real.json'
    with open(out_file, 'w', encoding='utf-8') as f:
        json.dump({
            'GOLD_FULL': gold_full_res,
            'GOLD_STRESS': gold_ruin_test,
            'BTC_FULL': btc_full_res,
            'BTC_STRESS': btc_ruin_test,
            'SPECS_GOLD': specs_gold,
            'SPECS_BTC': specs_btc
        }, f, indent=2, default=str)
    print(f"\nResultados salvos com sucesso em: {out_file}")
    
    mt5.shutdown()
