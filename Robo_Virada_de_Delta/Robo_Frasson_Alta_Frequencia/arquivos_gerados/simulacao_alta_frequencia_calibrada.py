import yfinance as yf
import pandas as pd
import numpy as np
import json
import os

# ==============================================================================
# PARAMETRIZACAO PROFISSIONAL CARTEIRA $10.000 USD
# ==============================================================================
CAPITAL = 10000.0

CONFIGS = {
    'XAUUSD_M15': {
        'ticker': 'GC=F',
        'name': 'Ouro Spot (XAUUSD - Alta Frequência M15)',
        'timeframe': '15m',
        'lot_size': 0.15,         # 15 oz ($15 por $1.00 de ouro)
        'unit_mult': 15.0,        # $15/pt
        'partial_ratio': 0.70,    # 70% Parcial no TP1
        'fee_per_trade': 0.90,    # VT Markets Raw ECN ($6/lot * 0.15 = $0.90)
        'spread_pts': 0.14,
        'slippage_pts': 0.05,
        'min_vh': 0.80,
        'frasson_shift': 3,
        'frasson_mult': 2.00,
        'vol_spike': 1.15,
        'wick_min': 0.35,
        'sl_mult': 1.2,
        'tp1_mult': 1.0,
        'tp2_mult': 2.5
    },
    'BTCUSD_M15': {
        'ticker': 'BTC-USD',
        'name': 'Bitcoin (BTCUSD - Alta Frequência M15)',
        'timeframe': '15m',
        'lot_size': 0.25,         # 0.25 BTC ($0.25 por $1.00 de BTC)
        'unit_mult': 0.25,        # $0.25/pt
        'partial_ratio': 0.70,    # 70% Parcial no TP1
        'fee_per_trade': 1.50,    # VT Markets Raw ECN ($6/lot * 0.25 = $1.50)
        'spread_pts': 17.00,
        'slippage_pts': 2.50,
        'min_vh': 1.10,
        'frasson_shift': 5,
        'frasson_mult': 2.20,
        'vol_spike': 1.20,
        'wick_min': 0.35,
        'sl_mult': 1.2,
        'tp1_mult': 1.0,
        'tp2_mult': 2.5
    }
}

