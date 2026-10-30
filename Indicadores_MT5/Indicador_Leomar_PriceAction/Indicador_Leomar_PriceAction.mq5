//+------------------------------------------------------------------+
//|                                  Indicador_Leomar_PriceAction.mq5 |
//|                                     Metodologia Leomar (Leo Brasília) |
//|                                 Burgo585 - Price Action & Pivôs 2026 |
//+------------------------------------------------------------------+
#property copyright "Burgo585 & Leomar"
#property link      "https://github.com/burgo585/burgo_eas"
#property version   "1.00"
#property description "Indicador Oficial de Price Action Puro de Leomar"
#property description "- Identificação de Pivôs em V e W Empenado em regiões extremas"
#property description "- Filtro Mandatório Anti-Vela Careca (Exige Pavio Contrário)"
#property description "- Média Móvel de 200 períodos como Alvo e Guia de Tendência"
#property description "- Projeção Automática de Stop Loss Técnico e Alvo 3:1"
#property description "- Painel Visual HUD e Alertas Multicanais (Popup, Som, Push)"

#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   3

//--- Plot 1: Média Móvel 200 (Guia e Alvo)
#property indicator_label1  "Média 200 (Alvo/Guia)"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDeepSkyBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Plot 2: Seta de Compra
#property indicator_label2  "Compra (Pivô + Pavio)"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLimeGreen
#property indicator_width2  3

//--- Plot 3: Seta de Venda
#property indicator_label3  "Venda (Pivô + Pavio)"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrCrimson
#property indicator_width3  3

//--- Enumeração de Métodos de Média
enum ENUM_EMA_TYPE
{
   EMA_EXPONENCIAL = MODE_EMA, // Exponencial (Recomendada)
   EMA_SIMPLES     = MODE_SMA  // Simples
};

//+------------------------------------------------------------------+
//| Inputs do Indicador                                              |
//+------------------------------------------------------------------+
input group "=== CONFIGURAÇÃO DA MÉDIA DE 200 ==="
input int              InpEmaPeriod         = 200;              // Período da Média
input ENUM_EMA_TYPE    InpEmaMethod         = EMA_EXPONENCIAL;  // Tipo de Média Móvel
input ENUM_APPLIED_PRICE InpEmaApplied      = PRICE_CLOSE;      // Preço Aplicado

input group "=== GEOMETRIA DE PIVÔS E FRACTAIS ==="
input int              InpSwingStrength     = 3;                // Força do Swing (Barras de cada lado)
input int              InpMaxHistoryBars    = 800;              // Máx. Barras no Histórico (Otimização / Leveza)

input group "=== GATILHO DO PAVIO (MICROESTRUTURA) ==="
input int              InpMinWickPoints     = 25;               // Pavio Mínimo Contrário em Pontos (Filtro Vela Careca)
input int              InpMinBodyPoints     = 40;               // Corpo Mínimo do Candle em Pontos
input double           InpRiskRewardRatio   = 3.0;              // Relação Alvo / Risco (Padrão 3:1 de Leomar)

input group "=== ALERTAS E NOTIFICAÇÕES ==="
input bool             InpAlertPopup        = true;             // Alerta Pop-up na Tela
input bool             InpAlertSound        = true;             // Alerta Sonoro
input string           InpSoundFile         = "alert.wav";      // Arquivo de Som
input bool             InpAlertPush         = false;            // Notificação Push no Celular

input group "=== ELEMENTOS VISUAIS NO GRÁFICO ==="
input bool             InpShowDashboard     = true;             // Exibir Painel Visual HUD
input bool             InpShowLines         = true;             // Traçar Linhas de Entrada, Stop e Alvo 3:1
input color            InpColorEntry        = clrGold;          // Cor da Linha de Entrada
input color            InpColorStop         = clrRed;           // Cor da Linha de Stop
input color            InpColorTarget       = clrLimeGreen;     // Cor da Linha de Alvo 3:1

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

// Estrutura para Swings (Topos e Fundos)
struct SwingPoint
{
   datetime time;
   double   price;
   int      barIndex;
   bool     isHigh;
};

