import datetime
import pandas as pd
import numpy as np
from simulate_user_image_config import run_exact_ea_sim, df

print("=== COMPARAÇÃO DETALHADA DAS VARIANTES DA CONFIGURAÇÃO DA IMAGEM ===\n")

# Variante A: Exatamente o que está na imagem
vA = run_exact_ea_sim(df, balance_init=100.0, initial_lot=0.01, target_side=3.0, target_global=15.0,
                       base_dist_pts=300, lot_mult=1.2, max_martingale=3, max_orders=4,
                       use_atr=True, atr_mult=1.5, use_trailing=True, trailing_start=5.0, trailing_drop_pct=10.0,
                       trade_direction="BUY_ONLY")

# Variante B: Na imagem, mas com TrailingStartUSD = 3.0 (iniciando no mesmo valor do TargetSide)
vB = run_exact_ea_sim(df, balance_init=100.0, initial_lot=0.01, target_side=3.0, target_global=15.0,
                       base_dist_pts=300, lot_mult=1.2, max_martingale=3, max_orders=4,
                       use_atr=True, atr_mult=1.5, use_trailing=True, trailing_start=3.0, trailing_drop_pct=15.0,
                       trade_direction="BUY_ONLY")

# Variante C: Na imagem, mas com TP Fixo de $3.00 (sem Trailing Stop)
vC = run_exact_ea_sim(df, balance_init=100.0, initial_lot=0.01, target_side=3.0, target_global=15.0,
                       base_dist_pts=300, lot_mult=1.2, max_martingale=3, max_orders=4,
                       use_atr=True, atr_mult=1.5, use_trailing=False,
                       trade_direction="BUY_ONLY")

# Variante D: Na imagem com Banca de $2.000
vD = run_exact_ea_sim(df, balance_init=2000.0, initial_lot=0.01, target_side=3.0, target_global=15.0,
                       base_dist_pts=300, lot_mult=1.2, max_martingale=3, max_orders=4,
                       use_atr=True, atr_mult=1.5, use_trailing=True, trailing_start=5.0, trailing_drop_pct=10.0,
                       trade_direction="BUY_ONLY")

# Variante E: Na imagem com Banca de $2.000 e TP Fixo de $3.00
vE = run_exact_ea_sim(df, balance_init=2000.0, initial_lot=0.01, target_side=3.0, target_global=15.0,
                       base_dist_pts=300, lot_mult=1.2, max_martingale=3, max_orders=4,
                       use_atr=True, atr_mult=1.5, use_trailing=False,
                       trade_direction="BUY_ONLY")

results = [
    {"Config": "Imagem Exata ($100)", "LucroUSD": vA['LucroUSD'], "LucroPct": f"{vA['LucroPct']}%", "MaxDD_Pct": f"{vA['MaxDD_Pct']}%", "MinEquity": vA['MinEquity'], "PeakEquity": vA['PeakEquity'], "Trades": vA['Trades'], "Quebrou": vA['StopOut']},
    {"Config": "Imagem com Trailing Start $3 ($100)", "LucroUSD": vB['LucroUSD'], "LucroPct": f"{vB['LucroPct']}%", "MaxDD_Pct": f"{vB['MaxDD_Pct']}%", "MinEquity": vB['MinEquity'], "PeakEquity": vB['PeakEquity'], "Trades": vB['Trades'], "Quebrou": vB['StopOut']},
    {"Config": "Imagem com TP Fixo $3 ($100)", "LucroUSD": vC['LucroUSD'], "LucroPct": f"{vC['LucroPct']}%", "MaxDD_Pct": f"{vC['MaxDD_Pct']}%", "MinEquity": vC['MinEquity'], "PeakEquity": vC['PeakEquity'], "Trades": vC['Trades'], "Quebrou": vC['StopOut']},
    {"Config": "Imagem Exata ($2.000)", "LucroUSD": vD['LucroUSD'], "LucroPct": f"{vD['LucroPct']}%", "MaxDD_Pct": f"{vD['MaxDD_Pct']}%", "MinEquity": vD['MinEquity'], "PeakEquity": vD['PeakEquity'], "Trades": vD['Trades'], "Quebrou": vD['StopOut']},
    {"Config": "Imagem com TP Fixo $3 ($2.000)", "LucroUSD": vE['LucroUSD'], "LucroPct": f"{vE['LucroPct']}%", "MaxDD_Pct": f"{vE['MaxDD_Pct']}%", "MinEquity": vE['MinEquity'], "PeakEquity": vE['PeakEquity'], "Trades": vE['Trades'], "Quebrou": vE['StopOut']},
]

df_res = pd.DataFrame(results)
print(df_res.to_string(index=False))
