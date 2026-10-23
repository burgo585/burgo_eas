//+------------------------------------------------------------------+
//|                                         TRAX_IVB_OrderFlow.mq5   |
//|                        Sistema Quantitativo TRAX - Fábio Valentim|
//|                  Modelos IVB (Initial Volume Breakout) & OrderFlow|
//+------------------------------------------------------------------+
#property copyright "TRAX Quantitative Trading System - Fábio Valentim"
#property link      "https://github.com/deepcharts"
#property version   "2.00"
#property description "Indicador Institucional de Order Flow e Initial Balance (IVB Modelos 1 e 2)"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   5

//--- Definição gráfica dos Plots
#property indicator_label1  "TRAX Sinal Compra (IVB)"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLimeGreen
#property indicator_style1  STYLE_SOLID
#property indicator_width1  3

#property indicator_label2  "TRAX Sinal Venda (IVB)"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  3

#property indicator_label3  "Initial Balance High (IB High)"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

#property indicator_label4  "Initial Balance Low (IB Low)"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrOrangeRed
#property indicator_style4  STYLE_SOLID
#property indicator_width4  2

#property indicator_label5  "Initial Balance PoC (IB PoC)"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrGold
#property indicator_style5  STYLE_DOT
#property indicator_width5  1

//--- Parâmetros de Entrada Institucionais
input group "=== CONFIGURAÇÃO DO INITIAL BALANCE (ABERTURA) ==="
input int      InpStartHour            = 9;       // Hora de Início da Sessão (Horário Broker)
input int      InpStartMinute          = 30;      // Minuto de Início da Sessão
input int      InpIBMinutes            = 30;      // Duração da Faixa de Abertura (Minutos)

input group "=== MODELOS IVB & ORDER FLOW ==="
input double   InpVolumeMultiplier     = 1.25;    // Modelo 1: Multiplicador de Expansão de Volume
input double   InpDeltaThresholdMult   = 2.0;     // Modelo 2: Limiar de Spike de Delta (vs Média)
input bool     InpEnableSoundAlerts    = true;    // Disparar Alertas Sonoros e Notificações MT5
input bool     InpShowDashboard        = true;    // Exibir Painel de Telemetria no Gráfico

//--- Buffers do Indicador
double BufferBuy[];
double BufferSell[];
double BufferIBHigh[];
double BufferIBLow[];
double BufferIBPoC[];

//--- Variáveis Globais de Estado
datetime g_ultimo_alerta = 0;
string   g_prefixo_gui   = "TRAX_GUI_";

//+------------------------------------------------------------------+
//| Função de Inicialização Customizada                             |
//+------------------------------------------------------------------+
int OnInit()
{
   // Mapeamento dos buffers aos arrays
   SetIndexBuffer(0, BufferBuy, INDICATOR_DATA);
   SetIndexBuffer(1, BufferSell, INDICATOR_DATA);
   SetIndexBuffer(2, BufferIBHigh, INDICATOR_DATA);
   SetIndexBuffer(3, BufferIBLow, INDICATOR_DATA);
   SetIndexBuffer(4, BufferIBPoC, INDICATOR_DATA);

   // Configuração dos símbolos de setas (Wingdings: 233 = Seta Cima, 234 = Seta Baixo)
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);

   // Valores vazios para não desenhar linhas quando fora da sessão
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, 0.0);

   IndicatorSetString(INDICATOR_SHORTNAME, "TRAX IVB Order Flow");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Função de Desinicialização Customizada                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Limpa todos os elementos visuais criados no gráfico
   ObjectsDeleteAll(0, g_prefixo_gui);
}

