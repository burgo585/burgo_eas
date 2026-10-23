"""
Script de Teste e Validação da CAIXA 1 (Ingestão de Dados, Data Fusion e Presets).
Executa testes unitários e de integração em todos os componentes fundacionais da Caixa 1.
"""

import datetime
from pathlib import Path
import numpy as np
import pandas as pd

from config.settings import carregar_presets
from src.data.mt5_feed import MT5TickFeed
from src.data.binance_feed import BinanceFeed
from src.data.macro_feed import MacroDataFeed
from src.data.data_synchronizer import DataSynchronizer
from src.utils.logger import obter_logger

logger = obter_logger("TesteCaixa1")


def testar_presets():
    """Valida a leitura e integridade das regras dos presets (MNQ, XAUUSD, BTCUSD)."""
    logger.info("--- [1/6] TESTANDO CARREGAMENTO E VALIDAÇÃO DOS PRESETS ---")
    config = carregar_presets()

    # Validação do MNQ
    assert "MNQ" in config.assets, "MNQ ausente nos presets!"
    mnq = config.assets["MNQ"]
    assert mnq.moc_loc_active is True, "MNQ deve possuir moc_loc_active = True!"
    assert mnq.moc_loc_window_start == "15:50:00", "Início da janela MOC/LOC incorreto!"
    assert mnq.moc_loc_window_end == "15:59:50", "Fim da janela MOC/LOC incorreto!"
    assert mnq.kill_switch_time == "15:59:50", "Horário do Kill-switch incorreto!"
    assert mnq.delta_threshold_multiplier == 3.0, "Multiplicador de Delta incorreto!"

    # Validação do XAUUSD
    assert "XAUUSD" in config.assets, "XAUUSD ausente nos presets!"
    xau = config.assets["XAUUSD"]
    assert xau.moc_loc_active is False, "XAUUSD deve possuir moc_loc_active = False!"

    # Validação do BTCUSD
    assert "BTCUSD" in config.assets, "BTCUSD ausente nos presets!"
    btc = config.assets["BTCUSD"]
    assert btc.moc_loc_active is False, "BTCUSD deve possuir moc_loc_active = False!"

    logger.info("[OK] Presets validados com sucesso para MNQ, XAUUSD e BTCUSD.")


def testar_classificacao_agressao_mt5():
    """Valida a classificação institucional de agressão (Order Flow) e cálculo de Delta."""
    logger.info("--- [2/6] TESTANDO CLASSIFICAÇÃO DE AGRESSÃO E TICKS MT5 ---")

    feed = MT5TickFeed()

    # Cenário 1: Flag explícita TICK_FLAG_BUY (32)
    lado1 = feed.classificar_agressao(flag=32, price=20500.5, bid=20500.25, ask=20500.5)
    assert lado1 == "BUY", f"Esperado BUY, recebido {lado1}"

    # Cenário 2: Flag explícita TICK_FLAG_SELL (64)
    lado2 = feed.classificar_agressao(flag=64, price=20500.25, bid=20500.25, ask=20500.5)
    assert lado2 == "SELL", f"Esperado SELL, recebido {lado2}"

    # Cenário 3: Sem flag explícita (CFD/Forex), executado no Ask
    lado3 = feed.classificar_agressao(flag=0, price=20500.5, bid=20500.25, ask=20500.5)
    assert lado3 == "BUY", f"Esperado BUY, recebido {lado3}"

    # Cenário 4: Sem flag explícita (CFD/Forex), executado no Bid
    lado4 = feed.classificar_agressao(flag=0, price=20500.25, bid=20500.25, ask=20500.5)
    assert lado4 == "SELL", f"Esperado SELL, recebido {lado4}"

    logger.info("[OK] Algoritmo de agressão de microestrutura validado.")


