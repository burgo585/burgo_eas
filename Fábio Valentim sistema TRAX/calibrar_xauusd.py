"""
Módulo de Calibração Quantitativa e Otimização Institucional de Parâmetros: XAUUSD.
Processa o histórico de ticks reais, extrai a microestrutura M1,
executa Grid Search vetorizado ultra-rápido e calibra os limiares de Delta, Zonas SMC,
Break-Even, Trailing Stop e Filtros de Sessão para maximizar o Profit Factor e Win Rate.
"""

from pathlib import Path
import json
import time
import numpy as np
import pandas as pd

from config.settings import carregar_presets
from src.data.mt5_feed import MT5TickFeed
from src.analytics.order_flow import OrderFlowEngine
from src.analytics.smc_zones import SMCZonesEngine
from src.execution.signals import SinalTrade
from src.utils.logger import obter_logger

logger = obter_logger("CalibradorXAUUSD")


def carregar_ou_processar_base_m1(caminho_csv: Path, limite_ticks: int = 1_000_000) -> pd.DataFrame:
    """Carrega a base M1 em cache Parquet ou processa a partir do CSV bruto de ticks."""
    caminho_parquet_cache = Path("data/XAUUSD_M1_calibracao.parquet")
    caminho_parquet_cache.parent.mkdir(parents=True, exist_ok=True)

    if caminho_parquet_cache.exists():
        logger.info(f"Carregando base M1 do cache Parquet: {caminho_parquet_cache}")
        return pd.read_parquet(caminho_parquet_cache)

    logger.info(f"Processando {limite_ticks:,} ticks reais do CSV para M1...")
    df_ticks = MT5TickFeed.processar_csv_ticks_mt5(
        caminho_csv=caminho_csv,
        chunksize=100_000,
        limite_linhas=limite_ticks
    )

    order_flow_engine = OrderFlowEngine(tick_size=0.05)
    df_m1 = order_flow_engine.agregar_ticks_em_candles_m1(df_ticks)
    df_m1.to_parquet(caminho_parquet_cache, engine="pyarrow", compression="snappy", index=False)
    return df_m1


def precomputar_mascaras_smc(df_m1: pd.DataFrame, todas_zonas: list) -> tuple:
    """Pré-computa vetorizado se cada candle M1 toca suporte ou resistência SMC ativo."""
    n = len(df_m1)
    lows = df_m1["low"].values
    highs = df_m1["high"].values

    em_suporte = np.zeros(n, dtype=bool)
    em_resistencia = np.zeros(n, dtype=bool)

    for z in todas_zonas:
        idx_ini = z.indice_barra + 1
        if idx_ini >= n:
            continue
        # Limita até 300 barras após a criação para respeitar a relevância da zona
        idx_fim = min(idx_ini + 300, n)
        faixa_low = lows[idx_ini:idx_fim]
        faixa_high = highs[idx_ini:idx_fim]

        tocou = (faixa_low <= z.nivel_superior) & (faixa_high >= z.nivel_inferior)

        if "BULLISH" in z.tipo:
            em_suporte[idx_ini:idx_fim] |= tocou
        elif "BEARISH" in z.tipo:
            em_resistencia[idx_ini:idx_fim] |= tocou

    return em_suporte, em_resistencia


def simular_rapido_trades(
    sinais_indices: np.ndarray,
    sinais_tipos: np.ndarray,
    sinais_entradas: np.ndarray,
    sinais_sl: np.ndarray,
    sinais_tp: np.ndarray,
    highs: np.ndarray,
    lows: np.ndarray,
    usar_breakeven: bool = True,
    breakeven_rr: float = 0.8
) -> dict:
    """Simulador vetorizado de alta velocidade para os trades."""
    if len(sinais_indices) == 0:
        return {"total": 0, "win_rate": 0.0, "pnl": 0.0, "profit_factor": 0.0, "max_dd": 0.0}

    n_candles = len(highs)
    pnls = []

    for idx, tipo, entry, sl, tp in zip(sinais_indices, sinais_tipos, sinais_entradas, sinais_sl, sinais_tp):
        dist_risco = abs(entry - sl)
        alvo_be = dist_risco * breakeven_rr
        be_ativado = False
        sl_dinamico = sl

        lim_fim = min(idx + 120, n_candles)
        pnl_trade = 0.0
        finalizado = False

        if tipo == 1:  # BUY
            for j in range(idx + 1, lim_fim):
                h = highs[j]
                l = lows[j]
                if usar_breakeven and not be_ativado and (h - entry >= alvo_be):
                    sl_dinamico = entry + 0.05
                    be_ativado = True
                if l <= sl_dinamico:
                    pnl_trade = sl_dinamico - entry
                    finalizado = True
                    break
                elif h >= tp:
                    pnl_trade = tp - entry
                    finalizado = True
                    break
        else:  # SELL
            for j in range(idx + 1, lim_fim):
                h = highs[j]
                l = lows[j]
                if usar_breakeven and not be_ativado and (entry - l >= alvo_be):
                    sl_dinamico = entry - 0.05
                    be_ativado = True
                if h >= sl_dinamico:
                    pnl_trade = entry - sl_dinamico
                    finalizado = True
                    break
                elif l <= tp:
                    pnl_trade = entry - tp
                    finalizado = True
                    break

        if finalizado:
            pnls.append(pnl_trade)

    if not pnls:
        return {"total": 0, "win_rate": 0.0, "pnl": 0.0, "profit_factor": 0.0, "max_dd": 0.0}

    pnls_arr = np.array(pnls)
    total = len(pnls_arr)
    gains = np.sum(pnls_arr > 0)
    win_rate = (gains / total) * 100.0
    pnl_total = np.sum(pnls_arr)

    soma_g = np.sum(pnls_arr[pnls_arr > 0])
    soma_l = np.abs(np.sum(pnls_arr[pnls_arr <= 0]))
    profit_factor = (soma_g / soma_l) if soma_l > 0 else (99.0 if soma_g > 0 else 0.0)

    # Max Drawdown
    cum_pnl = np.cumsum(pnls_arr)
    peaks = np.maximum.accumulate(cum_pnl)
    drawdowns = peaks - cum_pnl
    max_dd = np.max(drawdowns) if len(drawdowns) > 0 else 0.0

    return {
        "total": total,
        "gains": int(gains),
        "losses": int(total - gains),
        "win_rate": win_rate,
        "pnl": pnl_total,
        "profit_factor": profit_factor,
        "max_dd": max_dd
    }


