# MEMÓRIA & INTELIGÊNCIA INSTITUCIONAL: SISTEMAS DINÂMICOS, ATRATORES E FLUXO BOOKMAP

> **Origem dos Dados**: Reuniões e Apresentações Técnicas (Mikael Bradford S. R. Sepaul - SunriseMGR & Sepaul Research com #Burgo585 e Marcus Plech - Outubro de 2026).
> **Ativos de Aplicação**: XAUUSD (Ouro Spot / Futuros COMEX GC), BTCUSD e Índices.

---

## 1. Fundamentos Teóricos: Atratores e Transições de Fase de Landau

### 1.1. A VWAP como Atrator Não-Linear e Bifurcação de Forquilha Supercrítica
* Rejeição da hipótese de que preços são variáveis Independentes e Identicamente Distribuídas (IID).
* Séries financeiras comportam-se como **variedades estocásticas dissipativas não-lineares** modeladas pela **Equação de Langevin com Potencial de Ginzburg-Landau de 4ª ordem**:
  $$\frac{d(\delta P)}{dt} = -\frac{\partial U(\delta P)}{\partial (\delta P)} + \sigma(\delta P) \cdot \xi(t)$$
  onde $\delta P(t) = P(t) - P_{atrator}(t)$ e $U(\delta P)$ é o potencial efetivo de liquidez.
* **Bifurcação da VWAP**:
  * **Regime Antipersistente ($\alpha_{DFA} < 0.48$)**: A VWAP atua como um **Atrator Elástico Estável** (força restauradora elástica). Quando o preço se afasta e forma exaustão/pavio, ele é puxado de volta para o centro do poço de potencial (Mean Reversion / Absorção na VWAP).
  * **Regime de Fluxo Anômalo / Balístico ($\alpha_{DFA} \ge 0.52$)**: A VWAP sofre bifurcação e torna-se um **Repulsor Balístico de Escape**. O preço rompe com agressão massiva e acelera em tendência direcional (Valid BOS).

---

## 2. Teorema do Headroom Geométrico

> **Regra de Ouro**: A existência de um sinal ou atrator é condição necessária, porém **estritamente insuficiente** para abrir uma posição.

* **Fórmula do Headroom Geométrico ($R_{geo}$)**:
  $$R_{geo} = \frac{D_{barreira}}{D_{stop}} \ge 1.80$$
  * $D_{barreira}$: Distância em pontos do ponto de entrada até a barreira de liquidez estrutural mais próxima (Parede de Liquidez do Bookmap, Topo/Fundo ou POC institucional).
  * $D_{stop}$: Distância em pontos do ponto de entrada até o Stop Loss técnico estrutural.
* **Veto de Operação**: Se $R_{geo} < 1.80$, o trade é **sumariamente vetado**, pois o espaço livre ("headroom") é insuficiente para garantir assimetria matemática positiva.

---

## 3. Gestão de Saída e Execução

### 3.1. Execução Dual-Tranche
* **Perna 1 (Scalp - 50%)**: Alvo curto de alta probabilidade ($+250$ pts). Garante lucro rápido e remunera a operação.
* **Perna 2 (Runner - 50%)**: Deixada para surfar a tendência mirando as Paredes de Liquidez do Bookmap ou relação $1:3$ R:R.
* **Break-Even Obrigatório**: Assim que a perna Scalp atinge o TP1, o Stop Loss da perna Runner é movido instantaneamente para o preço de abertura ($0 \times 0$ ou $0 \times 0 + \text{taxas}$).

### 3.2. Trailing Barra-a-Barra Estrutural
* Condução do Stop da perna Runner baseado no extremo da barra anterior ($L_{t-1} - 0.20$ na compra ou $H_{t-1} + 0.20$ na venda).
* **Colheita Antecipada (Front-Running)**: Quando o preço atinge $\ge 75\%$ do caminho até a barreira de liquidez, apertar o trailing stop e encerrar a mercado se houver absorção contrária.

---

## 4. Poço Estático vs. Poço Estocástico

1. **Poço Estático (M15 / Intraday)**:
   * Níveis de volume acumulado passados, POCs fixos de sessões anteriores, Suportes e Resistências estáticos.
2. **Poço Estocástico (H1 e H4 - Dinâmico)**:
   * Zonas em mutação contínua alimentadas pelo fluxo de ordens limite (DOM/Heatmap) e volume real.
   * Interseção entre Poço Estático e Poço Estocástico gera os pontos de maior fricção e reversão do mercado.

---

## 5. Arquitetura Bookmap MBO + MT5 Spot

* **Bookmap (COMEX GC - Futuros)**:
  * Visão contínua em **MBO (Market by Order)**: Heatmap histórico, spoofing, ordens iceberg, bolhas de agressão e Cumulative Volume Delta (CVD).
* **MetaTrader 5 (XAUUSD Spot - Corretora)**:
  * Execução rápida e gestão de lote.
* **Rastreamento de Basis ($\Delta P$)**:
  $$\text{Basis} = P_{COMEX} - P_{MT5}$$
  $$\text{Nível MT5} = \text{Nível Bookmap} - \text{Basis}$$
* Garante projeção milimétrica de VWAP, POC, HVN e Paredes de Liquidez diretamente nas velas do MT5.
