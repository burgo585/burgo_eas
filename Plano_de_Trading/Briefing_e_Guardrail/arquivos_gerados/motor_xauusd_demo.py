import os
import time
import threading
from datetime import datetime, timezone
import MetaTrader5 as mt5
import pandas as pd
import numpy as np
import tkinter as tk

# ==============================================================================
# 1. CREDENCIAIS E ATIVO INSTITUCIONAL
# ==============================================================================
MT5_PATH = r"C:\Program Files\MetaTrader 5\terminal64.exe"
ACCOUNT_LOGIN    = 1123867
ACCOUNT_PASSWORD = "Louco123123@"
ACCOUNT_SERVER   = "VTMarkets-Demo"

SYMBOL = "XAUUSD-VIP"                  # "XAUUSD-VIP" ou "BTCUSD"
TIMEFRAME = mt5.TIMEFRAME_M15
RISK_PERCENT = 1.0  
ATR_PERIOD = 14
ATR_MULTIPLIER_SL = 1.5 
RR_RATIO = 2.0                         # Take Profit é 2x o Stop Loss (Payoff 2:1)
PVSRA_LOOKBACK = 10
MAGIC_NUMBER = 20260902

# ==============================================================================
# 2. PARÂMETROS DE SEGURANÇA E GUARDRAIL (SUNRISE PROTOCOL)
# ==============================================================================
GUARDRAIL_CONFIG = {
    "enabled": True,
    "max_spread_drag_pct": 5.0,        # Spread não pode consumir mais que 5% do alvo (TP)
    "max_allowed_spread_pts": {
        "XAUUSD-VIP": 50,              # Máximo 50 pts ($0.50) para Ouro
        "BTCUSD": 3000                 # Máximo 3000 pts ($30.00) para Bitcoin
    },
    "max_margin_usage_pct": 20.0,      # Posição não pode comprometer mais que 20% da margem livre
    "institutional_sessions_only": True,# Operar apenas nas janelas de Londres e NY
    "allowed_hours_utc": [
        (8, 12),                       # Sessão de Londres (08:00 - 12:00 UTC)
        (15, 19)                       # Pico de Nova York (15:00 - 19:00 UTC)
    ],
    "allow_weekends": False            # Bloquear operações no fim de semana
}

# ==============================================================================
# 3. ESTADO GLOBAL DO SISTEMA (FSM)
# ==============================================================================
system_state = {
    "connected": False,
    "atr": 0.0,
    "sl_points": 0.0,
    "tp_points": 0.0,
    "lot_size": 0.0,
    "spread_pts": 0,
    "spread_drag_pct": 0.0,
    "pvsra_text": "Aguardando volume...",
    "pvsra_color": "#888888",
    "last_update": "--:--:--",
    "trading_enabled": False, 
    "status_msg": "Iniciando sistema...",
    "guardrail_status": "GuardRail: Ativo"
}

# ==============================================================================
# 4. MOTOR QUANTITATIVO (DADOS E RISCO)
# ==============================================================================
def initialize_specific_mt5():
    initialized = mt5.initialize(path=MT5_PATH, login=ACCOUNT_LOGIN, password=ACCOUNT_PASSWORD, server=ACCOUNT_SERVER, timeout=60000, portable=False)
    if not initialized:
        return False
    t_info = mt5.terminal_info()
    if t_info is None or not t_info.trade_allowed:
        return False
    return mt5.symbol_select(SYMBOL, True)

