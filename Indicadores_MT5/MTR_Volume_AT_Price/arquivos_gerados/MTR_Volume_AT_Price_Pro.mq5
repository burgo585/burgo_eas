//+------------------------------------------------------------------+
//|                                    MTR-Volume-AT-Price-Pro.mq5   |
//|               Volume At Price & Auction Market Theory Pro        |
//|          Otimizado para Alta Performance em Qualquer Ativo       |
//+------------------------------------------------------------------+
#property copyright   "J Metra R Vieira & Antigravity Pro"
#property version     "3.40"
#property description "Volume At Price Pro: Banner de Ordem Operacional Visivel, Tape Tick-a-Tick em Tempo Real, Imas de Liquidez e Zonas de Aceleracao (HVN/LVN)."

#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_label1  "MTR Volume AT Price Pro"
#property indicator_type1   DRAW_NONE

//--- Modos de Faixa de Perfil
enum ENUM_MTR_VAP_RANGE
  {
   MTR_VAP_CURRENT_DAY   = 0, // Dia Atual (Sessao Intraday)
   MTR_VAP_PREVIOUS_DAY  = 1, // Dia Anterior Completo
   MTR_VAP_CURRENT_WEEK  = 2, // Semana Atual
   MTR_VAP_PREVIOUS_WEEK = 3, // Semana Anterior
   MTR_VAP_CURRENT_MONTH = 4, // Mes Atual
   MTR_VAP_PREVIOUS_MONTH= 5, // Mes Anterior
   MTR_VAP_LOOKBACK_BARS = 6, // Ultimas N Barras
   MTR_VAP_VISIBLE_RANGE = 7, // Faixa Visivel do Grafico
   MTR_VAP_SESSION       = 8, // Horario de Sessao Customizada
   MTR_VAP_FIXED_RANGE   = 9, // Intervalo entre Duas Ancoras
   MTR_VAP_ANCHORED      = 10 // Da Ancora ate o Preco Atual
  };

//--- Fonte de Volume
enum ENUM_MTR_VAP_VOLUME
  {
   MTR_VAP_VOLUME_AUTO       = 0, // Automatico (Real se disponivel; senao Ticks)
   MTR_VAP_VOLUME_REAL       = 1, // Somente Negocios Reais (Bolsa/B3/Acoes/Futuros)
   MTR_VAP_VOLUME_TICK_COUNT = 2  // Apenas Contagem de Ticks (Forex/CFD)
  };

//--- Posicao das Legendas de Preco
enum ENUM_MTR_VAP_LABEL_SIDE
  {
   MTR_VAP_LABEL_RIGHT = 0, // Legenda na Borda Direita
   MTR_VAP_LABEL_LEFT  = 1  // Legenda na Borda Esquerda
  };

//--- Tipo de Sinal de Entrada
enum ENUM_MTR_SIGNAL_MODE
  {
   MTR_SIGNAL_ALL       = 0, // Todos (Reversao VA + Rompimento + NPOC)
   MTR_SIGNAL_REVERSAL  = 1, // Apenas Rejeicao de Extremidade (Fade/Retorno a Media)
   MTR_SIGNAL_BREAKOUT  = 2, // Apenas Rompimento de Valor (Tendencia/Expansao)
   MTR_SIGNAL_NONE      = 3  // Desativar Sinais
  };

//--- Estado Operacional do Sistema de Decisao
enum ENUM_MTR_TRADE_STATE
  {
   TRADE_STATE_NEUTRAL,     // Aguardando aproximacao de zonas chave
   TRADE_STATE_PREP_BUY,    // PREPARAR COMPRA (preco em desconto no VAL)
   TRADE_STATE_PREP_SELL,   // PREPARAR VENDA (preco em premio no VAH)
   TRADE_STATE_ACTIVE_BUY,  // SINAL CONFIRMADO: ENTRAR COMPRA AGORA!
   TRADE_STATE_ACTIVE_SELL, // SINAL CONFIRMADO: ENTRAR VENDA AGORA!
   TRADE_STATE_TP1_HIT,     // ALVO 1 (POC) ATINGIDO! HORA DE REALIZAR PARCIAL
   TRADE_STATE_TP2_HIT,     // ALVO FINAL ATINGIDO! HORA DE SAIR COM LUCRO TOTAL
   TRADE_STATE_STOP_HIT     // STOP LOSS ATINGIDO! HORA DE SAIR (PROTECAO)
  };

//--- Entradas do Usuario
input group "=== Configuracao do Ativo e Faixa ==="
input bool                  InpUseCurrentSymbol     = true;                 // Usar simbolo atual do grafico
input string                InpSymbol               = "";                   // Simbolo especifico (vazio = atual)
input ENUM_MTR_VAP_RANGE    InpRangeMode            = MTR_VAP_CURRENT_DAY;  // Faixa de perfil padrao
input int                   InpLookbackBars         = 200;                  // Barras lookback (se modo N barras)
input string                InpInstanceId           = "PRO";                // Identificador unico da instancia
input int                   InpSessionStartHour     = 0;                    // Inicio da sessao: hora
input int                   InpSessionStartMinute   = 0;                    // Inicio da sessao: minuto
input int                   InpSessionEndHour       = 23;                   // Fim da sessao: hora
input int                   InpSessionEndMinute     = 59;                   // Fim da sessao: minuto

input group "=== Resolucao Adaptativa (Multi-Ativo) ==="
input bool                  InpAutoStep             = true;                 // [CRITICO] Degrau Automatico (Qualquer Ativo)
input int                   InpTargetLevels         = 70;                   // Qtd de Niveis Desejada no Perfil (30 a 120)
input int                   InpTicksPerLevel        = 25;                   // Ticks por nivel (apenas se Degrau Auto = false)
input ENUM_MTR_VAP_VOLUME   InpVolumeSource         = MTR_VAP_VOLUME_AUTO;  // Fonte de volume
input double                InpValueAreaPercent     = 68.2;                 // Value Area % (68.2% = 1 Desvio Padrao)
input ENUM_TIMEFRAMES       InpCalculationTimeframe = PERIOD_M1;            // Timeframe para interpolacao/fallback

input group "=== Performance & Anti-Travamento (Anti-Lag) ==="
input int                   InpRefreshSeconds       = 4;                    // Atualizacao segura do Timer (segundos)
input int                   InpMaxTicksToLoad       = 100000;               // Limite max. de ticks por leitura (Evita travar MT5)
input bool                  InpUseRatesForLongRange = true;                 // Usar barras M1 se periodo > 24h (Ultra Rapido)
input int                   InpThrottlePriceMoves   = 2;                    // Recalcular apenas se mover N ticks (Economiza CPU)

input group "=== Exibicao Grafica do Perfil ==="
input int                   InpMaximumWidthBars     = 40;                   // Largura max. do perfil em barras
input double                InpProfileWidthPercent  = 20.0;                 // Largura percentual da tela
input bool                  InpAnchorAtChartRight   = true;                 // Ancorar a direita da tela
input int                   InpRightMarginPixels    = 6;                    // Margem direita (pixels)
input bool                  InpShowValueArea        = true;                 // Destacar Value Area (VAH / VAL)
input bool                  InpShowPocLine          = true;                 // Desenhar linha do POC
input bool                  InpShowVwap             = true;                 // Desenhar VWAP institucional
input bool                  InpShowProfileHighLow   = true;                 // Extremos do Perfil (High / Low)
input bool                  InpShowBuySell          = true;                 // Separar Delta Comprador/Vendedor no Histograma
input bool                  InpShowLevelLabels      = true;                 // Exibir etiquetas de preco dos niveis
input ENUM_MTR_VAP_LABEL_SIDE InpLevelLabelSide     = MTR_VAP_LABEL_RIGHT;  // Lado das legendas de preco
input int                   InpFixedLabelMarginPixels = 12;                 // Margem da legenda (pixels)
input bool                  InpExtendLevelsRight    = true;                 // Estender linhas ate o preco atual
input color                 InpProfileColor         = C'42,48,60';          // Cor fora da Value Area (Neutro)
input color                 InpValueAreaColor       = C'41,128,185';        // Cor dentro da Value Area (Azul)
input color                 InpPocColor             = clrGold;              // Cor do POC (Ponto de Controle)
input color                 InpValueAreaLineColor   = clrSilver;            // Linhas VAH / VAL
input color                 InpVwapColor            = clrAqua;              // Linha VWAP
input color                 InpHighLowColor         = clrSlateGray;         // Extremos High / Low
input color                 InpBuyColor             = C'39,174,96';         // Volume Comprador (Verde)
input color                 InpSellColor            = C'192,57,43';         // Volume Vendedor (Vermelho)
input int                   InpFontSize             = 8;                    // Tamanho da fonte

input group "=== Nos de Volume (HVN e LVN) ==="
input bool                  InpShowHvn              = true;                 // Destacar High Volume Nodes (Aceitacao/Suporte)
input bool                  InpShowLvn              = true;                 // Destacar Low Volume Nodes (Rejeicao/Aceleracao)
input double                InpHvnThresholdPercent  = 75.0;                 // Limiar HVN (% do pico do POC)
input double                InpLvnThresholdPercent  = 15.0;                 // Limiar LVN (% do pico do POC)
input color                 InpHvnColor             = clrMediumSlateBlue;   // Cor do patamar HVN
input color                 InpLvnColor             = clrDarkOrange;        // Cor do patamar LVN
input bool                  InpDrawNodeLines        = true;                 // Desenhar Linhas de HVN/LVN no Grafico
input int                   InpMaxNodesToDraw       = 3;                    // Qtd maxima de linhas HVN/LVN desenhadas
input int                   InpMinimumNodeSpacingLevels = 4;                // Espacamento minimo entre nos de volume

input group "=== Contexto Historico em Cache (Zero Lag) ==="
input bool                  InpShowPreviousPeriod   = true;                 // Exibir POC, VAH e VAL do Periodo Anterior
input bool                  InpShowUntestedPocs     = true;                 // Naked POCs (Imas Institucionais de Liquidez)
input int                   InpUntestedDailyPeriods = 3;                    // Dias historicos para Naked POCs
input int                   InpUntestedWeeklyPeriods= 2;                    // Semanas historicas para Naked POCs
input color                 InpPreviousLevelColor   = clrMediumOrchid;      // Cor dos niveis do periodo anterior
input color                 InpUntestedPocColor     = clrDeepPink;          // Cor de Naked POCs

input group "=== Sinais de Alta Probabilidade (Entradas) ==="
input ENUM_MTR_SIGNAL_MODE  InpSignalMode           = MTR_SIGNAL_ALL;       // Modo de identificacao de entradas
input bool                  InpFilterTrendWithEma   = true;                 // Filtrar sinais a favor da tendencia (EMA)
input int                   InpTrendEmaPeriod       = 50;                   // Periodo da EMA de tendencia
input ENUM_TIMEFRAMES       InpTrendTimeframe       = PERIOD_H1;            // Timeframe da EMA de tendencia
input double                InpSignalMinVolumeFactor= 1.15;                 // Volume minimo relativo na barra do sinal
input bool                  InpAlertPopup           = true;                 // Alerta Popup na tela
input bool                  InpAlertSound           = true;                 // Alerta Sonoro
input bool                  InpAlertPush            = false;                // Notificacao no Celular (MT5 App)
input color                 InpBuySignalColor       = clrLime;              // Cor da Seta de Compra
input color                 InpSellSignalColor      = clrRed;               // Cor da Seta de Venda

input group "=== Painel Visual Draggable (Arrastavel & Minimizavel) ==="
input bool                  InpShowTradeCard        = true;                 // Exibir Card de Decisao no Grafico
input ENUM_BASE_CORNER      InpCardCorner           = CORNER_LEFT_UPPER;    // Posicao inicial do Card
input int                   InpCardX                = 20;                   // Posicao X inicial (pixels)
input int                   InpCardY                = 35;                   // Posicao Y inicial (pixels)
input int                   InpCardFontSize         = 9;                    // Tamanho da fonte do Card
input bool                  InpDrawTradeLevels      = true;                 // Desenhar Linhas de Entrada/Stop/Alvos no Grafico
input bool                  InpAlertPrepare         = true;                 // Alerta antecipado: "PREPARAR ENTRADA"
input color                 InpCardBgColor          = C'16,20,28';          // Fundo 100% Opaco (Sobrepoe Grafico)
input color                 InpCardBorderColor      = C'41,128,185';        // Cor da borda do Card
input color                 InpCardHeaderColor      = C'25,32,44';          // Cor da barra de titulo (Arrastavel)

input group "=== Mini Painel Informativo Secundario (Opcional) ==="
input bool                  InpShowInfoPanel        = false;                // Exibir mini painel com dados brutos
input int                   InpPanelX               = 20;                   // Posicao X
input int                   InpPanelY               = 360;                  // Posicao Y
input int                   InpPanelLineSpacing     = 16;                   // Espacamento

//--- Buffer dummy
double DummyBuffer[];

//--- Estruturas
struct MTR_PROFILE_STATS
  {
   bool     valid;
   datetime from_time;
   datetime to_time;
   double   poc;
   double   vah;
   double   val;
   double   high;
   double   low;
   double   total;
  };

struct MTR_NAKED_POC
  {
   double   price;
   datetime time_start;
   string   label;
   bool     tested;
  };

struct MTR_VOLUME_NODE
  {
   double   price;
   double   volume;
   bool     is_hvn;
   string   label;
  };

//--- Variaveis Globais
string            g_symbol            = "";
string            g_prefix            = "";
datetime          g_last_bar_time     = 0;
datetime          g_last_calc_time    = 0;
double            g_last_calc_price   = 0.0;
string            g_anchor_start      = "";
string            g_anchor_end        = "";
datetime          g_last_signal_time  = 0;
int               g_used_label_y[];
int               g_prev_hist_bars    = 0;

//--- Cache historico e Nos de Volume
datetime          g_last_hist_day_calc = 0;
MTR_PROFILE_STATS g_cached_prev_period;
MTR_NAKED_POC     g_cached_daily_pocs[];
MTR_NAKED_POC     g_cached_weekly_pocs[];
MTR_VOLUME_NODE   g_detected_hvns[];
MTR_VOLUME_NODE   g_detected_lvns[];

//--- Rota e Ima de Liquidez Imediato
double            g_next_magnet_price  = 0.0;
string            g_next_magnet_type   = "";
double            g_next_magnet_dist   = 0.0;
string            g_route_description  = "";

//--- Monitor Tick-a-Tick Intra-Candle (Tempo Real)
datetime          g_cur_candle_time       = 0;
long              g_cur_candle_ticks      = 0;
double            g_cur_candle_buy_vol    = 0.0;
double            g_cur_candle_sell_vol   = 0.0;
double            g_cur_candle_delta      = 0.0;
double            g_cur_candle_prev_p     = 0.0;
string            g_cur_candle_flow_desc  = "";
string            g_cur_candle_absorp     = "";

//--- Estado Operacional do Trade (Sinais, Entrada, Alvo, Stop)
ENUM_MTR_TRADE_STATE g_trade_state       = TRADE_STATE_NEUTRAL;
double            g_active_entry_price   = 0.0;
double            g_active_sl_price      = 0.0;
double            g_active_tp1_price     = 0.0;
double            g_active_tp2_price     = 0.0;
string            g_active_setup_name    = "";
datetime          g_active_signal_time   = 0;
string            g_prep_text            = "";
bool              g_alerted_prep_buy     = false;
bool              g_alerted_prep_sell    = false;
bool              g_tp1_alerted          = false;
bool              g_tp2_alerted          = false;
bool              g_stop_alerted         = false;

//--- Variaveis do Card Flutuante (Arrasto & Minimizacao)
int               g_card_x             = -1;
int               g_card_y             = -1;
int               g_card_width         = 460;
int               g_card_height        = 236;
bool              g_card_minimized     = false;
bool              g_is_dragging        = false;
int               g_drag_offset_x      = 0;
int               g_drag_offset_y      = 0;

