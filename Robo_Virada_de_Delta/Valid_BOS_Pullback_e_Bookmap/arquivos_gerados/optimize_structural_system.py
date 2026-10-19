# -*- coding: utf-8 -*-
"""
optimize_structural_system.py
Simulador e Otimizador Profundo de Estrutura Institucional (Video 'Nunca Pensei Em Quebrar A Estrutura Dessa Forma')
Analisa 2 anos completos (2024-2026) em M1, M5, M15, M30, H1 no XAUUSD-STDc (VT Markets).
"""

import sys
sys.stdout.reconfigure(encoding='utf-8')

import numpy as np
import pandas as pd
from datetime import datetime
import MetaTrader5 as mt5

TERMINAL_PATH = r"C:\Program Files\MetaTrader 5 - Copia\terminal64.exe"
SYMBOL = "XAUUSD-STDc"

def calculate_ema(prices, period):
    return pd.Series(prices).ewm(span=period, adjust=False).mean().to_numpy(copy=True)

def calculate_adx(high, low, close, period=14):
    n = len(close)
    if n < period * 2:
        return np.full(n, 25.0)
    
    tr = np.zeros(n)
    tr[0] = high[0] - low[0]
    for i in range(1, n):
        tr[i] = max(high[i] - low[i], abs(high[i] - close[i-1]), abs(low[i] - close[i-1]))
    
    plus_dm = np.zeros(n)
    minus_dm = np.zeros(n)
    for i in range(1, n):
        up_move = high[i] - high[i-1]
        down_move = low[i-1] - low[i]
        if up_move > down_move and up_move > 0:
            plus_dm[i] = up_move
        if down_move > up_move and down_move > 0:
            minus_dm[i] = down_move
            
    tr_s = pd.Series(tr).ewm(alpha=1.0/period, adjust=False).mean().to_numpy(copy=True)
    plus_dm_s = pd.Series(plus_dm).ewm(alpha=1.0/period, adjust=False).mean().to_numpy(copy=True)
    minus_dm_s = pd.Series(minus_dm).ewm(alpha=1.0/period, adjust=False).mean().to_numpy(copy=True)
    
    tr_s = np.where(tr_s == 0, 1e-5, tr_s)
    plus_di = 100.0 * (plus_dm_s / tr_s)
    minus_di = 100.0 * (minus_dm_s / tr_s)
    
    sum_di = plus_di + minus_di
    sum_di = np.where(sum_di == 0, 1e-5, sum_di)
    dx = 100.0 * np.abs(plus_di - minus_di) / sum_di
    adx = pd.Series(dx).ewm(alpha=1.0/period, adjust=False).mean().to_numpy(copy=True)
    return adx