def get_market_data_with_pvsra(symbol, timeframe, num_bars):
    rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, num_bars)
    if rates is None or len(rates) < PVSRA_LOOKBACK + 2: 
        return None, 0.0, "Dados insuficientes", "#ff0000", 0

    df = pd.DataFrame(rates)
    
    # ATR (True Range)
    df['prev_close'] = df['close'].shift(1)
    df['tr1'] = df['high'] - df['low']
    df['tr2'] = np.abs(df['high'] - df['prev_close'])
    df['tr3'] = np.abs(df['low'] - df['prev_close'])
    df['tr'] = df[['tr1', 'tr2', 'tr3']].max(axis=1)
    df['atr'] = df['tr'].rolling(window=ATR_PERIOD).mean()
    
    # Médias de Tendência Institucional
    df['ema_50'] = df['close'].ewm(span=50, adjust=False).mean()
    df['ema_200'] = df['close'].ewm(span=200, adjust=False).mean()

    # PVSRA (Price Volume Spread Analysis)
    df['avg_vol'] = df['tick_volume'].rolling(window=PVSRA_LOOKBACK).mean()
    df['candle_spread'] = (df['close'] - df['open']).abs()
    df['avg_spread'] = df['candle_spread'].rolling(window=PVSRA_LOOKBACK).mean()
    
    last_closed = df.iloc[-2]
    is_bull = last_closed['close'] >= last_closed['open']
    
    # Condições PVSRA
    cond_climax = (last_closed['tick_volume'] >= 2.0 * last_closed['avg_vol']) or \
                  ((last_closed['tick_volume'] * last_closed['candle_spread']) >= (2.0 * last_closed['avg_vol'] * last_closed['avg_spread']))
    cond_rising = (not cond_climax) and (last_closed['tick_volume'] >= 1.5 * last_closed['avg_vol'])
    
    # Filtro de Tendência: Compra só acima da EMA 200, Venda só abaixo
    trend_bull = last_closed['close'] > last_closed['ema_200']
    trend_bear = last_closed['close'] < last_closed['ema_200']

    pvsra_txt = "Volume Normal"
    pvsra_col = "#cccccc"
    signal_dir = 0 # 1 para Compra, -1 para Venda
    
    if cond_climax:
        pvsra_txt = "CLÍMAX TOURO" if is_bull else "CLÍMAX URSO"
        pvsra_col = "#00ff00" if is_bull else "#ff0000"
        if is_bull and trend_bull:
            signal_dir = 1
        elif (not is_bull) and trend_bear:
            signal_dir = -1
    elif cond_rising:
        pvsra_txt = "RISING TOURO" if is_bull else "RISING URSO"
        pvsra_col = "#1e90ff" if is_bull else "#ff00ff"
        if is_bull and trend_bull:
            signal_dir = 1
        elif (not is_bull) and trend_bear:
            signal_dir = -1

    return df, df['atr'].iloc[-1], pvsra_txt, pvsra_col, signal_dir

def calculate_dynamic_lot(symbol, risk_percent, sl_points):
    info = mt5.symbol_info(symbol)
    acc = mt5.account_info()
    if info is None or acc is None or sl_points <= 0 or info.trade_tick_size == 0: 
        return 0.0
    
    balance = acc.balance
    max_loss_money = balance * (risk_percent / 100.0)
    risk_per_lot = (sl_points / info.trade_tick_size) * info.trade_tick_value
    
    if risk_per_lot == 0: 
        return 0.0
        
    raw_lot = max_loss_money / risk_per_lot
    normalized_lot = np.floor(raw_lot / info.volume_step) * info.volume_step
    normalized_lot = max(info.volume_min, min(info.volume_max, normalized_lot))
    
    # Auditoria de Margem
    margin_required = mt5.order_calc_margin(mt5.ORDER_TYPE_BUY, symbol, normalized_lot, info.ask)
    if margin_required is None or margin_required > acc.margin_free:
        return 0.0
        
    return max(0.0, round(normalized_lot, 2))