//--- Declaracoes de Funcoes
bool   ResolveRange(datetime &from_time, datetime &to_time);
void   DrawProfile(bool force);
double CalculateAdaptiveStep(double min_price, double max_price, double tick_size);
void   UpdateHistoricalCache(datetime now);
bool   CalculateProfileStats(datetime from_time, datetime to_time, ENUM_TIMEFRAMES tf, MTR_PROFILE_STATS &stats);
bool   WasPriceTested(double price, datetime after_time, datetime until_time, ENUM_TIMEFRAMES tf);
void   DetectVolumeNodesAndMagnets(const double &profile[], int levels, double min_price, double price_step,
                                  double max_volume, int poc, double vah_price, double val_price, double cur_price);
void   CalculateNextMagnetAndRoute(double cur_price, double poc_price, double vah_price, double val_price);
void   CheckTradeSignals(double poc, double vah, double val, double vwap);
void   MonitorActiveTrade(double cur_price);
void   ProcessRealTimeTick(datetime newest, const double &open[], const double &high[], const double &low[],
                           const double &close[], const long &tick_volume[], const long &volume[], int rates_total);
void   UpdateRealTimeCardTick(double cur_price);
void   TriggerAlert(string type_str, string reason_str, double entry_price, double target_price);
void   DrawHistogramBars(const double &profile[], const double &buy_profile[], const double &sell_profile[],
                         int levels, double min_price, double price_step, double max_volume,
                         datetime to_time, int poc, int val, int vah);
void   DrawReferenceLevels(datetime from_time, datetime to_time, double min_price, double max_price,
                           double price_step, int poc, int val, int vah, double vwap);
void   DrawCachedHistoricalLevels(datetime current_from);
void   DrawTradeDecisionCard(double cur_price, double poc, double vah, double val, double vwap);
void   UpdateCardPositions();
void   DrawActiveTradeLines();
void   DrawInfoPanel(string source_str, string delta_str, double total_vol, double buy_vol, double sell_vol,
                     double poc, double vwap, double vah, double val, double price_step);
void   DrawScreenProfileRectangle(string name, int right_offset, int width, double low_price, double high_price, color col);
void   DrawFixedPriceLabel(string suffix, double price, string text_val, color text_col);
int    FindReadableLabelY(int desired_y);
double LevelMidPrice(double min_price, double price_step, int level);
datetime GetChartRightTime(datetime fallback_time);
datetime StartOfDay(datetime value);
datetime StartOfWeek(datetime value);
datetime StartOfMonth(datetime value);
bool     ResolveSessionRange(datetime now, datetime &from_time, datetime &to_time);
void     EnsureRangeAnchors();
void     DeleteAllObjects(bool include_anchors);
string   FormatVolume(double val);
string   FormatSignedVolume(double val);
void     DrawPanelLine(int line, string text_val, color text_col, bool bold);

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, DummyBuffer, INDICATOR_DATA);
   IndicatorSetString(INDICATOR_SHORTNAME, "MTR-Volume-AT-Price-Pro");

   g_symbol = (InpUseCurrentSymbol || InpSymbol == "") ? _Symbol : InpSymbol;
   if(!SymbolSelect(g_symbol, true))
     {
      Print("MTR-Volume-AT-Price-Pro: Impossivel selecionar o simbolo: ", g_symbol);
      return(INIT_FAILED);
     }

   g_prefix = "MTR_VAP_" + IntegerToString((int)ChartID()) + "_" +
              InpInstanceId + "_" + IntegerToString((int)GetTickCount()) + "_";
   g_anchor_start = g_prefix + "ANC_START";
   g_anchor_end   = g_prefix + "ANC_END";

   g_last_bar_time      = 0;
   g_last_calc_time     = 0;
   g_last_calc_price    = 0.0;
   g_last_signal_time   = 0;
   g_prev_hist_bars     = 0;
   g_last_hist_day_calc = 0;

   g_trade_state        = TRADE_STATE_NEUTRAL;
   g_active_entry_price = 0.0;
   g_active_sl_price    = 0.0;
   g_active_tp1_price   = 0.0;
   g_active_tp2_price   = 0.0;
   g_active_setup_name  = "";
   g_active_signal_time = 0;
   g_prep_text          = "";
   g_alerted_prep_buy   = false;
   g_alerted_prep_sell  = false;
   g_tp1_alerted        = false;
   g_tp2_alerted        = false;
   g_stop_alerted       = false;

   // Habilita captura de mouse para arrastar o painel
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

   // Calcula coordenadas iniciais do Card
   long chart_w = 0;
   ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, chart_w);
   if(InpCardCorner == CORNER_RIGHT_UPPER && chart_w > 0)
      g_card_x = (int)chart_w - InpCardX - g_card_width;
   else if(InpCardCorner == CORNER_RIGHT_LOWER && chart_w > 0)
      g_card_x = (int)chart_w - InpCardX - g_card_width;
   else
      g_card_x = InpCardX;
   g_card_y = InpCardY;

   // Inicializa o cache historico imediatamente
   UpdateHistoricalCache(TimeCurrent());

   if(InpRefreshSeconds > 0)
      EventSetTimer(MathMax(1, InpRefreshSeconds));

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);
   DeleteAllObjects(true);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   DrawProfile(false);
  }