def simulate_structural_strategy(df, params):
    pivot_legs = params.get('pivot_legs', 3)
    min_exp_bars = params.get('min_exp_bars', 2)
    max_struct_bars = params.get('max_struct_bars', 40)
    tol_pts = params.get('tol_pts', 150) # em centavos (150 = $1.50)
    max_retrace_pct = params.get('max_retrace_pct', 0.618) # 61.8% Golden Pocket
    entry_mode = params.get('entry_mode', 'REJECTION') # 'REJECTION' ou 'BOS'
    use_ema = params.get('use_ema', True)
    use_adx = params.get('use_adx', True)
    min_adx = params.get('min_adx', 20.0)
    rr_ratio = params.get('rr_ratio', 2.0)
    use_partial = params.get('use_partial', True)
    use_be = params.get('use_be', True)
    sl_buffer = params.get('sl_buffer', 50) # 50 pts = $0.50
    min_sl = params.get('min_sl', 150) # 150 pts = $1.50
    spread_pts = 28 # $0.28 de spread real da VT Markets

    point = 0.01

    opens = df['open'].values
    highs = df['high'].values
    lows = df['low'].values
    closes = df['close'].values
    n = len(closes)

    ema = calculate_ema(closes, 200) if use_ema else np.zeros(n)
    adx = calculate_adx(highs, lows, closes, 14) if use_adx else np.full(n, 25.0)

    swings = []
    structures = []
    trades = []
    active_trade = None

    cur_high = 0.0
    cur_low = 0.0

    for i in range(pivot_legs * 2 + 1, n):
        # 1. Gerenciar Trade Ativo com Spread Real
        if active_trade is not None:
            cur_hi = highs[i]
            cur_lo = lows[i]
            t_dir = active_trade['dir']
            t_entry = active_trade['entry']
            t_sl = active_trade['sl']
            t_tp = active_trade['tp']
            t_risk = active_trade['risk']

            closed = False
            pnl_r = 0.0

            if t_dir == 1: # COMPRA
                # BE em 1R
                if not active_trade['be_done'] and cur_hi >= (t_entry + t_risk):
                    active_trade['be_done'] = True
                    if use_be:
                        active_trade['sl'] = t_entry + (spread_pts * point)
                    if use_partial:
                        active_trade['partial_taken'] = True

                if cur_lo <= active_trade['sl']:
                    exit_p = active_trade['sl']
                    if active_trade.get('partial_taken', False):
                        pnl_r = (+1.0 * 0.5) + (((exit_p - t_entry) / t_risk) * 0.5)
                    else:
                        pnl_r = (exit_p - t_entry) / t_risk
                    closed = True
                elif cur_hi >= t_tp:
                    exit_p = t_tp
                    if active_trade.get('partial_taken', False):
                        pnl_r = (+1.0 * 0.5) + (((exit_p - t_entry) / t_risk) * 0.5)
                    else:
                        pnl_r = (exit_p - t_entry) / t_risk
                    closed = True

            elif t_dir == -1: # VENDA
                if not active_trade['be_done'] and cur_lo <= (t_entry - t_risk):
                    active_trade['be_done'] = True
                    if use_be:
                        active_trade['sl'] = t_entry - (spread_pts * point)
                    if use_partial:
                        active_trade['partial_taken'] = True

                if cur_hi >= active_trade['sl']:
                    exit_p = active_trade['sl']
                    if active_trade.get('partial_taken', False):
                        pnl_r = (+1.0 * 0.5) + (((t_entry - exit_p) / t_risk) * 0.5)
                    else:
                        pnl_r = (t_entry - exit_p) / t_risk
                    closed = True
                elif cur_lo <= t_tp:
                    exit_p = t_tp
                    if active_trade.get('partial_taken', False):
                        pnl_r = (+1.0 * 0.5) + (((t_entry - exit_p) / t_risk) * 0.5)
                    else:
                        pnl_r = (t_entry - exit_p) / t_risk
                    closed = True

            if closed:
                active_trade['pnl_r'] = pnl_r
                trades.append(active_trade)
                active_trade = None

        # 2. Pivôs de Swing
        p_idx = i - pivot_legs
        if p_idx >= pivot_legs:
            # High
            is_h = True
            for k in range(p_idx - pivot_legs, p_idx + pivot_legs + 1):
                if k != p_idx and highs[k] >= highs[p_idx]:
                    is_h = False
                    break
            if is_h and highs[p_idx] != cur_high:
                cur_high = highs[p_idx]
                swings.append({'dir': 1, 'price': highs[p_idx], 'idx': p_idx, 'broken': False})
                if len(swings) > 40: swings.pop(0)

            # Low
            is_l = True
            for k in range(p_idx - pivot_legs, p_idx + pivot_legs + 1):
                if k != p_idx and lows[k] <= lows[p_idx]:
                    is_l = False
                    break
            if is_l and lows[p_idx] != cur_low:
                cur_low = lows[p_idx]
                swings.append({'dir': -1, 'price': lows[p_idx], 'idx': p_idx, 'broken': False})
                if len(swings) > 40: swings.pop(0)

        # 3. Rompimentos de Swing
        for sw in swings:
            if sw['broken'] or i <= sw['idx']: continue
            if sw['dir'] == 1:
                if closes[i] > sw['price'] and closes[i-1] <= sw['price']:
                    sw['broken'] = True
                    if not use_ema or closes[i] > ema[i]:
                        structures.append({
                            'dir': 1, 'state': 'EXPANDING', 'b_idx': i,
                            'ref': sw['price'], 'ext': highs[i], 'pb_ext': 0.0,
                            'active': True, 'triggered': False
                        })
                        if len(structures) > 25: structures.pop(0)
            elif sw['dir'] == -1:
                if closes[i] < sw['price'] and closes[i-1] >= sw['price']:
                    sw['broken'] = True
                    if not use_ema or closes[i] < ema[i]:
                        structures.append({
                            'dir': -1, 'state': 'EXPANDING', 'b_idx': i,
                            'ref': sw['price'], 'ext': lows[i], 'pb_ext': 0.0,
                            'active': True, 'triggered': False
                        })
                        if len(structures) > 25: structures.pop(0)

        # 4. Atualizar Estruturas e Reteste Institucional
        tol = tol_pts * point
        for st in structures:
            if not st['active']: continue

            # === BULLISH ===
            if st['dir'] == 1:
                if st['state'] == 'EXPANDING':
                    if highs[i] > st['ext']: st['ext'] = highs[i]
                    bars = i - st['b_idx']
                    if bars >= min_exp_bars:
                        st['state'] = 'QUALIFIED'
                    if bars > max_struct_bars:
                        st['active'] = False
                        continue

                if st['state'] == 'QUALIFIED':
                    if highs[i] > st['ext']: st['ext'] = highs[i]
                    bars = i - st['b_idx']
                    exp_h = st['ext'] - st['ref']
                    if exp_h <= 0: continue

                    # Zona de Reteste Institucional:
                    # Topo rompid + tolerância até o nível de desconto (máx 61.8% da expansão)
                    upper_zone = st['ref'] + tol
                    lower_zone = st['ref'] - (exp_h * max_retrace_pct)

                    # Se o preço tocou na zona de reteste
                    if lows[i] <= upper_zone and closes[i] >= lower_zone:
                        st['state'] = 'IN_PULLBACK'
                        st['pb_ext'] = lows[i]

                        # Entrada Rejeição Price Action na Zona
                        if entry_mode == 'REJECTION' and not st['triggered'] and active_trade is None:
                            trend_ok = (not use_ema) or (closes[i] > ema[i])
                            adx_ok = (not use_adx) or (adx[i] >= min_adx)
                            # Rejeição: pavio inferior ou candle de alta
                            rng = highs[i] - lows[i]
                            wick = min(opens[i], closes[i]) - lows[i]
                            rej_ok = (rng > 0) and ((wick / rng >= 0.25) or (closes[i] > opens[i]))

                            if trend_ok and adx_ok and rej_ok:
                                st['triggered'] = True
                                entry = closes[i]
                                raw_sl = lows[i] - (sl_buffer * point)
                                sl_dist = max(entry - raw_sl, min_sl * point)
                                sl = entry - sl_dist
                                tp = entry + (sl_dist * rr_ratio)
                                active_trade = {
                                    'dir': 1, 'entry': entry, 'sl': sl, 'tp': tp,
                                    'risk': sl_dist, 'be_done': False, 'partial_taken': False
                                }
                    elif closes[i] < lower_zone or bars > max_struct_bars:
                        st['active'] = False
                        continue

                elif st['state'] == 'IN_PULLBACK':
                    if lows[i] < st['pb_ext']: st['pb_ext'] = lows[i]
                    bars = i - st['b_idx']
                    exp_h = st['ext'] - st['ref']
                    lower_zone = st['ref'] - (exp_h * max_retrace_pct)

                    if closes[i] < lower_zone or bars > max_struct_bars:
                        st['active'] = False
                        continue

                    # Entrada Valid BOS (rompe a máxima da perna de expansão)
                    if closes[i] > st['ext']:
                        if entry_mode == 'BOS' and not st['triggered'] and active_trade is None:
                            trend_ok = (not use_ema) or (closes[i] > ema[i])
                            adx_ok = (not use_adx) or (adx[i] >= min_adx)
                            if trend_ok and adx_ok:
                                st['triggered'] = True
                                entry = closes[i]
                                raw_sl = st['pb_ext'] - (sl_buffer * point)
                                sl_dist = max(entry - raw_sl, min_sl * point)
                                sl = entry - sl_dist
                                tp = entry + (sl_dist * rr_ratio)
                                active_trade = {
                                    'dir': 1, 'entry': entry, 'sl': sl, 'tp': tp,
                                    'risk': sl_dist, 'be_done': False, 'partial_taken': False
                                }
                        st['active'] = False

            # === BEARISH ===
            elif st['dir'] == -1:
                if st['state'] == 'EXPANDING':
                    if lows[i] < st['ext']: st['ext'] = lows[i]
                    bars = i - st['b_idx']
                    if bars >= min_exp_bars:
                        st['state'] = 'QUALIFIED'
                    if bars > max_struct_bars:
                        st['active'] = False
                        continue

                if st['state'] == 'QUALIFIED':
                    if lows[i] < st['ext']: st['ext'] = lows[i]
                    bars = i - st['b_idx']
                    exp_h = st['ref'] - st['ext']
                    if exp_h <= 0: continue

                    lower_zone = st['ref'] - tol
                    upper_zone = st['ref'] + (exp_h * max_retrace_pct)

                    if highs[i] >= lower_zone and closes[i] <= upper_zone:
                        st['state'] = 'IN_PULLBACK'
                        st['pb_ext'] = highs[i]

                        if entry_mode == 'REJECTION' and not st['triggered'] and active_trade is None:
                            trend_ok = (not use_ema) or (closes[i] < ema[i])
                            adx_ok = (not use_adx) or (adx[i] >= min_adx)
                            rng = highs[i] - lows[i]
                            wick = highs[i] - max(opens[i], closes[i])
                            rej_ok = (rng > 0) and ((wick / rng >= 0.25) or (closes[i] < opens[i]))

                            if trend_ok and adx_ok and rej_ok:
                                st['triggered'] = True
                                entry = closes[i]
                                raw_sl = highs[i] + (sl_buffer * point)
                                sl_dist = max(raw_sl - entry, min_sl * point)
                                sl = entry + sl_dist
                                tp = entry - (sl_dist * rr_ratio)
                                active_trade = {
                                    'dir': -1, 'entry': entry, 'sl': sl, 'tp': tp,
                                    'risk': sl_dist, 'be_done': False, 'partial_taken': False
                                }
                    elif closes[i] > upper_zone or bars > max_struct_bars:
                        st['active'] = False
                        continue

                elif st['state'] == 'IN_PULLBACK':
                    if highs[i] > st['pb_ext']: st['pb_ext'] = highs[i]
                    bars = i - st['b_idx']
                    exp_h = st['ref'] - st['ext']
                    upper_zone = st['ref'] + (exp_h * max_retrace_pct)

                    if closes[i] > upper_zone or bars > max_struct_bars:
                        st['active'] = False
                        continue

                    if closes[i] < st['ext']:
                        if entry_mode == 'BOS' and not st['triggered'] and active_trade is None:
                            trend_ok = (not use_ema) or (closes[i] < ema[i])
                            adx_ok = (not use_adx) or (adx[i] >= min_adx)
                            if trend_ok and adx_ok:
                                st['triggered'] = True
                                entry = closes[i]
                                raw_sl = st['pb_ext'] + (sl_buffer * point)
                                sl_dist = max(raw_sl - entry, min_sl * point)
                                sl = entry + sl_dist
                                tp = entry - (sl_dist * rr_ratio)
                                active_trade = {
                                    'dir': -1, 'entry': entry, 'sl': sl, 'tp': tp,
                                    'risk': sl_dist, 'be_done': False, 'partial_taken': False
                                }
                        st['active'] = False

    return trades

