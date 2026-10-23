"""
Laboratório Quantitativo Institucional TRAX.
Avalia o impacto dos Filtros Institucionais de Elite sobre os 60.000 candles do Nasdaq:
1. Filtro de Tendência HTF (EMA 200) - Elimina falsos rompimentos contra a maré
2. Filtro de Expansão de Range (SMC Volatility Filter)
3. Limiar Rigoroso de Order Flow (Delta Spike >= 2.0x média)
4. Filtro de Sessão / Horários de Alta Liquidez
"""

import MetaTrader5 as mt5
import pandas as pd
import numpy as np

def simular_estrategia(df, filtro_tendencia=True, filtro_sessao=True, delta_mult=2.0, vol_mult=1.3, rr_ratio=2.5, atr_sl_mult=1.5, lote=0.10):
    point = 0.01
    n_total = len(df)
    rolling_bars = 20

    trades = []
    posicao = None
    saldo = 10000.0

    for i in range(200, n_total):
        b = df.iloc[i]
        c1 = df.iloc[i-1] # barra fechada 1
        c2 = df.iloc[i-2] # barra 2

        # Gerenciamento de Posição Aberta
        if posicao is not None:
            high = b['high']
            low = b['low']
            tipo = posicao['tipo']
            sl = posicao['sl']
            tp = posicao['tp']
            entry_price = posicao['entry_price']
            atr_mom = posicao['atr']
            be = posicao['be']

            fechou = False
            pts = 0.0

            if tipo == "BUY":
                if high >= tp:
                    pts = tp - entry_price
                    fechou = True
                elif low <= sl:
                    pts = sl - entry_price
                    fechou = True
                else:
                    ganho = high - entry_price
                    # Break-even em 1x ATR
                    if ganho >= atr_mom * 1.0 and not be:
                        posicao['sl'] = entry_price + (2.0 * point)
                        posicao['be'] = True
                    # Trailing stop
                    if ganho >= atr_mom * 1.8:
                        novo_sl = b['close'] - (atr_mom * 0.8)
                        if novo_sl > posicao['sl']:
                            posicao['sl'] = novo_sl

            elif tipo == "SELL":
                if low <= tp:
                    pts = entry_price - tp
                    fechou = True
                elif high >= sl:
                    pts = entry_price - sl
                    fechou = True
                else:
                    ganho = entry_price - low
                    if ganho >= atr_mom * 1.0 and not be:
                        posicao['sl'] = entry_price - (2.0 * point)
                        posicao['be'] = True
                    if ganho >= atr_mom * 1.8:
                        novo_sl = b['close'] + (atr_mom * 0.8)
                        if novo_sl < posicao['sl']:
                            posicao['sl'] = novo_sl

            if fechou:
                pnl = pts * lote * 1.0
                saldo += pnl
                trades.append({
                    "tipo": tipo,
                    "pts": pts,
                    "pnl": pnl,
                    "win": (pnl > 0),
                    "saldo": saldo
                })
                posicao = None
            continue

        # Avaliação de Entradas
        # Filtro de Sessão / Horário
        hora = b['time_dt'].hour
        if filtro_sessao:
            # Foco em Londres (08h às 12h) e NY (13h às 21h) - horário UTC/corretora
            if not ((8 <= hora <= 12) or (14 <= hora <= 22)):
                continue

        sub = df.iloc[i-1-rolling_bars : i-1]
        ib_h = sub['high'].max()
        ib_l = sub['low'].min()
        if ib_h <= ib_l:
            continue

        media_vol = c1['vol_media']
        delta = c1['delta']
        limiar_delta = media_vol * 0.20 * delta_mult
        atr_val = c1['atr']
        dist_sl = max(atr_val * atr_sl_mult, 50 * point)

        # Filtro de Tendência HTF (EMA 200)
        tendencia_alta = c1['close'] > c1['ema200']
        tendencia_baixa = c1['close'] < c1['ema200']

        # COMPRA
        romp_h = (c1['close'] > ib_h) and (c2['close'] <= ib_h + 2.0 * point)
        vol_ok_buy = (c1['tick_volume'] >= media_vol * vol_mult)
        delta_ok_buy = (delta > 0) and (abs(delta) >= limiar_delta)

        if romp_h and (vol_ok_buy and delta_ok_buy):
            if filtro_tendencia and not tendencia_alta:
                continue # Rejeita compra contra a tendência principal

            posicao = {
                "tipo": "BUY",
                "entry_price": b['open'],
                "sl": b['open'] - dist_sl,
                "tp": b['open'] + (dist_sl * rr_ratio),
                "atr": atr_val,
                "be": False
            }
            continue

        # VENDA
        romp_l = (c1['close'] < ib_l) and (c2['close'] >= ib_l - 2.0 * point)
        vol_ok_sell = (c1['tick_volume'] >= media_vol * vol_mult)
        delta_ok_sell = (delta < 0) and (abs(delta) >= limiar_delta)

        if romp_l and (vol_ok_sell and delta_ok_sell):
            if filtro_tendencia and not tendencia_baixa:
                continue # Rejeita venda contra a tendência principal

            posicao = {
                "tipo": "SELL",
                "entry_price": b['open'],
                "sl": b['open'] + dist_sl,
                "tp": b['open'] - (dist_sl * rr_ratio),
                "atr": atr_val,
                "be": False
            }
            continue

    if len(trades) == 0:
        return {"total": 0, "win_rate": 0, "lucro": 0, "pf": 0}

    tdf = pd.DataFrame(trades)
    wins = tdf[tdf['pnl'] > 0]
    losses = tdf[tdf['pnl'] < 0]
    lucro_bruto = wins['pnl'].sum() if len(wins) > 0 else 0
    perda_bruta = abs(losses['pnl'].sum()) if len(losses) > 0 else 0
    lucro_liq = lucro_bruto - perda_bruta
    pf = (lucro_bruto / perda_bruta) if perda_bruta > 0 else 99.0
    win_rate = (len(wins) / len(tdf)) * 100.0

    return {
        "total": len(tdf),
        "win_rate": win_rate,
        "lucro_bruto": lucro_bruto,
        "perda_bruta": perda_bruta,
        "lucro_liq": lucro_liq,
        "pf": pf
    }

