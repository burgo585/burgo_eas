//+------------------------------------------------------------------+
//|                                                BoletaScalping.mq5 |
//|                             Copyright 2026, Senior MQL5 Developer |
//|                     Front-end GUI & Risco Pro + Parciais Dinâmicas |
//+------------------------------------------------------------------+
#property copyright "Senior MQL5 Developer"
#property link      "https://www.mql5.com"
#property version   "7.20"
#property description "Boleta Visual de Scalping com z-index Máximo (Always On Top), Risco Pro, HUD e Parciais"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Cores Dark Mode Customizadas
#define COLOR_PANEL_BG      C'45,45,45'
#define COLOR_HEADER_BG     C'30,30,30'
#define COLOR_MARKET_BG     C'20,20,25'
#define COLOR_STRIP_BG      C'28,28,34'
#define COLOR_BORDER        clrBlack
#define COLOR_TEXT_MAIN     clrWhite
#define COLOR_TEXT_MUTED    C'185,185,185'
#define COLOR_EDIT_BG       C'25,25,25'
#define COLOR_EDIT_RO_BG    C'50,50,50'
#define COLOR_CHECK_ACTIVE  C'0,180,90'
#define COLOR_CHECK_INACT   C'60,60,60'
#define COLOR_STEP_BTN      C'55,55,65'
#define COLOR_PERIOD_BTN    C'40,40,55'
#define COLOR_BUY_BTN       C'0,140,60'
#define COLOR_SELL_BTN      C'180,34,34'
#define COLOR_INVERT_BTN    C'220,130,20'
#define COLOR_HEDGE_BTN     C'30,90,160'
#define COLOR_CLOSE_ALL_BTN C'210,210,210'
#define COLOR_CLOSE_PRF_BTN C'34,120,60'
#define COLOR_CLOSE_LSS_BTN C'140,40,40'
#define COLOR_CANCEL_BTN    C'70,70,85'
#define COLOR_GHOST_CONFIRM C'20,100,180'
#define COLOR_PROFIT_GREEN  C'0,230,110'
#define COLOR_LOSS_RED      C'255,80,80'
#define COLOR_TOGGLE_PCT    C'30,75,130'
#define COLOR_TOGGLE_CASH   C'30,110,80'

//--- Prefixo global para objetos
#define PREFIX_GUI   "BOLETA_GUI_"
#define PREFIX_GHOST "BOLETA_GHOST_"

//--- Prioridades de Camada (Z-Order / "z-index" Máximo para Sobreposição Absoluta no MT5)
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

//+------------------------------------------------------------------+
//| Parâmetros de Entrada (Inputs)                                   |
//+------------------------------------------------------------------+
input group "=== CONFIGURAÇÃO DO ATIVO & ROTEAMENTO ==="
input string          InpSymbol            = "";                 // Ativo Operado (Vazio = Gráfico Atual)
input ulong           InpMagicNumber       = 123456;             // Magic Number das Ordens
input ulong           InpSlippage          = 20;                 // Desvio Máximo / Slippage (pontos)
input bool            InpFilterSymbolOnly  = true;               // Filtrar Métricas apenas deste Ativo (false = Conta Toda)

input group "=== EXIBIÇÃO DE INFORMAÇÕES (HUD & MERCADO) ==="
input ENUM_HUD_PERIOD InpDefaultHudPeriod  = HUD_PERIOD_TODAY;   // Visualização Inicial do HUD
input bool            InpShowCandleTimer   = true;               // Exibir Relógio do Candle
input bool            InpShowSpread        = true;               // Exibir Spread em Pontos

input group "=== GESTÃO DE RISCO (PERCENTUAL E FINANCEIRO FIXO) ==="
input ENUM_RISK_MODE  InpDefaultRiskMode   = RISK_MODE_PERCENT;  // Modo de Risco Inicial
input double          InpRiskPercent       = 1.0;                // Risco Percentual Inicial (%)
input double          InpRiskCash          = 50.0;               // Risco Financeiro Fixo Inicial ($)
input double          InpDefaultLot        = 0.01;               // Lote Manual Inicial
input bool            InpSLActive          = true;               // Ativar Stop Loss Inicial
input int             InpDefaultSL         = 150;                // Stop Loss Padrão (pontos)
input bool            InpTPActive          = true;               // Ativar Take Profit Inicial
input int             InpDefaultTP         = 300;                // Take Profit Padrão (pontos)
input bool            InpBEActive          = true;               // Ativar Break Even Inicial
input int             InpDefaultBE         = 100;                // Break Even Padrão (pontos)
input bool            InpTSActive          = true;               // Ativar Trailing Stop Inicial
input int             InpDefaultTS         = 120;                // Trailing Stop Padrão (pontos)

input group "=== REALIZAÇÃO PARCIAL ==="
input bool            InpParcialActive     = true;               // Ativar Parcial Inicial
input bool            InpParcialIsCash     = false;              // Modo Alvo Parcial (false = Pontos, true = $)
input int             InpParcialTargetPts  = 150;                // Alvo da Parcial Padrão (pontos)
input double          InpParcialTargetCash = 25.0;               // Alvo da Parcial Padrão ($)
input double          InpParcialVolumePct  = 50.0;               // Volume da Parcial (% da Posição)
input bool            InpParcialMoveBE     = true;               // Mover SL para Zero a Zero pós Parcial

input group "=== INCREMENTOS DOS BOTÕES (+ / -) ==="
input double          InpStepRiskPct       = 0.5;                // Passo do Risco Percentual (%)
input double          InpStepRiskCash      = 10.0;               // Passo do Risco Fixo ($)
input int             InpStepPoints        = 20;                 // Passo de Pontos (SL, TP, BE, TS, Parcial Pts)
input double          InpStepParcialCash   = 5.0;                // Passo do Alvo Parcial ($)
input double          InpStepParcialVol    = 10.0;               // Passo do Volume Parcial (%)

input group "=== POSICIONAMENTO DA BOLETA ==="
input int             InpPanelX            = 20;                 // Posição Inicial X no Gráfico
input int             InpPanelY            = 40;                 // Posição Inicial Y no Gráfico

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
   
   // Arredondamento para baixo (MathFloor) baseado no SYMBOL_VOLUME_STEP p/ segurança absoluta
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

// Forward declaration para controle de parciais
void MarkPartialExecuted(ulong ticket);

//+------------------------------------------------------------------+
//| Classe: CBoletaPanel                                             |
//| Responsabilidade: Renderização e Gestão de Eventos da GUI        |
//+------------------------------------------------------------------+
class CBoletaPanel
{
private:
   string            m_symbol;
   ulong             m_magic;
   ulong             m_slippage;
   long              m_chart_id;
   int               m_subwin;
   int               m_x;
   int               m_y;
   int               m_width;
   int               m_height;
   int               m_header_h;
   
   bool              m_is_minimized;
   bool              m_is_dragging;
   int               m_drag_offset_x;
   int               m_drag_offset_y;
   
   // Modos e Toggles
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
   int               m_parcial_target_pts;
   double            m_parcial_target_cash;
   double            m_parcial_vol_pct;
   
   // Métricas
   double            m_history_profit;
   double            m_history_loss;
   double            m_history_net;
   double            m_floating_pnl;
   
   // Ordem Fantasma
   ENUM_GHOST_TYPE   m_ghost_type;
   bool              m_ghost_aiming;
   double            m_ghost_entry_price;
   double            m_ghost_sl_price;
   double            m_ghost_lot;
   
   void              CreateRectangleLabel(const string name, int x, int y, int w, int h, color bg_color, color border_color, int zorder=ZORDER_PANEL_BG);
   void              CreateButton(const string name, int x, int y, int w, int h, const string text, color bg_color, color txt_color, int font_size=8, bool bold=true);
   void              CreateEdit(const string name, int x, int y, int w, int h, const string text, color bg_color, color txt_color, bool read_only=false);
   void              CreateLabel(const string name, int x, int y, const string text, color txt_color, int font_size=8, bool bold=false);
   
   void              UpdateVisibility();
   void              UpdateFieldValues();
   
   int               m_last_objects_total;
   bool              m_is_rebuilding;

public:
                     CBoletaPanel();
                    ~CBoletaPanel();
   
   bool              Init(const string symbol, ulong magic, ulong slippage, int x=20, int y=40);
   void              Destroy();
   void              Render();
   void              BringToFront();
   void              CheckForegroundState();
   void              UpdateLiveMetrics();
   
   // Getters
   bool              IsDragging()             const { return m_is_dragging; }
   int               GetLastObjectsTotal()    const { return m_last_objects_total; }
   string            GetSymbol()              const { return m_symbol; }
   ENUM_RISK_MODE    GetRiskMode()            const { return m_risk_mode; }
   bool              IsSLActive()             const { return m_sl_active; }
   bool              IsTPActive()             const { return m_tp_active; }
   bool              IsBEActive()             const { return m_be_active; }
   bool              IsTSActive()             const { return m_ts_active; }
   bool              IsParcialActive()        const { return m_parcial_active; }
   bool              IsParcialCashMode()      const { return m_parcial_is_cash; }
   bool              IsParcialMoveBE()        const { return m_parcial_move_be; }
   
   double            GetRiskPercent()         const { return m_risk_percent; }
   double            GetRiskCash()            const { return m_risk_cash; }
   double            GetManualLot()           const { return m_manual_lot; }
   int               GetSLPoints()            const { return m_sl_points; }
   int               GetTPPoints()            const { return m_tp_points; }
   int               GetBEPoints()            const { return m_be_points; }
   int               GetTSPoints()            const { return m_ts_points; }
   int               GetParcialTargetPoints() const { return m_parcial_target_pts; }
   double            GetParcialTargetCash()   const { return m_parcial_target_cash; }
   double            GetParcialVolumePct()    const { return m_parcial_vol_pct; }
   double            GetEffectiveLot();
   
   void              RecalculateRiskLot();
   void              CalculateHistoricalStats();
   
