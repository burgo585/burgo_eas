# 📊 Relatório Técnico: Custos Operacionais na VT Markets & Matriz de Calibração (MNQ, MES, XAUUSD e BTCUSD)

Este documento apresenta a análise de custos transacionais segregada para **Ouro Spot (XAUUSD)** e **Bitcoin (BTCUSD)** negociados via CFD Forex na corretora **VT Markets**, além das melhores configurações testadas e calibradas para o **Robô Frasson & Order Flow Pro**.

---

## 1. 🟡 ANÁLISE DE CUSTOS SEGREGADA: XAUUSD (OURO SPOT) - VT MARKETS

### 1.1 Especificação do Contrato
* **Ativo:** Ouro vs Dólar Americano (`XAUUSD`).
* **Tamanho do Contrato Padrão (1.00 Lote):** $100\text{ onças troy (oz)}$.
* **Volume Mínimo:** $0.01\text{ lote}$ ($1\text{ oz}$).
* **Passo de Volume:** $0.01\text{ lote}$.
* **Casas Decimais (Digits):** 2 dígitos (ex: $2650.45).
* **Tamanho do Tick:** $\$0.01$ (1 centavo).
* **Valor do Ponto Cheio ($1.00 USD de variação do ouro):**
  * **1.00 Lote Padrão:** $\$100.00\text{ USD}$
  * **0.10 Lote Mini:** $\$10.00\text{ USD}$
  * **0.04 Lote Sugerido (2 ordens de 0.02):** $\$4.00\text{ USD}$ por dólar
  * **0.01 Lote Micro:** $\$1.00\text{ USD}$

---

### 1.2 Estrutura de Custos por Tipo de Conta

#### A) Conta Raw ECN (Recomendada para Scalping e Day Trade)
* **Spread Médio Típico:** $0.14\text{ USD / oz}$ (14 centavos / 1.4 pips). Em picos de liquidez (Londres/NY), oscila entre $0.08$ e $0.16$.
* **Comissão de Negociação:** $\$6.00\text{ USD}$ por lote padrão *round-turn* ($\$3.00$ na abertura, $\$3.00$ no fechamento).
* **Simulação de Custos por Lote:**

| Volume Operado | Spread Médio ($) | Comissão ($) | Custo Total por Trade ($) | Custo em USD / oz Equivalente |
| :---: | :---: | :---: | :---: | :---: |
| **0.01 Lote (Micro)** | $\$0.14$ | $\$0.06$ | **$\$0.20$** | $\$0.20$ / oz |
| **0.02 Lote** | $\$0.28$ | $\$0.12$ | **$\$0.40$** | $\$0.20$ / oz |
| **0.04 Lote (Padrão 2x 0.02)** | **$\$0.56$** | **$\$0.24$** | **$\$0.80$** | **$\$0.20$ / oz** |
| **0.10 Lote (Mini)** | $\$1.40$ | $\$0.60$ | **$\$2.00$** | $\$0.20$ / oz |
| **1.00 Lote (Padrão)** | $\$14.00$ | $\$6.00$ | **$\$20.00$** | $\$0.20$ / oz |

#### B) Conta Standard STP (Zero Comissão)
* **Spread Médio Típico:** $0.25\text{ USD / oz}$ (25 centavos / 2.5 pips).
* **Comissão:** $\$0.00\text{ USD}$ (embutida no spread).
* **Custo Total no Lote Padrão (0.04 Lote):** $0.04 \times 100 \times 0.25 = \mathbf{\$1.00\text{ USD}}$.
* **Conclusão:** A conta **Raw ECN gera uma economia de $20\%$ no custo operacional total** em relação à Standard STP ($0.80 vs $1.00 por trade).

---

### 1.3 Custos de Swap / Financiamento Noturno (Overnight)
* **Swap Long (Compra):** Médio de $-38.00\text{ a }-42.00\text{ USD}$ por lote padrão / noite ($\approx -0.16\text{ USD}$ por noite no lote de 0.04).
* **Swap Short (Venda):** Médio de $+18.00\text{ a }+22.00\text{ USD}$ por lote padrão / noite ($\approx +0.08\text{ USD}$ por noite no lote de 0.04).
* **Quarta-feira:** Cobrança de swap triplo (compensação do fim de semana).
* > [!IMPORTANT]
  > **Mitigação Total:** Como a estratégia opera em M5/M1 intradiário com filtro de encerramento até as 18:30 (horário do servidor), **as posições nunca dormem abertas para o rollover das 21:59 GMT**. Portanto, **o custo de swap é ZERO ($0.00)**.

