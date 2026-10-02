import json

def update_notebook():
    file_path = 'btcusd_guardrail_backtest_v3.ipynb'
    with open(file_path, 'r', encoding='utf-8') as f:
        nb = json.load(f)

    # 1. Update Markdown header (Cell 0)
    source_0 = nb['cells'][0]['source']
    for i, line in enumerate(source_0):
        if '10.000' in line:
            source_0[i] = line.replace('10.000', '1.000')
        if '$10,000' in line:
            source_0[i] = line.replace('$10,000', '$1,000')

    # 2. Update Cell 6 (Function definition default parameter)
    source_6 = nb['cells'][6]['source']
    for i, line in enumerate(source_6):
        if 'initial_capital=10000.0' in line:
            source_6[i] = line.replace('initial_capital=10000.0', 'initial_capital=1000.0')

    # 3. Update Cell 8 (Execution call and report text)
    source_8 = nb['cells'][8]['source']
    for i, line in enumerate(source_8):
        if 'initial_capital=10000.0' in line:
            source_8[i] = line.replace('initial_capital=10000.0', 'initial_capital=1000.0')
        if 'net_profit = final_balance - 10000.0' in line:
            source_8[i] = line.replace('10000.0', '1000.0')
        if 'total_return_pct = (net_profit / 10000.0)' in line:
            source_8[i] = line.replace('10000.0', '1000.0')
        if '$10,000.00' in line:
            source_8[i] = line.replace('$10,000.00', '$1,000.00 (Saldo Real da Conta)')

    # 4. Update Cell 10 (Chart baseline and title)
    source_10 = nb['cells'][10]['source']
    for i, line in enumerate(source_10):
        if '[10000.0]*len(equity_df)' in line:
            source_10[i] = line.replace('10000.0', '1000.0')
        if '$10k' in line:
            source_10[i] = line.replace('$10k', '$1k')
        if '$10,000' in line:
            source_10[i] = line.replace('$10,000', '$1,000')

    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(nb, f, indent=1)

    print("[SUCESSO] btcusd_guardrail_backtest_v3.ipynb atualizado com o saldo REAL de $1,000.00!")

if __name__ == '__main__':
    update_notebook()
