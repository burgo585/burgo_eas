import json
import pandas as pd

# Carregar os resultados de otimizador_xauusd
# Vamos salvar todos os resultados no json durante uma varredura rapida de analise
with open(r'c:\Robo Virada de Delta\Robo_Frasson_Alta_Frequencia_PRO\Testes_Quantitativos\top_configs_xauusd.json') as f:
    top_10 = json.load(f)

print("Top 10 Carregado com sucesso.")
