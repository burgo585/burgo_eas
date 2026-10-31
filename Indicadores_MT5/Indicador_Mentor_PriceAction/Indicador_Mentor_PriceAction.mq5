//+------------------------------------------------------------------+
//|                                   Indicador_Mentor_PriceAction.mq5|
//|                             Metodologia Mentor Price Action Pro |
//|                                 Burgo585 - Price Action & Pivôs  |
//+------------------------------------------------------------------+
#property copyright "Burgo585 & O Mentor"
#property link      "https://github.com/burgo585/burgo_eas"
#property version   "3.70"
#property description "Indicador Oficial de Price Action Puro do Mentor (Versão 3.70 Pro - Clean)"
#property description "- Traçado Estrutural dos Pivôs com Filtro Anti-Ruído de Micro-Oscilações"
#property description "- Linha Projetada no Espaço Futuro sem Poluir Candles com Rótulos Concisos"
#property description "- Modo Gráfico Limpo: Apenas Topo e Fundo Ativos Rotulados (Fim da Sopa de Letras)"
#property description "- Painel HUD Auto-Escalável [A+ / A-] com Sumário de Cores e Arraste Fluido"
#property description "- Monitoramento em Tempo Real do Candle 0, Pavio, Tempo e Ação Imediata"

#property indicator_chart_window
#property indicator_buffers 10
#property indicator_plots   4

//--- Plot 1: Média Móvel 200
#property indicator_label1  "Média 200 (Alvo/Guia)"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDeepSkyBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Plot 2: Seta de Compra
#property indicator_label2  "Compra Pivô (Gatilho)"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_width2  2

//--- Plot 3: Seta de Venda
#property indicator_label3  "Venda Pivô (Gatilho)"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrMagenta
#property indicator_width3  2

//--- Plot 4: Coloração Personalizada de Candles
#property indicator_label4  "Mentor Candles"
#property indicator_type4   DRAW_COLOR_CANDLES
#property indicator_color4  clrSeaGreen, clrFireBrick, clrLime, clrMagenta, clrGold, clrDimGray
#property indicator_width4  1

enum ENUM_EMA_TYPE
{
   EMA_EXPONENCIAL = MODE_EMA, // Exponencial
   EMA_SIMPLES     = MODE_SMA  // Simples
};

//+------------------------------------------------------------------+
//| Inputs do Indicador                                              |
//+------------------------------------------------------------------+
input group "=== TAMANHO DO PAINEL E ESCALA DAS FONTES ==="
input double             InpPanelScale           = 1.0;              // Escala Geral do Painel (0.75 a 2.0)
input int                InpBaseFontSize         = 9;                // Tamanho Base da Fonte (8 a 16)
input bool               InpShowLegendAtStart    = false;            // Iniciar com Sumário de Cores Aberto [📖]

input group "=== CONFIGURAÇÃO DA MÉDIA DE 200 (BÚSSOLA) ==="
input int                InpEmaPeriod            = 200;              // Período da Média
input ENUM_EMA_TYPE      InpEmaMethod            = EMA_EXPONENCIAL;  // Tipo de Média Móvel
input ENUM_APPLIED_PRICE InpEmaApplied           = PRICE_CLOSE;      // Preço Aplicado

input group "=== ESTRUTURA VISUAL DOS PIVÔS (V E W EMPENADO) ==="
input int                InpSwingStrength        = 3;                // Sensibilidade dos Swings (3=Equilibrado, 4=Conservador)
input int                InpMinSwingPoints       = 35;               // Amplitude Mínima do Swing em Pontos (Filtro Anti-Ruído)
input int                InpMaxHistoryBars       = 600;              // Histórico de Barras Avaliadas
input bool               InpDrawPivotLines       = true;             // Desenhar Zigue-Zague Estrutural do Pivô
input color              InpPivotLineColor       = clrCyan;          // Cor da Estrutura do Pivô
input int                InpPivotLineWidth       = 2;                // Espessura da Estrutura (1 a 5)
input bool               InpShowPivotBadges      = true;             // Exibir Rótulos nos Pivôs
input bool               InpShowOnlyActiveBadges = true;             // Exibir APENAS Topo e Fundo Ativos (Gráfico 100% Limpo)
input int                InpArrowWidth           = 2;                // Tamanho das Setas de Gatilho (1=Discreta, 2=Padrão, 3=Grande)

input group "=== LINHA DE GATILHO DE ROMPIMENTO E DIREÇÃO ==="
input bool               InpShowTriggerLines     = true;             // Exibir Linhas de Rompimento Projetadas
input color              InpColorTriggerBuy      = clrGold;          // Cor da Linha de Gatilho de Compra
input color              InpColorTriggerSell     = clrDeepPink;      // Cor da Linha de Gatilho de Venda
input int                InpTriggerLineWidth     = 2;                // Espessura da Linha de Rompimento
input bool               InpShowDirectionSign    = true;             // Exibir Setas e Texto de Direção na Linha

input group "=== COLORAÇÃO DINÂMICA DE CANDLES ==="
input bool               InpColorizeCandles   = true;             // Ativar Coloração Especial de Candles
input color              InpColorBull         = clrSeaGreen;      // Candle Alta Normal
input color              InpColorBear         = clrFireBrick;     // Candle Baixa Normal
input color              InpColorBreakBuy     = clrLime;          // Candle Rompimento de Alta (Compra ↗)
input color              InpColorBreakSell    = clrMagenta;       // Candle Rompimento de Baixa (Venda ↘)
input color              InpColorWickSetup    = clrGold;          // Candle com Pavio Válido de Setup
input color              InpColorBaldWarning  = clrDimGray;       // Vela Careca / Armadilha (Não Operar)

input group "=== GATILHO DO PAVIO (MICROESTRUTURA) ==="
input int                InpMinWickPoints     = 12;               // Pavio Mínimo Contrário em Pontos (Filtro Vela Careca)
input int                InpMinBodyPoints     = 20;               // Corpo Mínimo do Candle em Pontos
input double             InpRiskRewardRatio   = 3.0;              // Relação Alvo:Risco (Padrão 3:1 do Mentor)

input group "=== GESTÃO DE BANCA ($300) ==="
input double             InpAccountBalance    = 300.0;            // Saldo da Conta ($)
input double             InpLotSize           = 0.01;             // Lote Recomendado ($300 -> 0.01)

input group "=== LINHAS OPERACIONAIS DE EXECUÇÃO ==="
input bool               InpShowLines         = true;             // Traçar Linhas de Entrada, Stop e Alvo
input color              InpColorEntry        = clrGold;          // Cor da Linha de Entrada
input color              InpColorStop         = clrRed;           // Cor da Linha de Stop Loss
input color              InpColorTarget       = clrLimeGreen;     // Cor da Linha de Alvo 3:1

input group "=== ALERTAS MULTICANAIS ==="
input bool               InpAlertPopup        = true;             // Alerta Pop-up na Tela
input bool               InpAlertSound        = true;             // Alerta Sonoro
input string             InpSoundFile         = "alert.wav";      // Som do Alerta
input bool               InpAlertPush         = false;            // Notificação Push no Celular

