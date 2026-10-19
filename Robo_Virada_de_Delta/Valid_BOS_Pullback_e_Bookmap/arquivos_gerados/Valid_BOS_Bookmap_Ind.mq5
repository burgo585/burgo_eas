//+------------------------------------------------------------------+
//|                                      Valid_BOS_Bookmap_Ind.mq5  |
//|               Indicador Quantitativo Institucional Pro Max       |
//|               Conceito: Valid BOS Pullback & Scalpers            |
//|               Desenvolvido para: @viniciusburgo                  |
//|               Desenvolvedor Quant Sênior                         |
//+------------------------------------------------------------------+
#property copyright   "@viniciusburgo - Quant Trading Systems"
#property link        "https://www.mql5.com"
#property version     "5.25"
#property description "Indicador Institucional com Rastreamento Multi-Estrutura de Topos e Fundos,"
#property description "Marcação Completa de Pivôs no Gráfico, Monitor de Microestrutura ao Vivo,"
#property description "Zonas de Liquidez Retangulares, Sinais de Rejeição/BOS e Scalpers Intermediários."
#property description "Painel arrastável (Draggable) e minimizável com diagnóstico e alertas sonoros."

#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   4

// Plot 1: Sinal de Compra Principal (Valid BOS Bullish)
#property indicator_label1  "Valid BOS Bullish"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLimeGreen
#property indicator_style1  STYLE_SOLID
#property indicator_width1  4

// Plot 2: Sinal de Venda Principal (Valid BOS Bearish)
#property indicator_label2  "Valid BOS Bearish"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrCrimson
#property indicator_style2  STYLE_SOLID
#property indicator_width2  4

// Plot 3: Sinal Scalper Compra (Micro-Pullback)
#property indicator_label3  "Scalp Buy"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrCyan
#property indicator_style3  STYLE_SOLID
#property indicator_width3  3

// Plot 4: Sinal Scalper Venda (Micro-Pullback)
#property indicator_label4  "Scalp Sell"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrDarkOrange
#property indicator_style4  STYLE_SOLID
#property indicator_width3  3

//+------------------------------------------------------------------+
//| ENUMERAÇÕES                                                      |
//+------------------------------------------------------------------+
enum ENUM_CONFIRM_IND_METHOD
{
   IND_CONFIRM_ON_CLOSE = 0, // Fechamento do Candle (Garantia de 0 Repainting)
   IND_CONFIRM_ON_WICK  = 1  // Toque da Máxima/Mínima (Wick)
};

enum ENUM_IND_STATE
{
   IND_STATE_IDLE                = 0, // Aguardando rompimento do nível inicial
   IND_STATE_EXPANDING           = 1, // Nível rompido, contando barras de expansão
   IND_STATE_EXPANSION_QUALIFIED = 2, // Expansão mínima atingida, aguardando recuo tocar o nível
   IND_STATE_VALID_PULLBACK      = 3  // Pullback válido confirmado (linha pontilhada/zona), aguardando BOS
};

enum ENUM_IND_ENTRY_TRIGGER
{
   IND_ENTRY_PULLBACK_REJ = 0, // Entrada na Rejeição do Reteste (Smart Money: Stop Curto & Alto R:R)
   IND_ENTRY_VALID_BOS    = 1  // Entrada no Rompimento do Extremo (BOS Clássico Conservador)
};

enum ENUM_TRADE_STATUS
{
   TRADE_NONE      = 0,
   TRADE_RUNNING   = 1,
   TRADE_HIT_TP    = 2,
   TRADE_HIT_SL    = 3
};

//+------------------------------------------------------------------+
//| PARÂMETROS DE ENTRADA (INPUTS)                                   |
//+------------------------------------------------------------------+
input group "=== 1. DETECÇÃO DE ESTRUTURA INSTITUCIONAL (BOS) ==="
input int                     InpPivotLegs             = 3;                    // Período do Pivô (3 barras esq/dir = confirmação ágil)
input int                     InpMinExpansionBars      = 2;                    // Barras Mínimas de Expansão (2 barras = valor ótimo)
input int                     InpMaxStructureBars      = 40;                   // Expiração Máxima da Estrutura (em Barras)
input int                     InpRetestTolerancePts    = 30;                   // Tolerância de Reteste da Zona (Pontos - Garante Reteste Real)
input int                     InpHistoryLookback       = 500;                  // Barras Históricas para Análise
input ENUM_CONFIRM_IND_METHOD InpConfirmMethod         = IND_CONFIRM_ON_CLOSE; // Critério de Confirmação

input group "=== 2. FILTROS INSTITUCIONAIS DE ALTA ASSERTIVIDADE ==="
input ENUM_IND_ENTRY_TRIGGER  InpEntryTrigger          = IND_ENTRY_PULLBACK_REJ; // Modo de Entrada (Rejeição no Reteste ou BOS)
input bool                    InpUseEMATrendFilter     = true;                   // Ativar Filtro de Tendência Macro (EMA 200)?
input int                     InpEMAPeriod             = 200;                    // Período da EMA Macro
input bool                    InpUseADXFilter          = true;                   // Ativar Filtro Anti-Lateralização (ADX)?
input int                     InpADXPeriod             = 14;                     // Período do ADX
input double                  InpMinADXLevel           = 20.0;                   // Nível Mínimo do ADX (Filtra Mercado Lateral)
input bool                    InpRequireRejectionCandle= true;                   // Exigir Candle de Rejeição de Price Action no Reteste?
input int                     InpMinBOSDisplacementPts = 30;                     // Deslocamento Mínimo no BOS (Pontos - Anti-Violinada)
input bool                    InpFilterVisuals         = false;                  // Filtrar Desenho no Gráfico? (false = Plota TODAS as estruturas)

input group "=== 3. SCALPERS NOS MOVIMENTOS INTERMEDIÁRIOS ==="
input bool                    InpEnableScalpers        = true;                 // Ativar Sinais de Scalper Intermediário?
input int                     InpScalpLookbackBars     = 3;                    // Barras Mínimas de Recuo para Micro-Pullback (2 a 5)
input double                  InpScalpRiskReward       = 1.2;                  // Relação R:R para Alvo Curto do Scalper
input double                  InpScalpMinWickPct       = 25.0;                 // Percentual Mínimo de Pavio de Rejeição no Scalper (%)

input group "=== 4. PLANO DE TRADE: ENTRADA, STOP LOSS & ALVOS ==="
input double                  InpRiskRewardRatio       = 2.0;                  // Relação Risco:Retorno para Take Profit Principal
input int                     InpSLBufferPoints        = 20;                   // Folga de Stop Loss além do Pullback (Pontos)
input bool                    InpUseBreakEvenSim       = true;                 // Simular Proteção no 0x0 (Break-Even) ao Atingir 1R?
input bool                    InpShowProjectedBoxes    = true;                 // Exibir Caixas e Linhas de SL/TP no Gráfico?
input bool                    InpTrackActiveTrade      = true;                 // Monitorar Saída (Atingimento de TP / SL)?

input group "=== 5. MONITORAMENTO EM TEMPO REAL DA VELA & FLUXO ==="
input bool                    InpShowCandleTimer       = true;                 // Exibir Contador Regressivo do Candle Atual?
input bool                    InpShowLiveCandleTag     = true;                 // Exibir Etiqueta Flutuante de Ação da Vela no Gráfico?
input bool                    InpAlertPopUp            = true;                 // Alerta em Janela Pop-Up?
input bool                    InpAlertSound            = true;                 // Alerta Sonoro Ativo?
input string                  InpSoundBOS              = "alert.wav";          // Som: Sinal BOS Principal
input string                  InpSoundScalp            = "news.wav";           // Som: Sinal Scalper Intermediário
input string                  InpSoundTP               = "expert.wav";         // Som: Take Profit Atingido
input string                  InpSoundSL               = "timeout.wav";        // Som: Stop Loss Acionado
input bool                    InpAlertPush             = false;                // Notificação Push no Celular?

input group "=== 6. MARCAÇÕES ULTRA VISÍVEIS NO GRÁFICO ==="
input bool                    InpShowSwingPivots       = true;                 // Plotar Rótulos de Topos e Fundos (Swings) no Gráfico?
input bool                    InpShowBrokenLevels      = true;                 // Manter Níveis Rompidos no Histórico como Guia?
input bool                    InpDrawZoneBoxes         = true;                 // Desenhar Caixas de Zonas de Liquidez / Reteste?
input bool                    InpShowActiveLevels      = true;                 // Exibir Linhas de Níveis Ativos (Topo/Fundo a Romper)?
input bool                    InpDrawStructureLines    = true;                 // Desenhar Linhas de Setups (Pontilhadas e Sólidas)?
input bool                    InpShowLabels            = true;                 // Exibir Rótulos em Destaque (Valid Pullback / Valid BOS)?
input color                   InpColorBullish          = clrLimeGreen;         // Cor de Alta (Verde Neon)
input color                   InpColorBearish          = clrCrimson;           // Cor de Baixa (Vermelho Neon)
input color                   InpColorPullback         = clrDeepSkyBlue;       // Cor do Pullback (Azul Ciano)
input color                   InpColorScalpBull        = clrCyan;              // Cor do Scalper de Alta
input color                   InpColorScalpBear        = clrDarkOrange;        // Cor do Scalper de Baixa
input color                   InpColorLevels           = clrDarkOrange;        // Cor das Linhas Ativas Vigentes
input color                   InpColorZoneBox          = C'20,40,65';          // Cor da Caixa da Zona de Liquidez
input int                     InpArrowBullCode         = 233;                  // Código do Arrow de Alta (Wingdings: Seta para cima)
input int                     InpArrowBearCode         = 234;                  // Código do Arrow de Baixa (Wingdings: Seta para baixo)


//+------------------------------------------------------------------+
//| PARÂMETROS INSTITUCIONAIS BOOKMAP (COMEX GC)                     |
//+------------------------------------------------------------------+
input group "=== 8. INTEGRAÇÃO INSTITUCIONAL BOOKMAP (COMEX GC) ==="
input bool                    InpUseBookmap            = true;                 // Ativar Conexão com Bookmap (COMEX Fluxo Real)?
input string                  InpBookmapHost           = "127.0.0.1";          // Host do Servidor Bookmap
input int                     InpBookmapPort           = 5555;                 // Porta do Servidor Bookmap
input bool                    InpAutoBasisTracking     = true;                 // Rastreamento Automático do Desconto (Basis)?
input double                  InpManualBasisOffset     = 20.0;                 // Desconto Manual (se Auto-Rastreamento = false)
input bool                    InpPlotBookmapLevels     = true;                 // Plotar Linhas de Liquidez do Bookmap no Gráfico?
input bool                    InpUseVwapWickSignal     = true;                 // Ativar Sinal Institucional de Absorção na VWAP?
input int                     InpMinAggressionDelta    = 50;                   // Delta Mínimo de Agressão do Bookmap (+/-)
input double                  InpMinWickPct            = 20.0;                 // Tamanho Mínimo do Pavio (% do Candle)
input int                     InpMinWallVolume         = 200;                  // Volume Mínimo para Parede de Liquidez (Lotes)
input int                     InpScalpTakeProfitPts    = 250;                  // Alvo Padrão TP1 (Scalp 50%) em Pontos
input int                     InpMinSLPoints           = 50;                   // Distância Mínima de Stop Loss (Pontos)
input color                   InpColorBookmapVWAP      = clrMagenta;           // Cor da VWAP Total do Bookmap
input color                   InpColorBookmapPOC       = clrGold;              // Cor do POC da COMEX
input color                   InpColorBookmapVAH       = C'255,140,80';        // Cor do VAH (Value Area High 70%)
input color                   InpColorBookmapVAL       = C'100,180,255';       // Cor do VAL (Value Area Low 70%)
input color                   InpColorBookmapHVN       = clrDeepSkyBlue;       // Cor do Nó de Volume (HVN)
input color                   InpColorBidWall          = clrLimeGreen;         // Cor da Parede de Compra (Bid Wall)
input color                   InpColorAskWall          = clrRed;               // Cor da Parede de Venda (Ask Wall)

input group "=== 7. PAINEL ARRASTÁVEL E MINIMIZÁVEL (HUD DASHBOARD) ==="
input bool                    InpShowDashboard         = true;                 // Ativar Painel Interativo na Tela?
input int                     InpInitialPanelX         = 25;                   // Posição Inicial X (Pixels da Esquerda)
input int                     InpInitialPanelY         = 40;                   // Posição Inicial Y (Pixels do Topo)
input int                     InpFontSize              = 8;                    // Tamanho da Fonte do Painel (7 a 14)
input bool                    InpAutoScalePanel        = true;                 // Auto-Ajustar Dimensões Proporcional à Fonte?
input int                     InpPanelWidth            = 450;                  // Largura Manual (se Auto-Ajustar = false)
input int                     InpPanelHeight           = 320;                  // Altura Manual (se Auto-Ajustar = false)
input color                   InpPanelBgColor          = C'14,18,28';          // Cor de Fundo do Painel
input color                   InpPanelHeaderColor      = C'22,30,48';          // Cor do Cabeçalho do Painel
input color                   InpPanelBorderColor      = C'45,65,95';          // Cor da Borda do Painel

//+------------------------------------------------------------------+
//| BUFFERS DO INDICADOR                                             |
//+------------------------------------------------------------------+
double BufferBullBOS[];
double BufferBearBOS[];
double BufferScalpBull[];
double BufferScalpBear[];
double BufferSLReference[];
double BufferTargetReference[];

//+------------------------------------------------------------------+
//| ESTRUTURAS INTERNAS (MOTOR MULTI-ESTRUTURA)                      |
//+------------------------------------------------------------------+
struct SSwingPoint
{
   int      direction; // 1 = Topo (High), -1 = Fundo (Low)
   double   price;
   datetime time;
   int      barIndex;
   bool     broken;
};

struct SIndStructure
{
   int            id;
   int            direction;        // 1 = Bullish, -1 = Bearish
   ENUM_IND_STATE state;
   datetime       breakoutTime;
   int            breakoutIndex;
   double         refLevel;
   datetime       pivotTime;
   double         extremePrice;
   datetime       extremeTime;
   double         pullbackExtreme;
   datetime       pullbackTime;
   string         lineName;
   string         pbLabelName;
   string         bosLabelName;
   string         zoneBoxName;
   bool           tradeTriggered;
   bool           isActive;
};

struct SActiveTradeMonitor
{
   ENUM_TRADE_STATUS status;
   int               direction;      // 1 = BUY, -1 = SELL
   bool              isScalp;
   double            entryPrice;
   datetime          entryTime;
   double            slPrice;
   double            tpPrice;
   double            riskPoints;
   double            rewardPoints;
   string            entryLineName;
   string            slLineName;
   string            tpLineName;
   string            boxName;
   string            outcomeLabel;

   void Reset()
   {
      status       = TRADE_NONE;
      direction    = 0;
      isScalp      = false;
      entryPrice   = 0.0;
      entryTime    = 0;
      slPrice      = 0.0;
      tpPrice      = 0.0;
      riskPoints   = 0.0;
      rewardPoints = 0.0;
      entryLineName= "";
      slLineName   = "";
      tpLineName   = "";
      boxName      = "";
      outcomeLabel = "";
   }
};

SSwingPoint         g_swings[];
SIndStructure       g_structures[];
int                 g_structureCounter = 0;
SActiveTradeMonitor g_activeTrade;

