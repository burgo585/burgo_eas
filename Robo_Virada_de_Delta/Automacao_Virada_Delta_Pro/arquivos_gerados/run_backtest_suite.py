import yfinance as yf
import pandas as pd
import numpy as np
import os
import json

def fetch_data(symbol, ticker, period='60d', interval='5m'):
    print(f"Baixando dados para {symbol} ({ticker})...")
    df = yf.download(ticker, period=period, interval=interval, progress=False)
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = [col[0] for col in df.columns]
    df = df.dropna()
    print(f"{symbol}: {len(df)} barras carregadas.")
    return df

def calculate_hurst(series, lags=[5, 10, 20]):
    """Calcula expoente de Hurst simplificado e rapido via Variância dos Incrementos"""
    tau = []
    lagvec = []
    for lag in lags:
        pp = np.subtract(series[lag:], series[:-lag])
        lagvec.append(lag)
        tau.append(np.std(pp))
    m = np.polyfit(np.log(lagvec), np.log(tau), 1)
    return m[0]

def add_features(df):
    close = df['Close'].values
    high = df['High'].values
    low = df['Low'].values
    volume = df['Volume'].values
    n = len(df)
    
    # EMAs
    df['EMA_20'] = df['Close'].ewm(span=20, adjust=False).mean()
    df['EMA_50'] = df['Close'].ewm(span=50, adjust=False).mean()
    df['EMA_200'] = df['Close'].ewm(span=200, adjust=False).mean()
    df['Dragon_Mid'] = df['Close'].ewm(span=34, adjust=False).mean()
    
    # ATR 14
    tr1 = df['High'] - df['Low']
    tr2 = (df['High'] - df['Close'].shift(1)).abs()
    tr3 = (df['Low'] - df['Close'].shift(1)).abs()
    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    df['ATR_14'] = tr.rolling(14).mean().bfill()
    
    # PVSRA
    vol_sma10 = df['Volume'].rolling(10).mean()
    spread = df['High'] - df['Low']
    spread_vol = spread * df['Volume']
    spread_vol_max = spread_vol.rolling(10).max()
    
    df['PVSRA_Climax'] = (df['Volume'] >= 2.0 * vol_sma10) | (spread_vol >= spread_vol_max)
    df['PVSRA_Rising'] = (df['Volume'] >= 1.5 * vol_sma10) & (~df['PVSRA_Climax'])
    
    # Volume Anormal v6 (ADV rolling)
    adv_rolling = df['Volume'].rolling(288).mean()
    df['Abnormal_Vol'] = df['Volume'] >= (1.6 * adv_rolling)
    
    # Deformação Elástica Delta_t
    df['Delta_t'] = (df['Close'] - df['EMA_20']) / df['ATR_14']
    
    # Hurst / DFA rolling (janela 40 barras)
    hurst_vals = np.full(n, 0.50)
    window = 40
    for i in range(window, n):
        sub_c = close[i-window:i]
        try:
            hurst_vals[i] = calculate_hurst(sub_c)
        except:
            hurst_vals[i] = 0.50
    df['Hurst'] = np.clip(hurst_vals, 0.20, 0.90)
    
    # Perfil de Volume Rolante (288 barras = aprox 24h)
    poc_vals = np.zeros(n)
    vah_vals = np.zeros(n)
    val_vals = np.zeros(n)
    
    # Calculo eficiente de POC/VAH/VAL a cada 12 barras (1 hora) e forward fill
    prof_win = 288
    for i in range(prof_win, n, 6):
        c_win = close[i-prof_win:i]
        v_win = volume[i-prof_win:i]
        if v_win.sum() == 0:
            v_win = np.ones_like(c_win)
            
        bins = np.linspace(c_win.min(), c_win.max(), 30)
        bin_idx = np.digitize(c_win, bins) - 1
        vol_per_bin = np.zeros(len(bins))
        for b, v in zip(bin_idx, v_win):
            if 0 <= b < len(bins):
                vol_per_bin[b] += v
                
        poc_idx = np.argmax(vol_per_bin)
        poc = bins[poc_idx]
        
        # Area de valor (70%)
        total_vol = vol_per_bin.sum()
        cum_vol = 0
        vah = poc
        val = poc
        # expand from poc
        low_idx = poc_idx
        high_idx = poc_idx
        target_vol = total_vol * 0.70
        cum_vol = vol_per_bin[poc_idx]
        
        while cum_vol < target_vol and (low_idx > 0 or high_idx < len(bins) - 1):
            v_above = vol_per_bin[high_idx + 1] if high_idx + 1 < len(bins) else 0
            v_below = vol_per_bin[low_idx - 1] if low_idx - 1 >= 0 else 0
            if v_above >= v_below and high_idx + 1 < len(bins):
                high_idx += 1
                cum_vol += v_above
            elif low_idx - 1 >= 0:
                low_idx -= 1
                cum_vol += v_below
            else:
                break
        
        vah = bins[high_idx]
        val = bins[low_idx]
        
        end_idx = min(i + 6, n)
        poc_vals[i:end_idx] = poc
        vah_vals[i:end_idx] = vah
        val_vals[i:end_idx] = val
        
    df['POC'] = pd.Series(poc_vals, index=df.index).replace(0, np.nan).bfill()
    df['VAH'] = pd.Series(vah_vals, index=df.index).replace(0, np.nan).bfill()
    df['VAL'] = pd.Series(val_vals, index=df.index).replace(0, np.nan).bfill()
    
    return df

