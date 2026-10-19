import yfinance as yf
import pandas as pd
import numpy as np
import json
import os

ACCOUNT_SIZE = 10000.0 # Carteira base de $10.000 USD

ASSETS_HF = {
    'XAUUSD': {
        'ticker': 'GC=F',
        'name': 'Ouro Spot (XAUUSD - VT Markets)',
        'timeframe': 'M5',
        'lot_size': 0.10,        # 10 oz ($10 por $1.00 de ouro)
        'unit_value': 10.0,       # $10/pt
        'partial_ratio': 0.70,   # 70% parcial no Alvo 1
        'fee_per_trade': 0.60,   # VT Markets Raw ECN ($6/lot * 0.10 = $0.60)
        'spread_pts': 0.14,      # Spread medio Raw ECN ($0.14)
        'slippage_pts': 0.05,
        'frasson_shift': 3,
        'frasson_mult': 2.00,
        'vol_spike': 1.15,
        'wick_min': 0.30,
        'session_start': 7,
        'session_end': 18
    },
    'BTCUSD': {
        'ticker': 'BTC-USD',
        'name': 'Bitcoin (BTCUSD - VT Markets)',
        'timeframe': 'M5',
        'lot_size': 0.20,        # 0.20 BTC ($0.20 por $1.00 de BTC)
        'unit_value': 0.20,      # $0.20/pt
        'partial_ratio': 0.70,   # 70% parcial no Alvo 1
        'fee_per_trade': 1.20,   # VT Markets Raw ECN ($6/lot * 0.20 = $1.20)
        'spread_pts': 17.00,     # Spread medio Raw ECN ($17.00)
        'slippage_pts': 2.50,
        'frasson_shift': 5,
        'frasson_mult': 2.20,
        'vol_spike': 1.20,
        'wick_min': 0.35,
        'session_start': 12,
        'session_end': 22
    },
    'MNQ': {
        'ticker': 'NQ=F',
        'name': 'Micro Nasdaq (MNQ)',
        'timeframe': 'M1',
        'lot_size': 2.0,         # 2 micros
        'unit_value': 2.0,       # $2/pt
        'partial_ratio': 0.50,   # 50% parcial
        'fee_per_trade': 2.40,   # $1.20 round-turn * 2
        'spread_pts': 0.50,
        'slippage_pts': 0.25,
        'frasson_shift': 5,
        'frasson_mult': 2.00,
        'vol_spike': 1.15,
        'wick_min': 0.30,
        'session_start': 13,
        'session_end': 20
    },
    'MES': {
        'ticker': 'ES=F',
        'name': 'Micro S&P 500 (MES)',
        'timeframe': '12R',
        'lot_size': 2.0,         # 2 micros
        'unit_value': 5.0,       # $5/pt
        'partial_ratio': 0.50,   # 50% parcial
        'fee_per_trade': 2.40,   # $1.20 round-turn * 2
        'spread_pts': 0.25,
        'slippage_pts': 0.25,
        'frasson_shift': 5,
        'frasson_mult': 2.00,
        'vol_spike': 1.10,
        'wick_min': 0.35,
        'session_start': 13,
        'session_end': 20
    }
}

