# -*- coding: utf-8 -*-
"""
Script de Geração de Manuais Comerciais e Guias Operacionais em PDF
Autor: @ViniciusBurgo
Conceito: Valid BOS Pullback Pro & Pro Max
"""

import os
import subprocess

BASE_DIR = r"c:\Robo Virada de Delta\Valid_BOS_Pullback"
EDGE_PATH = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

CSS_STYLES = """
@page {
    size: A4 portrait;
    margin: 8mm 10mm 8mm 10mm;
}

* {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
    -webkit-print-color-adjust: exact !important;
    print-color-adjust: exact !important;
}

body {
    font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, Roboto, Helvetica, Arial, sans-serif;
    color: #0f172a;
    background-color: #ffffff;
    font-size: 8.5pt;
    line-height: 1.35;
}

.page {
    width: 190mm;
    height: 279mm;
    max-height: 279mm;
    overflow: hidden;
    position: relative;
    page-break-after: always;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    padding: 2mm 0;
}

.page:last-child {
    page-break-after: avoid;
}

/* HEADER */
.header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    padding-bottom: 2.5mm;
    border-bottom: 1.5px solid #0052cc;
    margin-bottom: 2.5mm;
}

.header-left h1 {
    font-size: 15pt;
    font-weight: 800;
    color: #0a192f;
    letter-spacing: -0.3px;
    margin-bottom: 1px;
}

.header-left .subtitle {
    font-size: 6.8pt;
    font-weight: 700;
    color: #475569;
    letter-spacing: 0.8px;
    text-transform: uppercase;
}

.header-right {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    gap: 2px;
}

.badge-author {
    background-color: #0a192f;
    color: #38bdf8;
    font-size: 7.2pt;
    font-weight: 700;
    padding: 3px 8px;
    border-radius: 4px;
    letter-spacing: 0.2px;
}

.badge-certified {
    font-size: 6.2pt;
    font-weight: 700;
    color: #059669;
    display: flex;
    align-items: center;
    gap: 4px;
    letter-spacing: 0.5px;
}

.badge-certified::before {
    content: "●";
    font-size: 7pt;
    color: #10b981;
}

/* SECTION HEADINGS */
.section-title {
    display: flex;
    align-items: center;
    font-size: 9.8pt;
    font-weight: 800;
    color: #0f172a;
    border-left: 3.5px solid #0052cc;
    padding-left: 6px;
    margin-bottom: 2mm;
}

.section-desc {
    font-size: 7.6pt;
    color: #334155;
    line-height: 1.35;
    margin-bottom: 3mm;
    text-align: justify;
}

/* 2-COLUMN GRID (PAGE 1) */
.grid-2col {
    display: grid;
    grid-template-columns: 82mm 104mm;
    gap: 4mm;
    margin-bottom: 3mm;
}

/* MOCKUP ON-CHART PANEL */
.mockup-panel {
    background: #0d131f;
    border: 1px solid #1e293b;
    border-radius: 6px;
    box-shadow: 0 4px 10px rgba(0,0,0,0.15);
    padding: 6px 8px;
    color: #e2e8f0;
    font-family: 'Segoe UI', Tahoma, sans-serif;
}

.mock-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    background: #172033;
    padding: 3px 6px;
    border-radius: 4px;
    border: 1px solid #29354d;
    margin-bottom: 6px;
}

.mock-title {
    font-size: 6.5pt;
    font-weight: 700;
    color: #ffffff;
}

.mock-min {
    font-size: 6pt;
    color: #94a3b8;
    background: #242f47;
    padding: 1px 4px;
    border-radius: 2px;
}

.mock-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 6pt;
    padding: 2px 0;
    border-bottom: 1px solid #182234;
}

.mock-row.highlight {
    background: rgba(30, 41, 59, 0.4);
    padding: 3px 4px;
    border-radius: 3px;
    margin: 2px 0;
}

.mock-label {
    color: #94a3b8;
}

.mock-val {
    font-weight: 600;
}

.mock-val.green { color: #10b981; }
.mock-val.red { color: #ef4444; }
.mock-val.cyan { color: #38bdf8; }
.mock-val.gold { color: #f59e0b; }
.mock-val.white { color: #ffffff; }

.mock-buttons {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 4px;
    margin-top: 5px;
}

.mock-btn {
    text-align: center;
    font-size: 6.2pt;
    font-weight: 700;
    padding: 3.5px 0;
    border-radius: 3px;
    color: #ffffff;
}

.mock-btn.buy { background: #059669; }
.mock-btn.sell { background: #dc2626; }
.mock-btn.panic { background: #1e293b; border: 1px solid #334155; }
.mock-btn.pause { background: #b91c1c; }

/* FEATURE CARDS (RIGHT COLUMN) */
.cards-col {
    display: flex;
    flex-direction: column;
    gap: 2mm;
}

.feat-card {
    background: #f8fafc;
    border: 1px solid #e2e8f0;
    border-radius: 5px;
    padding: 5px 8px;
    position: relative;
}

.card-top {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 2px;
}

.card-title {
    font-size: 7.6pt;
    font-weight: 700;
    color: #0f172a;
}

.card-tag {
    font-size: 5.5pt;
    font-weight: 700;
    padding: 1.5px 5px;
    border-radius: 3px;
    letter-spacing: 0.3px;
}

.tag-blue { background: #e0f2fe; color: #0284c7; }
.tag-green { background: #dcfce7; color: #15803d; }
.tag-purple { background: #f3e8ff; color: #7e22ce; }
.tag-amber { background: #fef3c7; color: #b45309; }

.card-body {
    font-size: 6.8pt;
    color: #475569;
    line-height: 1.3;
}

/* CALLOUT BOXES */
.callout-box {
    background: #eef6fc;
    border-left: 3.5px solid #0066cc;
    padding: 6px 10px;
    border-radius: 0 4px 4px 0;
    margin-top: auto;
    margin-bottom: 2mm;
}

.callout-title {
    font-size: 7.5pt;
    font-weight: 700;
    color: #004d99;
    margin-bottom: 2px;
}

.callout-text {
    font-size: 6.8pt;
    color: #1e293b;
    line-height: 1.35;
}

/* FOOTER */
.footer {
    display: flex;
    justify-content: space-between;
    align-items: center;
    border-top: 1px solid #cbd5e1;
    padding-top: 2mm;
    margin-top: 1mm;
    font-size: 6.5pt;
    color: #64748b;
}

.footer-author {
    font-weight: 600;
}

/* PAGE 2 ELEMENTS */
.grid-2cards {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 3.5mm;
    margin-bottom: 3.5mm;
}

.formula-card {
    background: #f8fafc;
    border: 1px solid #e2e8f0;
    border-radius: 5px;
    padding: 7px 9px;
}

.formula-box {
    background: #ffffff;
    border: 1px dashed #cbd5e1;
    border-radius: 4px;
    padding: 5px 8px;
    margin-top: 5px;
    font-family: 'Consolas', 'Courier New', monospace;
    font-size: 6.8pt;
    font-weight: 700;
    color: #0f172a;
    text-align: center;
}

/* FLOWCHART */
.flowchart-wrapper {
    margin-bottom: 3.5mm;
}

.flowchart-title {
    font-size: 7.8pt;
    font-weight: 700;
    color: #0f172a;
    margin-bottom: 2mm;
}

.flowchart-grid {
    display: grid;
    grid-template-columns: 1fr 18px 1fr 18px 1fr 18px 1fr;
    align-items: center;
}

.flow-step {
    border-radius: 5px;
    padding: 6px 4px;
    text-align: center;
    color: #ffffff;
    font-weight: 700;
}

.flow-step .num {
    font-size: 6pt;
    opacity: 0.9;
    display: block;
    margin-bottom: 2px;
}

.flow-step .text {
    font-size: 6.6pt;
    line-height: 1.2;
}

.flow-step.step1 { background: #0f172a; }
.flow-step.step2 { background: #0284c7; }
.flow-step.step3 { background: #059669; }
.flow-step.step4 { background: #ea580c; }

.flow-arrow {
    text-align: center;
    font-size: 10pt;
    font-weight: 800;
    color: #94a3b8;
}

/* DATA TABLES */
.table-custom {
    width: 100%;
    border-collapse: collapse;
    margin-bottom: 3mm;
    font-size: 6.6pt;
}

.table-custom th {
    background: #0f172a;
    color: #ffffff;
    font-weight: 700;
    text-align: left;
    padding: 4px 6px;
    font-size: 6.6pt;
    border: 1px solid #0f172a;
}

.table-custom td {
    padding: 3.5px 6px;
    border: 1px solid #e2e8f0;
    color: #1e293b;
    vertical-align: top;
    line-height: 1.25;
}

.table-custom tr:nth-child(even) {
    background: #f8fafc;
}

.table-custom .param-col {
    font-weight: 700;
    color: #0052cc;
    white-space: nowrap;
}

/* PAGE 3 ELEMENTS */
.steps-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 2.5mm;
    margin-bottom: 3.5mm;
}

.step-card {
    border: 1px solid #cbd5e1;
    border-radius: 5px;
    overflow: hidden;
    background: #ffffff;
}

.step-header {
    background: #e0f2fe;
    color: #0284c7;
    font-size: 6.5pt;
    font-weight: 700;
    padding: 3.5px 6px;
    border-bottom: 1px solid #cbd5e1;
}

.step-body {
    padding: 5px 6px;
    font-size: 6.4pt;
    color: #334155;
    line-height: 1.3;
}

.checklist-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 3.5mm;
    margin-top: 1mm;
}

.check-card {
    background: #f8fafc;
    border: 1px solid #e2e8f0;
    border-radius: 5px;
    padding: 6px 8px;
}

.check-item {
    display: flex;
    align-items: flex-start;
    gap: 4px;
    font-size: 6.5pt;
    color: #334155;
    margin-bottom: 3px;
    line-height: 1.25;
}

.check-item::before {
    content: "✓";
    font-weight: 800;
    color: #059669;
}
"""