# ==============================================================================
# 5. MÓDULO DE VALIDAÇÃO DE SEGURANÇA GUARDRAIL (SUNRISE)
# ==============================================================================
def guardrail_validate_trade(symbol, order_type, lot_size, sl_points, tp_points):
    """
    Audita exaustivamente a ordem antes do envio:
    1. Trava de Spread Drag (spread vs alvo de lucro)
    2. Teto absoluto de spread da corretora
    3. Trava de margem comprometida
    4. Trava de janela institucional de liquidez (sessão Londres/NY)
    5. Nível de stop da corretora (trade_stops_level)
    """
    if not GUARDRAIL_CONFIG["enabled"]:
        return True, "GuardRail desativado"

    info = mt5.symbol_info(symbol)
    acc = mt5.account_info()
    if info is None or acc is None:
        return False, "GuardRail: Dados de símbolo ou conta inacessíveis"

    # 1. Filtro de Horário / Sessão Institucional
    now_utc = datetime.now(timezone.utc)
    if not GUARDRAIL_CONFIG["allow_weekends"] and now_utc.weekday() >= 5:
        return False, "GuardRail BLOQUEIO: Fim de semana (mercado de baixa liquidez)"

    if GUARDRAIL_CONFIG["institutional_sessions_only"]:
        hour = now_utc.hour
        in_session = any(start <= hour < end for start, end in GUARDRAIL_CONFIG["allowed_hours_utc"])
        if not in_session:
            return False, f"GuardRail BLOQUEIO: Fora da janela institucional ({hour:02d}:00 UTC). Permitido: Londres 8-12h e NY 15-19h"

    # 2. Teto Absoluto de Spread
    max_pts = GUARDRAIL_CONFIG["max_allowed_spread_pts"].get(symbol, 100)
    current_spread = info.spread
    if current_spread > max_pts:
        return False, f"GuardRail BLOQUEIO: Spread elevado ({current_spread} pts > teto {max_pts} pts)"

    # 3. Trava de Spread Drag (% do Alvo consumido pelo spread)
    if tp_points <= 0:
        return False, "GuardRail BLOQUEIO: Alvo de TP inválido"
        
    spread_drag_pct = (current_spread / tp_points) * 100.0
    system_state["spread_drag_pct"] = spread_drag_pct
    system_state["spread_pts"] = current_spread

    if spread_drag_pct > GUARDRAIL_CONFIG["max_spread_drag_pct"]:
        return False, f"GuardRail BLOQUEIO: Spread consome {spread_drag_pct:.1f}% do lucro esperado (limite: {GUARDRAIL_CONFIG['max_spread_drag_pct']}%)"

    # 4. Trava de Margem Comprometida
    margin_required = mt5.order_calc_margin(order_type, symbol, lot_size, info.ask if order_type == mt5.ORDER_TYPE_BUY else info.bid)
    if margin_required is not None:
        margin_usage_pct = (margin_required / acc.margin_free) * 100.0
        if margin_usage_pct > GUARDRAIL_CONFIG["max_margin_usage_pct"]:
            return False, f"GuardRail BLOQUEIO: Margem necessária ({margin_usage_pct:.1f}%) excede limite de segurança de {GUARDRAIL_CONFIG['max_margin_usage_pct']}%"

    # 5. Distância de Stops Mínimos da Corretora
    if sl_points <= info.trade_stops_level or tp_points <= info.trade_stops_level:
        return False, f"GuardRail BLOQUEIO: SL/TP ({sl_points:.0f}/{tp_points:.0f} pts) menor que o nível mínimo da corretora ({info.trade_stops_level} pts)"

    return True, "GuardRail: Ordem 100% Aprovada"

# ==============================================================================
# 6. MOTOR DE EXECUÇÃO (ORDER SEND)
# ==============================================================================
def execute_trade(symbol, order_type, lot_size, sl_points, tp_points):
    """Envia a ordem para a corretora via IPC após validação rigorosa."""
    info = mt5.symbol_info(symbol)
    tick = mt5.symbol_info_tick(symbol)
    if info is None or tick is None:
        print("[ERRO] Falha ao ler ticks do símbolo.")
        return False
    
    if order_type == mt5.ORDER_TYPE_BUY:
        price = tick.ask
        sl_price = price - (sl_points * info.point)
        tp_price = price + (tp_points * info.point)
    else:
        price = tick.bid
        sl_price = price + (sl_points * info.point)
        tp_price = price - (tp_points * info.point)

    # Validação GuardRail antes de montar o pacote de ordem
    aprovado, motivo = guardrail_validate_trade(symbol, order_type, lot_size, sl_points, tp_points)
    if not aprovado:
        print(f"[REJEIÇÃO GUARDRAIL] {motivo}")
        system_state["status_msg"] = motivo
        return False

    request = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": symbol,
        "volume": float(lot_size),
        "type": order_type,
        "price": price,
        "sl": round(sl_price, info.digits),
        "tp": round(tp_price, info.digits),
        "deviation": 20,
        "magic": MAGIC_NUMBER,
        "comment": "Sunrise_GuardRail_Exec",
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC
    }

    result = mt5.order_send(request)
    
    if result.retcode != mt5.TRADE_RETCODE_DONE:
        print(f"[ERRO DE EXECUÇÃO] Retcode: {result.retcode}")
        system_state["status_msg"] = f"Erro Broker: Retcode {result.retcode}"
        return False
        
    print(f"[SUCESSO] Ordem Executada. Ticket: {result.order}")
    system_state["status_msg"] = f"Sucesso! Ordem #{result.order} executada"
    return True

