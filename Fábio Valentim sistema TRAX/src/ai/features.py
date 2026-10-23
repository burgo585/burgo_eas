"""
Módulo de Engenharia de Recursos (Feature Engineering) para Inteligência Artificial Institucional.
Empacota, normaliza e constrói o vetor de atributos preditivos:
- Delta Ratio (Delta / Volume)
- Distância do Fechamento ao Point of Control (PoC)
- Minuto do Dia (Sazonalidade intradiária)
- Níveis de Volatilidade e Dólar (VIX e DXY)
- Desequilíbrio do Book (Binance L2 Imbalance)
"""

from typing import Dict, Any, List, Optional
import numpy as np
import pandas as pd

from src.utils.logger import obter_logger

logger = obter_logger("AIFeatures")


class FeatureEngineer:
    """
    Construtor institucional de vetores de features para modelos preditivos de HFT.
    Garante ausência de vazamento de dados futuros (No Data Leakage).
    """

    NOMES_FEATURES = [
        "delta_ratio",
        "dist_close_poc",
        "minute_of_day",
        "vix",
        "dxy",
        "delta_multiplier",
        "atr_relativo",
        "l2_imbalance"
    ]

    @classmethod
    def extrair_features_candle(
        cls,
        candle: Dict[str, Any],
        vix: float = 18.0,
        dxy: float = 104.0,
        l2_imbalance: float = 0.0,
        atr_valor: float = 1.0
    ) -> np.ndarray:
        """
        Extrai o vetor numérico de features para inferência em tempo real in-memory.

        :param candle: Dicionário com dados do candle M1 (close, poc, vol, delta, delta_multiplier, timestamp).
        :param vix: Nível atual do índice VIX.
        :param dxy: Nível atual do índice DXY.
        :param l2_imbalance: Desequilíbrio atual de book L2.
        :param atr_valor: Valor do ATR de 14 períodos para normalização de distâncias.
        :return: Array 1D do NumPy com as features prontas para o modelo preditivo.
        """
        vol = float(candle.get("vol", 1.0))
        delta = float(candle.get("delta", 0.0))
        delta_ratio = delta / vol if vol > 0 else 0.0

        close = float(candle.get("close", 0.0))
        poc = float(candle.get("poc", close))
        dist_close_poc = (close - poc) / (atr_valor if atr_valor > 0 else 1.0)

        ts = pd.to_datetime(candle.get("timestamp", pd.Timestamp.now(tz="UTC")), utc=True)
        minute_of_day = (ts.hour * 60 + ts.minute) / 1440.0  # Normalizado entre 0 e 1

        delta_mult = float(candle.get("delta_multiplier", 1.0))
        atr_rel = (atr_valor / close) * 100.0 if close > 0 else 0.0

        vetor = np.array([
            delta_ratio,
            dist_close_poc,
            minute_of_day,
            float(vix) / 100.0,       # VIX normalizado
            float(dxy) / 100.0,       # DXY normalizado
            min(delta_mult, 10.0),    # Limitado para evitar outliers
            atr_rel,
            float(l2_imbalance)
        ], dtype=np.float32)

        return vetor

    @classmethod
    def construir_matriz_features(
        cls,
        df_candles: pd.DataFrame,
        df_macro: Optional[pd.DataFrame] = None,
        atr_periodo: int = 14
    ) -> pd.DataFrame:
        """
        Gera a matriz completa de features e histórico para o motor de treino offline.

        :param df_candles: DataFrame de candles M1 com microestrutura.
        :param df_macro: DataFrame opcional contendo séries de VIX e DXY sincronizadas.
        :param atr_periodo: Período do ATR.
        :return: DataFrame estruturado contendo a matriz X pronta para treinamento supervisionado.
        """
        df = df_candles.copy()
        n = len(df)
        if n == 0:
            return pd.DataFrame(columns=cls.NOMES_FEATURES)

        # 1. Delta Ratio
        df["vol_safe"] = np.where(df["vol"] > 0, df["vol"], 1.0)
        df["delta_ratio"] = df["delta"] / df["vol_safe"]

        # 2. ATR para normalização de distâncias
        high = df["high"]
        low = df["low"]
        close_ant = df["close"].shift(1).bfill()
        tr = np.maximum(high - low, np.maximum((high - close_ant).abs(), (low - close_ant).abs()))
        atr = tr.rolling(atr_periodo, min_periods=1).mean()
        df["atr_valor"] = np.where(atr > 0, atr, 1.0)

        # 3. Distância Close ao PoC normalizada pelo ATR
        df["dist_close_poc"] = (df["close"] - df["poc"]) / df["atr_valor"]

        # 4. Minuto do dia normalizado (0 a 1)
        ts = pd.to_datetime(df["timestamp"], utc=True)
        df["minute_of_day"] = (ts.dt.hour * 60 + ts.dt.minute) / 1440.0

        # 5. Variáveis Macro (VIX e DXY)
        if df_macro is not None and not df_macro.empty:
            if "macro_vix" in df_macro.columns:
                df["vix"] = df_macro["macro_vix"].ffill().bfill() / 100.0
            else:
                df["vix"] = 0.18
            if "macro_dxy" in df_macro.columns:
                df["dxy"] = df_macro["macro_dxy"].ffill().bfill() / 100.0
            else:
                df["dxy"] = 1.04
        else:
            df["vix"] = 0.18
            df["dxy"] = 1.04

        # 6. Multiplicador de Delta e ATR Relativo
        df["delta_multiplier"] = df.get("delta_multiplier", pd.Series(np.ones(n))).clip(upper=10.0)
        df["atr_relativo"] = (df["atr_valor"] / df["close"]) * 100.0

        # 7. L2 Imbalance
        df["l2_imbalance"] = df.get("l2_imbalance", pd.Series(np.zeros(n))).fillna(0.0)

        return df[cls.NOMES_FEATURES]