def testar_persistencia_parquet():
    """Valida exportação e importação de ticks para backtesting em Parquet."""
    logger.info("--- [3/6] TESTANDO PERSISTÊNCIA PARQUET PARA BACKTESTING ---")

    agora = datetime.datetime.now(datetime.timezone.utc)
    dados_mock = {
        "timestamp": [agora + datetime.timedelta(seconds=i) for i in range(5)],
        "time_msc": [int((agora + datetime.timedelta(seconds=i)).timestamp() * 1000) for i in range(5)],
        "bid": [20000.0, 20000.25, 20000.25, 20000.5, 20000.5],
        "ask": [20000.25, 20000.5, 20000.5, 20000.75, 20000.75],
        "last": [20000.25, 20000.25, 20000.5, 20000.75, 20000.5],
        "vol": [10.0, 5.0, 15.0, 8.0, 12.0],
        "flags": [32, 64, 32, 32, 64],
        "aggression": ["BUY", "SELL", "BUY", "BUY", "SELL"],
        "buy_vol": [10.0, 0.0, 15.0, 8.0, 0.0],
        "sell_vol": [0.0, 5.0, 0.0, 0.0, 12.0],
        "delta": [10.0, -5.0, 15.0, 8.0, -12.0]
    }
    df_mock = pd.DataFrame(dados_mock)

    caminho_teste = Path("data/teste_ticks_mnq.parquet")
    MT5TickFeed.salvar_para_parquet(df_mock, caminho_teste)
    assert caminho_teste.exists(), "Arquivo parquet não foi gerado!"

    df_carregado = MT5TickFeed.carregar_dados_backtest(caminho_teste)
    assert len(df_carregado) == 5, "Tamanho dos dados carregados diverge!"
    assert "delta" in df_carregado.columns, "Coluna delta não encontrada!"

    # Limpeza
    if caminho_teste.exists():
        caminho_teste.unlink()

    logger.info("[OK] Motor de gravação e leitura de Parquet validado com sucesso.")


def testar_binance_imbalance():
    """Valida a fórmula e snapshot do Order Book L2 Imbalance da Binance."""
    logger.info("--- [4/6] TESTANDO CÁLCULO DE ORDER BOOK L2 IMBALANCE DA BINANCE ---")

    feed_binance = BinanceFeed()
    bids_mock = [["90000.0", "15.5"], ["89990.0", "10.0"]]  # Total Bids = 25.5
    asks_mock = [["90010.0", "5.5"], ["90020.0", "4.0"]]    # Total Asks = 9.5

    imbalance, total_bid, total_ask, best_bid, best_ask = feed_binance.calcular_imbalance(bids_mock, asks_mock)

    # Imbalance = (25.5 - 9.5) / (25.5 + 9.5) = 16.0 / 35.0 ~= +0.4571 (Forte pressão compradora)
    esperado = (25.5 - 9.5) / 35.0
    assert abs(imbalance - esperado) < 1e-4, f"Imbalance calculado incorreto: {imbalance}"
    assert best_bid == 90000.0, "Best bid incorreto"
    assert best_ask == 90010.0, "Best ask incorreto"

    snapshot = feed_binance.obter_snapshot_rest_sincrono()
    assert "l2_imbalance" in snapshot, "Snapshot L2 incompleto!"

    logger.info(f"[OK] Imbalance L2 validado com precisão: {imbalance:+.4f} (Pressão compradora confirmada).")


def testar_macro_feed():
    """Valida o módulo macroeconômico e classificação do regime de risco."""
    logger.info("--- [5/6] TESTANDO INGESTÃO MACROECONÔMICA E REGIME DE RISCO ---")

    macro = MacroDataFeed()
    snapshot = macro.obter_snapshot_macro_atual()

    assert "vix" in snapshot, "VIX ausente no snapshot macro!"
    assert "dxy" in snapshot, "DXY ausente no snapshot macro!"
    assert "us10y" in snapshot, "US10Y ausente no snapshot macro!"
    assert "risk_regime" in snapshot, "Regime de risco ausente!"

    logger.info(f"[OK] Estado macro capturado: VIX={snapshot['vix']}, DXY={snapshot['dxy']}, Regime={snapshot['risk_regime']}")