//--- Buffers
double BufferEMA200[];
double BufferBuy[];
double BufferSell[];
double BufferCandleOpen[];
double BufferCandleHigh[];
double BufferCandleLow[];
double BufferCandleClose[];
double BufferCandleColor[];
double BufferStopLoss[];
double BufferTakeProfit[];

//--- Variáveis Globais
int      emaHandle = INVALID_HANDLE;
datetime lastAlertTime = 0;
string   prefixObjects = "MENTOR_PA_";

// Coordenadas, Escala e Estado do Painel HUD
int      panelX          = 20;
int      panelY          = 35;
double   gPanelScale     = 1.0;
int      gBaseFontSize   = 9;
bool     panelMinimized  = false;
bool     gShowLegend     = false;
bool     isDragging      = false;
int      dragOffsetX     = 0;
int      dragOffsetY     = 0;

struct SwingPoint
{
   datetime time;
   double   price;
   int      barIndex;
   bool     isHigh;
};

// Último Sinal Identificado
string   gLastSignalType   = "AGUARDANDO";
double   gLastEntryPrice   = 0.0;
double   gLastStopLoss     = 0.0;
double   gLastTakeProfit   = 0.0;
datetime gLastSignalTime   = 0;
string   gLastPatternDesc  = "Rastreando Pivô...";
double   gActivePivotHigh  = 0.0;
double   gActivePivotLow   = 0.0;
datetime gActiveHighTime   = 0;
datetime gActiveLowTime    = 0;

// Cache de Dados para Atualização do HUD sem Dependência de Ticks
double   gCachePrice       = 0.0;
double   gCacheEma         = 0.0;
datetime gCacheTimeBar     = 0;
double   gCacheOpen        = 0.0;
double   gCacheHigh        = 0.0;
double   gCacheLow         = 0.0;
double   gCacheClose       = 0.0;
double   gCacheDistToBuy   = 9999.0;
double   gCacheDistToSell  = 9999.0;
string   gCacheFormacaoStatus = "Aguardando Leitura";
color    gCacheFormacaoColor  = clrLightSkyBlue;
string   gCacheAcaoMsg     = "Aguardando";
color    gCacheAcaoTxt     = clrWhite;
color    gCacheAcaoBg      = C'15,30,45';
string   gCacheWickStr     = "";
color    gCacheWickColor   = clrWhite;

// Funções de Escala Proporcional
int sW(int w) { return (int)MathRound(w * gPanelScale); }
int sH(int h) { return (int)MathRound(h * gPanelScale); }
int sF(int f) { return MathMax(7, (int)MathRound(f * gPanelScale)); }

