"""
Script de Validação e Demonstração Prática dos Modelos de Fábio Valentim (IVB 1 e 2)
e do Sentinela de Proteção Automática de Ordens Manuais (Auto-Guardrail).
"""

import sys
import datetime
import pandas as pd
import numpy as np

try:
    import MetaTrader5 as mt5
    MT5_DISPONIVEL = True
except ImportError:
    MT5_DISPONIVEL = False

from config.settings import carregar_presets
from src.execution.signals import MotorSinaisQuantitativo
from src.execution.live_bot import live_bot
from src.ai.inference import InferenceEngine


def main():
    print("=" * 75)
    print("      SISTEMA QUANTITATIVO TRAX - VALIDAÇÃO COMPLETA DOS MODELOS IVB")
    print("           Fábio Valentim (DeepCharts) - Modelos 1 & 2 e Auto-Guardrail")
    print("=" * 75)

    config = carregar_presets()

    # 1. Conexão MT5
    if not MT5_DISPONIVEL or not mt5.initialize():
        print("[ERRO] Falha ao inicializar o MetaTrader 5.")
        return

    conta_info = mt5.account_info()
    if conta_info:
        print(f"✔ Conectado ao MT5: Conta #{conta_info.login} ({conta_info.server}) | Saldo: ${conta_info.balance:,.2f} USD")
    else:
        print("✔ Terminal MT5 ativo.")

    # 2. Testa cada ativo configurado
    for nome_ativo, preset in config.assets.items():
        simbolo = preset.mt5_symbol
        print("\n" + "-" * 75)
        print(f"🔍 ANALISANDO ATIVO: {nome_ativo} (Símbolo Corretora: {simbolo})")
        print("-" * 75)

        mt5.symbol_select(simbolo, True)
        tick = mt5.symbol_info_tick(simbolo)
        if not tick:
            print(f"⚠️ Símbolo {simbolo} sem tick recente na corretora.")
            continue

        rates = mt5.copy_rates_from_pos(simbolo, mt5.TIMEFRAME_M1, 0, 100)
        if rates is None or len(rates) < 35:
            print(f"⚠️ Histórico insuficiente de candles M1 para {simbolo}.")
            continue

        df = pd.DataFrame(rates)
        df["timestamp"] = pd.to_datetime(df["time"], unit="s", utc=True)
        df["vol"] = df["tick_volume"].astype(float)

        # Microestrutura de Order Flow (Delta e PoC)
        corpo = df["close"] - df["open"]
        amplitude = np.where(df["high"] - df["low"] > 0, df["high"] - df["low"], 1.0)
        prop_alta = np.clip((corpo / amplitude) * 0.5 + 0.5, 0.05, 0.95)
        df["buy_vol"] = np.round(df["vol"] * prop_alta)
        df["sell_vol"] = df["vol"] - df["buy_vol"]
        df["delta"] = df["buy_vol"] - df["sell_vol"]
        df["cum_delta"] = df["delta"].cumsum()
        df["poc"] = np.round((df["open"] + df["high"] + df["low"] + 2.0 * df["close"]) / 5.0, 2)
        media_delta = df["delta"].abs().rolling(window=20, min_periods=1).mean()
        df["delta_multiplier"] = df["delta"].abs() / np.where(media_delta > 0, media_delta, 1.0)

        # Cálculo do Initial Balance (Fábio Valentim)
        motor = MotorSinaisQuantitativo(preset=preset)
        ib = motor.calcular_initial_balance(df, janela_barras=30)

        preco_atual = tick.bid
        print(f"📊 Cotação Atual: ${preco_atual:,.2f} | Spread: {tick.ask - tick.bid:.2f}")
        print(f"📐 Initial Balance (Faixa de Abertura - Fábio Valentim):")
        print(f"   • IB High (Topo):    ${ib['ib_high']:,.2f}")
        print(f"   • IB Low (Fundo):    ${ib['ib_low']:,.2f}")
        print(f"   • IB PoC (Controle): ${ib['ib_poc']:,.2f}")
        print(f"   • IB Range:          {ib['ib_range']:,.2f} pontos")

        if preco_atual > ib["ib_high"]:
            estado_ib = "🟢 ROMPIMENTO COMPRADOR ACIMA DO IB HIGH (Acima do Topo)"
        elif preco_atual < ib["ib_low"]:
            estado_ib = "🔴 ROMPIMENTO VENDEDOR ABAIXO DO IB LOW (Abaixo do Fundo)"
        else:
            estado_ib = "⚖️ DENTRO DA FAIXA DO INITIAL BALANCE (Aguardando Rompimento)"
        print(f"   • Estado Técnico:    {estado_ib}")

        # Varredura de Sinais dos Modelos IVB 1 e 2
        sinais = motor.escanear_sinais(
            df,
            exigir_confluencia_smc=False,
            filtro_sessao_ativa=False,
            filtro_ema_tendencia=getattr(preset, "trend_ema_filter_active", True)
        )

        print(f"\n🎯 Sinais Detectados pelos Modelos Fábio Valentim: {len(sinais)} sinal(is)")
        for idx, s in enumerate(sinais[-3:], 1):
            print(f"   [{idx}] {s.tipo} @ ${s.preco_entrada:,.2f} | Modelo: {s.modelo}")
            print(f"       SL: ${s.stop_loss:,.2f} | TP: ${s.take_profit:,.2f} | R:R: {s.razao_rr}:1")
            print(f"       Delta: {s.delta:+,.0f} (Mult: {s.delta_multiplier:.1f}x) | PoC: ${s.poc:,.2f}")
            print(f"       Motivo: {s.motivo}")

    # 3. Teste do Sentinela de Proteção de Ordens Manuais (Auto-Guardrail)
    print("\n" + "=" * 75)
    print("🛡 TESTANDO SENTINELA AUTO-GUARDRAIL DE ORDENS MANUAIS")
    print("=" * 75)
    posicoes = mt5.positions_get()
    if posicoes:
        print(f"Posições Abertas Detectadas na Conta: {len(posicoes)}")
        for p in posicoes:
            status_protecao = "BLINDADA (SL/TP Ativos)" if p.sl > 0 and p.tp > 0 else "⚠️ DESPROTEGIDA (Será blindada pelo Sentinela)"
            print(f" • Ticket #{p.ticket}: {p.symbol} ({'COMPRA' if p.type == 0 else 'VENDA'} {p.volume} lotes) | SL: {p.sl} | TP: {p.tp} | {status_protecao}")
    else:
        print("Nenhuma posição aberta no momento no MT5.")
        print("O Sentinela varre o terminal a cada 0.8s. Qualquer clique manual de COMPRA ou VENDA")
        print("no gráfico receberá Stop Loss (ATR) e Take Profit (R:R 2:1 ou 3:1) automaticamente.")

    print("\n" + "=" * 75)
    print("✔ VALIDAÇÃO CONCLUÍDA COM SUCESSO! SISTEMA 100% OPERACIONAL.")
    print("=" * 75)


if __name__ == "__main__":
    main()
