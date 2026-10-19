//+------------------------------------------------------------------+
//|                                  BoletaScalpingComCanais.mq5     |
//|                             Copyright 2026, ViniBurgo Developer  |
//|    Boleta Scalping Pro & Risco + Canais Auto 40x40 + Mira Mouse  |
//+------------------------------------------------------------------+
#property copyright "Senior MQL5 Developer"
#property link      "https://www.mql5.com"
#property version   "10.00"
#property description "Boleta Visual de Scalping com Risco $, 40 Projeções de Canais (Manual/Auto D1) e Mira Fantasma"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Paleta Dark Mode Moderna e Fluida (Idêntica ao Layout do Usuário)
#define COLOR_PANEL_BG        C'22,24,29'    // Fundo Principal Slate Obsidian
#define COLOR_HEADER_BG       C'16,17,21'    // Cabeçalho Sofisticado
#define COLOR_MARKET_BG       C'28,31,38'    // Faixa Mercado
#define COLOR_STRIP_BG        C'28,31,38'    // Faixa HUD
#define COLOR_SECTION_BG      C'25,28,34'    // Fundo da gaveta de canais
#define COLOR_BORDER          C'38,42,52'    // Borda Sutil
#define COLOR_TEXT_MAIN       C'240,242,245' // Texto Claro
#define COLOR_TEXT_MUTED      C'150,155,168' // Texto Secundário
#define COLOR_EDIT_BG         C'32,35,44'    // Campo de Edição
#define COLOR_EDIT_RO_BG      C'42,45,55'    // Campo Read-Only
#define COLOR_CHECK_ACTIVE    C'0,210,130'   // Check Ativo (Mint Green idêntico à imagem)
#define COLOR_CHECK_INACT     C'55,60,72'    // Check Inativo
#define COLOR_STEP_BTN        C'44,48,60'    // Botões Step (- / +)
#define COLOR_PERIOD_BTN      C'40,45,60'    // Botão Período HUD
#define COLOR_DRAWER_BTN      C'32,45,60'    // Botão Sanfona / Gaveta de Canais
#define COLOR_CHAN_START      C'30,55,80'    // Botão Marcar Manual
#define COLOR_CHAN_PROJ       C'25,90,65'    // Botão Projetar Manual
#define COLOR_CHAN_AUTO       C'35,95,65'    // Botão Marcar Auto (Destaque Verde)
#define COLOR_CHAN_DAY_TODAY  C'30,55,90'    // Botão Dia Hoje (Azul)
#define COLOR_CHAN_DAY_YEST   C'95,50,30'    // Botão Dia Ontem (Âmbar)
#define COLOR_BUY_BTN         C'16,160,85'   // Compra Emerald
#define COLOR_SELL_BTN        C'210,45,55'   // Venda Coral
#define COLOR_INVERT_BTN      C'205,115,20'  // Inverter Amber
#define COLOR_HEDGE_BTN       C'35,90,165'   // Hedge Sapphire
#define COLOR_CLOSE_ALL_BTN   C'235,238,242' // Zerar Tudo Prata
#define COLOR_CLOSE_PRF_BTN   C'30,120,65'   // Zerar Lucro
#define COLOR_CLOSE_LSS_BTN   C'145,40,45'   // Zerar Prejuízo
#define COLOR_CANCEL_BTN      C'60,65,78'    // Cancelar Ordens
#define COLOR_GHOST_CONFIRM   C'20,110,190'  // Fantasma Confirmar
#define COLOR_PROFIT_GREEN    C'0,230,120'   // Verde Lucro
#define COLOR_LOSS_RED        C'255,85,85'   // Vermelho Prejuízo
#define COLOR_TOGGLE_PCT      C'35,80,145'   // Modo Risco %
#define COLOR_TOGGLE_CASH     C'25,125,90'   // Modo Risco $ (Verde igual imagem)

//--- Prefixo global para objetos
#define PREFIX_GUI         "BPRO_GUI_"
#define PREFIX_GHOST       "BPRO_GHOST_"
#define PREFIX_CANAL_LINES "BPRO_CLINE_"
#define PREFIX_CANAL_TEMP  "BPRO_CTEMP_"

//--- Z-Order de Camada (Renderização Absoluta)
#define ZORDER_PANEL_BG      999990
#define ZORDER_PANEL_STRIP   999995
#define ZORDER_PANEL_CTRL    999998
#define ZORDER_PANEL_TXT     999999

//--- Enumeradores
enum ENUM_GHOST_TYPE
{
   GHOST_NONE,
   GHOST_BUY,
   GHOST_SELL
};

enum ENUM_RISK_MODE
{
   RISK_MODE_PERCENT,  // Risco por Porcentagem (%)
   RISK_MODE_CASH,     // Risco por Valor Financeiro Fixo ($)
   RISK_MODE_MANUAL    // Lote Fixo Manual
};

enum ENUM_HUD_PERIOD
{
   HUD_PERIOD_TODAY,   // Hoje (Desde 00:00)
   HUD_PERIOD_WEEK,    // Últimos 7 Dias
   HUD_PERIOD_MONTH,   // Últimos 30 Dias
   HUD_PERIOD_ALL,     // Todo o Histórico
   HUD_PERIOD_WALLET   // Saldo da Carteira (Balance / Equity)
};

enum ENUM_AUTO_DAY
{
   AUTO_DAY_CURRENT,   // Dia Atual (Hoje)
   AUTO_DAY_PREVIOUS   // Dia Anterior (Ontem / D-1)
};

enum ENUM_CHANNEL_FIT_MODE
{
   FIT_MODE_DILUTE,    // Diluir a sobra em todos os canais (Canais 100% perfeitamente iguais)
   FIT_MODE_EXTREME    // Fixo estrito de 500 pts (Sobra colocada na extremidade / 40º canal)
};

//+------------------------------------------------------------------+
//| Parâmetros de Entrada (.SET / CONFIGURAÇÃO PADRÃO)               |
//+------------------------------------------------------------------+
input group "=== CONFIGURAÇÃO DO ATIVO & ROTEAMENTO ==="
input string          InpSymbol            = "";                 // Ativo Operado (Vazio = Gráfico Atual)
input ulong           InpMagicNumber       = 123456;             // Magic Number das Ordens
input ulong           InpSlippage          = 20;                 // Desvio Máximo / Slippage (pontos)
input bool            InpFilterSymbolOnly  = true;               // Filtrar Métricas apenas deste Ativo

input group "=== GESTÃO DE RISCO (CONFIGURAÇÃO PADRÃO DA IMAGEM) ==="
input ENUM_RISK_MODE  InpDefaultRiskMode   = RISK_MODE_CASH;     // Modo de Risco Inicial (Risco: $)
input double          InpRiskCash          = 0.01;               // Risco Financeiro Fixo Inicial ($)
input double          InpRiskPercent       = 1.0;                // Risco Percentual Inicial (%)
input double          InpDefaultLot        = 0.01;               // Lote Manual Inicial
input bool            InpSLActive          = true;               // Ativar Stop Loss Inicial
input int             InpDefaultSL         = 150;                // Stop Loss Padrão (pontos)
input bool            InpTPActive          = true;               // Ativar Take Profit Inicial
input int             InpDefaultTP         = 300;                // Take Profit Padrão (pontos)
input bool            InpBEActive          = true;               // Ativar Break Even Inicial
input int             InpDefaultBE         = 60;                 // Break Even Padrão (pontos)
input bool            InpTSActive          = true;               // Ativar Trailing Stop Inicial
input int             InpDefaultTS         = 150;                // Trailing Stop Padrão (pontos)
input int             InpDefaultTSStep     = 2;                  // Passo do Trailing Stop / Trailing Step (pontos)

input group "=== CANAIS DE FREQUÊNCIA (40 CIMA / 40 BAIXO / AUTO D1) ==="
input int             InpProjUp            = 40;                 // Canais padrão para CIMA (Salvo em 40)
input int             InpProjDown          = 40;                 // Canais padrão para BAIXO (Salvo em 40)
input int             InpChannelPoints     = 500;                // Tamanho Padrão do Canal Auto (pontos)
input ENUM_AUTO_DAY   InpAutoDayRef        = AUTO_DAY_CURRENT;   // Dia Inicial da Marcação Auto (Hoje ou Ontem)
input ENUM_CHANNEL_FIT_MODE InpChannelFitMode = FIT_MODE_DILUTE; // Ajuste da Sobra do Canal Auto
input bool            InpAutoOnStartup     = false;              // Projetar Auto Imediatamente ao Iniciar
input bool            InpCanalPushAlert    = true;               // Notificação Push no Rompimento
input bool            InpCanalScreenAlert  = true;               // Alerta Sonoro / Pop-up no Rompimento
input color           InpColorChannel      = C'220,50,50';       // Cor das Linhas Principais
input color           InpColorChannelMid   = C'235,185,40';      // Cor das Linhas Médias (50%)
input bool            InpShowChannelRefMarkers = true;           // Exibir Marcadores de Topo/Fundo no Gráfico
input color           InpColorRefMarkers   = clrYellow;          // Cor dos Marcadores (Pontos/Setas/Textos)

input group "=== CUSTOMIZAÇÃO VISUAL (.SET / O QUE APARECE NA TELA) ==="
input bool            InpShowMarketStrip   = true;               // Exibir Faixa de Mercado (Ativo/Spread/Timer)
input bool            InpShowSpread        = true;               // Exibir Spread na Faixa de Mercado
input bool            InpShowCandleTimer   = true;               // Exibir Relógio do Candle na Faixa
input bool            InpShowHudStrip      = true;               // Exibir Faixa HUD (Lucro/Prejuízo/Líquido)
input ENUM_HUD_PERIOD InpDefaultHudPeriod  = HUD_PERIOD_TODAY;   // Visualização Inicial do HUD
input bool            InpShowRiskSection   = true;               // Exibir Seção de Gestão de Risco (% / $)
input bool            InpShowLotSection    = true;               // Exibir Linha de Lote
input bool            InpShowSLSection     = true;               // Exibir Linha de Stop Loss
input bool            InpShowTPSection     = true;               // Exibir Linha de Take Profit
input bool            InpShowParcialSection= false;              // Exibir Linhas de Parcial (Oculto conforme imagem)
input bool            InpShowBESection     = true;               // Exibir Linha de Break Even
input bool            InpShowTSSection     = true;               // Exibir Linha de Trailing Stop
input bool            InpEnableChannels    = true;               // Ativar Módulo de Canais Integrado
input bool            InpChannelsStartOpen = false;              // Iniciar Gaveta de Canais Aberta (false = Recolhida)
input bool            InpShowInvertHedge   = true;               // Exibir Botões Inverter e Hedge
input bool            InpShowSelectiveClose= true;               // Exibir Botões Zerar Lucro / Zerar Prejuízo
input bool            InpShowCancelPendings= true;               // Exibir Botão Cancelar Ordens Pendentes
input bool            InpShowGhostOrder    = true;               // Exibir Botão de Ordem Fantasma

input group "=== REALIZAÇÃO PARCIAL (SE HABILITADA) ==="
input bool            InpParcialActive     = true;               // Ativar Parcial Inicial
input bool            InpParcialIsCash     = false;              // Modo Alvo Parcial (false = Pontos, true = $)
input int             InpParcialTargetPts  = 150;                // Alvo da Parcial Padrão (pontos)
input double          InpParcialTargetCash = 25.0;               // Alvo da Parcial Padrão ($)
input double          InpParcialVolumePct  = 50.0;               // Volume da Parcial (% da Posição)
input bool            InpParcialMoveBE     = true;               // Mover SL para Zero a Zero pós Parcial

input group "=== INCREMENTOS DOS BOTÕES (+ / -) ==="
input double          InpStepRiskPct       = 0.5;                // Passo do Risco Percentual (%)
input double          InpStepRiskCash      = 1.0;                // Passo do Risco Fixo ($)
input int             InpStepPoints        = 20;                 // Passo de Pontos (SL, TP, BE, TS, Parcial Pts)
input double          InpStepParcialCash   = 5.0;                // Passo do Alvo Parcial ($)
input double          InpStepParcialVol    = 10.0;               // Passo do Volume Parcial (%)

input group "=== POSICIONAMENTO DA BOLETA ==="
input int             InpPanelX            = 20;                 // Posição Inicial X no Gráfico
input int             InpPanelY            = 40;                 // Posição Inicial Y no Gráfico

