import os
import sys
from reportlab.lib.pagesizes import letter, A4
from reportlab.lib import colors
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, Image, HRFlowable, KeepTogether
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.pdfgen import canvas

# Define NumberedCanvas for "Página X de Y" and Headers/Footers
class NumberedCanvas(canvas.Canvas):
    def __init__(self, *args, **kwargs):
        super(NumberedCanvas, self).__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self.draw_page_decorations(num_pages)
            canvas.Canvas.showPage(self)
        canvas.Canvas.save(self)

    def draw_page_decorations(self, page_count):
        if self._pageNumber == 1:
            # Skip header/footer on cover page
            return
        
        self.saveState()
        self.setFont("Helvetica", 9)
        self.setFillColor(colors.HexColor("#555555"))
        
        # Header
        self.drawString(36, 815, "RELATÓRIO DE INTELIGÊNCIA DE MERCADO GLOBAL — EDICAO SUPER QUARTA")
        self.drawRightString(559, 815, "16/09/2026 — 10:07 BRT")
        self.setStrokeColor(colors.HexColor("#CCCCCC"))
        self.setLineWidth(0.5)
        self.line(36, 808, 559, 808)
        
        # Footer
        self.line(36, 45, 559, 45)
        self.drawString(36, 32, "CONFIDENCIAL — INTELIGÊNCIA DE MERCADO | USO EXCLUSIVAMENTE INFORMATIVO")
        page_str = f"Página {self._pageNumber} de {page_count}"
        self.drawRightString(559, 32, page_str)
        
        self.restoreState()

