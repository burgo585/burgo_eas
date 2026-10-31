# 📖 Manual Completo do Usuário — Boleta Scalping Pro v10

Bem-vindo ao guia operacional da **Boleta Scalping Pro v10** para MetaTrader 5. Este manual detalha todos os recursos, atalhos, modo de operação ultrarrápido, gestão de risco, canais de frequência e leitura forense de histórico.

---

## 🧭 Sumário Rápido
1. [Anatomia Visual da Interface](#1-anatomia-visual-da-interface)
2. [Operações e Execução em 1 Clique](#2-operações-e-execução-em-1-clique)
3. [Linhas Visuais de SL & TP no Gráfico (24/7)](#3-linhas-visuais-de-sl--tp-no-gráfico-247)
4. [Ajuste de Zoom e Escala sem Vazamento](#4-ajuste-de-zoom-e-escala-sem-vazamento)
5. [Leitura Forense do Histórico de Trades e Win Rate](#5-leitura-forense-do-histórico-de-trades-e-win-rate)
6. [Gaveta de Canais de Frequência (40x40)](#6-gaveta-de-canais-de-frequência-40x40)
7. [Tabela de Parâmetros do Preset (.set)](#7-tabela-de-parâmetros-do-preset-set)

---

## 1. Anatomia Visual da Interface

A boleta foi construída com tecnologia Dark Mode responsiva de alta densidade visual.

```
+-------------------------------------------------------------+
| SCALP PRO v10                          [115%]  [-]  [X]     |  <- Cabeçalho & Zoom
+-------------------------------------------------------------+
| GOLD#                     Sp: 20             [M15] 08:44    |  <- Faixa de Mercado
+------------------------------+------------------------------+
| CAP. INICIAL                 | LOTE ATUAL                   |
| $1,000.00                    | 0.04                         |  <- Cartões HUD
+------------------------------+------------------------------+
| LUCRO HOJE                   | % ACERTOS (CONTA)            |
| +$148.50                     | 56.1% (193/344)              |
+------------------------------+------------------------------+
| [Hoje]  [7D]  [Geral]  [Conta]  [2026.10.01]  [OK]          |  <- Barra de Apuração
+-------------------------------------------------------------+
| [ ] Risco: $                 [-]   150.00   [+]             |  <- Gestão de Risco
|     Lote Operacional         [-]     0.04   [+]             |  <- Lote Nativo
+-------------------------------------------------------------+
| [X] Stop Loss (pts)          [-]      200   [+]             |  <- SL Nativo
| [X] Take Profit (pts)        [-]      300   [+]             |  <- TP Nativo
| [ ] Break Even (pts)         [-]       60   [+]             |
| [ ] Trailing Stop (pts)      [-]      150   [+]             |
+-------------------------------------------------------------+
| [ ] [Pts] Alvo Parcial       [-]      150   [+]             |  <- Parcial
|     Vol. Parcial (%)         [-]      50%   [+]             |
| [ ] Mover SL p/ Zero a Zero pós Parcial                     |
+-------------------------------------------------------------+
| CANAIS DE FREQUENCIA (40x40)  [+]                           |  <- Gaveta de Canais
+------------------------------+------------------------------+
|        [+] COMPRA            |          [-] VENDA           |  <- Execução Rápida
+------------------------------+------------------------------+
|                     INVERTER POSICAO                        |
+------------------------------+------------------------------+
|         Zerar Lucro          |        Zerar Prejuizo        |
+-------------------------------------------------------------+
|                    ZERAR TODAS AS ORDENS                    |
+-------------------------------------------------------------+
```

---

## 2. Operações e Execução em 1 Clique

As ordens são enviadas imediatamente no tick do mercado:

- **`[+] COMPRA` (Verde)**: Envia ordem de compra a mercado no preço Ask. O Stop Loss entra em -200 pontos e o Take Profit em +300 pontos nativamente.
- **`[-] VENDA` (Vermelho)**: Envia ordem de venda a mercado no preço Bid. O Stop Loss entra em +200 pontos e o Take Profit em -300 pontos.
- **`INVERTER POSICAO` (Azul)**: Encerra a posição aberta atual e abre instantaneamente uma ordem de sinal contrário com o mesmo lote.
- **`Zerar Lucro`**: Encerra na hora apenas as posições com lucro positivo no momento.
- **`Zerar Prejuízo`**: Estanca perdas fechando apenas as posições no vermelho.
- **`ZERAR TODAS AS ORDENS` (Amarelo)**: Fecha todas as posições abertas e cancela qualquer ordem pendente na conta. O botão exibe o lucro flutuante atualizado em tempo real.

---

## 3. Linhas Visuais de SL & TP no Gráfico (24/7)

Mesmo quando não há posições abertas, a boleta desenha e atualiza no gráfico:
1. **Linha Verde Pontilhada (`TP [300 pts]`)**: Mostra exatamente onde ficará o seu alvo de lucro e o valor em dólar com base no seu lote atual.
2. **Linha Vermelha Pontilhada (`SL [200 pts]`)**: Mostra exatamente onde ficará o seu corte de perda e o valor em dólar.
3. **Trailing Bracket Móvel**: Conforme o preço oscila, as linhas acompanham o preço em tempo real. Ao clicar em Compra ou Venda, a ordem cai exatamente nos níveis marcados.

> [!TIP]
> Você pode personalizar as cores, a espessura e o estilo das linhas diretamente no arquivo `.set` através dos parâmetros `InpColorLiveTP` e `InpColorLiveSL`.

---

## 4. Ajuste de Zoom e Escala sem Vazamento

Para garantir conforto visual em qualquer monitor (Full HD, 2K ou 4K):
- **Botão de Zoom no Topo**: Ao lado dos botões de minimizar e fechar, clique em `[115%]`.
- A escala alterna em ciclo:
  $$\text{100\% (Compacta)} \longrightarrow \text{115\% (Confortável)} \longrightarrow \text{130\% (Grande)} \longrightarrow \text{150\% (Extra Grande)} \longrightarrow \text{100\%}$$
- Todos os controles, botões `-` e `+`, caixas de texto e títulos se ajustam proporcionalmente sem estourar as margens.

---

## 5. Leitura Forense do Histórico de Trades e Win Rate

A boleta monitora em tempo real a sua performance na conta:

- **Botão `[Conta]` / `[Ativo]`**:
  - `[Conta]` *(Padrão Recomendado)*: Lê todas as negociações de todos os ativos da conta (Ouro, Bitcoin, Petróleo, Índices).
  - `[Ativo]`: Filtra as estatísticas apenas para o ativo do gráfico atual.
- **Períodos Rápidos**:
  - `[Hoje]`: Apenas operações fechadas no dia de hoje.
  - `[7D]`: Últimos 7 dias corridos.
  - `[Geral]`: Todo o histórico completo desde o início da conta.
- **Data Personalizada**:
  - Digite a data inicial na caixa de texto (ex: `2026.10.01`) e clique em `[OK]`. A taxa de acerto e o lucro acumulado daquele período serão calculados imediatamente.

---

## 6. Gaveta de Canais de Frequência (40x40)

Ferramenta matemática de suporte e resistência simétrica:
1. Clique em `CANAIS DE FREQUENCIA (40x40) [+]` para abrir a gaveta.
2. Clique no botão **`1. Marcar 2 Linhas`**: duas linhas horizontais surgirão no gráfico.
3. Posicione uma linha no topo relevante e a outra no fundo de referência.
4. Clique em **`2. Projetar 40 Canais`**: o robô gerará 40 canais matemáticos simétricos acima e 40 abaixo.
5. Use **`Ocultar Linhas`** para limpar a visão ou **`Limpar Canais`** para reiniciar.

---

## 7. Tabela de Parâmetros do Preset (.set)

| Parâmetro | Padrão Nativo | Descrição |
| :--- | :---: | :--- |
| `InpGuiScale` | `GUI_SCALE_115` | Escala visual da interface (100%, 115%, 130%, 150%). |
| `InpDefaultLot` | `0.04` | Lote operacional inicial nativo. |
| `InpSLActive` / `InpDefaultSL` | `true` / `200` | Stop Loss ativado nativamente em 200 pontos. |
| `InpTPActive` / `InpDefaultTP` | `true` / `300` | Take Profit ativado nativamente em 300 pontos. |
| `InpRiskCash` | `150.0` | Valor financeiro do risco ($150), iniciando desmarcado. |
| `InpLiveSLTPLines` | `true` | Exibição de linhas dinâmicas de SL e TP no gráfico 24/7. |
| `InpSimultaneousTrailing` | `true` | Bracket móvel acompanhando o preço em tempo real. |
| `InpFilterSymbolOnly` | `false` | Leitura de toda a conta (false) ou somente do ativo (true). |
| `InpEnableATRAlvos` | `false` | Cálculo e sugestão volátil de alvos por ATR. |

---
*Manual gerado para a Boleta Scalping Pro v10 — MetaTrader 5.*