def backtest_engine(df, strategy_type='REVERSAL', exit_type='FULL_TP'):
    """
    strategy_type:
      'REVERSAL': Fade nas extremidades (|Delta_t| >= 2.0, H <= 0.55, Climax/Exaustão)
      'BREAKOUT': Rompimento de barreira (|Delta_t| >= 2.2, H > 0.58, Volume Anormal, Rompendo VAH/VAL)
      'HYBRID': Ambos adaptados pelo Hurst (H <= 0.55 -> Reversal, H > 0.58 -> Breakout)
      
    exit_type:
      'FULL_TP': 100% no primeiro alvo estrutural (POC/Médias para Reversão; 2.0*ATR para Breakout)
      'PARTIAL_TRAILING': 70% no TP1 + 30% em Trailing Stop estrutural barra-a-barra
      'TRAILING_ONLY': Trailing Stop barra-a-barra (L_{t-1} / H_{t-1}) com Front-running
    """
    trades = []
    in_position = False
    pos_type = None # 'BUY' or 'SELL'
    entry_price = 0.0
    sl_price = 0.0
    tp1_price = 0.0
    entry_idx = 0
    trade_source = None
    partial_taken = False
    realized_pnl_pts = 0.0
    
    close = df['Close'].values
    high = df['High'].values
    low = df['Low'].values
    open_p = df['Open'].values
    delta_t = df['Delta_t'].values
    hurst = df['Hurst'].values
    atr = df['ATR_14'].values
    poc = df['POC'].values
    vah = df['VAH'].values
    val = df['VAL'].values
    climax = df['PVSRA_Climax'].values
    abnormal = df['Abnormal_Vol'].values
    ema20 = df['EMA_20'].values
    
    n = len(df)
    start_bar = 300 # aguarda aquecimento dos indicadores
    
    for i in range(start_bar, n):
        # 1. Gerenciar posição aberta
        if in_position:
            bars_held = i - entry_idx
            curr_high = high[i]
            curr_low = low[i]
            curr_close = close[i]
            curr_open = open_p[i]
            
            # Checar Stop Loss
            hit_sl = False
            hit_tp = False
            
            if pos_type == 'BUY':
                if curr_low <= sl_price:
                    # SL atingido
                    exit_price = sl_price
                    pts = exit_price - entry_price
                    total_pts = (pts * 0.3 + realized_pnl_pts * 0.7) if partial_taken else pts
                    trades.append({
                        'type': 'BUY', 'source': trade_source, 'entry': entry_price, 'exit': exit_price,
                        'pts': total_pts, 'win': total_pts > 0, 'bars': bars_held, 'reason': 'SL'
                    })
                    in_position = False
                    continue
                
                # Checar TP1
                if not partial_taken and curr_high >= tp1_price:
                    if exit_type == 'FULL_TP':
                        exit_price = tp1_price
                        pts = exit_price - entry_price
                        trades.append({
                            'type': 'BUY', 'source': trade_source, 'entry': entry_price, 'exit': exit_price,
                            'pts': pts, 'win': pts > 0, 'bars': bars_held, 'reason': 'TP_FULL'
                        })
                        in_position = False
                        continue
                    elif exit_type == 'PARTIAL_TRAILING':
                        partial_taken = True
                        realized_pnl_pts = tp1_price - entry_price
                        # Move SL para breakeven
                        sl_price = entry_price
                        
                # Trailing Stop Estrutural para BUY (L_{t-1} - 0.2*ATR)
                if exit_type in ['PARTIAL_TRAILING', 'TRAILING_ONLY']:
                    new_sl = low[i-1] - 0.2 * atr[i-1]
                    if new_sl > sl_price:
                        sl_price = new_sl
                        
            elif pos_type == 'SELL':
                if curr_high >= sl_price:
                    # SL atingido
                    exit_price = sl_price
                    pts = entry_price - exit_price
                    total_pts = (pts * 0.3 + realized_pnl_pts * 0.7) if partial_taken else pts
                    trades.append({
                        'type': 'SELL', 'source': trade_source, 'entry': entry_price, 'exit': exit_price,
                        'pts': total_pts, 'win': total_pts > 0, 'bars': bars_held, 'reason': 'SL'
                    })
                    in_position = False
                    continue
                
                # Checar TP1
                if not partial_taken and curr_low <= tp1_price:
                    if exit_type == 'FULL_TP':
                        exit_price = tp1_price
                        pts = entry_price - exit_price
                        trades.append({
                            'type': 'SELL', 'source': trade_source, 'entry': entry_price, 'exit': exit_price,
                            'pts': pts, 'win': pts > 0, 'bars': bars_held, 'reason': 'TP_FULL'
                        })
                        in_position = False
                        continue
                    elif exit_type == 'PARTIAL_TRAILING':
                        partial_taken = True
                        realized_pnl_pts = entry_price - tp1_price
                        # Move SL para breakeven
                        sl_price = entry_price
                        
                # Trailing Stop Estrutural para SELL (H_{t-1} + 0.2*ATR)
                if exit_type in ['PARTIAL_TRAILING', 'TRAILING_ONLY']:
                    new_sl = high[i-1] + 0.2 * atr[i-1]
                    if new_sl < sl_price:
                        sl_price = new_sl
                        
            # Timeout máximo de 60 barras (5 horas) se ficar lateral
            if bars_held >= 60:
                pts = (curr_close - entry_price) if pos_type == 'BUY' else (entry_price - curr_close)
                total_pts = (pts * 0.3 + realized_pnl_pts * 0.7) if partial_taken else pts
                trades.append({
                    'type': pos_type, 'source': trade_source, 'entry': entry_price, 'exit': curr_close,
                    'pts': total_pts, 'win': total_pts > 0, 'bars': bars_held, 'reason': 'TIMEOUT'
                })
                in_position = False
                continue
                
            continue # Se está posicionado, não entra em novo trade
            
        # 2. Avaliar novas entradas se flat
        can_reversal = (strategy_type in ['REVERSAL', 'HYBRID'])
        can_breakout = (strategy_type in ['BREAKOUT', 'HYBRID'])
        
        # --- A. Condição de Reversão / Fade (Regime Alpha) ---
        if can_reversal and hurst[i] <= 0.55:
            # Venda em topo esticado: Delta_t >= 2.0 com Climax ou Rejeição de VAH
            if delta_t[i] >= 2.0 and (climax[i] or close[i] >= vah[i]):
                # Gatilho: candle fechou abaixo da máxima ou com rejeição
                sl = max(high[i], high[i-1]) + 0.3 * atr[i]
                tp = poc[i] if poc[i] < close[i] else ema20[i]
                
                # Checar Headroom Geométrico
                dist_stop = sl - close[i]
                dist_target = close[i] - tp
                if dist_stop > 0 and dist_target / dist_stop >= 1.50:
                    in_position = True
                    pos_type = 'SELL'
                    entry_price = close[i]
                    sl_price = sl
                    tp1_price = tp + 0.2 * dist_target # front-running no alvo
                    entry_idx = i
                    trade_source = 'REVERSAL'
                    partial_taken = False
                    realized_pnl_pts = 0.0
                    continue
                    
            # Compra em fundo esticado: Delta_t <= -2.0 com Climax ou Rejeição de VAL
            elif delta_t[i] <= -2.0 and (climax[i] or close[i] <= val[i]):
                sl = min(low[i], low[i-1]) - 0.3 * atr[i]
                tp = poc[i] if poc[i] > close[i] else ema20[i]
                
                dist_stop = close[i] - sl
                dist_target = tp - close[i]
                if dist_stop > 0 and dist_target / dist_stop >= 1.50:
                    in_position = True
                    pos_type = 'BUY'
                    entry_price = close[i]
                    sl_price = sl
                    tp1_price = tp - 0.2 * dist_target # front-running no alvo
                    entry_idx = i
                    trade_source = 'REVERSAL'
                    partial_taken = False
                    realized_pnl_pts = 0.0
                    continue

        # --- B. Condição de Rompimento Balístico / BOS (Regime Gamma) ---
        if can_breakout and hurst[i] > 0.58:
            # Rompimento de Alta: Rompeu VAH com volume anormal e Hurst alto
            if close[i] > vah[i] and close[i-1] <= vah[i-1] and (abnormal[i] or climax[i]):
                sl = vah[i] - 0.8 * atr[i] # volta para dentro do valor
                tp = close[i] + 2.2 * atr[i]
                
                dist_stop = close[i] - sl
                dist_target = tp - close[i]
                if dist_stop > 0 and dist_target / dist_stop >= 1.60:
                    in_position = True
                    pos_type = 'BUY'
                    entry_price = close[i]
                    sl_price = sl
                    tp1_price = tp
                    entry_idx = i
                    trade_source = 'BREAKOUT_BOS'
                    partial_taken = False
                    realized_pnl_pts = 0.0
                    continue
                    
            # Rompimento de Baixa: Rompeu VAL com volume anormal e Hurst alto
            elif close[i] < val[i] and close[i-1] >= val[i-1] and (abnormal[i] or climax[i]):
                sl = val[i] + 0.8 * atr[i]
                tp = close[i] - 2.2 * atr[i]
                
                dist_stop = sl - close[i]
                dist_target = close[i] - tp
                if dist_stop > 0 and dist_target / dist_stop >= 1.60:
                    in_position = True
                    pos_type = 'SELL'
                    entry_price = close[i]
                    sl_price = sl
                    tp1_price = tp
                    entry_idx = i
                    trade_source = 'BREAKOUT_BOS'
                    partial_taken = False
                    realized_pnl_pts = 0.0
                    continue

    return trades