//+------------------------------------------------------------------+
//| Primitivos Gráficos Ultraleves                                   |
//+------------------------------------------------------------------+
void GUI_CreateRectangleLabel(long chart_id, const string full_name, int x, int y, int w, int h, color bg_color, color border_color, int zorder=ZORDER_PANEL_BG)
{
   if(ObjectFind(chart_id, full_name) < 0)
      ObjectCreate(chart_id, full_name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   
   ObjectSetInteger(chart_id, full_name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(chart_id, full_name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(chart_id, full_name, OBJPROP_XSIZE, w);
   ObjectSetInteger(chart_id, full_name, OBJPROP_YSIZE, h);
   ObjectSetInteger(chart_id, full_name, OBJPROP_BGCOLOR, bg_color);
   ObjectSetInteger(chart_id, full_name, OBJPROP_BORDER_COLOR, border_color);
   ObjectSetInteger(chart_id, full_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(chart_id, full_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(chart_id, full_name, OBJPROP_BACK, false);
   ObjectSetInteger(chart_id, full_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chart_id, full_name, OBJPROP_ZORDER, zorder);
}

void GUI_CreateButton(long chart_id, const string full_name, int x, int y, int w, int h, const string text, color bg_color, color txt_color, int font_size=8, bool bold=true, int zorder=ZORDER_PANEL_CTRL)
{
   if(ObjectFind(chart_id, full_name) < 0)
      ObjectCreate(chart_id, full_name, OBJ_BUTTON, 0, 0, 0);
   
   ObjectSetInteger(chart_id, full_name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(chart_id, full_name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(chart_id, full_name, OBJPROP_XSIZE, w);
   ObjectSetInteger(chart_id, full_name, OBJPROP_YSIZE, h);
   ObjectSetString(chart_id, full_name, OBJPROP_TEXT, text);
   ObjectSetString(chart_id, full_name, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(chart_id, full_name, OBJPROP_FONTSIZE, font_size);
   ObjectSetInteger(chart_id, full_name, OBJPROP_BGCOLOR, bg_color);
   ObjectSetInteger(chart_id, full_name, OBJPROP_COLOR, txt_color);
   ObjectSetInteger(chart_id, full_name, OBJPROP_BORDER_COLOR, COLOR_BORDER);
   ObjectSetInteger(chart_id, full_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(chart_id, full_name, OBJPROP_BACK, false);
   ObjectSetInteger(chart_id, full_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chart_id, full_name, OBJPROP_ZORDER, zorder);
   ObjectSetInteger(chart_id, full_name, OBJPROP_STATE, false);
}

void GUI_CreateEdit(long chart_id, const string full_name, int x, int y, int w, int h, const string text, color bg_color, color txt_color, bool read_only=false, int zorder=ZORDER_PANEL_CTRL)
{
   if(ObjectFind(chart_id, full_name) < 0)
      ObjectCreate(chart_id, full_name, OBJ_EDIT, 0, 0, 0);
   
   ObjectSetInteger(chart_id, full_name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(chart_id, full_name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(chart_id, full_name, OBJPROP_XSIZE, w);
   ObjectSetInteger(chart_id, full_name, OBJPROP_YSIZE, h);
   ObjectSetString(chart_id, full_name, OBJPROP_TEXT, text);
   ObjectSetString(chart_id, full_name, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(chart_id, full_name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(chart_id, full_name, OBJPROP_ALIGN, ALIGN_CENTER);
   ObjectSetInteger(chart_id, full_name, OBJPROP_BGCOLOR, bg_color);
   ObjectSetInteger(chart_id, full_name, OBJPROP_COLOR, txt_color);
   ObjectSetInteger(chart_id, full_name, OBJPROP_BORDER_COLOR, COLOR_BORDER);
   ObjectSetInteger(chart_id, full_name, OBJPROP_READONLY, read_only);
   ObjectSetInteger(chart_id, full_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(chart_id, full_name, OBJPROP_BACK, false);
   ObjectSetInteger(chart_id, full_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chart_id, full_name, OBJPROP_ZORDER, zorder);
}

void GUI_CreateLabel(long chart_id, const string full_name, int x, int y, const string text, color txt_color, int font_size=8, bool bold=false, int zorder=ZORDER_PANEL_TXT)
{
   if(ObjectFind(chart_id, full_name) < 0)
      ObjectCreate(chart_id, full_name, OBJ_LABEL, 0, 0, 0);
   
   ObjectSetInteger(chart_id, full_name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(chart_id, full_name, OBJPROP_YDISTANCE, y);
   ObjectSetString(chart_id, full_name, OBJPROP_TEXT, text);
   ObjectSetString(chart_id, full_name, OBJPROP_FONT, bold ? "Segoe UI Semibold" : "Segoe UI");
   ObjectSetInteger(chart_id, full_name, OBJPROP_FONTSIZE, font_size);
   ObjectSetInteger(chart_id, full_name, OBJPROP_COLOR, txt_color);
   ObjectSetInteger(chart_id, full_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(chart_id, full_name, OBJPROP_BACK, false);
   ObjectSetInteger(chart_id, full_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chart_id, full_name, OBJPROP_ZORDER, zorder);
}

//+------------------------------------------------------------------+
//| Funções Utilitárias                                              |
//+------------------------------------------------------------------+
int GetLotDecimals(const string sym)
{
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step <= 0.000001) return 2;
   if(step >= 1.0)      return 0;
   if(step >= 0.1)      return 1;
   if(step >= 0.01)     return 2;
   if(step >= 0.001)    return 3;
   return 4;
}

double NormalizeLot(double lot, const string sym)
{
   double stepLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   
   if(stepLot <= 0.0) stepLot = 0.01;
   if(minLot <= 0.0)  minLot = 0.01;
   if(maxLot <= 0.0)  maxLot = 100.0;
   
   double norm = MathFloor(lot / stepLot) * stepLot;
   if(norm < minLot) norm = minLot;
   if(norm > maxLot) norm = maxLot;
   
   int dec = GetLotDecimals(sym);
   return NormalizeDouble(norm, dec);
}

void SetBestFillingMode(CTrade &trade, const string sym)
{
   uint filling = (uint)SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) != 0)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((filling & SYMBOL_FILLING_FOK) != 0)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
}

string GetCandleTimerString(const string sym, ENUM_TIMEFRAMES tf)
{
   datetime bar_time = (datetime)SeriesInfoInteger(sym, tf, SERIES_LASTBAR_DATE);
   if(bar_time == 0) return "--:--";
   
   int period_secs = PeriodSeconds(tf);
   if(period_secs <= 0) return "--:--";
   
   datetime next_bar_time = bar_time + period_secs;
   datetime cur_time = TimeCurrent();
   
   long remaining = (long)(next_bar_time - cur_time);
   if(remaining < 0) remaining = 0;
   
   int hours = (int)(remaining / 3600);
   int mins  = (int)((remaining % 3600) / 60);
   int secs  = (int)(remaining % 60);
   
   if(hours > 0)
      return StringFormat("%02d:%02d:%02d", hours, mins, secs);
   else
      return StringFormat("%02d:%02d", mins, secs);
}

string GetPeriodName(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";
      case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";
      case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
      default:         return "TF";
   }
}

//+------------------------------------------------------------------+
//| Classe Principal: CBoletaMaster                                  |
//+------------------------------------------------------------------+
class CBoletaMaster
{
private:
   string            m_symbol;
   ulong             m_magic;
   ulong             m_slippage;
   long              m_chart_id;
   int               m_x;
   int               m_y;
   int               m_width;
   int               m_height;
   int               m_header_h;
   
   bool              m_is_minimized;
   bool              m_is_dragging;
   int               m_drag_offset_x;
   int               m_drag_offset_y;
   
   // Módulo de Canais Integrado (Gaveta Retrátil)
   bool              m_channels_expanded;
   int               m_proj_up;
   int               m_proj_down;
   int               m_channel_pts;
   ENUM_AUTO_DAY     m_auto_day;
   ENUM_CHANNEL_FIT_MODE m_fit_mode;
   int               m_chan_step;
   bool              m_chan_visible;
   double            m_highest_proj;
   double            m_lowest_proj;
   bool              m_has_projections;
   bool              m_alerted_high;
   bool              m_alerted_low;
   datetime          m_last_alert_time;
   string            m_temp_line1;
   string            m_temp_line2;
   
   // Modos e Toggles Operacionais
   ENUM_RISK_MODE    m_risk_mode;
   ENUM_HUD_PERIOD   m_hud_period;
   bool              m_sl_active;
   bool              m_tp_active;
   bool              m_be_active;
   bool              m_ts_active;
   bool              m_parcial_active;
   bool              m_parcial_is_cash;
   bool              m_parcial_move_be;
   
   // Valores Operacionais
   double            m_risk_percent;
   double            m_risk_cash;
   double            m_manual_lot;
   int               m_sl_points;
   int               m_tp_points;
   int               m_be_points;
   int               m_ts_points;
   int               m_ts_step_pts;
   int               m_parcial_target_pts;
   double            m_parcial_target_cash;
   double            m_parcial_vol_pct;
   
   // Métricas
   double            m_history_profit;
   double            m_history_loss;
   double            m_history_net;
   double            m_floating_pnl;
   
   // Ordem Fantasma Interativa
   bool              m_ghost_placing;      // Modo mira ativo seguindo mouse
   bool              m_rbutton_was_down;   // Anti-debounce do clique direito
   ENUM_GHOST_TYPE   m_ghost_type;
   double            m_ghost_entry_price;
   double            m_ghost_sl_price;
   double            m_ghost_lot;
   
   CTrade            m_trade;
   
   string            GetGVPrefix() const { return "BProCan_" + IntegerToString(m_chart_id) + "_"; }
   void              CreateRectangleLabel(const string name, int x, int y, int w, int h, color bg_color, color border_color, int zorder=ZORDER_PANEL_BG);
   void              CreateButton(const string name, int x, int y, int w, int h, const string text, color bg_color, color txt_color, int font_size=8, bool bold=true);
   void              CreateEdit(const string name, int x, int y, int w, int h, const string text, color bg_color, color txt_color, bool read_only=false);
   void              CreateLabel(const string name, int x, int y, const string text, color txt_color, int font_size=8, bool bold=false);
   
   void              UpdateFieldValues();
   void              DesenharHLine(const string name, double price, color clr, int style, int width=0, const string desc="");
   void              DesenharMarcadoresReferencia(datetime bar_time, double top_body, double bottom_body, const string day_name, double top_pavio_pts, double btm_pavio_pts);
   void              CriarLinhaTemporaria(const string nome, double price);
   void              SalvarEstadoCanais(double baseTop, double baseBottom, double amp=0.0, datetime refTime=0, double topPavio=0.0, double btmPavio=0.0);
   void              LimparVariaveisGlobaisCanais();
   
   void              UpdateGhostPreview(double price, datetime time);
   void              CreateAnchoredGhostLines();

public:
                     CBoletaMaster();
                    ~CBoletaMaster();
   
   bool              Init(const string symbol, ulong magic, ulong slippage, int x=20, int y=40);
   void              Destroy(const int reason=REASON_REMOVE);
   void              Render();
   void              BringToFront();
   void              CheckForegroundState();
   void              UpdateLiveMetrics();
   bool              Contains(int x, int y) const;
   
   // Getters
   bool              IsDragging()             const { return m_is_dragging; }
   string            GetSymbol()              const { return m_symbol; }
   bool              IsSLActive()             const { return m_sl_active; }
   bool              IsTPActive()             const { return m_tp_active; }
   bool              IsBEActive()             const { return m_be_active; }
   bool              IsTSActive()             const { return m_ts_active; }
   bool              IsParcialActive()        const { return m_parcial_active; }
   bool              IsParcialCashMode()      const { return m_parcial_is_cash; }
   bool              IsParcialMoveBE()        const { return m_parcial_move_be; }
   int               GetBEPoints()            const { return m_be_points; }
   int               GetTSPoints()            const { return m_ts_points; }
   int               GetTSStepPoints()        const { return m_ts_step_pts; }
   int               GetParcialTargetPoints() const { return m_parcial_target_pts; }
   double            GetParcialTargetCash()   const { return m_parcial_target_cash; }
   double            GetParcialVolumePct()    const { return m_parcial_vol_pct; }
   double            GetEffectiveLot();
   
   void              RecalculateRiskLot();
   void              CalculateHistoricalStats();
   
   // Toggles Principais
   void              ToggleMinimize();
   void              ToggleChannelsDrawer();
   void              ToggleRiskAuto();
   void              ToggleRiskMode();
   void              ToggleSL();
   void              ToggleTP();
   void              ToggleBE();
   void              ToggleTS();
   void              ToggleParcial();
   void              ToggleParcialMode();
   void              ToggleParcialBE();
   void              CycleHudPeriod();
   void              MovePanel(int new_x, int new_y);
   
   // Ajustes Steppers (+ / -)
   void              AdjustRisk(double delta);
   void              AdjustLot(double delta);
   void              AdjustSL(int delta);
   void              AdjustTP(int delta);
   void              AdjustBE(int delta);
   void              AdjustTS(int delta);
   void              AdjustParcialTarget(double delta);
   void              AdjustParcialVol(double delta);
   void              AdjustChanUp(int delta);
   void              AdjustChanDown(int delta);
   
   // Ações de Canais (Manual e Automático D1)
   void              StartChannelMarking();
   void              ProjetarCanais();
   void              ProjetarCanaisAuto();
   void              ToggleAutoDay();
   void              ToggleChannelVisibility();
   void              LimparCanais();
   void              RestaurarEstadoCanais();
   void              CheckBreakout();
   
   // Execuções
   void              ExecuteBuy();
   void              ExecuteSell();
   void              ExecuteInvert();
   void              ExecuteHedge();
   void              ExecuteCloseAll();
   void              ExecuteCloseProfit();
   void              ExecuteCloseLoss();
   void              ExecuteCancelPendings();
   
   // Fantasmas com Mira Interativa
   void              StartGhostPlacement(ENUM_GHOST_TYPE type);
   void              AnchorGhostOrder(double entry_price);
   void              UpdateGhostFromDrag(const string obj_name);
   void              ExecuteGhostOrder();
   void              ClearGhostOrder();
   bool              HasGhostOrder()    const { return (m_ghost_type != GHOST_NONE && !m_ghost_placing); }
   bool              IsGhostPlacing()   const { return m_ghost_placing; }
   
   // Eventos
   void              OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam);
   void              HandleEndEdit(const string &obj_name);
   void              HandleButtonClick(const string &obj_name);
};

//+------------------------------------------------------------------+
//| Construtor CBoletaMaster                                         |
//+------------------------------------------------------------------+
CBoletaMaster::CBoletaMaster()
   : m_symbol(""),
     m_magic(123456),
     m_slippage(20),
     m_chart_id(0),
     m_x(20),
     m_y(40),
     m_width(250),
     m_height(480),
     m_header_h(26),
     m_is_minimized(false),
     m_is_dragging(false),
     m_drag_offset_x(0),
     m_drag_offset_y(0),
     m_channels_expanded(false),
     m_proj_up(40),
     m_proj_down(40),
     m_channel_pts(500),
     m_chan_step(0),
     m_chan_visible(true),
     m_highest_proj(0.0),
     m_lowest_proj(0.0),
     m_has_projections(false),
     m_alerted_high(false),
     m_alerted_low(false),
     m_last_alert_time(0),
     m_risk_mode(RISK_MODE_CASH),
     m_hud_period(HUD_PERIOD_TODAY),
     m_sl_active(true),
     m_tp_active(true),
     m_be_active(true),
     m_ts_active(true),
     m_parcial_active(true),
     m_parcial_is_cash(false),
     m_parcial_move_be(true),
     m_risk_percent(1.0),
     m_risk_cash(0.01),
     m_manual_lot(0.01),
     m_sl_points(150),
     m_tp_points(300),
     m_be_points(60),
     m_ts_points(150),
     m_ts_step_pts(2),
     m_parcial_target_pts(150),
     m_parcial_target_cash(25.0),
     m_parcial_vol_pct(50.0),
     m_auto_day(AUTO_DAY_CURRENT),
     m_fit_mode(FIT_MODE_DILUTE),
     m_history_profit(0.0),
     m_history_loss(0.0),
     m_history_net(0.0),
     m_floating_pnl(0.0),
     m_ghost_placing(false),
     m_rbutton_was_down(false),
     m_ghost_type(GHOST_NONE),
     m_ghost_entry_price(0.0),
     m_ghost_sl_price(0.0),
     m_ghost_lot(0.01)
{
   m_temp_line1 = PREFIX_CANAL_TEMP + "1";
   m_temp_line2 = PREFIX_CANAL_TEMP + "2";
}

CBoletaMaster::~CBoletaMaster()
{
   Destroy(REASON_REMOVE);
}

bool CBoletaMaster::Init(const string symbol, ulong magic, ulong slippage, int x=20, int y=40)
{
   m_chart_id   = ChartID();
   m_symbol     = (symbol != "") ? symbol : _Symbol;
   m_magic      = magic;
   m_slippage   = slippage;
   m_x          = x;
   m_y          = y;
   
   m_risk_mode           = InpDefaultRiskMode;
   m_hud_period          = InpDefaultHudPeriod;
   m_risk_cash           = InpRiskCash;
   m_risk_percent        = InpRiskPercent;
   m_manual_lot          = InpDefaultLot;
   m_sl_active           = InpSLActive;
   m_sl_points           = InpDefaultSL;
   m_tp_active           = InpTPActive;
   m_tp_points           = InpDefaultTP;
   m_be_active           = InpBEActive;
   m_be_points           = InpDefaultBE;
   m_ts_active           = InpTSActive;
   m_ts_points           = InpDefaultTS;
   m_ts_step_pts         = InpDefaultTSStep;
   m_parcial_active      = InpParcialActive;
   m_parcial_is_cash     = InpParcialIsCash;
   m_parcial_target_pts  = InpParcialTargetPts;
   m_parcial_target_cash = InpParcialTargetCash;
   m_parcial_vol_pct     = InpParcialVolumePct;
   m_parcial_move_be     = InpParcialMoveBE;
   
   m_proj_up             = InpProjUp;
   m_proj_down           = InpProjDown;
   m_channel_pts         = InpChannelPoints;
   m_auto_day            = InpAutoDayRef;
   m_fit_mode            = InpChannelFitMode;
   m_channels_expanded   = InpChannelsStartOpen;
   m_chan_step           = 0;
   m_chan_visible        = true;
   m_ghost_placing       = false;
   m_rbutton_was_down    = false;
   
   m_trade.SetExpertMagicNumber(m_magic);
   m_trade.SetDeviationInPoints(m_slippage);
   m_trade.SetMarginMode();
   SetBestFillingMode(m_trade, m_symbol);
   
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin <= 0.0) freeMargin = AccountInfoDouble(ACCOUNT_BALANCE);
   
   if(freeMargin > 0.0)
   {
      if(m_risk_mode == RISK_MODE_PERCENT)
         m_risk_cash = freeMargin * (m_risk_percent / 100.0);
      else if(m_risk_mode == RISK_MODE_CASH && m_risk_cash > 0.0)
         m_risk_percent = (m_risk_cash / freeMargin) * 100.0;
   }
   
   SymbolSelect(m_symbol, true);
   ChartSetInteger(m_chart_id, CHART_EVENT_MOUSE_MOVE, true);
   ChartSetInteger(m_chart_id, CHART_FOREGROUND, false);
   
   Render();
   RestaurarEstadoCanais();
   
   if(InpAutoOnStartup && !m_has_projections)
      ProjetarCanaisAuto();
      
   RecalculateRiskLot();
   UpdateLiveMetrics();
   return true;
}

void CBoletaMaster::Destroy(const int reason)
{
   ChartSetInteger(m_chart_id, CHART_CONTEXT_MENU, true);
   ObjectsDeleteAll(m_chart_id, PREFIX_GUI);
   ClearGhostOrder();
   ObjectDelete(m_chart_id, m_temp_line1);
   ObjectDelete(m_chart_id, m_temp_line2);
   
   if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE)
   {
      LimparCanais();
   }
   ChartRedraw(m_chart_id);
}

bool CBoletaMaster::Contains(int x, int y) const
{
   int cur_h = m_is_minimized ? m_header_h : m_height;
   return (x >= m_x && x <= m_x + m_width && y >= m_y && y <= m_y + cur_h);
}

void CBoletaMaster::CheckForegroundState()
{
   if(ChartGetInteger(m_chart_id, CHART_FOREGROUND) != 0)
   {
      ChartSetInteger(m_chart_id, CHART_FOREGROUND, false);
      ChartRedraw(m_chart_id);
   }
}

void CBoletaMaster::BringToFront()
{
   if(m_is_dragging) return;
   if(ChartGetInteger(m_chart_id, CHART_FOREGROUND) != 0)
      ChartSetInteger(m_chart_id, CHART_FOREGROUND, false);
   
   Render();
   UpdateFieldValues();
   UpdateLiveMetrics();
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::CreateRectangleLabel(const string name, int x, int y, int w, int h, color bg_color, color border_color, int zorder=ZORDER_PANEL_BG)
{
   GUI_CreateRectangleLabel(m_chart_id, PREFIX_GUI + name, x, y, w, h, bg_color, border_color, zorder);
}

void CBoletaMaster::CreateButton(const string name, int x, int y, int w, int h, const string text, color bg_color, color txt_color, int font_size=8, bool bold=true)
{
   GUI_CreateButton(m_chart_id, PREFIX_GUI + name, x, y, w, h, text, bg_color, txt_color, font_size, bold, ZORDER_PANEL_CTRL);
}

void CBoletaMaster::CreateEdit(const string name, int x, int y, int w, int h, const string text, color bg_color, color txt_color, bool read_only=false)
{
   GUI_CreateEdit(m_chart_id, PREFIX_GUI + name, x, y, w, h, text, bg_color, txt_color, read_only, ZORDER_PANEL_CTRL);
}

void CBoletaMaster::CreateLabel(const string name, int x, int y, const string text, color txt_color, int font_size=8, bool bold=false)
{
   GUI_CreateLabel(m_chart_id, PREFIX_GUI + name, x, y, text, txt_color, font_size, bold, ZORDER_PANEL_TXT);
}

//+------------------------------------------------------------------+
//| Renderização Procedural Dinâmica (Customização Total via .SET)   |
//+------------------------------------------------------------------+
void CBoletaMaster::Render()
{
   ChartSetInteger(m_chart_id, CHART_FOREGROUND, false);
   ObjectsDeleteAll(m_chart_id, PREFIX_GUI);
   
   // 1. Cabeçalho Minimalista
   CreateRectangleLabel("Panel_BG", m_x, m_y, m_width, m_header_h, COLOR_PANEL_BG, COLOR_BORDER, ZORDER_PANEL_BG);
   CreateRectangleLabel("Header_BG", m_x, m_y, m_width, m_header_h, COLOR_HEADER_BG, COLOR_BORDER, ZORDER_PANEL_STRIP);
   CreateLabel("Header_Title", m_x + 10, m_y + 5, "SCALP PRO v10", clrWhite, 9, true);
   CreateButton("Btn_Min", m_x + 200, m_y + 3, 20, 20, m_is_minimized ? "+" : "-", COLOR_EDIT_BG, COLOR_TEXT_MAIN, 9, true);
   CreateButton("Btn_Close", m_x + 224, m_y + 3, 20, 20, "X", COLOR_SELL_BTN, COLOR_TEXT_MAIN, 9, true);
   
   if(m_is_minimized)
   {
      ChartRedraw(m_chart_id);
      return;
   }
   
   int cur_y = m_y + m_header_h + 4;
   int row_w = m_width - 16;
   int offset_x = m_x + 8;
   
   // 2. Faixa de Mercado
   if(InpShowMarketStrip)
   {
      CreateRectangleLabel("Strip_Market_BG", offset_x, cur_y, row_w, 22, COLOR_MARKET_BG, COLOR_BORDER, ZORDER_PANEL_STRIP);
      CreateLabel("Lbl_Mkt_Symbol", offset_x + 6, cur_y + 3, m_symbol, clrGold, 8, true);
      if(InpShowSpread)
         CreateLabel("Lbl_Mkt_Spread", offset_x + 115, cur_y + 3, "Sp: --", clrWhite, 8, false);
      if(InpShowCandleTimer)
         CreateLabel("Lbl_Mkt_Timer",  offset_x + 172, cur_y + 3, "? --:--", clrCyan, 8, true);
      cur_y += 25;
   }
   
   // 3. Faixa HUD
   if(InpShowHudStrip)
   {
      CreateRectangleLabel("Strip_Daily_BG", offset_x, cur_y, row_w, 22, COLOR_STRIP_BG, COLOR_BORDER, ZORDER_PANEL_STRIP);
      CreateButton("Btn_Hud_Period", offset_x + 2, cur_y + 2, 42, 18, "Hoje", COLOR_PERIOD_BTN, clrYellow, 7, true);
      CreateLabel("Lbl_Hud_P1", offset_x + 48, cur_y + 3, "+$0.00", COLOR_PROFIT_GREEN, 8, true);
      CreateLabel("Lbl_Hud_P2", offset_x + 112, cur_y + 3, "-$0.00", COLOR_LOSS_RED, 8, true);
      CreateLabel("Lbl_Hud_P3", offset_x + 176, cur_y + 3, "Líq: $0", clrWhite, 8, true);
      cur_y += 26;
   }
   
   // 4. Seção de Risco (Risco: $ padrão da imagem)
   if(InpShowRiskSection)
   {
      bool is_auto_risk = (m_risk_mode != RISK_MODE_MANUAL);
      CreateButton("Chk_Risk", offset_x, cur_y + 1, 16, 16, is_auto_risk ? "X" : "", is_auto_risk ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 8, true);
      
      string risk_toggle_text = (m_risk_mode == RISK_MODE_PERCENT) ? "Risco: %" : "Risco: $";
      color risk_toggle_bg = (m_risk_mode == RISK_MODE_PERCENT) ? COLOR_TOGGLE_PCT : COLOR_TOGGLE_CASH;
      CreateButton("Btn_Risk_Toggle", offset_x + 20, cur_y, 102, 18, risk_toggle_text, risk_toggle_bg, COLOR_TEXT_MAIN, 8, true);
      
      CreateButton("Btn_Risk_Dec", offset_x + 128, cur_y, 20, 18, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
      string init_risk_str = (m_risk_mode == RISK_MODE_PERCENT) ? DoubleToString(m_risk_percent, 1) : DoubleToString(m_risk_cash, 2);
      CreateEdit("Edit_Risk", offset_x + 151, cur_y, 60, 18, init_risk_str, COLOR_EDIT_BG, COLOR_TEXT_MAIN, false);
      CreateButton("Btn_Risk_Inc", offset_x + 214, cur_y, 20, 18, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
      cur_y += 23;
   }
   
   // 5. Linha de Lote Operacional
   if(InpShowLotSection)
   {
      bool is_auto_risk = (m_risk_mode != RISK_MODE_MANUAL);
      int dec = GetLotDecimals(m_symbol);
      CreateLabel("Lbl_Lot", offset_x + 20, cur_y + 3, "Lote Operacional", COLOR_TEXT_MAIN, 8, false);
      CreateButton("Btn_Lot_Dec", offset_x + 128, cur_y, 20, 18, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
      CreateEdit("Edit_Lot", offset_x + 151, cur_y, 60, 18, DoubleToString(m_manual_lot, dec), is_auto_risk ? COLOR_EDIT_RO_BG : COLOR_EDIT_BG, is_auto_risk ? clrYellow : COLOR_TEXT_MAIN, is_auto_risk);
      CreateButton("Btn_Lot_Inc", offset_x + 214, cur_y, 20, 18, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
      cur_y += 23;
   }
   
   // 6. Stop Loss (pts)
   if(InpShowSLSection)
   {
      CreateButton("Chk_SL", offset_x, cur_y + 1, 16, 16, m_sl_active ? "X" : "", m_sl_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 8, true);
      CreateLabel("Lbl_SL", offset_x + 20, cur_y + 3, "Stop Loss (pts)", COLOR_TEXT_MAIN, 8, false);
      CreateButton("Btn_SL_Dec", offset_x + 128, cur_y, 20, 18, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
      CreateEdit("Edit_SL", offset_x + 151, cur_y, 60, 18, IntegerToString(m_sl_points), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false);
      CreateButton("Btn_SL_Inc", offset_x + 214, cur_y, 20, 18, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
      cur_y += 23;
   }
   
   // 7. Take Profit (pts)
   if(InpShowTPSection)
   {
      CreateButton("Chk_TP", offset_x, cur_y + 1, 16, 16, m_tp_active ? "X" : "", m_tp_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 8, true);
      CreateLabel("Lbl_TP", offset_x + 20, cur_y + 3, "Take Profit (pts)", COLOR_TEXT_MAIN, 8, false);
      CreateButton("Btn_TP_Dec", offset_x + 128, cur_y, 20, 18, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
      CreateEdit("Edit_TP", offset_x + 151, cur_y, 60, 18, IntegerToString(m_tp_points), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false);
      CreateButton("Btn_TP_Inc", offset_x + 214, cur_y, 20, 18, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
      cur_y += 23;
   }
   
   // 8. Seção de Parciais (Oculta por padrão conforme imagem)
   if(InpShowParcialSection)
   {
      CreateButton("Chk_Parcial", offset_x, cur_y + 1, 16, 16, m_parcial_active ? "X" : "", m_parcial_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 8, true);
      CreateLabel("Lbl_Parcial", offset_x + 20, cur_y + 3, "Alvo Parcial", COLOR_TEXT_MUTED, 8, false);
      string parcial_toggle_text = m_parcial_is_cash ? "$" : "Pts";
      color parcial_toggle_bg = m_parcial_is_cash ? COLOR_TOGGLE_CASH : COLOR_TOGGLE_PCT;
      CreateButton("Btn_Parcial_Toggle", offset_x + 92, cur_y, 30, 18, parcial_toggle_text, parcial_toggle_bg, COLOR_TEXT_MAIN, 8, true);
      
      CreateButton("Btn_Parcial_Dec", offset_x + 128, cur_y, 20, 18, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
      string init_parcial_target = m_parcial_is_cash ? DoubleToString(m_parcial_target_cash, 2) : IntegerToString(m_parcial_target_pts);
      CreateEdit("Edit_Parcial_Target", offset_x + 151, cur_y, 60, 18, init_parcial_target, COLOR_EDIT_BG, COLOR_TEXT_MAIN, false);
      CreateButton("Btn_Parcial_Inc", offset_x + 214, cur_y, 20, 18, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
      cur_y += 23;
      
      CreateLabel("Lbl_Parcial_Vol", offset_x + 20, cur_y + 3, "Vol. Parcial (%)", COLOR_TEXT_MUTED, 8, false);
      CreateButton("Btn_Parcial_Vol_Dec", offset_x + 128, cur_y, 20, 18, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
      CreateEdit("Edit_Parcial_Vol", offset_x + 151, cur_y, 60, 18, StringFormat("%.0f%%", m_parcial_vol_pct), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false);
      CreateButton("Btn_Parcial_Vol_Inc", offset_x + 214, cur_y, 20, 18, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
      cur_y += 22;
      
      CreateButton("Chk_Parcial_BE", offset_x, cur_y + 1, 16, 16, m_parcial_move_be ? "X" : "", m_parcial_move_be ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 8, true);
      CreateLabel("Lbl_Parcial_BE", offset_x + 20, cur_y + 3, "Mover SL p/ Zero a Zero pós Parcial", COLOR_TEXT_MUTED, 7, false);
      cur_y += 22;
   }
   
   // 9. Break Even (pts) - Padrão 60
   if(InpShowBESection)
   {
      CreateButton("Chk_BE", offset_x, cur_y + 1, 16, 16, m_be_active ? "X" : "", m_be_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 8, true);
      CreateLabel("Lbl_BE", offset_x + 20, cur_y + 3, "Break Even (pts)", COLOR_TEXT_MAIN, 8, false);
      CreateButton("Btn_BE_Dec", offset_x + 128, cur_y, 20, 18, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
      CreateEdit("Edit_BE", offset_x + 151, cur_y, 60, 18, IntegerToString(m_be_points), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false);
      CreateButton("Btn_BE_Inc", offset_x + 214, cur_y, 20, 18, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
      cur_y += 23;
   }
   
   // 10. Trailing Stop (pts) - Padrão 150
   if(InpShowTSSection)
   {
      CreateButton("Chk_TS", offset_x, cur_y + 1, 16, 16, m_ts_active ? "X" : "", m_ts_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 8, true);
      CreateLabel("Lbl_TS", offset_x + 20, cur_y + 3, "Trailing Stop (pts)", COLOR_TEXT_MAIN, 8, false);
      CreateButton("Btn_TS_Dec", offset_x + 128, cur_y, 20, 18, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
      CreateEdit("Edit_TS", offset_x + 151, cur_y, 60, 18, IntegerToString(m_ts_points), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false);
      CreateButton("Btn_TS_Inc", offset_x + 214, cur_y, 20, 18, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
      cur_y += 24;
   }
   
   // 11. Gaveta de Canais Integrada (Suporte a 40 Linhas e Auto D1)
   if(InpEnableChannels)
   {
      string drawer_txt = m_channels_expanded ? "CANAIS DE FREQUÊNCIA (40x40)  [-]" : "CANAIS DE FREQUÊNCIA (40x40)  [+]";
      CreateButton("Btn_Channels_Toggle", offset_x, cur_y, row_w, 22, drawer_txt, COLOR_DRAWER_BTN, clrGold, 8, true);
      cur_y += 24;
      
      if(m_channels_expanded)
      {
         CreateRectangleLabel("Chan_Drawer_BG", offset_x, cur_y, row_w, 118, COLOR_SECTION_BG, COLOR_BORDER, ZORDER_PANEL_STRIP);
         
         // Linha 1: Marcação Manual
         CreateButton("Btn_Chan_Start", offset_x + 5, cur_y + 4, 108, 22, "1. Marcar Manual", COLOR_CHAN_START, clrWhite, 8, true);
         CreateButton("Btn_Chan_Project", offset_x + 119, cur_y + 4, 108, 22, "2. Projetar", COLOR_CHAN_PROJ, clrWhite, 8, true);
         
         // Linha 2: Botão MARCAÇÃO AUTOMÁTICA D1 e Campo de Ajuste de Pontos
         int y_sub = cur_y + 28;
         string day_txt = (m_auto_day == AUTO_DAY_CURRENT) ? "Hoje" : "Ontem";
         color day_bg   = (m_auto_day == AUTO_DAY_CURRENT) ? COLOR_CHAN_DAY_TODAY : COLOR_CHAN_DAY_YEST;
         CreateButton("Btn_Chan_Day", offset_x + 5, y_sub, 44, 22, day_txt, day_bg, clrWhite, 8, true);
         CreateEdit("Edit_Chan_Pts", offset_x + 52, y_sub, 42, 22, IntegerToString(m_channel_pts), COLOR_EDIT_BG, clrWhite, false);
         CreateLabel("Lbl_Chan_Pts", offset_x + 96, y_sub + 4, "pts", clrSilver, 7, false);
         CreateButton("Btn_Chan_Auto", offset_x + 119, y_sub, 108, 22, "Marcar Auto", COLOR_CHAN_AUTO, clrYellow, 8, true);
         
         // Linha 3: Steppers Cima (40) e Baixo (40)
         y_sub += 24;
         CreateLabel("Lbl_Chan_Up", offset_x + 6, y_sub + 2, "Cima:", clrWhite, 7, true);
         CreateButton("Btn_Chan_Up_Dec", offset_x + 36, y_sub, 18, 18, "-", COLOR_STEP_BTN, clrWhite, 7, true);
         CreateEdit("Edit_Chan_Up", offset_x + 56, y_sub, 34, 18, IntegerToString(m_proj_up), COLOR_EDIT_BG, clrWhite, false);
         CreateButton("Btn_Chan_Up_Inc", offset_x + 92, y_sub, 18, 18, "+", COLOR_STEP_BTN, clrWhite, 7, true);
         
         CreateLabel("Lbl_Chan_Dn", offset_x + 118, y_sub + 2, "Baixo:", clrWhite, 7, true);
         CreateButton("Btn_Chan_Dn_Dec", offset_x + 148, y_sub, 18, 18, "-", COLOR_STEP_BTN, clrWhite, 7, true);
         CreateEdit("Edit_Chan_Dn", offset_x + 168, y_sub, 34, 18, IntegerToString(m_proj_down), COLOR_EDIT_BG, clrWhite, false);
         CreateButton("Btn_Chan_Dn_Inc", offset_x + 204, y_sub, 18, 18, "+", COLOR_STEP_BTN, clrWhite, 7, true);
         
         // Linha 4: Ocultar/Mostrar e Limpar
         y_sub += 21;
         CreateButton("Btn_Chan_HideShow", offset_x + 5, y_sub, 108, 20, m_chan_visible ? "Ocultar Linhas" : "Mostrar Linhas", C'45,48,60', clrWhite, 7, true);
         CreateButton("Btn_Chan_Clear", offset_x + 119, y_sub, 108, 20, "Limpar Canais", COLOR_CLOSE_LSS_BTN, clrWhite, 7, true);
         
         // Linha 5: Status
         y_sub += 21;
         CreateLabel("Lbl_Chan_Status", offset_x + 8, y_sub, "Status: Pronto (40 canais)", clrLimeGreen, 7, true);
         
         cur_y += 122;
      }
   }
   
   // 12. Botões Operacionais
   cur_y += 4;
   int half_btn_w = (row_w - 6) / 2;
   CreateButton("Btn_Buy", offset_x, cur_y, half_btn_w, 30, "COMPRAR", COLOR_BUY_BTN, COLOR_TEXT_MAIN, 9, true);
   CreateButton("Btn_Sell", offset_x + half_btn_w + 6, cur_y, half_btn_w, 30, "VENDER", COLOR_SELL_BTN, COLOR_TEXT_MAIN, 9, true);
   cur_y += 34;
   
   if(InpShowInvertHedge)
   {
      CreateButton("Btn_Invert", offset_x, cur_y, half_btn_w, 24, "INVERTER", COLOR_INVERT_BTN, COLOR_TEXT_MAIN, 8, true);
      CreateButton("Btn_Hedge", offset_x + half_btn_w + 6, cur_y, half_btn_w, 24, "HEDGE [H]", COLOR_HEDGE_BTN, COLOR_TEXT_MAIN, 8, true);
      cur_y += 28;
   }
   
   CreateButton("Btn_CloseAll", offset_x, cur_y, row_w, 26, "ZERAR TUDO", COLOR_CLOSE_ALL_BTN, clrBlack, 8, true);
   cur_y += 29;
   
   if(InpShowSelectiveClose)
   {
      CreateButton("Btn_CloseProfit", offset_x, cur_y, half_btn_w, 22, "Zerar Lucro", COLOR_CLOSE_PRF_BTN, COLOR_TEXT_MAIN, 8, true);
      CreateButton("Btn_CloseLoss", offset_x + half_btn_w + 6, cur_y, half_btn_w, 22, "Zerar Prej.", COLOR_CLOSE_LSS_BTN, COLOR_TEXT_MAIN, 8, true);
      cur_y += 25;
   }
   
   if(InpShowCancelPendings)
   {
      CreateButton("Btn_CancelPendings", offset_x, cur_y, row_w, 22, "CANCELAR ORDENS [C]", COLOR_CANCEL_BTN, COLOR_TEXT_MAIN, 8, true);
      cur_y += 25;
   }
   
   if(InpShowGhostOrder)
   {
      string ghost_txt = "FANTASMA: [Up/Dn]";
      color ghost_bg   = C'35,38,48';
      if(m_ghost_placing)
      {
         ghost_txt = (m_ghost_type == GHOST_BUY) ? "[MIRA COMPRA] Clique Direito Fixa" : "[MIRA VENDA] Clique Direito Fixa";
         ghost_bg  = (m_ghost_type == GHOST_BUY) ? C'16,130,85' : C'180,35,45';
      }
      else if(HasGhostOrder())
      {
         ghost_txt = "[ENTER] Enviar Fantasma";
         ghost_bg  = COLOR_GHOST_CONFIRM;
      }
      CreateButton("Btn_GhostConfirm", offset_x, cur_y, row_w, 22, ghost_txt, ghost_bg, COLOR_TEXT_MAIN, 8, true);
      cur_y += 25;
   }
   
   m_height = cur_y - m_y + 4;
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Panel_BG", OBJPROP_YSIZE, m_height);
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::ToggleChannelsDrawer()
{
   m_channels_expanded = !m_channels_expanded;
   Render();
   UpdateFieldValues();
   UpdateLiveMetrics();
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::CalculateHistoricalStats()
{
   m_history_profit = 0.0;
   m_history_loss   = 0.0;
   m_history_net    = 0.0;
   m_floating_pnl   = 0.0;
   
   datetime start_time = 0;
   datetime cur_time   = TimeCurrent();
   
   switch(m_hud_period)
   {
      case HUD_PERIOD_TODAY:
      {
         MqlDateTime dt;
         TimeToStruct(cur_time, dt);
         dt.hour = 0;
         dt.min  = 0;
         dt.sec  = 0;
         start_time = StructToTime(dt);
         break;
      }
      case HUD_PERIOD_WEEK:
         start_time = cur_time - (7 * 86400);
         break;
      case HUD_PERIOD_MONTH:
         start_time = cur_time - (30 * 86400);
         break;
      case HUD_PERIOD_ALL:
      case HUD_PERIOD_WALLET:
         start_time = 0;
         break;
   }
   
   if(HistorySelect(start_time, cur_time))
   {
      int total_deals = HistoryDealsTotal();
      for(int i = 0; i < total_deals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket <= 0) continue;
         
         if(InpFilterSymbolOnly)
         {
            string deal_sym = HistoryDealGetString(ticket, DEAL_SYMBOL);
            if(deal_sym != m_symbol && m_symbol != "") continue;
         }
         
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) continue;
         
         double pnl  = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         double comm = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
         double total_deal = pnl + comm + swap;
         
         if(total_deal >= 0.0)
            m_history_profit += total_deal;
         else
            m_history_loss += total_deal;
         
         m_history_net += total_deal;
      }
   }
   
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i))
      {
         if(!InpFilterSymbolOnly || pos.Symbol() == m_symbol || m_symbol == "")
         {
            m_floating_pnl += pos.Profit() + pos.Commission() + pos.Swap();
         }
      }
   }
}

void CBoletaMaster::UpdateLiveMetrics()
{
   if(m_is_minimized) return;
   
   if(InpShowMarketStrip)
   {
      long spread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      string tf_name = GetPeriodName(_Period);
      string timer_str = GetCandleTimerString(m_symbol, _Period);
      
      ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Mkt_Symbol", OBJPROP_TEXT, m_symbol);
      if(InpShowSpread)
         ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Mkt_Spread", OBJPROP_TEXT, StringFormat("Sp: %d", spread));
      if(InpShowCandleTimer)
         ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Mkt_Timer",  OBJPROP_TEXT, StringFormat("[%s] %s", tf_name, timer_str));
   }
   
   if(InpShowHudStrip)
   {
      CalculateHistoricalStats();
      string period_btn_text = "Hoje";
      switch(m_hud_period)
      {
         case HUD_PERIOD_TODAY:  period_btn_text = "Hoje"; break;
         case HUD_PERIOD_WEEK:   period_btn_text = "7D";   break;
         case HUD_PERIOD_MONTH:  period_btn_text = "30D";  break;
         case HUD_PERIOD_ALL:    period_btn_text = "Tudo"; break;
         case HUD_PERIOD_WALLET: period_btn_text = "Saldo"; break;
      }
      ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_Hud_Period", OBJPROP_TEXT, period_btn_text);
      
      if(m_hud_period == HUD_PERIOD_WALLET)
      {
         double bal = AccountInfoDouble(ACCOUNT_BALANCE);
         double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
         ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Hud_P1", OBJPROP_TEXT, StringFormat("Sal: $%.0f", bal));
         ObjectSetInteger(m_chart_id, PREFIX_GUI + "Lbl_Hud_P1", OBJPROP_COLOR, clrWhite);
         ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Hud_P2", OBJPROP_TEXT, StringFormat("Eq: $%.0f", eq));
         ObjectSetInteger(m_chart_id, PREFIX_GUI + "Lbl_Hud_P2", OBJPROP_COLOR, (eq >= bal) ? COLOR_PROFIT_GREEN : COLOR_LOSS_RED);
         ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Hud_P3", OBJPROP_TEXT, StringFormat("Flut: %s$%.1f", (m_floating_pnl>=0)?"+":"-", MathAbs(m_floating_pnl)));
         ObjectSetInteger(m_chart_id, PREFIX_GUI + "Lbl_Hud_P3", OBJPROP_COLOR, (m_floating_pnl >= 0) ? COLOR_PROFIT_GREEN : COLOR_LOSS_RED);
      }
      else
      {
         ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Hud_P1", OBJPROP_TEXT, StringFormat("+$%.1f", m_history_profit));
         ObjectSetInteger(m_chart_id, PREFIX_GUI + "Lbl_Hud_P1", OBJPROP_COLOR, COLOR_PROFIT_GREEN);
         ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Hud_P2", OBJPROP_TEXT, StringFormat("-$%.1f", MathAbs(m_history_loss)));
         ObjectSetInteger(m_chart_id, PREFIX_GUI + "Lbl_Hud_P2", OBJPROP_COLOR, COLOR_LOSS_RED);
         string net_text = StringFormat("Líq: %s$%.1f", (m_history_net >= 0) ? "+" : "-", MathAbs(m_history_net));
         ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Hud_P3", OBJPROP_TEXT, net_text);
         ObjectSetInteger(m_chart_id, PREFIX_GUI + "Lbl_Hud_P3", OBJPROP_COLOR, (m_history_net >= 0) ? COLOR_PROFIT_GREEN : COLOR_LOSS_RED);
      }
   }
   
   if(MathAbs(m_floating_pnl) > 0.001)
   {
      string close_text = StringFormat("ZERAR TUDO (%s$%.2f)", (m_floating_pnl >= 0) ? "+" : "-", MathAbs(m_floating_pnl));
      ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_CloseAll", OBJPROP_TEXT, close_text);
   }
   else
   {
      ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_CloseAll", OBJPROP_TEXT, "ZERAR TUDO");
   }
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::CycleHudPeriod()
{
   if(m_hud_period == HUD_PERIOD_TODAY)       m_hud_period = HUD_PERIOD_WEEK;
   else if(m_hud_period == HUD_PERIOD_WEEK)   m_hud_period = HUD_PERIOD_MONTH;
   else if(m_hud_period == HUD_PERIOD_MONTH)  m_hud_period = HUD_PERIOD_ALL;
   else if(m_hud_period == HUD_PERIOD_ALL)    m_hud_period = HUD_PERIOD_WALLET;
   else                                       m_hud_period = HUD_PERIOD_TODAY;
   UpdateLiveMetrics();
}

void CBoletaMaster::UpdateFieldValues()
{
   if(m_is_minimized) return;
   int dec = GetLotDecimals(m_symbol);
   
   if(InpShowRiskSection)
   {
      if(m_risk_mode == RISK_MODE_PERCENT)
      {
         ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Risk", OBJPROP_TEXT, DoubleToString(m_risk_percent, 1));
         ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_Risk_Toggle", OBJPROP_TEXT, "Risco: %");
         ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_Risk_Toggle", OBJPROP_BGCOLOR, COLOR_TOGGLE_PCT);
      }
      else if(m_risk_mode == RISK_MODE_CASH)
      {
         ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Risk", OBJPROP_TEXT, DoubleToString(m_risk_cash, 2));
         ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_Risk_Toggle", OBJPROP_TEXT, "Risco: $");
         ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_Risk_Toggle", OBJPROP_BGCOLOR, COLOR_TOGGLE_CASH);
      }
      else
      {
         ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Risk", OBJPROP_TEXT, "--");
         ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_Risk_Toggle", OBJPROP_TEXT, "Risco: Man");
         ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_Risk_Toggle", OBJPROP_BGCOLOR, COLOR_EDIT_BG);
      }
      bool is_auto_risk = (m_risk_mode != RISK_MODE_MANUAL);
      ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_Risk", OBJPROP_TEXT, is_auto_risk ? "X" : "");
      ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_Risk", OBJPROP_BGCOLOR, is_auto_risk ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   }
   
   if(InpShowLotSection)
   {
      bool is_auto_risk = (m_risk_mode != RISK_MODE_MANUAL);
      ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Lot", OBJPROP_TEXT, DoubleToString(m_manual_lot, dec));
      ObjectSetInteger(m_chart_id, PREFIX_GUI + "Edit_Lot", OBJPROP_READONLY, is_auto_risk);
      ObjectSetInteger(m_chart_id, PREFIX_GUI + "Edit_Lot", OBJPROP_BGCOLOR, is_auto_risk ? COLOR_EDIT_RO_BG : COLOR_EDIT_BG);
      ObjectSetInteger(m_chart_id, PREFIX_GUI + "Edit_Lot", OBJPROP_COLOR, is_auto_risk ? clrYellow : COLOR_TEXT_MAIN);
   }
   
   if(InpShowSLSection)
   {
      ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_SL", OBJPROP_TEXT, IntegerToString(m_sl_points));
      ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_SL", OBJPROP_TEXT, m_sl_active ? "X" : "");
      ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_SL", OBJPROP_BGCOLOR, m_sl_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   }
   
   if(InpShowTPSection)
   {
      ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_TP", OBJPROP_TEXT, IntegerToString(m_tp_points));
      ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_TP", OBJPROP_TEXT, m_tp_active ? "X" : "");
      ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_TP", OBJPROP_BGCOLOR, m_tp_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   }
   
   if(InpShowParcialSection)
   {
      ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_Parcial", OBJPROP_TEXT, m_parcial_active ? "X" : "");
      ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_Parcial", OBJPROP_BGCOLOR, m_parcial_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
      if(m_parcial_is_cash)
      {
         ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Parcial_Target", OBJPROP_TEXT, DoubleToString(m_parcial_target_cash, 2));
         ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_Parcial_Toggle", OBJPROP_TEXT, "$");
         ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_Parcial_Toggle", OBJPROP_BGCOLOR, COLOR_TOGGLE_CASH);
      }
      else
      {
         ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Parcial_Target", OBJPROP_TEXT, IntegerToString(m_parcial_target_pts));
         ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_Parcial_Toggle", OBJPROP_TEXT, "Pts");
         ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_Parcial_Toggle", OBJPROP_BGCOLOR, COLOR_TOGGLE_PCT);
      }
      ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Parcial_Vol", OBJPROP_TEXT, StringFormat("%.0f%%", m_parcial_vol_pct));
      ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_Parcial_BE", OBJPROP_TEXT, m_parcial_move_be ? "X" : "");
      ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_Parcial_BE", OBJPROP_BGCOLOR, m_parcial_move_be ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   }
   
   if(InpShowBESection)
   {
      ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_BE", OBJPROP_TEXT, IntegerToString(m_be_points));
      ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_BE", OBJPROP_TEXT, m_be_active ? "X" : "");
      ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_BE", OBJPROP_BGCOLOR, m_be_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   }
   
   if(InpShowTSSection)
   {
      ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_TS", OBJPROP_TEXT, IntegerToString(m_ts_points));
      ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_TS", OBJPROP_TEXT, m_ts_active ? "X" : "");
      ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_TS", OBJPROP_BGCOLOR, m_ts_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   }
   
   if(InpEnableChannels && m_channels_expanded)
   {
      ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Chan_Up", OBJPROP_TEXT, IntegerToString(m_proj_up));
      ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Chan_Dn", OBJPROP_TEXT, IntegerToString(m_proj_down));
      ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Chan_Pts", OBJPROP_TEXT, IntegerToString(m_channel_pts));
      ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_Chan_Day", OBJPROP_TEXT, (m_auto_day == AUTO_DAY_CURRENT) ? "Hoje" : "Ontem");
      ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_Chan_Day", OBJPROP_BGCOLOR, (m_auto_day == AUTO_DAY_CURRENT) ? COLOR_CHAN_DAY_TODAY : COLOR_CHAN_DAY_YEST);
      ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_Chan_HideShow", OBJPROP_TEXT, m_chan_visible ? "Ocultar Linhas" : "Mostrar Linhas");
   }
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::MovePanel(int new_x, int new_y)
{
   int dx = new_x - m_x;
   int dy = new_y - m_y;
   m_x = new_x;
   m_y = new_y;
   
   int total = ObjectsTotal(m_chart_id, 0);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(m_chart_id, i, 0);
      if(StringFind(name, PREFIX_GUI) == 0)
      {
         int obj_x = (int)ObjectGetInteger(m_chart_id, name, OBJPROP_XDISTANCE);
         int obj_y = (int)ObjectGetInteger(m_chart_id, name, OBJPROP_YDISTANCE);
         ObjectSetInteger(m_chart_id, name, OBJPROP_XDISTANCE, obj_x + dx);
         ObjectSetInteger(m_chart_id, name, OBJPROP_YDISTANCE, obj_y + dy);
      }
   }
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::ToggleMinimize()
{
   m_is_minimized = !m_is_minimized;
   Render();
   UpdateFieldValues();
   UpdateLiveMetrics();
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::ToggleRiskAuto()
{
   if(m_risk_mode == RISK_MODE_MANUAL)
   {
      m_risk_mode = RISK_MODE_CASH;
      RecalculateRiskLot();
   }
   else
   {
      m_risk_mode = RISK_MODE_MANUAL;
   }
   UpdateFieldValues();
}

void CBoletaMaster::ToggleRiskMode()
{
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin <= 0.0) freeMargin = AccountInfoDouble(ACCOUNT_BALANCE);
   
   if(m_risk_mode == RISK_MODE_PERCENT)
   {
      m_risk_mode = RISK_MODE_CASH;
      if(freeMargin > 0.0 && m_risk_cash <= 0.0)
         m_risk_cash = freeMargin * (m_risk_percent / 100.0);
   }
   else if(m_risk_mode == RISK_MODE_CASH)
   {
      m_risk_mode = RISK_MODE_PERCENT;
      if(freeMargin > 0.0 && m_risk_percent <= 0.0)
         m_risk_percent = (m_risk_cash / freeMargin) * 100.0;
   }
   else
   {
      m_risk_mode = RISK_MODE_CASH;
   }
   RecalculateRiskLot();
   UpdateFieldValues();
}

void CBoletaMaster::ToggleSL()          { m_sl_active = !m_sl_active; if(m_sl_active && m_risk_mode != RISK_MODE_MANUAL) RecalculateRiskLot(); UpdateFieldValues(); }
void CBoletaMaster::ToggleTP()          { m_tp_active = !m_tp_active; UpdateFieldValues(); }
void CBoletaMaster::ToggleBE()          { m_be_active = !m_be_active; UpdateFieldValues(); }
void CBoletaMaster::ToggleTS()          { m_ts_active = !m_ts_active; UpdateFieldValues(); }
void CBoletaMaster::ToggleParcial()     { m_parcial_active = !m_parcial_active; UpdateFieldValues(); }
void CBoletaMaster::ToggleParcialMode() { m_parcial_is_cash = !m_parcial_is_cash; UpdateFieldValues(); }
void CBoletaMaster::ToggleParcialBE()   { m_parcial_move_be = !m_parcial_move_be; UpdateFieldValues(); }

void CBoletaMaster::AdjustRisk(double delta)
{
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin <= 0.0) freeMargin = AccountInfoDouble(ACCOUNT_BALANCE);
   
   if(m_risk_mode == RISK_MODE_PERCENT)
   {
      m_risk_percent += delta;
      if(m_risk_percent < 0.1)  m_risk_percent = 0.1;
      if(m_risk_percent > 50.0) m_risk_percent = 50.0;
      if(freeMargin > 0.0)
         m_risk_cash = freeMargin * (m_risk_percent / 100.0);
   }
   else
   {
      m_risk_mode = RISK_MODE_CASH;
      m_risk_cash += delta;
      if(m_risk_cash < 0.01) m_risk_cash = 0.01;
      if(freeMargin > 0.0)
         m_risk_percent = (m_risk_cash / freeMargin) * 100.0;
   }
   RecalculateRiskLot();
   UpdateFieldValues();
}

void CBoletaMaster::AdjustLot(double delta)
{
   m_risk_mode = RISK_MODE_MANUAL;
   m_manual_lot = NormalizeLot(m_manual_lot + delta, m_symbol);
   UpdateFieldValues();
}

void CBoletaMaster::AdjustSL(int delta)
{
   m_sl_points += delta;
   if(m_sl_points < 10) m_sl_points = 10;
   if(m_risk_mode != RISK_MODE_MANUAL) RecalculateRiskLot();
   UpdateFieldValues();
}

void CBoletaMaster::AdjustTP(int delta)
{
   m_tp_points += delta;
   if(m_tp_points < 0) m_tp_points = 0;
   UpdateFieldValues();
}

void CBoletaMaster::AdjustBE(int delta)
{
   m_be_points += delta;
   if(m_be_points < 0) m_be_points = 0;
   UpdateFieldValues();
}

void CBoletaMaster::AdjustTS(int delta)
{
   m_ts_points += delta;
   if(m_ts_points < 0) m_ts_points = 0;
   UpdateFieldValues();
}

void CBoletaMaster::AdjustParcialTarget(double delta)
{
   if(m_parcial_is_cash)
   {
      m_parcial_target_cash += delta;
      if(m_parcial_target_cash < 1.0) m_parcial_target_cash = 1.0;
   }
   else
   {
      m_parcial_target_pts += (int)delta;
      if(m_parcial_target_pts < 10) m_parcial_target_pts = 10;
   }
   UpdateFieldValues();
}

void CBoletaMaster::AdjustParcialVol(double delta)
{
   m_parcial_vol_pct += delta;
   if(m_parcial_vol_pct < 5.0)  m_parcial_vol_pct = 5.0;
   if(m_parcial_vol_pct > 95.0) m_parcial_vol_pct = 95.0;
   UpdateFieldValues();
}

void CBoletaMaster::AdjustChanUp(int delta)
{
   m_proj_up += delta;
   if(m_proj_up < 0) m_proj_up = 0;
   if(m_proj_up > 100) m_proj_up = 100;
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Chan_Up", OBJPROP_TEXT, IntegerToString(m_proj_up));
   if(m_has_projections) ProjetarCanais();
}

void CBoletaMaster::AdjustChanDown(int delta)
{
   m_proj_down += delta;
   if(m_proj_down < 0) m_proj_down = 0;
   if(m_proj_down > 100) m_proj_down = 100;
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Chan_Dn", OBJPROP_TEXT, IntegerToString(m_proj_down));
   if(m_has_projections) ProjetarCanais();
}

void CBoletaMaster::ToggleAutoDay()
{
   m_auto_day = (m_auto_day == AUTO_DAY_CURRENT) ? AUTO_DAY_PREVIOUS : AUTO_DAY_CURRENT;
   string day_txt = (m_auto_day == AUTO_DAY_CURRENT) ? "Hoje" : "Ontem";
   color day_bg   = (m_auto_day == AUTO_DAY_CURRENT) ? COLOR_CHAN_DAY_TODAY : COLOR_CHAN_DAY_YEST;
   ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_Chan_Day", OBJPROP_TEXT, day_txt);
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_Chan_Day", OBJPROP_BGCOLOR, day_bg);
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::RecalculateRiskLot()
{
   if(m_risk_mode == RISK_MODE_MANUAL || !m_sl_active || m_sl_points <= 0)
      return;
   
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin <= 0.0) freeMargin = AccountInfoDouble(ACCOUNT_BALANCE);
   
   double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   
   if(tickValue <= 0.0) tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0.0) tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);
   
   if(tickSize > 0.0 && point > 0.0)
   {
      double ptsPerTick = tickSize / point;
      if(ptsPerTick > 0.0)
         tickValue = tickValue / ptsPerTick;
   }
   if(tickValue <= 0.0) tickValue = 1.0;
   
   double calculated_lot = 0.0;
   double denominator = m_sl_points * tickValue;
   
   if(denominator > 0.0)
   {
      if(m_risk_mode == RISK_MODE_PERCENT)
         calculated_lot = (freeMargin * (m_risk_percent / 100.0)) / denominator;
      else if(m_risk_mode == RISK_MODE_CASH)
         calculated_lot = m_risk_cash / denominator;
   }
   
   m_manual_lot = NormalizeLot(calculated_lot, m_symbol);
   int dec = GetLotDecimals(m_symbol);
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Lot", OBJPROP_TEXT, DoubleToString(m_manual_lot, dec));
   ChartRedraw(m_chart_id);
}

double CBoletaMaster::GetEffectiveLot()
{
   return NormalizeLot(m_manual_lot, m_symbol);
}

//+------------------------------------------------------------------+
//| Módulo de Canais - Funções Internas                              |
//+------------------------------------------------------------------+
void CBoletaMaster::StartChannelMarking()
{
   ObjectDelete(m_chart_id, m_temp_line1);
   ObjectDelete(m_chart_id, m_temp_line2);
   m_chan_step = 1;
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_TEXT, "Status: Clique Linha 1");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_COLOR, clrRed);
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::CriarLinhaTemporaria(const string nome, double price)
{
   ObjectCreate(m_chart_id, nome, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(m_chart_id, nome, OBJPROP_COLOR, clrMagenta);
   ObjectSetInteger(m_chart_id, nome, OBJPROP_WIDTH, 2);
   ObjectSetInteger(m_chart_id, nome, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(m_chart_id, nome, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(m_chart_id, nome, OBJPROP_SELECTED, true);
   ObjectSetInteger(m_chart_id, nome, OBJPROP_BACK, false);
   ObjectSetInteger(m_chart_id, nome, OBJPROP_ZORDER, 100);
   ObjectSetInteger(m_chart_id, nome, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

void CBoletaMaster::DesenharHLine(const string name, double price, color clr, int style, int width=0, const string desc="")
{
   ObjectCreate(m_chart_id, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(m_chart_id, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(m_chart_id, name, OBJPROP_STYLE, style);
   int w = (width > 0) ? width : ((style == STYLE_SOLID) ? 2 : 1);
   ObjectSetInteger(m_chart_id, name, OBJPROP_WIDTH, w);
   ObjectSetInteger(m_chart_id, name, OBJPROP_BACK, true);
   ObjectSetInteger(m_chart_id, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(m_chart_id, name, OBJPROP_ZORDER, 0);
   ObjectSetInteger(m_chart_id, name, OBJPROP_TIMEFRAMES, m_chan_visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   if(desc != "")
      ObjectSetString(m_chart_id, name, OBJPROP_TEXT, desc);
}

void CBoletaMaster::DesenharMarcadoresReferencia(datetime bar_time, double top_body, double bottom_body, const string day_name, double top_pavio_pts, double btm_pavio_pts)
{
   if(!InpShowChannelRefMarkers) return;
   
   // 1. Caixa de Enquadramento do Dia / Corpo do Candle D1 (Reference Box)
   string box_name = PREFIX_CANAL_LINES + "Ref_Box";
   ObjectCreate(m_chart_id, box_name, OBJ_RECTANGLE, 0, bar_time, top_body, bar_time + 86400, bottom_body);
   ObjectSetInteger(m_chart_id, box_name, OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(m_chart_id, box_name, OBJPROP_STYLE, STYLE_DASHDOT);
   ObjectSetInteger(m_chart_id, box_name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(m_chart_id, box_name, OBJPROP_BACK, true);
   ObjectSetInteger(m_chart_id, box_name, OBJPROP_FILL, false);
   ObjectSetInteger(m_chart_id, box_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(m_chart_id, box_name, OBJPROP_TIMEFRAMES, m_chan_visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   
   // 2. Marcador Pontual no Topo do Corpo (Seta para Baixo apontando no Topo)
   string top_arrow = PREFIX_CANAL_LINES + "Ref_Top_Arrow";
   ObjectCreate(m_chart_id, top_arrow, OBJ_ARROW, 0, bar_time, top_body);
   ObjectSetInteger(m_chart_id, top_arrow, OBJPROP_ARROWCODE, 234); // Seta Wingdings para baixo
   ObjectSetInteger(m_chart_id, top_arrow, OBJPROP_COLOR, InpColorRefMarkers);
   ObjectSetInteger(m_chart_id, top_arrow, OBJPROP_WIDTH, 4);
   ObjectSetInteger(m_chart_id, top_arrow, OBJPROP_BACK, false);
   ObjectSetInteger(m_chart_id, top_arrow, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
   ObjectSetInteger(m_chart_id, top_arrow, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(m_chart_id, top_arrow, OBJPROP_TIMEFRAMES, m_chan_visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   
   // 3. Marcador Pontual no Fundo do Corpo (Seta para Cima apontando no Fundo)
   string btm_arrow = PREFIX_CANAL_LINES + "Ref_Btm_Arrow";
   ObjectCreate(m_chart_id, btm_arrow, OBJ_ARROW, 0, bar_time, bottom_body);
   ObjectSetInteger(m_chart_id, btm_arrow, OBJPROP_ARROWCODE, 233); // Seta Wingdings para cima
   ObjectSetInteger(m_chart_id, btm_arrow, OBJPROP_COLOR, InpColorRefMarkers);
   ObjectSetInteger(m_chart_id, btm_arrow, OBJPROP_WIDTH, 4);
   ObjectSetInteger(m_chart_id, btm_arrow, OBJPROP_BACK, false);
   ObjectSetInteger(m_chart_id, btm_arrow, OBJPROP_ANCHOR, ANCHOR_TOP);
   ObjectSetInteger(m_chart_id, btm_arrow, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(m_chart_id, btm_arrow, OBJPROP_TIMEFRAMES, m_chan_visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   
   // 4. Texto Descritivo no Topo Ancorado no Ponto Exato
   string top_txt = PREFIX_CANAL_LINES + "Ref_Top_Txt";
   ObjectCreate(m_chart_id, top_txt, OBJ_TEXT, 0, bar_time, top_body);
   string top_desc = StringFormat("  TOPO REF D1 (%s): %.*f [Pavio desc: %.0f pts]", day_name, _Digits, top_body, top_pavio_pts);
   ObjectSetString(m_chart_id, top_txt, OBJPROP_TEXT, top_desc);
   ObjectSetString(m_chart_id, top_txt, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(m_chart_id, top_txt, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(m_chart_id, top_txt, OBJPROP_COLOR, InpColorRefMarkers);
   ObjectSetInteger(m_chart_id, top_txt, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(m_chart_id, top_txt, OBJPROP_BACK, false);
   ObjectSetInteger(m_chart_id, top_txt, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(m_chart_id, top_txt, OBJPROP_TIMEFRAMES, m_chan_visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   
   // 5. Texto Descritivo no Fundo Ancorado no Ponto Exato
   string btm_txt = PREFIX_CANAL_LINES + "Ref_Btm_Txt";
   ObjectCreate(m_chart_id, btm_txt, OBJ_TEXT, 0, bar_time, bottom_body);
   string btm_desc = StringFormat("  FUNDO REF D1 (%s): %.*f [Pavio desc: %.0f pts]", day_name, _Digits, bottom_body, btm_pavio_pts);
   ObjectSetString(m_chart_id, btm_txt, OBJPROP_TEXT, btm_desc);
   ObjectSetString(m_chart_id, btm_txt, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(m_chart_id, btm_txt, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(m_chart_id, btm_txt, OBJPROP_COLOR, InpColorRefMarkers);
   ObjectSetInteger(m_chart_id, btm_txt, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(m_chart_id, btm_txt, OBJPROP_BACK, false);
   ObjectSetInteger(m_chart_id, btm_txt, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(m_chart_id, btm_txt, OBJPROP_TIMEFRAMES, m_chan_visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   
   // 6. Tags de Identificação das Linhas no Preço Atual (Borda direita da tela)
   datetime cur_t = TimeCurrent();
   string top_tag = PREFIX_CANAL_LINES + "Ref_Top_Tag";
   ObjectCreate(m_chart_id, top_tag, OBJ_TEXT, 0, cur_t, top_body);
   ObjectSetString(m_chart_id, top_tag, OBJPROP_TEXT, "  ◄ TOPO REF D1 (" + day_name + ")");
   ObjectSetString(m_chart_id, top_tag, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(m_chart_id, top_tag, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(m_chart_id, top_tag, OBJPROP_COLOR, InpColorRefMarkers);
   ObjectSetInteger(m_chart_id, top_tag, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(m_chart_id, top_tag, OBJPROP_BACK, false);
   ObjectSetInteger(m_chart_id, top_tag, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(m_chart_id, top_tag, OBJPROP_TIMEFRAMES, m_chan_visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   
   string btm_tag = PREFIX_CANAL_LINES + "Ref_Btm_Tag";
   ObjectCreate(m_chart_id, btm_tag, OBJ_TEXT, 0, cur_t, bottom_body);
   ObjectSetString(m_chart_id, btm_tag, OBJPROP_TEXT, "  ◄ FUNDO REF D1 (" + day_name + ")");
   ObjectSetString(m_chart_id, btm_tag, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(m_chart_id, btm_tag, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(m_chart_id, btm_tag, OBJPROP_COLOR, InpColorRefMarkers);
   ObjectSetInteger(m_chart_id, btm_tag, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(m_chart_id, btm_tag, OBJPROP_BACK, false);
   ObjectSetInteger(m_chart_id, btm_tag, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(m_chart_id, btm_tag, OBJPROP_TIMEFRAMES, m_chan_visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
}

void CBoletaMaster::ProjetarCanais()
{
   double price1 = 0.0, price2 = 0.0;
   
   if(ObjectFind(m_chart_id, m_temp_line1) >= 0 && ObjectFind(m_chart_id, m_temp_line2) >= 0)
   {
      price1 = ObjectGetDouble(m_chart_id, m_temp_line1, OBJPROP_PRICE);
      price2 = ObjectGetDouble(m_chart_id, m_temp_line2, OBJPROP_PRICE);
   }
   else if(m_has_projections)
   {
      string p = GetGVPrefix();
      price1 = GlobalVariableGet(p + "base_top");
      price2 = GlobalVariableGet(p + "base_bottom");
   }
   else
   {
      Alert("Posicione as duas linhas de referência antes de projetar!");
      return;
   }
   
   double topPrice = MathMax(price1, price2);
   double bottomPrice = MathMin(price1, price2);
   double amplitude = topPrice - bottomPrice;
   
   if(amplitude <= 0)
   {
      Alert("A amplitude entre as linhas de canal não pode ser zero!");
      return;
   }
   
   ObjectsDeleteAll(m_chart_id, PREFIX_CANAL_LINES);
   
   double midPrice = bottomPrice + (amplitude / 2.0);
   DesenharHLine(PREFIX_CANAL_LINES + "Top", topPrice, InpColorChannel, STYLE_SOLID);
   DesenharHLine(PREFIX_CANAL_LINES + "Bottom", bottomPrice, InpColorChannel, STYLE_SOLID);
   DesenharHLine(PREFIX_CANAL_LINES + "Mid", midPrice, InpColorChannelMid, STYLE_DASH);
   
   m_highest_proj = topPrice;
   m_lowest_proj  = bottomPrice;
   
   for(int i = 1; i <= m_proj_up; i++)
   {
      double pTop = topPrice + (i * amplitude);
      double pMid = pTop - (amplitude / 2.0);
      DesenharHLine(PREFIX_CANAL_LINES + "Up_" + IntegerToString(i), pTop, InpColorChannel, STYLE_SOLID);
      DesenharHLine(PREFIX_CANAL_LINES + "UpMid_" + IntegerToString(i), pMid, InpColorChannelMid, STYLE_DASH);
      m_highest_proj = pTop;
   }
   
   for(int i = 1; i <= m_proj_down; i++)
   {
      double pBottom = bottomPrice - (i * amplitude);
      double pMid = pBottom + (amplitude / 2.0);
      DesenharHLine(PREFIX_CANAL_LINES + "Down_" + IntegerToString(i), pBottom, InpColorChannel, STYLE_SOLID);
      DesenharHLine(PREFIX_CANAL_LINES + "DownMid_" + IntegerToString(i), pMid, InpColorChannelMid, STYLE_DASH);
      m_lowest_proj = pBottom;
   }
   
   SalvarEstadoCanais(topPrice, bottomPrice, amplitude);
   ObjectDelete(m_chart_id, m_temp_line1);
   ObjectDelete(m_chart_id, m_temp_line2);
   
   m_chan_step = 0;
   m_has_projections = true;
   m_chan_visible = true;
   m_alerted_high = false;
   m_alerted_low  = false;
   
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_TEXT, StringFormat("Projetado: %d Cima / %d Baixo", m_proj_up, m_proj_down));
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_COLOR, clrCyan);
   ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Projeção Automática Baseada no Topo e Fundo sem Pavio do Candle  |
//+------------------------------------------------------------------+
void CBoletaMaster::ProjetarCanaisAuto()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   // Determina o candle a ser analisado: 0 = Dia Atual (Hoje), 1 = Dia Anterior (Ontem/D-1)
   int bar_idx = (m_auto_day == AUTO_DAY_PREVIOUS) ? 1 : 0;
   int copied = CopyRates(m_symbol, PERIOD_D1, bar_idx, 1, rates);
   if(copied <= 0)
   {
      Alert(StringFormat("Não foi possível carregar os dados diários (D1) do %s para %s", 
            (m_auto_day == AUTO_DAY_PREVIOUS) ? "dia anterior (ontem)" : "dia atual (hoje)", m_symbol));
      return;
   }
   
   double open_p  = rates[0].open;
   double close_p = rates[0].close;
   double high_p  = rates[0].high;
   double low_p   = rates[0].low;
   
   // DESCARTANDO O PAVIL DO CANDLE:
   // Topo: maior preço entre Abertura e Fechamento (corpo do candle sem o pavio superior)
   // Fundo: menor preço entre Abertura e Fechamento (corpo do candle sem o pavio inferior)
   double top_body    = MathMax(open_p, close_p);
   double bottom_body = MathMin(open_p, close_p);
   
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0.0) point = 0.00001;
   
   // Medida alvo do canal configurada pelo usuário (Padrão 500 pontos, alterável a qualquer momento)
   double target_amp = (m_channel_pts > 0) ? (m_channel_pts * point) : (500.0 * point);
   if(target_amp <= 0.0) target_amp = 500.0 * point;
   
   double body_dist = top_body - bottom_body;
   if(body_dist <= 0.0)
   {
      body_dist = target_amp;
      bottom_body = top_body - target_amp;
   }
   
   ObjectsDeleteAll(m_chart_id, PREFIX_CANAL_LINES);
   
   double amplitude = target_amp;
   int num_body_channels = 1;
   double sobra = 0.0;
   
   if(m_fit_mode == FIT_MODE_DILUTE)
   {
      // 1. DILUIÇÃO DA SOBRA EM TODOS OS CANAIS (RECOMENDADO):
      // A distância do corpo do candle divide-se em N canais perfeitamente iguais.
      // O tamanho de cada canal ajusta-se suavemente para cima ou para baixo dos 500 pts.
      num_body_channels = (int)MathRound(body_dist / target_amp);
      if(num_body_channels < 1) num_body_channels = 1;
      amplitude = body_dist / (double)num_body_channels;
   }
   else // FIT_MODE_EXTREME
   {
      // 2. FIXO ESTRITO (500 PTS) E SOBRA COLOCADA NO 40º CANAL (EXTREMIDADE FINAL):
      amplitude = target_amp;
      num_body_channels = (int)MathFloor(body_dist / target_amp);
      if(num_body_channels < 1) num_body_channels = 1;
      sobra = body_dist - (num_body_channels * amplitude);
   }
   
   datetime bar_time = rates[0].time;
   double top_pavio_pts = (high_p - top_body) / point;
   double btm_pavio_pts = (bottom_body - low_p) / point;
   string day_str = (m_auto_day == AUTO_DAY_PREVIOUS) ? "Ontem" : "Hoje";
   
   // Base inferior ancorada no fundo do corpo do candle D1 (espessura 3 para destaque)
   DesenharHLine(PREFIX_CANAL_LINES + "Bottom", bottom_body, InpColorChannel, STYLE_SOLID, 3, "FUNDO REFERÊNCIA D1 (" + day_str + ")");
   
   // Canais internos dentro do corpo (todos com a mesma amplitude idêntica, sem canal residual menor)
   for(int k = 1; k < num_body_channels; k++)
   {
      double pInner = bottom_body + (k * amplitude);
      double pMid   = pInner - (amplitude / 2.0);
      DesenharHLine(PREFIX_CANAL_LINES + "Inner_" + IntegerToString(k), pInner, InpColorChannel, STYLE_SOLID);
      DesenharHLine(PREFIX_CANAL_LINES + "InnerMid_" + IntegerToString(k), pMid, InpColorChannelMid, STYLE_DASH);
   }
   
   // Linha média de 50% do último canal interno antes do Topo
   double pLastInnerMid = (bottom_body + num_body_channels * amplitude) - (amplitude / 2.0);
   DesenharHLine(PREFIX_CANAL_LINES + "InnerMid_" + IntegerToString(num_body_channels), pLastInnerMid, InpColorChannelMid, STYLE_DASH);
   
   // Topo da grade do corpo (espessura 3 para destaque)
   double anchor_top = bottom_body + (num_body_channels * amplitude);
   DesenharHLine(PREFIX_CANAL_LINES + "Top", anchor_top, InpColorChannel, STYLE_SOLID, 3, "TOPO REFERÊNCIA D1 (" + day_str + ")");
   
   m_highest_proj = anchor_top;
   m_lowest_proj  = bottom_body;
   
   // 1. Projeções para CIMA a partir do Topo (Padrão 40 canais com passos de amplitude uniforme)
   for(int i = 1; i <= m_proj_up; i++)
   {
      double cur_amp = amplitude;
      if(m_fit_mode == FIT_MODE_EXTREME && i == m_proj_up && sobra > 0.0)
         cur_amp += sobra; // Coloca a sobra no 40º canal da ponta superior
         
      double pTop = anchor_top + (i * amplitude);
      if(m_fit_mode == FIT_MODE_EXTREME && i == m_proj_up && sobra > 0.0)
         pTop += sobra;
         
      double pMid = pTop - (cur_amp / 2.0);
      DesenharHLine(PREFIX_CANAL_LINES + "Up_" + IntegerToString(i), pTop, InpColorChannel, STYLE_SOLID);
      DesenharHLine(PREFIX_CANAL_LINES + "UpMid_" + IntegerToString(i), pMid, InpColorChannelMid, STYLE_DASH);
      m_highest_proj = pTop;
   }
   
   // 2. Projeções para BAIXO a partir do Fundo (Padrão 40 canais com passos de amplitude uniforme)
   for(int i = 1; i <= m_proj_down; i++)
   {
      double pBottom = bottom_body - (i * amplitude);
      double pMid    = pBottom + (amplitude / 2.0);
      DesenharHLine(PREFIX_CANAL_LINES + "Down_" + IntegerToString(i), pBottom, InpColorChannel, STYLE_SOLID);
      DesenharHLine(PREFIX_CANAL_LINES + "DownMid_" + IntegerToString(i), pMid, InpColorChannelMid, STYLE_DASH);
      m_lowest_proj = pBottom;
   }
   
   // Desenha Marcadores no Gráfico indicando exatamente onde o Topo e o Fundo foram pegos
   DesenharMarcadoresReferencia(bar_time, anchor_top, bottom_body, day_str, top_pavio_pts, btm_pavio_pts);
   
   SalvarEstadoCanais(anchor_top, bottom_body, amplitude, bar_time, top_pavio_pts, btm_pavio_pts);
   ObjectDelete(m_chart_id, m_temp_line1);
   ObjectDelete(m_chart_id, m_temp_line2);
   
   m_chan_step = 0;
   m_has_projections = true;
   m_chan_visible = true;
   m_alerted_high = false;
   m_alerted_low  = false;
   
   double eff_pts = amplitude / point;
   string status_str = StringFormat("Auto %s (~%.0f pts): %d C / %d B", day_str, eff_pts, m_proj_up, m_proj_down);
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_TEXT, status_str);
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_COLOR, clrCyan);
   
   Print(StringFormat("Auto Canal [%s - %s]: Topo = %.*f (Pavio: %.0f pts) | Fundo = %.*f (Pavio: %.0f pts) | Canal = %.1f pts (%d no corpo) | %d Cima / %d Baixo",
         m_symbol, day_str, _Digits, anchor_top, top_pavio_pts, _Digits, bottom_body, btm_pavio_pts, eff_pts, num_body_channels, m_proj_up, m_proj_down));
   
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::ToggleChannelVisibility()
{
   m_chan_visible = !m_chan_visible;
   int total = ObjectsTotal(m_chart_id, 0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(m_chart_id, i, 0);
      if(StringFind(name, PREFIX_CANAL_LINES) == 0)
         ObjectSetInteger(m_chart_id, name, OBJPROP_TIMEFRAMES, m_chan_visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   }
   ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_Chan_HideShow", OBJPROP_TEXT, m_chan_visible ? "Ocultar Linhas" : "Mostrar Linhas");
   if(m_has_projections)
      GlobalVariableSet(GetGVPrefix() + "visible", m_chan_visible ? 1.0 : 0.0);
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::LimparCanais()
{
   ObjectsDeleteAll(m_chart_id, PREFIX_CANAL_LINES);
   ObjectDelete(m_chart_id, m_temp_line1);
   ObjectDelete(m_chart_id, m_temp_line2);
   LimparVariaveisGlobaisCanais();
   
   m_chan_step = 0;
   m_has_projections = false;
   m_alerted_high = false;
   m_alerted_low  = false;
   m_highest_proj = 0.0;
   m_lowest_proj  = 0.0;
   
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_TEXT, "Status: Limpo");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_COLOR, clrWhite);
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::SalvarEstadoCanais(double baseTop, double baseBottom, double amp=0.0, datetime refTime=0, double topPavio=0.0, double btmPavio=0.0)
{
   string p = GetGVPrefix();
   double save_amp = (amp > 0.0) ? amp : (baseTop - baseBottom);
   GlobalVariableSet(p + "has_proj", 1.0);
   GlobalVariableSet(p + "base_top", baseTop);
   GlobalVariableSet(p + "base_bottom", baseBottom);
   GlobalVariableSet(p + "amplitude", save_amp);
   GlobalVariableSet(p + "high_proj", m_highest_proj);
   GlobalVariableSet(p + "low_proj", m_lowest_proj);
   GlobalVariableSet(p + "proj_up", (double)m_proj_up);
   GlobalVariableSet(p + "proj_down", (double)m_proj_down);
   GlobalVariableSet(p + "channel_pts", (double)m_channel_pts);
   GlobalVariableSet(p + "auto_day", (double)m_auto_day);
   GlobalVariableSet(p + "visible", m_chan_visible ? 1.0 : 0.0);
   if(refTime > 0)
   {
      GlobalVariableSet(p + "ref_time", (double)refTime);
      GlobalVariableSet(p + "top_pavio", topPavio);
      GlobalVariableSet(p + "btm_pavio", btmPavio);
   }
}

void CBoletaMaster::LimparVariaveisGlobaisCanais()
{
   string p = GetGVPrefix();
   GlobalVariableDel(p + "has_proj");
   GlobalVariableDel(p + "base_top");
   GlobalVariableDel(p + "base_bottom");
   GlobalVariableDel(p + "amplitude");
   GlobalVariableDel(p + "high_proj");
   GlobalVariableDel(p + "low_proj");
   GlobalVariableDel(p + "proj_up");
   GlobalVariableDel(p + "proj_down");
   GlobalVariableDel(p + "channel_pts");
   GlobalVariableDel(p + "auto_day");
   GlobalVariableDel(p + "visible");
   GlobalVariableDel(p + "ref_time");
   GlobalVariableDel(p + "top_pavio");
   GlobalVariableDel(p + "btm_pavio");
}

void CBoletaMaster::RestaurarEstadoCanais()
{
   string p = GetGVPrefix();
   if(GlobalVariableCheck(p + "has_proj") && GlobalVariableGet(p + "has_proj") > 0.5)
   {
      double baseTop    = GlobalVariableGet(p + "base_top");
      double baseBottom = GlobalVariableGet(p + "base_bottom");
      m_proj_up         = (int)GlobalVariableGet(p + "proj_up");
      m_proj_down       = (int)GlobalVariableGet(p + "proj_down");
      if(GlobalVariableCheck(p + "channel_pts"))
         m_channel_pts  = (int)GlobalVariableGet(p + "channel_pts");
      if(GlobalVariableCheck(p + "auto_day"))
         m_auto_day     = (ENUM_AUTO_DAY)(int)GlobalVariableGet(p + "auto_day");
      m_chan_visible    = (GlobalVariableGet(p + "visible") > 0.5);
      
      double amplitude = 0.0;
      if(GlobalVariableCheck(p + "amplitude"))
         amplitude = GlobalVariableGet(p + "amplitude");
      if(amplitude <= 0.0)
         amplitude = baseTop - baseBottom;
         
      ObjectsDeleteAll(m_chart_id, PREFIX_CANAL_LINES);
      if(amplitude > 0.0)
      {
         double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
         if(point <= 0.0) point = 0.00001;
         
         double body_dist = baseTop - baseBottom;
         int num_body_channels = (int)MathRound(body_dist / amplitude);
         if(num_body_channels < 1) num_body_channels = 1;
         
         string day_str = (m_auto_day == AUTO_DAY_PREVIOUS) ? "Ontem" : "Hoje";
         DesenharHLine(PREFIX_CANAL_LINES + "Bottom", baseBottom, InpColorChannel, STYLE_SOLID, 3, "FUNDO REFERÊNCIA D1 (" + day_str + ")");
         for(int k = 1; k < num_body_channels; k++)
         {
            double pInner = baseBottom + (k * amplitude);
            double pMid   = pInner - (amplitude / 2.0);
            DesenharHLine(PREFIX_CANAL_LINES + "Inner_" + IntegerToString(k), pInner, InpColorChannel, STYLE_SOLID);
            DesenharHLine(PREFIX_CANAL_LINES + "InnerMid_" + IntegerToString(k), pMid, InpColorChannelMid, STYLE_DASH);
         }
         double pLastMid = baseTop - (amplitude / 2.0);
         DesenharHLine(PREFIX_CANAL_LINES + "InnerMid_" + IntegerToString(num_body_channels), pLastMid, InpColorChannelMid, STYLE_DASH);
         DesenharHLine(PREFIX_CANAL_LINES + "Top", baseTop, InpColorChannel, STYLE_SOLID, 3, "TOPO REFERÊNCIA D1 (" + day_str + ")");
         
         m_highest_proj = baseTop;
         m_lowest_proj  = baseBottom;
         
         for(int i = 1; i <= m_proj_up; i++)
         {
            double pTop = baseTop + (i * amplitude);
            double pMid = pTop - (amplitude / 2.0);
            DesenharHLine(PREFIX_CANAL_LINES + "Up_" + IntegerToString(i), pTop, InpColorChannel, STYLE_SOLID);
            DesenharHLine(PREFIX_CANAL_LINES + "UpMid_" + IntegerToString(i), pMid, InpColorChannelMid, STYLE_DASH);
            m_highest_proj = pTop;
         }
         
         for(int i = 1; i <= m_proj_down; i++)
         {
            double pBottom = baseBottom - (i * amplitude);
            double pMid = pBottom + (amplitude / 2.0);
            DesenharHLine(PREFIX_CANAL_LINES + "Down_" + IntegerToString(i), pBottom, InpColorChannel, STYLE_SOLID);
            DesenharHLine(PREFIX_CANAL_LINES + "DownMid_" + IntegerToString(i), pMid, InpColorChannelMid, STYLE_DASH);
            m_lowest_proj = pBottom;
         }
         
         if(InpShowChannelRefMarkers && GlobalVariableCheck(p + "ref_time"))
         {
            datetime refTime = (datetime)GlobalVariableGet(p + "ref_time");
            double topPavio  = GlobalVariableCheck(p + "top_pavio") ? GlobalVariableGet(p + "top_pavio") : 0.0;
            double btmPavio  = GlobalVariableCheck(p + "btm_pavio") ? GlobalVariableGet(p + "btm_pavio") : 0.0;
            DesenharMarcadoresReferencia(refTime, baseTop, baseBottom, day_str, topPavio, btmPavio);
         }
         
         m_has_projections = true;
         double eff_pts = amplitude / point;
         ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_TEXT, StringFormat("Canal Ativo (~%.0f pts): %d C / %d B", eff_pts, m_proj_up, m_proj_down));
         ObjectSetInteger(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_COLOR, clrCyan);
      }
   }
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::CheckBreakout()
{
   if(!m_has_projections) return;
   double curPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   
   if(m_highest_proj > 0.0 && curPrice > m_highest_proj)
   {
      if(!m_alerted_high && (TimeCurrent() - m_last_alert_time > 15))
      {
         m_alerted_high = true;
         m_last_alert_time = TimeCurrent();
         string msg = StringFormat("[%s] ROMPIMENTO DE ALTA DO CANAL: %s", m_symbol, DoubleToString(curPrice, _Digits));
         if(InpCanalScreenAlert) Alert(msg);
         if(InpCanalPushAlert)   SendNotification(msg);
      }
   }
   else
   {
      m_alerted_high = false;
   }
   
   if(m_lowest_proj > 0.0 && curPrice < m_lowest_proj)
   {
      if(!m_alerted_low && (TimeCurrent() - m_last_alert_time > 15))
      {
         m_alerted_low = true;
         m_last_alert_time = TimeCurrent();
         string msg = StringFormat("[%s] ROMPIMENTO DE BAIXA DO CANAL: %s", m_symbol, DoubleToString(curPrice, _Digits));
         if(InpCanalScreenAlert) Alert(msg);
         if(InpCanalPushAlert)   SendNotification(msg);
      }
   }
   else
   {
      m_alerted_low = false;
   }
}

//+------------------------------------------------------------------+
//| Ordem Fantasma Interativa (Mira via Mouse + Clique Direito)      |
//+------------------------------------------------------------------+
void CBoletaMaster::StartGhostPlacement(ENUM_GHOST_TYPE type)
{
   ClearGhostOrder();
   m_ghost_type    = type;
   m_ghost_placing = true;
   m_rbutton_was_down = true;
   
   ChartSetInteger(m_chart_id, CHART_CONTEXT_MENU, false);
   
   string type_label = (type == GHOST_BUY) ? "COMPRA" : "VENDA";
   ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_GhostConfirm", OBJPROP_TEXT, 
      StringFormat("[MIRA %s] Clique Direito p/ Fixar", type_label));
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_GhostConfirm", OBJPROP_BGCOLOR, 
      (type == GHOST_BUY) ? C'16,130,85' : C'180,35,45');
   
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::UpdateGhostPreview(double price, datetime time)
{
   string line_name = PREFIX_GHOST + "PREVIEW";
   string badge_name = PREFIX_GHOST + "BADGE";
   
   color c_color = (m_ghost_type == GHOST_BUY) ? clrDodgerBlue : clrCrimson;
   
   // Linha guia horizontal que segue a altura do mouse
   if(ObjectFind(m_chart_id, line_name) < 0)
   {
      ObjectCreate(m_chart_id, line_name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(m_chart_id, line_name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(m_chart_id, line_name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(m_chart_id, line_name, OBJPROP_BACK, false);
      ObjectSetInteger(m_chart_id, line_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chart_id, line_name, OBJPROP_ZORDER, 200);
   }
   ObjectSetDouble(m_chart_id, line_name, OBJPROP_PRICE, price);
   ObjectSetInteger(m_chart_id, line_name, OBJPROP_COLOR, c_color);
   
   // Badge em TAMANHO MAIOR (Destaque absoluto do valor onde o mouse está)
   if(ObjectFind(m_chart_id, badge_name) < 0)
   {
      ObjectCreate(m_chart_id, badge_name, OBJ_TEXT, 0, time, price);
      ObjectSetInteger(m_chart_id, badge_name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetString(m_chart_id, badge_name, OBJPROP_FONT, "Segoe UI Bold");
      ObjectSetInteger(m_chart_id, badge_name, OBJPROP_FONTSIZE, 13); // TAMANHO GRANDE
      ObjectSetInteger(m_chart_id, badge_name, OBJPROP_BACK, false);
      ObjectSetInteger(m_chart_id, badge_name, OBJPROP_ZORDER, 210);
   }
   
   string tipo_str = (m_ghost_type == GHOST_BUY) ? "▲ COMPRA" : "▼ VENDA";
   string badge_txt = StringFormat("  %s: %.*f  [CLIQUE BOTÃO DIREITO P/ FIXAR]", tipo_str, _Digits, price);
   
   ObjectMove(m_chart_id, badge_name, 0, time, price);
   ObjectSetString(m_chart_id, badge_name, OBJPROP_TEXT, badge_txt);
   ObjectSetInteger(m_chart_id, badge_name, OBJPROP_COLOR, (m_ghost_type == GHOST_BUY) ? C'0,210,255' : C'255,80,90');
   
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::AnchorGhostOrder(double entry_price)
{
   m_ghost_placing = false;
   ChartSetInteger(m_chart_id, CHART_CONTEXT_MENU, true);
   
   ObjectDelete(m_chart_id, PREFIX_GHOST + "PREVIEW");
   ObjectDelete(m_chart_id, PREFIX_GHOST + "BADGE");
   
   m_ghost_entry_price = entry_price;
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0) point = 0.00001;
   
   int default_dist_pts = (m_sl_points > 0) ? m_sl_points : 150;
   
   if(m_ghost_type == GHOST_BUY)
      m_ghost_sl_price = m_ghost_entry_price - (default_dist_pts * point);
   else
      m_ghost_sl_price = m_ghost_entry_price + (default_dist_pts * point);
   
   CreateAnchoredGhostLines();
   
   ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_GhostConfirm", OBJPROP_TEXT, "[ENTER] Enviar Fantasma");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_GhostConfirm", OBJPROP_BGCOLOR, COLOR_GHOST_CONFIRM);
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::CreateAnchoredGhostLines()
{
   string entry_name = PREFIX_GHOST + "ENTRY";
   string sl_name    = PREFIX_GHOST + "SL";
   string tag_name   = PREFIX_GHOST + "TAG";
   
   ObjectCreate(m_chart_id, entry_name, OBJ_HLINE, 0, 0, m_ghost_entry_price);
   ObjectSetInteger(m_chart_id, entry_name, OBJPROP_COLOR, (m_ghost_type == GHOST_BUY) ? clrDodgerBlue : clrCrimson);
   ObjectSetInteger(m_chart_id, entry_name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(m_chart_id, entry_name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(m_chart_id, entry_name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(m_chart_id, entry_name, OBJPROP_SELECTED, true);
   ObjectSetInteger(m_chart_id, entry_name, OBJPROP_BACK, false);
   ObjectSetInteger(m_chart_id, entry_name, OBJPROP_ZORDER, 100);
   ObjectSetString(m_chart_id, entry_name, OBJPROP_TOOLTIP, "Entrada Fantasma (Arraste para ajustar)");
   
   ObjectCreate(m_chart_id, sl_name, OBJ_HLINE, 0, 0, m_ghost_sl_price);
   ObjectSetInteger(m_chart_id, sl_name, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(m_chart_id, sl_name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(m_chart_id, sl_name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(m_chart_id, sl_name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(m_chart_id, sl_name, OBJPROP_SELECTED, true);
   ObjectSetInteger(m_chart_id, sl_name, OBJPROP_BACK, false);
   ObjectSetInteger(m_chart_id, sl_name, OBJPROP_ZORDER, 100);
   ObjectSetString(m_chart_id, sl_name, OBJPROP_TOOLTIP, "Stop Loss Fantasma (Arraste p/ recalcular lote)");
   
   ObjectCreate(m_chart_id, tag_name, OBJ_TEXT, 0, TimeCurrent(), m_ghost_entry_price);
   ObjectSetInteger(m_chart_id, tag_name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(m_chart_id, tag_name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetString(m_chart_id, tag_name, OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(m_chart_id, tag_name, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(m_chart_id, tag_name, OBJPROP_BACK, false);
   ObjectSetInteger(m_chart_id, tag_name, OBJPROP_ZORDER, 105);
   
   UpdateGhostFromDrag(sl_name);
}

void CBoletaMaster::UpdateGhostFromDrag(const string obj_name)
{
   if(!HasGhostOrder()) return;
   
   string entry_name = PREFIX_GHOST + "ENTRY";
   string sl_name    = PREFIX_GHOST + "SL";
   string tag_name   = PREFIX_GHOST + "TAG";
   
   m_ghost_entry_price = ObjectGetDouble(m_chart_id, entry_name, OBJPROP_PRICE);
   m_ghost_sl_price    = ObjectGetDouble(m_chart_id, sl_name, OBJPROP_PRICE);
   
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0) point = 0.00001;
   
   int dist_pts = (int)MathRound(MathAbs(m_ghost_entry_price - m_ghost_sl_price) / point);
   if(dist_pts <= 0) dist_pts = 1;
   
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin <= 0.0) freeMargin = AccountInfoDouble(ACCOUNT_BALANCE);
   
   double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize > 0.0 && point > 0.0)
   {
      double ptsPerTick = tickSize / point;
      if(ptsPerTick > 0.0)
         tickValue = tickValue / ptsPerTick;
   }
   if(tickValue <= 0.0) tickValue = 1.0;
   
   double denominator = dist_pts * tickValue;
   double raw_lot = 0.0;
   double riskMoney = 0.0;
   
   if(denominator > 0.0)
   {
      if(m_risk_mode == RISK_MODE_PERCENT)
      {
         riskMoney = freeMargin * (m_risk_percent / 100.0);
         raw_lot   = riskMoney / denominator;
      }
      else if(m_risk_mode == RISK_MODE_CASH)
      {
         riskMoney = m_risk_cash;
         raw_lot   = riskMoney / denominator;
      }
      else
      {
         riskMoney = m_manual_lot * denominator;
         raw_lot   = m_manual_lot;
      }
   }
   else
   {
      raw_lot = m_manual_lot;
   }
   
   m_ghost_lot = NormalizeLot(raw_lot, m_symbol);
   datetime cur_time = (datetime)SeriesInfoInteger(m_symbol, _Period, SERIES_LASTBAR_DATE);
   if(cur_time == 0) cur_time = TimeCurrent();
   
   int dec = GetLotDecimals(m_symbol);
   string type_str = (m_ghost_type == GHOST_BUY) ? "BUY PENDENTE" : "SELL PENDENTE";
   string risk_label = (m_risk_mode == RISK_MODE_PERCENT) ? StringFormat("%.1f%%", m_risk_percent) : StringFormat("$%.2f", m_risk_cash);
   string tag_text = StringFormat(" %s | Lote: %.*f | Dist SL: %d pts | Risco: %s ($%.2f) | [ENTER] Executar", 
                                  type_str, dec, m_ghost_lot, dist_pts, risk_label, riskMoney);
   
   ObjectMove(m_chart_id, tag_name, 0, cur_time, m_ghost_entry_price);
   ObjectSetString(m_chart_id, tag_name, OBJPROP_TEXT, tag_text);
   
   m_sl_points  = dist_pts;
   m_manual_lot = m_ghost_lot;
   if(InpShowSLSection)
      ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_SL", OBJPROP_TEXT, IntegerToString(m_sl_points));
   if(InpShowLotSection)
      ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Lot", OBJPROP_TEXT, DoubleToString(m_manual_lot, dec));
   
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::ExecuteGhostOrder()
{
   if(!HasGhostOrder()) return;
   
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   
   double sl = m_sl_active ? m_ghost_sl_price : 0.0;
   double tp = 0.0;
   if(m_tp_active && m_tp_points > 0)
   {
      if(m_ghost_type == GHOST_BUY)
         tp = m_ghost_entry_price + (m_tp_points * point);
      else
         tp = m_ghost_entry_price - (m_tp_points * point);
   }
   
   if(m_ghost_type == GHOST_BUY)
   {
      if(m_ghost_entry_price < ask)
         m_trade.BuyLimit(m_ghost_lot, m_ghost_entry_price, m_symbol, sl, tp, ORDER_TIME_GTC, 0, "Scalp Buy Limit");
      else if(m_ghost_entry_price > ask)
         m_trade.BuyStop(m_ghost_lot, m_ghost_entry_price, m_symbol, sl, tp, ORDER_TIME_GTC, 0, "Scalp Buy Stop");
      else
         m_trade.Buy(m_ghost_lot, m_symbol, ask, sl, tp, "Scalp Buy");
   }
   else if(m_ghost_type == GHOST_SELL)
   {
      if(m_ghost_entry_price > bid)
         m_trade.SellLimit(m_ghost_lot, m_ghost_entry_price, m_symbol, sl, tp, ORDER_TIME_GTC, 0, "Scalp Sell Limit");
      else if(m_ghost_entry_price < bid)
         m_trade.SellStop(m_ghost_lot, m_ghost_entry_price, m_symbol, sl, tp, ORDER_TIME_GTC, 0, "Scalp Sell Stop");
      else
         m_trade.Sell(m_ghost_lot, m_symbol, bid, sl, tp, "Scalp Sell");
   }
   
   ClearGhostOrder();
   UpdateLiveMetrics();
}

void CBoletaMaster::ClearGhostOrder()
{
   m_ghost_placing    = false;
   m_rbutton_was_down = false;
   m_ghost_type       = GHOST_NONE;
   ChartSetInteger(m_chart_id, CHART_CONTEXT_MENU, true);
   ObjectsDeleteAll(m_chart_id, PREFIX_GHOST);
   
   if(InpShowGhostOrder)
   {
      ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_GhostConfirm", OBJPROP_TEXT, "FANTASMA: [Up/Dn]");
      ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_GhostConfirm", OBJPROP_BGCOLOR, C'35,38,48');
   }
   ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Execuções Ultrarrápidas de Mercado e Ordens                      |
//+------------------------------------------------------------------+
void CBoletaMaster::ExecuteBuy()
{
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double lot = GetEffectiveLot();
   double sl = (m_sl_active && m_sl_points > 0) ? (ask - m_sl_points * point) : 0.0;
   double tp = (m_tp_active && m_tp_points > 0) ? (ask + m_tp_points * point) : 0.0;
   m_trade.Buy(lot, m_symbol, ask, sl, tp, "Scalp Buy");
   UpdateLiveMetrics();
}

void CBoletaMaster::ExecuteSell()
{
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double lot = GetEffectiveLot();
   double sl = (m_sl_active && m_sl_points > 0) ? (bid + m_sl_points * point) : 0.0;
   double tp = (m_tp_active && m_tp_points > 0) ? (bid - m_tp_points * point) : 0.0;
   m_trade.Sell(lot, m_symbol, bid, sl, tp, "Scalp Sell");
   UpdateLiveMetrics();
}

void CBoletaMaster::ExecuteInvert()
{
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && (!InpFilterSymbolOnly || pos.Symbol() == m_symbol))
      {
         ENUM_POSITION_TYPE p_type = pos.PositionType();
         double p_vol = pos.Volume();
         ulong ticket = pos.Ticket();
         string sym = pos.Symbol();
         
         m_trade.PositionClose(ticket);
         
         if(p_type == POSITION_TYPE_BUY)
         {
            double sl = (m_sl_active && m_sl_points > 0) ? (bid + m_sl_points * point) : 0.0;
            double tp = (m_tp_active && m_tp_points > 0) ? (bid - m_tp_points * point) : 0.0;
            m_trade.Sell(p_vol, sym, bid, sl, tp, "Inverter Venda");
         }
         else if(p_type == POSITION_TYPE_SELL)
         {
            double sl = (m_sl_active && m_sl_points > 0) ? (ask - m_sl_points * point) : 0.0;
            double tp = (m_tp_active && m_tp_points > 0) ? (ask + m_tp_points * point) : 0.0;
            m_trade.Buy(p_vol, sym, ask, sl, tp, "Inverter Compra");
         }
      }
   }
   UpdateLiveMetrics();
}

void CBoletaMaster::ExecuteHedge()
{
   CPositionInfo pos;
   double total_buy_vol = 0.0, total_sell_vol = 0.0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && pos.Symbol() == m_symbol)
      {
         if(pos.PositionType() == POSITION_TYPE_BUY)
            total_buy_vol += pos.Volume();
         else if(pos.PositionType() == POSITION_TYPE_SELL)
            total_sell_vol += pos.Volume();
      }
   }
   
   double net_exposure = total_buy_vol - total_sell_vol;
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   
   if(net_exposure > 0.00001)
   {
      double lot_to_hedge = NormalizeLot(net_exposure, m_symbol);
      m_trade.Sell(lot_to_hedge, m_symbol, bid, 0, 0, "Hedge Trava Compra");
   }
   else if(net_exposure < -0.00001)
   {
      double lot_to_hedge = NormalizeLot(MathAbs(net_exposure), m_symbol);
      m_trade.Buy(lot_to_hedge, m_symbol, ask, 0, 0, "Hedge Trava Venda");
   }
   else if(total_buy_vol > 0.0 && total_sell_vol > 0.0)
   {
      Alert(StringFormat("Ativo %s já está 100%% hedged!", m_symbol));
   }
   else
   {
      double lot = GetEffectiveLot();
      m_trade.Buy(lot, m_symbol, ask, 0, 0, "Hedge Duplo Buy");
      m_trade.Sell(lot, m_symbol, bid, 0, 0, "Hedge Duplo Sell");
   }
   UpdateLiveMetrics();
}

void CBoletaMaster::ExecuteCloseAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && (!InpFilterSymbolOnly || PositionGetString(POSITION_SYMBOL) == m_symbol))
         m_trade.PositionClose(ticket);
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0 && (!InpFilterSymbolOnly || OrderGetString(ORDER_SYMBOL) == m_symbol))
         m_trade.OrderDelete(ticket);
   }
   UpdateLiveMetrics();
}

void CBoletaMaster::ExecuteCloseProfit()
{
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && (!InpFilterSymbolOnly || pos.Symbol() == m_symbol))
      {
         if(pos.Profit() > 0.0)
            m_trade.PositionClose(pos.Ticket());
      }
   }
   UpdateLiveMetrics();
}

void CBoletaMaster::ExecuteCloseLoss()
{
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && (!InpFilterSymbolOnly || pos.Symbol() == m_symbol))
      {
         if(pos.Profit() < 0.0)
            m_trade.PositionClose(pos.Ticket());
      }
   }
   UpdateLiveMetrics();
}

void CBoletaMaster::ExecuteCancelPendings()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0 && (!InpFilterSymbolOnly || OrderGetString(ORDER_SYMBOL) == m_symbol))
         m_trade.OrderDelete(ticket);
   }
   UpdateLiveMetrics();
}

//+------------------------------------------------------------------+
//| Gestão de Edições e Cliques                                      |
//+------------------------------------------------------------------+
void CBoletaMaster::HandleEndEdit(const string &obj_name)
{
   string short_name = obj_name;
   StringReplace(short_name, PREFIX_GUI, "");
   string val_str = ObjectGetString(m_chart_id, obj_name, OBJPROP_TEXT);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin <= 0.0) freeMargin = AccountInfoDouble(ACCOUNT_BALANCE);
   
   if(short_name == "Edit_Risk")
   {
      double r = StringToDouble(val_str);
      if(m_risk_mode == RISK_MODE_PERCENT)
      {
         if(r > 0.0) m_risk_percent = r;
         if(freeMargin > 0.0) m_risk_cash = freeMargin * (m_risk_percent / 100.0);
      }
      else if(m_risk_mode == RISK_MODE_CASH)
      {
         if(r > 0.0) m_risk_cash = r;
         if(freeMargin > 0.0) m_risk_percent = (m_risk_cash / freeMargin) * 100.0;
      }
      RecalculateRiskLot();
   }
   else if(short_name == "Edit_Lot")
   {
      m_risk_mode = RISK_MODE_MANUAL;
      double l = StringToDouble(val_str);
      if(l > 0.0) m_manual_lot = l;
   }
   else if(short_name == "Edit_SL")
   {
      int sl = (int)StringToInteger(val_str);
      if(sl >= 0) m_sl_points = sl;
      if(m_risk_mode != RISK_MODE_MANUAL) RecalculateRiskLot();
   }
   else if(short_name == "Edit_TP")
   {
      int tp = (int)StringToInteger(val_str);
      if(tp >= 0) m_tp_points = tp;
   }
   else if(short_name == "Edit_Parcial_Target")
   {
      if(m_parcial_is_cash)
      {
         double c = StringToDouble(val_str);
         if(c > 0.0) m_parcial_target_cash = c;
      }
      else
      {
         int p = (int)StringToInteger(val_str);
         if(p >= 0) m_parcial_target_pts = p;
      }
   }
   else if(short_name == "Edit_Parcial_Vol")
   {
      string clean_val = val_str;
      StringReplace(clean_val, "%", "");
      double v = StringToDouble(clean_val);
      if(v >= 1.0 && v <= 100.0) m_parcial_vol_pct = v;
   }
   else if(short_name == "Edit_BE")
   {
      int be = (int)StringToInteger(val_str);
      if(be >= 0) m_be_points = be;
   }
   else if(short_name == "Edit_TS")
   {
      int ts = (int)StringToInteger(val_str);
      if(ts >= 0) m_ts_points = ts;
   }
   else if(short_name == "Edit_Chan_Up")
   {
      int up = (int)StringToInteger(val_str);
      if(up >= 0 && up <= 100) m_proj_up = up;
      if(m_has_projections) ProjetarCanais();
   }
   else if(short_name == "Edit_Chan_Dn")
   {
      int dn = (int)StringToInteger(val_str);
      if(dn >= 0 && dn <= 100) m_proj_down = dn;
      if(m_has_projections) ProjetarCanais();
   }
   else if(short_name == "Edit_Chan_Pts")
   {
      int pts = (int)StringToInteger(val_str);
      if(pts > 0) m_channel_pts = pts;
   }
   UpdateFieldValues();
}

void CBoletaMaster::HandleButtonClick(const string &obj_name)
{
   string short_name = obj_name;
   StringReplace(short_name, PREFIX_GUI, "");
   ObjectSetInteger(m_chart_id, obj_name, OBJPROP_STATE, false);
   
   if(short_name == "Btn_Min")              { ToggleMinimize(); return; }
   if(short_name == "Btn_Close")            { Destroy(REASON_REMOVE); ExpertRemove(); return; }
   if(short_name == "Btn_Hud_Period")       { CycleHudPeriod(); return; }
   
   // Toggle da Gaveta de Canais
   if(short_name == "Btn_Channels_Toggle")  { ToggleChannelsDrawer(); return; }
   if(short_name == "Btn_Chan_Start")       { StartChannelMarking(); return; }
   if(short_name == "Btn_Chan_Project")     { ProjetarCanais(); return; }
   if(short_name == "Btn_Chan_Day")         { ToggleAutoDay(); return; }
   if(short_name == "Btn_Chan_Auto")        { ProjetarCanaisAuto(); return; } // BOTÃO MARCAR AUTO
   if(short_name == "Btn_Chan_Up_Dec")      { AdjustChanUp(-1); return; }
   if(short_name == "Btn_Chan_Up_Inc")      { AdjustChanUp(1); return; }
   if(short_name == "Btn_Chan_Dn_Dec")      { AdjustChanDown(-1); return; }
   if(short_name == "Btn_Chan_Dn_Inc")      { AdjustChanDown(1); return; }
   if(short_name == "Btn_Chan_HideShow")    { ToggleChannelVisibility(); return; }
   if(short_name == "Btn_Chan_Clear")       { LimparCanais(); return; }
   
   // Toggles Operacionais
   if(short_name == "Chk_Risk")             { ToggleRiskAuto(); return; }
   if(short_name == "Btn_Risk_Toggle")      { ToggleRiskMode(); return; }
   if(short_name == "Chk_SL")               { ToggleSL(); return; }
   if(short_name == "Chk_TP")               { ToggleTP(); return; }
   if(short_name == "Chk_BE")               { ToggleBE(); return; }
   if(short_name == "Chk_TS")               { ToggleTS(); return; }
   if(short_name == "Chk_Parcial")          { ToggleParcial(); return; }
   if(short_name == "Btn_Parcial_Toggle")   { ToggleParcialMode(); return; }
   if(short_name == "Chk_Parcial_BE")       { ToggleParcialBE(); return; }
   
   // Steppers (+ / -)
   if(short_name == "Btn_Risk_Dec")
   {
      AdjustRisk((m_risk_mode == RISK_MODE_CASH) ? -InpStepRiskCash : -InpStepRiskPct);
      return;
   }
   if(short_name == "Btn_Risk_Inc")
   {
      AdjustRisk((m_risk_mode == RISK_MODE_CASH) ? InpStepRiskCash : InpStepRiskPct);
      return;
   }
   
   double lot_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
   if(lot_step <= 0.0) lot_step = 0.01;
   if(short_name == "Btn_Lot_Dec")          { AdjustLot(-lot_step); return; }
   if(short_name == "Btn_Lot_Inc")          { AdjustLot(lot_step); return; }
   
   if(short_name == "Btn_SL_Dec")           { AdjustSL(-InpStepPoints); return; }
   if(short_name == "Btn_SL_Inc")           { AdjustSL(InpStepPoints); return; }
   
   if(short_name == "Btn_TP_Dec")           { AdjustTP(-InpStepPoints); return; }
   if(short_name == "Btn_TP_Inc")           { AdjustTP(InpStepPoints); return; }
   
   if(short_name == "Btn_Parcial_Dec")
   {
      AdjustParcialTarget(m_parcial_is_cash ? -InpStepParcialCash : -InpStepPoints);
      return;
   }
   if(short_name == "Btn_Parcial_Inc")
   {
      AdjustParcialTarget(m_parcial_is_cash ? InpStepParcialCash : InpStepPoints);
      return;
   }
   if(short_name == "Btn_Parcial_Vol_Dec")   { AdjustParcialVol(-InpStepParcialVol); return; }
   if(short_name == "Btn_Parcial_Vol_Inc")   { AdjustParcialVol(InpStepParcialVol); return; }
   
   if(short_name == "Btn_BE_Dec")           { AdjustBE(-InpStepPoints); return; }
   if(short_name == "Btn_BE_Inc")           { AdjustBE(InpStepPoints); return; }
   
   if(short_name == "Btn_TS_Dec")           { AdjustTS(-InpStepPoints); return; }
   if(short_name == "Btn_TS_Inc")           { AdjustTS(InpStepPoints); return; }
   
   // Ações de Negociação
   if(short_name == "Btn_Buy")              { ExecuteBuy(); return; }
   if(short_name == "Btn_Sell")             { ExecuteSell(); return; }
   if(short_name == "Btn_Invert")           { ExecuteInvert(); return; }
   if(short_name == "Btn_Hedge")            { ExecuteHedge(); return; }
   if(short_name == "Btn_CloseAll")         { ExecuteCloseAll(); return; }
   if(short_name == "Btn_CloseProfit")      { ExecuteCloseProfit(); return; }
   if(short_name == "Btn_CloseLoss")        { ExecuteCloseLoss(); return; }
   if(short_name == "Btn_CancelPendings")   { ExecuteCancelPendings(); return; }
   
   if(short_name == "Btn_GhostConfirm")
   {
      if(m_ghost_placing)
      {
         double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         AnchorGhostOrder(ask);
      }
      else if(HasGhostOrder())
      {
         ExecuteGhostOrder();
      }
      else
      {
         StartGhostPlacement(GHOST_BUY);
      }
      return;
   }
}

void CBoletaMaster::OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(StringFind(sparam, PREFIX_GUI) == 0)
         HandleEndEdit(sparam);
      return;
   }
   
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(StringFind(sparam, PREFIX_GUI) == 0)
         HandleButtonClick(sparam);
      return;
   }
   
   if(id == CHARTEVENT_OBJECT_DRAG)
   {
      if(StringFind(sparam, PREFIX_GHOST) == 0)
         UpdateGhostFromDrag(sparam);
      return;
   }
   
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int mouse_x = (int)lparam;
      int mouse_y = (int)dparam;
      uint flags  = (uint)StringToInteger(sparam);
      bool lbutton_down = ((flags & 1) == 1);
      bool rbutton_down = ((flags & 2) == 2);
      
      // 1. MIRA FANTASMA ATIVA (Seguindo o mouse + Clique Direito para Fixar)
      if(m_ghost_placing)
      {
         int subwin = 0;
         datetime cur_time;
         double cur_price;
         if(ChartXYToTimePrice(m_chart_id, mouse_x, mouse_y, subwin, cur_time, cur_price))
         {
            cur_price = NormalizeDouble(cur_price, _Digits);
            UpdateGhostPreview(cur_price, cur_time);
            
            // Clique com o BOTÃO DIREITO DO MOUSE fixa no gráfico
            if(rbutton_down && !m_rbutton_was_down)
            {
               m_rbutton_was_down = true;
               AnchorGhostOrder(cur_price);
               return;
            }
         }
         if(!rbutton_down)
            m_rbutton_was_down = false;
         return;
      }
      
      // 2. Arrastar Painel
      if(lbutton_down)
      {
         if(!m_is_dragging)
         {
            if(mouse_x >= m_x && mouse_x <= m_x + m_width &&
               mouse_y >= m_y && mouse_y <= m_y + m_header_h)
            {
               m_is_dragging   = true;
               m_drag_offset_x = mouse_x - m_x;
               m_drag_offset_y = mouse_y - m_y;
            }
         }
         else
         {
            int next_x = mouse_x - m_drag_offset_x;
            int next_y = mouse_y - m_drag_offset_y;
            if(next_x < 0) next_x = 0;
            if(next_y < 0) next_y = 0;
            MovePanel(next_x, next_y);
         }
      }
      else
      {
         if(m_is_dragging)
         {
            m_is_dragging = false;
            BringToFront();
         }
         m_is_dragging = false;
      }
      return;
   }
   
   // Captura de Cliques para Marcação Manual das Linhas de Canal
   if(id == CHARTEVENT_CLICK && (m_chan_step == 1 || m_chan_step == 2))
   {
      int x = (int)lparam, y = (int)dparam;
      if(Contains(x, y)) return;
      
      int subwin = 0;
      datetime time; double price;
      if(ChartXYToTimePrice(m_chart_id, x, y, subwin, time, price))
      {
         if(m_chan_step == 1)
         {
            CriarLinhaTemporaria(m_temp_line1, price);
            m_chan_step = 2;
            ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_TEXT, "Status: Clique Linha 2");
            ObjectSetInteger(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_COLOR, clrRed);
         }
         else if(m_chan_step == 2)
         {
            CriarLinhaTemporaria(m_temp_line2, price);
            m_chan_step = 3;
            ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_TEXT, "Ajuste e clique Projetar");
            ObjectSetInteger(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_COLOR, clrLimeGreen);
         }
         ChartRedraw(m_chart_id);
      }
      return;
   }
   
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      BringToFront();
      return;
   }
   
   // Teclas de Atalho
   if(id == CHARTEVENT_KEYDOWN)
   {
      if(lparam == 72 || lparam == 104) { ExecuteHedge(); return; }          // H
      if(lparam == 67 || lparam == 99)  { ExecuteCancelPendings(); return; } // C
      if(lparam == 77 || lparam == 109) { ToggleMinimize(); return; }        // M
      if(lparam == 38) { StartGhostPlacement(GHOST_BUY); return; }           // Seta Cima -> Mira Compra
      if(lparam == 40) { StartGhostPlacement(GHOST_SELL); return; }          // Seta Baixo -> Mira Venda
      if(lparam == 13) { if(HasGhostOrder()) ExecuteGhostOrder(); return; }  // Enter
      if(lparam == 27) { if(HasGhostOrder() || m_ghost_placing) ClearGhostOrder(); return; } // ESC
   }
}

//+------------------------------------------------------------------+
//| Instância Global Única                                           |
//+------------------------------------------------------------------+
CBoletaMaster g_boleta;

//+------------------------------------------------------------------+
//| Controle Otimizado de Execução de Parciais                       |
//+------------------------------------------------------------------+
ulong g_partial_tickets[];

bool IsPartialExecuted(ulong ticket)
{
   int total = ArraySize(g_partial_tickets);
   for(int i = 0; i < total; i++)
   {
      if(g_partial_tickets[i] == ticket) return true;
   }
   return false;
}

void MarkPartialExecuted(ulong ticket)
{
   int total = ArraySize(g_partial_tickets);
   ArrayResize(g_partial_tickets, total + 1);
   g_partial_tickets[total] = ticket;
}

void CleanPartialTickets()
{
   int size = ArraySize(g_partial_tickets);
   if(size == 0) return;
   
   ulong kept[];
   CPositionInfo pos;
   for(int i = 0; i < size; i++)
   {
      ulong t = g_partial_tickets[i];
      if(pos.SelectByTicket(t))
      {
         int ks = ArraySize(kept);
         ArrayResize(kept, ks + 1);
         kept[ks] = t;
      }
   }
   ArrayCopy(g_partial_tickets, kept);
}

//+------------------------------------------------------------------+
//| Gestão Contínua de Posições (Parciais, BE & TS)                  |
//+------------------------------------------------------------------+
void GerenciarPosicoesAbertas()
{
   bool be_active       = g_boleta.IsBEActive();
   bool ts_active       = g_boleta.IsTSActive();
   bool parcial_active  = g_boleta.IsParcialActive();
   
   if(!be_active && !ts_active && !parcial_active)
      return;
   
   int be_pts           = g_boleta.GetBEPoints();
   int ts_pts           = g_boleta.GetTSPoints();
   int ts_step_pts      = g_boleta.GetTSStepPoints();
   if(ts_step_pts <= 0) ts_step_pts = 1;
   bool parcial_is_cash = g_boleta.IsParcialCashMode();
   int parcial_pts      = g_boleta.GetParcialTargetPoints();
   double parcial_cash  = g_boleta.GetParcialTargetCash();
   double parcial_pct   = g_boleta.GetParcialVolumePct();
   
   string sym = g_boleta.GetSymbol();
   CTrade trade;
   trade.SetExpertMagicNumber(InpMagicNumber);
   SetBestFillingMode(trade, sym);
   CPositionInfo pos;
   
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(point <= 0.0) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i) || pos.Symbol() != sym)
         continue;
      
      ulong  ticket    = pos.Ticket();
      double openPrice = pos.PriceOpen();
      double curSL     = pos.StopLoss();
      double curTP     = pos.TakeProfit();
      double curVol    = pos.Volume();
      ENUM_POSITION_TYPE posType = pos.PositionType();
      
      // 1. Execução de Parcial (se estiver ativa)
      if(parcial_active && !IsPartialExecuted(ticket))
      {
         bool atingiu_parcial = false;
         
         if(parcial_is_cash)
         {
            double lucro_liquido = pos.Profit() + pos.Swap() + pos.Commission();
            if(parcial_cash > 0.0 && lucro_liquido >= parcial_cash)
               atingiu_parcial = true;
         }
         else
         {
            if(parcial_pts > 0)
            {
               if(posType == POSITION_TYPE_BUY)
               {
                  double dist_pts = (bid - openPrice) / point;
                  if(dist_pts >= parcial_pts) atingiu_parcial = true;
               }
               else if(posType == POSITION_TYPE_SELL)
               {
                  double dist_pts = (openPrice - ask) / point;
                  if(dist_pts >= parcial_pts) atingiu_parcial = true;
               }
            }
         }
         
         if(atingiu_parcial)
         {
            double close_vol = NormalizeLot(curVol * (parcial_pct / 100.0), sym);
            double min_vol = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
            if(close_vol < min_vol) close_vol = min_vol;
            
            if(close_vol >= curVol)
            {
               if(curVol > min_vol) close_vol = NormalizeLot(curVol - min_vol, sym);
               else                 close_vol = curVol;
            }
            
            if(close_vol > 0.0)
            {
               if(trade.PositionClosePartial(ticket, close_vol))
               {
                  MarkPartialExecuted(ticket);
                  if(g_boleta.IsParcialMoveBE())
                  {
                     if(pos.SelectByTicket(ticket))
                     {
                        double rem_sl = pos.StopLoss();
                        double rem_tp = pos.TakeProfit();
                        bool need_modify = false;
                        
                        if(posType == POSITION_TYPE_BUY  && rem_sl < openPrice)                need_modify = true;
                        else if(posType == POSITION_TYPE_SELL && (rem_sl == 0.0 || rem_sl > openPrice)) need_modify = true;
                        
                        if(need_modify) trade.PositionModify(ticket, openPrice, rem_tp);
                     }
                  }
                  PrintFormat("PARCIAL EXECUTADA: Ticket #%I64u | Vol: %.2f", ticket, close_vol);
               }
            }
         }
      }
      
      // 2. Break Even & Trailing Stop (BUY)
      if(posType == POSITION_TYPE_BUY)
      {
         double profit_pts = (bid - openPrice) / point;
         bool be_atingido = false;
         
         if(be_active && be_pts > 0)
         {
            if(profit_pts >= be_pts)
            {
               if(curSL < openPrice)
               {
                  trade.PositionModify(ticket, openPrice, curTP);
                  curSL = openPrice;
               }
               be_atingido = true;
            }
         }
         else be_atingido = true;
         
         if(ts_active && ts_pts > 0 && be_atingido)
         {
            double desired_sl = bid - (ts_pts * point);
            if(desired_sl >= openPrice)
            {
               double min_step = point * ts_step_pts;
               if(curSL == 0.0 || desired_sl >= curSL + min_step)
                  trade.PositionModify(ticket, desired_sl, curTP);
            }
         }
      }
      // 3. Break Even & Trailing Stop (SELL)
      else if(posType == POSITION_TYPE_SELL)
      {
         double profit_pts = (openPrice - ask) / point;
         bool be_atingido = false;
         
         if(be_active && be_pts > 0)
         {
            if(profit_pts >= be_pts)
            {
               if(curSL == 0.0 || curSL > openPrice)
               {
                  trade.PositionModify(ticket, openPrice, curTP);
                  curSL = openPrice;
               }
               be_atingido = true;
            }
         }
         else be_atingido = true;
         
         if(ts_active && ts_pts > 0 && be_atingido)
         {
            double desired_sl = ask + (ts_pts * point);
            if(desired_sl <= openPrice)
            {
               double min_step = point * ts_step_pts;
               if(curSL == 0.0 || desired_sl <= curSL - min_step)
                  trade.PositionModify(ticket, desired_sl, curTP);
            }
         }
      }
   }
   CleanPartialTickets();
}

//+------------------------------------------------------------------+
//| Evento: OnInit                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ChartSetInteger(ChartID(), CHART_FOREGROUND, false);
   
   if(!g_boleta.Init(InpSymbol, InpMagicNumber, InpSlippage, InpPanelX, InpPanelY))
   {
      Print("Erro ao inicializar Boleta Scalping Pro!");
      return INIT_FAILED;
   }
   
   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Evento: OnDeinit                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   g_boleta.Destroy(reason);
}

//+------------------------------------------------------------------+
//| Evento: OnTimer                                                  |
//+------------------------------------------------------------------+
void OnTimer()
{
   g_boleta.CheckForegroundState();
   g_boleta.UpdateLiveMetrics();
}

//+------------------------------------------------------------------+
//| Evento: OnTick                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
   g_boleta.CheckForegroundState();
   g_boleta.UpdateLiveMetrics();
   GerenciarPosicoesAbertas();
   if(InpEnableChannels) g_boleta.CheckBreakout();
}

//+------------------------------------------------------------------+
//| Evento: OnChartEvent                                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   g_boleta.OnChartEvent(id, lparam, dparam, sparam);
}
//+------------------------------------------------------------------+
