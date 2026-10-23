"""
Módulo de Geração de Sinais de Trade e Automação de Execução.
Combina Order Flow (Delta Spikes e PoC), Zonas SMC (Order Blocks e FVG)
e regras institucionais para abertura e gestão de posições.
"""

from typing import List, Dict, Any, Optional
import numpy as np
import pandas as pd

from config.settings import PresetAtivo
from src.analytics.smc_zones import SMCZonesEngine, ZonaInstitucional
from src.utils.logger import obter_logger

logger = obter_logger("SignalsEngine")


class SinalTrade:
    """Estrutura representativa de um sinal institucional disparado (IVB Modelos 1 e 2)."""

    def __init__(
        self,
        tipo: str,                  # 'BUY' ou 'SELL'
        timestamp: pd.Timestamp,
        preco_entrada: float,
        stop_loss: float,
        take_profit: float,
        razao_rr: float,
        delta: float,
        delta_multiplier: float,
        poc: float,
        motivo: str,
        modelo: str = "IVB_1",      # 'IVB_1' (Volume Profile) ou 'IVB_2' (Delta Imbalance)
        ib_high: float = 0.0,
        ib_low: float = 0.0
    ):
        self.tipo = tipo
        self.timestamp = timestamp
        self.preco_entrada = preco_entrada
        self.stop_loss = stop_loss
        self.take_profit = take_profit
        self.razao_rr = razao_rr
        self.delta = delta
        self.delta_multiplier = delta_multiplier
        self.poc = poc
        self.motivo = motivo
        self.modelo = modelo
        self.ib_high = ib_high
        self.ib_low = ib_low

    def to_dict(self) -> Dict[str, Any]:
        return {
            "timestamp": self.timestamp,
            "tipo": self.tipo,
            "preco_entrada": self.preco_entrada,
            "stop_loss": self.stop_loss,
            "take_profit": self.take_profit,
            "razao_rr": self.razao_rr,
            "delta": self.delta,
            "delta_mult": self.delta_multiplier,
            "poc": self.poc,
            "motivo": self.motivo,
            "modelo": self.modelo,
            "ib_high": self.ib_high,
            "ib_low": self.ib_low
        }


