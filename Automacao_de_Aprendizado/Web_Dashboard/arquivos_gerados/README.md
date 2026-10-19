# 🌟 Central de Gestão de Risco & Educação Financeira (Sunrise Quant)

Automação local interativa desenvolvida para dimensionamento institucional de risco, análise de fricção real (spread, swap, slippage), avaliação de volatilidade ATR e aprendizado quantitativo com foco em **XAUUSD (Ouro)**, **BTCUSD (Bitcoin)** e **NAS100 (Nasdaq 100)**.

---

## 🚀 Como Iniciar

Basta dar **2 cliques** no arquivo:
```text
iniciar_dashboard.bat
```
Ou executar no terminal PowerShell / CMD dentro desta pasta:
```bash
python server.py
```
O painel abrirá automaticamente no seu navegador no endereço:
**`http://localhost:8000`**

---

## 🧮 O Que a Aplicação Faz

### 1. Calculadora Institucional & Raio-X Real
* **Dimensionamento Dinâmico de Lote:** Calcula o tamanho exato de lote para respeitar estritamente o risco percentual ($\le 1.0\%$ ou $0.5\%$ para mesas proprietárias).
* **Fricção Invisível:** Separação entre perda nominal vs. **perda real** (incluindo Spread, Comissão da corretora e Swap acumulado).
* **Volatilidade & Ruído (ATR):** Alerta instantâneo quando o Stop Loss estiver menor que $1.2\times\text{ATR}$ (risco de violinada browniana).
* **Boleta Pronta:** Gera a boleta no padrão do MetaTrader 5 / cTrader com botão de 1 clique para copiar (`Copiar Boleta`).
* **Presets Rápidos:**
  * 🥇 Scalping Ouro (XAUUSD)
  * 🏛️ Cripto / Bitcoin (BTCUSD)
  * ⚡ Day Trade Nasdaq (NAS100)
  * 🏆 Mesa Proprietária (Prop Firm - Risco 0.5%)
  * 🌙 Swing Trade & Carry (simulação com swap de múltiplos dias)

### 2. Tabela de Assimetria & Simulador de Ruína
* **Simulador Interativo com Slider:** Permite simular qualquer nível de perda (de 5% a 95%) e calcula instantaneamente a rentabilidade necessária para recuperar a conta.
* **Tabela de Esforço de Recuperação (Drawdown):** Mostra a assimetria matemática ($10\% \to +11.1\%$, $50\% \to +100\%$, etc.).
* **Resistência a Sequências de Perdas:** Compara a sobrevida da conta com riscos de 0.5%, 1.0%, 2.0% e 5.0% (Zona de Ruína).

### 3. Radar Macroeconômico & Sessões
* Horários nobres de liquidez institucional (Londres, Nova York, Overlap, Tóquio) no horário de Brasília (UTC-3).
* Filtro de notícias vermelhas de alto impacto (NFP, CPI, FOMC, BCE/BoE) e protocolo de segurança dos 15 minutos.

### 4. Central de Aprendizado Integrada
* **Pilares de Risco:** Travas de risco obrigatórias, a realidade dos 90% que quebram, proibição de Martingale/preço médio.
* **Engenharia de Bots:** As 4 camadas desacopladas (Signal Engine, Risk Governor, Execution Handler, Audit Logger).
* **Filtros de Execução:** Spread máximo, filtros de horários de liquidez, proteção contra timeout e Magic Number.
* **Funil de Produção (4 etapas):** Do Backtest com 99% de ticks reais até a conta real escalada.
* **Grade Curricular:** Aulas estruturadas do Módulo 0 ao Módulo 4.

---

## 📁 Estrutura de Arquivos

```text
Automação de Aprendizado/
├── engine/
│   ├── assets_db.py       # Especificações de XAUUSD, BTCUSD, NAS100
│   ├── calculators.py     # Motor quantitativo (lote, fricção, ATR, drawdown)
│   └── presets.py         # Setups rápidos pré-configurados
├── content/
│   └── knowledge_base.py  # Conteúdo teórico e didático completo das imagens
├── server.py              # Backend FastAPI
├── web/                   # Interface visual moderna (Dark Mode)
│   ├── index.html         # Estrutura do painel e abas
│   ├── styles.css         # Visual institucional estilo Discord/TradingView
│   └── app.js             # Reatividade instantânea e lógica do frontend
├── iniciar_dashboard.bat  # Inicializador rápido com 2 cliques
└── README.md              # Documentação do projeto
```