//+------------------------------------------------------------------+
//| ESTRUTURA DE DADOS DO BOOKMAP EM TEMPO REAL                      |
//+------------------------------------------------------------------+
struct SBookmapData
{
   string   symbol;
   double   lastPrice;
   double   vwap;
   double   poc;
   double   vah;
   double   val;
   double   hvn;
   double   profileHigh;
   double   profileLow;
   double   bidWallPrice;
   int      bidWallVol;
   double   askWallPrice;
   int      askWallVol;
   long     delta;
   long     cvd;
   long     totalVol;
   datetime lastUpdateTime;
   bool     isConnected;
};

SBookmapData g_bmData;
double       g_smoothedBasis       = 0.0;
int          g_socketHandle        = INVALID_HANDLE;
datetime     g_lastSocketTry       = 0;
ulong        g_lastFileRead        = 0;
bool         g_signalsActive       = true;       // Controle Manual de Sinais
bool         g_bookmapActive       = true;       // Controle Manual do Bookmap
int          g_lastSignalDirection = 0;          // 1 = Compra, -1 = Venda, 0 = Neutro
double       g_lastSignalEntry     = 0.0;
double       g_lastSignalSL        = 0.0;
double       g_lastSignalTP1       = 0.0;
double       g_lastSignalTP2       = 0.0;

// OTIMIZAÇÃO DE PERFORMANCE (ULTRA-LEVE)
ulong        g_lastRedrawTick      = 0;
int          g_lastSecRem          = -1;
double       g_lastBidPrice        = 0.0;
long         g_lastDelta           = 0;
double       g_lastRenderedVwap    = 0.0;
double       g_lastRenderedPoc     = 0.0;
double       g_lastRenderedVah     = 0.0;
double       g_lastRenderedVal     = 0.0;
double       g_lastRenderedHvn     = 0.0;
double       g_lastRenderedBidWall = 0.0;
double       g_lastRenderedAskWall = 0.0;
datetime     g_lastRenderTime      = 0;


// Níveis Vigentes
double   g_currentSwingHigh   = 0.0;
datetime g_currentHighTime    = 0;
double   g_currentSwingLow    = 0.0;
datetime g_currentLowTime     = 0;

// Estatísticas
int      g_totalValidPullbacks = 0;
int      g_totalValidBOS       = 0;
int      g_totalScalps         = 0;
int      g_totalTradesWon      = 0;
int      g_totalTradesLost     = 0;
string   g_lastSignalText      = "Aguardando estrutura...";
color    g_lastSignalColor     = clrSilver;

// Diagnóstico de Ação do Candle em Tempo Real
string   g_candleActionText    = "Monitorando fluxo...";
color    g_candleActionColor   = clrSilver;
string   g_candleContextDiag   = "Aguardando níveis";
datetime g_lastScalpTime       = 0;

// Painel Interativo Arrastável
int      g_fontSize            = 8;
int      g_panelX              = 25;
int      g_panelY              = 40;
int      g_panelWidth          = 450;
int      g_panelHeightFull     = 320;
int      g_panelHeightMin      = 34;
int      g_headerH             = 32;
int      g_lineH               = 20;
int      g_lineYStart          = 38;
bool     g_panelMinimized      = false;
bool     g_isDragging          = false;
int      g_dragOffsetX         = 0;
int      g_dragOffsetY         = 0;

// Handles de Filtros Técnicos
int      g_handleEMA           = INVALID_HANDLE;
int      g_handleADX           = INVALID_HANDLE;

const string G_PREFIX          = "VBPI_";

//+------------------------------------------------------------------+
//| FUNÇÕES AUXILIARES DE CÁLCULO E LAYOUT                           |
//+------------------------------------------------------------------+
int GetLineRelY(int lineIndex)
{
   int extraGap = 0;
   if(lineIndex >= 2) extraGap += 3;
   if(lineIndex >= 5) extraGap += 4;
   if(lineIndex >= 8) extraGap += 4;
   if(lineIndex >= 11) extraGap += 4;
   if(lineIndex >= 14) extraGap += 4;
   return g_lineYStart + (lineIndex * g_lineH) + extraGap;
}

void CalculateDashboardDimensions()
{
   g_fontSize = MathMax(7, MathMin(14, InpFontSize));
   double scale = (double)g_fontSize / 8.0;

   g_headerH    = (int)MathRound(34.0 * scale);
   g_lineH      = (int)MathRound(19.0 * scale);
   g_lineYStart = g_headerH + 6;

   int totalLines = 15;
   g_panelHeightFull = g_lineYStart + (totalLines * g_lineH) + 24;
   g_panelHeightMin  = g_headerH + 4;
   g_panelWidth      = (int)MathRound(560.0 * scale);
}

bool IsTrendAligned(int dir, int idx, const double &emaData[], const double &closeData[])
{
   if(!InpUseEMATrendFilter || g_handleEMA == INVALID_HANDLE) return true;
   if(idx < 0 || idx >= ArraySize(emaData) || idx >= ArraySize(closeData)) return true;

   if(dir == 1)  return (closeData[idx] > emaData[idx]);
   if(dir == -1) return (closeData[idx] < emaData[idx]);
   return true;
}

bool IsMarketTrending(int idx, const double &adxData[])
{
   if(!InpUseADXFilter || g_handleADX == INVALID_HANDLE) return true;
   if(idx < 0 || idx >= ArraySize(adxData)) return true;
   return (adxData[idx] >= InpMinADXLevel);
}

bool HasBullishRejection(double openP, double highP, double lowP, double closeP)
{
   double range = highP - lowP;
   if(range <= 0.0) return false;
   double lowerWick = MathMin(openP, closeP) - lowP;
   return ((lowerWick / range) >= 0.25 || closeP > openP);
}

bool HasBearishRejection(double openP, double highP, double lowP, double closeP)
{
   double range = highP - lowP;
   if(range <= 0.0) return false;
   double upperWick = highP - MathMax(openP, closeP);
   return ((upperWick / range) >= 0.25 || closeP < openP);
}

//+------------------------------------------------------------------+
//| INICIALIZAÇÃO DO INDICADOR                                       |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufferBullBOS, INDICATOR_DATA);
   SetIndexBuffer(1, BufferBearBOS, INDICATOR_DATA);
   SetIndexBuffer(2, BufferScalpBull, INDICATOR_DATA);
   SetIndexBuffer(3, BufferScalpBear, INDICATOR_DATA);
   SetIndexBuffer(4, BufferSLReference, INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, BufferTargetReference, INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0, PLOT_ARROW, InpArrowBullCode);
   PlotIndexSetInteger(1, PLOT_ARROW, InpArrowBearCode);
   PlotIndexSetInteger(2, PLOT_ARROW, 217); // Seta menor para cima
   PlotIndexSetInteger(3, PLOT_ARROW, 218); // Seta menor para baixo

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, 0.0);

   string shortName = StringFormat("Valid_BOS_Pullback_Pro(%d,%d,R:R=%.1f)", InpPivotLegs, InpMinExpansionBars, InpRiskRewardRatio);
   IndicatorSetString(INDICATOR_SHORTNAME, shortName);
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   if(InpUseEMATrendFilter)
   {
      g_handleEMA = iMA(_Symbol, _Period, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   }

   if(InpUseADXFilter)
   {
      g_handleADX = iADX(_Symbol, _Period, InpADXPeriod);
   }

   g_activeTrade.Reset();
   ArrayResize(g_swings, 0);
   ArrayResize(g_structures, 0);
   g_structureCounter = 0;

   CleanObjects(G_PREFIX);

   if(InpShowDashboard)
   {
      CreateInteractiveDashboard();
   }

   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   EventSetMillisecondTimer(500);
   UpdateBookmapData();
   RenderBookmapLevels();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| DESINICIALIZAÇÃO DO INDICADOR                                    |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_handleEMA != INVALID_HANDLE) IndicatorRelease(g_handleEMA);
   if(g_handleADX != INVALID_HANDLE) IndicatorRelease(g_handleADX);

   CleanObjects(G_PREFIX);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| TRATAMENTO DE EVENTOS DE GRÁFICO (MOUSE / DRAG / BOTÕES)         |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(!InpShowDashboard) return;

   // 1. Cliques nos Botões do Cabeçalho
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == G_PREFIX + "Btn_Min")
      {
         g_panelMinimized = !g_panelMinimized;
         ObjectSetString(0, G_PREFIX + "Btn_Min", OBJPROP_TEXT, g_panelMinimized ? "+" : "—");
         ObjectSetInteger(0, G_PREFIX + "Dash_BG", OBJPROP_YSIZE, g_panelMinimized ? g_panelHeightMin : g_panelHeightFull);
         UpdateDashboardVisibility();
         ChartRedraw(0);
         return;
      }

      if(sparam == G_PREFIX + "Btn_Reset")
      {
         g_totalTradesWon      = 0;
         g_totalTradesLost     = 0;
         g_totalValidPullbacks = 0;
         g_totalValidBOS       = 0;
         g_totalScalps         = 0;
         g_lastSignalDirection = 0;
         g_lastSignalText      = "Estatísticas Resetadas";
         g_lastSignalColor     = clrSilver;
         g_activeTrade.Reset();
         CleanObjects(G_PREFIX + "Trade_");
         CleanObjects(G_PREFIX + "Outcome_");
         CleanObjects(G_PREFIX + "Bull_Zone_");
         CleanObjects(G_PREFIX + "Bear_Zone_");
         UpdateDashboardContent(SymbolInfoDouble(_Symbol, SYMBOL_BID));
         ChartRedraw(0);
         return;
      }

      if(sparam == G_PREFIX + "Btn_ToggleSignals")
      {
         g_signalsActive = !g_signalsActive;
         ObjectSetString(0, G_PREFIX + "Btn_ToggleSignals", OBJPROP_TEXT, g_signalsActive ? "🟢 SINAIS: ON" : "🔴 SINAIS: OFF");
         ObjectSetInteger(0, G_PREFIX + "Btn_ToggleSignals", OBJPROP_BGCOLOR, g_signalsActive ? C'20,60,35' : C'70,25,25');
         UpdateDashboardContent(SymbolInfoDouble(_Symbol, SYMBOL_BID));
         ChartRedraw(0);
         return;
      }

      if(sparam == G_PREFIX + "Btn_ToggleBM")
      {
         g_bookmapActive = !g_bookmapActive;
         ObjectSetString(0, G_PREFIX + "Btn_ToggleBM", OBJPROP_TEXT, g_bookmapActive ? "⚡ BM: ON" : "⚡ BM: OFF");
         ObjectSetInteger(0, G_PREFIX + "Btn_ToggleBM", OBJPROP_BGCOLOR, g_bookmapActive ? C'25,50,75' : C'50,50,50');
         ObjectSetInteger(0, G_PREFIX + "Btn_ToggleBM", OBJPROP_COLOR, g_bookmapActive ? clrAqua : clrSilver);
         if(!g_bookmapActive)
         {
            ObjectDelete(0, G_PREFIX + "BM_VWAP");
            ObjectDelete(0, G_PREFIX + "BM_POC");
            ObjectDelete(0, G_PREFIX + "BM_VAH");
            ObjectDelete(0, G_PREFIX + "BM_VAL");
            ObjectDelete(0, G_PREFIX + "BM_HVN");
            ObjectDelete(0, G_PREFIX + "BM_BidWall");
            ObjectDelete(0, G_PREFIX + "BM_AskWall");
         }
         else
         {
            RenderBookmapLevels();
         }
         ChartRedraw(0);
         return;
      }
   }

   // 2. Arrastar livremente com clique e arrasto no cabeçalho
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int mouseX = (int)lparam;
      int mouseY = (int)dparam;
      uint mouseState = (uint)sparam;
      bool leftDown = ((mouseState & 1) == 1);

      if(leftDown)
      {
         if(!g_isDragging)
         {
            if(mouseX >= g_panelX && mouseX <= (g_panelX + g_panelWidth) &&
               mouseY >= g_panelY && mouseY <= (g_panelY + g_headerH))
            {
               g_isDragging  = true;
               g_dragOffsetX = mouseX - g_panelX;
               g_dragOffsetY = mouseY - g_panelY;
            }
         }
         else
         {
            g_panelX = mouseX - g_dragOffsetX;
            g_panelY = mouseY - g_dragOffsetY;

            int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
            int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

            if(g_panelX < 0) g_panelX = 0;
            if(g_panelY < 0) g_panelY = 0;
            if(g_panelX + g_panelWidth > chartW) g_panelX = MathMax(0, chartW - g_panelWidth);
            if(g_panelY + g_headerH > chartH)    g_panelY = MathMax(0, chartH - g_headerH);

            RepositionDashboard();
            ChartRedraw(0);
         }
      }
      else
      {
         g_isDragging = false;
      }
   }
}

//+------------------------------------------------------------------+
//| GERENCIAMENTO DE SWINGS E ESTRUTURAS                             |
//+------------------------------------------------------------------+
void AddSwing(int dir, double price, datetime t, int idx)
{
   int sz = ArraySize(g_swings);
   if(sz > 0 && g_swings[sz-1].time == t && g_swings[sz-1].direction == dir)
      return;

   if(sz >= 60)
   {
      for(int k = 0; k < sz - 1; k++)
         g_swings[k] = g_swings[k+1];
      ArrayResize(g_swings, sz - 1);
      sz--;
   }

   ArrayResize(g_swings, sz + 1);
   g_swings[sz].direction = dir;
   g_swings[sz].price     = price;
   g_swings[sz].time      = t;
   g_swings[sz].barIndex  = idx;
   g_swings[sz].broken    = false;
}

void AddStructure(int dir, double refLvl, datetime pTime, int bIndex, datetime bTime, double extPrice, bool drawObjects)
{
   int sz = ArraySize(g_structures);
   if(sz >= 30)
   {
      for(int k = 0; k < sz - 1; k++)
         g_structures[k] = g_structures[k+1];
      ArrayResize(g_structures, sz - 1);
      sz--;
   }

   ArrayResize(g_structures, sz + 1);
   g_structureCounter++;
   g_structures[sz].id              = g_structureCounter;
   g_structures[sz].direction       = dir;
   g_structures[sz].state           = IND_STATE_EXPANDING;
   g_structures[sz].breakoutTime    = bTime;
   g_structures[sz].breakoutIndex   = bIndex;
   g_structures[sz].refLevel        = refLvl;
   g_structures[sz].pivotTime       = pTime;
   g_structures[sz].extremePrice    = extPrice;
   g_structures[sz].extremeTime     = bTime;
   g_structures[sz].pullbackExtreme = 0.0;
   g_structures[sz].pullbackTime    = 0;
   g_structures[sz].tradeTriggered  = false;
   g_structures[sz].isActive        = true;

   string dirStr = (dir == 1) ? "Bull_" : "Bear_";
   g_structures[sz].lineName = G_PREFIX + dirStr + "Line_" + IntegerToString(g_structureCounter) + "_" + TimeToString(bTime);
   g_structures[sz].pbLabelName  = "";
   g_structures[sz].bosLabelName = "";
   g_structures[sz].zoneBoxName  = "";

   if(InpDrawStructureLines && drawObjects)
   {
      color lClr = (dir == 1) ? InpColorBullish : InpColorBearish;
      DrawTrend(g_structures[sz].lineName, pTime, refLvl, bTime, refLvl, lClr, STYLE_SOLID, 2);
   }
}

//+------------------------------------------------------------------+
//| CÁLCULO PRINCIPAL DO INDICADOR (ONCALCULATE)                     |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| MÓDULO DE INTEGRAÇÃO COM BOOKMAP (COMEX FLUXO REAL)              |
//+------------------------------------------------------------------+
string ExtractJsonString(string json, string key)
{
   int pos = StringFind(json, key);
   if(pos < 0) return "";
   pos += StringLen(key);
   if(StringGetCharacter(json, pos) == 34) pos++;
   int endPos = StringFind(json, CharToString(34), pos);
   if(endPos < 0) return "";
   return StringSubstr(json, pos, endPos - pos);
}

