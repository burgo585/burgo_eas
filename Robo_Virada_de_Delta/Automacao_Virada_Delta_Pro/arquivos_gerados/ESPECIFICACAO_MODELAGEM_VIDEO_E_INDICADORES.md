# ESPECIFICAÇÃO TÉCNICA E MATEMÁTICA DO PROJETO DE AUTOMAÇÃO
## Base Teórica: Dinâmica Não-Linear, Atratores e Microestrutura (Sepaul Research & SunriseMGR)
## Base Operacional: Motores MTR_PVSRA e MTR-Volume-AT-Price-Pro

---

## 1. DADOS DE ORIGEM E REGISTRO DO VÍDEO ANALISADO
- **Arquivo analisado:** `Meet_ bds-uzvw-jmb - Brave 2026-10-16 01-29-19.mp4`
- **Origem:** Captura de tela de reunião Google Meet (`bds-uzvw-jmb`), gravada em 16/10/2026.
- **Participantes:**
  - **Mikael Sepaul** (Apresentador / Pesquisador)
  - **#Burgo585** (Vini Burgo)
  - **Marcus Plech**
- **Documento Apresentado:** 
  - Repositório: `SunriseMGR / papers / 00_sistemas_dinamicos_atratores / nonlinear_attractor_paper_v6.pdf`
  - Título do Paper: *"Uma Abordagem Institucional de Microestrutura de Alta Resolução (M5), Transições de Fase de Landau, Geometria de Headroom, Trailing Estrutural e Modelos Ensemble Stacking"*
  - Autor: Mikael Bradford S. R. Sepaul (ORCID: 0009-0005-9817-2488)
  - Afiliação: Sepaul Research & SunriseMGR Quantitative Research & Behavioral Governance
  - Contato: `mikael@sepaulresearch.com` | Website: `sepaulresearch.com`
  - Classificação JEL / AMS: C51, C58, D81, G12, G14, 37D45

---

## 2. RESUMO EXECUTIVO & SUMÁRIO ABSTRATO (TRANSCRIÇÃO LITERAL E CONCEITUAL)

1. **Rejeição da Hipótese do Mercado Eficiente (HME) e Variáveis IID:**
   - Séries temporais de ativos altamente líquidos (com foco em Ouro Spot `XAUUSD` e Bitcoin `BTCUSD`) **não** se comportam como passeios aleatórios gaussianos.
   - Apresentam caudas pesadas (curtose excessiva), agrupamento de volatilidade (*volatility clustering*) e regimes estocásticos dissipativos não-lineares.

2. **Equação de Langevin & Potencial de Ginzburg-Landau de 4ª Ordem:**
   - A trajetória dos preços é modelada como uma **órbita cinemática sobre uma variedade de baixa dimensão** governada por estados atratores.
   - A $\text{VWAP}_{24h}$ sofre uma **bifurcação de forquilha supercrítica**:
     - **Regime Antipersistente ($\alpha_{DFA} < 0.48$):** A VWAP atua como um **atrator elástico estável** (força restauradora / reversão à média).
     - **Regime Persistente / Fluxo Anômalo ($\alpha_{DFA} \ge 0.52$):** A VWAP sofre quebra de simetria e torna-se um **repulsor balístico de velocidade de escape** (tendência explosiva / expansão).

3. **Teorema do Headroom Geométrico:**
   - A mera existência de um atrator ou reversão é condição necessária, porém **estritamente insuficiente** para justificar um trade.
   - Qualquer entrada é **sumariamente vetada** se a assimetria geométrica de espaço livre até a barreira de liquidez estrutural mais próxima não satisfizer:
     $$R_{geo} = \frac{D_{barreira}}{D_{stop}} \ge 1.80x$$

4. **Protocolo de Saída e Gestão de Posição:**
   - **Trailing Barra-a-Barra Estrutural:** Stop móvel ancorado na mínima/máxima da barra anterior com offset:
     $$SL_t = L_{t-1} - 0.20 \quad (\text{para compra}) \quad \text{ou} \quad SL_t = H_{t-1} + 0.20 \quad (\text{para venda})$$
   - **Aperto por Exaustão:** Aceleração do stop quando o volume clímax ou absorção for detectado no sentido favorável.
   - **Colheita Antecipada (*Front-Running*):** Realização compulsória ao atingir $\ge 75\%$ da meta / barreira de liquidez.

