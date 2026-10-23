# Relatório Forense de Backtest 2026 — Estratégia Stormer H4 Swing Trade

**Período Auditado:** `01/01/2026 a 23/10/2026`  
**Parâmetros Oficiais:** Tempo Gráfico `H4` | `EMA 70` | `Estocástico Lento (8,3,3)` | `Setup 1-2-3` | Alvo no Topo/Fundo Anterior | Stop na Mínima/Máxima  
**Metodologia Causal:** Zero Lookahead Bias (`.shift(1)`), Sem Viagem no Tempo Intrabarra, Sem Teletransporte de Pavio, Custos Reais de Corretora (Spread, Swap e Comissão ECN).

## 1. Tabela Resumo Consolidada (Ano 2026)

| Ativo | Modo Operacional | Trades | Taxa de Acerto | Pontos Capturados | Lucro Líquido ($) | Fator de Lucro (PF) | Pior Drawdown (%) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Mini Índice B3 (WIN / BVSPX)** | `BUY_ONLY` | 8 | 62.5% (5V/3D) | +7953.2 pts | $+15561.57 | **1.99** | 78.11% |
| **Mini Índice B3 (WIN / BVSPX)** | `BIDIRECTIONAL` | 10 | 50.0% (5V/5D) | +4499.4 pts | $+8758.63 | **1.39** | 96.60% |
| **Nasdaq 100 (NAS100)** | `BUY_ONLY` | 7 | 28.6% (2V/5D) | -109.7 pts | $-1104.59 | **0.90** | 87.66% |
| **Nasdaq 100 (NAS100)** | `BIDIRECTIONAL` | 20 | 45.0% (9V/11D) | +1933.3 pts | $+19322.73 | **1.83** | 80.73% |
| **Ouro (XAUUSD)** | `BUY_ONLY` | 3 | 66.7% (2V/1D) | +113.9 pts | $+117.16 | **2.34** | 0.78% |
| **Ouro (XAUUSD)** | `BIDIRECTIONAL` | 13 | 46.2% (6V/7D) | +165.6 pts | $+559.81 | **2.01** | 4.26% |
| **Bitcoin (BTCUSD)** | `BUY_ONLY` | 12 | 41.7% (5V/7D) | +9407.6 pts | $+915.34 | **2.25** | 4.26% |
| **Bitcoin (BTCUSD)** | `BIDIRECTIONAL` | 30 | 40.0% (12V/18D) | +14246.8 pts | $+1230.95 | **1.66** | 4.61% |

---

## 2. Detalhamento e Análise por Ativo em 2026

### Mini Índice B3 (WIN / BVSPX) — Modo `BUY_ONLY`
- **Volume de Trades:** 8 operações ao longo de ~10 meses
- **Taxa de Acerto (*Win Rate*):** 62.5% (5 Vitórias / 3 Derrotas)
- **Saldo em Pontos:** **+7953.2 pontos**
- **Fator de Lucro (*Profit Factor*):** **1.99**
- **Rebaixamento Flutuante Máximo (*MaxDD*):** 78.11% (-US$ 28733.26)
- **Resultado no Mini Índice B3 (1 mini contrato = R$ 0,20/pt):** **R$ +1581.84 Líquidos** (descontados R$ 1,10 de emolumentos B3 por trade)
- **Custos Totais:** Swap pago: $-98.38 | Comissões: -$0.80

