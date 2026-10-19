import json
import base64
import io
import pandas as pd

def embed_data():
    parquet_path = 'data/BTCUSD_M15.parquet'
    notebook_path = 'btcusd_guardrail_backtest_v3.ipynb'
    
    print(f"Lendo {parquet_path}...")
    df = pd.read_parquet(parquet_path)
    cols = ['datetime', 'open', 'high', 'low', 'close', 'tick_volume', 'spread']
    df_small = df[cols].copy()
    
    buf = io.BytesIO()
    df_small.to_parquet(buf, compression='gzip', index=False)
    buf.seek(0)
    b64_str = base64.b64encode(buf.read()).decode('utf-8')
    print(f"Tamanho da string base64: {len(b64_str):,} caracteres (~{len(b64_str)/(1024*1024):.2f} MB)")
    
    print(f"Carregando {notebook_path}...")
    with open(notebook_path, 'r', encoding='utf-8') as f:
        nb = json.load(f)
        
    code_lines = [
        '# @title 📦 1. Base de Dados Histórica Embutida (BTCUSD M15 - 88.776 Barras) { display-mode: "form" }\n',
        '# O DataFrame está 100% embutido diretamente neste arquivo .ipynb em formato comprimido.\n',
        '# Nenhum upload de arquivo é necessário! Basta executar esta célula.\n',
        '\n',
        'import base64\n',
        'import io\n',
        'import pandas as pd\n',
        'import numpy as np\n',
        'import plotly.graph_objects as go\n',
        'from plotly.subplots import make_subplots\n',
        '\n',
        'print("[+] Decodificando DataFrame embutido no próprio notebook...")\n',
        f'_EMBEDDED_DATA = """{b64_str}"""\n',
        '\n',
        'df = pd.read_parquet(io.BytesIO(base64.b64decode(_EMBEDDED_DATA)))\n',
        'df["datetime"] = pd.to_datetime(df["datetime"])\n',
        'df.sort_values("datetime", inplace=True)\n',
        'df.reset_index(drop=True, inplace=True)\n',
        '\n',
        'print(f"[SUCESSO] DataFrame carregado: {len(df):,} barras!")\n',
        'print(f"[PERÍODO] {df[\'datetime\'].min()} até {df[\'datetime\'].max()} (UTC)")\n',
        'try:\n',
        '    display(df.head())\n',
        'except NameError:\n',
        '    print(df.head())\n'
    ]
    
    # Substitui a célula 2 (índice 2)
    nb['cells'][2]['source'] = code_lines
    
    with open(notebook_path, 'w', encoding='utf-8') as f:
        json.dump(nb, f, indent=1)
        
    print("[SUCESSO] Notebook atualizado com o DataFrame embutido diretamente no arquivo!")

if __name__ == '__main__':
    embed_data()