   // Toggles
   void              ToggleMinimize();
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
   
   // Ajustes (+ / -)
   void              AdjustRisk(double delta);
   void              AdjustLot(double delta);
   void              AdjustSL(int delta);
   void              AdjustTP(int delta);
   void              AdjustBE(int delta);
   void              AdjustTS(int delta);
   void              AdjustParcialTarget(double delta);
   void              AdjustParcialVol(double delta);
   
   // Execuções
   void              ExecuteBuy();
   void              ExecuteSell();
   void              ExecuteInvert();
   void              ExecuteHedge();
   void              ExecuteCloseAll();
   void              ExecuteCloseProfit();
   void              ExecuteCloseLoss();
   void              ExecuteCancelPendings();
   void              ExecuteParcialManual();
   
   // Fantasmas
   void              StartGhostOrder(ENUM_GHOST_TYPE type);
   void              UpdateGhostAiming(double price, datetime dt);
   void              LockGhostAiming(double price, datetime dt);
   void              UpdateGhostFromDrag(const string obj_name);
   void              ExecuteGhostOrder();
   void              ClearGhostOrder();
   bool              HasGhostOrder() const { return (m_ghost_type != GHOST_NONE); }
   bool              IsGhostAiming() const { return m_ghost_aiming; }
   
   // Eventos
   void              OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam);
   void              HandleEndEdit(const string &obj_name);
   void              HandleButtonClick(const string &obj_name);
};

//+------------------------------------------------------------------+
//| Construtor                                                       |
//+------------------------------------------------------------------+
CBoletaPanel::CBoletaPanel()
   : m_symbol(""),
     m_magic(123456),
     m_slippage(20),
     m_chart_id(0),
     m_subwin(0),
     m_x(20),
     m_y(40),
     m_width(245),
     m_height(450),
     m_header_h(24),
     m_is_minimized(false),
     m_is_dragging(false),
     m_drag_offset_x(0),
     m_drag_offset_y(0),
     m_risk_mode(RISK_MODE_PERCENT),
     m_hud_period(HUD_PERIOD_TODAY),
     m_sl_active(true),
     m_tp_active(true),
     m_be_active(true),
     m_ts_active(true),
     m_parcial_active(true),
     m_parcial_is_cash(false),
     m_parcial_move_be(true),
     m_risk_percent(1.0),
     m_risk_cash(50.0),
     m_manual_lot(0.01),
     m_sl_points(150),
     m_tp_points(300),
     m_be_points(100),
     m_ts_points(120),
     m_parcial_target_pts(150),
     m_parcial_target_cash(25.0),
     m_parcial_vol_pct(50.0),
     m_history_profit(0.0),
     m_history_loss(0.0),
     m_history_net(0.0),
     m_floating_pnl(0.0),
     m_ghost_type(GHOST_NONE),
     m_ghost_aiming(false),
     m_ghost_entry_price(0.0),
      m_ghost_sl_price(0.0),
      m_ghost_lot(0.01),
      m_last_objects_total(0),
      m_is_rebuilding(false)
{
}

CBoletaPanel::~CBoletaPanel()
{
   Destroy();
}

bool CBoletaPanel::Init(const string symbol, ulong magic, ulong slippage, int x=20, int y=40)
{
   m_chart_id   = ChartID();
   m_subwin     = 0;
   m_symbol     = (symbol != "") ? symbol : _Symbol;
   m_magic      = magic;
   m_slippage   = slippage;
   m_x          = x;
   m_y          = y;
   
   m_risk_mode           = InpDefaultRiskMode;
   m_hud_period          = InpDefaultHudPeriod;
   m_risk_percent        = InpRiskPercent;
   m_risk_cash           = InpRiskCash;
   m_manual_lot          = InpDefaultLot;
   m_sl_active           = InpSLActive;
   m_sl_points           = InpDefaultSL;
   m_tp_active           = InpTPActive;
   m_tp_points           = InpDefaultTP;
   m_be_active           = InpBEActive;
   m_be_points           = InpDefaultBE;
   m_ts_active           = InpTSActive;
   m_ts_points           = InpDefaultTS;
   m_parcial_active      = InpParcialActive;
   m_parcial_is_cash     = InpParcialIsCash;
   m_parcial_target_pts  = InpParcialTargetPts;
   m_parcial_target_cash = InpParcialTargetCash;
   m_parcial_vol_pct     = InpParcialVolumePct;
   m_parcial_move_be     = InpParcialMoveBE;
   
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin <= 0.0) freeMargin = AccountInfoDouble(ACCOUNT_BALANCE);
   
   if(freeMargin > 0.0)
   {
      if(m_risk_mode == RISK_MODE_PERCENT)
         m_risk_cash = freeMargin * (m_risk_percent / 100.0);
      else if(m_risk_mode == RISK_MODE_CASH)
         m_risk_percent = (m_risk_cash / freeMargin) * 100.0;
   }
   
   SymbolSelect(m_symbol, true);
   ChartSetInteger(m_chart_id, CHART_EVENT_MOUSE_MOVE, true);
   ChartSetInteger(m_chart_id, CHART_FOREGROUND, false); // Força gráfico (candles/grid) para segundo plano
   
   m_last_objects_total = ObjectsTotal(m_chart_id, -1, -1);
   m_is_rebuilding      = false;
   
   Render();
   RecalculateRiskLot();
   UpdateLiveMetrics();
   return true;
}

void CBoletaPanel::Destroy()
{
   ObjectsDeleteAll(m_chart_id, PREFIX_GUI);
   ClearGhostOrder();
   ChartRedraw(m_chart_id);
}

void CBoletaPanel::CheckForegroundState()
{
   if(ChartGetInteger(m_chart_id, CHART_FOREGROUND) != 0)
   {
      ChartSetInteger(m_chart_id, CHART_FOREGROUND, false);
      ChartRedraw(m_chart_id);
   }
}

void CBoletaPanel::BringToFront()
{
   if(m_is_rebuilding || m_is_dragging) return;
   m_is_rebuilding = true;
   
   // 1. Força os candles, grade e buffers de indicadores para o plano de fundo
   if(ChartGetInteger(m_chart_id, CHART_FOREGROUND) != 0)
      ChartSetInteger(m_chart_id, CHART_FOREGROUND, false);
   
   // 2. Remove todos os objetos visuais da boleta
   ObjectsDeleteAll(m_chart_id, PREFIX_GUI);
   
   // 3. Recria todos os objetos da boleta na tela com Z-Order / "z-index" máximo (999.999)
   // No MetaTrader 5, a renderização visual é regida estritamente pela ordem de criação.
   // Ao recriar aqui, os objetos da boleta passam a ter a criação mais recente de todo o gráfico,
   // garantindo sobreposição física e visual sobre qualquer indicador, vela ou objeto existente.
   Render();
   
   // 4. Restaura textos e métricas
   UpdateFieldValues();
   UpdateLiveMetrics();
   
   // 5. Atualiza o contador de objetos do watchdog
   m_last_objects_total = ObjectsTotal(m_chart_id, -1, -1);
   
   ChartRedraw(m_chart_id);
   m_is_rebuilding = false;
}

void CBoletaPanel::CreateRectangleLabel(const string name, int x, int y, int w, int h, color bg_color, color border_color, int zorder=ZORDER_PANEL_BG)
{
   string full_name = PREFIX_GUI + name;
   if(ObjectFind(m_chart_id, full_name) < 0)
      ObjectCreate(m_chart_id, full_name, OBJ_RECTANGLE_LABEL, m_subwin, 0, 0);
   
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_XSIZE, w);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_YSIZE, h);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_BGCOLOR, bg_color);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_BORDER_COLOR, border_color);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_BACK, false);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_ZORDER, zorder);
}

void CBoletaPanel::CreateButton(const string name, int x, int y, int w, int h, const string text, color bg_color, color txt_color, int font_size=8, bool bold=true)
{
   string full_name = PREFIX_GUI + name;
   if(ObjectFind(m_chart_id, full_name) < 0)
      ObjectCreate(m_chart_id, full_name, OBJ_BUTTON, m_subwin, 0, 0);
   
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_XSIZE, w);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_YSIZE, h);
   ObjectSetString(m_chart_id, full_name, OBJPROP_TEXT, text);
   ObjectSetString(m_chart_id, full_name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_FONTSIZE, font_size);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_BGCOLOR, bg_color);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_COLOR, txt_color);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_BORDER_COLOR, COLOR_BORDER);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_BACK, false);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_ZORDER, ZORDER_PANEL_CTRL);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_STATE, false);
}

void CBoletaPanel::CreateEdit(const string name, int x, int y, int w, int h, const string text, color bg_color, color txt_color, bool read_only=false)
{
   string full_name = PREFIX_GUI + name;
   if(ObjectFind(m_chart_id, full_name) < 0)
      ObjectCreate(m_chart_id, full_name, OBJ_EDIT, m_subwin, 0, 0);
   
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_XSIZE, w);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_YSIZE, h);
   ObjectSetString(m_chart_id, full_name, OBJPROP_TEXT, text);
   ObjectSetString(m_chart_id, full_name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_ALIGN, ALIGN_CENTER);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_BGCOLOR, bg_color);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_COLOR, txt_color);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_BORDER_COLOR, COLOR_BORDER);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_READONLY, read_only);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_BACK, false);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_ZORDER, ZORDER_PANEL_CTRL);
}

void CBoletaPanel::CreateLabel(const string name, int x, int y, const string text, color txt_color, int font_size=8, bool bold=false)
{
   string full_name = PREFIX_GUI + name;
   if(ObjectFind(m_chart_id, full_name) < 0)
      ObjectCreate(m_chart_id, full_name, OBJ_LABEL, m_subwin, 0, 0);
   
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_YDISTANCE, y);
   ObjectSetString(m_chart_id, full_name, OBJPROP_TEXT, text);
   ObjectSetString(m_chart_id, full_name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_FONTSIZE, font_size);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_COLOR, txt_color);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_BACK, false);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(m_chart_id, full_name, OBJPROP_ZORDER, ZORDER_PANEL_TXT);
}

