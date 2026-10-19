import yfinance as yf
import pandas as pd
import numpy as np
import os
import json

def fetch_clean_data(ticker, period='60d', interval='5m'):
    df = yf.download(ticker, period=period, interval=interval, progress=False)
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = [col[0] for col in df.columns]
    df = df.dropna()
    return df

def calculate_metrics(df):
    close = df['Close']
    high = df['High']
    low = df['Low']
    vol = df['Volume']
    
    # Médias
    df['EMA_20'] = close.ewm(span=20, adjust=False).mean()
    df['EMA_50'] = close.ewm(span=50, adjust=False).mean()
    df['EMA_200'] = close.ewm(span=200, adjust=False).mean()
    df['Dragon_Mid'] = close.ewm(span=34, adjust=False).mean()
    df['Dragon_High'] = high.ewm(span=34, adjust=False).mean()
    df['Dragon_Low'] = low.ewm(span=34, adjust=False).mean()
    
    # ATR 14
    tr1 = high - low
    tr2 = (high - close.shift(1)).abs()
    tr3 = (low - close.shift(1)).abs()
    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    df['ATR'] = tr.rolling(14).mean().bfill()
    
    # PVSRA
    vol_sma = vol.rolling(10).mean()
    spread = high - low
    spread_vol = spread * vol
    spread_vol_max = spread_vol.rolling(10).max()
    
    df['Climax'] = (vol >= 2.0 * vol_sma) | (spread_vol >= spread_vol_max)
    df['Rising'] = (vol >= 1.5 * vol_sma) & (~df['Climax'])
    df['Abnormal'] = vol >= (1.6 * vol.rolling(288).mean().bfill())
    
    # Deformação Elástica Delta_t
    df['Delta_t'] = (close - df['Dragon_Mid']) / df['ATR']
    
    # Candlestick Rejection Features
    body = (close - df['Open']).abs()
    upper_wick = high - df[['Open', 'Close']].max(axis=1)
    lower_wick = df[['Open', 'Close']].min(axis=1) - low
    
    df['Bear_Rejection'] = (upper_wick >= 1.2 * body) & (close < high - 0.5 * spread)
    df['Bull_Rejection'] = (lower_wick >= 1.2 * body) & (close > low + 0.5 * spread)
    
    # Rolling Volume Profile (POC, VAH, VAL) 24h (288 barras de M5)
    n = len(df)
    c_vals = close.values
    v_vals = vol.values
    poc_arr = np.zeros(n)
    vah_arr = np.zeros(n)
    val_arr = np.zeros(n)
    
    win = 288
    for i in range(win, n, 12):
        cw = c_vals[i-win:i]
        vw = v_vals[i-win:i]
        if vw.sum() == 0:
            vw = np.ones_like(cw)
        bins = np.linspace(cw.min(), cw.max(), 30)
        b_idx = np.digitize(cw, bins) - 1
        vol_bins = np.zeros(len(bins))
        for b, v in zip(b_idx, vw):
            if 0 <= b < len(bins):
                vol_bins[b] += v
        
        p_idx = np.argmax(vol_bins)
        poc = bins[p_idx]
        
        # Area de valor 70%
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
        
        vah = bins[h_idx]
        val = bins[l_idx]
        end = min(i+12, n)
        poc_arr[i:end] = poc
        vah_arr[i:end] = vah
        val_arr[i:end] = val
        
    df['POC'] = pd.Series(poc_arr, index=df.index).replace(0, np.nan).bfill()
    df['VAH'] = pd.Series(vah_arr, index=df.index).replace(0, np.nan).bfill()
    df['VAL'] = pd.Series(val_arr, index=df.index).replace(0, np.nan).bfill()
    
    return df

