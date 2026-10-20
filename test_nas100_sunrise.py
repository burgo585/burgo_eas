import os
import pandas as pd
import numpy as np

def prepare_nas100_indicators(df, atr_period=14, lookback_pvsra=10, ema_fast=50, ema_slow=200):
    df = df.copy()
    df.sort_values('datetime', inplace=True)
    df.reset_index(drop=True, inplace=True)

    # Médias Móveis Exponenciais
    df['ema_fast'] = df['close'].ewm(span=ema_fast, adjust=False).mean()
    df['ema_slow'] = df['close'].ewm(span=ema_slow, adjust=False).mean()

    # ATR (True Range) com shift(1) para causalidade estrita
    prev_close = df['close'].shift(1)
    tr1 = df['high'] - df['low']
    tr2 = (df['high'] - prev_close).abs()
    tr3 = (df['low'] - prev_close).abs()
    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    df['atr'] = tr.rolling(atr_period).mean()

    # PVSRA (Price Volume Spread Analysis)
    avg_vol = df['tick_volume'].rolling(lookback_pvsra).mean()
    candle_spread = (df['close'] - df['open']).abs()
    avg_spread = candle_spread.rolling(lookback_pvsra).mean()

    cond_climax = (df['tick_volume'] >= 2.0 * avg_vol) | ((df['tick_volume'] * candle_spread) >= (2.0 * avg_vol * avg_spread))
    cond_rising = (df['tick_volume'] >= 1.5 * avg_vol) & (~cond_climax)

    df['pvsra'] = 0
    df.loc[cond_rising, 'pvsra'] = 1  # Rising
    df.loc[cond_climax, 'pvsra'] = 2  # Climax

    return df