//+------------------------------------------------------------------+
//| Renderização Principal do Layout                                 |
//+------------------------------------------------------------------+
void CBoletaPanel::Render()
{
   // Força os candles/barras e a grade para o plano de fundo (atrás dos objetos gráficos)
   ChartSetInteger(m_chart_id, CHART_FOREGROUND, false);
   
   int cur_h = m_is_minimized ? m_header_h : m_height;
   
   // 1. Painel de Fundo
   CreateRectangleLabel("Panel_BG", m_x, m_y, m_width, cur_h, COLOR_PANEL_BG, COLOR_BORDER, ZORDER_PANEL_BG);
   CreateRectangleLabel("Header_BG", m_x, m_y, m_width, m_header_h, COLOR_HEADER_BG, COLOR_BORDER, ZORDER_PANEL_STRIP);
   
   // 2. Cabeçalho Limpo (Título + Controles)
   CreateLabel("Header_Title", m_x + 8, m_y + 5, "Boleta Scalp Pro", COLOR_TEXT_MAIN, 9, true);
   CreateButton("Btn_Min", m_x + 195, m_y + 2, 20, 20, m_is_minimized ? "+" : "-", COLOR_EDIT_BG, COLOR_TEXT_MAIN, 9, true);
   CreateButton("Btn_Close", m_x + 219, m_y + 2, 20, 20, "X", COLOR_SELL_BTN, COLOR_TEXT_MAIN, 9, true);
   
   // 3. Barra de Mercado Dedicada (Ativo Completo, Spread e Relógio do Candle)
   int cur_y = m_y + 25;
   CreateRectangleLabel("Strip_Market_BG", m_x + 10, cur_y, 225, 20, COLOR_MARKET_BG, COLOR_BORDER, ZORDER_PANEL_STRIP);
   CreateLabel("Lbl_Mkt_Symbol", m_x + 14, cur_y + 3, m_symbol, clrGold, 8, true);
   CreateLabel("Lbl_Mkt_Spread", m_x + 115, cur_y + 3, "Sp: --", clrWhite, 8, false);
   CreateLabel("Lbl_Mkt_Timer",  m_x + 168, cur_y + 3, "⏳ --:--", clrCyan, 8, true);
   
   // 4. Faixa de Informações e Métricas (HUD com Seletor de Período Clicável)
   cur_y += 22;
   CreateRectangleLabel("Strip_Daily_BG", m_x + 10, cur_y, 225, 20, COLOR_STRIP_BG, COLOR_BORDER, ZORDER_PANEL_STRIP);
   CreateButton("Btn_Hud_Period", m_x + 12, cur_y + 1, 40, 18, "Hoje", COLOR_PERIOD_BTN, clrYellow, 7, true);
   CreateLabel("Lbl_Hud_P1", m_x + 56, cur_y + 3, "+$0.00", COLOR_PROFIT_GREEN, 8, true);
   CreateLabel("Lbl_Hud_P2", m_x + 118, cur_y + 3, "-$0.00", COLOR_LOSS_RED, 8, true);
   CreateLabel("Lbl_Hud_P3", m_x + 180, cur_y + 3, "Líq: $0", clrWhite, 8, true);
   
   // 5. Seção de Risco (Toggle Risco % vs Risco $)
   cur_y += 24;
   bool is_auto_risk = (m_risk_mode != RISK_MODE_MANUAL);
   CreateButton("Chk_Risk", m_x + 10, cur_y + 1, 16, 16, is_auto_risk ? "X" : "", is_auto_risk ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, COLOR_TEXT_MAIN, 8, true);
   
   string risk_toggle_text = (m_risk_mode == RISK_MODE_PERCENT) ? "Risco: %" : "Risco: $";
   color risk_toggle_bg = (m_risk_mode == RISK_MODE_PERCENT) ? COLOR_TOGGLE_PCT : COLOR_TOGGLE_CASH;
   CreateButton("Btn_Risk_Toggle", m_x + 30, cur_y, 95, 18, risk_toggle_text, risk_toggle_bg, COLOR_TEXT_MAIN, 8, true);
   
   CreateButton("Btn_Risk_Dec", m_x + 130, cur_y, 18, 18, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
   string init_risk_str = (m_risk_mode == RISK_MODE_PERCENT) ? DoubleToString(m_risk_percent, 1) : DoubleToString(m_risk_cash, 2);
   CreateEdit("Edit_Risk", m_x + 150, cur_y, 58, 18, init_risk_str, COLOR_EDIT_BG, COLOR_TEXT_MAIN, false);
   CreateButton("Btn_Risk_Inc", m_x + 210, cur_y, 18, 18, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
   
   // Linha 2: Lote
   cur_y += 23;
   int dec = GetLotDecimals(m_symbol);
   CreateLabel("Lbl_Lot", m_x + 30, cur_y + 3, "Lote", COLOR_TEXT_MAIN, 8, false);
   CreateButton("Btn_Lot_Dec", m_x + 130, cur_y, 18, 18, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
   CreateEdit("Edit_Lot", m_x + 150, cur_y, 58, 18, DoubleToString(m_manual_lot, dec), is_auto_risk ? COLOR_EDIT_RO_BG : COLOR_EDIT_BG, is_auto_risk ? clrYellow : COLOR_TEXT_MAIN, is_auto_risk);
   CreateButton("Btn_Lot_Inc", m_x + 210, cur_y, 18, 18, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
   
   // Linha 3: Stop Loss (pts)
   cur_y += 23;
   CreateButton("Chk_SL", m_x + 10, cur_y + 1, 16, 16, m_sl_active ? "X" : "", m_sl_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, COLOR_TEXT_MAIN, 8, true);
   CreateLabel("Lbl_SL", m_x + 30, cur_y + 3, "Stop Loss", COLOR_TEXT_MAIN, 8, false);
   CreateButton("Btn_SL_Dec", m_x + 130, cur_y, 18, 18, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
   CreateEdit("Edit_SL", m_x + 150, cur_y, 58, 18, IntegerToString(m_sl_points), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false);
   CreateButton("Btn_SL_Inc", m_x + 210, cur_y, 18, 18, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
   
   // Linha 4: Take Profit (pts)
   cur_y += 23;
   CreateButton("Chk_TP", m_x + 10, cur_y + 1, 16, 16, m_tp_active ? "X" : "", m_tp_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, COLOR_TEXT_MAIN, 8, true);
   CreateLabel("Lbl_TP", m_x + 30, cur_y + 3, "Take Profit", COLOR_TEXT_MUTED, 8, false);
   CreateButton("Btn_TP_Dec", m_x + 130, cur_y, 18, 18, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
   CreateEdit("Edit_TP", m_x + 150, cur_y, 58, 18, IntegerToString(m_tp_points), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false);
   CreateButton("Btn_TP_Inc", m_x + 210, cur_y, 18, 18, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
   
   // Linha 5: Alvo da Parcial (Toggle Pontos vs $)
   cur_y += 23;
   CreateButton("Chk_Parcial", m_x + 10, cur_y + 1, 16, 16, m_parcial_active ? "X" : "", m_parcial_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, COLOR_TEXT_MAIN, 8, true);
   CreateLabel("Lbl_Parcial", m_x + 30, cur_y + 3, "Alvo Parcial", COLOR_TEXT_MUTED, 8, false);
   string parcial_toggle_text = m_parcial_is_cash ? "$" : "Pts";
   color parcial_toggle_bg = m_parcial_is_cash ? COLOR_TOGGLE_CASH : COLOR_TOGGLE_PCT;
   CreateButton("Btn_Parcial_Toggle", m_x + 94, cur_y, 33, 18, parcial_toggle_text, parcial_toggle_bg, COLOR_TEXT_MAIN, 8, true);
   
   CreateButton("Btn_Parcial_Dec", m_x + 130, cur_y, 18, 18, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
   string init_parcial_target = m_parcial_is_cash ? DoubleToString(m_parcial_target_cash, 2) : IntegerToString(m_parcial_target_pts);
   CreateEdit("Edit_Parcial_Target", m_x + 150, cur_y, 58, 18, init_parcial_target, COLOR_EDIT_BG, COLOR_TEXT_MAIN, false);
   CreateButton("Btn_Parcial_Inc", m_x + 210, cur_y, 18, 18, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
   
   // Linha 6: Volume da Parcial (% da Posição)
   cur_y += 23;
   CreateLabel("Lbl_Parcial_Vol", m_x + 30, cur_y + 3, "Vol. Parcial (%) [P]", COLOR_TEXT_MUTED, 8, false);
   CreateButton("Btn_Parcial_Vol_Dec", m_x + 130, cur_y, 18, 18, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
   CreateEdit("Edit_Parcial_Vol", m_x + 150, cur_y, 58, 18, StringFormat("%.0f%%", m_parcial_vol_pct), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false);
   CreateButton("Btn_Parcial_Vol_Inc", m_x + 210, cur_y, 18, 18, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
   
   // Linha 7: Mover SL para Zero a Zero pós Parcial
   cur_y += 21;
   CreateButton("Chk_Parcial_BE", m_x + 10, cur_y + 1, 16, 16, m_parcial_move_be ? "X" : "", m_parcial_move_be ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, COLOR_TEXT_MAIN, 8, true);
   CreateLabel("Lbl_Parcial_BE", m_x + 30, cur_y + 3, "Mover SL para o zero a zero", COLOR_TEXT_MUTED, 8, false);
   
   // Linha 8: Break Even (pts)
   cur_y += 23;
   CreateButton("Chk_BE", m_x + 10, cur_y + 1, 16, 16, m_be_active ? "X" : "", m_be_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, COLOR_TEXT_MAIN, 8, true);
   CreateLabel("Lbl_BE", m_x + 30, cur_y + 3, "Break Even", COLOR_TEXT_MUTED, 8, false);
   CreateButton("Btn_BE_Dec", m_x + 130, cur_y, 18, 18, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
   CreateEdit("Edit_BE", m_x + 150, cur_y, 58, 18, IntegerToString(m_be_points), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false);
   CreateButton("Btn_BE_Inc", m_x + 210, cur_y, 18, 18, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
   
   // Linha 8: Trailing Stop (pts)
   cur_y += 23;
   CreateButton("Chk_TS", m_x + 10, cur_y + 1, 16, 16, m_ts_active ? "X" : "", m_ts_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, COLOR_TEXT_MAIN, 8, true);
   CreateLabel("Lbl_TS", m_x + 30, cur_y + 3, "Trailing", COLOR_TEXT_MUTED, 8, false);
   CreateButton("Btn_TS_Dec", m_x + 130, cur_y, 18, 18, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
   CreateEdit("Edit_TS", m_x + 150, cur_y, 58, 18, IntegerToString(m_ts_points), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false);
   CreateButton("Btn_TS_Inc", m_x + 210, cur_y, 18, 18, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 8, true);
   
   // 6. Grade de Botões de Ação
   cur_y += 26;
   CreateButton("Btn_Buy", m_x + 10, cur_y, 109, 28, "COMPRAR", COLOR_BUY_BTN, COLOR_TEXT_MAIN, 9, true);
   CreateButton("Btn_Sell", m_x + 126, cur_y, 109, 28, "VENDER", COLOR_SELL_BTN, COLOR_TEXT_MAIN, 9, true);
   
   cur_y += 31;
   CreateButton("Btn_Invert", m_x + 10, cur_y, 109, 25, "INVERTER", COLOR_INVERT_BTN, COLOR_TEXT_MAIN, 9, true);
   CreateButton("Btn_Hedge", m_x + 126, cur_y, 109, 25, "HEDGE [H]", COLOR_HEDGE_BTN, COLOR_TEXT_MAIN, 9, true);
   
   cur_y += 28;
   CreateButton("Btn_CloseAll", m_x + 10, cur_y, 225, 24, "ZERAR TUDO", COLOR_CLOSE_ALL_BTN, clrBlack, 8, true);
   
   cur_y += 26;
   CreateButton("Btn_CloseProfit", m_x + 10, cur_y, 109, 23, "Zerar Lucro", COLOR_CLOSE_PRF_BTN, COLOR_TEXT_MAIN, 8, true);
   CreateButton("Btn_CloseLoss", m_x + 126, cur_y, 109, 23, "Zerar Prej.", COLOR_CLOSE_LSS_BTN, COLOR_TEXT_MAIN, 8, true);
   
   cur_y += 25;
   CreateButton("Btn_CancelPendings", m_x + 10, cur_y, 225, 23, "CANCELAR ORDENS [C]", COLOR_CANCEL_BTN, COLOR_TEXT_MAIN, 8, true);
   
   cur_y += 25;
   CreateButton("Btn_GhostConfirm", m_x + 10, cur_y, 225, 22, HasGhostOrder() ? "[ENTER] Enviar Fantasma" : "FANTASMA: [Up/Dn]", HasGhostOrder() ? COLOR_GHOST_CONFIRM : C'40,40,45', COLOR_TEXT_MAIN, 8, true);
   
   UpdateVisibility();
   ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Cálculo Matemático do Histórico Selecionado                      |
//+------------------------------------------------------------------+
void CBoletaPanel::CalculateHistoricalStats()
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
   
   // P&L Aberto
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

//+------------------------------------------------------------------+
//| Atualização Periódica das Informações em Tempo Real              |
//+------------------------------------------------------------------+
void CBoletaPanel::UpdateLiveMetrics()
{
   // 1. Atualiza Spread e Relógio do Candle na Barra de Mercado
   long spread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
   string tf_name = GetPeriodName(_Period);
   string timer_str = GetCandleTimerString(m_symbol, _Period);
   
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Mkt_Symbol", OBJPROP_TEXT, m_symbol);
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Mkt_Spread", OBJPROP_TEXT, InpShowSpread ? StringFormat("Sp: %d", spread) : "");
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Mkt_Timer",  OBJPROP_TEXT, InpShowCandleTimer ? StringFormat("[%s] %s", tf_name, timer_str) : "");
   
   // 2. Atualiza Estatísticas do Histórico / Carteira
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
   
   // 3. Atualiza Texto do Botão Zerar Tudo com Flutuante
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

void CBoletaPanel::CycleHudPeriod()
{
   if(m_hud_period == HUD_PERIOD_TODAY)
      m_hud_period = HUD_PERIOD_WEEK;
   else if(m_hud_period == HUD_PERIOD_WEEK)
      m_hud_period = HUD_PERIOD_MONTH;
   else if(m_hud_period == HUD_PERIOD_MONTH)
      m_hud_period = HUD_PERIOD_ALL;
   else if(m_hud_period == HUD_PERIOD_ALL)
      m_hud_period = HUD_PERIOD_WALLET;
   else
      m_hud_period = HUD_PERIOD_TODAY;
   
   UpdateLiveMetrics();
}

void CBoletaPanel::UpdateVisibility()
{
   long timeframe_mask = m_is_minimized ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS;
   
   int total = ObjectsTotal(m_chart_id, m_subwin);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(m_chart_id, i, m_subwin);
      if(StringFind(name, PREFIX_GUI) == 0)
      {
         if(name == PREFIX_GUI + "Panel_BG" ||
            name == PREFIX_GUI + "Header_BG" ||
            name == PREFIX_GUI + "Header_Title" ||
            name == PREFIX_GUI + "Btn_Min" ||
            name == PREFIX_GUI + "Btn_Close")
         {
            ObjectSetInteger(m_chart_id, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
         }
         else
         {
            ObjectSetInteger(m_chart_id, name, OBJPROP_TIMEFRAMES, timeframe_mask);
         }
      }
   }
   
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Panel_BG", OBJPROP_YSIZE, m_is_minimized ? m_header_h : m_height);
   ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_Min", OBJPROP_TEXT, m_is_minimized ? "+" : "-");
}

void CBoletaPanel::UpdateFieldValues()
{
   int dec = GetLotDecimals(m_symbol);
   
   // 1. Campo de Risco Unificado
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
   
   // 2. Campo de Lote
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Lot", OBJPROP_TEXT, DoubleToString(m_manual_lot, dec));
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Edit_Lot", OBJPROP_READONLY, is_auto_risk);
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Edit_Lot", OBJPROP_BGCOLOR, is_auto_risk ? COLOR_EDIT_RO_BG : COLOR_EDIT_BG);
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Edit_Lot", OBJPROP_COLOR, is_auto_risk ? clrYellow : COLOR_TEXT_MAIN);
   
   // 3. Stop Loss e Take Profit
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_SL", OBJPROP_TEXT, IntegerToString(m_sl_points));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_SL", OBJPROP_TEXT, m_sl_active ? "X" : "");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_SL", OBJPROP_BGCOLOR, m_sl_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_TP", OBJPROP_TEXT, IntegerToString(m_tp_points));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_TP", OBJPROP_TEXT, m_tp_active ? "X" : "");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_TP", OBJPROP_BGCOLOR, m_tp_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   
   // 4. Parcial: Alvo, Volume e Mover SL 0x0
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
   
   // 5. Break Even e Trailing Stop
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_BE", OBJPROP_TEXT, IntegerToString(m_be_points));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_BE", OBJPROP_TEXT, m_be_active ? "X" : "");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_BE", OBJPROP_BGCOLOR, m_be_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_TS", OBJPROP_TEXT, IntegerToString(m_ts_points));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_TS", OBJPROP_TEXT, m_ts_active ? "X" : "");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_TS", OBJPROP_BGCOLOR, m_ts_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   
   ChartRedraw(m_chart_id);
}

void CBoletaPanel::MovePanel(int new_x, int new_y)
{
   int dx = new_x - m_x;
   int dy = new_y - m_y;
   
   m_x = new_x;
   m_y = new_y;
   
   int total = ObjectsTotal(m_chart_id, m_subwin);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(m_chart_id, i, m_subwin);
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

void CBoletaPanel::ToggleMinimize()
{
   m_is_minimized = !m_is_minimized;
   UpdateVisibility();
   ChartRedraw(m_chart_id);
}

void CBoletaPanel::ToggleRiskAuto()
{
   if(m_risk_mode == RISK_MODE_MANUAL)
   {
      m_risk_mode = RISK_MODE_PERCENT;
      RecalculateRiskLot();
   }
   else
   {
      m_risk_mode = RISK_MODE_MANUAL;
   }
   UpdateFieldValues();
}

void CBoletaPanel::ToggleRiskMode()
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
      m_risk_mode = RISK_MODE_PERCENT;
   }
   
   RecalculateRiskLot();
   UpdateFieldValues();
}

void CBoletaPanel::ToggleSL()
{
   m_sl_active = !m_sl_active;
   if(m_sl_active && m_risk_mode != RISK_MODE_MANUAL) RecalculateRiskLot();
   UpdateFieldValues();
}

void CBoletaPanel::ToggleTP()
{
   m_tp_active = !m_tp_active;
   UpdateFieldValues();
}

void CBoletaPanel::ToggleBE()
{
   m_be_active = !m_be_active;
   UpdateFieldValues();
}

void CBoletaPanel::ToggleTS()
{
   m_ts_active = !m_ts_active;
   UpdateFieldValues();
}

void CBoletaPanel::ToggleParcial()
{
   m_parcial_active = !m_parcial_active;
   UpdateFieldValues();
}

void CBoletaPanel::ToggleParcialMode()
{
   m_parcial_is_cash = !m_parcial_is_cash;
   UpdateFieldValues();
}

void CBoletaPanel::ToggleParcialBE()
{
   m_parcial_move_be = !m_parcial_move_be;
   UpdateFieldValues();
}

void CBoletaPanel::AdjustRisk(double delta)
{
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin <= 0.0) freeMargin = AccountInfoDouble(ACCOUNT_BALANCE);
   
   if(m_risk_mode == RISK_MODE_PERCENT || m_risk_mode == RISK_MODE_MANUAL)
   {
      m_risk_mode = RISK_MODE_PERCENT;
      m_risk_percent += delta;
      if(m_risk_percent < 0.1)  m_risk_percent = 0.1;
      if(m_risk_percent > 50.0) m_risk_percent = 50.0;
      if(freeMargin > 0.0)
         m_risk_cash = freeMargin * (m_risk_percent / 100.0);
   }
   else if(m_risk_mode == RISK_MODE_CASH)
   {
      m_risk_cash += delta;
      if(m_risk_cash < 1.0) m_risk_cash = 1.0;
      if(freeMargin > 0.0)
         m_risk_percent = (m_risk_cash / freeMargin) * 100.0;
   }
   
   RecalculateRiskLot();
   UpdateFieldValues();
}

void CBoletaPanel::AdjustLot(double delta)
{
   m_risk_mode = RISK_MODE_MANUAL;
   m_manual_lot = NormalizeLot(m_manual_lot + delta, m_symbol);
   UpdateFieldValues();
}

void CBoletaPanel::AdjustSL(int delta)
{
   m_sl_points += delta;
   if(m_sl_points < 10) m_sl_points = 10;
   
   if(m_risk_mode != RISK_MODE_MANUAL)
      RecalculateRiskLot();
   UpdateFieldValues();
}

void CBoletaPanel::AdjustTP(int delta)
{
   m_tp_points += delta;
   if(m_tp_points < 0) m_tp_points = 0;
   UpdateFieldValues();
}

void CBoletaPanel::AdjustBE(int delta)
{
   m_be_points += delta;
   if(m_be_points < 0) m_be_points = 0;
   UpdateFieldValues();
}

void CBoletaPanel::AdjustTS(int delta)
{
   m_ts_points += delta;
   if(m_ts_points < 0) m_ts_points = 0;
   UpdateFieldValues();
}

void CBoletaPanel::AdjustParcialTarget(double delta)
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

void CBoletaPanel::AdjustParcialVol(double delta)
{
   m_parcial_vol_pct += delta;
   if(m_parcial_vol_pct < 5.0)  m_parcial_vol_pct = 5.0;
   if(m_parcial_vol_pct > 95.0) m_parcial_vol_pct = 95.0;
   UpdateFieldValues();
}

//+------------------------------------------------------------------+
//| Recálculo Matemático do Lote Dinâmico                            |
//+------------------------------------------------------------------+
void CBoletaPanel::RecalculateRiskLot()
{
   if(m_risk_mode == RISK_MODE_MANUAL || !m_sl_active || m_sl_points <= 0)
      return;
   
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin <= 0.0) freeMargin = AccountInfoDouble(ACCOUNT_BALANCE);
   
   double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   
   if(tickValue <= 0.0)
      tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0.0)
      tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);
   
   if(tickSize > 0.0 && point > 0.0)
   {
      double ptsPerTick = tickSize / point;
      if(ptsPerTick > 0.0)
         tickValue = tickValue / ptsPerTick;
   }
   
   if(tickValue <= 0.0)
      tickValue = 1.0;
   
   double calculated_lot = 0.0;
   double denominator = m_sl_points * tickValue;
   
   if(denominator > 0.0)
   {
      if(m_risk_mode == RISK_MODE_PERCENT)
      {
         // Lote = (Saldo Livre * (Valor_Input / 100)) / (Distância_SL_Pontos * Tick_Value)
         calculated_lot = (freeMargin * (m_risk_percent / 100.0)) / denominator;
      }
      else if(m_risk_mode == RISK_MODE_CASH)
      {
         // Lote = Valor_Input / (Distância_SL_Pontos * Tick_Value)
         calculated_lot = m_risk_cash / denominator;
      }
   }
   
   m_manual_lot = NormalizeLot(calculated_lot, m_symbol);
   int dec = GetLotDecimals(m_symbol);
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Lot", OBJPROP_TEXT, DoubleToString(m_manual_lot, dec));
   ChartRedraw(m_chart_id);
}

double CBoletaPanel::GetEffectiveLot()
{
   return NormalizeLot(m_manual_lot, m_symbol);
}

void CBoletaPanel::StartGhostOrder(ENUM_GHOST_TYPE type)
{
   ClearGhostOrder();
   m_ghost_type   = type;
   m_ghost_aiming = true;
   
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0) point = 0.00001;
   int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   
   int default_dist_pts = (m_sl_points > 0) ? m_sl_points : 100;
   
   if(type == GHOST_BUY)
   {
      m_ghost_entry_price = ask;
      m_ghost_sl_price    = NormalizeDouble(ask - (default_dist_pts * point), digits);
   }
   else if(type == GHOST_SELL)
   {
      m_ghost_entry_price = bid;
      m_ghost_sl_price    = NormalizeDouble(bid + (default_dist_pts * point), digits);
   }
   
   string entry_name = PREFIX_GHOST + "ENTRY";
   string sl_name    = PREFIX_GHOST + "SL";
   string tag_name   = PREFIX_GHOST + "TAG";
   
   ObjectCreate(m_chart_id, entry_name, OBJ_HLINE, 0, 0, m_ghost_entry_price);
   ObjectSetInteger(m_chart_id, entry_name, OBJPROP_COLOR, (type == GHOST_BUY) ? clrDodgerBlue : clrCrimson);
   ObjectSetInteger(m_chart_id, entry_name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(m_chart_id, entry_name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(m_chart_id, entry_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(m_chart_id, entry_name, OBJPROP_SELECTED, false);
   ObjectSetInteger(m_chart_id, entry_name, OBJPROP_BACK, false);
   ObjectSetInteger(m_chart_id, entry_name, OBJPROP_ZORDER, 100);
   ObjectSetString(m_chart_id, entry_name, OBJPROP_TOOLTIP, "Mira da Entrada Fantasma (Mova o mouse e clique para fixar)");
   
   ObjectCreate(m_chart_id, sl_name, OBJ_HLINE, 0, 0, m_ghost_sl_price);
   ObjectSetInteger(m_chart_id, sl_name, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(m_chart_id, sl_name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(m_chart_id, sl_name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(m_chart_id, sl_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(m_chart_id, sl_name, OBJPROP_SELECTED, false);
   ObjectSetInteger(m_chart_id, sl_name, OBJPROP_BACK, false);
   ObjectSetInteger(m_chart_id, sl_name, OBJPROP_ZORDER, 100);
   ObjectSetString(m_chart_id, sl_name, OBJPROP_TOOLTIP, "Stop Loss Fantasma");
   
   datetime cur_time = (datetime)SeriesInfoInteger(m_symbol, _Period, SERIES_LASTBAR_DATE);
   if(cur_time == 0) cur_time = TimeCurrent();
   
   ObjectCreate(m_chart_id, tag_name, OBJ_TEXT, 0, cur_time, m_ghost_entry_price);
   ObjectSetInteger(m_chart_id, tag_name, OBJPROP_COLOR, (type == GHOST_BUY) ? clrCyan : clrCoral);
   ObjectSetInteger(m_chart_id, tag_name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetString(m_chart_id, tag_name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(m_chart_id, tag_name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(m_chart_id, tag_name, OBJPROP_BACK, false);
   ObjectSetInteger(m_chart_id, tag_name, OBJPROP_ZORDER, 105);
   
   UpdateGhostAiming(m_ghost_entry_price, cur_time);
   ChartRedraw(m_chart_id);
}

void CBoletaPanel::UpdateGhostAiming(double price, datetime dt)
{
   if(m_ghost_type == GHOST_NONE) return;
   
   int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0) point = 0.00001;
   
   m_ghost_entry_price = NormalizeDouble(price, digits);
   int dist_pts = (m_sl_points > 0) ? m_sl_points : 100;
   
   if(m_ghost_type == GHOST_BUY)
      m_ghost_sl_price = NormalizeDouble(m_ghost_entry_price - (dist_pts * point), digits);
   else
      m_ghost_sl_price = NormalizeDouble(m_ghost_entry_price + (dist_pts * point), digits);
      
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
   
   string entry_name = PREFIX_GHOST + "ENTRY";
   string sl_name    = PREFIX_GHOST + "SL";
   string tag_name   = PREFIX_GHOST + "TAG";
   
   ObjectMove(m_chart_id, entry_name, 0, 0, m_ghost_entry_price);
   ObjectMove(m_chart_id, sl_name, 0, 0, m_ghost_sl_price);
   
   datetime cur_time = dt;
   if(cur_time <= 0)
   {
      cur_time = (datetime)SeriesInfoInteger(m_symbol, _Period, SERIES_LASTBAR_DATE);
      if(cur_time <= 0) cur_time = TimeCurrent();
   }
   
   int dec = GetLotDecimals(m_symbol);
   string type_str = (m_ghost_type == GHOST_BUY) ? "COMPRA" : "VENDA";
   string risk_label = (m_risk_mode == RISK_MODE_PERCENT) ? StringFormat("%.1f%%", m_risk_percent) : StringFormat("$%.2f", m_risk_cash);
   
   string tag_text = StringFormat(" 🎯 [CLIQUE P/ FIXAR] %s @ %.*f | SL: %.*f (%d pts) | Lote: %.*f | Risco: %s ($%.2f) | [ESC] Cancelar",
                                  type_str, digits, m_ghost_entry_price, digits, m_ghost_sl_price, dist_pts, dec, m_ghost_lot, risk_label, riskMoney);
                                  
   ObjectMove(m_chart_id, tag_name, 0, cur_time, m_ghost_entry_price);
   ObjectSetString(m_chart_id, tag_name, OBJPROP_TEXT, tag_text);
   ObjectSetInteger(m_chart_id, tag_name, OBJPROP_COLOR, (m_ghost_type == GHOST_BUY) ? clrCyan : clrCoral);
   
   string btn_text = StringFormat("MIRA %s: %.*f [CLIQUE]", type_str, digits, m_ghost_entry_price);
   ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_GhostConfirm", OBJPROP_TEXT, btn_text);
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_GhostConfirm", OBJPROP_BGCOLOR, C'180,120,0');
   
   ChartRedraw(m_chart_id);
}

void CBoletaPanel::LockGhostAiming(double price, datetime dt)
{
   if(m_ghost_type == GHOST_NONE) return;
   
   m_ghost_aiming = false;
   
   int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0) point = 0.00001;
   
   if(price > 0.0)
   {
      m_ghost_entry_price = NormalizeDouble(price, digits);
      int dist_pts = (m_sl_points > 0) ? m_sl_points : 100;
      if(m_ghost_type == GHOST_BUY)
         m_ghost_sl_price = NormalizeDouble(m_ghost_entry_price - (dist_pts * point), digits);
      else
         m_ghost_sl_price = NormalizeDouble(m_ghost_entry_price + (dist_pts * point), digits);
   }
   
   string entry_name = PREFIX_GHOST + "ENTRY";
   string sl_name    = PREFIX_GHOST + "SL";
   string tag_name   = PREFIX_GHOST + "TAG";
   
   ObjectMove(m_chart_id, entry_name, 0, 0, m_ghost_entry_price);
   ObjectMove(m_chart_id, sl_name, 0, 0, m_ghost_sl_price);
   
   ObjectSetInteger(m_chart_id, entry_name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(m_chart_id, entry_name, OBJPROP_SELECTED, true);
   ObjectSetInteger(m_chart_id, sl_name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(m_chart_id, sl_name, OBJPROP_SELECTED, true);
   ObjectSetInteger(m_chart_id, tag_name, OBJPROP_COLOR, clrWhite);
   
   UpdateGhostFromDrag(sl_name);
   
   ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_GhostConfirm", OBJPROP_TEXT, "[ENTER] Enviar Fantasma");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_GhostConfirm", OBJPROP_BGCOLOR, COLOR_GHOST_CONFIRM);
   
   PlaySound("ok.wav");
   ChartRedraw(m_chart_id);
}

void CBoletaPanel::UpdateGhostFromDrag(const string obj_name)
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
         // Lote = (Saldo Livre * (Valor_Input / 100)) / (Distância_SL_Pontos * Tick_Value)
         riskMoney = freeMargin * (m_risk_percent / 100.0);
         raw_lot   = riskMoney / denominator;
      }
      else if(m_risk_mode == RISK_MODE_CASH)
      {
         // Lote = Valor_Input / (Distância_SL_Pontos * Tick_Value)
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
   int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   string type_str = (m_ghost_type == GHOST_BUY) ? "BUY PENDENTE" : "SELL PENDENTE";
   string risk_label = (m_risk_mode == RISK_MODE_PERCENT) ? StringFormat("%.1f%%", m_risk_percent) : StringFormat("$%.2f", m_risk_cash);
   string tag_text = StringFormat(" ✅ %s @ %.*f | Lote: %.*f | Dist SL: %d pts | Risco: %s ($%.2f) | [ENTER] Executar", 
                                  type_str, digits, m_ghost_entry_price, dec, m_ghost_lot, dist_pts, risk_label, riskMoney);
   
   ObjectMove(m_chart_id, tag_name, 0, cur_time, m_ghost_entry_price);
   ObjectSetString(m_chart_id, tag_name, OBJPROP_TEXT, tag_text);
   
   m_sl_points  = dist_pts;
   m_manual_lot = m_ghost_lot;
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_SL", OBJPROP_TEXT, IntegerToString(m_sl_points));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Lot", OBJPROP_TEXT, DoubleToString(m_manual_lot, dec));
   
   ChartRedraw(m_chart_id);
}

void CBoletaPanel::ExecuteGhostOrder()
{
   if(!HasGhostOrder()) return;
   
   if(m_ghost_aiming)
      LockGhostAiming(m_ghost_entry_price, TimeCurrent());
   
   CTrade trade;
   trade.SetExpertMagicNumber(m_magic);
   trade.SetDeviationInPoints(m_slippage);
   trade.SetMarginMode();
   SetBestFillingMode(trade, m_symbol);
   
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
   
   bool sent = false;
   if(m_ghost_type == GHOST_BUY)
   {
      if(m_ghost_entry_price < ask)
         sent = trade.BuyLimit(m_ghost_lot, m_ghost_entry_price, m_symbol, sl, tp, ORDER_TIME_GTC, 0, "Scalp Buy Limit");
      else if(m_ghost_entry_price > ask)
         sent = trade.BuyStop(m_ghost_lot, m_ghost_entry_price, m_symbol, sl, tp, ORDER_TIME_GTC, 0, "Scalp Buy Stop");
      else
         sent = trade.Buy(m_ghost_lot, m_symbol, ask, sl, tp, "Scalp Buy Market");
   }
   else if(m_ghost_type == GHOST_SELL)
   {
      if(m_ghost_entry_price > bid)
         sent = trade.SellLimit(m_ghost_lot, m_ghost_entry_price, m_symbol, sl, tp, ORDER_TIME_GTC, 0, "Scalp Sell Limit");
      else if(m_ghost_entry_price < bid)
         sent = trade.SellStop(m_ghost_lot, m_ghost_entry_price, m_symbol, sl, tp, ORDER_TIME_GTC, 0, "Scalp Sell Stop");
      else
         sent = trade.Sell(m_ghost_lot, m_symbol, bid, sl, tp, "Scalp Sell Market");
   }
   
   if(sent)
      PrintFormat("Ordem Fantasma Executada em %s! Ticket: %I64u", m_symbol, trade.ResultOrder());
   else
      PrintFormat("Falha ao Enviar Fantasma em %s: RetCode %u (%s)", m_symbol, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   
   ClearGhostOrder();
   UpdateLiveMetrics();
}

void CBoletaPanel::ClearGhostOrder()
{
   m_ghost_type   = GHOST_NONE;
   m_ghost_aiming = false;
   ObjectsDeleteAll(m_chart_id, PREFIX_GHOST);
   
   ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_GhostConfirm", OBJPROP_TEXT, "FANTASMA: [Up/Dn]");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_GhostConfirm", OBJPROP_BGCOLOR, C'40,40,45');
   ChartRedraw(m_chart_id);
}

void CBoletaPanel::ExecuteBuy()
{
   CTrade trade;
   trade.SetExpertMagicNumber(m_magic);
   trade.SetDeviationInPoints(m_slippage);
   trade.SetMarginMode();
   SetBestFillingMode(trade, m_symbol);
   
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double lot = GetEffectiveLot();
   
   double sl = (m_sl_active && m_sl_points > 0) ? (ask - m_sl_points * point) : 0.0;
   double tp = (m_tp_active && m_tp_points > 0) ? (ask + m_tp_points * point) : 0.0;
   
   trade.Buy(lot, m_symbol, ask, sl, tp, "Boleta Scalp Buy");
   UpdateLiveMetrics();
}

void CBoletaPanel::ExecuteSell()
{
   CTrade trade;
   trade.SetExpertMagicNumber(m_magic);
   trade.SetDeviationInPoints(m_slippage);
   trade.SetMarginMode();
   SetBestFillingMode(trade, m_symbol);
   
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double lot = GetEffectiveLot();
   
   double sl = (m_sl_active && m_sl_points > 0) ? (bid + m_sl_points * point) : 0.0;
   double tp = (m_tp_active && m_tp_points > 0) ? (bid - m_tp_points * point) : 0.0;
   
   trade.Sell(lot, m_symbol, bid, sl, tp, "Boleta Scalp Sell");
   UpdateLiveMetrics();
}

void CBoletaPanel::ExecuteInvert()
{
   CTrade trade;
   trade.SetExpertMagicNumber(m_magic);
   trade.SetDeviationInPoints(m_slippage);
   trade.SetMarginMode();
   SetBestFillingMode(trade, m_symbol);
   
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && pos.Symbol() == m_symbol)
      {
         ENUM_POSITION_TYPE p_type = pos.PositionType();
         double p_vol = pos.Volume();
         ulong ticket = pos.Ticket();
         
         trade.PositionClose(ticket);
         
         if(p_type == POSITION_TYPE_BUY)
         {
            double sl = (m_sl_active && m_sl_points > 0) ? (bid + m_sl_points * point) : 0.0;
            double tp = (m_tp_active && m_tp_points > 0) ? (bid - m_tp_points * point) : 0.0;
            trade.Sell(p_vol, m_symbol, bid, sl, tp, "Inverter para Venda");
         }
         else if(p_type == POSITION_TYPE_SELL)
         {
            double sl = (m_sl_active && m_sl_points > 0) ? (ask - m_sl_points * point) : 0.0;
            double tp = (m_tp_active && m_tp_points > 0) ? (ask + m_tp_points * point) : 0.0;
            trade.Buy(p_vol, m_symbol, ask, sl, tp, "Inverter para Compra");
         }
      }
   }
   UpdateLiveMetrics();
}

void CBoletaPanel::ExecuteHedge()
{
   CTrade trade;
   trade.SetExpertMagicNumber(m_magic);
   trade.SetDeviationInPoints(m_slippage);
   trade.SetMarginMode();
   SetBestFillingMode(trade, m_symbol);
   
   CPositionInfo pos;
   double total_buy_vol = 0.0;
   double total_sell_vol = 0.0;
   
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
      trade.Sell(lot_to_hedge, m_symbol, bid, 0, 0, "Hedge Trava Compra");
      PrintFormat("Hedge Ativado em %s: Vendido %.2f para zerar delta.", m_symbol, lot_to_hedge);
   }
   else if(net_exposure < -0.00001)
   {
      double lot_to_hedge = NormalizeLot(MathAbs(net_exposure), m_symbol);
      trade.Buy(lot_to_hedge, m_symbol, ask, 0, 0, "Hedge Trava Venda");
      PrintFormat("Hedge Ativado em %s: Comprado %.2f para zerar delta.", m_symbol, lot_to_hedge);
   }
   else if(total_buy_vol > 0.0 && total_sell_vol > 0.0)
   {
      Alert(StringFormat("O ativo %s já está 100%% hedged (Volume Comprado = Volume Vendido)!", m_symbol));
   }
   else
   {
      double lot = GetEffectiveLot();
      trade.Buy(lot, m_symbol, ask, 0, 0, "Hedge Duplo Buy");
      trade.Sell(lot, m_symbol, bid, 0, 0, "Hedge Duplo Sell");
      PrintFormat("Hedge Duplo Aberto em %s: Buy %.2f e Sell %.2f simultâneos.", m_symbol, lot, lot);
   }
   UpdateLiveMetrics();
}

void CBoletaPanel::ExecuteCloseAll()
{
   CTrade trade;
   trade.SetExpertMagicNumber(m_magic);
   SetBestFillingMode(trade, m_symbol);
   
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && pos.Symbol() == m_symbol)
         trade.PositionClose(pos.Ticket());
   }
   COrderInfo ord;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(ord.SelectByIndex(i) && ord.Symbol() == m_symbol)
         trade.OrderDelete(ord.Ticket());
   }
   UpdateLiveMetrics();
}

void CBoletaPanel::ExecuteCloseProfit()
{
   CTrade trade;
   trade.SetExpertMagicNumber(m_magic);
   SetBestFillingMode(trade, m_symbol);
   
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && pos.Symbol() == m_symbol)
      {
         if(pos.Profit() > 0.0)
            trade.PositionClose(pos.Ticket());
      }
   }
   UpdateLiveMetrics();
}

void CBoletaPanel::ExecuteCloseLoss()
{
   CTrade trade;
   trade.SetExpertMagicNumber(m_magic);
   SetBestFillingMode(trade, m_symbol);
   
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && pos.Symbol() == m_symbol)
      {
         if(pos.Profit() < 0.0)
            trade.PositionClose(pos.Ticket());
      }
   }
   UpdateLiveMetrics();
}

void CBoletaPanel::ExecuteCancelPendings()
{
   CTrade trade;
   trade.SetExpertMagicNumber(m_magic);
   SetBestFillingMode(trade, m_symbol);
   
   COrderInfo ord;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(ord.SelectByIndex(i) && ord.Symbol() == m_symbol)
         trade.OrderDelete(ord.Ticket());
   }
   UpdateLiveMetrics();
}

void CBoletaPanel::ExecuteParcialManual()
{
   CTrade trade;
   trade.SetExpertMagicNumber(m_magic);
   SetBestFillingMode(trade, m_symbol);
   
   CPositionInfo pos;
   double min_vol = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   int executed_count = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && pos.Symbol() == m_symbol)
      {
         ulong ticket = pos.Ticket();
         double curVol = pos.Volume();
         double openPrice = pos.PriceOpen();
         
         double close_vol = NormalizeLot(curVol * (m_parcial_vol_pct / 100.0), m_symbol);
         if(close_vol < min_vol) close_vol = min_vol;
         
         if(close_vol >= curVol)
         {
            if(curVol > min_vol)
               close_vol = NormalizeLot(curVol - min_vol, m_symbol);
            else
               close_vol = curVol;
         }
         
         if(close_vol > 0.0)
         {
            if(trade.PositionClosePartial(ticket, close_vol))
            {
               executed_count++;
               MarkPartialExecuted(ticket);
               
               if(m_parcial_move_be)
               {
                  if(pos.SelectByTicket(ticket))
                  {
                     double rem_tp = pos.TakeProfit();
                     trade.PositionModify(ticket, openPrice, rem_tp);
                     PrintFormat("SL movido para o Zero a Zero (0x0) pós Parcial Manual: Ticket #%I64u | Novo SL: %.5f", ticket, openPrice);
                  }
               }
               PrintFormat("PARCIAL MANUAL EXECUTADA (Tecla P): Ticket #%I64u | Vol: %.2f (%.1f%%)", ticket, close_vol, m_parcial_vol_pct);
            }
         }
      }
   }
   
   if(executed_count > 0)
   {
      UpdateLiveMetrics();
      ChartRedraw(m_chart_id);
   }
   else
   {
      PrintFormat("Nenhuma posição aberta em %s para parcial manual.", m_symbol);
   }
}

void CBoletaPanel::HandleEndEdit(const string &obj_name)
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
   
   UpdateFieldValues();
}