def executar_calibracao():
    caminho_csv = Path("XAUUSD-STDc_202506161213_202610022356ticks.csv")
    df_m1 = carregar_ou_processar_base_m1(caminho_csv)
    n = len(df_m1)

    logger.info(f"Base de calibração carregada: {n:,} candles M1.")

    # 1. Pré-computa Zonas SMC
    logger.info("Detectando Zonas Institucionais (Order Blocks e FVGs)...")
    smc_engine = SMCZonesEngine(fvg_min_tamanho=0.25, delta_impulsao_multiplicador=2.0)
    order_blocks = smc_engine.detectar_order_blocks(df_m1)
    fvgs = smc_engine.detectar_fvg(df_m1)
    todas_zonas = order_blocks + fvgs
    logger.info(f"Zonas Mapeadas: {len(order_blocks)} Order Blocks | {len(fvgs)} FVGs")

    em_suporte, em_resistencia = precomputar_mascaras_smc(df_m1, todas_zonas)

    # 2. Pré-computa Indicadores Técnicos
    closes = df_m1["close"].values
    highs = df_m1["high"].values
    lows = df_m1["low"].values
    deltas = df_m1["delta"].values
    delta_mults = df_m1.get("delta_multiplier", pd.Series(np.ones(n))).values
    pocs = df_m1["poc"].values
    horas = pd.to_datetime(df_m1["timestamp"]).dt.hour.values

    # ATR 14
    tr = np.maximum(highs - lows, np.maximum(np.abs(highs - np.roll(closes, 1)), np.abs(lows - np.roll(closes, 1))))
    atr = pd.Series(tr).rolling(14, min_periods=1).mean().values

    # EMA 50
    ema_50 = pd.Series(closes).ewm(span=50, adjust=False).mean().values

    logger.info("Iniciando Grid Search institucional vetorizado...")
    tempo_ini = time.time()

    grade_delta_thresh = [1.8, 2.2, 2.5, 3.0]
    grade_atr_sl = [1.0, 1.5, 2.0]
    grade_rr = [1.5, 2.0, 2.5]
    grade_breakeven = [True, False]
    grade_sessao = [True, False]
    grade_ema = [True, False]

    melhores_parametros = None
    melhor_resultado = None
    maior_score = -999999.0
    resultados_grade = []

    for delta_thresh in grade_delta_thresh:
        for atr_sl in grade_atr_sl:
            for rr in grade_rr:
                for sessao in grade_sessao:
                    for ema in grade_ema:
                        # Vetorização de condições de disparo
                        cond_sessao = (horas >= 7) & (horas < 18) if sessao else np.ones(n, dtype=bool)

                        # Condições BUY
                        cond_buy = (
                            (delta_mults >= delta_thresh) &
                            (deltas > 0) &
                            (closes >= pocs) &
                            em_suporte &
                            cond_sessao
                        )
                        if ema:
                            cond_buy &= (closes > ema_50)

                        # Condições SELL
                        cond_sell = (
                            (delta_mults >= delta_thresh) &
                            (deltas < 0) &
                            (closes <= pocs) &
                            em_resistencia &
                            cond_sessao
                        )
                        if ema:
                            cond_sell &= (closes < ema_50)

                        # Não gera sinais nos primeiros 50 candles
                        cond_buy[:50] = False
                        cond_sell[:50] = False

                        idx_buys = np.where(cond_buy)[0]
                        idx_sells = np.where(cond_sell)[0]

                        # Consolida sinais
                        todos_idx = np.concatenate([idx_buys, idx_sells])
                        tipos = np.concatenate([np.ones(len(idx_buys), dtype=int), -np.ones(len(idx_sells), dtype=int)])
                        ordem = np.argsort(todos_idx)
                        todos_idx = todos_idx[ordem]
                        tipos = tipos[ordem]

                        if len(todos_idx) < 5:
                            continue

                        entradas = closes[todos_idx]
                        dist_sl = np.maximum(
                            np.where(tipos == 1, closes[todos_idx] - lows[todos_idx], highs[todos_idx] - closes[todos_idx]),
                            atr[todos_idx] * atr_sl
                        )
                        sls = np.where(tipos == 1, entradas - dist_sl, entradas + dist_sl)
                        tps = np.where(tipos == 1, entradas + (dist_sl * rr), entradas - (dist_sl * rr))

                        for be in grade_breakeven:
                            res = simular_rapido_trades(
                                sinais_indices=todos_idx,
                                sinais_tipos=tipos,
                                sinais_entradas=entradas,
                                sinais_sl=sls,
                                sinais_tp=tps,
                                highs=highs,
                                lows=lows,
                                usar_breakeven=be,
                                breakeven_rr=0.8
                            )

                            if res["total"] < 5:
                                continue

                            score = (res["pnl"] * 3.0) + (res["win_rate"] * 1.5) + (res["profit_factor"] * 25.0) - (res["max_dd"] * 1.2)

                            registro = {
                                "delta_mult": delta_thresh,
                                "atr_sl": atr_sl,
                                "rr": rr,
                                "filtro_sessao": sessao,
                                "filtro_ema": ema,
                                "breakeven": be,
                                "trades": res["total"],
                                "win_rate": res["win_rate"],
                                "pnl": res["pnl"],
                                "profit_factor": res["profit_factor"],
                                "drawdown": res["max_dd"],
                                "score": score
                            }
                            resultados_grade.append(registro)

                            if score > maior_score and res["pnl"] > 0:
                                maior_score = score
                                melhor_resultado = res
                                melhores_parametros = registro

    tempo_total = time.time() - tempo_ini
    logger.info(f"Grid Search finalizado em {tempo_total:.2f}s ({len(resultados_grade)} combinações avaliadas).")

    df_grade = pd.DataFrame(resultados_grade).sort_values("score", ascending=False)

    if melhores_parametros is not None:
        logger.info("=================================================================")
        logger.info("CALIBRAÇÃO QUANTITATIVA DO XAUUSD CONCLUÍDA COM SUCESSO!")
        logger.info("=================================================================")
        logger.info("CONFIGURAÇÃO ÓTIMA INSTITUCIONAL:")
        logger.info(f"  -> Delta Multiplier: {melhores_parametros['delta_mult']}x")
        logger.info(f"  -> ATR Stop Loss: {melhores_parametros['atr_sl']}x ATR")
        logger.info(f"  -> Risco:Retorno (R:R): 1 : {melhores_parametros['rr']}")
        logger.info(f"  -> Filtro de Sessão (07:00-18:00 UTC): {melhores_parametros['filtro_sessao']}")
        logger.info(f"  -> Alinhamento EMA 50: {melhores_parametros['filtro_ema']}")
        logger.info(f"  -> Proteção Break-Even: {melhores_parametros['breakeven']}")
        logger.info("-----------------------------------------------------------------")
        logger.info("RESULTADO NA BASE REAL DO XAUUSD:")
        logger.info(f"  -> Total de Trades: {melhores_parametros['trades']}")
        logger.info(f"  -> Win Rate: {melhores_parametros['win_rate']:.2f}%")
        logger.info(f"  -> Profit Factor: {melhores_parametros['profit_factor']:.2f}")
        logger.info(f"  -> PnL Acumulado: +{melhores_parametros['pnl']:.2f} pts")
        logger.info(f"  -> Max Drawdown: {melhores_parametros['drawdown']:.2f} pts")
        logger.info("=================================================================")

        # Atualiza presets.json
        caminho_presets = Path("config/presets.json")
        with open(caminho_presets, "r", encoding="utf-8") as f:
            dados_presets = json.load(f)

        dados_presets["assets"]["XAUUSD"]["delta_threshold_multiplier"] = melhores_parametros["delta_mult"]
        dados_presets["assets"]["XAUUSD"]["atr_sl_multiplier"] = melhores_parametros["atr_sl"]
        dados_presets["assets"]["XAUUSD"]["risk_reward_ratio"] = melhores_parametros["rr"]
        dados_presets["assets"]["XAUUSD"]["session_filter_active"] = melhores_parametros["filtro_sessao"]
        dados_presets["assets"]["XAUUSD"]["trend_ema_filter_active"] = melhores_parametros["filtro_ema"]
        dados_presets["assets"]["XAUUSD"]["breakeven_active"] = melhores_parametros["breakeven"]

        with open(caminho_presets, "w", encoding="utf-8") as f:
            json.dump(dados_presets, f, indent=2, ensure_ascii=False)

        logger.info("[OK] presets.json atualizado com os parâmetros calibrados!")
    else:
        logger.warning("Top 5 melhores configurações encontradas na grade:")
        print(df_grade.head(5))


if __name__ == "__main__":
    executar_calibracao()