def run_nas100_simulation(df, session_mode='ny_london', initial_balance=1000.0, risk_pct=1.0,
                          rr_ratio=2.0, sl_atr_mult=1.5, slippage_pts=10.0):
    """
    Simulação quantitativa rigorosa sem viés de antecipação:
    - Ativo: NAS100. (Cash CFD da VT Markets)
    - Digits: 2 | Point: 0.01 | 100 pts = $1.00 USD no índice
    - Lote mínimo: 0.10 | Passo: 0.10
    - Multiplicador de valor: $1.00 USD por ponto por lote cheio ($0.10 por ponto em 0.10 lote)
    - Spread real: 90 pontos ($0.90 USD) + slippage realista (10 pontos = $0.10 USD) = $1.00 USD de fricção total
    - Swap Long: -6.2353 pts/noite ($0.62 por 1.0 lote / $0.062 por 0.10 lote)
    - Swap Short: +1.2117 pts/noite ($0.12 por 1.0 lote / $0.012 por 0.10 lote)
    - Rollover triplo: Sexta-feira às 21h UTC
    """
    n = len(df)
    opens = df['open'].values
    highs = df['high'].values
    lows = df['low'].values
    closes = df['close'].values
    spreads_pts = df['spread'].values  # spread em pontos (ex: 90 pts = 0.90)
    atrs = df['atr'].values
    pvsras = df['pvsra'].values
    ema_fasts = df['ema_fast'].values
    ema_slows = df['ema_slow'].values
    dates = pd.to_datetime(df['datetime'].values)
    hours = dates.hour.values
    minutes = dates.minute.values
    dows = dates.dayofweek.values

    balance = initial_balance
    trades = []
    in_pos = False
    pos_type = 0  # 1 = Buy, -1 = Sell
    lot_size = 0.0
    entry_p = 0.0
    sl_p = 0.0
    tp_p = 0.0
    entry_idx = 0
    equity_curve = [initial_balance]
    total_swap = 0.0
    total_spread = 0.0

    for i in range(200, n - 1):
        if in_pos:
            h = highs[i]
            l = lows[i]
            exit_trade = False
            exit_p = 0.0
            outcome = ""

            if pos_type == 1:  # Compra
                hit_sl = l <= sl_p
                hit_tp = h >= tp_p
                if hit_sl and hit_tp:
                    exit_p = sl_p - (slippage_pts * 0.01)
                    outcome = "SL"
                    exit_trade = True
                elif hit_sl:
                    exit_p = sl_p - (slippage_pts * 0.01)
                    outcome = "SL"
                    exit_trade = True
                elif hit_tp:
                    exit_p = tp_p
                    outcome = "TP"
                    exit_trade = True

            elif pos_type == -1:  # Venda
                hit_sl = h >= sl_p
                hit_tp = l <= tp_p
                if hit_sl and hit_tp:
                    exit_p = sl_p + (slippage_pts * 0.01)
                    outcome = "SL"
                    exit_trade = True
                elif hit_sl:
                    exit_p = sl_p + (slippage_pts * 0.01)
                    outcome = "SL"
                    exit_trade = True
                elif hit_tp:
                    exit_p = tp_p
                    outcome = "TP"
                    exit_trade = True

            if exit_trade:
                # 1 ponto de índice = $1.00 USD por lote cheio
                price_diff = (exit_p - entry_p) if pos_type == 1 else (entry_p - exit_p)
                gross = price_diff * lot_size

                # Cálculo de Swap Overnight real
                swap = 0.0
                e_date = dates[entry_idx]
                x_date = dates[i]
                for r in pd.date_range(e_date.floor('D') + pd.Timedelta(hours=21), x_date, freq='1D'):
                    if e_date < r <= x_date:
                        days = 3 if r.dayofweek == 4 else 1  # Triplo na sexta
                        rate_pts = -6.2353 if pos_type == 1 else +1.2117
                        swap += (rate_pts * 0.01 * lot_size) * days

                net_pnl = gross + swap
                balance += net_pnl
                total_swap += swap

                trades.append({
                    'entry_date': dates[entry_idx],
                    'exit_date': dates[i],
                    'type': 'BUY' if pos_type == 1 else 'SELL',
                    'outcome': outcome,
                    'lot': lot_size,
                    'entry_price': entry_p,
                    'exit_price': exit_p,
                    'net_pnl': net_pnl,
                    'gross': gross,
                    'swap': swap,
                    'balance': balance,
                    'duration_bars': i - entry_idx
                })

                in_pos = False

        equity_curve.append(balance)

        # Checagem de Novo Sinal
        if not in_pos and not np.isnan(atrs[i]) and atrs[i] > 0:
            # Filtros de Sessão
            if dows[i] >= 5:  # Bloqueio estrito de fins de semana
                continue

            h_curr = hours[i]
            m_curr = minutes[i]

            if session_mode == 'ny_core':
                # Sessão principal de Nova York (13:30 às 20:00 UTC)
                in_sess = (13 < h_curr < 20) or (h_curr == 13 and m_curr >= 30)
                if not in_sess:
                    continue
            elif session_mode == 'ny_london':
                # Londres (8-12h UTC) e NY (14-19h UTC)
                is_london = (8 <= h_curr < 12)
                is_ny = (14 <= h_curr < 19)
                if not (is_london or is_ny):
                    continue
            elif session_mode == 'all_day':
                pass  # Dias úteis 24h

            c, o = closes[i], opens[i]
            vol_ok = pvsras[i] in [1, 2]
            trend_up = (c > ema_slows[i]) and (ema_fasts[i] > ema_slows[i])
            trend_down = (c < ema_slows[i]) and (ema_fasts[i] < ema_slows[i])

            buy_sig = trend_up and vol_ok and (c > o)
            sell_sig = trend_down and vol_ok and (c < o)

            if buy_sig or sell_sig:
                next_o = opens[i+1]
                spread_pts_val = spreads_pts[i+1] if spreads_pts[i+1] > 0 else 90.0
                spread_usd = spread_pts_val * 0.01

                sl_dist = atrs[i] * sl_atr_mult
                tp_dist = sl_dist * rr_ratio

                # Trava Spread Drag (< 5% do TP)
                if (spread_usd / tp_dist) * 100.0 > 5.0:
                    continue

                # Dimensionamento com risco de 1%
                risk_money = balance * (risk_pct / 100.0)
                # 1 ponto de índice = $1.00 USD por 1.0 lote, então risco por lote = sl_dist * 1.0
                raw_lot = risk_money / sl_dist
                # Lote mínimo 0.10, passo 0.10
                lot_size = max(0.10, min(100.0, np.floor(raw_lot / 0.10) * 0.10))

                # Trava de segurança: se lote mínimo 0.10 arrisca > 3% da conta, aborta
                actual_risk = lot_size * sl_dist
                if (actual_risk / balance) * 100.0 > 3.0:
                    continue

                total_spread += (spread_usd * lot_size)
                pos_type = 1 if buy_sig else -1
                entry_idx = i + 1

                if pos_type == 1:
                    entry_p = next_o + spread_usd + (slippage_pts * 0.01)
                    sl_p = entry_p - sl_dist
                    tp_p = entry_p + tp_dist
                else:
                    entry_p = next_o - (slippage_pts * 0.01)
                    sl_p = entry_p + sl_dist + spread_usd
                    tp_p = entry_p - tp_dist

                in_pos = True

    df_trades = pd.DataFrame(trades)
    df_equity = pd.DataFrame({'equity': equity_curve})
    return df_trades, df_equity

