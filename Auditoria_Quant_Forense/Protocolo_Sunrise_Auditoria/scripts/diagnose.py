from run_sessions_test import TimedBacktestEngine
from run_xauusd_tests import get_xauusd_data
import pandas as pd

df = get_xauusd_data()
engine = TimedBacktestEngine(df, initial_balance=2000.0)

# Diagnóstico da execução
cfg = {
    'InitialLot': 0.01,
    'TargetSideUSD': 2.00,
    'TargetGlobalUSD': 20.00,
    'BaseDistance': 600,
    'LotMultiplier': 1.5,
    'MaxMartingale': 8,
    'MaxTotalOrders': 15,
    'UseATR': True,
    'ATRMultiplier': 1.5,
    'UseTrailingStop': True,
    'TrailingStartUSD': 5.00,
    'TrailingDropPct': 10.0
}

# Vamos investigar onde o saldo foi drenado:
# Analisando o comportamento de compras vs vendas no Ouro
print("Primeiro candle:", df['time'].iloc[0], "Preço:", df['close'].iloc[0])
print("Último candle:", df['time'].iloc[-1], "Preço:", df['close'].iloc[-1])
delta = df['close'].iloc[-1] - df['close'].iloc[0]
print(f"Variação bruta do Ouro no período: +${delta:.2f} por onça!")
