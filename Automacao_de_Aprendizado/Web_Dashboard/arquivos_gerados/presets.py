"""
presets.py - Setups pré-definidos rápidos inspirados no ecossistema das imagens.
Fornece parâmetros recomendados para XAUUSD, BTCUSD, NAS100 e Mesa Proprietária.
"""

from typing import Dict, Any, List

PRESETS: Dict[str, Dict[str, Any]] = {
    "xauusd_scalping": {
        "id": "xauusd_scalping",
        "name": "🥇 Scalping Ouro (XAUUSD)",
        "symbol": "XAUUSD",
        "description": "Stop 15 pips, TP 30 pips, Risco 1.0%, Alavancagem 1:500",
        "capital": 500.0,
        "risk_pct": 1.0,
        "stop_pips": 15.0,
        "tp_pips": 30.0,
        "leverage": 500,
        "spread_pips": 2.0,
        "order_type": "BUY",
        "timeframe": "M15",
        "holding_days": 0,
        "notes": "Foco em operações curtas. Atenção aos horários de pico (09:00 - 12:30 BRT)."
    },
    "btcusd_volatility": {
        "id": "btcusd_volatility",
        "name": "🏛️ Cripto / Bitcoin (BTCUSD)",
        "symbol": "BTCUSD",
        "description": "Stop 500 pips ($500), TP 1500 pips ($1500), Risco 1.5%, Alavancagem 1:500",
        "capital": 200.0,
        "risk_pct": 1.5,
        "stop_pips": 500.0,
        "tp_pips": 1500.0,
        "leverage": 500,
        "spread_pips": 15.0,
        "order_type": "BUY",
        "timeframe": "M15",
        "holding_days": 0,
        "notes": "Espelhamento do exemplo da imagem. Stop amplo para amortecer ruído no Bitcoin."
    },
    "nas100_daytrade": {
        "id": "nas100_daytrade",
        "name": "⚡ Day Trade Nasdaq (NAS100)",
        "symbol": "NAS100",
        "description": "Stop 30 pips (30 pts), TP 90 pips (90 pts), Risco 1.0%, Alavancagem 1:100",
        "capital": 1000.0,
        "risk_pct": 1.0,
        "stop_pips": 30.0,
        "tp_pips": 90.0,
        "leverage": 100,
        "spread_pips": 1.8,
        "order_type": "BUY",
        "timeframe": "M15",
        "holding_days": 0,
        "notes": "Relação 1:3.0 na abertura de Nova York. Excelente liquidez institucional."
    },
    "prop_firm": {
        "id": "prop_firm",
        "name": "🏆 Mesa Proprietária (Prop Firm - Risco 0.5%)",
        "symbol": "NAS100",
        "description": "Risco estrito de 0.5%, Stop 25 pips, TP 50 pips, Alavancagem 1:50",
        "capital": 10000.0,
        "risk_pct": 0.5,
        "stop_pips": 25.0,
        "tp_pips": 50.0,
        "leverage": 50,
        "spread_pips": 1.8,
        "order_type": "BUY",
        "timeframe": "M15",
        "holding_days": 0,
        "notes": "Modelo institucional para aprovação em testes de mesa sem violar trailing drawdown."
    },
    "swing_carry": {
        "id": "swing_carry",
        "name": "🌙 Swing Trade & Carry (3 dias aberto)",
        "symbol": "XAUUSD",
        "description": "Simulação de posição aberta por 3 dias com cálculo de Swap acumulado",
        "capital": 2000.0,
        "risk_pct": 1.0,
        "stop_pips": 45.0,
        "tp_pips": 135.0,
        "leverage": 200,
        "spread_pips": 2.0,
        "order_type": "BUY",
        "timeframe": "H1",
        "holding_days": 3,
        "notes": "Avalia o impacto real da taxa de swap/rollover quando uma ordem dorme de um dia para outro."
    }
}


def list_presets() -> List[Dict[str, Any]]:
    """Retorna a lista de presets para consumo na interface."""
    return list(PRESETS.values())


def get_preset(preset_id: str) -> Dict[str, Any]:
    """Retorna os parâmetros de um preset pelo ID."""
    return PRESETS.get(preset_id, PRESETS["xauusd_scalping"])