//+------------------------------------------------------------------+
//| ChartEvent function (Arrasto do Painel e Minimizacao)            |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   // 1. Redimensionamento de tela
   if(id == CHARTEVENT_CHART_CHANGE)
     {
      DrawProfile(false);
      return;
     }

   // 2. Ancoras do perfil
   if(id == CHARTEVENT_OBJECT_DRAG && (sparam == g_anchor_start || sparam == g_anchor_end))
     {
      DrawProfile(true);
      return;
     }

   // 3. Clique no botao de minimizar/maximizar
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == g_prefix + "CARD_BTN_MIN")
     {
      g_card_minimized = !g_card_minimized;
      ObjectSetInteger(0, g_prefix + "CARD_BTN_MIN", OBJPROP_STATE, false);
      DrawProfile(true);
      ChartRedraw(0);
      return;
     }

   // 4. Mover / Arrastar Card com o Mouse (Click & Drag suave)
   if(id == CHARTEVENT_MOUSE_MOVE && InpShowTradeCard)
     {
      int mouse_x = (int)lparam;
      int mouse_y = (int)dparam;
      uint flags  = (uint)StringToInteger(sparam);
      bool left_pressed = ((flags & 1) != 0);

      if(left_pressed)
        {
         if(!g_is_dragging)
           {
            // Detecta clique na barra de titulo do painel (altura 28px)
            if(mouse_x >= g_card_x && mouse_x <= (g_card_x + g_card_width - 32) &&
               mouse_y >= g_card_y && mouse_y <= (g_card_y + 28))
              {
               g_is_dragging   = true;
               g_drag_offset_x = mouse_x - g_card_x;
               g_drag_offset_y = mouse_y - g_card_y;
              }
           }
         else
           {
            // Arrastando o painel: atualiza coordenadas
            long cw = 0, ch = 0;
            ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, cw);
            ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0, ch);
            if(cw <= 0) cw = 1200;
            if(ch <= 0) ch = 800;

            int new_x = mouse_x - g_drag_offset_x;
            int new_y = mouse_y - g_drag_offset_y;

            g_card_x = MathMax(2, MathMin((int)cw - 80, new_x));
            g_card_y = MathMax(2, MathMin((int)ch - 30, new_y));

            UpdateCardPositions();
            ChartRedraw(0);
           }
        }
      else
        {
         if(g_is_dragging)
           {
            g_is_dragging = false;
            UpdateCardPositions();
            ChartRedraw(0);
           }
        }
     }
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
   if(rates_total <= 0)
      return(0);

   datetime newest = time[rates_total - 1];
   if(ArrayGetAsSeries(time))
      newest = time[0];

   // 1. Processamento ultra-leve e em tempo real a CADA TICK do candle atual [0]
   ProcessRealTimeTick(newest, open, high, low, close, tick_volume, volume, rates_total);

   // 2. Se nova barra abriu, recalcula o perfil completo
   if(newest != g_last_bar_time)
     {
      g_last_bar_time = newest;
      DrawProfile(true);
     }

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Funcao Central de Construcao do Perfil (Com Anti-Lag Otimizado)  |
//+------------------------------------------------------------------+
void DrawProfile(bool force)
  {
   datetime now = TimeCurrent();

   double current_price = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   if(current_price <= 0.0)
      current_price = SymbolInfoDouble(g_symbol, SYMBOL_LAST);

   double tick_size = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      tick_size = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   if(tick_size <= 0.0)
      tick_size = _Point;

   if(!force)
     {
      if(now - g_last_calc_time < (datetime)InpRefreshSeconds)
         return;

      if(g_last_calc_price > 0.0 && InpThrottlePriceMoves > 0)
        {
         double price_diff_ticks = MathAbs(current_price - g_last_calc_price) / tick_size;
         if(price_diff_ticks < InpThrottlePriceMoves && (now - g_last_calc_time < (datetime)(InpRefreshSeconds * 3)))
           {
            MonitorActiveTrade(current_price);
            return;
           }
        }
     }

   datetime from_time = 0;
   datetime to_time   = now;
   if(!ResolveRange(from_time, to_time) || from_time >= to_time)
      return;

   if(StartOfDay(now) != g_last_hist_day_calc)
      UpdateHistoricalCache(now);

   long span_seconds = (long)(to_time - from_time);
   bool use_bars_direct = false;
   if(InpUseRatesForLongRange && span_seconds > 86400 * 2)
      use_bars_direct = true;

   MqlTick ticks[];
   int copied_ticks = 0;
   bool use_real_trades = false;

   if(!use_bars_direct && InpVolumeSource != MTR_VAP_VOLUME_TICK_COUNT)
     {
      ulong from_msc = (ulong)from_time * 1000;
      ulong to_msc   = (ulong)(to_time + 1) * 1000;
      copied_ticks   = CopyTicksRange(g_symbol, ticks, COPY_TICKS_ALL, from_msc, to_msc);

      if(copied_ticks > InpMaxTicksToLoad)
        {
         copied_ticks = 0;
         use_bars_direct = true;
        }
      else if(copied_ticks > 0)
        {
         for(int i = 0; i < copied_ticks && i < 200; i++)
           {
            if(ticks[i].volume_real > 0.0 || ticks[i].volume > 0)
              {
               use_real_trades = true;
               break;
              }
           }
        }
     }

   double min_price = DBL_MAX;
   double max_price = -DBL_MAX;

   MqlRates rates[];
   int rates_copied = 0;

   if(copied_ticks > 0 && !use_bars_direct)
     {
      for(int i = 0; i < copied_ticks; i++)
        {
         double p = (ticks[i].last > 0.0) ? ticks[i].last : ((ticks[i].bid > 0.0) ? ticks[i].bid : ticks[i].ask);
         if(p <= 0.0) continue;
         if(p < min_price) min_price = p;
         if(p > max_price) max_price = p;
        }
     }
   else
     {
      rates_copied = CopyRates(g_symbol, InpCalculationTimeframe, from_time, to_time, rates);
      if(rates_copied <= 0)
         rates_copied = CopyRates(g_symbol, _Period, from_time, to_time, rates);

      if(rates_copied > 0)
        {
         use_bars_direct = true;
         for(int i = 0; i < rates_copied; i++)
           {
            if(rates[i].low < min_price) min_price = rates[i].low;
            if(rates[i].high > max_price) max_price = rates[i].high;
           }
        }
     }

   if(min_price == DBL_MAX || max_price <= min_price)
      return;

   double price_step = CalculateAdaptiveStep(min_price, max_price, tick_size);
   if(price_step <= 0.0)
      price_step = tick_size;

   min_price = MathFloor(min_price / price_step) * price_step;
   int levels = (int)MathFloor((max_price - min_price) / price_step) + 1;
   if(levels < 1) levels = 1;
   if(levels > 300) levels = 300;

   double profile[];
   double buy_profile[];
   double sell_profile[];
   ArrayResize(profile, levels);
   ArrayResize(buy_profile, levels);
   ArrayResize(sell_profile, levels);
   ArrayInitialize(profile, 0.0);
   ArrayInitialize(buy_profile, 0.0);
   ArrayInitialize(sell_profile, 0.0);

   bool aggressor_reliable = false;

   if(use_bars_direct && rates_copied > 0)
     {
      for(int i = 0; i < rates_copied; i++)
        {
         int first = (int)MathFloor((rates[i].low - min_price) / price_step);
         int last  = (int)MathFloor((rates[i].high - min_price) / price_step);
         first = MathMax(0, MathMin(first, levels - 1));
         last  = MathMax(0, MathMin(last, levels - 1));
         if(last < first) { int tmp = first; first = last; last = tmp; }

         int touched = MathMax(1, last - first + 1);
         double bar_vol = (rates[i].real_volume > 0) ? (double)rates[i].real_volume : (double)rates[i].tick_volume;
         if(bar_vol <= 0.0) bar_vol = 1.0;
         double vol_per_level = bar_vol / touched;

         double range = MathMax(price_step, rates[i].high - rates[i].low);
         double buy_ratio = MathMax(0.0, MathMin(1.0, (rates[i].close - rates[i].low) / range));

         for(int lvl = first; lvl <= last; lvl++)
           {
            profile[lvl]      += vol_per_level;
            buy_profile[lvl]  += vol_per_level * buy_ratio;
            sell_profile[lvl] += vol_per_level * (1.0 - buy_ratio);
           }
        }
     }
   else if(copied_ticks > 0)
     {
      double prev_p = 0.0;
      for(int i = 0; i < copied_ticks; i++)
        {
         double p = (ticks[i].last > 0.0) ? ticks[i].last : ((ticks[i].bid > 0.0) ? ticks[i].bid : ticks[i].ask);
         if(p <= 0.0) continue;

         int lvl = (int)MathFloor((p - min_price) / price_step);
         lvl = MathMax(0, MathMin(lvl, levels - 1));

         double val = 1.0;
         if(use_real_trades && (ticks[i].volume_real > 0.0 || ticks[i].volume > 0))
            val = (ticks[i].volume_real > 0.0) ? ticks[i].volume_real : (double)ticks[i].volume;

         profile[lvl] += val;

         bool is_buy  = ((ticks[i].flags & TICK_FLAG_BUY) == TICK_FLAG_BUY);
         bool is_sell = ((ticks[i].flags & TICK_FLAG_SELL) == TICK_FLAG_SELL);

         if(is_buy && !is_sell)
            buy_profile[lvl] += val;
         else if(is_sell && !is_buy)
            sell_profile[lvl] += val;
         else if(prev_p > 0.0 && p > prev_p)
            buy_profile[lvl] += val;
         else if(prev_p > 0.0 && p < prev_p)
            sell_profile[lvl] += val;
         else
           {
            buy_profile[lvl]  += val * 0.5;
            sell_profile[lvl] += val * 0.5;
           }
         prev_p = p;
        }
      aggressor_reliable = use_real_trades;
     }

   double total_volume = 0.0;
   double total_buy    = 0.0;
   double total_sell   = 0.0;
   double weighted_sum = 0.0;
   double max_volume   = 0.0;
   int    poc          = -1;

   for(int i = 0; i < levels; i++)
     {
      total_volume += profile[i];
      total_buy    += buy_profile[i];
      total_sell   += sell_profile[i];
      weighted_sum += profile[i] * LevelMidPrice(min_price, price_step, i);
      if(profile[i] > max_volume)
        {
         max_volume = profile[i];
         poc = i;
        }
     }

   if(poc < 0 || max_volume <= 0.0)
      return;

   int val = poc;
   int vah = poc;
   double target_vol = total_volume * MathMax(1.0, MathMin(100.0, InpValueAreaPercent)) / 100.0;
   double acc_vol    = profile[poc];

   while(acc_vol < target_vol && (val > 0 || vah < levels - 1))
     {
      double below = (val > 0) ? profile[val - 1] : -1.0;
      double above = (vah < levels - 1) ? profile[vah + 1] : -1.0;

      if(above >= below && vah < levels - 1)
        {
         vah++;
         acc_vol += profile[vah];
        }
      else if(val > 0)
        {
         val--;
         acc_vol += profile[val];
        }
      else
         break;
     }

   double vwap = (total_volume > 0.0) ? (weighted_sum / total_volume) : 0.0;

   double poc_price = LevelMidPrice(min_price, price_step, poc);
   double vah_price = min_price + (vah + 1) * price_step;
   double val_price = min_price + val * price_step;

   ArrayResize(g_used_label_y, 0);

   DrawHistogramBars(profile, buy_profile, sell_profile, levels,
                     min_price, price_step, max_volume,
                     to_time, poc, val, vah);

   DetectVolumeNodesAndMagnets(profile, levels, min_price, price_step,
                               max_volume, poc, vah_price, val_price, current_price);

   DrawReferenceLevels(from_time, to_time, min_price, max_price,
                       price_step, poc, val, vah, vwap);

   if(InpShowPreviousPeriod || InpShowUntestedPocs)
      DrawCachedHistoricalLevels(from_time);

   if(InpSignalMode != MTR_SIGNAL_NONE)
      CheckTradeSignals(poc_price, vah_price, val_price, vwap);

   MonitorActiveTrade(current_price);

   if(InpShowTradeCard)
      DrawTradeDecisionCard(current_price, poc_price, vah_price, val_price, vwap);

   if(InpDrawTradeLevels)
      DrawActiveTradeLines();

   if(InpShowInfoPanel)
     {
      string src_str   = use_bars_direct ? "BARRAS_M1" : (use_real_trades ? "REAL_TICKS" : "TICK_VOL");
      string delta_str = aggressor_reliable ? "DELTA_REAL" : "DELTA_ESTIMADO";
      DrawInfoPanel(src_str, delta_str, total_volume, total_buy, total_sell,
                    poc_price, vwap, vah_price, val_price, price_step);
     }

   g_last_calc_time  = now;
   g_last_calc_price = current_price;
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Calculo do Degrau Adaptativo de Preco (Universal)                |
//+------------------------------------------------------------------+
double CalculateAdaptiveStep(double min_price, double max_price, double tick_size)
  {
   if(!InpAutoStep)
      return(tick_size * MathMax(1, InpTicksPerLevel));

   double range = max_price - min_price;
   if(range <= 0.0)
      range = tick_size * 100.0;

   int target = MathMax(20, MathMin(150, InpTargetLevels));
   double raw_step = range / target;

   long ticks_in_step = (long)MathRound(raw_step / tick_size);
   if(ticks_in_step < 1)
      ticks_in_step = 1;

   return(ticks_in_step * tick_size);
  }

//+------------------------------------------------------------------+
//| Atualizacao Inteligente de Cache Historico (Executado 1x por dia)|
//+------------------------------------------------------------------+
void UpdateHistoricalCache(datetime now)
  {
   g_last_hist_day_calc = StartOfDay(now);

   datetime prev_from = 0, prev_to = 0;
   datetime today = StartOfDay(now);
   prev_from = today - 86400;
   prev_to   = today - 1;

   g_cached_prev_period.valid = false;
   CalculateProfileStats(prev_from, prev_to, PERIOD_M5, g_cached_prev_period);

   ArrayResize(g_cached_daily_pocs, 0);
   int daily_count = MathMax(0, MathMin(10, InpUntestedDailyPeriods));
   for(int i = 1; i <= daily_count; i++)
     {
      datetime d_to   = today - (i - 1) * 86400 - 1;
      datetime d_from = StartOfDay(d_to);
      MTR_PROFILE_STATS st;
      if(CalculateProfileStats(d_from, d_to, PERIOD_M5, st))
        {
         if(!WasPriceTested(st.poc, d_to + 1, now, PERIOD_M15))
           {
            int sz = ArraySize(g_cached_daily_pocs);
            ArrayResize(g_cached_daily_pocs, sz + 1);
            g_cached_daily_pocs[sz].price      = st.poc;
            g_cached_daily_pocs[sz].time_start = d_to;
            g_cached_daily_pocs[sz].label      = "NPOC_D" + IntegerToString(i);
            g_cached_daily_pocs[sz].tested     = false;
           }
        }
     }

   ArrayResize(g_cached_weekly_pocs, 0);
   int weekly_count = MathMax(0, MathMin(5, InpUntestedWeeklyPeriods));
   datetime this_week = StartOfWeek(now);
   for(int i = 1; i <= weekly_count; i++)
     {
      datetime w_to   = this_week - (i - 1) * 7 * 86400 - 1;
      datetime w_from = StartOfWeek(w_to);
      MTR_PROFILE_STATS st;
      if(CalculateProfileStats(w_from, w_to, PERIOD_M15, st))
        {
         if(!WasPriceTested(st.poc, w_to + 1, now, PERIOD_H1))
           {
            int sz = ArraySize(g_cached_weekly_pocs);
            ArrayResize(g_cached_weekly_pocs, sz + 1);
            g_cached_weekly_pocs[sz].price      = st.poc;
            g_cached_weekly_pocs[sz].time_start = w_to;
            g_cached_weekly_pocs[sz].label      = "NPOC_W" + IntegerToString(i);
            g_cached_weekly_pocs[sz].tested     = false;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Calculo de Estatisticas de Perfil via Barras (Ultra Leve)        |
//+------------------------------------------------------------------+
bool CalculateProfileStats(datetime from_time, datetime to_time, ENUM_TIMEFRAMES tf, MTR_PROFILE_STATS &stats)
  {
   stats.valid = false;
   MqlRates rates[];
   int copied = CopyRates(g_symbol, tf, from_time, to_time, rates);
   if(copied < 5)
      return(false);

   double low  = DBL_MAX;
   double high = -DBL_MAX;
   for(int i = 0; i < copied; i++)
     {
      if(rates[i].low < low)   low  = rates[i].low;
      if(rates[i].high > high) high = rates[i].high;
     }

   double tick_size = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0) tick_size = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   if(tick_size <= 0.0) tick_size = _Point;

   double step = CalculateAdaptiveStep(low, high, tick_size);
   low = MathFloor(low / step) * step;
   int levels = (int)MathFloor((high - low) / step) + 1;
   if(levels < 1 || levels > 250) return(false);

   double prof[];
   ArrayResize(prof, levels);
   ArrayInitialize(prof, 0.0);

   for(int i = 0; i < copied; i++)
     {
      int first = (int)MathFloor((rates[i].low - low) / step);
      int last  = (int)MathFloor((rates[i].high - low) / step);
      first = MathMax(0, MathMin(first, levels - 1));
      last  = MathMax(0, MathMin(last, levels - 1));
      if(last < first) { int tmp = first; first = last; last = tmp; }
      int cnt = MathMax(1, last - first + 1);
      double vol = (rates[i].real_volume > 0) ? (double)rates[i].real_volume : (double)rates[i].tick_volume;
      double vpl = vol / cnt;
      for(int l = first; l <= last; l++)
         prof[l] += vpl;
     }

   double total = 0.0;
   double max_v = 0.0;
   int poc = -1;
   for(int i = 0; i < levels; i++)
     {
      total += prof[i];
      if(prof[i] > max_v)
        {
         max_v = prof[i];
         poc = i;
        }
     }
   if(poc < 0 || total <= 0.0) return(false);

   int val = poc, vah = poc;
   double target = total * InpValueAreaPercent / 100.0;
   double acc = prof[poc];
   while(acc < target && (val > 0 || vah < levels - 1))
     {
      double b = (val > 0) ? prof[val - 1] : -1.0;
      double a = (vah < levels - 1) ? prof[vah + 1] : -1.0;
      if(a >= b && vah < levels - 1) { vah++; acc += prof[vah]; }
      else if(val > 0) { val--; acc += prof[val]; }
      else break;
     }

   stats.valid     = true;
   stats.from_time = from_time;
   stats.to_time   = to_time;
   stats.poc       = LevelMidPrice(low, step, poc);
   stats.val       = low + val * step;
   stats.vah       = low + (vah + 1) * step;
   stats.low       = low;
   stats.high      = high;
   stats.total     = total;
   return(true);
  }

//+------------------------------------------------------------------+
//| Verificacao se Preco foi Testado                                 |
//+------------------------------------------------------------------+
bool WasPriceTested(double price, datetime after_time, datetime until_time, ENUM_TIMEFRAMES tf)
  {
   MqlRates rates[];
   int copied = CopyRates(g_symbol, tf, after_time, until_time, rates);
   for(int i = 0; i < copied; i++)
     {
      if(rates[i].low <= price && rates[i].high >= price)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Deteccao de Nos de Volume (HVN e LVN) e Imas de Liquidez        |
//+------------------------------------------------------------------+
void DetectVolumeNodesAndMagnets(const double &profile[], int levels, double min_price, double price_step,
                                 double max_volume, int poc, double vah_price, double val_price, double cur_price)
  {
   ArrayResize(g_detected_hvns, 0);
   ArrayResize(g_detected_lvns, 0);

   if(levels < 5 || max_volume <= 0.0)
      return;

   int min_spacing = MathMax(2, InpMinimumNodeSpacingLevels);
   double hvn_thresh = max_volume * MathMax(20.0, MathMin(95.0, InpHvnThresholdPercent)) / 100.0;
   double lvn_thresh = max_volume * MathMax(2.0, MathMin(40.0, InpLvnThresholdPercent)) / 100.0;

   // 1. Detectar HVNs (Picos locais de volume / Zonas de Aceitacao e Imas)
   for(int i = 2; i < levels - 2; i++)
     {
      if(MathAbs(i - poc) < min_spacing)
         continue;

      if(profile[i] > profile[i - 1] && profile[i] > profile[i + 1] &&
         profile[i] >= profile[i - 2] && profile[i] >= profile[i + 2] &&
         profile[i] >= hvn_thresh)
        {
         bool too_close = false;
         for(int k = 0; k < ArraySize(g_detected_hvns); k++)
           {
            int saved_lvl = (int)MathRound((g_detected_hvns[k].price - min_price) / price_step);
            if(MathAbs(i - saved_lvl) < min_spacing)
              {
               too_close = true;
               if(profile[i] > g_detected_hvns[k].volume)
                 {
                  g_detected_hvns[k].price  = LevelMidPrice(min_price, price_step, i);
                  g_detected_hvns[k].volume = profile[i];
                 }
               break;
              }
           }
         if(!too_close && ArraySize(g_detected_hvns) < MathMax(2, InpMaxNodesToDraw))
           {
            int sz = ArraySize(g_detected_hvns);
            ArrayResize(g_detected_hvns, sz + 1);
            g_detected_hvns[sz].price  = LevelMidPrice(min_price, price_step, i);
            g_detected_hvns[sz].volume = profile[i];
            g_detected_hvns[sz].is_hvn = true;
            g_detected_hvns[sz].label  = "HVN_" + IntegerToString(sz + 1);
           }
        }
     }

   // 2. Detectar LVNs (Vales locais de volume / Vacuos de Liquidez e Aceleracao)
   for(int i = 2; i < levels - 2; i++)
     {
      if(MathAbs(i - poc) < min_spacing)
         continue;

      if(profile[i] < profile[i - 1] && profile[i] < profile[i + 1] &&
         profile[i] <= lvn_thresh && profile[i] > 0.0)
        {
         bool too_close = false;
         for(int k = 0; k < ArraySize(g_detected_lvns); k++)
           {
            int saved_lvl = (int)MathRound((g_detected_lvns[k].price - min_price) / price_step);
            if(MathAbs(i - saved_lvl) < min_spacing)
              {
               too_close = true;
               break;
              }
           }
         if(!too_close && ArraySize(g_detected_lvns) < MathMax(2, InpMaxNodesToDraw))
           {
            int sz = ArraySize(g_detected_lvns);
            ArrayResize(g_detected_lvns, sz + 1);
            g_detected_lvns[sz].price  = LevelMidPrice(min_price, price_step, i);
            g_detected_lvns[sz].volume = profile[i];
            g_detected_lvns[sz].is_hvn = false;
            g_detected_lvns[sz].label  = "LVN_" + IntegerToString(sz + 1);
           }
        }
     }

   // 3. Prever Rota e Ima de Liquidez Mais Proximo
   CalculateNextMagnetAndRoute(cur_price, LevelMidPrice(min_price, price_step, poc), vah_price, val_price);
  }

//+------------------------------------------------------------------+
//| Calculo do Proximo Ima de Liquidez e Rota de Movimento           |
//+------------------------------------------------------------------+
void CalculateNextMagnetAndRoute(double cur_price, double poc_price, double vah_price, double val_price)
  {
   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);

   double nearest_above_dist  = DBL_MAX;
   double nearest_above_price = 0.0;
   string nearest_above_type  = "";

   double nearest_below_dist  = DBL_MAX;
   double nearest_below_price = 0.0;
   string nearest_below_type  = "";

   // 1. POC
   if(poc_price > cur_price)
     {
      double d = poc_price - cur_price;
      if(d < nearest_above_dist) { nearest_above_dist = d; nearest_above_price = poc_price; nearest_above_type = "POC"; }
     }
   else if(poc_price < cur_price)
     {
      double d = cur_price - poc_price;
      if(d < nearest_below_dist) { nearest_below_dist = d; nearest_below_price = poc_price; nearest_below_type = "POC"; }
     }

   // 2. VAH (acima)
   if(vah_price > cur_price)
     {
      double d = vah_price - cur_price;
      if(d < nearest_above_dist) { nearest_above_dist = d; nearest_above_price = vah_price; nearest_above_type = "VAH"; }
     }

   // 3. VAL (abaixo)
   if(val_price < cur_price)
     {
      double d = cur_price - val_price;
      if(d < nearest_below_dist) { nearest_below_dist = d; nearest_below_price = val_price; nearest_below_type = "VAL"; }
     }

   // 4. HVNs
   for(int i = 0; i < ArraySize(g_detected_hvns); i++)
     {
      double hp = g_detected_hvns[i].price;
      if(hp > cur_price)
        {
         double d = hp - cur_price;
         if(d < nearest_above_dist) { nearest_above_dist = d; nearest_above_price = hp; nearest_above_type = g_detected_hvns[i].label; }
        }
      else if(hp < cur_price)
        {
         double d = cur_price - hp;
         if(d < nearest_below_dist) { nearest_below_dist = d; nearest_below_price = hp; nearest_below_type = g_detected_hvns[i].label; }
        }
     }

   // 5. Naked POCs
   for(int i = 0; i < ArraySize(g_cached_daily_pocs); i++)
     {
      double np = g_cached_daily_pocs[i].price;
      if(np > cur_price)
        {
         double d = np - cur_price;
         if(d < nearest_above_dist) { nearest_above_dist = d; nearest_above_price = np; nearest_above_type = g_cached_daily_pocs[i].label; }
        }
      else if(np < cur_price)
        {
         double d = cur_price - np;
         if(d < nearest_below_dist) { nearest_below_dist = d; nearest_below_price = np; nearest_below_type = g_cached_daily_pocs[i].label; }
        }
     }

   // Determina a direcao provavel
   bool heading_up = false;
   if(g_trade_state == TRADE_STATE_ACTIVE_BUY || g_trade_state == TRADE_STATE_PREP_BUY)
      heading_up = true;
   else if(g_trade_state == TRADE_STATE_ACTIVE_SELL || g_trade_state == TRADE_STATE_PREP_SELL)
      heading_up = false;
   else
     {
      if(g_cur_candle_delta > 0 || cur_price > poc_price)
         heading_up = true;
      else
         heading_up = false;
     }

   if(heading_up && nearest_above_price > 0.0)
     {
      g_next_magnet_price = nearest_above_price;
      g_next_magnet_type  = nearest_above_type;
      g_next_magnet_dist  = (nearest_above_price - cur_price) / _Point;

      double lvn_in_path = 0.0;
      for(int i = 0; i < ArraySize(g_detected_lvns); i++)
        {
         if(g_detected_lvns[i].price > cur_price && g_detected_lvns[i].price < nearest_above_price)
           {
            lvn_in_path = g_detected_lvns[i].price;
            break;
           }
        }

      if(lvn_in_path > 0.0)
         g_route_description = StringFormat("Vacuo em %s (Aceleracao rapida ate o Ima %s)", DoubleToString(lvn_in_path, digits), DoubleToString(g_next_magnet_price, digits));
      else
         g_route_description = StringFormat("Fluxo de Alta buscando %s (%s)", DoubleToString(g_next_magnet_price, digits), g_next_magnet_type);
     }
   else if(!heading_up && nearest_below_price > 0.0)
     {
      g_next_magnet_price = nearest_below_price;
      g_next_magnet_type  = nearest_below_type;
      g_next_magnet_dist  = (cur_price - nearest_below_price) / _Point;

      double lvn_in_path = 0.0;
      for(int i = 0; i < ArraySize(g_detected_lvns); i++)
        {
         if(g_detected_lvns[i].price < cur_price && g_detected_lvns[i].price > nearest_below_price)
           {
            lvn_in_path = g_detected_lvns[i].price;
            break;
           }
        }

      if(lvn_in_path > 0.0)
         g_route_description = StringFormat("Vacuo em %s (Aceleracao rapida ate o Ima %s)", DoubleToString(lvn_in_path, digits), DoubleToString(g_next_magnet_price, digits));
      else
         g_route_description = StringFormat("Fluxo de Baixa buscando %s (%s)", DoubleToString(g_next_magnet_price, digits), g_next_magnet_type);
     }
   else
     {
      g_next_magnet_price = poc_price;
      g_next_magnet_type  = "POC";
      g_next_magnet_dist  = MathAbs(cur_price - poc_price) / _Point;
      g_route_description = "Oscilando em torno do POC institucional";
     }
  }

//+------------------------------------------------------------------+
//| Detector de Sinais de Alta Probabilidade (Entradas Precisas)     |
//+------------------------------------------------------------------+
void CheckTradeSignals(double poc, double vah, double val, double vwap)
  {
   MqlRates bars[];
   ArraySetAsSeries(bars, true);
   if(CopyRates(g_symbol, _Period, 0, 4, bars) < 4)
      return;

   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);

   // 1. Fase de Preparacao na Barra Atual (Ao Vivo - Barra [0])
   if(g_trade_state != TRADE_STATE_ACTIVE_BUY && g_trade_state != TRADE_STATE_ACTIVE_SELL)
     {
      if(bars[0].low < val && bars[0].close >= val)
        {
         g_trade_state = TRADE_STATE_PREP_BUY;
         g_prep_text   = "PREPARAR COMPRA: Testando VAL (" + DoubleToString(val, digits) + "). Se fechar acima, COMPRE!";
         if(InpAlertPrepare && !g_alerted_prep_buy)
           {
            TriggerAlert("PREPARAR COMPRA", "Preco testando VAL em " + DoubleToString(val, digits) + ". Aguarde fechamento!", bars[0].close, poc);
            g_alerted_prep_buy = true;
           }
        }
      else if(bars[0].high > vah && bars[0].close <= vah)
        {
         g_trade_state = TRADE_STATE_PREP_SELL;
         g_prep_text   = "PREPARAR VENDA: Testando VAH (" + DoubleToString(vah, digits) + "). Se fechar abaixo, VENDA!";
         if(InpAlertPrepare && !g_alerted_prep_sell)
           {
            TriggerAlert("PREPARAR VENDA", "Preco testando VAH em " + DoubleToString(vah, digits) + ". Aguarde fechamento!", bars[0].close, poc);
            g_alerted_prep_sell = true;
           }
        }
      else
        {
         g_alerted_prep_buy  = false;
         g_alerted_prep_sell = false;
         if(g_trade_state == TRADE_STATE_PREP_BUY || g_trade_state == TRADE_STATE_PREP_SELL)
            g_trade_state = TRADE_STATE_NEUTRAL;
        }
     }

   // 2. Fase de Confirmacao e Disparo na Barra Fechada [1]
   datetime signal_bar_time = bars[1].time;
   if(signal_bar_time == g_last_signal_time)
      return;

   double avg_vol = (bars[2].tick_volume + bars[3].tick_volume) / 2.0;
   if(avg_vol <= 0.0) avg_vol = 1.0;
   bool vol_confirm = ((double)bars[1].tick_volume >= avg_vol * InpSignalMinVolumeFactor);

   bool trend_bullish = true;
   bool trend_bearish = true;
   if(InpFilterTrendWithEma)
     {
      int handle = iMA(g_symbol, InpTrendTimeframe, InpTrendEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(handle != INVALID_HANDLE)
        {
         double ema[];
         if(CopyBuffer(handle, 0, 1, 1, ema) == 1)
           {
            trend_bullish = (bars[1].close > ema[0]);
            trend_bearish = (bars[1].close < ema[0]);
           }
         IndicatorRelease(handle);
        }
     }

   MqlRates closed = bars[1];
   MqlRates prev   = bars[2];

   double candle_range = MathMax(_Point, closed.high - closed.low);
   double lower_wick   = closed.close > closed.open ? (closed.open - closed.low) : (closed.close - closed.low);
   double upper_wick   = closed.close > closed.open ? (closed.high - closed.close) : (closed.high - closed.open);

   bool buy_signal  = false;
   bool sell_signal = false;
   string reason    = "";

   // SETUP 1: REJEICAO DE VALUE AREA (Falso Rompimento / Retorno a Media)
   if(InpSignalMode == MTR_SIGNAL_ALL || InpSignalMode == MTR_SIGNAL_REVERSAL)
     {
      if(closed.low < val && closed.close > val && trend_bullish && vol_confirm)
        {
         if(lower_wick >= candle_range * 0.35 || closed.close > closed.open)
           {
            buy_signal = true;
            reason = "Rejeicao em VAL (Falso Rompimento / Desconto)";
           }
        }

      if(closed.high > vah && closed.close < vah && trend_bearish && vol_confirm)
        {
         if(upper_wick >= candle_range * 0.35 || closed.close < closed.open)
           {
            sell_signal = true;
            reason = "Rejeicao em VAH (Falso Rompimento / Premio)";
           }
        }
     }

   // SETUP 2: ROMPIMENTO DE VALUE AREA (Expansao / Tendencia de Valor)
   if(!buy_signal && !sell_signal && (InpSignalMode == MTR_SIGNAL_ALL || InpSignalMode == MTR_SIGNAL_BREAKOUT))
     {
      if(prev.close <= vah && closed.close > vah && closed.close > vwap && trend_bullish && vol_confirm)
        {
         buy_signal = true;
         reason = "Rompimento do VAH com Volume | Expansao de Alta";
        }

      if(prev.close >= val && closed.close < val && closed.close < vwap && trend_bearish && vol_confirm)
        {
         sell_signal = true;
         reason = "Rompimento do VAL com Volume | Expansao de Baixa";
        }
     }

   // SETUP 3: TOQUE E REJEICAO EM NAKED POC
   if(!buy_signal && !sell_signal && InpSignalMode == MTR_SIGNAL_ALL)
     {
      for(int i = 0; i < ArraySize(g_cached_daily_pocs); i++)
        {
         double npoc_p = g_cached_daily_pocs[i].price;
         if(closed.low <= npoc_p && closed.close > npoc_p && lower_wick > candle_range * 0.4)
           {
            buy_signal = true;
            reason = "Reacao em Naked POC Diario (" + DoubleToString(npoc_p, digits) + ")";
            break;
           }
         if(closed.high >= npoc_p && closed.close < npoc_p && upper_wick > candle_range * 0.4)
           {
            sell_signal = true;
            reason = "Reacao em Naked POC Diario (" + DoubleToString(npoc_p, digits) + ")";
            break;
           }
        }
     }

   // SETUP 4: CAPTURA DE LIQUIDEZ / ABSORCAO EM HVN INTERMEDIARIO
   if(!buy_signal && !sell_signal && InpSignalMode == MTR_SIGNAL_ALL)
     {
      for(int i = 0; i < ArraySize(g_detected_hvns); i++)
        {
         double hvn_p = g_detected_hvns[i].price;
         if(closed.low < hvn_p && closed.close > hvn_p && lower_wick >= candle_range * 0.40 && vol_confirm && trend_bullish)
           {
            buy_signal = true;
            reason = "Captura de Liquidez em " + g_detected_hvns[i].label + " (" + DoubleToString(hvn_p, digits) + ")";
            break;
           }
         if(closed.high > hvn_p && closed.close < hvn_p && upper_wick >= candle_range * 0.40 && vol_confirm && trend_bearish)
           {
            sell_signal = true;
            reason = "Captura de Liquidez em " + g_detected_hvns[i].label + " (" + DoubleToString(hvn_p, digits) + ")";
            break;
           }
        }
     }

   // Ativacao do Trade
   if(buy_signal || sell_signal)
     {
      g_last_signal_time   = signal_bar_time;
      g_active_signal_time = signal_bar_time;
      g_active_entry_price = closed.close;
      g_active_setup_name  = reason;
      g_tp1_alerted        = false;
      g_tp2_alerted        = false;
      g_stop_alerted       = false;

      double sl_buffer = MathMax(_Point * 10, candle_range * 0.15);

      if(buy_signal)
        {
         g_trade_state     = TRADE_STATE_ACTIVE_BUY;
         g_active_sl_price = closed.low - sl_buffer;
         g_active_tp1_price= (closed.close < poc) ? poc : (vah);
         g_active_tp2_price= (closed.close < poc) ? vah : (vah + (vah - val) * 0.5);
        }
      else
        {
         g_trade_state     = TRADE_STATE_ACTIVE_SELL;
         g_active_sl_price = closed.high + sl_buffer;
         g_active_tp1_price= (closed.close > poc) ? poc : (val);
         g_active_tp2_price= (closed.close > poc) ? val : (val - (vah - val) * 0.5);
        }

      string sig_side = buy_signal ? "BUY" : "SELL";
      string arrow_name = g_prefix + "SIG_" + sig_side + "_" + IntegerToString((int)signal_bar_time);
      double point_offset = MathMax(_Point * 10, candle_range * 0.25);
      double arrow_price  = buy_signal ? (closed.low - point_offset) : (closed.high + point_offset);

      if(ObjectCreate(0, arrow_name, buy_signal ? OBJ_ARROW_BUY : OBJ_ARROW_SELL, 0, signal_bar_time, arrow_price))
        {
         ObjectSetInteger(0, arrow_name, OBJPROP_COLOR, buy_signal ? InpBuySignalColor : InpSellSignalColor);
         ObjectSetInteger(0, arrow_name, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, arrow_name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, arrow_name, OBJPROP_HIDDEN, true);
        }

      string tag_name = g_prefix + "SIGTAG_" + sig_side + "_" + IntegerToString((int)signal_bar_time);
      double tag_price = buy_signal ? (arrow_price - point_offset * 0.8) : (arrow_price + point_offset * 0.8);
      if(ObjectCreate(0, tag_name, OBJ_TEXT, 0, signal_bar_time, tag_price))
        {
         ObjectSetString(0, tag_name, OBJPROP_TEXT, (buy_signal ? " COMPRAR AGORA: " : " VENDER AGORA: ") + reason);
         ObjectSetString(0, tag_name, OBJPROP_FONT, "Segoe UI Semibold");
         ObjectSetInteger(0, tag_name, OBJPROP_FONTSIZE, MathMax(7, InpFontSize));
         ObjectSetInteger(0, tag_name, OBJPROP_COLOR, buy_signal ? InpBuySignalColor : InpSellSignalColor);
         ObjectSetInteger(0, tag_name, OBJPROP_ANCHOR, buy_signal ? ANCHOR_UPPER : ANCHOR_LOWER);
         ObjectSetInteger(0, tag_name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, tag_name, OBJPROP_HIDDEN, true);
        }

      TriggerAlert(buy_signal ? "ENTRAR COMPRA AGORA" : "ENTRAR VENDA AGORA",
                   reason + "\nStop Loss: " + DoubleToString(g_active_sl_price, digits) +
                   "\nAlvo 1: " + DoubleToString(g_active_tp1_price, digits) +
                   "\nAlvo 2: " + DoubleToString(g_active_tp2_price, digits),
                   g_active_entry_price, g_active_tp1_price);
     }
  }

//+------------------------------------------------------------------+
//| Monitoramento em Tempo Real do Trade (Hora de Sair / Parcial)    |
//+------------------------------------------------------------------+
void MonitorActiveTrade(double cur_price)
  {
   if(g_trade_state != TRADE_STATE_ACTIVE_BUY && g_trade_state != TRADE_STATE_ACTIVE_SELL &&
      g_trade_state != TRADE_STATE_TP1_HIT)
      return;

   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);

   if(g_trade_state == TRADE_STATE_ACTIVE_BUY || (g_trade_state == TRADE_STATE_TP1_HIT && g_active_tp2_price > g_active_tp1_price))
     {
      if(cur_price >= g_active_tp2_price && !g_tp2_alerted)
        {
         g_trade_state = TRADE_STATE_TP2_HIT;
         g_tp2_alerted = true;
         TriggerAlert("HORA DE SAIR (ALVO FINAL ATINGIDO!)",
                      "Preco atingiu o Alvo 2 em " + DoubleToString(g_active_tp2_price, digits) + "!\nEncerre 100% da posicao com lucro total.",
                      cur_price, g_active_tp2_price);
        }
      else if(cur_price >= g_active_tp1_price && !g_tp1_alerted)
        {
         g_trade_state = TRADE_STATE_TP1_HIT;
         g_tp1_alerted = true;
         TriggerAlert("HORA DE SAIR (ALVO 1 / PARCIAL!)",
                      "Preco chegou no Alvo 1 (POC) em " + DoubleToString(g_active_tp1_price, digits) + "!\nRealize parcial de 50% a 70% e coloque o Stop no preco de entrada (0x0).",
                      cur_price, g_active_tp2_price);
        }
      else if(cur_price <= g_active_sl_price && !g_stop_alerted)
        {
         g_trade_state  = TRADE_STATE_STOP_HIT;
         g_stop_alerted = true;
         TriggerAlert("STOP LOSS ATINGIDO (SAIR DA OPERACAO)",
                      "Preco tocou o Stop Loss em " + DoubleToString(g_active_sl_price, digits) + ".\nSaia da operacao para protecao patrimonial.",
                      cur_price, g_active_sl_price);
        }
     }
   else if(g_trade_state == TRADE_STATE_ACTIVE_SELL || (g_trade_state == TRADE_STATE_TP1_HIT && g_active_tp2_price < g_active_tp1_price))
     {
      if(cur_price <= g_active_tp2_price && !g_tp2_alerted)
        {
         g_trade_state = TRADE_STATE_TP2_HIT;
         g_tp2_alerted = true;
         TriggerAlert("HORA DE SAIR (ALVO FINAL ATINGIDO!)",
                      "Preco atingiu o Alvo 2 em " + DoubleToString(g_active_tp2_price, digits) + "!\nEncerre 100% da posicao com lucro total.",
                      cur_price, g_active_tp2_price);
        }
      else if(cur_price <= g_active_tp1_price && !g_tp1_alerted)
        {
         g_trade_state = TRADE_STATE_TP1_HIT;
         g_tp1_alerted = true;
         TriggerAlert("HORA DE SAIR (ALVO 1 / PARCIAL!)",
                      "Preco chegou no Alvo 1 (POC) em " + DoubleToString(g_active_tp1_price, digits) + "!\nRealize parcial de 50% a 70% e coloque o Stop no preco de entrada (0x0).",
                      cur_price, g_active_tp2_price);
        }
      else if(cur_price >= g_active_sl_price && !g_stop_alerted)
        {
         g_trade_state  = TRADE_STATE_STOP_HIT;
         g_stop_alerted = true;
         TriggerAlert("STOP LOSS ATINGIDO (SAIR DA OPERACAO)",
                      "Preco tocou o Stop Loss em " + DoubleToString(g_active_sl_price, digits) + ".\nSaia da operacao para protecao patrimonial.",
                      cur_price, g_active_sl_price);
        }
     }
  }

//+------------------------------------------------------------------+
//| Processamento em Tempo Real a Cada Tick do Candle Atual [0]      |
//+------------------------------------------------------------------+
void ProcessRealTimeTick(datetime newest, const double &open[], const double &high[], const double &low[],
                         const double &close[], const long &tick_volume[], const long &volume[], int rates_total)
  {
   int idx = rates_total - 1;
   if(ArrayGetAsSeries(close))
      idx = 0;

   double cur_p  = close[idx];
   double open_p = open[idx];
   double high_p = high[idx];
   double low_p  = low[idx];
   long   ticks  = tick_volume[idx];

   // Se abriu novo candle, reinicia acumuladores
   if(newest != g_cur_candle_time)
     {
      g_cur_candle_time     = newest;
      g_cur_candle_ticks    = 0;
      g_cur_candle_buy_vol  = 0.0;
      g_cur_candle_sell_vol = 0.0;
      g_cur_candle_delta    = 0.0;
      g_cur_candle_prev_p   = open_p;
     }

   long delta_ticks = ticks - g_cur_candle_ticks;
   if(delta_ticks <= 0) delta_ticks = 1;
   g_cur_candle_ticks = ticks;

   MqlTick last_tick;
   bool used_flags = false;
   if(SymbolInfoTick(g_symbol, last_tick))
     {
      if((last_tick.flags & (TICK_FLAG_BUY | TICK_FLAG_SELL)) != 0)
        {
         used_flags = true;
         double v_unit = (last_tick.volume_real > 0.0) ? (double)last_tick.volume_real : (double)delta_ticks;
         if((last_tick.flags & TICK_FLAG_BUY) != 0)
            g_cur_candle_buy_vol += v_unit;
         else if((last_tick.flags & TICK_FLAG_SELL) != 0)
            g_cur_candle_sell_vol += v_unit;
        }
     }

   if(!used_flags)
     {
      if(cur_p > g_cur_candle_prev_p)
         g_cur_candle_buy_vol += (double)delta_ticks;
      else if(cur_p < g_cur_candle_prev_p)
         g_cur_candle_sell_vol += (double)delta_ticks;
      else
        {
         double mid = (high_p + low_p) * 0.5;
         if(cur_p > mid)
            g_cur_candle_buy_vol += (double)delta_ticks * 0.65;
         else if(cur_p < mid)
            g_cur_candle_sell_vol += (double)delta_ticks * 0.65;
         else
           {
            g_cur_candle_buy_vol += (double)delta_ticks * 0.5;
            g_cur_candle_sell_vol += (double)delta_ticks * 0.5;
           }
        }
     }

   g_cur_candle_prev_p = cur_p;
   g_cur_candle_delta  = g_cur_candle_buy_vol - g_cur_candle_sell_vol;

   double tot_c = g_cur_candle_buy_vol + g_cur_candle_sell_vol;
   double buy_pct = (tot_c > 0.0) ? (g_cur_candle_buy_vol / tot_c * 100.0) : 50.0;
   double sell_pct = 100.0 - buy_pct;

   double c_range    = MathMax(_Point, high_p - low_p);
   double upper_wick = high_p - MathMax(open_p, cur_p);
   double lower_wick = MathMin(open_p, cur_p) - low_p;

   if(upper_wick >= c_range * 0.38 && g_cur_candle_delta < 0)
      g_cur_candle_absorp = "ABSORCAO TOPO (Venda defendendo)";
   else if(lower_wick >= c_range * 0.38 && g_cur_candle_delta > 0)
      g_cur_candle_absorp = "ABSORCAO FUNDO (Compra defendendo)";
   else if(buy_pct >= 62.0)
      g_cur_candle_absorp = "PRESSAO COMPRADORA FORTE ▲";
   else if(sell_pct >= 62.0)
      g_cur_candle_absorp = "PRESSAO VENDEDORA FORTE ▼";
   else
      g_cur_candle_absorp = "FLUXO EQUILIBRADO ⚖️";

   string d_sign = (g_cur_candle_delta > 0) ? "+" : "";
   g_cur_candle_flow_desc = StringFormat("[%s C:%.0f%% | V:%.0f%% | Delta:%s%.0f | %d Ticks] - %s",
                                         (g_cur_candle_delta >= 0 ? "▲" : "▼"),
                                         buy_pct, sell_pct, d_sign, g_cur_candle_delta,
                                         (int)g_cur_candle_ticks, g_cur_candle_absorp);

   UpdateRealTimeCardTick(cur_p);
  }

//+------------------------------------------------------------------+
//| Atualizacao Ultra Rapida dos Textos do Card a Cada Tick (0.001ms)|
//+------------------------------------------------------------------+
void UpdateRealTimeCardTick(double cur_price)
  {
   if(!InpShowTradeCard || g_card_minimized)
      return;

   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);

   // Atualiza linha de micro-fluxo ao vivo
   string name_flow = g_prefix + "CARD_L_2";
   if(ObjectFind(0, name_flow) >= 0)
      ObjectSetString(0, name_flow, OBJPROP_TEXT, "⚡ CANDLE AO VIVO: " + g_cur_candle_flow_desc);

   // Se em trade ativo, atualiza P&L em pontos e monitora saida
   if(g_trade_state == TRADE_STATE_ACTIVE_BUY || g_trade_state == TRADE_STATE_ACTIVE_SELL ||
      g_trade_state == TRADE_STATE_TP1_HIT)
     {
      double pnl_pts = (g_trade_state == TRADE_STATE_ACTIVE_BUY || g_trade_state == TRADE_STATE_TP1_HIT) ?
                       ((cur_price - g_active_entry_price) / _Point) :
                       ((g_active_entry_price - cur_price) / _Point);
      string sign = (pnl_pts >= 0) ? "+" : "";

      string name_price = g_prefix + "CARD_L_3";
      if(ObjectFind(0, name_price) >= 0)
        {
         ObjectSetString(0, name_price, OBJPROP_TEXT,
                         StringFormat("Entrada: %s  |  Atual: %s  |  P&L: %s%.0f pts",
                                      DoubleToString(g_active_entry_price, digits),
                                      DoubleToString(cur_price, digits),
                                      sign, pnl_pts));
         ObjectSetInteger(0, name_price, OBJPROP_COLOR, (pnl_pts >= 0 ? clrLime : clrTomato));
        }

      MonitorActiveTrade(cur_price);
     }

   // Atualiza distancia do ima de liquidez
   if(g_next_magnet_price > 0.0)
     {
      g_next_magnet_dist = MathAbs(cur_price - g_next_magnet_price) / _Point;
      string name_mag = g_prefix + "CARD_L_0";
      if(ObjectFind(0, name_mag) >= 0)
        {
         ObjectSetString(0, name_mag, OBJPROP_TEXT,
                         StringFormat("🎯 IMA DE LIQUIDEZ: %s (%s  |  a %.0f pts)",
                                      DoubleToString(g_next_magnet_price, digits),
                                      g_next_magnet_type, g_next_magnet_dist));
        }
     }

   // Redraw suave limitado a 10 FPS (Zero consumo de CPU)
   static ulong last_redraw_msc = 0;
   ulong now_msc = GetTickCount64();
   if(now_msc - last_redraw_msc >= 100)
     {
      last_redraw_msc = now_msc;
      ChartRedraw(0);
     }
  }

//+------------------------------------------------------------------+
//| Emissao de Alertas Multicanais                                   |
//+------------------------------------------------------------------+
void TriggerAlert(string type_str, string reason_str, double entry_price, double target_price)
  {
   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   string msg = StringFormat("[MTR VAP PRO] %s | %s\nPreco Atual: %s\nNivel Chave: %s\n%s",
                             type_str, g_symbol, DoubleToString(entry_price, digits),
                             DoubleToString(target_price, digits), reason_str);

   if(InpAlertPopup)
      Alert(msg);
   if(InpAlertSound)
      PlaySound("expert.wav");
   if(InpAlertPush)
      SendNotification(msg);
  }

//+------------------------------------------------------------------+
//| Card Visual de Decisao no Grafico (Sobreposicao Topo & Arrastavel|
//+------------------------------------------------------------------+
void DrawTradeDecisionCard(double cur_price, double poc, double vah, double val, double vwap)
  {
   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   string card_bg     = g_prefix + "CARD_BG";
   string card_hdr    = g_prefix + "CARD_HDR";
   string card_btn    = g_prefix + "CARD_BTN_MIN";
   string card_ban_bg = g_prefix + "CARD_BANNER_BG";
   string card_ban_tx = g_prefix + "CARD_BANNER_TXT";
   string card_ban_sb = g_prefix + "CARD_BANNER_SUB";

   int current_h = g_card_minimized ? 32 : g_card_height;

   // 1. Fundo Principal Opaco (Sobrepoe Tudo no Grafico com Z-Order Topo)
   if(ObjectFind(0, card_bg) < 0)
     {
      ObjectCreate(0, card_bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, card_bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, card_bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, card_bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, card_bg, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, card_bg, OBJPROP_BACK, false);
      ObjectSetInteger(0, card_bg, OBJPROP_ZORDER, 100);
     }
   ObjectSetInteger(0, card_bg, OBJPROP_XDISTANCE, g_card_x);
   ObjectSetInteger(0, card_bg, OBJPROP_YDISTANCE, g_card_y);
   ObjectSetInteger(0, card_bg, OBJPROP_XSIZE, g_card_width);
   ObjectSetInteger(0, card_bg, OBJPROP_YSIZE, current_h);
   ObjectSetInteger(0, card_bg, OBJPROP_BGCOLOR, InpCardBgColor);
   ObjectSetInteger(0, card_bg, OBJPROP_COLOR, InpCardBorderColor);
   ObjectSetInteger(0, card_bg, OBJPROP_BACK, false);
   ObjectSetInteger(0, card_bg, OBJPROP_ZORDER, 100);

   // 2. Barra de Titulo Superior (Barra de Arrasto)
   if(ObjectFind(0, card_hdr) < 0)
     {
      ObjectCreate(0, card_hdr, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, card_hdr, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, card_hdr, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, card_hdr, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, card_hdr, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, card_hdr, OBJPROP_BACK, false);
      ObjectSetInteger(0, card_hdr, OBJPROP_ZORDER, 102);
     }
   ObjectSetInteger(0, card_hdr, OBJPROP_XDISTANCE, g_card_x);
   ObjectSetInteger(0, card_hdr, OBJPROP_YDISTANCE, g_card_y);
   ObjectSetInteger(0, card_hdr, OBJPROP_XSIZE, g_card_width);
   ObjectSetInteger(0, card_hdr, OBJPROP_YSIZE, 28);
   ObjectSetInteger(0, card_hdr, OBJPROP_BGCOLOR, InpCardHeaderColor);
   ObjectSetInteger(0, card_hdr, OBJPROP_COLOR, InpCardBorderColor);
   ObjectSetInteger(0, card_hdr, OBJPROP_BACK, false);
   ObjectSetInteger(0, card_hdr, OBJPROP_ZORDER, 102);

   // 3. Botao de Minimizar / Maximizar
   if(ObjectFind(0, card_btn) < 0)
     {
      ObjectCreate(0, card_btn, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, card_btn, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, card_btn, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, card_btn, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, card_btn, OBJPROP_BACK, false);
      ObjectSetInteger(0, card_btn, OBJPROP_ZORDER, 110);
      ObjectSetInteger(0, card_btn, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, card_btn, OBJPROP_FONT, "Segoe UI Bold");
     }
   ObjectSetInteger(0, card_btn, OBJPROP_XDISTANCE, g_card_x + g_card_width - 30);
   ObjectSetInteger(0, card_btn, OBJPROP_YDISTANCE, g_card_y + 4);
   ObjectSetInteger(0, card_btn, OBJPROP_XSIZE, 25);
   ObjectSetInteger(0, card_btn, OBJPROP_YSIZE, 20);
   ObjectSetString(0, card_btn, OBJPROP_TEXT, g_card_minimized ? "[+]" : "[-]");
   ObjectSetInteger(0, card_btn, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, card_btn, OBJPROP_BGCOLOR, C'45,55,75');
   ObjectSetInteger(0, card_btn, OBJPROP_BORDER_COLOR, C'70,85,115');
   ObjectSetInteger(0, card_btn, OBJPROP_STATE, false);
   ObjectSetInteger(0, card_btn, OBJPROP_BACK, false);
   ObjectSetInteger(0, card_btn, OBJPROP_ZORDER, 110);

   // 4. Banner Visual de Ordem de Acao (Destaque Maximo / Z-Order 104)
   color ban_bg_col  = C'30,40,55';
   color ban_tx_col  = clrWhite;
   string ban_title  = "";
   string ban_sub    = "";

   switch(g_trade_state)
     {
      case TRADE_STATE_NEUTRAL:
         ban_bg_col = C'30,40,55';
         ban_tx_col = clrWhite;
         ban_title  = "⏸️ ORDEM: AGUARDAR FORA DE MERCADO";
         ban_sub    = "Preco em equilibrio na Value Area | Aguarde teste de extremos ou rompimento";
         break;
      case TRADE_STATE_PREP_BUY:
         ban_bg_col = C'210,145,15';
         ban_tx_col = clrBlack;
         ban_title  = "⏳ ATENCAO: PREPARAR COMPRA NO VAL!";
         ban_sub    = "Aguarde esta vela fechar acima do VAL. Gatilho iminente na proxima vela!";
         break;
      case TRADE_STATE_PREP_SELL:
         ban_bg_col = C'225,95,15';
         ban_tx_col = clrBlack;
         ban_title  = "⏳ ATENCAO: PREPARAR VENDA NO VAH!";
         ban_sub    = "Aguarde esta vela fechar abaixo do VAH. Gatilho iminente na proxima vela!";
         break;
      case TRADE_STATE_ACTIVE_BUY:
         ban_bg_col = C'0,145,60';
         ban_tx_col = clrWhite;
         ban_title  = "⚡ ORDEM AGORA: COMPRAR A MERCADO!";
         ban_sub    = "Gatilho acionado! Execute a compra na boleta e configure Stop Loss e Alvos";
         break;
      case TRADE_STATE_ACTIVE_SELL:
         ban_bg_col = C'195,25,25';
         ban_tx_col = clrWhite;
         ban_title  = "⚡ ORDEM AGORA: VENDER A MERCADO!";
         ban_sub    = "Gatilho acionado! Execute a venda na boleta e configure Stop Loss e Alvos";
         break;
      case TRADE_STATE_TP1_HIT:
         ban_bg_col = C'15,130,205';
         ban_tx_col = clrWhite;
         ban_title  = "🎯 ORDEM: REALIZAR PARCIAL (70%) AGORA!";
         ban_sub    = "Alvo 1 batido com lucro! Realize parcial e mova o Stop Loss para o 0x0";
         break;
      case TRADE_STATE_TP2_HIT:
         ban_bg_col = C'190,150,15';
         ban_tx_col = clrBlack;
         ban_title  = "🏆 ORDEM: ENCERRAR 100% DA OPERACAO!";
         ban_sub    = "Alvo Final alcancado! Encerre todas as posicoes restantes com lucro total";
         break;
      case TRADE_STATE_STOP_HIT:
         ban_bg_col = C'150,20,20';
         ban_tx_col = clrWhite;
         ban_title  = "🛑 ORDEM: SAIR DO TRADE (STOP LOSS)";
         ban_sub    = "Nivel violado. Saia imediatamente para preservar seu patrimonio";
         break;
     }

   if(ObjectFind(0, card_ban_bg) < 0)
     {
      ObjectCreate(0, card_ban_bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, card_ban_bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, card_ban_bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, card_ban_bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, card_ban_bg, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, card_ban_bg, OBJPROP_BACK, false);
      ObjectSetInteger(0, card_ban_bg, OBJPROP_ZORDER, 104);
     }
   ObjectSetInteger(0, card_ban_bg, OBJPROP_XDISTANCE, g_card_minimized ? -1000 : (g_card_x + 8));
   ObjectSetInteger(0, card_ban_bg, OBJPROP_YDISTANCE, g_card_y + 32);
   ObjectSetInteger(0, card_ban_bg, OBJPROP_XSIZE, g_card_width - 16);
   ObjectSetInteger(0, card_ban_bg, OBJPROP_YSIZE, g_card_minimized ? 0 : 38);
   ObjectSetInteger(0, card_ban_bg, OBJPROP_BGCOLOR, ban_bg_col);
   ObjectSetInteger(0, card_ban_bg, OBJPROP_COLOR, ban_bg_col);
   ObjectSetInteger(0, card_ban_bg, OBJPROP_BACK, false);
   ObjectSetInteger(0, card_ban_bg, OBJPROP_ZORDER, 104);

   if(ObjectFind(0, card_ban_tx) < 0)
     {
      ObjectCreate(0, card_ban_tx, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, card_ban_tx, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, card_ban_tx, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, card_ban_tx, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, card_ban_tx, OBJPROP_BACK, false);
      ObjectSetInteger(0, card_ban_tx, OBJPROP_ZORDER, 106);
     }
   ObjectSetInteger(0, card_ban_tx, OBJPROP_XDISTANCE, g_card_minimized ? -1000 : (g_card_x + 16));
   ObjectSetInteger(0, card_ban_tx, OBJPROP_YDISTANCE, g_card_y + 35);
   ObjectSetInteger(0, card_ban_tx, OBJPROP_COLOR, ban_tx_col);
   ObjectSetInteger(0, card_ban_tx, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, card_ban_tx, OBJPROP_FONT, "Segoe UI Black");
   ObjectSetString(0, card_ban_tx, OBJPROP_TEXT, g_card_minimized ? "" : ban_title);

   if(ObjectFind(0, card_ban_sb) < 0)
     {
      ObjectCreate(0, card_ban_sb, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, card_ban_sb, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, card_ban_sb, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, card_ban_sb, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, card_ban_sb, OBJPROP_BACK, false);
      ObjectSetInteger(0, card_ban_sb, OBJPROP_ZORDER, 106);
     }
   ObjectSetInteger(0, card_ban_sb, OBJPROP_XDISTANCE, g_card_minimized ? -1000 : (g_card_x + 16));
   ObjectSetInteger(0, card_ban_sb, OBJPROP_YDISTANCE, g_card_y + 53);
   ObjectSetInteger(0, card_ban_sb, OBJPROP_COLOR, (ban_tx_col == clrBlack ? C'30,30,30' : clrWhiteSmoke));
   ObjectSetInteger(0, card_ban_sb, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, card_ban_sb, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetString(0, card_ban_sb, OBJPROP_TEXT, g_card_minimized ? "" : ban_sub);

   // Titulo do Cabecalho
   string title_txt = "";
   color  title_col = InpPocColor;
   if(g_card_minimized)
     {
      title_txt = "MTR PRO | " + ban_title;
      title_col = (ban_bg_col == C'30,40,55' ? clrSilver : (ban_tx_col == clrBlack ? clrYellow : ban_bg_col));
     }
   else
     {
      title_txt = "PAINEL DE DECISAO & ORDEM | " + g_symbol + " (MTR VAP PRO)";
      title_col = InpPocColor;
     }

   string hdr_lbl_name = g_prefix + "CARD_HDR_TXT";
   if(ObjectFind(0, hdr_lbl_name) < 0)
     {
      ObjectCreate(0, hdr_lbl_name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, hdr_lbl_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, hdr_lbl_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, hdr_lbl_name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, hdr_lbl_name, OBJPROP_BACK, false);
      ObjectSetInteger(0, hdr_lbl_name, OBJPROP_ZORDER, 105);
     }
   ObjectSetInteger(0, hdr_lbl_name, OBJPROP_XDISTANCE, g_card_x + 12);
   ObjectSetInteger(0, hdr_lbl_name, OBJPROP_YDISTANCE, g_card_y + 6);
   ObjectSetInteger(0, hdr_lbl_name, OBJPROP_COLOR, title_col);
   ObjectSetInteger(0, hdr_lbl_name, OBJPROP_FONTSIZE, InpCardFontSize);
   ObjectSetString(0, hdr_lbl_name, OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetString(0, hdr_lbl_name, OBJPROP_TEXT, title_txt);

   // 5. Linhas de Conteudo Detalhado (7 Linhas: CARD_L_0 a CARD_L_6)
   string lines[];
   color  colors[];
   ArrayResize(lines, 7);
   ArrayResize(colors, 7);

   // Linha 0: Ima de Liquidez
   lines[0] = StringFormat("🎯 IMA DE LIQUIDEZ: %s (%s  |  a %.0f pts)",
                           DoubleToString(g_next_magnet_price, digits),
                           g_next_magnet_type, g_next_magnet_dist);
   colors[0] = clrGold;

   // Linha 1: Rota e Vacuos
   lines[1] = "📍 ROTA PREVISTA: " + g_route_description;
   colors[1] = (StringFind(g_route_description, "Vacuo") >= 0 ? clrDarkOrange : clrAqua);

   // Linha 2: Micro-Fluxo ao Vivo do Candle Atual
   lines[2] = "⚡ CANDLE AO VIVO: " + g_cur_candle_flow_desc;
   colors[2] = clrLightCyan;

   if(g_trade_state == TRADE_STATE_ACTIVE_BUY || g_trade_state == TRADE_STATE_ACTIVE_SELL ||
      g_trade_state == TRADE_STATE_TP1_HIT || g_trade_state == TRADE_STATE_TP2_HIT || g_trade_state == TRADE_STATE_STOP_HIT)
     {
      double risk_pts   = MathAbs(g_active_entry_price - g_active_sl_price) / _Point;
      double gain1_pts  = MathAbs(g_active_tp1_price - g_active_entry_price) / _Point;
      double gain2_pts  = MathAbs(g_active_tp2_price - g_active_entry_price) / _Point;
      double rr_ratio   = (risk_pts > 0.0) ? (gain1_pts / risk_pts) : 0.0;
      double pnl_pts    = (g_trade_state == TRADE_STATE_ACTIVE_BUY || g_trade_state == TRADE_STATE_TP1_HIT) ?
                          ((cur_price - g_active_entry_price) / _Point) :
                          ((g_active_entry_price - cur_price) / _Point);
      string sign       = (pnl_pts >= 0) ? "+" : "";

      lines[3] = StringFormat("Entrada: %s  |  Atual: %s  |  P&L: %s%.0f pts",
                              DoubleToString(g_active_entry_price, digits),
                              DoubleToString(cur_price, digits),
                              sign, pnl_pts);
      colors[3] = (pnl_pts >= 0 ? clrLime : clrTomato);

      lines[4] = StringFormat("🛑 STOP LOSS: %s (-%.0f pts) -> Protecao Tecnica",
                              DoubleToString(g_active_sl_price, digits), risk_pts);
      colors[4] = clrTomato;

      lines[5] = StringFormat("🎯 ALVO 1 (POC): %s (+%.0f pts) -> Fechar 70%% e Mover Stop para 0x0",
                              DoubleToString(g_active_tp1_price, digits), gain1_pts);
      colors[5] = clrGold;

      lines[6] = StringFormat("🏆 ALVO 2: %s (+%.0f pts) | R:R 1:%.1f | Bateu Alvo 1, proteja no 0x0!",
                              DoubleToString(g_active_tp2_price, digits), gain2_pts, rr_ratio);
      colors[6] = clrLime;
     }
   else if(g_trade_state == TRADE_STATE_PREP_BUY || g_trade_state == TRADE_STATE_PREP_SELL)
     {
      lines[3] = g_prep_text;
      colors[3] = clrYellow;

      lines[4] = "Stop Previsto: Alguns ticks atras da maxima/minima da vela de rejeicao.";
      colors[4] = clrTomato;

      lines[5] = StringFormat("Alvo Previsto: Retorno ao POC institucional em %s.", DoubleToString(poc, digits));
      colors[5] = clrGold;

      lines[6] = "Gatilho: Nao antecipe! Espere o fechamento da vela para confirmar.";
      colors[6] = clrSilver;
     }
   else
     {
      lines[3] = StringFormat("Preco Atual: %s  |  POC: %s  |  VWAP: %s",
                              DoubleToString(cur_price, digits), DoubleToString(poc, digits), DoubleToString(vwap, digits));
      colors[3] = clrSilver;

      double dist_val = MathAbs(cur_price - val) / _Point;
      double dist_vah = MathAbs(cur_price - vah) / _Point;

      lines[4] = StringFormat("Distancia ate VAL (Compra): %.0f pts  |  Ate VAH (Venda): %.0f pts", dist_val, dist_vah);
      colors[4] = clrLightCyan;

      lines[5] = "Estrategia: Nao opere no meio do perfil (perto do POC). Espere as bordas!";
      colors[5] = clrGold;

      lines[6] = "O sistema alertara na tela com audio assim que surgir oportunidade de entrada!";
      colors[6] = clrLime;
     }

   for(int i = 0; i < 7; i++)
     {
      string name = g_prefix + "CARD_L_" + IntegerToString(i);
      if(ObjectFind(0, name) < 0)
        {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
         ObjectSetInteger(0, name, OBJPROP_ZORDER, 105);
        }
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, g_card_minimized ? -1000 : (g_card_x + 12));
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, g_card_y + 74 + i * 21);
      ObjectSetInteger(0, name, OBJPROP_COLOR, colors[i]);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpCardFontSize);
      ObjectSetString(0, name, OBJPROP_FONT, (i == 0 || i == 3) ? "Segoe UI Bold" : "Segoe UI");
      ObjectSetString(0, name, OBJPROP_TEXT, g_card_minimized ? "" : lines[i]);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 105);
     }
  }

//+------------------------------------------------------------------+
//| Atualizacao Ultra Rapida das Coordenadas ao Arrastar             |
//+------------------------------------------------------------------+
void UpdateCardPositions()
  {
   int current_h = g_card_minimized ? 32 : g_card_height;

   ObjectSetInteger(0, g_prefix + "CARD_BG", OBJPROP_XDISTANCE, g_card_x);
   ObjectSetInteger(0, g_prefix + "CARD_BG", OBJPROP_YDISTANCE, g_card_y);
   ObjectSetInteger(0, g_prefix + "CARD_BG", OBJPROP_YSIZE, current_h);

   ObjectSetInteger(0, g_prefix + "CARD_HDR", OBJPROP_XDISTANCE, g_card_x);
   ObjectSetInteger(0, g_prefix + "CARD_HDR", OBJPROP_YDISTANCE, g_card_y);

   ObjectSetInteger(0, g_prefix + "CARD_HDR_TXT", OBJPROP_XDISTANCE, g_card_x + 12);
   ObjectSetInteger(0, g_prefix + "CARD_HDR_TXT", OBJPROP_YDISTANCE, g_card_y + 6);

   ObjectSetInteger(0, g_prefix + "CARD_BTN_MIN", OBJPROP_XDISTANCE, g_card_x + g_card_width - 30);
   ObjectSetInteger(0, g_prefix + "CARD_BTN_MIN", OBJPROP_YDISTANCE, g_card_y + 4);

   if(g_card_minimized)
     {
      ObjectSetInteger(0, g_prefix + "CARD_BANNER_BG", OBJPROP_YSIZE, 0);
      ObjectSetInteger(0, g_prefix + "CARD_BANNER_BG", OBJPROP_XDISTANCE, -1000);
      ObjectSetInteger(0, g_prefix + "CARD_BANNER_TXT", OBJPROP_XDISTANCE, -1000);
      ObjectSetInteger(0, g_prefix + "CARD_BANNER_SUB", OBJPROP_XDISTANCE, -1000);

      for(int i = 0; i < 7; i++)
        {
         string name = g_prefix + "CARD_L_" + IntegerToString(i);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, -1000);
        }
     }
   else
     {
      ObjectSetInteger(0, g_prefix + "CARD_BANNER_BG", OBJPROP_XDISTANCE, g_card_x + 8);
      ObjectSetInteger(0, g_prefix + "CARD_BANNER_BG", OBJPROP_YDISTANCE, g_card_y + 32);
      ObjectSetInteger(0, g_prefix + "CARD_BANNER_BG", OBJPROP_XSIZE, g_card_width - 16);
      ObjectSetInteger(0, g_prefix + "CARD_BANNER_BG", OBJPROP_YSIZE, 38);

      ObjectSetInteger(0, g_prefix + "CARD_BANNER_TXT", OBJPROP_XDISTANCE, g_card_x + 16);
      ObjectSetInteger(0, g_prefix + "CARD_BANNER_TXT", OBJPROP_YDISTANCE, g_card_y + 35);

      ObjectSetInteger(0, g_prefix + "CARD_BANNER_SUB", OBJPROP_XDISTANCE, g_card_x + 16);
      ObjectSetInteger(0, g_prefix + "CARD_BANNER_SUB", OBJPROP_YDISTANCE, g_card_y + 53);

      for(int i = 0; i < 7; i++)
        {
         string name = g_prefix + "CARD_L_" + IntegerToString(i);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, g_card_x + 12);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, g_card_y + 74 + i * 21);
        }
     }
  }