double ExtractJsonDouble(string json, string key)
{
   int pos = StringFind(json, key);
   if(pos < 0) return 0.0;
   pos += StringLen(key);
   string sub = StringSubstr(json, pos);
   return StringToDouble(sub);
}

void ParseBookmapJson(string json)
{
   if(StringLen(json) < 10) return;

   double lp = ExtractJsonDouble(json, "\"lp\":");
   if(lp <= 0.0) return;

   g_bmData.lastPrice    = lp;
   g_bmData.vwap         = ExtractJsonDouble(json, "\"vwap\":");
   g_bmData.poc          = ExtractJsonDouble(json, "\"poc\":");
   g_bmData.vah          = ExtractJsonDouble(json, "\"vah\":");
   g_bmData.val          = ExtractJsonDouble(json, "\"val\":");
   g_bmData.hvn          = ExtractJsonDouble(json, "\"hvn\":");
   g_bmData.profileHigh  = ExtractJsonDouble(json, "\"prh\":");
   g_bmData.profileLow   = ExtractJsonDouble(json, "\"prl\":");
   g_bmData.bidWallPrice = ExtractJsonDouble(json, "\"bwp\":");
   g_bmData.bidWallVol   = (int)ExtractJsonDouble(json, "\"bwv\":");
   g_bmData.askWallPrice = ExtractJsonDouble(json, "\"awp\":");
   g_bmData.askWallVol   = (int)ExtractJsonDouble(json, "\"awv\":");
   g_bmData.delta        = (long)ExtractJsonDouble(json, "\"del\":");
   g_bmData.cvd          = (long)ExtractJsonDouble(json, "\"cvd\":");
   g_bmData.totalVol     = (long)ExtractJsonDouble(json, "\"vol\":");

   double curBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(curBid <= 0.0) curBid = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Normalização Multi-Ativo Inteligente (Ouro GC, Bitcoin BTC, etc.)
   if(curBid > 0.0 && g_bmData.lastPrice > curBid * 5.0)
   {
      double ratio = MathRound(g_bmData.lastPrice / curBid);
      if(ratio >= 8.0 && ratio <= 12.0)
      {
         g_bmData.lastPrice    /= 10.0;
         if(g_bmData.vwap > 0.0) g_bmData.vwap /= 10.0;
         g_bmData.poc          /= 10.0;
         if(g_bmData.vah > 0.0)  g_bmData.vah  /= 10.0;
         if(g_bmData.val > 0.0)  g_bmData.val  /= 10.0;
         g_bmData.hvn          /= 10.0;
         if(g_bmData.profileHigh > 0.0) g_bmData.profileHigh /= 10.0;
         if(g_bmData.profileLow > 0.0)  g_bmData.profileLow  /= 10.0;
         if(g_bmData.bidWallPrice > 0.0) g_bmData.bidWallPrice /= 10.0;
         if(g_bmData.askWallPrice > 0.0) g_bmData.askWallPrice /= 10.0;
      }
      else if(ratio >= 80.0 && ratio <= 120.0)
      {
         g_bmData.lastPrice    /= 100.0;
         if(g_bmData.vwap > 0.0) g_bmData.vwap /= 100.0;
         g_bmData.poc          /= 100.0;
         if(g_bmData.vah > 0.0)  g_bmData.vah  /= 100.0;
         if(g_bmData.val > 0.0)  g_bmData.val  /= 100.0;
         g_bmData.hvn          /= 100.0;
         if(g_bmData.profileHigh > 0.0) g_bmData.profileHigh /= 100.0;
         if(g_bmData.profileLow > 0.0)  g_bmData.profileLow  /= 100.0;
         if(g_bmData.bidWallPrice > 0.0) g_bmData.bidWallPrice /= 100.0;
         if(g_bmData.askWallPrice > 0.0) g_bmData.askWallPrice /= 100.0;
      }
   }
   else if(g_bmData.lastPrice > 10000.0 && curBid < 10000.0)
   {
      g_bmData.lastPrice /= 10.0;
      if(g_bmData.vwap > 10000.0) g_bmData.vwap /= 10.0;
      g_bmData.poc /= 10.0;
      if(g_bmData.vah > 10000.0) g_bmData.vah /= 10.0;
      if(g_bmData.val > 10000.0) g_bmData.val /= 10.0;
      g_bmData.hvn /= 10.0;
      if(g_bmData.profileHigh > 10000.0) g_bmData.profileHigh /= 10.0;
      if(g_bmData.profileLow > 10000.0)  g_bmData.profileLow  /= 10.0;
      if(g_bmData.bidWallPrice > 10000.0) g_bmData.bidWallPrice /= 10.0;
      if(g_bmData.askWallPrice > 10000.0) g_bmData.askWallPrice /= 10.0;
   }

   double areaOffset = (curBid > 10000.0) ? (curBid * 0.003) : 3.0;
   if(g_bmData.vah <= 0.0 && g_bmData.poc > 0.0) g_bmData.vah = g_bmData.poc + areaOffset;
   if(g_bmData.val <= 0.0 && g_bmData.poc > 0.0) g_bmData.val = g_bmData.poc - areaOffset;
   if(g_bmData.profileHigh <= 0.0) g_bmData.profileHigh = (g_bmData.vah > 0.0) ? (g_bmData.vah + areaOffset * 1.5) : (g_bmData.lastPrice + areaOffset * 3.0);
   if(g_bmData.profileLow <= 0.0)  g_bmData.profileLow  = (g_bmData.val > 0.0) ? (g_bmData.val - areaOffset * 1.5) : (g_bmData.lastPrice - areaOffset * 3.0);

   if(g_bmData.lastPrice > 0.0)
   {
      if(!g_bmData.isConnected)
      {
         PrintFormat("⚡ [BOOKMAP CONECTADO] COMEX: %.2f USD | Delta: %d | Poc: %.2f | VAH: %.2f | VAL: %.2f | VWAP: %.2f", g_bmData.lastPrice, g_bmData.delta, g_bmData.poc, g_bmData.vah, g_bmData.val, g_bmData.vwap);
      }
      g_bmData.lastUpdateTime = TimeCurrent();
      g_bmData.isConnected = true;

      if(curBid > 0.0)
      {
         double rawBasis = g_bmData.lastPrice - curBid;
         if(InpAutoBasisTracking)
         {
            double basisThreshold = (curBid > 10000.0) ? 1000.0 : 50.0;
            if(g_smoothedBasis == 0.0 || MathAbs(g_smoothedBasis - rawBasis) > basisThreshold)
               g_smoothedBasis = rawBasis;
            else
               g_smoothedBasis = (g_smoothedBasis * 0.95) + (rawBasis * 0.05);
         }
         else
         {
            g_smoothedBasis = InpManualBasisOffset;
         }
      }
   }
}

void UpdateBookmapData()
{
   if(!InpUseBookmap) return;

   datetime now = TimeCurrent();
   string payload = "";

   // 1. Tentar ler do Socket TCP se disponível
   if(g_socketHandle == INVALID_HANDLE && (now - g_lastSocketTry >= 3))
   {
      g_lastSocketTry = now;
      g_socketHandle = SocketCreate();
      if(g_socketHandle != INVALID_HANDLE)
      {
         if(!SocketConnect(g_socketHandle, InpBookmapHost, InpBookmapPort, 50))
         {
            SocketClose(g_socketHandle);
            g_socketHandle = INVALID_HANDLE;
         }
      }
   }

   if(g_socketHandle != INVALID_HANDLE)
   {
      if(!SocketIsConnected(g_socketHandle))
      {
         SocketClose(g_socketHandle);
         g_socketHandle = INVALID_HANDLE;
      }
      else
      {
         uint readable = SocketIsReadable(g_socketHandle);
         if(readable > 0)
         {
            uchar buffer[];
            ArrayResize(buffer, (int)readable + 1);
            int bytesRead = SocketRead(g_socketHandle, buffer, readable, 20);
            if(bytesRead > 0)
            {
               buffer[bytesRead] = 0;
               payload = CharArrayToString(buffer, 0, bytesRead, CP_UTF8);
            }
         }
      }
   }

   // 2. Fallback de Arquivo com Throttling (no máximo a cada 250ms)
   if(payload == "" && (GetTickCount64() - g_lastFileRead >= 250))
   {
      g_lastFileRead = GetTickCount64();
      int fileHandle = FileOpen("bookmap_stream.json", FILE_READ|FILE_BIN|FILE_SHARE_READ|FILE_SHARE_WRITE);
      if(fileHandle == INVALID_HANDLE)
         fileHandle = FileOpen("bookmap_stream.json", FILE_READ|FILE_BIN|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_COMMON);

      if(fileHandle != INVALID_HANDLE)
      {
         ulong sz = FileSize(fileHandle);
         if(sz > 0 && sz < 4096)
         {
            uchar buf[];
            ArrayResize(buf, (int)sz + 1);
            uint bytesRead = FileReadArray(fileHandle, buf, 0, (int)sz);
            if(bytesRead > 0)
            {
               buf[bytesRead] = 0;
               payload = CharArrayToString(buf, 0, (int)bytesRead, CP_UTF8);
            }
         }
         FileClose(fileHandle);
      }
   }

   if(payload != "")
   {
      ParseBookmapJson(payload);
   }
   else if(g_bmData.lastUpdateTime > 0 && (now - g_bmData.lastUpdateTime > 10))
   {
      g_bmData.isConnected = false;
   }
}

void DrawRayLevel(string name, datetime t1, double p1, datetime t2, double p2, color c, ENUM_LINE_STYLE st, int w, string tooltip)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);

   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_STYLE, st);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
}

void RenderBookmapLevels()
{
   if(!InpPlotBookmapLevels || !g_bookmapActive || !g_bmData.isConnected || g_smoothedBasis == 0.0)
   {
      ObjectDelete(0, G_PREFIX + "BM_VWAP");
      ObjectDelete(0, G_PREFIX + "BM_POC");
      ObjectDelete(0, G_PREFIX + "BM_VAH");
      ObjectDelete(0, G_PREFIX + "BM_VAL");
      ObjectDelete(0, G_PREFIX + "BM_HVN");
      ObjectDelete(0, G_PREFIX + "BM_BidWall");
      ObjectDelete(0, G_PREFIX + "BM_AskWall");
      g_lastRenderedVwap    = 0.0;
      g_lastRenderedPoc     = 0.0;
      g_lastRenderedVah     = 0.0;
      g_lastRenderedVal     = 0.0;
      g_lastRenderedHvn     = 0.0;
      g_lastRenderedBidWall = 0.0;
      g_lastRenderedAskWall = 0.0;
      return;
   }

   double mt5_vwap    = (g_bmData.vwap > 0.0) ? (g_bmData.vwap - g_smoothedBasis) : 0.0;
   double mt5_poc     = (g_bmData.poc > 0.0) ? (g_bmData.poc - g_smoothedBasis) : 0.0;
   double mt5_vah     = (g_bmData.vah > 0.0) ? (g_bmData.vah - g_smoothedBasis) : 0.0;
   double mt5_val     = (g_bmData.val > 0.0) ? (g_bmData.val - g_smoothedBasis) : 0.0;
   double mt5_hvn     = (g_bmData.hvn > 0.0) ? (g_bmData.hvn - g_smoothedBasis) : 0.0;
   double mt5_bidWall = (g_bmData.bidWallPrice > 0.0) ? (g_bmData.bidWallPrice - g_smoothedBasis) : 0.0;
   double mt5_askWall = (g_bmData.askWallPrice > 0.0) ? (g_bmData.askWallPrice - g_smoothedBasis) : 0.0;

   datetime now = TimeCurrent();
   bool levelsChanged = (MathAbs(mt5_vwap - g_lastRenderedVwap) > 0.01 ||
                         MathAbs(mt5_poc - g_lastRenderedPoc) > 0.01 ||
                         MathAbs(mt5_vah - g_lastRenderedVah) > 0.01 ||
                         MathAbs(mt5_val - g_lastRenderedVal) > 0.01 ||
                         MathAbs(mt5_hvn - g_lastRenderedHvn) > 0.01 ||
                         MathAbs(mt5_bidWall - g_lastRenderedBidWall) > 0.01 ||
                         MathAbs(mt5_askWall - g_lastRenderedAskWall) > 0.01);

   if(!levelsChanged && (now - g_lastRenderTime < 30)) return;

   g_lastRenderedVwap    = mt5_vwap;
   g_lastRenderedPoc     = mt5_poc;
   g_lastRenderedVah     = mt5_vah;
   g_lastRenderedVal     = mt5_val;
   g_lastRenderedHvn     = mt5_hvn;
   g_lastRenderedBidWall = mt5_bidWall;
   g_lastRenderedAskWall = mt5_askWall;
   g_lastRenderTime      = now;

   datetime t1 = iTime(_Symbol, _Period, MathMin(30, iBars(_Symbol, _Period) - 1));
   datetime t2 = now + PeriodSeconds(_Period) * 15;

   if(mt5_vwap > 0.0)
   {
      string vwapDesc = StringFormat("🟣 VWAP TOTAL BOOKMAP [COMEX %.2f - Basis %.2f = MT5 %.2f]", g_bmData.vwap, g_smoothedBasis, mt5_vwap);
      DrawRayLevel(G_PREFIX + "BM_VWAP", t1, mt5_vwap, t2, mt5_vwap, InpColorBookmapVWAP, STYLE_DASHDOT, 2, vwapDesc);
   }
   else ObjectDelete(0, G_PREFIX + "BM_VWAP");

   string pocDesc = StringFormat("★ POC BOOKMAP [COMEX %.2f - Basis %.2f = MT5 %.2f]", g_bmData.poc, g_smoothedBasis, mt5_poc);
   DrawRayLevel(G_PREFIX + "BM_POC", t1, mt5_poc, t2, mt5_poc, InpColorBookmapPOC, STYLE_SOLID, 2, pocDesc);

   if(mt5_vah > 0.0)
   {
      string vahDesc = StringFormat("🔺 VAH 70%% BOOKMAP [COMEX %.2f - Basis %.2f = MT5 %.2f]", g_bmData.vah, g_smoothedBasis, mt5_vah);
      DrawRayLevel(G_PREFIX + "BM_VAH", t1, mt5_vah, t2, mt5_vah, InpColorBookmapVAH, STYLE_DASH, 1, vahDesc);
   }
   else ObjectDelete(0, G_PREFIX + "BM_VAH");

   if(mt5_val > 0.0)
   {
      string valDesc = StringFormat("🔻 VAL 70%% BOOKMAP [COMEX %.2f - Basis %.2f = MT5 %.2f]", g_bmData.val, g_smoothedBasis, mt5_val);
      DrawRayLevel(G_PREFIX + "BM_VAL", t1, mt5_val, t2, mt5_val, InpColorBookmapVAL, STYLE_DASH, 1, valDesc);
   }
   else ObjectDelete(0, G_PREFIX + "BM_VAL");

   string hvnDesc = StringFormat("✦ HVN BOOKMAP [COMEX %.2f - Basis %.2f = MT5 %.2f]", g_bmData.hvn, g_smoothedBasis, mt5_hvn);
   DrawRayLevel(G_PREFIX + "BM_HVN", t1, mt5_hvn, t2, mt5_hvn, InpColorBookmapHVN, STYLE_DASH, 1, hvnDesc);
   DrawRayLevel(G_PREFIX + "BM_HVN", t1, mt5_hvn, t2, mt5_hvn, InpColorBookmapHVN, STYLE_DASH, 1, hvnDesc);

   if(g_bmData.bidWallVol >= InpMinWallVolume && mt5_bidWall > 0.0)
   {
      string bwDesc = StringFormat("🛡️ PAREDE COMPRA BOOKMAP [MT5 %.2f | %d Lotes]", mt5_bidWall, g_bmData.bidWallVol);
      DrawRayLevel(G_PREFIX + "BM_BidWall", t1, mt5_bidWall, t2, mt5_bidWall, InpColorBidWall, STYLE_SOLID, 2, bwDesc);
   }
   else ObjectDelete(0, G_PREFIX + "BM_BidWall");

   if(g_bmData.askWallVol >= InpMinWallVolume && mt5_askWall > 0.0)
   {
      string awDesc = StringFormat("🏰 PAREDE VENDA BOOKMAP [MT5 %.2f | %d Lotes]", mt5_askWall, g_bmData.askWallVol);
      DrawRayLevel(G_PREFIX + "BM_AskWall", t1, mt5_askWall, t2, mt5_askWall, InpColorAskWall, STYLE_SOLID, 2, awDesc);
   }
   else ObjectDelete(0, G_PREFIX + "BM_AskWall");
}