def evaluate_metrics(trades, initial_deposit=10000.0, risk_pct=1.0):
    if not trades:
        return {'trades': 0, 'win_rate': 0.0, 'pf': 0.0, 'net_profit': 0.0, 'net_pct': 0.0, 'max_dd': 0.0}
    total = len(trades)
    wins = [t for t in trades if t['pnl_r'] > 0]
    losses = [t for t in trades if t['pnl_r'] <= 0]
    win_rate = (len(wins) / total) * 100.0
    gross_win = sum(t['pnl_r'] for t in wins)
    gross_loss = abs(sum(t['pnl_r'] for t in losses))
    pf = (gross_win / gross_loss) if gross_loss > 0 else 99.0

    balance = initial_deposit
    peak = balance
    max_dd = 0.0
    risk_usd = initial_deposit * (risk_pct / 100.0)
    for t in trades:
        balance += t['pnl_r'] * risk_usd
        if balance > peak: peak = balance
        dd = (peak - balance) / peak * 100.0 if peak > 0 else 0.0
        if dd > max_dd: max_dd = dd

    net = balance - initial_deposit
    net_pct = (net / initial_deposit) * 100.0
    return {
        'trades': total, 'win_rate': win_rate, 'pf': pf,
        'net_profit': net, 'net_pct': net_pct, 'max_dd': max_dd
    }

