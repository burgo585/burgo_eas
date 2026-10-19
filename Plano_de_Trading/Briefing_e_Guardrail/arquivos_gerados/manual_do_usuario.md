# 🛡️ Manual do Usuário e Especificação Quantitativa
## Motor Institucional de Trading com Protocolo Sunrise GuardRail

---

## 1. Visão Geral do Sistema

O sistema é uma plataforma institucional de negociação quantitativa automatizada desenvolvida para operar no terminal **MetaTrader 5 (MT5)** com corretoras institucionais (como a **VT Markets**). O motor integra algoritmos de leitura de fluxo de volume institucional (**PVSRA**), volatilidade adaptativa (**ATR**), médias móveis exponenciais de tendência e uma camada autônoma de segurança cibernética e de risco chamada **Sunrise GuardRail**.

### Arquitetura de Componentes
```
[Mercado MT5: XAUUSD / BTCUSD]
              │
              ▼
    [1. Leitura em Tempo Real] ──> Dados M15 (OHLCV, Ticks, Spread, ATR)
              │
              ▼
    [2. Filtro de Tendência]   ──> Alinhamento Macro (EMA 50 & EMA 200)
              │
              ▼
    [3. Gatilho Institucional] ──> PVSRA (Clímax de Absorção / Rising Volume)
              │
              ▼
    [4. Sunrise GuardRail]     ──> 🛡️ Auditoria Pré-Trade (Spread Drag, Margem, Sessão)
              │
       ┌──────┴──────┐
    [Aprovado]   [Rejeitado] ──> Log de Auditoria & Bloqueio Instantâneo
       │
       ▼
    [5. Execução em Milissegundos] ──> Ordem a Mercado com SL e TP Embutidos
```

---

## 2. Gatilhos de Entrada (Entry Triggers)

Para que uma ordem de compra ou venda seja submetida à validação do GuardRail, todas as quatro condições abaixo devem ser satisfeitas simultaneamente:

### Gatilho 1: Volume Institucional e Absorção (PVSRA)
A leitura de volume compara a atividade da última vela fechada ($t-1$) contra a média móvel de volume institucional dos últimos 10 períodos:
* **Condição Clímax (Institucional Pesado):**
  $$\text{Volume} \ge 2.0 \times \text{Média do Volume (10)}$$
  OU
  $$\text{Volume} \times \text{Amplitude da Vela} \ge 2.0 \times (\text{Média Volume} \times \text{Média Amplitude})$$
* **Condição Rising (Expansão Agressiva de Volume):**
  $$\text{Volume} \ge 1.5 \times \text{Média do Volume (10)}$$

### Gatilho 2: Alinhamento de Macro-Tendência (EMAs)
O robô nunca opera contra o fluxo dominante institucional:
* **Filtro de Compra:** O fechamento da vela deve estar **estritamente acima** da `EMA 200` e a `EMA 50` deve estar acima da `EMA 200`.
* **Filtro de Venda:** O fechamento da vela deve estar **estritamente abaixo** da `EMA 200` e a `EMA 50` deve estar abaixo da `EMA 200`.

### Gatilho 3: Confirmação da Vela Direcional
* **Compra:** A vela que gerou a absorção de volume deve ser de alta ($\text{Close} \ge \text{Open}$).
* **Venda:** A vela que gerou a absorção de volume deve ser de baixa ($\text{Close} < \text{Open}$).

### Gatilho 4: Janela Institucional de Liquidez (Horário)
Entradas só são permitidas durante janelas de alta liquidez global (dias úteis):
* **Sessão de Londres:** das **08:00 às 12:00 UTC**.
* **Pico de Nova York:** das **15:00 às 19:00 UTC**.
* *Sábados, domingos e madrugadas asiáticas têm entradas bloqueadas por regra de liquidez.*

---

## 3. Gatilhos de Saída (Exit Triggers)

Toda ordem enviada para a corretora já nasce com **Stop Loss (SL)** e **Take Profit (TP)** pré-alocados no servidor da corretora, eliminando risco de execução em quedas de conexão.

### Saída 1: Stop Loss Dinâmico Baseado em ATR (Volatilidade Real)
O stop loss não utiliza pontos arbitrários; ele se adapta à volatilidade do mercado calculada pelo ATR (14 períodos):
$$\text{Distância de SL} = 1.5 \times \text{ATR}(14)$$
* **Ordem de Compra:** $\text{Preço SL} = \text{Preço de Entrada (Ask)} - \text{Distância de SL}$
* **Ordem de Venda:** $\text{Preço SL} = \text{Preço de Entrada (Bid)} + \text{Distância de SL} + \text{Spread}$

### Saída 2: Take Profit com Payoff Assimétrico (R:R 2.0:1)
O objetivo de lucro busca o dobro do risco assumido:
$$\text{Distância de TP} = 2.0 \times \text{Distância de SL}$$
* **Ordem de Compra:** $\text{Preço TP} = \text{Preço de Entrada (Ask)} + \text{Distância de TP}$
* **Ordem de Venda:** $\text{Preço TP} = \text{Preço de Entrada (Bid)} - \text{Distância de TP}$

### Saída 3: Política de Posição Única (Sem Empilhamento / Sem Martingale)
* O sistema opera estritamente com **1 posição ativa por vez** no ativo. 
* Enquanto uma posição estiver em andamento, novos gatilhos são ignorados até que a ordem seja encerrada pelo SL ou pelo TP.

---

## 4. Protocolo Sunrise GuardRail: Validações de Segurança

O **Sunrise GuardRail** atua como um firewall algorítmico. Nenhuma ordem chega à corretora sem passar pelo crivo de todas as regras abaixo:

```
                  [Sinal Quantitativo Detectado]
                                │
                                ▼
    ┌────────────────────────────────────────────────────────┐
    │              AUDITORIAS DO SUNRISE GUARDRAIL           │
    ├────────────────────────────────────────────────────────┤
    │ 1. Spread Drag Check: (Spread / Alvo) <= 5% ?          │
    │ 2. Spread Teto Check: Spread <= Teto Máximo ?          │
    │ 3. Janela de Sessão: Hora UTC em [8-12h ou 15-19h] ?   │
    │ 4. Margem Livre: Margem da ordem <= 20% da livre ?     │
    │ 5. Stops Level: SL e TP > trade_stops_level ?          │
    └────────────────────────────────────────────────────────┘
                                │
                 ┌──────────────┴──────────────┐
              [TODOS OK]                   [FALHOU EM 1+]
                 │                               │
                 ▼                               ▼
       [Liberar Envio Ordem]           [Bloquear Ordem & Alertar UI]
```

### 1. Trava de Fricção de Spread (Spread Drag Ratio)
* **Objetivo:** Impedir que o spread da corretora devore o lucro esperado.
* **Fórmula:**
  $$\text{Spread Drag} = \left(\frac{\text{Spread em Pontos}}{\text{Distância do Take Profit em Pontos}}\right) \times 100$$
* **Regra:** Se $\text{Spread Drag} > 5.0\%$, a ordem é **rejeitada imediatamente**.
* **Impacto Comprovado:** Elimina trades com baixa expectativa matemática causados por spreads altos ou alvos curtos.

### 2. Teto Máximo de Spread Absoluto
* Em momentos de notícias econômicas de alto impacto ou fechamento de mercado, o spread pode alargar anormalmente.
* **Limites Máximos:**
  * **XAUUSD-VIP:** Máximo de **50 pontos** (\$0,50 por onça).
  * **BTCUSD:** Máximo de **3.000 pontos** (\$30,00 por Bitcoin).
* Qualquer cotação acima desses tetos suspende novas ordens.

### 3. Trava de Margem Comprometida
* Antes de alocar o lote, o GuardRail simula a margem exigida via `order_calc_margin()`.
* Se a margem da nova ordem comprometer mais de **20% da margem livre**, o lote é redimensionado ou a ordem é abortada para blindar a conta contra *Margin Call* (50%) ou *Stop Out* (20%).

### 4. Dimensionamento Estrito de Risco (1.0% por Trade)
* O lote é recalculado a cada nova oportunidade com base no patrimônio líquido atual:
  $$\text{Risco Financeiro (\$} = \text{Saldo} \times 0.01$$
  $$\text{Lote} = \frac{\text{Risco Financeiro}}{\text{Distância do SL em Ticks} \times \text{Valor do Tick}}$$
* O lote é normalizado dentro do `volume_step`, `volume_min` e `volume_max` do ativo.

---

## 5. Especificações de Ativos e Custos na VT Markets

Dados auditados diretamente da conta demo institucional (`1123867`):

| Parâmetro | BTCUSD | XAUUSD-VIP |
| :--- | :---: | :---: |
| **Categoria** | Cripto CFD | Ouro Spot VIP |
| **Tamanho do Contrato (1 Lote)** | 1.0 Bitcoin | 100 onças troy |
| **Lote Mínimo / Passo** | 0.01 / 0.01 | 0.01 / 0.01 |
| **Dígitos / Tamanho do Ponto** | 2 (\$0,01) | 2 (\$0,01) |
| **Spread Típico** | ~1.696 pts (\$16,96 / BTC) | ~27 pts (\$0,27 / oz) |
| **Comissão por Lote** | **\$0,00** (Zero) | **\$0,00** (Zero) |
| **Margem Requerida (Lote 0.01)** | **\$1,66** | **\$8,36** |
| **Valor de 1 Ponto (0.01 Lote)** | \$0,0001 | \$0,01 |
| **Variação de \$1.00 (0.01 Lote)** | \$0,01 | \$1,00 |
| **Swap Long (Compra)** | -20,0% ao ano | -79.48 pts/noite |
| **Swap Short (Venda)** | **0,0%** (Isento) | **+34.41 pts/noite** (Crédito) |
| **Dia de Rollover Triplo** | Sexta-feira | Quarta-feira |

---

## 6. Guia Operacional

### Como Executar o Robô no Terminal Local
1. Certifique-se de que o **MetaTrader 5** está aberto e logado na conta.
2. Certifique-se de que o botão **"Algo Trading" (Negociação Automatizada)** está ativo (verde) na barra superior do MT5.
3. No terminal Windows (PowerShell), execute o motor:
   ```powershell
   cd "C:\Plano de Trading"
   python motor_xauusd_demo.py
   ```
4. A janela do **Sunrise GuardRail Dashboard** será aberta exibindo:
   * Status da conexão com o MT5
   * Leitura do ATR e PVSRA em tempo real
   * Indicador visual do Spread e taxa de Spread Drag
   * Botão de ativação: clique em **"ROBÔ DESLIGADO"** para armar o sistema (**"ROBÔ LIGADO"**).

### Como Realizar Testes e Backtest no Google Colab
1. Acesse o [Google Colab](https://colab.research.google.com/).
2. Faça o upload do notebook [btcusd_colab_analysis.ipynb](file:///C:/Plano%20de%20Trading/btcusd_colab_analysis.ipynb).
3. Na célula de carregamento de dados, faça o upload do dataset [data/BTCUSD_M15.parquet](file:///C:/Plano%20de%20Trading/data/BTCUSD_M15.parquet).
4. Execute todas as células para visualizar a simulação ordem a ordem, comparativo de estratégias com e sem filtro de sessão, e curvas interativas de patrimônio e drawdown.
