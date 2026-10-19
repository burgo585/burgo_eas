import zipfile
import xml.etree.ElementTree as ET
import pandas as pd
import numpy as np

excel_path = r'C:\Robo Virada de Delta\Robo_Frasson_Alta_Frequencia_PRO\ReportTester-265701434.xlsx'

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
    
    print("=== CABEÇALHO E CONFIGURAÇÃO DO TESTE ===")
    rows = s_tree.findall('.//ns:row', ns_s)
    for r in rows[:70]:
        row_idx = int(r.attrib.get('r'))
        cells = []
        for c in r.findall('ns:c', ns_s):
            ref = c.attrib.get('r')
            t = c.attrib.get('t')
            v = c.find('ns:v', ns_s)
            val = v.text if v is not None else ''
            if t == 's' and val:
                val = shared_strings[int(val)]
            if val:
                cells.append(f'{ref}: {val}')
        if cells:
            print(f'L{row_idx:02d}: ' + ' | '.join(cells))

    # Extrair transações
    deals = []
    in_deals = False
    for r in rows:
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
            in_deals = True
            continue
            
        if in_deals:
            direction = cells.get('E', '')
            profit_str = cells.get('K', '')
            time_val = cells.get('A', '')
            comment = cells.get('M', '')
            vol_str = cells.get('F', '')
            price_str = cells.get('G', '')
            deal_type = cells.get('D', '')
            
            if direction == 'out' and profit_str:
                try:
                    profit = float(profit_str)
                    vol = float(vol_str) if vol_str else 0.0
                    deals.append({
                        'time': time_val,
                        'profit': profit,
                        'comment': comment,
                        'vol': vol,
                        'type': deal_type
                    })
                except:
                    pass

df = pd.DataFrame(deals)
print(f"\nTotal de negociações finalizadas (out): {len(df)}")
if len(df) > 0:
    wins = df[df['profit'] > 0]
    losses = df[df['profit'] < 0]
    evens = df[df['profit'] == 0]
    
    print("\n=== ESTATÍSTICAS DOS TRADES ===")
    print(f"Vitórias: {len(wins)} ({len(wins)/len(df)*100:.2f}%)")
    print(f"Derrotas: {len(losses)} ({len(losses)/len(df)*100:.2f}%)")
    print(f"Breakeven/Zero: {len(evens)} ({len(evens)/len(df)*100:.2f}%)")
    print(f"Lucro Bruto: ${wins['profit'].sum():.2f}")
    print(f"Prejuízo Bruto: ${losses['profit'].sum():.2f}")
    print(f"Lucro Líquido: ${df['profit'].sum():.2f}")
    print(f"Maior Ganho: ${wins['profit'].max():.2f}")
    print(f"Maior Perda: ${losses['profit'].min():.2f}")
    print(f"Ganho Médio: ${wins['profit'].mean():.2f}")
    print(f"Perda Média: ${losses['profit'].mean():.2f}")
    
    # Comentários de saída
    tp_c = df[df['comment'].str.startswith('tp', na=False)]
    sl_c = df[df['comment'].str.startswith('sl', na=False)]
    print(f"\nSaídas por Take Profit: {len(tp_c)} | Lucro: ${tp_c['profit'].sum():.2f}")
    print(f"Saídas por Stop Loss/BE: {len(sl_c)} | Lucro: ${sl_c['profit'].sum():.2f}")
