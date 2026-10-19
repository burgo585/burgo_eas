# 🚀 Burgo Scalpe Pro - Expert Advisor (MT5)

[![MQL5](https://img.shields.io/badge/Language-MQL5-blue.svg)](https://www.mql5.com)
[![Platform](https://img.shields.io/badge/Platform-MetaTrader%205-orange.svg)](https://www.metatrader5.com)
[![Version](https://img.shields.io/badge/Version-V43.00-green.svg)](src/Burgo%20Scalpe%20Pro%20V43%20XAUUSD%20M1.mq5)
[![License](https://img.shields.io/badge/License-Proprietary-red.svg)](#licença)

**Burgo Scalpe Pro** é um Expert Advisor (EA) de alta performance para MetaTrader 5 projetado com algoritmos avançados de Scalping, Grid Progressivo Inteligente, Proteções Severas de Equity e Filtros de Regime de Mercado (ADX, CHOP, ATR, EMA200 e RSI).

---

## 📌 Sumário
- [Visão Geral](#-visão-geral)
- [Principais Funcionalidades (V43)](#-principais-funcionalidades-v43)
- [Estrutura do Repositório](#-estrutura-do-repositório)
- [Instalação e Compilação](#-instalação-e-compilação)
- [Histórico de Versões](#-histórico-de-versões)
- [Documentação Detalhada](#-documentação-detalhada)
- [Aviso de Risco](#-aviso-de-risco)

---

## 🔍 Visão Geral

O **Burgo Scalpe Pro** foi projetado para operar com alvos curtos e alta frequência (Scalping), combinado com um sistema de recuperação baseado em Grid Progressivo com controle rigoroso de alavancagem e drawdown.

A versão mais recente (**V43 - XAUUSD M1 Scalper Edition**) foi especificamente otimizada e calibrada para o par **XAUUSD (Ouro)** no tempo gráfico **M1**, oferecendo velocidade na execução de lucros ("Bateu, Levou") e proteção adaptativa contra fortes impulsos de volatilidade.

---

## 🔥 Principais Funcionalidades (V43)

- **Motor de Giro Scalping Fast Profits**: Fechamento acelerado por lado operado e alvo global em USD para reset dinâmico da conta.
- **Filtro de Tendência Macro (EMA 200)**: Garante que as entradas fiquem alinhadas à tendência principal de prazos maiores (ex: M30 / H4).
- **Choppiness Index (CHOP)**: Bloqueia a abertura ou expansão do grid durante super-tendências direcionais de estouro (evitando contrartendências perigosas).
- **Filtro Anti-Oscilação (ADX)**: Pausa o grid quando a força da tendência estiver insuficiente ou em consolidação inadequada.
- **Hard Equity Stop %**: Proteção emergencial que encerra todas as posições caso o Drawdown atinja o limite máximo tolerado (ex: 15% ou 20%).
- **Trailing Stop em USD**: Trava lucros parciais dinamicamente conforme a operação evolui a favor.
- **Painel Interativo de Controle no Gráfico**: Interface gráfica moderna com monitoramento em tempo real de Float, Saldo, Lotes, Spread, ADX, CHOP, RSI e botões de pânico/limpeza.

---

## 📁 Estrutura do Repositório

```
BurgoScalpPro/
├── .gitignore                      # Filtros de arquivos temporários e compilação
├── README.md                       # Documentação principal
├── CHANGELOG.md                    # Histórico detalhado da evolução (V41 -> V43)
├── CONTRIBUTING.md                 # Guia de contribuição e desenvolvimento MQL5
├── docs/
│   ├── ARCHITECTURE.md             # Documentação de arquitetura técnica e componentes
│   └── PARAMETERS.md               # Guia completo dos parâmetros de entrada (Inputs)
├── presets/
│   └── README.md                   # Instruções de uso dos arquivos de configuração (.set)
└── src/
    ├── Burgo Scalpe Pro V43 XAUUSD M1.mq5  # [RECOMENDADO] Versão V43 calibrada para XAUUSD M1
    ├── Burgo Scalpe Pro V42.mq5            # Versão V42 (Multiativos com CHOP & EMA200)
    └── Burgo Scalpe Pro V41.mq5            # Versão V41 (Versão base com ADX & Cooldown)
```

---

## 🛠️ Instalação e Compilação

1. **Clonar ou Baixar o Repositório**:
   Baixe o código fonte localizado na pasta [`src/`](src/).

2. **Copiar para o MetaEditor**:
   - Abra o MetaTrader 5.
   - Pressione `F4` para abrir o MetaEditor.
   - No MetaEditor, navegue na janela *Navegador* até `Experts`.
   - Copie o arquivo [`src/Burgo Scalpe Pro V43 XAUUSD M1.mq5`](src/Burgo%20Scalpe%20Pro%20V43%20XAUUSD%20M1.mq5) para o diretório `MQL5\Experts\` do seu MT5.

3. **Compilar**:
   - Abra o arquivo no MetaEditor e clique em **Compilar** (`F7`).
   - Verifique se a compilação finalizou com `0 errors, 0 warnings`.

4. **Executar no Gráfico**:
   - Retorne ao MetaTrader 5 (`F4`).
   - Abra o gráfico de **XAUUSD** no tempo gráfico **M1**.
   - Arraste o EA **Burgo Scalpe Pro V43** para o gráfico.
   - Certifique-se de habilitar **Algo Trading** (Trading Automatizado) no MT5.

---

## 📜 Histórico de Versões

| Versão | Destaque | Arquivo |
|---|---|---|
| **V43.00** | Edição Scalper XAUUSD M1 ("Bateu, Levou"), expansão rápida de grid e step ajustado para Ouro | [`src/Burgo Scalpe Pro V43 XAUUSD M1.mq5`](src/Burgo%20Scalpe%20Pro%20V43%20XAUUSD%20M1.mq5) |
| **V42.00** | Introdução do Choppiness Index (CHOP), Filtro Direcional EMA 200, Step Progressivo e Hard Equity Stop % | [`src/Burgo Scalpe Pro V42.mq5`](src/Burgo%20Scalpe%20Pro%20V42.mq5) |
| **V41.00** | Introdução do Filtro Anti-Oscilação ADX, tempo de Cooldown pós-fechamento e Reciclagem Smart | [`src/Burgo Scalpe Pro V41.mq5`](src/Burgo%20Scalpe%20Pro%20V41.mq5) |

Veja o histórico detalhado em [`CHANGELOG.md`](CHANGELOG.md).

---

## 📚 Documentação Detalhada

- 🏗️ **[Arquitetura Técnica (`docs/ARCHITECTURE.md`)](docs/ARCHITECTURE.md)**: Explicação detalhada da lógica de decisão, indicadores, gerenciador de ordens e interface gráfica.
- ⚙️ **[Guia de Parâmetros (`docs/PARAMETERS.md`)](docs/PARAMETERS.md)**: Descrição detalhada de cada parâmetro de entrada (`input`) e suas recomendações de calibração.
- ⚙️ **[Presets e Configurações (`presets/README.md`)](presets/README.md)**: Instruções para salvar e aplicar conjuntos de configurações `.set`.

---

## ⚠️ Aviso de Risco (*Risk Disclaimer*)

Operar no mercado financeiro (especialmente pares voláteis como XAUUSD com estratégias de Grid e Martingale) envolve **alto risco financeiro**.
- **Testes Obrigatórios**: Teste sempre o Expert Advisor em uma conta **Demonstração (Demo)** e execute testes de histórico no **Strategy Tester** do MT5 antes de operar em conta real.
- **Gerenciamento de Risco**: Defina um valor de `InpHardEquityStopPct` condizente com seu perfil de risco e nunca arrisque capital que não possa perder.
- **Isenção de Responsabilidade**: Os desenvolvedores não se responsabilizam por eventuais perdas decorrentes do uso deste software.