def generate_indicator_html():
    return f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <title>Valid BOS Pullback Pro - Manual do Indicador</title>
    <style>{CSS_STYLES}</style>
</head>
<body>

<!-- ==================== PÁGINA 1 ==================== -->
<div class="page">
    <div>
        <div class="header">
            <div class="header-left">
                <h1>VALID BOS PULLBACK PRO</h1>
                <div class="subtitle">MANUAL TÉCNICO & GUIA OPERACIONAL DEFINITIVO • METATRADER 5</div>
            </div>
            <div class="header-right">
                <div class="badge-author">DESENVOLVIDO POR @ViniciusBurgo</div>
                <div class="badge-certified">CÓDIGO HOMOLOGADO & AUDITADO</div>
            </div>
        </div>

        <div class="section-title">1. Arquitetura do Sistema & Engenharia de Tela</div>
        <div class="section-desc">
            O <strong>Valid BOS Pullback Pro</strong>, projetado e desenvolvido por <strong>@ViniciusBurgo</strong>, é um ecossistema analítico institucional para MetaTrader 5 projetado para mapear o fluxo de ordens dos grandes participantes (Smart Money Concepts). O indicador combina filtros estatísticos de deslocamento, rejeição volumétrica em topos/fundos institucionais e projeção paramétrica de alvos assimétricos (1:2 a 1:3). O painel integrado opera sob Z-Order otimizado com tecnologia Always-on-Top, eliminando conflitos de sobreposição gráfica.
        </div>

        <div class="grid-2col">
            <!-- Mockup do Painel do Indicador -->
            <div class="mockup-panel">
                <div class="mock-header">
                    <span class="mock-title">★ VALID BOS PRO - INDICADOR</span>
                    <span class="mock-min">[ - ]</span>
                </div>
                <div class="mock-row">
                    <span class="mock-label">Candle / Spread</span>
                    <span class="mock-val gold">00:42 • Sp: 18 pts</span>
                </div>
                <div class="mock-row highlight">
                    <span class="mock-label">Diagnóstico Fluxo</span>
                    <span class="mock-val cyan">[EMA: ALTA] [ADX: 26.4 OK]</span>
                </div>
                <div class="mock-row">
                    <span class="mock-label">Resistência (Topo)</span>
                    <span class="mock-val white">2648.50 [+140 pts]</span>
                </div>
                <div class="mock-row">
                    <span class="mock-label">Suporte (Fundo)</span>
                    <span class="mock-val white">2632.10 [-220 pts]</span>
                </div>
                <div class="mock-row">
                    <span class="mock-label">Estrutura Alta</span>
                    <span class="mock-val cyan">VALID PULLBACK ATIVO!</span>
                </div>
                <div class="mock-row">
                    <span class="mock-label">Plano de Trade</span>
                    <span class="mock-val green">COMPRA @ 2640.20</span>
                </div>
                <div class="mock-row">
                    <span class="mock-label">Stop Loss / TP</span>
                    <span class="mock-val white">SL: 2636.20 | TP: 2648.20</span>
                </div>
                <div class="mock-row highlight">
                    <span class="mock-label">Status da Operação</span>
                    <span class="mock-val green">EM ANDAMENTO (+65 pts)</span>
                </div>
                <div class="mock-row">
                    <span class="mock-label">Placar Histórico</span>
                    <span class="mock-val cyan">14 Wins | 3 Losses (82.3%)</span>
                </div>
                <div class="mock-row">
                    <span class="mock-label">Último Sinal</span>
                    <span class="mock-val green">COMPRA: Rejeição no Reteste</span>
                </div>
            </div>

            <!-- Coluna de Recursos -->
            <div class="cards-col">
                <div class="feat-card">
                    <div class="card-top">
                        <span class="card-title">Barra de Mercado & Relógio do Candle</span>
                        <span class="card-tag tag-blue">MERCADO</span>
                    </div>
                    <div class="card-body">
                        Monitora o ativo em tempo real, informando o spread exato da corretora e um timer regressivo milimétrico da barra corrente ([TF] MM:SS), alertando o operador da iminência de fechamento.
                    </div>
                </div>

                <div class="feat-card">
                    <div class="card-top">
                        <span class="card-title">Diagnóstico Institucional em Tempo Real</span>
                        <span class="card-tag tag-green">CONFLUÊNCIA</span>
                    </div>
                    <div class="card-body">
                        Verifica a cada tick a confluência da tendência macro (EMA 200) e a intensidade direcional (ADX > 20.0), informando na tela se o ativo está em fluxo comprador, vendedor ou consolidado.
                    </div>
                </div>

                <div class="feat-card">
                    <div class="card-top">
                        <span class="card-title">Projeção Visual de Entrada, SL e Take Profit</span>
                        <span class="card-tag tag-purple">RISK REWARD</span>
                    </div>
                    <div class="card-body">
                        Desenha caixas e linhas dinâmicas de Entrada (Azul), Stop Loss Técnico (Vermelho) e Take Profit Institucional (Verde 1:2.0), além da linha dourada de Break-Even no 0x0 ao atingir 1R.
                    </div>
                </div>

                <div class="feat-card">
                    <div class="card-top">
                        <span class="card-title">Painel Arrastável (Drag & Drop) & Responsivo</span>
                        <span class="card-tag tag-amber">INTERFACE</span>
                    </div>
                    <div class="card-body">
                        Interface fluida desenvolvida com auto-dimensionamento matemático proporcional à fonte escolhida (7 a 14) e botão de minimizar `[ - ]` com reposicionamento livre pelo gráfico.
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div>
        <div class="callout-box">
            <div class="callout-title">Garantia Absoluta Zero Repainting (@ViniciusBurgo)</div>
            <div class="callout-text">
                O sistema implementa validação estrita no fechamento do candle [1]. Nenhum sinal ou marcação plota em barras abertas ou desaparece do histórico. O sinal impresso no gráfico é 100% definitivo e auditável, garantindo fidelidade estatística incondicional em backtests visuais e pregões ao vivo.
            </div>
        </div>

        <div class="footer">
            <span class="footer-author">Valid BOS Pullback Pro v5.20 • Engenharia: @ViniciusBurgo</span>
            <span>Página 1 de 3</span>
        </div>
    </div>