SwingPoint recentHighs[];
SwingPoint recentLows[];

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Mapeamento de Buffers
   SetIndexBuffer(0, BufferEMA200, INDICATOR_DATA);
   SetIndexBuffer(1, BufferBuy,    INDICATOR_DATA);
   SetIndexBuffer(2, BufferSell,   INDICATOR_DATA);
   SetIndexBuffer(3, BufferStopLoss,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(4, BufferTakeProfit, INDICATOR_CALCULATIONS);

   //--- Configuração das Setas Wingdings
   PlotIndexSetInteger(1, PLOT_ARROW, 233); // Seta para Cima (Compra)
   PlotIndexSetInteger(2, PLOT_ARROW, 234); // Seta para Baixo (Venda)

   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);

   //--- Inicializar Handle da Média de 200
   emaHandle = iMA(_Symbol, _Period, InpEmaPeriod, 0, (ENUM_MA_METHOD)InpEmaMethod, InpEmaApplied);
   if (emaHandle == INVALID_HANDLE)
   {
      Print("Erro ao criar indicador de Média Móvel de 200!");
      return INIT_FAILED;
   }

   //--- Nome Curto do Indicador
   string shortName = StringFormat("Leomar Price Action (EMA %d | 3:1 | Pavio >= %d pts)", InpEmaPeriod, InpMinWickPoints);
   IndicatorSetString(INDICATOR_SHORTNAME, shortName);
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   //--- Array sizes
   ArrayResize(recentHighs, 0);
   ArrayResize(recentLows, 0);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Liberar handle da EMA
   if (emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);

   // Limpar todos os objetos visuais criados pelo indicador
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
   if (rates_total < InpEmaPeriod + InpSwingStrength * 2 + 10)
      return 0;

   //--- Otimização: calcular EMA apenas nas barras necessárias
   int emaToCopy = rates_total - prev_calculated;
   if (prev_calculated > 0)
      emaToCopy++;
   else
      emaToCopy = rates_total;

   if (CopyBuffer(emaHandle, 0, 0, emaToCopy, BufferEMA200) <= 0)
      return 0;

   //--- Definir limite de barras para não sobrecarregar CPU
   int limit = rates_total - prev_calculated;
   if (prev_calculated == 0)
   {
      limit = MathMin(rates_total - InpSwingStrength - 1, InpMaxHistoryBars);
      ArrayInitialize(BufferBuy, 0.0);
      ArrayInitialize(BufferSell, 0.0);
      ArrayInitialize(BufferStopLoss, 0.0);
      ArrayInitialize(BufferTakeProfit, 0.0);
   }

   //--- Loop de varredura causal de barras
   for (int i = limit; i >= 1; i--)
   {
      // Resetar buffers de sinal nesta barra
      BufferBuy[i]  = 0.0;
      BufferSell[i] = 0.0;

      // 1. Verificar se a barra 'i + InpSwingStrength' é um Swing High ou Swing Low
      int swingBar = i + InpSwingStrength;
      if (swingBar < rates_total - InpSwingStrength)
      {
         CheckAndStoreSwings(swingBar, high, low, time, rates_total);
      }

      // 2. Avaliar se o candle 'i' fechou rompendo estrutura de pivô
      CheckPivotSignals(i, open, high, low, close, time, rates_total);
   }

   //--- Atualizar Painel HUD e Linhas de Sinal no gráfico em tempo real
   if (InpShowDashboard)
   {
      double currentPrice = close[rates_total - 1];
      double currentEma   = BufferEMA200[rates_total - 1];
      UpdateDashboard(currentPrice, currentEma, time[rates_total - 1]);
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| Detecção e Armazenamento de Topos e Fundos (Fractais)            |
//+------------------------------------------------------------------+
void CheckAndStoreSwings(int bar, const double &high[], const double &low[], const datetime &time[], int total)
{
   bool isHigh = true;
   bool isLow  = true;
   double hVal = high[bar];
   double lVal = low[bar];

   for (int k = 1; k <= InpSwingStrength; k++)
   {
      if (bar - k >= 0 && (high[bar - k] >= hVal || low[bar - k] <= lVal))
      {
         if (high[bar - k] >= hVal) isHigh = false;
         if (low[bar - k] <= lVal)  isLow  = false;
      }
      if (bar + k < total && (high[bar + k] >= hVal || low[bar + k] <= lVal))
      {
         if (high[bar + k] >= hVal) isHigh = false;
         if (low[bar + k] <= lVal)  isLow  = false;
      }
   }

   if (isHigh)
   {
      int size = ArraySize(recentHighs);
      ArrayResize(recentHighs, size + 1);
      recentHighs[size].time     = time[bar];
      recentHighs[size].price    = hVal;
      recentHighs[size].barIndex = bar;
      recentHighs[size].isHigh   = true;
   }

   if (isLow)
   {
      int size = ArraySize(recentLows);
      ArrayResize(recentLows, size + 1);
      recentLows[size].time     = time[bar];
      recentLows[size].price    = lVal;
      recentLows[size].barIndex = bar;
      recentLows[size].isHigh   = false;
   }
}

//+------------------------------------------------------------------+
//| Avaliação de Sinais de Pivô com Filtro Anti-Vela Careca          |
//+------------------------------------------------------------------+
void CheckPivotSignals(int i,
                       const double &open[],
                       const double &high[],
                       const double &low[],
                       const double &close[],
                       const datetime &time[],
                       int total)
{
   int totalHighs = ArraySize(recentHighs);
   int totalLows  = ArraySize(recentLows);

   if (totalHighs < 2 || totalLows < 2)
      return;

   // Pegar os dois topos e fundos mais recentes anteriores à barra 'i'
   SwingPoint lastHigh = GetLatestSwing(recentHighs, i);
   SwingPoint prevHigh = GetPreviousSwing(recentHighs, i, lastHigh.time);

   SwingPoint lastLow  = GetLatestSwing(recentLows, i);
   SwingPoint prevLow  = GetPreviousSwing(recentLows, i, lastLow.time);

   if (lastHigh.price <= 0 || lastLow.price <= 0)
      return;

   double cOpen  = open[i];
   double cClose = close[i];
   double cHigh  = high[i];
   double cLow   = low[i];
   double pEma   = BufferEMA200[i];

   double minWick = InpMinWickPoints * _Point;
   double minBody = InpMinBodyPoints * _Point;

   //=================================================================
   // 1. SINAL DE COMPRA: ROMPIMENTO DE PIVÔ DE ALTA (V OU W EMPENADO)
   //=================================================================
   // O candle 'i' deve romper para cima a máxima do pivô intermediário (lastHigh)
   if (cClose > lastHigh.price && open[i] <= lastHigh.price && (cClose - cOpen) >= minBody)
   {
      // O pivô de alta precisa ter um fundo de suporte definido
      double pivotSupport = MathMin(lastLow.price, prevLow.price);

      // FILTRO MANDATÓRIO LEOMAR: PROIBIDO VELA CARECA!
      // A vela deve ter respirado e feito pavio inferior antes de romper
      double lowerWick = MathMin(cOpen, cClose) - cLow;
      if (lowerWick >= minWick)
      {
         // Stop Loss milimétrico logo abaixo do fundo do pivô
         double stopLoss = lastLow.price - (10 * _Point);
         double risk     = cClose - stopLoss;

         if (risk > (30 * _Point)) // Risco plausível
         {
            double takeProfit = cClose + (risk * InpRiskRewardRatio);

            BufferBuy[i]        = cLow - (15 * _Point);
            BufferStopLoss[i]   = stopLoss;
            BufferTakeProfit[i] = takeProfit;

            // Se for a barra fechada mais recente e ainda não alertou
            if (i == 1 && time[1] != lastAlertTime)
            {
               lastAlertTime = time[1];
               DispararAlerta("COMPRA", cClose, stopLoss, takeProfit, pEma);
               if (InpShowLines)
                  DesenharLinhasOperacionais("COMPRA", cClose, stopLoss, takeProfit);
            }
         }
      }
   }

   //=================================================================
   // 2. SINAL DE VENDA: ROMPIMENTO DE PIVÔ DE BAIXA (TOPO DUPLO OU V)
   //=================================================================
   // O candle 'i' deve romper para baixo a mínima do pivô intermediário (lastLow)
   if (cClose < lastLow.price && open[i] >= lastLow.price && (cOpen - cClose) >= minBody)
   {
      // FILTRO MANDATÓRIO LEOMAR: PROIBIDO VELA CARECA!
      // A vela deve ter respirado e feito pavio superior antes de romper
      double upperWick = cHigh - MathMax(cOpen, cClose);
      if (upperWick >= minWick)
      {
         // Stop Loss milimétrico logo acima do topo do pivô
         double stopLoss = lastHigh.price + (10 * _Point);
         double risk     = stopLoss - cClose;

         if (risk > (30 * _Point))
         {
            double takeProfit = cClose - (risk * InpRiskRewardRatio);

            BufferSell[i]       = cHigh + (15 * _Point);
            BufferStopLoss[i]   = stopLoss;
            BufferTakeProfit[i] = takeProfit;

            if (i == 1 && time[1] != lastAlertTime)
            {
               lastAlertTime = time[1];
               DispararAlerta("VENDA", cClose, stopLoss, takeProfit, pEma);
               if (InpShowLines)
                  DesenharLinhasOperacionais("VENDA", cClose, stopLoss, takeProfit);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Auxiliares para Busca de Swings Recentes                         |
//+------------------------------------------------------------------+
SwingPoint GetLatestSwing(const SwingPoint &arr[], int currentBar)
{
   SwingPoint sp;
   sp.price = 0;
   sp.time  = 0;
   sp.barIndex = 0;

   int count = ArraySize(arr);
   for (int i = count - 1; i >= 0; i--)
   {
      if (arr[i].barIndex > currentBar)
      {
         return arr[i];
      }
   }
   return sp;
}

SwingPoint GetPreviousSwing(const SwingPoint &arr[], int currentBar, datetime excludeTime)
{
   SwingPoint sp;
   sp.price = 0;
   sp.time  = 0;
   sp.barIndex = 0;

   int count = ArraySize(arr);
   for (int i = count - 1; i >= 0; i--)
   {
      if (arr[i].barIndex > currentBar && arr[i].time != excludeTime)
      {
         return arr[i];
      }
   }
   return sp;
}

//+------------------------------------------------------------------+
//| Emissão de Alertas Multicanais                                   |
//+------------------------------------------------------------------+
void DispararAlerta(string tipo, double entrada, double stop, double alvo, double emaVal)
{
   double distEmaPts = MathAbs(entrada - emaVal) / _Point;
   string msg = StringFormat("LEOMAR PA [%s]: %s | Entrada: %s | Stop: %s | Alvo 3:1: %s | Dist. EMA 200: %.0f pts",
                             _Symbol, tipo,
                             DoubleToString(entrada, _Digits),
                             DoubleToString(stop, _Digits),
                             DoubleToString(alvo, _Digits),
                             distEmaPts);

   if (InpAlertPopup)
      Alert(msg);

   if (InpAlertSound && InpSoundFile != "")
      PlaySound(InpSoundFile);

   if (InpAlertPush)
      SendNotification(msg);
}

//+------------------------------------------------------------------+
//| Desenho de Linhas de Nível Operacional                           |
//+------------------------------------------------------------------+
void DesenharLinhasOperacionais(string tipo, double entrada, double stop, double alvo)
{
   string nameEntry = prefixObjects + "LINE_ENTRY";
   string nameStop  = prefixObjects + "LINE_STOP";
   string nameTarget= prefixObjects + "LINE_TARGET";

   // Linha de Entrada
   CriarOuAtualizarLinha(nameEntry, entrada, InpColorEntry, STYLE_SOLID, 2, "Entrada (" + tipo + ")");
   // Linha de Stop
   CriarOuAtualizarLinha(nameStop, stop, InpColorStop, STYLE_DASH, 2, "Stop Técnico");
   // Linha de Alvo 3:1
   CriarOuAtualizarLinha(nameTarget, alvo, InpColorTarget, STYLE_SOLID, 2, "Alvo 3:1");

   ChartRedraw();
}

void CriarOuAtualizarLinha(string name, double price, color clr, ENUM_LINE_STYLE style, int width, string text)
{
   if (ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   else
   {
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
   }
}

//+------------------------------------------------------------------+
//| Painel Visual HUD no Canto Superior Esquerdo                     |
//+------------------------------------------------------------------+
void UpdateDashboard(double price, double emaVal, datetime barTime)
{
   string bgName = prefixObjects + "HUD_BG";
   if (ObjectFind(0, bgName) < 0)
   {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, 20);
      ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, 30);
      ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 300);
      ObjectSetInteger(0, bgName, OBJPROP_YSIZE, 130);
      ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, C'15,23,42'); // Slate escuro
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_COLOR, C'51,65,85');
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
   }

   double distEmaPts = (price - emaVal) / _Point;
   string trendStr   = (price >= emaVal) ? "ALTA (Preco acima da 200)" : "BAIXA (Preco abaixo da 200)";
   color  trendClr   = (price >= emaVal) ? clrLimeGreen : clrCrimson;

   CriarLabelHUD(prefixObjects + "TITLE", 30, 40, "LEOMAR PA - PIVOS & EMA 200", clrDeepSkyBlue, 10, true);
   CriarLabelHUD(prefixObjects + "TREND", 30, 62, "Tendencia 200: " + trendStr, trendClr, 9, false);
   CriarLabelHUD(prefixObjects + "DIST",  30, 82, StringFormat("Distancia p/ EMA: %+.0f pts (Ima)", distEmaPts), clrGold, 9, false);
   CriarLabelHUD(prefixObjects + "RULE",  30, 102, "Regra: Pavio Obrigatorio (Anti-Careca)", clrWhite, 9, false);
   CriarLabelHUD(prefixObjects + "RR",    30, 122, "Alvo Programado: Risco:Retorno 3:1", clrSpringGreen, 9, false);
}

void CriarLabelHUD(string name, int x, int y, string text, color clr, int fontSize, bool isBold)
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