//+------------------------------------------------------------------+
//| Desenha as Linhas Projetadas de Entrada/Stop/Alvos no Grafico    |
//+------------------------------------------------------------------+
void DrawActiveTradeLines()
  {
   if(g_trade_state != TRADE_STATE_ACTIVE_BUY && g_trade_state != TRADE_STATE_ACTIVE_SELL &&
      g_trade_state != TRADE_STATE_TP1_HIT)
     {
      ObjectDelete(0, g_prefix + "TL_ENTRY");
      ObjectDelete(0, g_prefix + "TL_STOP");
      ObjectDelete(0, g_prefix + "TL_TP1");
      ObjectDelete(0, g_prefix + "TL_TP2");
      ObjectDelete(0, g_prefix + "TL_ENTRY_LBL");
      ObjectDelete(0, g_prefix + "TL_STOP_LBL");
      ObjectDelete(0, g_prefix + "TL_TP1_LBL");
      ObjectDelete(0, g_prefix + "TL_TP2_LBL");
      return;
     }

   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   datetime right_time = GetChartRightTime(TimeCurrent() + 3600);
   datetime start_time = g_active_signal_time;
   if(start_time <= 0) start_time = TimeCurrent() - 1800;

   // 1. Linha de Entrada
   string name_ent = g_prefix + "TL_ENTRY";
   if(ObjectFind(0, name_ent) < 0) ObjectCreate(0, name_ent, OBJ_TREND, 0, start_time, g_active_entry_price, right_time, g_active_entry_price);
   ObjectSetDouble(0, name_ent, OBJPROP_PRICE, 0, g_active_entry_price);
   ObjectSetDouble(0, name_ent, OBJPROP_PRICE, 1, g_active_entry_price);
   ObjectSetInteger(0, name_ent, OBJPROP_TIME, 0, start_time);
   ObjectSetInteger(0, name_ent, OBJPROP_TIME, 1, right_time);
   ObjectSetInteger(0, name_ent, OBJPROP_COLOR, (g_trade_state == TRADE_STATE_ACTIVE_BUY) ? InpBuySignalColor : InpSellSignalColor);
   ObjectSetInteger(0, name_ent, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name_ent, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name_ent, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name_ent, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name_ent, OBJPROP_HIDDEN, true);

   // 2. Linha de Stop Loss
   string name_sl = g_prefix + "TL_STOP";
   if(ObjectFind(0, name_sl) < 0) ObjectCreate(0, name_sl, OBJ_TREND, 0, start_time, g_active_sl_price, right_time, g_active_sl_price);
   ObjectSetDouble(0, name_sl, OBJPROP_PRICE, 0, g_active_sl_price);
   ObjectSetDouble(0, name_sl, OBJPROP_PRICE, 1, g_active_sl_price);
   ObjectSetInteger(0, name_sl, OBJPROP_TIME, 0, start_time);
   ObjectSetInteger(0, name_sl, OBJPROP_TIME, 1, right_time);
   ObjectSetInteger(0, name_sl, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, name_sl, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name_sl, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name_sl, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name_sl, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name_sl, OBJPROP_HIDDEN, true);

   // 3. Linha de Alvo 1 (POC / Parcial)
   string name_tp1 = g_prefix + "TL_TP1";
   if(ObjectFind(0, name_tp1) < 0) ObjectCreate(0, name_tp1, OBJ_TREND, 0, start_time, g_active_tp1_price, right_time, g_active_tp1_price);
   ObjectSetDouble(0, name_tp1, OBJPROP_PRICE, 0, g_active_tp1_price);
   ObjectSetDouble(0, name_tp1, OBJPROP_PRICE, 1, g_active_tp1_price);
   ObjectSetInteger(0, name_tp1, OBJPROP_TIME, 0, start_time);
   ObjectSetInteger(0, name_tp1, OBJPROP_TIME, 1, right_time);
   ObjectSetInteger(0, name_tp1, OBJPROP_COLOR, clrGold);
   ObjectSetInteger(0, name_tp1, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name_tp1, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name_tp1, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name_tp1, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name_tp1, OBJPROP_HIDDEN, true);

   // 4. Linha de Alvo 2 (Final)
   string name_tp2 = g_prefix + "TL_TP2";
   if(ObjectFind(0, name_tp2) < 0) ObjectCreate(0, name_tp2, OBJ_TREND, 0, start_time, g_active_tp2_price, right_time, g_active_tp2_price);
   ObjectSetDouble(0, name_tp2, OBJPROP_PRICE, 0, g_active_tp2_price);
   ObjectSetDouble(0, name_tp2, OBJPROP_PRICE, 1, g_active_tp2_price);
   ObjectSetInteger(0, name_tp2, OBJPROP_TIME, 0, start_time);
   ObjectSetInteger(0, name_tp2, OBJPROP_TIME, 1, right_time);
   ObjectSetInteger(0, name_tp2, OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, name_tp2, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name_tp2, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name_tp2, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name_tp2, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name_tp2, OBJPROP_HIDDEN, true);

   // Etiquetas Visuais
   DrawFixedPriceLabel("TL_ENT_LBL", g_active_entry_price, "ENTRADA " + DoubleToString(g_active_entry_price, digits), (g_trade_state == TRADE_STATE_ACTIVE_BUY ? InpBuySignalColor : InpSellSignalColor));
   DrawFixedPriceLabel("TL_SL_LBL", g_active_sl_price, "STOP LOSS " + DoubleToString(g_active_sl_price, digits), clrRed);
   DrawFixedPriceLabel("TL_TP1_LBL", g_active_tp1_price, "ALVO 1 (POC) " + DoubleToString(g_active_tp1_price, digits), clrGold);
   DrawFixedPriceLabel("TL_TP2_LBL", g_active_tp2_price, "ALVO 2 (FINAL) " + DoubleToString(g_active_tp2_price, digits), clrLime);
  }