def run_simulation(cfg):
    print(f"\nBaixando dados para {cfg['name']} ({cfg['timeframe']})...")
    df = yf.download(cfg['ticker'], period='60d', interval=cfg['timeframe'].lower(), progress=False)
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = [col[0] for col in df.columns]
    df = df.dropna()
    
    close = df['Close']
    high = df['High']
    low = df['Low']
    vol = df['Volume']
    
    tr1 = high - low
    tr2 = (high - close.shift(1)).abs()
    tr3 = (low - close.shift(1)).abs()
    atr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1).rolling(14).mean()
    ma50 = close.rolling(50).mean()
    ma14 = close.rolling(14).mean()
    
    shift = cfg['frasson_shift']
    f_center = ma14.shift(shift)
    f_upper = (ma14 + cfg['frasson_mult'] * atr).shift(shift)
    f_lower = (ma14 - cfg['frasson_mult'] * atr).shift(shift)
    
    vol_ma = vol.rolling(15).mean()
    
    # Volatilidade
    log_ret = np.log(close / close.shift(1))
    vh = (log_ret.rolling(20).std() * np.sqrt(252 * 26)) * 10.0
    
    bar_range = high - low
    l_wick = np.minimum(df['Open'], close) - low
    u_wick = high - np.maximum(df['Open'], close)
    
    trades = []
    in_pos = False
    pos_type = 0
    entry_price = 0.0
    sl_price = 0.0
    tp1_price = 0.0
    tp2_price = 0.0
    tp1_hit = False
    
    unit_mult = cfg['unit_mult']
    fee = cfg['fee_per_trade']
    part_r = cfg['partial_ratio']
    rem_r = 1.0 - part_r
    
    for i in range(50, len(df)):
        curr = df.iloc[i]
        prev = df.iloc[i-1]
        c_atr = atr.iloc[i-1]
        if np.isnan(c_atr) or c_atr <= 0: continue
        
        if in_pos:
            # TP1
            if not tp1_hit:
                if (pos_type == 1 and curr['High'] >= tp1_price) or (pos_type == -1 and curr['Low'] <= tp1_price):
                    tp1_hit = True
                    pnl = abs(tp1_price - entry_price) * unit_mult * part_r - fee * part_r
                    trades.append(pnl)
                    sl_price = entry_price # Breakeven
                    
            # SL
            sl_trig = (pos_type == 1 and curr['Low'] <= sl_price) or (pos_type == -1 and curr['High'] >= sl_price)
            if sl_trig:
                ratio = rem_r if tp1_hit else 1.0
                pnl_pts = (sl_price - entry_price) if pos_type == 1 else (entry_price - sl_price)
                trades.append(pnl_pts * unit_mult * ratio - fee * ratio)
                in_pos = False
                continue
                
            # TP2
            tp2_trig = (pos_type == 1 and curr['High'] >= tp2_price) or (pos_type == -1 and curr['Low'] <= tp2_price)
            if tp2_trig:
                ratio = rem_r if tp1_hit else 1.0
                pnl_pts = (tp2_price - entry_price) if pos_type == 1 else (entry_price - tp2_price)
                trades.append(pnl_pts * unit_mult * ratio - fee * ratio)
                in_pos = False
                continue
                
            # Trailing stop
            if tp1_hit:
                if pos_type == 1:
                    new_sl = f_lower.iloc[i-1]
                    if new_sl > sl_price: sl_price = new_sl
                else:
                    new_sl = f_upper.iloc[i-1]
                    if new_sl < sl_price: sl_price = new_sl
        else:
            if vh.iloc[i-1] < cfg['min_vh']: continue
            
            br = bar_range.iloc[i-1]
            if br <= 0: continue
            lw = l_wick.iloc[i-1] / br
            uw = u_wick.iloc[i-1] / br
            
            v_ok = prev['Volume'] >= (cfg['vol_spike'] * vol_ma.iloc[i-1])
            
            buy_sig = False
            sell_sig = False
            
            # 1. Pullback no canal na direção da tendência
            if prev['Low'] <= f_center.iloc[i-1] and prev['Close'] > f_center.iloc[i-1] and prev['Close'] > ma50.iloc[i-1] and prev['Close'] > prev['Open']:
                buy_sig = True
            elif prev['High'] >= f_center.iloc[i-1] and prev['Close'] < f_center.iloc[i-1] and prev['Close'] < ma50.iloc[i-1] and prev['Close'] < prev['Open']:
                sell_sig = True
                
            # 2. Rejeição com Pavio e Volume na banda
            if not buy_sig and not sell_sig and v_ok:
                if lw >= cfg['wick_min'] and prev['Low'] <= f_lower.iloc[i-1] and prev['Close'] > prev['Open']:
                    buy_sig = True
                elif uw >= cfg['wick_min'] and prev['High'] >= f_upper.iloc[i-1] and prev['Close'] < prev['Open']:
                    sell_sig = True
                    
            if buy_sig:
                in_pos = True
                pos_type = 1
                entry_price = curr['Open'] + (cfg['spread_pts'] + cfg['slippage_pts'])
                sl_price = entry_price - (cfg['sl_mult'] * c_atr)
                tp1_price = entry_price + (cfg['tp1_mult'] * c_atr)
                tp2_price = entry_price + (cfg['tp2_mult'] * c_atr)
                tp1_hit = False
            elif sell_sig:
                in_pos = True
                pos_type = -1
                entry_price = curr['Open'] - (cfg['spread_pts'] + cfg['slippage_pts'])
                sl_price = entry_price + (cfg['sl_mult'] * c_atr)
                tp1_price = entry_price - (cfg['tp1_mult'] * c_atr)
                tp2_price = entry_price - (cfg['tp2_mult'] * c_atr)
                tp1_hit = False
                
    t_s = pd.Series(trades)
    wins = t_s[t_s > 0]
    losses = t_s[t_s <= 0]
    
    n_days = 42.0 # 60 dias corridos = 42 dias de pregão
    n_trades = len(trades)
    trades_per_day = n_trades / n_days
    
    wr = len(wins) / n_trades * 100 if n_trades > 0 else 0
    gross_win = wins.sum() if len(wins) > 0 else 0
    gross_loss = abs(losses.sum()) if len(losses) > 0 else 1e-6
    pf = gross_win / gross_loss
    net_60d = t_s.sum()
    
    # Projeção 2 anos (504 dias úteis)
    proj_trades_2y = int(trades_per_day * 504)
    net_2y = (net_60d / 42.0) * 504.0
    return_pct_2y = (net_2y / CAPITAL) * 100.0
    
    equity = t_s.cumsum()
    dd = np.maximum.accumulate(equity) - equity
    max_dd = dd.max() if len(dd) > 0 else 0
    
    return {
        'asset': cfg['name'],
        'timeframe': cfg['timeframe'],
        'lot_size': cfg['lot_size'],
        'trades_per_day': round(trades_per_day, 2),
        'trades_2years_projected': proj_trades_2y,
        'win_rate_pct': round(wr, 2),
        'profit_factor': round(pf, 2),
        'net_profit_60d_usd': round(net_60d, 2),
        'projected_net_2years_usd': round(net_2y, 2),
        'return_pct_2years': round(return_pct_2y, 2),
        'max_drawdown_usd': round(max_dd, 2)
    }

def main():
    print("="*75)
    print("SIMULACAO CALIBRADA DE ALTA FREQUENCIA (1 A 2 TRADES/DIA) - BANCA $10.000")
    print("="*75)
    
    out_dir = r"c:\Robo Virada de Delta\Robo_Frasson_Alta_Frequencia_PRO\Testes_Quantitativos"
    results = {}
    for k, cfg in CONFIGS.items():
        res = run_simulation(cfg)
        results[k] = res
        print(f"\nResultados {res['asset']}:")
        print(f"  Frequência: {res['trades_per_day']} trades/dia ({res['trades_2years_projected']} trades em 2 anos)")
        print(f"  Taxa de Acerto (Win Rate): {res['win_rate_pct']}% | Profit Factor: {res['profit_factor']}")
        print(f"  Lucro 60 Dias: ${res['net_profit_60d_usd']} | Projeção 2 Anos: +${res['projected_net_2years_usd']} (+{res['return_pct_2years']}%)")
        print(f"  Max Drawdown: ${res['max_drawdown_usd']}")
        
    with open(os.path.join(out_dir, "resultado_calibrado_hf.json"), 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=4, ensure_ascii=False)

if __name__ == '__main__':
    main()
