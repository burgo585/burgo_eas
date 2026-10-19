import asyncio
import json
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import MetaTrader5 as mt5

# Importar o detector de padrões
from run_thorough_tests import fetch_mt5_candles, detect_patterns

def run_profit_maximizer_backtest(df, rr=2.5, use_be=True, be_trigger_r=1.2, use_trailing=True, 
                                  session_filter=True, min_vol_ratio=1.2, allow_partial=True):
    """
    Simulador avançado para maximizar lucros no XAUUSD:
    - Relação Risco:Retorno customizada (ex: 2.0, 2.5, 3.0, 4.0)
    - Break-Even Dinâmico
    - Trailing Stop Dinâmico por estrutura de barras
    - Filtro de Sessão Nobre (Londres + Nova York: 10:00 às 20:00 GMT+3 no VTMarkets)
    - Parciais (50% em 1.5R, 50% no alvo longo)
    """
    trades = []
    n = len(df)
    spread = 0.30 # $0.30 de spread no ouro (30 pts)
    
    for i in range(50, n - 25):
        # 1. Filtro de Sessão (Horário de maior liquidez e amplitude)
        if session_filter:
            hora = df["time"].iloc[i].hour
            # Horário do servidor VTMarkets: Londres abre ~10h, NY até ~20h
            if hora < 10 or hora > 20:
                continue
                
        c = df["close"].iloc[i]
        o = df["open"].iloc[i]
        h = df["high"].iloc[i]
        l = df["low"].iloc[i]
        vol = df["volume"].iloc[i]
        vol_avg = df["vol_ma20"].iloc[i]
        ema50 = df["ema50"].iloc[i]
        
        # Filtro de Volume Institucional
        if vol < min_vol_ratio * vol_avg:
            continue
            
        # Padrões mais fortes selecionados
        buy_candlestick = (
            df["bullish_engulfing"].iloc[i] or
            df["three_outside_up"].iloc[i] or
            df["hammer"].iloc[i] or
            df["tweezer_bottom"].iloc[i]
        )
        
        sell_candlestick = (
            df["bearish_engulfing"].iloc[i] or
            df["three_outside_down"].iloc[i] or
            df["hanging_man"].iloc[i] or
            df["tweezer_top"].iloc[i]
        )
        
        # Alinhamento com tendência
        buy_signal = buy_candlestick and (c > ema50)
        sell_signal = sell_candlestick and (c < ema50)
        
        if not buy_signal and not sell_signal:
            continue
            
        direction = "BUY" if buy_signal else "SELL"
        entry_price = df["open"].iloc[i+1]
        
        # Stop estrutural
        buffer = 0.50
        if direction == "BUY":
            entry_price += (spread / 2.0)
            sl = min(df["low"].iloc[i], df["low"].iloc[i-1]) - buffer
            risk = entry_price - sl
            if risk < 0.60 or risk > 12.0:
                continue
            tp_final = entry_price + (risk * rr)
            tp_partial = entry_price + (risk * 1.5)
        else:
            entry_price -= (spread / 2.0)
            sl = max(df["high"].iloc[i], df["high"].iloc[i-1]) + buffer
            risk = sl - entry_price
            if risk < 0.60 or risk > 12.0:
                continue
            tp_final = entry_price - (risk * rr)
            tp_partial = entry_price - (risk * 1.5)
            
        current_sl = sl
        partial_hit = False
        outcome = None
        exit_r = 0.0
        
        # Simular barra a barra
        for k in range(i+1, min(i+120, n)):
            bar_h = df["high"].iloc[k]
            bar_l = df["low"].iloc[k]
            bar_c = df["close"].iloc[k]
            
            if direction == "BUY":
                # Verificar Break-Even
                if use_be and not partial_hit:
                    if bar_h >= entry_price + (risk * be_trigger_r):
                        current_sl = max(current_sl, entry_price + 0.10) # BE protegido com spread
                        
                # Verificar Parcial
                if allow_partial and not partial_hit:
                    if bar_h >= tp_partial:
                        partial_hit = True
                        current_sl = max(current_sl, entry_price + 0.20) # Trava no lucro
                        
                # Trailing Stop dinâmico por mínima da barra anterior
                if use_trailing and partial_hit:
                    trail_level = df["low"].iloc[k-1] - buffer
                    if trail_level > current_sl:
                        current_sl = trail_level
                        
                # Testar Saídas
                if bar_l <= current_sl:
                    # Bateu no Stop / Trailing / BE
                    if partial_hit:
                        outcome = "PARTIAL_WIN"
                        # 50% realizou em 1.5R, 50% saiu no trailing
                        trailing_r = (current_sl - entry_price) / risk
                        exit_r = 0.5 * 1.5 + 0.5 * max(trailing_r, 0.0)
                    else:
                        if current_sl >= entry_price:
                            outcome = "BREAKEVEN"
                            exit_r = 0.05
                        else:
                            outcome = "LOSS"
                            exit_r = -1.0
                    break
                    
                elif bar_h >= tp_final:
                    outcome = "FULL_WIN"
                    if allow_partial and partial_hit:
                        exit_r = 0.5 * 1.5 + 0.5 * rr
                    else:
                        exit_r = rr
                    break
                    
            else: # SELL
                if use_be and not partial_hit:
                    if bar_l <= entry_price - (risk * be_trigger_r):
                        current_sl = min(current_sl, entry_price - 0.10)
                        
                if allow_partial and not partial_hit:
                    if bar_l <= tp_partial:
                        partial_hit = True
                        current_sl = min(current_sl, entry_price - 0.20)
                        
                if use_trailing and partial_hit:
                    trail_level = df["high"].iloc[k-1] + buffer
                    if trail_level < current_sl:
                        current_sl = trail_level
                        
                if bar_h >= current_sl:
                    if partial_hit:
                        outcome = "PARTIAL_WIN"
                        trailing_r = (entry_price - current_sl) / risk
                        exit_r = 0.5 * 1.5 + 0.5 * max(trailing_r, 0.0)
                    else:
                        if current_sl <= entry_price:
                            outcome = "BREAKEVEN"
                            exit_r = 0.05
                        else:
                            outcome = "LOSS"
                            exit_r = -1.0
                    break
                    
                elif bar_l <= tp_final:
                    outcome = "FULL_WIN"
                    if allow_partial and partial_hit:
                        exit_r = 0.5 * 1.5 + 0.5 * rr
                    else:
                        exit_r = rr
                    break
                    
        if outcome is not None:
            trades.append({
                "entry_time": df["time"].iloc[i+1],
                "direction": direction,
                "outcome": outcome,
                "exit_r": exit_r
            })
            
    tdf = pd.DataFrame(trades)
    return tdf

