"""
Script de Automação e Backtest do Motor de Order Flow e SMC nos Ticks Reais do XAUUSD.
Processa o histórico massivo de ticks, agrega em barras M1, calcula Delta e PoC,
identifica Order Blocks institucionais e executa a máquina de sinais quantitativos.
"""

from pathlib import Path
import pandas as pd

from config.settings import carregar_presets
from src.data.mt5_feed import MT5TickFeed
from src.analytics.order_flow import OrderFlowEngine
from src.analytics.smc_zones import SMCZonesEngine
from src.execution.signals import MotorSinaisQuantitativo
from src.utils.logger import obter_logger

logger = obter_logger("AutomacaoXAUUSD")


def executar_automacao_completa_xauusd(limite_ticks: int = 250_000):
    """
    Executa o fluxo fim-a-fim da automação nos ticks reais de Ouro (XAUUSD).
    """
    caminho_csv = Path("XAUUSD-STDc_202506161213_202610022356ticks.csv")
    if not caminho_csv.exists():
        logger.error(f"Arquivo de ticks do XAUUSD não encontrado: {caminho_csv}")
        return

    config = carregar_presets()
    preset_xau = config.assets["XAUUSD"]

    logger.info("=================================================================")
    logger.info("INICIANDO AUTOMAÇÃO INSTITUCIONAL DE ORDER FLOW: XAUUSD")
    logger.info(f"Base de ticks: {caminho_csv.name} | Amostra: {limite_ticks:,} ticks")
    logger.info(f"Parâmetros: SL ATR Mult = {preset_xau.atr_sl_multiplier}x | R:R = {preset_xau.risk_reward_ratio}x | Delta Thresh = {preset_xau.delta_threshold_multiplier}x")
    logger.info("=================================================================")

    # ETAPA 1: Ingestão e Processamento dos Ticks Reais
    logger.info("--- [ETAPA 1/4] INGESTÃO E CLASSIFICAÇÃO DE AGRESSÃO DOS TICKS ---")
    df_ticks = MT5TickFeed.processar_csv_ticks_mt5(
        caminho_csv=caminho_csv,
        chunksize=50_000,
        limite_linhas=limite_ticks
    )
    logger.info(f"[OK] {len(df_ticks):,} ticks processados com sucesso.")

    # ETAPA 2: Motor Analítico de Order Flow (Barras M1, Delta, CVD e PoC)
    logger.info("--- [ETAPA 2/4] MOTOR DE ORDER FLOW: AGREGAÇÃO M1, DELTA E POC ---")
    order_flow_engine = OrderFlowEngine(tick_size=0.05)
    df_m1 = order_flow_engine.agregar_ticks_em_candles_m1(df_ticks)
    logger.info(f"[OK] {len(df_m1):,} candles M1 estruturados com Volume Profile e PoC.")

    # Amostra dos 5 primeiros candles M1
    print("\n--- Amostra de Candles M1 com Order Flow (Delta & PoC) ---")
    colunas_vis = ["timestamp", "open", "high", "low", "close", "vol", "delta", "cum_delta", "poc"]
    print(df_m1[colunas_vis].head())

    # ETAPA 3: Zonas SMC (Order Blocks e Fair Value Gaps)
    logger.info("--- [ETAPA 3/4] MOTOR SMC: IDENTIFICAÇÃO DE ORDER BLOCKS E FVG ---")
    smc_engine = SMCZonesEngine(
        fvg_min_tamanho=0.30,
        delta_impulsao_multiplicador=preset_xau.delta_threshold_multiplier
    )
    order_blocks = smc_engine.detectar_order_blocks(df_m1)
    fvgs = smc_engine.detectar_fvg(df_m1)
    order_blocks = smc_engine.atualizar_mitigacao_zonas(order_blocks, df_m1)

    logger.info(f"[OK] Zonas Institucionais Mapeadas: {len(order_blocks)} Order Blocks | {len(fvgs)} Fair Value Gaps.")
    obs_bullish = [ob for ob in order_blocks if ob.tipo == "BULLISH_OB"]
    obs_bearish = [ob for ob in order_blocks if ob.tipo == "BEARISH_OB"]
    logger.info(f"     -> Bullish Order Blocks (Suportes Institucionais): {len(obs_bullish)}")
    logger.info(f"     -> Bearish Order Blocks (Resistências Institucionais): {len(obs_bearish)}")

    # ETAPA 4: Máquina de Sinais e Simulação de Backtest
    logger.info("--- [ETAPA 4/4] MÁQUINA DE SINAIS E SIMULAÇÃO DE TRADES ---")
    todas_zonas = order_blocks + fvgs
    motor_sinais = MotorSinaisQuantitativo(preset=preset_xau)

    # 4.1 Cenário A: Sinais de Order Flow Puro (Delta Spikes + Rompimento PoC)
    sinais_puros = motor_sinais.escanear_sinais(df_m1, zonas_smc=todas_zonas, exigir_confluencia_smc=False)
    res_puro = motor_sinais.simular_backtest_sinais(sinais_puros, df_m1)

    # 4.2 Cenário B: Sinais de Confluência Institucional da Imagem 1 (Delta + PoC + Faixas SMC)
    sinais_confluencia = motor_sinais.escanear_sinais(df_m1, zonas_smc=todas_zonas, exigir_confluencia_smc=True)
    res_confluencia = motor_sinais.simular_backtest_sinais(sinais_confluencia, df_m1)

    logger.info("=================================================================")
    logger.info("RELATÓRIO INSTITUCIONAL QUANTITATIVO: COMPARATIVO DE PERFORMANCE")
    logger.info("=================================================================")
    logger.info(f"[CENÁRIO A - FLUXO PURO] Trades: {res_puro['total_trades']} | Gains: {res_puro['gains']} | Losses: {res_puro['losses']} | Win Rate: {res_puro['win_rate']:.2f}% | PnL: {res_puro['pnl_pontos']:+,.2f} pts")
    logger.info(f"[CENÁRIO B - FLUXO + SMC (IMAGEM 1)] Trades: {res_confluencia['total_trades']} | Gains: {res_confluencia['gains']} | Losses: {res_confluencia['losses']} | Win Rate: {res_confluencia['win_rate']:.2f}% | PnL: {res_confluencia['pnl_pontos']:+,.2f} pts")
    logger.info("=================================================================")

    if sinais_confluencia:
        print("\n--- Sinais Validados pela Confluência SMC ---")
        df_sc = pd.DataFrame([s.to_dict() for s in sinais_confluencia])
        print(df_sc[["timestamp", "tipo", "preco_entrada", "stop_loss", "take_profit", "delta_mult", "motivo"]])


if __name__ == "__main__":
    executar_automacao_completa_xauusd(limite_ticks=250_000)
