import sys
sys.stdout.reconfigure(encoding='utf-8')
import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from datetime import datetime

term_path = r'C:\Program Files\MetaTrader 5 - Copia\terminal64.exe'
if not mt5.initialize(term_path):
    print(f"Failed to initialize MT5 at {term_path}: {mt5.last_error()}")
    sys.exit(1)

print("="*85)
print("     AUDITORIA FORENSE MULTI-ATIVO 2026: SETUP MESTRE STORMER 'TRAP NO 1-2-3'")
print("   Ativos: Mini Índice B3 (BVSPX), Nasdaq 100, Ouro (XAUUSD) e Bitcoin (BTC)")
print("   Período: 01/01/2026 a 23/10/2026 (Sem otimização, Sem dados do futuro, Dados reais)")
print("   Alvo: 2x o Risco (2R Oficial) | Stop: Mínima do Trap | Suporte a Inside Bar")
print("="*85)

symbols_cfg = {
    "Mini Índice B3 (WIN / BVSPX)": {
        "symbol": "BVSPX.s",
        "category": "B3 / Índice Brasileiro",
        "commission_round": 1.0,
        "slippage_ticks": 2,
        "b3_pts_multiplier": 0.20, # R$ 0,20 por ponto
        "b3_fees_per_trade": 1.10   # R$ 1,10 taxas B3 por mini contrato
    },
    "Nasdaq 100 (NAS100)": {
        "symbol": "NAS100.s",
        "category": "Índice Americano (Tech)",
        "commission_round": 2.0,
        "slippage_ticks": 2
    },
    "Ouro (XAUUSD)": {
        "symbol": "XAUUSD-STDc",
        "category": "Commodity / Metal Precioso",
        "commission_round": 6.0,
        "slippage_ticks": 2
    },
    "Bitcoin (BTCUSD)": {
        "symbol": "BTCUSD.c",
        "category": "Criptoativo",
        "commission_round": 6.0,
        "slippage_ticks": 2
    }
}

utc_from = datetime(2025, 8, 1) # Aquecimento dos indicadores
utc_to = datetime(2026, 10, 23, 23, 59, 59)
eval_start_date = pd.to_datetime("2026-01-01 00:00:00")

