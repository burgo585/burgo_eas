import MetaTrader5 as mt5
from datetime import datetime, timedelta
import pandas as pd

def check_account(path, desc):
    print("=" * 75)
    print(f"AUDITORIA FORENSE: {desc} ({path})")
    print("=" * 75)
    if not mt5.initialize(path=path):
        print("Falha ao inicializar MT5:", mt5.last_error())
        return
    acc = mt5.account_info()
    if not acc:
        print("Falha ao obter account_info")
        mt5.shutdown()
        return
    print(f"Login: {acc.login} | Servidor: {acc.server} | Moeda: {acc.currency} | Alavancagem: 1:{acc.leverage}")
    print(f"Saldo (Balance): US$ {acc.balance:.2f} | Patrimonio Liquido (Equity): US$ {acc.equity:.2f}")
    print(f"Margem: US$ {acc.margin:.2f} | Margem Livre: US$ {acc.margin_free:.2f} | Nivel: {acc.margin_level:.1f}%")

    # 1. Posições Abertas Agora
    positions = mt5.positions_get()
    print(f"\n--- POSICOES ABERTAS AGORA ({len(positions) if positions else 0}) ---")
    if positions:
        for p in positions:
            p_type = 'BUY' if p.type == 0 else 'SELL'
            t_str = datetime.fromtimestamp(p.time).strftime('%Y-%m-%d %H:%M:%S')
            print(f"Ticket: {p.ticket} | {p_type} {p.volume:.2f} {p.symbol} @ {p.price_open:.2f} -> Atual: {p.price_current:.2f} | Flutuante: US$ {p.profit:.2f} | Magic: {p.magic} | Comentário: '{p.comment}' | Aberto: {t_str}")
    else:
        print("Nenhuma posicao aberta no momento.")

    # 2. Deals de ontem e hoje
    now = datetime.now()
    since = now - timedelta(hours=36)
    deals = mt5.history_deals_get(since, now + timedelta(hours=2))
    print(f"\n--- HISTORICO DE DEALS DESDE ONTEM ({len(deals) if deals else 0}) ---")
    if deals:
        rows = []
        for d in deals:
            if d.type == 2: # Balance
                print(f"[BALANCE/DEPOSITO] Ticket: {d.ticket} | Valor: US$ {d.profit:.2f} | Comentário: '{d.comment}' | Hora: {datetime.fromtimestamp(d.time)}")
                continue
            rows.append({
                'Time': datetime.fromtimestamp(d.time),
                'TimeStr': datetime.fromtimestamp(d.time).strftime('%Y-%m-%d %H:%M:%S'),
                'Symbol': d.symbol,
                'Type': 'BUY' if d.type == 0 else 'SELL',
                'Entry': {0: 'IN', 1: 'OUT', 2: 'INOUT'}.get(d.entry, str(d.entry)),
                'Lots': d.volume,
                'Price': d.price,
                'Profit': d.profit,
                'Comm': d.commission,
                'Swap': d.swap,
                'Magic': d.magic,
                'Comment': d.comment,
                'Order': d.order,
                'Ticket': d.ticket
            })
        df = pd.DataFrame(rows)
        if not df.empty:
            outs = df[df['Entry'] == 'OUT']
            print(f"Total de Fechamentos (Saídas): {len(outs)}")
            lucro_bruto = df['Profit'].sum()
            comm = df['Comm'].sum()
            swap = df['Swap'].sum()
            liq = lucro_bruto + comm + swap
            print(f"Lucro Bruto Fechado: US$ {lucro_bruto:.2f}")
            print(f"Comissoes Pagas: US$ {comm:.2f}")
            print(f"Swap Pago: US$ {swap:.2f}")
            print(f"Resultado Liquido Fechado: US$ {liq:.2f}")
            
            print("\n--- TODOS OS FECHAMENTOS (SAIDAS) DE HOJE ---")
            today_start = datetime(now.year, now.month, now.day)
            outs_today = outs[outs['Time'] >= today_start]
            if not outs_today.empty:
                print(outs_today[['TimeStr', 'Symbol', 'Type', 'Lots', 'Price', 'Profit', 'Comm', 'Swap', 'Magic', 'Comment']].to_string(index=False))
            else:
                print("Nenhum fechamento registrado hoje.")
                print("\nUltimos 15 fechamentos gerais:")
                print(outs.tail(15)[['TimeStr', 'Symbol', 'Type', 'Lots', 'Price', 'Profit', 'Comm', 'Swap', 'Magic', 'Comment']].to_string(index=False))

    mt5.shutdown()

if __name__ == '__main__':
    check_account(r'C:\MetaTrader\terminal64.exe', 'Terminal Principal (Conta 1062632)')
    check_account(r'C:\Program Files\MetaTrader 5 - Copia\terminal64.exe', 'Terminal Copia (Conta 26570143)')
    check_account(r'C:\Program Files\MetaTrader 5\terminal64.exe', 'Terminal Secundario (Conta 1123867)')