5. **Auditoria Empírica Global Comprovada:**
   - **Corpus de 6 anos (2021 a 2026):** 407.232 barras consecutivas de M5 no Ouro Spot (`XAUUSDz`).
   - **Fricção Real Exness Conta Zero:** USD 0.24 / oz (USD 0.05 spread + USD 0.16 comissão + USD 0.03 slippage).
   - **Dimensionamento por Quarter-Kelly Dinâmico:** $1,5\%$ a $4,5\%$ de Equity.
   - **Resultados:**
     - Retorno líquido: **+134,23%** (com juros compostos reais).
     - Drawdown Máximo: **15,92%**.
     - Calmar Ratio: **8,43x**.
     - Win Rate: **56,2%**.
     - Profit Factor: **1,51x**.
     - Redução de stops cheios em **80,6%** (de 36 para apenas 7 stops cheios).
   - **Auditoria 2024-2026 (702 Trades Reais):**
     - Lucro Líquido Acumulado: +USD 3.052,36 (lote base 0.10).
     - Sharpe Ratio (dias ativos): 1,93 | Calmar Ratio: 4,24x | Rebaixamento Máx: USD 720,02.
     - Invariância Forense de 2026: 100% dos meses positivos ou neutros.

---

## 3. TABELA CONSOLIDADA DE NOTAÇÃO MATEMÁTICA, GRANDEZAS FÍSICAS E FÓRMULAS CANÔNICAS

| Símbolo | Grandeza / Conceito Físico | Formulação Canônica / Definição | Unidade | Regime / Limiar de Decisão |
| :--- | :--- | :--- | :--- | :--- |
| **$P(t)$** | Preço Spot do Ativo (`XAUUSD`) | Trajetória de estado observável no espaço contínuo | USD / oz | $P_t \in \mathbb{R}^+$ |
| **$\tau$** | Atraso de Imersão de Takens | Primeiro mínimo local da Informação Mútua Média $I(\tau)$ | barras (min) | $\tau^* = 3$ barras (45 min no M15 / 15 min no M5) |
| **$m$** | Dimensão de Imersão Topológica | Convergência de Falsos Vizinhos Mais Próximos (FNN) | adimensional | $m = 4$ dimensões no espaço de fase |
| **$\Delta_t$** | Deformação Elástica Instantânea | $\Delta_t = \frac{P_t - T_t}{\sigma_t}$ (Afastamento do vórtice Tenkan) | adimensional | $|\Delta_t| \ge 2.5$ (*Strain Injection* / Deformação Extrema) |
| **$\kappa_i$** | Rigidez Elástica do Atrator $i$ | Derivada de restauração: $\kappa_i = -\beta_i$ (Lasso penalizado) | adimensional | $\kappa > 0$ (Atrator Estável) \| $\kappa < 0$ (Repulsor Balístico) |
| **$U(P)$** | Paisagem de Potencial Efetivo | $U(P) = -\int D^{(1)}(P) dP$ (Integração de Kramers-Moyal) | $\text{USD}^2/\text{oz}^2$ | *Multi-well* local (Poços de liquidez) |
| **$\alpha_{DFA}$** | Expoente True DFA-1 (Hurst) | Inclinação logarítmica de escala: $\log F(s) = \alpha \log s + C$ | adimensional | $\alpha \ge 0.52$ (Tendência/Escape) \| $\alpha < 0.48$ (Reversão/Atrator) |
| **$\text{VWAP}_{24h}$** | Preço Médio Ponderado por Volume | $\text{VWAP}_t = \frac{\sum_{i=1}^w P_i V_i}{\sum_{i=1}^w V_i} \quad (w = 96 \text{ barras M15 = 24h})$ | USD / oz | Consenso Institucional Diário |
| **$\text{EMA}_{50}^{M30}$** | Média Exponencial Macro M30 | $\text{EMA}_t = \lambda P_t + (1-\lambda)\text{EMA}_{t-1} \quad (\lambda = \frac{2}{50+1})$ | USD / oz | Poço Macro de Gravitação / Alvo |
| **$\text{VolRatio}$** | Razão de Volume Institucional | $\text{VolRatio}_t = \frac{V_t}{\text{SMA}_{20}(V)}$ | adimensional | $\text{VolRatio} \ge 1.20$ (Expansão Institucional) |
| **$\Omega_t$** | Índice de Autodestruição Varejista | $\Omega_t = \left(\frac{\|P_{entry} - T_t\|}{\sigma_t}\right) \times \left(\frac{\|P - SL\|}{\|P - TP\|}\right) \times \Psi_{imb}$ | adimensional | $\Omega_t > 2.0$ (**VETO SUMÁRIO DA OPERAÇÃO**) |
| **$\text{ATR}_{14}$** | Amplitude Real Média de Wilder | $\text{EWM}_{\alpha=1/14}(\max(H-L, \|H-C_{-1}\|, \|L-C_{-1}\|))$ | USD / oz | Régua de Escala / Normalização |
| **$VAL, VAH$** | Fronteiras da Área de Valor | Corte dos percentis de 70% da integral de volume do VPVR | USD / oz | Limiares de Aceitação / Desconto e Prêmio |
| **$POC$** | Point of Control (Pico do VPVR) | $\arg\max_P f_V(P)$ (Pico de máxima densidade de leilão em 24h) | USD / oz | Centróide de Leilão / Ímã Primário |
| **$\gamma_{esc}$** | Velocidade de Fuga da VWAP | Taxa cinética $\|\dot{P}_t\| > \sqrt{2 D^{(2)}}$ cruzando a VWAP | $\text{USD}/(\text{oz}\cdot\text{min})$ | Fuga Repulsiva (Rompimento Balístico) |
| **$R_{geo}$** | Headroom Geométrico Estrutural | Razão de espaço livre até a barreira: $\frac{D_{barreira}}{D_{stop}}$ | adimensional | $R_{geo} \ge 1.80x$ (**Filtro de Entrada Mandatório**) |
| **$f_{quarter}$** | Fração de Quarter-Kelly Dinâmica | $f_{quarter} = \frac{f^*}{4} \in [1,5\%, 4,5\%]$ da Equity real | adimensional (%) | Dimensionamento Ótimo de Risco por Trade |