def main():
    print("=" * 90)
    print(" CARREGANDO DADOS HISTÓRICOS DE 2 ANOS DO MT5 VT MARKETS...")
    print("=" * 90)

    if not mt5.initialize(path=TERMINAL_PATH):
        print("Erro MT5:", mt5.last_error())
        return

    data = {}
    for tf_str, tf_code in [('M5', mt5.TIMEFRAME_M5), ('M15', mt5.TIMEFRAME_M15), ('M30', mt5.TIMEFRAME_M30), ('H1', mt5.TIMEFRAME_H1)]:
        rates = mt5.copy_rates_from_pos(SYMBOL, tf_code, 0, 50000)
        if rates is not None and len(rates) > 100:
            df = pd.DataFrame(rates)
            df['datetime'] = pd.to_datetime(df['time'], unit='s')
            data[tf_str] = df
            print(f" {tf_str:>4}: {len(df):>6} barras | De {df['datetime'].iloc[0].strftime('%Y-%m-%d')} ate {df['datetime'].iloc[-1].strftime('%Y-%m-%d')}")
    mt5.shutdown()

    # GRADE DE TESTES ESTRUTURAIS INSTITUCIONAIS
    print("\n" + "=" * 115)
    print(f"{'TF':<5} | {'GATILHO':<10} | {'PIVÔ':<5} | {'TOL':<6} | {'R:R':<5} | {'PARCIAL':<8} | {'TRADES':<7} | {'WIN%':<7} | {'PF':<6} | {'LUCRO ($)':<11} | {'LUCRO %':<8} | {'MAX DD%':<8}")
    print("=" * 115)

    all_results = []
    # Testar combinações inteligentes
    for tf in ['M5', 'M15', 'M30', 'H1']:
        if tf not in data: continue
        df = data[tf]

        # Configurações de tolerância proporcionais ao timeframe
        tol_options = [100, 200, 350] if tf in ['M5', 'M15'] else [200, 400, 600]
        
        for entry_m in ['REJECTION', 'BOS']:
            for piv in [3, 5]:
                for tol in tol_options:
                    for rr in [1.5, 2.0, 3.0]:
                        for part in [True, False]:
                            p = {
                                'pivot_legs': piv,
                                'min_exp_bars': 2 if piv == 3 else 3,
                                'max_struct_bars': 40,
                                'tol_pts': tol,
                                'max_retrace_pct': 0.618,
                                'entry_mode': entry_m,
                                'use_ema': True,
                                'use_adx': True,
                                'min_adx': 20.0,
                                'rr_ratio': rr,
                                'use_partial': part,
                                'use_be': True,
                                'sl_buffer': 50,
                                'min_sl': 150 if tf in ['M5', 'M15'] else 250
                            }
                            tr = simulate_structural_strategy(df, p)
                            m = evaluate_metrics(tr, initial_deposit=10000.0, risk_pct=1.0)
                            
                            # Filtrar apenas resultados com amostra estatística confiável (mínimo 15 trades)
                            if m['trades'] >= 15:
                                res_item = {
                                    'tf': tf, 'entry': entry_m, 'piv': piv, 'tol': tol,
                                    'rr': rr, 'part': part, 'trades': m['trades'],
                                    'win_rate': m['win_rate'], 'pf': m['pf'],
                                    'net': m['net_profit'], 'net_pct': m['net_pct'],
                                    'dd': m['max_dd']
                                }
                                all_results.append(res_item)
                                if m['pf'] >= 1.3 and m['net_profit'] > 0:
                                    part_str = "SIM (1:1)" if part else "NÃO (Seco)"
                                    print(f"{tf:<5} | {entry_m:<10} | {piv:<5} | {tol:<6} | 1:{rr:<3.1f} | {part_str:<8} | {m['trades']:<7} | {m['win_rate']:>5.1f}% | {m['pf']:>5.2f} | ${m['net_profit']:>9.2f} | {m['net_pct']:>6.1f}% | {m['max_dd']:>6.2f}%")

    print("=" * 115)

    if all_results:
        df_res = pd.DataFrame(all_results)
        # Ordenar pelos maiores Profit Factors com consistência
        df_res = df_res[df_res['trades'] >= 25]
        if not df_res.empty:
            df_sorted = df_res.sort_values(by=['pf', 'net'], ascending=False)
            print("\n" + ">>> RANKING OFICIAL DAS MELHORES CONFIGURACOES INSTITUCIONAIS <<<")
            for rank, (_, row) in enumerate(df_sorted.head(5).iterrows(), 1):
                part_label = "COM Parcial 50% em 1:1 + Break-Even" if row['part'] else "SEM Parcial (Alvo Total)"
                print(f" [#{rank}] TIMEFRAME: {row['tf']} | GATILHO: {row['entry']} | PIVÔ: {row['piv']} | TOLERÂNCIA: {row['tol']} pts ($ {row['tol']*0.01:.2f})")
                print(f"       Relação R:R: 1:{row['rr']} | Gestão: {part_label}")
                print(f"       Total de Operações: {row['trades']} | Taxa de Acerto: {row['win_rate']:.1f}%")
                print(f"       Fator de Lucro (Profit Factor): {row['pf']:.2f}")
                print(f"       Lucro Líquido: ${row['net']:.2f} (+{row['net_pct']:.1f}%) | Drawdown Máximo: {row['dd']:.2f}%\n")

if __name__ == '__main__':
    main()