void CBoletaPanel::HandleButtonClick(const string &obj_name)
{
   string short_name = obj_name;
   StringReplace(short_name, PREFIX_GUI, "");
   ObjectSetInteger(m_chart_id, obj_name, OBJPROP_STATE, false);
   
   if(short_name == "Btn_Min")            { ToggleMinimize(); return; }
   if(short_name == "Btn_Close")          { Destroy(); ExpertRemove(); return; }
   
   // Alternância de Período do HUD (Hoje, 7D, 30D, Tudo, Saldo)
   if(short_name == "Btn_Hud_Period")     { CycleHudPeriod(); return; }
   
   // Toggle de Ativação Automática do Risco e Alternância % vs $
   if(short_name == "Chk_Risk")           { ToggleRiskAuto(); return; }
   if(short_name == "Btn_Risk_Toggle")    { ToggleRiskMode(); return; }
   
   // Toggles Operacionais
   if(short_name == "Chk_SL")             { ToggleSL(); return; }
   if(short_name == "Chk_TP")             { ToggleTP(); return; }
   if(short_name == "Chk_BE")             { ToggleBE(); return; }
   if(short_name == "Chk_TS")             { ToggleTS(); return; }
   if(short_name == "Chk_Parcial")        { ToggleParcial(); return; }
   if(short_name == "Btn_Parcial_Toggle") { ToggleParcialMode(); return; }
   if(short_name == "Chk_Parcial_BE")     { ToggleParcialBE(); return; }
   
   // Steppers de Risco (+ / -)
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
   if(short_name == "Btn_Lot_Dec")        { AdjustLot(-lot_step); return; }
   if(short_name == "Btn_Lot_Inc")        { AdjustLot(lot_step); return; }
   
   if(short_name == "Btn_SL_Dec")         { AdjustSL(-InpStepPoints); return; }
   if(short_name == "Btn_SL_Inc")         { AdjustSL(InpStepPoints); return; }
   
   if(short_name == "Btn_TP_Dec")         { AdjustTP(-InpStepPoints); return; }
   if(short_name == "Btn_TP_Inc")         { AdjustTP(InpStepPoints); return; }
   
   // Steppers da Parcial
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
   if(short_name == "Btn_Parcial_Vol_Dec") { AdjustParcialVol(-InpStepParcialVol); return; }
   if(short_name == "Btn_Parcial_Vol_Inc") { AdjustParcialVol(InpStepParcialVol); return; }
   
   if(short_name == "Btn_BE_Dec")         { AdjustBE(-InpStepPoints); return; }
   if(short_name == "Btn_BE_Inc")         { AdjustBE(InpStepPoints); return; }
   
   if(short_name == "Btn_TS_Dec")         { AdjustTS(-InpStepPoints); return; }
   if(short_name == "Btn_TS_Inc")         { AdjustTS(InpStepPoints); return; }
   
   // Ações Operacionais
   if(short_name == "Btn_Buy")            { ExecuteBuy(); return; }
   if(short_name == "Btn_Sell")           { ExecuteSell(); return; }
   if(short_name == "Btn_Invert")         { ExecuteInvert(); return; }
   if(short_name == "Btn_Hedge")          { ExecuteHedge(); return; }
   if(short_name == "Btn_CloseAll")       { ExecuteCloseAll(); return; }
   if(short_name == "Btn_CloseProfit")    { ExecuteCloseProfit(); return; }
   if(short_name == "Btn_CloseLoss")      { ExecuteCloseLoss(); return; }
   if(short_name == "Btn_CancelPendings") { ExecuteCancelPendings(); return; }
   
   if(short_name == "Btn_GhostConfirm")
   {
      if(HasGhostOrder())
      {
         if(m_ghost_aiming)
            LockGhostAiming(m_ghost_entry_price, TimeCurrent());
         else
            ExecuteGhostOrder();
      }
      else
      {
         StartGhostOrder(GHOST_BUY);
      }
      return;
   }
}

