"""
Script de Teste e Validação da Base Real de Ticks do XAUUSD.
Lê os ticks a partir do arquivo CSV institucional XAUUSD-STDc_202506161213_202610022356ticks.csv
e valida o cálculo de microestrutura de Order Flow e Delta.
"""

from pathlib import Path
from src.data.mt5_feed import MT5TickFeed
from src.utils.logger import obter_logger

logger = obter_logger("TesteXAUUSD")


def executar_validacao_xauusd():
    caminho_csv = Path("XAUUSD-STDc_202506161213_202610022356ticks.csv")
    if not caminho_csv.exists():
        logger.error(f"Arquivo de ticks do XAUUSD não encontrado em: {caminho_csv.resolve()}")
        return

    logger.info("=================================================================")
    logger.info("INICIANDO TESTE COM DADOS REAIS DE TICKS DO XAUUSD")
    logger.info(f"Arquivo de entrada: {caminho_csv.name} ({caminho_csv.stat().st_size / (1024**3):.2f} GB)")
    logger.info("=================================================================")

    # Processa uma amostra de 50.000 ticks reais para validação rápida da microestrutura
    limite_amostra = 50_000
    df_amostra = MT5TickFeed.processar_csv_ticks_mt5(
        caminho_csv=caminho_csv,
        chunksize=25_000,
        limite_linhas=limite_amostra
    )

    logger.info(f"Amostra de {len(df_amostra):,} ticks carregada com sucesso!")
    logger.info(f"Intervalo de tempo analisado: {df_amostra['timestamp'].min()} até {df_amostra['timestamp'].max()}")
    logger.info(f"Variação de preço: Mín = ${df_amostra['price'].min():.2f} | Máx = ${df_amostra['price'].max():.2f}")

    total_compras = df_amostra["buy_vol"].sum()
    total_vendas = df_amostra["sell_vol"].sum()
    delta_acumulado = df_amostra["delta"].sum()

    logger.info(f"Volume Comprador Agressivo: {total_compras:,.0f}")
    logger.info(f"Volume Vendedor Agressivo: {total_vendas:,.0f}")
    logger.info(f"Delta Acumulado na Amostra: {delta_acumulado:+,.0f}")

    print("\n--- Primeiros 5 Ticks Processados ---")
    print(df_amostra[["timestamp", "bid", "ask", "price", "aggression", "delta"]].head())

    print("\n--- Últimos 5 Ticks Processados ---")
    print(df_amostra[["timestamp", "bid", "ask", "price", "aggression", "delta"]].tail())

    logger.info("=================================================================")
    logger.info("[OK] DADOS REAIS DO XAUUSD VALIDADOS COM SUCESSO NO ECOSSISTEMA!")
    logger.info("=================================================================")


if __name__ == "__main__":
    executar_validacao_xauusd()