def analyze_performance(trades):
    if not trades:
        return {
            'total_trades': 0, 'win_rate': 0.0, 'profit_factor': 0.0,
            'total_pts': 0.0, 'avg_trade_pts': 0.0, 'max_dd_pts': 0.0,
            'avg_bars': 0.0, 'sharpe': 0.0
        }
    
    df_t = pd.DataFrame(trades)
    total_trades = len(df_t)
    wins = df_t[df_t['pts'] > 0]
    losses = df_t[df_t['pts'] <= 0]
    
    win_rate = (len(wins) / total_trades) * 100.0
    gross_profit = wins['pts'].sum() if len(wins) > 0 else 0.0
    gross_loss = abs(losses['pts'].sum()) if len(losses) > 0 else 0.0001
    profit_factor = gross_profit / gross_loss if gross_loss > 0 else 999.0
    
    cum_pts = df_t['pts'].cumsum()
    peak = cum_pts.cummax()
    dd = peak - cum_pts
    max_dd = dd.max() if len(dd) > 0 else 0.0
    
    std_pts = df_t['pts'].std()
    sharpe = (df_t['pts'].mean() / std_pts * np.sqrt(252)) if std_pts > 0 else 0.0
    
    return {
        'total_trades': total_trades,
        'win_rate': round(win_rate, 1),
        'profit_factor': round(profit_factor, 2),
        'total_pts': round(cum_pts.iloc[-1], 2),
        'avg_trade_pts': round(df_t['pts'].mean(), 2),
        'max_dd_pts': round(max_dd, 2),
        'avg_bars': round(df_t['bars'].mean(), 1),
        'sharpe': round(sharpe, 2)
    }

