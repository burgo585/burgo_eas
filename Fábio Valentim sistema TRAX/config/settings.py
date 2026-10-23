"""
Módulo de Carregamento e Validação de Parâmetros e Presets Institucionais.
Lê o arquivo presets.json e expõe estruturas tipadas para os módulos de execução e análise.
"""

import json
from pathlib import Path
from typing import Dict, Any, Optional
from pydantic import BaseModel, Field


class ConfiguracaoSistema(BaseModel):
    """Parâmetros operacionais centrais do ecossistema."""
    version: str = "1.0.0"
    name: str = "TRAX Institutional Quant Engine"
    timezone_ny: str = "America/New_York"
    timezone_local: str = "America/Sao_Paulo"
    log_level: str = "INFO"
    ai_confidence_threshold: float = 0.70


class ConfiguracaoMT5(BaseModel):
    """Parâmetros de conexão direta com o terminal MetaTrader 5."""
    account: int = 0
    password: str = ""
    server: str = ""
    path: str = ""
    portable: bool = False
    timeout_ms: int = 60000


class ConfiguracaoFRED(BaseModel):
    """Parâmetros da API do Federal Reserve Economic Data (FRED)."""
    enabled: bool = True
    api_key: str = "DEMO_OR_REPLACE_WITH_FRED_API_KEY"
    series: Dict[str, str] = Field(default_factory=dict)


class ConfiguracaoMacro(BaseModel):
    """Configurações de ingestão de dados macroeconômicos e correlação cruzada."""
    yfinance_enabled: bool = True
    update_interval_seconds: int = 60
    tickers: Dict[str, str] = Field(default_factory=dict)
    fred: ConfiguracaoFRED = Field(default_factory=ConfiguracaoFRED)


class ConfiguracaoBinance(BaseModel):
    """Configuração dos feeds de Order Book L2 e Liquidações da Binance."""
    enabled: bool = True
    ws_base_url: str = "wss://fstream.binance.com/ws"
    rest_base_url: str = "https://fapi.binance.com"
    depth_symbol: str = "btcusdt"
    depth_levels: int = 20
    depth_speed_ms: int = 100


class PresetAtivo(BaseModel):
    """Preset institucional específico de cada ativo da cesta (MNQ, XAUUSD, BTCUSD)."""
    symbol: str
    mt5_symbol: str
    description: str
    asset_class: str
    tick_file_path: Optional[str] = None
    quote_tick_mode: bool = False
    moc_loc_active: bool = False
    moc_loc_window_start: Optional[str] = None
    moc_loc_window_end: Optional[str] = None
    kill_switch_time: Optional[str] = None
    trading_hours: Optional[str] = "24/5"
    binance_reference_symbol: Optional[str] = None
    atr_period: int = 14
    atr_sl_multiplier: float = 1.5
    risk_reward_ratio: float = 2.0
    delta_threshold_multiplier: float = 3.0
    min_volume_threshold: int = 100
    fvg_min_ticks: int = 4
    lot_size: float = 1.0
    max_slippage_points: float = 2.0
    magic_number: int = 100001
    binance_imbalance_threshold: Optional[float] = 0.30
    cross_macro_correlation: Dict[str, bool] = Field(default_factory=dict)
    session_filter_active: Optional[bool] = False
    trend_ema_filter_active: Optional[bool] = False
    breakeven_active: Optional[bool] = False
    ib_session_start_hour: Optional[int] = 9
    ib_session_start_min: Optional[int] = 30
    ib_duration_minutes: Optional[int] = 30
    ivb_model1_active: Optional[bool] = True
    ivb_model2_active: Optional[bool] = True
    auto_guardrail_active: Optional[bool] = True
    trading_hours_mode: Optional[str] = "24h"
    trading_start_time: Optional[str] = "00:00"
    trading_end_time: Optional[str] = "23:59"
    trading_timezone: Optional[str] = "America/Sao_Paulo"


class ConfiguracaoGlobal(BaseModel):
    """Estrutura consolidada de todos os presets do ecossistema."""
    system: ConfiguracaoSistema
    mt5: ConfiguracaoMT5
    macro: ConfiguracaoMacro
    binance: ConfiguracaoBinance
    assets: Dict[str, PresetAtivo]


def carregar_presets(caminho_arquivo: Optional[Path] = None) -> ConfiguracaoGlobal:
    """
    Carrega e valida o arquivo JSON de presets.

    :param caminho_arquivo: Caminho opcional para o arquivo JSON.
    :return: Instância validada de ConfiguracaoGlobal.
    """
    if caminho_arquivo is None:
        raiz_projeto = Path(__file__).resolve().parent.parent
        caminho_arquivo = raiz_projeto / "config" / "presets.json"

    if not caminho_arquivo.exists():
        raise FileNotFoundError(f"Arquivo de presets não encontrado: {caminho_arquivo}")

    with open(caminho_arquivo, "r", encoding="utf-8") as f:
        dados = json.load(f)

    return ConfiguracaoGlobal(**dados)
