import os
import sys
import time
from datetime import datetime, timezone
import MetaTrader5 as mt5
import pandas as pd
import numpy as np

# ==============================================================================
# CONFIGURAÇÕES DO MOTOR INSTITUCIONAL - SUNRISE GUARDRAIL
# ==============================================================================
MT5_PATH = r"C:\Program Files\MetaTrader 5\terminal64.exe"
ACCOUNT_LOGIN = 1123867
ACCOUNT_PASSWORD = "Louco123123@"
ACCOUNT_SERVER = "VTMarkets-Demo"

SYMBOL = "BTCUSD"
TIMEFRAME = mt5.TIMEFRAME_M15
RISK_PERCENT = 1.0               # 1.0% do saldo atual
ATR_PERIOD = 14
ATR_MULTIPLIER_SL = 1.5
RR_RATIO = 2.0                   # Payoff 2:1 (Take Profit = 2x Stop Loss)
PVSRA_LOOKBACK = 10
MAGIC_NUMBER = 20260930

# Trava Sunrise GuardRail
GUARDRAIL = {
    "enabled": True,
    "max_spread_drag_pct": 5.0,  # Spread não pode consumir > 5% do alvo
    "max_spread_pts": 3000,      # Teto de 3.000 pts ($30.00)
    "max_margin_usage_pct": 20.0,# Máximo 20% da margem livre
    "session_filter": True,      # Apenas sessões Londres e Nova York
    "allowed_hours_utc": [(8, 12), (15, 19)],
    "allow_weekends": False
}

def connect_mt5():
    if not mt5.initialize(path=MT5_PATH, login=ACCOUNT_LOGIN, password=ACCOUNT_PASSWORD, server=ACCOUNT_SERVER, timeout=30000):
        print(f"[ERRO] Falha ao inicializar MT5: {mt5.last_error()}")
        return False
    acc = mt5.account_info()
    if not acc:
        return False
    print(f"[CONEXÃO OK] Conta: {acc.login} | Servidor: {acc.server} | Saldo: ${acc.balance:,.2f} | Margem Livre: ${acc.margin_free:,.2f}")
    return mt5.symbol_select(SYMBOL, True)

def get_market_analysis():
    rates = mt5.copy_rates_from_pos(SYMBOL, TIMEFRAME, 0, 250)
    if rates is None or len(rates) < PVSRA_LOOKBACK + 50:
        return None, 0.0, "Sem dados", 0

    df = pd.DataFrame(rates)
    
    # ATR
    prev_close = df['close'].shift(1)
    tr1 = df['high'] - df['low']
    tr2 = (df['high'] - prev_close).abs()
    tr3 = (df['low'] - prev_close).abs()
    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    df['atr'] = tr.rolling(ATR_PERIOD).mean()

    # EMAs
    df['ema_50'] = df['close'].ewm(span=50, adjust=False).mean()
    df['ema_200'] = df['close'].ewm(span=200, adjust=False).mean()

    # PVSRA
    df['avg_vol'] = df['tick_volume'].rolling(PVSRA_LOOKBACK).mean()
    df['candle_spread'] = (df['close'] - df['open']).abs()
    df['avg_spread'] = df['candle_spread'].rolling(PVSRA_LOOKBACK).mean()

    last_closed = df.iloc[-2]
    is_bull = last_closed['close'] >= last_closed['open']
    
    cond_climax = (last_closed['tick_volume'] >= 2.0 * last_closed['avg_vol']) or \
                  ((last_closed['tick_volume'] * last_closed['candle_spread']) >= (2.0 * last_closed['avg_vol'] * last_closed['avg_spread']))
    cond_rising = (not cond_climax) and (last_closed['tick_volume'] >= 1.5 * last_closed['avg_vol'])

    trend_bull = (last_closed['close'] > last_closed['ema_200']) and (last_closed['ema_50'] > last_closed['ema_200'])
    trend_bear = (last_closed['close'] < last_closed['ema_200']) and (last_closed['ema_50'] < last_closed['ema_200'])

    pvsra_desc = "NORMAL"
    signal_dir = 0  # 1 = Compra, -1 = Venda

    if cond_climax:
        pvsra_desc = "CLÍMAX TOURO" if is_bull else "CLÍMAX URSO"
        if is_bull and trend_bull: signal_dir = 1
        elif (not is_bull) and trend_bear: signal_dir = -1
    elif cond_rising:
        pvsra_desc = "RISING TOURO" if is_bull else "RISING URSO"
        if is_bull and trend_bull: signal_dir = 1
        elif (not is_bull) and trend_bear: signal_dir = -1

    return df, df['atr'].iloc[-1], pvsra_desc, signal_dir

def calculate_lot(sl_distance_usd):
    acc = mt5.account_info()
    info = mt5.symbol_info(SYMBOL)
    if acc is None or info is None or sl_distance_usd <= 0:
        return 0.0

    risk_money = acc.balance * (RISK_PERCENT / 100.0)
    raw_lot = risk_money / sl_distance_usd
    lot = max(info.volume_min, min(info.volume_max, np.floor(raw_lot / info.volume_step) * info.volume_step))
    return round(lot, 2)

