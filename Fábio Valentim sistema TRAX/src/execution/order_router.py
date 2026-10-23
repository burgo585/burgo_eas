"""
Módulo de Roteamento de Ordens e Máquina de Estados Multi-Ativos (Order Router Institucional).
Conecta o Motor de Order Flow, Zonas SMC, o Pipeline de Inteligência Artificial (> 70%)
e o Kill-Switch de MOC/LOC ao envio e gestão de ordens em tempo real no MetaTrader 5.
"""

import asyncio
from typing import Dict, Any, Optional, List
import pandas as pd

try:
    import MetaTrader5 as mt5
    MT5_DISPONIVEL = True
except ImportError:
    MT5_DISPONIVEL = False

from config.settings import ConfiguracaoGlobal, PresetAtivo
from src.ai.inference import InferenceEngine
from src.execution.kill_switch import KillSwitchMOC
from src.execution.signals import SinalTrade
from src.utils.logger import obter_logger

logger = obter_logger("OrderRouter")


class OrderRouter:
    """
    Roteador de execução institucional com máquina de estados para MNQ, XAUUSD e BTCUSD.
    Aplica validação tripla: Order Flow + Filtro SMC + Inferência de Inteligência Artificial (> 70%).
    """

    def __init__(
        self,
        config_global: ConfiguracaoGlobal,
        inference_engine: Optional[InferenceEngine] = None
    ):
        """
        Inicializa o roteador de ordens.

        :param config_global: Configurações completas e presets por ativo.
        :param inference_engine: Motor de IA para autorização probabilística.
        """
        self.config = config_global
        self.inference_engine = inference_engine
        self.kill_switch_mnq = KillSwitchMOC(
            simbolo="MNQ",
            horario_kill_ny=self.config.assets.get("MNQ", PresetAtivo(
                symbol="MNQ", mt5_symbol="MNQ", description="", asset_class=""
            )).kill_switch_time or "15:59:50",
            timezone_ny=self.config.system.timezone_ny
        )
        self.executando = False

    def validar_regras_ativo(self, simbolo: str) -> bool:
        """
        Verifica regras operacionais de horário e leilão específicas por ativo:
        - MNQ: Exige estritamente janela das 15:50 às 15:59:50 NY (Imagem 2).
        - XAUUSD / BTCUSD: Operação contínua 24/5 ou 24/7.

        :param simbolo: Ativo sob validação.
        :return: True se a janela operacional do ativo estiver autorizada.
        """
        preset = self.config.assets.get(simbolo)
        if not preset:
            logger.error(f"Preset não encontrado para o ativo: {simbolo}")
            return False

        # Regra de MOC/LOC para o Nasdaq (MNQ)
        if preset.moc_loc_active:
            if not self.kill_switch_mnq.dentro_janela_moc_loc():
                agora_ny = self.kill_switch_mnq.obter_horario_ny_atual().strftime("%H:%M:%S")
                logger.info(f"[{simbolo} BLOQUEADO] Fora da janela institucional MOC/LOC (15:50-15:59:50). Horário NY atual: {agora_ny}")
                return False

        return True

    def processar_e_rotear_sinal(
        self,
        sinal: SinalTrade,
        simbolo: str,
        candle_atual: Dict[str, Any],
        vix: float = 18.0,
        dxy: float = 104.0,
        l2_imbalance: float = 0.0,
        atr_valor: float = 1.0
    ) -> bool:
        """
        Submete o sinal quantitativo à avaliação da IA e, se aprovado, envia a mercado no MT5.

        :param sinal: Objeto de sinal gerado pelo motor de fluxo.
        :param simbolo: Símbolo a executar.
        :param candle_atual: Dados de microestrutura do candle.
        :param vix: Nível do VIX.
        :param dxy: Nível do DXY.
        :param l2_imbalance: Desequilíbrio L2 da Binance.
        :param atr_valor: Volatilidade ATR atual.
        :return: True se a ordem foi enviada e confirmada pela corretora.
        """
        # 1. Validação de Regras e Horário por Ativo (Regra MOC/LOC para MNQ)
        if not self.validar_regras_ativo(simbolo):
            return False

        # 2. Avaliação de Inteligência Artificial (In-Memory Inference > 70%)
        if self.inference_engine:
            autorizado, prob = self.inference_engine.prever_probabilidade(
                candle=candle_atual,
                vix=vix,
                dxy=dxy,
                l2_imbalance=l2_imbalance,
                atr_valor=atr_valor
            )
            if not autorizado:
                logger.warning(f"[{simbolo}] Ordem vetada pela IA (Probabilidade: {prob:.1%}). Roteamento cancelado.")
                return False

        # 3. Envio da Ordem para o MetaTrader 5
        preset = self.config.assets[simbolo]
        return self._enviar_ordem_mt5(sinal, preset)

    def _enviar_ordem_mt5(self, sinal: SinalTrade, preset: PresetAtivo) -> bool:
        """
        Formata o pacote de ordem e transmite via API MetaTrader 5.

        :param sinal: Dados do sinal de compra/venda.
        :param preset: Parâmetros institucionais do ativo.
        :return: True se a ordem foi executada com sucesso.
        """
        if not MT5_DISPONIVEL:
            logger.info(f"[SIMULAÇÃO ORDEM ENVIADA] {sinal.tipo} {preset.lot_size}x {preset.mt5_symbol} a {sinal.preco_entrada:.2f} | SL={sinal.stop_loss:.2f} | TP={sinal.take_profit:.2f}")
            return True

        tipo_ordem = mt5.ORDER_TYPE_BUY if sinal.tipo == "BUY" else mt5.ORDER_TYPE_SELL
        preco_execucao = mt5.symbol_info_tick(preset.mt5_symbol).ask if sinal.tipo == "BUY" else mt5.symbol_info_tick(preset.mt5_symbol).bid

        requisicao = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": preset.mt5_symbol,
            "volume": float(preset.lot_size),
            "type": tipo_ordem,
            "price": float(preco_execucao),
            "sl": float(sinal.stop_loss),
            "tp": float(sinal.take_profit),
            "deviation": int(preset.max_slippage_points * 10),
            "magic": int(preset.magic_number),
            "comment": f"TRAX AI HFT: {sinal.motivo[:25]}",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }

        logger.info(f"Transmitindo ordem {sinal.tipo} de {preset.lot_size} lotes em {preset.mt5_symbol}...")
        resultado = mt5.order_send(requisicao)

        if resultado and resultado.retcode == mt5.TRADE_RETCODE_DONE:
            logger.info(f"✔ ORDEM EXECUTADA NO MT5 COM SUCESSO! Ticket #{resultado.order} a {resultado.price}")
            return True
        else:
            erro = resultado.retcode if resultado else mt5.last_error()
            logger.error(f"Falha na execução da ordem no MT5: Código {erro}")
            return False

    async def rotina_trailing_stop_continuo(self, intervalo_segundos: float = 1.0):
        """
        Loop contínuo que monitora posições abertas no MT5 e ajusta o Stop Loss
        ancorado na volatilidade (ATR) para proteger os lucros da operação.
        """
        self.executando = True
        logger.info("Rotina de Trailing Stop contínuo institucional ativada.")

        while self.executando:
            try:
                if MT5_DISPONIVEL:
                    for simbolo, preset in self.config.assets.items():
                        posicoes = mt5.positions_get(symbol=preset.mt5_symbol)
                        if not posicoes:
                            continue

                        tick = mt5.symbol_info_tick(preset.mt5_symbol)
                        if not tick:
                            continue

                        for pos in posicoes:
                            if pos.magic != preset.magic_number:
                                continue

                            # Compra: Se o preço subiu, arrasta o SL para cima
                            if pos.type == mt5.ORDER_TYPE_BUY:
                                distancia = tick.bid - pos.price_open
                                if distancia > (preset.atr_sl_multiplier * 0.5):
                                    novo_sl = tick.bid - (preset.atr_sl_multiplier * 0.8)
                                    if novo_sl > pos.sl:
                                        req_mod = {
                                            "action": mt5.TRADE_ACTION_SLTP,
                                            "position": pos.ticket,
                                            "sl": float(novo_sl),
                                            "tp": float(pos.tp)
                                        }
                                        mt5.order_send(req_mod)

                            # Venda: Se o preço caiu, arrasta o SL para baixo
                            elif pos.type == mt5.ORDER_TYPE_SELL:
                                distancia = pos.price_open - tick.ask
                                if distancia > (preset.atr_sl_multiplier * 0.5):
                                    novo_sl = tick.ask + (preset.atr_sl_multiplier * 0.8)
                                    if pos.sl == 0.0 or novo_sl < pos.sl:
                                        req_mod = {
                                            "action": mt5.TRADE_ACTION_SLTP,
                                            "position": pos.ticket,
                                            "sl": float(novo_sl),
                                            "tp": float(pos.tp)
                                        }
                                        mt5.order_send(req_mod)

                await asyncio.sleep(intervalo_segundos)
            except Exception as e:
                logger.error(f"Erro no loop de Trailing Stop: {e}")
                await asyncio.sleep(2.0)

    def parar(self):
        """Encerra com segurança os loops e threads de execução."""
        self.executando = False
        self.kill_switch_mnq.parar()
        logger.info("Roteador de ordens e threads de execução finalizadas.")
