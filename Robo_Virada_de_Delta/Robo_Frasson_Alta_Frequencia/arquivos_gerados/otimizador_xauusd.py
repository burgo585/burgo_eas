import yfinance as yf
import pandas as pd
import numpy as np
import json
import time

print("Baixando 60 dias de dados M5 do Ouro (GC=F)...")
df_raw = yf.download('GC=F', period='60d', interval='5m', progress=False)
if isinstance(df_raw.columns, pd.MultiIndex):
    df_raw.columns = [col[0] for col in df_raw.columns]
df_raw = df_raw.dropna()

# Filtro de sessao Londres e NY (07:00 as 18:00 UTC) - horario nobre de liquidez do Ouro
active_mask = (df_raw.index.hour >= 7) & (df_raw.index.hour <= 18)
df_active = df_raw[active_mask].copy()

opens = df_active['Open'].values
highs = df_active['High'].values
lows = df_active['Low'].values
closes = df_active['Close'].values
volumes = df_active['Volume'].values
dates = df_active.index.date
unique_days = len(np.unique(dates))
n_bars = len(closes)

print(f"Total de barras M5: {n_bars} em {unique_days} dias de negociação.")

lot = 0.15 # 0.15 lot = $15.00 por ponto de Ouro (ideal para conta de $10.000, risco controlado de ~1%)
unit_mult = 100.0 * lot
fee_per_trade = 0.90 # VT Markets Raw ECN ($6/lot round turn * 0.15 = $0.90)
spread_slip = 0.18   # Spread tipico VT Markets (0.14) + slippage (0.04)

# Computar True Range e Indicadores
tr = np.maximum(highs - lows, np.maximum(np.abs(highs - np.roll(closes, 1)), np.abs(lows - np.roll(closes, 1))))
tr[0] = highs[0] - lows[0]

atr_10 = pd.Series(tr).rolling(10).mean().values
atr_14 = pd.Series(tr).rolling(14).mean().values
ma_10 = pd.Series(closes).rolling(10).mean().values
ma_14 = pd.Series(closes).rolling(14).mean().values
ema_50 = pd.Series(closes).ewm(span=50).mean().values
ema_200 = pd.Series(closes).ewm(span=200).mean().values
vol_ma10 = pd.Series(volumes).rolling(10).mean().values

bar_range = highs - lows
l_wick = np.minimum(opens, closes) - lows
u_wick = highs - np.maximum(opens, closes)

results = []
print("Iniciando otimização avançada com contabilidade exata por posição e filtros de fluxo...")
t0 = time.time()

p_list = [(10, ma_10, atr_10), (14, ma_14, atr_14)]
shifts = [2, 3, 5]
mults = [1.5, 1.8, 2.0, 2.2]
targets = [
    # tp1_m, tp2_m, sl_m, part_r
    (0.6, 1.5, 0.9, 0.70), # Scalper curto
    (0.7, 1.8, 1.0, 0.70), # Scalper balanceado
    (0.8, 2.0, 1.0, 0.70), # Alvo 1.0x ATR
    (0.8, 2.2, 1.2, 0.75), # 75% parcial + corrida
    (1.0, 2.5, 1.2, 0.70), # Alvo amplo
    (0.5, 1.2, 0.75, 0.80),# Alta assertividade parcial rápida
    (0.7, 2.0, 0.9, 0.65), # 65% parcial
]
triggers = ['pullback_trend', 'reversal_trend', 'hybrid_trend', 'reversal_pure']
vol_filters = [1.0, 1.15]
max_trades_day = 4 # Controle anti-overtrading por dia