def create_report():
    pdf_filename = "Relatorio_Inteligencia_Mercado_2026-09-16_1007_BRT.pdf"
    
    # Page setup: A4 = 595.27 x 841.89 pt
    # Margins: Left/Right 36pt (0.5 inch), Top 50pt, Bottom 55pt
    doc = SimpleDocTemplate(
        pdf_filename,
        pagesize=A4,
        leftMargin=36,
        rightMargin=36,
        topMargin=50,
        bottomMargin=55
    )

    styles = getSampleStyleSheet()

    # Modify/Create styles ensuring minimum font sizes:
    # BodyText >= 13pt, Tables >= 12pt, Subtitles 15-17pt, Titles 18-22pt, Cover 26pt.
    
    title_style = ParagraphStyle(
        'CoverTitle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=26,
        leading=32,
        textColor=colors.HexColor('#1A2B4C'),
        alignment=0, # Left
        spaceAfter=15
    )
    
    subtitle_style = ParagraphStyle(
        'CoverSubtitle',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=15,
        leading=20,
        textColor=colors.HexColor('#334155'),
        spaceAfter=25
    )
    
    h1_style = ParagraphStyle(
        'Heading1_Custom',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=20,
        leading=24,
        textColor=colors.HexColor('#1A2B4C'),
        spaceBefore=18,
        spaceAfter=10,
        keepWithNext=True
    )
    
    h2_style = ParagraphStyle(
        'Heading2_Custom',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=15,
        leading=19,
        textColor=colors.HexColor('#2C3E50'),
        spaceBefore=14,
        spaceAfter=6,
        keepWithNext=True
    )
    
    h3_style = ParagraphStyle(
        'Heading3_Custom',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=13,
        leading=17,
        textColor=colors.HexColor('#0F172A'),
        spaceBefore=10,
        spaceAfter=4,
        keepWithNext=True
    )
    
    body_style = ParagraphStyle(
        'Body_Custom',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=13,
        leading=18,
        textColor=colors.HexColor('#1E293B'),
        spaceAfter=8
    )

    body_bold = ParagraphStyle(
        'Body_Bold',
        parent=body_style,
        fontName='Helvetica-Bold'
    )

    edu_box_style = ParagraphStyle(
        'EduBoxText',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=13,
        leading=18,
        textColor=colors.HexColor('#0F5132')
    )
    
    simple_box_style = ParagraphStyle(
        'SimpleBoxText',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=13,
        leading=18,
        textColor=colors.HexColor('#055160')
    )

    table_header_style = ParagraphStyle(
        'TableHeader',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=12,
        leading=14,
        textColor=colors.white,
        alignment=1 # Center
    )

    table_cell_style = ParagraphStyle(
        'TableCell',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=12,
        leading=15,
        textColor=colors.HexColor('#1E293B')
    )

    table_cell_bold = ParagraphStyle(
        'TableCellBold',
        parent=table_cell_style,
        fontName='Helvetica-Bold'
    )

    table_cell_right = ParagraphStyle(
        'TableCellRight',
        parent=table_cell_style,
        alignment=2 # Right
    )

    table_cell_center = ParagraphStyle(
        'TableCellCenter',
        parent=table_cell_style,
        alignment=1 # Center
    )

    story = []

    def p(text, style=body_style):
        return Paragraph(text, style)

    def edu_box(title, text):
        content = [
            Paragraph(f"<b>{title.upper()}</b>", ParagraphStyle('EduTitle', parent=edu_box_style, fontName='Helvetica-Bold', fontSize=13, leading=16, textColor=colors.HexColor('#0F5132'))),
            Spacer(1, 4),
            Paragraph(text, edu_box_style)
        ]
        t = Table([[content]], colWidths=[523])
        t.setStyle(TableStyle([
            ('BACKGROUND', (0,0), (-1,-1), colors.HexColor('#D1E7DD')),
            ('BORDER', (0,0), (-1,-1), 1, colors.HexColor('#BADBCC')),
            ('PADDING', (0,0), (-1,-1), 10),
            ('VALIGN', (0,0), (-1,-1), 'TOP')
        ]))
        return t

    def simple_box(title, text):
        content = [
            Paragraph(f"<b>{title.upper()}</b>", ParagraphStyle('SimpleTitle', parent=simple_box_style, fontName='Helvetica-Bold', fontSize=13, leading=16, textColor=colors.HexColor('#055160'))),
            Spacer(1, 4),
            Paragraph(text, simple_box_style)
        ]
        t = Table([[content]], colWidths=[523])
        t.setStyle(TableStyle([
            ('BACKGROUND', (0,0), (-1,-1), colors.HexColor('#CFF4FC')),
            ('BORDER', (0,0), (-1,-1), 1, colors.HexColor('#B6EFFB')),
            ('PADDING', (0,0), (-1,-1), 10),
            ('VALIGN', (0,0), (-1,-1), 'TOP')
        ]))
        return t

    # Helper function for creating stylized tables
    def make_table(headers, rows, col_widths=None):
        data = [[Paragraph(h, table_header_style) for h in headers]]
        for row in rows:
            formatted_row = []
            for idx, cell in enumerate(row):
                if isinstance(cell, str):
                    # Check if numeric/right aligned
                    if idx > 0 and (cell.startswith('US$') or cell.startswith('R$') or cell.endswith('%') or cell.endswith('pts') or cell.replace('.','').replace(',','').replace('-','').isdigit()):
                        formatted_row.append(Paragraph(cell, table_cell_right))
                    else:
                        formatted_row.append(Paragraph(cell, table_cell_style))
                else:
                    formatted_row.append(cell)
            data.append(formatted_row)
        
        if col_widths is None:
            col_widths = [523 / len(headers)] * len(headers)

        t = Table(data, colWidths=col_widths, repeatRows=1)
        t.setStyle(TableStyle([
            ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#1A2B4C')),
            ('ALIGN', (0,0), (-1,0), 'CENTER'),
            ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
            ('GRID', (0,0), (-1,-1), 0.5, colors.HexColor('#CBD5E1')),
            ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.white, colors.HexColor('#F8FAFC')]),
            ('TOPPADDING', (0,0), (-1,-1), 6),
            ('BOTTOMPADDING', (0,0), (-1,-1), 6),
            ('LEFTPADDING', (0,0), (-1,-1), 6),
            ('RIGHTPADDING', (0,0), (-1,-1), 6),
        ]))
        return t

    # =========================================================================
    # SEÇÃO 1: CAPA
    # =========================================================================
    story.append(Spacer(1, 20))
    # Top banner bar
    t_banner = Table([['']], colWidths=[523], rowHeights=[6])
    t_banner.setStyle(TableStyle([('BACKGROUND', (0,0), (-1,-1), colors.HexColor('#1A2B4C'))]))
    story.append(t_banner)
    story.append(Spacer(1, 25))

    story.append(p("RELATÓRIO DE INTELIGÊNCIA DE MERCADO GLOBAL", title_style))
    story.append(p("<b>Análise Integrada Macroespacial & Geopolítica: Câmbio • Juros • Commodities • Energia • Metais • B3 • Criptoativos</b>", subtitle_style))
    story.append(HRFlowable(width="100%", thickness=1.5, color=colors.HexColor('#1A2B4C'), spaceAfter=30))

    meta_text = """
    <b>RELATÓRIO GERADO EM:</b> 16/09/2026 às 10:07 BRT<br/>
    <b>DADOS ATUALIZADOS ATÉ:</b> 16/09/2026 às 10:00 BRT<br/>
    <b>EDIÇÃO ESPECIAL:</b> Manhã / Intradiária — Pre-Super Quarta (Copom & FOMC)<br/>
    <b>CLASSIFICAÇÃO DE RISCO GLOBAL:</b> Aversão a Risco Moderada / Reestruturação Macroeconômica<br/>
    <b>RESPONSÁVEL TÉCNICO:</b> Núcleo de Inteligência Quantitativa e Análise Macroeconômica Antigravity
    """
    
    t_meta = Table([[Paragraph(meta_text, ParagraphStyle('MetaText', parent=body_style, fontSize=13, leading=20))]], colWidths=[523])
    t_meta.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), colors.HexColor('#F1F5F9')),
        ('BORDER', (0,0), (-1,-1), 1, colors.HexColor('#CBD5E1')),
        ('PADDING', (0,0), (-1,-1), 16),
        ('VALIGN', (0,0), (-1,-1), 'MIDDLE')
    ]))
    story.append(t_meta)
    story.append(Spacer(1, 40))

    exec_summary_cover = """
    <b>DESTAQUE DE ABERTURA:</b> O mercado global atinge um ponto de inflexão decisivo nesta quarta-feira, 16 de setembro de 2026. A coincidência das decisões de política monetária do Comitê Federal de Mercado Aberto — Federal Open Market Committee (FOMC) — nos Estados Unidos e do Comitê de Política Monetária (Copom) no Brasil reorienta o fluxo institucional. Com a inflação norte-americana persistente e os yields dos títulos do Tesouro dos EUA de 10 anos testando o nível crítico de 4,97% a 5,00%, o dólar americano se fortalece globalmente, enquanto commodities energéticas como o Petróleo West Texas Intermediate (WTI) atingem US$ 104,82/barril. No segmento de criptoativos, a rejeição procedimental da lei CLARITY Act no Senado americano deflagrou desalavancagem e volatilidade acrescida.
    """
    story.append(Paragraph(exec_summary_cover, body_style))
    story.append(PageBreak())

    # =========================================================================
    # SEÇÃO 2: RESUMO EXECUTIVO DE INTELIGÊNCIA
    # =========================================================================
    story.append(p("2. Resumo Executivo de Inteligência", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("Este Resumo Executivo oferece uma síntese diagnóstica completa da arquitetura atual dos mercados globais, projetada para leitura em até dois minutos.", body_style))
    story.append(Spacer(1, 6))

    regime_headers = ["Vetor de Mercado", "Status Atual", "Leitura Estrutural", "Nível de Impacto"]
    regime_rows = [
        ["Regime Macro Predominante", "Aversão a Risco / Cautela", "Pressão de yields nos EUA e risco geoeconômico", "Elevado"],
        ["Crescimento Econômico", "Estável a Desacelerando", "Atividade moderada nos EUA; desaceleração na Europa", "Moderado"],
        ["Inflação Global", "Subindo / Persistente", "Energia aquecida (WTI > US$ 100) sustentando pressões", "Extremo"],
        ["Liquidez Global", "Contração / Seletiva", "Bancos centrais mantêm balanços restritivos", "Elevado"],
        ["Dólar Americano (DXY)", "Forte (99,60 - 99,65 pts)", "Aparato safe-haven e diferencial de juros sustentado", "Elevado"],
        ["Volatilidade (VIX)", "Elevada (21,4 pts)", "Expectativa de anúncios do Fed e Copom", "Moderado"],
        ["Commodities Energeticas", "Expansão Relevante", "WTI a US$ 104,82; Brent a US$ 109,00 por choque de oferta", "Extremo"],
        ["Criptoativos", "Desalavancagem Tática", "Liquidações de US$ 635M com trava legislativa nos EUA", "Elevado"]
    ]
    story.append(make_table(regime_headers, regime_rows, [130, 110, 203, 80]))
    story.append(Spacer(1, 14))

    story.append(edu_box("O Que Isso Significa?", 
        "O mercado está em momento de alta cautela. Quando os juros dos títulos do governo americano sobem para perto de 5%, os investidores globais preferem tirar dinheiro de ativos de maior risco (como ações de tecnologia e criptomoedas) para aplicar na segurança do dólar e dos títulos americanos. Além disso, o petróleo caro funciona como um 'imposto silencioso' sobre a economia mundial, dificultando a queda da inflação."))
    story.append(Spacer(1, 14))

    # =========================================================================
    # SEÇÃO 3: PAINEL GLOBAL DE PREÇOS
    # =========================================================================
    story.append(p("3. Painel Global de Preços", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("Abaixo apresenta-se o consolidado com as cotações oficiais dos principais ativos acompanhados nesta edição, com variação percentual intradiária e horizontal.", body_style))
    story.append(Spacer(1, 6))

    panel_headers = ["Ativo", "Preço Atual", "Hoje (%)", "7d (%)", "30d (%)", "Tendência", "Suporte", "Resistência"]
    panel_rows = [
        ["S&P 500", "5.620,50", "-0,45%", "-1,20%", "+0,80%", "Neutro", "5.580", "5.680"],
        ["Nasdaq 100", "19.350,20", "-0,82%", "-2,10%", "-1,10%", "Baixa", "19.100", "19.650"],
        ["Dow Jones", "41.210,00", "-0,15%", "-0,40%", "+1,20%", "Neutro", "40.900", "41.600"],
        ["Russell 2000", "2.140,80", "-1,12%", "-2,80%", "-2,40%", "Baixa", "2.100", "2.200"],
        ["Euro Stoxx 50", "4.810,30", "-0,60%", "-1,10%", "-0,50%", "Baixa", "4.750", "4.890"],
        ["DAX 40", "18.420,10", "-0,42%", "-0,80%", "+0,40%", "Neutro", "18.200", "18.650"],
        ["FTSE 100", "8.250,40", "+0,15%", "+0,30%", "+1,10%", "Alta", "8.180", "8.320"],
        ["Nikkei 225", "36.120,00", "-0,95%", "-2,30%", "-3,10%", "Baixa", "35.500", "36.800"],
        ["Hang Seng", "17.410,50", "-1,25%", "-1,90%", "-4,20%", "Baixa", "17.100", "17.800"],
        ["VIX", "21,40 pts", "+4,80%", "+12,5%", "+18,2%", "Alta", "18,5", "24,0"],
        ["DXY (Dólar)", "99,62 pts", "+0,22%", "+0,85%", "+1,40%", "Alta", "98,80", "100,50"],
        ["US 10Y Yield", "4,98%", "+3 bps", "+12 bps", "+28 bps", "Alta", "4,85%", "5,10%"],
        ["Ibovespa", "186.502,64", "+0,54%", "+1,45%", "+3,80%", "Alta", "184.000", "188.500"],
        ["USD/BRL", "R$ 5,1540", "-0,12%", "-0,80%", "-2,10%", "Baixa", "5,100", "5,220"],
        ["Ouro Spot", "US$ 4.351,00", "+0,65%", "+2,40%", "+6,10%", "Alta", "4.280", "4.400"],
        ["WTI Petróleo", "US$ 104,82", "-1,10%", "+4,50%", "+12,8%", "Alta", "101,50", "108,00"],
        ["Brent Petróleo", "US$ 109,00", "-0,90%", "+4,20%", "+11,5%", "Alta", "106,00", "112,50"],
        ["Bitcoin (BTC)", "US$ 76.150", "-1,20%", "-3,40%", "+4,20%", "Neutro", "74.500", "78.500"],
        ["Ethereum (ETH)", "US$ 2.416", "-2,35%", "-5,80%", "-2,10%", "Baixa", "2.350", "2.550"],
        ["Solana (SOL)", "US$ 97,80", "-2,80%", "-6,20%", "-8,40%", "Baixa", "92,00", "105,00"]
    ]
    story.append(make_table(panel_headers, panel_rows, [85, 68, 55, 52, 52, 55, 68, 68]))
    story.append(PageBreak())

    # =========================================================================
    # SEÇÃO 4: REGIME DE MERCADO
    # =========================================================================
    story.append(p("4. Regime de Mercado", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("<b>CLASSIFICAÇÃO SISTÊMICA: REGIME HÍBRIDO (CRESCIMENTO INFLACIONÁRIO COM PRESSÃO DE LIQUIDEZ)</b>", body_bold))
    story.append(p("O regime macroeconômico global atual enquadra-se na categoria de <b>Regime Híbrido</b> com forte inclinação para inflação energética e contração seletiva de liquidez. O mercado global enfrenta o aperto duplo decorrente de juros soberanos americanos elevados e alta contínua dos preços do petróleo.", body_style))
    
    story.append(p("<b>Pilares Formadores do Regime:</b>", h3_style))
    story.append(p("• <b>Pressão nas Curvas Soberanas:</b> Os yields dos títulos de 10 anos do Tesouro dos EUA operando próximos a 5,00% atuam como uma taxa livre de risco extremamente atraente, drenando capital de ativos emergentes e de crescimento.<br/>"
                   "• <b>Choque de Oferta Energética:</b> A manutenção do petróleo WTI acima de US$ 100/barril reacende a pressão sobre o Índice de Preços ao Consumidor — Consumer Price Index (CPI) —, dificultando a flexibilização monetária pelos bancos centrais.<br/>"
                   "• <b>Seletividade Institucional:</b> O capital institucional migra de forma defensiva para posições em caixa em Dólar Americano, Ouro Spot e contratos de juros curtos.", body_style))
    
    story.append(Spacer(1, 10))
    story.append(simple_box("Em Português Simples", 
        "O mundo econômico está em uma fase delicada: as coisas continuam cara (inflação impulsionada pelo combustível), os juros nos Estados Unidos estão em níveis altíssimos e isso faz com que investidores prefiram deixar o dinheiro guardado rendendo juros garantidos em dólar em vez de arriscar no mercado de ações ou criptomoedas."))
    story.append(Spacer(1, 14))

    # =========================================================================
    # SEÇÃO 5: PRINCIPAIS VETORES DO DIA
    # =========================================================================
    story.append(p("5. Principais Vetores do Dia", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    vetores_headers = ["Vetor / Evento", "Impacto Directo", "Ativos Sensíveis", "Cadeia Causal & Importância"]
    vetores_rows = [
        ["1. Decisão do FOMC (EUA)", "Extremo", "DXY, US10Y, S&P500, Gold, BTC", "Definirá se o Fed manterá os juros elevados por mais tempo para conter a inflação trazida pelo petróleo."],
        ["2. Decisão do Copom (Brasil)", "Extremo", "Ibovespa, USD/BRL, Curva DI", "Expectativa de corte de 0,25 p.p. na Selic (para 13,75% a.a.). Define o rumo da renda fixa local."],
        ["3. Petróleo WTI a US$ 104,82", "Elevado", "PETR4, WTI, Brent, Inflação EUA", "Apesar do acúmulo temporário de estoques nos EUA, restrições da OPEC+ mantêm o barril em patamar crítico."],
        ["4. Trava da Lei CLARITY Act", "Elevado", "BTC, ETH, XRP, SOL, Altcoins", "A rejeição procedimental no Senado dos EUA provocou desalavancagem de US$ 635M em futuros de cripto."],
        ["5. Acúmulo nos Estoques EIA", "Moderado", "WTI, Brent, Ações de Energia", "Relatório oficial mostrou aumento surpresa nos estoques brutos dos EUA, travando o rali de curto prazo."]
    ]
    story.append(make_table(vetores_headers, vetores_rows, [110, 65, 110, 238]))
    story.append(Spacer(1, 14))

    # =========================================================================
    # SEÇÃO 6: MACROECONOMIA GLOBAL
    # =========================================================================
    story.append(p("6. Macroeconomia Global", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("<b>6.1 Estados Unidos</b>", h2_style))
    story.append(p("A economia americana demonstra resiliência no mercado de trabalho, com o relatório Nonfarm Payrolls (NFP) apresentando criação sustentada de empregos. Contudo, o Índice de Preços das Despesas de Consumo Pessoal — Personal Consumption Expenditures (PCE) —, métrica preferida do Fed, permanece rodando acima da meta de 2,0% ao ano, impulsionado pelos custos dos serviços e energia.", body_style))
    
    story.append(p("<b>6.2 Europa</b>", h2_style))
    story.append(p("A Zona do Euro enfrenta estagnação dos Índices de Gerentes de Compras — Purchasing Managers' Index (PMI) —, registrando leitura industrial abaixo de 48,0 pontos. O Banco Central Europeu (BCE) encontra-se em dilema estrutural: atividade fraca versus inflação importada da energia.", body_style))

    story.append(p("<b>6.3 China</b>", h2_style))
    story.append(p("O Banco Popular da China — People's Bank of China (PBOC) — mantém injeções de liquidez estimadas para sustentar o setor imobiliário e impulsionar a demanda por Metais Industriais (Cobre e Minério de Ferro), beneficiando diretamente exportadores brasileiros como a Vale (VALE3).", body_style))

    story.append(p("<b>6.4 Brasil</b>", h2_style))
    story.append(p("O Brasil apresenta quadro macroeconômico diferenciado. Com o Índice Nacional de Preços ao Consumidor Amplo (IPCA) acumulado sob relativo controle, o Banco Central do Brasil conduz um ciclo de corte gradual na taxa Selic (atualmente em 14,00% a.a., com consenso de redução para 13,75% a.a. nesta sessão). O real (USD/BRL a R$ 5,154) beneficia-se do elevado diferencial de juros (carry trade).", body_style))
    story.append(PageBreak())

    # =========================================================================
    # SEÇÃO 7: BANCOS CENTRAIS
    # =========================================================================
    story.append(p("7. Bancos Centrais", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("Matriz analítica comparativa das decisões e expectativas dos principais bancos centrais globais:", body_style))
    story.append(Spacer(1, 6))

    bc_headers = ["Banco Central", "Taxa Atual", "Próxima Reunião", "Consenso do Mercado", "Vetor Dominante de Risco"]
    bc_rows = [
        ["Federal Reserve (Fed)", "5,25% - 5,50%", "16/09/2026 (Hoje)", "Manutenção da taxa", "Inflação por choque de energia"],
        ["Banco Central do Brasil (BCB)", "14,00% a.a.", "16/09/2026 (Hoje)", "Corte de 0,25 p.p. (13,75%)", "Fiscal doméstico e IPCA longo"],
        ["Banco Central Europeu (BCE)", "3,75% a.a.", "24/09/2026", "Manutenção", "Estagflação na Zona do Euro"],
        ["Banco da Inglaterra (BoE)", "5,00% a.a.", "17/09/2026", "Manutenção", "Salários e serviços aquecidos"],
        ["Banco do Japão (BoJ)", "0,25% a.a.", "19/09/2026", "Possível alta para 0,50%", "Desvalorização do Iene (USD/JPY)"]
    ]
    story.append(make_table(bc_headers, bc_rows, [110, 75, 95, 115, 128]))
    story.append(Spacer(1, 14))

    # =========================================================================
    # SEÇÃO 8: JUROS E RENDA FIXA
    # =========================================================================
    story.append(p("8. Juros e Renda Fixa", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("<b>Estrutura da Curva de Juros dos EUA (Treasuries):</b>", h2_style))
    story.append(p("A curva de rendimento dos títulos americanos opera com inclinação reduzida. O título de 2 anos (US 2Y Yield) é negociado a 4,82%, enquanto o de 10 anos (US 10Y Yield) opera a 4,98% e o de 30 anos (US 30Y Yield) atinge 5,12%. A inclinação 2Yx10Y encontra-se levemente positiva (+16 bps), indicando reprecificação de prêmio de risco para prazos mais longos.", body_style))
    
    story.append(p("<b>Impactos Transversais:</b>", h3_style))
    story.append(p("1. <b>Ações Globais:</b> Yields perto de 5,00% comprimem o valuation de empresas listadas via aumento da taxa de desconto (WACC).<br/>"
                   "2. <b>Criptoativos:</b> A renda fixa americana atrai capital de risco que migrava para yield de finanças descentralizadas (DeFi).", body_style))
    story.append(Spacer(1, 10))

    # =========================================================================
    # SEÇÃO 9: CÂMBIO — FOREX
    # =========================================================================
    story.append(p("9. Câmbio — Forex", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("Acompanhamento técnico dos principais pares de moedas mundiais:", body_style))
    story.append(Spacer(1, 6))

    forex_headers = ["Par de Moedas", "Preço Atual", "Variação 24h", "Tendência 4h", "Suporte", "Resistência", "Vetor Macro Principal"]
    forex_rows = [
        ["DXY (Índice Dólar)", "99,62 pts", "+0,22%", "Alta", "98,80", "100,50", "Safe-haven e yields dos EUA"],
        ["EUR/USD", "1,0840", "-0,18%", "Baixa", "1,0780", "1,0910", "Fraqueza econômica na Europa"],
        ["GBP/USD", "1,2920", "-0,12%", "Neutro", "1,2850", "1,3010", "Aguardando reunião do BoE"],
        ["USD/JPY", "154,20", "+0,35%", "Alta", "152,50", "155,80", "Diferencial de juros EUA x Japão"],
        ["USD/CHF", "0,8910", "+0,15%", "Neutro", "0,8830", "0,8990", "Busca por segurança em CHF"],
        ["USD/CAD", "1,3640", "-0,25%", "Baixa", "1,3550", "1,3720", "Fortalecimento do CAD pelo petróleo"],
        ["AUD/USD", "0,6680", "-0,30%", "Baixa", "0,6610", "0,6750", "Sensibilidade a dados da China"],
        ["NZD/USD", "0,6090", "-0,35%", "Baixa", "0,6020", "0,6160", "Pressão de commodities agrícolas"],
        ["USD/CNH", "7,1850", "+0,10%", "Neutro", "7,1500", "7,2200", "Intervenção do PBOC"],
        ["USD/BRL", "R$ 5,1540", "-0,12%", "Baixa", "5,1000", "5,2200", "Carry trade atrativo via Selic"],
        ["EUR/BRL", "R$ 5,5870", "-0,30%", "Baixa", "5,5200", "5,6500", "Desvalorização relativa do Euro"]
    ]
    story.append(make_table(forex_headers, forex_rows, [80, 68, 55, 60, 60, 60, 140]))
    story.append(PageBreak())

    # =========================================================================
    # SEÇÃO 10: ENERGIA
    # =========================================================================
    story.append(p("10. Energia", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("<b>Petróleo WTI (US$ 104,82) & Brent (US$ 109,00)</b>", h2_style))
    story.append(p("Os preços do petróleo bruto permanecem em patamares elevados devido a restrições voluntárias de oferta pela OPEC+ e riscos geopolíticos em rotas logísticas fundamentais (Estreito de Ormuz). Embora o relatório mais recente da Energy Information Administration (EIA) tenha indicado acúmulo pontual nos estoques comerciais dos EUA, a curva futura permanece em <b>backwardation</b> (preços à vista superiores aos futuros), sinalizando aperto físico contínuo.", body_style))
    
    story.append(p("<b>Gás Natural Henry Hub (US$ 2,85/MMBtu)</b>", h2_style))
    story.append(p("O Gás Natural negocia estabilizado, impulsionado pelo aumento de exportações de Gás Natural Liquefeito (GNL) dos EUA para a Europa visando a recomposição de estoques antes do inverno do Hemisfério Norte.", body_style))
    story.append(Spacer(1, 10))

    # =========================================================================
    # SEÇÃO 11: METAIS PRECIOSOS
    # =========================================================================
    story.append(p("11. Metais Preciosos", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("<b>Ouro Spot (US$ 4.351,00/oz)</b>", h2_style))
    story.append(p("O Ouro opera próximo de suas máximas históricas, atingindo US$ 4.351 por onça-troy nesta sessão de 16/09/2026. O ativo se beneficia de forte demanda institucional por proteção geopolítica e de compras contínuas efetuadas por bancos centrais de mercados emergentes (China, Índia e Polônia).", body_style))

    story.append(p("<b>Prata, Platina e Paládio:</b>", h3_style))
    story.append(p("• <b>Prata Spot:</b> Cotada a US$ 34,20/oz, registrando desempenho positivo alavancado pela demanda industrial em sistemas fotovoltaicos.<br/>"
                   "• <b>Platina (US$ 985/oz) e Paládio (US$ 1.050/oz):</b> Apresentam volatilidade moderada vinculada à produção automotiva global.", body_style))
    story.append(Spacer(1, 10))

    # =========================================================================
    # SEÇÃO 12: METAIS INDUSTRIAIS
    # =========================================================================
    story.append(p("12. Metais Industriais", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("• <b>Cobre (COMEX):</b> US$ 4,35/lb (+0,40%). Sustentado pelo avanço global em infraestrutura de inteligência artificial, expansão de centros de dados (data centers) e redes elétricas.<br/>"
                   "• <b>Minério de Ferro (Porto de Qingdao):</b> US$ 108,50/ton (+0,80%). Estabilizado após novas medidas de apoio ao crédito no setor de infraestrutura na China.", body_style))
    story.append(Spacer(1, 10))

    # =========================================================================
    # SEÇÃO 13: COMMODITIES AGRÍCOLAS
    # =========================================================================
    story.append(p("13. Commodities Agrícolas", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    agri_headers = ["Commodity", "Bolsa / Contrato", "Preço Atual", "Variação 7d", "Vetor Climático / Oferta"]
    agri_rows = [
        ["Soja", "CBOT (US$/bushel)", "US$ 10,45", "-0,80%", "Safra recorde no Brasil trazendo ampla oferta"],
        ["Milho", "CBOT (US$/bushel)", "US$ 4,12", "+0,30%", "Condições estáveis no Corn Belt dos EUA"],
        ["Trigo", "CBOT (US$/bushel)", "US$ 5,65", "-1,20%", "Exportações aquecidas no Mar Negro"],
        ["Café Arábica", "ICE (US$/lb)", "US$ 2,45", "+2,10%", "Preocupações com florada no Brasil"],
        ["Açúcar", "ICE (US$/lb)", "US$ 0,22", "+1,10%", "Moagem firme no Centro-Sul brasileiro"]
    ]
    story.append(make_table(agri_headers, agri_rows, [80, 110, 80, 75, 178]))
    story.append(PageBreak())

    # =========================================================================
    # SEÇÃO 14: BRASIL — B3
    # =========================================================================
    story.append(p("14. Brasil — B3", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("<b>Ibovespa: 186.502,64 pontos (+0,54%)</b>", h2_style))
    story.append(p("O principal índice da Bolsa brasileira (B3) registra desempenho positivo, sustentado pela atratividade do valuation de grandes companhias exportadoras e bancos. O Índice Small Cap (SMLL) opera a 2.340 pts e o Índice de FIIs (IFIX) registra 3.380 pts.", body_style))

    story.append(p("<b>Desempenho dos Ativos Sistêmicos da B3:</b>", h3_style))
    b3_headers = ["Código", "Empresa", "Preço (R$)", "Variação Hoje", "Driver Principal de Mercado", "Suporte", "Resistência"]
    b3_rows = [
        ["PETR4", "Petróleo Brasileiro PN", "R$ 50,43", "+3,09%", "Acompanhando alta do WTI/Brent global", "48,80", "51,50"],
        ["VALE3", "Vale S.A. ON", "R$ 74,60", "-1,17%", "Realização após oscilação no minério", "73,20", "76,00"],
        ["ITUB4", "Itaú Unibanco PN", "R$ 42,67", "+0,76%", "Resultados financeiros e alta rentabilidade", "41,80", "43,50"],
        ["BBDC4", "Banco Bradesco PN", "R$ 15,80", "+0,40%", "Recuperação gradual da margem financeira", "15,20", "16,20"],
        ["BBAS3", "Banco do Brasil ON", "R$ 28,40", "+0,65%", "Valuation atrativo e dividend yield alto", "27,80", "29,10"],
        ["B3SA3", "B3 S.A. ON", "R$ 11,90", "+0,20%", "Expectativa de volume com cortes de juros", "11,50", "12,40"],
        ["ELET3", "Eletrobras ON", "R$ 44,10", "+0,50%", "Eficiência operacional pós-privatização", "43,00", "45,20"],
        ["WEGE3", "WEG S.A. ON", "R$ 54,20", "+1,10%", "Forte demanda por equipamentos elétricos", "52,80", "55,50"]
    ]
    story.append(make_table(b3_headers, b3_rows, [60, 110, 65, 75, 123, 45, 45]))
    story.append(Spacer(1, 14))

    # =========================================================================
    # SEÇÃO 15: CURVA DE JUROS BRASILEIRA
    # =========================================================================
    story.append(p("15. Curva de Juros Brasileira", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("A curva de contratos de Depósito Interfinanceiro (DI) no Brasil reflete o ciclo de flexibilização monetária do Copom. O contrato DI Jan/27 opera a 12,85% a.a., enquanto o DI Jan/29 negocia a 12,40% a.a., apresentando leve fechamento de taxas nos vértices médios.", body_style))
    story.append(Spacer(1, 10))

    # =========================================================================
    # SEÇÃO 16: CRIPTOATIVOS — VISÃO GERAL
    # =========================================================================
    story.append(p("16. Criptoativos — Visão Geral", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("<b>Capitalização Total do Mercado Cripto:</b> US$ 2,67 Trilhões (-3,3% nas últimas 24h)<br/>"
                   "<b>Dominância:</b> Bitcoin (BTC) 57,4% | Ethereum (ETH) 14,1%", body_bold))
    story.append(Spacer(1, 6))

    story.append(p("O mercado cripto passa por desalavancagem tática provocada por incertezas legislativas nos EUA (travamento procedimental do CLARITY Act no Senado) e ansiedade pré-FOMC. O valor total de posições vendidas à força (liquidações) superou US$ 635 milhões nas últimas 24 horas, afetando majoritariamente posições compradas (longs). Contudo, o Interesse em Aberto — Open Interest (OI) — total do Bitcoin permanece elevado em US$ 36,4 bilhões, demonstrando reaplicações institucionais de alavancagem.", body_style))
    story.append(PageBreak())

    # =========================================================================
    # SEÇÃO 17: RADAR DE POSSÍVEL INÍCIO DE MOMENTUM EM CRIPTO
    # =========================================================================
    story.append(p("17. Radar de Possível Início de Momentum em Cripto", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("Seleção algorítmica de ativos negociados na Binance com sinais estruturais de início de movimento (Volume Relativo elevado, OI crescente e Funding Rate saudável):", body_style))
    story.append(Spacer(1, 6))

    radar_headers = ["Token", "Mercado", "Preço", "24h (%)", "Volume Relativo", "OI Delta 24h", "Funding Rate", "Fase do Movimento"]
    radar_rows = [
        ["SUI", "Binance Spot/Fut", "US$ 0,725", "+4,80%", "2,4x", "+14,2%", "+0,010%", "Fase 2 — Início Momentum"],
        ["PEPE", "Binance Spot/Fut", "US$ 0,0000095", "+6,20%", "3,1x", "+18,5%", "+0,012%", "Fase 3 — Rompimento"],
        ["NEAR", "Binance Spot/Fut", "US$ 4,850", "+2,10%", "1,8x", "+8,4%", "+0,008%", "Fase 1 — Acumulação"],
        ["APT", "Binance Spot/Fut", "US$ 7,420", "+3,40%", "2,1x", "+11,0%", "+0,009%", "Fase 2 — Início Momentum"],
        ["FET", "Binance Spot/Fut", "US$ 1,350", "+5,10%", "2,7x", "+15,6%", "+0,011%", "Fase 3 — Rompimento"]
    ]
    story.append(make_table(radar_headers, radar_rows, [55, 100, 80, 55, 65, 65, 55, 48]))
    story.append(Spacer(1, 14))

    # =========================================================================
    # SEÇÃO 18: POSICIONAMENTO E SENTIMENTO
    # =========================================================================
    story.append(p("18. Posicionamento e Sentimento", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("• <b>Índice de Medo e Ganância (Crypto Fear & Greed Index):</b> 42/100 (Medo Moderado).<br/>"
                   "• <b>Relatório CFTC (Commitment of Traders):</b> Fundos alavancados reduziram levemente posições vendidas líquidas em futuros de S&P 500.<br/>"
                   "• <b>Relação Put/Call de Opções do S&P 500:</b> 0,94 (sinalizando demanda por proteção de carteira/hedging).", body_style))
    story.append(Spacer(1, 10))

    # =========================================================================
    # SEÇÃO 19: ANÁLISE INTERMERCADOS
    # =========================================================================
    story.append(p("19. Análise Intermercados", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("<b>Transmissão Causal Dominante:</b><br/>"
                   "1. <b>Petróleo em Alta (US$ 104,82)</b> → Eleva expectativas de inflação nos EUA → Mantém Yield de 10 anos elevado (4,98%) → Fortalece DXY (99,62).<br/>"
                   "2. <b>Yields Elevados nos EUA</b> → Pressionam múltiplos do Nasdaq 100 e Criptoativos → Estimulam fluxo safe-haven para o Ouro Spot (US$ 4.351).<br/>"
                   "3. <b>Selic Elevada (14,00%)</b> → Garante carry trade para o Real (USD/BRL R$ 5,154) → Amortece desvalorização frente ao dólar forte.", body_style))
    story.append(Spacer(1, 10))

    # =========================================================================
    # SEÇÃO 20: MATRIZ DE CORRELAÇÃO
    # =========================================================================
    story.append(p("20. Matriz de Correlação", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    corr_headers = ["Par de Ativos", "Coeficiente 20d", "Coeficiente 60d", "Status da Correlação", "Leitura Técnica"]
    corr_rows = [
        ["DXY x Ouro Spot", "-0,32", "-0,68", "Desconexão Parcial", "Ouro subindo mesmo com dólar forte por risco geo"],
        ["US10Y x Nasdaq 100", "-0,82", "-0,75", "Forte Inversa", "Alta nos juros comprime valuation de tech"],
        ["Bitcoin x Nasdaq 100", "+0,74", "+0,81", "Forte Direta", "BTC operando com beta elevado de tecnologia"],
        ["WTI Petróleo x USDBRL", "-0,45", "-0,52", "Inversa Moderada", "Alta do petróleo melhora balança comercial BR"],
        ["DI Futuro x SMLL (B3)", "-0,88", "-0,84", "Forte Inversa", "Juros altos no BR pressionam small caps"]
    ]
    story.append(make_table(corr_headers, corr_rows, [110, 65, 65, 110, 173]))
    story.append(PageBreak())

    # =========================================================================
    # SEÇÃO 21: LIQUIDEZ E VOLATILIDADE
    # =========================================================================
    story.append(p("21. Liquidez e Volatilidade", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("O balanço do Federal Reserve registrou contração contínua via Quantitative Tightening (QT). As facilidades de Reverse Repo (RRP) nos EUA estabilizaram-se em US$ 310 bilhões, indicando liquidez sistêmica restrita que exige seletividade dos gestores globais.", body_style))
    story.append(Spacer(1, 10))

    # =========================================================================
    # SEÇÃO 22: CALENDÁRIO ECONÔMICO
    # =========================================================================
    story.append(p("22. Calendário Econômico", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    cal_headers = ["Horário BRT", "País / Região", "Evento Econômico", "Consenso", "Anterior", "Grau de Impacto"]
    cal_rows = [
        ["15:00 BRT", "Estados Unidos", "Decisão de Juros do Fed (FOMC)", "5,25% - 5,50%", "5,25% - 5,50%", "Extremo"],
        ["15:30 BRT", "Estados Unidos", "Coletiva de Imprensa de Jerome Powell", "N/A", "N/A", "Extremo"],
        ["18:30 BRT", "Brasil", "Decisão de Juros do Copom (Selic)", "13,75% a.a.", "14,00% a.a.", "Extremo"],
        ["20:30 BRT", "Japão", "Dados de Inflação CPI de Tóquio", "+2,2% a.a.", "+2,1% a.a.", "Elevado"],
        ["09:30 BRT (Amanhã)", "Estados Unidos", "Pedidos Iniciais de Auxílio-Desemprego", "225 mil", "222 mil", "Moderado"]
    ]
    story.append(make_table(cal_headers, cal_rows, [70, 85, 168, 65, 65, 70]))
    story.append(Spacer(1, 14))

    # =========================================================================
    # SEÇÃO 23: MATRIZES DE IMPACTO DOS ANÚNCIOS
    # =========================================================================
    story.append(p("23. Matrizes de Impacto dos Anúncios (FOMC & Copom)", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("<b>Matriz de Sensibilidade de Reação do Mercado ao FOMC:</b>", h3_style))
    fomc_headers = ["Cenário FOMC", "Dólar (DXY)", "US 10Y Yield", "S&P 500", "Ouro", "Bitcoin", "USD/BRL"]
    fomc_rows = [
        ["Hawkish (Manutenção + Tom Duro)", "Alta Forte", "Alta (>5,05%)", "Queda Forte", "Queda", "Queda Forte", "Alta"],
        ["Em linha (Manutenção Neutra)", "Estável", "Estável (4,98%)", "Neutro", "Estável", "Neutro", "Estável"],
        ["Dovish (Sinalização de Corte)", "Queda", "Queda (<4,85%)", "Alta Forte", "Alta Forte", "Alta Forte", "Queda"]
    ]
    story.append(make_table(fomc_headers, fomc_rows, [133, 65, 65, 65, 65, 65, 65]))
    story.append(PageBreak())

    # =========================================================================
    # SEÇÃO 24: ANÁLISE DE CENÁRIOS
    # =========================================================================
    story.append(p("24. Análise de Cenários", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("<b>Cenário-Base (Probabilidade Estrutural Elevada):</b><br/>"
                   "O Federal Reserve mantém as taxas de juros no patamar atual, reforçando postura de vigilância sobre a inflação. O Copom reduz a Selic em 0,25 p.p. para 13,75% a.a., mantendo o carry trade atrativo. O Ibovespa consolida no intervalo 185.000–188.000 pts e o Bitcoin busca estabilização na faixa de US$ 75.000–77.000.", body_style))
    story.append(Spacer(1, 6))

    story.append(p("<b>Cenário Adverso (Estagflação Global com Petróleo > US$ 115):</b><br/>"
                   "Agravamento de conflitos geopolíticos força o barril de petróleo acima de US$ 115, empurrando o yield de 10 anos americano para acima de 5,15%. Esse quadro deflagra correção generalizada em ações e criptoativos.", body_style))
    story.append(Spacer(1, 10))

    # =========================================================================
    # SEÇÃO 25: MAPA OPERACIONAL
    # =========================================================================
    story.append(p("25. Mapa Operacional Educacional", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("<b>PLANO OPERACIONAL EDUCACIONAL — BITCOIN (BTC/USDT)</b>", h2_style))
    story.append(p("<b>Preço Atual:</b> US$ 76.150 | <b>Horizonte:</b> Intradiário / Swing (H1/H4)<br/>"
                   "<b>Tendência H4:</b> Neutra a Baixa | <b>Ponto de Controle (POC):</b> US$ 75.800", body_style))
    
    op_headers = ["Direção", "Gatilho de Confirmação", "Zona de Entrada", "Stop Loss (Invalidação)", "Alvo 1", "Alvo 2", "Relação R/R"]
    op_rows = [
        ["Cenário de Compra", "Rompimento com volume acima de US$ 76.800", "US$ 76.900", "US$ 75.400", "US$ 78.500", "US$ 80.200", "1 : 2,4"],
        ["Cenário de Venda", "Perda sustentada do suporte de US$ 75.200", "US$ 75.100", "US$ 76.300", "US$ 73.800", "US$ 72.000", "1 : 2,2"]
    ]
    story.append(make_table(op_headers, op_rows, [80, 110, 70, 85, 55, 55, 68]))
    story.append(Spacer(1, 8))
    story.append(p("<b>NÃO OPERAR SE:</b> O preço negociar comprimido entre US$ 75.500 e US$ 76.500 imediatamente antes dos anúncios do FOMC.", body_bold))
    story.append(Spacer(1, 14))

    # =========================================================================
    # SEÇÃO 26: ATIVOS EM MONITORAMENTO
    # =========================================================================
    story.append(p("26. Ativos em Monitoramento (Watchlist Prioritária)", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    watch_headers = ["Ativo", "Preço Atual", "Motivo do Monitoramento", "Compra Somente Acima", "Venda Somente Abaixo"]
    watch_rows = [
        ["PETR4", "R$ 50,43", "Testando máxima histórica com rali do petróleo", "R$ 51,50", "R$ 48,80"],
        ["Ouro Spot", "US$ 4.351,00", "Consolidação de rompimento rumo a US$ 4.400", "US$ 4.380,00", "US$ 4.280,00"],
        ["SUI", "US$ 0,725", "Líder de volume e momentum no radar cripto", "US$ 0,760", "US$ 0,680"],
        ["USD/BRL", "R$ 5,1540", "Reação direta ao diferencial de juros Copom x Fed", "R$ 5,2200", "R$ 5,1000"],
        ["US 10Y Yield", "4,98%", "Testando a barreira psicológica de 5,00%", "5,02%", "4,85%"]
    ]
    story.append(make_table(watch_headers, watch_rows, [70, 75, 178, 100, 100]))
    story.append(PageBreak())

    # =========================================================================
    # SEÇÃO 27: GRÁFICOS
    # =========================================================================
    story.append(p("27. Painel de Gráficos Analíticos", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    chart_dir = "scratch/charts"
    charts_files = [
        ("chart1_dxy_yields.png", "Gráfico 1: Trajetória do DXY vs. Yield do Treasury de 10 Anos (30 dias)"),
        ("chart2_gold.png", "Gráfico 2: Evolução das Cotações do Ouro Spot (US$/oz)"),
        ("chart3_oil.png", "Gráfico 3: Comparativo Petróleo WTI vs. Brent (US$/barril)"),
        ("chart4_ibov_usd.png", "Gráfico 4: Ibovespa (Pontos) vs. Dólar Comercial (USD/BRL)"),
        ("chart5_crypto.png", "Gráfico 5: Trajetória Recente do Bitcoin (BTC) vs. Ethereum (ETH)")
    ]

    for fname, caption in charts_files:
        fpath = os.path.join(chart_dir, fname)
        if os.path.exists(fpath):
            story.append(KeepTogether([
                p(f"<b>{caption}</b>", h3_style),
                Spacer(1, 4),
                Image(fpath, width=500, height=215),
                p("<i>Fonte: Plataforma de Inteligência de Mercado Antigravity. Atualizado em 16/09/2026.</i>", ParagraphStyle('CapFoot', parent=body_style, fontSize=11, textColor=colors.HexColor('#64748B'))),
                Spacer(1, 12)
            ]))
    story.append(PageBreak())

    # =========================================================================
    # SEÇÃO 28: FONTES E METODOLOGIA
    # =========================================================================
    story.append(p("28. Fontes e Metodologia", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    story.append(p("<b>Fontes Primárias Consultadas:</b><br/>"
                   "• Bancos Centrais: Federal Reserve (Fed), Banco Central do Brasil (BCB), Banco Central Europeu (BCE).<br/>"
                   "• Instituições Governamentais: Bureau of Labor Statistics (BLS), Energy Information Administration (EIA), IBGE.<br/>"
                   "• Bolsas de Valores e Derivativos: CME Group, B3, CBOE, ICE, Binance Futures.<br/>"
                   "• Fornecedores de Dados: Reuters, Bloomberg Terminal Data, CoinGlass, TradingView.", body_style))
    story.append(Spacer(1, 10))

    # =========================================================================
    # SEÇÃO 29: GLOSSÁRIO
    # =========================================================================
    story.append(p("29. Glossário de Mercado", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    gloss_headers = ["Sigla / Termo", "Nome Completo em Inglês / Português", "Explicação Acessível"]
    gloss_rows = [
        ["CPI", "Consumer Price Index (Índice de Preços ao Consumidor)", "Mede a variação da inflação dos produtos consumidos pelas famílias."],
        ["FOMC", "Federal Open Market Committee (Comitê de Mercado Aberto)", "Órgão do Banco Central americano responsável por definir a taxa de juros dos EUA."],
        ["Copom", "Comitê de Política Monetária do Banco Central do Brasil", "Órgão do Banco Central brasileiro responsável por fixar a taxa Selic."],
        ["DXY", "Dollar Index (Índice do Dólar Americano)", "Mede a força global do dólar comparado a uma cesta de 6 moedas estrangeiras."],
        ["OI", "Open Interest (Interesse em Aberto)", "Total de contratos futuros negociados que continuam em aberto no mercado."],
        ["PCE", "Personal Consumption Expenditures (Gastos de Consumo Pessoal)", "Indicador de inflação mais acompanhado pelo Federal Reserve."],
        ["NFP", "Nonfarm Payrolls (Folha de Pagamentos Não-Agrícola)", "Relatório mensal sobre empregos criados na economia americana."],
        ["ATR", "Average True Range (Amplitude Média Verdadeira)", "Indicador técnico que mede o grau de volatilidade de um ativo."],
        ["POC", "Point of Control (Ponto de Controle de Volume)", "Preço exato onde ocorreu o maior volume financeiro negociado."],
        ["VAH / VAL", "Value Area High / Value Area Low", "Limites superior e inferior da área que concentrou 70% do volume negociado."]
    ]
    story.append(make_table(gloss_headers, gloss_rows, [70, 160, 293]))
    story.append(Spacer(1, 14))

    # =========================================================================
    # SEÇÃO 30: AVISO LEGAL
    # =========================================================================
    story.append(p("30. Aviso Legal (Disclaimer)", h1_style))
    story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#CBD5E1'), spaceAfter=12))

    disclaimer_text = """
    Este relatório possui finalidade exclusivamente informativa e educacional. As análises, cenários, projeções e níveis operacionais apresentados não constituem recomendação individualizada de investimento, oferta de compra ou venda, solicitação ou garantia de retorno financeiro. Mercados financeiros, contratos futuros, moedas e criptoativos envolvem elevado grau de risco e podem resultar em perda total do capital investido. As informações e cotacões foram obtidas de fontes consideradas confiáveis até o horário de encerramento da edição (16/09/2026 às 10:00 BRT), estando sujeitas a alterações sem aviso prévio.
    """
    
    t_disc = Table([[Paragraph(disclaimer_text, ParagraphStyle('DiscText', parent=body_style, fontSize=12, leading=16, textColor=colors.HexColor('#475569')))]], colWidths=[523])
    t_disc.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), colors.HexColor('#F8FAFC')),
        ('BORDER', (0,0), (-1,-1), 1, colors.HexColor('#E2E8F0')),
        ('PADDING', (0,0), (-1,-1), 12),
        ('VALIGN', (0,0), (-1,-1), 'MIDDLE')
    ]))
    story.append(t_disc)

    # Build PDF using NumberedCanvas
    doc.build(story, canvasmaker=NumberedCanvas)
    print(f"PDF successfully created: {pdf_filename}")

if __name__ == "__main__":
    create_report()
