"""
Módulo de Detecção de Zonas SMC (Smart Money Concepts e Liquidez Institucional).
Identifica dinamicamente Order Blocks (faixas horizontais de suporte e resistência institucionais da Imagem 1),
Fair Value Gaps (FVG) e níveis de mitigação de liquidez.
"""

from typing import List, Dict, Any, Optional
import numpy as np
import pandas as pd

from src.utils.logger import obter_logger

logger = obter_logger("SMCZonesEngine")


class ZonaInstitucional:
    """Representa um bloco de liquidez ou ineficiência no gráfico."""

    def __init__(
        self,
        tipo: str,              # 'BULLISH_OB', 'BEARISH_OB', 'BULLISH_FVG', 'BEARISH_FVG'
        nivel_superior: float,
        nivel_inferior: float,
        timestamp_criacao: pd.Timestamp,
        indice_barra: int,
        delta_origem: float = 0.0,
        volume_origem: float = 0.0
    ):
        self.tipo = tipo
        self.nivel_superior = nivel_superior
        self.nivel_inferior = nivel_inferior
        self.timestamp_criacao = timestamp_criacao
        self.indice_barra = indice_barra
        self.delta_origem = delta_origem
        self.volume_origem = volume_origem
        self.mitigado = False
        self.testado = False

    def to_dict(self) -> Dict[str, Any]:
        return {
            "tipo": self.tipo,
            "nivel_superior": self.nivel_superior,
            "nivel_inferior": self.nivel_inferior,
            "timestamp": self.timestamp_criacao,
            "indice": self.indice_barra,
            "delta_origem": self.delta_origem,
            "mitigado": self.mitigado,
            "testado": self.testado
        }


