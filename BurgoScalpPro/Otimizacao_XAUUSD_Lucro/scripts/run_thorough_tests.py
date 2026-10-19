import asyncio
import json
import os
import re
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import websockets
import MetaTrader5 as mt5

# --- 1. FUNÇÕES DE EXTRAÇÃO TRADINGVIEW ---
def construct_tv_msg(msg_str):
    return f"~m~{len(msg_str)}~m~{msg_str}"

def parse_tv_msgs(raw):
    pattern = r"~m~(\d+)~m~"
    messages = []
    pos = 0
    while True:
        match = re.search(pattern, raw[pos:])
        if not match:
            break
        length = int(match.group(1))
        start = pos + match.end()
        end = start + length
        msg_payload = raw[start:end]
        messages.append(msg_payload)
        pos = end
    return messages

async def fetch_tv_candles(symbol="OANDA:XAUUSD", timeframe="5", num_bars=2000):
    uri = "wss://data.tradingview.com/socket.io/websocket"
    headers = {
        "Origin": "https://data.tradingview.com",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    }
    async with websockets.connect(uri, additional_headers=headers) as ws:
        await ws.send(construct_tv_msg(json.dumps({"m": "set_auth_token", "p": ["unauthorized_user_token"]})))
        chart_session = f"cs_{symbol.replace(':', '_')}_{timeframe}"
        await ws.send(construct_tv_msg(json.dumps({"m": "chart_create_session", "p": [chart_session, ""]})))
        symbol_spec = json.dumps({"adjustment": "splits", "symbol": symbol})
        await ws.send(construct_tv_msg(json.dumps({"m": "resolve_symbol", "p": [chart_session, "sds_sym_1", f"={symbol_spec}"]})))
        await ws.send(construct_tv_msg(json.dumps({"m": "create_series", "p": [chart_session, "sds_1", "s1", "sds_sym_1", timeframe, num_bars, ""]})))
        
        bars = []
        timeout = 15
        start_time = asyncio.get_event_loop().time()
        while asyncio.get_event_loop().time() - start_time < timeout:
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=3)
            except asyncio.TimeoutError:
                break
            if "~h~" in raw:
                await ws.send(raw)
                continue
            for m in parse_tv_msgs(raw):
                if not m.startswith("{"):
                    continue
                try:
                    data = json.loads(m)
                    if data.get("m") == "timescale_update":
                        series = data.get("p", [])[1].get("sds_1", {}).get("s", [])
                        if series:
                            for item in series:
                                v = item.get("v", [])
                                if len(v) >= 6:
                                    bars.append({
                                        "time": pd.to_datetime(v[0], unit='s'),
                                        "open": v[1],
                                        "high": v[2],
                                        "low": v[3],
                                        "close": v[4],
                                        "volume": v[5]
                                    })
                            return pd.DataFrame(bars)
                except Exception:
                    pass
        return pd.DataFrame(bars)

# --- 2. EXTRAÇÃO METATRADER 5 ---
def fetch_mt5_candles(symbol="XAUUSD-VIP", timeframe=mt5.TIMEFRAME_M5, num_bars=2000):
    mt5_path = r"C:\Program Files\MetaTrader 5\terminal64.exe"
    if not mt5.initialize(path=mt5_path):
        raise RuntimeError(f"Falha ao inicializar MT5: {mt5.last_error()}")
    mt5.symbol_select(symbol, True)
    rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, num_bars)
    mt5.shutdown()
    if rates is None or len(rates) == 0:
        raise RuntimeError(f"Nenhum candle retornado para {symbol}")
    df = pd.DataFrame(rates)
    df["time"] = pd.to_datetime(df["time"], unit="s")
    df.rename(columns={"tick_volume": "volume"}, inplace=True)
    return df[["time", "open", "high", "low", "close", "volume", "spread"]]

