import yfinance as yf
import pandas as pd
import numpy as np
import json
import os
import datetime

# ==============================================================================
# CONFIGURACOES GLOBAIS DO ESTUDO DE 2 ANOS
# ==============================================================================
PERIOD = '730d' # 2 anos completos (2024 - 2026)
INTERVAL = '1h'

ASSETS_CONFIG = {
    'MNQ': {
        'ticker': 'NQ=F',
        'name': 'Micro Nasdaq (MNQ)',
        'point_value': 2.0,      # $2 por ponto por contrato
        'contracts': 2,           # 2 micros
        'min_vh': 1.20,
        'frasson_period': 14,
        'frasson_shift': 5,
        'frasson_mult': 2.00,
        'trigger_mode': 'breakout', # Rompimento/escoramento Frasson
        'fixed_sl_pts': 36.0,
        'fixed_tp1_pts': 36.0,
        'fixed_tp2_pts': 88.0,
        'fee_per_trade': 2.40,    # $1.20 round-turn por contrato * 2 = $2.40
        'spread_pts': 0.50,       # 0.5 pt spread medio
        'slippage_pts': 0.25,     # 0.25 pt slippage
    },
    'MES': {
        'ticker': 'ES=F',
        'name': 'Micro S&P 500 (MES)',
        'point_value': 5.0,      # $5 por ponto por contrato
        'contracts': 2,           # 2 micros
        'min_vh': 0.80,
        'frasson_period': 14,
        'frasson_shift': 5,
        'frasson_mult': 2.00,
        'trigger_mode': 'rejection_poc', # Rejeição com POC/Pavio
        'fixed_sl_pts': 10.0,
        'fixed_tp1_pts': 10.0,
        'fixed_tp2_pts': 20.0,
        'fee_per_trade': 2.40,    # $1.20 round-turn por contrato * 2 = $2.40
        'spread_pts': 0.25,       # 0.25 pt spread
        'slippage_pts': 0.25,
    },
    'XAUUSD': {
        'ticker': 'GC=F',
        'name': 'Ouro Spot (XAUUSD - VT Markets)',
        'point_value': 100.0,     # $100 por ponto ($1/oz) por lote padrão
        'lots': 0.04,             # 0.04 lote (2 ordens de 0.02)
        'min_vh': 0.95,
        'frasson_period': 14,
        'frasson_shift': 3,
        'frasson_mult': 2.00,
        'trigger_mode': 'rejection_poc',
        'fixed_sl_pts': 4.50,     # $4.50 / oz
        'fixed_tp1_pts': 4.50,    # $4.50 / oz
        'fixed_tp2_pts': 11.00,   # $11.00 / oz
        'fee_per_trade': 0.24,    # $6/lote * 0.04 = $0.24 comissao round-turn
        'spread_pts': 0.14,       # $0.14 spread medio Raw ECN
        'slippage_pts': 0.05,
    },
    'BTCUSD': {
        'ticker': 'BTC-USD',
        'name': 'Bitcoin (BTCUSD - VT Markets)',
        'point_value': 1.0,       # $1 por $1 de BTC por lote padrao
        'lots': 0.04,             # 0.04 BTC (2 ordens de 0.02)
        'min_vh': 1.40,
        'frasson_period': 14,
        'frasson_shift': 5,
        'frasson_mult': 2.20,
        'trigger_mode': 'rejection_poc',
        'fixed_sl_pts': 450.0,    # $450 USD
        'fixed_tp1_pts': 450.0,   # $450 USD
        'fixed_tp2_pts': 1150.0,  # $1.150 USD
        'fee_per_trade': 0.24,    # $6/lote * 0.04 = $0.24 comissao round-turn
        'spread_pts': 17.00,      # $17 spread medio Raw ECN
        'slippage_pts': 3.00,
    }
}

def download_asset(ticker):
    print(f"Baixando dados historicos para {ticker} ({PERIOD})...")
    df = yf.download(ticker, period=PERIOD, interval=INTERVAL, progress=False)
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = [col[0] for col in df.columns]
    df = df.dropna()
    print(f"Carregadas {len(df)} barras de {df.index[0]} ate {df.index[-1]}.")
    return df

