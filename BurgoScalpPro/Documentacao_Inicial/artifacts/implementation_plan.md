# 🚀 Plano de Otimização: Burgo Scalpe Pro V44 (High Performance & Efficiency)

Este documento detalha o plano de evolução do **Burgo Scalpe Pro** para a versão **V44**, focado em tornar o robô **computacionalmente ultra-rápido** (sem travamentos de ticks) e **estratégicamente mais eficiente** no ativo **XAUUSD (Ouro)** nos timeframes M1 e M5.

---

## 🧠 Avaliação Técnica da Mudança

Conforme as diretrizes de gerenciamento de risco de bots de trading:
- **Otimização Racional**: Reduzir chamadas repetitivas de indicadores e manipulação da GUI no evento `OnTick` elimina gargalos de CPU e latência no envio de ordens no MT5 durante velas de forte oscilação.
- **Eficiência Estratégica**: Adicionar confirmação de micro-momentum (direção da vela) e **Reciclagem Inteligente Par-a-Par** permite fechar ordens em prejuízo usando o lucro parcial das ordens do grid, liberando margem sem aguardar todo o ciclo acumular o alvo total.

---

## 📌 Principais Melhorias Propostas para a V44

### 1. ⚡ Otimização Extrema de Velocidade de Código (Desempenho CPU / Ticks)
- **Painel Visual Desacoplado via Timer (`EventSetMillisecondTimer(200)`)**:
  - Em vez de reescrever dezenas de objetos gráficos na tela a cada tick (o que gera lag no MT5), a função `AtualizarValoresPainel` passará a rodar via evento `OnTimer()` a cada 200ms ou quando houver execução de ordens.
- **Cálculo de Estatísticas e Histórico em Cache**:
  - `CalculateStats()` deixará de percorrer todo o histórico da conta em cada tick. Será atualizada apenas 1x por segundo ou quando uma posição for encerrada.
- **Cache de Indicadores (ADX, CHOP, EMA200, ATR, RSI)**:
  - Leitura dos buffers otimizada para ser acionada na mudança de barra ou quando o preço deslocar uma distância relevante, economizando chamadas desnecessárias de `CopyBuffer`.

### 2. 🎯 Eficiência Estratégica & Filtro de Micro-Momentum
- **Filtro de Micro-Momentum na 1ª Ordem**:
  - Evita "comprar em faca caindo" ou "vender em vela de alta explosiva". Além da EMA 200 Macro, a 1ª ordem só é disparada se o preço atual em M1/M5 estiver alinhado com o sentido da micro-vela atual (`Bid > Open` para compras, `Ask < Open` para vendas).
- **Reciclagem Inteligente Ativa (Par-a-Par)**:
  - Quando o grid tiver 3 ou mais ordens abertas e a ordem mais recente estiver positiva (+ $1.50), o robô automaticamente encerra essa ordem positiva **junto** com a pior ordem negativa (- $1.10), garantindo um saldo líquido positivo (+ $0.40) e encurtando o grid imediatamente.

### 3. 🌐 Autodetecção do Tipo de Preenchimento da Corretora (`Filling Mode`)
- Identificação automática do tipo de preenchimento aceito pela corretora (`SYMBOL_FILLING_FOK`, `SYMBOL_FILLING_IOC` ou `SYMBOL_FILLING_RETURN`) para evitar erros de ordem rejeitada ("Off Quotes" ou "Invalid Filling").

---

## 📂 Arquivos Afetados

### [MODIFY] [Burgo Scalpe Pro V43 XAUUSD M1.mq5](file:///c:/Users/Vini_Burgo/Documents/BurgoScalpPro/src/Burgo%20Scalpe%20Pro%20V43%20XAUUSD%20M1.mq5) -> Criar [Burgo Scalpe Pro V44 High Speed.mq5](file:///c:/Users/Vini_Burgo/Documents/BurgoScalpPro/src/Burgo%20Scalpe%20Pro%20V44%20High%20Speed.mq5)

- Criar a nova versão **V44 High Speed** preservando a versão V43 intacta para comparação.
- Adicionar evento `OnTimer()` para renderização fluida do painel gráfico.
- Implementar o filtro de micro-momentum da vela M1/M5.
- Atualizar a função `TentarReciclar` para varrer ordens par-a-par durante a execução do grid.
- Implementar o cache temporizado de estatísticas e leitura de indicadores.

---

## 🧪 Plano de Verificação e Testes

### 1. Compilação no MQL5
- Verificar se a versão V44 compila com **0 Erros e 0 Avisos (Warnings)**.

### 2. Teste de Desempenho no Strategy Tester do MetaTrader 5
- Rodar simulação no **Strategy Tester** no par **XAUUSD (Ouro)** em M1 e M5 nos últimos 6 meses.
- Comparar a velocidade de processamento de ticks (Ticks/segundo) entre V43 e V44.
- Validar se o lucro líquido e a taxa de acerto aumentaram devido ao micro-momentum e reciclagem ativa.
