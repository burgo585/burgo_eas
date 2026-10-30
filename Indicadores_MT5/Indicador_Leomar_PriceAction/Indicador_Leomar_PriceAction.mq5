//+------------------------------------------------------------------+
//|                                  Indicador_Leomar_PriceAction.mq5 |
//|                                     Metodologia Leomar (Leo Brasília) |
//|                                 Burgo585 - Price Action & Pivôs 2026 |
//+------------------------------------------------------------------+
#property copyright "Burgo585 & Leomar"
#property link      "https://github.com/burgo585/burgo_eas"
#property version   "2.00"
#property description "Indicador Oficial de Price Action Puro de Leomar (Versão 2.00 Pro)"
#property description "- Traçado Visual Intuitivo da Geometria dos Pivôs (V e W)"
#property description "- Painel Flutuante Arrastável com Mouse e Minimizável [- / +]"
#property description "- Marcações Claras de Entrada, Stop Loss e Alvo 3:1"
#property description "- Filtro Anti-Vela Careca e Média Móvel de 200 Períodos"
#property description "- Otimizado para Contas Pequenas ($300 - Lote 0.01)"

#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   3

//--- Plot 1: Média Móvel 200
#property indicator_label1  "Média 200 (Alvo/Guia)"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDeepSkyBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Plot 2: Seta de Compra
#property indicator_label2  "Compra Pivô"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLimeGreen
#property indicator_width2  4

//--- Plot 3: Seta de Venda
#property indicator_label3  "Venda Pivô"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrCrimson
#property indicator_width3  4

enum ENUM_EMA_TYPE
{
   EMA_EXPONENCIAL = MODE_EMA, // Exponencial
   EMA_SIMPLES     = MODE_SMA  // Simples
};

//+------------------------------------------------------------------+
//| Inputs do Indicador                                              |
//+------------------------------------------------------------------+
input group "=== CONFIGURAÇÃO DA MÉDIA DE 200 ==="
input int                InpEmaPeriod         = 200;              // Período da Média
input ENUM_EMA_TYPE      InpEmaMethod         = EMA_EXPONENCIAL;  // Tipo de Média Móvel
input ENUM_APPLIED_PRICE InpEmaApplied        = PRICE_CLOSE;      // Preço Aplicado

input group "=== SENSIBILIDADE DOS PIVÔS (GEOMETRIA) ==="
input int                InpSwingStrength     = 2;                // Força dos Topos/Fundos (2 = Dinâmico, 3 = Conservador)
input int                InpMaxHistoryBars    = 600;              // Histórico Avaliado na Tela
input bool               InpDrawPivotLines    = true;             // Desenhar Linhas Geométricas dos Pivôs (V e W)
input color              InpPivotLineColor    = clrSlateBlue;     // Cor das Linhas do Pivô
input int                InpPivotLineWidth    = 2;                // Espessura das Linhas do Pivô

input group "=== GATILHO DO PAVIO (MICROESTRUTURA) ==="
input int                InpMinWickPoints     = 12;               // Pavio Mínimo Contrário em Pontos (Filtro Vela Careca)
input int                InpMinBodyPoints     = 20;               // Corpo Mínimo do Candle em Pontos
input double             InpRiskRewardRatio   = 3.0;              // Relação Alvo:Risco (Padrão 3:1)

input group "=== GESTÃO DE BANCA ($300) ==="
input double             InpAccountBalance    = 300.0;            // Valor da Sua Banca ($)
input double             InpLotSize           = 0.01;             // Lote Recomendado ($300 -> 0.01)

input group "=== ALERTAS ==="
input bool               InpAlertPopup        = true;             // Alerta Pop-up na Tela
input bool               InpAlertSound        = true;             // Alerta Sonoro
input string             InpSoundFile         = "alert.wav";      // Som do Alerta
input bool               InpAlertPush         = false;            // Notificação Push no Celular

input group "=== ELEMENTOS VISUAIS E PAINEL ==="
input bool               InpShowLines         = true;             // Traçar Linhas de Entrada, Stop e Alvo
input color              InpColorEntry        = clrGold;          // Cor da Linha de Entrada
input color              InpColorStop         = clrRed;           // Cor da Linha de Stop
input color              InpColorTarget       = clrLimeGreen;     // Cor da Linha de Alvo 3:1