#### Histórico Causal de Trades:
| Entrada | Saída | Direção | Resultado | Pontos | PnL Líquido (USD) | Lote |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| 2026-01-14 12:00 | 2026-01-14 20:00 | BUY | [WIN] | +2062.4 | $+4062.25 | 0.1 |
| 2026-02-02 16:00 | 2026-02-11 12:00 | BUY | [WIN] | +4572.7 | $+9006.71 | 0.1 |
| 2026-02-19 16:00 | 2026-03-03 16:00 | BUY | [LOSS] | -2151.1 | $-4238.25 | 0.1 |
| 2026-03-10 12:00 | 2026-03-13 20:00 | BUY | [LOSS] | -4578.9 | $-9021.68 | 0.1 |
| 2026-04-22 12:00 | 2026-04-22 16:00 | BUY | [LOSS] | -1320.3 | $-2601.35 | 0.1 |
| 2026-07-27 16:00 | 2026-07-28 12:00 | BUY | [WIN] | +2637.2 | $+5194.42 | 0.1 |
| 2026-07-28 12:00 | 2026-07-28 16:00 | BUY | [WIN] | +2057.9 | $+4053.39 | 0.1 |
| 2026-09-30 12:00 | 2026-10-02 12:00 | BUY | [WIN] | +4673.5 | $+9205.26 | 0.1 |


### Mini Índice B3 (WIN / BVSPX) — Modo `BIDIRECTIONAL`
- **Volume de Trades:** 10 operações ao longo de ~10 meses
- **Taxa de Acerto (*Win Rate*):** 50.0% (5 Vitórias / 5 Derrotas)
- **Saldo em Pontos:** **+4499.4 pontos**
- **Fator de Lucro (*Profit Factor*):** **1.39**
- **Rebaixamento Flutuante Máximo (*MaxDD*):** 96.60% (-US$ 35536.20)
- **Resultado no Mini Índice B3 (1 mini contrato = R$ 0,20/pt):** **R$ +888.89 Líquidos** (descontados R$ 1,10 de emolumentos B3 por trade)
- **Custos Totais:** Swap pago: $-96.39 | Comissões: -$1.00

#### Histórico Causal de Trades:
| Entrada | Saída | Direção | Resultado | Pontos | PnL Líquido (USD) | Lote |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| 2026-01-14 12:00 | 2026-01-14 20:00 | BUY | [WIN] | +2062.4 | $+4062.25 | 0.1 |
| 2026-02-02 16:00 | 2026-02-11 12:00 | BUY | [WIN] | +4572.7 | $+9006.71 | 0.1 |
| 2026-02-19 16:00 | 2026-03-03 16:00 | BUY | [LOSS] | -2151.1 | $-4238.25 | 0.1 |
| 2026-03-10 12:00 | 2026-03-13 20:00 | BUY | [LOSS] | -4578.9 | $-9021.68 | 0.1 |
| 2026-04-22 12:00 | 2026-04-22 16:00 | BUY | [LOSS] | -1320.3 | $-2601.35 | 0.1 |
| 2026-06-24 16:00 | 2026-06-25 12:00 | SELL | [LOSS] | -1995.3 | $-3931.28 | 0.1 |
| 2026-06-26 12:00 | 2026-06-26 16:00 | SELL | [LOSS] | -1458.4 | $-2873.45 | 0.1 |
| 2026-07-27 16:00 | 2026-07-28 12:00 | BUY | [WIN] | +2637.2 | $+5194.42 | 0.1 |
| 2026-07-28 12:00 | 2026-07-28 16:00 | BUY | [WIN] | +2057.9 | $+4053.39 | 0.1 |
| 2026-09-30 12:00 | 2026-10-02 12:00 | BUY | [WIN] | +4673.5 | $+9205.26 | 0.1 |


### Nasdaq 100 (NAS100) — Modo `BUY_ONLY`
- **Volume de Trades:** 7 operações ao longo de ~10 meses
- **Taxa de Acerto (*Win Rate*):** 28.6% (2 Vitórias / 5 Derrotas)
- **Saldo em Pontos:** **-109.7 pontos**
- **Fator de Lucro (*Profit Factor*):** **0.90**
- **Rebaixamento Flutuante Máximo (*MaxDD*):** 87.66% (-US$ 8765.83)
- **Custos Totais:** Swap pago: $-6.19 | Comissões: -$1.40

