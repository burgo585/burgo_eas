"""
Módulo de Ingestão de Dados Macroeconômicos e Sentimento Global.
Consome dados de volatilidade e juros via yfinance (VIX, DXY, US10Y)
e indicadores de risco macroeconômico via FRED API (Federal Reserve Economic Data).
"""

import datetime
from typing import Optional, Dict, Any, List
import numpy as np
import pandas as pd
import requests
import yfinance as yf

from src.utils.logger import obter_logger
from config.settings import ConfiguracaoMacro

logger = obter_logger("MacroFeed")


class MacroDataFeed:
    """
    Coletor institucional de dados macroeconômicos em tempo real e históricos.
    Calcula regime de mercado (Risk-On / Risk-Off) para correlação cruzada com MNQ e XAUUSD.
    """

    def __init__(self, config_macro: Optional[ConfiguracaoMacro] = None):
        """
        Inicializa o leitor de feeds macroeconômicos.

        :param config_macro: Configurações de tickers e parâmetros FRED.
        """
        self.config = config_macro or ConfiguracaoMacro()
        self.tickers_map = self.config.tickers
        self.fred_config = self.config.fred
        self._cache_macro: Dict[str, Any] = {
            "timestamp": datetime.datetime.now(datetime.timezone.utc),
            "vix": 18.0,
            "dxy": 104.0,
            "us10y": 4.25,
            "fed_funds": 5.25,
            "yield_spread_10y2y": -0.15,
            "high_yield_spread": 3.50,
            "risk_regime": "RISK_NEUTRAL"  # RISK_ON, RISK_OFF, RISK_NEUTRAL
        }

    def obter_cotacoes_yfinance_recentes(self) -> Dict[str, float]:
        """
        Extrai o último nível negociado de VIX, DXY e US10Y via yfinance.

        :return: Dicionário contendo os valores mais recentes.
        """
        resultados = {}
        for nome_chave, ticker_simbolo in self.tickers_map.items():
            if nome_chave == "dxy_fallback":
                continue
            try:
                t = yf.Ticker(ticker_simbolo)
                # Tenta primeiro fast_info, com fallback para history
                preco = getattr(t.fast_info, "last_price", None)
                if preco is None or np.isnan(preco):
                    hist = t.history(period="1d", interval="1m")
                    if not hist.empty:
                        preco = float(hist["Close"].iloc[-1])
                    else:
                        preco = getattr(self._cache_macro, nome_chave, 0.0)

                resultados[nome_chave] = float(preco)
            except Exception as e:
                logger.warning(f"Erro ao extrair {ticker_simbolo} via yfinance: {e}")
                if nome_chave == "dxy" and "dxy_fallback" in self.tickers_map:
                    # Tenta fallback para ETF UUP se DXY falhar
                    try:
                        t_fallback = yf.Ticker(self.tickers_map["dxy_fallback"])
                        preco_fb = getattr(t_fallback.fast_info, "last_price", None)
                        if preco_fb is not None:
                            resultados[nome_chave] = float(preco_fb)
                    except Exception:
                        resultados[nome_chave] = self._cache_macro.get(nome_chave, 100.0)
                else:
                    resultados[nome_chave] = self._cache_macro.get(nome_chave, 0.0)

        # Atualiza cache interno
        if "vix" in resultados:
            self._cache_macro["vix"] = resultados["vix"]
        if "dxy" in resultados:
            self._cache_macro["dxy"] = resultados["dxy"]
        if "us10y" in resultados:
            self._cache_macro["us10y"] = resultados["us10y"]

        self._cache_macro["timestamp"] = datetime.datetime.now(datetime.timezone.utc)
        self._classificar_regime_risco()
        return resultados

    def baixar_series_yfinance_historicas(
        self,
        periodo: str = "5d",
        intervalo: str = "1m"
    ) -> pd.DataFrame:
        """
        Baixa o histórico detalhado em barras de 1 minuto de VIX, DXY e US10Y.

        :param periodo: Período de histórico (ex: '5d', '1mo').
        :param intervalo: Resolução temporal (ex: '1m', '5m', '1d').
        :return: DataFrame unificado com timestamp UTC.
        """
        logger.info(f"Baixando séries históricas yfinance (Período: {periodo}, Resolução: {intervalo})...")
        dfs = []

        for nome_chave, ticker_simbolo in self.tickers_map.items():
            if nome_chave == "dxy_fallback":
                continue
            try:
                df_ticker = yf.download(
                    ticker_simbolo,
                    period=periodo,
                    interval=intervalo,
                    progress=False,
                    auto_adjust=True
                )
                if not df_ticker.empty:
                    df_res = pd.DataFrame()
                    # Compatibilidade com formatos de colunas MultiIndex recentes do yfinance
                    if isinstance(df_ticker.columns, pd.MultiIndex):
                        df_res[f"macro_{nome_chave}"] = df_ticker["Close"].iloc[:, 0]
                    else:
                        df_res[f"macro_{nome_chave}"] = df_ticker["Close"]

                    df_res["timestamp"] = df_ticker.index
                    df_res["timestamp"] = pd.to_datetime(df_res["timestamp"], utc=True)
                    dfs.append(df_res.dropna())
            except Exception as e:
                logger.warning(f"Falha ao baixar histórico de {ticker_simbolo}: {e}")

        if not dfs:
            logger.warning("Nenhum dado histórico yfinance retornado.")
            return pd.DataFrame()

        # Alinhamento das séries macro temporais
        df_consolidado = dfs[0]
        for df_item in dfs[1:]:
            df_consolidado = pd.merge(
                df_consolidado,
                df_item,
                on="timestamp",
                how="outer"
            ).sort_values("timestamp")

        # Preenchimento para frente (Forward-fill) sem olhar o futuro
        df_consolidado = df_consolidado.ffill().bfill().reset_index(drop=True)
        return df_consolidado

    def consultar_series_fred(self) -> Dict[str, float]:
        """
        Consulta as taxas mais recentes do Federal Reserve (FRED) via REST API institucional.
        Identifica postura da política monetária e inversão da curva de juros.

        :return: Dicionário com os indicadores econômicos atualizados.
        """
        if not self.fred_config.enabled or not self.fred_config.api_key:
            return {
                "fed_funds": self._cache_macro["fed_funds"],
                "yield_spread_10y2y": self._cache_macro["yield_spread_10y2y"],
                "high_yield_spread": self._cache_macro["high_yield_spread"]
            }

        resultados = {}
        base_url = "https://api.stlouisfed.org/fred/series/observations"

        for nome_metrica, codigo_serie in self.fred_config.series.items():
            try:
                params = {
                    "series_id": codigo_serie,
                    "api_key": self.fred_config.api_key,
                    "file_type": "json",
                    "sort_order": "desc",
                    "limit": 5
                }
                resp = requests.get(base_url, params=params, timeout=5)
                if resp.status_code == 200:
                    dados = resp.json().get("observations", [])
                    # Encontra a primeira observação válida (diferente de '.')
                    for obs in dados:
                        val_str = obs.get("value", "")
                        if val_str and val_str != ".":
                            resultados[nome_metrica] = float(val_str)
                            self._cache_macro[nome_metrica] = float(val_str)
                            break
            except Exception as e:
                logger.warning(f"Erro ao consultar série FRED {codigo_serie}: {e}")
                resultados[nome_metrica] = self._cache_macro.get(nome_metrica, 0.0)

        self._classificar_regime_risco()
        return resultados

    def _classificar_regime_risco(self):
        """
        Calcula o regime macroeconômico atual com base na matriz VIX, Juros e Curva.
        - RISK_ON: VIX baixo (<16) e spreads estáveis (propício a rali em MNQ e Cripto).
        - RISK_OFF: VIX alto (>22) ou abertura forte de spreads de crédito (aversão ao risco, fuga para Ouro/Dólar).
        - RISK_NEUTRAL: Condições intermediárias.
        """
        vix = self._cache_macro.get("vix", 18.0)
        yield_spread = self._cache_macro.get("yield_spread_10y2y", 0.0)

        if vix > 24.0 or yield_spread < -0.5:
            self._cache_macro["risk_regime"] = "RISK_OFF"
        elif vix < 16.0 and yield_spread >= -0.1:
            self._cache_macro["risk_regime"] = "RISK_ON"
        else:
            self._cache_macro["risk_regime"] = "RISK_NEUTRAL"

    def obter_snapshot_macro_atual(self) -> Dict[str, Any]:
        """
        Retorna o estado consolidado mais recente de todas as variáveis macroeconômicas.

        :return: Dicionário contendo VIX, DXY, US10Y, taxas FRED e regime de risco.
        """
        return dict(self._cache_macro)