void CBoletaPanel::OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
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
      {
         HandleButtonClick(sparam);
         return;
      }
      
      // Se clicou em outro objeto no gráfico enquanto mirava a ordem fantasma, fixa no local
      if(m_ghost_aiming)
      {
         LockGhostAiming(m_ghost_entry_price, TimeCurrent());
         return;
      }
      return;
   }
   
   if(id == CHARTEVENT_CLICK)
   {
      if(m_ghost_aiming)
      {
         int mouse_x = (int)lparam;
         int mouse_y = (int)dparam;
         int cur_h = m_is_minimized ? m_header_h : m_height;
         bool on_panel = (mouse_x >= m_x && mouse_x <= m_x + m_width &&
                          mouse_y >= m_y && mouse_y <= m_y + cur_h);
         if(!on_panel)
         {
            datetime dt = 0;
            double price = 0.0;
            int subw = 0;
            if(ChartXYToTimePrice(m_chart_id, mouse_x, mouse_y, subw, dt, price))
            {
               if(price > 0.0)
               {
                  LockGhostAiming(price, dt);
                  return;
               }
            }
            LockGhostAiming(m_ghost_entry_price, TimeCurrent());
            return;
         }
      }
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
      
      int cur_h = m_is_minimized ? m_header_h : m_height;
      bool on_panel = (mouse_x >= m_x && mouse_x <= m_x + m_width &&
                       mouse_y >= m_y && mouse_y <= m_y + cur_h);
      
      // 1. Rastreamento da mira do mouse para Ordem Fantasma
      if(m_ghost_aiming && !m_is_dragging && !on_panel)
      {
         datetime dt = 0;
         double price = 0.0;
         int subw = 0;
         if(ChartXYToTimePrice(m_chart_id, mouse_x, mouse_y, subw, dt, price))
         {
            if(price > 0.0)
               UpdateGhostAiming(price, dt);
         }
      }
      
      // 2. Arraste do Cabeçalho do Painel
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
            BringToFront(); // Garante sobreposição no topo absoluto ao soltar o painel
         }
         m_is_dragging = false;
      }
      return;
   }
   
   if(id == CHARTEVENT_OBJECT_CREATE || id == CHARTEVENT_OBJECT_CHANGE)
   {
      // Se um objeto foi criado ou modificado no gráfico por um indicador ou usuário (não pela boleta),
      // trazemos imediatamente a boleta para a frente para cobri-lo com z-index máximo!
      if(StringFind(sparam, PREFIX_GUI) != 0 && StringFind(sparam, PREFIX_GHOST) != 0)
      {
         BringToFront();
      }
      return;
   }
   
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      // Se o usuário alternar templates, timeframes ou configurações do gráfico (F8),
      // garante que a boleta seja reconstruída no topo absoluto da tela.
      BringToFront();
      return;
   }
   
   if(id == CHARTEVENT_KEYDOWN)
   {
      if(lparam == 72 || lparam == 104) { ExecuteHedge(); return; }          // H
      if(lparam == 67 || lparam == 99)  { ExecuteCancelPendings(); return; } // C
      if(lparam == 77 || lparam == 109) { ToggleMinimize(); return; }        // M
      if(lparam == 80 || lparam == 112) { ExecuteParcialManual(); return; }  // P
      if(lparam == 38) { StartGhostOrder(GHOST_BUY); return; }               // Seta Cima
      if(lparam == 40) { StartGhostOrder(GHOST_SELL); return; }              // Seta Baixo
      if(lparam == 13) { if(HasGhostOrder()) ExecuteGhostOrder(); return; }  // Enter
      if(lparam == 27) { if(HasGhostOrder()) ClearGhostOrder(); return; }    // ESC
   }
}