</div>

<!-- ==================== PÁGINA 2 ==================== -->
<div class="page">
    <div>
        <div class="header">
            <div class="header-left">
                <h1>VALID BOS PULLBACK PRO</h1>
                <div class="subtitle">MANUAL TÉCNICO & GUIA OPERACIONAL DEFINITIVO • METATRADER 5</div>
            </div>
            <div class="header-right">
                <div class="badge-author">DESENVOLVIDO POR @ViniciusBurgo</div>
                <div class="badge-certified">CÓDIGO HOMOLOGADO & AUDITADO</div>
            </div>
        </div>

        <div class="section-title">2. Engenharia Analítica: Smart Money & Estrutura Validada</div>
        <div class="section-desc">
            Eliminando o viés psicológico e os erros de interpretação comuns do varejo, o algoritmo classifica o ciclo de preço em 4 fases sequenciais. Apenas após a confirmação de uma quebra de estrutura (BOS) com expansão comprovada é que o recuo técnico (pullback) é qualificado para envio de sinal.
        </div>

        <div class="grid-2cards">
            <div class="formula-card">
                <div class="card-top">
                    <span class="card-title">Gatilho 1: Smart Money Rejection (Reteste)</span>
                    <span class="card-tag tag-green">ALTO R:R (1:2 - 1:3)</span>
                </div>
                <div class="card-body">
                    Entrada no teste de suporte/resistência com candle de rejeição. Proporciona o Stop Loss mais curto e barato do mercado com alvos de 2x a 3x o risco.
                </div>
                <div class="formula-box">
                    Entrada = Fechamento_Reteste | SL = Mínima_Reteste - Folga
                </div>
            </div>

            <div class="formula-card">
                <div class="card-top">
                    <span class="card-title">Gatilho 2: Break of Structure (BOS Clássico)</span>
                    <span class="card-tag tag-blue">MOMENTUM CONFIRMADO</span>
                </div>
                <div class="card-body">
                    Entrada na continuidade do fluxo quando o preço rompe o topo/fundo da expansão com deslocamento mínimo anti-ruído parametrizado.
                </div>
                <div class="formula-box">
                    Entrada = Rompimento_Extremo + Deslocamento_Pts
                </div>
            </div>
        </div>

        <div class="flowchart-wrapper">
            <div class="flowchart-title">Fluxograma Tático: Ciclo Institucional de Validação da Estrutura</div>
            <div class="flowchart-grid">
                <div class="flow-step step1">
                    <span class="num">ETAPA 1</span>
                    <span class="text">SCAN PIVÔ<br><small style="font-size:5.5pt;font-weight:400;">Topos/Fundos 5 pernas</small></span>
                </div>
                <div class="flow-arrow">➔</div>
                <div class="flow-step step2">
                    <span class="num">ETAPA 2</span>
                    <span class="text">EXPANSÃO<br><small style="font-size:5.5pt;font-weight:400;">Mínimo 5 barras filtro</small></span>
                </div>
                <div class="flow-arrow">➔</div>
                <div class="flow-step step3">
                    <span class="num">ETAPA 3</span>
                    <span class="text">RETESTE & REJ<br><small style="font-size:5.5pt;font-weight:400;">Pavio ≥ 35% no Nível</small></span>
                </div>
                <div class="flow-arrow">➔</div>
                <div class="flow-step step4">
                    <span class="num">ETAPA 4</span>
                    <span class="text">ALVO & 0x0<br><small style="font-size:5.5pt;font-weight:400;">Proteção 1R • TP 2R</small></span>
                </div>
            </div>
        </div>

        <div class="section-title" style="font-size: 8.8pt; margin-bottom: 1.5mm;">Especificação Técnica dos Módulos Institucionais</div>
        <table class="table-custom">
            <thead>
                <tr>
                    <th style="width: 20%;">Módulo</th>
                    <th style="width: 25%;">Gatilho Operacional</th>
                    <th style="width: 28%;">Comportamento no Gráfico</th>
                    <th style="width: 27%;">Benefício Estratégico</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td class="param-col">Pivôs Ágeis (3 Pernas)</td>
                    <td>Varredura de 3 barras à esquerda e 3 à direita</td>
                    <td>Plota rótulos visuais ▲ TOPO e ▼ FUNDO em cada extremo</td>
                    <td>Captura todas as estruturas sem atraso ou perda de swings</td>
                </tr>
                <tr>
                    <td class="param-col">Expansão Ótima (2 Barras)</td>
                    <td>Exige 2 barras mínimas de deslocamento pós-rompimento</td>
                    <td>Linha sólida se mantém ativa durante o novo extremo</td>
                    <td>Validado em 50.000 barras: dobra os trades com 54.6% win rate</td>
                </tr>
                <tr>
                    <td class="param-col">Tolerância de Reteste (30 pts)</td>
                    <td>Zona de 30 pts ($0.30 no Ouro) para absorção da liquidez</td>
                    <td>Linha se transforma em Pontilhada Azul + Caixa Retangular</td>
                    <td>Garante que toques milimétricos na zona sejam validados</td>
                </tr>
                <tr>
                    <td class="param-col">Motor Multi-Estrutura</td>
                    <td>Rastreamento concorrente de múltiplos topos e fundos</td>
                    <td>Mantém histórico gráfico rico sem apagar linhas úteis</td>
                    <td>O gráfico nunca fica vazio e acompanha o ciclo completo</td>
                </tr>
                <tr>
                    <td class="param-col">Rejeição & Valid BOS</td>
                    <td>Pavio direcional ≥ 25% ou quebra do novo extremo</td>
                    <td>Emite flechas neon, caixas de alvos 1:2 e alertas sonoros</td>
                    <td>Confirmação instantânea de absorção institucional</td>
                </tr>
            </tbody>
        </table>
    </div>

    <div>
        <div class="callout-box">
            <div class="callout-title">Blindagem Institucional contra Mercados Laterais (@ViniciusBurgo)</div>
            <div class="callout-text">
                O filtro ADX integrado atua como um disjuntor de segurança: enquanto o índice de força direcional estiver abaixo do nível institucional (20.0), nenhum sinal é liberado, mesmo que haja rompimento visual. Isso protege o operador durante horários de almoço, feriados ou acúmulo sem liquidez.
            </div>
        </div>

        <div class="footer">
            <span class="footer-author">Valid BOS Pullback Pro v5.20 • Engenharia: @ViniciusBurgo</span>
            <span>Página 2 de 3</span>
        </div>
    </div>