def simulate_hf_asset(cfg):
    print(f"\n>>> Simulando Alta Frequência para {cfg['name']}...")
    # Baixa dados de M5 (60 dias)
    df = yf.download(cfg['ticker'], period='60d', interval='5m', progress=False)
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
    
    vol_ma10 = vol.rolling(10).mean()
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
    
    unit_mult = cfg['unit_value']
    fee = cfg['fee_per_trade']
    part_ratio = cfg['partial_ratio']
    rem_ratio = 1.0 - part_ratio
    
    for i in range(50, len(df)):
        curr = df.iloc[i]
        prev = df.iloc[i-1]
        c_atr = atr.iloc[i-1]
        if np.isnan(c_atr) or c_atr <= 0: continue
        
        if in_pos:
            # Checa TP1 (Parcial 70%)
            if not tp1_hit:
                if (pos_type == 1 and curr['High'] >= tp1_price) or (pos_type == -1 and curr['Low'] <= tp1_price):
                    tp1_hit = True
                    pnl = abs(tp1_price - entry_price) * unit_mult * part_ratio - fee * part_ratio
                    trades.append(pnl)
                    sl_price = entry_price # Breakeven
                    
            # Checa SL
            sl_trig = (pos_type == 1 and curr['Low'] <= sl_price) or (pos_type == -1 and curr['High'] >= sl_price)
            if sl_trig:
                ratio = rem_ratio if tp1_hit else 1.0
                pnl_pts = (sl_price - entry_price) if pos_type == 1 else (entry_price - sl_price)
                trades.append(pnl_pts * unit_mult * ratio - fee * ratio)
                in_pos = False
                continue
                
            # Checa TP2 (Final 30%)
            tp2_trig = (pos_type == 1 and curr['High'] >= tp2_price) or (pos_type == -1 and curr['Low'] <= tp2_price)
            if tp2_trig:
                ratio = rem_ratio if tp1_hit else 1.0
                pnl_pts = (tp2_price - entry_price) if pos_type == 1 else (entry_price - tp2_price)
                trades.append(pnl_pts * unit_mult * ratio - fee * ratio)
                in_pos = False
                continue
                
            # Trailing stop na banda oposta Frasson para os 30% restantes
            if tp1_hit:
                if pos_type == 1:
                    new_sl = f_lower.iloc[i-1]
                    if new_sl > sl_price: sl_price = new_sl
                else:
                    new_sl = f_upper.iloc[i-1]
                    if new_sl < sl_price: sl_price = new_sl
        else:
            # Filtro de sessao
            h = curr.name.hour
            if h < cfg['session_start'] or h > cfg['session_end']: continue
            
            br = bar_range.iloc[i-1]
            if br <= 0: continue
            lw = l_wick.iloc[i-1] / br
            uw = u_wick.iloc[i-1] / br
            
            v_ok = prev['Volume'] >= (cfg['vol_spike'] * vol_ma10.iloc[i-1])
            
            buy_sig = False
            sell_sig = False
            
            # Gatilho Híbrido 1: Pullback na Média Central com Tendência alinhada
            if prev['Low'] <= f_center.iloc[i-1] and prev['Close'] > f_center.iloc[i-1] and prev['Close'] > ma50.iloc[i-1] and prev['Close'] > prev['Open']:
                buy_sig = True
            elif prev['High'] >= f_center.iloc[i-1] and prev['Close'] < f_center.iloc[i-1] and prev['Close'] < ma50.iloc[i-1] and prev['Close'] < prev['Open']:
                sell_sig = True
                
            # Gatilho Híbrido 2: Rejeição de Extremidade (Pavio longo + Volume)
            if not buy_sig and not sell_sig and v_ok:
                if lw >= cfg['wick_min'] and prev['Low'] <= f_lower.iloc[i-1] and prev['Close'] > prev['Open']:
                    buy_sig = True
                elif uw >= cfg['wick_min'] and prev['High'] >= f_upper.iloc[i-1] and prev['Close'] < prev['Open']:
                    sell_sig = True
                    
            if buy_sig:
                in_pos = True
                pos_type = 1
                entry_price = curr['Open'] + (cfg['spread_pts'] + cfg['slippage_pts'])
                sl_price = entry_price - (1.2 * c_atr)
                tp1_price = entry_price + (1.0 * c_atr)
                tp2_price = entry_price + (2.4 * c_atr)
                tp1_hit = False
            elif sell_sig:
                in_pos = True
                pos_type = -1
                entry_price = curr['Open'] - (cfg['spread_pts'] + cfg['slippage_pts'])
                sl_price = entry_price + (1.2 * c_atr)
                tp1_price = entry_price - (1.0 * c_atr)
                tp2_price = entry_price - (2.4 * c_atr)
                tp1_hit = False
                
    t_s = pd.Series(trades)
    wins = t_s[t_s > 0]
    losses = t_s[t_s <= 0]
    
    n_days = 42.0 # 60 dias corridos = aprox 42 dias de pregão
    n_trades = len(trades)
    trades_per_day = n_trades / n_days
    
    wr = len(wins) / n_trades * 100 if n_trades > 0 else 0
    gross_win = wins.sum() if len(wins) > 0 else 0
    gross_loss = abs(losses.sum()) if len(losses) > 0 else 1e-6
    pf = gross_win / gross_loss
    net_60d = t_s.sum()
    
    # Projeção anual e 2 anos
    net_annual = net_60d * 6.0
    net_2years = net_annual * 2.0
    return_pct_2years = (net_2years / ACCOUNT_SIZE) * 100.0
    
    # Curva e Drawdown
    equity = t_s.cumsum()
    running_max = np.maximum.accumulate(equity)
    dd = running_max - equity
    max_dd = dd.max() if len(dd) > 0 else 0
    
    return {
        'asset': cfg['name'],
        'timeframe': cfg['timeframe'],
        'lot_size': cfg['lot_size'],
        'account_base_usd': ACCOUNT_SIZE,
        'trades_60d': n_trades,
        'trades_per_day': round(trades_per_day, 2),
        'trades_projected_2years': int(trades_per_day * 252 * 2),
        'win_rate_pct': round(wr, 2),
        'profit_factor': round(pf, 2),
        'net_profit_60d_usd': round(net_60d, 2),
        'projected_net_2years_usd': round(net_2years, 2),
        'return_pct_2years': round(return_pct_2years, 2),
        'max_drawdown_60d_usd': round(max_dd, 2)
    }

def main():
    print("="*75)
    print("TESTES QUANTITATIVOS DE ALTA FREQUENCIA & ASSERTIVIDADE (M5/M1)")
    print(f"CARTEIRA BASE: ${ACCOUNT_SIZE:,.2f} USD | MODELO HIBRIDO COM PARCIAL 70/30")
    print("="*75)
    
    out_dir = r"c:\Robo Virada de Delta\Robo_Frasson_Alta_Frequencia_PRO\Testes_Quantitativos"
    os.makedirs(out_dir, exist_ok=True)
    
    results = {}
    for k, cfg in ASSETS_HF.items():
        res = simulate_hf_asset(cfg)
        results[k] = res
        print(f"Resultado {k}:")
        print(f"  Frequência: {res['trades_per_day']} trades/dia ({res['trades_projected_2years']} trades em 2 anos)")
        print(f"  Win Rate: {res['win_rate_pct']}% | Profit Factor: {res['profit_factor']}")
        print(f"  Lucro 60 Dias: ${res['net_profit_60d_usd']} | Projeção 2 Anos: +${res['projected_net_2years_usd']} (+{res['return_pct_2years']}%)")
        print(f"  Max Drawdown (60d): ${res['max_drawdown_60d_usd']}")
        
    json_path = os.path.join(out_dir, "resultado_alta_frequencia.json")
    with open(json_path, 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=4, ensure_ascii=False)
        
    print(f"\n[SUCESSO] Relatório de Alta Frequência salvo em: {json_path}")

if __name__ == '__main__':
    main()