//+------------------------------------------------------------------+
//| NOVO GATILHO: ABSORÇÃO DE VWAP NO PAVIO COM DELTA (INDICADOR)    |
//+------------------------------------------------------------------+
void CheckVwapWickAbsorptionInd(datetime bTime, double bOpen, double bHigh, double bLow, double bClose, bool isLive)
{
   if(!InpUseBookmap || !g_bmData.isConnected || g_smoothedBasis == 0.0 || g_bmData.vwap <= 0.0 || !InpUseVwapWickSignal) return;
   if(!g_bookmapActive || !g_signalsActive) return;

   double mt5_vwap = g_bmData.vwap - g_smoothedBasis;
   double range = bHigh - bLow;
   if(range <= 0.0) return;

   double bodyTop    = MathMax(bOpen, bClose);
   double bodyBottom = MathMin(bOpen, bClose);
   double lowerWick  = bodyBottom - bLow;
   double upperWick  = bHigh - bodyTop;
   double pt         = _Point > 0.0 ? _Point : 0.0001;
   double tol        = 10.0 * pt;

   // 1. COMPRA: VWAP Total no pavio inferior + Forte Agressão Compradora
   if(lowerWick >= range * (InpMinWickPct / 100.0))
   {
      if(mt5_vwap >= (bLow - tol) && mt5_vwap <= (bodyBottom + tol))
      {
         if(g_bmData.delta >= InpMinAggressionDelta)
         {
            string sigId = StringFormat("%sVwapAbs_Buy_%d", G_PREFIX, (int)bTime);
            if(ObjectFind(0, sigId) < 0)
            {
               ObjectCreate(0, sigId, OBJ_ARROW_BUY, 0, bTime, bLow - (15 * pt));
               ObjectSetInteger(0, sigId, OBJPROP_COLOR, clrLimeGreen);
               ObjectSetInteger(0, sigId, OBJPROP_WIDTH, 3);
               ObjectSetString(0, sigId, OBJPROP_TOOLTIP, StringFormat("⚡ ABSORÇÃO COMPRADORA: VWAP no Pavio Inferior @ %.2f | Delta: %+d", mt5_vwap, g_bmData.delta));
            }

            g_lastSignalDirection = 1;
            g_lastSignalText      = StringFormat("⚡ COMPRA: Absorção VWAP no Pavio Inferior (Delta %+d)", g_bmData.delta);
            g_lastSignalColor     = clrLimeGreen;

            SetupNewTradePlan(1, bClose, bTime, bLow, false);

            if(isLive)
            {
               DispatchNotification(StringFormat("⚡ [BOOKMAP ABSORÇÃO] COMPRA CONFIRMADA: VWAP @ %.2f no Pavio Inferior + Forte Delta Comprador (%+d) no %s @ %.2f!",
                                    mt5_vwap, g_bmData.delta, _Symbol, bClose), InpSoundBOS, true);
            }
            return;
         }
      }
   }

   // 2. VENDA: VWAP Total no pavio superior + Forte Agressão Vendedora
   if(upperWick >= range * (InpMinWickPct / 100.0))
   {
      if(mt5_vwap >= (bodyTop - tol) && mt5_vwap <= (bHigh + tol))
      {
         if(g_bmData.delta <= -InpMinAggressionDelta)
         {
            string sigId = StringFormat("%sVwapAbs_Sell_%d", G_PREFIX, (int)bTime);
            if(ObjectFind(0, sigId) < 0)
            {
               ObjectCreate(0, sigId, OBJ_ARROW_SELL, 0, bTime, bHigh + (15 * pt));
               ObjectSetInteger(0, sigId, OBJPROP_COLOR, clrRed);
               ObjectSetInteger(0, sigId, OBJPROP_WIDTH, 3);
               ObjectSetString(0, sigId, OBJPROP_TOOLTIP, StringFormat("⚡ ABSORÇÃO VENDEDORA: VWAP no Pavio Superior @ %.2f | Delta: %+d", mt5_vwap, g_bmData.delta));
            }

            g_lastSignalDirection = -1;
            g_lastSignalText      = StringFormat("⚡ VENDA: Absorção VWAP no Pavio Superior (Delta %+d)", g_bmData.delta);
            g_lastSignalColor     = clrRed;

            SetupNewTradePlan(-1, bClose, bTime, bHigh, false);

            if(isLive)
            {
               DispatchNotification(StringFormat("⚡ [BOOKMAP ABSORÇÃO] VENDA CONFIRMADA: VWAP @ %.2f no Pavio Superior + Forte Delta Vendedor (%+d) no %s @ %.2f!",
                                    mt5_vwap, g_bmData.delta, _Symbol, bClose), InpSoundBOS, true);
            }
            return;
         }
      }
   }
}