#### Histórico Causal de Trades:
| Entrada | Saída | Direção | Resultado | Pontos | PnL Líquido (USD) | Lote |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| 2026-03-12 12:00 | 2026-03-12 16:00 | BUY | [LOSS] | -205.6 | $-2056.00 | 0.1 |
| 2026-05-18 12:00 | 2026-05-18 16:00 | BUY | [LOSS] | -316.6 | $-3166.00 | 0.1 |
| 2026-06-05 12:00 | 2026-06-05 16:00 | BUY | [LOSS] | -183.2 | $-1832.00 | 0.1 |
| 2026-06-17 04:00 | 2026-06-17 20:00 | BUY | [LOSS] | -135.6 | $-1356.00 | 0.1 |
| 2026-06-18 04:00 | 2026-06-22 16:00 | BUY | [WIN] | +529.0 | $+5290.00 | 0.1 |
| 2026-08-07 00:00 | 2026-08-13 16:00 | BUY | [WIN] | +491.2 | $+4912.00 | 0.1 |
| 2026-10-09 04:00 | 2026-10-13 00:00 | BUY | [LOSS] | -288.9 | $-2889.00 | 0.1 |


### Nasdaq 100 (NAS100) — Modo `BIDIRECTIONAL`
- **Volume de Trades:** 20 operações ao longo de ~10 meses
- **Taxa de Acerto (*Win Rate*):** 45.0% (9 Vitórias / 11 Derrotas)
- **Saldo em Pontos:** **+1933.3 pontos**
- **Fator de Lucro (*Profit Factor*):** **1.83**
- **Rebaixamento Flutuante Máximo (*MaxDD*):** 80.73% (-US$ 8859.48)
- **Custos Totais:** Swap pago: $-5.27 | Comissões: -$4.00

#### Histórico Causal de Trades:
| Entrada | Saída | Direção | Resultado | Pontos | PnL Líquido (USD) | Lote |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| 2026-02-09 08:00 | 2026-02-09 16:00 | SELL | [LOSS] | -169.8 | $-1698.00 | 0.1 |
| 2026-02-10 04:00 | 2026-02-10 16:00 | SELL | [LOSS] | -127.3 | $-1274.00 | 0.1 |
| 2026-02-11 12:00 | 2026-02-11 16:00 | SELL | [LOSS] | -140.5 | $-1405.00 | 0.1 |
| 2026-02-19 16:00 | 2026-02-20 16:00 | SELL | [LOSS] | -255.1 | $-2551.00 | 0.1 |
| 2026-03-03 04:00 | 2026-03-03 08:00 | SELL | [WIN] | +394.2 | $+3942.00 | 0.1 |
| 2026-03-12 12:00 | 2026-03-12 16:00 | BUY | [LOSS] | -205.6 | $-2056.00 | 0.1 |
| 2026-03-18 16:00 | 2026-03-19 12:00 | SELL | [WIN] | +386.8 | $+3868.00 | 0.1 |
| 2026-05-18 12:00 | 2026-05-18 16:00 | BUY | [LOSS] | -316.6 | $-3166.00 | 0.1 |
| 2026-06-05 12:00 | 2026-06-05 16:00 | BUY | [LOSS] | -183.2 | $-1832.00 | 0.1 |
| 2026-06-17 04:00 | 2026-06-17 20:00 | BUY | [LOSS] | -135.6 | $-1356.00 | 0.1 |
| 2026-06-18 04:00 | 2026-06-22 16:00 | BUY | [WIN] | +529.0 | $+5290.00 | 0.1 |
| 2026-07-13 20:00 | 2026-07-14 12:00 | SELL | [LOSS] | -339.3 | $-3393.00 | 0.1 |
| 2026-07-16 08:00 | 2026-07-16 16:00 | SELL | [WIN] | +297.6 | $+2976.00 | 0.1 |
| 2026-07-22 04:00 | 2026-07-24 16:00 | SELL | [WIN] | +867.5 | $+8675.00 | 0.1 |
| 2026-08-07 00:00 | 2026-08-13 16:00 | BUY | [WIN] | +491.2 | $+4912.00 | 0.1 |
| 2026-09-14 00:00 | 2026-09-14 04:00 | SELL | [WIN] | +339.7 | $+3397.00 | 0.1 |
| 2026-10-09 04:00 | 2026-10-13 00:00 | BUY | [LOSS] | -288.9 | $-2889.00 | 0.1 |
| 2026-10-16 16:00 | 2026-10-16 20:00 | SELL | [WIN] | +430.0 | $+4300.00 | 0.1 |
| 2026-10-21 08:00 | 2026-10-21 16:00 | SELL | [LOSS] | -163.3 | $-1633.00 | 0.1 |
| 2026-10-22 04:00 | 2026-10-22 16:00 | SELL | [WIN] | +522.5 | $+5225.00 | 0.1 |