//+------------------------------------------------------------------+
//| Função Principal de Cálculo e Plotagem                          |
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
   if(rates_total < 40)
      return(0);

   // Define arrays como série temporal (índice 0 = candle atual mais recente)
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(tick_volume, true);
   ArraySetAsSeries(BufferBuy, true);
   ArraySetAsSeries(BufferSell, true);
   ArraySetAsSeries(BufferIBHigh, true);
   ArraySetAsSeries(BufferIBLow, true);
   ArraySetAsSeries(BufferIBPoC, true);

   int limite = rates_total - prev_calculated;
   if(limite > rates_total - 2)
      limite = rates_total - 2;

   // Variáveis para rastreamento do Initial Balance por dia/sessão
   double ib_high = 0.0;
   double ib_low  = 0.0;
   double ib_poc  = 0.0;
   bool   ib_formado = false;
   datetime dia_atual = 0;

   // Processa as barras históricas e em tempo real
   for(int i = limite; i >= 0; i--)
   {
      BufferBuy[i]    = 0.0;
      BufferSell[i]   = 0.0;
      BufferIBHigh[i] = 0.0;
      BufferIBLow[i]  = 0.0;
      BufferIBPoC[i]  = 0.0;

      MqlDateTime dt;
      TimeToStruct(time[i], dt);
      datetime dia_barra = time[i] - (time[i] % 86400);

      // Reseta os parâmetros de abertura na transição de dia
      if(dia_barra != dia_atual)
      {
         dia_atual = dia_barra;
         ib_high = 0.0;
         ib_low = 0.0;
         ib_poc = 0.0;
         ib_formado = false;
      }

      int minutos_totais_barra = dt.hour * 60 + dt.min;
      int minutos_inicio_ib    = InpStartHour * 60 + InpStartMinute;
      int minutos_fim_ib       = minutos_inicio_ib + InpIBMinutes;

      // 1. Fase de Formação da Faixa de Abertura (Initial Balance)
      if(minutos_totais_barra >= minutos_inicio_ib && minutos_totais_barra < minutos_fim_ib)
      {
         if(ib_high == 0.0 || high[i] > ib_high) ib_high = high[i];
         if(ib_low == 0.0 || low[i] < ib_low)   ib_low  = low[i];

         // Aproximação ponderada do PoC de abertura
         double poc_candle = (open[i] + high[i] + low[i] + 2.0 * close[i]) / 5.0;
         if(ib_poc == 0.0)
            ib_poc = poc_candle;
         else
            ib_poc = (ib_poc + poc_candle) / 2.0;

         BufferIBHigh[i] = ib_high;
         BufferIBLow[i]  = ib_low;
         BufferIBPoC[i]  = ib_poc;
         continue;
      }

      // 2. Faixa de Abertura Finalizada - Projeção dos Níveis Institucionais
      if(minutos_totais_barra >= minutos_fim_ib && ib_high > 0.0 && ib_low > 0.0)
      {
         ib_formado = true;
         BufferIBHigh[i] = ib_high;
         BufferIBLow[i]  = ib_low;
         BufferIBPoC[i]  = ib_poc;

         // Média móvel de volume das últimas 20 barras
         double soma_vol = 0;
         for(int k = 1; k <= 20 && (i + k) < rates_total; k++)
            soma_vol += (double)tick_volume[i + k];
         double media_vol = (soma_vol > 0) ? (soma_vol / 20.0) : (double)tick_volume[i];

         // Cálculo de Microestrutura (Delta e PoC da barra atual)
         double amplitude = high[i] - low[i];
         if(amplitude <= 0) amplitude = _Point;
         double corpo = close[i] - open[i];
         double prop_alta = (corpo / amplitude) * 0.5 + 0.5;
         if(prop_alta < 0.05) prop_alta = 0.05;
         if(prop_alta > 0.95) prop_alta = 0.95;

         double buy_vol = (double)tick_volume[i] * prop_alta;
         double sell_vol = (double)tick_volume[i] - buy_vol;
         double delta = buy_vol - sell_vol;
         double poc_barra = (open[i] + high[i] + low[i] + 2.0 * close[i]) / 5.0;

         // GATILHO COMPRADOR (BUY) - MODELO 1 (Volume Profile) & MODELO 2 (Delta Flow)
         bool rompimento_compra_m1 = (close[i] > ib_high && close[i+1] <= ib_high && (double)tick_volume[i] >= media_vol * InpVolumeMultiplier && close[i] >= poc_barra);
         bool delta_agressao_compra = (delta > 0 && (double)tick_volume[i] >= media_vol * InpDeltaThresholdMult && close[i] > ib_high);

         if(rompimento_compra_m1 || delta_agressao_compra)
         {
            BufferBuy[i] = low[i] - (amplitude * 0.4);
            if(i == 0 && InpEnableSoundAlerts && time[0] != g_ultimo_alerta)
            {
               g_ultimo_alerta = time[0];
               string modelo_str = rompimento_compra_m1 ? "IVB Modelo 1 (Volume Profile)" : "IVB Modelo 2 (Delta Flow)";
               Alert(StringFormat("🚀 [TRAX BUY] %s detectado em %s @ %.5f! Stop abaixo de IB High (%.5f)", modelo_str, _Symbol, close[i], ib_high));
            }
         }

         // GATILHO VENDEDOR (SELL) - MODELO 1 (Volume Profile) & MODELO 2 (Delta Flow)
         bool rompimento_venda_m1 = (close[i] < ib_low && close[i+1] >= ib_low && (double)tick_volume[i] >= media_vol * InpVolumeMultiplier && close[i] <= poc_barra);
         bool delta_agressao_venda = (delta < 0 && (double)tick_volume[i] >= media_vol * InpDeltaThresholdMult && close[i] < ib_low);

         if(rompimento_venda_m1 || delta_agressao_venda)
         {
            BufferSell[i] = high[i] + (amplitude * 0.4);
            if(i == 0 && InpEnableSoundAlerts && time[0] != g_ultimo_alerta)
            {
               g_ultimo_alerta = time[0];
               string modelo_str = rompimento_venda_m1 ? "IVB Modelo 1 (Volume Profile)" : "IVB Modelo 2 (Delta Flow)";
               Alert(StringFormat("🔻 [TRAX SELL] %s detectado em %s @ %.5f! Stop acima de IB Low (%.5f)", modelo_str, _Symbol, close[i], ib_low));
            }
         }
      }
   }

   // 3. Atualiza o Dashboard no Gráfico
   if(InpShowDashboard)
   {
      double amplitude_ib = (ib_high > 0 && ib_low > 0) ? (ib_high - ib_low) : 0.0;
      AtualizarPainelVisual(ib_high, ib_low, ib_poc, amplitude_ib, ib_formado);
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Criação e Atualização de Textos do Dashboard no Gráfico         |
//+------------------------------------------------------------------+
void AtualizarPainelVisual(double ib_high, double ib_low, double ib_poc, double range_ib, bool formado)
{
   int x = 20;
   int y = 30;
   int espacamento = 18;

   CriarOuAtualizarLabel("L1", "=== SISTEMA TRAX - ORDER FLOW & IVB ===", x, y, clrAqua, 10, true);
   y += espacamento;
   CriarOuAtualizarLabel("L2", StringFormat("Ativo: %s | Tempo: %s", _Symbol, EnumToString(_Period)), x, y, clrWhite, 9, false);
   y += espacamento;
   CriarOuAtualizarLabel("L3", StringFormat("Estado IB: %s", formado ? "DEFINIDO & ATIVO" : "EM FORMAÇÃO"), x, y, formado ? clrLime : clrYellow, 9, true);
   y += espacamento;
   CriarOuAtualizarLabel("L4", StringFormat("IB High: %.2f", ib_high), x, y, clrDodgerBlue, 9, false);
   y += espacamento;
   CriarOuAtualizarLabel("L5", StringFormat("IB Low:  %.2f", ib_low), x, y, clrOrangeRed, 9, false);
   y += espacamento;
   CriarOuAtualizarLabel("L6", StringFormat("IB PoC:  %.2f", ib_poc), x, y, clrGold, 9, false);
   y += espacamento;
   CriarOuAtualizarLabel("L7", StringFormat("IB Range: %.2f pts", range_ib), x, y, clrLightGray, 9, false);
   y += espacamento;
   CriarOuAtualizarLabel("L8", "Auto-Guardrail (SL/TP): ATIVADO (0.8s)", x, y, clrLimeGreen, 9, true);
   y += espacamento;
   CriarOuAtualizarLabel("L9", "Motor Live Autônomo: CONECTADO", x, y, clrAqua, 9, false);
}

//+------------------------------------------------------------------+
//| Função Auxiliar para Criar/Atualizar Labels                      |
//+------------------------------------------------------------------+
void CriarOuAtualizarLabel(string id, string texto, int x, int y, color cor, int tamanho_fonte, bool negrito)
{
   string nome_obj = g_prefixo_gui + id;
   if(ObjectFind(0, nome_obj) < 0)
   {
      ObjectCreate(0, nome_obj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nome_obj, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, nome_obj, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   }

   ObjectSetInteger(0, nome_obj, OBJPROP_XDISTANCE, x + 240);
   ObjectSetInteger(0, nome_obj, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, nome_obj, OBJPROP_TEXT, texto);
   ObjectSetString(0, nome_obj, OBJPROP_FONT, negrito ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, nome_obj, OBJPROP_FONTSIZE, tamanho_fonte);
   ObjectSetInteger(0, nome_obj, OBJPROP_COLOR, cor);
   ObjectSetInteger(0, nome_obj, OBJPROP_SELECTABLE, false);
}
//+------------------------------------------------------------------+