def calculate_indicators(df, cfg):
    close = df['Close']
    high = df['High']
    low = df['Low']
    vol = df['Volume']
    
    # 1. Volatilidade Historica Anualizada (janela 20 barras)
    log_ret = np.log(close / close.shift(1))
    std_ret = log_ret.rolling(20).std()
    # Fator de anualização
    ann_factor = np.sqrt(252 * 6.5 if 'BTC' not in cfg['name'] else 365 * 24)
    df['VH'] = (std_ret * ann_factor) * 10.0 # Normalizacao padrão
    
    # 2. Frasson ATR (Period 14, Shift, Multiplier)
    tr1 = high - low
    tr2 = (high - close.shift(1)).abs()
    tr3 = (low - close.shift(1)).abs()
    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    atr = tr.rolling(cfg['frasson_period']).mean()
    
    ma_center = close.rolling(cfg['frasson_period']).mean()
    
    # Aplica deslocamento (shift)
    shift = cfg['frasson_shift']
    df['Frasson_Center'] = ma_center.shift(shift)
    df['Frasson_Upper'] = (ma_center + cfg['frasson_mult'] * atr).shift(shift)
    df['Frasson_Lower'] = (ma_center - cfg['frasson_mult'] * atr).shift(shift)
    df['Frasson_Amp'] = df['Frasson_Upper'] - df['Frasson_Lower']
    
    # 3. Analise de Volume e Pavio
    df['Vol_Avg10'] = vol.rolling(10).mean()
    df['Bar_Range'] = high - low
    df['Upper_Wick'] = high - np.maximum(df['Open'], close)
    df['Lower_Wick'] = np.minimum(df['Open'], close) - low
    
    return df.dropna()

