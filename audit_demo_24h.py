import MetaTrader5 as mt5
from datetime import datetime, timedelta
import pandas as pd

def audit_24h():
    if not mt5.initialize(path=r'C:\MetaTrader\terminal64.exe'):
        print("Erro ao inicializar MT5")
        return

    acc = mt5.account_info()
    now = datetime.now()
    since_24h = now - timedelta(hours=24)

    print("================================================================================")
    print("      AUDITORIA FORENSE QUANTITATIVA: ÚLTIMAS 24 HORAS (CONTA 1062632)         ")
    print("================================================================================")
    print(f"Momento da Auditoria: {now.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Janela de Análise: Desde {since_24h.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Saldo Atual: US$ {acc.balance:.2f} | Patrimônio Líquido: US$ {acc.equity:.2f}")
    print(f"Margem Ocupada: US$ {acc.margin:.2f} | Margem Livre: US$ {acc.margin_free:.2f} | Nível: {acc.margin_level:.1f}%")
    print(f"Alavancagem: 1:{acc.leverage} | Moeda: {acc.currency} | Corretora: {acc.server}")
    print("--------------------------------------------------------------------------------")

    # 1. Posições Abertas Atualmente
    positions = mt5.positions_get()
    print(f"\n[1] POSIÇÕES ABERTAS NO MOMENTO ({len(positions) if positions else 0})")
    total_open_profit = 0.0
    total_open_volume = 0.0
    if positions:
        pos_data = []
        for p in positions:
            p_type = "BUY" if p.type == 0 else "SELL"
            t_str = datetime.fromtimestamp(p.time).strftime("%Y-%m-%d %H:%M:%S")
            pos_data.append({
                "Ticket": p.ticket,
                "Abertura": t_str,
                "Ativo": p.symbol,
                "Tipo": p_type,
                "Lotes": p.volume,
                "Preco_Entrada": p.price_open,
                "Preco_Atual": p.price_current,
                "SL": p.sl,
                "TP": p.tp,
                "Flutuante_USD": p.profit,
                "Swap": p.swap,
                "Magic": p.magic,
                "Comentario": p.comment
            })
            total_open_profit += p.profit + p.swap
            total_open_volume += p.volume
        df_p = pd.DataFrame(pos_data)
        print(df_p.to_string(index=False))
        print(f"\nTotal Flutuante Aberto: US$ {total_open_profit:.2f}")
        print(f"Volume Total Aberto: {total_open_volume:.2f} lotes")
        print(f"Comprometimento de Margem: US$ {acc.margin:.2f} de US$ {acc.equity:.2f} ({acc.margin/acc.equity*100:.1f}%)")
    else:
        print("Nenhuma posição aberta no momento.")

    # 2. Deals nas últimas 24 horas
    deals_24h = mt5.history_deals_get(since_24h, now + timedelta(hours=1))
    print("\n--------------------------------------------------------------------------------")
    print(f"[2] NEGOCIAÇÕES EXECUTADAS (DEALS) NAS ÚLTIMAS 24H ({len(deals_24h) if deals_24h else 0})")

    if deals_24h:
        d_list = []
        for d in deals_24h:
            t_str = datetime.fromtimestamp(d.time).strftime("%Y-%m-%d %H:%M:%S")
            entry_name = {0: "ENTRADA", 1: "SAIDA", 2: "INOUT"}.get(d.entry, str(d.entry))
            deal_type = {0: "BUY", 1: "SELL", 2: "BALANCE"}.get(d.type, str(d.type))
            d_list.append({
                "Ticket": d.ticket,
                "Ordem": d.order,
                "Hora": t_str,
                "Timestamp": d.time,
                "Ativo": d.symbol,
                "Tipo": deal_type,
                "Direcao": entry_name,
                "Lotes": d.volume,
                "Preco": d.price,
                "Lucro_USD": d.profit,
                "Comissao": d.commission,
                "Swap": d.swap,
                "Magic": d.magic,
                "Comentario": d.comment
            })
        df_d = pd.DataFrame(d_list)
        
        # Filtra deals normais (excluindo ajustes de balanço, se houver)
        trade_deals = df_d[df_d["Tipo"] != "BALANCE"].copy()
        entries = trade_deals[trade_deals["Direcao"] == "ENTRADA"]
        exits = trade_deals[trade_deals["Direcao"] == "SAIDA"]

        print(f"Total de Ordens Executadas: {len(trade_deals)} (Aberturas: {len(entries)} | Fechamentos: {len(exits)})")
        
        lucro_bruto = trade_deals["Lucro_USD"].sum()
        comissoes = trade_deals["Comissao"].sum()
        swaps = trade_deals["Swap"].sum()
        lucro_liquido = lucro_bruto + comissoes + swaps

        print(f"Lucro Bruto Fechado: US$ {lucro_bruto:.2f}")
        print(f"Comissões Pagas: US$ {comissoes:.2f}")
        print(f"Swap Pago: US$ {swaps:.2f}")
        print(f"Resultado Líquido Fechado (24h): US$ {lucro_liquido:.2f}")

        # Saldo estimado no início das 24h
        # Saldo_atual = Saldo_inicio + lucro_liquido (mais balanços)
        balance_24h_ago = acc.balance - lucro_liquido
        print(f"\nSaldo Estimado há 24h atrás: US$ {balance_24h_ago:.2f}")
        print(f"Variação no Saldo Fechado: US$ {lucro_liquido:.2f} ({lucro_liquido/balance_24h_ago*100:+.2f}%)")
        print(f"Patrimônio Líquido no momento (Equity): US$ {acc.equity:.2f} (Variação Real Flutuante: US$ {(acc.equity - balance_24h_ago):.2f})")

        print("\n--- HISTÓRICO COMPLETO DE OPERAÇÕES DE SAÍDA (FECHAMENTOS) ---")
        if not exits.empty:
            cols = ["Hora", "Ativo", "Tipo", "Lotes", "Preco", "Lucro_USD", "Comissao", "Comentario"]
            print(exits[cols].to_string(index=False))

        print("\n--- HISTÓRICO DAS ÚLTIMAS 15 OPERAÇÕES DE ENTRADA (ABERTURAS) ---")
        if not entries.empty:
            cols_e = ["Hora", "Ativo", "Tipo", "Lotes", "Preco", "Comissao", "Comentario"]
            print(entries.tail(15)[cols_e].to_string(index=False))

    # 3. Análise dos Ciclos do Robô
    print("\n--------------------------------------------------------------------------------")
    print("[3] COMPORTAMENTO DE MICROESTRUTURA & GESTÃO DE RISCO (ÚLTIMAS 24H)")
    if deals_24h:
        print("Ativos operados:", trade_deals["Ativo"].unique())
        print("Lotes disparados:", sorted(trade_deals["Lotes"].unique()))
        print("Comentários das ordens:", trade_deals["Comentario"].unique())

        # Verifica se há martingale
        multipliers = []
        lotes_ordenados = trade_deals.sort_values("Timestamp")["Lotes"].tolist()
        print(f"Sequência recente de lotes: {lotes_ordenados[-20:]}")

    mt5.shutdown()

if __name__ == "__main__":
    audit_24h()
