import MetaTrader5 as mt5
import pandas as pd
import numpy as np
import time
import threading
import tkinter as tk
from datetime import datetime

# ==============================================================================
# 1. CREDENCIAIS E ATIVO INSTITUCIONAL
# ==============================================================================
MT5_PATH = r"C:\Program Files\MetaTrader 5\terminal64.exe"
ACCOUNT_LOGIN    = 1123867            # <--- COLOQUE SEU LOGIN
ACCOUNT_PASSWORD = Louco123123@      # <--- COLOQUE SUA SENHA
ACCOUNT_SERVER   = VTMarkets-Demo    # <--- COLOQUE SEU SERVIDOR

SYMBOL = "XAUUSD-VIP"                  # Sufixo validado da corretora
TIMEFRAME = mt5.TIMEFRAME_M15
RISK_PERCENT = 1.0  
ATR_PERIOD = 14
ATR_MULTIPLIER_SL = 1.5 
RR_RATIO = 2.0                         # Take Profit será 2x o Stop Loss
PVSRA_LOOKBACK = 10
MAGIC_NUMBER = 20260902

# ==============================================================================
# 2. ESTADO GLOBAL DO SISTEMA (FSM)
# ==============================================================================
system_state = {
    "connected": False,
    "atr": 0.0,
    "sl_points": 0.0,
    "lot_size": 0.0,
    "pvsra_text": "Aguardando volume...",
    "pvsra_color": "#888888",
    "last_update": "--:--:--",
    "trading_enabled": False, 
    "status_msg": "Iniciando sistema..."
}

# ==============================================================================
# 3. MOTOR QUANTITATIVO (DADOS E RISCO)
# ==============================================================================
def initialize_specific_mt5():
    initialized = mt5.initialize(path=MT5_PATH, login=ACCOUNT_LOGIN, password=ACCOUNT_PASSWORD, server=ACCOUNT_SERVER, timeout=60000, portable=False)
    if not initialized or not mt5.terminal_info().trade_allowed:
        return False
    return mt5.symbol_select(SYMBOL, True)

def get_market_data_with_pvsra(symbol, timeframe, num_bars):
    rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, num_bars)
    if rates is None or len(rates) < PVSRA_LOOKBACK + 2: 
        return None, 0.0, "Dados insuficientes", "#ff0000", 0

    df = pd.DataFrame(rates)
    
    # ATR
    df['prev_close'] = df['close'].shift(1)
    df['tr1'] = df['high'] - df['low']
    df['tr2'] = np.abs(df['high'] - df['prev_close'])
    df['tr3'] = np.abs(df['low'] - df['prev_close'])
    df['tr'] = df[['tr1', 'tr2', 'tr3']].max(axis=1)
    df['atr'] = df['tr'].rolling(window=ATR_PERIOD).mean()
    
    # PVSRA e Market Structure
    df['avg_vol'] = df['tick_volume'].rolling(window=PVSRA_LOOKBACK).mean()
    df['value2'] = df['tick_volume'] * (df['high'] - df['low'])
    df['max_value2'] = df['value2'].rolling(window=PVSRA_LOOKBACK).max().shift(1)
    
    last_closed = df.iloc[-2]
    is_bull = last_closed['close'] >= last_closed['open']
    ratio = last_closed['tick_volume'] / last_closed['avg_vol'] if last_closed['avg_vol'] > 0 else 0
    
    is_climax = (ratio >= 2.0) or (last_closed['max_value2'] > 0 and last_closed['value2'] >= last_closed['max_value2'])
    is_rising = (not is_climax) and (ratio >= 1.5)
    
    pvsra_txt = "Volume Normal"
    pvsra_col = "#cccccc"
    signal_dir = 0 # 1 para Compra, -1 para Venda
    
    if is_climax:
        pvsra_txt = "CLÍMAX TOURO" if is_bull else "CLÍMAX URSO"
        pvsra_col = "#00ff00" if is_bull else "#ff0000"
        signal_dir = 1 if is_bull else -1
    elif is_rising:
        pvsra_txt = "RISING TOURO" if is_bull else "RISING URSO"
        pvsra_col = "#1e90ff" if is_bull else "#ff00ff"
        signal_dir = 1 if is_bull else -1

    return df, df['atr'].iloc[-1], pvsra_txt, pvsra_col, signal_dir

