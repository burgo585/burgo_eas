# 📜 Histórico de Alterações (Changelog) - Burgo Scalpe Pro

Todas as alterações notáveis neste projeto serão documentadas neste arquivo.

---

## [V43.00] - 2024 / XAUUSD M1 Scalper Edition

### 🎯 Foco principal
Otimização total para alta velocidade de execução, giro rápido de caixa e segurança contra a alta volatilidade e ruído do **Ouro (XAUUSD)** no tempo gráfico **M1**.

### ✨ Adicionado & Alterado
- **Calibração de Alvo Rápido ("Bateu, Levou")**:
  - `InpTargetSideUSD`: Reduzido para `$1.00` (giros extremamente rápidos).
  - `InpTargetGlobalUSD`: Ajustado para `$15.00`.
- **Ajuste de Parâmetros para XAUUSD**:
  - `InpBaseDistance`: Ajustado para `500` pontos de ouro (compatível com os picos de preço).
  - `InpLotMultiplier`: Fixado em `1.30` (multiplicador conservador).
  - `InpMaxTotalOrders`: Limitado a `10` ordens máximas por ciclo.
- **Filtro Direcional Macro em M30**:
  - `InpEMA200TF`: Alterado para `PERIOD_M30` para capturar a tendência intradiária do Ouro com precisão sem atrasar entradas curtas.
- **Configuração de Spreads & Filtros**:
  - `InpMaxSpread`: Aumentado para `40` pontos (adaptado aos spreads flutuantes do Ouro).
  - `InpADXThreshold`: Ajustado para `20.0` para maior agilidade operacional no M1.
  - `InpCooldownBars`: Reduzido para `1` barra (1 minuto de pausa pós-ciclo).
  - `InpStepMultiplier`: Expandido para `1.25` para amortecer movimentos rápidos (spikes).
- **Proteção Nuclear**:
  - `InpHardEquityStopPct`: Ativado em `15.0%` da conta.
- **Trailing Stop Apressado**:
  - `InpTrailingStartUSD`: `$0.50` para rápida captura de tendência a favor.

---

## [V42.00] - 2024 / CHOP + EMA200 + Grid Progressivo + Hard Equity Stop

### 🎯 Foco principal
Aumento substancial do controle de risco, combate a tendências prolongadas contrárias e introdução de filtros avançados de estrutura de mercado.

### ✨ Adicionado & Alterado
- **Choppiness Index (CHOP)**:
  - Adicionado indicador CHOP (`InpUseCHOP`, `InpCHOPPeriod = 14`).
  - Limite de tendência (`InpCHOPTrendLimit = 38.2`). Se o CHOP estiver abaixo de 38.2, a tendência é considerada explosiva e o grid é travado.
- **Filtro Direcional de EMA 200**:
  - Adicionado `InpUseEMA200Filter` com TF configurável (`InpEMA200TF = PERIOD_H4`). Permite grids apenas na direção da tendência macro.
- **Hard Equity Stop %**:
  - Adicionada proteção de emergência `InpHardEquityStopPct` (padrão `20.0%`). Fecha todas as ordens e reseta o EA se o drawdown ultrapassar o valor definido.
- **Multiplicador Progressivo de Distância (`InpStepMultiplier`)**:
  - A distância entre as ordens do grid agora se expande geometricamente (`InpStepMultiplier = 1.20`), evitando acúmulo excessivo de ordens em tiros curtos.
- **Gatilho de Entrada RSI (Opcional)**:
  - Adicionado suporte a filtro de sobrecompra/sobrevenda via RSI (`InpUseRSITrigger`).
- **Otimização de Lotes**:
  - Redução do multiplicador de lotes padrão de `1.5` para `1.3` com base em pesquisas de eficiência de margem.

---

## [V41.00] - 2024 / Anti-Oscilação ADX + Cooldown + Reciclagem Smart

### 🎯 Foco principal
Implementação de mecanismos para evitar operações falsas em mercados de baixa volatilidade/consolidação e prevenção de repetição contínua de ciclos em topo/fundo.

### ✨ Adicionado & Alterado
- **Filtro ADX Anti-Oscilação**:
  - Integração do `iADX` para identificar força de movimento. Mercado abaixo do threshold de ADX bloqueia a abertura do grid.
- **Tempo de Cooldown de Barras**:
  - Adicionado `InpCooldownBars` para forçar um período de espera após o fechamento completo de um lado (Buy/Sell) antes de reabrir posições.
- **Painel Interativo no Gráfico**:
  - Criação da interface gráfica nativa em MQL5 com suporte a minimização, estatísticas de Win Rate, Floating P/L, estatísticas diárias e botões de controle direto (Buy/Sell manual, Limpeza, Panic Button, Fechar Lucrativas e Toggles de Filtros).
- **Proteção de Drawdown Máximo**:
  - Integração da verificação `InpMaxDrawdownPct` para pausa temporária de novas ordens do grid.
