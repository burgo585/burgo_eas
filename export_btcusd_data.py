import os
import sys
import argparse
from datetime import datetime, timezone
import MetaTrader5 as mt5
import pandas as pd

# ==============================================================================
# CONFIGURAÇÃO PADRÃO
# ==============================================================================
MT5_PATH = r"C:\Program Files\MetaTrader 5\terminal64.exe"
ACCOUNT_LOGIN = 1123867
ACCOUNT_PASSWORD = "Louco123123@"
ACCOUNT_SERVER = "VTMarkets-Demo"
DEFAULT_SYMBOL = "BTCUSD"

TIMEFRAME_MAP = {
    "M1": mt5.TIMEFRAME_M1,
    "M5": mt5.TIMEFRAME_M5,
    "M15": mt5.TIMEFRAME_M15,
    "M30": mt5.TIMEFRAME_M30,
    "H1": mt5.TIMEFRAME_H1,
    "H4": mt5.TIMEFRAME_H4,
    "D1": mt5.TIMEFRAME_D1,
}

def connect_mt5(path=MT5_PATH, login=ACCOUNT_LOGIN, password=ACCOUNT_PASSWORD, server=ACCOUNT_SERVER):
    print("Conectando ao MetaTrader 5...")
    if not mt5.initialize(path=path, login=login, password=password, server=server, timeout=60000):
        print(f"[ERRO] Falha ao inicializar MT5: {mt5.last_error()}")
        return False
    
    acc = mt5.account_info()
    if acc:
        print(f"[OK] Conectado: Conta {acc.login} | Servidor: {acc.server} | Saldo: ${acc.balance:,.2f}")
    return True

def fetch_massive_bars(symbol=DEFAULT_SYMBOL, tf_str="M15", max_total_bars=500000, chunk_size=50000):
    if tf_str not in TIMEFRAME_MAP:
        raise ValueError(f"Timeframe inválido: {tf_str}. Opções: {list(TIMEFRAME_MAP.keys())}")
    
    tf = TIMEFRAME_MAP[tf_str]
    
    if not mt5.symbol_select(symbol, True):
        print(f"[ERRO] Falha ao selecionar símbolo {symbol}: {mt5.last_error()}")
        return None

    print(f"\n--- Iniciando extração massiva: {symbol} [{tf_str}] ---")
    all_chunks = []
    current_time_anchor = datetime.now(timezone.utc)
    total_collected = 0

    while total_collected < max_total_bars:
        fetch_count = min(chunk_size, max_total_bars - total_collected)
        rates = mt5.copy_rates_from(symbol, tf, current_time_anchor, fetch_count)
        
        if rates is None or len(rates) == 0:
            print(f"[*] Fim do histórico disponível da corretora ou sem mais dados.")
            break
        
        df_chunk = pd.DataFrame(rates)
        all_chunks.append(df_chunk)
        total_collected += len(df_chunk)
        
        earliest_epoch = df_chunk['time'].min()
        earliest_dt = datetime.fromtimestamp(earliest_epoch, tz=timezone.utc)
        print(f"  + Lote extraído: {len(df_chunk):>6} barras | Ponto mais antigo do lote: {earliest_dt.strftime('%Y-%m-%d %H:%M:%S UTC')}")
        
        # Se veio menos que o requisitado, chegamos ao início da história da corretora
        if len(df_chunk) < fetch_count:
            print("[*] Todas as barras disponíveis na corretora foram extraídas.")
            break
            
        # Move a âncora para antes da barra mais antiga do lote atual
        current_time_anchor = earliest_dt
        if len(all_chunks) > 1 and all_chunks[-1]['time'].min() == all_chunks[-2]['time'].min():
            print("[*] Paginação estabilizada no início do histórico.")
            break

    if not all_chunks:
        print("[AVISO] Nenhuma barra foi recuperada.")
        return None

    # Consolida e limpa dados
    df = pd.concat(all_chunks, ignore_index=True)
    df.drop_duplicates(subset=['time'], inplace=True)
    df.sort_values(by='time', ascending=True, inplace=True)
    df.reset_index(drop=True, inplace=True)

    # Converte timestamp para datetime legível
    df['datetime'] = pd.to_datetime(df['time'], unit='s', utc=True)
    
    # Reorganiza colunas
    cols = ['datetime', 'open', 'high', 'low', 'close', 'tick_volume', 'spread', 'real_volume', 'time']
    df = df[[c for c in cols if c in df.columns]]

    start_date = df['datetime'].iloc[0].strftime('%Y-%m-%d %H:%M:%S')
    end_date = df['datetime'].iloc[-1].strftime('%Y-%m-%d %H:%M:%S')
    print(f"\n[SUCESSO] Total consolidado: {len(df):,} barras")
    print(f"Período: {start_date} até {end_date} (UTC)")
    
    return df

def save_datasets(df, symbol, tf_str, output_dir="data"):
    os.makedirs(output_dir, exist_ok=True)
    
    base_name = f"{symbol}_{tf_str}"
    parquet_path = os.path.join(output_dir, f"{base_name}.parquet")
    csv_path = os.path.join(output_dir, f"{base_name}.csv.gz")
    
    # Salvar em Parquet
    df.to_parquet(parquet_path, engine="pyarrow", index=False)
    parquet_mb = os.path.getsize(parquet_path) / (1024 * 1024)
    print(f"[ARQUIVO] Parquet salvo: {parquet_path} ({parquet_mb:.2f} MB)")
    
    # Salvar em CSV compactado (.csv.gz)
    df.to_csv(csv_path, index=False, compression="gzip")
    csv_mb = os.path.getsize(csv_path) / (1024 * 1024)
    print(f"[ARQUIVO] CSV.GZ salvo:  {csv_path} ({csv_mb:.2f} MB)")
    
    return parquet_path, csv_path

def main():
    parser = argparse.ArgumentParser(description="Extração massiva de dados históricos MT5")
    parser.add_argument("--symbol", type=str, default=DEFAULT_SYMBOL, help="Símbolo MT5 (ex: BTCUSD)")
    parser.add_argument("--tf", type=str, default="M15", help="Timeframe (M1, M5, M15, M30, H1, H4, D1)")
    parser.add_argument("--max_bars", type=int, default=500000, help="Quantidade máxima de barras a extrair")
    parser.add_argument("--all_tfs", action="store_true", help="Extrair múltiplos timeframes chave (M5, M15, H1, D1)")
    
    args = parser.parse_args()
    
    if not connect_mt5():
        sys.exit(1)
        
    try:
        tfs_to_run = ["M5", "M15", "H1", "D1"] if args.all_tfs else [args.tf.upper()]
        for tf in tfs_to_run:
            df = fetch_massive_bars(symbol=args.symbol, tf_str=tf, max_total_bars=args.max_bars)
            if df is not None and not df.empty:
                save_datasets(df, args.symbol, tf)
    finally:
        mt5.shutdown()
        print("\nDesconectado do MT5 com sucesso.")

if __name__ == "__main__":
    main()
