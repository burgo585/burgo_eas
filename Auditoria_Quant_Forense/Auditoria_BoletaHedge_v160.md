# Relatório Forense de Auditoria Quantitativa: BoletaHedge.mq5 (v1.60)
**Data da Auditoria:** 27 de Outubro de 2026  
**Auditor:** Antigravity Quant Forensic Auditor (Protocolo Sunrise)  
**Ativo-Alvo:** XAUUSD / Forex / CFDs em MetaTrader 5 (Hedging Mode)  
**Arquivo Inspecionado:** `c:\Users\Vini_Burgo\Downloads\BoletaHedge.mq5`

---

## 1. Painel de Realidade e Risco de Ruína (Protocolo Sunrise)

| Métrica de Realidade Forense | Valor Auditado | Significado Prático para o seu Bolso |
| :--- | :---: | :--- |
| **Veredito Forense** | **REPROVADO PARA PRODUÇÃO SEM CORREÇÕES CRÍTICAS** | O código possui bugs graves de execução concorrente e risco de ruína por remoção de Stop Loss. |
| **Risco de Falência por Alargamento de Spread / Swap** | **MUITO ALTO (Hedge Crônico)** | A trava não congela perdas: em swap noturno e abertura de spread (rollover), a conta sangra diariamente e pode tomar Stop-Out. |
| **Segurança Operacional em Falha de Trava** | **CRÍTICA (Zero)** | A função `Travar()` apaga todos os Stop Losses antes de saber se a ordem de hedge foi executada com sucesso. Se o broker rejeitar, a conta fica desprotegida. |
| **Confiabilidade do Módulo de Fechamento (CloseBy)** | **INCONSISTENTE (Bug de Duplicação)** | `GroupStep()` não atualiza timestamp em CloseBy, disparando ordens a mercado duplicadas nas mesmas posições no tick seguinte. |
| **Sensibilidade a Slippage nos Alvos** | **EXTREMA** | Alvo de US$ 0,30 no grupo e US$ 0,01 na cesta são engolidos pela slippage e spread, fechando em prejuízo real. |

---

## 2. Diagnóstico Executivo

A automação `BoletaHedge.mq5` (v1.60) foi concebida para atuar como ferramenta de recuperação de drawdown, implementando:
1. **Trava Delta Neutro**: Igualar lotes de compra e venda (`IsLocked()`).
2. **Desalavancagem Cirúrgica no 0 a 0**: Fechar gradualmente posições perdedoras usando o lucro de "pernas" adicionais ou redução de lote.
3. **Mecanismo Close By**: Liquidação cruzada sem pagamento duplo de spread.

Embora o design conceitual da interface gráfica seja sofisticado, a implementação de baixo nível apresenta **3 bugs críticos de execução**, **2 falhas conceituais graves de microestrutura de mercado** e **1 desconexão de integração com a BoletaScalping**. 

A automação **NÃO DEVE** ser operada em conta real com dinheiro real antes da aplicação dos reparos detalhados a seguir.

---

## 3. Detalhamento Forense das Vulnerabilidades Encontradas

### [VULNERABILIDADE 1 - CRÍTICA] `InpLockStripStops`: Remoção Incondicional de SL/TP antes da Confirmação da Trava
- **Linhas de Código:** 275-306 em `Travar()`
- **Mecanismo do Erro:**
  Na linha 280, o laço percorre todas as posições e remove seus SLs e TPs (`g_trade.PositionModify(ticket, 0.0, 0.0)`). Somente após isso (linha 299) é que o EA tenta enviar a ordem de contra-posição (`g_trade.Sell` ou `g_trade.Buy` a mercado).
- **Impacto Financeiro:** Se a ordem de trava for rejeitada pelo broker (por margem livre insuficiente, slippage superior a 20 pontos, spread fora dos parâmetros, requote ou volatilidade de notícias), as posições abertas já tiveram seus Stop Losses apagados. A conta fica 100% exposta, transformando um risco controlado num Stop-Out catastrófico.

### [VULNERABILIDADE 2 - CRÍTICA] Disparo Duplicado de Fechamento por Ausência de Registro em `CloseBy`
- **Linhas de Código:** 616-655 em `GroupStep()`
- **Mecanismo do Erro:**
  Quando `CloseByAllowed()` é verdadeiro, o EA chama `g_trade.PositionCloseBy(g_group[bi], g_group[si])`. Porém, o array `g_group_sent` **não é preenchido para essas ordens**.
  No mesmo ciclo ou no próximo tick (antes de a resposta assíncrona do servidor atualizar o cache local do terminal), o laço seguinte (linhas 646-655) executa `GroupRemaining(i)`. Como a posição ainda consta aberta no cache, e `GroupRecentlySent` retorna falso, o EA **tenta fechar novamente a mesma posição a mercado** via `PositionClose` ou `PositionClosePartial`.
