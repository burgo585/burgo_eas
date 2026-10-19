import os
import glob
import datetime
import numpy as np
import pandas as pd
import MetaTrader5 as mt5

print("======================================================================")
print("ETAPA 1: MAPEAMENTO FORENSE DO AMBIENTE, ARQUIVOS E ESPECIFICAÇÕES MT5")
print("======================================================================")

paths_to_scan = [
    r"C:\Users\Vini_Burgo\.gemini\antigravity\scratch",
    r"C:\Users\Vini_Burgo\.gemini\antigravity\brain\4148e527-451e-4431-8215-17e8fa4d8cd6",
    r"C:\Users\Vini_Burgo\AppData\Roaming\MetaQuotes\Terminal\5A1174AE1007A2760EEEF72EC2A459D5\MQL5\Experts",
    r"C:\Users\Vini_Burgo\AppData\Roaming\MetaQuotes\Terminal\5A1174AE1007A2760EEEF72EC2A459D5\MQL5\Profiles\Tester",
    r"C:\Users\Vini_Burgo\AppData\Roaming\MetaQuotes\Terminal\5A1174AE1007A2760EEEF72EC2A459D5\config"
]

for base in paths_to_scan:
    if os.path.exists(base):
        print(f"\n[Diretório]: {base}")
        for root, dirs, files in os.walk(base):
            if ".system_generated" in root or "__pycache__" in root:
                continue
            for f in files:
                if f.endswith(('.py', '.mq5', '.ex5', '.set', '.ini', '.html', '.csv', '.json')):
                    full_p = os.path.join(root, f)
                    sz = os.path.getsize(full_p)
                    mtime = datetime.datetime.fromtimestamp(os.path.getmtime(full_p)).strftime('%Y-%m-%d %H:%M:%S')
                    print(f"  - {full_p} | {sz:,} bytes | Modificado: {mtime}")

print("\n======================================================================")
print("INSPEÇÃO DAS ESPECIFICAÇÕES REAIS DO ATIVO XAUUSD-ECN NO MT5")
print("======================================================================")
if mt5.initialize(path=r"C:\MetaTrader\terminal64.exe"):
    acc = mt5.account_info()
    if acc:
        print(f"Conta MT5: Login={acc.login} | Servidor={acc.server} | Alavancagem={acc.leverage} | Saldo={acc.balance} | Moeda={acc.currency}")
    sym = mt5.symbol_info("XAUUSD-ECN")
    if sym:
        print(f"Símbolo: {sym.name}")
        print(f"  Digits: {sym.digits} | Point: {sym.point}")
        print(f"  Contract Size: {sym.trade_contract_size}")
        print(f"  Spread Atual: {sym.spread} pontos (${sym.spread * sym.point:.2f}) | Spread Float: {sym.spread_float}")
        print(f"  Stops Level: {sym.trade_stops_level} pontos")
        print(f"  Swap Long: {sym.swap_long} | Swap Short: {sym.swap_short} | Swap Mode: {sym.swap_mode} | Swap Rollover 3Days: {sym.swap_rollover3days}")
        print(f"  Volume Min: {sym.volume_min} | Step: {sym.volume_step} | Max: {sym.volume_max}")
        print(f"  Trade Calc Mode: {sym.trade_calc_mode}")

    # Extrair dados M15 reais com coluna 'spread' e 'real_volume'/'tick_volume'
    utc_from = datetime.datetime(2024, 1, 1)
    utc_to = datetime.datetime(2026, 10, 19, 23, 59)
    rates = mt5.copy_rates_range("XAUUSD-ECN", mt5.TIMEFRAME_M15, utc_from, utc_to)
    mt5.shutdown()

    df = pd.DataFrame(rates)
    df['time'] = pd.to_datetime(df['time'], unit='s')
    print(f"\nDados Históricos M15: {len(df)} barras ({df['time'].iloc[0]} até {df['time'].iloc[-1]})")
    print(f"Spread registrado nas barras M15 (em pontos): Min={df['spread'].min()}, Mediana={df['spread'].median()}, Média={df['spread'].mean():.1f}, P95={df['spread'].quantile(0.95):.1f}, Max={df['spread'].max()}")
else:
    print("Falha ao inicializar MT5")
