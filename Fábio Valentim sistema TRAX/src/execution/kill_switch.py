"""
Módulo de Blindagem de Risco e Kill-Switch Automático de Fechamento (MOC/LOC Closing Cross).
Thread assíncrona de alta prioridade dedicada a zerar todas as posições abertas do MNQ (Nasdaq)
às 15:59:50 (Horário de Nova York), blindando a conta institucional contra o choque do leilão das 16:00.
Espelha a regra rigorosa da Imagem 2.
"""

import asyncio
import datetime
from zoneinfo import ZoneInfo
from typing import Optional, List, Dict, Any

try:
    import MetaTrader5 as mt5
    MT5_DISPONIVEL = True
except ImportError:
    MT5_DISPONIVEL = False

from src.utils.logger import obter_logger

logger = obter_logger("KillSwitchNY")


class KillSwitchMOC:
    """
    Guardião temporal e interruptor de emergência (Kill-Switch) para o Nasdaq (MNQ).
    Encerra ordens e posições antes do fechamento oficial da NYSE/Nasdaq (Closing Cross).
    """

    def __init__(
        self,
        simbolo: str = "MNQ",
        horario_kill_ny: str = "15:59:50",
        timezone_ny: str = "America/New_York"
    ):
        """
        Inicializa o Kill-Switch.

        :param simbolo: Ativo submetido ao leilão MOC (MNQ).
        :param horario_kill_ny: Horário exato de liquidação total em NY (padrão '15:59:50').
        :param timezone_ny: Fuso horário oficial de Nova York.
        """
        self.simbolo = simbolo
        self.timezone_ny = ZoneInfo(timezone_ny)
        partes = horario_kill_ny.split(":")
        self.hora_kill = int(partes[0])
        self.minuto_kill = int(partes[1])
        self.segundo_kill = int(partes[2]) if len(partes) > 2 else 0

        self.executando = False
        self.kill_executado_hoje = False
        self._data_ultimo_kill: Optional[datetime.date] = None

    def obter_horario_ny_atual(self) -> datetime.datetime:
        """Retorna o timestamp corrente no fuso de Nova York (Wall Street)."""
        return datetime.datetime.now(self.timezone_ny)

    def dentro_janela_moc_loc(self) -> bool:
        """
        Verifica se o relógio de Nova York está dentro da janela MOC/LOC estrita (15:50:00 às 15:59:50).
        Regra de negócio da Imagem 2: Somente neste intervalo o gatilho do MNQ é armado.
        """
        agora_ny = self.obter_horario_ny_atual()
        hora = agora_ny.hour
        minuto = agora_ny.minute
        segundo = agora_ny.second

        # Das 15:50:00 até 15:59:49
        if hora == 15 and 50 <= minuto < 60:
            if minuto == 59 and segundo >= self.segundo_kill:
                return False
            return True
        return False

    def dentro_horario_operacional_nasdaq(self) -> bool:
        """
        Verifica se o relógio de Nova York está dentro do pregão regular institucional (09:30:00 às 15:59:50 NY).
        Permite capturar os movimentos de abertura (RTH), o intraday e a janela especial de fechamento (MOC).
        """
        agora_ny = self.obter_horario_ny_atual()
        hora = agora_ny.hour
        minuto = agora_ny.minute
        segundo = agora_ny.second

        if hora < 9 or (hora == 9 and minuto < 30):
            return False
        if hora >= 16:
            return False
        if hora == 15 and minuto == 59 and segundo >= self.segundo_kill:
            return False

        return True

    def momento_zeragem_atingido(self) -> bool:
        """Verifica se o relógio bateu exatamente o horário do Kill-Switch (15:59:50 NY)."""
        agora_ny = self.obter_horario_ny_atual()
        if agora_ny.hour == self.hora_kill and agora_ny.minute == self.minuto_kill:
            if agora_ny.second >= self.segundo_kill:
                return True
        elif agora_ny.hour >= 16:
            return True
        return False

    def zerar_posicoes_mnq_mt5(self) -> int:
        """
        Fecha imediatamente a mercado todas as posições abertas do MNQ e cancela ordens pendentes.

        :return: Quantidade de posições zeradas.
        """
        if not MT5_DISPONIVEL:
            logger.warning("[SIMULAÇÃO] Kill-Switch: Posições do MNQ liquidadas virtualmente às 15:59:50 NY.")
            return 0

        logger.critical(f"🚨 [KILL-SWITCH ATIVADO] 15:59:50 NY ATINGIDO! LIQUIDANDO TODAS AS POSIÇÕES DE {self.simbolo}...")

        posicoes = mt5.positions_get(symbol=self.simbolo)
        total_zeradas = 0

        if posicoes:
            for pos in posicoes:
                ticket = pos.ticket
                volume = pos.volume
                tipo_pos = pos.type  # 0 = BUY, 1 = SELL

                # Ordem oposta a mercado para liquidação instantânea
                tipo_ordem_fechar = mt5.ORDER_TYPE_SELL if tipo_pos == mt5.ORDER_TYPE_BUY else mt5.ORDER_TYPE_BUY
                preco_fechar = mt5.symbol_info_tick(self.simbolo).bid if tipo_pos == mt5.ORDER_TYPE_BUY else mt5.symbol_info_tick(self.simbolo).ask

                requisicao = {
                    "action": mt5.TRADE_ACTION_DEAL,
                    "symbol": self.simbolo,
                    "volume": volume,
                    "type": tipo_ordem_fechar,
                    "position": ticket,
                    "price": preco_fechar,
                    "deviation": 20,
                    "magic": 999999,
                    "comment": "TRAX MOC/LOC Kill-Switch 15:59:50",
                    "type_time": mt5.ORDER_TIME_GTC,
                    "type_filling": mt5.ORDER_FILLING_IOC,
                }

                resultado = mt5.order_send(requisicao)
                if resultado and resultado.retcode == mt5.TRADE_RETCODE_DONE:
                    logger.info(f"✔ Posição #{ticket} de {self.simbolo} zerada com sucesso! Retcode: {resultado.retcode}")
                    total_zeradas += 1
                else:
                    erro = resultado.retcode if resultado else "Sem resposta"
                    logger.error(f"Falha ao zerar posição #{ticket}: Retcode {erro}")

        # Cancela qualquer ordem pendente
        ordens_pendentes = mt5.orders_get(symbol=self.simbolo)
        if ordens_pendentes:
            for ordem in ordens_pendentes:
                req_cancela = {
                    "action": mt5.TRADE_ACTION_REMOVE,
                    "order": ordem.ticket
                }
                mt5.order_send(req_cancela)
                logger.info(f"Ordem pendente #{ordem.ticket} cancelada pelo Kill-Switch.")

        logger.info(f"Kill-Switch concluído: {total_zeradas} posições encerradas. Conta blindada contra o Closing Cross das 16:00!")
        return total_zeradas

    def verificar_e_executar_kill_switch_se_necessario(self) -> int:
        """
        Verificação síncrona periódica: Checa se o horário de Nova York atingiu o limiar
        de Kill-Switch (15:59:50 NY). Se atingido e ainda não disparado hoje, liquida as posições.

        :return: Quantidade de posições encerradas (0 se nada foi zerado).
        """
        agora_ny = self.obter_horario_ny_atual()
        data_hoje = agora_ny.date()

        # Reseta o gatilho diário se mudou de dia
        if self._data_ultimo_kill != data_hoje:
            self.kill_executado_hoje = False

        if not self.kill_executado_hoje and self.momento_zeragem_atingido():
            zeradas = self.zerar_posicoes_mnq_mt5()
            self.kill_executado_hoje = True
            self._data_ultimo_kill = data_hoje
            return zeradas

        return 0

    async def loop_monitoramento_kill_switch(self, intervalo_ms: int = 100):
        """
        Thread assíncrona contínua de alta precisão que monitora o relógio de Nova York.
        """
        self.executando = True
        logger.info(f"Thread do Kill-Switch MOC/LOC ativa para {self.simbolo} (Alvo: 15:59:50 NY).")

        while self.executando:
            try:
                agora_ny = self.obter_horario_ny_atual()
                data_hoje = agora_ny.date()

                # Reseta o gatilho para o novo dia
                if self._data_ultimo_kill != data_hoje:
                    self.kill_executado_hoje = False

                if not self.kill_executado_hoje and self.momento_zeragem_atingido():
                    self.zerar_posicoes_mnq_mt5()
                    self.kill_executado_hoje = True
                    self._data_ultimo_kill = data_hoje

                await asyncio.sleep(intervalo_ms / 1000.0)

            except Exception as e:
                logger.error(f"Erro na thread do Kill-Switch: {e}")
                await asyncio.sleep(1.0)

    def parar(self):
        """Encerra a thread do Kill-Switch."""
        self.executando = False
        logger.info("Thread do Kill-Switch encerrada.")
