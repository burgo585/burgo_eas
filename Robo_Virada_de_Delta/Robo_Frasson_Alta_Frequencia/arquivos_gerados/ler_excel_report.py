import zipfile
import xml.etree.ElementTree as ET
import re

excel_path = r'C:\Robo Virada de Delta\Robo_Frasson_Alta_Frequencia_PRO\ReportTester-26570143.xlsx'

with zipfile.ZipFile(excel_path, 'r') as z:
    # 1. Carregar sharedStrings se existir
    shared_strings = []
    if 'xl/sharedStrings.xml' in z.namelist():
        tree = ET.fromstring(z.read('xl/sharedStrings.xml'))
        ns = {'ns': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
        for si in tree.findall('.//ns:si', ns):
            # Pode ter tags <t> diretas ou em <r><t>
            texts = [t.text for t in si.findall('.//ns:t', ns) if t.text]
            shared_strings.append(''.join(texts))

    # 2. Ler workbook para pegar os nomes das planilhas
    wb_tree = ET.fromstring(z.read('xl/workbook.xml'))
    ns_wb = {'ns': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
             'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'}
    sheets = []
    for sheet in wb_tree.findall('.//ns:sheet', ns_wb):
        sheets.append((sheet.attrib.get('name'), sheet.attrib.get('sheetId')))
    
    print("Planilhas encontradas:", sheets)

    # 3. Ler sheets
    sheet_files = [f for f in z.namelist() if f.startswith('xl/worksheets/sheet') and f.endswith('.xml')]
    sheet_files.sort()
    
    for s_file in sheet_files:
        print(f"\n==================== ARQUIVO: {s_file} ====================")
        s_tree = ET.fromstring(z.read(s_file))
        ns_s = {'ns': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
        
        rows = s_tree.findall('.//ns:row', ns_s)
        for r in rows:
            row_idx = r.attrib.get('r')
            cells = []
            for c in r.findall('ns:c', ns_s):
                cell_ref = c.attrib.get('r')
                cell_type = c.attrib.get('t')
                v = c.find('ns:v', ns_s)
                val = v.text if v is not None else ""
                
                if cell_type == 's' and val:
                    val = shared_strings[int(val)]
                
                cells.append((cell_ref, val))
            
            # Formatar linha
            if any(val for _, val in cells):
                line_str = " | ".join(f"{ref}: {val}" for ref, val in cells if val)
                print(f"Linha {row_idx:3s}: {line_str}")
