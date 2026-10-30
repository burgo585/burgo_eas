//+------------------------------------------------------------------+
//|                                  Indicador_Leomar_PriceAction.mq5 |
//|                                     Metodologia Leomar (Leo Brasília) |
//|                                 Burgo585 - Price Action & Pivôs 2026 |
//+------------------------------------------------------------------+
#property copyright "Burgo585 & Leomar"
#property link      "https://github.com/burgo585/burgo_eas"
#property version   "1.20"
#property description "Indicador Oficial de Price Action Puro de Leomar (Versão 1.20)"
#property description "- Mapeamento 100% Series (Visual Imediato no Gráfico)"
#property description "- Identificação de Pivôs em V e W Empenado com Setas e Linhas"
#property description "- Filtro Mandatório Anti-Vela Careca (Exige Pavio Contrário)"
#property description "- Média Móvel de 200 períodos como Alvo e Guia de Tendência"
#property description "- Projeção Contínua de Entrada, Stop Loss e Alvo 3:1"
#property description "- Painel Visual HUD com Gestão para Contas Pequenas ($300)"

#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   3

//--- Plot 1: Média 200 (Alvo/Guia)
#property indicator_label1  "Média 200 (Alvo/Guia)"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDeepSkyBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Plot 2: Seta de Compra
#property indicator_label2  "Compra (Pivô + Pavio)"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLimeGreen
#property indicator_width2  4

//--- Plot 3: Seta de Venda
#property indicator_label3  "Venda (Pivô + Pavio)"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrCrimson
#property indicator_width3  4

enum ENUM_EMA_TYPE
{
   EMA_EXPONENCIAL = MODE_EMA, // Exponencial (Recomendada)
   EMA_SIMPLES     = MODE_SMA  // Simples
};

//+------------------------------------------------------------------+
//| Inputs do Indicador                                              |
//+------------------------------------------------------------------+
input group "=== CONFIGURAÇÃO DA MÉDIA DE 200 ==="
input int                InpEmaPeriod         = 200;              // Período da Média
input ENUM_EMA_TYPE      InpEmaMethod         = EMA_EXPONENCIAL;  // Tipo de Média Móvel
input ENUM_APPLIED_PRICE InpEmaApplied        = PRICE_CLOSE;      // Preço Aplicado

input group "=== GEOMETRIA DE PIVÔS E FRACTAIS ==="
input int                InpSwingStrength     = 3;                // Força do Swing (Barras de cada lado)
input int                InpMaxHistoryBars    = 500;              // Histórico Visível Avaliado (Barras Recentes)

input group "=== GATILHO DO PAVIO (MICROESTRUTURA) ==="
input int                InpMinWickPoints     = 20;               // Pavio Mínimo Contrário em Pontos (Filtro Vela Careca)
input int                InpMinBodyPoints     = 30;               // Corpo Mínimo do Candle em Pontos
input double             InpRiskRewardRatio   = 3.0;              // Relação Alvo / Risco (Padrão 3:1 de Leomar)

input group "=== GESTÃO DE BANCA E LOTES ==="
input double             InpAccountBalance    = 300.0;            // Valor da Sua Banca em Dólares ($)
input double             InpCustomLot         = 0.01;             // Lote Recomendado (Para $300 use 0.01!)

input group "=== ALERTAS E NOTIFICAÇÕES ==="
input bool               InpAlertPopup        = true;             // Alerta Pop-up na Tela
input bool               InpAlertSound        = true;             // Alerta Sonoro
input string             InpSoundFile         = "alert.wav";      // Arquivo de Som
input bool               InpAlertPush         = false;            // Notificação Push no Celular

input group "=== ELEMENTOS VISUAIS NO GRÁFICO ==="
input bool               InpShowDashboard     = true;             // Exibir Painel Visual HUD
input bool               InpShowLines         = true;             // Traçar Linhas de Entrada, Stop e Alvo 3:1
input bool               InpShowPivotMarks    = true;             // Marcar Topos e Fundos de Pivô no Gráfico
input color              InpColorEntry        = clrGold;          // Cor da Linha de Entrada
input color              InpColorStop         = clrRed;           // Cor da Linha de Stop
input color              InpColorTarget       = clrLimeGreen;     // Cor da Linha de Alvo 3:1

//--- Buffers de Cálculo
double BufferEMA200[];
double BufferBuy[];
double BufferSell[];
double BufferStopLoss[];
double BufferTakeProfit[];

//--- Variáveis Globais de Controle
int      emaHandle = INVALID_HANDLE;
datetime lastAlertTime = 0;
string   prefixObjects = "LEOMAR_PA_";