def simulate_strategy(df, mode='REVERSAL_CONFIRMED', rr_target=1.4, use_trend_filter=True, exit_mode='FULL'):
    """
    Simulador com rigor de execução real:
    mode:
      - 'REVERSAL_CONFIRMED': Deformação Delta_t >= 2.0 + Candle de Rejeição + Climax/Rising
      - 'BOS_PULLBACK': Rompimento de Estrutura + Reteste no POC/VAH/VAL
      - 'HYBRID_TOTAL': Reversão nas extremidades + Pullback pós-BOS
    """
    trades = []
    in_pos = False
    pos_type = None
    entry_p = 0.0
    sl_p = 0.0
    tp_p = 0.0
    entry_i = 0
    partial_hit = False
    realized_pts = 0.0
    
    close = df['Close'].values
    high = df['High'].values
    low = df['Low'].values
    open_p = df['Open'].values
    ema200 = df['EMA_200'].values
    ema20 = df['EMA_20'].values
    dragon_mid = df['Dragon_Mid'].values
    delta_t = df['Delta_t'].values
    poc = df['POC'].values
    vah = df['VAH'].values
    val = df['VAL'].values
    climax = df['Climax'].values
    rising = df['Rising'].values
    abnormal = df['Abnormal'].values
    bear_rej = df['Bear_Rejection'].values
    bull_rej = df['Bull_Rejection'].values
    atr = df['ATR'].values
    
    n = len(df)
    
    for i in range(300, n):
        if in_pos:
            bars_held = i - entry_i
            ch = high[i]
            cl = low[i]
            cc = close[i]
            
            # Checar SL
            if pos_type == 'BUY':
                if cl <= sl_p:
                    loss_pts = sl_p - entry_p
                    total = (loss_pts * 0.3 + realized_pts * 0.7) if partial_hit else loss_pts
                    trades.append({'type': 'BUY', 'pts': total, 'win': total > 0, 'bars': bars_held, 'reason': 'SL'})
                    in_pos = False
                    continue
                # Checar TP
                if ch >= tp_p:
                    if exit_mode == 'FULL':
                        win_pts = tp_p - entry_p
                        trades.append({'type': 'BUY', 'pts': win_pts, 'win': True, 'bars': bars_held, 'reason': 'TP'})
                        in_pos = False
                        continue
                    elif exit_mode == 'PARTIAL_TRAILING':
                        if not partial_hit:
                            partial_hit = True
                            realized_pts = tp_p - entry_p
                            sl_p = entry_p # Breakeven
                # Trailing Stop Estrutural
                if exit_mode in ['PARTIAL_TRAILING', 'TRAILING']:
                    trail = low[i-1] - 0.15 * atr[i-1]
                    if trail > sl_p:
                        sl_p = trail
                        
            elif pos_type == 'SELL':
                if ch >= sl_p:
                    loss_pts = entry_p - sl_p
                    total = (loss_pts * 0.3 + realized_pts * 0.7) if partial_hit else loss_pts
                    trades.append({'type': 'SELL', 'pts': total, 'win': total > 0, 'bars': bars_held, 'reason': 'SL'})
                    in_pos = False
                    continue
                # Checar TP
                if cl <= tp_p:
                    if exit_mode == 'FULL':
                        win_pts = entry_p - tp_p
                        trades.append({'type': 'SELL', 'pts': win_pts, 'win': True, 'bars': bars_held, 'reason': 'TP'})
                        in_pos = False
                        continue
                    elif exit_mode == 'PARTIAL_TRAILING':
                        if not partial_hit:
                            partial_hit = True
                            realized_pts = entry_p - tp_p
                            sl_p = entry_p # Breakeven
                # Trailing Stop Estrutural
                if exit_mode in ['PARTIAL_TRAILING', 'TRAILING']:
                    trail = high[i-1] + 0.15 * atr[i-1]
                    if trail < sl_p:
                        sl_p = trail
                        
            # Timeout (máximo 48 barras = 4h em M5)
            if bars_held >= 48:
                pts = (cc - entry_p) if pos_type == 'BUY' else (entry_p - cc)
                total = (pts * 0.3 + realized_pts * 0.7) if partial_hit else pts
                trades.append({'type': pos_type, 'pts': total, 'win': total > 0, 'bars': bars_held, 'reason': 'TIMEOUT'})
                in_pos = False
                continue
                
            continue
            
        # Avaliar Entrada
        # 1. SETUP REVERSÃO CONFIRMADA (O Trade do Gráfico)
        if mode in ['REVERSAL_CONFIRMED', 'HYBRID_TOTAL']:
            # Venda em Topo Esticado
            cond_sell_rev = (delta_t[i] >= 1.8) and (climax[i] or rising[i] or close[i] >= vah[i]) and bear_rej[i]
            if use_trend_filter:
                # Se acima da EMA 200, exige Delta_t maior (>= 2.3) ou clímax forte
                if close[i] > ema200[i]:
                    cond_sell_rev = cond_sell_rev and (delta_t[i] >= 2.2 or climax[i])
                    
            if cond_sell_rev:
                # Stop no topo do candle de rejeição + margem
                sl = high[i] + 0.25 * atr[i]
                risk = sl - close[i]
                if risk > 0:
                    tp = close[i] - rr_target * risk
                    # Front-running: se o POC estiver entre entry e TP, ajusta para o POC se der R:R >= 1.2
                    if poc[i] < close[i] and (close[i] - poc[i]) >= 1.2 * risk:
                        tp = poc[i] + 0.15 * risk
                        
                    in_pos = True
                    pos_type = 'SELL'
                    entry_p = close[i]
                    sl_p = sl
                    tp_p = tp
                    entry_i = i
                    partial_hit = False
                    realized_pts = 0.0
                    continue
                    
            # Compra em Fundo Esticado
            cond_buy_rev = (delta_t[i] <= -1.8) and (climax[i] or rising[i] or close[i] <= val[i]) and bull_rej[i]
            if use_trend_filter:
                if close[i] < ema200[i]:
                    cond_buy_rev = cond_buy_rev and (delta_t[i] <= -2.2 or climax[i])
                    
            if cond_buy_rev:
                sl = low[i] - 0.25 * atr[i]
                risk = close[i] - sl
                if risk > 0:
                    tp = close[i] + rr_target * risk
                    if poc[i] > close[i] and (poc[i] - close[i]) >= 1.2 * risk:
                        tp = poc[i] - 0.15 * risk
                        
                    in_pos = True
                    pos_type = 'BUY'
                    entry_p = close[i]
                    sl_p = sl
                    tp_p = tp
                    entry_i = i
                    partial_hit = False
                    realized_pts = 0.0
                    continue

        # 2. SETUP BOS PULLBACK (Rompimento com Reteste Estrutural)
        if mode in ['BOS_PULLBACK', 'HYBRID_TOTAL']:
            # Pullback de Alta após romper VAH
            cond_buy_bos = (close[i] > ema200[i]) and (low[i] <= vah[i] and close[i] > vah[i]) and (bull_rej[i] or close[i] > open_p[i])
            if cond_buy_bos and (delta_t[i] >= 0.2 and delta_t[i] <= 1.5):
                sl = val[i] if (close[i] - val[i]) <= 1.8 * atr[i] else (close[i] - 1.2 * atr[i])
                risk = close[i] - sl
                if risk > 0:
                    tp = close[i] + (rr_target + 0.4) * risk
                    in_pos = True
                    pos_type = 'BUY'
                    entry_p = close[i]
                    sl_p = sl
                    tp_p = tp
                    entry_i = i
                    partial_hit = False
                    realized_pts = 0.0
                    continue
                    
            # Pullback de Baixa após romper VAL
            cond_sell_bos = (close[i] < ema200[i]) and (high[i] >= val[i] and close[i] < val[i]) and (bear_rej[i] or close[i] < open_p[i])
            if cond_sell_bos and (delta_t[i] <= -0.2 and delta_t[i] >= -1.5):
                sl = vah[i] if (vah[i] - close[i]) <= 1.8 * atr[i] else (close[i] + 1.2 * atr[i])
                risk = sl - close[i]
                if risk > 0:
                    tp = close[i] - (rr_target + 0.4) * risk
                    in_pos = True
                    pos_type = 'SELL'
                    entry_p = close[i]
                    sl_p = sl
                    tp_p = tp
                    entry_i = i
                    partial_hit = False
                    realized_pts = 0.0
                    continue

    return trades

