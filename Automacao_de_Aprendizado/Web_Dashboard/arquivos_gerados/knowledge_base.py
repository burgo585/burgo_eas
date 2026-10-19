"""
knowledge_base.py - Base de Conhecimento e Módulos Didáticos Educativos.
Estruturado EXATAMENTE conforme os canais e categorias do Discord das imagens do usuário:

1. 🛡️ PILARES DE RISCO & SOBREVIVÊNCIA
2. 🧪 VALIDAÇÃO & BACKTESTING REALISTA
3. 🤖 ENGENHARIA & ARQUITETURA DO BOT
4. 🚀 DO CÓDIGO À CONTA REAL
5. 📚 MÓDULO 0: FUNDAMENTOS & RISCO
6. 💻 MÓDULO 1: AMBIENTE & ARQUITETURA
7. 🤖 MÓDULO 2: PROGRAMAÇÃO DO ROBÔ
8. 🧪 MÓDULO 3: BACKTEST & VALIDAÇÃO
9. 🚀 MÓDULO 4: OPERAÇÃO EM PRODUÇÃO
"""

from typing import Dict, Any, List

# Estrutura unificada de Categorias e Canais
DISCORD_CATEGORIES: List[Dict[str, Any]] = [
    {
        "category_id": "pilares_risco",
        "title": "🛡️ PILARES DE RISCO & SOBREVIVÊNCIA",
        "channels": [
            {
                "id": "travas-de-risco-obrigatorias",
                "title": "# 🛑-travas-de-risco-obrigatorias",
                "header": "🛑 TRAVAS DE RISCO OBRIGATÓRIAS: ANTES DE QUALQUER CÓDIGO",
                "subtitle": "Regras de proteção do capital antes de ligar qualquer robô ou abrir ordens.",
                "content_markdown": """
### 🛑 TRAVAS DE RISCO OBRIGATÓRIAS: ANTES DE QUALQUER CÓDIGO
Criar um robô lucrativo não começa pela estratégia de entrada, **começa pelas travas de segurança**.

Sem um sistema de proteção matemático, qualquer robô eventualmente quebrará a conta em momentos de alta volatilidade ou anomalia de mercado.

---

#### 1. Regra de Ouro: Risco Fixo Máximo por Trade (≤ 1.0%)
* O tamanho do lote (*lot size*) **NUNCA** deve ser fixo. Ele deve ser calculado dinamicamente em cada entrada:
```python
Lote = (Capital * 0.01) / (Distancia_Stop_Pontos * Valor_Ponto)
```
* **Stop Loss é obrigatório** no envio da ordem. Proibido qualquer trade sem stop.

#### 2. Trava Diária de Perda (Daily Drawdown Lock)
* Se o robô atingir **2% a 3% de perda no dia**, ele encerra todas as ordens e **trava até o dia seguinte**.
* Isso impede que o algoritmo entre em espiral de perda durante notícias atípicas.

#### 3. Proibição Absoluta de Martingale & Preço Médio
* Dobrar lote após perdas ou segurar posições perdedoras sem stop dá a ilusão de 99% de acerto, mas com **100% de certeza de falência matemática** a longo prazo.

#### 4. A Matemática da Assimetria de Perda
* Perda de 10% → Exige **+11.1%** de lucro para empatar
* Perda de 20% → Exige **+25.0%** de lucro para empatar
* Perda de 30% → Exige **+42.8%** de lucro para empatar
* Perda de 50% → Exige **+100.0%** de lucro para empatar (*Dobrar a conta!*)
* Perda de 80% → Exige **+400.0%** de lucro para empatar

> *Engenharia de Risco • Sobrevivência em Primeiro Lugar*
                """
            },
            {
                "id": "a-realidade-dos-90-porcento",
                "title": "# ⚠️-a-realidade-dos-90-porcento",
                "header": "⚠️ A REALIDADE DOS 90%: POR QUE A MAIORIA QUEBRA?",
                "subtitle": "A matemática da quebra de contas, custos invisíveis de fricção e armadilhas do varejo.",
                "content_markdown": """
### ⚠️ A REALIDADE DOS 90%: POR QUE A MAIORIA QUEBRA?
Mais de 90% dos operadores e criadores de robôs perdem todo o capital em menos de 12 meses. Entender os motivos científicos desse número é essencial para sobreviver.

---

#### 1. Custos Invisíveis de Fricção (Spread, Swap e Slippage)
* O custo de spread e derrapagem (*slippage*) corrói silenciosamente o lucro de robôs de alta frequência.
* Um bot que parece lucrativo no papel pode quebrar na prática apenas pelos custos da corretora.

#### 2. A Armadilha da Sobre-Alavancagem
* Alavancagem alta (1:100, 1:500) não aumenta chances de ganho; apenas acelera matematicamente o momento em que uma oscilação comum liquida a conta.

#### 3. A Falácia dos Indicadores Isolados
* Cruzamento de médias móveis, RSI ou MACD são apenas derivadas atrasadas do preço. Sem controle rigoroso de volatilidade e risco, nenhum indicador funciona sozinho.

> *Educação Quantitativa & Realidade Estatística*
                """
            }
        ]
    },
    {
        "category_id": "validacao_backtest",
        "title": "🧪 VALIDAÇÃO & BACKTESTING REALISTA",
        "channels": [
            {
                "id": "metodologia-de-backtest",
                "title": "# 📊-metodologia-de-backtest",
                "header": "📊 METODOLOGIA DE BACKTEST REALISTA",
                "subtitle": "Como testar estratégias com rigor científico sem se iludir.",
                "content_markdown": """
### 📊 METODOLOGIA DE BACKTEST REALISTA
Um backtest confiável precisa replicar as exatas condições adversas do mercado real.

---

#### 1. Modelagem com Real Ticks 99%
* Nunca use dados gerados artificialmente pelo MetaTrader.
* Baixe histórico de ticks reais da corretora com spread flutuante.

#### 2. Incorporação de Custos Reais
* Aplique o spread médio real do ativo (ex: 2.0 pips no XAUUSD).
* Insira o custo de comissão por lote da corretora (ex: $6.00/lote) e taxa de swap diária.

#### 3. Simulação de Latência e Slippage
* Ative no Strategy Tester a simulação de atraso de rede (delay de 50ms a 100ms) para checar se a estratégia sobrevive à derrapagem real.
                """
            },
            {
                "id": "armadilhas-de-overfitting",
                "title": "# 🚫-armadilhas-de-overfitting",
                "header": "🚫 ARMADILHAS DE OVERFITTING (SOBRE-AJUSTE)",
                "subtitle": "Por que robôs com curvas perfeitas no passado quebram na conta real.",
                "content_markdown": """
### 🚫 ARMADILHAS DE OVERFITTING (SOBRE-AJUSTE)
O maior inimigo do desenvolvedor quantitativo é a ilusão de controle criada pelo otimizador de parâmetros.

---

#### 1. O que é Overfitting?
* É quando você ajusta tantos parâmetros e filtros que o robô 'decora' o ruído do passado em vez de capturar uma ineficiência estrutural do mercado.

#### 2. Como Evitar (Protocolo 70/30)
* Divida o histórico em duas partes sagradas:
  * **In-Sample (70%):** Período onde você tem permissão para ajustar e otimizar parâmetros.
  * **Out-of-Sample (30%):** Período onde o robô é testado 'às cegas' sem NENHUMA alteração.
* Se a curva no período Out-of-Sample não for consistente com o In-Sample, descarte a estratégia imediatamente.
                """
            }
        ]
    },
    {
        "category_id": "engenharia_bot",
        "title": "🤖 ENGENHARIA & ARQUITETURA DO BOT",
        "channels": [
            {
                "id": "anatomia-de-um-bot-robusto",
                "title": "# 💻-anatomia-de-um-bot-robusto",
                "header": "💻 ANATOMIA DE UM BOT ROBUSTO: AS 4 CAMADAS ESSENCIAIS",
                "subtitle": "As 4 camadas essenciais de software que compõem um robô de trading profissional.",
                "content_markdown": """
### 💻 ANATOMIA DE UM BOT ROBUSTO: AS 4 CAMADAS ESSENCIAIS
Um robô amador mistura regras de entrada com envio de ordens no mesmo bloco de código. Um robô profissional é construído em **4 camadas desacopladas e independentes**:

---

#### 1. Camada de Análise & Sinal (Signal Engine)
* Responsável apenas por calcular indicadores, estruturas de preço e responder: **COMPRAR**, **VENDER** ou **AGUARDAR**.
* **Regra de Ouro:** Essa camada NÃO sabe o saldo da conta e NÃO envia ordens.

#### 2. Camada de Risco & Dimensionamento (Risk Governor)
* Recebe o sinal e verifica se o trade é permitido:
  * O limite diário de perda foi atingido? → Se sim, **BLOQUEIA**.
  * O spread atual está muito alto? → Se sim, **BLOQUEIA**.
  * Calcula lote dinâmico exato → **Risco ≤ 1.0% do capital**.

#### 3. Camada de Execução (Execution Handler)
* Constrói a requisição de ordem para o MetaTrader 5 / Corretora.
* Garante envio de **Stop Loss e Take Profit anexados na mesma requisição**.
* Trata erros de conexão, requotes e slippage (derrapagem).

#### 4. Camada de Telemetria & Logs (Audit Logger)
* Registra em arquivo todo evento: motivo da entrada, preço de execução, slippage sofrido e saldo.
* Sem logs detalhados, é impossível diagnosticar por que o bot ganhou ou perdeu.

> *Arquitetura de Software • Engenharia Algorítmica*
                """
            },
            {
                "id": "filtros-e-protecoes-de-execucao",
                "title": "# ⚙️-filtros-e-protecoes-de-execucao",
                "header": "⚙️ FILTROS & PROTEÇÕES CRÍTICAS DE EXECUÇÃO",
                "subtitle": "Filtros de spread, horários, proteção contra slippage e tratamento de erros de corretora.",
                "content_markdown": """
### ⚙️ FILTROS & PROTEÇÕES CRÍTICAS DE EXECUÇÃO
Muitos robôs lucrativos quebram simplesmente porque operam em momentos em que a corretora abre o spread ou a liquidez do mercado seca. Todo bot precisa ter estes 4 filtros ativos:

---

#### 1. Filtro de Spread Máximo
* Se o spread atual for maior que a média normal (ex: > 1.5 pips no EURUSD ou > 25 pips no Ouro), o bot **não pode abrir ordens**.
* Evita entradas durante a virada do dia (**Rollover às 18h BRT**) quando o spread explode.

#### 2. Filtro de Horário Operacional
* Opere apenas nos horários de maior volume e liquidez institucional:
  * **Sessão de Londres:** 04:00 às 12:00 BRT
  * **Sessão de Nova York:** 09:00 às 17:00 BRT
  * **Superposição (Overlap):** 09:00 às 12:00 BRT *(Melhor liquidez)*
* Fora desses horários, o mercado fica lateral e gera falsos sinais.

#### 3. Proteção Contra Requotes & Timeout
* Se a corretora demorar mais de **1000ms (1 segundo)** para responder ou devolver um *Requote*, o bot deve cancelar a tentativa e reavaliar o preço em vez de tentar cegamente a qualquer custo.

#### 4. Magic Number Individual
* Cada robô deve usar um número de identificação exclusivo (ex: `MagicNumber = 1123867`).
* Isso impede que o bot feche ou interfira em ordens manuais ou de outros robôs na mesma conta.

> *Proteções de Execução • Controle de Fricção*
                """
            }
        ]
    },
    {
        "category_id": "do_codigo_a_conta_real",
        "title": "🚀 DO CÓDIGO À CONTA REAL",
        "channels": [
            {
                "id": "checklist-de-producao",
                "title": "# 📋-checklist-de-producao",
                "header": "📋 FUNIL DE VALIDAÇÃO: 4 ETAPAS ATÉ A CONTA REAL",
                "subtitle": "O funil de validação em 4 etapas antes de colocar dinheiro real em risco.",
                "content_markdown": """
### 📋 FUNIL DE VALIDAÇÃO: 4 ETAPAS ATÉ A CONTA REAL
Colocar um robô em conta real sem cumprir este funil é o equivalente a apostar no escuro. Siga rigorosamente cada etapa:

---

#### Etapa 1: Backtest Histórico Rigoroso
* Mínimo de 3 anos de histórico com **Real Ticks 99%**.
* Validação In-Sample (70%) e Out-of-Sample (30%).
* Max Drawdown < 15% e Profit Factor entre 1.4 e 2.0.

#### Etapa 2: Forward Test em Conta Demo (30 a 60 dias)
* Deixe o bot rodando 24 horas por dia em uma VPS (servidor dedicado).
* Compare a taxa de acerto e o drawdown da Demo com os resultados do backtest.
* Se houver discrepância grande, investigue slippage ou falha de lógica.

#### Etapa 3: Conta Real com Lote Mínimo (0.01)
* Coloque o bot em conta real operando **apenas com o lote mínimo de 0.01** por pelo menos 30 dias.
* Objetivo: testar a execução da corretora real, swap noturno e execução sob dinheiro de verdade com risco financeiro irrelevante.

#### Etapa 4: Escala Gradual de Capital
* Somente após a Etapa 3 fechar positiva e com execução perfeita, você escala o capital respeitando sempre o limite de **≤ 1.0% de risco por operação**.

> *Protocolo de Validação • Passo a Passo Seguro*
                """
            },
            {
                "id": "disciplina-algoritmica",
                "title": "# 🧠-disciplina-algoritmica",
                "header": "🧠 DISCIPLINA ALGORÍTMICA: NÃO QUEBRE O SEU PRÓPRIO ROBÔ",
                "subtitle": "Por que intervenções manuais quebram robôs e como manter a disciplina técnica.",
                "content_markdown": """
### 🧠 DISCIPLINA ALGORÍTMICA: NÃO QUEBRE O SEU PRÓPRIO ROBÔ
Ironicamente, a maior causa de falha em trading automatizado não é o código, é o **operador humano que desliga ou altera o robô na hora errada**.

---

#### 1. O Erro da Intervenção Emocional
* O robô toma 2 ou 3 stops normais (previstos na estatística).
* O operador entra em pânico, fecha operações manualmente ou desliga o robô.
* Em seguida, o mercado entra no ciclo favorável e o operador perde os trades vencedores que compensariam as perdas.

#### 2. O Erro da Otimização Impulsiva
* Alterar os parâmetros do bot toda semana após um dia negativo destrói qualquer validade estatística.
* O robô deve ser avaliado por **blocos de 100 trades**, nunca pelo resultado de 1 dia ou 1 semana.

#### 3. A Regra de Ouro do Algoritmo
> *"Se você confia no seu backtest e na sua gestão de risco, deixe o código executar o trabalho para o qual ele foi desenhado."*

> *Psicologia Algorítmica • Consistência & Disciplina*
                """
            }
        ]
    },
    {
        "category_id": "modulo_0",
        "title": "📚 MÓDULO 0: FUNDAMENTOS & RISCO",
        "channels": [
            {
                "id": "aula-01-mecanica-e-liquidez",
                "title": "# 📖-aula-01-mecanica-e-liquidez",
                "header": "📚 AULA 0.1: MECÂNICA DE MERCADO & FORMAÇÃO DE PREÇO",
                "subtitle": "Order Book, ordens a mercado vs limite, custos de fricção e análise de microestrutura VPVR vs Gamma no XAUUSD.",
                "content_markdown": """
### 📚 AULA 0.1: MECÂNICA DE MERCADO & FORMAÇÃO DE PREÇO
Antes de programar uma única linha de código, você precisa entender como as ordens são executadas no mundo real. Gráficos são apenas o histórico das ordens que foram negociadas entre compradores e vendedores.

---

#### 1. Livro de Ofertas (Order Book): Bid vs. Ask
* **Bid (Preço de Venda):** O preço mais alto que alguém está disposto a comprar de você.
* **Ask (Preço de Compra):** O preço mais baixo que alguém está disposto a vender para você.
* **Spread:** A diferença entre o Ask e o Bid (`Spread = Ask - Bid`). É a taxa imediata de entrada no trade cobrada pela corretora/mercado.

#### 2. Tipos de Ordens (A Mercado vs. Limite)
* **Ordens a Mercado (Market Orders):** Consomem liquidez imediata. Têm garantia de execução, mas sofrem risco de **Slippage** (preço pior que o esperado).
* **Ordens Limite (Limit Orders):** Fornecem liquidez ao livro. Garantem o preço desejado ou melhor, mas correm o risco de não serem preenchidas se o preço não chegar lá.

#### 3. O Efeito Silencioso da Fricção Operacional
$$\\text{Custo Total por Trade} = \\text{Spread} + \\text{Comissao} + \\text{Slippage} + \\text{Swap\\_Noturno}$$

> *Se um robô faz 20 trades por dia buscando 3 pips de lucro e paga 1.5 pips de spread + comissão, **50% de todo o ganho fica com a corretora!** Robôs de timeframe muito curto sofrem severamente com fricção.*

> *Módulo 0 • Aula 1 • Engenharia de Bots de Trading*

---

### 📊 MICROESTRUTURA: VPVR COM VALUE AREAS vs. GAMMA EXPOSURE NO XAUUSD
Em mercados Spot e CFDs (como o **XAUUSD** no MetaTrader), calcular *"Gamma Exposure (GEX)"* é, em grande parte, um improviso metodológico com atraso de dados, enquanto o **VPVR com Value Areas (POC, VAH, VAL)** é a leitura direta e física do leilão real.

#### 1. A Falha Estrutural do "Gamma Exposure" em CFDs (XAUUSD)
* **Gamma real pertence a opções centralizadas:** O conceito de Gamma Exposure só faz sentido matemático onde existe uma câmara centralizada de opções (como CBOE / CME para índices e ações como SPX/SPY/AAPL), onde os Market Makers de opções têm a obrigação contratual e algorítmica de fazer Delta-Hedging contínuo no subjacente.
* **XAUUSD é mercado de Balcão (OTC / CFD):** Não existe livro de opções centralizado em CFD de ouro. Quem plota "Gamma no XAUUSD" está pegando dados com atraso de contratos de opções de Ouro da COMEX (GC) ou do ETF GLD e tentando "mapear" arbitrariamente para o gráfico de spot/CFD.
* **O resultado?** O nível de *"Zero Gamma"* ou *"Call/Put Wall"* acaba caindo exatamente nos mesmos níveis onde já houve grande acúmulo de volume institucional no VPVR.

#### 2. Por que o VPVR com Value Areas (POC, VAH, VAL) é Superior e Suficiente?
* **Pegada Real (Physical Footprint):** O VPVR não faz suposições sobre como um market maker "deveria" se proteger; ele mostra onde o dinheiro efetivamente trocou de mãos e onde a liquidez foi absorvida.
* **Teoria dos Leilões (Auction Market Theory):**
  * **POC (Point of Control):** Preço de maior consenso e equilíbrio de valor
  * **VAH (Value Area High):** Fronteira estatística superior (~68-70% do volume)
  * **VAL (Value Area Low):** Fronteira estatística inferior (~68-70% do volume)
* **Zero Hipóteses Desnecessárias:** Pela Navalha de Occam, se o VPVR mostra os nós de alto volume (HVN) e as zonas de rejeição (LVN) com precisão cirúrgica sem depender de dados de opções de terceiros, ele é a ferramenta mais limpa e determinística.

#### 3. Então por que tanta gente insiste em usar Gamma Exposure no XAUUSD?
* **A. O "Viés de Complexidade" (Greek Letter Syndrome):** No varejo existe a ilusão de que quanto mais complexo ou cheio de termos matemáticos (Gama, Vanna, Charm, Volga) for um indicador, "mais institucional" ele é. Dizer que opera "Gamma Flip" soa mais sofisticado do que dizer "Rejeição de VAH no VPVR".
* **B. A Indústria de Indicadores:** É muito mais lucrativo vender um indicador de $100/mês prometendo "os segredos de Gamma dos bancos" do que ensinar a interpretar um Volume Profile nativo e entender absorção e leilão.
* **C. Ignorância sobre a Natureza dos Ativos:** Não saber a diferença entre mercado à vista (OTC), futuros regulados (CME) e opções. Viram o conceito funcionando no S&P 500 (SPX) e tentaram forçar para o Ouro sem entender que a mecânica de liquidez é totalmente diferente.

> 💡 **Conclusão Científica:**  
> *"Para o XAUUSD, o VPVR com as Value Areas e os nós de volume (HVN/LVN) é mais do que suficiente: é a representação mais pura da distribuição de liquidez e absorção institucional. Qualquer camada de Gamma colocada em cima de CFD é redundante e apenas adiciona ruído e dependência de dados externos aproximados."*  
> — Sepaul Research & Sunrise Lab • Microestrutura de Mercado
                """
            },
            {
                "id": "aula-02-matematica-do-risco",
                "title": "# 📖-aula-02-matematica-do-risco",
                "header": "📚 AULA 0.2: A MATEMÁTICA INEGOCIÁVEL DA GESTÃO DE RISCO",
                "subtitle": "Cálculo dinâmico de lote, proibição de Martingale e tabela de assimetria de recuperação.",
                "content_markdown": """
### 📚 AULA 0.2: A MATEMÁTICA INEGOCIÁVEL DA GESTÃO DE RISCO
A única variável que um trader ou robô controla com 100% de certeza é quanto pode perder se estiver errado. O gerenciamento de risco é o motor central que separa um sistema lucrativo da ruína financeira.

---

#### 1. Cálculo Dinâmico de Lote (Regra de Ouro do 1%)
Nunca use lote fixo (ex: "sempre operar 0.10"). O lote deve ser calculado pela distância do Stop Loss:
```python
Risco_Financeiro = Saldo_Conta * 0.01
Lote = Risco_Financeiro / (Distancia_Stop_Pontos * Valor_Por_Ponto)
```
* Se o Stop for longo (50 pips), o lote será menor; se for curto (15 pips), o lote será proporcionalmente ajustado.

#### 2. A Armadilha Fatal do Martingale & Preço Médio
* **Martingale:** Dobrar a aposta após cada perda (`0.01 ➜ 0.02 ➜ 0.04 ➜ 0.08 ➜ 0.16 ➜ 0.32 ➜ 0.64 ➜ 1.28`).
* Após 7 perdas consecutivas, um lote de 0.01 vira 1.28 lotes, exigindo milhares de dólares de margem. Uma única tendência forte leva a conta a ZERO.
* **Conclusão:** Martingale não é estratégia, é suicídio matemático disfarçado.

#### 3. Tabela da Assimetria de Recuperação
* Rebaixamento de 10% ➜ Precisa de **+11.1%** para recuperar
* Rebaixamento de 20% ➜ Precisa de **+25.0%** para recuperar
* Rebaixamento de 30% ➜ Precisa de **+42.8%** para recuperar
* Rebaixamento de 50% ➜ Precisa de **+100.0%** para recuperar (*Dobrar a conta*)
* Rebaixamento de 75% ➜ Precisa de **+300.0%** para recuperar
* Rebaixamento de 90% ➜ Precisa de **+900.0%** para recuperar

> *Módulo 0 • Aula 2 • Engenharia de Bots de Trading*
                """
            }
        ]
    },
    {
        "category_id": "modulo_1",
        "title": "💻 MÓDULO 1: AMBIENTE & ARQUITETURA",
        "channels": [
            {
                "id": "aula-03-setup-mt5-e-ferramentas",
                "title": "# 📖-aula-03-setup-mt5-e-ferramentas",
                "header": "💻 AULA 0.3: SETUP DO AMBIENTE DE DESENVOLVIMENTO",
                "subtitle": "MQL5 vs Python+MT5, instalação de pacotes e a importância crítica da VPS para execução 24/7.",
                "content_markdown": """
### 💻 AULA 0.3: SETUP DO AMBIENTE DE DESENVOLVIMENTO
Para criar e rodar robôs com estabilidade profissional, você precisa configurar as ferramentas certas no seu computador e na nuvem.

---

#### 1. As Duas Principais Tecnologias
* **MQL5 Nativo:** Linguagem C++ compilada diretamente dentro do MetaTrader 5. Ultra rápida (latência de microsegundos), roda direto no terminal sem depender de programas externos.
* **Python + Biblioteca MetaTrader5:** Excelente para prototipagem rápida, machine learning, análise quantitativa pesada e envio de ordens via IPC socket.

#### 2. Instalação do Ambiente Python (Passo a Passo)
```bash
# 1. Instalar bibliotecas essenciais no terminal
pip install MetaTrader5 pandas numpy matplotlib
```

#### 3. O Papel Crítico da VPS (Virtual Private Server)
* **Nunca rode um robô em conta real no seu notebook pessoal do dia a dia** (risco de queda de energia, perda de internet, atualizações do Windows que reiniciam o PC).
* Um bot profissional roda em uma **VPS Windows Server 24/7** localizada próxima aos servidores da corretora (Londres ou Nova York) com latência < 2ms.

> *Módulo 1 • Aula 3 • Engenharia de Bots de Trading*
                """
            },
            {
                "id": "aula-04-as-4-camadas-de-software",
                "title": "# 📖-aula-04-as-4-camadas-de-software",
                "header": "💻 AULA 0.4: ARQUITETURA MODULAR (AS 4 CAMADAS)",
                "subtitle": "Separação de responsabilidades: Signal Engine, Risk Governor, Execution Motor e Telemetry & Log.",
                "content_markdown": """
### 💻 AULA 0.4: ARQUITETURA MODULAR (AS 4 CAMADAS)
O maior erro de iniciantes é colocar tudo em uma única função gigante (`OnTick`). A arquitetura profissional deve seguir a Separação de Responsabilidades:

---

#### Diagrama de Fluxo das 4 Camadas
```text
1. SIGNAL ENGINE    ➜ Analisa dados de mercado e gera sinal (COMPRA / VENDA)
        │
2. RISK GOVERNOR   ➜ Valida se o trade é permitido e calcula lote dinâmico
        │
3. EXECUTION MOTOR ➜ Envia a ordem ao MT5 com SL/TP atrelados e trata erros
        │
4. TELEMETRY & LOG ➜ Grava o log com hash SHA-256 e envia alerta se falhar
```

#### Por que essa separação é vital?
Se você quiser trocar de estratégia (ex: de Cruzamento de Média para Rompimento de Volatilidade), você só altera a **Camada 1**. Todo o sistema de travas de risco, envio de ordens e telemetria continua 100% blindado e intocado!

> *Módulo 1 • Aula 4 • Engenharia de Bots de Trading*
                """
            }
        ]
    },
    {
        "category_id": "modulo_2",
        "title": "🤖 MÓDULO 2: PROGRAMAÇÃO DO ROBÔ",
        "channels": [
            {
                "id": "aula-05-envio-de-ordens-e-stops",
                "title": "# 📖-aula-05-envio-de-ordens-e-stops",
                "header": "🤖 AULA 0.5: ENVIO DE ORDENS & CONTROLE DE EXECUÇÃO",
                "subtitle": "Código em Python para envio com SL/TP acoplados e tratamento de erros de retorno (retcode).",
                "content_markdown": """
### 🤖 AULA 0.5: ENVIO DE ORDENS & CONTROLE DE EXECUÇÃO
Aprenda a estruturar o envio correto de ordens com tratamento de retorno da corretora.

---

#### 1. Exemplo de Envio em Python (MetaTrader5 API)
```python
import MetaTrader5 as mt5

def abrir_ordem_compra(simbolo, lote, sl_pontos, tp_pontos, magic=1123867):
    tick = mt5.symbol_info_tick(simbolo)
    preco = tick.ask
    ponto = mt5.symbol_info(simbolo).point

    request = {
        'action': mt5.TRADE_ACTION_DEAL,
        'symbol': simbolo,
        'volume': float(lote),
        'type': mt5.ORDER_TYPE_BUY,
        'price': preco,
        'sl': preco - (sl_pontos * ponto),
        'tp': preco + (tp_pontos * ponto),
        'deviation': 10, # Slippage máximo tolerado
        'magic': magic,
        'comment': 'Sunrise Bot Execution',
        'type_time': mt5.ORDER_TIME_GTC,
        'type_filling': mt5.ORDER_FILLING_IOC,
    }
    resultado = mt5.order_send(request)
    return resultado
```

#### 2. O que checar após o envio?
* Sempre verifique se `resultado.retcode == mt5.TRADE_RETCODE_DONE`.
* Se retornar erro (ex: `10015` = Preço inválido, `10014` = Volume inválido, `10016` = Stop inválido), o bot deve registrar o log e aguardar, nunca tentar em loop infinito.

> *Módulo 2 • Aula 5 • Engenharia de Bots de Trading*
                """
            },
            {
                "id": "aula-06-codigo-das-travas-de-risco",
                "title": "# 📖-aula-06-codigo-das-travas-de-risco",
                "header": "🤖 AULA 0.6: CODIFICANDO AS TRAVAS DE SEGURANÇA",
                "subtitle": "Implementação prática da trava de perda diária (Daily Drawdown) e filtro de spread máximo.",
                "content_markdown": """
### 🤖 AULA 0.6: CODIFICANDO AS TRAVAS DE SEGURANÇA
Veja como implementar as travas de perda diária e filtro de spread direto no código.

---

#### 1. Trava de Perda Diária (Daily Drawdown Limiter)
```python
def verificar_trava_diaria(limite_perda_pct=2.5):
    conta = mt5.account_info()
    saldo_inicial = conta.balance # Ou capturado na abertura do dia
    patrimonio_atual = conta.equity

    perda_atual_pct = ((saldo_inicial - patrimonio_atual) / saldo_inicial) * 100

    if perda_atual_pct >= limite_perda_pct:
        print(f'🛑 TRAVA ACIONADA: Perda do dia ({perda_atual_pct:.2f}%) atingiu o limite!')
        return False # BLOQUEIA NOVOS TRADES
    return True # PERMITE OPERAR
```

#### 2. Filtro de Spread Máximo
```python
def verificar_spread_permitido(simbolo, max_spread_pips=2.0):
    info = mt5.symbol_info(simbolo)
    spread_atual_pips = info.spread / 10.0

    if spread_atual_pips > max_spread_pips:
        print(f'⚠️ SPREAD ALTO: {spread_atual_pips} pips (Limite: {max_spread_pips})')
        return False
    return True
```

> *Módulo 2 • Aula 6 • Engenharia de Bots de Trading*
                """
            },
            {
                "id": "template-codigo-completo",
                "title": "# 💻-template-codigo-completo",
                "header": "💻 TEMPLATE BASE: ESTRUTURA COMPLETA DE ROBÔ EM PYTHON",
                "subtitle": "Template base funcional completo pronto para personalização, com as 4 camadas integradas.",
                "content_markdown": """
### 💻 TEMPLATE BASE: ESTRUTURA COMPLETA DE ROBÔ EM PYTHON
Aqui está o template base funcional completo pronto para download e personalização, com todas as 4 camadas integradas!

---

#### Estrutura do Loop Principal
```python
import time
import MetaTrader5 as mt5

# 1. Inicializar MT5
if not mt5.initialize():
    print('Erro ao conectar ao MT5')
    exit()

print('⚡ Bot Conectado com Sucesso ao MetaTrader 5!')

while True:
    # Camada 2: Checagem de Risco e Segurança
    if not verificar_trava_diaria(limite_perda_pct=2.0):
        time.sleep(60)
        continue

    if not verificar_spread_permitido('EURUSD', max_spread_pips=1.5):
        time.sleep(5)
        continue

    # Camada 1: Checagem de Sinal
    # (Insira suas regras de entrada aqui)

    time.sleep(1) # Intervalo do tick
```

> *Módulo 2 • Template Oficial de Código*
                """
            }
        ]
    },
    {
        "category_id": "modulo_3",
        "title": "🧪 MÓDULO 3: BACKTEST & VALIDAÇÃO",
        "channels": [
            {
                "id": "aula-07-configuracao-strategy-tester",
                "title": "# 📖-aula-07-configuracao-strategy-tester",
                "header": "🧪 AULA 0.7: CONFIGURAÇÃO DE ALTA PRECISÃO NO STRATEGY TESTER",
                "subtitle": "Parâmetros obrigatórios no MT5 (ticks reais 99%, depósito real, 3-5 anos) e armadilhas do M1 OHLC.",
                "content_markdown": """
### 🧪 AULA 0.7: CONFIGURAÇÃO DE ALTA PRECISÃO NO STRATEGY TESTER
Para que o backtest tenha valor científico e não gere ilusões, siga esta configuração no MetaTrader 5:

---

#### 1. Parâmetros Obrigatórios do Testador
* **Modelo de Execução:** *"Cada tick baseado em ticks reais"* (Every tick based on real ticks)
* **Depósito Inicial:** Use o valor REAL que você pretende colocar (ex: $500 ou $1,000)
* **Alavancagem:** 1:100 (ou o valor exato da sua corretora)
* **Período Mínimo:** Pelo menos 3 a 5 anos de histórico

#### 2. Por que nunca usar "Apenas preços de abertura" ou "M1 OHLC"?
Esses modos simplificados ignoram a oscilação de preço dentro da vela, fazendo com que Stop Loss e Take Profits sejam preenchidos de forma irrealista e escondendo perdas que aconteceriam no mercado real.

> *Módulo 3 • Aula 7 • Engenharia de Bots de Trading*
                """
            },
            {
                "id": "aula-08-metodos-anti-overfitting",
                "title": "# 📖-aula-08-metodos-anti-overfitting",
                "header": "🧪 AULA 0.8: TÉCNICAS ANTI-OVERFITTING (TESTES FORA DA AMOSTRA)",
                "subtitle": "Regra 70/30 (In-Sample vs Out-of-Sample) e simulações de Monte Carlo para validação estatística.",
                "content_markdown": """
### 🧪 AULA 0.8: TÉCNICAS ANTI-OVERFITTING (TESTES FORA DA AMOSTRA)
Como garantir que o seu robô aprendeu uma vantagem estatística real e não apenas "decorou" o passado.

---

#### 1. A Regra 70/30 (In-Sample vs. Out-of-Sample)
* **2021 a 2023 (70% - In-Sample):** Use para otimizar e calibrar parâmetros
* **2024 a 2026 (30% - Out-of-Sample):** Teste "às cegas" sem alterar nada

> *Se o robô tiver uma curva linda em 2021-2023 e despencar em 2024-2026, ele sofreu overfitting. Descarte imediatamente.*

#### 2. Simulação de Monte Carlo
Ao rodar 1000 simulações reorganizando aleatoriamente a ordem dos seus trades, você descobre se uma sequência de 6 stops seguidos quebraria a sua conta no pior cenário estatístico.

> *Módulo 3 • Aula 8 • Engenharia de Bots de Trading*
                """
            },
            {
                "id": "aula-09-leitura-de-metricas",
                "title": "# 📖-aula-09-leitura-de-metricas",
                "header": "🧪 AULA 0.9: DECIFRANDO O RELATÓRIO DO BACKTEST",
                "subtitle": "As únicas 3 métricas que importam: Profit Factor (1.3 a 1.8), Max Drawdown (< 15-20%) e Recovery Factor (> 4.0).",
                "content_markdown": """
### 🧪 AULA 0.9: DECIFRANDO O RELATÓRIO DO BACKTEST
As únicas métricas que um desenvolvedor quantitativo sério olha no relatório:

---

#### 1. Fator de Lucro (Profit Factor - PF)
$$\\text{PF} = \\frac{\\text{Lucro\\_Bruto}}{\\text{Perda\\_Bruta}}$$

* **PF < 1.0:** Sistema perdedor.
* **PF entre 1.3 e 1.8:** Excelente e realista para o mercado real.
* **PF > 3.0:** Quase sempre sinal de overfitting ou poucos trades.

#### 2. Rebaixamento Máximo Relativo (Max Drawdown)
A maior queda percentual do patrimônio a partir do topo mais alto. Deve ser **estritamente inferior a 15% a 20%** para manter o risco de ruína próximo de zero.

#### 3. Fator de Recuperação (Recovery Factor)
$$\\text{Recovery Factor} = \\frac{\\text{Lucro\\_Líquido\\_Total}}{\\text{Drawdown\\_Máximo\\_Absoluto}}$$

* Indica quantas vezes o lucro total superou a pior perda histórica.
* **Ideal:** > 4.0.

> *Módulo 3 • Aula 9 • Engenharia de Bots de Trading*
                """
            }
        ]
    },
    {
        "category_id": "modulo_4",
        "title": "🚀 MÓDULO 4: OPERAÇÃO EM PRODUÇÃO",
        "channels": [
            {
                "id": "aula-10-o-funil-de-producao",
                "title": "# 📖-aula-10-o-funil-de-producao",
                "header": "🚀 AULA 10: O FUNIL DE VALIDAÇÃO EM 4 ETAPAS",
                "subtitle": "Do Backtest rigoroso à escala gradual de capital com risco ≤ 1.0%.",
                "content_markdown": """
### 🚀 AULA 10: O FUNIL DE VALIDAÇÃO: 4 ETAPAS ATÉ A CONTA REAL
Colocar um robô em conta real sem cumprir este funil é o equivalente a apostar no escuro. Siga rigorosamente cada etapa:

---

#### Etapa 1: Backtest Histórico Rigoroso
* Mínimo de 3 anos de histórico com **Real Ticks 99%**.
* Validação In-Sample (70%) e Out-of-Sample (30%).
* Max Drawdown < 15% e Profit Factor entre 1.4 e 2.0.

#### Etapa 2: Forward Test em Conta Demo (30 a 60 dias)
* Deixe o bot rodando 24 horas por dia em uma VPS (servidor dedicado).
* Compare a taxa de acerto e o drawdown da Demo com os resultados do backtest.
* Se houver discrepância grande, investigue slippage ou falha de lógica.

#### Etapa 3: Conta Real com Lote Mínimo (0.01)
* Coloque o bot em conta real operando **apenas com o lote mínimo de 0.01** por pelo menos 30 dias.
* Objetivo: testar a execução da corretora real, swap noturno e execução sob dinheiro de verdade com risco financeiro irrelevante.

#### Etapa 4: Escala Gradual de Capital
* Somente após a Etapa 3 fechar positiva e com execução perfeita, você escala o capital respeitando sempre o limite de **≤ 1.0% de risco por operação**.

> *Módulo 4 • Aula 10 • Do Código à Conta Real*
                """
            },
            {
                "id": "aula-11-disciplina-algoritmica",
                "title": "# 📖-aula-11-disciplina-algoritmica",
                "header": "🚀 AULA 11: DISCIPLINA ALGORÍTMICA (NÃO QUEBRE SEU ROBÔ)",
                "subtitle": "Psicologia do operador quantitativo: avaliar em blocos de 100 trades sem intervenção emocional.",
                "content_markdown": """
### 🚀 AULA 11: DISCIPLINA ALGORÍTMICA: NÃO QUEBRE O SEU PRÓPRIO ROBÔ
Ironicamente, a maior causa de falha em trading automatizado não é o código, é o **operador humano que desliga ou altera o robô na hora errada**.

---

#### 1. O Erro da Intervenção Emocional
* O robô toma 2 ou 3 stops normais (previstos na estatística).
* O operador entra em pânico, fecha operações manualmente ou desliga o robô.
* Em seguida, o mercado entra no ciclo favorável e o operador perde os trades vencedores que compensariam as perdas.

#### 2. O Erro da Otimização Impulsiva
* Alterar os parâmetros do bot toda semana após um dia negativo destrói qualquer validade estatística.
* O robô deve ser avaliado por **blocos de 100 trades**, nunca pelo resultado de 1 dia ou 1 semana.

#### 3. A Regra de Ouro do Algoritmo
> *"Se você confia no seu backtest e na sua gestão de risco, deixe o código executar o trabalho para o qual ele foi desenhado."*

> *Módulo 4 • Aula 11 • Disciplina & Consistência*
                """
            }
        ]
    }
]


def get_discord_categories() -> List[Dict[str, Any]]:
    """Retorna a árvore completa de categorias e canais do Discord."""
    return DISCORD_CATEGORIES


def get_channel_by_id(channel_id: str) -> Dict[str, Any]:
    """Busca um canal/aula pelo ID em todas as categorias."""
    for cat in DISCORD_CATEGORIES:
        for ch in cat["channels"]:
            if ch["id"] == channel_id:
                return {**ch, "category_title": cat["title"]}
    # Fallback para o primeiro canal
    return {**DISCORD_CATEGORIES[0]["channels"][0], "category_title": DISCORD_CATEGORIES[0]["title"]}
