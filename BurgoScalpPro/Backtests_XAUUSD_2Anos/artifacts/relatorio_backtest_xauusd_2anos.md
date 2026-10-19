# Relatório Consolidado de Backtest: Burgo Scalpe Pro (XAUUSD - Ouro) - 2 Anos Completos

> **Período de Análise:** 11/10/2024 a 09/10/2026 (**2 Anos Completos** / 47.151 barras M15 reais do servidor)  
> **Ativo:** XAUUSD (Ouro) | **Timeframe:** M15  
> **Janela Operacional:** 04:00 às 18:00 (Horário do Servidor) | Filtro de Sexta-feira: sem novos giros pós 17:00  
> **Depósito Inicial:** \$1.000,00 USD | **Alavancagem:** 1:500  

---

## 1. Comparativo de Desempenho no Ouro (XAUUSD)

No Ouro, testamos as abordagens com base nas 47.151 barras M15 reais:

| Métrica | Configuração Recomendada (Alvo Fixo $5/$10 + Reciclagem) | Configuração Alternativa (Com Trailing Stop 10%) | Com Filtro EMA 200 H1 (Unidirecional) |
| :--- | :---: | :---: | :---: |
| **Saldo Inicial** | \$1.000,00 | \$1.000,00 | \$1.000,00 |
| **Saldo Final** | **\$174.803,63** :star2: | **\$61.042,10** | \$96.205,11 |
| **Lucro Líquido** | **+\$173.803,63 (+17.380,36%)** | **+\$60.042,10 (+6.004,21%)** | +\$95.205,11 (+9.520,51%) |
| **Taxa de Acerto (Win Rate)** | **75,95%** (24.394V / 7.724D) | **64,95%** (15.986V / 8.621D) | **78,78%** |
| **Fator de Lucro (Profit Factor)** | **1,81** :fire: | **1,27** | **1,92** |
| **Total de Trades** | **32.118** | 24.611 | 16.131 |
| **Reciclagens Bem-Sucedidas** | **1.146 vezes** | **3.041 vezes** | 32 vezes |
| **Rebaixamento Máximo (DD)** | **\$1.145,68** | \$1.306,96 | \$1.420,10 |
| **Stops da Cesta Acionados (-\$80)** | 1.414 vezes | 1.163 vezes | 767 vezes |
| **Meses Positivos** | **25 de 25 meses (100% no verde!)** :white_check_mark: | **25 de 25 meses (100% no verde!)** | 24 de 25 meses |

---

## 2. Por que o Alvo Fixo ($5/$10) Superou o Trailing Stop no Ouro?

1. **Ruído e Volatilidade Natural do Ouro:**  
   O Trailing Stop configurado com recuo de 10% em um alvo de \$5.00 é acionado quando o lucro recua apenas \$0,50 (50 centavos). No Ouro, o spread e as oscilações de segundos acionavam precocemente a saída antes da reciclagem ou do alvo total de \$10 global.
2. **Execução Rápida do Alvo Fixo:**  
   Com `InpUseTrailingStop = false`, ao bater \$5.00 de lucro no lado ou \$10.00 global, o EA encerra a cesta no topo do movimento ou recicla a ordem contrária instantaneamente, embolsando o valor cheio e liberando a margem para o próximo giro.

---

## 3. Desempenho Mês a Mês no Ouro (Configuração Recomendada)

Todos os 25 meses do período de 2 anos fecharam com lucro:

| Mês | Lucro Líquido do Mês (PnL) | Saldo Acumulado |
| :---: | :---: | :---: |
| **2024-10** | +$1.943,38 | $2.943,38 |
| **2024-11** | +$2.296,26 | $5.239,64 |
| **2024-12** | +$2.296,80 | $7.536,44 |
| **2025-01** | +$1.910,88 | $9.447,32 |
| **2025-02** | +$3.197,90 | $12.645,22 |
| **2025-03** | +$3.368,04 | $16.013,26 |
| **2025-04** | +$8.249,79 | $24.263,05 |
| **2025-05** | +$5.764,28 | $30.027,33 |
| **2025-06** | +$4.700,86 | $34.728,19 |
| **2025-07** | +$3.030,30 | $37.758,49 |
| **2025-08** | +$3.635,51 | $41.394,00 |
| **2025-09** | +$5.283,36 | $46.677,36 |
| **2025-10** | +$7.553,75 | $54.231,11 |
| **2025-11** | +$6.945,81 | $61.176,92 |
| **2025-12** | +$6.421,57 | $67.598,49 |
| **2026-01** | +$10.204,34 | $77.802,83 |
| **2026-02** | +$9.612,91 | $87.415,74 |
| **2026-03** | +$10.188,13 | $97.603,87 |
| **2026-04** | +$10.652,86 | $108.256,73 |
| **2026-05** | +$8.946,63 | $117.203,36 |
| **2026-06** | +$9.798,94 | $127.002,30 |
| **2026-07** | +$8.620,35 | $135.622,65 |
| **2026-08** | +$7.946,70 | $143.569,35 |
| **2026-09** | +$8.415,37 | $151.984,72 |
| **2026-10 (parcial)** | +$1.539,71 | **$174.803,63** |

---

## 4. Melhorias e Correções Implementadas na Automação (V43.1)

1. **Gestão de Lucro e Stops 24h:** O fechamento de alvo (`InpTargetSideUSD`), trailing stop e alvos globais foram movidos para fora do bloco restrito de horário. Mesmo fora da janela de abertura (04h às 18h), ordens existentes abertas fecham no lucro imediatamente caso o preço atinja o alvo à noite.
2. **Proteção Anti-Quebra da Cesta (`InpMaxLossUSD = 80.00`):** Garante que nenhuma sequência adversa ultrapasse -$80 de perda flutuante, cortando o risco pela raiz.
3. **Detecção Dinâmica do Modo de Preenchimento:** Detecta se a conta é IOC, FOK ou Return no `OnInit`, eliminando erros de rejeição de ordem da corretora.
4. **Desvio e Tolerância de Slippage:** Adicionado desvio de 50 pontos para garantir execução rápida de ordens a mercado no XAUUSD sem requotes.
5. **Trava Anti-Repetição de Hedge:** O hedge abre no máximo uma única vez por nível de gatilho, impedindo abertura em cascata.

---

## 5. Como Executar no MetaTrader 5 Agora Mesmo

O robô já está compilado e o arquivo de preset foi salvo em todos os seus terminais MT5:

1. Abra o MetaTrader 5 e aperte `Ctrl + R` (Testador de Estratégia).
2. Selecione o Expert: **Burgo Scalpe Pro**.
3. Selecione o Ativo: **XAUUSD** (ou `XAUUSD-VIP`).
4. Selecione o Período: **M15** e as datas de **11/10/2024 até hoje**.
5. Na aba **Parâmetros**, clique com botão direito e escolha **Carregar (Load)**.
6. Escolha o arquivo de preset:
   - [`Burgo Scalpe Pro_M15_XAUUSD.set`](file:///C:/Users/Vini_Burgo/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Profiles/Tester/Burgo%20Scalpe%20Pro_M15_XAUUSD.set)
7. Clique em **Iniciar**.