# --- 3. RECONHECIMENTO RIGOROSO DE PADRÕES DE CANDLESTICK ---
def detect_patterns(df):
    df = df.copy()
    o = df["open"].values
    h = df["high"].values
    l = df["low"].values
    c = df["close"].values
    v = df["volume"].values
    
    n = len(df)
    
    body = np.abs(c - o)
    span = h - l
    span = np.where(span == 0, 0.0001, span)
    body_pct = body / span
    
    upper_wick = h - np.maximum(o, c)
    lower_wick = np.minimum(o, c) - l
    
    # Médias para contexto
    df["ema20"] = df["close"].ewm(span=20).mean()
    df["ema50"] = df["close"].ewm(span=50).mean()
    df["vol_ma20"] = df["volume"].rolling(20).mean()
    
    # Flags de padrões
    hammer = np.zeros(n, dtype=bool)
    hanging_man = np.zeros(n, dtype=bool)
    bullish_engulfing = np.zeros(n, dtype=bool)
    bearish_engulfing = np.zeros(n, dtype=bool)
    tweezer_bottom = np.zeros(n, dtype=bool)
    tweezer_top = np.zeros(n, dtype=bool)
    three_outside_up = np.zeros(n, dtype=bool)
    three_outside_down = np.zeros(n, dtype=bool)
    piercing_line = np.zeros(n, dtype=bool)
    dark_cloud = np.zeros(n, dtype=bool)
    
    for i in range(2, n):
        # 1. Hammer (Martelo): corpo pequeno topo, cauda inferior >= 2x corpo, pavio superior pequeno
        if (body_pct[i] <= 0.35) and (lower_wick[i] >= 2.0 * body[i]) and (upper_wick[i] <= 0.15 * span[i]) and (c[i] > o[i]):
            # Contexto: vem de queda recente
            if c[i-1] < o[i-1] or c[i] < df["ema20"].iloc[i]:
                hammer[i] = True
                
        # 2. Hanging Man (Enforcado): corpo pequeno topo após alta
        if (body_pct[i] <= 0.35) and (lower_wick[i] >= 2.0 * body[i]) and (upper_wick[i] <= 0.15 * span[i]):
            if c[i] > df["ema20"].iloc[i] and c[i-1] > o[i-1]:
                hanging_man[i] = True
                
        # 3. Engolfo de Alta
        if (c[i-1] < o[i-1]) and (c[i] > o[i]) and (o[i] <= c[i-1]) and (c[i] >= o[i-1]) and (body[i] > body[i-1]):
            bullish_engulfing[i] = True
            
        # 4. Engolfo de Baixa
        if (c[i-1] > o[i-1]) and (c[i] < o[i]) and (o[i] >= c[i-1]) and (c[i] <= o[i-1]) and (body[i] > body[i-1]):
            bearish_engulfing[i] = True
            
        # 5. Tweezer Bottom (Pinça de Fundo)
        if abs(l[i] - l[i-1]) <= (0.0005 * c[i]) and (c[i-1] < o[i-1]) and (c[i] > o[i]):
            tweezer_bottom[i] = True
            
        # 6. Tweezer Top (Pinça de Topo)
        if abs(h[i] - h[i-1]) <= (0.0005 * c[i]) and (c[i-1] > o[i-1]) and (c[i] < o[i]):
            tweezer_top[i] = True
            
        # 7. Piercing Line (Linha de Perfuração)
        mid_prev = (o[i-1] + c[i-1]) / 2.0
        if (c[i-1] < o[i-1]) and (o[i] < l[i-1]) and (c[i] > mid_prev) and (c[i] < o[i-1]):
            piercing_line[i] = True
            
        # 8. Dark Cloud Cover (Nuvem Negra)
        if (c[i-1] > o[i-1]) and (o[i] > h[i-1]) and (c[i] < mid_prev) and (c[i] > o[i-1]):
            dark_cloud[i] = True
            
        # 9. Three Outside Up (Engolfo + Confirmação na 3ª barra)
        if bullish_engulfing[i-1] and (c[i] > h[i-1]):
            three_outside_up[i] = True
            
        # 10. Three Outside Down
        if bearish_engulfing[i-1] and (c[i] < l[i-1]):
            three_outside_down[i] = True
            
    df["hammer"] = hammer
    df["hanging_man"] = hanging_man
    df["bullish_engulfing"] = bullish_engulfing
    df["bearish_engulfing"] = bearish_engulfing
    df["tweezer_bottom"] = tweezer_bottom
    df["tweezer_top"] = tweezer_top
    df["piercing_line"] = piercing_line
    df["dark_cloud"] = dark_cloud
    df["three_outside_up"] = three_outside_up
    df["three_outside_down"] = three_outside_down
    
    return df