struct SwingPoint
{
   datetime time;
   double   price;
   int      barIndex;
   bool     isHigh;
};

// Dados do Último Sinal Ativo
string   gLastSignalType   = "AGUARDANDO";
double   gLastEntryPrice   = 0.0;
double   gLastStopLoss     = 0.0;
double   gLastTakeProfit   = 0.0;
datetime gLastSignalTime   = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Mapeamento dos Buffers do Indicador
   SetIndexBuffer(0, BufferEMA200, INDICATOR_DATA);
   SetIndexBuffer(1, BufferBuy,    INDICATOR_DATA);
   SetIndexBuffer(2, BufferSell,   INDICATOR_DATA);
   SetIndexBuffer(3, BufferStopLoss,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(4, BufferTakeProfit, INDICATOR_CALCULATIONS);

   //--- Mapear TODOS os buffers como SÉRIES (Barra 0 = Atual, Barra 1 = Anterior)
   ArraySetAsSeries(BufferEMA200, true);
   ArraySetAsSeries(BufferBuy,    true);
   ArraySetAsSeries(BufferSell,   true);
   ArraySetAsSeries(BufferStopLoss,   true);
   ArraySetAsSeries(BufferTakeProfit, true);

   //--- Configuração das Setas Wingdings
   PlotIndexSetInteger(1, PLOT_ARROW, 233); // Seta para Cima (Compra)
   PlotIndexSetInteger(2, PLOT_ARROW, 234); // Seta para Baixo (Venda)

   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);

   //--- Inicializar Handle da Média de 200
   emaHandle = iMA(_Symbol, _Period, InpEmaPeriod, 0, (ENUM_MA_METHOD)InpEmaMethod, InpEmaApplied);
   if (emaHandle == INVALID_HANDLE)
   {
      Print("[Leomar PA] Erro ao criar handle da Média Móvel de 200!");
      return INIT_FAILED;
   }

   string shortName = StringFormat("Leomar Price Action v1.20 (EMA %d | 3:1)", InpEmaPeriod);
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
   if (rates_total < InpEmaPeriod + 20)
      return 0;

   //--- Definir todos os arrays de preços como SÉRIES para sincronia visual
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   //--- Copiar Média Móvel de 200 períodos para o Buffer visível
   int copyCount = CopyBuffer(emaHandle, 0, 0, rates_total, BufferEMA200);
   if (copyCount <= 0)
   {
      // Fallback: cálculo causal direto da EMA caso o handle esteja inicializando
      CalculateDirectEma(rates_total, close);
   }

   //--- Definir limite de barras recentes para avaliação rápida
   int limit = InpMaxHistoryBars;
   if (limit > rates_total - InpSwingStrength - 5)
      limit = rates_total - InpSwingStrength - 5;

   // Limpar buffers na faixa avaliada
   for (int i = 0; i <= limit; i++)
   {
      BufferBuy[i]  = 0.0;
      BufferSell[i] = 0.0;
   }

   //--- Detectar Swings (Topos e Fundos) recentes causalmente
   SwingPoint confirmedHighs[];
   SwingPoint confirmedLows[];
   ArrayResize(confirmedHighs, 0);
   ArrayResize(confirmedLows, 0);

   // Varredura do passado para o presente (do índice limit até 1)
   for (int i = limit; i >= 1; i--)
   {
      // Checar se a barra 'i + InpSwingStrength' é um topo ou fundo
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

            if (InpShowPivotMarks && swBar < 80)
               DesenharMarcadorPivo("H_" + IntegerToString(swBar), time[swBar], hVal, clrOrangeRed, "Topo Pivô");
         }

         if (isL)
         {
            int sz = ArraySize(confirmedLows);
            ArrayResize(confirmedLows, sz + 1);
            confirmedLows[sz].time = time[swBar];
            confirmedLows[sz].price = lVal;
            confirmedLows[sz].barIndex = swBar;
            confirmedLows[sz].isHigh = false;

            if (InpShowPivotMarks && swBar < 80)
               DesenharMarcadorPivo("L_" + IntegerToString(swBar), time[swBar], lVal, clrDodgerBlue, "Fundo Pivô (V/W)");
         }
      }

      // Avaliar Rompimento de Pivô com Filtro Anti-Vela Careca
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

         // 1. SINAL DE COMPRA (Pivô de Alta em V ou W Empenado)
         if (cClose > lastHigh && cOpen <= lastHigh && (cClose - cOpen) >= minBody)
         {
            // Filtro Anti-Vela Careca: Deve ter feito pavio inferior prévio
            double lowerWick = MathMin(cOpen, cClose) - cLow;
            if (lowerWick >= minWick)
            {
               double stopLoss = lastLow - (15 * _Point);
               double risk     = cClose - stopLoss;

               if (risk >= (30 * _Point))
               {
                  double takeProfit = cClose + (risk * InpRiskRewardRatio);

                  // Plotar Seta de Compra exatamente abaixo do candle
                  BufferBuy[i] = cLow - (20 * _Point);
                  BufferStopLoss[i] = stopLoss;
                  BufferTakeProfit[i] = takeProfit;

                  // Atualizar dados do último sinal mais recente
                  if (i <= 30 && time[i] > gLastSignalTime)
                  {
                     gLastSignalType = "COMPRA";
                     gLastEntryPrice = cClose;
                     gLastStopLoss   = stopLoss;
                     gLastTakeProfit = takeProfit;
                     gLastSignalTime = time[i];

                     if (InpShowLines)
                        AtualizarLinhasGraficas("COMPRA", cClose, stopLoss, takeProfit);

                     if (i == 1 && time[1] != lastAlertTime)
                     {
                        lastAlertTime = time[1];
                        EmitirAlerta("COMPRA", cClose, stopLoss, takeProfit);
                     }
                  }
               }
            }
         }

         // 2. SINAL DE VENDA (Pivô de Baixa)
         if (cClose < lastLow && cOpen >= lastLow && (cOpen - cClose) >= minBody)
         {
            // Filtro Anti-Vela Careca: Deve ter feito pavio superior prévio
            double upperWick = cHigh - MathMax(cOpen, cClose);
            if (upperWick >= minWick)
            {
               double stopLoss = lastHigh + (15 * _Point);
               double risk     = stopLoss - cClose;

               if (risk >= (30 * _Point))
               {
                  double takeProfit = cClose - (risk * InpRiskRewardRatio);

                  // Plotar Seta de Venda exatamente acima do candle
                  BufferSell[i] = cHigh + (20 * _Point);
                  BufferStopLoss[i] = stopLoss;
                  BufferTakeProfit[i] = takeProfit;

                  if (i <= 30 && time[i] > gLastSignalTime)
                  {
                     gLastSignalType = "VENDA";
                     gLastEntryPrice = cClose;
                     gLastStopLoss   = stopLoss;
                     gLastTakeProfit = takeProfit;
                     gLastSignalTime = time[i];

                     if (InpShowLines)
                        AtualizarLinhasGraficas("VENDA", cClose, stopLoss, takeProfit);

                     if (i == 1 && time[1] != lastAlertTime)
                     {
                        lastAlertTime = time[1];
                        EmitirAlerta("VENDA", cClose, stopLoss, takeProfit);
                     }
                  }
               }
            }
         }
      }
   }

   // Se nenhuma linha foi desenhada ainda, traçar linha de suporte e resistência do pivô atual
   if (gLastEntryPrice == 0.0 && ArraySize(confirmedHighs) > 0 && ArraySize(confirmedLows) > 0)
   {
      double curH = confirmedHighs[ArraySize(confirmedHighs)-1].price;
      double curL = confirmedLows[ArraySize(confirmedLows)-1].price;
      CriarLinhaHorizontal(prefixObjects + "PIVOT_RES", curH, clrGold, STYLE_DOT, 1, "Resistência Pivô Atual");
      CriarLinhaHorizontal(prefixObjects + "PIVOT_SUP", curL, clrDeepSkyBlue, STYLE_DOT, 1, "Suporte Pivô Atual");
   }

   //--- Atualizar Painel Visual HUD no Canto da Tela
   if (InpShowDashboard)
   {
      double curPrice = close[0];
      double curEma   = BufferEMA200[0];
      AtualizarPainelHUD(curPrice, curEma);
   }

   ChartRedraw();
   return rates_total;
}

