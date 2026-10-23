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

print("="*80)
print("     AUDITORIA FORENSE MULTI-ATIVO 2026 - ESTRATÉGIA OFICIAL STORMER H4")
print("   Ativos: Mini Índice B3 (WIN / BVSPX), Nasdaq 100, Ouro (XAUUSD), Bitcoin (BTC)")
print("   Período: 01/01/2026 a 23/10/2026 (Sem otimização, Sem lookahead, Dados reais)")
print("="*80)

symbols_cfg = {
    "Mini Índice B3 (WIN / BVSPX)": {
        "symbol": "BVSPX.s",
        "category": "B3 / Índice Brasileiro",
        "commission_round": 1.0,
        "slippage_ticks": 2,
        "b3_pts_multiplier": 0.20, # R$ 0,20 por ponto no mini índice
        "b3_fees_per_trade": 1.10   # R$ 1,10 emolumentos + taxa B3 por contrato
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

def run_causal_test(name, cfg, allow_sell=False, initial_balance=10000.0, risk_pct=1.0):
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

    # 1. Indicadores Causalmente Deslocados (.shift(1) em barras fechadas)
    df['ema70'] = df['close'].ewm(span=70, adjust=False).mean().shift(1)
    df['ema70_prev'] = df['ema70'].shift(1)

    low8 = df['low'].rolling(8).min()
    high8 = df['high'].rolling(8).max()
    fast_k = 100.0 * (df['close'] - low8) / (high8 - low8 + 1e-10)
    df['stoch_k'] = fast_k.rolling(3).mean().shift(1)
    df['stoch_d'] = df['stoch_k'].rolling(3).mean().shift(1)

    # Barras fechadas para o padrão 1-2-3
    df['high_1'] = df['high'].shift(1) # Candle 3
    df['low_1'] = df['low'].shift(1)
    df['close_1'] = df['close'].shift(1)

    df['high_2'] = df['high'].shift(2) # Candle 2 (Fundo/Topo do padrão)
    df['low_2'] = df['low'].shift(2)

    df['high_3'] = df['high'].shift(3) # Candle 1
    df['low_3'] = df['low'].shift(3)

    # Alvos retrospectivos nos 20 candles anteriores
    df['swing_high_target'] = df['high'].shift(3).rolling(20).max()
    df['swing_low_target'] = df['low'].shift(3).rolling(20).min()

    # Condições de Compra
    cond_ema_buy = (df['ema70'] > df['ema70_prev']) & (df['close_1'] >= df['ema70'])
    df['stoch_oversold'] = (df['stoch_k'] < 20.0).rolling(6).max() == 1.0
    cond_123_buy = (df['low_2'] < df['low_3']) & (df['low_1'] > df['low_2'])
    df['buy_signal'] = cond_ema_buy & df['stoch_oversold'] & cond_123_buy

    # Condições de Venda
    cond_ema_sell = (df['ema70'] < df['ema70_prev']) & (df['close_1'] <= df['ema70'])
    df['stoch_overbought'] = (df['stoch_k'] > 80.0).rolling(6).max() == 1.0
    cond_123_sell = (df['high_2'] > df['high_3']) & (df['high_1'] < df['high_2'])
    df['sell_signal'] = cond_ema_sell & df['stoch_overbought'] & cond_123_sell

    # 2. Loop de Simulação Causal
    balance = initial_balance
    peak_equity = initial_balance
    max_dd_usd = 0.0
    max_dd_pct = 0.0

    position = None
    trades_log = []
    total_commission = 0.0
    total_swap = 0.0
    total_gross_profit = 0.0
    total_gross_loss = 0.0
    total_points = 0.0

    start_idx = df[df['time'] >= eval_start_date].index[0]

    for i in range(start_idx, len(df)):
        row = df.iloc[i]

        if position is not None:
            # Swap accrual aproximado
            # Aproximação swap MT5 por dia (6 barras H4)
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
                    exit_price = tp # SEM TELETRANSPORTE
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
                        "result": "WIN (TP)",
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
                        "result": "WIN (TP)",
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

        # Nova entrada
        if position is None:
            if row['buy_signal']:
                trigger = row['high_1']
                sl_p = row['low_2'] - (50 * point)
                tp_p = row['swing_high_target']
                risk_d = trigger - sl_p
                reward_d = tp_p - trigger

                if risk_d > 0 and (reward_d / risk_d >= 1.0):
                    if row['high'] >= trigger:
                        entry_p = trigger + spread_val + slippage_val
                        # Calcula lote para arriscar 1% da banca
                        risk_usd = balance * (risk_pct / 100.0)
                        loss_for_1lot = abs(mt5.order_calc_profit(mt5.ORDER_TYPE_BUY, sym, 1.0, entry_p, sl_p) or (risk_d * 1.0))
                        if loss_for_1lot > 0:
                            calc_lot = risk_usd / loss_for_1lot
                        else:
                            calc_lot = vol_min
                        lot = max(vol_min, round(np.floor(calc_lot / vol_step) * vol_step, 2))
                        comm = lot * comm_per_lot
                        total_commission += comm
                        balance -= comm

                        position = {
                            "type": "BUY",
                            "entry_price": entry_p,
                            "sl": sl_p,
                            "tp": tp_p,
                            "lot": lot,
                            "entry_time": row['time']
                        }

            elif allow_sell and row['sell_signal']:
                trigger = row['low_1']
                sl_p = row['high_2'] + (50 * point)
                tp_p = row['swing_low_target']
                risk_d = sl_p - trigger
                reward_d = trigger - tp_p

                if risk_d > 0 and (reward_d / risk_d >= 1.0):
                    if row['low'] <= trigger:
                        entry_p = trigger - slippage_val
                        risk_usd = balance * (risk_pct / 100.0)
                        loss_for_1lot = abs(mt5.order_calc_profit(mt5.ORDER_TYPE_SELL, sym, 1.0, entry_p, sl_p) or (risk_d * 1.0))
                        if loss_for_1lot > 0:
                            calc_lot = risk_usd / loss_for_1lot
                        else:
                            calc_lot = vol_min
                        lot = max(vol_min, round(np.floor(calc_lot / vol_step) * vol_step, 2))
                        comm = lot * comm_per_lot
                        total_commission += comm
                        balance -= comm

                        position = {
                            "type": "SELL",
                            "entry_price": entry_p,
                            "sl": sl_p,
                            "tp": tp_p,
                            "lot": lot,
                            "entry_time": row['time']
                        }

    n_trades = len(trades_log)
    wins = len([t for t in trades_log if "WIN" in t["result"]])
    losses = len([t for t in trades_log if "LOSS" in t["result"]])
    win_rate = (wins / n_trades * 100.0) if n_trades > 0 else 0.0
    pf = (total_gross_profit / total_gross_loss) if total_gross_loss > 0 else 999.0
    net_pnl = balance - initial_balance

    # Cálculo B3 específico se for índice brasileiro
    b3_net_brl = 0.0
    if "b3_pts_multiplier" in cfg:
        # PnL em Reais para 1 mini contrato na B3:
        # Cada ponto = R$ 0,20. Emolumentos = R$ 1,10 / trade.
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

# Executa para todos
all_results = []
for k, cfg in symbols_cfg.items():
    # Buy Only (Fiel ao Stormer)
    r_buy = run_causal_test(k, cfg, allow_sell=False)
    all_results.append(r_buy)
    # Bidirecional
    r_both = run_causal_test(k, cfg, allow_sell=True)
    all_results.append(r_both)

mt5.shutdown()

# Imprime relatório consolidado
print("\n" + "="*95)
print("             RELATÓRIO CONSOLIDADO DE PERFORMANCE 2026 (01/01/2026 A 23/10/2026)")
print("="*95)
print(f"{'Ativo':<28} | {'Modo':<13} | {'Trades':<6} | {'Win%':<6} | {'Pontos':<10} | {'Lucro Líq ($)':<13} | {'PF':<5} | {'MaxDD (%)':<9}")
print("-"*95)
for r in all_results:
    if "error" in r:
        print(f"{r.get('asset_name','?'):<28} | ERRO: {r['error']}")
    else:
        print(f"{r['asset_name']:<28} | {r['mode']:<13} | {r['total_trades']:<6} | {r['win_rate']:<5.1f}% | {r['total_points']:<10.1f} | ${r['net_pnl_usd']:<12.2f} | {r['profit_factor']:<5.2f} | {r['max_dd_pct']:<8.2f}%")

# Salva arquivo consolidado
with open(r"C:\Users\Vini_Burgo\.gemini\antigravity\brain\2cceb840-74c7-470b-9b9c-da2793fd84da\scratch\relatorio_forense_2026_multi.json", "w", encoding="utf-8") as f:
    import json
    json.dump(all_results, f, indent=2, ensure_ascii=False)

print("\nRelatório salvo com sucesso.")