# --- 4. MOTOR DE BACKTEST MINUCIOSO ---
def backtest_engine(df, mode="pure", rr=1.5, spread_pts=3.0):
    """
    mode:
      - 'pure': qualquer padrão dispara ordem
      - 'trend_filtered': só compra acima de EMA50 / só vende abaixo de EMA50
      - 'high_precision': tendência + volume institucional (> 1.2x média) + confirmação
    """
    trades = []
    n = len(df)
    
    for i in range(50, n - 20):
        c = df["close"].iloc[i]
        o = df["open"].iloc[i]
        h = df["high"].iloc[i]
        l = df["low"].iloc[i]
        vol = df["volume"].iloc[i]
        vol_avg = df["vol_ma20"].iloc[i]
        ema50 = df["ema50"].iloc[i]
        
        # Sinais de Compra
        buy_signal = (
            df["hammer"].iloc[i] or
            df["bullish_engulfing"].iloc[i] or
            df["tweezer_bottom"].iloc[i] or
            df["piercing_line"].iloc[i] or
            df["three_outside_up"].iloc[i]
        )
        
        # Sinais de Venda
        sell_signal = (
            df["hanging_man"].iloc[i] or
            df["bearish_engulfing"].iloc[i] or
            df["tweezer_top"].iloc[i] or
            df["dark_cloud"].iloc[i] or
            df["three_outside_down"].iloc[i]
        )
        
        if not buy_signal and not sell_signal:
            continue
            
        # Filtros por Modo
        if mode == "trend_filtered":
            if buy_signal and c < ema50:
                buy_signal = False
            if sell_signal and c > ema50:
                sell_signal = False
                
        elif mode == "high_precision":
            # Exige confluência com volume acima da média (absorção institucional / agressão real)
            # E alinhamento de tendência
            if buy_signal:
                if (c < ema50) or (vol < 1.15 * vol_avg):
                    buy_signal = False
            if sell_signal:
                if (c > ema50) or (vol < 1.15 * vol_avg):
                    sell_signal = False
                    
        direction = None
        if buy_signal and not sell_signal:
            direction = "BUY"
        elif sell_signal and not buy_signal:
            direction = "SELL"
        else:
            continue
            
        # Execução na abertura da barra seguinte (i+1)
        entry_price = df["open"].iloc[i+1]
        
        # Cálculo de Stop Loss estrutural baseado no padrão
        buffer = 0.50 # $0.50 de folga no ouro
        if direction == "BUY":
            entry_price += (spread_pts * 0.1) # Custo de spread
            sl = min(df["low"].iloc[i], df["low"].iloc[i-1]) - buffer
            risk = entry_price - sl
            if risk <= 0.50 or risk > 15.0: # Filtra trades bizarros/minúsculos
                continue
            tp = entry_price + (risk * rr)
        else:
            entry_price -= (spread_pts * 0.1)
            sl = max(df["high"].iloc[i], df["high"].iloc[i-1]) + buffer
            risk = sl - entry_price
            if risk <= 0.50 or risk > 15.0:
                continue
            tp = entry_price - (risk * rr)
            
        # Avaliação barra a barra até saída
        outcome = None
        pnl = 0.0
        exit_time = None
        
        for k in range(i+1, min(i+100, n)):
            bar_h = df["high"].iloc[k]
            bar_l = df["low"].iloc[k]
            
            if direction == "BUY":
                if bar_l <= sl:
                    outcome = "LOSS"
                    pnl = -risk
                    exit_time = df["time"].iloc[k]
                    break
                elif bar_h >= tp:
                    outcome = "WIN"
                    pnl = risk * rr
                    exit_time = df["time"].iloc[k]
                    break
            else:
                if bar_h >= sl:
                    outcome = "LOSS"
                    pnl = -risk
                    exit_time = df["time"].iloc[k]
                    break
                elif bar_l <= tp:
                    outcome = "WIN"
                    pnl = risk * rr
                    exit_time = df["time"].iloc[k]
                    break
                    
        if outcome is not None:
            trades.append({
                "entry_time": df["time"].iloc[i+1],
                "exit_time": exit_time,
                "direction": direction,
                "entry_price": entry_price,
                "sl": sl,
                "tp": tp,
                "risk": risk,
                "outcome": outcome,
                "pnl": pnl,
                "pnl_r": 1.5 if outcome == "WIN" else -1.0
            })
            
    tdf = pd.DataFrame(trades)
    return tdf

