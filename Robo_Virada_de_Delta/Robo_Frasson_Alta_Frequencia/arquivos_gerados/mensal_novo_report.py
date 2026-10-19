import zipfile
import xml.etree.ElementTree as ET
import pandas as pd

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
    rows = s_tree.findall('.//ns:row', ns_s)
    
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
            
            if direction == 'out' and profit_str:
                try:
                    profit = float(profit_str)
                    deals.append({
                        'time': time_val,
                        'profit': profit,
                        'comment': comment
                    })
                except:
                    pass

df = pd.DataFrame(deals)
df['month'] = df['time'].str[:7]
monthly = df.groupby('month')['profit'].agg(['count', 'sum'])
print("=== RESULTADO MÊS A MÊS NO NOVO TESTE ===")
for m, row in monthly.iterrows():
    print(f"Mês {m}: {int(row['count'])} trades | Resultado: ${row['sum']:.2f}")

# Sequencia de lucro e rebaixamento
cum = df['profit'].cumsum()
peak = cum.cummax()
dd = (peak - cum).max()
print(f"\nLucro Total Líquido: ${cum.iloc[-1]:.2f}")
print(f"Drawdown Máximo do Lucro: ${dd:.2f}")
print(f"Taxa de Acerto Geral: {len(df[df['profit']>0])/len(df)*100:.2f}%")