- **Impacto Financeiro:** Erros `TRADE_RETCODE_FROZEN`, `TRADE_RETCODE_REJECT` e sobrecarga de requisições à corretora, podendo levar a congelamento do terminal ou rejeição da conta por flood de ordens.

### [VULNERABILIDADE 3 - ALTA] Cegueira Temporal em `TrackCycle()` (`+1 ms`)
- **Linhas de Código:** 358-372 e 429
- **Mecanismo do Erro:**
  Ao identificar a trava, a linha 359 define:
  `g_bal_msc = tick.time_msc + 1;`
  Quando uma nova perna é aberta no mesmo tick pelo trader ou botão, o servidor atribui a ela `POSITION_TIME_MSC == tick.time_msc`. Na linha 429, a verificação `g_pos[i].time_msc >= g_cycle_start_msc` falha (pois `tick.time_msc < tick.time_msc + 1`).
- **Impacto Financeiro:** A perna recém-aberta é desconsiderada como "perna" e passa a ser classificada como parte da trava-base, induzindo o algoritmo do 0 a 0 a fechar o lado errado ou calcular um saldo distorcido.

### [VULNERABILIDADE 4 - ALTA] Paradoxo da Sugestão (`LegSuggestion`) em Mercados Tendenciais
- **Linhas de Código:** 528-534
- **Mecanismo do Erro:**
  `buy = (g_buy_net < g_sell_net);`
  Se a compra está perdendo mais que a venda, o mercado está em forte queda. A função sugere `SUG_CUT` (reduzir as vendas que estão ganhando) ou `SUG_LEG` (comprar mais).
- **Impacto Financeiro:** Em um crash de mercado ou forte tendência direcional, cortar a posição protetora ou comprar contra o fluxo viola o princípio básico de contenção de dano. Retirar o lado vencedor durante uma tendência acelera a quebra da conta.

### [VULNERABILIDADE 5 - MÉDIA/ALTA] Alvos Microscópicos Devorados por Slippage e Custos
- **Linhas de Código:** 47 (`InpGroupMinProfit = 0.30`) e 58 (`InpBasketMinProfit = 0.01`)
- **Mecanismo do Erro:**
  Alvos de US$ 0,30 ou US$ 0,01 não resistem ao bounce do bid/ask no momento em que 2 a 4 posições são liquidadas a mercado. Uma variação de meio pip na execução reverte o saldo do grupo para negativo.
- **Impacto Financeiro:** A conta fecha "no 0 a 0" na teoria, mas registra perdas líquidas recorrentes na prática devido à slippage de saída.

### [VULNERABILIDADE 6 - INTEGRAÇÃO] Variável Global Fantasma (`BHedge_LOCK_`)
- **Linhas de Código:** 35 e 708-715
- **Mecanismo do Erro:**
  A `BoletaHedge` atualiza `BHedge_LOCK_<sym>` assumindo que a `BoletaScalping` suspenderá trailing stops. Contudo, a auditoria no código da `BoletaScalping.mq5` revelou que essa variável sequer é monitorada pela boleta principal.
- **Impacto:** Conflito de gestão simultânea de posições entre os dois EAs no mesmo ativo.

### [VULNERABILIDADE 7 - PERFORMANCE] Sobrecarga de Renderização Gráfica (`ChartRedraw`)
- **Linhas de Código:** 914, 934-968, 1034-1036
- **Mecanismo do Erro:**
  `ChartRedraw(0)` é executado a cada tick dentro de `Process()`. Em momentos de alta volatilidade (50-100 ticks/seg), o terminal sofre gargalo de renderização na interface gráfica, elevando a latência de execução.

---

## 4. Recomendações e Plano de Correção

1. **Inversão da Ordem na Trava**: Primeiro confirmar a execução da ordem de hedge com `TradeOk()`; somente após o preenchimento bem-sucedido, proceder com a remoção dos Stop Losses.
2. **Controle de Bloqueio em CloseBy**: Registrar imediatamente os tickets `bi` e `si` em `g_group_sent` com timestamp atual após a chamada de `PositionCloseBy`.
3. **Ajuste na Marcação de Milissegundos**: Utilizar `tick.time_msc` sem soma arbitrária de milissegundos e usar tolerância `>= g_cycle_start_msc - 100` ou sinalizar pernas por Magic Number / Ordem Ticket.
4. **Alvos Mínimos Realistas**: Elevar o piso do grupo para valor que cubra folga de spread de pelo menos 1 a 2 spreads completos do ativo (ex: no mínimo US$ 1,50 a US$ 3,00 para 0.01 de XAUUSD).
5. **Throttling de Interface Gráfica**: Limitar chamadas a `UpdatePanel()` e `ChartRedraw()` a intervalos de no mínimo 100ms a 200ms.
6. **Integração Real com BoletaScalping**: Implementar a verificação de `GlobalVariableCheck("BHedge_LOCK_" + _Symbol)` nas funções de BreakEven e Trailing Stop da `BoletaScalping.mq5`.