def evaluate_summary(trades, name):
    if not trades:
        return {'Estratégia': name, 'Trades': 0, 'WinRate (%)': 0.0, 'Profit Factor': 0.0, 'Pontos Total': 0.0, 'Max DD': 0.0, 'Sharpe': 0.0}
    df_t = pd.DataFrame(trades)
    tot = len(df_t)
    wins = df_t[df_t['pts'] > 0]
    losses = df_t[df_t['pts'] <= 0]
    
    wr = (len(wins) / tot) * 100.0
    gp = wins['pts'].sum() if len(wins) > 0 else 0.0
    gl = abs(losses['pts'].sum()) if len(losses) > 0 else 0.0001
    pf = gp / gl
    
    cum = df_t['pts'].cumsum()
    peak = cum.cummax()
    dd = peak - cum
    max_dd = dd.max() if len(dd) > 0 else 0.0
    std = df_t['pts'].std()
    sharpe = (df_t['pts'].mean() / std * np.sqrt(252)) if std > 0 else 0.0
    
    return {
        'Estratégia': name,
        'Trades': tot,
        'WinRate (%)': round(wr, 1),
        'Profit Factor': round(pf, 2),
        'Pontos Total': round(cum.iloc[-1], 2),
        'Max DD': round(max_dd, 2),
        'Sharpe': round(sharpe, 2)
    }