//+------------------------------------------------------------------+
//| EVENTO DE TIMER (ATUALIZAÇÃO INSTANTÂNEA BOOKMAP & DASHBOARD)    |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdateBookmapData();
   RenderBookmapLevels();

   if(InpShowDashboard)
   {
      double curPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(curPrice > 0.0)
      {
         UpdateDashboardContent(curPrice);

         // Redraw Inteligente (Dirty Check): Só redesenha se houver alteração real
         datetime barTime = iTime(_Symbol, _Period, 0);
         int secRem = (int)((barTime + PeriodSeconds(_Period)) - TimeCurrent());
         ulong nowTick = GetTickCount64();

         bool priceChanged = MathAbs(curPrice - g_lastBidPrice) > (0.5 * _Point);
         bool secChanged   = (secRem != g_lastSecRem);
         bool deltaChanged = (g_bmData.delta != g_lastDelta);

         if(priceChanged || secChanged || deltaChanged || (nowTick - g_lastRedrawTick >= 1000))
         {
            g_lastBidPrice   = curPrice;
            g_lastSecRem     = secRem;
            g_lastDelta      = g_bmData.delta;
            g_lastRedrawTick = nowTick;
            ChartRedraw(0);
         }
      }
   }
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < InpHistoryLookback) return(0);

   ArraySetAsSeries(time, false);
   ArraySetAsSeries(open, false);
   ArraySetAsSeries(high, false);
   ArraySetAsSeries(low, false);
   ArraySetAsSeries(close, false);
   ArraySetAsSeries(tick_volume, false);

   int start = prev_calculated - 1;
   if(start < InpPivotLegs * 2 + 1)
   {
      start = InpPivotLegs * 2 + 1;
      ArrayInitialize(BufferBullBOS, 0.0);
      ArrayInitialize(BufferBearBOS, 0.0);
      ArrayInitialize(BufferScalpBull, 0.0);
      ArrayInitialize(BufferScalpBear, 0.0);
      ArrayResize(g_swings, 0);
      ArrayResize(g_structures, 0);
      g_structureCounter = 0;
   }

   // 1. Cópia dos Buffers de Filtros
   double emaArr[];
   ArraySetAsSeries(emaArr, false);
   if(InpUseEMATrendFilter && g_handleEMA != INVALID_HANDLE)
   {
      CopyBuffer(g_handleEMA, 0, 0, rates_total, emaArr);
   }

   double adxArr[];
   ArraySetAsSeries(adxArr, false);
   if(InpUseADXFilter && g_handleADX != INVALID_HANDLE)
   {
      CopyBuffer(g_handleADX, 0, 0, rates_total, adxArr);
   }

   datetime curServerTime = TimeCurrent();

   // 2. Processamento das Barras
   for(int i = start; i < rates_total - 1; i++)
   {
      BufferBullBOS[i]   = 0.0;
      BufferBearBOS[i]   = 0.0;
      BufferScalpBull[i] = 0.0;
      BufferScalpBear[i] = 0.0;

      // Proteção vital: Notificações sonoras/pop-up APENAS em tempo real ao vivo!
      bool isLive = (i >= rates_total - 2) && (time[i] >= curServerTime - PeriodSeconds(_Period) * 3);
      bool drawObjects = (i >= rates_total - InpHistoryLookback);

      // 2.1 Identificação de Pivôs
      int pIdx = i - InpPivotLegs;
      if(pIdx >= InpPivotLegs)
      {
         bool isHigh = true;
         for(int k = pIdx - InpPivotLegs; k <= pIdx + InpPivotLegs; k++)
         {
            if(k == pIdx) continue;
            if(high[k] >= high[pIdx]) { isHigh = false; break; }
         }
         if(isHigh && (high[pIdx] != g_currentSwingHigh || time[pIdx] != g_currentHighTime))
         {
            g_currentSwingHigh = high[pIdx];
            g_currentHighTime  = time[pIdx];
            AddSwing(1, high[pIdx], time[pIdx], pIdx);

            if(InpShowSwingPivots && drawObjects)
            {
               string pTag = G_PREFIX + "PivotH_" + TimeToString(time[pIdx]);
               DrawBadgeLabel(pTag, time[pIdx], high[pIdx], "▲ TOPO " + DoubleToString(high[pIdx], _Digits), clrSilver, ANCHOR_LOWER);
            }
         }

         bool isLow = true;
         for(int k = pIdx - InpPivotLegs; k <= pIdx + InpPivotLegs; k++)
         {
            if(k == pIdx) continue;
            if(low[k] <= low[pIdx]) { isLow = false; break; }
         }
         if(isLow && (low[pIdx] != g_currentSwingLow || time[pIdx] != g_currentLowTime))
         {
            g_currentSwingLow = low[pIdx];
            g_currentLowTime  = time[pIdx];
            AddSwing(-1, low[pIdx], time[pIdx], pIdx);

            if(InpShowSwingPivots && drawObjects)
            {
               string pTag = G_PREFIX + "PivotL_" + TimeToString(time[pIdx]);
               DrawBadgeLabel(pTag, time[pIdx], low[pIdx], "▼ FUNDO " + DoubleToString(low[pIdx], _Digits), clrSilver, ANCHOR_UPPER);
            }
         }
      }

      // 2.2 Rastreamento de Rompimento de Swings
      int swingCount = ArraySize(g_swings);
      for(int s = 0; s < swingCount; s++)
      {
         if(g_swings[s].broken) continue;
         if(time[i] <= g_swings[s].time) continue;

         if(g_swings[s].direction == 1) // Topo a Romper
         {
            bool isBreak = (InpConfirmMethod == IND_CONFIRM_ON_CLOSE) ? 
                           (close[i] > g_swings[s].price && close[i-1] <= g_swings[s].price) : 
                           (high[i] > g_swings[s].price && high[i-1] <= g_swings[s].price);

            if(isBreak)
            {
               g_swings[s].broken = true;
               if(!InpFilterVisuals || IsTrendAligned(1, i, emaArr, close))
               {
                  AddStructure(1, g_swings[s].price, g_swings[s].time, i, time[i], high[i], drawObjects);
               }
            }
         }
         else if(g_swings[s].direction == -1) // Fundo a Romper
         {
            bool isBreak = (InpConfirmMethod == IND_CONFIRM_ON_CLOSE) ? 
                           (close[i] < g_swings[s].price && close[i-1] >= g_swings[s].price) : 
                           (low[i] < g_swings[s].price && low[i-1] >= g_swings[s].price);

            if(isBreak)
            {
               g_swings[s].broken = true;
               if(!InpFilterVisuals || IsTrendAligned(-1, i, emaArr, close))
               {
                  AddStructure(-1, g_swings[s].price, g_swings[s].time, i, time[i], low[i], drawObjects);
               }
            }
         }
      }

      // 2.3 Atualização das Estruturas Ativas
      UpdateActiveStructures(i, time, open, high, low, close, emaArr, adxArr, isLive, drawObjects);

      // 2.4 Scalpers em Movimentos Intermediários
      if(InpEnableScalpers)
      {
         DetectIntermediateScalps(i, time, open, high, low, close, emaArr, adxArr, isLive, drawObjects);
      }

      // 5. GATILHO INSTITUCIONAL BOOKMAP: Absorção na VWAP com Agressão
      if(InpUseBookmap && InpUseVwapWickSignal)
      {
         CheckVwapWickAbsorptionInd(time[i], open[i], high[i], low[i], close[i], isLive);
      }
   }

   // 3. Monitoramento da Operação Ativa
   if(InpTrackActiveTrade && g_activeTrade.status == TRADE_RUNNING)
   {
      MonitorActiveTradeOutcome(rates_total, time, high, low, close);
   }

   // 4. Níveis Ativos Vigentes
   if(InpShowActiveLevels)
      RenderActiveLevels();

   // 5. Diagnóstico da Vela [0] ao Vivo
   DiagnoseLiveCandleAction(rates_total, time, open, high, low, close, tick_volume);

   // 6. Atualização do Dashboard
   if(InpShowDashboard)
   {
      double curPrice = close[rates_total - 1];
      UpdateDashboardContent(curPrice);
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| ATUALIZAÇÃO DO CICLO DE VIDA DAS ESTRUTURAS ATIVAS               |
//+------------------------------------------------------------------+
void UpdateActiveStructures(int i, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const double &emaArr[], const double &adxArr[], bool isLive, bool drawObjects)
{
   int stCount = ArraySize(g_structures);
   double tol = InpRetestTolerancePts * _Point;

   for(int s = 0; s < stCount; s++)
   {
      if(!g_structures[s].isActive) continue;

      if(InpDrawStructureLines && drawObjects)
         UpdateTrend(g_structures[s].lineName, time[i]);

      // ================= BULLISH STRUCTURE =================
      if(g_structures[s].direction == 1)
      {
         if(g_structures[s].state == IND_STATE_EXPANDING)
         {
            if(high[i] > g_structures[s].extremePrice)
            {
               g_structures[s].extremePrice = high[i];
               g_structures[s].extremeTime  = time[i];
            }

            int barsSince = i - g_structures[s].breakoutIndex;
            if(low[i] <= (g_structures[s].refLevel + tol))
            {
               if(barsSince < InpMinExpansionBars)
               {
                  g_structures[s].isActive = false;
                  if(InpShowBrokenLevels && drawObjects)
                  {
                     ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_COLOR, clrDimGray);
                     ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_STYLE, STYLE_DOT);
                     ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_WIDTH, 1);
                  }
                  else if(drawObjects) ObjectDelete(0, g_structures[s].lineName);
                  continue;
               }
               else
               {
                  g_structures[s].state = IND_STATE_EXPANSION_QUALIFIED;
               }
            }
            else if(barsSince >= InpMinExpansionBars)
            {
               g_structures[s].state = IND_STATE_EXPANSION_QUALIFIED;
            }

            if(barsSince > InpMaxStructureBars)
            {
               g_structures[s].isActive = false;
               if(InpShowBrokenLevels && drawObjects)
               {
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_COLOR, clrDimGray);
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_STYLE, STYLE_DOT);
               }
               else if(drawObjects) ObjectDelete(0, g_structures[s].lineName);
               continue;
            }
         }

         if(g_structures[s].state == IND_STATE_EXPANSION_QUALIFIED)
         {
            if(high[i] > g_structures[s].extremePrice)
            {
               g_structures[s].extremePrice = high[i];
               g_structures[s].extremeTime  = time[i];
            }

            int totalBars = i - g_structures[s].breakoutIndex;
            if(low[i] <= (g_structures[s].refLevel + tol))
            {
               double expansionHeight = g_structures[s].extremePrice - g_structures[s].refLevel;
               if(close[i] < (g_structures[s].refLevel - expansionHeight))
               {
                  g_structures[s].isActive = false;
                  if(InpShowBrokenLevels && drawObjects)
                  {
                     ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_COLOR, clrDimGray);
                     ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_STYLE, STYLE_DOT);
                  }
                  else if(drawObjects) ObjectDelete(0, g_structures[s].lineName);
                  continue;
               }

               g_structures[s].state           = IND_STATE_VALID_PULLBACK;
               g_structures[s].pullbackExtreme = low[i];
               g_structures[s].pullbackTime    = time[i];
               g_totalValidPullbacks++;

               if(InpDrawStructureLines && drawObjects)
               {
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_STYLE, STYLE_DOT);
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_COLOR, InpColorPullback);
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_WIDTH, 2);
               }

               if(InpShowLabels && drawObjects)
               {
                  g_structures[s].pbLabelName = G_PREFIX + "Bull_PB_" + IntegerToString(g_structures[s].id) + "_" + TimeToString(time[i]);
                  DrawBadgeLabel(g_structures[s].pbLabelName, time[i], low[i], "✦ VALID PULLBACK", InpColorPullback, ANCHOR_UPPER);
               }

               if(InpDrawZoneBoxes && drawObjects)
               {
                  g_structures[s].zoneBoxName = G_PREFIX + "Bull_Zone_" + IntegerToString(g_structures[s].id) + "_" + TimeToString(time[i]);
                  datetime tEnd = time[i] + PeriodSeconds(_Period) * 15;
                  DrawZoneBox(g_structures[s].zoneBoxName, g_structures[s].breakoutTime, tEnd, g_structures[s].refLevel, g_structures[s].pullbackExtreme, InpColorZoneBox, "ZONA DE LIQUIDEZ / PULLBACK");
               }

               // GATILHO 1: ENTRADA NA REJEIÇÃO DO RETESTE
               if(InpEntryTrigger == IND_ENTRY_PULLBACK_REJ && !g_structures[s].tradeTriggered)
               {
                  bool trendOk = IsTrendAligned(1, i, emaArr, close);
                  bool adxOk   = IsMarketTrending(i, adxArr);
                  bool rejOk   = (!InpRequireRejectionCandle) || HasBullishRejection(open[i], high[i], low[i], close[i]);

                  if(trendOk && adxOk && rejOk)
                  {
                     g_structures[s].tradeTriggered = true;
                     BufferBullBOS[i] = low[i] - 20 * _Point;
                     g_totalValidBOS++;
                     g_lastSignalText = "COMPRA: Rejeição no Reteste @ " + DoubleToString(close[i], _Digits);
                     g_lastSignalColor = InpColorBullish;

                     SetupNewTradePlan(1, close[i], time[i], low[i], false);
                     DispatchNotification("✦ COMPRA: Rejeição no Reteste de Alta no " + _Symbol + " @ " + DoubleToString(close[i], _Digits) + "!", InpSoundBOS, isLive);
                  }
               }
               else
               {
                  DispatchNotification("Valid Pullback de Alta Confirmado no " + _Symbol + "!", InpSoundBOS, isLive);
               }
            }
            else if(totalBars > InpMaxStructureBars)
            {
               g_structures[s].isActive = false;
               if(InpShowBrokenLevels && drawObjects)
               {
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_COLOR, clrDimGray);
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_STYLE, STYLE_DOT);
               }
               else if(drawObjects) ObjectDelete(0, g_structures[s].lineName);
               continue;
            }
         }
         else if(g_structures[s].state == IND_STATE_VALID_PULLBACK)
         {
            if(low[i] < g_structures[s].pullbackExtreme)
            {
               g_structures[s].pullbackExtreme = low[i];
               g_structures[s].pullbackTime    = time[i];
               if(InpDrawZoneBoxes && drawObjects && g_structures[s].zoneBoxName != "")
               {
                  ObjectSetDouble(0, g_structures[s].zoneBoxName, OBJPROP_PRICE, 1, g_structures[s].pullbackExtreme);
               }
            }

            int totalBars = i - g_structures[s].breakoutIndex;
            double expansionHeight = g_structures[s].extremePrice - g_structures[s].refLevel;

            if(totalBars > InpMaxStructureBars || close[i] < (g_structures[s].refLevel - expansionHeight * 0.5))
            {
               g_structures[s].isActive = false;
               if(InpShowBrokenLevels && drawObjects)
               {
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_COLOR, clrDimGray);
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_STYLE, STYLE_DOT);
               }
               else if(drawObjects) ObjectDelete(0, g_structures[s].lineName);
               continue;
            }

            // GATILHO 2: ENTRADA NO ROMPIMENTO DO TOPO (BOS CLÁSSICO)
            double minBreakoutPrice = g_structures[s].extremePrice + (InpMinBOSDisplacementPts * _Point);
            bool isBOS = (InpConfirmMethod == IND_CONFIRM_ON_CLOSE) ? 
                         (close[i] > minBreakoutPrice) : 
                         (high[i] > minBreakoutPrice);

            if(isBOS)
            {
               if(InpDrawStructureLines && drawObjects)
               {
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_STYLE, STYLE_SOLID);
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_COLOR, InpColorBullish);
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_WIDTH, 3);
               }

               if(InpShowLabels && drawObjects)
               {
                  g_structures[s].bosLabelName = G_PREFIX + "Bull_BOS_" + IntegerToString(g_structures[s].id) + "_" + TimeToString(time[i]);
                  DrawBadgeLabel(g_structures[s].bosLabelName, time[i], high[i], "★ VALID BOS (COMPRA)", InpColorBullish, ANCHOR_LOWER);
               }

               if(InpEntryTrigger == IND_ENTRY_VALID_BOS && !g_structures[s].tradeTriggered)
               {
                  bool trendOk = IsTrendAligned(1, i, emaArr, close);
                  bool adxOk   = IsMarketTrending(i, adxArr);

                  if(trendOk && adxOk)
                  {
                     g_structures[s].tradeTriggered = true;
                     BufferBullBOS[i] = low[i] - 20 * _Point;
                     g_totalValidBOS++;
                     g_lastSignalText = "COMPRA: Valid BOS em " + DoubleToString(close[i], _Digits);
                     g_lastSignalColor = InpColorBullish;

                     SetupNewTradePlan(1, close[i], time[i], g_structures[s].pullbackExtreme, false);
                     DispatchNotification("★ VALID BOS DE COMPRA CONFIRMADO no " + _Symbol + " @ " + DoubleToString(close[i], _Digits) + "!", InpSoundBOS, isLive);
                  }
               }

               g_structures[s].isActive = false;
            }
         }
      }

      // ================= BEARISH STRUCTURE =================
      else if(g_structures[s].direction == -1)
      {
         if(g_structures[s].state == IND_STATE_EXPANDING)
         {
            if(low[i] < g_structures[s].extremePrice)
            {
               g_structures[s].extremePrice = low[i];
               g_structures[s].extremeTime  = time[i];
            }

            int barsSince = i - g_structures[s].breakoutIndex;
            if(high[i] >= (g_structures[s].refLevel - tol))
            {
               if(barsSince < InpMinExpansionBars)
               {
                  g_structures[s].isActive = false;
                  if(InpShowBrokenLevels && drawObjects)
                  {
                     ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_COLOR, clrDimGray);
                     ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_STYLE, STYLE_DOT);
                     ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_WIDTH, 1);
                  }
                  else if(drawObjects) ObjectDelete(0, g_structures[s].lineName);
                  continue;
               }
               else
               {
                  g_structures[s].state = IND_STATE_EXPANSION_QUALIFIED;
               }
            }
            else if(barsSince >= InpMinExpansionBars)
            {
               g_structures[s].state = IND_STATE_EXPANSION_QUALIFIED;
            }

            if(barsSince > InpMaxStructureBars)
            {
               g_structures[s].isActive = false;
               if(InpShowBrokenLevels && drawObjects)
               {
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_COLOR, clrDimGray);
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_STYLE, STYLE_DOT);
               }
               else if(drawObjects) ObjectDelete(0, g_structures[s].lineName);
               continue;
            }
         }

         if(g_structures[s].state == IND_STATE_EXPANSION_QUALIFIED)
         {
            if(low[i] < g_structures[s].extremePrice)
            {
               g_structures[s].extremePrice = low[i];
               g_structures[s].extremeTime  = time[i];
            }

            int totalBars = i - g_structures[s].breakoutIndex;
            if(high[i] >= (g_structures[s].refLevel - tol))
            {
               double expansionHeight = g_structures[s].refLevel - g_structures[s].extremePrice;
               if(close[i] > (g_structures[s].refLevel + expansionHeight))
               {
                  g_structures[s].isActive = false;
                  if(InpShowBrokenLevels && drawObjects)
                  {
                     ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_COLOR, clrDimGray);
                     ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_STYLE, STYLE_DOT);
                  }
                  else if(drawObjects) ObjectDelete(0, g_structures[s].lineName);
                  continue;
               }

               g_structures[s].state           = IND_STATE_VALID_PULLBACK;
               g_structures[s].pullbackExtreme = high[i];
               g_structures[s].pullbackTime    = time[i];
               g_totalValidPullbacks++;

               if(InpDrawStructureLines && drawObjects)
               {
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_STYLE, STYLE_DOT);
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_COLOR, InpColorPullback);
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_WIDTH, 2);
               }

               if(InpShowLabels && drawObjects)
               {
                  g_structures[s].pbLabelName = G_PREFIX + "Bear_PB_" + IntegerToString(g_structures[s].id) + "_" + TimeToString(time[i]);
                  DrawBadgeLabel(g_structures[s].pbLabelName, time[i], high[i], "✦ VALID PULLBACK", InpColorPullback, ANCHOR_LOWER);
               }

               if(InpDrawZoneBoxes && drawObjects)
               {
                  g_structures[s].zoneBoxName = G_PREFIX + "Bear_Zone_" + IntegerToString(g_structures[s].id) + "_" + TimeToString(time[i]);
                  datetime tEnd = time[i] + PeriodSeconds(_Period) * 15;
                  DrawZoneBox(g_structures[s].zoneBoxName, g_structures[s].breakoutTime, tEnd, g_structures[s].refLevel, g_structures[s].pullbackExtreme, InpColorZoneBox, "ZONA DE LIQUIDEZ / PULLBACK");
               }

               // GATILHO 1: ENTRADA NA REJEIÇÃO DO RETESTE
               if(InpEntryTrigger == IND_ENTRY_PULLBACK_REJ && !g_structures[s].tradeTriggered)
               {
                  bool trendOk = IsTrendAligned(-1, i, emaArr, close);
                  bool adxOk   = IsMarketTrending(i, adxArr);
                  bool rejOk   = (!InpRequireRejectionCandle) || HasBearishRejection(open[i], high[i], low[i], close[i]);

                  if(trendOk && adxOk && rejOk)
                  {
                     g_structures[s].tradeTriggered = true;
                     BufferBearBOS[i] = high[i] + 20 * _Point;
                     g_totalValidBOS++;
                     g_lastSignalText = "VENDA: Rejeição no Reteste @ " + DoubleToString(close[i], _Digits);
                     g_lastSignalColor = InpColorBearish;

                     SetupNewTradePlan(-1, close[i], time[i], high[i], false);
                     DispatchNotification("✦ VENDA: Rejeição no Reteste de Baixa no " + _Symbol + " @ " + DoubleToString(close[i], _Digits) + "!", InpSoundBOS, isLive);
                  }
               }
               else
               {
                  DispatchNotification("Valid Pullback de Baixa Confirmado no " + _Symbol + "!", InpSoundBOS, isLive);
               }
            }
            else if(totalBars > InpMaxStructureBars)
            {
               g_structures[s].isActive = false;
               if(InpShowBrokenLevels && drawObjects)
               {
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_COLOR, clrDimGray);
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_STYLE, STYLE_DOT);
               }
               else if(drawObjects) ObjectDelete(0, g_structures[s].lineName);
               continue;
            }
         }
         else if(g_structures[s].state == IND_STATE_VALID_PULLBACK)
         {
            if(high[i] > g_structures[s].pullbackExtreme)
            {
               g_structures[s].pullbackExtreme = high[i];
               g_structures[s].pullbackTime    = time[i];
               if(InpDrawZoneBoxes && drawObjects && g_structures[s].zoneBoxName != "")
               {
                  ObjectSetDouble(0, g_structures[s].zoneBoxName, OBJPROP_PRICE, 1, g_structures[s].pullbackExtreme);
               }
            }

            int totalBars = i - g_structures[s].breakoutIndex;
            double expansionHeight = g_structures[s].refLevel - g_structures[s].extremePrice;

            if(totalBars > InpMaxStructureBars || close[i] > (g_structures[s].refLevel + expansionHeight * 0.5))
            {
               g_structures[s].isActive = false;
               if(InpShowBrokenLevels && drawObjects)
               {
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_COLOR, clrDimGray);
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_STYLE, STYLE_DOT);
               }
               else if(drawObjects) ObjectDelete(0, g_structures[s].lineName);
               continue;
            }

            // GATILHO 2: ENTRADA NO ROMPIMENTO DO FUNDO (BOS CLÁSSICO)
            double minBreakoutPrice = g_structures[s].extremePrice - (InpMinBOSDisplacementPts * _Point);
            bool isBOS = (InpConfirmMethod == IND_CONFIRM_ON_CLOSE) ? 
                         (close[i] < minBreakoutPrice) : 
                         (low[i] < minBreakoutPrice);

            if(isBOS)
            {
               if(InpDrawStructureLines && drawObjects)
               {
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_STYLE, STYLE_SOLID);
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_COLOR, InpColorBearish);
                  ObjectSetInteger(0, g_structures[s].lineName, OBJPROP_WIDTH, 3);
               }

               if(InpShowLabels && drawObjects)
               {
                  g_structures[s].bosLabelName = G_PREFIX + "Bear_BOS_" + IntegerToString(g_structures[s].id) + "_" + TimeToString(time[i]);
                  DrawBadgeLabel(g_structures[s].bosLabelName, time[i], low[i], "★ VALID BOS (VENDA)", InpColorBearish, ANCHOR_UPPER);
               }

               if(InpEntryTrigger == IND_ENTRY_VALID_BOS && !g_structures[s].tradeTriggered)
               {
                  bool trendOk = IsTrendAligned(-1, i, emaArr, close);
                  bool adxOk   = IsMarketTrending(i, adxArr);

                  if(trendOk && adxOk)
                  {
                     g_structures[s].tradeTriggered = true;
                     BufferBearBOS[i] = high[i] + 20 * _Point;
                     g_totalValidBOS++;
                     g_lastSignalText = "VENDA: Valid BOS em " + DoubleToString(close[i], _Digits);
                     g_lastSignalColor = InpColorBearish;

                     SetupNewTradePlan(-1, close[i], time[i], g_structures[s].pullbackExtreme, false);
                     DispatchNotification("★ VALID BOS DE VENDA CONFIRMADO no " + _Symbol + " @ " + DoubleToString(close[i], _Digits) + "!", InpSoundBOS, isLive);
                  }
               }

               g_structures[s].isActive = false;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| DETECÇÃO DE SCALPERS EM MOVIMENTOS INTERMEDIÁRIOS                |
