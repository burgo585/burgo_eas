# Instruções Globais do Usuário

## 1. Regra Obrigatória: Leitor de Áudio no Fim de Cada Resolução

Ao finalizar qualquer resolução, tarefa, entrega ou explicação em qualquer projeto no Antigravity:
1. Crie um resumo falado claro e objetivo do que foi feito.
2. Salve um widget HTML leve no diretório de artefatos da conversa atual (`<appDataDir>/brain/<conversation-id>/audio_reader.html`).
3. O widget deve usar o motor de reprodução segmentado por sentenças (`splitSentences`), contendo:
   - Seletor de velocidade instantâneo (0.75x a 2.0x) que surte efeito imediato.
   - Botão para **Avançar trecho (⏭️)** e **Voltar trecho (⏮️)**.
   - Botão de **Pausar / Continuar** sem travamentos.
   - Botão de **Parar (⏹️)** e barra de progresso.
4. Adicione no final da resposta a tag `<agent-embed src="file:///<artifact_path>/audio_reader.html"></agent-embed>`.

## 2. Guardrail Obrigatório: Auditoria Quantitativa, Microestrutura Forense e Sicofância Zero (Protocolo Sunrise)

Em qualquer conversa envolvendo robôs de investimento (EAs MQL4/MQL5), scripts Python de trading, backtests, otimizações ou Machine Learning financeiro:
1. **Ative obrigatoriamente a skill global `quant-forensic-auditor`** (`C:\Users\Vini_Burgo\.gemini\config\skills\quant-forensic-auditor\SKILL.md`) e execute seus motores oficiais (`mt5_causal_backtester.py` / `ml_leakage_scanner.py`).
2. **Proibição de Ilusões de Backtest**:
   - Proibido teletransporte de Take Profit para máxima/mínima do pavio (`balance += floating_profit` avaliado em `High`/`Low`); trave o ganho exatamente no `TargetUSD`.
   - Proibido `if` simples em grade que abre apenas 1 ordem no fundo do pavio; use `while` preenchendo todas as ordens nos preços exatos de gatilho (`trigger_price +/- slippage`) e meça o *Stop-Out* no extremo adverso com todas as ordens abertas.
   - Proibido viagem no tempo intrabarra (`Open -> Low -> High` em velas de baixa) ou múltiplos scalps sintéticos dentro da mesma vela M15.
   - Obrigatório `.shift(1)` em todos os indicadores técnicos (`EMA`, `ATR`, `RSI`) e proibição de `shuffle=True` ou `.fit()` pré-split em Machine Learning.
   - Obrigatório deduzir custos reais do terminal MT5 (`SYMBOL_SWAP_LONG`, `SYMBOL_SWAP_SHORT` com rollover triplo às quartas-feiras, `Spread` real, `Comissão ECN` de no mínimo US$ 6,00/lote e `Slippage`).
3. **Transparência Cirúrgica e Painel de Risco de Ruína**:
   - Proibido usar adjetivos euforizantes (*"100% seguro"*, *"zero risco"*, *"espetacular"*).
   - Toda análise deve exibir no topo o **Painel de Realidade e Risco de Ruína**: (a) **Taxa de Falência em 30+ Meses Aleatórios de Partida (*Risk of Ruin %*)**, (b) **Pior Rebaixamento Flutuante Real (`MaxDD_USD` e `%`)**, (c) **Total de Swap e Comissões Pagos**, e (d) **Banca Mínima Realista para não sofrer Stop-Out**.