---

## 4. FORMULAÇÕES FÍSICO-MATEMÁTICAS DETALHADAS

### 4.1 Teorema de Takens & Reconstrução do Espaço de Fase
A dinâmica dos preços no espaço de estados $\mathcal{M}$ é reconstruída por:
$$\vec{x}(t) = \left[ P(t), P(t-\tau), P(t-2\tau), \dots, P(t - (m-1)\tau) \right]^T \in \mathbb{R}^m$$
- **Atraso Ótimo ($\tau^*$):** Determinado pela Informação Mútua Média:
  $$I(\tau) = \sum_{P(t), P(t-\tau)} \mathbb{P}(P(t), P(t-\tau)) \log_2 \left( \frac{\mathbb{P}(P(t), P(t-\tau))}{\mathbb{P}(P(t))\mathbb{P}(P(t-\tau))} \right)$$
  Para o Ouro Spot M15: $\tau^* = 3$ barras (45 minutos); para M5: $\tau^* = 3$ barras (15 minutos).
- **Dimensão de Imersão ($m$):** Pelo método dos Falsos Vizinhos Mais Próximos (FNN), fixa-se $m = 4$.
- **Retrato de Fase 2D:**
  - Eixo Vertical: Velocidade Cinemática $\gamma_t = \frac{\partial P}{\partial t} \approx \frac{P_t - P_{t-1}}{\Delta t}$.
  - Eixo Horizontal: Deformação Elástica $\Delta_t = \frac{P_t - T_t}{\sigma_t}$.
  - Zona de Equilíbrio / Coerência Determinística: $|\Delta_t| \le 1.0$.
  - Zona de Injeção de Tensão (*Strain Injection*): $|\Delta_t| \ge 2.5$.

### 4.2 Equação Estocástica de Langevin e Kramers-Moyal
O afastamento do preço em relação a um atrator $\delta P(t) = P(t) - P_{atrator}(t)$ segue a Equação Diferencial Estocástica de Langevin:
$$\frac{d(\delta P)}{dt} = -\frac{\partial U(\delta P)}{\partial (\delta P)} + \sigma(\delta P) \cdot \xi(t)$$
onde:
- $U(\delta P)$ denota a paisagem de potencial efetivo.
- $\xi(t)$ é ruído branco gaussiano satisfazendo $\langle \xi(t) \rangle = 0$ e correlação delta $\langle \xi(t)\xi(t') \rangle = 2\delta(t-t')$.
- Os coeficientes de Kramers-Moyal de ordem $k$ são dados por:
  $$D^{(k)}(x) = \frac{1}{k!} \lim_{\Delta t \to 0} \frac{1}{\Delta t} \int (y - x)^k \mathbb{P}(y, t+\Delta t \mid x, t) \, dy$$
  - $D^{(1)}(x)$: Coeficiente de Deriva Determinística (*Drift*).
  - $D^{(2)}(x)$: Coeficiente de Difusão Estocástica (*Diffusion / Volatilidade intrínseca*).
