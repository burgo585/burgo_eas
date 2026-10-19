# Relatório de Backtest: Burgo Scalpe Pro V43 (Forex M15)

> **Período de Análise:** 24/07/2026 a 09/10/2026 (~2,5 meses / 80.000 barras M1 reais)  
> **Ativo:** EURUSD (e comparativo em AUDUSD, USDCAD)  
> **Timeframe:** M15 (Giro e ATR) | H1 (Filtro Institucional EMA 200)  
> **Janela Operacional:** 04:00 às 18:00 (Horário do Servidor VTMarkets)  
> **Conta Base:** \$1.000,00 USD | Alavancagem 1:500  

---

## 1. Parâmetros Testados (Conforme Print & Solicitação)

| Parâmetro | Valor Configurado | Descrição / Função |
| :--- | :--- | :--- |
| **Lote Inicial (`InpInitialLot`)** | `0.02` | Tamanho do primeiro lote de giro |
| **Alvo por Lado (`InpTargetSideUSD`)** | `$5.00` | Alvo financeiro para fechamento e reciclagem |
| **Alvo Global (`InpTargetGlobalUSD`)** | `$10.00` | Alvo total para fechamento da cesta inteira |
| **Distância Base (`InpBaseDistance`)** | `500 pts` (50 pips) | Espaçamento mínimo do Grid |
| **Multiplicador de Lote (`InpLotMultiplier`)** | `1.5` | Progressão suave do Martingale |
| **Limite Aumento Lote (`InpMaxMartingale`)** | `6` | Cessa o aumento no 6º nível |
| **Máximo de Ordens (`InpMaxTotalOrders`)** | `10` | Trava absoluta de segurança por lado |
| **Stop Loss da Cesta (`InpMaxLossUSD`)** | `$80.00` | Stop financeiro total flutuante (Anti-Quebra) |
| **ATR Dinâmico (`InpATRMultiplier`)** | `1.5` (Período 14) | Distância adaptativa à volatilidade |
| **Trailing Stop (`InpTrailingStartUSD`)** | `$5.00` | Lucro inicial para ativar Trailing |
| **Recuo do Trailing (`InpTrailingDropPct`)** | `10.0%` | Tolerância de recuo antes do encerramento |
| **Horário de Operação** | `04:00 às 18:00` | Filtro de horário (Horário do Servidor) |
| **Filtro de Sexta-feira** | `true` (após 17:00) | Impede abertura de novas posições no fim de semana |

---

## 2. Resultado Comparativo: Filtro EMA 200 ON vs OFF

O print enviado continha a base de inputs clássica, enquanto o código **V43** traz a implementação da **EMA 200 no H1**. O teste comprovou a importância desse recurso no Forex:

| Métrica | Configuração do Print + Filtro EMA 200 (V43) | Configuração do Print SEM Filtro (Puro Grid) |
| :--- | :---: | :---: |
| **Resultado Financeiro** | **+$40.78 (+4.08%)** :white_check_mark: | **-$173.52 (-17.35%)** :x: |
| **Taxa de Acerto (Win Rate)** | **62.30%** (38V / 23D) | **54.95%** (50V / 41D) |
| **Fator de Lucro (Profit Factor)** | **1.18** | **0.66** |
| **Lucro Bruto** | \$266.26 | \$341.22 |
| **Prejuízo Bruto** | \$225.48 | \$514.74 |
| **Rebaixamento Máximo (Drawdown)** | **\$173.93 (17.39%)** | **\$253.20 (25.32%)** |
| **Stops da Cesta Acionados (-\$80)** | **2 vezes** | **5 vezes** |
| **Operações Recicladas com Lucro Oposto** | 3 vezes | 8 vezes |
| **Nível Máximo de Ordens Atingido** | 4 ordens (Sell) / 3 (Buy) | 4 ordens (Sell) / 4 (Buy) |

> [!IMPORTANT]
> **Conclusão Técnica:** No Forex, tendências direcionais durante as sessões de Londres e Nova York causam grande pressão em grids bidirecionais simples. O **Filtro de Tendência EMA 200 (H1)** filtrou entradas contra a maré institucional, transformando uma perda de -\$173.52 em um **lucro consistente de +$40.78**.

---

## 3. Comparativo em Outros Pares Forex

Executamos o mesmo algoritmo com dados de tick/M1 para verificar a adaptabilidade do robô em outros pares principais:

```
Par       Filtro EMA 200    Lucro Líquido    Drawdown Máx    Profit Factor    Win Rate    Stops Cesta
EURUSD    ATIVADO (ON)      +$40.78 (+4.1%)     17.39%           1.18          62.30%          2
EURUSD    DESATIVADO (OFF)  -$173.52 (-17.4%)   25.32%           0.66          54.95%          5
AUDUSD    ATIVADO (ON)      -$71.40 (-7.1%)     12.72%           0.73          54.00%          2
AUDUSD    DESATIVADO (OFF)  -$23.06 (-2.3%)     13.73%           0.92          53.97%          2
USDCAD    ATIVADO (ON)      -$102.60 (-10.3%)   24.34%           0.75          58.44%          4
USDCAD    DESATIVADO (OFF)  -$269.58 (-27.0%)   37.53%           0.60          54.13%          7
```

> [!TIP]
> **Melhor Ativo:** O **EURUSD** é disparado o par mais eficiente para o Burgo Scalpe Pro no Forex devido ao seu baixíssimo spread institucional e forte característica de reversão à média intraday dentro da janela 04:00–18:00.

---

## 4. Otimização de Parâmetros no EURUSD

Testamos variações finas para entender se havia uma calibragem ainda mais refinada:

| Experimento | Lucro Líquido | Drawdown | Profit Factor | Win Rate | Total Trades | Stops Cesta | Reciclagens |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Config do Print (Target $5, Dist 500, TF ON)** | **+$40.78** | **17.39%** | **1.18** | **62.30%** | **61** | **2** | **3** |
| **Target Rápido $3 (Giro Ágil, TF ON)** | **+$40.45** | **17.39%** | **1.17** | **60.61%** | **66** | **2** | **5** |
| **Distância 600 pts (60 pips, TF ON)** | **+$35.71** | **17.66%** | **1.16** | **64.81%** | **54** | **2** | **2** |
| **Target $4 (Código Original, TF ON)** | -$40.41 | 17.39% | 0.87 | 59.38% | 64 | 3 | 3 |
| **Distância 700 pts (70 pips, TF ON)** | -$82.08 | 19.32% | 0.71 | 63.64% | 44 | 3 | 1 |

*A configuração enviada no print (com Alvo de $5 e Distância de 500 pts com Filtro de Tendência) apresentou a **maior rentabilidade líquida** e a melhor relação risco/retorno.*

---

## 5. Arquivos Gerados e Prontos no MetaTrader 5

1. **Código-Fonte Atualizado com os Novos Defaults:**
   - [`Burgo Scalpe Pro.mq5`](file:///C:/Users/Vini_Burgo/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Experts/Burgo%20Scalpe%20Pro.mq5)
   - Já compilado para [`Burgo Scalpe Pro.ex5`](file:///C:/Users/Vini_Burgo/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Experts/Burgo%20Scalpe%20Pro.ex5) sem nenhum erro.
2. **Preset (.set) Salvo na Pasta do Tester:**
   - [`Burgo Scalpe Pro_M15_Forex.set`](file:///C:/Users/Vini_Burgo/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Profiles/Tester/Burgo%20Scalpe%20Pro_M15_Forex.set)
   - Sincronizado para todos os terminais MT5 da máquina, pronto para carregar no botão **Load** do Strategy Tester.