def compute_forensic_metrics(df_trades, df_equity, initial_capital=1000.0):
    if df_trades.empty:
        return {
            'trades': 0, 'win_rate': 0.0, 'profit_factor': 0.0,
            'total_return': 0.0, 'max_dd_pct': 0.0, 'max_dd_usd': 0.0,
            'final_balance': initial_capital, 'total_swap': 0.0,
            'tp_count': 0, 'sl_count': 0
        }

    total = len(df_trades)
    wins = df_trades[df_trades['net_pnl'] > 0]
    losses = df_trades[df_trades['net_pnl'] <= 0]

    gross_win = wins['net_pnl'].sum() if not wins.empty else 0.0
    gross_loss = abs(losses['net_pnl'].sum()) if not losses.empty else 1e-6
    pf = gross_win / gross_loss

    final_bal = df_equity['equity'].iloc[-1]
    ret_pct = ((final_bal - initial_capital) / initial_capital) * 100.0

    df_equity['peak'] = df_equity['equity'].cummax()
    df_equity['dd_pct'] = (df_equity['equity'] - df_equity['peak']) / df_equity['peak'] * 100.0
    df_equity['dd_usd'] = df_equity['peak'] - df_equity['equity']

    max_dd_pct = abs(df_equity['dd_pct'].min())
    max_dd_usd = df_equity['dd_usd'].max()

    tp_c = (df_trades['outcome'] == 'TP').sum()
    sl_c = (df_trades['outcome'] == 'SL').sum()
    total_swap = df_trades['swap'].sum()

    return {
        'trades': total,
        'win_rate': (len(wins) / total) * 100.0,
        'profit_factor': pf,
        'total_return': ret_pct,
        'max_dd_pct': max_dd_pct,
        'max_dd_usd': max_dd_usd,
        'final_balance': final_bal,
        'total_swap': total_swap,
        'tp_count': tp_c,
        'sl_count': sl_c
    }

def run_rolling_risk_of_ruin(df, session_mode='ny_london', initial_balance=1000.0):
    """
    Protocolo Sunrise: Mede a taxa de sobrevivência/ruína iniciando no dia 1º de cada mês
    ao longo de todos os meses disponíveis.
    """
    df['month_year'] = df['datetime'].dt.to_period('M')
    unique_months = df['month_year'].unique()

    ruin_count = 0
    survived_count = 0
    drawdowns = []

    for m in unique_months:
        sub = df[df['month_year'] >= m].copy().reset_index(drop=True)
        if len(sub) < 500:
            continue
        tr, eq = run_nas100_simulation(sub, session_mode=session_mode, initial_balance=initial_balance)
        if not tr.empty:
            min_bal = eq['equity'].min()
            peak = eq['equity'].cummax()
            dd = (eq['equity'] - peak) / peak * 100
            max_dd = abs(dd.min())
            drawdowns.append(max_dd)
            if min_bal < 200.0:  # 20% do saldo = Stop-Out compulsório
                ruin_count += 1
            else:
                survived_count += 1

    total_sims = ruin_count + survived_count
    ruin_pct = (ruin_count / total_sims * 100.0) if total_sims > 0 else 0.0
    avg_dd = np.mean(drawdowns) if drawdowns else 0.0
    worst_dd = max(drawdowns) if drawdowns else 0.0

    return ruin_pct, ruin_count, total_sims, avg_dd, worst_dd