//+------------------------------------------------------------------+
//| Desenho Otimizado do Histograma de Volume (Gerenciamento em Pool)|
//+------------------------------------------------------------------+
void DrawHistogramBars(const double &profile[], const double &buy_profile[], const double &sell_profile[],
                       int levels, double min_price, double price_step, double max_volume,
                       datetime to_time, int poc, int val, int vah)
  {
   long chart_width = 0;
   ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, chart_width);
   if(chart_width <= 0) chart_width = 800;

   int max_width_px = (int)MathMax(1.0, chart_width * MathMin(60.0, InpProfileWidthPercent) / 100.0);

   for(int i = 0; i < levels && !IsStopped(); i++)
     {
      if(profile[i] <= 0.0)
         continue;

      int width_px = (int)MathMax(1.0, max_width_px * profile[i] / max_volume);
      double low_p  = min_price + i * price_step;
      double high_p = low_p + price_step;

      string bar_name = g_prefix + "BAR_" + IntegerToString(i);
      color bar_col = (InpShowValueArea && i >= val && i <= vah) ? InpValueAreaColor : InpProfileColor;

      if(i == poc)
         bar_col = InpPocColor;
      else if(InpShowHvn && profile[i] >= max_volume * InpHvnThresholdPercent / 100.0)
         bar_col = InpHvnColor;
      else if(InpShowLvn && profile[i] <= max_volume * InpLvnThresholdPercent / 100.0)
         bar_col = InpLvnColor;

      if(InpShowBuySell && i != poc)
        {
         double row_tot = MathMax(0.0001, profile[i]);
         int sell_px = (int)MathRound(width_px * sell_profile[i] / row_tot);
         int buy_px  = MathMax(0, width_px - sell_px);

         DrawScreenProfileRectangle(bar_name + "_B", InpRightMarginPixels, buy_px, low_p, high_p, InpBuyColor);
         DrawScreenProfileRectangle(bar_name + "_S", InpRightMarginPixels + buy_px, sell_px, low_p, high_p, InpSellColor);
        }
      else
        {
         DrawScreenProfileRectangle(bar_name, InpRightMarginPixels, width_px, low_p, high_p, bar_col);
        }
     }

   if(g_prev_hist_bars > levels)
     {
      for(int i = levels; i < g_prev_hist_bars; i++)
        {
         ObjectDelete(0, g_prefix + "BAR_" + IntegerToString(i));
         ObjectDelete(0, g_prefix + "BAR_" + IntegerToString(i) + "_B");
         ObjectDelete(0, g_prefix + "BAR_" + IntegerToString(i) + "_S");
        }
     }
   g_prev_hist_bars = levels;
  }