def simulate_strategy(df, cfg):
    trades = []
    in_pos = False
    
    pos_type = 0 # 1 Buy, -1 Sell
    entry_price = 0.0
    sl_price = 0.0
    tp1_price = 0.0
    tp2_price = 0.0
    
    tp1_hit = False
    pos_vol_remaining = 1.0 # 0.5 apos parcial
    entry_time = None
    
    # Dimensionamento
    if 'contracts' in cfg:
        total_units = cfg['contracts']
        unit_mult = cfg['point_value'] # $2/pt ou $5/pt
    else:
        total_units = cfg['lots']
        unit_mult = cfg['point_value'] * cfg['lots'] # Ex: 100 * 0.04 = $4/pt
        
    for i in range(1, len(df)):
        prev_row = df.iloc[i-1]
        curr_row = df.iloc[i]
        
        # Gestao de Posicao Aberta
        if in_pos:
            c_high = curr_row['High']
            c_low = curr_row['Low']
            
            # Checa Alvo 1 (Parcial de 50%)
            if not tp1_hit:
                if (pos_type == 1 and c_high >= tp1_price) or (pos_type == -1 and c_low <= tp1_price):
                    tp1_hit = True
                    # Realiza 50% do lucro no Alvo 1
                    pnl_pts1 = abs(tp1_price - entry_price)
                    pnl_usd1 = (pnl_pts1 * unit_mult * 0.5) - (cfg['fee_per_trade'] * 0.5)
                    trades.append({
                        'type': 'BUY_T1' if pos_type == 1 else 'SELL_T1',
                        'entry_time': str(entry_time),
                        'exit_time': str(curr_row.name),
                        'entry_price': entry_price,
                        'exit_price': tp1_price,
                        'pnl_pts': pnl_pts1,
                        'pnl_usd': pnl_usd1,
                        'stage': 'PARCIAL'
                    })
                    # Move Stop para Breakeven estrutural
                    sl_price = entry_price
            
            # Checa Stop Loss
            sl_triggered = False
            if pos_type == 1 and c_low <= sl_price:
                sl_triggered = True
                exit_p = sl_price
            elif pos_type == -1 and c_high >= sl_price:
                sl_triggered = True
                exit_p = sl_price
                
            if sl_triggered:
                rem_ratio = 0.5 if tp1_hit else 1.0
                pnl_pts = (exit_p - entry_price) if pos_type == 1 else (entry_price - exit_p)
                pnl_usd = (pnl_pts * unit_mult * rem_ratio) - (cfg['fee_per_trade'] * rem_ratio)
                trades.append({
                    'type': 'BUY_SL' if pos_type == 1 else 'SELL_SL',
                    'entry_time': str(entry_time),
                    'exit_time': str(curr_row.name),
                    'entry_price': entry_price,
                    'exit_price': exit_p,
                    'pnl_pts': pnl_pts,
                    'pnl_usd': pnl_usd,
                    'stage': 'STOP_LOSS'
                })
                in_pos = False
                continue
                
            # Checa Alvo 2 (Final Conduzido)
            tp2_triggered = False
            if pos_type == 1 and c_high >= tp2_price:
                tp2_triggered = True
                exit_p = tp2_price
            elif pos_type == -1 and c_low <= tp2_price:
                tp2_triggered = True
                exit_p = tp2_price
                
            if tp2_triggered:
                rem_ratio = 0.5 if tp1_hit else 1.0
                pnl_pts = (exit_p - entry_price) if pos_type == 1 else (entry_price - exit_p)
                pnl_usd = (pnl_pts * unit_mult * rem_ratio) - (cfg['fee_per_trade'] * rem_ratio)
                trades.append({
                    'type': 'BUY_T2' if pos_type == 1 else 'SELL_T2',
                    'entry_time': str(entry_time),
                    'exit_time': str(curr_row.name),
                    'entry_price': entry_price,
                    'exit_price': exit_p,
                    'pnl_pts': pnl_pts,
                    'pnl_usd': pnl_usd,
                    'stage': 'FINAL'
                })
                in_pos = False
                continue
                
            # Trailing Stop escorado nas bandas Frasson se já bateu Alvo 1
            if tp1_hit:
                if pos_type == 1:
                    new_sl = curr_row['Frasson_Lower']
                    if new_sl > sl_price:
                        sl_price = new_sl
                else:
                    new_sl = curr_row['Frasson_Upper']
                    if new_sl < sl_price:
                        sl_price = new_sl
                        
        else:
            # Avaliacao de Novas Entradas
            # 1. Filtro GPS de Volatilidade 5M
            if prev_row['VH'] < cfg['min_vh']:
                continue # Mao no bolso
                
            # 2. Avalia Gatilho
            trigger_buy = False
            trigger_sell = False
            
            if cfg['trigger_mode'] == 'breakout':
                # Compra: Fecha acima da banda superior com expansao de volume
                if prev_row['Close'] > prev_row['Frasson_Upper'] and prev_row['Close'] > prev_row['Open'] and prev_row['Volume'] >= prev_row['Vol_Avg10']:
                    trigger_buy = True
                # Venda: Fecha abaixo da banda inferior com expansao de volume
                elif prev_row['Close'] < prev_row['Frasson_Lower'] and prev_row['Close'] < prev_row['Open'] and prev_row['Volume'] >= prev_row['Vol_Avg10']:
                    trigger_sell = True
            else: # rejection_poc
                # Rejeicao com pavio longo (>= 35%)
                b_range = prev_row['Bar_Range']
                if b_range > 0:
                    l_wick_pct = prev_row['Lower_Wick'] / b_range
                    u_wick_pct = prev_row['Upper_Wick'] / b_range
                    
                    if l_wick_pct >= 0.35 and prev_row['Close'] > prev_row['Open'] and prev_row['Low'] <= prev_row['Frasson_Lower']:
                        trigger_buy = True
                    elif u_wick_pct >= 0.35 and prev_row['Close'] < prev_row['Open'] and prev_row['High'] >= prev_row['Frasson_Upper']:
                        trigger_sell = True
                        
            if trigger_buy:
                in_pos = True
                pos_type = 1
                entry_price = curr_row['Open'] + (cfg['spread_pts'] + cfg['slippage_pts'])
                sl_price = entry_price - cfg['fixed_sl_pts']
                tp1_price = entry_price + cfg['fixed_tp1_pts']
                tp2_price = entry_price + cfg['fixed_tp2_pts']
                tp1_hit = False
                entry_time = curr_row.name
            elif trigger_sell:
                in_pos = True
                pos_type = -1
                entry_price = curr_row['Open'] - (cfg['spread_pts'] + cfg['slippage_pts'])
                sl_price = entry_price + cfg['fixed_sl_pts']
                tp1_price = entry_price - cfg['fixed_tp1_pts']
                tp2_price = entry_price - cfg['fixed_tp2_pts']
                tp1_hit = False
                entry_time = curr_row.name
                
    return trades