def calculate_dynamic_lot(symbol, risk_percent, sl_points):
    info = mt5.symbol_info(symbol)
    if info is None or sl_points <= 0 or info.trade_tick_size == 0: return 0.0
    
    balance = mt5.account_info().balance
    max_loss_money = balance * (risk_percent / 100.0)
    risk_per_lot = (sl_points / info.trade_tick_size) * info.trade_tick_value
    
    if risk_per_lot == 0: return 0.0
    raw_lot = max_loss_money / risk_per_lot
    normalized_lot = np.floor(raw_lot / info.volume_step) * info.volume_step
    
    # Auditoria de Margem (Impede envio de lote que falharia por falta de dinheiro)
    margin_required = (normalized_lot * 100 * info.ask) / mt5.account_info().leverage
    if margin_required > mt5.account_info().margin_free:
        return 0.0
        
    return max(0.0, round(normalized_lot, 2))

# ==============================================================================
# 4. MOTOR DE EXECUÇÃO (ORDER SEND)
# ==============================================================================
def execute_trade(symbol, order_type, lot_size, sl_points, tp_points):
    """Envia a ordem para a corretora via IPC e audita o Retcode."""
    info = mt5.symbol_info(symbol)
    tick = mt5.symbol_info_tick(symbol)
    
    if order_type == mt5.ORDER_TYPE_BUY:
        price = tick.ask
        sl_price = price - (sl_points * info.point)
        tp_price = price + (tp_points * info.point)
    else:
        price = tick.bid
        sl_price = price + (sl_points * info.point)
        tp_price = price - (tp_points * info.point)

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
        "comment": "GEM_Quant_Exec",
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC # Mitigação de erro de Fill Policy
    }

    result = mt5.order_send(request)
    
    if result.retcode != mt5.TRADE_RETCODE_DONE:
        print(f"[ERRO DE EXECUÇÃO] Retcode: {result.retcode}")
        return False
        
    print(f"[SUCESSO] Ordem Executada. Ticket: {result.order}")
    return True

# ==============================================================================
# 5. THREAD DO MOTOR DE NEGOCIAÇÃO (BACKGROUND)
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
        
        # 1. Auditoria de Posições (Pilar 15)
        posicoes_abertas = mt5.positions_get(symbol=SYMBOL)
        tem_posicao = False if posicoes_abertas is None else len(posicoes_abertas) > 0
        
        # 2. Leitura de Mercado e Cálculo Quantitativo
        df, atr, pvsra_txt, pvsra_col, signal_dir = get_market_data_with_pvsra(SYMBOL, TIMEFRAME, 50)
        
        if df is not None and atr > 0:
            point = mt5.symbol_info(SYMBOL).point
            sl_points = (atr * ATR_MULTIPLIER_SL) / point
            lot_size = calculate_dynamic_lot(SYMBOL, RISK_PERCENT, sl_points)
            
            system_state["atr"] = atr
            system_state["sl_points"] = sl_points
            system_state["lot_size"] = lot_size
            system_state["pvsra_text"] = pvsra_txt
            system_state["pvsra_color"] = pvsra_col
            system_state["last_update"] = datetime.now().strftime('%H:%M:%S')

            # 3. Lógica de Execução e Status
            if tem_posicao:
                system_state["status_msg"] = "Posição Aberta. Gerenciando Risco..."
            elif not system_state["trading_enabled"]:
                system_state["status_msg"] = "Robô PAUSADO. Leitura de dados ativa."
            else:
                system_state["status_msg"] = "Robô ARMADO. Aguardando Gatilho..."
                
                # Gatilho de Entrada: Se PVSRA aponta agressão e o lote é válido
                if signal_dir != 0 and lot_size > 0:
                    
                    # Checagem contra o Nível de Stops do Broker (Geralmente 20 pts)
                    stop_level = mt5.symbol_info(SYMBOL).trade_stops_level
                    if sl_points > stop_level:
                        
                        ordem = mt5.ORDER_TYPE_BUY if signal_dir == 1 else mt5.ORDER_TYPE_SELL
                        tp_points = sl_points * RR_RATIO
                        
                        system_state["status_msg"] = "Enviando Ordem para o Broker..."
                        
                        sucesso = execute_trade(SYMBOL, ordem, lot_size, sl_points, tp_points)
                        
                        if sucesso:
                            # Pausa a thread após a execução para o MT5 atualizar as posições
                            time.sleep(3) 

        time.sleep(2) # Ciclo de varredura (2 segundos)