count = 0
for (p_val, ma_arr, atr_arr) in p_list:
    for s in shifts:
        f_center = np.roll(ma_arr, s)
        for m in mults:
            f_upper = f_center + m * np.roll(atr_arr, s)
            f_lower = f_center - m * np.roll(atr_arr, s)
            
            for (tp1_m, tp2_m, sl_m, part_r) in targets:
                rem_r = 1.0 - part_r
                for trig in triggers:
                    for vm in vol_filters:
                        count += 1
                        trades = []
                        in_pos = False
                        pos_type = 0
                        entry_price = 0.0
                        sl_price = 0.0
                        tp1_price = 0.0
                        tp2_price = 0.0
                        tp1_hit = False
                        accum_pnl = 0.0
                        
                        cur_day = None
                        trades_today = 0
                        
                        for i in range(200, n_bars):
                            d = dates[i]
                            if d != cur_day:
                                cur_day = d
                                trades_today = 0
                                
                            c_high = highs[i]
                            c_low = lows[i]
                            c_open = opens[i]
                            c_close = closes[i]
                            
                            prev_i = i - 1
                            cur_atr = atr_arr[prev_i]
                            if np.isnan(cur_atr) or cur_atr <= 0: continue
                            
                            if in_pos:
                                # Verifica TP1 se ainda não atingido
                                if not tp1_hit:
                                    if (pos_type == 1 and c_high >= tp1_price) or (pos_type == -1 and c_low <= tp1_price):
                                        tp1_hit = True
                                        pnl_tp1 = abs(tp1_price - entry_price) * unit_mult * part_r - (fee_per_trade * part_r)
                                        accum_pnl += pnl_tp1
                                        sl_price = entry_price # Move SL para o Breakeven
                                        
                                # Verifica SL / Breakeven
                                sl_trig = (pos_type == 1 and c_low <= sl_price) or (pos_type == -1 and c_high >= sl_price)
                                if sl_trig:
                                    ratio = rem_r if tp1_hit else 1.0
                                    pnl_pts = (sl_price - entry_price) if pos_type == 1 else (entry_price - sl_price)
                                    pnl_rem = pnl_pts * unit_mult * ratio - (fee_per_trade * ratio)
                                    total_pos_pnl = accum_pnl + pnl_rem
                                    trades.append(total_pos_pnl)
                                    in_pos = False
                                    continue
                                    
                                # Verifica TP2
                                tp2_trig = (pos_type == 1 and c_high >= tp2_price) or (pos_type == -1 and c_low <= tp2_price)
                                if tp2_trig:
                                    ratio = rem_r if tp1_hit else 1.0
                                    pnl_pts = (tp2_price - entry_price) if pos_type == 1 else (entry_price - tp2_price)
                                    pnl_rem = pnl_pts * unit_mult * ratio - (fee_per_trade * ratio)
                                    total_pos_pnl = accum_pnl + pnl_rem
                                    trades.append(total_pos_pnl)
                                    in_pos = False
                                    continue
                            else:
                                if trades_today >= max_trades_day:
                                    continue
                                    
                                br = bar_range[prev_i]
                                if br <= 0: continue
                                lw = l_wick[prev_i] / br
                                uw = u_wick[prev_i] / br
                                
                                v_ok = volumes[prev_i] >= (vm * vol_ma10[prev_i])
                                fc = f_center[prev_i]
                                fu = f_upper[prev_i]
                                fl = f_lower[prev_i]
                                
                                p_close = closes[prev_i]
                                p_open = opens[prev_i]
                                p_high = highs[prev_i]
                                p_low = lows[prev_i]
                                
                                uptrend = p_close > ema_50[prev_i]
                                downtrend = p_close < ema_50[prev_i]
                                
                                buy_sig = False
                                sell_sig = False
                                
                                if trig == 'pullback_trend':
                                    # Recuo na linha central com tendência a favor
                                    if uptrend and p_low <= fc and p_close > fc and p_close > p_open and v_ok:
                                        buy_sig = True
                                    elif downtrend and p_high >= fc and p_close < fc and p_close < p_open and v_ok:
                                        sell_sig = True
                                        
                                elif trig == 'reversal_trend':
                                    # Rejeição na banda a favor da tendência macro
                                    if uptrend and p_low <= fl and lw >= 0.30 and p_close > p_open and v_ok:
                                        buy_sig = True
                                    elif downtrend and p_high >= fu and uw >= 0.30 and p_close < p_open and v_ok:
                                        sell_sig = True
                                        
                                elif trig == 'hybrid_trend':
                                    # Pullback OU Rejeição com tendência
                                    if uptrend and ((p_low <= fc and p_close > fc) or (p_low <= fl and lw >= 0.25)) and p_close > p_open and v_ok:
                                        buy_sig = True
                                    elif downtrend and ((p_high >= fc and p_close < fc) or (p_high >= fu and uw >= 0.25)) and p_close < p_open and v_ok:
                                        sell_sig = True
                                        
                                elif trig == 'reversal_pure':
                                    # Rejeição pura de banda (contra-tendência e a favor)
                                    if p_low <= fl and lw >= 0.35 and p_close > p_open and v_ok:
                                        buy_sig = True
                                    elif p_high >= fu and uw >= 0.35 and p_close < p_open and v_ok:
                                        sell_sig = True
                                        
                                if buy_sig:
                                    in_pos = True
                                    pos_type = 1
                                    entry_price = c_open + spread_slip
                                    sl_price = entry_price - (sl_m * cur_atr)
                                    tp1_price = entry_price + (tp1_m * cur_atr)
                                    tp2_price = entry_price + (tp2_m * cur_atr)
                                    tp1_hit = False
                                    accum_pnl = 0.0
                                    trades_today += 1
                                elif sell_sig:
                                    in_pos = True
                                    pos_type = -1
                                    entry_price = c_open - spread_slip
                                    sl_price = entry_price + (sl_m * cur_atr)
                                    tp1_price = entry_price - (tp1_m * cur_atr)
                                    tp2_price = entry_price - (tp2_m * cur_atr)
                                    tp1_hit = False
                                    accum_pnl = 0.0
                                    trades_today += 1
                                    
                        if len(trades) >= 20:
                            t_s = pd.Series(trades)
                            wins = t_s[t_s > 0]
                            losses = t_s[t_s <= 0]
                            wr = len(wins) / len(t_s) * 100
                            gross_w = wins.sum()
                            gross_l = abs(losses.sum())
                            pf = gross_w / gross_l if gross_l > 0 else 0
                            net = t_s.sum()
                            t_per_day = len(t_s) / unique_days
                            
                            # Max Drawdown
                            cum = t_s.cumsum()
                            peak = cum.cummax()
                            dd = (peak - cum).max()
                            
                            results.append({
                                'frasson_period': p_val,
                                'shift': s,
                                'multiplier': m,
                                'tp1_mult': tp1_m,
                                'tp2_mult': tp2_m,
                                'sl_mult': sl_m,
                                'partial_ratio': part_r,
                                'trigger': trig,
                                'vol_mult': vm,
                                'trades_per_day': round(t_per_day, 2),
                                'total_trades': len(t_s),
                                'win_rate': round(wr, 2),
                                'profit_factor': round(pf, 2),
                                'net_60d_usd': round(net, 2),
                                'max_dd_usd': round(dd, 2),
                                'proj_2y_usd': round((net / unique_days) * 504.0, 2),
                                'score': round(wr * pf * np.sqrt(t_per_day), 2)
                            })