def analyze_performance(trades, name):
    if not trades:
        return {'status': 'Sem trades'}
        
    df_t = pd.DataFrame(trades)
    
    total_pnl = df_t['pnl_usd'].sum()
    wins = df_t[df_t['pnl_usd'] > 0]
    losses = df_t[df_t['pnl_usd'] <= 0]
    
    win_rate = len(wins) / len(df_t) * 100.0 if len(df_t) > 0 else 0
    gross_profit = wins['pnl_usd'].sum() if len(wins) > 0 else 0
    gross_loss = abs(losses['pnl_usd'].sum()) if len(losses) > 0 else 1e-6
    profit_factor = gross_profit / gross_loss
    
    # Curva de Capital e Drawdown
    equity_curve = df_t['pnl_usd'].cumsum()
    running_max = np.maximum.accumulate(equity_curve)
    drawdowns = running_max - equity_curve
    max_dd = drawdowns.max() if len(drawdowns) > 0 else 0
    
    avg_win = wins['pnl_usd'].mean() if len(wins) > 0 else 0
    avg_loss = abs(losses['pnl_usd'].mean()) if len(losses) > 0 else 0
    payoff = avg_win / avg_loss if avg_loss > 0 else 0
    
    return {
        'asset': name,
        'total_trades': len(df_t),
        'net_profit_usd': round(total_pnl, 2),
        'win_rate_pct': round(win_rate, 2),
        'profit_factor': round(profit_factor, 2),
        'max_drawdown_usd': round(max_dd, 2),
        'avg_win_usd': round(avg_win, 2),
        'avg_loss_usd': round(avg_loss, 2),
        'payoff_ratio': round(payoff, 2),
        'gross_profit_usd': round(gross_profit, 2),
        'gross_loss_usd': round(gross_loss, 2)
    }

def main():
    results = {}
    print("="*70)
    print("INICIANDO SUITE DE TESTES QUANTITATIVOS (2 ANOS: 2024 - 2026)")
    print("="*70)
    
    out_dir = r"c:\Robo Virada de Delta\Robo_Frasson_Orderflow_MultiAsset\Testes_2_Anos"
    os.makedirs(out_dir, exist_ok=True)
    
    for key, cfg in ASSETS_CONFIG.items():
        print(f"\n>>> Processando {cfg['name']}...")
        df = download_asset(cfg['ticker'])
        df = calculate_indicators(df, cfg)
        trades = simulate_strategy(df, cfg)
        metrics = analyze_performance(trades, cfg['name'])
        results[key] = metrics
        
        # Salva trades detalhados em CSV
        if trades:
            pd.DataFrame(trades).to_csv(os.path.join(out_dir, f"trades_2anos_{key}.csv"), index=False)
            
        print(f"Resultado {key}: Lucro Líquido = ${metrics['net_profit_usd']} | PF = {metrics['profit_factor']} | WR = {metrics['win_rate_pct']}% | MaxDD = ${metrics['max_drawdown_usd']}")
        
    json_path = os.path.join(out_dir, "resultado_consolidado_2anos.json")
    with open(json_path, 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=4, ensure_ascii=False)
        
    print(f"\n[SUCESSO] Relatorio e trades de 2 anos salvos em: {out_dir}")

if __name__ == '__main__':
    main()