# ==============================================================================
# 6. INTERFACE GRÁFICA (UI MAIN THREAD)
# ==============================================================================
class TradingDashboard:
    def __init__(self, root):
        self.root = root
        self.root.title("GEM Quant Dashboard - XAUUSD")
        self.root.geometry("450x380")
        self.root.configure(bg="#121212")
        self.root.attributes("-topmost", True)

        font_title = ("Consolas", 14, "bold")
        font_data = ("Consolas", 12)
        font_pvsra = ("Consolas", 13, "bold")
        bg_color = "#121212"

        self.frame = tk.Frame(self.root, bg=bg_color, padx=20, pady=15)
        self.frame.pack(fill=tk.BOTH, expand=True)

        tk.Label(self.frame, text=f"{SYMBOL} | {mt5.TIMEFRAME_M15}", font=font_title, bg=bg_color, fg="#00ff00").pack(pady=(0, 10))
        
        self.lbl_atr = tk.Label(self.frame, text="ATR: --", font=font_data, bg=bg_color, fg="#ffffff")
        self.lbl_atr.pack(anchor="w", pady=2)
        self.lbl_sl = tk.Label(self.frame, text="SL Dinâmico: -- pts", font=font_data, bg=bg_color, fg="#ffffff")
        self.lbl_sl.pack(anchor="w", pady=2)
        self.lbl_lot = tk.Label(self.frame, text="Lote (Risco 1%): --", font=font_data, bg=bg_color, fg="#00ffff")
        self.lbl_lot.pack(anchor="w", pady=2)
        
        tk.Frame(self.frame, height=1, bg="#333333").pack(fill=tk.X, pady=10)
        
        tk.Label(self.frame, text="SINAL PVSRA (Tick/Volume):", font=("Consolas", 10), bg=bg_color, fg="#888888").pack(anchor="w")
        self.lbl_pvsra = tk.Label(self.frame, text="Analisando...", font=font_pvsra, bg=bg_color, fg="#ffffff")
        self.lbl_pvsra.pack(anchor="w", pady=2)

        tk.Frame(self.frame, height=1, bg="#333333").pack(fill=tk.X, pady=10)

        self.lbl_update = tk.Label(self.frame, text="Última Att: --:--:--", font=("Consolas", 9), bg=bg_color, fg="#888888")
        self.lbl_update.pack(anchor="w")

        self.lbl_status = tk.Label(self.frame, text="Status: Inicializando...", font=("Consolas", 10, "italic"), bg=bg_color, fg="#ffcc00")
        self.lbl_status.pack(pady=10)

        self.btn_toggle = tk.Button(self.frame, text="ROBÔ DESLIGADO", font=("Consolas", 12, "bold"), bg="#aa0000", fg="#ffffff", command=self.toggle_trading, width=20, height=2)
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
        self.lbl_sl.config(text=f"SL Dinâmico: {system_state['sl_points']:.0f} pts")
        self.lbl_lot.config(text=f"Lote (Risco 1%): {system_state['lot_size']}")
        self.lbl_pvsra.config(text=system_state['pvsra_text'], fg=system_state['pvsra_color'])
        self.lbl_update.config(text=f"Última Leitura: {system_state['last_update']}")
        
        self.lbl_status.config(text=system_state["status_msg"], fg="#ff0000" if not system_state["connected"] else ("#00ff00" if system_state["trading_enabled"] else "#ffcc00"))
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