### Ouro (XAUUSD) — Modo `BUY_ONLY`
- **Volume de Trades:** 3 operações ao longo de ~10 meses
- **Taxa de Acerto (*Win Rate*):** 66.7% (2 Vitórias / 1 Derrotas)
- **Saldo em Pontos:** **+113.9 pontos**
- **Fator de Lucro (*Profit Factor*):** **2.34**
- **Rebaixamento Flutuante Máximo (*MaxDD*):** 0.78% (-US$ 79.80)
- **Custos Totais:** Swap pago: $-2.07 | Comissões: -$0.42

#### Histórico Causal de Trades:
| Entrada | Saída | Direção | Resultado | Pontos | PnL Líquido (USD) | Lote |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| 2026-05-11 16:00 | 2026-05-12 00:00 | BUY | [WIN] | +63.5 | $+63.51 | 0.01 |
| 2026-08-19 12:00 | 2026-08-19 16:00 | BUY | [WIN] | +72.7 | $+145.38 | 0.02 |
| 2026-08-27 00:00 | 2026-08-27 12:00 | BUY | [LOSS] | -22.3 | $-89.24 | 0.04 |


### Ouro (XAUUSD) — Modo `BIDIRECTIONAL`
- **Volume de Trades:** 13 operações ao longo de ~10 meses
- **Taxa de Acerto (*Win Rate*):** 46.2% (6 Vitórias / 7 Derrotas)
- **Saldo em Pontos:** **+165.6 pontos**
- **Fator de Lucro (*Profit Factor*):** **2.01**
- **Rebaixamento Flutuante Máximo (*MaxDD*):** 4.26% (-US$ 432.58)
- **Custos Totais:** Swap pago: $10.69 | Comissões: -$1.62

#### Histórico Causal de Trades:
| Entrada | Saída | Direção | Resultado | Pontos | PnL Líquido (USD) | Lote |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| 2026-03-25 12:00 | 2026-03-31 04:00 | SELL | [LOSS] | -70.0 | $-69.96 | 0.01 |
| 2026-03-31 12:00 | 2026-03-31 16:00 | SELL | [LOSS] | -76.3 | $-76.29 | 0.01 |
| 2026-05-11 16:00 | 2026-05-12 00:00 | BUY | [WIN] | +63.5 | $+63.52 | 0.01 |
| 2026-05-22 04:00 | 2026-05-25 00:00 | SELL | [LOSS] | -34.2 | $-68.38 | 0.02 |
| 2026-06-12 08:00 | 2026-06-15 00:00 | SELL | [LOSS] | -75.4 | $-75.40 | 0.01 |
| 2026-06-16 00:00 | 2026-06-17 20:00 | SELL | [LOSS] | -63.2 | $-63.18 | 0.01 |
| 2026-06-29 00:00 | 2026-06-30 04:00 | SELL | [WIN] | +105.3 | $+315.81 | 0.03 |
| 2026-07-10 12:00 | 2026-07-13 16:00 | SELL | [WIN] | +73.1 | $+146.12 | 0.02 |
| 2026-08-19 12:00 | 2026-08-19 16:00 | BUY | [WIN] | +72.7 | $+145.40 | 0.02 |
| 2026-08-27 00:00 | 2026-08-27 12:00 | BUY | [LOSS] | -22.3 | $-89.20 | 0.04 |
| 2026-09-21 12:00 | 2026-09-28 00:00 | SELL | [WIN] | +106.8 | $+213.50 | 0.02 |
| 2026-09-30 08:00 | 2026-09-30 12:00 | SELL | [LOSS] | -20.8 | $-104.00 | 0.05 |
| 2026-10-12 12:00 | 2026-10-22 12:00 | SELL | [WIN] | +106.4 | $+212.80 | 0.02 |