def calculate_metrics(tdf, initial_capital=10000.0, risk_per_trade_pct=1.0):
    if tdf.empty:
        return {
            "total_trades": 0, "win_rate": 0, "profit_factor": 0,
            "net_profit": 0, "max_drawdown": 0, "expectancy_r": 0
        }
    
    wins = tdf[tdf["outcome"] == "WIN"]
    losses = tdf[tdf["outcome"] == "LOSS"]
    total = len(tdf)
    win_rate = (len(wins) / total) * 100.0 if total > 0 else 0
    
    gross_profit = wins["pnl"].sum()
    gross_loss = abs(losses["pnl"].sum())
    profit_factor = (gross_profit / gross_loss) if gross_loss > 0 else (99.0 if gross_profit > 0 else 0)
    
    # Simulação de Curva de Capital (com 1% de risco fixo por trade)
    balance = initial_capital
    curve = [balance]
    peak = balance
    max_dd = 0.0
    
    for _, t in tdf.iterrows():
        risk_dollar = balance * (risk_per_trade_pct / 100.0)
        gain = risk_dollar * t["pnl_r"]
        balance += gain
        curve.append(balance)
        if balance > peak:
            peak = balance
        dd = (peak - balance) / peak * 100.0
        if dd > max_dd:
            max_dd = dd
            
    net_profit_pct = ((balance - initial_capital) / initial_capital) * 100.0
    expectancy_r = (win_rate/100.0 * 1.5) - ((1.0 - win_rate/100.0) * 1.0)
    
    return {
        "total_trades": total,
        "win_rate": round(win_rate, 2),
        "profit_factor": round(profit_factor, 2),
        "net_profit_pct": round(net_profit_pct, 2),
        "max_drawdown": round(max_dd, 2),
        "expectancy_r": round(expectancy_r, 3),
        "final_balance": round(balance, 2),
        "curve": curve
    }

