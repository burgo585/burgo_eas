"""
Módulo de Treinamento Offline de Inteligência Artificial Institucional.
Lê candles M1 históricos, rotula operações entre Lucro (1) e Prejuízo (0),
treina modelo de Gradient Boosting, calcula Feature Importance e exporta em .joblib.
"""

from pathlib import Path
from typing import Dict, Any, Tuple, Optional
import numpy as np
import pandas as pd
import joblib

from sklearn.ensemble import HistGradientBoostingClassifier, RandomForestClassifier
from sklearn.inspection import permutation_importance
from sklearn.metrics import accuracy_score, precision_score, recall_score, roc_auc_score, f1_score
from sklearn.model_selection import TimeSeriesSplit

from src.ai.features import FeatureEngineer
from config.settings import PresetAtivo
from src.utils.logger import obter_logger

logger = obter_logger("AITrainer")


class ModelTrainer:
    """
    Motor de treinamento supervisionado para modelos preditivos institucionais.
    Treina árvore de decisão por Gradient Boosting para classificar probabilidade de vitória de cada setup.
    """

    def __init__(self, random_state: int = 42):
        self.random_state = random_state
        self.modelo = HistGradientBoostingClassifier(
            max_iter=150,
            learning_rate=0.05,
            max_depth=5,
            min_samples_leaf=20,
            l2_regularization=1.5,
            random_state=self.random_state
        )
        self.metricas_treino: Dict[str, float] = {}
        self.importancia_features: Dict[str, float] = {}

    def rotular_operacoes(
        self,
        df_candles: pd.DataFrame,
        preset: PresetAtivo,
        horizonte_barras: int = 60
    ) -> Tuple[pd.DataFrame, pd.Series]:
        """
        Cria o dataset supervisionado rotulando com precisão os desfechos futuros:
        - 1: O trade atingiu o Take Profit institucional antes do Stop Loss.
        - 0: O trade foi estopado ou não alcançou a relação de ganho pretendida.

        :param df_candles: DataFrame de candles M1 com microestrutura.
        :param preset: Parâmetros operacionais do ativo (SL, RR).
        :param horizonte_barras: Janela máxima de barras para busca do alvo.
        :return: Tupla contendo matriz de features X e série binária de targets y.
        """
        logger.info(f"Iniciando rotulação matemática de trades futuros para {preset.symbol}...")
        n = len(df_candles)
        closes = df_candles["close"].values
        highs = df_candles["high"].values
        lows = df_candles["low"].values
        deltas = df_candles["delta"].values

        # ATR 14
        tr = np.maximum(highs - lows, np.maximum(np.abs(highs - np.roll(closes, 1)), np.abs(lows - np.roll(closes, 1))))
        atr = pd.Series(tr).rolling(preset.atr_period, min_periods=1).mean().values

        labels = []
        indices_validos = []

        for i in range(20, n - horizonte_barras):
            preco_entrada = closes[i]
            dist_sl = atr[i] * preset.atr_sl_multiplier
            delta = deltas[i]

            # Direção do teste com base no Delta da barra
            if delta >= 0:
                # Setup Comprador
                alvo_tp = preco_entrada + (dist_sl * preset.risk_reward_ratio)
                alvo_sl = preco_entrada - dist_sl
                ganhou = 0

                for j in range(i + 1, i + horizonte_barras):
                    if lows[j] <= alvo_sl:
                        ganhou = 0
                        break
                    elif highs[j] >= alvo_tp:
                        ganhou = 1
                        break

                labels.append(ganhou)
                indices_validos.append(i)

            else:
                # Setup Vendedor
                alvo_tp = preco_entrada - (dist_sl * preset.risk_reward_ratio)
                alvo_sl = preco_entrada + dist_sl
                ganhou = 0

                for j in range(i + 1, i + horizonte_barras):
                    if highs[j] >= alvo_sl:
                        ganhou = 0
                        break
                    elif lows[j] <= alvo_tp:
                        ganhou = 1
                        break

                labels.append(ganhou)
                indices_validos.append(i)

        df_filtrado = df_candles.iloc[indices_validos].reset_index(drop=True)
        X = FeatureEngineer.construir_matriz_features(df_filtrado)
        y = pd.Series(labels, name="target")

        proporcao_vitorias = (y.sum() / len(y)) * 100 if len(y) > 0 else 0.0
        logger.info(f"Dataset rotulado: {len(X):,} amostras | Proporção de Alvos Atingidos: {proporcao_vitorias:.2f}%")
        return X, y

    def treinar_e_avaliar(
        self,
        X: pd.DataFrame,
        y: pd.Series,
        test_size_ratio: float = 0.20
    ) -> Dict[str, Any]:
        """
        Executa treino com divisão temporal estrita (Walk-Forward / Time-Series Split)
        para garantir fidelidade e ausência de overfitting intradiário.

        :param X: Matriz de features normalizadas.
        :param y: Vetor binário de classes (0 ou 1).
        :param test_size_ratio: Proporção temporal para o conjunto de teste out-of-sample.
        :return: Dicionário contendo métricas institucionais do modelo.
        """
        n_total = len(X)
        ponto_corte = int(n_total * (1.0 - test_size_ratio))

        X_train, X_test = X.iloc[:ponto_corte], X.iloc[ponto_corte:]
        y_train, y_test = y.iloc[:ponto_corte], y.iloc[ponto_corte:]

        logger.info(f"Treinando modelo preditivo: Treino = {len(X_train):,} | Teste = {len(X_test):,} amostras...")
        self.modelo.fit(X_train, y_train)

        # Inferência nas amostras fora da amostra (Out-of-Sample)
        probabilidades = self.modelo.predict_proba(X_test)[:, 1]
        previsoes = (probabilidades >= 0.50).astype(int)

        precisao = precision_score(y_test, previsoes, zero_division=0)
        revocacao = recall_score(y_test, previsoes, zero_division=0)
        f1 = f1_score(y_test, previsoes, zero_division=0)
        roc_auc = roc_auc_score(y_test, probabilidades) if len(np.unique(y_test)) > 1 else 0.50
        acuracia = accuracy_score(y_test, previsoes)

        self.metricas_treino = {
            "accuracy": acuracia,
            "precision": precisao,
            "recall": revocacao,
            "f1_score": f1,
            "roc_auc": roc_auc
        }

        # Cálculo de Permutation Feature Importance
        perm_res = permutation_importance(
            self.modelo, X_test, y_test,
            n_repeats=5, random_state=self.random_state
        )
        self.importancia_features = {
            col: float(importancia)
            for col, importancia in zip(X.columns, perm_res.importances_mean)
        }

        logger.info("=================================================================")
        logger.info("MÉTRICAS INSTITUCIONAIS DO MODELO PREDITIVO (OUT-OF-SAMPLE)")
        logger.info(f"  -> ROC AUC:    {roc_auc:.4f}")
        logger.info(f"  -> Precisão:   {precisao:.2%}")
        logger.info(f"  -> Revocação:  {revocacao:.2%}")
        logger.info(f"  -> F1-Score:   {f1:.4f}")
        logger.info("-----------------------------------------------------------------")
        logger.info("RANKING DE FEATURE IMPORTANCE:")
        for feat, imp in sorted(self.importancia_features.items(), key=lambda x: x[1], reverse=True):
            logger.info(f"  -> {feat:<18}: {imp:+.4f}")
        logger.info("=================================================================")

        return {
            "metricas": self.metricas_treino,
            "feature_importance": self.importancia_features
        }

    def salvar_artefato(self, caminho_arquivo: Path):
        """
        Salva o modelo treinado, lista de features e metadados em formato binário comprimido.

        :param caminho_arquivo: Caminho de destino (.joblib).
        """
        caminho_arquivo.parent.mkdir(parents=True, exist_ok=True)
        artefato = {
            "modelo": self.modelo,
            "features": FeatureEngineer.NOMES_FEATURES,
            "metricas": self.metricas_treino,
            "feature_importance": self.importancia_features,
            "versao": "1.0.0"
        }
        joblib.dump(artefato, caminho_arquivo, compress=3)
        logger.info(f"Modelo de IA institucional salvo com sucesso em: {caminho_arquivo}")