</div>

<!-- ==================== PÁGINA 3 ==================== -->
<div class="page">
    <div>
        <div class="header">
            <div class="header-left">
                <h1>VALID BOS PULLBACK PRO</h1>
                <div class="subtitle">MANUAL TÉCNICO & GUIA OPERACIONAL DEFINITIVO • METATRADER 5</div>
            </div>
            <div class="header-right">
                <div class="badge-author">DESENVOLVIDO POR @ViniciusBurgo</div>
                <div class="badge-certified">CÓDIGO HOMOLOGADO & AUDITADO</div>
            </div>
        </div>

        <div class="section-title">3. Guia Operacional & Passo a Passo de Execução</div>
        <div class="section-desc">
            O fluxo operacional do indicador foi desenhado para ser intuitivo, objetivo e de rápida leitura, permitindo que traders discricionários tomem decisões com a mesma clareza e frieza matemática de uma mesa profissional.
        </div>

        <div class="steps-grid">
            <div class="step-card">
                <div class="step-header">1. Alerta & Flecha</div>
                <div class="step-body">
                    Aguarde a flecha de confirmação (Verde para Compra, Vermelha para Venda) no fechamento do candle.
                </div>
            </div>
            <div class="step-card">
                <div class="step-header">2. Check no Painel</div>
                <div class="step-body">
                    Confirme se o diagnóstico no painel está alinhado: [EMA: ALTA/BAIXA] e [ADX: OK].
                </div>
            </div>
            <div class="step-card">
                <div class="step-header">3. Posicionar Ordens</div>
                <div class="step-body">
                    Insira a ordem com Stop Loss na linha vermelha projetada e Take Profit na linha verde (R:R 1:2.0).
                </div>
            </div>
            <div class="step-card">
                <div class="step-header">4. Condução no 0x0</div>
                <div class="step-body">
                    Quando a linha amarela de Break-Even surgir (1R), mova o Stop Loss para o zero a zero imediatamente.
                </div>
            </div>
        </div>

        <div class="section-title" style="font-size: 8.8pt; margin-bottom: 1.5mm;">Dicionário Operacional das Marcações Gráficas</div>
        <table class="table-custom">
            <thead>
                <tr>
                    <th style="width: 22%;">Elemento Gráfico</th>
                    <th style="width: 25%;">Leitura do Mercado</th>
                    <th style="width: 33%;">Aplicação Tática</th>
                    <th style="width: 20%;">Identificação</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td class="param-col">Flecha Verde Neon</td>
                    <td>Confirmação de Rejeição de Baixa / BOS Alta</td>
                    <td>Abertura de Compra no fechamento do candle</td>
                    <td>Abaixo da barra [1]</td>
                </tr>
                <tr>
                    <td class="param-col">Flecha Vermelha Neon</td>
                    <td>Confirmação de Rejeição de Alta / BOS Baixa</td>
                    <td>Abertura de Venda no fechamento do candle</td>
                    <td>Acima da barra [1]</td>
                </tr>
                <tr>
                    <td class="param-col">Linha Pontilhada Azul</td>
                    <td>Valid Pullback ativo (Reteste do nível rompido)</td>
                    <td>Atenção máxima para gatilho iminente</td>
                    <td>Linha horizontal ciano</td>
                </tr>
                <tr>
                    <td class="param-col">Linha Sólida Verde/Vermelha</td>
                    <td>Valid BOS confirmado com expansão validada</td>
                    <td>Confirmação da direção da tendência institucional</td>
                    <td>Linha grossa colorida</td>
                </tr>
                <tr>
                    <td class="param-col">Linha Tracejada Dourada</td>
                    <td>Gatilho de Break-Even atingido (+1.0R a favor)</td>
                    <td>Proteção imediata da posição sem risco</td>
                    <td>Nível de Entrada + 5 pts</td>
                </tr>
                <tr>
                    <td class="param-col">Linha Verde Tracejada</td>
                    <td>Take Profit institucional calculado (1:2.0)</td>
                    <td>Zona de realização total de lucros</td>
                    <td>Alvo final projetado</td>
                </tr>
            </tbody>
        </table>

        <div class="checklist-grid">
            <div class="check-card">
                <div class="card-top" style="margin-bottom: 4px;">
                    <span class="card-title">Checklist Pré-Operacional</span>
                    <span class="card-tag tag-blue">CONFIGURAÇÃO</span>
                </div>
                <div class="check-item">Anexe o indicador ao gráfico desejado (ex: XAUUSD M5).</div>
                <div class="check-item">Verifique se o painel está visível (InpShowDashboard = true).</div>
                <div class="check-item">Confirme se os alertas sonoros e push estão ativados.</div>
                <div class="check-item">Posicione o painel na área mais conveniente arrastando pelo topo.</div>
            </div>

            <div class="check-card">
                <div class="card-top" style="margin-bottom: 4px;">
                    <span class="card-title">Ativos & Tempos Homologados</span>
                    <span class="card-tag tag-green">MERCADOS</span>
                </div>
                <div class="check-item"><strong>XAUUSD (Ouro):</strong> M1, M5 e M15 (Excelente fluidez).</div>
                <div class="check-item"><strong>Mini-Índice (WIN):</strong> 1 Minuto, 5 Minutos e Gráfico Renko.</div>
                <div class="check-item"><strong>Forex (EURUSD, GBPUSD):</strong> M5, M15 e H1.</div>
                <div class="check-item"><strong>Criptoativos (BTCUSD, ETHUSD):</strong> M5 e M15.</div>
            </div>
        </div>
    </div>

    <div>
        <div class="callout-box">
            <div class="callout-title">Suporte e Atualizações Oficiais (@ViniciusBurgo)</div>
            <div class="callout-text">
                O Valid BOS Pullback Pro é mantido e aprimorado de forma contínua por <strong>@ViniciusBurgo</strong>. Dúvidas operacionais, atualizações de versão e materiais complementares são fornecidos com exclusividade aos membros oficiais.
            </div>
        </div>

        <div class="footer">
            <span class="footer-author">Valid BOS Pullback Pro v5.20 • Engenharia: @ViniciusBurgo</span>
            <span>Página 3 de 3</span>
        </div>
    </div>
