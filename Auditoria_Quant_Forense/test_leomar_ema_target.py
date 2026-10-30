# -*- coding: utf-8 -*-
"""
Teste Forense de Reversão para a Média de 200 (O Alvo Ímã de Leomar)
- Condição: Afastamento extremo da Média de 200 (>= $3.00 / 300 pts)
- Gatilho: Pivô de Reversão com Pavio Contrário voltando para a Média
- Alvo (Take Profit): Toque Exato na Média de 200 Períodos!
"""
import sys
import os
import pandas as pd
import numpy as np

PARQUET_PATH = r"C:\Users\Vini_Burgo\Documents\burgo_eas\Pesquisa_e_Estudos\testes_microestrutura\xauusd_m5_xm_real_ticks.parquet"

def run_ema_target_backtest():
    df = pd.read_parquet(PARQUET_PATH).sort_values("time").reset_index(drop=True)
    df["ema_200"] = df["close"].ewm(span=200, adjust=False).mean().shift(1)
    
    k = 3
    n = len(df)
    highs = df["high"].values
    lows = df["low"].values
    
    is_sh = np.zeros(n, dtype=bool)
    is_sl = np.zeros(n, dtype=bool)
    for i in range(k, n - k):
        h_val = highs[i]
        l_val = lows[i]
        if all(highs[i - j] < h_val for j in range(1, k + 1)) and all(highs[i + j] <= h_val for j in range(1, k + 1)):
            is_sh[i] = True
        if all(lows[i - j] > l_val for j in range(1, k + 1)) and all(lows[i + j] >= l_val for j in range(1, k + 1)):
            is_sl[i] = True
            
    times = df["time"].values
    opens = df["open"].values
    closes = df["close"].values
    spreads = df["spread_mean"].values
    emas = df["ema_200"].values
    
    confirmed_highs = []
    confirmed_lows = []
    trades = []
    in_pos = False
    pos_type = None
    pos_entry = 0.0
    pos_sl = 0.0
    pos_open_time = None
    
    lot_size = 0.10
    commission_per_lot = 6.0
    slippage_usd = 0.05
    min_wick_usd = 0.25
    min_body_usd = 0.40
    min_dist_ema = 3.0 # mínimo 300 pontos de afastamento
    
    for i in range(250, n):
        check_idx = i - k
        if check_idx >= 0:
            if is_sh[check_idx]: confirmed_highs.append((check_idx, highs[check_idx], times[check_idx]))
            if is_sl[check_idx]: confirmed_lows.append((check_idx, lows[check_idx], times[check_idx]))
        if len(confirmed_highs) > 20: confirmed_highs = confirmed_highs[-20:]
        if len(confirmed_lows) > 20: confirmed_lows = confirmed_lows[-20:]
        
        c_time = pd.Timestamp(times[i])
        c_open = opens[i]
        c_high = highs[i]
        c_low = lows[i]
        c_close = closes[i]
        c_spread = spreads[i]
        c_ema = emas[i]
        
        if in_pos:
            holding_days = (c_time - pos_open_time).total_seconds() / 86400.0
            swap_cost = holding_days * (-18.0 * lot_size if pos_type == "BUY" else 10.0 * lot_size)
            commission = commission_per_lot * lot_size
            
            hit_tp = False
            hit_sl = False
            exit_price = 0.0
            
            # O Alvo Dinâmico é o toque na EMA 200 atual!
            if pos_type == "BUY":
                # Compra quer atingir a EMA 200 que está acima
                target_ema = c_ema
                if c_close >= c_open:
                    if c_low <= pos_sl: hit_sl = True; exit_price = pos_sl - slippage_usd
                    elif c_high >= target_ema: hit_tp = True; exit_price = target_ema
                else:
                    if c_high >= target_ema: hit_tp = True; exit_price = target_ema
                    if c_low <= pos_sl: hit_sl = True; exit_price = pos_sl - slippage_usd
            elif pos_type == "SELL":
                # Venda quer atingir a EMA 200 que está abaixo
                target_ema = c_ema
                if c_close <= c_open:
                    if c_high + c_spread >= pos_sl: hit_sl = True; exit_price = pos_sl + slippage_usd
                    elif c_low + c_spread <= target_ema: hit_tp = True; exit_price = target_ema
                else:
                    if c_low + c_spread <= target_ema: hit_tp = True; exit_price = target_ema
                    if c_high + c_spread >= pos_sl: hit_sl = True; exit_price = pos_sl + slippage_usd
                    
            if hit_tp or hit_sl:
                if hit_tp and hit_sl:
                    exit_price = pos_sl - slippage_usd if pos_type == "BUY" else pos_sl + slippage_usd
                    hit_tp = False; hit_sl = True
                    
                mult = 100.0 * lot_size
                gross_pnl = (exit_price - pos_entry) * mult if pos_type == "BUY" else (pos_entry - exit_price) * mult
                net_pnl = gross_pnl + swap_cost - commission
                
                trades.append({
                    "open_time": pos_open_time,
                    "close_time": c_time,
                    "net_pnl": net_pnl,
                    "is_win": net_pnl > 0
                })
                in_pos = False
                continue
                
        # Entradas: Afastamento >= min_dist_ema
        if not in_pos and len(confirmed_highs) >= 2 and len(confirmed_lows) >= 2:
            last_high = confirmed_highs[-1][1]
            last_low = confirmed_lows[-1][1]
            
            # COMPRA de Reversão: Preço bem ABAIXO da EMA 200 (c_ema - c_close >= min_dist_ema)
            if (c_ema - c_close) >= min_dist_ema:
                if c_close > last_high and c_open <= last_high and (c_close - c_open) >= min_body_usd:
                    lower_wick = min(c_open, c_close) - c_low
                    if lower_wick >= min_wick_usd:
                        sl_level = last_low - 0.20
                        risk = c_close - sl_level
                        if 0.50 <= risk <= 6.0:
                            in_pos = True
                            pos_type = "BUY"
                            pos_entry = c_close + (c_spread / 2.0) + slippage_usd
                            pos_sl = sl_level
                            pos_open_time = c_time
                            continue
                            
            # VENDA de Reversão: Preço bem ACIMA da EMA 200 (c_close - c_ema >= min_dist_ema)
            if (c_close - c_ema) >= min_dist_ema:
                if c_close < last_low and c_open >= last_low and (c_open - c_close) >= min_body_usd:
                    upper_wick = c_high - max(c_open, c_close)
                    if upper_wick >= min_wick_usd:
                        sl_level = last_high + 0.20
                        risk = sl_level - c_close
                        if 0.50 <= risk <= 6.0:
                            in_pos = True
                            pos_type = "SELL"
                            pos_entry = c_close - (c_spread / 2.0) - slippage_usd
                            pos_sl = sl_level
                            pos_open_time = c_time
                            continue

    df_t = pd.DataFrame(trades)
    print(f"\n=======================================================")
    print(f"RESULTADOS REVERSÃO PARA A MÉDIA DE 200 (Alvo = Toque na 200 EMA):")
    print(f"=======================================================")
    if df_t.empty:
        print("Nenhum trade realizado.")
        return
        
    wins = df_t[df_t["is_win"]]
    losses = df_t[~df_t["is_win"]]
    total = len(df_t)
    wr = len(wins) / total * 100.0
    gp = wins["net_pnl"].sum()
    gl = abs(losses["net_pnl"].sum())
    pf = gp / gl if gl > 0 else 0
    net = df_t["net_pnl"].sum()
    cum = df_t["net_pnl"].cumsum()
    dd = (cum.cummax() - cum).max()
    avg_win = wins["net_pnl"].mean() if not wins.empty else 0
    avg_loss = abs(losses["net_pnl"].mean()) if not losses.empty else 1
    payoff = avg_win / avg_loss if avg_loss > 0 else 0
    
    print(f"Total de Trades: {total}")
    print(f"Taxa de Acerto (Win Rate): {wr:.2f}%")
    print(f"Profit Factor: {pf:.2f}")
    print(f"Payoff (Média Ganho / Média Perda): {payoff:.2f} : 1 (Ganho Médio: ${avg_win:.2f} vs Perda Média: ${avg_loss:.2f})")
    print(f"Resultado Líquido Real: US$ {net:,.2f}")
    print(f"Max Drawdown: US$ {dd:,.2f}")

if __name__ == "__main__":
    run_ema_target_backtest()
