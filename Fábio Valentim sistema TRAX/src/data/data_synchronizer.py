"""
Módulo Sincronizador de Dados Heterogêneos (Data Fusion & Temporal Alignment).
Executa merge_asof institucional de alta performance entre o fluxo de ticks/candles do MT5
e as fontes externas assíncronas (Binance L2 Imbalance/Liquidações, VIX, DXY, US10Y e FRED).
Garante rigorosamente ausência de viés de antecipação (Zero Lookahead Bias).
"""

import datetime
from typing import Optional, Union, Dict, Any
import numpy as np
import pandas as pd

from src.utils.logger import obter_logger

logger = obter_logger("DataSynchronizer")


class DataSynchronizer:
    """
    Sincronizador temporal orientado a eventos quantitativos.
    Unifica fluxos de microestrutura e macroeconomia em uma única matriz analítica.
    """

    def __init__(self, tolerancia_tempo_segundos: int = 300):
        """
        Inicializa o sincronizador.

        :param tolerancia_tempo_segundos: Janela máxima de tolerância para forward-fill de dados externos.
        """
        self.tolerancia = pd.Timedelta(seconds=tolerancia_tempo_segundos)

    def sincronizar_fluxos(
        self,
        df_primario: pd.DataFrame,
        df_binance: Optional[pd.DataFrame] = None,
        df_macro: Optional[pd.DataFrame] = None,
        coluna_tempo: str = "timestamp"
    ) -> pd.DataFrame:
        """
        Executa merge_asof com direção 'backward' (passado para presente).
        Garante que a barra ou tick no instante T utilize estritamente a última
        informação externa disponível até T, eliminando qualquer vazamento de dados futuros.

        :param df_primario: DataFrame base do MT5 (ticks ou candles M1 ordenados).
        :param df_binance: DataFrame de desequilíbrio de book L2 e liquidações da Binance.
        :param df_macro: DataFrame com séries macroeconômicas (VIX, DXY, US10Y).
        :param coluna_tempo: Nome da coluna de data/hora comum.
        :return: DataFrame fundido e pronto para os motores de Order Flow e IA.
        """
        if df_primario.empty:
            logger.warning("DataFrame primário vazio. Retornando base vazia.")
            return df_primario

        # 1. Normalização rigorosa do índice temporal do DataFrame primário
        df_resultado = df_primario.copy()
        df_resultado[coluna_tempo] = pd.to_datetime(df_resultado[coluna_tempo], utc=True)
        df_resultado = df_resultado.sort_values(coluna_tempo).reset_index(drop=True)

        # 2. Fusão assíncrona com os fluxos da Binance (L2 Imbalance e Liquidações)
        if df_binance is not None and not df_binance.empty:
            df_b = df_binance.copy()
            df_b[coluna_tempo] = pd.to_datetime(df_b[coluna_tempo], utc=True)
            df_b = df_b.sort_values(coluna_tempo).reset_index(drop=True)

            colunas_interesse_binance = [
                coluna_tempo, "l2_imbalance", "l2_bid_qty", "l2_ask_qty",
                "liq_long_vol", "liq_short_vol"
            ]
            colunas_presentes_b = [c for c in colunas_interesse_binance if c in df_b.columns]
            df_b_filtrado = df_b[colunas_presentes_b]

            logger.info("Realizando merge_asof com dados externos da Binance...")
            df_resultado = pd.merge_asof(
                df_resultado,
                df_b_filtrado,
                on=coluna_tempo,
                direction="backward",
                tolerance=self.tolerancia
            )

        # 3. Fusão assíncrona com os indicadores Macroeconômicos (yfinance e FRED)
        if df_macro is not None and not df_macro.empty:
            df_m = df_macro.copy()
            df_m[coluna_tempo] = pd.to_datetime(df_m[coluna_tempo], utc=True)
            df_m = df_m.sort_values(coluna_tempo).reset_index(drop=True)

            logger.info("Realizando merge_asof com dados macroeconômicos (VIX, DXY, US10Y)...")
            df_resultado = pd.merge_asof(
                df_resultado,
                df_m,
                on=coluna_tempo,
                direction="backward",
                tolerance=self.tolerancia
            )

        # 4. Tratamento e preenchimento defensivo de valores ausentes (Forward-Fill institucional)
        # Preenche com os valores prévios conhecidos sem inventar dados
        colunas_numericas = df_resultado.select_dtypes(include=[np.number]).columns
        df_resultado[colunas_numericas] = df_resultado[colunas_numericas].ffill().fillna(0.0)

        logger.info(f"Sincronização concluída: {len(df_resultado)} registros consolidados.")
        return df_resultado

    def fundir_snapshot_tempo_real(
        self,
        tick_ou_barra: Dict[str, Any],
        snapshot_binance: Dict[str, Any],
        snapshot_macro: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Fusão ultra-rápida (in-memory) em nível de milissegundos para o loop ao vivo de HFT.
        Combina o evento de tick instantâneo com os estados mais recentes dos feeds externos.

        :param tick_ou_barra: Dicionário contendo os dados do tick/candle MT5.
        :param snapshot_binance: Último snapshot registrado do feed da Binance.
        :param snapshot_macro: Último snapshot dos indicadores macroeconômicos.
        :return: Registro consolidado com todas as variáveis unificadas para a IA.
        """
        registro_fundido = dict(tick_ou_barra)

        # Injeta variáveis de microestrutura de cripto
        registro_fundido["binance_l2_imbalance"] = snapshot_binance.get("l2_imbalance", 0.0)
        registro_fundido["binance_liq_long_vol"] = snapshot_binance.get("liq_long_vol", 0.0)
        registro_fundido["binance_liq_short_vol"] = snapshot_binance.get("liq_short_vol", 0.0)

        # Injeta variáveis macroeconômicas
        registro_fundido["macro_vix"] = snapshot_macro.get("vix", 18.0)
        registro_fundido["macro_dxy"] = snapshot_macro.get("dxy", 104.0)
        registro_fundido["macro_us10y"] = snapshot_macro.get("us10y", 4.25)
        registro_fundido["macro_risk_regime"] = snapshot_macro.get("risk_regime", "RISK_NEUTRAL")
        registro_fundido["macro_yield_spread"] = snapshot_macro.get("yield_spread_10y2y", -0.15)

        return registro_fundido