//+------------------------------------------------------------------+
//| Cálculo Direto da EMA como Fallback                              |
//+------------------------------------------------------------------+
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
//| Emissão de Alertas Multicanais                                   |
//+------------------------------------------------------------------+
void EmitirAlerta(string tipo, double entrada, double stop, double alvo)
{
   double riscoPts = MathAbs(entrada - stop) / _Point;
   double alvoPts  = MathAbs(alvo - entrada) / _Point;

   string msg = StringFormat("LEOMAR PA [%s]: Sinal de %s Confirmado!\nEntrada: %s\nStop Loss: %s (%.0f pts)\nAlvo 3:1: %s (%.0f pts)",
                             _Symbol, tipo,
                             DoubleToString(entrada, _Digits),
                             DoubleToString(stop, _Digits), riscoPts,
                             DoubleToString(alvo, _Digits), alvoPts);

   if (InpAlertPopup)
      Alert(msg);

   if (InpAlertSound && InpSoundFile != "")
      PlaySound(InpSoundFile);

   if (InpAlertPush)
      SendNotification(msg);
}

//+------------------------------------------------------------------+
//| Traçado de Linhas Operacionais (Entrada, Stop, Alvo)             |
//+------------------------------------------------------------------+
void AtualizarLinhasGraficas(string tipo, double entrada, double stop, double alvo)
{
   string nameEntry = prefixObjects + "LINE_ENTRY";
   string nameStop  = prefixObjects + "LINE_STOP";
   string nameTarget= prefixObjects + "LINE_TARGET";

   CriarLinhaHorizontal(nameEntry, entrada, InpColorEntry, STYLE_SOLID, 2, "ENTRADA (" + tipo + "): " + DoubleToString(entrada, _Digits));
   CriarLinhaHorizontal(nameStop, stop, InpColorStop, STYLE_DASH, 2, "STOP LOSS: " + DoubleToString(stop, _Digits));
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

void DesenharMarcadorPivo(string id, datetime t, double price, color clr, string desc)
{
   string name = prefixObjects + "PIV_" + id;
   if (ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159); // Pequeno círculo
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, desc);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
}