//+------------------------------------------------------------------+
//| Desenho de Retangulo de Histograma em Coordenadas de Tela        |
//+------------------------------------------------------------------+
void DrawScreenProfileRectangle(string name, int right_offset, int width, double low_price, double high_price, color col)
  {
   if(width <= 0)
     {
      ObjectDelete(0, name);
      return;
     }

   int x_low = 0, y_low = 0, x_high = 0, y_high = 0;
   datetime ref_time = iTime(g_symbol, _Period, 0);
   if(ref_time <= 0) ref_time = TimeCurrent();

   if(!ChartTimePriceToXY(0, 0, ref_time, low_price, x_low, y_low) ||
      !ChartTimePriceToXY(0, 0, ref_time, high_price, x_high, y_high))
      return;

   int top    = MathMin(y_low, y_high);
   int height = MathMax(1, MathAbs(y_low - y_high));

   long chart_width = 0;
   if(!ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, chart_width) || chart_width <= 0)
      return;

   int left = MathMax(0, (int)chart_width - MathMax(0, right_offset) - width);

   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
         return;
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, left);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, top);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, col);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
  }

//+------------------------------------------------------------------+
//| Desenho das Linhas de Referencia Estruturais                     |
//+------------------------------------------------------------------+
void DrawReferenceLevels(datetime from_time, datetime to_time, double min_price, double max_price,
                         double price_step, int poc, int val, int vah, double vwap)
  {
   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   datetime right_time = GetChartRightTime(to_time);

   // POC
   if(InpShowPocLine)
     {
      double poc_p = LevelMidPrice(min_price, price_step, poc);
      string name = g_prefix + "POC";
      if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TREND, 0, from_time, poc_p, right_time, poc_p);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, poc_p);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, poc_p);
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, from_time);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, right_time);
      ObjectSetInteger(0, name, OBJPROP_COLOR, InpPocColor);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, InpExtendLevelsRight);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

      if(InpShowLevelLabels)
         DrawFixedPriceLabel("POC_LBL", poc_p, "POC " + DoubleToString(poc_p, digits), InpPocColor);
     }

   // VAH e VAL
   if(InpShowValueArea)
     {
      double vah_p = min_price + (vah + 1) * price_step;
      double val_p = min_price + val * price_step;

      string name_vah = g_prefix + "VAH";
      if(ObjectFind(0, name_vah) < 0) ObjectCreate(0, name_vah, OBJ_TREND, 0, from_time, vah_p, right_time, vah_p);
      ObjectSetDouble(0, name_vah, OBJPROP_PRICE, 0, vah_p);
      ObjectSetDouble(0, name_vah, OBJPROP_PRICE, 1, vah_p);
      ObjectSetInteger(0, name_vah, OBJPROP_TIME, 0, from_time);
      ObjectSetInteger(0, name_vah, OBJPROP_TIME, 1, right_time);
      ObjectSetInteger(0, name_vah, OBJPROP_COLOR, InpValueAreaLineColor);
      ObjectSetInteger(0, name_vah, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, name_vah, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name_vah, OBJPROP_RAY_RIGHT, InpExtendLevelsRight);
      ObjectSetInteger(0, name_vah, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name_vah, OBJPROP_HIDDEN, true);

      string name_val = g_prefix + "VAL";
      if(ObjectFind(0, name_val) < 0) ObjectCreate(0, name_val, OBJ_TREND, 0, from_time, val_p, right_time, val_p);
      ObjectSetDouble(0, name_val, OBJPROP_PRICE, 0, val_p);
      ObjectSetDouble(0, name_val, OBJPROP_PRICE, 1, val_p);
      ObjectSetInteger(0, name_val, OBJPROP_TIME, 0, from_time);
      ObjectSetInteger(0, name_val, OBJPROP_TIME, 1, right_time);
      ObjectSetInteger(0, name_val, OBJPROP_COLOR, InpValueAreaLineColor);
      ObjectSetInteger(0, name_val, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, name_val, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name_val, OBJPROP_RAY_RIGHT, InpExtendLevelsRight);
      ObjectSetInteger(0, name_val, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name_val, OBJPROP_HIDDEN, true);

      if(InpShowLevelLabels)
        {
         DrawFixedPriceLabel("VAH_LBL", vah_p, "VAH " + DoubleToString(vah_p, digits), InpValueAreaLineColor);
         DrawFixedPriceLabel("VAL_LBL", val_p, "VAL " + DoubleToString(val_p, digits), InpValueAreaLineColor);
        }
     }

   // VWAP
   if(InpShowVwap && vwap > 0.0)
     {
      string name_vwap = g_prefix + "VWAP";
      if(ObjectFind(0, name_vwap) < 0) ObjectCreate(0, name_vwap, OBJ_TREND, 0, from_time, vwap, right_time, vwap);
      ObjectSetDouble(0, name_vwap, OBJPROP_PRICE, 0, vwap);
      ObjectSetDouble(0, name_vwap, OBJPROP_PRICE, 1, vwap);
      ObjectSetInteger(0, name_vwap, OBJPROP_TIME, 0, from_time);
      ObjectSetInteger(0, name_vwap, OBJPROP_TIME, 1, right_time);
      ObjectSetInteger(0, name_vwap, OBJPROP_COLOR, InpVwapColor);
      ObjectSetInteger(0, name_vwap, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name_vwap, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name_vwap, OBJPROP_RAY_RIGHT, InpExtendLevelsRight);
      ObjectSetInteger(0, name_vwap, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name_vwap, OBJPROP_HIDDEN, true);

      if(InpShowLevelLabels)
         DrawFixedPriceLabel("VWAP_LBL", vwap, "VWAP " + DoubleToString(vwap, digits), InpVwapColor);
     }

   // High e Low do Perfil
   if(InpShowProfileHighLow && max_price > min_price)
     {
      string name_hi = g_prefix + "HIGH";
      if(ObjectFind(0, name_hi) < 0) ObjectCreate(0, name_hi, OBJ_TREND, 0, from_time, max_price, right_time, max_price);
      ObjectSetDouble(0, name_hi, OBJPROP_PRICE, 0, max_price);
      ObjectSetDouble(0, name_hi, OBJPROP_PRICE, 1, max_price);
      ObjectSetInteger(0, name_hi, OBJPROP_TIME, 0, from_time);
      ObjectSetInteger(0, name_hi, OBJPROP_TIME, 1, right_time);
      ObjectSetInteger(0, name_hi, OBJPROP_COLOR, InpHighLowColor);
      ObjectSetInteger(0, name_hi, OBJPROP_STYLE, STYLE_DASHDOTDOT);
      ObjectSetInteger(0, name_hi, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name_hi, OBJPROP_RAY_RIGHT, InpExtendLevelsRight);
      ObjectSetInteger(0, name_hi, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name_hi, OBJPROP_HIDDEN, true);

      string name_lo = g_prefix + "LOW";
      if(ObjectFind(0, name_lo) < 0) ObjectCreate(0, name_lo, OBJ_TREND, 0, from_time, min_price, right_time, min_price);
      ObjectSetDouble(0, name_lo, OBJPROP_PRICE, 0, min_price);
      ObjectSetDouble(0, name_lo, OBJPROP_PRICE, 1, min_price);
      ObjectSetInteger(0, name_lo, OBJPROP_TIME, 0, from_time);
      ObjectSetInteger(0, name_lo, OBJPROP_TIME, 1, right_time);
      ObjectSetInteger(0, name_lo, OBJPROP_COLOR, InpHighLowColor);
      ObjectSetInteger(0, name_lo, OBJPROP_STYLE, STYLE_DASHDOTDOT);
      ObjectSetInteger(0, name_lo, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name_lo, OBJPROP_RAY_RIGHT, InpExtendLevelsRight);
      ObjectSetInteger(0, name_lo, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name_lo, OBJPROP_HIDDEN, true);

      if(InpShowLevelLabels)
        {
         DrawFixedPriceLabel("HIGH_LBL", max_price, "HIGH " + DoubleToString(max_price, digits), InpHighLowColor);
         DrawFixedPriceLabel("LOW_LBL", min_price, "LOW " + DoubleToString(min_price, digits), InpHighLowColor);
        }
     }

   // HVN Lines (High Volume Nodes - Imas de Liquidez Intermediarios)
   if(InpShowHvn && InpDrawNodeLines)
     {
      int max_hvn = MathMin(InpMaxNodesToDraw, ArraySize(g_detected_hvns));
      for(int k = 0; k < max_hvn; k++)
        {
         double hp = g_detected_hvns[k].price;
         string name_h = g_prefix + "HVN_" + IntegerToString(k);
         if(ObjectFind(0, name_h) < 0) ObjectCreate(0, name_h, OBJ_TREND, 0, from_time, hp, right_time, hp);
         ObjectSetDouble(0, name_h, OBJPROP_PRICE, 0, hp);
         ObjectSetDouble(0, name_h, OBJPROP_PRICE, 1, hp);
         ObjectSetInteger(0, name_h, OBJPROP_TIME, 0, from_time);
         ObjectSetInteger(0, name_h, OBJPROP_TIME, 1, right_time);
         ObjectSetInteger(0, name_h, OBJPROP_COLOR, InpHvnColor);
         ObjectSetInteger(0, name_h, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, name_h, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name_h, OBJPROP_RAY_RIGHT, InpExtendLevelsRight);
         ObjectSetInteger(0, name_h, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name_h, OBJPROP_HIDDEN, true);

         if(InpShowLevelLabels)
            DrawFixedPriceLabel("HVN_" + IntegerToString(k) + "_LBL", hp, "HVN " + DoubleToString(hp, digits) + " [IMA]", InpHvnColor);
        }
      for(int k = max_hvn; k < 10; k++)
        {
         ObjectDelete(0, g_prefix + "HVN_" + IntegerToString(k));
         ObjectDelete(0, g_prefix + "FIX_LBL_HVN_" + IntegerToString(k) + "_LBL");
        }
     }
   else
     {
      for(int k = 0; k < 10; k++)
        {
         ObjectDelete(0, g_prefix + "HVN_" + IntegerToString(k));
         ObjectDelete(0, g_prefix + "FIX_LBL_HVN_" + IntegerToString(k) + "_LBL");
        }
     }

   // LVN Lines (Low Volume Nodes - Vacuos de Liquidez / Aceleracao)
   if(InpShowLvn && InpDrawNodeLines)
     {
      int max_lvn = MathMin(InpMaxNodesToDraw, ArraySize(g_detected_lvns));
      for(int k = 0; k < max_lvn; k++)
        {
         double lp = g_detected_lvns[k].price;
         string name_l = g_prefix + "LVN_" + IntegerToString(k);
         if(ObjectFind(0, name_l) < 0) ObjectCreate(0, name_l, OBJ_TREND, 0, from_time, lp, right_time, lp);
         ObjectSetDouble(0, name_l, OBJPROP_PRICE, 0, lp);
         ObjectSetDouble(0, name_l, OBJPROP_PRICE, 1, lp);
         ObjectSetInteger(0, name_l, OBJPROP_TIME, 0, from_time);
         ObjectSetInteger(0, name_l, OBJPROP_TIME, 1, right_time);
         ObjectSetInteger(0, name_l, OBJPROP_COLOR, InpLvnColor);
         ObjectSetInteger(0, name_l, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, name_l, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name_l, OBJPROP_RAY_RIGHT, InpExtendLevelsRight);
         ObjectSetInteger(0, name_l, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name_l, OBJPROP_HIDDEN, true);

         if(InpShowLevelLabels)
            DrawFixedPriceLabel("LVN_" + IntegerToString(k) + "_LBL", lp, "LVN " + DoubleToString(lp, digits) + " [VACUO]", InpLvnColor);
        }
      for(int k = max_lvn; k < 10; k++)
        {
         ObjectDelete(0, g_prefix + "LVN_" + IntegerToString(k));
         ObjectDelete(0, g_prefix + "FIX_LBL_LVN_" + IntegerToString(k) + "_LBL");
        }
     }
   else
     {
      for(int k = 0; k < 10; k++)
        {
         ObjectDelete(0, g_prefix + "LVN_" + IntegerToString(k));
         ObjectDelete(0, g_prefix + "FIX_LBL_LVN_" + IntegerToString(k) + "_LBL");
        }
     }
  }

