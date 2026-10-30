# -*- coding: utf-8 -*-
"""
Teste Forense com Filtros de Contexto de Leomar:
1. Filtro de Sessão Institucional (Londres e Nova York - 08:00 às 18:00 GMT/Servidor)
2. Filtro da Média Móvel de 200 (Alinhamento de Tendência ou Extremo de 400+ pts)
3. Trava Diária de Meta e Limite de Trades (Máx 2 trades por dia, encerra após bater a meta)
"""
import sys
import os
import pandas as pd
import numpy as np

PARQUET_PATH = r"C:\Users\Vini_Burgo\Documents\burgo_eas\Pesquisa_e_Estudos\testes_microestrutura\xauusd_m5_xm_real_ticks.parquet"

def run_context_backtest():
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
    pos_tp = 0.0
    pos_open_time = None
    pos_open_idx = 0
    
    current_day = None
    daily_trades_count = 0
    daily_target_hit = False
    daily_pnl = 0.0
    
    lot_size = 0.10
    commission_per_lot = 6.0
    slippage_usd = 0.05
    min_wick_usd = 0.25
    min_body_usd = 0.40
    risk_reward = 3.0
    
    for i in range(250, n):
        check_idx = i - k
        if check_idx >= 0:
            if is_sh[check_idx]:
                confirmed_highs.append((check_idx, highs[check_idx], times[check_idx]))
            if is_sl[check_idx]:
                confirmed_lows.append((check_idx, lows[check_idx], times[check_idx]))
        if len(confirmed_highs) > 20: confirmed_highs = confirmed_highs[-20:]
        if len(confirmed_lows) > 20: confirmed_lows = confirmed_lows[-20:]
        
        c_time = pd.Timestamp(times[i])
        day_str = c_time.strftime("%Y-%m-%d")
        
        if day_str != current_day:
            current_day = day_str
            daily_trades_count = 0
            daily_target_hit = False
            daily_pnl = 0.0
            
        c_open = opens[i]
        c_high = highs[i]
        c_low = lows[i]
        c_close = closes[i]
        c_spread = spreads[i]
        c_ema = emas[i]
        
        # Gestão da posição aberta
        if in_pos:
            holding_days = (c_time - pos_open_time).total_seconds() / 86400.0
            swap_cost = holding_days * (-18.0 * lot_size if pos_type == "BUY" else 10.0 * lot_size)
            commission = commission_per_lot * lot_size
            
            hit_tp = False
            hit_sl = False
            exit_price = 0.0
            
            if pos_type == "BUY":
                if c_close >= c_open:
                    if c_low <= pos_sl: hit_sl = True; exit_price = pos_sl - slippage_usd
                    elif c_high >= pos_tp: hit_tp = True; exit_price = pos_tp
                else:
                    if c_high >= pos_tp: hit_tp = True; exit_price = pos_tp
                    if c_low <= pos_sl: hit_sl = True; exit_price = pos_sl - slippage_usd
            elif pos_type == "SELL":
                if c_close <= c_open:
                    if c_high + c_spread >= pos_sl: hit_sl = True; exit_price = pos_sl + slippage_usd
                    elif c_low + c_spread <= pos_tp: hit_tp = True; exit_price = pos_tp
                else:
                    if c_low + c_spread <= pos_tp: hit_tp = True; exit_price = pos_tp
                    if c_high + c_spread >= pos_sl: hit_sl = True; exit_price = pos_sl + slippage_usd
                    
            if hit_tp or hit_sl:
                if hit_tp and hit_sl:
                    exit_price = pos_sl - slippage_usd if pos_type == "BUY" else pos_sl + slippage_usd
                    hit_tp = False; hit_sl = True
                    
                mult = 100.0 * lot_size
                gross_pnl = (exit_price - pos_entry) * mult if pos_type == "BUY" else (pos_entry - exit_price) * mult
                net_pnl = gross_pnl + swap_cost - commission
                
                daily_pnl += net_pnl
                daily_trades_count += 1
                
                # Se bateu meta no dia (+US$ 300 ou 3:1), trava novas operações no dia
                if daily_pnl >= 300.0:
                    daily_target_hit = True
                    
                trades.append({
                    "open_time": pos_open_time,
                    "close_time": c_time,
                    "type": pos_type,
                    "net_pnl": net_pnl,
                    "is_win": net_pnl > 0
                })
                in_pos = False
                continue
                
        # Abertura de ordens com Filtros de Contexto de Leomar
        if not in_pos and not daily_target_hit and daily_trades_count < 2:
            # 1. Filtro de Horário: Sessão de Londres e NY (08:00 às 17:00)
            hour = c_time.hour
            if hour < 8 or hour > 17:
                continue
                
            if len(confirmed_highs) < 2 or len(confirmed_lows) < 2:
                continue
                
            last_high = confirmed_highs[-1][1]
            last_low = confirmed_lows[-1][1]
            dist_ema = c_close - c_ema # positivo se acima, negativo se abaixo
            
            # COMPRA: Pivô de alta + Alinhado com a Média 200 OU Extremo de Sobrevenda (Reversão em V afastado > $4.00 da 200)
            if c_close > last_high and c_open <= last_high and (c_close - c_open) >= min_body_usd:
                lower_wick = min(c_open, c_close) - c_low
                if lower_wick >= min_wick_usd:
                    # Filtro de Contexto de Tendência:
                    # (a) A favor da tendência (Close > EMA 200)
                    # (b) OU Reversão de Extremo (Preço abaixo da 200 por mais de $4.00)
                    if (c_close > c_ema) or (c_ema - c_close >= 4.0):
                        sl_level = last_low - 0.20
                        risk = c_close - sl_level
                        if 0.50 <= risk <= 6.0:
                            in_pos = True
                            pos_type = "BUY"
                            pos_entry = c_close + (c_spread / 2.0) + slippage_usd
                            pos_sl = sl_level
                            pos_tp = c_close + (risk * risk_reward)
                            pos_open_time = c_time
                            pos_open_idx = i
                            continue
                            
            # VENDA: Pivô de baixa + Alinhado com a Média 200 OU Extremo de Sobrecompra (Reversão afastado > $4.00 acima da 200)
            if c_close < last_low and c_open >= last_low and (c_open - c_close) >= min_body_usd:
                upper_wick = c_high - max(c_open, c_close)
                if upper_wick >= min_wick_usd:
                    if (c_close < c_ema) or (c_close - c_ema >= 4.0):
                        sl_level = last_high + 0.20
                        risk = sl_level - c_close
                        if 0.50 <= risk <= 6.0:
                            in_pos = True
                            pos_type = "SELL"
                            pos_entry = c_close - (c_spread / 2.0) - slippage_usd
                            pos_sl = sl_level
                            pos_tp = c_close - (risk * risk_reward)
                            pos_open_time = c_time
                            pos_open_idx = i
                            continue

    df_t = pd.DataFrame(trades)
    print(f"\n=======================================================")
    print(f"RESULTADOS COM CONTEXTO DE LEOMAR (Sessão 08-17h + Tendência/Extremo 200 + Meta Diária):")
    print(f"=======================================================")
    if df_t.empty:
        print("Nenhum trade realizado.")
        return
        
    df_t["cum_pnl"] = df_t["net_pnl"].cumsum()
    wins = df_t[df_t["is_win"]]
    losses = df_t[~df_t["is_win"]]
    total = len(df_t)
    wr = len(wins) / total * 100.0
    gp = wins["net_pnl"].sum() if not wins.empty else 0
    gl = abs(losses["net_pnl"].sum()) if not losses.empty else 1
    pf = gp / gl
    payoff = (wins["net_pnl"].mean() / abs(losses["net_pnl"].mean())) if not losses.empty and not wins.empty else 0
    net = df_t["net_pnl"].sum()
    peak = df_t["cum_pnl"].cummax()
    dd = (peak - df_t["cum_pnl"]).max()
    
    print(f"Total de Trades: {total}")
    print(f"Taxa de Acerto (Win Rate): {wr:.2f}%")
    print(f"Profit Factor: {pf:.2f}")
    print(f"Payoff (Média Ganho / Média Perda): {payoff:.2f} : 1")
    print(f"Lucro Líquido Real: +US$ {net:,.2f}")
    print(f"Pior Drawdown: -US$ {dd:,.2f}")
    
    return {
        "total": total,
        "wr": wr,
        "pf": pf,
        "payoff": payoff,
        "net": net,
        "dd": dd
    }

if __name__ == "__main__":
    run_context_backtest()