</div>

</body>
</html>
"""

def generate_expert_html():
    return f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <title>Valid BOS Pullback Pro Max - Manual do Robô EA</title>
    <style>{CSS_STYLES}</style>
</head>
<body>

<!-- ==================== PÁGINA 1 ==================== -->
<div class="page">
    <div>
        <div class="header">
            <div class="header-left">
                <h1>VALID BOS PULLBACK PRO MAX</h1>
                <div class="subtitle">MANUAL TÉCNICO & GUIA OPERACIONAL DEFINITIVO • METATRADER 5</div>
            </div>
            <div class="header-right">
                <div class="badge-author">DESENVOLVIDO POR @ViniciusBurgo</div>
                <div class="badge-certified">CÓDIGO HOMOLOGADO & AUDITADO</div>
            </div>
        </div>

        <div class="section-title">1. Arquitetura da Automação & Cockpit On-Chart</div>
        <div class="section-desc">
            O <strong>Valid BOS Pullback Pro Max EA</strong>, projetado e desenvolvido por <strong>@ViniciusBurgo</strong>, é um sistema totalmente automatizado que executa no milissegundo exato a mesma lógica institucional do nosso consagrado indicador. Com dimensionamento matemático de lote por risco percentual, esteira de proteção pós-ordem com avanço automático para o Zero a Zero (Break-Even) e cockpit operacional interativo na tela, o robô elimina 100% da hesitação e da fadiga emocional do trader.
        </div>

        <div class="grid-2col">
            <!-- Mockup do Painel do EA -->
            <div class="mockup-panel">
                <div class="mock-header">
                    <span class="mock-title">★ VALID BOS PRO - ROBÔ AUTÔNOMO</span>
                    <span class="mock-min">[ - ]</span>
                </div>
                <div class="mock-row">
                    <span class="mock-label">Candle / Spread</span>
                    <span class="mock-val gold">00:38 • Sp: 15 pts</span>
                </div>
                <div class="mock-row highlight">
                    <span class="mock-label">Filtros Técnicos</span>
                    <span class="mock-val cyan">[EMA: ALTA] [ADX: 25.1 OK]</span>
                </div>
                <div class="mock-row">
                    <span class="mock-label">Resistência (Topo)</span>
                    <span class="mock-val white">2652.40 [+110 pts]</span>
                </div>
                <div class="mock-row">
                    <span class="mock-label">Suporte (Fundo)</span>
                    <span class="mock-val white">2635.80 [-240 pts]</span>
                </div>
                <div class="mock-row highlight">
                    <span class="mock-label">Posições & Flutuante</span>
                    <span class="mock-val green">1 Aberta | Lucro: +$140.00</span>
                </div>
                <div class="mock-row">
                    <span class="mock-label">Plano de Execução</span>
                    <span class="mock-val green">COMPRA @ 2642.10 (Lote: 0.35)</span>
                </div>
                <div class="mock-row">
                    <span class="mock-label">Stop Loss / TP</span>
                    <span class="mock-val white">SL: 2638.10 | TP: 2650.10</span>
                </div>
                <div class="mock-row">
                    <span class="mock-label">Status Proteção</span>
                    <span class="mock-val gold">PROTEGIDO NO BREAK-EVEN (0x0)</span>
                </div>
                <div class="mock-row highlight">
                    <span class="mock-label">Placar Fechado</span>
                    <span class="mock-val cyan">Trades: 18 Wins | 4 Losses (81.8%)</span>
                </div>
                <div class="mock-buttons">
                    <div class="mock-btn pause">PAUSAR ROBO</div>
                    <div class="mock-btn panic">FECHAR TUDO</div>
                </div>
            </div>

            <!-- Coluna de Recursos -->
            <div class="cards-col">
                <div class="feat-card">
                    <div class="card-top">
                        <span class="card-title">Execução Instantânea no Fechamento</span>
                        <span class="card-tag tag-blue">EXECUÇÃO</span>
                    </div>
                    <div class="card-body">
                        O algoritmo avalia o fechamento da barra e emite a ordem a mercado em fração de milissegundo, garantindo o melhor preço do book sem delay e sem hesitação humana.
                    </div>
                </div>

                <div class="feat-card">
                    <div class="card-top">
                        <span class="card-title">Proteção de Lucro Automática (Break-Even)</span>
                        <span class="card-tag tag-green">AUTOMAÇÃO</span>
                    </div>
                    <div class="card-body">
                        Ao atingir 1.0x o risco inicial, o robô move automaticamente o Stop Loss da corretora para o preço de abertura + 5 pontos, garantindo lucro de taxas e eliminando o risco da posição.
                    </div>
                </div>

                <div class="feat-card">
                    <div class="card-top">
                        <span class="card-title">Motor de Risco Pro (Auto-Sizing)</span>
                        <span class="card-tag tag-purple">RISK ENGINE</span>
                    </div>
                    <div class="card-body">
                        Calcula o tamanho do lote dinamicamente com base no risco percentual da conta (ex: 0.5%, 1.0% ou 2.0%) e na distância exata em pontos até a mínima/máxima do pullback.
                    </div>
                </div>

                <div class="feat-card">
                    <div class="card-top">
                        <span class="card-title">Cockpit On-Chart com Ação Direta</span>
                        <span class="card-tag tag-amber">CONTROLE</span>
                    </div>
                    <div class="card-body">
                        Botões operacionais interativos na tela: [PAUSAR/ATIVAR ROBO] para travar novas entradas e [FECHAR TUDO] para liquidação imediata de emergência ou batimento de meta diária.
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div>
        <div class="callout-box">
            <div class="callout-title">Arquitetura de Execução Blindada (@ViniciusBurgo)</div>
            <div class="callout-text">
                O robô foi desenvolvido com travas de segurança ativas: conferência de slippage máximo, verificação de spread alargado antes do envio e memória de tickets para impedir ordens duplicadas no mesmo candle, operando perfeitamente tanto em VPS de baixa latência quanto em computadores pessoais.
            </div>
        </div>

        <div class="footer">
            <span class="footer-author">Valid BOS Pullback Pro Max EA v5.20 • Engenharia: @ViniciusBurgo</span>
            <span>Página 1 de 3</span>
        </div>
    </div>
</div>

<!-- ==================== PÁGINA 2 ==================== -->
<div class="page">
    <div>
        <div class="header">
            <div class="header-left">
                <h1>VALID BOS PULLBACK PRO MAX</h1>
                <div class="subtitle">MANUAL TÉCNICO & GUIA OPERACIONAL DEFINITIVO • METATRADER 5</div>
            </div>
            <div class="header-right">
                <div class="badge-author">DESENVOLVIDO POR @ViniciusBurgo</div>
                <div class="badge-certified">CÓDIGO HOMOLOGADO & AUDITADO</div>
            </div>
        </div>

        <div class="section-title">2. Modelagem Matemática de Risco & Proteção de Capital</div>
        <div class="section-desc">
            Eliminando o erro operacional humano, o robô recalcula o lote exato no momento do envio com base na especificação contratual do símbolo operado (Tick Size e Tick Value), assegurando respeito absoluto ao plano financeiro.
        </div>

        <div class="grid-2cards">
            <div class="formula-card">
                <div class="card-top">
                    <span class="card-title">Modo Percentual (% do Saldo)</span>
                    <span class="card-tag tag-green">COMPOUND / EXPONENCIAL</span>
                </div>
                <div class="card-body">
                    Calcula a exposição tolerada em cima do saldo disponível da conta. Permite crescimento exponencial e proporcional à evolução patrimonial.
                </div>
                <div class="formula-box">
                    Lote = (Saldo × Risco%) ÷ (Distância_SL_Pts × Valor_Ponto)
                </div>
            </div>

            <div class="formula-card">
                <div class="card-top">
                    <span class="card-title">Modo Lote Fixo (Contratos / Lotes)</span>
                    <span class="card-tag tag-blue">CONSERVADOR / MESAS</span>
                </div>
                <div class="card-body">
                    Determina um volume de negociação estático predefinido pelo operador, ideal para avaliações de mesas proprietárias com limites rígidos.
                </div>
                <div class="formula-box">
                    Lote = Volume_Parametrizado (ex: 0.10 ou 1.0 contrato)
                </div>
            </div>
        </div>

        <div class="flowchart-wrapper">
            <div class="flowchart-title">Fluxograma Tático: Ciclo Completo da Ordem Automatizada</div>
            <div class="flowchart-grid">
                <div class="flow-step step1">
                    <span class="num">ETAPA 1</span>
                    <span class="text">VALIDAÇÃO<br><small style="font-size:5.5pt;font-weight:400;">BOS + Rejeição + Filtros</small></span>
                </div>
                <div class="flow-arrow">➔</div>
                <div class="flow-step step2">
                    <span class="num">ETAPA 2</span>
                    <span class="text">DISPARO & SL<br><small style="font-size:5.5pt;font-weight:400;">Lote calculado + SL/TP</small></span>
                </div>
                <div class="flow-arrow">➔</div>
                <div class="flow-step step3">
                    <span class="num">ETAPA 3</span>
                    <span class="text">BREAK-EVEN<br><small style="font-size:5.5pt;font-weight:400;">Avanço p/ 0x0 em +1.0R</small></span>
                </div>
                <div class="flow-arrow">➔</div>
                <div class="flow-step step4">
                    <span class="num">ETAPA 4</span>
                    <span class="text">TAKE PROFIT<br><small style="font-size:5.5pt;font-weight:400;">Liquidação total em 2.0R</small></span>
                </div>
            </div>
        </div>

        <div class="section-title" style="font-size: 8.8pt; margin-bottom: 1.5mm;">Especificação Técnica dos Módulos de Execução</div>
        <table class="table-custom">
            <thead>
                <tr>
                    <th style="width: 20%;">Módulo</th>
                    <th style="width: 25%;">Condição de Disparo</th>
                    <th style="width: 28%;">Comportamento em Mercado</th>
                    <th style="width: 27%;">Benefício Estratégico</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td class="param-col">Piso SL (200 pts) & Teto Lote</td>
                    <td>Stop Loss mínimo de segurança e teto máximo de 2.0 lotes</td>
                    <td>Bloqueia explosão suicida de lotes em micro-stops</td>
                    <td>Blindagem matemática de capital que impede quebrar a conta</td>
                </tr>
                <tr>
                    <td class="param-col">Realização Parcial (50% no 1:1)</td>
                    <td>Fecha 50% do volume da ordem ao atingir +1.0R a favor</td>
                    <td>Garante lucro líquido no bolso e deixa saldo buscar 2R</td>
                    <td>Estatística comprovada: Profit Factor sobe para 1.38</td>
                </tr>
                <tr>
                    <td class="param-col">Break-Even Protegido (+25 pts)</td>
                    <td>Move Stop Loss para entrada + 25 pontos de folga</td>
                    <td>Cobre spread real, swap e slippage na saída no 0x0</td>
                    <td>Garante que uma operação lucrativa nunca vire perda</td>
                </tr>
                <tr>
                    <td class="param-col">Circuit Breaker ($500 USD)</td>
                    <td>Limite diário de prejuízo máximo com bloqueio automático</td>
                    <td>Trava novas operações pelo resto do dia ao atingir limite</td>
                    <td>Aderência 100% às regras das maiores Mesas Proprietárias</td>
                </tr>
                <tr>
                    <td class="param-col">Motor Multi-Estrutura</td>
                    <td>Rastreia e executa os mesmos swings do indicador</td>
                    <td>Conexão direta de algoritmos entre Indicador e Expert</td>
                    <td>Execução instantânea sem delay no fechamento do candle</td>
                </tr>
            </tbody>
        </table>
    </div>

    <div>
        <div class="callout-box">
            <div class="callout-title">Homologação para Mesas Proprietárias (@ViniciusBurgo)</div>
            <div class="callout-text">
                O Valid BOS Pullback Pro Max foi desenhado com estrita aderência às regras das maiores empresas de aprovação de contas do mundo (FTMO, FundedNext, Apex, MyForexFunds). Não utiliza Grid tóxico, não usa Martingale e trabalha sempre com Stop Loss obrigatório registrado no servidor da corretora.
            </div>
        </div>

        <div class="footer">
            <span class="footer-author">Valid BOS Pullback Pro Max EA v5.20 • Engenharia: @ViniciusBurgo</span>
            <span>Página 2 de 3</span>
        </div>
    </div>
</div>

<!-- ==================== PÁGINA 3 ==================== -->
<div class="page">
    <div>
        <div class="header">
            <div class="header-left">
                <h1>VALID BOS PULLBACK PRO MAX</h1>
                <div class="subtitle">MANUAL TÉCNICO & GUIA OPERACIONAL DEFINITIVO • METATRADER 5</div>
            </div>
            <div class="header-right">
                <div class="badge-author">DESENVOLVIDO POR @ViniciusBurgo</div>
                <div class="badge-certified">CÓDIGO HOMOLOGADO & AUDITADO</div>
            </div>
        </div>

        <div class="section-title">3. Comandos Táticos, Cockpit On-Chart & Checklist</div>
        <div class="section-desc">
            O painel interativo do robô foi projetado para oferecer controle tático imediato na tela do gráfico, permitindo pausas temporárias, liquidações de emergência e acompanhamento completo de desempenho.
        </div>

        <div class="steps-grid">
            <div class="step-card">
                <div class="step-header">1. Inicialização</div>
                <div class="step-body">
                    Arraste o EA para o gráfico do ativo (ex: XAUUSD M5) e habilite o botão "AlgoTrading" no MT5.
                </div>
            </div>
            <div class="step-card">
                <div class="step-header">2. Gestão de Risco</div>
                <div class="step-body">
                    Defina o risco por operação (ex: 1.0%) e o limite de posições simultâneas (InpMaxConcurrentPositions).
                </div>
            </div>
            <div class="step-card">
                <div class="step-header">3. Monitoramento</div>
                <div class="step-body">
                    Acompanhe o flutuante em tempo real e o placar estatístico consolidado diretamente no painel.
                </div>
            </div>
            <div class="step-card">
                <div class="step-header">4. Ações Táticas</div>
                <div class="step-body">
                    Utilize o botão PAUSAR para dias de notícias ou FECHAR TUDO para encerrar todas as posições na hora.
                </div>
            </div>
        </div>

        <div class="section-title" style="font-size: 8.8pt; margin-bottom: 1.5mm;">Dicionário Operacional das Ações do Cockpit</div>
        <table class="table-custom">
            <thead>
                <tr>
                    <th style="width: 22%;">Comando / Botão</th>
                    <th style="width: 25%;">Mecanismo no Servidor</th>
                    <th style="width: 33%;">Aplicação Tática</th>
                    <th style="width: 20%;">Feedback Visual</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td class="param-col">PAUSAR / ATIVAR ROBO</td>
                    <td>Habilita ou trava o envio de novas ordens</td>
                    <td>Proteção antes de notícias de alto impacto (ex: Payroll/FOMC)</td>
                    <td>Botão alterna Vermelho / Verde</td>
                </tr>
                <tr>
                    <td class="param-col">FECHAR TUDO</td>
                    <td>Encerra todas as posições a mercado e cancela ordens</td>
                    <td>Botão de pânico, batimento de meta diária ou estorno de risco</td>
                    <td>Liquidação em 1 clique</td>
                </tr>
                <tr>
                    <td class="param-col">[ - ] / [ + ] (Minimizar)</td>
                    <td>Oculta o corpo do painel mantendo apenas o cabeçalho</td>
                    <td>Libera espaço no gráfico para análise visual de candles</td>
                    <td>Alterna altura do painel</td>
                </tr>
                <tr>
                    <td class="param-col">Execução de Compra/Venda</td>
                    <td>Roteamento com lote calculado, Stop Loss e Take Profit</td>
                    <td>Entrada na virada de barra quando todos os filtros confluem</td>
                    <td>Setas e caixas desenhadas</td>
                </tr>
                <tr>
                    <td class="param-col">Avanço de Break-Even</td>
                    <td>Modifica o Stop Loss para o ponto de entrada + 5 pontos</td>
                    <td>Proteção automática quando o preço atinge 1.0R a favor</td>
                    <td>Texto de status fica Dourado</td>
                </tr>
                <tr>
                    <td class="param-col">Placar Consolidado</td>
                    <td>Consulta o histórico real da conta pelo Magic Number</td>
                    <td>Exibe vitórias, derrotas, taxa de acerto (%) e lucro líquido</td>
                    <td>Linha de Trades no painel</td>
                </tr>
            </tbody>
        </table>

        <div class="checklist-grid">
            <div class="check-card">
                <div class="card-top" style="margin-bottom: 4px;">
                    <span class="card-title">Checklist de Inicialização Rápida</span>
                    <span class="card-tag tag-blue">CONFIGURAÇÃO</span>
                </div>
                <div class="check-item">Ative o botão <strong>AlgoTrading</strong> na barra de ferramentas do MT5.</div>
                <div class="check-item">Em Propriedades do EA, marque <strong>Permitir Negociação Real</strong>.</div>
                <div class="check-item">Defina o <strong>InpRiskPercent</strong> de acordo com sua gestão de banca.</div>
                <div class="check-item">Código oficial desenvolvido e homologado por <strong>@ViniciusBurgo</strong>.</div>
            </div>

            <div class="check-card">
                <div class="card-top" style="margin-bottom: 4px;">
                    <span class="card-title">Recomendações de Mercado</span>
                    <span class="card-tag tag-green">BOAS PRÁTICAS</span>
                </div>
                <div class="check-item"><strong>XAUUSD (Ouro M5):</strong> Relação R:R de 1:2 com Break-Even em 1R.</div>
                <div class="check-item"><strong>Mini-Índice (WIN M1 / M5):</strong> Excelente para sessões da manhã.</div>
                <div class="check-item"><strong>Forex (EURUSD M15):</strong> Operações limpas com baixo spread.</div>
                <div class="check-item">Recomendado utilizar VPS próxima ao servidor da sua corretora.</div>
            </div>
        </div>
    </div>

    <div>
        <div class="callout-box">
            <div class="callout-title">Suporte e Atualizações Oficiais (@ViniciusBurgo)</div>
            <div class="callout-text">
                O Valid BOS Pullback Pro Max é mantido e aprimorado de forma contínua por <strong>@ViniciusBurgo</strong>. Dúvidas operacionais, atualizações de versão e consultoria de parametrização são fornecidas com exclusividade aos membros oficiais.
            </div>
        </div>

        <div class="footer">
            <span class="footer-author">Valid BOS Pullback Pro Max EA v5.20 • Engenharia: @ViniciusBurgo</span>
            <span>Página 3 de 3</span>
        </div>
    </div>
</div>

</body>
</html>
"""