//+------------------------------------------------------------------+
//| Desenha Niveis Historicos em Cache (Sem Lag)                     |
//+------------------------------------------------------------------+
void DrawCachedHistoricalLevels(datetime current_from)
  {
   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   datetime right_time = GetChartRightTime(TimeCurrent());

   if(InpShowPreviousPeriod && g_cached_prev_period.valid)
     {
      string name_p_poc = g_prefix + "PREV_POC";
      if(ObjectFind(0, name_p_poc) < 0) ObjectCreate(0, name_p_poc, OBJ_TREND, 0, current_from, g_cached_prev_period.poc, right_time, g_cached_prev_period.poc);
      ObjectSetDouble(0, name_p_poc, OBJPROP_PRICE, 0, g_cached_prev_period.poc);
      ObjectSetDouble(0, name_p_poc, OBJPROP_PRICE, 1, g_cached_prev_period.poc);
      ObjectSetInteger(0, name_p_poc, OBJPROP_COLOR, InpPreviousLevelColor);
      ObjectSetInteger(0, name_p_poc, OBJPROP_STYLE, STYLE_DASHDOT);
      ObjectSetInteger(0, name_p_poc, OBJPROP_RAY_RIGHT, InpExtendLevelsRight);
      ObjectSetInteger(0, name_p_poc, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name_p_poc, OBJPROP_HIDDEN, true);

      if(InpShowLevelLabels)
         DrawFixedPriceLabel("PREV_POC_LBL", g_cached_prev_period.poc, "D-1 POC " + DoubleToString(g_cached_prev_period.poc, digits), InpPreviousLevelColor);
     }

   if(InpShowUntestedPocs)
     {
      for(int i = 0; i < ArraySize(g_cached_daily_pocs); i++)
        {
         string name_np = g_prefix + "D_NPOC_" + IntegerToString(i);
         double np_p = g_cached_daily_pocs[i].price;
         if(ObjectFind(0, name_np) < 0) ObjectCreate(0, name_np, OBJ_TREND, 0, g_cached_daily_pocs[i].time_start, np_p, right_time, np_p);
         ObjectSetDouble(0, name_np, OBJPROP_PRICE, 0, np_p);
         ObjectSetDouble(0, name_np, OBJPROP_PRICE, 1, np_p);
         ObjectSetInteger(0, name_np, OBJPROP_COLOR, InpUntestedPocColor);
         ObjectSetInteger(0, name_np, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, name_np, OBJPROP_RAY_RIGHT, InpExtendLevelsRight);
         ObjectSetInteger(0, name_np, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name_np, OBJPROP_HIDDEN, true);

         if(InpShowLevelLabels)
            DrawFixedPriceLabel(g_cached_daily_pocs[i].label, np_p, g_cached_daily_pocs[i].label + " " + DoubleToString(np_p, digits), InpUntestedPocColor);
        }

      for(int i = 0; i < ArraySize(g_cached_weekly_pocs); i++)
        {
         string name_wp = g_prefix + "W_NPOC_" + IntegerToString(i);
         double wp_p = g_cached_weekly_pocs[i].price;
         if(ObjectFind(0, name_wp) < 0) ObjectCreate(0, name_wp, OBJ_TREND, 0, g_cached_weekly_pocs[i].time_start, wp_p, right_time, wp_p);
         ObjectSetDouble(0, name_wp, OBJPROP_PRICE, 0, wp_p);
         ObjectSetDouble(0, name_wp, OBJPROP_PRICE, 1, wp_p);
         ObjectSetInteger(0, name_wp, OBJPROP_COLOR, InpUntestedPocColor);
         ObjectSetInteger(0, name_wp, OBJPROP_STYLE, STYLE_DASHDOTDOT);
         ObjectSetInteger(0, name_wp, OBJPROP_RAY_RIGHT, InpExtendLevelsRight);
         ObjectSetInteger(0, name_wp, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name_wp, OBJPROP_HIDDEN, true);

         if(InpShowLevelLabels)
            DrawFixedPriceLabel(g_cached_weekly_pocs[i].label, wp_p, g_cached_weekly_pocs[i].label + " " + DoubleToString(wp_p, digits), InpUntestedPocColor);
        }
     }
  }