class MotorSinaisQuantitativo:
    """
    Máquina de estados para validação de setups de fluxo institucional.
    """

    def __init__(self, preset: PresetAtivo):
        """
        Inicializa o motor com o preset do ativo.

        :param preset: Configurações do ativo (ex: XAUUSD).
        """
        self.preset = preset
        self.smc_engine = SMCZonesEngine(
            fvg_min_tamanho=0.20,
            delta_impulsao_multiplicador=self.preset.delta_threshold_multiplier
        )

    def calcular_atr(self, df_candles: pd.DataFrame, periodo: int = 14) -> pd.Series:
        """Calcula o Average True Range (ATR) para stop dinâmico."""
        high = df_candles["high"]
        low = df_candles["low"]
        close_ant = df_candles["close"].shift(1)

        tr1 = high - low
        tr2 = (high - close_ant).abs()
        tr3 = (low - close_ant).abs()
        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)

        return tr.rolling(window=periodo, min_periods=1).mean()

    def calcular_initial_balance(
        self,
        df_candles: pd.DataFrame,
        janela_barras: int = 30
    ) -> Dict[str, float]:
        """
        Calcula os níveis do Initial Balance (IB) da abertura da sessão (Fábio Valentim):
        - IB High: Máxima estabelecida nos primeiros N minutos.
        - IB Low: Mínima estabelecida nos primeiros N minutos.
        - IB PoC: Ponto de Controle (preço ponderado por volume) da abertura.
        - IB Range: Amplitude total da zona de abertura.
        """
        if df_candles.empty:
            return {"ib_high": 0.0, "ib_low": 0.0, "ib_poc": 0.0, "ib_range": 0.0}

        sub = df_candles.head(min(janela_barras, len(df_candles)))
        ib_high = float(sub["high"].max())
        ib_low = float(sub["low"].min())
        ib_range = ib_high - ib_low

        if "vol" in sub.columns and sub["vol"].sum() > 0:
            ib_poc = float((sub["poc"] * sub["vol"]).sum() / sub["vol"].sum())
        else:
            ib_poc = float((ib_high + ib_low) / 2.0)

        return {
            "ib_high": ib_high,
            "ib_low": ib_low,
            "ib_poc": round(ib_poc, 2),
            "ib_range": round(ib_range, 2)
        }

    def escanear_sinais(
        self,
        df_candles: pd.DataFrame,
        zonas_smc: Optional[List[ZonaInstitucional]] = None,
        exigir_confluencia_smc: bool = False,
        filtro_sessao_ativa: bool = False,
        filtro_ema_tendencia: bool = True
    ) -> List[SinalTrade]:
        """
        Varre os candles M1 avaliando os Modelos de Order Flow de Fábio Valentim:
        - Modelo 1 (Volume Profile / PoC Breakout): Rompimento aceito fora do Initial Balance com expansão de volume e suporte em PoC.
        - Modelo 2 (Delta Imbalance & Absorção): Rompimento ou reteste com agressão extrema de Delta (>= threshold) e absorção comprovada.
        """
        sinais = []
        n = len(df_candles)
        if n < 35:
            return sinais

        if zonas_smc is None:
            zonas_smc = self.smc_engine.detectar_order_blocks(df_candles)

        atr_series = self.calcular_atr(df_candles, self.preset.atr_period)
        ema_50 = df_candles["close"].ewm(span=50, adjust=False).mean()
        media_vol_serie = df_candles["vol"].rolling(window=20, min_periods=1).mean()

        # Calcula o Initial Balance (primeiros 30 minutos)
        ib_info = self.calcular_initial_balance(df_candles, janela_barras=30)
        ib_high = ib_info["ib_high"]
        ib_low = ib_info["ib_low"]
        ib_poc = ib_info["ib_poc"]

        for i in range(30, n):
            candle = df_candles.iloc[i]
            candle_ant = df_candles.iloc[i - 1]
            atr = atr_series.iloc[i] if not np.isnan(atr_series.iloc[i]) else 1.0
            ema_atual = ema_50.iloc[i]
            media_vol = media_vol_serie.iloc[i] if not np.isnan(media_vol_serie.iloc[i]) else 1.0

            # Filtro de Sessão Ativa de Liquidez (Londres e NY: 07:00 às 18:00 UTC)
            if filtro_sessao_ativa:
                hora_utc = candle["timestamp"].hour
                if hora_utc < 7 or hora_utc >= 18:
                    continue

            preco_fechamento = candle["close"]
            preco_minima = candle["low"]
            preco_maxima = candle["high"]
            delta_atual = candle["delta"]
            delta_mult = candle.get("delta_multiplier", 1.0)
            poc_atual = candle["poc"]
            volume_atual = candle["vol"]

            # Regra de Delta Extremo definida no preset
            delta_extremo_compra = (delta_mult >= self.preset.delta_threshold_multiplier) and (delta_atual > 0)
            delta_extremo_venda = (delta_mult >= self.preset.delta_threshold_multiplier) and (delta_atual < 0)

            # Filtro de Tendência Estrutural
            tendencia_alta = not filtro_ema_tendencia or (preco_fechamento > ema_atual)
            tendencia_baixa = not filtro_ema_tendencia or (preco_fechamento < ema_atual)

            # Verificação de confluência SMC (Order Block ou FVG ativo)
            em_suporte_smc = True
            em_resistencia_smc = True

            if exigir_confluencia_smc and zonas_smc:
                zonas_anteriores = [z for z in zonas_smc if z.indice_barra < i and not z.mitigado]
                em_suporte_smc = any(
                    z.nivel_inferior <= preco_minima <= z.nivel_superior or
                    z.nivel_inferior <= preco_fechamento <= z.nivel_superior
                    for z in zonas_anteriores if "BULLISH" in z.tipo
                )
                em_resistencia_smc = any(
                    z.nivel_inferior <= preco_maxima <= z.nivel_superior or
                    z.nivel_inferior <= preco_fechamento <= z.nivel_superior
                    for z in zonas_anteriores if "BEARISH" in z.tipo
                )

            # ============================================================
            # MODELO 2: ORDER FLOW DELTA IMBALANCE & ABSORÇÃO (Fábio Valentim)
            # ============================================================
            if delta_extremo_compra and (preco_fechamento >= poc_atual) and em_suporte_smc and tendencia_alta:
                dist_sl = max(candle["close"] - candle["low"], atr * self.preset.atr_sl_multiplier)
                sl = candle["close"] - dist_sl
                tp = candle["close"] + (dist_sl * self.preset.risk_reward_ratio)

                sinal = SinalTrade(
                    tipo="BUY",
                    timestamp=candle["timestamp"],
                    preco_entrada=preco_fechamento,
                    stop_loss=sl,
                    take_profit=tp,
                    razao_rr=self.preset.risk_reward_ratio,
                    delta=delta_atual,
                    delta_multiplier=delta_mult,
                    poc=poc_atual,
                    motivo=f"IVB Modelo 2: Delta Spike Comprador ({delta_mult:.1f}x) + Absorção Institucional",
                    modelo="IVB_2",
                    ib_high=ib_high,
                    ib_low=ib_low
                )
                sinais.append(sinal)
                continue

            elif delta_extremo_venda and (preco_fechamento <= poc_atual) and em_resistencia_smc and tendencia_baixa:
                dist_sl = max(candle["high"] - candle["close"], atr * self.preset.atr_sl_multiplier)
                sl = candle["close"] + dist_sl
                tp = candle["close"] - (dist_sl * self.preset.risk_reward_ratio)

                sinal = SinalTrade(
                    tipo="SELL",
                    timestamp=candle["timestamp"],
                    preco_entrada=preco_fechamento,
                    stop_loss=sl,
                    take_profit=tp,
                    razao_rr=self.preset.risk_reward_ratio,
                    delta=delta_atual,
                    delta_multiplier=delta_mult,
                    poc=poc_atual,
                    motivo=f"IVB Modelo 2: Delta Spike Vendedor ({delta_mult:.1f}x) + Absorção Institucional",
                    modelo="IVB_2",
                    ib_high=ib_high,
                    ib_low=ib_low
                )
                sinais.append(sinal)
                continue

            # ============================================================
            # MODELO 1: VOLUME PROFILE BREAKOUT & POC DEFENSE (Fábio Valentim)
            # ============================================================
            rompimento_alta_ib = (preco_fechamento > ib_high) and (candle_ant["close"] <= ib_high * 1.0005)
            expansao_volume = volume_atual >= (media_vol * 1.20)
            defesa_poc_alta = preco_fechamento >= poc_atual

            if rompimento_alta_ib and expansao_volume and defesa_poc_alta and tendencia_alta:
                dist_sl = max(candle["close"] - ib_high, atr * self.preset.atr_sl_multiplier)
                sl = candle["close"] - dist_sl
                tp = candle["close"] + (dist_sl * self.preset.risk_reward_ratio)

                sinal = SinalTrade(
                    tipo="BUY",
                    timestamp=candle["timestamp"],
                    preco_entrada=preco_fechamento,
                    stop_loss=sl,
                    take_profit=tp,
                    razao_rr=self.preset.risk_reward_ratio,
                    delta=delta_atual,
                    delta_multiplier=delta_mult,
                    poc=poc_atual,
                    motivo=f"IVB Modelo 1: Rompimento IB High ({ib_high:.2f}) + Expansão Volume + Defesa PoC",
                    modelo="IVB_1",
                    ib_high=ib_high,
                    ib_low=ib_low
                )
                sinais.append(sinal)
                continue

            rompimento_baixa_ib = (preco_fechamento < ib_low) and (candle_ant["close"] >= ib_low * 0.9995)
            defesa_poc_baixa = preco_fechamento <= poc_atual

            if rompimento_baixa_ib and expansao_volume and defesa_poc_baixa and tendencia_baixa:
                dist_sl = max(ib_low - candle["close"], atr * self.preset.atr_sl_multiplier)
                sl = candle["close"] + dist_sl
                tp = candle["close"] - (dist_sl * self.preset.risk_reward_ratio)

                sinal = SinalTrade(
                    tipo="SELL",
                    timestamp=candle["timestamp"],
                    preco_entrada=preco_fechamento,
                    stop_loss=sl,
                    take_profit=tp,
                    razao_rr=self.preset.risk_reward_ratio,
                    delta=delta_atual,
                    delta_multiplier=delta_mult,
                    poc=poc_atual,
                    motivo=f"IVB Modelo 1: Rompimento IB Low ({ib_low:.2f}) + Expansão Volume + Defesa PoC",
                    modelo="IVB_1",
                    ib_high=ib_high,
                    ib_low=ib_low
                )
                sinais.append(sinal)

        return sinais

    @staticmethod
    def simular_backtest_sinais(
        sinais: List[SinalTrade],
        df_candles: pd.DataFrame,
        usar_breakeven: bool = True,
        breakeven_gatilho_rr: float = 1.0,
        usar_trailing_stop: bool = False,
        trailing_atr_mult: float = 1.5
    ) -> Dict[str, Any]:
        """
        Executa a simulação candle a candle com gestão de risco dinâmica:
        - Break-Even: Ao atingir proporção de ganho (ex: 1.0 R:R), move o SL para o preço de entrada.
        - Trailing Stop: Condução de stop ancorada na volatilidade (ATR) para proteger lucros acumulados.
        - Métricas Institucionais: Win Rate, Profit Factor, Payoff Ratio e Max Drawdown.

        :param sinais: Lista de sinais gerados.
        :param df_candles: DataFrame de candles M1 completos.
        :param usar_breakeven: Ativa proteção no 0x0 ao atingir gatilho.
        :param breakeven_gatilho_rr: Proporção do risco inicial para ativar o break-even.
        :param usar_trailing_stop: Ativa trailing stop dinâmico.
        :param trailing_atr_mult: Multiplicador de ATR para o trailing stop.
        :return: Dicionário contendo estatísticas completas de performance institucional.
        """
        if not sinais:
            return {
                "total_trades": 0, "gains": 0, "losses": 0, "win_rate": 0.0,
                "pnl_pontos": 0.0, "profit_factor": 0.0, "payoff": 0.0, "max_drawdown": 0.0
            }

        resultados = []
        df_indexado = df_candles.set_index("timestamp").sort_index()
        timestamps_lista = list(df_indexado.index)

        for sinal in sinais:
            tempo_sinal = sinal.timestamp
            if tempo_sinal not in df_indexado.index:
                continue

            pos_idx = timestamps_lista.index(tempo_sinal)
            operacao_concluida = False
            lucro_pontos = 0.0
            resultado_status = "ABERTO"

            sl_dinamico = sinal.stop_loss
            dist_risco_inicial = abs(sinal.preco_entrada - sinal.stop_loss)
            alvo_breakeven = dist_risco_inicial * breakeven_gatilho_rr
            breakeven_ativado = False

            for j in range(pos_idx + 1, min(pos_idx + 120, len(timestamps_lista))):
                candle_futuro = df_indexado.iloc[j]
                high = candle_futuro["high"]
                low = candle_futuro["low"]
                close = candle_futuro["close"]

                if sinal.tipo == "BUY":
                    # 1. Verificação de ativação de Break-Even
                    if usar_breakeven and not breakeven_ativado and (high - sinal.preco_entrada >= alvo_breakeven):
                        sl_dinamico = max(sl_dinamico, sinal.preco_entrada + 0.05)
                        breakeven_ativado = True

                    # 2. Condução por Trailing Stop
                    if usar_trailing_stop and breakeven_ativado:
                        novo_trail = high - (dist_risco_inicial * 0.8)
                        sl_dinamico = max(sl_dinamico, novo_trail)

                    # 3. Verificação de saída
                    if low <= sl_dinamico:
                        lucro_pontos = sl_dinamico - sinal.preco_entrada
                        resultado_status = "GAIN" if lucro_pontos > 0 else "LOSS"
                        operacao_concluida = True
                        break
                    elif high >= sinal.take_profit:
                        lucro_pontos = sinal.take_profit - sinal.preco_entrada
                        resultado_status = "GAIN"
                        operacao_concluida = True
                        break

                elif sinal.tipo == "SELL":
                    # 1. Verificação de ativação de Break-Even
                    if usar_breakeven and not breakeven_ativado and (sinal.preco_entrada - low >= alvo_breakeven):
                        sl_dinamico = min(sl_dinamico, sinal.preco_entrada - 0.05)
                        breakeven_ativado = True

                    # 2. Condução por Trailing Stop
                    if usar_trailing_stop and breakeven_ativado:
                        novo_trail = low + (dist_risco_inicial * 0.8)
                        sl_dinamico = min(sl_dinamico, novo_trail)

                    # 3. Verificação de saída
                    if high >= sl_dinamico:
                        lucro_pontos = sinal.preco_entrada - sl_dinamico
                        resultado_status = "GAIN" if lucro_pontos > 0 else "LOSS"
                        operacao_concluida = True
                        break
                    elif low <= sinal.take_profit:
                        lucro_pontos = sinal.preco_entrada - sinal.take_profit
                        resultado_status = "GAIN"
                        operacao_concluida = True
                        break

            if operacao_concluida:
                resultados.append({
                    "timestamp": sinal.timestamp,
                    "tipo": sinal.tipo,
                    "status": resultado_status,
                    "pnl": lucro_pontos
                })

        if not resultados:
            return {
                "total_trades": 0, "win_rate": 0.0, "pnl_pontos": 0.0,
                "profit_factor": 0.0, "payoff": 0.0, "max_drawdown": 0.0
            }

        df_res = pd.DataFrame(resultados)
        total = len(df_res)
        gains = len(df_res[df_res["pnl"] > 0])
        losses = len(df_res[df_res["pnl"] <= 0])
        win_rate = (gains / total) * 100 if total > 0 else 0.0
        pnl_total = df_res["pnl"].sum()

        soma_gains = df_res[df_res["pnl"] > 0]["pnl"].sum()
        soma_losses = abs(df_res[df_res["pnl"] <= 0]["pnl"].sum())
        profit_factor = (soma_gains / soma_losses) if soma_losses > 0 else (99.0 if soma_gains > 0 else 0.0)

        media_gain = df_res[df_res["pnl"] > 0]["pnl"].mean() if gains > 0 else 0.0
        media_loss = abs(df_res[df_res["pnl"] <= 0]["pnl"].mean()) if losses > 0 else 1.0
        payoff = (media_gain / media_loss) if media_loss > 0 else 0.0

        # Cálculo de Max Drawdown da curva acumulada
        pnl_acumulado = df_res["pnl"].cumsum()
        pico_acumulado = pnl_acumulado.cummax()
        drawdown_serie = pico_acumulado - pnl_acumulado
        max_drawdown = drawdown_serie.max() if not drawdown_serie.empty else 0.0

        return {
            "total_trades": total,
            "gains": gains,
            "losses": losses,
            "win_rate": win_rate,
            "pnl_pontos": pnl_total,
            "profit_factor": profit_factor,
            "payoff": payoff,
            "max_drawdown": max_drawdown,
            "detalhes": df_res
        }
