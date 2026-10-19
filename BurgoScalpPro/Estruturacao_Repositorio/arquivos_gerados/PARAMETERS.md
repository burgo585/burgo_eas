# ⚙️ Guia Completo de Parâmetros (Inputs) - Burgo Scalpe Pro

Este guia detalha a função de cada parâmetro de entrada (`input`) presente no **Burgo Scalpe Pro (V43)**.

---

## 📌 Grupos de Parâmetros

### 1. ==== MOTOR DE GIRO (SCALPING) ====

| Parâmetro | Tipo | Padrão (V43) | Descrição |
|---|---|---|---|
| `InpInitialLot` | `double` | `0.01` | Lote da primeira ordem de cada ciclo de entrada. |
| `InpTargetSideUSD` | `double` | `1.00` | Alvo financeiro em dólares para fechamento e limpeza de ordens de um mesmo lado (Buy/Sell). |
| `InpTargetGlobalUSD` | `double` | `15.00` | Lucro total acumulado em dólares para zeramento completo de todas as posições da conta. |
| `InpMagicNumber` | `int` | `888124` | Número identificador único das ordens enviadas por este EA. |

---

### 2. ==== LIMITE DE SEGURANÇA (OURO) ====

| Parâmetro | Tipo | Padrão (V43) | Descrição |
|---|---|---|---|
| `InpBaseDistance` | `int` | `500` | Distância inicial mínima em pontos (points) entre a ordem atual e a próxima ordem do grid. |
| `InpLotMultiplier` | `double` | `1.30` | Multiplicador progressivo aplicado ao tamanho do lote a cada nova ordem do grid. |
| `InpMaxMartingale` | `int` | `8` | Limite de níveis em que o lote continuará aumentando. A partir deste nível, os lotes adicionais permanecem constantes. |
| `InpMaxTotalOrders` | `int` | `10` | Quantidade máxima de ordens abertas em simultâneo permitidas pelo robô. |

---

### 3. ==== FILTROS DE VOLATILIDADE ====

| Parâmetro | Tipo | Padrão (V43) | Descrição |
|---|---|---|---|
| `InpTimeframe` | `ENUM_TIMEFRAMES` | `PERIOD_CURRENT` | Tempo gráfico utilizado para cálculo dos indicadores locais (ATR, ADX, CHOP, RSI). |
| `InpUseATR` | `bool` | `true` | Habilita ajuste dinâmico da distância do grid de acordo com o indicador ATR. |
| `InpATRPeriod` | `int` | `14` | Período de cálculo do Average True Range (ATR). |
| `InpATRMultiplier` | `double` | `1.5` | Multiplicador aplicado sobre a leitura do ATR para determinar o espaçamento do grid. |

---

### 4. ==== FILTRO ANTI-OSCILAÇÃO ====

| Parâmetro | Tipo | Padrão (V43) | Descrição |
|---|---|---|---|
| `InpUseADX` | `bool` | `true` | Ativa o filtro de força de tendência ADX. |
| `InpADXPeriod` | `int` | `14` | Período do indicador Average Directional Index (ADX). |
| `InpADXThreshold` | `double` | `20.0` | Valor mínimo do ADX exigido. Se ADX for inferior a este limiar, novas entradas no grid são bloqueadas. |
| `InpCooldownBars` | `int` | `1` | Quantidade de velas/barras de pausa forçada após o fechamento completo de um ciclo de negociação. |
| `InpMaxDrawdownPct` | `double` | `15.0` | Porcentagem máxima de Drawdown flutuante para pausar a expansão do grid. |

---

### 5. ==== FILTROS AVANÇADOS ====

| Parâmetro | Tipo | Padrão (V43) | Descrição |
|---|---|---|---|
| `InpUseCHOP` | `bool` | `true` | Ativa o filtro Choppiness Index (CHOP). |
| `InpCHOPPeriod` | `int` | `14` | Período do Choppiness Index. |
| `InpCHOPTrendLimit` | `double` | `38.2` | Limite inferior do CHOP. Se o CHOP estiver abaixo de 38.2, a tendência é muito forte (estouro) e o grid trava. |
| `InpUseEMA200Filter` | `bool` | `true` | Ativa o filtro direcional de tendência macro com base na Média Móvel Exponencial de 200 períodos. |
| `InpEMA200TF` | `ENUM_TIMEFRAMES` | `PERIOD_M30` | Tempo gráfico para o cálculo da EMA 200 (ex: M30 ou H4). |
| `InpUseRSITrigger` | `bool` | `false` | Habilita entrada obrigatória por níveis de sobrevenda/sobrecompra do RSI. |
| `InpRSIPeriod` | `int` | `14` | Período do indicador RSI. |
| `InpRSIOversold` | `double` | `30.0` | Nível de sobrevenda (permite compras). |
| `InpRSIOverbought` | `double` | `70.0` | Nível de sobrecompra (permite vendas). |
| `InpStepMultiplier` | `double` | `1.25` | Expansão geométrica da distância entre ordens à medida que o grid se aprofunda. |
| `InpMaxSpread` | `int` | `40` | Spread máximo em pontos permitido para envio de novas ordens (evita operar em horários de troca de vela/notícias). |
| `InpHardEquityStopPct` | `double` | `15.0` | **Proteção de Emergência**: Fecha 100% das posições se o drawdown atingir este percentual da conta. |

---

### 6. ==== TRAILING STOP ====

| Parâmetro | Tipo | Padrão (V43) | Descrição |
|---|---|---|---|
| `InpUseTrailingStop` | `bool` | `true` | Ativa o sistema de acompanhamento dinâmico de lucros. |
| `InpTrailingStartUSD` | `double` | `0.50` | Lucro acumulado mínimo em dólares para ativar o rastreamento do Trailing Stop. |
| `InpTrailingDropPct` | `double` | `10.0` | Percentual de recuo tolerado a partir do pico de lucro flutuante antes de encerrar o lado. |

---

### 7. ==== HORÁRIOS DE OPERAÇÃO ====

| Parâmetro | Tipo | Padrão (V43) | Descrição |
|---|---|---|---|
| `InpStartTime` | `string` | `"00:00"` | Horário de início das operações no servidor do MetaTrader 5 (Formato HH:MM). |
| `InpEndTime` | `string` | `"23:59"` | Horário de término das operações (Formato HH:MM). |

---

## 💡 Recomendações por Ativo e Perfil de Risco

### 🌟 XAUUSD (Ouro) - Perfil Scalper M1 (V43 Recomendado)
- **Timeframe**: M1
- **Lote Inicial**: `0.01` por cada `$1.000` de saldo.
- **Distance**: `500` pontos (50 pips).
- **EMA200 TF**: `PERIOD_M30`.
- **Hard Equity Stop**: `15.0%`.

### 📈 Forex (EURUSD / GBPUSD) - Perfil Conservador M5 / M15
- **Timeframe**: M5 ou M15
- **Distance**: `250` - `350` pontos.
- **Lot Multiplier**: `1.25` - `1.30`.
- **EMA200 TF**: `PERIOD_H4`.
- **Hard Equity Stop**: `20.0%`.
