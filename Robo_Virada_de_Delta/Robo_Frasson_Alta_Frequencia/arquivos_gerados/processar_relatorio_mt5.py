import zipfile
import xml.etree.ElementTree as ET
import pandas as pd
import numpy as np

excel_path = r'C:\Robo Virada de Delta\Robo_Frasson_Alta_Frequencia_PRO\ReportTester-26570143.xlsx'

with zipfile.ZipFile(excel_path, 'r') as z:
    shared_strings = []
    if 'xl/sharedStrings.xml' in z.namelist():
        tree = ET.fromstring(z.read('xl/sharedStrings.xml'))
        ns = {'ns': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
        for si in tree.findall('.//ns:si', ns):
            texts = [t.text for t in si.findall('.//ns:t', ns) if t.text]
            shared_strings.append(''.join(texts))

    s_tree = ET.fromstring(z.read('xl/worksheets/sheet1.xml'))
    ns_s = {'ns': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
    
    deals = []
    in_deals_section = False
    
    for r in s_tree.findall('.//ns:row', ns_s):
        row_idx = int(r.attrib.get('r'))
        cells = {}
        for c in r.findall('ns:c', ns_s):
            ref = c.attrib.get('r')
            col = ''.join([ch for ch in ref if ch.isalpha()])
            t = c.attrib.get('t')
            v = c.find('ns:v', ns_s)
            val = v.text if v is not None else ''
            if t == 's' and val:
                val = shared_strings[int(val)]
            cells[col] = val
            
        a_val = cells.get('A', '')
        if 'Negociações' in a_val or 'Transações' in a_val:
            in_deals_section = True
            continue
            
        if in_deals_section:
            # Colunas de negociações no MT5:
            # A: Horário, B: Transação, C: Ativo, D: Tipo, E: Direção, F: Volume, G: Preço, H: Ordem, I: Comissão, J: Swap, K: Lucro, L: Saldo, M: Comentário
            time_val = cells.get('A', '')
            deal_id = cells.get('B', '')
            direction = cells.get('E', '') # in / out
            profit_str = cells.get('K', '')
            balance_str = cells.get('L', '')
            comment = cells.get('M', '')
            volume_str = cells.get('F', '')
            price_str = cells.get('G', '')
            deal_type = cells.get('D', '')
            
            if direction == 'out' and profit_str:
                try:
                    profit = float(profit_str)
                    vol = float(volume_str) if volume_str else 0.0
                    price = float(price_str) if price_str else 0.0
                    deals.append({
                        'time': time_val,
                        'profit': profit,
                        'comment': comment,
                        'vol': vol,
                        'price': price,
                        'type': deal_type
                    })
                except:
                    pass

df_deals = pd.DataFrame(deals)
print(f"Total de saídas (deals 'out') extraídas: {len(df_deals)}")

if len(df_deals) > 0:
    wins = df_deals[df_deals['profit'] > 0]
    losses = df_deals[df_deals['profit'] < 0]
    evens = df_deals[df_deals['profit'] == 0]
    
    print("\n" + "="*70)
    print("ANÁLISE QUANTITATIVA DOS TRADES DO TESTE (ReportTester-26570143.xlsx):")
    print("="*70)
    print(f"Total de saídas: {len(df_deals)}")
    print(f"Vitórias: {len(wins)} ({len(wins)/len(df_deals)*100:.2f}%)")
    print(f"Derrotas: {len(losses)} ({len(losses)/len(df_deals)*100:.2f}%)")
    print(f"Empates (Zero/BE): {len(evens)} ({len(evens)/len(df_deals)*100:.2f}%)")
    print(f"Lucro Bruto: ${wins['profit'].sum():.2f}")
    print(f"Prejuízo Bruto: ${losses['profit'].sum():.2f}")
    print(f"Lucro Líquido: ${df_deals['profit'].sum():.2f}")
    print(f"Maior Ganho: ${wins['profit'].max():.2f}")
    print(f"Maior Perda: ${losses['profit'].min():.2f}")
    print(f"Ganho Médio: ${wins['profit'].mean():.2f}")
    print(f"Perda Média: ${losses['profit'].mean():.2f}")
    
    # Análise dos Comentários (TP vs SL)
    print("\n--- DISTRIBUIÇÃO POR TIPO DE SAÍDA ---")
    tp_exits = df_deals[df_deals['comment'].str.startswith('tp', na=False)]
    sl_exits = df_deals[df_deals['comment'].str.startswith('sl', na=False)]
    print(f"Saídas por Take Profit (TP): {len(tp_exits)} ({len(tp_exits)/len(df_deals)*100:.1f}%) | Lucro: ${tp_exits['profit'].sum():.2f}")
    print(f"Saídas por Stop Loss / BE (SL): {len(sl_exits)} ({len(sl_exits)/len(df_deals)*100:.1f}%) | Lucro: ${sl_exits['profit'].sum():.2f}")
    
    # Análise de saídas no Breakeven dentro dos SLs
    sl_be = sl_exits[sl_exits['profit'] >= 0]
    sl_real_loss = sl_exits[sl_exits['profit'] < 0]
    print(f"   -> SL no Breakeven (lucro >= $0): {len(sl_be)} trades (Lucro acumulado: ${sl_be['profit'].sum():.2f})")
    print(f"   -> SL Real (Stop de Perda): {len(sl_real_loss)} trades (Prejuízo acumulado: ${sl_real_loss['profit'].sum():.2f})")
    
    # Agrupamento mensal
    df_deals['month'] = df_deals['time'].str[:7]
    monthly = df_deals.groupby('month')['profit'].agg(['count', 'sum'])
    print("\n--- RESULTADO MÊS A MÊS ---")
    for m, row in monthly.iterrows():
        print(f"Mês {m}: {int(row['count'])} trades | Resultado: ${row['sum']:.2f}")