//+------------------------------------------------------------------+
void DetectIntermediateScalps(int i, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const double &emaArr[], const double &adxArr[], bool isLive, bool drawObjects)
{
   if(i < InpScalpLookbackBars + 2) return;
   if(BufferBullBOS[i] > 0.0 || BufferBearBOS[i] > 0.0) return;

   // Cooldown obrigatório de pelo menos 3 barras entre scalpers
   if(time[i] - g_lastScalpTime < PeriodSeconds(_Period) * 3) return;

   double point = _Point > 0.0 ? _Point : 0.0001;

   // 1. SCALPER BUY (Micro-Pullback em Tendência de Alta)
   if(IsTrendAligned(1, i, emaArr, close) && IsMarketTrending(i, adxArr))
   {
      bool hadPullback = true;
      for(int k = 1; k <= InpScalpLookbackBars; k++)
      {
         if(close[i-k] >= open[i-k] && high[i-k] >= high[i-k-1]) { hadPullback = false; break; }
      }

      if(hadPullback && (low[i] > g_currentSwingLow || g_currentSwingLow == 0.0))
      {
         double range = high[i] - low[i];
         if(range > 0.0)
         {
            double lowerWick = MathMin(open[i], close[i]) - low[i];
            double wickPct = (lowerWick / range) * 100.0;

            // Rejeição compradora ou engolfo real fechando positivo
            if((close[i] > open[i] && wickPct >= InpScalpMinWickPct) || (close[i] > open[i] && close[i] > high[i-1]))
            {
               BufferScalpBull[i] = low[i] - 15 * point;
               g_totalScalps++;
               g_lastScalpTime = time[i];
               g_lastSignalText = "⚡ SCALP BUY @ " + DoubleToString(close[i], _Digits);
               g_lastSignalColor = InpColorScalpBull;

               if(InpShowLabels && drawObjects)
               {
                  string sTag = G_PREFIX + "Scalp_Bull_" + TimeToString(time[i]);
                  DrawBadgeLabel(sTag, time[i], low[i], "⚡ SCALP BUY", InpColorScalpBull, ANCHOR_UPPER);
               }

               SetupNewTradePlan(1, close[i], time[i], low[i], true);
               DispatchNotification("⚡ SINAL SCALPER DE COMPRA no " + _Symbol + " @ " + DoubleToString(close[i], _Digits) + "!", InpSoundScalp, isLive);
            }
         }
      }
   }

   // 2. SCALPER SELL (Micro-Pullback em Tendência de Baixa)
   if(IsTrendAligned(-1, i, emaArr, close) && IsMarketTrending(i, adxArr))
   {
      bool hadPullback = true;
      for(int k = 1; k <= InpScalpLookbackBars; k++)
      {
         if(close[i-k] <= open[i-k] && low[i-k] <= low[i-k-1]) { hadPullback = false; break; }
      }

      if(hadPullback && (high[i] < g_currentSwingHigh || g_currentSwingHigh == 0.0))
      {
         double range = high[i] - low[i];
         if(range > 0.0)
         {
            double upperWick = high[i] - MathMax(open[i], close[i]);
            double wickPct = (upperWick / range) * 100.0;

            // Rejeição vendedora ou engolfo real fechando negativo
            if((close[i] < open[i] && wickPct >= InpScalpMinWickPct) || (close[i] < open[i] && close[i] < low[i-1]))
            {
               BufferScalpBear[i] = high[i] + 15 * point;
               g_totalScalps++;
               g_lastScalpTime = time[i];
               g_lastSignalText = "⚡ SCALP SELL @ " + DoubleToString(close[i], _Digits);
               g_lastSignalColor = InpColorScalpBear;

               if(InpShowLabels && drawObjects)
               {
                  string sTag = G_PREFIX + "Scalp_Bear_" + TimeToString(time[i]);
                  DrawBadgeLabel(sTag, time[i], high[i], "⚡ SCALP SELL", InpColorScalpBear, ANCHOR_LOWER);
               }

               SetupNewTradePlan(-1, close[i], time[i], high[i], true);
               DispatchNotification("⚡ SINAL SCALPER DE VENDA no " + _Symbol + " @ " + DoubleToString(close[i], _Digits) + "!", InpSoundScalp, isLive);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CRIAÇÃO E GESTÃO DO PLANO DE TRADE PROJETADO                     |
//+------------------------------------------------------------------+
void SetupNewTradePlan(int dir, double entryP, datetime entryT, double refStopP, bool isScalp)
{
   if(!InpShowProjectedBoxes && !InpTrackActiveTrade) return;

   CleanObjects(G_PREFIX + "Trade_");

   double point = _Point > 0.0 ? _Point : 0.0001;
   double buffer = InpSLBufferPoints * point;
   double slPrice = 0.0;
   double riskPts = 0.0;

   if(dir == 1)
   {
      slPrice = refStopP - buffer;
      riskPts = (entryP - slPrice) / point;
      if(riskPts < 50.0) { riskPts = 50.0; slPrice = entryP - (riskPts * point); }
   }
   else
   {
      slPrice = refStopP + buffer;
      riskPts = (slPrice - entryP) / point;
      if(riskPts < 50.0) { riskPts = 50.0; slPrice = entryP + (riskPts * point); }
   }

   double rr = isScalp ? InpScalpRiskReward : InpRiskRewardRatio;
   double rewardPts = riskPts * rr;
   double tpPrice = (dir == 1) ? (entryP + rewardPts * point) : (entryP - rewardPts * point);

   g_activeTrade.status       = TRADE_RUNNING;
   g_activeTrade.direction    = dir;
   g_activeTrade.isScalp      = isScalp;
   g_activeTrade.entryPrice   = entryP;
   g_activeTrade.entryTime    = entryT;
   g_activeTrade.slPrice      = slPrice;
   g_activeTrade.tpPrice      = tpPrice;
   g_activeTrade.riskPoints   = riskPts;
   g_activeTrade.rewardPoints = rewardPts;

      g_lastSignalDirection = dir;
   g_lastSignalEntry     = entryP;
   g_lastSignalSL        = slPrice;
   g_lastSignalTP1       = (dir == 1) ? (entryP + InpScalpTakeProfitPts * point) : (entryP - InpScalpTakeProfitPts * point);
   g_lastSignalTP2       = tpPrice;

   datetime tEnd = entryT + PeriodSeconds(_Period) * 30;

   if(InpShowProjectedBoxes)
   {
      g_activeTrade.entryLineName = G_PREFIX + "Trade_Entry";
      DrawTargetLine(g_activeTrade.entryLineName, entryT, tEnd, entryP, clrWhite, "ENTRADA PROJETADA");

      g_activeTrade.slLineName = G_PREFIX + "Trade_SL";
      DrawTargetLine(g_activeTrade.slLineName, entryT, tEnd, slPrice, clrCrimson, "STOP LOSS (" + DoubleToString(riskPts, 0) + " pts)");

      g_activeTrade.tpLineName = G_PREFIX + "Trade_TP";
      DrawTargetLine(g_activeTrade.tpLineName, entryT, tEnd, tpPrice, clrLimeGreen, "TAKE PROFIT (" + DoubleToString(rewardPts, 0) + " pts | R:R 1:" + DoubleToString(rr, 1) + ")");

      g_activeTrade.boxName = G_PREFIX + "Trade_Box";
      color boxClr = (dir == 1) ? C'15,35,25' : C'35,15,20';
      DrawZoneBox(g_activeTrade.boxName, entryT, tEnd, entryP, tpPrice, boxClr, "PROJEÇÃO DE ALVO DO TRADE");
   }
}

//+------------------------------------------------------------------+
//| MONITORAMENTO DE RESULTADO DA OPERAÇÃO                           |
//+------------------------------------------------------------------+
void MonitorActiveTradeOutcome(int rates_total, const datetime &time[], const double &high[], const double &low[], const double &close[])
{
   int cIdx = rates_total - 1;
   datetime curT = time[cIdx];
   double curHigh = high[cIdx];
   double curLow  = low[cIdx];

   if(InpShowProjectedBoxes)
   {
      datetime newEnd = curT + PeriodSeconds(_Period) * 10;
      if(ObjectFind(0, g_activeTrade.entryLineName) >= 0) ObjectSetInteger(0, g_activeTrade.entryLineName, OBJPROP_TIME, 1, newEnd);
      if(ObjectFind(0, g_activeTrade.slLineName) >= 0)    ObjectSetInteger(0, g_activeTrade.slLineName, OBJPROP_TIME, 1, newEnd);
      if(ObjectFind(0, g_activeTrade.tpLineName) >= 0)    ObjectSetInteger(0, g_activeTrade.tpLineName, OBJPROP_TIME, 1, newEnd);
      if(ObjectFind(0, g_activeTrade.boxName) >= 0)       ObjectSetInteger(0, g_activeTrade.boxName, OBJPROP_TIME, 1, newEnd);
   }

   // 1. Simulação de Break-Even ao atingir 1R
   if(InpUseBreakEvenSim)
   {
      double point = _Point > 0.0 ? _Point : 0.0001;
      if(g_activeTrade.direction == 1)
      {
         if(curHigh >= (g_activeTrade.entryPrice + g_activeTrade.riskPoints * point))
         {
            g_activeTrade.slPrice = g_activeTrade.entryPrice + 10 * point;
            if(InpShowProjectedBoxes && ObjectFind(0, g_activeTrade.slLineName) >= 0)
            {
               ObjectSetDouble(0, g_activeTrade.slLineName, OBJPROP_PRICE, 0, g_activeTrade.slPrice);
               ObjectSetDouble(0, g_activeTrade.slLineName, OBJPROP_PRICE, 1, g_activeTrade.slPrice);
               ObjectSetString(0, g_activeTrade.slLineName + "_Txt", OBJPROP_TEXT, "  ◀ STOP NO BREAK-EVEN (0x0)");
            }
         }
      }
      else if(g_activeTrade.direction == -1)
      {
         if(curLow <= (g_activeTrade.entryPrice - g_activeTrade.riskPoints * point))
         {
            g_activeTrade.slPrice = g_activeTrade.entryPrice - 10 * point;
            if(InpShowProjectedBoxes && ObjectFind(0, g_activeTrade.slLineName) >= 0)
            {
               ObjectSetDouble(0, g_activeTrade.slLineName, OBJPROP_PRICE, 0, g_activeTrade.slPrice);
               ObjectSetDouble(0, g_activeTrade.slLineName, OBJPROP_PRICE, 1, g_activeTrade.slPrice);
               ObjectSetString(0, g_activeTrade.slLineName + "_Txt", OBJPROP_TEXT, "  ◀ STOP NO BREAK-EVEN (0x0)");
            }
         }
      }
   }

   // 2. Verificação de Take Profit
   bool hitTP = (g_activeTrade.direction == 1) ? (curHigh >= g_activeTrade.tpPrice) : (curLow <= g_activeTrade.tpPrice);
   if(hitTP)
   {
      g_activeTrade.status = TRADE_HIT_TP;
      g_totalTradesWon++;
      g_lastSignalText = "✓ TAKE PROFIT ATINGIDO! (+" + DoubleToString(g_activeTrade.rewardPoints, 0) + " pts)";
      g_lastSignalColor = clrLimeGreen;

      string outLabel = G_PREFIX + "Outcome_TP_" + TimeToString(curT);
      DrawBadgeLabel(outLabel, curT, g_activeTrade.tpPrice, "✓ TAKE PROFIT (+ " + DoubleToString(g_activeTrade.rewardPoints, 0) + " pts)", clrLimeGreen, g_activeTrade.direction == 1 ? ANCHOR_LOWER : ANCHOR_UPPER);

      DispatchNotification("✓ TAKE PROFIT ATINGIDO no " + _Symbol + "! +" + DoubleToString(g_activeTrade.rewardPoints, 0) + " pontos de lucro!", InpSoundTP, true);
      return;
   }

   // 3. Verificação de Stop Loss
   bool hitSL = (g_activeTrade.direction == 1) ? (curLow <= g_activeTrade.slPrice) : (curHigh >= g_activeTrade.slPrice);
   if(hitSL)
   {
      g_activeTrade.status = TRADE_HIT_SL;
      g_totalTradesLost++;
      g_lastSignalText = "✗ STOP LOSS ACIONADO (-" + DoubleToString(g_activeTrade.riskPoints, 0) + " pts)";
      g_lastSignalColor = clrCrimson;

      string outLabel = G_PREFIX + "Outcome_SL_" + TimeToString(curT);
      DrawBadgeLabel(outLabel, curT, g_activeTrade.slPrice, "✗ STOP LOSS (- " + DoubleToString(g_activeTrade.riskPoints, 0) + " pts)", clrCrimson, g_activeTrade.direction == 1 ? ANCHOR_UPPER : ANCHOR_LOWER);

      DispatchNotification("✗ STOP LOSS ACIONADO no " + _Symbol + "! Operação encerrada para proteção de capital.", InpSoundSL, true);
      return;
   }
}

//+------------------------------------------------------------------+
//| DIAGNÓSTICO EM TEMPO REAL DA MICROESTRUTURA DO CANDLE AO VIVO    |
//+------------------------------------------------------------------+
void DiagnoseLiveCandleAction(int rates_total, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tick_volume[])
{
   int cIdx = rates_total - 1;
   double cOpen  = open[cIdx];
   double cHigh  = high[cIdx];
   double cLow   = low[cIdx];
   double cClose = close[cIdx];

   double range = cHigh - cLow;
   if(range <= 0.0) range = _Point;

   double body = MathAbs(cClose - cOpen);
   double upperWick = cHigh - MathMax(cOpen, cClose);
   double lowerWick = MathMin(cOpen, cClose) - cLow;

   double pctBody  = (body / range) * 100.0;
   double pctUpper = (upperWick / range) * 100.0;
   double pctLower = (lowerWick / range) * 100.0;

   if(InpUseBookmap && g_bmData.isConnected && g_bmData.vwap > 0.0 && g_smoothedBasis != 0.0)
   {
      double mt5_vwap = g_bmData.vwap - g_smoothedBasis;
      double bTop = MathMax(cOpen, cClose);
      double bBot = MathMin(cOpen, cClose);
      double tol  = 10.0 * _Point;

      if(mt5_vwap >= (cLow - tol) && mt5_vwap <= (bBot + tol) && pctLower >= InpMinWickPct)
      {
         g_candleActionText  = StringFormat("⚡ ABSORÇÃO VWAP NO PAVIO INFERIOR (Pavio %.0f%% | Delta %+d)", pctLower, g_bmData.delta);
         g_candleActionColor = (g_bmData.delta >= InpMinAggressionDelta) ? clrLimeGreen : clrGold;
      }
      else if(mt5_vwap >= (bTop - tol) && mt5_vwap <= (cHigh + tol) && pctUpper >= InpMinWickPct)
      {
         g_candleActionText  = StringFormat("⚡ ABSORÇÃO VWAP NO PAVIO SUPERIOR (Pavio %.0f%% | Delta %+d)", pctUpper, g_bmData.delta);
         g_candleActionColor = (g_bmData.delta <= -InpMinAggressionDelta) ? clrCrimson : clrGold;
      }
      else if(pctLower >= 45.0)
      {
         g_candleActionText  = "🔥 ABSORÇÃO COMPRADORA (Pavio " + DoubleToString(pctLower, 0) + "%)";
         g_candleActionColor = clrLimeGreen;
      }
      else if(pctUpper >= 45.0)
      {
         g_candleActionText  = "🔻 ABSORÇÃO VENDEDORA (Pavio " + DoubleToString(pctUpper, 0) + "%)";
         g_candleActionColor = clrCrimson;
      }
      else if(pctBody >= 68.0 && cClose > cOpen)
      {
         g_candleActionText  = "🚀 IMPULSO COMPRADOR (Corpo " + DoubleToString(pctBody, 0) + "%)";
         g_candleActionColor = clrLime;
      }
      else if(pctBody >= 68.0 && cClose < cOpen)
      {
         g_candleActionText  = "💥 IMPULSO VENDEDOR (Corpo " + DoubleToString(pctBody, 0) + "%)";
         g_candleActionColor = clrRed;
      }
      else
      {
         g_candleActionText  = "⚖ EQUILÍBRIO / MICRO-LATERAL (Corpo " + DoubleToString(pctBody, 0) + "%)";
         g_candleActionColor = clrSilver;
      }
   }
   else if(pctLower >= 45.0)
   {
      g_candleActionText  = "🔥 ABSORÇÃO COMPRADORA (Pavio " + DoubleToString(pctLower, 0) + "%)";
      g_candleActionColor = clrLimeGreen;
   }
   else if(pctUpper >= 45.0)
   {
      g_candleActionText  = "🔻 ABSORÇÃO VENDEDORA (Pavio " + DoubleToString(pctUpper, 0) + "%)";
      g_candleActionColor = clrCrimson;
   }
   else if(pctBody >= 68.0 && cClose > cOpen)
   {
      g_candleActionText  = "🚀 IMPULSO COMPRADOR (Corpo " + DoubleToString(pctBody, 0) + "%)";
      g_candleActionColor = clrLime;
   }
   else if(pctBody >= 68.0 && cClose < cOpen)
   {
      g_candleActionText  = "💥 IMPULSO VENDEDOR (Corpo " + DoubleToString(pctBody, 0) + "%)";
      g_candleActionColor = clrRed;
   }
   else
   {
      g_candleActionText  = "⚖ EQUILÍBRIO / MICRO-LATERAL (Corpo " + DoubleToString(pctBody, 0) + "%)";
      g_candleActionColor = clrSilver;
   }

   g_candleContextDiag = (cClose >= cOpen ? "Compradores no Controle" : "Vendedores no Controle");

   if(InpShowLiveCandleTag)
   {
      string liveTag = G_PREFIX + "Live_Candle_Tag";
      datetime tCur = time[cIdx];
      int secRem = (int)((tCur + PeriodSeconds(_Period)) - TimeCurrent());
      if(secRem < 0) secRem = 0;
      string timeStr = StringFormat("%02d:%02d", secRem / 60, secRem % 60);

      string fullTag = "  ◀ " + g_candleActionText + " [" + timeStr + "]";
      DrawFloatingTag(liveTag, tCur, cClose, fullTag, g_candleActionColor);
   }
}

//+------------------------------------------------------------------+
//| RENDERIZAÇÃO DOS NÍVEIS ATIVOS VIGENTES                          |
//+------------------------------------------------------------------+
void RenderActiveLevels()
{
   datetime t1 = iTime(_Symbol, _Period, MathMin(35, iBars(_Symbol, _Period) - 1));
   datetime t2 = iTime(_Symbol, _Period, 0);

   if(g_currentSwingHigh > 0.0)
   {
      string hName = G_PREFIX + "Active_Res";
      DrawHLine(hName, t1, t2, g_currentSwingHigh, InpColorLevels, STYLE_SOLID, 2, "RESISTÊNCIA VIGENTE (Topo a Romper)");
   }
   if(g_currentSwingLow > 0.0)
   {
      string lName = G_PREFIX + "Active_Sup";
      DrawHLine(lName, t1, t2, g_currentSwingLow, InpColorLevels, STYLE_SOLID, 2, "SUPORTE VIGENTE (Fundo a Romper)");
   }
}

//+------------------------------------------------------------------+
//| CRIAÇÃO DO PAINEL ARRASTÁVEL E MINIMIZÁVEL                       |
//+------------------------------------------------------------------+
void CreateInteractiveDashboard()
{
   CalculateDashboardDimensions();

   string bgName = G_PREFIX + "Dash_BG";
   ObjectDelete(0, bgName);
   ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, g_panelX);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, g_panelY);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, g_panelWidth);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, g_panelMinimized ? g_panelHeightMin : g_panelHeightFull);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, InpPanelBgColor);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_COLOR, InpPanelBorderColor);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);

   string hdName = G_PREFIX + "Dash_Header";
   ObjectDelete(0, hdName);
   ObjectCreate(0, hdName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, hdName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, hdName, OBJPROP_XDISTANCE, g_panelX);
   ObjectSetInteger(0, hdName, OBJPROP_YDISTANCE, g_panelY);
   ObjectSetInteger(0, hdName, OBJPROP_XSIZE, g_panelWidth);
   ObjectSetInteger(0, hdName, OBJPROP_YSIZE, g_headerH);
   ObjectSetInteger(0, hdName, OBJPROP_BGCOLOR, InpPanelHeaderColor);
   ObjectSetInteger(0, hdName, OBJPROP_BORDER_COLOR, InpPanelBorderColor);
   ObjectSetInteger(0, hdName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, hdName, OBJPROP_SELECTABLE, false);

   CreateDashLabel(G_PREFIX + "Lbl_Title", "★ VALID BOS INDICADOR PRO | @viniciusburgo", 12, (g_headerH - g_fontSize - 4) / 2, clrGold, g_fontSize, true);

   int btnH = (int)MathRound(20.0 * ((double)g_fontSize / 8.0));
   int btnY = (g_headerH - btnH) / 2;

   int wSig = 100;
   int wBM  = 80;
   int wMin = 22;
   int wRes = 22;

   int curX = g_panelWidth - 6;

   curX -= wRes;
   CreateDashButton(G_PREFIX + "Btn_Reset", "R", curX, btnY, wRes, btnH, C'50,30,40', clrLightCoral, g_fontSize);

   curX -= (wMin + 4);
   CreateDashButton(G_PREFIX + "Btn_Min", g_panelMinimized ? "+" : "—", curX, btnY, wMin, btnH, C'35,48,72', clrWhite, g_fontSize);

   curX -= (wBM + 4);
   CreateDashButton(G_PREFIX + "Btn_ToggleBM", g_bookmapActive ? "⚡ BM: ON" : "⚡ BM: OFF", curX, btnY, wBM, btnH, g_bookmapActive ? C'25,50,75' : C'50,50,50', g_bookmapActive ? clrAqua : clrSilver, g_fontSize - 1);

   curX -= (wSig + 4);
   CreateDashButton(G_PREFIX + "Btn_ToggleSignals", g_signalsActive ? "🟢 SINAIS: ON" : "🔴 SINAIS: OFF", curX, btnY, wSig, btnH, g_signalsActive ? C'20,60,35' : C'70,25,25', clrWhite, g_fontSize - 1);

   CreateDashLabel(G_PREFIX + "Txt_Timer",       "⏱ Candle: --:-- | Spread: -- pts | Corretora VT Markets", 12, GetLineRelY(0), clrAqua, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_Action",      "🎯 AÇÃO IMEDIATA: [ ⚪ MONITORANDO FLUXO ]", 12, GetLineRelY(1), clrGold, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_EntrySL",     "📍 ENTRADA EXATA: --- | 🛑 STOP LOSS: ---", 12, GetLineRelY(2), clrWhite, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_TPTargets",   "🎯 ALVOS: TP1 (Scalp 50%) --- | 🚀 TP2 (Runner 50%) ---", 12, GetLineRelY(3), clrDeepSkyBlue, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_RiskRule",    "🛡️ GESTÃO: Ao atingir TP1 ➔ Stop do Runner vai pro Zero a Zero (0x0)!", 12, GetLineRelY(4), clrYellowGreen, g_fontSize - 1, false);
   CreateDashLabel(G_PREFIX + "Txt_ResSup",      "Resistência Topo: --- | Suporte Fundo: ---", 12, GetLineRelY(5), clrOrange, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_BMComp",      "⚡ BOOKMAP COMEX GC: --- | 🏦 VT MARKETS SPOT: ---", 12, GetLineRelY(6), clrAqua, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_BMBasis",     "⚖ DIFERENÇA (BASIS): --- ➔ Níveis projetados nas velas MT5", 12, GetLineRelY(7), clrGold, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_BMDelta",     "📊 DELTA COMEX: --- | CVD: ---", 12, GetLineRelY(8), clrSilver, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_BMNodes",     "🟣 VWAP: --- | ★ POC: --- | 🔺 VAH: --- | 🔻 VAL: ---", 12, GetLineRelY(9), clrGold, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_BMVPVR",      "📊 VPVR: Range [--- ⟷ ---] | Status: Aguardando...", 12, GetLineRelY(10), clrAqua, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_BMWalls",     "🏰 PAREDE VENDA: --- | 🛡️ PAREDE COMPRA: ---", 12, GetLineRelY(11), clrSilver, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_LiveCandle",  "Vela [0]: Monitorando microestrutura...", 12, GetLineRelY(12), clrWhite, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_Diag",        "Contexto Técnico: Analisando EMA / ADX...", 12, GetLineRelY(13), clrSilver, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_BotStatus",   "STATUS OPERACIONAL: 🟢 SINAIS ATIVOS E MONITORANDO", 12, GetLineRelY(14), clrLimeGreen, g_fontSize, true);

   UpdateDashboardVisibility();
}