### Bitcoin (BTCUSD) — Modo `BUY_ONLY`
- **Volume de Trades:** 12 operações ao longo de ~10 meses
- **Taxa de Acerto (*Win Rate*):** 41.7% (5 Vitórias / 7 Derrotas)
- **Saldo em Pontos:** **+9407.6 pontos**
- **Fator de Lucro (*Profit Factor*):** **2.25**
- **Rebaixamento Flutuante Máximo (*MaxDD*):** 4.26% (-US$ 488.57)
- **Custos Totais:** Swap pago: $-11.59 | Comissões: -$9.84

#### Histórico Causal de Trades:
| Entrada | Saída | Direção | Resultado | Pontos | PnL Líquido (USD) | Lote |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| 2026-01-09 00:00 | 2026-01-14 00:00 | BUY | [WIN] | +3306.9 | $+132.28 | 0.04 |
| 2026-03-14 16:00 | 2026-03-16 04:00 | BUY | [WIN] | +3048.7 | $+548.77 | 0.18 |
| 2026-04-13 00:00 | 2026-04-13 08:00 | BUY | [LOSS] | -851.8 | $-102.23 | 0.12 |
| 2026-04-13 16:00 | 2026-04-14 00:00 | BUY | [WIN] | +2563.8 | $+384.57 | 0.15 |
| 2026-04-19 16:00 | 2026-04-19 20:00 | BUY | [LOSS] | -841.9 | $-109.44 | 0.13 |
| 2026-04-20 08:00 | 2026-04-22 08:00 | BUY | [WIN] | +3578.2 | $+357.81 | 0.1 |
| 2026-04-29 12:00 | 2026-04-29 16:00 | BUY | [LOSS] | -1167.5 | $-105.07 | 0.09 |
| 2026-05-08 12:00 | 2026-05-13 16:00 | BUY | [LOSS] | -818.5 | $-106.41 | 0.13 |
| 2026-07-24 04:00 | 2026-07-24 16:00 | BUY | [LOSS] | -594.3 | $-106.98 | 0.18 |
| 2026-08-27 00:00 | 2026-08-28 04:00 | BUY | [WIN] | +2601.5 | $+260.16 | 0.1 |
| 2026-08-30 12:00 | 2026-08-31 00:00 | BUY | [LOSS] | -340.6 | $-109.01 | 0.32 |
| 2026-09-24 00:00 | 2026-09-24 08:00 | BUY | [LOSS] | -1076.8 | $-107.68 | 0.1 |


### Bitcoin (BTCUSD) — Modo `BIDIRECTIONAL`
- **Volume de Trades:** 30 operações ao longo de ~10 meses
- **Taxa de Acerto (*Win Rate*):** 40.0% (12 Vitórias / 18 Derrotas)
- **Saldo em Pontos:** **+14246.8 pontos**
- **Fator de Lucro (*Profit Factor*):** **1.66**
- **Rebaixamento Flutuante Máximo (*MaxDD*):** 4.61% (-US$ 527.64)
- **Custos Totais:** Swap pago: $-11.72 | Comissões: -$23.28

