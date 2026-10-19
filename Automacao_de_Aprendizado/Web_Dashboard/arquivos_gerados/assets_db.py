"""
assets_db.py - Especificações dos Ativos Principais: XAUUSD, BTCUSD, NAS100.
Contém configurações de contratos, valores de pip/ponto, spreads típicos,
volatilidade ATR padrão e regras operacionais.
"""

from typing import Dict, Any

ASSETS: Dict[str, Dict[str, Any]] = {
    "XAUUSD": {
        "name": "Ouro / Dólar Americano (Gold)",
        "symbol": "XAUUSD",
        "market": "Commodities / Metais",
        "contract_size": 100.0,       # 100 onças troy por lote padrão
        "digits": 2,                  # 2 casas decimais (ex: 2650.50)
        "point_size": 0.01,           # 1 ponto = 0.01 USD ($1.00 por lote padrão)
        "pip_size": 0.10,             # 1 pip = 10 pontos = 0.10 USD
        "pip_value_per_standard_lot": 10.0,  # $10.00 por pip em 1.00 lote ($0.10 em 0.01 lote)
        "min_lot": 0.01,
        "lot_step": 0.01,
        "max_lot": 50.0,
        "default_price": 2650.00,
        "typical_spread_pips": 2.0,   # 20 pontos = 2.0 pips (spread normal)
        "typical_commission_per_lot": 6.0,   # $6.00 por lote round-turn
        "typical_swap_long_daily": -4.50,    # Swap diário por lote
        "typical_swap_short_daily": 1.20,
        "typical_atr": {
            "M1": 8.0,      # pips
            "M5": 16.0,
            "M15": 30.0,
            "H1": 65.0,
            "H4": 150.0,
            "D1": 320.0
        },
        "default_leverage": 500,
        "liquidity_peak": "Londres / NY (09:00 - 13:00 BRT)",
        "notes": "Ativo de extrema aceleração em notícias econômicas (NFP, CPI). Alavancagem alta exige respeito rigoroso ao ATR."
    },
    "BTCUSD": {
        "name": "Bitcoin / Dólar Americano",
        "symbol": "BTCUSD",
        "market": "Criptomoedas",
        "contract_size": 1.0,         # 1 BTC por 1.00 lote padrão (em corretoras MT5/CFD)
        "digits": 2,                  # ex: 68500.50
        "point_size": 0.01,           # 1 ponto = $0.01
        "pip_size": 1.0,              # 1 pip = $1.00 na cotação
        "pip_value_per_standard_lot": 1.0,  # Em 1.00 lote (1 BTC), $1 de oscilação = $1 de resultado ($0.01 em 0.01 lote)
        "min_lot": 0.01,
        "lot_step": 0.01,
        "max_lot": 20.0,
        "default_price": 68500.00,
        "typical_spread_pips": 15.0,  # $15 de spread em média
        "typical_commission_per_lot": 0.0,   # Muitas corretoras cobram spread embutido
        "typical_swap_long_daily": -12.00,
        "typical_swap_short_daily": -12.00,
        "typical_atr": {
            "M1": 80.0,
            "M5": 220.0,
            "M15": 500.0,
            "H1": 1100.0,
            "H4": 2600.0,
            "D1": 5200.0
        },
        "default_leverage": 100,      # Alavancagem padrão (pode ir de 1:20 a 1:500 dependendo da corretora)
        "liquidity_peak": "24/7 contínuo (picos de volume na abertura dos EUA)",
        "notes": "Oscilações amplas e contínuas 24/7. O stop loss em pontos é mais largo para amortecer variações voláteis."
    },
    "NAS100": {
        "name": "Nasdaq 100 Index (US100 / USTEC)",
        "symbol": "NAS100",
        "market": "Índice de Ações (Tecnologia EUA)",
        "contract_size": 1.0,         # 1 contrato de índice por 1.00 lote CFD padrão
        "digits": 2,                  # ex: 20450.25
        "point_size": 0.01,           # 1 ponto = 0.01 no MT5 (100 pontos = 1 ponto inteiro do índice)
        "pip_size": 1.0,              # 1 pip = 1 ponto do índice ($1.00 de oscilação do índice)
        "pip_value_per_standard_lot": 1.0,  # Em 1.00 lote, 1 ponto de índice = $1.00 (ou $0.01 em 0.01 lote)
        "min_lot": 0.01,
        "lot_step": 0.01,
        "max_lot": 50.0,
        "default_price": 20450.00,
        "typical_spread_pips": 1.8,   # 1.8 pontos do índice
        "typical_commission_per_lot": 4.0,
        "typical_swap_long_daily": -6.50,
        "typical_swap_short_daily": 2.10,
        "typical_atr": {
            "M1": 15.0,
            "M5": 40.0,
            "M15": 85.0,
            "H1": 180.0,
            "H4": 380.0,
            "D1": 750.0
        },
        "default_leverage": 100,
        "liquidity_peak": "Sessão de Nova York (09:30 às 16:00 EST / 10:30 às 17:00 BRT)",
        "notes": "Índice de altíssima liquidez e sensibilidade aos balanços das Big Techs e política monetária do FED."
    }
}


def get_asset(symbol: str) -> Dict[str, Any]:
    """Retorna a configuração do ativo ou uma configuração padrão caso não exista."""
    symbol_upper = symbol.upper()
    if symbol_upper in ASSETS:
        return ASSETS[symbol_upper]
    
    # Fallback genérico
    return {
        "name": f"Ativo Customizado ({symbol_upper})",
        "symbol": symbol_upper,
        "market": "Personalizado",
        "contract_size": 100.0,
        "digits": 2,
        "point_size": 0.01,
        "pip_size": 0.10,
        "pip_value_per_standard_lot": 10.0,
        "min_lot": 0.01,
        "lot_step": 0.01,
        "max_lot": 50.0,
        "default_price": 100.00,
        "typical_spread_pips": 2.0,
        "typical_commission_per_lot": 0.0,
        "typical_swap_long_daily": 0.0,
        "typical_swap_short_daily": 0.0,
        "typical_atr": {
            "M1": 5.0,
            "M5": 10.0,
            "M15": 20.0,
            "H1": 45.0,
            "H4": 100.0,
            "D1": 200.0
        },
        "default_leverage": 100,
        "liquidity_peak": "Horário Comercial",
        "notes": "Ativo customizado definido pelo usuário."
    }