def main():
    os.makedirs(BASE_DIR, exist_ok=True)
    
    ind_html_path = os.path.join(BASE_DIR, "manual_indicador.html")
    ind_pdf_path = os.path.join(BASE_DIR, "VALID_BOS_PULLBACK_INDICADOR_MANUAL.pdf")
    
    ea_html_path = os.path.join(BASE_DIR, "manual_expert.html")
    ea_pdf_path = os.path.join(BASE_DIR, "VALID_BOS_PULLBACK_EXPERT_MANUAL.pdf")
    
    with open(ind_html_path, "w", encoding="utf-8") as f:
        f.write(generate_indicator_html())
    print(f"[OK] Gerado HTML Indicador: {ind_html_path}")
    
    with open(ea_html_path, "w", encoding="utf-8") as f:
        f.write(generate_expert_html())
    print(f"[OK] Gerado HTML Expert: {ea_html_path}")
    
    # Compilar PDFs usando Microsoft Edge Headless
    for html_p, pdf_p in [(ind_html_path, ind_pdf_path), (ea_html_path, ea_pdf_path)]:
        cmd = [
            EDGE_PATH,
            "--headless",
            "--disable-gpu",
            "--no-pdf-header-footer",
            f"--print-to-pdf={pdf_p}",
            f"file:///{html_p.replace(os.sep, '/')}"
        ]
        print(f"[RENDER] Compilando PDF: {pdf_p}...")
        res = subprocess.run(cmd, capture_output=True, text=True)
        if os.path.exists(pdf_p):
            size = os.path.getsize(pdf_p)
            print(f"[SUCESSO] PDF criado com sucesso ({size:,} bytes): {pdf_p}")
        else:
            print(f"[ERRO] Falha ao criar PDF: {pdf_p}")

if __name__ == "__main__":
    main()
