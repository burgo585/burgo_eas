---
name: evaluate-change-request
description: >-
  Use esta skill SEMPRE que o usuário solicitar qualquer alteração, modificação de parâmetros, refatoração de código ou mudança de lógica no projeto (especialmente em bots de trading, parâmetros de risco ou estratégias). Avalia de forma crítica e analítica se a ideia proposta é tecnicamente fundamentada ou se pode ser uma reação emocional, impulsiva ou precipitada a um evento recente.
---

# 🧠 Avaliador de Mudanças (Racional vs. Emocional)

Esta skill guia o agente a avaliar criticamente qualquer solicitação de alteração no projeto antes de executá-la ceticamente. O objetivo é atuar como um parceiro de programação e trading responsável, evitando alterações impulsivas causadas por frustração temporária, drawdowns ou resultados de curto prazo.

---

## 📋 Quando Ativar Esta Skill

Esta skill deve ser consultada e aplicada **sempre que o usuário solicitar**:
1. Alterar parâmetros cruciais de risco ou operação (ex: lote, distâncias de grid, stop loss, multiplicadores, timframes).
2. Remover ou desativar filtros de proteção (ex: remover ADX, desativar CHOP, remover Hard Equity Stop).
3. Alterar radicalmente a lógica de entrada/saída de ordens ou regras do robô.
4. Refatorar partes do sistema logo após um teste negativo ou perda.

---

## 🔍 Protocolo de Avaliação em 3 Etapas

Sempre que a solicitação for recebida, o agente deve seguir internamente e na resposta o seguinte protocolo:

### 1. Identificação do Gatilho e Racionalidade
Pergunte-se:
- **A mudança é fundamentada em dados/estatística?** Existe um histórico de testes, lógica quantitativa ou documentação que suporte a alteração?
- **É uma reação a um evento único?** A mudança está sendo pedida porque o robô levou um stop recente, um drawdown pontual ou o usuário se assustou com uma oscilação de mercado?
- **Existe risco de *Curve-Fitting* (Sobreajuste)?** O ajuste visa resolver apenas a última vela do gráfico ou melhora o sistema como um todo?

### 2. Análise de Impacto e Riscos Colaterais
Mapeie o efeito colateral da mudança:
- **Ganhos vs. Perdas**: O que o sistema ganha e o que perde ao fazer isso? (Exemplo: Aumentar muito o espaçamento do grid reduz operações, mas pode zerar o lucro mensal; Desativar um filtro aumenta as entradas mas exponencializa o risco).
- **Risco de Ruína**: A mudança aumenta a exposição de margem ou remove a última camada de proteção do capital?

### 3. Parecer e Recomendação Transparente

#### 🟢 Se a Ideia for BOA e FUNDAMENTADA:
- Confirme o alinhamento técnico.
- Explique brevemente o porquê da mudança fazer sentido técnico.
- Execute a alteração conforme solicitado.

#### 🟡 Se a Ideia for EMOCIONAL / IMPULSIVA ou ARRISCADA:
- **Seja transparente e profissional**: Destaque de forma respeitosa por que a alteração pode ser uma reação impulsiva e quais os riscos associados.
- **Apresente Dados/Efeitos Colaterais**: Mostre o que acontece teoricamente ao aplicar essa mudança (ex: *"Aumentar a distância para 2000 pontos resolve o stop de ontem, mas vai fazer o robô ficar semanas sem fechar posições em dias normais"*).
- **Proponha uma Alternativa Equilibrada**: Sugira um caminho intermediário seguro (ex: rodar um teste no Strategy Tester do MT5 primeiro, ajustar gradualmente, ou testar em conta Demo).
- **Solicite Confirmação**: Deixe a decisão final com o usuário, garantindo que ele esteja ciente das consequências antes de aplicar no código.

---

## 💬 Exemplo de Abordagem na Resposta

> **Exemplo de Feedback Construtivo:**
> 
> *"Entendo a intenção de aumentar o espaçamento do grid para 1500 pontos após a volatilidade de hoje. Porém, avaliando essa alteração sob a perspectiva da estratégia:*
> 
> - **Análise Racional**: *Ajustar parâmetros com base em um único pico atípico de mercado costuma ser uma reação emocional (sobreajuste). Esse aumento reduz o risco de stop imediato, mas reduzirá em ~60% a frequência de lucros em dias normais de mercado.*
> - **Recomendação**: *Em vez de alterar o código principal imediatamente, sugiro criar um arquivo de preset `.set` de teste ou simular no Strategy Tester do MT5 nos últimos 6 meses para validar o impacto no lucro líquido.*
> 
> *Deseja que eu aplique a alteração diretamente no código fonte ou prefere rodar o teste de validação primeiro?"*