//+------------------------------------------------------------------+
//| Instância Global do Painel                                       |
//+------------------------------------------------------------------+
CBoletaPanel g_panel;

//+------------------------------------------------------------------+
//| Controle de Execução de Parciais (Impede repetição por posição)  |
//+------------------------------------------------------------------+
ulong g_partial_tickets[];

bool IsPartialExecuted(ulong ticket)
{
   int total = ArraySize(g_partial_tickets);
   for(int i = 0; i < total; i++)
   {
      if(g_partial_tickets[i] == ticket)
         return true;
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
//| Gestão de Posições (Parciais, Break Even & Trailing Stop)        |
//+------------------------------------------------------------------+
void GerenciarPosicoesAbertas()
{
   bool be_active       = g_panel.IsBEActive();
   bool ts_active       = g_panel.IsTSActive();
   bool parcial_active  = g_panel.IsParcialActive();
   
   if(!be_active && !ts_active && !parcial_active)
      return;
   
   int be_pts           = g_panel.GetBEPoints();
   int ts_pts           = g_panel.GetTSPoints();
   bool parcial_is_cash = g_panel.IsParcialCashMode();
   int parcial_pts      = g_panel.GetParcialTargetPoints();
   double parcial_cash  = g_panel.GetParcialTargetCash();
   double parcial_pct   = g_panel.GetParcialVolumePct();
   
   string sym = g_panel.GetSymbol();
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
      
      // =================================================================
      // 1. EXECUÇÃO DA PARCIAL (Pontos vs Financeiro $)
      // =================================================================
      if(parcial_active && !IsPartialExecuted(ticket))
      {
         bool atingiu_parcial = false;
         
         if(parcial_is_cash)
         {
            // Alvo em $ (Financeiro Líquido: Profit + Swap + Commission)
            double lucro_liquido = pos.Profit() + pos.Swap() + pos.Commission();
            if(parcial_cash > 0.0 && lucro_liquido >= parcial_cash)
               atingiu_parcial = true;
         }
         else
         {
            // Alvo em Pontos (Distância entre Preço Atual e POSITION_PRICE_OPEN)
            if(parcial_pts > 0)
            {
               if(posType == POSITION_TYPE_BUY)
               {
                  double dist_pts = (bid - openPrice) / point;
                  if(dist_pts >= parcial_pts)
                     atingiu_parcial = true;
               }
               else if(posType == POSITION_TYPE_SELL)
               {
                  double dist_pts = (openPrice - ask) / point;
                  if(dist_pts >= parcial_pts)
                     atingiu_parcial = true;
               }
            }
         }
         
         if(atingiu_parcial)
         {
            double close_vol = NormalizeLot(curVol * (parcial_pct / 100.0), sym);
            double min_vol = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
            if(close_vol < min_vol) close_vol = min_vol;
            
            // Garantir que não fecha além do volume existente
            if(close_vol >= curVol)
            {
               if(curVol > min_vol)
                  close_vol = NormalizeLot(curVol - min_vol, sym);
               else
                  close_vol = curVol;
            }
            
            if(close_vol > 0.0)
            {
               if(trade.PositionClosePartial(ticket, close_vol))
               {
                  MarkPartialExecuted(ticket);
                  
                  // Se o checkbox 'Mover SL para o zero a zero' estiver marcado:
                  if(g_panel.IsParcialMoveBE())
                  {
                     if(pos.SelectByTicket(ticket))
                     {
                        double rem_sl = pos.StopLoss();
                        double rem_tp = pos.TakeProfit();
                        bool need_modify = false;
                        
                        if(posType == POSITION_TYPE_BUY)
                        {
                           if(rem_sl < openPrice)
                              need_modify = true;
                        }
                        else if(posType == POSITION_TYPE_SELL)
                        {
                           if(rem_sl == 0.0 || rem_sl > openPrice)
                              need_modify = true;
                        }
                        
                        if(need_modify)
                        {
                           if(trade.PositionModify(ticket, openPrice, rem_tp))
                           {
                              PrintFormat("SL movido para o Zero a Zero (0x0) pós Parcial: Ticket #%I64u | Novo SL: %.5f", ticket, openPrice);
                           }
                           else
                           {
                              PrintFormat("Falha ao mover SL p/ 0x0 no Ticket #%I64u: RetCode %u (%s)", 
                                          ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
                           }
                        }
                     }
                  }
                  PrintFormat("PARCIAL EXECUTADA COM SUCESSO: Ticket #%I64u | Vol: %.2f (%.1f%%) | Alvo: %s",
                              ticket, close_vol, parcial_pct, 
                              parcial_is_cash ? StringFormat("$%.2f", parcial_cash) : StringFormat("%d pts", parcial_pts));
               }
            }
         }
      }
      
      // =================================================================
      // 2. BREAK EVEN & TRAILING STOP (BUY)
      // =================================================================
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
         else
         {
            be_atingido = true;
         }
         
         if(ts_active && ts_pts > 0 && be_atingido)
         {
            double desired_sl = bid - (ts_pts * point);
            if(desired_sl >= openPrice)
            {
               if(curSL == 0.0 || desired_sl > curSL + (point * 2.0))
               {
                  trade.PositionModify(ticket, desired_sl, curTP);
               }
            }
         }
      }
      // =================================================================
      // 3. BREAK EVEN & TRAILING STOP (SELL)
      // =================================================================
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
         else
         {
            be_atingido = true;
         }
         
         if(ts_active && ts_pts > 0 && be_atingido)
         {
            double desired_sl = ask + (ts_pts * point);
            if(desired_sl <= openPrice)
            {
               if(curSL == 0.0 || desired_sl < curSL - (point * 2.0))
               {
                  trade.PositionModify(ticket, desired_sl, curTP);
               }
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
   // Força o gráfico (candles, wicks e grade) para o segundo plano
   ChartSetInteger(ChartID(), CHART_FOREGROUND, false);
   ChartSetInteger(ChartID(), CHART_EVENT_MOUSE_MOVE, true);
   
   if(!g_panel.Init(InpSymbol, InpMagicNumber, InpSlippage, InpPanelX, InpPanelY))
   {
      Print("Erro ao inicializar Boleta Scalping Pro v7.20!");
      return INIT_FAILED;
   }
   
   // Timer de 1 segundo para atualizar o relógio do candle com fluidez
   EventSetTimer(1);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Evento: OnDeinit                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   g_panel.Destroy();
}

//+------------------------------------------------------------------+
//| Evento: OnTimer                                                  |
//+------------------------------------------------------------------+
void OnTimer()
{
   g_panel.CheckForegroundState();
   
   // Watchdog: se algum indicador criou objetos no gráfico silenciosamente, traz o painel para a frente
   int cur_objs = ObjectsTotal(ChartID(), -1, -1);
   if(cur_objs != g_panel.GetLastObjectsTotal() && !g_panel.IsDragging())
   {
      g_panel.BringToFront();
   }
   
   g_panel.UpdateLiveMetrics();
}

//+------------------------------------------------------------------+
//| Evento: OnTick                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
   g_panel.CheckForegroundState();
   
   // Watchdog dinâmico por tick
   int cur_objs = ObjectsTotal(ChartID(), -1, -1);
   if(cur_objs != g_panel.GetLastObjectsTotal() && !g_panel.IsDragging())
   {
      g_panel.BringToFront();
   }
   
   g_panel.UpdateLiveMetrics();
   GerenciarPosicoesAbertas();
}

//+------------------------------------------------------------------+
//| Evento: OnChartEvent                                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   g_panel.OnChartEvent(id, lparam, dparam, sparam);
}
//+------------------------------------------------------------------+
