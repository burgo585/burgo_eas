import json
import sys

sys.stdout.reconfigure(encoding='utf-8')

def parse_notebook():
    file_path = 'btcusd_guardrail_backtest_v3-output.ipynb'
    with open(file_path, 'r', encoding='utf-8') as f:
        nb = json.load(f)

    print(f"Total de células: {len(nb['cells'])}\n")

    for idx, cell in enumerate(nb['cells']):
        cell_type = cell.get('cell_type', '')
        if cell_type == 'markdown':
            header = ''.join(cell.get('source', []))[:80].replace('\n', ' ')
            print(f"--- [Célula {idx}: MARKDOWN] --- {header}...")
        elif cell_type == 'code':
            exec_count = cell.get('execution_count', None)
            outputs = cell.get('outputs', [])
            print(f"\n=======================================================")
            print(f"=== [Célula {idx}: CÓDIGO (Exec #{exec_count})] ===")
            print(f"=======================================================")
            if not outputs:
                print("(Sem saídas)")
            for out in outputs:
                out_type = out.get('output_type', '')
                if out_type == 'stream':
                    print(''.join(out.get('text', [])))
                elif out_type in ['execute_result', 'display_data']:
                    data = out.get('data', {})
                    if 'text/plain' in data:
                        print(''.join(data['text/plain']))
                elif out_type == 'error':
                    print(f"[ERRO]: {out.get('ename')}: {out.get('evalue')}")
                    for tb in out.get('traceback', [])[-3:]:
                        print(tb)

if __name__ == '__main__':
    parse_notebook()