def main():
    assets = {
        'XAUUSD': 'GC=F',
        'NAS100': 'NQ=F',
        'BTCUSD': 'BTC-USD'
    }
    
    results = {}
    
    for asset_name, ticker in assets.items():
        print(f"\n=======================================================")
        print(f"PROCESSANDO ATIVO: {asset_name} ({ticker})")
        print(f"=======================================================")
        df = fetch_data(asset_name, ticker, period='60d', interval='5m')
        df = add_features(df)
        
        results[asset_name] = {}
        
        # Testar combinações de estratégia e saída
        strategies = ['REVERSAL', 'BREAKOUT', 'HYBRID']
        exits = ['FULL_TP', 'PARTIAL_TRAILING', 'TRAILING_ONLY']
        
        for strat in strategies:
            for ex in exits:
                key = f"{strat}__{ex}"
                trades = backtest_engine(df, strategy_type=strat, exit_type=ex)
                metrics = analyze_performance(trades)
                results[asset_name][key] = metrics
                print(f"[{asset_name}] {key:<26} | Trades: {metrics['total_trades']:<3} | WinRate: {metrics['win_rate']:>5}% | PF: {metrics['profit_factor']:>5} | Pts: {metrics['total_pts']:>8} | MaxDD: {metrics['max_dd_pts']:>6} | Sharpe: {metrics['sharpe']:>5}")

    # Salvar resultados em JSON
    out_json = r"c:\Robo Virada de Delta\Automacao_Virada_Delta\testes_estrategia\resultados_backtest.json"
    with open(out_json, 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=2, ensure_ascii=False)
    print(f"\nResultados salvos com sucesso em {out_json}")

if __name__ == '__main__':
    main()