// Declarações antecipadas
void AtualizarLinhasDeGatilho(datetime curTime, double curClose);
void DesenharEstruturaPivos(const SwingPoint &highs[], const SwingPoint &lows[]);
void DesenharLinhasOperacionais(string tipo, double entrada, double stop, double alvo);
void CriarLinhaTendencia(string name, datetime t1, double p1, datetime t2, double p2, color clr, ENUM_LINE_STYLE style, int width);
void CriarLinhaHorizontal(string name, double price, color clr, ENUM_LINE_STYLE style, int width, string desc);
void CriarTextoGrafico(string name, datetime t, double p, string text, color clr, int fontSize, bool isBold);
void CriarSetaGrafica(string name, datetime t, double p, int arrowCode, color clr);
void DispararAlerta(string tipo, double entrada, double stop, double alvo);
void DesenharOuAtualizarHUD();
void LimparTodosLabelsHUD();
void CriarOuAtualizarRetanguloHUD(string name, int x, int y, int w, int h, color bgClr, color borderClr);
void CriarOuAtualizarLabelHUD(string name, int x, int y, string text, color clr, int fontSize, bool isBold);
void CriarOuAtualizarBotaoHUD(string name, int x, int y, int w, int h, string text, color txtClr, color bgClr, int fontSize = 8);
void ApagarElementoHUD(string name);
void CalculateDirectEma(int total, const double &close[]);

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   gPanelScale     = InpPanelScale;
   gBaseFontSize   = InpBaseFontSize;
   gShowLegend     = InpShowLegendAtStart;

   SetIndexBuffer(0, BufferEMA200,      INDICATOR_DATA);
   SetIndexBuffer(1, BufferBuy,         INDICATOR_DATA);
   SetIndexBuffer(2, BufferSell,        INDICATOR_DATA);

   SetIndexBuffer(3, BufferCandleOpen,  INDICATOR_DATA);
   SetIndexBuffer(4, BufferCandleHigh,  INDICATOR_DATA);
   SetIndexBuffer(5, BufferCandleLow,   INDICATOR_DATA);
   SetIndexBuffer(6, BufferCandleClose, INDICATOR_DATA);
   SetIndexBuffer(7, BufferCandleColor, INDICATOR_COLOR_INDEX);

   SetIndexBuffer(8, BufferStopLoss,    INDICATOR_CALCULATIONS);
   SetIndexBuffer(9, BufferTakeProfit,  INDICATOR_CALCULATIONS);

   ArraySetAsSeries(BufferEMA200,      true);
   ArraySetAsSeries(BufferBuy,         true);
   ArraySetAsSeries(BufferSell,        true);
   ArraySetAsSeries(BufferCandleOpen,  true);
   ArraySetAsSeries(BufferCandleHigh,  true);
   ArraySetAsSeries(BufferCandleLow,   true);
   ArraySetAsSeries(BufferCandleClose, true);
   ArraySetAsSeries(BufferCandleColor, true);
   ArraySetAsSeries(BufferStopLoss,    true);
   ArraySetAsSeries(BufferTakeProfit,  true);

   // CRUCIAL: Definir EMPTY_VALUE para NUNCA distorcer a escala do gráfico no Zoom!
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(1, PLOT_ARROW, 233); // Seta de Compra
   PlotIndexSetInteger(2, PLOT_ARROW, 234); // Seta de Venda
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, InpArrowWidth);
   PlotIndexSetInteger(2, PLOT_LINE_WIDTH, InpArrowWidth);

   PlotIndexSetInteger(3, PLOT_DRAW_TYPE, InpColorizeCandles ? DRAW_COLOR_CANDLES : DRAW_NONE);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, 0, InpColorBull);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, 1, InpColorBear);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, 2, InpColorBreakBuy);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, 3, InpColorBreakSell);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, 4, InpColorWickSetup);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, 5, InpColorBaldWarning);

   emaHandle = iMA(_Symbol, _Period, InpEmaPeriod, 0, (ENUM_MA_METHOD)InpEmaMethod, InpEmaApplied);
   if (emaHandle == INVALID_HANDLE)
   {
      Print("[Mentor PA] Erro ao criar handle da Média 200!");
      return INIT_FAILED;
   }

   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   ChartSetInteger(0, CHART_SHIFT, true);
   ChartSetDouble(0, CHART_SHIFT_SIZE, 12.0);

   string shortName = StringFormat("Mentor Price Action v3.70 Pro - Clean (EMA %d | 3:1)", InpEmaPeriod);
   IndicatorSetString(INDICATOR_SHORTNAME, shortName);
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);

   ObjectsDeleteAll(0, prefixObjects);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
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
   if (rates_total < InpEmaPeriod + 10)
      return 0;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int copyCount = CopyBuffer(emaHandle, 0, 0, rates_total, BufferEMA200);
   if (copyCount <= 0)
      CalculateDirectEma(rates_total, close);

   // Preencher TODOS os candles para a escala vertical do gráfico ser 100% perfeita
   int startCandle = (prev_calculated > 0) ? (rates_total - prev_calculated + 2) : (rates_total - 1);
   if (startCandle >= rates_total) startCandle = rates_total - 1;

   for (int i = startCandle; i >= 0; i--)
   {
      BufferBuy[i]  = EMPTY_VALUE;
      BufferSell[i] = EMPTY_VALUE;

      if (InpColorizeCandles)
      {
         BufferCandleOpen[i]  = open[i];
         BufferCandleHigh[i]  = high[i];
         BufferCandleLow[i]   = low[i];
         BufferCandleClose[i] = close[i];
         BufferCandleColor[i] = (close[i] >= open[i]) ? 0.0 : 1.0;
      }
      else
      {
         BufferCandleOpen[i]  = EMPTY_VALUE;
         BufferCandleHigh[i]  = EMPTY_VALUE;
         BufferCandleLow[i]   = EMPTY_VALUE;
         BufferCandleClose[i] = EMPTY_VALUE;
         BufferCandleColor[i] = EMPTY_VALUE;
      }
   }

   int limit = InpMaxHistoryBars;
   if (limit > rates_total - InpSwingStrength - 5)
      limit = rates_total - InpSwingStrength - 5;

   ObjectsDeleteAll(0, prefixObjects + "PV_");
   ObjectsDeleteAll(0, prefixObjects + "BADGE_");

   SwingPoint confirmedHighs[];
   SwingPoint confirmedLows[];
   ArrayResize(confirmedHighs, 0);
   ArrayResize(confirmedLows, 0);

   int lastBrokenHighIdx = -1;
   int lastBrokenLowIdx  = -1;

   for (int i = limit; i >= 1; i--)
   {
      int swBar = i + InpSwingStrength;
      if (swBar < rates_total - InpSwingStrength)
      {
         bool isH = true;
         bool isL = true;
         double hVal = high[swBar];
         double lVal = low[swBar];

         for (int k = 1; k <= InpSwingStrength; k++)
         {
            if (high[swBar - k] >= hVal || high[swBar + k] > hVal) isH = false;
            if (low[swBar - k] <= lVal || low[swBar + k] < lVal)   isL = false;
         }

         if (isH)
         {
            int sz = ArraySize(confirmedHighs);
            int lastLsz = ArraySize(confirmedLows);
            bool acceptH = true;
            if (lastLsz > 0)
            {
               double distPts = (hVal - confirmedLows[lastLsz - 1].price) / _Point;
               if (distPts < InpMinSwingPoints) acceptH = false;
            }
            if (acceptH)
            {
               ArrayResize(confirmedHighs, sz + 1);
               confirmedHighs[sz].time     = time[swBar];
               confirmedHighs[sz].price    = hVal;
               confirmedHighs[sz].barIndex = swBar;
               confirmedHighs[sz].isHigh   = true;
            }
         }

         if (isL)
         {
            int sz = ArraySize(confirmedLows);
            int lastHsz = ArraySize(confirmedHighs);
            bool acceptL = true;
            if (lastHsz > 0)
            {
               double distPts = (confirmedHighs[lastHsz - 1].price - lVal) / _Point;
               if (distPts < InpMinSwingPoints) acceptL = false;
            }
            if (acceptL)
            {
               ArrayResize(confirmedLows, sz + 1);
               confirmedLows[sz].time     = time[swBar];
               confirmedLows[sz].price    = lVal;
               confirmedLows[sz].barIndex = swBar;
               confirmedLows[sz].isHigh   = false;
            }
         }
      }

      int nH = ArraySize(confirmedHighs);
      int nL = ArraySize(confirmedLows);

      if (nH >= 1 && nL >= 1)
      {
         double lastHigh = confirmedHighs[nH - 1].price;
         double lastLow  = confirmedLows[nL - 1].price;

         double cOpen  = open[i];
         double cClose = close[i];
         double cHigh  = high[i];
         double cLow   = low[i];

         double minWick = InpMinWickPoints * _Point;
         double minBody = InpMinBodyPoints * _Point;

         double lowerWick = MathMin(cOpen, cClose) - cLow;
         double upperWick = cHigh - MathMax(cOpen, cClose);

         if (InpColorizeCandles)
         {
            if (cClose > cOpen && lowerWick < (minWick * 0.4) && (cHigh - cClose) < (minWick * 0.4))
               BufferCandleColor[i] = 5.0; // Vela Careca Alta (Cinza / Alerta)
            else if (cOpen > cClose && upperWick < (minWick * 0.4) && (cClose - cLow) < (minWick * 0.4))
               BufferCandleColor[i] = 5.0; // Vela Careca Baixa
            else if (cClose > cOpen && lowerWick >= minWick)
               BufferCandleColor[i] = 4.0; // Pavio de Setup Válido (Dourado)
            else if (cOpen > cClose && upperWick >= minWick)
               BufferCandleColor[i] = 4.0;
         }

         // Gatilho de Compra Único e Limpo por Rompimento de Topo
         if (cClose > lastHigh && (cOpen <= lastHigh || cLow <= lastHigh) && (cClose - cOpen) >= minBody)
         {
            if (lastBrokenHighIdx != (nH - 1))
            {
               if (lowerWick >= minWick)
               {
                  double stopLoss = lastLow - (15 * _Point);
                  double risk     = cClose - stopLoss;

                  if (risk >= (25 * _Point))
                  {
                     lastBrokenHighIdx = nH - 1; // Registra sinal único para este topo
                     double takeProfit = cClose + (risk * InpRiskRewardRatio);

                     BufferBuy[i]        = cLow - (15 * _Point);
                     BufferStopLoss[i]   = stopLoss;
                     BufferTakeProfit[i] = takeProfit;

                     if (InpColorizeCandles)
                        BufferCandleColor[i] = 2.0;

                     string padrao = "Pivô de Alta em V";
                     if (nL >= 2 && MathAbs(confirmedLows[nL-1].price - confirmedLows[nL-2].price) <= (150 * _Point))
                        padrao = "Pivô em W Empenado";

                     if (i <= 50 && time[i] >= gLastSignalTime)
                     {
                        gLastSignalType  = "COMPRA";
                        gLastEntryPrice  = cClose;
                        gLastStopLoss    = stopLoss;
                        gLastTakeProfit  = takeProfit;
                        gLastSignalTime  = time[i];
                        gLastPatternDesc = padrao;

                        if (InpShowLines)
                           DesenharLinhasOperacionais("COMPRA", cClose, stopLoss, takeProfit);

                        if (i == 1 && time[1] != lastAlertTime)
                        {
                           lastAlertTime = time[1];
                           DispararAlerta("COMPRA (" + padrao + ")", cClose, stopLoss, takeProfit);
                        }
                     }
                  }
               }
            }
         }

         // Gatilho de Venda Único e Limpo por Perda de Fundo
         if (cClose < lastLow && (cOpen >= lastLow || cHigh >= lastLow) && (cOpen - cClose) >= minBody)
         {
            if (lastBrokenLowIdx != (nL - 1))
            {
               if (upperWick >= minWick)
               {
                  double stopLoss = lastHigh + (15 * _Point);
                  double risk     = stopLoss - cClose;

                  if (risk >= (25 * _Point))
                  {
                     lastBrokenLowIdx = nL - 1; // Registra sinal único para este fundo
                     double takeProfit = cClose - (risk * InpRiskRewardRatio);

                     BufferSell[i]       = cHigh + (15 * _Point);
                     BufferStopLoss[i]   = stopLoss;
                     BufferTakeProfit[i] = takeProfit;

                     if (InpColorizeCandles)
                        BufferCandleColor[i] = 3.0;

                     string padrao = "Pivô de Baixa em V";
                     if (nH >= 2 && MathAbs(confirmedHighs[nH-1].price - confirmedHighs[nH-2].price) <= (150 * _Point))
                        padrao = "Topo Duplo (M)";

                     if (i <= 50 && time[i] >= gLastSignalTime)
                     {
                        gLastSignalType  = "VENDA";
                        gLastEntryPrice  = cClose;
                        gLastStopLoss    = stopLoss;
                        gLastTakeProfit  = takeProfit;
                        gLastSignalTime  = time[i];
                        gLastPatternDesc = padrao;

                        if (InpShowLines)
                           DesenharLinhasOperacionais("VENDA", cClose, stopLoss, takeProfit);

                        if (i == 1 && time[1] != lastAlertTime)
                        {
                           lastAlertTime = time[1];
                           DispararAlerta("VENDA (" + padrao + ")", cClose, stopLoss, takeProfit);
                        }
                     }
                  }
               }
            }
         }
      }
   }

   if (InpDrawPivotLines)
      DesenharEstruturaPivos(confirmedHighs, confirmedLows);

   int nH = ArraySize(confirmedHighs);
   int nL = ArraySize(confirmedLows);
   if (nH > 0 && nL > 0)
   {
      gActivePivotHigh = confirmedHighs[nH - 1].price;
      gActiveHighTime  = confirmedHighs[nH - 1].time;
      gActivePivotLow  = confirmedLows[nL - 1].price;
      gActiveLowTime   = confirmedLows[nL - 1].time;

      if (InpShowTriggerLines)
         AtualizarLinhasDeGatilho(time[0], close[0]);
   }

   // Atualizar Cache do HUD
   gCachePrice      = close[0];
   gCacheEma        = BufferEMA200[0];
   gCacheTimeBar    = time[0];
   gCacheOpen       = open[0];
   gCacheHigh       = high[0];
   gCacheLow        = low[0];
   gCacheClose      = close[0];
   gCacheDistToBuy  = (gActivePivotHigh > 0) ? (gActivePivotHigh - close[0]) / _Point : 9999.0;
   gCacheDistToSell = (gActivePivotLow > 0)  ? (close[0] - gActivePivotLow) / _Point  : 9999.0;

   double cLowerWick = (MathMin(open[0], close[0]) - low[0]) / _Point;
   double cUpperWick = (high[0] - MathMax(open[0], close[0])) / _Point;

   if (close[0] >= open[0])
   {
      if (cLowerWick >= InpMinWickPoints)
      {
         gCacheWickStr   = StringFormat("Pavio Inf: %.0f pts (OK - Mola Pronta)", cLowerWick);
         gCacheWickColor = clrSpringGreen;
      }
      else
      {
         gCacheWickStr   = StringFormat("Pavio Inf: %.0f pts (CUIDADO: Vela Careca!)", cLowerWick);
         gCacheWickColor = clrDimGray;
      }
   }
   else
   {
      if (cUpperWick >= InpMinWickPoints)
      {
         gCacheWickStr   = StringFormat("Pavio Sup: %.0f pts (OK - Mola Pronta)", cUpperWick);
         gCacheWickColor = clrSpringGreen;
      }
      else
      {
         gCacheWickStr   = StringFormat("Pavio Sup: %.0f pts (CUIDADO: Vela Careca!)", cUpperWick);
         gCacheWickColor = clrDimGray;
      }
   }

   // Formação em Andamento
   if (gCacheDistToBuy <= 45 && gCacheDistToBuy > 0)
   {
      gCacheFormacaoStatus = StringFormat("Testando Topo em %.2f (Faltam %.0f pts) ↗", gActivePivotHigh, gCacheDistToBuy);
      gCacheFormacaoColor  = clrGold;
   }
   else if (gCacheDistToSell <= 45 && gCacheDistToSell > 0)
   {
      gCacheFormacaoStatus = StringFormat("Testando Fundo em %.2f (Faltam %.0f pts) ↘", gActivePivotLow, gCacheDistToSell);
      gCacheFormacaoColor  = clrGold;
   }
   else if (nL >= 2 && MathAbs(confirmedLows[nL-1].price - confirmedLows[nL-2].price) <= (150 * _Point) && close[0] > confirmedLows[nL-1].price)
   {
      gCacheFormacaoStatus = "Padrão W Empenado Armado (Acumulação Compradora) ↗";
      gCacheFormacaoColor  = clrSpringGreen;
   }
   else if (nH >= 2 && MathAbs(confirmedHighs[nH-1].price - confirmedHighs[nH-2].price) <= (150 * _Point) && close[0] < confirmedHighs[nH-1].price)
   {
      gCacheFormacaoStatus = "Padrão Topo Duplo M Armado (Pressão Vendedora) ↘";
      gCacheFormacaoColor  = clrLightCoral;
   }
   else
   {
      gCacheFormacaoStatus = "Consolidação Neutra no Miolo do Pivô";
      gCacheFormacaoColor  = clrLightGray;
   }

   // Ação Exata do Mentor
   bool isCurrentBald = (close[0] >= open[0]) ? (cLowerWick < InpMinWickPoints * 0.4) : (cUpperWick < InpMinWickPoints * 0.4);

   if (gLastSignalTime >= time[1])
   {
      if (gLastSignalType == "COMPRA")
      {
         gCacheAcaoMsg = "🚀 AÇÃO: EXECUTAR COMPRA! Rompimento confirmado com pavio!";
         gCacheAcaoTxt = clrLime;
         gCacheAcaoBg  = C'10,40,25';
      }
      else if (gLastSignalType == "VENDA")
      {
         gCacheAcaoMsg = "📉 AÇÃO: EXECUTAR VENDA! Perda de fundo confirmada com pavio!";
         gCacheAcaoTxt = clrMagenta;
         gCacheAcaoBg  = C'40,15,30';
      }
   }
   else if (gCacheDistToBuy <= 40 && gCacheDistToBuy > 0)
   {
      if (isCurrentBald)
      {
         gCacheAcaoMsg = "⛔ AÇÃO: NÃO COMPRAR! Vela careca em andamento (risco de armadilha)!";
         gCacheAcaoTxt = clrYellow;
         gCacheAcaoBg  = C'45,30,10';
      }
      else
      {
         gCacheAcaoMsg = StringFormat("⚠️ AÇÃO: PREPARAR COMPRA! Faltam %.0f pts para o Topo!", gCacheDistToBuy);
         gCacheAcaoTxt = clrGold;
         gCacheAcaoBg  = C'35,35,15';
      }
   }
   else if (gCacheDistToSell <= 40 && gCacheDistToSell > 0)
   {
      if (isCurrentBald)
      {
         gCacheAcaoMsg = "⛔ AÇÃO: NÃO VENDER! Vela careca em andamento (risco de armadilha)!";
         gCacheAcaoTxt = clrYellow;
         gCacheAcaoBg  = C'45,30,10';
      }
      else
      {
         gCacheAcaoMsg = StringFormat("⚠️ AÇÃO: PREPARAR VENDA! Faltam %.0f pts para o Fundo!", gCacheDistToSell);
         gCacheAcaoTxt = clrGold;
         gCacheAcaoBg  = C'35,35,15';
      }
   }
   else
   {
      gCacheAcaoMsg = "⏳ AÇÃO: AGUARDAR - Paciência institucional até o rompimento.";
      gCacheAcaoTxt = clrAqua;
      gCacheAcaoBg  = C'15,30,45';
   }

   DesenharOuAtualizarHUD();

   ChartRedraw();
   return rates_total;
}