if __name__ == '__main__':
    parquet_path = 'data/NAS100_M15.parquet'
    print(f"Carregando {parquet_path}...")
    df_raw = pd.read_parquet(parquet_path)
    df = prepare_nas100_indicators(df_raw)
    print(f"Total de barras preparadas: {len(df):,} barras.")
    print(f"Período: {df['datetime'].iloc[0]} até {df['datetime'].iloc[-1]}\n")

    split_date = pd.to_datetime('2026-01-01 00:00:00+00:00')
    df_is = df[df['datetime'] < split_date].copy().reset_index(drop=True)
    df_oos = df[df['datetime'] >= split_date].copy().reset_index(drop=True)

    sessions = [
        ("1. SESSÃO NOVA YORK CENTRAL (13:30 às 20:00 UTC)", 'ny_core'),
        ("2. SESSÃO LONDRES + NOVA YORK (08-12h e 14-19h UTC)", 'ny_london'),
        ("3. DIAS ÚTEIS COMPLETO (24 Horas)", 'all_day')
    ]

    print("="*105)
    print("AUDITORIA QUANTITATIVA FORENSE PROTOCOLO SUNRISE - NAS100 (CASH CFD)")
    print("="*105)

    for sess_name, sess_code in sessions:
        print(f"\n>>> {sess_name}")
        print(f"{'-'*105}")
        print(f"{'Segmento':<30} | {'Trades':<6} | {'Win Rate':<8} | {'PF':<5} | {'Max DD%':<7} | {'Retorno %':<10} | {'Saldo Final':<10}")
        print(f"{'-'*105}")

        # Total
        tr_tot, eq_tot = run_nas100_simulation(df, session_mode=sess_code)
        m_tot = compute_forensic_metrics(tr_tot, eq_tot)
        print(f"{'PERÍODO TOTAL (2024-2026)':<30} | {m_tot['trades']:<6} | {m_tot['win_rate']:<7.2f}% | {m_tot['profit_factor']:<5.2f} | {m_tot['max_dd_pct']:<6.2f}% | {m_tot['total_return']:<+9.2f}% | ${m_tot['final_balance']:<9.2f}")

        # In-Sample
        tr_is, eq_is = run_nas100_simulation(df_is, session_mode=sess_code)
        m_is = compute_forensic_metrics(tr_is, eq_is)
        print(f"{'IN-SAMPLE (2024-2025)':<30} | {m_is['trades']:<6} | {m_is['win_rate']:<7.2f}% | {m_is['profit_factor']:<5.2f} | {m_is['max_dd_pct']:<6.2f}% | {m_is['total_return']:<+9.2f}% | ${m_is['final_balance']:<9.2f}")

        # Out-of-Sample
        tr_oos, eq_oos = run_nas100_simulation(df_oos, session_mode=sess_code)
        m_oos = compute_forensic_metrics(tr_oos, eq_oos)
        print(f"{'OUT-OF-SAMPLE (2026 CEGO)':<30} | {m_oos['trades']:<6} | {m_oos['win_rate']:<7.2f}% | {m_oos['profit_factor']:<5.2f} | {m_oos['max_dd_pct']:<6.2f}% | {m_oos['total_return']:<+9.2f}% | ${m_oos['final_balance']:<9.2f}")

        # Rolling Risk of Ruin
        ruin_p, r_c, t_c, avg_d, worst_d = run_rolling_risk_of_ruin(df, session_mode=sess_code)
        print(f"    -> Risco de Ruína (Início em Meses Aleatórios): {ruin_p:.1f}% ({r_c}/{t_c} quebras)")
        print(f"    -> Pior Rebaixamento em Qualquer Mês: {worst_d:.2f}% | Rebaixamento Médio: {avg_d:.2f}%\n")