def run_trap_backtest(name, cfg, allow_sell=False, initial_balance=10000.0, risk_pct=1.0):
    sym = cfg["symbol"]
    mt5.symbol_select(sym, True)
    info = mt5.symbol_info(sym)
    if not info:
        return {"error": f"Símbolo {sym} não encontrado"}

    rates = mt5.copy_rates_range(sym, mt5.TIMEFRAME_H4, utc_from, utc_to)
    if rates is None or len(rates) < 100:
        return {"error": f"Dados insuficientes para {sym}"}

    df = pd.DataFrame(rates)
    df['time'] = pd.to_datetime(df['time'], unit='s')
    df.sort_values('time', inplace=True)
    df.reset_index(drop=True, inplace=True)

    point = info.point
    tick_size = info.trade_tick_size if info.trade_tick_size > 0 else point
    vol_min = info.volume_min
    vol_step = info.volume_step
    swap_long = info.swap_long
    swap_short = info.swap_short
    spread_val = info.spread * point
    slippage_val = cfg["slippage_ticks"] * tick_size
    comm_per_lot = cfg["commission_round"]

    # 1. Indicadores com estrito .shift(1) em barras fechadas
    df['ema70'] = df['close'].ewm(span=70, adjust=False).mean().shift(1)
    df['ema70_prev'] = df['ema70'].shift(1)

    low8 = df['low'].rolling(8).min()
    high8 = df['high'].rolling(8).max()
    fast_k = 100.0 * (df['close'] - low8) / (high8 - low8 + 1e-10)
    df['stoch_k'] = fast_k.rolling(3).mean().shift(1)
    df['stoch_oversold'] = (df['stoch_k'] < 20.0).rolling(10).max() == 1.0
    df['stoch_overbought'] = (df['stoch_k'] > 80.0).rolling(10).max() == 1.0

    # 2. Loop de Simulação Causal de Trap
    balance = initial_balance
    peak_equity = initial_balance
    max_dd_usd = 0.0
    max_dd_pct = 0.0

    position = None # Ordem em mercado aberta
    pending_order = None # Ordem Buy Stop / Sell Stop armada aguardando rompimento
    trades_log = []
    total_commission = 0.0
    total_swap = 0.0
    total_gross_profit = 0.0
    total_gross_loss = 0.0
    total_points = 0.0

    start_idx = df[df['time'] >= eval_start_date].index[0]

    for i in range(start_idx, len(df)):
        row = df.iloc[i]

        # A. Gerenciamento de Posição Aberta
        if position is not None:
            bar_swap = (swap_long if position['type'] == 'BUY' else swap_short) * position['lot'] / 6.0
            total_swap += bar_swap
            balance += bar_swap

            p_type = position['type']
            lot = position['lot']
            sl = position['sl']
            tp = position['tp']
            entry = position['entry_price']

            hit_sl = False
            hit_tp = False

            if p_type == 'BUY':
                if row['low'] <= sl:
                    hit_sl = True
                elif row['high'] >= tp:
                    hit_tp = True

                if hit_sl:
                    exit_price = sl - slippage_val
                    pts = exit_price - entry
                    total_points += pts
                    pnl = mt5.order_calc_profit(mt5.ORDER_TYPE_BUY, sym, lot, entry, exit_price) or (pts * lot)
                    balance += pnl
                    total_gross_loss += abs(pnl)
                    trades_log.append({
                        "type": "BUY",
                        "entry_time": str(position['entry_time']),
                        "exit_time": str(row['time']),
                        "entry": round(entry, info.digits),
                        "exit": round(exit_price, info.digits),
                        "points": round(pts, 2),
                        "result": "LOSS (SL)",
                        "pnl_usd": round(pnl, 2),
                        "lot": lot
                    })
                    position = None
                elif hit_tp:
                    exit_price = tp # Sem teletransporte de pavio
                    pts = exit_price - entry
                    total_points += pts
                    pnl = mt5.order_calc_profit(mt5.ORDER_TYPE_BUY, sym, lot, entry, exit_price) or (pts * lot)
                    balance += pnl
                    total_gross_profit += pnl
                    trades_log.append({
                        "type": "BUY",
                        "entry_time": str(position['entry_time']),
                        "exit_time": str(row['time']),
                        "entry": round(entry, info.digits),
                        "exit": round(exit_price, info.digits),
                        "points": round(pts, 2),
                        "result": "WIN (TP 2R)",
                        "pnl_usd": round(pnl, 2),
                        "lot": lot
                    })
                    position = None
                else:
                    curr_p = row['close']
                    fpnl = mt5.order_calc_profit(mt5.ORDER_TYPE_BUY, sym, lot, entry, curr_p) or 0.0
                    ceq = balance + fpnl
                    if ceq > peak_equity: peak_equity = ceq
                    cdd = peak_equity - ceq
                    if cdd > max_dd_usd:
                        max_dd_usd = cdd
                        max_dd_pct = (max_dd_usd / peak_equity) * 100.0

            elif p_type == 'SELL':
                if row['high'] >= sl:
                    hit_sl = True
                elif row['low'] <= tp:
                    hit_tp = True

                if hit_sl:
                    exit_price = sl + slippage_val
                    pts = entry - exit_price
                    total_points += pts
                    pnl = mt5.order_calc_profit(mt5.ORDER_TYPE_SELL, sym, lot, entry, exit_price) or (pts * lot)
                    balance += pnl
                    total_gross_loss += abs(pnl)
                    trades_log.append({
                        "type": "SELL",
                        "entry_time": str(position['entry_time']),
                        "exit_time": str(row['time']),
                        "entry": round(entry, info.digits),
                        "exit": round(exit_price, info.digits),
                        "points": round(pts, 2),
                        "result": "LOSS (SL)",
                        "pnl_usd": round(pnl, 2),
                        "lot": lot
                    })
                    position = None
                elif hit_tp:
                    exit_price = tp
                    pts = entry - exit_price
                    total_points += pts
                    pnl = mt5.order_calc_profit(mt5.ORDER_TYPE_SELL, sym, lot, entry, exit_price) or (pts * lot)
                    balance += pnl
                    total_gross_profit += pnl
                    trades_log.append({
                        "type": "SELL",
                        "entry_time": str(position['entry_time']),
                        "exit_time": str(row['time']),
                        "entry": round(entry, info.digits),
                        "exit": round(exit_price, info.digits),
                        "points": round(pts, 2),
                        "result": "WIN (TP 2R)",
                        "pnl_usd": round(pnl, 2),
                        "lot": lot
                    })
                    position = None
                else:
                    curr_p = row['close']
                    fpnl = mt5.order_calc_profit(mt5.ORDER_TYPE_SELL, sym, lot, entry, curr_p) or 0.0
                    ceq = balance + fpnl
                    if ceq > peak_equity: peak_equity = ceq
                    cdd = peak_equity - ceq
                    if cdd > max_dd_usd:
                        max_dd_usd = cdd
                        max_dd_pct = (max_dd_usd / peak_equity) * 100.0

        # B. Gerenciamento de Ordem Pendente Armada
        if position is None and pending_order is not None:
            # Verifica se o candle atual ativou a ordem pendente
            p_ord = pending_order
            if p_ord['type'] == 'BUY_STOP':
                # Checa cancelamento por quebra do fundo (invalidação)
                if row['low'] <= p_ord['sl']:
                    pending_order = None # Cancelada por quebra de fundo
                # Checa ativação
                elif row['high'] >= p_ord['trigger']:
                    entry_p = p_ord['trigger'] + spread_val + slippage_val
                    position = {
                        "type": "BUY",
                        "entry_price": entry_p,
                        "sl": p_ord['sl'],
                        "tp": p_ord['tp'],
                        "lot": p_ord['lot'],
                        "entry_time": row['time']
                    }
                    balance -= (p_ord['lot'] * comm_per_lot)
                    total_commission += (p_ord['lot'] * comm_per_lot)
                    pending_order = None
                # Checa expiração (6 candles)
                elif i - p_ord['placed_idx'] >= 6:
                    pending_order = None

            elif p_ord['type'] == 'SELL_STOP':
                if row['high'] >= p_ord['sl']:
                    pending_order = None
                elif row['low'] <= p_ord['trigger']:
                    entry_p = p_ord['trigger'] - slippage_val
                    position = {
                        "type": "SELL",
                        "entry_price": entry_p,
                        "sl": p_ord['sl'],
                        "tp": p_ord['tp'],
                        "lot": p_ord['lot'],
                        "entry_time": row['time']
                    }
                    balance -= (p_ord['lot'] * comm_per_lot)
                    total_commission += (p_ord['lot'] * comm_per_lot)
                    pending_order = None
                elif i - p_ord['placed_idx'] >= 6:
                    pending_order = None

        # C. Identificação de Novo Setup Trap na Abertura do Candle
        if position is None and pending_order is None:
            # 1. COMPRA: Trap no Fundo do 1-2-3
            ema_subindo = (row['ema70'] > row['ema70_prev']) and (df['close'].iloc[i-1] >= row['ema70'])
            stoch_ok = row['stoch_oversold']

            if ema_subindo and stoch_ok:
                # Verifica se a barra i-1 foi um Trap (perdeu a mínima do fundo anterior)
                # O fundo anterior formado entre as barras i-2 e i-7
                prior_lows = [df['low'].iloc[i-k] for k in range(2, 7)]
                min_prior_low = min(prior_lows)
                trap_low = df['low'].iloc[i-1]
                trap_high = df['high'].iloc[i-1]

                # Suporte a Inside Bar: se a barra i-1 foi inside bar da barra i-2, e i-2 foi o trap
                is_inside = (df['high'].iloc[i-1] <= df['high'].iloc[i-2]) and (df['low'].iloc[i-1] >= df['low'].iloc[i-2])
                if is_inside:
                    prior_lows_ib = [df['low'].iloc[i-k] for k in range(3, 8)]
                    min_prior_ib = min(prior_lows_ib)
                    if df['low'].iloc[i-2] < min_prior_ib:
                        trap_low = df['low'].iloc[i-2]
                        trap_high = df['high'].iloc[i-2]

                if trap_low < min_prior_low:
                    # Trap confirmado!
                    trigger_p = trap_high
                    sl_p = trap_low - (50 * point)
                    risk_d = trigger_p - sl_p
                    tp_p = trigger_p + (2.0 * risk_d) # Alvo 2R Oficial Stormer

                    if risk_d > 0:
                        # Risco real estimado com spread e slippage
                        est_entry = trigger_p + spread_val + slippage_val
                        est_sl = sl_p - slippage_val
                        real_risk_d = est_entry - est_sl

                        risk_usd = balance * (risk_pct / 100.0)
                        loss_1lot = abs(mt5.order_calc_profit(mt5.ORDER_TYPE_BUY, sym, 1.0, est_entry, est_sl) or (real_risk_d * 1.0))
                        calc_lot = (risk_usd / loss_1lot) if loss_1lot > 0 else vol_min
                        lot = max(vol_min, round(np.floor(calc_lot / vol_step) * vol_step, 2))

                        # Arma ordem Buy Stop
                        pending_order = {
                            "type": "BUY_STOP",
                            "trigger": trigger_p,
                            "sl": sl_p,
                            "tp": tp_p,
                            "lot": lot,
                            "placed_idx": i,
                            "time": row['time']
                        }

            # 2. VENDA: Trap no Topo do 1-2-3 (Modo Bidirecional)
            if allow_sell and pending_order is None:
                ema_descendo = (row['ema70'] < row['ema70_prev']) and (df['close'].iloc[i-1] <= row['ema70'])
                stoch_overb = row['stoch_overbought']

                if ema_descendo and stoch_overb:
                    prior_highs = [df['high'].iloc[i-k] for k in range(2, 7)]
                    max_prior_high = max(prior_highs)
                    trap_high = df['high'].iloc[i-1]
                    trap_low = df['low'].iloc[i-1]

                    is_inside = (df['high'].iloc[i-1] <= df['high'].iloc[i-2]) and (df['low'].iloc[i-1] >= df['low'].iloc[i-2])
                    if is_inside:
                        prior_highs_ib = [df['high'].iloc[i-k] for k in range(3, 8)]
                        max_prior_ib = max(prior_highs_ib)
                        if df['high'].iloc[i-2] > max_prior_ib:
                            trap_high = df['high'].iloc[i-2]
                            trap_low = df['low'].iloc[i-2]

                    if trap_high > max_prior_high:
                        trigger_p = trap_low
                        sl_p = trap_high + (50 * point)
                        risk_d = sl_p - trigger_p
                        tp_p = trigger_p - (2.0 * risk_d) # Alvo 2R

                        if risk_d > 0:
                            est_entry = trigger_p - slippage_val
                            est_sl = sl_p + spread_val + slippage_val
                            real_risk_d = est_sl - est_entry

                            risk_usd = balance * (risk_pct / 100.0)
                            loss_1lot = abs(mt5.order_calc_profit(mt5.ORDER_TYPE_SELL, sym, 1.0, est_entry, est_sl) or (real_risk_d * 1.0))
                            calc_lot = (risk_usd / loss_1lot) if loss_1lot > 0 else vol_min
                            lot = max(vol_min, round(np.floor(calc_lot / vol_step) * vol_step, 2))

                            pending_order = {
                                "type": "SELL_STOP",
                                "trigger": trigger_p,
                                "sl": sl_p,
                                "tp": tp_p,
                                "lot": lot,
                                "placed_idx": i,
                                "time": row['time']
                            }

    n_trades = len(trades_log)
    wins = len([t for t in trades_log if "WIN" in t["result"]])
    losses = len([t for t in trades_log if "LOSS" in t["result"]])
    win_rate = (wins / n_trades * 100.0) if n_trades > 0 else 0.0
    pf = (total_gross_profit / total_gross_loss) if total_gross_loss > 0 else 999.0
    net_pnl = balance - initial_balance

    b3_net_brl = 0.0
    if "b3_pts_multiplier" in cfg:
        gross_brl = total_points * cfg["b3_pts_multiplier"]
        fees_brl = n_trades * cfg["b3_fees_per_trade"]
        b3_net_brl = gross_brl - fees_brl

    return {
        "asset_name": name,
        "symbol": sym,
        "mode": "BUY_ONLY" if not allow_sell else "BIDIRECTIONAL",
        "total_trades": n_trades,
        "wins": wins,
        "losses": losses,
        "win_rate": win_rate,
        "profit_factor": pf,
        "total_points": total_points,
        "b3_net_brl": b3_net_brl,
        "net_pnl_usd": net_pnl,
        "gross_profit_usd": total_gross_profit,
        "gross_loss_usd": total_gross_loss,
        "max_dd_usd": max_dd_usd,
        "max_dd_pct": max_dd_pct,
        "total_commission": total_commission,
        "total_swap": total_swap,
        "final_balance": balance,
        "trades": trades_log
    }