def guardrail_audit(order_type, lot, sl_dist_pts, tp_dist_pts):
    info = mt5.symbol_info(SYMBOL)
    acc = mt5.account_info()
    if info is None or acc is None:
        return False, "Dados indisponíveis"

    now = datetime.now(timezone.utc)
    if not GUARDRAIL["allow_weekends"] and now.weekday() >= 5:
        return False, "Fim de semana bloqueado"

    if GUARDRAIL["session_filter"]:
        hour = now.hour
        in_session = any(s <= hour < e for s, e in GUARDRAIL["allowed_hours_utc"])
        if not in_session:
            return False, f"Fora da janela institucional ({hour:02d}h UTC). Permitido: Londres (8-12h) e NY (15-19h)"

    if info.spread > GUARDRAIL["max_spread_pts"]:
        return False, f"Spread alto: {info.spread} pts > teto {GUARDRAIL['max_spread_pts']} pts"

    spread_drag = (info.spread / tp_dist_pts) * 100.0
    if spread_drag > GUARDRAIL["max_spread_drag_pct"]:
        return False, f"Spread Drag excessivo: {spread_drag:.1f}% do TP (limite: {GUARDRAIL['max_spread_drag_pct']}%)"

    margin_req = mt5.order_calc_margin(order_type, SYMBOL, lot, info.ask if order_type == mt5.ORDER_TYPE_BUY else info.bid)
    if margin_req and (margin_req / acc.margin_free) * 100.0 > GUARDRAIL["max_margin_usage_pct"]:
        return False, "Margem necessária acima de 20% da margem livre"

    return True, "Aprovado pelo Sunrise GuardRail"

def execute_order(order_type, lot, sl_dist_usd, tp_dist_usd):
    tick = mt5.symbol_info_tick(SYMBOL)
    info = mt5.symbol_info(SYMBOL)

    if order_type == mt5.ORDER_TYPE_BUY:
        price = tick.ask
        sl_price = price - sl_dist_usd
        tp_price = price + tp_dist_usd
        type_str = "BUY"
    else:
        price = tick.bid
        sl_price = price + sl_dist_usd
        tp_price = price - tp_dist_usd
        type_str = "SELL"

    request = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": SYMBOL,
        "volume": float(lot),
        "type": order_type,
        "price": price,
        "sl": round(sl_price, info.digits),
        "tp": round(tp_price, info.digits),
        "deviation": 50,
        "magic": MAGIC_NUMBER,
        "comment": "Sunrise_Trader_Live",
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC
    }

    result = mt5.order_send(request)
    if result.retcode != mt5.TRADE_RETCODE_DONE:
        print(f"[ERRO DE EXECUÇÃO] Retcode: {result.retcode} | {result.comment}")
        return False
    print(f"\n🚀 [ORDEM EXECUTADA] {type_str} {lot} {SYMBOL} @ {result.price:.2f} | Ticket #{result.order} | SL: {sl_price:.2f} | TP: {tp_price:.2f}")
    return True

def run_trader():
    print("="*65)
    print("      SUNRISE GUARDRAIL - MOTOR INSTITUCIONAL ATIVO (BTCUSD)      ")
    print("="*65)
    if not connect_mt5():
        sys.exit(1)

    print("[*] Monitoramento contínuo armado em M15. Pressione Ctrl+C para parar.\n")
    
    LOG_INTERVAL = 15  # Frequência determinada de log (15 segundos)
    last_log_time = 0
    try:
        while True:
            if not mt5.terminal_info().connected:
                print("[!] Terminal desconectado. Tentando reconectar...")
                time.sleep(5)
                continue

            open_positions = mt5.positions_get(symbol=SYMBOL)
            has_position = open_positions is not None and len(open_positions) > 0

            df, atr, pvsra_desc, signal_dir = get_market_analysis()

            now_str = datetime.now(timezone.utc).strftime("%H:%M:%S UTC")
            now_ts = time.time()
            
            if df is not None and atr > 0:
                info = mt5.symbol_info(SYMBOL)
                sl_dist_usd = atr * ATR_MULTIPLIER_SL
                tp_dist_usd = sl_dist_usd * RR_RATIO
                sl_dist_pts = sl_dist_usd / info.point
                tp_dist_pts = tp_dist_usd / info.point
                lot = calculate_lot(sl_dist_usd)
                spread_drag = (info.spread / tp_dist_pts) * 100.0

                # Log de batimento estritamente a cada 15 segundos
                if now_ts - last_log_time >= LOG_INTERVAL:
                    acc = mt5.account_info()
                    status_str = f"POSIÇÃO ABERTA ({open_positions[0].ticket} | PnL: ${open_positions[0].profit:.2f})" if has_position else "AGUARDANDO SINAL"
                    guardrail_note = ""
                    if signal_dir != 0 and not has_position:
                        order_type = mt5.ORDER_TYPE_BUY if signal_dir == 1 else mt5.ORDER_TYPE_SELL
                        aprovado, motivo = guardrail_audit(order_type, lot, sl_dist_pts, tp_dist_pts)
                        if not aprovado:
                            guardrail_note = f" | [TRAVA: {motivo}]"
                    print(f"[{now_str}] {SYMBOL} Bid: {info.bid:.2f} | Spread: {info.spread} pts ({spread_drag:.1f}%) | ATR: {atr:.2f} | PVSRA: {pvsra_desc} | {status_str}{guardrail_note}")
                    last_log_time = now_ts

                if not has_position and signal_dir != 0:
                    order_type = mt5.ORDER_TYPE_BUY if signal_dir == 1 else mt5.ORDER_TYPE_SELL
                    aprovado, motivo = guardrail_audit(order_type, lot, sl_dist_pts, tp_dist_pts)
                    if aprovado:
                        print(f"\n🚀 [+] SINAL VALIDADO! Gatilho: {pvsra_desc} | Direção: {'COMPRA' if signal_dir == 1 else 'VENDA'}")
                        if execute_order(order_type, lot, sl_dist_usd, tp_dist_usd):
                            time.sleep(5)

            time.sleep(5)  # Checagem a cada 5 segundos

    except KeyboardInterrupt:
        print("\n[!] Encerrando motor institucional...")
    finally:
        mt5.shutdown()
        print("[*] Desconectado do MetaTrader 5.")

if __name__ == "__main__":
    run_trader()
