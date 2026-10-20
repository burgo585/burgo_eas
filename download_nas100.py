import MetaTrader5 as mt5
import pandas as pd
import os

def download_data():
    if not mt5.initialize(path=r'C:\Program Files\MetaTrader 5\terminal64.exe'):
        print('MT5 init failed')
        return

    sym = 'NAS100.'
    mt5.symbol_select(sym, True)
    rates = mt5.copy_rates_from_pos(sym, mt5.TIMEFRAME_M15, 0, 80000)
    if rates is not None and len(rates) > 0:
        df = pd.DataFrame(rates)
        df['datetime'] = pd.to_datetime(df['time'], unit='s', utc=True)
        os.makedirs('data', exist_ok=True)
        df.to_parquet('data/NAS100_M15.parquet', index=False)
        print(f"Downloaded {len(df)} bars of {sym} M15.")
        print(f"Start: {df['datetime'].iloc[0]} | End: {df['datetime'].iloc[-1]}")
    else:
        print('Failed to copy rates')

    mt5.shutdown()

if __name__ == '__main__':
    download_data()