//--- Buffers
double BufferEMA200[];
double BufferBuy[];
double BufferSell[];
double BufferStopLoss[];
double BufferTakeProfit[];

//--- Variáveis Globais
int      emaHandle = INVALID_HANDLE;
datetime lastAlertTime = 0;
string   prefixObjects = "LEOMAR_PA_";

// Coordenadas e Estado do Painel HUD
int      panelX = 20;
int      panelY = 35;
bool     panelMinimized = false;
bool     isDragging = false;
int      dragOffsetX = 0;
int      dragOffsetY = 0;

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

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufferEMA200, INDICATOR_DATA);
   SetIndexBuffer(1, BufferBuy,    INDICATOR_DATA);
   SetIndexBuffer(2, BufferSell,   INDICATOR_DATA);
   SetIndexBuffer(3, BufferStopLoss,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(4, BufferTakeProfit, INDICATOR_CALCULATIONS);

   ArraySetAsSeries(BufferEMA200, true);
   ArraySetAsSeries(BufferBuy,    true);
   ArraySetAsSeries(BufferSell,   true);
   ArraySetAsSeries(BufferStopLoss,   true);
   ArraySetAsSeries(BufferTakeProfit, true);

   PlotIndexSetInteger(1, PLOT_ARROW, 233); // Seta de Compra
   PlotIndexSetInteger(2, PLOT_ARROW, 234); // Seta de Venda
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);

   emaHandle = iMA(_Symbol, _Period, InpEmaPeriod, 0, (ENUM_MA_METHOD)InpEmaMethod, InpEmaApplied);
   if (emaHandle == INVALID_HANDLE)
   {
      Print("[Leomar PA] Erro ao criar handle da Média 200!");
      return INIT_FAILED;
   }

   // Ativar eventos de mouse para arrastar o painel
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

   string shortName = StringFormat("Leomar Price Action v2.00 (EMA %d | 3:1)", InpEmaPeriod);
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

   // Copiar EMA 200
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
   }

   // Apagar linhas de pivô antigas antes de redesenhar
   if (InpDrawPivotLines)
   {
      for (int o = ObjectsTotal(0, -1, -1) - 1; o >= 0; o--)
      {
         string oName = ObjectName(0, o, -1, -1);
         if (StringFind(oName, prefixObjects + "PV_LINE_") >= 0 || StringFind(oName, prefixObjects + "LBL_") >= 0)
            ObjectDelete(0, oName);
      }
   }

   SwingPoint confirmedHighs[];
   SwingPoint confirmedLows[];
   ArrayResize(confirmedHighs, 0);
   ArrayResize(confirmedLows, 0);

   // Varredura de Topos e Fundos (Swings)
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
            confirmedHighs[sz].time = time[swBar];
            confirmedHighs[sz].price = hVal;
            confirmedHighs[sz].barIndex = swBar;
            confirmedHighs[sz].isHigh = true;
         }

         if (isL)
         {
            int sz = ArraySize(confirmedLows);
            ArrayResize(confirmedLows, sz + 1);
            confirmedLows[sz].time = time[swBar];
            confirmedLows[sz].price = lVal;
            confirmedLows[sz].barIndex = swBar;
            confirmedLows[sz].isHigh = false;
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

         // 1. COMPRA: Rompimento de Pivô de Alta (V ou W Empenado)
         // O candle abre abaixo ou na linha e rompe com corpo expressivo
         if (cClose > lastHigh && (cOpen <= lastHigh || cLow <= lastHigh) && (cClose - cOpen) >= minBody)
         {
            double lowerWick = MathMin(cOpen, cClose) - cLow;
            if (lowerWick >= minWick) // Filtro Anti-Vela Careca
            {
               double stopLoss = lastLow - (15 * _Point);
               double risk     = cClose - stopLoss;

               if (risk >= (25 * _Point))
               {
                  double takeProfit = cClose + (risk * InpRiskRewardRatio);

                  BufferBuy[i]        = cLow - (20 * _Point);
                  BufferStopLoss[i]   = stopLoss;
                  BufferTakeProfit[i] = takeProfit;

                  // Identificar se é W Empenado ou V
                  string padrao = "Pivô em V";
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

         // 2. VENDA: Rompimento de Pivô de Baixa (M ou V Invertido)
         if (cClose < lastLow && (cOpen >= lastLow || cHigh >= lastLow) && (cOpen - cClose) >= minBody)
         {
            double upperWick = cHigh - MathMax(cOpen, cClose);
            if (upperWick >= minWick) // Filtro Anti-Vela Careca
            {
               double stopLoss = lastHigh + (15 * _Point);
               double risk     = stopLoss - cClose;

               if (risk >= (25 * _Point))
               {
                  double takeProfit = cClose - (risk * InpRiskRewardRatio);

                  BufferSell[i]       = cHigh + (20 * _Point);
                  BufferStopLoss[i]   = stopLoss;
                  BufferTakeProfit[i] = takeProfit;

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

   // Traçar Estrutura Visual dos Pivôs Recentes (Linhas Conectando os Swings)
   if (InpDrawPivotLines)
      DesenharEstruturaPivos(confirmedHighs, confirmedLows);

   // Traçar Linha Amarela de Resistência e Suporte Atuais do Pivô em Formação
   int nH = ArraySize(confirmedHighs);
   int nL = ArraySize(confirmedLows);
   if (nH > 0 && nL > 0)
   {
      double curH = confirmedHighs[nH - 1].price;
      double curL = confirmedLows[nL - 1].price;
      CriarLinhaHorizontal(prefixObjects + "ACTIVE_RES", curH, clrGold, STYLE_DOT, 1, "Topo do Pivô (Gatilho Compra)");
      CriarLinhaHorizontal(prefixObjects + "ACTIVE_SUP", curL, clrDeepSkyBlue, STYLE_DOT, 1, "Fundo do Pivô (Gatilho Venda)");
   }

   // Atualizar Painel HUD
   AtualizarPainelHUD(close[0], BufferEMA200[0]);

   ChartRedraw();
   return rates_total;
}

//+------------------------------------------------------------------+
//| Traçado Visual das Linhas Geométricas dos Pivôs (V e W)          |
//+------------------------------------------------------------------+
void DesenharEstruturaPivos(const SwingPoint &highs[], const SwingPoint &lows[])
{
   int nH = ArraySize(highs);
   int nL = ArraySize(lows);

   // Traçar os últimos 4 topos e fundos para formar o desenho do V / W
   int maxP = 6;
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

   // Ordenar por tempo
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

   // Ligar pontos alternados com linhas de tendência
   for (int i = 0; i < totalP - 1; i++)
   {
      if (allPoints[i].isHigh != allPoints[i + 1].isHigh)
      {
         string lineName = prefixObjects + "PV_LINE_" + IntegerToString(i);
         CriarLinhaTendencia(lineName, allPoints[i].time, allPoints[i].price,
                             allPoints[i + 1].time, allPoints[i + 1].price,
                             InpPivotLineColor, STYLE_SOLID, InpPivotLineWidth);
      }
   }
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
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   }
   else
   {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   }
}

//+------------------------------------------------------------------+
//| Traçado de Linhas Operacionais (Entrada, Stop, Alvo 3:1)         |
//+------------------------------------------------------------------+
void DesenharLinhasOperacionais(string tipo, double entrada, double stop, double alvo)
{
   string nameEntry  = prefixObjects + "LINE_ENTRY";
   string nameStop   = prefixObjects + "LINE_STOP";
   string nameTarget = prefixObjects + "LINE_TARGET";

   CriarLinhaHorizontal(nameEntry, entrada, InpColorEntry, STYLE_SOLID, 2, "ENTRADA (" + tipo + "): " + DoubleToString(entrada, _Digits));
   CriarLinhaHorizontal(nameStop, stop, InpColorStop, STYLE_DASH, 2, "STOP TÉCNICO: " + DoubleToString(stop, _Digits));
   CriarLinhaHorizontal(nameTarget, alvo, InpColorTarget, STYLE_SOLID, 2, "ALVO 3:1: " + DoubleToString(alvo, _Digits));
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
   }
}

//+------------------------------------------------------------------+
//| Emissão de Alertas Multicanais                                   |
//+------------------------------------------------------------------+
void DispararAlerta(string tipo, double entrada, double stop, double alvo)
{
   double riscoPts = MathAbs(entrada - stop) / _Point;
   double alvoPts  = MathAbs(alvo - entrada) / _Point;
   double riscoUSD = (riscoPts * _Point) * 100.0 * InpLotSize;
   double alvoUSD  = (alvoPts * _Point) * 100.0 * InpLotSize;

   string msg = StringFormat("LEOMAR PA [%s]: Sinal de %s!\nEntrada: %s\nStop: %s (-$%.2f)\nAlvo 3:1: %s (+$%.2f)",
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
//| Painel Visual HUD Flutuante, Arrastável e Minimizável            |
//+------------------------------------------------------------------+
void AtualizarPainelHUD(double price, double emaVal)
{
   int width  = panelMinimized ? 220 : 340;
   int height = panelMinimized ? 40 : 190;

   // 1. Fundo do Painel
   string bgName = prefixObjects + "HUD_BG";
   CriarRetanguloHUD(bgName, panelX, panelY, width, height, C'15,23,42', C'56,189,248');

   // 2. Barra de Título (Cabeçalho Arrastável)
   string hdrName = prefixObjects + "HUD_HDR";
   CriarRetanguloHUD(hdrName, panelX, panelY, width, 30, C'30,41,59', C'71,85,105');

   // Título
   string titleText = panelMinimized ? "📊 LEOMAR PA (v2.0)" : "📊 LEOMAR PRICE ACTION (v2.0)";
   CriarLabelHUD(prefixObjects + "HUD_TITLE", panelX + 10, panelY + 7, titleText, clrDeepSkyBlue, 9, true);

   // Botão Minimizar / Expandir [-] / [+]
   string btnMin = prefixObjects + "BTN_MIN";
   string minLabel = panelMinimized ? "[+]" : "[-]";
   CriarBotaoHUD(btnMin, panelX + width - 35, panelY + 5, 25, 20, minLabel, clrYellow, C'51,65,85');

   // Se estiver minimizado, esconde os detalhes
   if (panelMinimized)
   {
      ApagarElementoHUD(prefixObjects + "L1");
      ApagarElementoHUD(prefixObjects + "L2");
      ApagarElementoHUD(prefixObjects + "L3");
      ApagarElementoHUD(prefixObjects + "L4");
      ApagarElementoHUD(prefixObjects + "L5");
      ApagarElementoHUD(prefixObjects + "L6");
      ApagarElementoHUD(prefixObjects + "L7");
      return;
   }

   // Painel Expandido: Detalhes Operacionais
   double distEmaPts = (price - emaVal) / _Point;
   string trendStr   = (price >= emaVal) ? "ALTA (Acima da 200)" : "BAIXA (Abaixo da 200)";
   color  trendClr   = (price >= emaVal) ? clrLimeGreen : clrCrimson;

   // Linha 1: Gestão de Banca
   CriarLabelHUD(prefixObjects + "L1", panelX + 12, panelY + 36,
                 StringFormat("💰 BANCA: $%.0f | LOTE SEGURO: %.2f", InpAccountBalance, InpLotSize), clrYellow, 9, true);

   // Linha 2: Tendência 200
   CriarLabelHUD(prefixObjects + "L2", panelX + 12, panelY + 56,
                 "📈 Tendência 200 EMA: " + trendStr, trendClr, 9, false);

   // Linha 3: Distância da Média 200
   CriarLabelHUD(prefixObjects + "L3", panelX + 12, panelY + 76,
                 StringFormat("🎯 Distância p/ Média: %+.0f pts (Alvo Ímã)", distEmaPts), clrWhite, 9, false);

   // Linha 4: Último Sinal e Padrão
   string sigStr = (gLastSignalType != "AGUARDANDO") ?
                   StringFormat("⚡ SINAL: %s (%s)", gLastSignalType, gLastPatternDesc) :
                   "⚡ STATUS: Rastreando Rompimento com Pavio...";
   color sigClr = (gLastSignalType == "COMPRA") ? clrLimeGreen : (gLastSignalType == "VENDA" ? clrCrimson : clrGold);
   CriarLabelHUD(prefixObjects + "L4", panelX + 12, panelY + 98, sigStr, sigClr, 9, true);

   // Linha 5: Preços de Entrada, Stop e Alvo
   if (gLastSignalType != "AGUARDANDO")
   {
      double riscoUSD = MathAbs(gLastEntryPrice - gLastStopLoss) * 100.0 * InpLotSize;
      double alvoUSD  = MathAbs(gLastTakeProfit - gLastEntryPrice) * 100.0 * InpLotSize;

      CriarLabelHUD(prefixObjects + "L5", panelX + 12, panelY + 120,
                    StringFormat("Entrada: %s | Stop: %s (-$%.2f)", DoubleToString(gLastEntryPrice, _Digits), DoubleToString(gLastStopLoss, _Digits), riscoUSD), clrLightGray, 8, false);

      CriarLabelHUD(prefixObjects + "L6", panelX + 12, panelY + 140,
                    StringFormat("Alvo 3:1: %s (Lucro: +$%.2f)", DoubleToString(gLastTakeProfit, _Digits), alvoUSD), clrSpringGreen, 9, true);
   }
   else
   {
      CriarLabelHUD(prefixObjects + "L5", panelX + 12, panelY + 120,
                    "Regra de Ouro: Proibido Operar Vela Careca!", clrAqua, 8, false);
      CriarLabelHUD(prefixObjects + "L6", panelX + 12, panelY + 140,
                    "Aguarde o candle respirar com pavio contrário.", clrLightGray, 8, false);
   }

   // Linha 7: Meta do Dia
   CriarLabelHUD(prefixObjects + "L7", panelX + 12, panelY + 165,
                 "🔒 Meta do Dia Batida (ex: +$10 a +$20)? FECHE O MT5!", clrOrange, 8, true);
}

//+------------------------------------------------------------------+
//| Tratamento de Eventos do Gráfico (Arrastar e Minimizar)          |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // 1. Clique no Botão de Minimizar / Expandir
   if (id == CHARTEVENT_OBJECT_CLICK)
   {
      if (sparam == prefixObjects + "BTN_MIN")
      {
         panelMinimized = !panelMinimized;
         ObjectSetInteger(0, prefixObjects + "BTN_MIN", OBJPROP_STATE, false);
         double curP = iClose(_Symbol, _Period, 0);
         AtualizarPainelHUD(curP, BufferEMA200[0]);
         ChartRedraw();
      }
   }

   // 2. Arrastar o Painel com o Mouse (Drag & Drop)
   if (id == CHARTEVENT_MOUSE_MOVE)
   {
      int mouseX = (int)lparam;
      int mouseY = (int)dparam;
      uint mouseFlags = (uint)sparam;

      bool leftButtonDown = (mouseFlags & 1) != 0;

      // Início do Arraste (clicou na barra de título)
      if (leftButtonDown && !isDragging)
      {
         int w = panelMinimized ? 220 : 340;
         if (mouseX >= panelX && mouseX <= panelX + w &&
             mouseY >= panelY && mouseY <= panelY + 30)
         {
            isDragging = true;
            dragOffsetX = mouseX - panelX;
            dragOffsetY = mouseY - panelY;
         }
      }
      // Movimentação do Painel
      else if (leftButtonDown && isDragging)
      {
         panelX = mouseX - dragOffsetX;
         panelY = mouseY - dragOffsetY;

         if (panelX < 5) panelX = 5;
         if (panelY < 20) panelY = 20;

         double curP = iClose(_Symbol, _Period, 0);
         AtualizarPainelHUD(curP, BufferEMA200[0]);
         ChartRedraw();
      }
      // Soltou o botão do mouse
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

void CriarBotaoHUD(string name, int x, int y, int w, int h, string text, color txtClr, color bgClr)
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
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
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