---

### 1.4 Impacto da Fricção no Trade de Ouro (Lote 0.04 / 2 Ordens de 0.02)
* **Stop Loss Técnico ($4.50 USD):** Risco de $\$180.00\text{ USD}$.
* **Alvo 1 Parcial ($4.50 USD em 0.02 lote):** Ganho de $\$90.00\text{ USD}$.
* **Alvo 2 Final ($11.00 USD em 0.02 lote):** Ganho de $\$220.00\text{ USD}$.
* **Lucro Bruto Projetado:** $\$310.00\text{ USD}$.
* **Fricção Total VT Markets Raw ECN:** **$\$0.80\text{ USD}$**.
* **Impacto Percentual da Fricção:** **Apenas $0.25\%$ do lucro bruto projetado**, conferindo extrema viabilidade matemática ao robô.

---

## 2. 🟠 ANÁLISE DE CUSTOS SEGREGADA: BTCUSD (BITCOIN) - VT MARKETS

### 2.1 Especificação do Contrato
* **Ativo:** Bitcoin vs Dólar Americano (`BTCUSD`).
* **Tamanho do Contrato Padrão (1.00 Lote):** $1.00\text{ Bitcoin (1 BTC)}$.
* **Volume Mínimo:** $0.01\text{ lote}$ ($0.01\text{ BTC}$).
* **Passo de Volume:** $0.01\text{ lote}$.
* **Casas Decimais (Digits):** 2 dígitos (ex: $68450.50).
* **Tamanho do Tick:** $\$0.01$.
* **Valor do Ponto ($1.00 USD de variação do BTC):**
  * **1.00 Lote (1 BTC):** $\$1.00\text{ USD}$
  * **0.10 Lote (0.1 BTC):** $\$0.10\text{ USD}$
  * **0.04 Lote Sugerido (2 ordens de 0.02 BTC):** $\$0.04\text{ USD}$ por dólar do Bitcoin
  * **0.01 Lote Micro:** $\$0.01\text{ USD}$

---

### 2.2 Estrutura de Custos por Tipo de Conta

#### A) Conta Raw ECN
* **Spread Médio Típico:** $\approx \$17.00\text{ USD}$ por Bitcoin (oscila entre $\$12.00$ e $\$24.00$ conforme a liquidez global).
* **Comissão de Negociação:** $\$6.00\text{ USD}$ por lote padrão *round-turn*.
* **Simulação de Custos por Lote:**

| Volume Operado | Spread Médio ($) | Comissão ($) | Custo Total por Trade ($) | Custo em USD / BTC Equivalente |
| :---: | :---: | :---: | :---: | :---: |
| **0.01 Lote (0.01 BTC)** | $\$0.17$ | $\$0.06$ | **$\$0.23$** | $\$23.00$ / BTC |
| **0.02 Lote (0.02 BTC)** | $\$0.34$ | $\$0.12$ | **$\$0.46$** | $\$23.00$ / BTC |
| **0.04 Lote (Padrão 2x 0.02)** | **$\$0.68$** | **$\$0.24$** | **$\$0.92$** | **$\$23.00$ / BTC** |
| **0.10 Lote (0.10 BTC)** | $\$1.70$ | $\$0.60$ | **$\$2.30$** | $\$23.00$ / BTC |
| **1.00 Lote (1.00 BTC)** | $\$17.00$ | $\$6.00$ | **$\$23.00$** | $\$23.00$ / BTC |

#### B) Conta Standard STP (Zero Comissão)
* **Spread Médio Típico:** $\approx \$24.00\text{ a }\$26.00\text{ USD}$ por Bitcoin.
* **Comissão:** $\$0.00\text{ USD}$.
* **Custo Total no Lote Padrão (0.04 Lote):** $0.04 \times 25.00 = \mathbf{\$1.00\text{ USD}}$.
* **Conclusão:** A conta **Raw ECN economiza $8\%$ a $12\%$ nos custos totais de Bitcoin**.

---

