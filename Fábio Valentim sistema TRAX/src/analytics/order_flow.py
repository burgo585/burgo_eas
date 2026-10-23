"""
Módulo do Motor Analítico de Order Flow (Microestrutura e Footprint Institucional).
Converte fluxo contínuo de ticks em barras OHLC-V de 1 minuto, calcula Delta de Agressão,
Delta Acumulado (CVD) e Mapeia o Point of Control (PoC) intradiário.
Reflete fielmente a matemática por trás dos clusters de volume e histograma da Imagem 1.
"""

from typing import Optional, Dict, Any, List, Tuple
import numpy as np
import pandas as pd

from src.utils.logger import obter_logger

logger = obter_logger("OrderFlowEngine")


class OrderFlowEngine:
    """
    Motor analítico de fluxo de ordens institucional.
    Calcula Footprint intradiário, Delta compradores vs vendedores e Point of Control (PoC).
    """

    def __init__(self, tick_size: float = 0.05):
        """
        Inicializa o motor de Order Flow.

        :param tick_size: Tamanho mínimo de variação de preço para discretização do perfil de volume (PoC).
        """
        self.tick_size = tick_size

    def agregar_ticks_em_candles_m1(self, df_ticks: pd.DataFrame) -> pd.DataFrame:
        """
        Agrega ticks brutos em candles M1 estruturados com separação de agressão institucional.

        :param df_ticks: DataFrame contendo ticks (timestamp, price, vol, buy_vol, sell_vol, delta).
        :return: DataFrame de candles M1 com colunas OHLC, Volume, Buy_Vol, Sell_Vol, Delta e PoC.
        """
        if df_ticks.empty:
            logger.warning("DataFrame de ticks vazio para agregação M1.")
            return pd.DataFrame()

        df = df_ticks.copy()
        if not pd.api.types.is_datetime64_any_dtype(df["timestamp"]):
            df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True)

        # Define índice temporal para agrupamento M1 (1 minuto)
        df = df.sort_values("timestamp")
        df["barra_m1"] = df["timestamp"].dt.floor("1min")

        logger.info(f"Agregando {len(df):,} ticks em barras M1...")

        # 1. Agregação OHLCV e volumes de agressão
        grupos = df.groupby("barra_m1")

        candles = grupos.agg(
            open=("price", "first"),
            high=("price", "max"),
            low=("price", "min"),
            close=("price", "last"),
            vol=("vol", "sum"),
            buy_vol=("buy_vol", "sum"),
            sell_vol=("sell_vol", "sum"),
            ticks_count=("vol", "count")
        ).reset_index()

        candles.rename(columns={"barra_m1": "timestamp"}, inplace=True)

        # 2. Cálculo matemático de Delta e Métricas da Imagem 1
        candles["delta"] = candles["buy_vol"] - candles["sell_vol"]
        candles["cum_delta"] = candles["delta"].cumsum()
        candles["delta_ratio"] = np.where(
            candles["vol"] > 0,
            candles["delta"] / candles["vol"],
            0.0
        )

        # 3. Cálculo do Point of Control (PoC) por candle (Volume Profile intra-barra)
        pocs = []
        poc_volumes = []

        for barra_tempo, dados_barra in grupos:
            precos_arredondados = np.round(dados_barra["price"] / self.tick_size) * self.tick_size
            # Agrupa volume por nível de preço discretizado dentro da barra M1
            vol_por_preco = dados_barra.groupby(precos_arredondados)["vol"].sum()
            if not vol_por_preco.empty:
                preco_poc = vol_por_preco.idxmax()
                vol_poc = vol_por_preco.max()
            else:
                preco_poc = dados_barra["price"].iloc[-1]
                vol_poc = 0.0

            pocs.append(preco_poc)
            poc_volumes.append(vol_poc)

        candles["poc"] = pocs
        candles["poc_vol"] = poc_volumes

        # 4. Rastreamento de Spikes de Delta (Delta da barra vs Média Móvel de N barras)
        janela_media = 20
        delta_abs_medio = candles["delta"].abs().rolling(window=janela_media, min_periods=1).mean()
        candles["delta_mean_20"] = delta_abs_medio
        candles["delta_multiplier"] = np.where(
            delta_abs_medio > 0,
            candles["delta"].abs() / delta_abs_medio,
            1.0
        )

        # Identifica barras com desequilíbrio extremo de agressão (Spikes de Delta)
        candles["is_delta_spike"] = candles["delta_multiplier"] >= 2.5

        logger.info(f"Agregação concluída: {len(candles):,} candles M1 calculados com Delta e PoC.")
        return candles

    @staticmethod
    def calcular_footprint_distribuicao(df_ticks_barra: pd.DataFrame, tick_size: float = 0.05) -> pd.DataFrame:
        """
        Mapeia a distribuição detalhada de agressão por nível de preço (Cluster Footprint).
        Permite reconstruir os blocos visuais de compradores e vendedores da Imagem 1.

        :param df_ticks_barra: Ticks pertencentes a uma única barra M1.
        :param tick_size: Resolução da grade de preço.
        :return: DataFrame indexado por preço contendo buy_vol, sell_vol e delta_nivel.
        """
        if df_ticks_barra.empty:
            return pd.DataFrame()

        df = df_ticks_barra.copy()
        df["price_level"] = np.round(df["price"] / tick_size) * tick_size

        perfil = df.groupby("price_level").agg(
            buy_vol=("buy_vol", "sum"),
            sell_vol=("sell_vol", "sum"),
            total_vol=("vol", "sum")
        ).reset_index()

        perfil["delta_level"] = perfil["buy_vol"] - perfil["sell_vol"]
        perfil = perfil.sort_values("price_level", ascending=False).reset_index(drop=True)
        return perfil