# --- 5. EXECUÇÃO COMPARATIVA GERAL ---
async def main():
    print("=== INICIANDO EXTRAÇÃO DE DADOS DE XAUUSD ===")
    
    # MT5
    print("1. Extraindo dados do MetaTrader 5 (VTMarkets XAUUSD-VIP)...")
    mt5_m5 = fetch_mt5_candles(symbol="XAUUSD-VIP", timeframe=mt5.TIMEFRAME_M5, num_bars=2000)
    mt5_m15 = fetch_mt5_candles(symbol="XAUUSD-VIP", timeframe=mt5.TIMEFRAME_M15, num_bars=1500)
    print(f"   [MT5] M5: {len(mt5_m5)} barras | M15: {len(mt5_m15)} barras")
    
    # TradingView
    print("2. Extraindo dados do TradingView (OANDA:XAUUSD WebSocket)...")
    tv_m5 = await fetch_tv_candles("OANDA:XAUUSD", "5", 2000)
    tv_m15 = await fetch_tv_candles("OANDA:XAUUSD", "15", 1500)
    print(f"   [TradingView] M5: {len(tv_m5)} barras | M15: {len(tv_m15)} barras")
    
    # Comparação de Dados
    print("\n3. Comparando fidelidade dos dados (MT5 vs TradingView)...")
    merged_m5 = pd.merge(mt5_m5, tv_m5, on="time", suffixes=("_mt5", "_tv"))
    diff_close = (merged_m5["close_mt5"] - merged_m5["close_tv"]).abs()
    corr = merged_m5["close_mt5"].corr(merged_m5["close_tv"])
    print(f"   Barras sincronizadas: {len(merged_m5)}")
    print(f"   Correlação de Preços: {corr:.6f}")
    print(f"   Diferença média de Preço (spread de cotação broker): ${diff_close.mean():.3f} USD")
    print(f"   Diferença máxima de Preço: ${diff_close.max():.3f} USD")
    
    # Processamento de Padrões
    print("\n4. Detectando padrões de Candlestick nos datasets...")
    mt5_m5_pat = detect_patterns(mt5_m5)
    mt5_m15_pat = detect_patterns(mt5_m15)
    tv_m5_pat = detect_patterns(tv_m5)
    tv_m15_pat = detect_patterns(tv_m15)
    
    modes = ["pure", "trend_filtered", "high_precision"]
    results = {}
    
    print("\n5. Executando testes minuciosos de backtesting...")
    # Teste no MT5 M5
    for m in modes:
        tdf = backtest_engine(mt5_m5_pat, mode=m, rr=1.5)
        metrics = calculate_metrics(tdf)
        results[f"MT5_M5_{m}"] = metrics
        print(f"   [MT5 M5 | {m:15s}] Trades: {metrics['total_trades']:4d} | WinRate: {metrics['win_rate']:5.2f}% | PF: {metrics['profit_factor']:4.2f} | Net%: {metrics['net_profit_pct']:+6.2f}% | MaxDD: {metrics['max_drawdown']:5.2f}% | Exp(R): {metrics['expectancy_r']:+.3f}")
        
    # Teste no MT5 M15
    for m in modes:
        tdf = backtest_engine(mt5_m15_pat, mode=m, rr=1.5)
        metrics = calculate_metrics(tdf)
        results[f"MT5_M15_{m}"] = metrics
        print(f"   [MT5 M15 | {m:15s}] Trades: {metrics['total_trades']:4d} | WinRate: {metrics['win_rate']:5.2f}% | PF: {metrics['profit_factor']:4.2f} | Net%: {metrics['net_profit_pct']:+6.2f}% | MaxDD: {metrics['max_drawdown']:5.2f}% | Exp(R): {metrics['expectancy_r']:+.3f}")

    # Teste no TradingView M5
    for m in modes:
        tdf = backtest_engine(tv_m5_pat, mode=m, rr=1.5)
        metrics = calculate_metrics(tdf)
        results[f"TV_M5_{m}"] = metrics
        print(f"   [TV M5  | {m:15s}] Trades: {metrics['total_trades']:4d} | WinRate: {metrics['win_rate']:5.2f}% | PF: {metrics['profit_factor']:4.2f} | Net%: {metrics['net_profit_pct']:+6.2f}% | MaxDD: {metrics['max_drawdown']:5.2f}% | Exp(R): {metrics['expectancy_r']:+.3f}")
        
    # Salvar resultados e gerar gráfico comparativo
    out_dir = r"C:\Users\Vini_Burgo\.gemini\antigravity\brain\adf2645a-de07-4126-86e3-a5dabf26ac21"
    
    # Plotar Curvas de Capital
    fig, axes = plt.subplots(1, 2, figsize=(15, 6))
    
    # Gráfico 1: MT5 M5 Comparativo
    axes[0].plot(results["MT5_M5_pure"]["curve"], label=f"Ingênuo (PF: {results['MT5_M5_pure']['profit_factor']})", color="red", linestyle="--")
    axes[0].plot(results["MT5_M5_trend_filtered"]["curve"], label=f"Tendência (PF: {results['MT5_M5_trend_filtered']['profit_factor']})", color="orange")
    axes[0].plot(results["MT5_M5_high_precision"]["curve"], label=f"Alta Precisão (PF: {results['MT5_M5_high_precision']['profit_factor']})", color="green", linewidth=2.5)
    axes[0].set_title("XAUUSD M5 (MetaTrader 5) - Curva de Capital por Modelo")
    axes[0].set_xlabel("Número de Operações")
    axes[0].set_ylabel("Saldo ($)")
    axes[0].legend()
    axes[0].grid(True, alpha=0.3)
    
    # Gráfico 2: MT5 M15 Comparativo
    axes[1].plot(results["MT5_M15_pure"]["curve"], label=f"Ingênuo (PF: {results['MT5_M15_pure']['profit_factor']})", color="red", linestyle="--")
    axes[1].plot(results["MT5_M15_trend_filtered"]["curve"], label=f"Tendência (PF: {results['MT5_M15_trend_filtered']['profit_factor']})", color="orange")
    axes[1].plot(results["MT5_M15_high_precision"]["curve"], label=f"Alta Precisão (PF: {results['MT5_M15_high_precision']['profit_factor']})", color="green", linewidth=2.5)
    axes[1].set_title("XAUUSD M15 (MetaTrader 5) - Curva de Capital por Modelo")
    axes[1].set_xlabel("Número de Operações")
    axes[1].set_ylabel("Saldo ($)")
    axes[1].legend()
    axes[1].grid(True, alpha=0.3)
    
    plt.tight_layout()
    chart_path = os.path.join(out_dir, "xauusd_backtest_comparison.png")
    plt.savefig(chart_path, dpi=150)
    plt.close()
    print(f"\nGráfico salvo em: {chart_path}")
    
    # Salvar resumo JSON
    # Remove curve for json serialization
    json_res = {k: {kk: vv for kk, vv in v.items() if kk != "curve"} for k, v in results.items()}
    with open(os.path.join(out_dir, "xauusd_results.json"), "w") as f:
        json.dump(json_res, f, indent=2)

if __name__ == "__main__":
    asyncio.run(main())
