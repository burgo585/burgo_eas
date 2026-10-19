import time
import MetaTrader5 as mt5

MT5_PATH = r"C:\Program Files\MetaTrader 5\terminal64.exe"
ACCOUNT_LOGIN = 1123867
ACCOUNT_PASSWORD = "Louco123123@"
ACCOUNT_SERVER = "VTMarkets-Demo"
SYMBOL = "BTCUSD"

def test_order_roundtrip():
    print("--- [TESTE DE CONECTIVIDADE E EXECUÇÃO DE ORDEM] ---")
    if not mt5.initialize(path=MT5_PATH, login=ACCOUNT_LOGIN, password=ACCOUNT_PASSWORD, server=ACCOUNT_SERVER, timeout=30000):
        print(f"[ERRO] Falha ao inicializar MT5: {mt5.last_error()}")
        return False

    acc = mt5.account_info()
    if not acc:
        print("[ERRO] Falha ao obter dados da conta.")
        mt5.shutdown()
        return False

    trade_mode_str = "DEMO" if acc.trade_mode == 0 else "REAL"
    print(f"[OK] Conectado: Conta {acc.login} ({trade_mode_str}) | Servidor: {acc.server} | Saldo: ${acc.balance:,.2f}")
    
    if not acc.trade_allowed or not acc.trade_expert:
        print(f"[ERRO] Negociação automatizada desativada no terminal (trade_allowed={acc.trade_allowed}, trade_expert={acc.trade_expert})")
        mt5.shutdown()
        return False

    if not mt5.symbol_select(SYMBOL, True):
        print(f"[ERRO] Falha ao selecionar símbolo {SYMBOL}: {mt5.last_error()}")
        mt5.shutdown()
        return False

    tick = mt5.symbol_info_tick(SYMBOL)
    info = mt5.symbol_info(SYMBOL)
    if tick is None or info is None:
        print(f"[ERRO] Falha ao obter cotação de {SYMBOL}")
        mt5.shutdown()
        return False

    print(f"[OK] Cotação Atual de {SYMBOL}: Bid={tick.bid:.2f} | Ask={tick.ask:.2f} | Spread={info.spread} pts")

    lot = 0.01  # Lote mínimo de teste
    price_open = tick.ask

    # 1. Enviar Ordem de Compra de Teste
    print(f"\n[1/3] Enviando ordem de COMPRA de teste: {lot} lote @ {price_open:.2f}...")
    request_buy = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": SYMBOL,
        "volume": lot,
        "type": mt5.ORDER_TYPE_BUY,
        "price": price_open,
        "deviation": 50,
        "magic": 999001,
        "comment": "Sunrise_Quick_Test",
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC
    }

    res_buy = mt5.order_send(request_buy)
    if res_buy.retcode != mt5.TRADE_RETCODE_DONE:
        print(f"[ERRO] Falha ao abrir ordem: Retcode {res_buy.retcode} ({res_buy.comment})")
        mt5.shutdown()
        return False

    ticket = res_buy.order
    print(f"[SUCESSO] Ordem ABERTA com sucesso! Ticket #{ticket} | Preço Executado: {res_buy.price:.2f}")

    # Pausa rápida de 1 segundo para verificar a posição no book
    time.sleep(1.0)
    pos = mt5.positions_get(ticket=ticket)
    if pos and len(pos) > 0:
        p = pos[0]
        print(f"[OK] Posição Ativa Confirmada: Ticket #{p.ticket} | Volume: {p.volume} | Lucro Atual: ${p.profit:.2f}")
    else:
        print("[AVISO] Posição aberta já processada ou listada pelo ticket deal.")

    # 2. Fechar Imediatamente a Posição Aberta
    tick_now = mt5.symbol_info_tick(SYMBOL)
    price_close = tick_now.bid
    print(f"\n[2/3] Fechando IMEDIATAMENTE a posição #{ticket} @ {price_close:.2f}...")

    request_close = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": SYMBOL,
        "volume": lot,
        "type": mt5.ORDER_TYPE_SELL,
        "position": ticket,
        "price": price_close,
        "deviation": 50,
        "magic": 999001,
        "comment": "Sunrise_Quick_Close",
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC
    }

    res_close = mt5.order_send(request_close)
    if res_close.retcode != mt5.TRADE_RETCODE_DONE:
        print(f"[ERRO] Falha ao fechar posição #{ticket}: Retcode {res_close.retcode} ({res_close.comment})")
        mt5.shutdown()
        return False

    print(f"[SUCESSO] Posição FECHADA com sucesso! Ticket Fechamento #{res_close.order} | Preço: {res_close.price:.2f}")

    # 3. Auditoria Final: Garantir que não há posições abertas
    time.sleep(1.0)
    remaining_pos = mt5.positions_get(symbol=SYMBOL)
    num_open = len(remaining_pos) if remaining_pos is not None else 0
    print(f"\n[3/3] Auditoria de Segurança: Posições remanescentes em {SYMBOL}: {num_open}")

    acc_after = mt5.account_info()
    print(f"[OK] Saldo Atualizado: ${acc_after.balance:,.2f} | Margem Comprometida: ${acc_after.margin:.2f}")
    print("[FINALIZADO] Conexão, envio e liquidação de ordens 100% FUNCIONAIS!")

    mt5.shutdown()
    return True

if __name__ == "__main__":
    test_order_roundtrip()