//+------------------------------------------------------------------+
//| Etiquetas de Preco Fixas com Prevencao de Colisao                |
//+------------------------------------------------------------------+
void DrawFixedPriceLabel(string suffix, double price, string text_val, color text_col)
  {
   int x = 0, y = 0;
   datetime vis_time = GetChartRightTime(TimeCurrent());
   if(!ChartTimePriceToXY(0, 0, vis_time, price, x, y))
      return;

   y = FindReadableLabelY(y);

   string name = g_prefix + suffix;
   bool left_side = (InpLevelLabelSide == MTR_VAP_LABEL_LEFT);

   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
         return;
      ObjectSetInteger(0, name, OBJPROP_CORNER, left_side ? CORNER_LEFT_UPPER : CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, left_side ? ANCHOR_LEFT : ANCHOR_RIGHT);
      ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Bold");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, MathMax(7, InpFontSize));
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
     }

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, MathMax(2, InpFixedLabelMarginPixels));
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, MathMax(0, y));
   ObjectSetString(0, name, OBJPROP_TEXT, text_val);
   ObjectSetInteger(0, name, OBJPROP_COLOR, text_col);
  }

//+------------------------------------------------------------------+
//| Desvio de Colisao Vertical para Legendas                         |
//+------------------------------------------------------------------+
int FindReadableLabelY(int desired_y)
  {
   int spacing = MathMax(11, InpFontSize + 4);
   int cand = MathMax(0, desired_y);
   bool coll = true;
   int guard = 0;

   while(coll && guard < 50)
     {
      coll = false;
      for(int i = 0; i < ArraySize(g_used_label_y); i++)
        {
         if(MathAbs(cand - g_used_label_y[i]) < spacing)
           {
            cand = g_used_label_y[i] + spacing;
            coll = true;
            break;
           }
        }
      guard++;
     }

   long h = 0;
   if(ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0, h) && h > spacing)
      cand = MathMin(cand, (int)h - spacing);

   int sz = ArraySize(g_used_label_y);
   ArrayResize(g_used_label_y, sz + 1);
   g_used_label_y[sz] = cand;
   return(cand);
  }

//+------------------------------------------------------------------+
//| Painel HUD Analitico Secundario                                  |
//+------------------------------------------------------------------+
void DrawInfoPanel(string source_str, string delta_str, double total_vol, double buy_vol, double sell_vol,
                   double poc, double vwap, double vah, double val, double price_step)
  {
   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   double cur_price = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   if(cur_price <= 0.0) cur_price = SymbolInfoDouble(g_symbol, SYMBOL_LAST);

   string lines[];
   color  colors[];
   ArrayResize(lines, 4);
   ArrayResize(colors, 4);

   lines[0] = "METRICAS | " + g_symbol;
   colors[0] = InpPocColor;

   lines[1] = StringFormat("Fonte: %s  |  Delta: %s  |  Degrau: %s",
                           source_str, (delta_str == "DELTA_REAL" ? "REAL" : "ESTIMADO"),
                           DoubleToString(price_step, digits));
   colors[1] = clrSilver;

   double delta = buy_vol - sell_vol;
   lines[2] = StringFormat("Volume: %s (C: %s | V: %s | Delta: %s)",
                           FormatVolume(total_vol), FormatVolume(buy_vol), FormatVolume(sell_vol),
                           FormatSignedVolume(delta));
   colors[2] = (delta >= 0.0) ? InpBuyColor : InpSellColor;

   lines[3] = StringFormat("POC: %s  |  VWAP: %s  |  VAH: %s  |  VAL: %s",
                           DoubleToString(poc, digits), DoubleToString(vwap, digits),
                           DoubleToString(vah, digits), DoubleToString(val, digits));
   colors[3] = clrWhite;

   for(int i = 0; i < ArraySize(lines); i++)
      DrawPanelLine(i, lines[i], colors[i], (i == 0));
  }

//+------------------------------------------------------------------+
//| Linha Individual do Mini Painel Secundario                       |
//+------------------------------------------------------------------+
void DrawPanelLine(int line, string text_val, color text_col, bool bold)
  {
   string name = g_prefix + "PNL_" + IntegerToString(line);
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
         return;
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 20);
     }

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, MathMax(0, InpPanelX));
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, MathMax(0, InpPanelY) + line * MathMax(11, InpPanelLineSpacing));
   ObjectSetInteger(0, name, OBJPROP_COLOR, text_col);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, MathMax(7, InpFontSize));
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Segoe UI Bold" : "Segoe UI");
   ObjectSetString(0, name, OBJPROP_TEXT, text_val);
  }

//+------------------------------------------------------------------+
//| Resolucao da Faixa de Tempo (Multi-Modos)                        |
//+------------------------------------------------------------------+
bool ResolveRange(datetime &from_time, datetime &to_time)
  {
   to_time = TimeCurrent();

   if(InpRangeMode == MTR_VAP_FIXED_RANGE || InpRangeMode == MTR_VAP_ANCHORED)
     {
      EnsureRangeAnchors();
      from_time = (datetime)ObjectGetInteger(0, g_anchor_start, OBJPROP_TIME, 0);
      if(InpRangeMode == MTR_VAP_FIXED_RANGE)
         to_time = (datetime)ObjectGetInteger(0, g_anchor_end, OBJPROP_TIME, 0);

      if(from_time > to_time)
        {
         datetime tmp = from_time;
         from_time = to_time;
         to_time = tmp;
        }
      return(from_time > 0 && to_time > from_time);
     }

   if(InpRangeMode == MTR_VAP_SESSION)
      return(ResolveSessionRange(to_time, from_time, to_time));

   if(InpRangeMode == MTR_VAP_CURRENT_DAY || InpRangeMode == MTR_VAP_PREVIOUS_DAY)
     {
      datetime today = StartOfDay(to_time);
      if(InpRangeMode == MTR_VAP_CURRENT_DAY)
         from_time = today;
      else
        {
         from_time = today - 86400;
         to_time   = today - 1;
        }
      return(true);
     }

   if(InpRangeMode == MTR_VAP_CURRENT_WEEK || InpRangeMode == MTR_VAP_PREVIOUS_WEEK)
     {
      datetime week = StartOfWeek(to_time);
      if(InpRangeMode == MTR_VAP_CURRENT_WEEK)
         from_time = week;
      else
        {
         from_time = week - 7 * 86400;
         to_time   = week - 1;
        }
      return(true);
     }

   if(InpRangeMode == MTR_VAP_CURRENT_MONTH || InpRangeMode == MTR_VAP_PREVIOUS_MONTH)
     {
      datetime month = StartOfMonth(to_time);
      if(InpRangeMode == MTR_VAP_CURRENT_MONTH)
         from_time = month;
      else
        {
         to_time   = month - 1;
         from_time = StartOfMonth(to_time);
        }
      return(true);
     }

   int shift = MathMax(1, InpLookbackBars) - 1;
   if(InpRangeMode == MTR_VAP_VISIBLE_RANGE)
     {
      long first_vis = 0;
      if(ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR, 0, first_vis))
         shift = (int)MathMax(0, first_vis);
     }

   from_time = iTime(g_symbol, _Period, shift);
   if(from_time <= 0)
      from_time = iTime(g_symbol, _Period, MathMax(0, Bars(g_symbol, _Period) - 1));

   return(from_time > 0);
  }

//+------------------------------------------------------------------+
//| Funcoes de Apoio de Data e Hora                                  |
//+------------------------------------------------------------------+
datetime StartOfDay(datetime value)
  {
   MqlDateTime dt;
   TimeToStruct(value, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return(StructToTime(dt));
  }

datetime StartOfWeek(datetime value)
  {
   MqlDateTime dt;
   TimeToStruct(value, dt);
   int days_back = (dt.day_of_week == 0) ? 0 : (dt.day_of_week - 1);
   return(StartOfDay(value) - days_back * 86400);
  }

datetime StartOfMonth(datetime value)
  {
   MqlDateTime dt;
   TimeToStruct(value, dt);
   dt.day = 1; dt.hour = 0; dt.min = 0; dt.sec = 0;
   return(StructToTime(dt));
  }

bool ResolveSessionRange(datetime now, datetime &from_time, datetime &to_time)
  {
   MqlDateTime dt;
   TimeToStruct(now, dt);
   dt.hour = MathMax(0, MathMin(23, InpSessionStartHour));
   dt.min  = MathMax(0, MathMin(59, InpSessionStartMinute));
   dt.sec  = 0;
   datetime st = StructToTime(dt);

   TimeToStruct(now, dt);
   dt.hour = MathMax(0, MathMin(23, InpSessionEndHour));
   dt.min  = MathMax(0, MathMin(59, InpSessionEndMinute));
   dt.sec  = 59;
   datetime fn = StructToTime(dt);

   if(fn <= st)
     {
      if(now < fn) st -= 86400;
      else fn += 86400;
     }
   if(now < st)
     {
      st -= 86400;
      fn -= 86400;
     }
   from_time = st;
   to_time   = MathMin(now, fn);
   return(to_time > from_time);
  }

//+------------------------------------------------------------------+
//| Ancoras Visuais Interativas                                      |
//+------------------------------------------------------------------+
void EnsureRangeAnchors()
  {
   datetime ini_start = iTime(g_symbol, _Period, MathMax(1, InpLookbackBars) - 1);
   if(ini_start <= 0) ini_start = TimeCurrent() - 86400;
   datetime ini_end = TimeCurrent();

   if(ObjectFind(0, g_anchor_start) < 0 &&
      ObjectCreate(0, g_anchor_start, OBJ_VLINE, 0, ini_start, 0.0))
     {
      ObjectSetInteger(0, g_anchor_start, OBJPROP_COLOR, clrLimeGreen);
      ObjectSetInteger(0, g_anchor_start, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, g_anchor_start, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, g_anchor_start, OBJPROP_SELECTED, true);
     }

   if(InpRangeMode == MTR_VAP_FIXED_RANGE && ObjectFind(0, g_anchor_end) < 0 &&
      ObjectCreate(0, g_anchor_end, OBJ_VLINE, 0, ini_end, 0.0))
     {
      ObjectSetInteger(0, g_anchor_end, OBJPROP_COLOR, clrTomato);
      ObjectSetInteger(0, g_anchor_end, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, g_anchor_end, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, g_anchor_end, OBJPROP_SELECTED, true);
     }
  }

//+------------------------------------------------------------------+
//| Preco Medio de um Nivel do Perfil                                |
//+------------------------------------------------------------------+
double LevelMidPrice(double min_price, double price_step, int level)
  {
   return(min_price + (level + 0.5) * price_step);
  }

//+------------------------------------------------------------------+
//| Horario da Borda Direita do Grafico                              |
//+------------------------------------------------------------------+
datetime GetChartRightTime(datetime fallback_time)
  {
   long w = 0;
   if(!ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, w) || w <= 0)
      return(fallback_time);

   int margin = MathMax(10, InpRightMarginPixels);
   int x = (int)MathMax(0, w - margin);
   int subwin = 0;
   datetime ct = 0;
   double cp = 0.0;

   if(!ChartXYToTimePrice(0, x, 10, subwin, ct, cp))
      return(fallback_time);

   return(ct > 0 ? ct : fallback_time);
  }

//+------------------------------------------------------------------+
//| Formatacao Compacta de Volume                                    |
//+------------------------------------------------------------------+
string FormatVolume(double val)
  {
   if(val >= 1000000000.0) return(DoubleToString(val / 1000000000.0, 1) + "B");
   if(val >= 1000000.0)    return(DoubleToString(val / 1000000.0, 1) + "M");
   if(val >= 1000.0)       return(DoubleToString(val / 1000.0, 1) + "K");
   if(MathAbs(val - MathRound(val)) < 0.001) return(IntegerToString((int)MathRound(val)));
   return(DoubleToString(val, 1));
  }

string FormatSignedVolume(double val)
  {
   return((val > 0.0 ? "+" : "") + FormatVolume(val));
  }

//+------------------------------------------------------------------+
//| Limpeza Segura dos Objetos do Indicador                          |
//+------------------------------------------------------------------+
void DeleteAllObjects(bool include_anchors)
  {
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, g_prefix) == 0)
        {
         if(!include_anchors && (name == g_anchor_start || name == g_anchor_end))
            continue;
         ObjectDelete(0, name);
        }
     }
  }
//+------------------------------------------------------------------+