def testar_data_synchronizer():
    """Valida o merge_asof de alta performance e fusão de dados heterogêneos."""
    logger.info("--- [6/6] TESTANDO DATA FUSION E MERGE_ASOF TEMPORAL ---")

    sincronizador = DataSynchronizer(tolerancia_tempo_segundos=300)

    # Base primária (Ticks / Candles MT5)
    t0 = datetime.datetime(2026, 10, 5, 15, 50, 0, tzinfo=datetime.timezone.utc)
    df_mt5 = pd.DataFrame({
        "timestamp": [t0 + datetime.timedelta(seconds=i * 60) for i in range(3)],
        "open": [20100.0, 20110.0, 20120.0],
        "close": [20110.0, 20120.0, 20130.0],
        "delta": [150.0, 320.0, 480.0]
    })

    # Dados assíncronos da Binance gerados segundos antes
    df_binance = pd.DataFrame({
        "timestamp": [
            t0 - datetime.timedelta(seconds=15),
            t0 + datetime.timedelta(seconds=45),
            t0 + datetime.timedelta(seconds=105)
        ],
        "l2_imbalance": [0.35, 0.42, 0.50],
        "liq_long_vol": [12000.0, 0.0, 0.0],
        "liq_short_vol": [0.0, 50000.0, 85000.0]
    })

    # Dados macroeconômicos
    df_macro = pd.DataFrame({
        "timestamp": [
            t0 - datetime.timedelta(seconds=60),
            t0 + datetime.timedelta(seconds=60)
        ],
        "macro_vix": [16.5, 16.2],
        "macro_dxy": [103.8, 103.7]
    })

    # Executa o merge_asof backward
    df_sincronizado = sincronizador.sincronizar_fluxos(
        df_primario=df_mt5,
        df_binance=df_binance,
        df_macro=df_macro
    )

    assert len(df_sincronizado) == 3, "Tamanho divergente após merge_asof!"
    assert "l2_imbalance" in df_sincronizado.columns, "Coluna l2_imbalance não fundida!"
    assert "macro_vix" in df_sincronizado.columns, "Coluna macro_vix não fundida!"

    # O primeiro registro no tempo t0 deve ter capturado o l2_imbalance de t0 - 15s (0.35)
    assert df_sincronizado["l2_imbalance"].iloc[0] == 0.35, "Falha no alinhamento temporal backward do merge_asof!"

    # Teste de fusão in-memory em tempo real
    tick_ao_vivo = {"symbol": "MNQ", "price": 20135.0, "delta": 510.0}
    snapshot_b = {"l2_imbalance": 0.55, "liq_long_vol": 0.0, "liq_short_vol": 90000.0}
    snapshot_m = {"vix": 16.0, "dxy": 103.5, "us10y": 4.15, "risk_regime": "RISK_ON", "yield_spread_10y2y": 0.05}

    registro_live = sincronizador.fundir_snapshot_tempo_real(tick_ao_vivo, snapshot_b, snapshot_m)
    assert registro_live["binance_l2_imbalance"] == 0.55
    assert registro_live["macro_risk_regime"] == "RISK_ON"

    logger.info("[OK] Sincronizador merge_asof e fusão in-memory validados com perfeição (Zero Lookahead Bias).")


if __name__ == "__main__":
    logger.info("=================================================================")
    logger.info("INICIANDO BATERIA DE TESTES DE INTEGRAÇÃO - CAIXA 1")
    logger.info("=================================================================")
    testar_presets()
    testar_classificacao_agressao_mt5()
    testar_persistencia_parquet()
    testar_binance_imbalance()
    testar_macro_feed()
    testar_data_synchronizer()
    logger.info("=================================================================")
    logger.info("TODOS OS TESTES DA CAIXA 1 FORAM EXECUTADOS E APROVADOS COM SUCESSO!")
    logger.info("=================================================================")
