import MetaTrader5 as mt5
import pandas as pd
import numpy as np
import datetime

def test_xauusd_data():
    if not mt5.initialize(path=r"C:\Program Files\MetaTrader 5\terminal64.exe"):
        print("Failed to initialize:", mt5.last_error())
        return

    sym = 'XAUUSD-VIP'
    mt5.symbol_select(sym, True)
    info = mt5.symbol_info(sym)
    print(f"Symbol: {sym}, Point: {info.point}, Spread: {info.spread}, Contract: {info.trade_contract_size}")

    # Fetch 2 years range
    start_dt = datetime.datetime(2024, 10, 11)
    end_dt = datetime.datetime(2026, 10, 11)
    rates_m15 = mt5.copy_rates_range(sym, mt5.TIMEFRAME_M15, start_dt, end_dt)
    rates_h1 = mt5.copy_rates_range(sym, mt5.TIMEFRAME_H1, start_dt - datetime.timedelta(days=60), end_dt)
    mt5.shutdown()

    if rates_m15 is None or rates_h1 is None:
        print("Failed to copy rates")
        return

    df_m15 = pd.DataFrame(rates_m15)
    df_m15['datetime'] = pd.to_datetime(df_m15['time'], unit='s')
    
    df_h1 = pd.DataFrame(rates_h1)
    df_h1['datetime'] = pd.to_datetime(df_h1['time'], unit='s')

    print(f"M15: {len(df_m15)} bars from {df_m15['datetime'].iloc[0]} to {df_m15['datetime'].iloc[-1]}")
    print(f"H1: {len(df_h1)} bars from {df_h1['datetime'].iloc[0]} to {df_h1['datetime'].iloc[-1]}")

if __name__ == '__main__':
    test_xauusd_data()