# ==============================================================================
# 7. THREAD DO MOTOR DE NEGOCIAÇÃO (BACKGROUND)
# ==============================================================================
def trading_loop():
    system_state["connected"] = initialize_specific_mt5()
    if not system_state["connected"]:
        system_state["status_msg"] = "ERRO: Terminal não conectado ou Algo inativo."
        return

    while True:
        if not mt5.terminal_info().connected:
            system_state["connected"] = False
            system_state["status_msg"] = "Conexão perdida. Reconectando..."
            time.sleep(5)
            continue
            
        system_state["connected"] = True
        
        # 1. Auditoria de Posições
        posicoes_abertas = mt5.positions_get(symbol=SYMBOL)
        tem_posicao = False if posicoes_abertas is None else len(posicoes_abertas) > 0
        
        # 2. Leitura de Mercado e Cálculo Quantitativo
        df, atr, pvsra_txt, pvsra_col, signal_dir = get_market_data_with_pvsra(SYMBOL, TIMEFRAME, 250)
        
        if df is not None and atr > 0:
            sym_info = mt5.symbol_info(SYMBOL)
            point = sym_info.point
            sl_points = (atr * ATR_MULTIPLIER_SL) / point
            tp_points = sl_points * RR_RATIO
            lot_size = calculate_dynamic_lot(SYMBOL, RISK_PERCENT, sl_points)
            
            system_state["atr"] = atr
            system_state["sl_points"] = sl_points
            system_state["tp_points"] = tp_points
            system_state["lot_size"] = lot_size
            system_state["spread_pts"] = sym_info.spread
            system_state["spread_drag_pct"] = (sym_info.spread / tp_points) * 100.0 if tp_points > 0 else 0.0
            system_state["pvsra_text"] = pvsra_txt
            system_state["pvsra_color"] = pvsra_col
            system_state["last_update"] = datetime.now().strftime('%H:%M:%S')

            # 3. Lógica de Execução e Status
            if tem_posicao:
                system_state["status_msg"] = "Posição Aberta. Gerenciando Risco..."
            elif not system_state["trading_enabled"]:
                system_state["status_msg"] = "Robô PAUSADO. Leitura ativa."
            else:
                system_state["status_msg"] = "Robô ARMADO. Aguardando Gatilho..."
                
                # Gatilho de Entrada: Sinal PVSRA + Tendência EMA 200 + Lote válido
                if signal_dir != 0 and lot_size > 0:
                    ordem = mt5.ORDER_TYPE_BUY if signal_dir == 1 else mt5.ORDER_TYPE_SELL
                    
                    # Checagem prévia pelo GuardRail
                    aprovado, msg = guardrail_validate_trade(SYMBOL, ordem, lot_size, sl_points, tp_points)
                    if aprovado:
                        system_state["status_msg"] = "Enviando Ordem Aprovada..."
                        sucesso = execute_trade(SYMBOL, ordem, lot_size, sl_points, tp_points)
                        if sucesso:
                            time.sleep(3)
                    else:
                        system_state["status_msg"] = msg

        time.sleep(2)

