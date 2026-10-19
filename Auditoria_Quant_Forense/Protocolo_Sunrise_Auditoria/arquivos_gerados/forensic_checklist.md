# Checklist de Auditoria Forense Quantitativa e Microestrutura (Protocolo Sunrise)

## 1. Falhas Clássicas de Simulação OHLC (Python / MQL5)
1. **Wick-Top/Bottom Take-Profit Teleportation**:
   - **Erro**: Avaliar `if buy_profit >= target_usd: balance += buy_profit` nos 4 pontos discretos `[Open, Low, High, Close]`.
   - **Consequência**: Em barras voláteis (ex: XAUUSD M15 com $20 de amplitude), o simulador salta de `Low` para `High` e credita $80 de lucro quando o robô real teria fechado a ordem assim que o lucro atingiu $3.00.
   - **Correção Obrigatória**: `balance += target_usd` (descontando slippage de saída).
2. **Wick-Bottom Grid Fill & Single-Order Cap**:
   - **Erro**: Avaliar `if ask < lowest_buy - dist: buy_positions.append({'price': ask})` apenas uma vez em `price = Low`.
   - **Consequência**: (a) Abre no máximo 1 ordem por vela mesmo que a vela despencasse 4 níveis de grade, reduzindo artificialmente o lote aberto e ocultando o Stop-Out; (b) Compra no preço exato da mínima absoluta do pavio (`Low`), em vez do preço onde o nível da grade foi rompido (`lowest_buy - dist`).
   - **Correção Obrigatória**: Usar `while len(positions) < max_orders and ask_low <= trigger_price:` preenchendo cada ordem em `min(ask_open, trigger_price) + slippage`, e calcular o pior Equity e Nível de Margem no `Low` com **todas** as ordens abertas.
3. **Intrabar Time Travel (`High` após `Low` em velas de baixa)**:
   - **Erro**: Forçar a sequência `Open -> Low -> High -> Close` em todas as velas, inclusive velas de baixa (`Close < Open`).
   - **Consequência**: Em uma vela de crash (`Open=5384, High=5386, Low=5102, Close=5189`), o simulador abre toda a grade de compras durante a queda até `5102` e, no passo seguinte, faz o preço "viajar ao passado" até `High=5386`, fechando todas as compras no lucro dentro da própria vela de crash!
   - **Correção Obrigatória**: Em velas de baixa (`Close < Open`), o caminho é estritamente `Open -> High -> Low -> Close`. Ordens abertas no `Low` só podem ser avaliadas no `Close`. Em modo conservador, aplicar `Open -> High -> Low -> Close` para compras e `Open -> Low -> High -> Close` para vendas.

## 2. Vazamento de Futuro (Data Leakage & Lookahead Bias)
1. **Indicadores na Barra `t` sem `.shift(1)`**:
   - **Erro**: `df['ema200'] = df['close'].ewm(span=200).mean()` lido no passo `Open` da barra `t`.
   - **Correção Obrigatória**: `df['ema200'] = df['close'].ewm(span=200).mean().shift(1)`.
2. **Machine Learning em Séries Temporais**:
   - Proibido `train_test_split(X, y, shuffle=True)`.
   - Proibido `scaler.fit_transform(X)` antes do corte temporal `train / val / test`.
   - Obrigatório `TimeSeriesSplit` ou Purged Walk-Forward com *embargo period*.

## 3. Custos Operacionais Reais e Risco de Cauda (Grid / Martingale)
1. **Swap Noturno (`SYMBOL_SWAP_LONG` / `SYMBOL_SWAP_SHORT`)**:
   - No Ouro (`XAUUSD`), posições compradas pagam forte *Swap* negativo (ex: `-77.44` pontos/lote/noite na VTMarkets, triplo na quarta-feira). Segurar 0.04 lotes por 1 mês custa mais de US$ 90 apenas em Swap!
2. **Viés de Data de Início (*Start-Date Survivorship Bias*)**:
   - Um teste único começando em uma data favorável onde a conta multiplica antes do primeiro crash mascara 90%+ de risco de ruína.
   - **Correção Obrigatória**: Testar a partida da conta (ex: US$ 100) no dia 1º de cada um dos 30+ meses do histórico e reportar a **Taxa de Falência Mensal (`Stop-Out %`)**.