void RepositionDashboard()
{
   ObjectSetInteger(0, G_PREFIX + "Dash_BG", OBJPROP_XDISTANCE, g_panelX);
   ObjectSetInteger(0, G_PREFIX + "Dash_BG", OBJPROP_YDISTANCE, g_panelY);
   ObjectSetInteger(0, G_PREFIX + "Dash_Header", OBJPROP_XDISTANCE, g_panelX);
   ObjectSetInteger(0, G_PREFIX + "Dash_Header", OBJPROP_YDISTANCE, g_panelY);

   int btnH = (int)MathRound(20.0 * ((double)g_fontSize / 8.0));
   int btnY = (g_headerH - btnH) / 2;

   int wSig = 100;
   int wBM  = 80;
   int wMin = 22;
   int wRes = 22;

   ObjectSetInteger(0, G_PREFIX + "Lbl_Title", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Lbl_Title", OBJPROP_YDISTANCE, g_panelY + (g_headerH - g_fontSize - 4) / 2);

   int curX = g_panelWidth - 6;

   curX -= wRes;
   ObjectSetInteger(0, G_PREFIX + "Btn_Reset", OBJPROP_XDISTANCE, g_panelX + curX);
   ObjectSetInteger(0, G_PREFIX + "Btn_Reset", OBJPROP_YDISTANCE, g_panelY + btnY);

   curX -= (wMin + 4);
   ObjectSetInteger(0, G_PREFIX + "Btn_Min", OBJPROP_XDISTANCE, g_panelX + curX);
   ObjectSetInteger(0, G_PREFIX + "Btn_Min", OBJPROP_YDISTANCE, g_panelY + btnY);

   curX -= (wBM + 4);
   ObjectSetInteger(0, G_PREFIX + "Btn_ToggleBM", OBJPROP_XDISTANCE, g_panelX + curX);
   ObjectSetInteger(0, G_PREFIX + "Btn_ToggleBM", OBJPROP_YDISTANCE, g_panelY + btnY);

   curX -= (wSig + 4);
   ObjectSetInteger(0, G_PREFIX + "Btn_ToggleSignals", OBJPROP_XDISTANCE, g_panelX + curX);
   ObjectSetInteger(0, G_PREFIX + "Btn_ToggleSignals", OBJPROP_YDISTANCE, g_panelY + btnY);

   ObjectSetInteger(0, G_PREFIX + "Txt_Timer", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_Timer", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(0));

   ObjectSetInteger(0, G_PREFIX + "Txt_Action", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_Action", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(1));

   ObjectSetInteger(0, G_PREFIX + "Txt_EntrySL", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_EntrySL", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(2));

   ObjectSetInteger(0, G_PREFIX + "Txt_TPTargets", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_TPTargets", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(3));

   ObjectSetInteger(0, G_PREFIX + "Txt_RiskRule", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_RiskRule", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(4));

   ObjectSetInteger(0, G_PREFIX + "Txt_ResSup", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_ResSup", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(5));

   ObjectSetInteger(0, G_PREFIX + "Txt_BMComp", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMComp", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(6));

   ObjectSetInteger(0, G_PREFIX + "Txt_BMBasis", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMBasis", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(7));

   ObjectSetInteger(0, G_PREFIX + "Txt_BMDelta", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMDelta", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(8));

   ObjectSetInteger(0, G_PREFIX + "Txt_BMNodes", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMNodes", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(9));

   ObjectSetInteger(0, G_PREFIX + "Txt_BMVPVR", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMVPVR", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(10));

   ObjectSetInteger(0, G_PREFIX + "Txt_BMWalls", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMWalls", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(11));

   ObjectSetInteger(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(12));

   ObjectSetInteger(0, G_PREFIX + "Txt_Diag", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_Diag", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(13));

   ObjectSetInteger(0, G_PREFIX + "Txt_BotStatus", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BotStatus", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(14));
}

void UpdateDashboardVisibility()
{
   long hiddenFlag = g_panelMinimized ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS;

   ObjectSetInteger(0, G_PREFIX + "Txt_Timer", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_Action", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_EntrySL", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_TPTargets", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_RiskRule", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_ResSup", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMComp", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMBasis", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMDelta", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMNodes", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMVPVR", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMWalls", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_Diag", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BotStatus", OBJPROP_TIMEFRAMES, hiddenFlag);
}

void UpdateDashboardContent(double curPrice)
{
   if(g_panelMinimized) return;

   double pt = _Point > 0.0 ? _Point : 0.0001;

   datetime barTime = iTime(_Symbol, _Period, 0);
   int secRem = (int)((barTime + PeriodSeconds(_Period)) - TimeCurrent());
   if(secRem < 0) secRem = 0;
   int mins = secRem / 60;
   int secs = secRem % 60;
   string timerStr = StringFormat("⏱ Candle: %02d:%02d | Spread: %d pts | Corretora: VT Markets", mins, secs, (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
   ObjectSetString(0, G_PREFIX + "Txt_Timer", OBJPROP_TEXT, timerStr);

   string actionTxt = "";
   color actionClr = clrGold;
   string entrySLTxt = "";
   string tpTargetsTxt = "";

   if(g_activeTrade.status == TRADE_RUNNING)
   {
      string posDir = (g_activeTrade.direction == 1) ? "COMPRA" : "VENDA";
      actionTxt = StringFormat("🎯 OPERAÇÃO EM CURSO: [ %s @ %.2f ]", posDir, g_activeTrade.entryPrice);
      actionClr = (g_activeTrade.direction == 1) ? clrLimeGreen : clrRed;

      double slDistPts = MathAbs(curPrice - g_activeTrade.slPrice) / pt;
      entrySLTxt = StringFormat("📍 ENTRADA: %.2f | 🛑 STOP LOSS: %.2f [%.0f pts] (Protegendo Capital)", g_activeTrade.entryPrice, g_activeTrade.slPrice, slDistPts);

      double tpDistPts = MathAbs(g_activeTrade.tpPrice - curPrice) / pt;
      tpTargetsTxt = StringFormat("🎯 TAKE PROFIT ATIVO: %.2f [%.0f pts restantes para o Alvo]", g_activeTrade.tpPrice, tpDistPts);
   }
   else
   {
      if(g_lastSignalDirection == 1)
      {
         actionTxt = "🎯 SINAL RECOMENDADO: [ 🟢 FORTE COMPRA NO PULLBACK / VWAP ]";
         actionClr = clrLimeGreen;
         double estSL = (g_lastSignalSL > 0.0) ? g_lastSignalSL : (g_currentSwingLow > 0.0 ? (g_currentSwingLow - InpSLBufferPoints * pt) : (curPrice - InpMinSLPoints * pt));
         double slPts = MathAbs(curPrice - estSL) / pt;
         entrySLTxt = StringFormat("📍 ENTRADA: %.2f | 🛑 STOP LOSS: %.2f [%.0f pts]", curPrice, estSL, slPts);
         double tp1 = curPrice + (InpScalpTakeProfitPts * pt);
         double tp2 = curPrice + (slPts * InpRiskRewardRatio * pt);
         tpTargetsTxt = StringFormat("🎯 TP1 (Scalp 50%%): %.2f [+%d pts] | 🚀 TP2 (Runner 50%%): %.2f", tp1, InpScalpTakeProfitPts, tp2);
      }
      else if(g_lastSignalDirection == -1)
      {
         actionTxt = "🎯 SINAL RECOMENDADO: [ 🔴 FORTE VENDA NO PULLBACK / VWAP ]";
         actionClr = clrRed;
         double estSL = (g_lastSignalSL > 0.0) ? g_lastSignalSL : (g_currentSwingHigh > 0.0 ? (g_currentSwingHigh + InpSLBufferPoints * pt) : (curPrice + InpMinSLPoints * pt));
         double slPts = MathAbs(estSL - curPrice) / pt;
         entrySLTxt = StringFormat("📍 ENTRADA: %.2f | 🛑 STOP LOSS: %.2f [%.0f pts]", curPrice, estSL, slPts);
         double tp1 = curPrice - (InpScalpTakeProfitPts * pt);
         double tp2 = curPrice - (slPts * InpRiskRewardRatio * pt);
         tpTargetsTxt = StringFormat("🎯 TP1 (Scalp 50%%): %.2f [-%d pts] | 🚀 TP2 (Runner 50%%): %.2f", tp1, InpScalpTakeProfitPts, tp2);
      }
      else
      {
         actionTxt = "🎯 AÇÃO IMEDIATA: [ ⚪ MONITORANDO FLUXO & ABSORÇÃO NA VWAP ]";
         actionClr = clrGold;
         entrySLTxt = StringFormat("📍 PRÓX. COMPRA: Acima de %.2f (Topo) | PRÓX. VENDA: Abaixo de %.2f (Fundo)", g_currentSwingHigh, g_currentSwingLow);
         tpTargetsTxt = StringFormat("🎯 ALVOS PADRÃO: TP1 Scalp %d pts | TP2 Runner Parede de Liquidez Bookmap", InpScalpTakeProfitPts);
      }
   }

   ObjectSetString(0, G_PREFIX + "Txt_Action", OBJPROP_TEXT, actionTxt);
   ObjectSetInteger(0, G_PREFIX + "Txt_Action", OBJPROP_COLOR, actionClr);

   ObjectSetString(0, G_PREFIX + "Txt_EntrySL", OBJPROP_TEXT, entrySLTxt);
   ObjectSetString(0, G_PREFIX + "Txt_TPTargets", OBJPROP_TEXT, tpTargetsTxt);

   ObjectSetString(0, G_PREFIX + "Txt_RiskRule", OBJPROP_TEXT, "🛡️ GESTÃO DE CAPITAL: Ao atingir TP1 ➔ SL da Perna Runner é puxado para o 0x0 (Break-Even)!");

   string resStr = "Resistência (Topo MT5): " + (g_currentSwingHigh > 0.0 ? DoubleToString(g_currentSwingHigh, _Digits) : "---");
   if(g_currentSwingHigh > 0.0) resStr += StringFormat(" [%.0f pts]", (g_currentSwingHigh - curPrice) / pt);
   string supStr = "Suporte (Fundo MT5): " + (g_currentSwingLow > 0.0 ? DoubleToString(g_currentSwingLow, _Digits) : "---");
   if(g_currentSwingLow > 0.0) supStr += StringFormat(" [%.0f pts]", (curPrice - g_currentSwingLow) / pt);
   ObjectSetString(0, G_PREFIX + "Txt_ResSup", OBJPROP_TEXT, resStr + " | " + supStr);

   if(g_bmData.isConnected && g_bmData.lastPrice > 0.0)
   {
      string bmSym = (g_bmData.symbol != "" ? g_bmData.symbol : (curPrice > 10000.0 ? "BTC" : "COMEX GC"));
      string compStr = StringFormat("⚡ BOOKMAP %s: %.2f USD | 🏦 %s SPOT: %.2f USD", bmSym, g_bmData.lastPrice, _Symbol, curPrice);
      ObjectSetString(0, G_PREFIX + "Txt_BMComp", OBJPROP_TEXT, compStr);

      string basisStr = StringFormat("⚖ DIFERENÇA (BASIS): %+.2f USD ➔ Níveis Bookmap sincronizados nas velas MT5", g_smoothedBasis);
      ObjectSetString(0, G_PREFIX + "Txt_BMBasis", OBJPROP_TEXT, basisStr);

      string deltaDiag = (g_bmData.delta > 50) ? "[COMPRADORES ATIVOS]" : ((g_bmData.delta < -50) ? "[VENDEDORES ATIVOS]" : "[FLUXO EQUILIBRADO]");
      color deltaClr = (g_bmData.delta > 0) ? clrLimeGreen : ((g_bmData.delta < 0) ? clrCrimson : clrSilver);
      string deltaStr = StringFormat("📊 DELTA BOOKMAP: %+d %s | CVD: %+d | Vol Total: %d", g_bmData.delta, deltaDiag, g_bmData.cvd, g_bmData.totalVol);
      ObjectSetString(0, G_PREFIX + "Txt_BMDelta", OBJPROP_TEXT, deltaStr);
      ObjectSetInteger(0, G_PREFIX + "Txt_BMDelta", OBJPROP_COLOR, deltaClr);

      double mt5_vwap = (g_bmData.vwap > 0.0) ? (g_bmData.vwap - g_smoothedBasis) : 0.0;
      double mt5_poc  = (g_bmData.poc > 0.0) ? (g_bmData.poc - g_smoothedBasis) : 0.0;
      double mt5_vah  = (g_bmData.vah > 0.0) ? (g_bmData.vah - g_smoothedBasis) : 0.0;
      double mt5_val  = (g_bmData.val > 0.0) ? (g_bmData.val - g_smoothedBasis) : 0.0;
      string nodesStr = StringFormat("🟣 VWAP: %.2f | ★ POC: %.2f | 🔺 VAH: %.2f | 🔻 VAL: %.2f", mt5_vwap, mt5_poc, mt5_vah, mt5_val);
      ObjectSetString(0, G_PREFIX + "Txt_BMNodes", OBJPROP_TEXT, nodesStr);

      double mt5_prh = (g_bmData.profileHigh > 0.0) ? (g_bmData.profileHigh - g_smoothedBasis) : (mt5_vah > 0.0 ? mt5_vah + 5.0 : curPrice + 10.0);
      double mt5_prl = (g_bmData.profileLow > 0.0) ? (g_bmData.profileLow - g_smoothedBasis) : (mt5_val > 0.0 ? mt5_val - 5.0 : curPrice - 10.0);
      string vpvrStatus = "";
      color  vpvrClr    = clrSilver;

      if(mt5_vah > 0.0 && mt5_val > 0.0)
      {
         if(curPrice > mt5_vah)
         {
            double diffPts = (curPrice - mt5_vah) / pt;
            vpvrStatus = StringFormat("🚀 ACIMA DO VAH (+%.0f pts) | EXPANSÃO COMPRADORA", diffPts);
            vpvrClr = clrLimeGreen;
         }
         else if(curPrice < mt5_val)
         {
            double diffPts = (mt5_val - curPrice) / pt;
            vpvrStatus = StringFormat("💥 ABAIXO DO VAL (-%.0f pts) | EXPANSÃO VENDEDORA", diffPts);
            vpvrClr = clrCrimson;
         }
         else
         {
            double distPoc = (curPrice - mt5_poc) / pt;
            vpvrStatus = StringFormat("⚖ NA VALUE AREA 70%% (Afast. POC %+.0f pts)", distPoc);
            vpvrClr = clrGold;
         }
      }
      else
      {
         vpvrStatus = "Calculando distribuição VPVR...";
         vpvrClr = clrSilver;
      }

      string vpvrStr = StringFormat("📊 VPVR: Range [%.2f ⟷ %.2f] | %s", mt5_prl, mt5_prh, vpvrStatus);
      ObjectSetString(0, G_PREFIX + "Txt_BMVPVR", OBJPROP_TEXT, vpvrStr);
      ObjectSetInteger(0, G_PREFIX + "Txt_BMVPVR", OBJPROP_COLOR, vpvrClr);


      double mt5_bidWall = (g_bmData.bidWallPrice > 0.0) ? (g_bmData.bidWallPrice - g_smoothedBasis) : 0.0;
      double mt5_askWall = (g_bmData.askWallPrice > 0.0) ? (g_bmData.askWallPrice - g_smoothedBasis) : 0.0;
      string wallsStr = "";
      if(g_bmData.askWallVol >= InpMinWallVolume && mt5_askWall > 0.0)
         wallsStr += StringFormat("🏰 VENDA: %.2f (%d lotes) ", mt5_askWall, g_bmData.askWallVol);
      else
         wallsStr += "🏰 VENDA: Sem parede massiva ";

      if(g_bmData.bidWallVol >= InpMinWallVolume && mt5_bidWall > 0.0)
         wallsStr += StringFormat("| 🛡️ COMPRA: %.2f (%d lotes)", mt5_bidWall, g_bmData.bidWallVol);
      else
         wallsStr += "| 🛡️ COMPRA: Sem parede massiva";
      ObjectSetString(0, G_PREFIX + "Txt_BMWalls", OBJPROP_TEXT, wallsStr);
   }
   else
   {
      ObjectSetString(0, G_PREFIX + "Txt_BMComp", OBJPROP_TEXT, "⚡ BOOKMAP: Conectando na porta 5555 / arquivo stream...");
      ObjectSetString(0, G_PREFIX + "Txt_BMBasis", OBJPROP_TEXT, "⚖ DIFERENÇA (BASIS): Aguardando primeiro tick do COMEX...");
      ObjectSetString(0, G_PREFIX + "Txt_BMDelta", OBJPROP_TEXT, "📊 DELTA BOOKMAP: Aguardando fluxo...");
      ObjectSetString(0, G_PREFIX + "Txt_BMNodes", OBJPROP_TEXT, "🟣 VWAP & PROFILE (POC/VAH/VAL): Aguardando Bookmap...");
      ObjectSetString(0, G_PREFIX + "Txt_BMVPVR", OBJPROP_TEXT, "📊 VPVR: Aguardando distribuição de volume Bookmap...");
      ObjectSetString(0, G_PREFIX + "Txt_BMWalls", OBJPROP_TEXT, "🏰 PAREDES DE LIQUIDEZ: Aguardando profundidade DOM...");
   }

   ObjectSetString(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_TEXT, "Vela [0]: " + g_candleActionText);
   ObjectSetInteger(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_COLOR, g_candleActionColor);

   string filterStr = "";
   if(InpUseEMATrendFilter && g_handleEMA != INVALID_HANDLE)
   {
      double emaBuf[1];
      if(CopyBuffer(g_handleEMA, 0, 0, 1, emaBuf) > 0)
      {
         if(curPrice > emaBuf[0]) filterStr += "[EMA200: ALTA] ";
         else filterStr += "[EMA200: BAIXA] ";
      }
   }
   if(InpUseADXFilter && g_handleADX != INVALID_HANDLE)
   {
      double adxBuf[1];
      if(CopyBuffer(g_handleADX, 0, 0, 1, adxBuf) > 0)
      {
         if(adxBuf[0] >= InpMinADXLevel) filterStr += "[ADX: " + DoubleToString(adxBuf[0], 1) + " OK] ";
         else filterStr += "[ADX: " + DoubleToString(adxBuf[0], 1) + " LATERAL] ";
      }
   }
   ObjectSetString(0, G_PREFIX + "Txt_Diag", OBJPROP_TEXT, "Contexto: " + filterStr + g_candleContextDiag);

   string botStatusStr = g_signalsActive ? "STATUS: 🟢 SINAIS ATIVOS E MONITORANDO COM ALERTAS" : "STATUS: 🔴 SINAIS PAUSADOS PELO USUÁRIO (SILENCIADO)";
   ObjectSetString(0, G_PREFIX + "Txt_BotStatus", OBJPROP_TEXT, botStatusStr);
   ObjectSetInteger(0, G_PREFIX + "Txt_BotStatus", OBJPROP_COLOR, g_signalsActive ? clrLimeGreen : clrRed);
}

//+------------------------------------------------------------------+
void CreateDashLabel(string name, string text, int x, int y, color clr, int size, bool bold)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, g_panelX + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, g_panelY + y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Segoe UI Bold" : "Segoe UI Semibold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void CreateDashButton(string name, string text, int x, int y, int w, int h, color bgClr, color txtClr, int fSize = 8)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, g_panelX + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, g_panelY + y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtClr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, InpPanelBorderColor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DrawTrend(string name, datetime t1, double p1, datetime t2, double p2, color clr, ENUM_LINE_STYLE style, int width)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void UpdateTrend(string name, datetime t2)
{
   if(ObjectFind(0, name) >= 0)
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
}

void DrawHLine(string name, datetime t1, datetime t2, double price, color clr, ENUM_LINE_STYLE style, int width, string desc)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, desc);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

   string txtName = name + "_Txt";
   ObjectDelete(0, txtName);
   ObjectCreate(0, txtName, OBJ_TEXT, 0, t2, price);
   ObjectSetString(0, txtName, OBJPROP_TEXT, "  " + desc + " [" + DoubleToString(price, _Digits) + "]");
   ObjectSetString(0, txtName, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(0, txtName, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, txtName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, txtName, OBJPROP_SELECTABLE, false);
}

void DrawTargetLine(string name, datetime t1, datetime t2, double price, color clr, string desc)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

   string txtName = name + "_Txt";
   ObjectDelete(0, txtName);
   ObjectCreate(0, txtName, OBJ_TEXT, 0, t2, price);
   ObjectSetString(0, txtName, OBJPROP_TEXT, "  ◀ " + desc);
   ObjectSetString(0, txtName, OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, txtName, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, txtName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, txtName, OBJPROP_SELECTABLE, false);
}

void DrawZoneBox(string name, datetime t1, datetime t2, double p1, double p2, color clr, string desc)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, desc);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DrawBadgeLabel(string name, datetime t, double p, string text, color clr, ENUM_ANCHOR_POINT anchor)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DrawFloatingTag(string name, datetime t, double p, string text, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
      ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Bold");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }

   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void DispatchNotification(string message, string soundFile = "", bool isLive = false)
{
   if(!isLive || !g_signalsActive) return;

   if(InpAlertPopUp)
      Alert(message);

   if(InpAlertSound && soundFile != "")
      PlaySound(soundFile);
   else if(InpAlertSound && InpSoundBOS != "")
      PlaySound(InpSoundBOS);

   if(InpAlertPush)
      SendNotification(message);
}

void CleanObjects(string prefix)
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}
//+------------------------------------------------------------------+