def evaluate(tdf, initial_capital=10000.0, risk_pct=1.0):
    if tdf.empty:
        return {"trades": 0, "win_rate": 0, "pf": 0, "net_pct": 0, "max_dd": 0, "exp_r": 0, "curve": [initial_capital]}
    
    wins = tdf[tdf["exit_r"] > 0]
    losses = tdf[tdf["exit_r"] < 0]
    total = len(tdf)
    win_rate = (len(wins) / total) * 100.0
    
    g_profit = wins["exit_r"].sum()
    g_loss = abs(losses["exit_r"].sum())
    pf = (g_profit / g_loss) if g_loss > 0 else 99.0
    
    balance = initial_capital
    curve = [balance]
    peak = balance
    max_dd = 0.0
    
    for _, t in tdf.iterrows():
        dollar_risk = balance * (risk_pct / 100.0)
        gain = dollar_risk * t["exit_r"]
        balance += gain
        curve.append(balance)
        if balance > peak:
            peak = balance
        dd = (peak - balance) / peak * 100.0
        if dd > max_dd:
            max_dd = dd
            
    net_pct = ((balance - initial_capital) / initial_capital) * 100.0
    exp_r = tdf["exit_r"].mean()
    
    return {
        "trades": total,
        "win_rate": round(win_rate, 2),
        "pf": round(pf, 2),
        "net_pct": round(net_pct, 2),
        "max_dd": round(max_dd, 2),
        "exp_r": round(exp_r, 3),
        "curve": curve
    }

def main():
    print("=== OTIMIZAÇÃO AVANÇADA DE LUCRO PARA XAUUSD ===")
    from test_tv import fetch_tradingview_bars
    tv_m15 = asyncio.run(fetch_tradingview_bars("OANDA:XAUUSD", "15", 3000))
    if tv_m15.empty:
        print("Erro: não foi possível obter dados do TradingView.")
        return
    print(f"Dados obtidos do TradingView (OANDA:XAUUSD): {len(tv_m15)} barras M15.")
    mt5_m15 = detect_patterns(tv_m15)
    
    # Testar grade de parâmetros
    configs = [
        {"name": "1. Base Anterior (Fixo 1.5R, Sem Filtro Sessão)", "rr": 1.5, "use_be": False, "use_trailing": False, "session_filter": False, "allow_partial": False},
        {"name": "2. Alvo Longo 2.5R + Filtro Horário Nobre", "rr": 2.5, "use_be": True, "use_trailing": False, "session_filter": True, "allow_partial": False},
        {"name": "3. Alvo Longo 3.0R + Break-Even em 1.2R", "rr": 3.0, "use_be": True, "use_trailing": False, "session_filter": True, "allow_partial": False},
        {"name": "4. Estrutura Pro: Parcial em 1.5R + Alvo 3.0R + Trailing", "rr": 3.0, "use_be": True, "use_trailing": True, "session_filter": True, "allow_partial": True},
        {"name": "5. Explosão de Ouro: Parcial em 2.0R + Alvo 4.0R + Trailing", "rr": 4.0, "use_be": True, "use_trailing": True, "session_filter": True, "allow_partial": True},
    ]
    
    res_list = []
    for c in configs:
        tdf = run_profit_maximizer_backtest(
            mt5_m15, rr=c["rr"], use_be=c["use_be"], use_trailing=c["use_trailing"],
            session_filter=c["session_filter"], allow_partial=c["allow_partial"]
        )
        metrics = evaluate(tdf)
        metrics["name"] = c["name"]
        res_list.append(metrics)
        print(f"\n--- {c['name']} ---")
        print(f"Trades: {metrics['trades']} | Win Rate: {metrics['win_rate']}% | Profit Factor: {metrics['pf']}")
        print(f"Retorno Líquido: {metrics['net_pct']:+.2f}% | Max Drawdown: {metrics['max_dd']}% | Exp(R): {metrics['exp_r']:+.3f}")
        
    # Plotar comparação das novas curvas de capital
    plt.figure(figsize=(12, 6))
    for r in res_list:
        plt.plot(r["curve"], label=f"{r['name']} (Retorno: {r['net_pct']:+.1f}% | PF: {r['pf']})")
    plt.title("XAUUSD M15 - Comparação de Estratégias de Maximização de Lucro")
    plt.xlabel("Operações")
    plt.ylabel("Capital ($)")
    plt.legend()
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    
    out_img = r"C:\Users\Vini_Burgo\.gemini\antigravity\brain\adf2645a-de07-4126-86e3-a5dabf26ac21\xauusd_profit_maximization.png"
    plt.savefig(out_img, dpi=150)
    plt.close()
    print(f"\nGráfico salvo em: {out_img}")

if __name__ == "__main__":
    main()