//+------------------------------------------------------------------+
//| Traçado Visual das Linhas Geométricas dos Pivôs (V e W Empenado) |
//+------------------------------------------------------------------+
void DesenharEstruturaPivos(const SwingPoint &highs[], const SwingPoint &lows[])
{
   int nH = ArraySize(highs);
   int nL = ArraySize(lows);

   int maxP = 8;
   SwingPoint allPoints[];
   ArrayResize(allPoints, 0);

   for (int i = MathMax(0, nH - maxP); i < nH; i++)
   {
      int sz = ArraySize(allPoints);
      ArrayResize(allPoints, sz + 1);
      allPoints[sz] = highs[i];
   }
   for (int i = MathMax(0, nL - maxP); i < nL; i++)
   {
      int sz = ArraySize(allPoints);
      ArrayResize(allPoints, sz + 1);
      allPoints[sz] = lows[i];
   }

   int totalP = ArraySize(allPoints);
   for (int i = 0; i < totalP - 1; i++)
   {
      for (int j = 0; j < totalP - i - 1; j++)
      {
         if (allPoints[j].time > allPoints[j + 1].time)
         {
            SwingPoint tmp = allPoints[j];
            allPoints[j] = allPoints[j + 1];
            allPoints[j + 1] = tmp;
         }
      }
   }

   for (int i = 0; i < totalP - 1; i++)
   {
      if (allPoints[i].isHigh != allPoints[i + 1].isHigh)
      {
         string lineName = prefixObjects + "PV_ZIG_" + IntegerToString(i);
         CriarLinhaTendencia(lineName, allPoints[i].time, allPoints[i].price,
                             allPoints[i + 1].time, allPoints[i + 1].price,
                             InpPivotLineColor, STYLE_SOLID, InpPivotLineWidth);
      }
   }

   if (InpShowPivotBadges)
   {
      if (InpShowOnlyActiveBadges)
      {
         // MODO CIRÚRGICO: Apenas 2 rótulos no gráfico inteiro (Topo Ativo e Fundo Ativo)
         if (nH > 0)
         {
            string bHigh = prefixObjects + "BADGE_ACTIVE_H";
            string tHigh = StringFormat("▲ TOPO ATIVO (%.2f)", highs[nH - 1].price);
            CriarTextoGrafico(bHigh, highs[nH - 1].time, highs[nH - 1].price + (15 * _Point), tHigh, clrGold, 8, true);
         }
         if (nL > 0)
         {
            string bLow = prefixObjects + "BADGE_ACTIVE_L";
            bool isW = false;
            if (nL >= 2 && MathAbs(lows[nL-1].price - lows[nL-2].price) <= (150 * _Point))
               isW = true;

            string tLow = isW ? StringFormat("▼ W EMPENADO (%.2f)", lows[nL - 1].price) : StringFormat("▼ FUNDO ATIVO (%.2f)", lows[nL - 1].price);
            color  cLow = isW ? clrSpringGreen : clrDeepSkyBlue;
            CriarTextoGrafico(bLow, lows[nL - 1].time, lows[nL - 1].price - (15 * _Point), tLow, cLow, 8, true);
         }
      }
      else
      {
         // Modo completo com rótulos compactos e discretos
         for (int i = 0; i < totalP; i++)
         {
            string badgeName = prefixObjects + "BADGE_" + IntegerToString(i);
            string textBadge;
            color  badgeColor;

            if (allPoints[i].isHigh)
            {
               textBadge = StringFormat("▲ %.2f", allPoints[i].price);
               badgeColor = clrGold;
               CriarTextoGrafico(badgeName, allPoints[i].time, allPoints[i].price + (12 * _Point), textBadge, badgeColor, 7, false);
            }
            else
            {
               textBadge = StringFormat("▼ %.2f", allPoints[i].price);
               badgeColor = clrDeepSkyBlue;
               CriarTextoGrafico(badgeName, allPoints[i].time, allPoints[i].price - (12 * _Point), textBadge, badgeColor, 7, false);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Linhas Projetadas de Gatilho de Rompimento com Indicação de Lado |
//+------------------------------------------------------------------+
void AtualizarLinhasDeGatilho(datetime curTime, double curClose)
{
   datetime projTime  = curTime + (PeriodSeconds() * 16);
   datetime labelTime = curTime + (PeriodSeconds() * 4); // Projetado à frente dos candles, no espaço livre!

   string lineBuyName  = prefixObjects + "LINE_TRIGGER_BUY";
   string labelBuyName = prefixObjects + "LBL_TRIGGER_BUY";
   string arrowBuyName = prefixObjects + "ARW_TRIGGER_BUY";

   CriarLinhaTendencia(lineBuyName, gActiveHighTime, gActivePivotHigh, projTime, gActivePivotHigh,
                       InpColorTriggerBuy, STYLE_SOLID, InpTriggerLineWidth);

   double distBuyPts = (gActivePivotHigh - curClose) / _Point;
   string txtBuy = (distBuyPts > 0) ?
                   StringFormat("⚡ GATILHO COMPRA: %.2f ↗ [Faltam %.0f pts]", gActivePivotHigh, distBuyPts) :
                   StringFormat("⚡ GATILHO COMPRA: ROMPENDO AGORA (%.2f) ↗", gActivePivotHigh);

   if (InpShowDirectionSign)
   {
      CriarTextoGrafico(labelBuyName, labelTime, gActivePivotHigh + (8 * _Point), txtBuy, InpColorTriggerBuy, 8, true);
      CriarSetaGrafica(arrowBuyName, projTime, gActivePivotHigh, 241, InpColorTriggerBuy);
   }

   string lineSellName  = prefixObjects + "LINE_TRIGGER_SELL";
   string labelSellName = prefixObjects + "LBL_TRIGGER_SELL";
   string arrowSellName = prefixObjects + "ARW_TRIGGER_SELL";

   CriarLinhaTendencia(lineSellName, gActiveLowTime, gActivePivotLow, projTime, gActivePivotLow,
                       InpColorTriggerSell, STYLE_SOLID, InpTriggerLineWidth);

   double distSellPts = (curClose - gActivePivotLow) / _Point;
   string txtSell = (distSellPts > 0) ?
                    StringFormat("⚡ GATILHO VENDA: %.2f ↘ [Faltam %.0f pts]", gActivePivotLow, distSellPts) :
                    StringFormat("⚡ GATILHO VENDA: PERDENDO AGORA (%.2f) ↘", gActivePivotLow);

   if (InpShowDirectionSign)
   {
      CriarTextoGrafico(labelSellName, labelTime, gActivePivotLow - (18 * _Point), txtSell, InpColorTriggerSell, 8, true);
      CriarSetaGrafica(arrowSellName, projTime, gActivePivotLow, 242, InpColorTriggerSell);
   }
}

//+------------------------------------------------------------------+
//| Traçado de Linhas Operacionais (Entrada, Stop, Alvo 3:1)         |
//+------------------------------------------------------------------+
void DesenharLinhasOperacionais(string tipo, double entrada, double stop, double alvo)
{
   string nameEntry  = prefixObjects + "EXEC_ENTRY";
   string nameStop   = prefixObjects + "EXEC_STOP";
   string nameTarget = prefixObjects + "EXEC_TARGET";

   datetime tStart = (gLastSignalTime > 0) ? gLastSignalTime : TimeCurrent();
   datetime tEnd   = TimeCurrent() + (PeriodSeconds() * 16);

   CriarLinhaTendencia(nameEntry, tStart, entrada, tEnd, entrada, InpColorEntry, STYLE_SOLID, 2);
   CriarLinhaTendencia(nameStop, tStart, stop, tEnd, stop, InpColorStop, STYLE_DASH, 2);
   CriarLinhaTendencia(nameTarget, tStart, alvo, tEnd, alvo, InpColorTarget, STYLE_SOLID, 2);
}

void CriarLinhaTendencia(string name, datetime t1, double p1, datetime t2, double p2, color clr, ENUM_LINE_STYLE style, int width)
{
   if (ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   else
   {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   }
}

void CriarLinhaHorizontal(string name, double price, color clr, ENUM_LINE_STYLE style, int width, string desc)
{
   if (ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetString(0, name, OBJPROP_TEXT, desc);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   else
   {
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
      ObjectSetString(0, name, OBJPROP_TEXT, desc);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   }
}

void CriarTextoGrafico(string name, datetime t, double p, string text, color clr, int fontSize, bool isBold)
{
   if (ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   }
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, isBold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
}

void CriarSetaGrafica(string name, datetime t, double p, int arrowCode, color clr)
{
   if (ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_ARROW, 0, t, p);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
   }
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}

void DispararAlerta(string tipo, double entrada, double stop, double alvo)
{
   double riscoPts = MathAbs(entrada - stop) / _Point;
   double alvoPts  = MathAbs(alvo - entrada) / _Point;
   double riscoUSD = (riscoPts * _Point) * 100.0 * InpLotSize;
   double alvoUSD  = (alvoPts * _Point) * 100.0 * InpLotSize;

   string msg = StringFormat("MENTOR PRICE ACTION [%s]: Sinal de %s!\nEntrada: %s\nStop: %s (-$%.2f)\nAlvo 3:1: %s (+$%.2f)",
                             _Symbol, tipo,
                             DoubleToString(entrada, _Digits),
                             DoubleToString(stop, _Digits), riscoUSD,
                             DoubleToString(alvo, _Digits), alvoUSD);

   if (InpAlertPopup)
      Alert(msg);
   if (InpAlertSound && InpSoundFile != "")
      PlaySound(InpSoundFile);
   if (InpAlertPush)
      SendNotification(msg);
}

//+------------------------------------------------------------------+
//| Atualização Dinâmica do HUD com Enquadramento Seguro e Sem Ticks |
//+------------------------------------------------------------------+
void DesenharOuAtualizarHUD()
{
   int baseWidth  = panelMinimized ? 220 : (gShowLegend ? 440 : 380);
   int baseHeight = panelMinimized ? 34  : (gShowLegend ? 425 : 290);

   int width  = sW(baseWidth);
   int height = sH(baseHeight);
   int hdrH   = sH(30);
   int lineH  = sH(23);

   // 1. Fundo do Painel
   CriarOuAtualizarRetanguloHUD(prefixObjects + "HUD_BG", panelX, panelY, width, height, C'13,19,33', C'56,189,248');

   // 2. Cabeçalho Arrastável
   CriarOuAtualizarRetanguloHUD(prefixObjects + "HUD_HDR", panelX, panelY, width, hdrH, C'26,36,54', C'71,85,105');

   // Título com Escala
   string titleText = panelMinimized ? "📊 MENTOR PA" : StringFormat("📊 MENTOR PA (x%.2f)", gPanelScale);
   CriarOuAtualizarLabelHUD(prefixObjects + "HUD_TITLE", panelX + sW(10), panelY + sH(7), titleText, clrDeepSkyBlue, sF(gBaseFontSize), true);

   // Botões do Cabeçalho: [📖 Guia] [A-] [A+] [- / +]
   int btnW = sW(26);
   int btnH = sH(19);
   int curBtnX = panelX + width - sW(8) - btnW;

   // Botão Minimizar [-] / [+]
   string minLabel = panelMinimized ? "[+]" : "[-]";
   CriarOuAtualizarBotaoHUD(prefixObjects + "BTN_MIN", curBtnX, panelY + sH(5), btnW, btnH, minLabel, clrYellow, C'45,55,75', sF(8));
   curBtnX -= (btnW + sW(4));

   // Botão Zoom Mais [A+]
   CriarOuAtualizarBotaoHUD(prefixObjects + "BTN_ZOOM_IN", curBtnX, panelY + sH(5), btnW, btnH, "A+", clrWhite, C'45,55,75', sF(8));
   curBtnX -= (btnW + sW(4));

   // Botão Zoom Menos [A-]
   CriarOuAtualizarBotaoHUD(prefixObjects + "BTN_ZOOM_OUT", curBtnX, panelY + sH(5), btnW, btnH, "A-", clrWhite, C'45,55,75', sF(8));
   curBtnX -= (sW(42) + sW(4));

   // Botão Sumário / Guia de Cores [📖]
   string legLabel = gShowLegend ? "📖 Fechar" : "📖 Guia";
   color  legBg    = gShowLegend ? clrDodgerBlue : C'45,55,75';
   CriarOuAtualizarBotaoHUD(prefixObjects + "BTN_LEGEND", curBtnX, panelY + sH(5), sW(42), btnH, legLabel, clrAqua, legBg, sF(8));

   // Se estiver minimizado, oculta o interior e encerra
   if (panelMinimized)
   {
      LimparTodosLabelsHUD();
      return;
   }

   // Calcular tempo restante do candle atual
   datetime barT = (gCacheTimeBar > 0) ? gCacheTimeBar : TimeCurrent();
   datetime nowT = TimeCurrent();
   int elapsedSec = (int)(nowT - barT);
   int remainSec  = PeriodSeconds() - elapsedSec;
   if (remainSec < 0) remainSec = 0;
   string timerStr = StringFormat("%02d:%02d", remainSec / 60, remainSec % 60);

   double distEmaPts = (gCachePrice - gCacheEma) / _Point;
   string trendStr   = (gCachePrice >= gCacheEma) ? "ALTA (Acima da 200)" : "BAIXA (Abaixo da 200)";
   color  trendClr   = (gCachePrice >= gCacheEma) ? clrLimeGreen : clrCrimson;

   // Renderização das Linhas Internas com Espaçamento e Enquadramento Garantidos
   int curY = panelY + hdrH + sH(6);

   // Linha 1: Gestão de Banca
   CriarOuAtualizarLabelHUD(prefixObjects + "L1", panelX + sW(12), curY,
                           StringFormat("💰 BANCA: $%.0f | LOTE SEGURO: %.2f", InpAccountBalance, InpLotSize), clrYellow, sF(gBaseFontSize), true);
   curY += lineH;

   // Linha 2: Média 200 & Tendência
   CriarOuAtualizarLabelHUD(prefixObjects + "L2", panelX + sW(12), curY,
                           StringFormat("📈 200 EMA: %s | Dist: %+.0f pts", trendStr, distEmaPts), trendClr, sF(gBaseFontSize), false);
   curY += lineH;

   // Linha 3: Monitoramento do Candle Atual (Barra 0)
   CriarOuAtualizarLabelHUD(prefixObjects + "L3", panelX + sW(12), curY,
                           StringFormat("⏱️ Vela [%s]: %s | %s", timerStr, (_Period == PERIOD_M1 ? "M1" : (_Period == PERIOD_M5 ? "M5" : "TF")), gCacheWickStr), gCacheWickColor, sF(gBaseFontSize), true);
   curY += lineH;

   // Linha 4: Formação em Andamento
   CriarOuAtualizarLabelHUD(prefixObjects + "L4", panelX + sW(12), curY,
                           "🔍 Em Andamento: " + gCacheFormacaoStatus, gCacheFormacaoColor, sF(gBaseFontSize), false);
   curY += lineH;

   // Linha 5: Gatilho Projetado
   string gatilhoStr = (gCacheDistToBuy <= 150) ? StringFormat("⚡ Rompimento Alta: %.2f (Faltam %.0f pts) ↗", gActivePivotHigh, gCacheDistToBuy) :
                       ((gCacheDistToSell <= 150) ? StringFormat("⚡ Rompimento Baixa: %.2f (Faltam %.0f pts) ↘", gActivePivotLow, gCacheDistToSell) :
                       "⚡ Gatilho: Aguardando aproximação da linha projetada");
   CriarOuAtualizarLabelHUD(prefixObjects + "L5", panelX + sW(12), curY, gatilhoStr, clrGold, sF(gBaseFontSize), true);
   curY += lineH;

   // Linha 6: Sinal
   if (gLastSignalType != "AGUARDANDO")
   {
      double riscoUSD = MathAbs(gLastEntryPrice - gLastStopLoss) * 100.0 * InpLotSize;
      double alvoUSD  = MathAbs(gLastTakeProfit - gLastEntryPrice) * 100.0 * InpLotSize;

      CriarOuAtualizarLabelHUD(prefixObjects + "L6", panelX + sW(12), curY,
                              StringFormat("Sinal: %s | Stop: %s (-$%.2f) | Alvo: %s (+$%.2f)",
                                           gLastSignalType, DoubleToString(gLastStopLoss, _Digits), riscoUSD,
                                           DoubleToString(gLastTakeProfit, _Digits), alvoUSD), clrSpringGreen, sF(gBaseFontSize - 1), false);
   }
   else
   {
      CriarOuAtualizarLabelHUD(prefixObjects + "L6", panelX + sW(12), curY,
                              "Regra de Ouro: Proibido operar vela careca sem pavio prévio!", clrAqua, sF(gBaseFontSize - 1), false);
   }
   curY += lineH;

   // Linha 7: CAIXA DE AÇÃO EXATA DO MENTOR
   int boxH = sH(28);
   CriarOuAtualizarRetanguloHUD(prefixObjects + "BOX_ACAO", panelX + sW(8), curY, width - sW(16), boxH, gCacheAcaoBg, gCacheAcaoTxt);
   CriarOuAtualizarLabelHUD(prefixObjects + "L_ACAO", panelX + sW(14), curY + sH(6), gCacheAcaoMsg, gCacheAcaoTxt, sF(gBaseFontSize), true);
   curY += boxH + sH(6);

   // Linha 8: Disciplina da Meta
   CriarOuAtualizarLabelHUD(prefixObjects + "L_META", panelX + sW(12), curY,
                           "🔒 Bateu a meta (+10$ a +20$)? FECHE O METATRADER 5!", clrOrange, sF(gBaseFontSize - 1), true);
   curY += lineH;

   // SEÇÃO EXPANSÍVEL: SUMÁRIO E LEGENDA DAS CORES [📖 GUIA]
   if (gShowLegend)
   {
      CriarOuAtualizarRetanguloHUD(prefixObjects + "LEG_BG", panelX + sW(8), curY, width - sW(16), sH(125), C'18,25,38', C'71,85,105');
      int legY = curY + sH(6);

      CriarOuAtualizarLabelHUD(prefixObjects + "LEG_TITLE", panelX + sW(14), legY, "📖 SUMÁRIO OFICIAL DE CORES E SINAIS:", clrAqua, sF(gBaseFontSize), true);
      legY += sH(18);

      CriarOuAtualizarLabelHUD(prefixObjects + "LEG_1", panelX + sW(14), legY, "🟢 Verde Neon: Rompimento Compra ↗ (Corpo sobre Topo + Pavio)", clrLime, sF(gBaseFontSize - 1), false);
      legY += sH(16);

      CriarOuAtualizarLabelHUD(prefixObjects + "LEG_2", panelX + sW(14), legY, "🟣 Magenta: Rompimento Venda ↘ (Corpo sob Fundo + Pavio)", clrMagenta, sF(gBaseFontSize - 1), false);
      legY += sH(16);

      CriarOuAtualizarLabelHUD(prefixObjects + "LEG_3", panelX + sW(14), legY, "🟡 Dourado: Candle com Pavio Válido (Mola Armada) / Linha Compra", clrGold, sF(gBaseFontSize - 1), false);
      legY += sH(16);

      CriarOuAtualizarLabelHUD(prefixObjects + "LEG_4", panelX + sW(14), legY, "🔘 Cinza Escuro: Vela Careca / Armadilha (NÃO OPERAR!)", clrDimGray, sF(gBaseFontSize - 1), true);
      legY += sH(16);

      CriarOuAtualizarLabelHUD(prefixObjects + "LEG_5", panelX + sW(14), legY, "🟦 Ciano Grosso: Estrutura Zigue-Zague | 🔵 Média 200: Alvo Ímã", clrDeepSkyBlue, sF(gBaseFontSize - 1), false);
      legY += sH(16);

      CriarOuAtualizarLabelHUD(prefixObjects + "LEG_6", panelX + sW(14), legY, "⚡ Linha Projetada: Nível Exato onde vai romper + Seta Direcional", clrYellow, sF(gBaseFontSize - 1), false);
   }
   else
   {
      ApagarElementoHUD(prefixObjects + "LEG_BG");
      ApagarElementoHUD(prefixObjects + "LEG_TITLE");
      for (int k = 1; k <= 6; k++)
         ApagarElementoHUD(prefixObjects + "LEG_" + IntegerToString(k));
   }
}

//+------------------------------------------------------------------+
//| Limpeza dos Labels Internos                                      |
//+------------------------------------------------------------------+
void LimparTodosLabelsHUD()
{
   for (int k = 1; k <= 6; k++)
      ApagarElementoHUD(prefixObjects + "L" + IntegerToString(k));

   ApagarElementoHUD(prefixObjects + "BOX_ACAO");
   ApagarElementoHUD(prefixObjects + "L_ACAO");
   ApagarElementoHUD(prefixObjects + "L_META");

   ApagarElementoHUD(prefixObjects + "LEG_BG");
   ApagarElementoHUD(prefixObjects + "LEG_TITLE");
   for (int k = 1; k <= 6; k++)
      ApagarElementoHUD(prefixObjects + "LEG_" + IntegerToString(k));
}

//+------------------------------------------------------------------+
//| Tratamento de Eventos do Gráfico (Arrastar, Zoom e Sumário)      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // 1. CLIQUE EM BOTÕES DO PAINEL
   if (id == CHARTEVENT_OBJECT_CLICK)
   {
      if (sparam == prefixObjects + "BTN_MIN")
      {
         panelMinimized = !panelMinimized;
         ObjectSetInteger(0, prefixObjects + "BTN_MIN", OBJPROP_STATE, false);
         LimparTodosLabelsHUD();
         DesenharOuAtualizarHUD();
         ChartRedraw();
         return;
      }
      else if (sparam == prefixObjects + "BTN_LEGEND")
      {
         gShowLegend = !gShowLegend;
         ObjectSetInteger(0, prefixObjects + "BTN_LEGEND", OBJPROP_STATE, false);
         LimparTodosLabelsHUD();
         DesenharOuAtualizarHUD();
         ChartRedraw();
         return;
      }
      else if (sparam == prefixObjects + "BTN_ZOOM_IN")
      {
         gPanelScale += 0.15;
         if (gPanelScale > 2.0) gPanelScale = 2.0;
         ObjectSetInteger(0, prefixObjects + "BTN_ZOOM_IN", OBJPROP_STATE, false);
         LimparTodosLabelsHUD();
         DesenharOuAtualizarHUD();
         ChartRedraw();
         return;
      }
      else if (sparam == prefixObjects + "BTN_ZOOM_OUT")
      {
         gPanelScale -= 0.15;
         if (gPanelScale < 0.75) gPanelScale = 0.75;
         ObjectSetInteger(0, prefixObjects + "BTN_ZOOM_OUT", OBJPROP_STATE, false);
         LimparTodosLabelsHUD();
         DesenharOuAtualizarHUD();
         ChartRedraw();
         return;
      }
   }

   // 2. ARRASTAR O PAINEL COM O MOUSE (DRAG & DROP REAL FLUIDO)
   if (id == CHARTEVENT_MOUSE_MOVE)
   {
      int mouseX = (int)lparam;
      int mouseY = (int)dparam;
      uint mouseFlags = (uint)sparam;

      bool leftButtonDown = (mouseFlags & 1) != 0;

      if (leftButtonDown && !isDragging)
      {
         int w = sW(panelMinimized ? 220 : (gShowLegend ? 440 : 380));
         int hdrH = sH(30);

         // Clicou no cabeçalho fora dos botões?
         if (mouseX >= panelX && mouseX <= panelX + w &&
             mouseY >= panelY && mouseY <= panelY + hdrH)
         {
            if (mouseX < panelX + w - sW(120)) // Área do título
            {
               isDragging = true;
               dragOffsetX = mouseX - panelX;
               dragOffsetY = mouseY - panelY;
            }
         }
      }
      else if (leftButtonDown && isDragging)
      {
         panelX = mouseX - dragOffsetX;
         panelY = mouseY - dragOffsetY;

         int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
         int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

         if (panelX < 5) panelX = 5;
         if (panelY < 15) panelY = 15;
         if (panelX > chartW - 100) panelX = chartW - 100;
         if (panelY > chartH - 50)  panelY = chartH - 50;

         DesenharOuAtualizarHUD();
         ChartRedraw();
      }
      else if (!leftButtonDown && isDragging)
      {
         isDragging = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Auxiliares Gráficos Ultra-Rápidos sem Recriação Desnecessária    |
//+------------------------------------------------------------------+
void CriarOuAtualizarRetanguloHUD(string name, int x, int y, int w, int h, color bgClr, color borderClr)
{
   if (ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, borderClr);
}

void CriarOuAtualizarLabelHUD(string name, int x, int y, string text, color clr, int fontSize, bool isBold)
{
   if (ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, isBold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void CriarOuAtualizarBotaoHUD(string name, int x, int y, int w, int h, string text, color txtClr, color bgClr, int fontSize = 8)
{
   if (ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtClr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
}

void ApagarElementoHUD(string name)
{
   if (ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
}

void CalculateDirectEma(int total, const double &close[])
{
   double k = 2.0 / (InpEmaPeriod + 1.0);
   int start = MathMin(total - 1, InpMaxHistoryBars);

   BufferEMA200[start] = close[start];
   for (int i = start - 1; i >= 0; i--)
   {
      BufferEMA200[i] = (close[i] * k) + (BufferEMA200[i + 1] * (1.0 - k));
   }
}
//+------------------------------------------------------------------+