### 2.3 Custos de Swap / Financiamento Noturno em Cripto
* **Taxa de Swap em Cripto CFDs:** Varia de $-15\%\text{ a }-25\%$ ao ano para posições compradas e $-5\%\text{ a }-10\%$ para vendidas.
* Para 1 BTC inteiro a $\$68.000$, o swap noturno equivale a aproximadamente $\approx -\$35.00\text{ USD}$ por noite.
* No lote operacional de **0.04 BTC**, o swap diário seria de $\approx -\$1.40\text{ USD}$ por noite.
* > [!TIP]
  > **Recomendação Estratégica:** Operar estritamente no modelo **Day Trade** fechando as posições antes da virada do dia para manter custo de swap zero.

---

### 2.4 Impacto da Fricção no Trade de Bitcoin (Lote 0.04 / 2 Ordens de 0.02)
* **Stop Loss Técnico ($450.00 USD de BTC):** Risco de $\$18.00\text{ USD}$ ($450 \times 0.04$).
* **Alvo 1 Parcial ($450.00 USD em 0.02 BTC):** Ganho de $\$9.00\text{ USD}$.
* **Alvo 2 Final ($1.150.00 USD em 0.02 BTC):** Ganho de $\$23.00\text{ USD}$.
* **Lucro Bruto Projetado:** $\$32.00\text{ USD}$.
* **Fricção Total VT Markets Raw ECN:** **$\$0.92\text{ USD}$**.
* **Impacto Percentual da Fricção:** **$2.87\%$ do lucro bruto projetado**, totalmente absorvível pela assimetria positiva do Frasson ATR.

---

## 3. 🎯 MATRIZ DE CALIBRAÇÃO E MELHORES CONFIGURAÇÕES TESTADAS

| Parâmetro / Ativo | Micro Nasdaq (MNQ) | Micro S&P 500 (MES) | Ouro Spot (XAUUSD) | Bitcoin (BTCUSD) |
| :--- | :---: | :---: | :---: | :---: |
| **Ambiente de Mercado** | Futuros CME / Micro | Futuros CME / Micro | VT Markets (Forex Raw) | VT Markets (Crypto Raw) |
| **Tempo Gráfico** | **1 Minuto (M1)** | **12R (Renko)** | **M5 (com trigger M1)** | **M5 (com trigger M1)** |
| **Filtro Macro (VH 5M)** | **$> 1.20$** | **$> 0.80$** | **$> 0.95$** | **$> 1.40$** |
| **Frasson ATR (Per, Shift, Mult)** | `14 | 5 | 2.00` | `14 | 5 | 2.00` | `14 | 3 | 2.00` | `14 | 5 | 2.20` |
| **Gatilho de Entrada** | Rompimento / Escoramento | Rejeição POC no Pavio | Rejeição POC no Pavio | Rejeição POC no Pavio |
| **Volume de Confirmação** | Volume $> 1.15\times$ Média | Volume $\ge$ Média | Volume $\ge 1.10\times$ Média | Volume $\ge 1.20\times$ Média |
| **Pavio Mínimo de Rejeição** | N/A (Breakout) | $\ge 35\%$ da barra | $\ge 38\%$ da barra | $\ge 40\%$ da barra |
| **Lote Operacional Padrão** | **2 Micros** | **2 Micros** | **0.04 Lotes** (2x 0.02) | **0.04 Lotes** (2x 0.02) |
| **Stop Loss Técnico** | ~36 pontos | 8 a 12 pts (+1 folga) | $4.50 USD (450 pts) | $450 USD (45.000 pts) |
| **Alvo 1 (Parcial)** | ~36 pontos ($1.0\times$) | 9 a 10 pontos | $4.50 USD ($1.0\times$) | $450 USD ($1.0\times$) |
| **Alvo 2 (Final Conduzido)** | ~88 pontos ($2.4\times$) | 20 pontos | $11.00 USD ($2.4\times$) | $1.150 USD ($2.5\times$) |
| **Ajuste de Breakeven no Alvo 1** | SIM (+1 pt) | SIM (+0.5 pt) | SIM (+$0.25 USD) | SIM (+$25 USD) |
| **Trailing Stop no Alvo 2** | SIM (Banda Oposta) | SIM (Banda Oposta) | SIM (Banda Oposta) | SIM (Banda Oposta) |
| **Filtro de Horário / Sessão** | 13:30 - 20:00 (NY) | 13:30 - 20:00 (NY) | 07:00 - 18:30 (Londres/NY) | 24/7 (Foco 12:00-21:00) |
| **Arquivo de Preset Criado** | `MNQ_M1_Frasson_Pro.set` | `MES_12R_Frasson_Pro.set` | `XAUUSD_VTMarkets_Pro.set` | `BTCUSD_VTMarkets_Pro.set` |
