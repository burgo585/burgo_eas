---
description: Guardrail Obrigatório de Auditoria Quantitativa e Microestrutura Forense para qualquer tarefa envolvendo robôs de investimento (EAs MQL4/MQL5), scripts Python de trading, backtests, otimizações ou Machine Learning financeiro.
trigger: always_on
---

# Guardrail Global: Integridade Quantitativa, Microestrutura Forense e Sicofância Zero (Protocolo Sunrise)

Sempre que o usuário solicitar a criação, análise, correção, otimização ou simulação/backtest de estratégias de trading, Expert Advisors (MQL4/MQL5), scripts Python financeiros, Backtrader, PineScript ou modelos de Machine Learning para mercado financeiro:

## 1. Ativação Obrigatória da Skill Global
- Você DEVE ler e seguir as instruções da skill global `quant-forensic-auditor` (`C:\Users\Vini_Burgo\.gemini\config\skills\quant-forensic-auditor\SKILL.md`) e utilizar seus scripts padronizados (`mt5_causal_backtester.py` e `ml_leakage_scanner.py`) antes de apresentar qualquer métrica de lucro ou risco.

## 2. Proibição Absoluta de Ilusões de Backtest (Regras de Engenharia Causal)
É estritamente **PROIBIDO** escrever ou executar simuladores simplificados que contenham qualquer uma das seguintes falhas:
1. **Teletransporte de Take Profit para o Pavio (Wick-Top/Bottom Profit Inflation)**: Nunca adicione o lucro calculado no `High` ou `Low` da barra (`balance += floating_profit`) quando um alvo fixo (`TargetUSD` / `TP`) é atingido. O lucro realizado deve ser estritamente travado no valor exato do gatilho (`TargetUSD`), descontados slippage e comissões.
2. **Compra/Venda no Fundo/Topo do Pavio e Supressão de Grade**: Em estratégias de Grid/Martingale/Preço Médio avaliadas em barras OHLC, nunca use um `if` simples que abre apenas 1 ordem por barra no preço `Low` ou `High`. Use um laço `while` que preencha **todas** as ordens cujos níveis (`ultimo_preco +/- distancia`) foram rompidos ao longo da excursão adversa, registrando o preço exato de cada gatilho (`trigger_price +/- slippage`), e avalie o *Stop-Out* no extremo adverso da vela com **todas** as ordens abertas.
3. **Viagem no Tempo Intrabarra (High-Low-High Time Travel)**:
   - Em velas de baixa (`Close < Open`), o caminho físico é `Open -> High -> Low -> Close`. Ordens de compra abertas durante a queda para o `Low` **jamais** podem ser fechadas com lucro no `High` da mesma vela (que ocorreu no passado), podendo ser avaliadas apenas no `Close`.
   - Em velas de alta (`Close >= Open`), no modo conservador/realista, teste a excursão sem permitir que uma ordem aberta no fundo do pavio `Low` seja encerrada no topo `High` da mesma barra de 15 minutos, e proíba múltiplos giros completos (abrir -> fechar -> reabrir -> fechar) dentro da mesma perna sintética OHLC.
4. **Lookahead Bias em Indicadores e Machine Learning**:
   - Todo indicador técnico (`EMA`, `SMA`, `ATR`, `RSI`, `Bollinger`) usado para decisão dentro da barra `t` DEVE usar `.shift(1)` (barra `t-1` fechada). É proibido ler `row.atr` ou `row.ema` calculados com o `Close`/`High`/`Low` da barra `t` antes do fechamento da barra.
   - Em Machine Learning: proibido `train_test_split(..., shuffle=True)` em séries temporais; proibido `.fit()` ou `.fit_transform()` de `Scaler`/`PCA`/imputers na matriz completa antes do split temporal; proibido features com `.shift(-k)`.
5. **Omissão de Custos Reais da Corretora**:
   - Nunca simule com `swap = 0` ou `commission = 0`. Extraia via API do MetaTrader 5 (`mt5.symbol_info`) o `swap_long`, `swap_short`, `swap_rollover3days` (triplo na quarta-feira), `spread` real, `trade_contract_size` e `leverage` da conta, aplicando comissão ECN realista (mínimo US$ 6,00/lote padrão *round-turn*) e *slippage* (mínimo 1 tick / US$ 0,10 no Ouro).

## 3. Política de Comunicação com o Usuário: Transparência Cirúrgica e Sicofância Zero
- **Proibição de Adjetivos Euforizantes**: Nunca use termos enganosos como *"100% seguro"*, *"zero risco de quebra"*, *"lucro espetacular"*, *"imune a quebras"* ou *"multiplicação garantida"*.
- **Painel Obrigatório de Realidade e Risco de Ruína**: Toda resposta que apresente resultados de backtest ou simulação DEVE exibir em destaque no topo:
  1. **Taxa de Quebra em Meses Aleatórios (*Risk of Ruin %*)**: Resultado do teste da estratégia iniciando no dia 1º de cada mês ao longo de 30+ meses independentes (ex: *"Quebrou a banca de $100 em 29 de 32 meses — 90,6% de chance de falência"*).
  2. **Pior Rebaixamento Flutuante Real (`MaxDD_USD` e `%`)**: A maior queda do Patrimônio Líquido (*Equity*) aberto do topo ao fundo, diferenciando claramente de saldo fechado (*Balance*).
  3. **Custos Ocultos Deduzidos**: Total pago em *Swap* noturno (destacando o custo semanal de carregar ordens presas) + Comissões ECN + Slippage.
  4. **Banca Mínima Realista para Sobrevivência**: O capital mínimo real necessário para suportar o maior choque histórico do ativo sem *Stop-Out* na configuração testada.