elapsed = time.time() - t0
print(f"Testadas {count} combinações em {elapsed:.2f} segundos! Sucessos encontrados: {len(results)}")

results.sort(key=lambda x: x['score'], reverse=True)
top_10 = results[:10]

with open(r'c:\Robo Virada de Delta\Robo_Frasson_Alta_Frequencia_PRO\Testes_Quantitativos\top_configs_xauusd.json', 'w') as f:
    json.dump(top_10, f, indent=4)

with open(r'c:\Robo Virada de Delta\Robo_Frasson_Alta_Frequencia_PRO\Testes_Quantitativos\all_results_xauusd.json', 'w') as f:
    json.dump(results, f, indent=4)

print("\n" + "="*85)
print("TOP 10 MELHORES CONFIGURACOES PARA XAUUSD (ORDENADAS POR SCORE GLOBAL):")
print("="*85)
for idx, r in enumerate(top_10, 1):
    print(f"\n--- TOP {idx} (Score: {r['score']}) ---")
    print(f"  Frasson ATR: Periodo={r['frasson_period']} | Deslocamento={r['shift']} | Multiplicador={r['multiplier']} | Gatilho={r['trigger']}")
    print(f"  Gestao: TP1={r['tp1_mult']}x ATR ({int(r['partial_ratio']*100)}% parcial + BE) | TP2={r['tp2_mult']}x ATR | SL={r['sl_mult']}x ATR")
    print(f"  Taxa de Acerto (Win Rate): {r['win_rate']}% | Profit Factor: {r['profit_factor']}x")
    print(f"  Frequencia: {r['trades_per_day']} trades/dia ({r['total_trades']} operacoes em {unique_days} dias)")
    print(f"  Lucro Liquido 60 Dias: ${r['net_60d_usd']} | Drawdown Maximo: ${r['max_dd_usd']}")
    print(f"  Projecao 2 Anos (504 dias): +${r['proj_2y_usd']} USD (Retorno de +{r['proj_2y_usd']/100:.1f}% sobre $10k)")

# Ranking direto por taxa de acerto entre os que tem mais de 1.5 trade/dia
high_wr = [x for x in results if x['trades_per_day'] >= 1.5 and x['profit_factor'] >= 1.2]
high_wr.sort(key=lambda x: x['win_rate'], reverse=True)

print("\n" + "="*85)
print("TOP 5 COM MAIOR TAXA DE ACERTO (WIN RATE >= 60% e FREQUENCIA >= 1.5 TRADES/DIA):")
print("="*85)
for idx, r in enumerate(high_wr[:5], 1):
    print(f"\n--- CAMPEAO ASSERTIVIDADE #{idx} ---")
    print(f"  Gatilho: {r['trigger']} | Frasson: P={r['frasson_period']} S={r['shift']} M={r['multiplier']}")
    print(f"  TP1={r['tp1_mult']}x ({int(r['partial_ratio']*100)}% + BE) | TP2={r['tp2_mult']}x | SL={r['sl_mult']}x")
    print(f"  TAXA DE ACERTO: {r['win_rate']}% | {r['trades_per_day']} trades/dia")
    print(f"  Profit Factor: {r['profit_factor']}x | Lucro 60d: ${r['net_60d_usd']} | Proj 2 Anos: +${r['proj_2y_usd']} USD")