# ==============================================================================
# 8. INTERFACE GRÁFICA (UI MAIN THREAD)
# ==============================================================================
class TradingDashboard:
    def __init__(self, root):
        self.root = root
        self.root.title("Sunrise GuardRail - Institutional Trading Engine")
        self.root.geometry("480x480")
        self.root.configure(bg="#121212")
        self.root.attributes("-topmost", True)

        font_title = ("Consolas", 14, "bold")
        font_data = ("Consolas", 11)
        font_pvsra = ("Consolas", 12, "bold")
        bg_color = "#121212"

        self.frame = tk.Frame(self.root, bg=bg_color, padx=20, pady=15)
        self.frame.pack(fill=tk.BOTH, expand=True)

        tk.Label(self.frame, text=f"{SYMBOL} | M15 | VT Markets", font=font_title, bg=bg_color, fg="#00ff00").pack(pady=(0, 5))
        self.lbl_guardrail = tk.Label(self.frame, text="🛡️ SUNRISE GUARDRAIL ATIVO", font=("Consolas", 10, "bold"), bg=bg_color, fg="#00E676")
        self.lbl_guardrail.pack(pady=(0, 10))
        
        self.lbl_atr = tk.Label(self.frame, text="ATR M15: --", font=font_data, bg=bg_color, fg="#ffffff")
        self.lbl_atr.pack(anchor="w", pady=2)
        
        self.lbl_sl = tk.Label(self.frame, text="SL / TP: -- / -- pts", font=font_data, bg=bg_color, fg="#ffffff")
        self.lbl_sl.pack(anchor="w", pady=2)
        
        self.lbl_spread = tk.Label(self.frame, text="Spread: -- pts | Fricção: --%", font=font_data, bg=bg_color, fg="#ffcc00")
        self.lbl_spread.pack(anchor="w", pady=2)

        self.lbl_lot = tk.Label(self.frame, text="Lote (Risco 1%): --", font=font_data, bg=bg_color, fg="#00ffff")
        self.lbl_lot.pack(anchor="w", pady=2)
        
        tk.Frame(self.frame, height=1, bg="#333333").pack(fill=tk.X, pady=8)
        
        tk.Label(self.frame, text="SINAL INSTITUCIONAL PVSRA:", font=("Consolas", 10), bg=bg_color, fg="#888888").pack(anchor="w")
        self.lbl_pvsra = tk.Label(self.frame, text="Analisando...", font=font_pvsra, bg=bg_color, fg="#ffffff")
        self.lbl_pvsra.pack(anchor="w", pady=2)

        tk.Frame(self.frame, height=1, bg="#333333").pack(fill=tk.X, pady=8)

        self.lbl_update = tk.Label(self.frame, text="Última Leitura: --:--:--", font=("Consolas", 9), bg=bg_color, fg="#888888")
        self.lbl_update.pack(anchor="w")

        self.lbl_status = tk.Label(self.frame, text="Status: Inicializando...", font=("Consolas", 9, "italic"), bg=bg_color, fg="#ffcc00", wraplength=440)
        self.lbl_status.pack(pady=10)

        self.btn_toggle = tk.Button(self.frame, text="ROBÔ DESLIGADO", font=("Consolas", 12, "bold"), bg="#aa0000", fg="#ffffff", command=self.toggle_trading, width=22, height=2)
        self.btn_toggle.pack()

        self.update_ui()

    def toggle_trading(self):
        system_state["trading_enabled"] = not system_state["trading_enabled"]
        if system_state["trading_enabled"]:
            self.btn_toggle.config(text="ROBÔ LIGADO", bg="#00aa00")
        else:
            self.btn_toggle.config(text="ROBÔ DESLIGADO", bg="#aa0000")

    def update_ui(self):
        self.lbl_atr.config(text=f"ATR M15: {system_state['atr']:.2f}")
        self.lbl_sl.config(text=f"SL Dinâmico: {system_state['sl_points']:.0f} pts | TP (2:1): {system_state['tp_points']:.0f} pts")
        self.lbl_spread.config(text=f"Spread: {system_state['spread_pts']} pts | Spread Drag: {system_state['spread_drag_pct']:.2f}%")
        self.lbl_lot.config(text=f"Lote (Risco 1%): {system_state['lot_size']}")
        self.lbl_pvsra.config(text=system_state['pvsra_text'], fg=system_state['pvsra_color'])
        self.lbl_update.config(text=f"Última Leitura: {system_state['last_update']}")
        
        status_color = "#ff0000" if not system_state["connected"] else ("#00ff00" if system_state["trading_enabled"] else "#ffcc00")
        self.lbl_status.config(text=system_state["status_msg"], fg=status_color)
        self.root.after(500, self.update_ui)

def on_closing():
    mt5.shutdown()
    root.destroy()
    import os
    os._exit(0)

if __name__ == "__main__":
    trade_thread = threading.Thread(target=trading_loop, daemon=True)
    trade_thread.start()
    root = tk.Tk()
    app = TradingDashboard(root)
    root.protocol("WM_DELETE_WINDOW", on_closing)
    root.mainloop()