def main():
    assets = {
        'XAUUSD': 'GC=F',
        'NAS100': 'NQ=F',
        'BTCUSD': 'BTC-USD'
    }
    
    final_report = {}
    
    for asset, ticker in assets.items():
        print(f"\n==================== TESTANDO {asset} ====================")
        df = fetch_clean_data(ticker, period='60d', interval='5m')
        df = calculate_metrics(df)
        
        runs = [
            # 1. Reversão Confirmada com TP Fixo
            ('Rev_Confirmada_TP_Fixo_1.4R', 'REVERSAL_CONFIRMED', 1.4, True, 'FULL'),
            ('Rev_Confirmada_TP_Fixo_1.8R', 'REVERSAL_CONFIRMED', 1.8, True, 'FULL'),
            # 2. Reversão com Parcial 70/30 e Trailing
            ('Rev_Confirmada_Parcial_70_30', 'REVERSAL_CONFIRMED', 1.4, True, 'PARTIAL_TRAILING'),
            # 3. Pullback Pós-BOS com Alvo Expansão
            ('BOS_Pullback_Trend_1.6R', 'BOS_PULLBACK', 1.6, True, 'FULL'),
            # 4. Híbrido Total (Reversão + BOS) com TP Fixo
            ('Hibrido_Total_TP_Fixo', 'HYBRID_TOTAL', 1.4, True, 'FULL'),
            # 5. Híbrido Total com Parcial 70/30 e Trailing
            ('Hibrido_Total_Parcial_70_30', 'HYBRID_TOTAL', 1.4, True, 'PARTIAL_TRAILING')
        ]
        
        asset_res = []
        for label, m, rr, tf, em in runs:
            t = simulate_strategy(df, mode=m, rr_target=rr, use_trend_filter=tf, exit_mode=em)
            stats = evaluate_summary(t, label)
            asset_res.append(stats)
            print(f"[{asset}] {label:<30} | Trades: {stats['Trades']:<3} | WinRate: {stats['WinRate (%)']:>5}% | PF: {stats['Profit Factor']:>5} | Pts: {stats['Pontos Total']:>8} | MaxDD: {stats['Max DD']:>6} | Sharpe: {stats['Sharpe']:>5}")
            
        final_report[asset] = asset_res
        
    out_file = r"c:\Robo Virada de Delta\Automacao_Virada_Delta\testes_estrategia\relatorio_final_testes.json"
    with open(out_file, 'w', encoding='utf-8') as f:
        json.dump(final_report, f, indent=2, ensure_ascii=False)
    print(f"\nRelatório final salvo em: {out_file}")

if __name__ == '__main__':
    main()
