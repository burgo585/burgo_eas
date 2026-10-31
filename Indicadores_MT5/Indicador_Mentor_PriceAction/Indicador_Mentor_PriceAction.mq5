//+------------------------------------------------------------------+
//|                                   Indicador_Mentor_PriceAction.mq5|
//|                             Metodologia Mentor Price Action Pro |
//|                                 Burgo585 - Price Action & Pivôs  |
//+------------------------------------------------------------------+
#property copyright "Burgo585 & O Mentor"
#property link      "https://github.com/burgo585/burgo_eas"
#property version   "3.50"
#property description "Indicador Oficial de Price Action Puro do Mentor (Versão 3.50 Pro)"
#property description "- Traçado Estrutural Hiper-Visível da Geometria dos Pivôs (V e W Empenado)"
#property description "- Linha Projetada de Gatilho de Rompimento com Nível e Direção (↗ / ↘)"
#property description "- Coloração Inteligente de Candles (Rompimento, Pavios de Setup e Vela Careca)"
#property description "- Painel HUD Auto-Escalável [A+ / A-] com Sumário de Cores [📖] e Enquadramento Seguro"
#property description "- Monitoramento em Tempo Real do Candle 0, Pavio, Tempo e Ação Imediata"
#property description "- Otimizado para Contas Pequenas ($300 - Lote 0.01)"

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
#property indicator_width2  4

//--- Plot 3: Seta de Venda
#property indicator_label3  "Venda Pivô (Gatilho)"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrMagenta
#property indicator_width3  4

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
input double             InpPanelScale        = 1.0;              // Escala Geral do Painel (0.75 a 2.0)
input int                InpBaseFontSize      = 9;                // Tamanho Base da Fonte (8 a 16)
input bool               InpShowLegendAtStart = false;            // Iniciar com Sumário de Cores Aberto [📖]

input group "=== CONFIGURAÇÃO DA MÉDIA DE 200 (BÚSSOLA) ==="
input int                InpEmaPeriod         = 200;              // Período da Média
input ENUM_EMA_TYPE      InpEmaMethod         = EMA_EXPONENCIAL;  // Tipo de Média Móvel
input ENUM_APPLIED_PRICE InpEmaApplied        = PRICE_CLOSE;      // Preço Aplicado

input group "=== ESTRUTURA VISUAL DOS PIVÔS (V E W EMPENADO) ==="
input int                InpSwingStrength     = 2;                // Sensibilidade dos Swings (2=Dinâmico, 3=Conservador)
input int                InpMaxHistoryBars    = 600;              // Histórico de Barras Avaliadas
input bool               InpDrawPivotLines    = true;             // Desenhar Zigue-Zague Estrutural do Pivô
input color              InpPivotLineColor    = clrCyan;          // Cor da Estrutura do Pivô
input int                InpPivotLineWidth    = 3;                // Espessura da Estrutura (1 a 5)
input bool               InpShowPivotBadges   = true;             // Exibir Rótulos nos Topos (H) e Fundos (L)