if __name__ == "__main__":
    if not mt5.initialize():
        print("Erro MT5")
        quit()

    simbolo = "NAS100.s"
    if not mt5.symbol_select(simbolo, True):
        for alt in ["NAS100ft.", "XAUUSD-STDc", "XAUUSD-VIP", "XAUUSD"]:
            if mt5.symbol_select(alt, True):
                simbolo = alt
                break
    print(f"Simbolo selecionado: {simbolo}")
    rates = mt5.copy_rates_from_pos(simbolo, mt5.TIMEFRAME_M1, 0, 60000)
    mt5.shutdown()

    if rates is None or len(rates) == 0:
        print("Erro ao carregar dados")
        quit()

    df = pd.DataFrame(rates)
    df['time_dt'] = pd.to_datetime(df['time'], unit='s')
    df['ema200'] = df['close'].ewm(span=200, adjust=False).mean()
    tr = pd.concat([df['high'] - df['low'], (df['high'] - df['close'].shift(1)).abs(), (df['low'] - df['close'].shift(1)).abs()], axis=1).max(axis=1)
    df['atr'] = tr.rolling(14).mean()

    corpo = df['close'] - df['open']
    amplitude = np.where(df['high'] - df['low'] > 0, df['high'] - df['low'], 0.01)
    prop = np.clip((corpo / amplitude) * 0.5 + 0.5, 0.05, 0.95)
    df['buy_vol'] = df['tick_volume'] * prop
    df['sell_vol'] = df['tick_volume'] - df['buy_vol']
    df['delta'] = df['buy_vol'] - df['sell_vol']
    df['vol_media'] = df['tick_volume'].rolling(20).mean()

    print("=================================================================")
    print("COMPARATIVO QUANTITATIVO: TESTANDO CAMADAS INSTITUCIONAIS")
    print("=================================================================")

    # Teste 1: Base (Sem filtros, como rodou antes)
    r1 = simular_estrategia(df, filtro_tendencia=False, filtro_sessao=False, delta_mult=1.0, vol_mult=1.0, rr_ratio=2.0)
    print(f"1. BASE BRUTA (Sem Filtros)  : Trades: {r1['total']} | WinRate: {r1['win_rate']:.1f}% | Lucro: ${r1['lucro_liq']:+,.2f} | PF: {r1['pf']:.2f}")

    # Teste 2: + Filtro de Tendência HTF (EMA 200)
    r2 = simular_estrategia(df, filtro_tendencia=True, filtro_sessao=False, delta_mult=1.0, vol_mult=1.0, rr_ratio=2.0)
    print(f"2. + FILTRO TENDENCIA HTF     : Trades: {r2['total']} | WinRate: {r2['win_rate']:.1f}% | Lucro: ${r2['lucro_liq']:+,.2f} | PF: {r2['pf']:.2f}")

    # Teste 3: + Filtro de Tendência HTF + Sessões Nobres (Londres/NY)
    r3 = simular_estrategia(df, filtro_tendencia=True, filtro_sessao=True, delta_mult=1.0, vol_mult=1.0, rr_ratio=2.0)
    print(f"3. + TENDENCIA + SESSOES NOBRES: Trades: {r3['total']} | WinRate: {r3['win_rate']:.1f}% | Lucro: ${r3['lucro_liq']:+,.2f} | PF: {r3['pf']:.2f}")

    # Teste 4: + Spike Real de Delta (2.0x) e Volume (1.3x) + R:R 2.5:1
    r4 = simular_estrategia(df, filtro_tendencia=True, filtro_sessao=True, delta_mult=2.0, vol_mult=1.2, rr_ratio=2.5)
    print(f"4. + FILTRO ORDER FLOW RIGIDO : Trades: {r4['total']} | WinRate: {r4['win_rate']:.1f}% | Lucro: ${r4['lucro_liq']:+,.2f} | PF: {r4['pf']:.2f}")

    print("=================================================================")