- O potencial macroscópico $U(x)$ é derivado integrando a deriva negativa:
  $$U(x) = -\int_{x_0}^x D^{(1)}(y) \, dy$$

### 4.3 Figura 2 do Artigo: Paisagem Multiestável e Bifurcação Saddle-Node
Conforme detalhado na **Figura 2** (*The Non-Linear Dissipative Potential Well $V(\Delta_t)$ and Saddle-Node Bifurcation*):
1. **Poço de Potencial Harmônico (Regime $\alpha$ - Restoring Elastic Drift):**
   - Para deformações controladas dentro dos limites do leilão ($-\Delta_{crit} \le \Delta_t \le +\Delta_{crit}$):
     $$V(\Delta) = \frac{1}{2} \kappa \Delta^2 \quad \text{(Harmonic Continuation)}$$
   - A força elástica restauradora atua puxando o preço de volta ao centróide/atrator $T_t$:
     $$F_{restore} = -\kappa \cdot \Delta_t$$
   - Regime Antipersistente / Browniano ($H \le 0.57$). A derivada determinística $D^{(1)}(x)$ cruza zero com inclinação negativa ($\frac{d D^{(1)}}{dx} < 0$), provando a estabilidade assintótica local nos limites da Área de Valor ($VAL$ e $VAH$).
2. **Limiares Críticos de Tensão:**
   - $-\Delta_{crit} = -2.5$ e $+\Delta_{crit} = +2.5$, calculados via deformação elástica normalizada:
     $$\Delta_t = \frac{|P_t - T_t|}{\sigma_t}$$
3. **Colapso de Barreira e Bifurcação Saddle-Node (Regime $\gamma$ - Breakout Runaway):**
   - Quando $|\Delta_t| > 2.5$ e o expoente de Hurst indica persistência superdifusiva ($H > 0.57$), ocorre a ruptura da barreira de potencial (*Saddle-Node Bifurcation Barrier Collapse & Runaway*).
   - O preço deixa o regime de oscilador elástico harmônico e entra em aceleração cinética livre (rompimento violento e continuação de tendência).

### 4.4 Seção 2.3 do Artigo: Paisagem de Langevin Multi-Well Inter-Timeframes
Os participantes do mercado operam em múltiplos horizontes temporais sobrepostos (desde a arbitragem de alta frequência até tesourarias soberanas e fundos de pensão macroeconômicos). Em decorrência dessa heterogeneidade informacional, o preço do ouro spot não está restrito a um poço isolado, mas é governado por uma **paisagem de potencial multiestável multi-escala**:

$$U_{total}(P) = \sum_{\tau \in \{M15, M30, H1, H4\}} w_\tau \cdot U_\tau(P)$$

onde:
- $\tau \in \{M15, M30, H1, H4\}$ representa os horizontes temporais estruturais.
- $w_\tau$ são os pesos ponderados de liquidez e volume relativo de cada timeframe ($\sum w_\tau = 1$).
- $U_\tau(P)$ é o perfil de energia de potencial gerado pelas zonas de leilão de cada período.

### 4.5 Hierarquia Conceitual dos Poços de Potencial e Relação com BOS (Break of Structure)
Conforme esquematizado e debatido durante a aula (Vídeo 2):
```
      [ POÇO ESTÁTICO (M15) ]
                |
             [ PREÇO ] ---------------> [ POÇO ESTOCÁSTICO (H4) ] (Macro Barreira)
                |
[ POÇO ESTOCÁSTICO (H1) ] <-----> [ SUPORTES E RESISTÊNCIAS / VOLUME AT PRICE ]
```
1. **Poço Estático (M15):**
   - Formado pelos níveis estáticos intraday: limites de leilão local ($VAL$, $VAH$, $POC$), níveis psicológicos inteiros/meios/quartos do PVSRA, e bandas do Dragon EMA 34.
2. **Poço Estocástico (H1):**
   - Formado por suportes e resistências de fluxo dinâmico, High Volume Nodes (HVNs) do perfil de 24h e Naked POCs diários não testados.
3. **Poço Estocástico (H4):**
   - Atrator macroeconômico primário (tendência da EMA 200, VWAP ancorada semanal/mensal), determinando o vetor diretor do fluxo institucional.
4. **Alinhamento com BOS (Break of Structure):**
   - Quando o preço produz um BOS rompendo um suporte/resistência chave com volume anormal v6 ou clímax PVSRA, ocorre o colapso da barreira do poço local M15/H1 ($|\Delta_t| > 2.5$ e $H > 0.57$). O fluxo institucional acelera através de vácuos de liquidez (LVNs) em direção à próxima barreira estável no poço estocástico macro H4.

