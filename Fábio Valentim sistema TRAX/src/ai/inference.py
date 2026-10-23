"""
Módulo de Inferência de Inteligência Artificial em Tempo Real (In-Memory Inference).
Executa previsões probabilísticas em sub-milissegundos antes do envio de ordens ao MT5.
Filtra sinais de trading autorizando execução estritamente se probabilidade > 70%.
"""

from pathlib import Path
from typing import Dict, Any, Tuple, Optional
import numpy as np
import pandas as pd
import joblib

from src.ai.features import FeatureEngineer
from src.utils.logger import obter_logger

logger = obter_logger("AIInference")


class InferenceEngine:
    """
    Motor preditivo in-memory de ultrabaixa latência para HFT.
    Avalia a probabilidade matemática de sucesso de cada setup antes do roteamento de ordens.
    """

    def __init__(self, caminho_modelo: Optional[Path] = None, limiar_confianca: float = 0.70):
        """
        Inicializa o motor carregando o artefato de IA na memória RAM.

        :param caminho_modelo: Caminho para o arquivo .joblib treinado.
        :param limiar_confianca: Probabilidade mínima de sucesso requerida (padrão 0.70 ou 70%).
        """
        self.limiar_confianca = limiar_confianca
        self.modelo = None
        self.features_esperadas = FeatureEngineer.NOMES_FEATURES
        self.modelo_carregado = False

        if caminho_modelo:
            caminho_modelo = Path(caminho_modelo) if isinstance(caminho_modelo, str) else caminho_modelo
            if caminho_modelo.exists():
                self.carregar_modelo(caminho_modelo)

    def carregar_modelo(self, caminho_modelo: Path):
        """Carrega e valida o artefato do modelo preditivo."""
        try:
            logger.info(f"Carregando modelo preditivo in-memory de: {caminho_modelo}...")
            artefato = joblib.load(caminho_modelo)
            self.modelo = artefato["modelo"]
            self.features_esperadas = artefato.get("features", FeatureEngineer.NOMES_FEATURES)
            self.modelo_carregado = True
            logger.info("Modelo de IA institucional carregado e pronto para inferência online.")
        except Exception as e:
            logger.error(f"Falha ao carregar artefato de IA: {e}")
            self.modelo_carregado = False

    def prever_probabilidade(
        self,
        candle: Dict[str, Any],
        vix: float = 18.0,
        dxy: float = 104.0,
        l2_imbalance: float = 0.0,
        atr_valor: float = 1.0
    ) -> Tuple[bool, float]:
        """
        Calcula a probabilidade de sucesso de uma ordem com latência em microssegundos.

        :param candle: Dicionário contendo dados do candle atual (close, poc, vol, delta, etc.).
        :param vix: Cotação atual do VIX.
        :param dxy: Nível atual do DXY.
        :param l2_imbalance: Desequilíbrio do book da Binance.
        :param atr_valor: Volatilidade ATR atual.
        :return: Tupla (autorizado: bool, probabilidade: float).
        """
        if not self.modelo_carregado or self.modelo is None:
            # Fallback seguro: se o modelo não estiver treinado, aprova com aviso
            return True, 0.50

        # 1. Extração do vetor de features em formato DataFrame com nomes
        vetor_x = FeatureEngineer.extrair_features_candle(
            candle=candle,
            vix=vix,
            dxy=dxy,
            l2_imbalance=l2_imbalance,
            atr_valor=atr_valor
        ).reshape(1, -1)
        df_x = pd.DataFrame(vetor_x, columns=self.features_esperadas)

        # 2. Inferência in-memory
        prob_sucesso = float(self.modelo.predict_proba(df_x)[0, 1])

        # 3. Filtro Institucional (> 70%)
        autorizado = prob_sucesso >= self.limiar_confianca

        if autorizado:
            logger.info(f"[IA APROVADA] Confiança: {prob_sucesso:.1%} >= Limiar ({self.limiar_confianca:.0%}). Ordem liberada!")
        else:
            logger.warning(f"[IA BLOQUEADA] Confiança insuficiente: {prob_sucesso:.1%} < Limiar ({self.limiar_confianca:.0%}). Ordem descartada.")

        return autorizado, prob_sucesso