//+------------------------------------------------------------------+
//| Painel Visual HUD Completo com Gestão de Banca de $300           |
//+------------------------------------------------------------------+
void AtualizarPainelHUD(double price, double emaVal)
{
   string bgName = prefixObjects + "HUD_BG";
   if (ObjectFind(0, bgName) < 0)
   {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, 15);
      ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, 25);
      ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 330);
      ObjectSetInteger(0, bgName, OBJPROP_YSIZE, 175);
      ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, C'15,23,42'); // Azul Slate escuro
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_COLOR, C'56,189,248'); // Borda ciano
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
   }

   double distEmaPts = (price - emaVal) / _Point;
   string trendStr   = (price >= emaVal) ? "ALTA (Acima da 200)" : "BAIXA (Abaixo da 200)";
   color  trendClr   = (price >= emaVal) ? clrLimeGreen : clrCrimson;

   CriarOuAtualizarLabel(prefixObjects + "T0", 25, 35,  "=== LEOMAR PRICE ACTION (v1.20) ===", clrDeepSkyBlue, 10, true);
   CriarOuAtualizarLabel(prefixObjects + "T1", 25, 55,  StringFormat("BANCA: $%.0f | LOTE SEGURO: %.2f", InpAccountBalance, InpCustomLot), clrYellow, 9, true);
   CriarOuAtualizarLabel(prefixObjects + "T2", 25, 75,  "Tendência 200 EMA: " + trendStr, trendClr, 9, false);
   CriarOuAtualizarLabel(prefixObjects + "T3", 25, 95,  StringFormat("Distância p/ Média 200: %+.0f pts", distEmaPts), clrWhite, 9, false);

   string signalDisplay = (gLastSignalType != "AGUARDANDO") ?
                          StringFormat("SINAL: %s em %s", gLastSignalType, DoubleToString(gLastEntryPrice, _Digits)) :
                          "STATUS: Rastreando Formação de Pivô...";
   color sigClr = (gLastSignalType == "COMPRA") ? clrLimeGreen : (gLastSignalType == "VENDA" ? clrCrimson : clrGold);
   CriarOuAtualizarLabel(prefixObjects + "T4", 25, 115, signalDisplay, sigClr, 9, true);

   if (gLastSignalType != "AGUARDANDO")
   {
      CriarOuAtualizarLabel(prefixObjects + "T5", 25, 135, StringFormat("Stop: %s | Alvo 3:1: %s", DoubleToString(gLastStopLoss, _Digits), DoubleToString(gLastTakeProfit, _Digits)), clrSpringGreen, 8, false);
   }
   else
   {
      CriarOuAtualizarLabel(prefixObjects + "T5", 25, 135, "Regra Ativa: Proibido Operar Vela Careca", clrLightGray, 8, false);
   }

   CriarOuAtualizarLabel(prefixObjects + "T6", 25, 155, "Meta Batida (ex: +$30/dia)? Fechar MT5!", clrOrange, 8, true);
}

void CriarOuAtualizarLabel(string name, int x, int y, string text, color clr, int fontSize, bool isBold)
{
   if (ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, isBold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}
//+------------------------------------------------------------------+
