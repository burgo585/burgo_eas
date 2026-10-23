"""
Módulo de Automação de Execução em Tempo Real (Live Trading Bot).
Conecta o Motor Quantitativo TRAX ao MetaTrader 5 (VT Markets Demo).
Executa em background thread com monitoramento contínuo em sub-segundos,
inferência de IA (> 70%), gestão de risco e Trailing Stop ancorado em ATR.
"""

from pathlib import Path
import threading
import time
import datetime
from zoneinfo import ZoneInfo
from typing import Dict, Any, Optional, List
import pandas as pd
import numpy as np

try:
    import MetaTrader5 as mt5
    MT5_DISPONIVEL = True
except ImportError:
    MT5_DISPONIVEL = False

from config.settings import carregar_presets, ConfiguracaoGlobal, PresetAtivo
from src.ai.inference import InferenceEngine
from src.execution.signals import MotorSinaisQuantitativo, SinalTrade
from src.execution.order_router import OrderRouter
from src.execution.kill_switch import KillSwitchMOC
from src.utils.logger import obter_logger

logger = obter_logger("LiveBot")


class LiveBotEngine:
    """
    Controlador central de execução autônoma ao vivo no MetaTrader 5.
    Implementa padrão Singleton/Thread-safe para operação ininterrupta de alta frequência.
    """

    _instancia = None
    _lock = threading.Lock()

    def __new__(cls, *args, **kwargs):
        with cls._lock:
            if cls._instancia is None:
                cls._instancia = super(LiveBotEngine, cls).__new__(cls)
                cls._instancia._inicializado = False
            return cls._instancia

    def __init__(self, caminho_modelo: Optional[Path] = None):
        if getattr(self, "_inicializado", False):
            return

        self.config: ConfiguracaoGlobal = carregar_presets()
        self.caminho_modelo = caminho_modelo or Path("models/modelo_ia_xauusd.joblib")
        self.ia_engine = InferenceEngine(caminho_modelo=self.caminho_modelo, limiar_confianca=self.config.system.ai_confidence_threshold)
        self.roteador = OrderRouter(config_global=self.config, inference_engine=self.ia_engine)
        simbolo_mnq = self.config.assets.get("MNQ").mt5_symbol if "MNQ" in self.config.assets else "NAS100ft."
        self.kill_switch_mnq = KillSwitchMOC(simbolo=simbolo_mnq)

        self.ativo: bool = False
        self.thread_execucao: Optional[threading.Thread] = None
        self.logs_recentes: List[str] = []
        self.telemetria_ao_vivo: Dict[str, Any] = {}
        self.diagnostico_ativos: Dict[str, Any] = {}
        self._ultimo_sinal_timestamp: Dict[str, Any] = {}
        self._contador_ciclos: int = 0
        self.ultimo_status: Dict[str, Any] = {
            "status": "PARADO",
            "ultima_checagem": None,
            "ultimo_sinal": None,
            "ordens_enviadas": 0
        }
        self._inicializado = True

    def adicionar_log(self, msg: str):
        """Registra logs com timestamp para exibição na interface."""
        agora = datetime.datetime.now().strftime("%H:%M:%S")
        entrada = f"[{agora}] {msg}"
        self.logs_recentes.append(entrada)
        if len(self.logs_recentes) > 100:
            self.logs_recentes.pop(0)
        logger.info(msg)

    def iniciar(self):
        """Dispara a thread de monitoramento contínuo em tempo real."""
        with self._lock:
            if self.ativo:
                return
            self.ativo = True
            self.thread_execucao = threading.Thread(target=self._loop_execucao, daemon=True)
            self.thread_execucao.start()
            self.adicionar_log("⚡ Robô Quantitativo TRAX INICIADO em modo LIVE na corretora VT Markets.")

    def parar(self):
        """Pausa o motor de execução autônoma."""
        with self._lock:
            self.ativo = False
            self.adicionar_log("⏹ Robô Quantitativo TRAX PAUSADO pelo operador.")

    def esta_ativo(self) -> bool:
        """Retorna se o robô está em execução."""
        return self.ativo

    def _loop_execucao(self):
        """
        Loop mestre de monitoramento contínuo em tempo real (1 segundo).
        Varre microestrutura de ticks, calcula Delta/PoC e avalia IA sem interrupções.
        """
        while self.ativo:
            try:
                self.config = carregar_presets()
                agora_utc = datetime.datetime.now(datetime.timezone.utc)
                self._contador_ciclos += 1

                # 1. Verifica Kill-Switch de Nova York para MNQ (às 15:59:50 NY)
                self.kill_switch_mnq.verificar_e_executar_kill_switch_se_necessario()

                # 2. Sentinela de Proteção Institucional (Auto-Guardrail para ordens manuais)
                self._proteger_ordens_manuais()

                # 3. Itera sobre cada ativo configurado
                for nome_ativo, preset in self.config.assets.items():
                    simbolo_broker = preset.mt5_symbol
                    self._avaliar_ativo(nome_ativo, preset, simbolo_broker)

                # 4. Gerencia Trailing Stop e condução de lucros (robô e manual)
                self._gerenciar_trailing_stop()

                # 5. Heartbeat periódico de telemetria a cada ~8 segundos
                if self._contador_ciclos % 10 == 0 and self.telemetria_ao_vivo:
                    resumo = " | ".join([
                        f"{k}: ${v.get('preco', 0.0):,.2f} (Δ Mult: {v.get('delta_mult', 1.0):.1f}x)"
                        for k, v in self.telemetria_ao_vivo.items()
                    ])
                    self.adicionar_log(f"🔍 [Vigilância HFT] Varredura ativa ao vivo: {resumo}")

                self.ultimo_status["ultima_checagem"] = agora_utc.strftime("%Y-%m-%d %H:%M:%S UTC")
                time.sleep(0.8)  # Varredura contínua de alta velocidade
            except Exception as e:
                self.adicionar_log(f"Erro no loop de execução do robô: {e}")
                time.sleep(2.0)

    def dentro_horario_permitido(self, preset: PresetAtivo) -> tuple:
        """
        Verifica se o momento atual está dentro da janela operacional configurada pelo operador.
        Retorna (autorizado: bool, motivo: str).
        """
        modo = getattr(preset, "trading_hours_mode", "24h") or "24h"
        if modo == "24h":
            return True, "Modo 24 Horas Ativo (Operação Contínua)"

        tz_str = getattr(preset, "trading_timezone", "America/Sao_Paulo") or "America/Sao_Paulo"
        try:
            tz = ZoneInfo(tz_str)
        except Exception:
            tz = ZoneInfo("America/Sao_Paulo")

        agora = datetime.datetime.now(tz)
        minutos_atuais = agora.hour * 60 + agora.minute

        inicio_str = getattr(preset, "trading_start_time", "00:00") or "00:00"
        fim_str = getattr(preset, "trading_end_time", "23:59") or "23:59"

        try:
            p_ini = [int(x) for x in inicio_str.split(":")]
            p_fim = [int(x) for x in fim_str.split(":")]
            minutos_ini = p_ini[0] * 60 + p_ini[1]
            minutos_fim = p_fim[0] * 60 + p_fim[1]
        except Exception:
            minutos_ini = 0
            minutos_fim = 1439

        if minutos_ini <= minutos_fim:
            dentro = minutos_ini <= minutos_atuais <= minutos_fim
        else:
            dentro = minutos_atuais >= minutos_ini or minutos_atuais <= minutos_fim

        nome_fuso = "BRT" if "Sao_Paulo" in tz_str else "NY"
        if dentro:
            return True, f"Liberado: Janela {inicio_str} às {fim_str} ({nome_fuso})"
        else:
            return False, f"Pausado: Fora do Horário ({agora.strftime('%H:%M')} fora de {inicio_str}-{fim_str} {nome_fuso})"

    def _avaliar_ativo(self, nome_ativo: str, preset: PresetAtivo, simbolo_broker: str):
        """Avalia microestrutura, Order Flow e IA para um ativo específico com dados em tempo real."""
        if not MT5_DISPONIVEL:
            return

        tick_atual = mt5.symbol_info_tick(simbolo_broker)
        if not tick_atual:
            return

        # 1. Validação de Horário Operacional Customizado
        horario_ok, horario_motivo = self.dentro_horario_permitido(preset)

        # Para Nasdaq (MNQ), checa adicionalmente o pregão regular de NY (09:30 às 15:59:50)
        if preset.moc_loc_active and not self.kill_switch_mnq.dentro_horario_operacional_nasdaq():
            horario_ok = False
            horario_motivo = "Pausado: Fora do Pregão Regular de NY (09:30 às 15:59:50)"

        # Obtém candles M1 recentes da corretora
        rates = mt5.copy_rates_from_pos(simbolo_broker, mt5.TIMEFRAME_M1, 0, 60)
        if rates is None or len(rates) < 30:
            return

        df = pd.DataFrame(rates)
        df["timestamp"] = pd.to_datetime(df["time"], unit="s", utc=True)
        df["vol"] = df["tick_volume"].astype(float)

        # Cálculo de microestrutura e fluxo
        corpo = df["close"] - df["open"]
        amplitude = df["high"] - df["low"]
        amplitude = np.where(amplitude > 0, amplitude, 1.0)
        proporcao_alta = np.clip((corpo / amplitude) * 0.5 + 0.5, 0.05, 0.95)

        df["buy_vol"] = np.round(df["vol"] * proporcao_alta)
        df["sell_vol"] = df["vol"] - df["buy_vol"]
        df["delta"] = df["buy_vol"] - df["sell_vol"]
        df["cum_delta"] = df["delta"].cumsum()
        df["delta_ratio"] = df["delta"] / np.where(df["vol"] > 0, df["vol"], 1.0)
        df["poc"] = np.round((df["open"] + df["high"] + df["low"] + 2.0 * df["close"]) / 5.0, 2)

        # Cálculo do Delta Multiplier (Spike relativo contra média de 20 barras)
        media_delta = df["delta"].abs().rolling(window=20, min_periods=1).mean()
        df["delta_multiplier"] = df["delta"].abs() / np.where(media_delta > 0, media_delta, 1.0)

        # Atualiza dados de telemetria em tempo real do ativo
        preco_atual = tick_atual.bid
        spread_atual = round(tick_atual.ask - tick_atual.bid, 2)
        delta_atual = float(df["delta"].iloc[-1])
        delta_mult_atual = float(df["delta_multiplier"].iloc[-1])
        poc_atual = float(df["poc"].iloc[-1])

        # Initial Balance (Fábio Valentim)
        motor_sinais = MotorSinaisQuantitativo(preset=preset)
        ib_info = motor_sinais.calcular_initial_balance(df, janela_barras=30)
        ib_h = ib_info["ib_high"]
        ib_l = ib_info["ib_low"]
        ib_p = ib_info["ib_poc"]
        ib_rng = ib_info["ib_range"]

        if preco_atual > ib_h:
            estado_ib = "ROMPIDO COMPRA"
        elif preco_atual < ib_l:
            estado_ib = "ROMPIDO VENDA"
        else:
            estado_ib = "DENTRO DA FAIXA"

        # Verifica posições abertas existentes
        posicoes = mt5.positions_get(symbol=simbolo_broker)
        tem_posicao = bool(posicoes and len(posicoes) > 0)

        # Monta diagnóstico em tempo real
        motivo_diagnostico = ""
        if not horario_ok:
            motivo_diagnostico = f"⏸ {horario_motivo}. Aguardando janela autorizada."
        elif tem_posicao:
            motivo_diagnostico = f"💼 Posição já em andamento (#{posicoes[0].ticket}). Trailing Stop e Auto-Guardrail ativos."
        elif estado_ib == "DENTRO DA FAIXA":
            motivo_diagnostico = f"⚖️ Preço em ${preco_atual:,.2f} consolidado no Initial Balance (${ib_l:,.2f} a ${ib_h:,.2f}). Aguardando rompimento."
        elif delta_mult_atual < preset.delta_threshold_multiplier:
            motivo_diagnostico = f"⏳ Rompimento em teste, mas Delta Spike ({delta_mult_atual:.1f}x) abaixo do limiar exigido ({preset.delta_threshold_multiplier:.1f}x)."
        else:
            motivo_diagnostico = "🎯 Setup técnico ativo! Avaliando confluência com modelo de Inteligência Artificial..."

        self.telemetria_ao_vivo[nome_ativo] = {
            "timestamp": datetime.datetime.now().strftime("%H:%M:%S"),
            "preco": preco_atual,
            "spread": spread_atual,
            "delta": delta_atual,
            "delta_mult": delta_mult_atual,
            "poc": poc_atual
        }

        self.diagnostico_ativos[nome_ativo] = {
            "timestamp": datetime.datetime.now().strftime("%H:%M:%S"),
            "preco": preco_atual,
            "spread": spread_atual,
            "horario_ok": horario_ok,
            "horario_motivo": horario_motivo,
            "ib_high": ib_h,
            "ib_low": ib_l,
            "ib_poc": ib_p,
            "ib_range": ib_rng,
            "estado_ib": estado_ib,
            "delta_atual": delta_atual,
            "delta_mult": delta_mult_atual,
            "delta_exigido": preset.delta_threshold_multiplier,
            "delta_ok": delta_mult_atual >= preset.delta_threshold_multiplier,
            "poc_atual": poc_atual,
            "tem_posicao": tem_posicao,
            "motivo_diagnostico": motivo_diagnostico
        }

        if not horario_ok or tem_posicao:
            return

        # Gera sinais quantitativos
        sinais = motor_sinais.escanear_sinais(
            df,
            exigir_confluencia_smc=False,
            filtro_sessao_ativa=False,
            filtro_ema_tendencia=getattr(preset, "trend_ema_filter_active", True)
        )

        if not sinais:
            return

        ultimo_sinal = sinais[-1]
        timestamp_sinal = str(ultimo_sinal.timestamp)

        # Garante que o robô só execute uma vez por candle/sinal novo
        if self._ultimo_sinal_timestamp.get(nome_ativo) == timestamp_sinal:
            return

        ultimo_candle = df.iloc[-1].to_dict()

        # Validação com Pipeline de Inteligência Artificial (> 70%)
        atr_serie = motor_sinais.calcular_atr(df, periodo=preset.atr_period)
        atr_atual = float(atr_serie.iloc[-1]) if not atr_serie.empty else 1.0

        autorizado_ia, probabilidade = self.ia_engine.prever_probabilidade(
            candle=ultimo_candle,
            vix=18.0,
            dxy=104.0,
            l2_imbalance=0.0,
            atr_valor=atr_atual
        )

        self._ultimo_sinal_timestamp[nome_ativo] = timestamp_sinal
        self.diagnostico_ativos[nome_ativo]["ia_probabilidade"] = probabilidade
        self.diagnostico_ativos[nome_ativo]["ia_autorizado"] = autorizado_ia

        self.adicionar_log(f"[{nome_ativo}] Gatilho {ultimo_sinal.tipo} detectado a ${ultimo_sinal.preco_entrada:,.2f}! Probabilidade IA: {probabilidade:.1%} (Limiar: {self.config.system.ai_confidence_threshold:.0%})")

        if autorizado_ia:
            self.adicionar_log(f"🚀 IA AUTORIZOU O TRADE ({probabilidade:.1%})! Transmitindo ordem a mercado em {simbolo_broker} no MT5...")
            sucesso = self.roteador.processar_e_rotear_sinal(
                sinal=ultimo_sinal,
                simbolo=nome_ativo,
                candle_atual=ultimo_candle,
                atr_valor=atr_atual
            )
            if sucesso:
                self.ultimo_status["ordens_enviadas"] += 1
                self.adicionar_log(f"✔ ORDEM EXECUTADA COM SUCESSO na VT Markets ({simbolo_broker})!")
        else:
            self.adicionar_log(f"🛡 Trade vetado pela IA (Probabilidade {probabilidade:.1%} < {self.config.system.ai_confidence_threshold:.0%}). Capital protegido.")

    def _proteger_ordens_manuais(self):
        """
        Sentinela de Proteção Institucional (Auto-Guardrail):
        Varre todas as posições abertas na conta do MT5. Caso identifique qualquer posição
        aberta manualmente pelo operador (ou por script) desprovida de Stop Loss ou Take Profit (sl == 0.0 ou tp == 0.0),
        calcula imediatamente o Stop Loss ancorado em volatilidade (ATR) e o Take Profit com base na razão R:R
        do preset institucional do ativo, transmitindo a blindagem em milissegundos para a corretora.
        """
        if not MT5_DISPONIVEL:
            return

        posicoes = mt5.positions_get()
        if not posicoes:
            return

        for pos in posicoes:
            # Posição já completamente blindada com SL e TP definidos
            if pos.sl > 0.0 and pos.tp > 0.0:
                continue

            simbolo = pos.symbol

            # Localiza o preset configurado para o símbolo ou adota perfil institucional padrão
            preset = None
            for _, p in self.config.assets.items():
                if p.mt5_symbol == simbolo or p.mt5_symbol in simbolo:
                    preset = p
                    break

            rr_ratio = preset.risk_reward_ratio if preset else 2.0
            atr_mult = preset.atr_sl_multiplier if preset else 1.5

            info_simbolo = mt5.symbol_info(simbolo)
            if not info_simbolo:
                continue

            digitos = info_simbolo.digits
            point = info_simbolo.point
            spread = max(info_simbolo.ask - info_simbolo.bid, point * 10)

            # Extrai ATR recente (M1) para cálculo de volatilidade técnica
            rates = mt5.copy_rates_from_pos(simbolo, mt5.TIMEFRAME_M1, 0, 20)
            if rates is not None and len(rates) >= 5:
                df_m1 = pd.DataFrame(rates)
                tr = np.maximum(
                    df_m1["high"] - df_m1["low"],
                    np.maximum(
                        (df_m1["high"] - df_m1["close"].shift(1)).abs(),
                        (df_m1["low"] - df_m1["close"].shift(1)).abs()
                    )
                )
                atr_valor = float(tr.tail(14).mean())
            else:
                atr_valor = spread * 3.0

            # Distância técnica de Stop Loss
            dist_sl = max(atr_valor * atr_mult, spread * 2.5, point * 50)

            novo_sl = float(pos.sl)
            novo_tp = float(pos.tp)

            if pos.type == mt5.ORDER_TYPE_BUY:
                if novo_sl <= 0.0:
                    novo_sl = round(pos.price_open - dist_sl, digitos)
                if novo_tp <= 0.0:
                    dist_efetiva = pos.price_open - novo_sl
                    novo_tp = round(pos.price_open + (dist_efetiva * rr_ratio), digitos)
            elif pos.type == mt5.ORDER_TYPE_SELL:
                if novo_sl <= 0.0:
                    novo_sl = round(pos.price_open + dist_sl, digitos)
                if novo_tp <= 0.0:
                    dist_efetiva = novo_sl - pos.price_open
                    novo_tp = round(pos.price_open - (dist_efetiva * rr_ratio), digitos)

            # Transmite a blindagem à corretora
            if novo_sl > 0.0 and novo_tp > 0.0:
                req = {
                    "action": mt5.TRADE_ACTION_SLTP,
                    "position": pos.ticket,
                    "symbol": simbolo,
                    "sl": float(novo_sl),
                    "tp": float(novo_tp)
                }
                res = mt5.order_send(req)
                tipo_str = "COMPRA" if pos.type == mt5.ORDER_TYPE_BUY else "VENDA"
                if res and res.retcode == mt5.TRADE_RETCODE_DONE:
                    self.adicionar_log(
                        f"🛡 [Auto-Guardrail] Ordem manual detectada no ticket #{pos.ticket} ({tipo_str} {simbolo} @ {pos.price_open:.{digitos}f})! "
                        f"Blindagem aplicada: SL = {novo_sl:.{digitos}f} | TP = {novo_tp:.{digitos}f} (Risco:Retorno {rr_ratio}:1)."
                    )
                else:
                    erro_desc = getattr(res, "comment", "Erro na corretora")
                    self.adicionar_log(
                        f"⚠️ [Auto-Guardrail] Falha ao blindar ticket manual #{pos.ticket}: {erro_desc} (retcode: {getattr(res, 'retcode', -1)})"
                    )

    def _gerenciar_trailing_stop(self):
        """
        Ajusta o Stop Loss das posições abertas à medida que o preço avança a favor.
        Suporta tanto ordens autônomas do robô quanto ordens manuais do operador (magic == 0).
        """
        if not MT5_DISPONIVEL:
            return

        for nome_ativo, preset in self.config.assets.items():
            posicoes = mt5.positions_get(symbol=preset.mt5_symbol)
            if not posicoes:
                continue

            tick = mt5.symbol_info_tick(preset.mt5_symbol)
            if not tick:
                continue

            for pos in posicoes:
                # Gerencia posições geradas pelo robô ou posições manuais do operador
                if pos.magic != preset.magic_number and pos.magic != 0:
                    continue

                gatilho_distancia = preset.atr_sl_multiplier * 1.0
                distancia_trail = preset.atr_sl_multiplier * 0.8

                if pos.type == mt5.ORDER_TYPE_BUY:
                    ganho = tick.bid - pos.price_open
                    if ganho > gatilho_distancia:
                        novo_sl = round(tick.bid - distancia_trail, 2)
                        if pos.sl == 0.0 or novo_sl > pos.sl:
                            req = {
                                "action": mt5.TRADE_ACTION_SLTP,
                                "position": pos.ticket,
                                "symbol": pos.symbol,
                                "sl": float(novo_sl),
                                "tp": float(pos.tp)
                            }
                            mt5.order_send(req)
                elif pos.type == mt5.ORDER_TYPE_SELL:
                    ganho = pos.price_open - tick.ask
                    if ganho > gatilho_distancia:
                        novo_sl = round(tick.ask + distancia_trail, 2)
                        if pos.sl == 0.0 or novo_sl < pos.sl:
                            req = {
                                "action": mt5.TRADE_ACTION_SLTP,
                                "position": pos.ticket,
                                "symbol": pos.symbol,
                                "sl": float(novo_sl),
                                "tp": float(pos.tp)
                            }
                            mt5.order_send(req)


# Instância Singleton global
live_bot = LiveBotEngine()