---

## 5. MAPEAMENTO E CONVERGÊNCIA DOS INDICADORES FORNECIDOS

A automação unificará as ferramentas já implementadas nos arquivos `MTR_PVSRA.mq5` e `MTR-Volume-AT-Price-Pro.mq5`, cruzando com a formulação física de Sepaul:

```
+-----------------------------------------------------------------------------------------+
|                                ARQUITETURA DO ROBÔ                                      |
+-----------------------------------------------------------------------------------------+
|                                                                                         |
| 1. CAMADA DE ESTADO & TOPOLOGIA (Volume At Price Pro + Takens)                         |
|    - Perfil de Volume VPVR Adaptativo (POC 24h, VAH, VAL) -> Centróides de Leilão       |
|    - VWAP 24h Institucional -> Atrator Elástico / Repulsor de Fuga                     |
|    - High Volume Nodes (HVN) -> Ímãs Secundários de Liquidez                            |
|    - Low Volume Nodes (LVN) -> Vácuos de Liquidez / Aceleração Cinética                 |
|    - Naked POCs (D-1, W-1) -> Ímãs Históricos Não-Testados                              |
|                                                                                         |
| 2. CAMADA DE MICROESTRUTURA & FLUXO (PVSRA + Tape Tick-a-Tick)                          |
|    - Detecção de Candles Clímax (Bull/Bear) e Rising (Verde, Vermelho, Azul, Roxo)     |
|    - Limiar de Volume Anormal v6 Dinâmico por EMA de ADV                                |
|    - Canal Dragon (EMA 34 High/Low/Median) -> Vórtice Tenkan / Linha Central            |
|    - Tendência Macro (EMA 200 / EMA 50 M30) -> Vetor de Deriva Institucional            |
|    - Fita Tick-a-Tick com Delta Comprador/Vendedor e Absorções de Topo/Fundo            |
|                                                                                         |
| 3. CAMADA DE FILTRAGEM & REGRAS MATEMÁTICAS ESTRITAS (Paper Sepaul)                     |
|    - Teste de Deformação Elástica: |Delta_t| >= 2.5 (Afastamento do Vórtice)            |
|    - Teorema do Headroom Geométrico: R_geo = D_barreira / D_stop >= 1.80x (Mandatório)   |
|    - Índice de Autodestruição Varejista: Omega_t <= 2.0 (Filtro Anti-Armadilha)         |
|    - Regime de Persistência DFA / Hurst: Reversão se Antipersistente, Escape se Balístico|
|                                                                                         |
| 4. CAMADA DE EXECUÇÃO, GESTÃO & SAÍDA                                                   |
|    - Dimensionamento de Lote por Quarter-Kelly Dinâmico (1.5% a 4.5% de risco)           |
|    - Alvo Parcial 1 (70%): No POC ou no Primeiro Ímã HVN                                |
|    - Alvo Final 2: Na barreira oposta (VAH/VAL ou Projeção Estrutural)                 |
|    - Colheita Antecipada (Front-Running): Realização a >= 75% da barreira               |
|    - Trailing Barra-a-Barra Estrutural (L_{t-1} - 0.20 ou H_{t-1} + 0.20)              |
|    - Saída por Exaustão: Encerramento imediato se surgir Clímax Oposto no PVSRA         |
+-----------------------------------------------------------------------------------------+
```

---

## 6. ESTRUTURA DOS ARQUIVOS DO PROJETO

Na pasta `c:\Robo Virada de Delta\Automacao_Virada_Delta`:
1. `ESPECIFICACAO_MODELAGEM_VIDEO_E_INDICADORES.md` (Este documento mestre).
2. `Include/`:
   - `PVSRA_Core.mqh`: Motor matemático do cálculo PVSRA (Volume Clímax, Rising, Volume Anormal v6, Dragon).
   - `VAP_Core.mqh`: Motor de Volume At Price (VPVR adaptativo, POC, VAH, VAL, HVN, LVN, Naked POCs, Micro-Delta).
   - `Nonlinear_Attractor_Core.mqh`: Módulo matemático de Langevin, Deformação Elástica $\Delta_t$, Headroom Geométrico $R_{geo}$, Índice $\Omega_t$ e Trailing Estrutural.
   - `Risk_Manager.mqh`: Dimensionamento por Quarter-Kelly Dinâmico e controle de rebaixamento.
3. `Robo_Virada_Delta_Pro.mq5`: O Expert Advisor institucional completo, pronto para compilação e operação no MetaTrader 5.
