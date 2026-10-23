"""
Validador de Backtest Quantitativo da Lógica do TRAX_Institutional_EA v2.70.
Consome o histórico de candles M1 reais diretamente do MetaTrader 5 da VT Markets.
Executa rigorosamente a mesma lógica de Breakout, Order Flow (Delta/PoC), ATR Stop e Trailing Stop.
"""

import sys
import datetime
import numpy as np
import pandas as pd
import MetaTrader5 as mt5

def executar_backtest_trax(simbolo="NAS100.s", n_barras=60000, rolling_bars=20, vol_mult=1.0, delta_mult=1.0, rr_ratio=2.0, atr_mult=1.5, lote=0.10):
    if not mt5.initialize():
        print("Erro ao inicializar MetaTrader 5")
        return None

    # Tenta símbolo alternativo se o principal não existir
    if not mt5.symbol_select(simbolo, True):
        for alt in ["NAS100ft.", "XAUUSD-VIP", "XAUUSD-STDc", "XAUUSD"]:
            if mt5.symbol_select(alt, True):
                simbolo = alt
                break

    info = mt5.symbol_info(simbolo)
    if info is None:
        print(f"Símbolo {simbolo} não encontrado no terminal.")
        mt5.shutdown()
        return None

    point = info.point
    digits = info.digits
    spread_pts = info.spread * point

    print(f"============================================================")
    print(f"[TRAX v2.70] INICIANDO BACKTEST INSTITUCIONAL")
    print(f"Ativo: {simbolo} | Timeframe: M1 | Lote: {lote}")
    print(f"Parametros: Rolling Bars: {rolling_bars} | R:R: {rr_ratio:.1f}:1 | ATR SL: {atr_mult}x | VolMult: {vol_mult:.2f}")
    print(f"============================================================")

    rates = mt5.copy_rates_from_pos(simbolo, mt5.TIMEFRAME_M1, 0, n_barras)
    mt5.shutdown()

    if rates is None or len(rates) < 100:
        print("Histórico insuficiente de barras.")
        return None

    df = pd.DataFrame(rates)
    df['time_dt'] = pd.to_datetime(df['time'], unit='s')
    n_total = len(df)
    print(f"Barras M1 carregadas: {n_total:,} (de {df['time_dt'].iloc[0]} a {df['time_dt'].iloc[-1]})")

    # 1. Cálculo de ATR (14 períodos)
    tr1 = df['high'] - df['low']
    tr2 = (df['high'] - df['close'].shift(1)).abs()
    tr3 = (df['low'] - df['close'].shift(1)).abs()
    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    df['atr'] = tr.rolling(window=14).mean().fillna(tr)

    # 2. Decomposição de Fluxo de Agressão e Delta Intra-Candle
    corpo = df['close'] - df['open']
    amplitude = df['high'] - df['low']
    amplitude = np.where(amplitude > 0, amplitude, point)
    prop_alta = np.clip((corpo / amplitude) * 0.5 + 0.5, 0.05, 0.95)
    df['buy_vol'] = df['tick_volume'] * prop_alta
    df['sell_vol'] = df['tick_volume'] - df['buy_vol']
    df['delta'] = df['buy_vol'] - df['sell_vol']
    df['vol_media'] = df['tick_volume'].rolling(window=15).mean().fillna(df['tick_volume'])
    df['poc'] = (df['open'] + df['high'] + df['low'] + 2.0 * df['close']) / 5.0

    # 3. Execução da Simulação Barra a Barra
    trades = []
    posicao_ativa = None # dict com {tipo, entry_price, sl, tp, entry_time, be_ativado, sl_inicial}
    saldo = 10000.0
    equity_curve = [saldo]

    for i in range(rolling_bars + 2, n_total):
        barra_atual = df.iloc[i] # Barra atual em formação / abertura
        candle_romp = df.iloc[i - 1] # Barra recém-fechada (shift 1)
        candle_ant = df.iloc[i - 2]  # Barra shift 2

        # Gerenciamento da Posição Ativa (se houver)
        if posicao_ativa is not None:
            preco_high = barra_atual['high']
            preco_low = barra_atual['low']
            tipo = posicao_ativa['tipo']
            sl = posicao_ativa['sl']
            tp = posicao_ativa['tp']
            preco_open = posicao_ativa['entry_price']
            atr_momento = posicao_ativa['atr']

            fechou = False
            resultado_pips = 0.0
            resultado_usd = 0.0
            motivo_saida = ""

            if tipo == "BUY":
                # Verifica Take Profit
                if preco_high >= tp:
                    resultado_pips = tp - preco_open
                    fechou = True
                    motivo_saida = "Take Profit (2:1)"
                # Verifica Stop Loss
                elif preco_low <= sl:
                    resultado_pips = sl - preco_open
                    fechou = True
                    motivo_saida = "Stop Loss"
                else:
                    # Break-Even: Se avançar 1x ATR, move SL para 0x0
                    ganho_atual = preco_high - preco_open
                    if ganho_atual >= atr_momento * 1.0 and not posicao_ativa['be_ativado']:
                        posicao_ativa['sl'] = preco_open + spread_pts
                        posicao_ativa['be_ativado'] = True

                    # Trailing Stop: conduz lucro a 0.75 ATR atrás
                    if ganho_atual >= atr_momento * 1.5:
                        novo_sl = barra_atual['close'] - (atr_momento * 0.75)
                        if novo_sl > posicao_ativa['sl']:
                            posicao_ativa['sl'] = novo_sl

            elif tipo == "SELL":
                # Take Profit
                if preco_low <= tp:
                    resultado_pips = preco_open - tp
                    fechou = True
                    motivo_saida = "Take Profit (2:1)"
                # Stop Loss
                elif preco_high >= sl:
                    resultado_pips = preco_open - sl
                    fechou = True
                    motivo_saida = "Stop Loss"
                else:
                    ganho_atual = preco_open - preco_low
                    if ganho_atual >= atr_momento * 1.0 and not posicao_ativa['be_ativado']:
                        posicao_ativa['sl'] = preco_open - spread_pts
                        posicao_ativa['be_ativado'] = True

                    if ganho_atual >= atr_momento * 1.5:
                        novo_sl = barra_atual['close'] + (atr_momento * 0.75)
                        if novo_sl < posicao_ativa['sl']:
                            posicao_ativa['sl'] = novo_sl

            if fechou:
                # Calcula valor monetário aproximado por ponto
                # No Nasdaq/CFD, 0.10 lote = $0.10 por ponto ou $1.00 dependendo do contrato
                fator_contrato = 1.0 if "NAS" in simbolo else 10.0
                resultado_usd = (resultado_pips / point) * lote * (point * fator_contrato)
                # Ajuste de PnL realista
                if "NAS" in simbolo:
                    resultado_usd = resultado_pips * lote * 1.0 # 0.10 lote no Nasdaq = $0.10 por ponto de índice
                elif "XAU" in simbolo:
                    resultado_usd = resultado_pips * lote * 100.0 # 0.10 lote no Ouro = $10 por dólar

                saldo += resultado_usd
                equity_curve.append(saldo)

                trades.append({
                    "ticket": len(trades) + 1,
                    "tipo": tipo,
                    "modelo": posicao_ativa['modelo'],
                    "entry_time": posicao_ativa['entry_time'],
                    "exit_time": barra_atual['time_dt'],
                    "entry_price": preco_open,
                    "exit_price": tp if "Take" in motivo_saida else sl,
                    "resultado_pts": resultado_pips,
                    "resultado_usd": resultado_usd,
                    "saldo_final": saldo,
                    "motivo": motivo_saida
                })
                posicao_ativa = None

            continue # Durante posição aberta, não abre nova ordem

        # 4. Avaliação de Gatilho de Entrada (se estiver livre)
        # Faixa das últimas N barras (shift 2 até shift 2+rolling_bars-1)
        sub_faixa = df.iloc[i - 1 - rolling_bars : i - 1]
        ib_high = sub_faixa['high'].max()
        ib_low = sub_faixa['low'].min()

        if ib_high <= ib_low:
            continue

        media_vol = candle_romp['vol_media']
        delta_atual = candle_romp['delta']
        limiar_delta = media_vol * 0.15 * delta_mult
        poc_barra = candle_romp['poc']
        atr_val = candle_romp['atr']
        preco_entrada = barra_atual['open']

        # GATILHO DE COMPRA
        rompimento_alta = (candle_romp['close'] > ib_high) and (candle_ant['close'] <= ib_high + 2.0 * point)
        m1_buy = (candle_romp['tick_volume'] >= media_vol * vol_mult) and (candle_romp['close'] >= poc_barra)
        m2_buy = (delta_atual > 0) and (abs(delta_atual) >= limiar_delta)

        if rompimento_alta and (m1_buy or m2_buy):
            dist_sl = max(atr_val * atr_mult, spread_pts * 2.5, 50 * point)
            sl = preco_entrada - dist_sl
            tp = preco_entrada + (dist_sl * rr_ratio)
            posicao_ativa = {
                "tipo": "BUY",
                "modelo": "Modelo 2 (Delta)" if m2_buy else "Modelo 1 (Volume)",
                "entry_price": preco_entrada,
                "sl": sl,
                "tp": tp,
                "entry_time": barra_atual['time_dt'],
                "atr": atr_val,
                "be_ativado": False
            }
            continue

        # GATILHO DE VENDA
        rompimento_baixa = (candle_romp['close'] < ib_low) and (candle_ant['close'] >= ib_low - 2.0 * point)
        m1_sell = (candle_romp['tick_volume'] >= media_vol * vol_mult) and (candle_romp['close'] <= poc_barra)
        m2_sell = (delta_atual < 0) and (abs(delta_atual) >= limiar_delta)

        if rompimento_baixa and (m1_sell or m2_sell):
            dist_sl = max(atr_val * atr_mult, spread_pts * 2.5, 50 * point)
            sl = preco_entrada + dist_sl
            tp = preco_entrada - (dist_sl * rr_ratio)
            posicao_ativa = {
                "tipo": "SELL",
                "modelo": "Modelo 2 (Delta)" if m2_sell else "Modelo 1 (Volume)",
                "entry_price": preco_entrada,
                "sl": sl,
                "tp": tp,
                "entry_time": barra_atual['time_dt'],
                "atr": atr_val,
                "be_ativado": False
            }
            continue

    # Relatório de Métricas Finais
    df_trades = pd.DataFrame(trades)
    if df_trades.empty:
        print("[AVISO] Nenhuma negociacao executada no periodo.")
        return None

    total_negociacoes = len(df_trades)
    vencedores = df_trades[df_trades['resultado_usd'] > 0]
    perdedores = df_trades[df_trades['resultado_usd'] < 0]
    empates = df_trades[df_trades['resultado_usd'] == 0]

    n_win = len(vencedores)
    n_loss = len(perdedores)
    win_rate = (n_win / total_negociacoes) * 100.0

    lucro_bruto = vencedores['resultado_usd'].sum() if not vencedores.empty else 0.0
    perda_bruta = abs(perdedores['resultado_usd'].sum()) if not perdedores.empty else 0.0
    lucro_liquido = lucro_bruto - perda_bruta
    profit_factor = (lucro_bruto / perda_bruta) if perda_bruta > 0 else 99.0

    # Drawdown Maximo
    eq_series = pd.Series(equity_curve)
    peak = eq_series.cummax()
    dd = (eq_series - peak)
    max_dd = abs(dd.min())
    max_dd_pct = (max_dd / 10000.0) * 100.0

    print("\n" + "="*60)
    print("RELATORIO DETALHADO DO BACKTEST (ORDENS REAIS EXECUTADAS)")
    print("="*60)
    print(f"Total de Negociacoes:           {total_negociacoes}")
    print(f"Trades Comprados (BUY):         {len(df_trades[df_trades['tipo'] == 'BUY'])}")
    print(f"Trades Vendidos (SELL):         {len(df_trades[df_trades['tipo'] == 'SELL'])}")
    print(f"Negociacoes com Lucro:          {n_win} ({win_rate:.1f}%)")
    print(f"Negociacoes com Perda:          {n_loss} ({len(perdedores)/total_negociacoes*100:.1f}%)")
    print(f"Negociacoes em 0x0 (BE):        {len(empates)}")
    print(f"------------------------------------------------------------")
    print(f"Lucro Bruto:                   +${lucro_bruto:,.2f} USD")
    print(f"Perda Bruta:                   -${perda_bruta:,.2f} USD")
    print(f"Lucro Liquido Total:           +${lucro_liquido:,.2f} USD")
    print(f"Fator de Lucro (Profit Factor): {profit_factor:.2f}")
    print(f"Rebaixamento Maximo (Drawdown): ${max_dd:,.2f} USD ({max_dd_pct:.2f}%)")
    print(f"Saldo Final:                    ${saldo:,.2f} USD")
    print("="*60)

    # Exibe amostra dos primeiros e ultimos trades
    print("\nAMOSTRA DOS PRIMEIROS TRADES EXECUTADOS:")
    for _, t in df_trades.head(5).iterrows():
        print(f"#{t['ticket']} | {t['tipo']} | {t['entry_time']} -> {t['exit_time']} | Pts: {t['resultado_pts']:+.2f} | PnL: ${t['resultado_usd']:+.2f} | {t['motivo']}")

    print("\nAMOSTRA DOS ULTIMOS TRADES EXECUTADOS:")
    for _, t in df_trades.tail(5).iterrows():
        print(f"#{t['ticket']} | {t['tipo']} | {t['entry_time']} -> {t['exit_time']} | Pts: {t['resultado_pts']:+.2f} | PnL: ${t['resultado_usd']:+.2f} | {t['motivo']}")

    return df_trades

if __name__ == "__main__":
    executar_backtest_trax(simbolo="NAS100.s", n_barras=60000, rolling_bars=20, vol_mult=1.0, delta_mult=1.0, rr_ratio=2.0, atr_mult=1.5, lote=0.10)
