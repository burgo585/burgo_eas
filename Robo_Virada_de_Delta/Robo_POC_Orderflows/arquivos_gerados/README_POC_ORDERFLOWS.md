# Motor de Trading Baseado na Dinâmica de POC (Orderflows - Mike Valtos)
## Especificação Corrigida e Fiel à Transcrição Oficial

Esta versão foi atualizada e implementada rigorosamente de acordo com os conceitos demonstrados no vídeo de Mike Valtos, **eliminando completamente entradas falsas e ruídos de barras isoladas**.

---

## Módulo 1: Classificação do Estado do Mercado (Filtro Obrigatório)
O robô analisa a estrutura das últimas 3 a 5 barras antes de qualquer decisão:
1. **Tendência de Alta Ativa (Bloqueio Total de Vendas):**
   * Critério: $POC[1] > POC[2] > POC[3]$ e $Close[1] > Close[2]$.
   * Ação: O mercado está em expansão compradora evidente. **Fica terminantemente proibido abrir vendas**, independentemente de sombras ou localização do POC.
2. **Tendência de Baixa Ativa (Bloqueio Total de Compras):**
   * Critério: $POC[1] < POC[2] < POC[3]$ e $Close[1] < Close[2]$.
   * Ação: O mercado está em expansão vendedora evidente. **Fica terminantemente proibido abrir compras**, independentemente de sombras ou localização do POC.
3. **Consolidação Detectada (Chop / Lateralidade):**
   * Se os POCs das últimas 3 barras estiverem contidos numa faixa estreita ($\le N$ ticks configuráveis), o mercado é classificado como lateral, aguardando o rompimento da base.

---

## Módulo 2: Os Dois Únicos Gatilhos Válidos

### Gatilho A: Rompimento da Base "2x4" (Consolidação de POCs)
* **Condição de Base:** Duas ou mais barras consecutivas compartilham o mesmo nível de POC (tolerância de até 1 a 2 ticks):
  $$|POC[2] - POC[3]| \le \text{Tolerância}$$
* **Entrada de Compra:** A barra $Bar[1]$ fecha acima desse nível de POC comum ($Close[1] > BasePOC$).
  * *Stop Loss:* Mínima das barras que formaram a base "2x4" menos buffer ($\min(Low[2], Low[3]) - \text{Buffer}$).
* **Entrada de Venda:** A barra $Bar[1]$ fecha abaixo desse nível de POC comum ($Close[1] < BasePOC$).
  * *Stop Loss:* Máxima das barras que formaram a base "2x4" mais buffer ($\max(High[2], High[3]) + \text{Buffer}$).

---

### Gatilho B: Falha de Continuação (Armadilha / Reversão Real)

#### Cenário de Compra (Bear Trap demonstrada no vídeo):
1. Ocorrem 2 barras vermelhas consecutivas com POCs decrescentes ($POC[3] > POC[2]$, $Close[3] < Open[3]$, $Close[2] < Open[2]$).
2. A barra seguinte $Bar[1]$ tenta renovar a mínima ($Low[1] \le Low[2]$), mas não tem continuidade:
   * **Fecha verde** ($Close[1] > Open[1]$);
   * **Fecha com preço acima de $POC[2]$** ($Close[1] > POC[2]$).
3. **Leitura Order Flow:** Vendedores foram absorvidos e ficaram encurralados/presos no fundo.
4. **Entrada:** Compra a mercado na abertura da barra seguinte.
5. **Stop Loss:** Mínima absoluta do movimento recente ($\min(Low[1], Low[2], Low[3]) - \text{Buffer}$).

#### Cenário de Venda (Bull Trap):
1. Ocorrem 2 barras verdes consecutivas com POCs crescentes ($POC[3] < POC[2]$, $Close[3] > Open[3]$, $Close[2] > Open[2]$).
2. A barra $Bar[1]$ tenta renovar a máxima, mas falha:
   * **Fecha vermelha** ($Close[1] < Open[1]$);
   * **Fecha com preço abaixo de $POC[2]$** ($Close[1] < POC[2]$).
3. **Leitura Order Flow:** Compradores foram absorvidos e ficaram presos no topo.
4. **Entrada:** Venda a mercado na abertura da barra seguinte.
5. **Stop Loss:** Máxima absoluta do movimento recente ($\max(High[1], High[2], High[3]) + \text{Buffer}$).

---

## Módulo 3: Visualização no Gráfico
* **Marcação da Base "2x4":** Linha horizontal espessa dourada (`OBJ_TREND`) no nível alinhado, permanecendo até ser rompida.
* **Seta de Entrada:** Plotada **estritamente após o fechamento da barra** confirmado pelo gatilho, jamais durante a barra em formação.
* **Nível do POC:** Pequenas linhas horizontais em cinza nos POCs de cada barra anterior para permitir a leitura visual da migração do fluxo.

---

## Módulo 4: Painel HUD em Tempo Real
Janela flutuante dark mode com as leituras essenciais:
* **Tendência de POC:** `MIGRANDO PARA CIMA (Alta - Bloqueio Venda)`, `MIGRANDO PARA BAIXO (Baixa - Bloqueio Compra)` ou `LATERAL (Chop)`.
* **Último Alinhamento ("2x4"):** Exibe o nível exato de preço (ex: *Base em 4052.25*).
* **Sinal Pendente:** `Nenhum`, `Aguardando Rompimento da Base` ou `Falha Detectada (Armadilha em curso)`.
* **Status da Ordem:** Direção (COMPRA / VENDA / SEM POSIÇÃO), Lote, Preço Médio, SL, TP e PnL flutuante ($ e Pontos).

---

## Módulo 5: Notificações Oficiais
Disparo de `Alert` e `SendNotification`:
* `[ORDEM EXECUTADA - ROMPIMENTO 2x4] Direção: COMPRA | Base rompida: 4052.25 | SL: 4048.00 | TP: 4060.50`
* `[ORDEM EXECUTADA - FALHA DE CONTINUAÇÃO] Direção: COMPRA | Vendedores presos abaixo de 4053.00 | SL: 4049.50 | TP: 4060.00`
* E notificações simétricas para vendas.

---

## Arquivos no Workspace:
* [`Robo_POC_Orderflows.mq5`](file:///c:/Robo%20Virada%20de%20Delta/Robo_POC_Orderflows.mq5)
* [`Robo_POC_Orderflows.ex5`](file:///c:/Robo%20Virada%20de%20Delta/Robo_POC_Orderflows.ex5)
* Instalado automaticamente em ambos os terminais MT5 da máquina.