all_results = []
for k, cfg in symbols_cfg.items():
    r_buy = run_trap_backtest(k, cfg, allow_sell=False)
    all_results.append(r_buy)
    r_both = run_trap_backtest(k, cfg, allow_sell=True)
    all_results.append(r_both)

mt5.shutdown()

print("\n" + "="*95)
print("             TABELA FORENSE: SETUP STORMER 'TRAP NO 1-2-3' - ANO 2026")
print("="*95)
print(f"{'Ativo':<28} | {'Modo':<13} | {'Trades':<6} | {'Win%':<6} | {'Pontos':<10} | {'Lucro Líq ($)':<13} | {'PF':<5} | {'MaxDD (%)':<9}")
print("-"*95)
for r in all_results:
    if "error" in r:
        print(f"{r.get('asset_name','?'):<28} | ERRO: {r['error']}")
    else:
        print(f"{r['asset_name']:<28} | {r['mode']:<13} | {r['total_trades']:<6} | {r['win_rate']:<5.1f}% | {r['total_points']:<10.1f} | ${r['net_pnl_usd']:<12.2f} | {r['profit_factor']:<5.2f} | {r['max_dd_pct']:<8.2f}%")

# Save detailed JSON
import json
with open(r"C:\Users\Vini_Burgo\.gemini\antigravity\brain\2cceb840-74c7-470b-9b9c-da2793fd84da\scratch\trap_2026_results.json", "w", encoding="utf-8") as f:
    json.dump(all_results, f, indent=2, ensure_ascii=False)

print("\nResultados salvos com sucesso em trap_2026_results.json.")