input group "=== LINHA DE GATILHO DE ROMPIMENTO E DIREÇÃO ==="
input bool               InpShowTriggerLines  = true;             // Exibir Linhas de Rompimento Projetadas
input color              InpColorTriggerBuy   = clrGold;          // Cor da Linha de Gatilho de Compra
input color              InpColorTriggerSell  = clrDeepPink;      // Cor da Linha de Gatilho de Venda
input int                InpTriggerLineWidth  = 2;                // Espessura da Linha de Rompimento
input bool               InpShowDirectionSign = true;             // Exibir Setas e Texto de Direção na Linha

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
void AtualizarPainelHUD(double price, double emaVal, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], int nH, int nL, const SwingPoint &highs[], const SwingPoint &lows[]);
void LimparTodosLabelsHUD();
void CriarRetanguloHUD(string name, int x, int y, int w, int h, color bgClr, color borderClr);
void CriarLabelHUD(string name, int x, int y, string text, color clr, int fontSize, bool isBold);
void CriarBotaoHUD(string name, int x, int y, int w, int h, string text, color txtClr, color bgClr, int fontSize = 8);
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

   PlotIndexSetInteger(1, PLOT_ARROW, 233); // Seta de Compra
   PlotIndexSetInteger(2, PLOT_ARROW, 234); // Seta de Venda
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);

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

   string shortName = StringFormat("Mentor Price Action v3.50 Pro (EMA %d | 3:1)", InpEmaPeriod);
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

   int limit = InpMaxHistoryBars;
   if (limit > rates_total - InpSwingStrength - 5)
      limit = rates_total - InpSwingStrength - 5;

   for (int i = 0; i <= limit; i++)
   {
      BufferBuy[i]  = 0.0;
      BufferSell[i] = 0.0;

      if (InpColorizeCandles)
      {
         BufferCandleOpen[i]  = open[i];
         BufferCandleHigh[i]  = high[i];
         BufferCandleLow[i]   = low[i];
         BufferCandleClose[i] = close[i];
         BufferCandleColor[i] = (close[i] >= open[i]) ? 0.0 : 1.0;
      }
   }

   ObjectsDeleteAll(0, prefixObjects + "PV_");
   ObjectsDeleteAll(0, prefixObjects + "BADGE_");

   SwingPoint confirmedHighs[];
   SwingPoint confirmedLows[];
   ArrayResize(confirmedHighs, 0);
   ArrayResize(confirmedLows, 0);

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
            ArrayResize(confirmedHighs, sz + 1);
            confirmedHighs[sz].time     = time[swBar];
            confirmedHighs[sz].price    = hVal;
            confirmedHighs[sz].barIndex = swBar;
            confirmedHighs[sz].isHigh   = true;
         }

         if (isL)
         {
            int sz = ArraySize(confirmedLows);
            ArrayResize(confirmedLows, sz + 1);
            confirmedLows[sz].time     = time[swBar];
            confirmedLows[sz].price    = lVal;
            confirmedLows[sz].barIndex = swBar;
            confirmedLows[sz].isHigh   = false;
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
               BufferCandleColor[i] = 5.0; // Vela Careca de Alta (Cinza / Alerta)
            else if (cOpen > cClose && upperWick < (minWick * 0.4) && (cClose - cLow) < (minWick * 0.4))
               BufferCandleColor[i] = 5.0; // Vela Careca de Baixa
            else if (cClose > cOpen && lowerWick >= minWick)
               BufferCandleColor[i] = 4.0; // Pavio de Setup Válido (Dourado)
            else if (cOpen > cClose && upperWick >= minWick)
               BufferCandleColor[i] = 4.0;
         }

         // Gatilho de Compra
         if (cClose > lastHigh && (cOpen <= lastHigh || cLow <= lastHigh) && (cClose - cOpen) >= minBody)
         {
            if (lowerWick >= minWick)
            {
               double stopLoss = lastLow - (15 * _Point);
               double risk     = cClose - stopLoss;

               if (risk >= (25 * _Point))
               {
                  double takeProfit = cClose + (risk * InpRiskRewardRatio);

                  BufferBuy[i]        = cLow - (20 * _Point);
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

         // Gatilho de Venda
         if (cClose < lastLow && (cOpen >= lastLow || cHigh >= lastLow) && (cOpen - cClose) >= minBody)
         {
            if (upperWick >= minWick)
            {
               double stopLoss = lastHigh + (15 * _Point);
               double risk     = stopLoss - cClose;

               if (risk >= (25 * _Point))
               {
                  double takeProfit = cClose - (risk * InpRiskRewardRatio);

                  BufferSell[i]       = cHigh + (20 * _Point);
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

   AtualizarPainelHUD(close[0], BufferEMA200[0], time, open, high, low, close, nH, nL, confirmedHighs, confirmedLows);

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
      for (int i = 0; i < totalP; i++)
      {
         string badgeName = prefixObjects + "BADGE_" + IntegerToString(i);
         string textBadge;
         color  badgeColor;

         if (allPoints[i].isHigh)
         {
            textBadge = StringFormat("▲ TOPO (H: %.2f)", allPoints[i].price);
            badgeColor = clrGold;
            CriarTextoGrafico(badgeName, allPoints[i].time, allPoints[i].price + (15 * _Point), textBadge, badgeColor, 8, true);
         }
         else
         {
            bool isW = false;
            if (i >= 2 && !allPoints[i-2].isHigh && MathAbs(allPoints[i].price - allPoints[i-2].price) <= (150 * _Point))
               isW = true;

            textBadge = isW ? StringFormat("▼ W EMPENADO (L: %.2f)", allPoints[i].price) : StringFormat("▼ FUNDO (L: %.2f)", allPoints[i].price);
            badgeColor = isW ? clrSpringGreen : clrDeepSkyBlue;
            CriarTextoGrafico(badgeName, allPoints[i].time, allPoints[i].price - (15 * _Point), textBadge, badgeColor, 8, true);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Linhas Projetadas de Gatilho de Rompimento com Indicação de Lado |
//+------------------------------------------------------------------+
void AtualizarLinhasDeGatilho(datetime curTime, double curClose)
{
   datetime projTime = curTime + (PeriodSeconds() * 8);

   string lineBuyName  = prefixObjects + "LINE_TRIGGER_BUY";
   string labelBuyName = prefixObjects + "LBL_TRIGGER_BUY";
   string arrowBuyName = prefixObjects + "ARW_TRIGGER_BUY";

   CriarLinhaTendencia(lineBuyName, gActiveHighTime, gActivePivotHigh, projTime, gActivePivotHigh,
                       InpColorTriggerBuy, STYLE_SOLID, InpTriggerLineWidth);

   double distBuyPts = (gActivePivotHigh - curClose) / _Point;
   string txtBuy = (distBuyPts > 0) ?
                   StringFormat("⚡ GATILHO COMPRA PIVÔ: Romper %.2f ↗ (Faltam %.0f pts) -> Alvo: Média 200 / 3:1", gActivePivotHigh, distBuyPts) :
                   StringFormat("⚡ GATILHO COMPRA PIVÔ: ROMPENDO AGORA (%.2f) ↗ -> SEGUIR COMPRA!", gActivePivotHigh);

   if (InpShowDirectionSign)
   {
      CriarTextoGrafico(labelBuyName, curTime + (PeriodSeconds() * 2), gActivePivotHigh + (8 * _Point), txtBuy, InpColorTriggerBuy, 9, true);
      CriarSetaGrafica(arrowBuyName, projTime, gActivePivotHigh, 241, InpColorTriggerBuy);
   }

   string lineSellName  = prefixObjects + "LINE_TRIGGER_SELL";
   string labelSellName = prefixObjects + "LBL_TRIGGER_SELL";
   string arrowSellName = prefixObjects + "ARW_TRIGGER_SELL";

   CriarLinhaTendencia(lineSellName, gActiveLowTime, gActivePivotLow, projTime, gActivePivotLow,
                       InpColorTriggerSell, STYLE_SOLID, InpTriggerLineWidth);

   double distSellPts = (curClose - gActivePivotLow) / _Point;
   string txtSell = (distSellPts > 0) ?
                    StringFormat("⚡ GATILHO VENDA PIVÔ: Romper %.2f ↘ (Faltam %.0f pts) -> Alvo: Suporte / 3:1", gActivePivotLow, distSellPts) :
                    StringFormat("⚡ GATILHO VENDA PIVÔ: PERDENDO AGORA (%.2f) ↘ -> SEGUIR VENDA!", gActivePivotLow);

   if (InpShowDirectionSign)
   {
      CriarTextoGrafico(labelSellName, curTime + (PeriodSeconds() * 2), gActivePivotLow - (18 * _Point), txtSell, InpColorTriggerSell, 9, true);
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

   CriarLinhaHorizontal(nameEntry, entrada, InpColorEntry, STYLE_SOLID, 2, "ENTRADA (" + tipo + "): " + DoubleToString(entrada, _Digits));
   CriarLinhaHorizontal(nameStop, stop, InpColorStop, STYLE_DASH, 2, "STOP TÉCNICO: " + DoubleToString(stop, _Digits));
   CriarLinhaHorizontal(nameTarget, alvo, InpColorTarget, STYLE_SOLID, 2, "ALVO 3:1 DO MENTOR: " + DoubleToString(alvo, _Digits));
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
   }
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, isBold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void CriarSetaGrafica(string name, datetime t, double p, int arrowCode, color clr)
{
   if (ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_ARROW, 0, t, p);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
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
//| Painel Visual HUD Auto-Escalável e Enquadrado                    |
//+------------------------------------------------------------------+
void AtualizarPainelHUD(double price, double emaVal,
                        const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[],
                        int nH, int nL, const SwingPoint &highs[], const SwingPoint &lows[])
{
   int baseWidth  = panelMinimized ? 240 : (gShowLegend ? 460 : 400);
   int baseHeight = panelMinimized ? 40  : (gShowLegend ? 430 : 295);

   int width  = sW(baseWidth);
   int height = sH(baseHeight);
   int hdrH   = sH(32);
   int lineH  = sH(23);

   // 1. Fundo do Painel
   string bgName = prefixObjects + "HUD_BG";
   CriarRetanguloHUD(bgName, panelX, panelY, width, height, C'13,19,33', C'56,189,248');

   // 2. Barra de Título (Cabeçalho Arrastável)
   string hdrName = prefixObjects + "HUD_HDR";
   CriarRetanguloHUD(hdrName, panelX, panelY, width, hdrH, C'26,36,54', C'71,85,105');

   // Título com Escala
   string titleText = panelMinimized ? "📊 MENTOR PA" : StringFormat("📊 MENTOR PA PRO (x%.2f)", gPanelScale);
   CriarLabelHUD(prefixObjects + "HUD_TITLE", panelX + sW(10), panelY + sH(7), titleText, clrDeepSkyBlue, sF(gBaseFontSize), true);

   // Botões do Cabeçalho: [📖 GUIA] [A-] [A+] [- / +]
   int btnW = sW(28);
   int btnH = sH(20);
   int curBtnX = panelX + width - sW(10) - btnW;

   // Botão Minimizar [-] / [+]
   string minLabel = panelMinimized ? "[+]" : "[-]";
   CriarBotaoHUD(prefixObjects + "BTN_MIN", curBtnX, panelY + sH(6), btnW, btnH, minLabel, clrYellow, C'45,55,75', sF(8));
   curBtnX -= (btnW + sW(4));

   // Botão Zoom Mais [A+]
   CriarBotaoHUD(prefixObjects + "BTN_ZOOM_IN", curBtnX, panelY + sH(6), btnW, btnH, "A+", clrWhite, C'45,55,75', sF(8));
   curBtnX -= (btnW + sW(4));

   // Botão Zoom Menos [A-]
   CriarBotaoHUD(prefixObjects + "BTN_ZOOM_OUT", curBtnX, panelY + sH(6), btnW, btnH, "A-", clrWhite, C'45,55,75', sF(8));
   curBtnX -= (sW(36) + sW(4));

   // Botão Sumário / Guia de Cores [📖]
   string legLabel = gShowLegend ? "📖 Fechar" : "📖 Guia";
   color  legBg    = gShowLegend ? clrDodgerBlue : C'45,55,75';
   CriarBotaoHUD(prefixObjects + "BTN_LEGEND", curBtnX, panelY + sH(6), sW(36), btnH, legLabel, clrAqua, legBg, sF(8));

   // Se estiver minimizado, limpa o interior e encerra
   if (panelMinimized)
   {
      LimparTodosLabelsHUD();
      return;
   }

   // Variáveis de Cálculo e Microestrutura do Candle 0
   double distEmaPts = (price - emaVal) / _Point;
   string trendStr   = (price >= emaVal) ? "ALTA (Acima da 200)" : "BAIXA (Abaixo da 200)";
   color  trendClr   = (price >= emaVal) ? clrLimeGreen : clrCrimson;

   double cOpen  = open[0];
   double cClose = close[0];
   double cHigh  = high[0];
   double cLow   = low[0];
   double lowerWick = (MathMin(cOpen, cClose) - cLow) / _Point;
   double upperWick = (cHigh - MathMax(cOpen, cClose)) / _Point;

   // Tempo restante da barra atual
   datetime barT = time[0];
   datetime nowT = TimeCurrent();
   int elapsedSec = (int)(nowT - barT);
   int remainSec  = PeriodSeconds() - elapsedSec;
   if (remainSec < 0) remainSec = 0;
   string timerStr = StringFormat("%02d:%02d", remainSec / 60, remainSec % 60);

   // Status do Pavio Atual
   string wickStr;
   color  wickClr;
   if (cClose >= cOpen)
   {
      if (lowerWick >= InpMinWickPoints)
      {
         wickStr = StringFormat("Pavio Inf: %.0f pts (OK - Mola Pronta)", lowerWick);
         wickClr = clrSpringGreen;
      }
      else
      {
         wickStr = StringFormat("Pavio Inf: %.0f pts (CUIDADO: Vela Careca!)", lowerWick);
         wickClr = clrDimGray;
      }
   }
   else
   {
      if (upperWick >= InpMinWickPoints)
      {
         wickStr = StringFormat("Pavio Sup: %.0f pts (OK - Mola Pronta)", upperWick);
         wickClr = clrSpringGreen;
      }
      else
      {
         wickStr = StringFormat("Pavio Sup: %.0f pts (CUIDADO: Vela Careca!)", upperWick);
         wickClr = clrDimGray;
      }
   }

   // Avaliação da Formação em Andamento
   double distToBuy  = (gActivePivotHigh > 0) ? (gActivePivotHigh - price) / _Point : 9999;
   double distToSell = (gActivePivotLow > 0)  ? (price - gActivePivotLow) / _Point  : 9999;

   string formacaoStatus = "";
   color  formacaoCor    = clrLightSkyBlue;

   if (distToBuy <= 45 && distToBuy > 0)
   {
      formacaoStatus = StringFormat("Testando Topo em %.2f (Faltam %.0f pts) ↗", gActivePivotHigh, distToBuy);
      formacaoCor    = clrGold;
   }
   else if (distToSell <= 45 && distToSell > 0)
   {
      formacaoStatus = StringFormat("Testando Fundo em %.2f (Faltam %.0f pts) ↘", gActivePivotLow, distToSell);
      formacaoCor    = clrGold;
   }
   else if (nL >= 2 && MathAbs(lows[nL-1].price - lows[nL-2].price) <= (150 * _Point) && price > lows[nL-1].price)
   {
      formacaoStatus = "Padrão W Empenado Armado (Acumulação Compradora) ↗";
      formacaoCor    = clrSpringGreen;
   }
   else if (nH >= 2 && MathAbs(highs[nH-1].price - highs[nH-2].price) <= (150 * _Point) && price < highs[nH-1].price)
   {
      formacaoStatus = "Padrão Topo Duplo M Armado (Pressão Vendedora) ↘";
      formacaoCor    = clrLightCoral;
   }
   else
   {
      formacaoStatus = "Consolidação Neutra no Miolo do Pivô";
      formacaoCor    = clrLightGray;
   }

   // Caixa de Ação Exata do Mentor
   string acaoMsg = "";
   color  acaoBg  = C'20,30,45';
   color  acaoTxt = clrWhite;

   bool isCurrentBald = (cClose >= cOpen) ? (lowerWick < InpMinWickPoints * 0.4) : (upperWick < InpMinWickPoints * 0.4);

   if (gLastSignalTime >= time[1])
   {
      if (gLastSignalType == "COMPRA")
      {
         acaoMsg = "🚀 AÇÃO: EXECUTAR COMPRA! Rompimento confirmado com pavio!";
         acaoTxt = clrLime;
         acaoBg  = C'10,40,25';
      }
      else if (gLastSignalType == "VENDA")
      {
         acaoMsg = "📉 AÇÃO: EXECUTAR VENDA! Perda de fundo confirmada com pavio!";
         acaoTxt = clrMagenta;
         acaoBg  = C'40,15,30';
      }
   }
   else if (distToBuy <= 40 && distToBuy > 0)
   {
      if (isCurrentBald)
      {
         acaoMsg = "⛔ AÇÃO: NÃO COMPRAR! Vela careca em andamento (risco de armadilha)!";
         acaoTxt = clrYellow;
         acaoBg  = C'45,30,10';
      }
      else
      {
         acaoMsg = StringFormat("⚠️ AÇÃO: PREPARAR COMPRA! Faltam %.0f pts para o Topo!", distToBuy);
         acaoTxt = clrGold;
         acaoBg  = C'35,35,15';
      }
   }
   else if (distToSell <= 40 && distToSell > 0)
   {
      if (isCurrentBald)
      {
         acaoMsg = "⛔ AÇÃO: NÃO VENDER! Vela careca em andamento (risco de armadilha)!";
         acaoTxt = clrYellow;
         acaoBg  = C'45,30,10';
      }
      else
      {
         acaoMsg = StringFormat("⚠️ AÇÃO: PREPARAR VENDA! Faltam %.0f pts para o Fundo!", distToSell);
         acaoTxt = clrGold;
         acaoBg  = C'35,35,15';
      }
   }
   else
   {
      acaoMsg = "⏳ AÇÃO: AGUARDAR - Paciência institucional até o rompimento.";
      acaoTxt = clrAqua;
      acaoBg  = C'15,30,45';
   }

   // RENDERIZAÇÃO DAS LINHAS DO PAINEL COM ENQUADRAMENTO PERFEITO
   int curY = panelY + hdrH + sH(6);

   // Linha 1: Gestão de Banca
   CriarLabelHUD(prefixObjects + "L1", panelX + sW(12), curY,
                 StringFormat("💰 BANCA: $%.0f | LOTE SEGURO: %.2f", InpAccountBalance, InpLotSize), clrYellow, sF(gBaseFontSize), true);
   curY += lineH;

   // Linha 2: Média 200 & Tendência
   CriarLabelHUD(prefixObjects + "L2", panelX + sW(12), curY,
                 StringFormat("📈 200 EMA: %s | Dist: %+.0f pts", trendStr, distEmaPts), trendClr, sF(gBaseFontSize), false);
   curY += lineH;

   // Linha 3: Monitoramento do Candle Atual (Barra 0)
   CriarLabelHUD(prefixObjects + "L3", panelX + sW(12), curY,
                 StringFormat("⏱️ Vela [%s]: %s | %s", timerStr, (_Period == PERIOD_M1 ? "M1" : (_Period == PERIOD_M5 ? "M5" : "TF")), wickStr), wickClr, sF(gBaseFontSize), true);
   curY += lineH;

   // Linha 4: Formação em Andamento
   CriarLabelHUD(prefixObjects + "L4", panelX + sW(12), curY,
                 "🔍 Em Andamento: " + formacaoStatus, formacaoCor, sF(gBaseFontSize), false);
   curY += lineH;

   // Linha 5: Gatilho Projetado
   string gatilhoStr = (distToBuy <= 150) ? StringFormat("⚡ Rompimento Alta: %.2f (Faltam %.0f pts) ↗", gActivePivotHigh, distToBuy) :
                       ((distToSell <= 150) ? StringFormat("⚡ Rompimento Baixa: %.2f (Faltam %.0f pts) ↘", gActivePivotLow, distToSell) :
                       "⚡ Gatilho: Aguardando aproximação da linha projetada");
   CriarLabelHUD(prefixObjects + "L5", panelX + sW(12), curY, gatilhoStr, clrGold, sF(gBaseFontSize), true);
   curY += lineH;

   // Linha 6: Último Sinal Executado
   if (gLastSignalType != "AGUARDANDO")
   {
      double riscoUSD = MathAbs(gLastEntryPrice - gLastStopLoss) * 100.0 * InpLotSize;
      double alvoUSD  = MathAbs(gLastTakeProfit - gLastEntryPrice) * 100.0 * InpLotSize;

      CriarLabelHUD(prefixObjects + "L6", panelX + sW(12), curY,
                    StringFormat("Sinal: %s | Stop: %s (-$%.2f) | Alvo: %s (+$%.2f)",
                                 gLastSignalType, DoubleToString(gLastStopLoss, _Digits), riscoUSD,
                                 DoubleToString(gLastTakeProfit, _Digits), alvoUSD), clrSpringGreen, sF(gBaseFontSize - 1), false);
   }
   else
   {
      CriarLabelHUD(prefixObjects + "L6", panelX + sW(12), curY,
                    "Regra de Ouro: Proibido operar vela careca sem pavio prévio!", clrAqua, sF(gBaseFontSize - 1), false);
   }
   curY += lineH;

   // Linha 7: CAIXA DE AÇÃO EXATA DO MENTOR
   int boxH = sH(28);
   CriarRetanguloHUD(prefixObjects + "BOX_ACAO", panelX + sW(8), curY, width - sW(16), boxH, acaoBg, acaoTxt);
   CriarLabelHUD(prefixObjects + "L_ACAO", panelX + sW(14), curY + sH(6), acaoMsg, acaoTxt, sF(gBaseFontSize), true);
   curY += boxH + sH(6);

   // Linha 8: Disciplina da Meta
   CriarLabelHUD(prefixObjects + "L_META", panelX + sW(12), curY,
                 "🔒 Bateu a meta (+10$ a +20$)? FECHE O METATRADER 5!", clrOrange, sF(gBaseFontSize - 1), true);
   curY += lineH;

   // SEÇÃO EXPANSÍVEL: SUMÁRIO E LEGENDA DAS CORES [📖 GUIA]
   if (gShowLegend)
   {
      CriarRetanguloHUD(prefixObjects + "LEG_BG", panelX + sW(8), curY, width - sW(16), sH(125), C'18,25,38', C'71,85,105');
      int legY = curY + sH(6);

      CriarLabelHUD(prefixObjects + "LEG_TITLE", panelX + sW(14), legY, "📖 SUMÁRIO OFICIAL DE CORES E SINAIS:", clrAqua, sF(gBaseFontSize), true);
      legY += sH(18);

      CriarLabelHUD(prefixObjects + "LEG_1", panelX + sW(14), legY, "🟢 Verde Neon: Rompimento Compra ↗ (Corpo sobre Topo + Pavio)", clrLime, sF(gBaseFontSize - 1), false);
      legY += sH(16);

      CriarLabelHUD(prefixObjects + "LEG_2", panelX + sW(14), legY, "🟣 Magenta: Rompimento Venda ↘ (Corpo sob Fundo + Pavio)", clrMagenta, sF(gBaseFontSize - 1), false);
      legY += sH(16);

      CriarLabelHUD(prefixObjects + "LEG_3", panelX + sW(14), legY, "🟡 Dourado: Candle com Pavio Válido (Mola Armada) / Linha Compra", clrGold, sF(gBaseFontSize - 1), false);
      legY += sH(16);

      CriarLabelHUD(prefixObjects + "LEG_4", panelX + sW(14), legY, "🔘 Cinza Escuro: Vela Careca / Armadilha (NÃO OPERAR!)", clrDimGray, sF(gBaseFontSize - 1), true);
      legY += sH(16);

      CriarLabelHUD(prefixObjects + "LEG_5", panelX + sW(14), legY, "🟦 Ciano Grosso: Estrutura Zigue-Zague | 🔵 Média 200: Alvo Ímã", clrDeepSkyBlue, sF(gBaseFontSize - 1), false);
      legY += sH(16);

      CriarLabelHUD(prefixObjects + "LEG_6", panelX + sW(14), legY, "⚡ Linha Projetada: Nível Exato onde vai romper + Seta Direcional", clrYellow, sF(gBaseFontSize - 1), false);
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
//| Limpeza Segura dos Objetos do Painel                             |
//+------------------------------------------------------------------+
void LimparTodosLabelsHUD()
{
   for (int k = 1; k <= 8; k++)
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
   if (id == CHARTEVENT_OBJECT_CLICK)
   {
      // Botão Minimizar
      if (sparam == prefixObjects + "BTN_MIN")
      {
         panelMinimized = !panelMinimized;
         ObjectSetInteger(0, prefixObjects + "BTN_MIN", OBJPROP_STATE, false);
         LimparTodosLabelsHUD();
         ChartRedraw();
      }
      // Botão Sumário / Guia de Cores
      else if (sparam == prefixObjects + "BTN_LEGEND")
      {
         gShowLegend = !gShowLegend;
         ObjectSetInteger(0, prefixObjects + "BTN_LEGEND", OBJPROP_STATE, false);
         LimparTodosLabelsHUD();
         ChartRedraw();
      }
      // Botão Zoom Mais [A+]
      else if (sparam == prefixObjects + "BTN_ZOOM_IN")
      {
         gPanelScale += 0.15;
         if (gPanelScale > 2.2) gPanelScale = 2.2;
         ObjectSetInteger(0, prefixObjects + "BTN_ZOOM_IN", OBJPROP_STATE, false);
         LimparTodosLabelsHUD();
         ChartRedraw();
      }
      // Botão Zoom Menos [A-]
      else if (sparam == prefixObjects + "BTN_ZOOM_OUT")
      {
         gPanelScale -= 0.15;
         if (gPanelScale < 0.75) gPanelScale = 0.75;
         ObjectSetInteger(0, prefixObjects + "BTN_ZOOM_OUT", OBJPROP_STATE, false);
         LimparTodosLabelsHUD();
         ChartRedraw();
      }
   }

   // Arrastar Painel com Mouse
   if (id == CHARTEVENT_MOUSE_MOVE)
   {
      int mouseX = (int)lparam;
      int mouseY = (int)dparam;
      uint mouseFlags = (uint)sparam;

      bool leftButtonDown = (mouseFlags & 1) != 0;

      if (leftButtonDown && !isDragging)
      {
         int w = sW(panelMinimized ? 240 : (gShowLegend ? 460 : 400));
         int h = sH(32);
         if (mouseX >= panelX && mouseX <= panelX + w &&
             mouseY >= panelY && mouseY <= panelY + h)
         {
            isDragging = true;
            dragOffsetX = mouseX - panelX;
            dragOffsetY = mouseY - panelY;
         }
      }
      else if (leftButtonDown && isDragging)
      {
         panelX = mouseX - dragOffsetX;
         panelY = mouseY - dragOffsetY;

         if (panelX < 5) panelX = 5;
         if (panelY < 20) panelY = 20;

         ChartRedraw();
      }
      else if (!leftButtonDown && isDragging)
      {
         isDragging = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Auxiliares Gráficos do Painel HUD                               |
//+------------------------------------------------------------------+
void CriarRetanguloHUD(string name, int x, int y, int w, int h, color bgClr, color borderClr)
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

void CriarLabelHUD(string name, int x, int y, string text, color clr, int fontSize, bool isBold)
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

void CriarBotaoHUD(string name, int x, int y, int w, int h, string text, color txtClr, color bgClr, int fontSize = 8)
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