class SMCZonesEngine:
    """
    Rastreador de zonas institucionais de Smart Money Concepts (SMC).
    Espelha a lógica das faixas coloridas e validações da Imagem 1.
    """

    def __init__(self, fvg_min_tamanho: float = 0.50, delta_impulsao_multiplicador: float = 2.0):
        """
        Inicializa o motor de Zonas SMC.

        :param fvg_min_tamanho: Tamanho mínimo em pontos para validar um Fair Value Gap (FVG).
        :param delta_impulsao_multiplicador: Fator de multiplicação de Delta para validar quebra institucional.
        """
        self.fvg_min_tamanho = fvg_min_tamanho
        self.delta_impulsao_multiplicador = delta_impulsao_multiplicador

    def detectar_fvg(self, df_candles: pd.DataFrame) -> List[ZonaInstitucional]:
        """
        Detecta Fair Value Gaps (ineficiências de liquidez de 3 barras).

        :param df_candles: DataFrame de candles M1 ordenados temporalmente.
        :return: Lista de zonas FVG encontradas.
        """
        zonas_fvg = []
        n = len(df_candles)
        if n < 3:
            return zonas_fvg

        highs = df_candles["high"].values
        lows = df_candles["low"].values
        timestamps = df_candles["timestamp"].values
        deltas = df_candles["delta"].values if "delta" in df_candles.columns else np.zeros(n)

        for i in range(2, n):
            # Bullish FVG: Mínima do candle atual > Máxima do candle de 2 períodos atrás
            if lows[i] > highs[i - 2]:
                gap = lows[i] - highs[i - 2]
                if gap >= self.fvg_min_tamanho:
                    zona = ZonaInstitucional(
                        tipo="BULLISH_FVG",
                        nivel_superior=lows[i],
                        nivel_inferior=highs[i - 2],
                        timestamp_criacao=pd.to_datetime(timestamps[i]),
                        indice_barra=i,
                        delta_origem=deltas[i]
                    )
                    zonas_fvg.append(zona)

            # Bearish FVG: Máxima do candle atual < Mínima do candle de 2 períodos atrás
            elif highs[i] < lows[i - 2]:
                gap = lows[i - 2] - highs[i]
                if gap >= self.fvg_min_tamanho:
                    zona = ZonaInstitucional(
                        tipo="BEARISH_FVG",
                        nivel_superior=lows[i - 2],
                        nivel_inferior=highs[i],
                        timestamp_criacao=pd.to_datetime(timestamps[i]),
                        indice_barra=i,
                        delta_origem=deltas[i]
                    )
                    zonas_fvg.append(zona)

        return zonas_fvg

    def detectar_order_blocks(self, df_candles: pd.DataFrame) -> List[ZonaInstitucional]:
        """
        Detecta Order Blocks institucionais:
        - Bullish OB: Último candle de baixa antes de uma impulsão compradora com Delta extremo que rompe a máxima anterior.
        - Bearish OB: Último candle de alta antes de uma impulsão vendedora com Delta extremo que rompe a mínima anterior.

        :param df_candles: DataFrame de candles M1 com OHLCV e Delta.
        :return: Lista de Order Blocks ativos e históricos.
        """
        order_blocks = []
        n = len(df_candles)
        if n < 4:
            return order_blocks

        opens = df_candles["open"].values
        highs = df_candles["high"].values
        lows = df_candles["low"].values
        closes = df_candles["close"].values
        deltas = df_candles["delta"].values if "delta" in df_candles.columns else np.zeros(n)
        volumes = df_candles["vol"].values if "vol" in df_candles.columns else np.zeros(n)
        timestamps = df_candles["timestamp"].values

        delta_medio = df_candles["delta"].abs().rolling(20, min_periods=1).mean().values if "delta" in df_candles.columns else np.ones(n)

        for i in range(1, n - 1):
            delta_atual = deltas[i + 1]
            med = delta_medio[i]

            # 1. Bullish Order Block:
            # Candle i é de baixa (close < open). Candle i+1 é impulsão de alta rompendo máxima de i com Delta comprador forte.
            if closes[i] < opens[i]:
                rompeu_alta = closes[i + 1] > highs[i]
                delta_forte = delta_atual > (self.delta_impulsao_multiplicador * med)
                if rompeu_alta and delta_forte:
                    ob = ZonaInstitucional(
                        tipo="BULLISH_OB",
                        nivel_superior=highs[i],
                        nivel_inferior=lows[i],
                        timestamp_criacao=pd.to_datetime(timestamps[i]),
                        indice_barra=i,
                        delta_origem=deltas[i],
                        volume_origem=volumes[i]
                    )
                    order_blocks.append(ob)

            # 2. Bearish Order Block:
            # Candle i é de alta (close > open). Candle i+1 é impulsão de baixa rompendo mínima de i com Delta vendedor forte.
            elif closes[i] > opens[i]:
                rompeu_baixa = closes[i + 1] < lows[i]
                delta_forte = delta_atual < -(self.delta_impulsao_multiplicador * med)
                if rompeu_baixa and delta_forte:
                    ob = ZonaInstitucional(
                        tipo="BEARISH_OB",
                        nivel_superior=highs[i],
                        nivel_inferior=lows[i],
                        timestamp_criacao=pd.to_datetime(timestamps[i]),
                        indice_barra=i,
                        delta_origem=deltas[i],
                        volume_origem=volumes[i]
                    )
                    order_blocks.append(ob)

        return order_blocks

    def atualizar_mitigacao_zonas(
        self,
        zonas: List[ZonaInstitucional],
        df_candles: pd.DataFrame
    ) -> List[ZonaInstitucional]:
        """
        Rastreia o ciclo de vida das zonas institucionais:
        Verifica se barras posteriores tocaram na zona (teste de liquidez) ou fecharam rompendo a zona (mitigação total).

        :param zonas: Lista de zonas detectadas.
        :param df_candles: DataFrame de candles M1.
        :return: Lista de zonas com estados de mitigação atualizados.
        """
        highs = df_candles["high"].values
        lows = df_candles["low"].values
        closes = df_candles["close"].values
        n = len(df_candles)

        for zona in zonas:
            idx_inicio = zona.indice_barra + 1
            if idx_inicio >= n:
                continue

            for j in range(idx_inicio, n):
                barra_high = highs[j]
                barra_low = lows[j]
                barra_close = closes[j]

                # Verifica se houve toque (reteste do Order Block institucional)
                if barra_low <= zona.nivel_superior and barra_high >= zona.nivel_inferior:
                    zona.testado = True

                # Mitigação total / Invalidação:
                # Se for Bullish e o preço fecha abaixo da mínima da zona
                if "BULLISH" in zona.tipo and barra_close < zona.nivel_inferior:
                    zona.mitigado = True
                    break

                # Se for Bearish e o preço fecha acima da máxima da zona
                if "BEARISH" in zona.tipo and barra_close > zona.nivel_superior:
                    zona.mitigado = True
                    break

        return zonas