#### Histórico Causal de Trades:
| Entrada | Saída | Direção | Resultado | Pontos | PnL Líquido (USD) | Lote |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| 2026-01-09 00:00 | 2026-01-14 00:00 | BUY | [WIN] | +3306.9 | $+132.28 | 0.04 |
| 2026-01-29 00:00 | 2026-01-29 16:00 | SELL | [WIN] | +2789.7 | $+139.49 | 0.05 |
| 2026-02-03 16:00 | 2026-02-03 20:00 | SELL | [WIN] | +3381.2 | $+304.31 | 0.09 |
| 2026-02-07 16:00 | 2026-02-09 00:00 | SELL | [LOSS] | -1790.9 | $-89.54 | 0.05 |
| 2026-02-15 04:00 | 2026-02-15 08:00 | SELL | [LOSS] | -907.2 | $-99.80 | 0.11 |
| 2026-02-15 16:00 | 2026-02-23 00:00 | SELL | [WIN] | +3662.0 | $+146.48 | 0.04 |
| 2026-03-01 20:00 | 2026-03-02 16:00 | SELL | [LOSS] | -2476.4 | $-99.06 | 0.04 |
| 2026-03-14 16:00 | 2026-03-16 04:00 | BUY | [WIN] | +3048.7 | $+579.26 | 0.19 |
| 2026-04-01 04:00 | 2026-04-01 08:00 | SELL | [LOSS] | -739.8 | $-103.58 | 0.14 |
| 2026-04-01 16:00 | 2026-04-06 00:00 | SELL | [LOSS] | -1062.0 | $-106.20 | 0.1 |
| 2026-04-13 00:00 | 2026-04-13 08:00 | BUY | [LOSS] | -851.8 | $-102.23 | 0.12 |
| 2026-04-13 16:00 | 2026-04-14 00:00 | BUY | [WIN] | +2563.8 | $+384.57 | 0.15 |
| 2026-04-19 16:00 | 2026-04-19 20:00 | BUY | [LOSS] | -841.9 | $-109.44 | 0.13 |
| 2026-04-20 08:00 | 2026-04-22 08:00 | BUY | [WIN] | +3578.2 | $+357.81 | 0.1 |
| 2026-04-29 12:00 | 2026-04-29 16:00 | BUY | [LOSS] | -1167.5 | $-105.07 | 0.09 |
| 2026-05-08 12:00 | 2026-05-13 16:00 | BUY | [LOSS] | -818.5 | $-106.41 | 0.13 |
| 2026-05-21 00:00 | 2026-05-21 04:00 | SELL | [LOSS] | -629.9 | $-107.08 | 0.17 |
| 2026-05-22 04:00 | 2026-05-22 20:00 | SELL | [WIN] | +1326.5 | $+198.97 | 0.15 |
| 2026-05-24 08:00 | 2026-05-24 12:00 | SELL | [LOSS] | -697.8 | $-111.64 | 0.16 |
| 2026-05-26 00:00 | 2026-05-26 16:00 | SELL | [LOSS] | -690.8 | $-110.52 | 0.16 |
| 2026-05-31 12:00 | 2026-06-01 12:00 | SELL | [WIN] | +1320.7 | $+316.97 | 0.24 |
| 2026-06-08 08:00 | 2026-06-12 16:00 | SELL | [LOSS] | -1604.0 | $-112.28 | 0.07 |
| 2026-06-14 08:00 | 2026-06-15 00:00 | SELL | [LOSS] | -435.6 | $-108.89 | 0.25 |
| 2026-06-21 20:00 | 2026-06-22 04:00 | SELL | [LOSS] | -483.1 | $-106.28 | 0.22 |
| 2026-06-28 00:00 | 2026-07-01 04:00 | SELL | [WIN] | +1969.2 | $+236.30 | 0.12 |
| 2026-07-24 04:00 | 2026-07-24 16:00 | BUY | [LOSS] | -594.3 | $-106.98 | 0.18 |
| 2026-08-27 00:00 | 2026-08-28 04:00 | BUY | [WIN] | +2601.5 | $+260.16 | 0.1 |
| 2026-08-30 12:00 | 2026-08-31 00:00 | BUY | [LOSS] | -340.6 | $-112.41 | 0.33 |
| 2026-09-15 04:00 | 2026-09-15 16:00 | SELL | [WIN] | +1907.3 | $+114.44 | 0.06 |
| 2026-09-24 00:00 | 2026-09-24 08:00 | BUY | [LOSS] | -1076.8 | $-107.68 | 0.1 |

