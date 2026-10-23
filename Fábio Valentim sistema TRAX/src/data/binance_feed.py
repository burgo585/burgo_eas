"""
Módulo de Ingestão de Fluxo Externo de Criptoativos via Binance.
Extrai desequilíbrio de Livro de Ofertas Level 2 (Order Book L2 Imbalance)
e eventos de Liquidação Forçada em tempo real com foco no BTCUSD.
"""

import asyncio
import json
import time
import datetime
from typing import Optional, Dict, List, Any
import pandas as pd
import requests
import websockets

from src.utils.logger import obter_logger
from config.settings import ConfiguracaoBinance

logger = obter_logger("BinanceFeed")


class BinanceFeed:
    """
    Coletor assíncrono de microestrutura da Binance Futures.
    Mapeia L2 Order Book Imbalance e volume de liquidações forçadas institucionais.
    """

    def __init__(self, config_binance: Optional[ConfiguracaoBinance] = None):
        """
        Inicializa o leitor de feeds da Binance.

        :param config_binance: Configurações de endpoints e parâmetros de profundidade.
        """
        self.config = config_binance or ConfiguracaoBinance()
        self.executando = False
        self.ultimo_snapshot: Dict[str, Any] = {
            "timestamp": datetime.datetime.now(datetime.timezone.utc),
            "symbol": self.config.depth_symbol.upper(),
            "l2_bid_qty": 0.0,
            "l2_ask_qty": 0.0,
            "l2_imbalance": 0.0,
            "best_bid": 0.0,
            "best_ask": 0.0,
            "liq_long_vol": 0.0,
            "liq_short_vol": 0.0
        }
        self.historico_snapshots: List[Dict[str, Any]] = []
        self._tarefas: List[asyncio.Task] = []

    def calcular_imbalance(self, bids: List[List[str]], asks: List[List[str]]) -> tuple:
        """
        Calcula o Desequilíbrio do Livro de Ofertas (L2 Order Book Imbalance).
        Fórmula: Imbalance = (Volume_Bids - Volume_Asks) / (Volume_Bids + Volume_Asks)

        :param bids: Lista de ofertas de compra [[preco, quantidade], ...]
        :param asks: Lista de ofertas de venda [[preco, quantidade], ...]
        :return: Tupla (imbalance, total_bid_qty, total_ask_qty, best_bid, best_ask)
        """
        try:
            total_bid_qty = sum(float(b[1]) for b in bids)
            total_ask_qty = sum(float(a[1]) for a in asks)
            best_bid = float(bids[0][0]) if bids else 0.0
            best_ask = float(asks[0][0]) if asks else 0.0

            denominador = total_bid_qty + total_ask_qty
            if denominador > 0:
                imbalance = (total_bid_qty - total_ask_qty) / denominador
            else:
                imbalance = 0.0

            return imbalance, total_bid_qty, total_ask_qty, best_bid, best_ask
        except Exception as e:
            logger.error(f"Erro ao calcular imbalance do book: {e}")
            return 0.0, 0.0, 0.0, 0.0, 0.0

    async def _stream_orderbook_l2(self):
        """
        WebSocket assíncrono para o feed de profundidade parcial de 20 níveis (L2).
        """
        simbolo = self.config.depth_symbol.lower()
        url = f"{self.config.ws_base_url}/{simbolo}@depth{self.config.depth_levels}@{self.config.depth_speed_ms}ms"

        while self.executando:
            try:
                logger.info(f"Conectando ao WebSocket L2 Depth da Binance: {url}")
                async with websockets.connect(url, ping_interval=20, ping_timeout=10) as ws:
                    logger.info("WebSocket L2 da Binance conectado com sucesso.")
                    while self.executando:
                        mensagem = await ws.recv()
                        dados = json.loads(mensagem)

                        bids = dados.get("b", [])
                        asks = dados.get("a", [])

                        imbalance, bid_qty, ask_qty, best_bid, best_ask = self.calcular_imbalance(bids, asks)

                        agora_utc = datetime.datetime.now(datetime.timezone.utc)
                        self.ultimo_snapshot["timestamp"] = agora_utc
                        self.ultimo_snapshot["l2_bid_qty"] = bid_qty
                        self.ultimo_snapshot["l2_ask_qty"] = ask_qty
                        self.ultimo_snapshot["l2_imbalance"] = imbalance
                        self.ultimo_snapshot["best_bid"] = best_bid
                        self.ultimo_snapshot["best_ask"] = best_ask

                        # Armazena cópia no buffer histórico para alinhamento temporal
                        self.historico_snapshots.append(dict(self.ultimo_snapshot))
                        if len(self.historico_snapshots) > 10000:
                            self.historico_snapshots.pop(0)

            except (websockets.ConnectionClosed, asyncio.CancelledError):
                logger.warning("Conexão WebSocket L2 Binance encerrada. Tentando reconexão...")
                await asyncio.sleep(2)
            except Exception as e:
                logger.error(f"Erro no WebSocket L2 da Binance: {e}")
                await asyncio.sleep(3)

    async def _stream_liquidacoes(self):
        """
        WebSocket assíncrono para captura do fluxo de liquidações forçadas do mercado de futuros.
        """
        url = f"{self.config.ws_base_url}/!forceOrder@arr"

        while self.executando:
            try:
                logger.info("Conectando ao stream de liquidações da Binance Futures...")
                async with websockets.connect(url, ping_interval=20, ping_timeout=10) as ws:
                    logger.info("Stream de liquidações da Binance ativo.")
                    while self.executando:
                        mensagem = await ws.recv()
                        dados = json.loads(mensagem)

                        ordem = dados.get("o", {})
                        simbolo_ordem = ordem.get("s", "").upper()

                        # Filtra apenas o ativo de referência (ex: BTCUSDT)
                        if simbolo_ordem == self.config.depth_symbol.upper():
                            lado = ordem.get("S", "")       # SELL (Long liquidado) ou BUY (Short liquidado)
                            volume = float(ordem.get("q", 0.0))
                            preco = float(ordem.get("p", 0.0))
                            valor_nocional = volume * preco

                            if lado == "SELL":
                                # Liquidação de compradores alavancados
                                self.ultimo_snapshot["liq_long_vol"] += valor_nocional
                                logger.info(f"[LIQUIDAÇÃO LONG] {simbolo_ordem}: ${valor_nocional:,.2f} a {preco}")
                            elif lado == "BUY":
                                # Liquidação de vendedores alavancados
                                self.ultimo_snapshot["liq_short_vol"] += valor_nocional
                                logger.info(f"[LIQUIDAÇÃO SHORT] {simbolo_ordem}: ${valor_nocional:,.2f} a {preco}")

            except (websockets.ConnectionClosed, asyncio.CancelledError):
                logger.warning("Conexão com stream de liquidações encerrada. Reconectando...")
                await asyncio.sleep(2)
            except Exception as e:
                logger.error(f"Erro no stream de liquidações: {e}")
                await asyncio.sleep(3)

    def obter_snapshot_rest_sincrono(self) -> Dict[str, Any]:
        """
        Método síncrono via REST API da Binance para inicialização rápida ou fallback.

        :return: Dicionário com métricas de livro e imbalance.
        """
        try:
            url = f"{self.config.rest_base_url}/fapi/v1/depth"
            params = {"symbol": self.config.depth_symbol.upper(), "limit": self.config.depth_levels}
            resposta = requests.get(url, params=params, timeout=5)

            if resposta.status_code == 200:
                dados = resposta.json()
                bids = dados.get("bids", [])
                asks = dados.get("asks", [])
                imbalance, bid_qty, ask_qty, best_bid, best_ask = self.calcular_imbalance(bids, asks)

                agora_utc = datetime.datetime.now(datetime.timezone.utc)
                self.ultimo_snapshot.update({
                    "timestamp": agora_utc,
                    "l2_bid_qty": bid_qty,
                    "l2_ask_qty": ask_qty,
                    "l2_imbalance": imbalance,
                    "best_bid": best_bid,
                    "best_ask": best_ask
                })
                return self.ultimo_snapshot
        except Exception as e:
            logger.error(f"Falha na requisição REST de depth da Binance: {e}")

        return self.ultimo_snapshot

    async def iniciar(self):
        """Dispara todas as corrotinas de captura da Binance."""
        if not self.config.enabled:
            logger.info("Feed da Binance desabilitado nas configurações.")
            return

        self.executando = True
        loop = asyncio.get_running_loop()
        self._tarefas.append(loop.create_task(self._stream_orderbook_l2()))
        self._tarefas.append(loop.create_task(self._stream_liquidacoes()))

    def parar(self):
        """Encerra com segurança todas as conexões assíncronas."""
        self.executando = False
        for tarefa in self._tarefas:
            tarefa.cancel()
        logger.info("Feeds da Binance finalizados.")

    def obter_dataframe_historico(self) -> pd.DataFrame:
        """
        Converte o buffer acumulado em um DataFrame indexado por timestamp UTC.

        :return: DataFrame Pandas com histórico de desequilíbrio e liquidações.
        """
        if not self.historico_snapshots:
            # Gera ao menos uma linha caso o buffer esteja vazio
            snapshot_atual = dict(self.ultimo_snapshot)
            return pd.DataFrame([snapshot_atual])

        df = pd.DataFrame(self.historico_snapshots)
        df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True)
        return df.sort_values("timestamp").reset_index(drop=True)
