//+------------------------------------------------------------------+
//|                                  BoletaScalpingComCanaisV10.mq5  |
//|                             Copyright 2026, ViniBurgo Developer  |
//|    Boleta Scalping Pro & Risco + Canais 40x40 + Ultra-Fast Speed |
//+------------------------------------------------------------------+
#property copyright "Senior MQL5 Developer"
#property link      "https://www.mql5.com"
#property version   "10.60"
#property description "Boleta Scalping Pro v10.60: Risco $150 Desmarcado, Zerar Todas no Rodape, Parcial Compacta e 4 Metricas HUD"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//| Paleta Dark Mode Institucional e Assertiva                       |
//+------------------------------------------------------------------+
#define COLOR_PANEL_BG        C'18,21,27'    // Slate Obsidian Fundo Principal
#define COLOR_HEADER_BG       C'13,15,20'    // Grafite Profundo Cabecalho
#define COLOR_MARKET_BG       C'24,28,36'    // Faixa Ativo & Spread
#define COLOR_CARD_BG         C'25,30,40'    // Cartao HUD Metricas
#define COLOR_CARD_BORDER     C'38,45,60'    // Borda Sutil HUD
#define COLOR_SECTION_BG      C'22,26,34'    // Fundo Gaveta Canais
#define COLOR_BORDER          C'42,48,64'    // Borda Principal
#define COLOR_TEXT_MAIN       C'245,248,252' // Texto Primario Branco Puro
#define COLOR_TEXT_MUTED      C'155,162,178' // Texto Secundario Suave
#define COLOR_EDIT_BG         C'28,33,44'    // Campo de Edicao
#define COLOR_EDIT_RO_BG      C'38,42,54'    // Campo Read-Only
#define COLOR_CHECK_ACTIVE    C'0,195,105'   // Check Ativo Verde Emerald Institucional
#define COLOR_CHECK_INACT     C'50,55,68'    // Check Inativo Cinza Grafite
#define COLOR_STEP_BTN        C'44,50,65'    // Botoes Steppers (- / +)
#define COLOR_DRAWER_BTN      C'30,42,58'    // Gaveta de Canais
#define COLOR_CHAN_START      C'28,60,95'    // Botao Marcar Manual (Azul Safira)
#define COLOR_CHAN_PROJ       C'20,105,70'   // Botao Projetar (Verde Esmeralda)
#define COLOR_BUY_BTN         C'0,175,90'    // Compra Emerald Fluido
#define COLOR_SELL_BTN        C'215,38,50'   // Venda Coral Crimson
#define COLOR_INVERT_BTN      C'195,110,18'  // Inverter Ambar
#define COLOR_CLOSE_ALL_BTN   C'240,242,250' // Zerar Todas Prata Platina Destaque
#define COLOR_CLOSE_PRF_BTN   C'25,125,65'   // Zerar Lucro Verde Escuro
#define COLOR_CLOSE_LSS_BTN   C'145,35,42'   // Zerar Prejuizo Vermelho Escuro
#define COLOR_PROFIT_GREEN    C'0,225,115'   // Verde Lucro
#define COLOR_LOSS_RED        C'255,75,75'   // Vermelho Prejuizo
#define COLOR_LOT_GOLD        C'255,200,50'  // Ambar Dourado Lote
#define COLOR_TOGGLE_PCT      C'32,75,140'   // Modo Risco %
#define COLOR_TOGGLE_CASH     C'20,115,80'   // Modo Risco $

//--- Prefixos de Objetos Graficos
#define PREFIX_GUI         "BSCALP_GUI_"
#define PREFIX_CANAL_LINES "BSCALP_CLINE_"
#define PREFIX_CANAL_TEMP  "BSCALP_CTEMP_"

//--- Camadas Z-Order
#define ZORDER_PANEL_BG      1000000
#define ZORDER_PANEL_STRIP   1000010
#define ZORDER_PANEL_CTRL    1000020
#define ZORDER_PANEL_TXT     1000030

//--- Enumeradores
enum ENUM_RISK_MODE
{
   RISK_MODE_MANUAL,   // Lote Fixo Manual (Padrao Desmarcado)
   RISK_MODE_CASH,     // Risco por Valor Financeiro Fixo ($150)
   RISK_MODE_PERCENT   // Risco por Porcentagem da Conta (%)
};

//+------------------------------------------------------------------+
//| Parametros de Entrada (.SET / CONFIGURACAO NATIVA)               |
//+------------------------------------------------------------------+
input group "=== CONFIGURACAO DO ATIVO & ROTEAMENTO ==="
input string          InpSymbol            = "";                 // Ativo Operado (Vazio = Grafico Atual)
input ulong           InpMagicNumber       = 123456;             // Magic Number das Ordens
input ulong           InpSlippage          = 20;                 // Desvio Maximo / Slippage (pontos)
input bool            InpFilterSymbolOnly  = true;               // Filtrar Metricas apenas deste Ativo

input group "=== GESTAO DE LOTE & RISCO ($150 DESMARCADO) ==="
input ENUM_RISK_MODE  InpDefaultRiskMode   = RISK_MODE_MANUAL;   // Modo de Risco Inicial (Manual Desmarcado)
input double          InpRiskCash          = 150.0;              // Risco Financeiro ($150 Nativo do Set)
input double          InpDefaultLot        = 0.04;               // Lote Operacional Nativo do Set
input double          InpRiskPercent       = 1.0;                // Risco Percentual Inicial (%) se ativado

input group "=== ALVOS NATIVOS DO SET (SL 200 PTS / TP 300 PTS) ==="
input bool            InpSLActive          = true;               // Stop Loss Inicial (Ativo por Padrao no Set)
input int             InpDefaultSL         = 200;                // Stop Loss Nativo do Set (pontos)
input bool            InpTPActive          = true;               // Take Profit Inicial (Ativo por Padrao no Set)
input int             InpDefaultTP         = 300;                // Take Profit Nativo do Set (pontos)
input bool            InpLiveSLTPLines     = true;               // Linhas Dinamicas de SL e TP no Grafico (24/7)
input bool            InpSimultaneousTrailing = true;            // Trailing Simultaneo SL & TP (Bracket Movel 24/7)
input bool            InpBEActive          = false;              // Break Even Inicial (Desmarcado por Padrao)
input int             InpDefaultBE         = 60;                 // Break Even Padrao (pontos)
input bool            InpTSActive          = false;              // Trailing Stop Inicial (Desmarcado por Padrao)
input int             InpDefaultTS         = 150;                // Trailing Stop Padrao (pontos)
input int             InpDefaultTSStep     = 2;                  // Passo do Trailing Stop (pontos)

input group "=== ESTILIZACAO DAS LINHAS VISUAIS SL/TP ==="
input color           InpColorLiveTP       = C'34,197,94';       // Cor da Linha Take Profit (Verde Platina)
input ENUM_LINE_STYLE InpStyleLiveTP       = STYLE_DASH;         // Estilo da Linha Take Profit
input int             InpWidthLiveTP       = 1;                  // Espessura da Linha Take Profit (1 a 5)
input color           InpColorLiveSL       = C'239,68,68';       // Cor da Linha Stop Loss (Vermelho Vibrante)
input ENUM_LINE_STYLE InpStyleLiveSL       = STYLE_DASH;         // Estilo da Linha Stop Loss
input int             InpWidthLiveSL       = 1;                  // Espessura da Linha Stop Loss (1 a 5)

input group "=== SUGESTAO DE ALVOS VIA ATR (DESLIGADO POR PADRAO) ==="
input bool            InpEnableATRAlvos    = false;              // Ativar Calculo de Alvos via ATR (Desligado por Padrao)
input ENUM_TIMEFRAMES InpATRTimeframe      = PERIOD_CURRENT;     // Tempo Grafico do ATR
input int             InpATRPeriod         = 14;                 // Periodo do ATR (Barras Fechadas)
input double          InpATRMulSL          = 1.5;                // Multiplicador ATR para Stop Loss
input double          InpATRMulTP          = 2.0;                // Multiplicador ATR para Take Profit
input bool            InpAutoApplyATR      = false;              // Aplicar Automaticamente ATR nos Alvos

input group "=== MODULARIDADE DA BOLETA (ESCOLHA O QUE EXIBIR NO SET) ==="
input bool            InpShowMarketStrip   = true;               // Exibir Faixa de Mercado (Ativo, Spread, Timer)
input bool            InpShowHUDStats      = true;               // Exibir 4 Cartoes HUD (Capital, Lote, Lucro, Win%)
input bool            InpShowRiskSection   = true;               // Exibir Linha de Gestao de Risco ($ / %)
input bool            InpShowLotSection    = true;               // Exibir Linha de Lote Operacional
input bool            InpShowSLSection     = true;               // Exibir Linha de Stop Loss (pts)
input bool            InpShowTPSection     = true;               // Exibir Linha de Take Profit (pts)
input bool            InpShowBESection     = true;               // Exibir Linha de Break Even (pts)
input bool            InpShowTSSection     = true;               // Exibir Linha de Trailing Stop (pts)
input bool            InpShowParcialSection= true;               // Exibir Secao de Realizacao Parcial
input bool            InpShowChannelsSection= true;              // Exibir Gaveta de Canais Manuais (40x40)
input bool            InpShowTradeButtons  = true;               // Exibir Botoes Operacionais (COMPRA e VENDA)
input bool            InpShowInvertButton  = true;               // Exibir Botao Inverter Posicao
input bool            InpShowCloseButtons  = true;               // Exibir Botoes Zerar Lucro / Zerar Prejuizo
input bool            InpShowCloseAll      = true;               // Exibir Botao Zerar Todas as Ordens (Rodape)

input group "=== REALIZACAO PARCIAL ==="
input bool            InpParcialActive     = false;              // Parcial Inicial (Desmarcado por Padrao)
input bool            InpParcialIsCash     = false;              // Modo Alvo Parcial (false = Pontos, true = $)
input int             InpParcialTargetPts  = 150;                // Alvo da Parcial Padrao (pontos)
input double          InpParcialTargetCash = 25.0;               // Alvo da Parcial Padrao ($)
input double          InpParcialVolumePct  = 50.0;               // Volume da Parcial (% da Posicao)
input bool            InpParcialMoveBE     = true;               // Mover SL p/ Zero a Zero pos Parcial

input group "=== CANAIS DE FREQUENCIA MANUAL (40 CIMA / 40 BAIXO) ==="
input int             InpProjUp            = 40;                 // Canais padrao para CIMA (Salvo em 40)
input int             InpProjDown          = 40;                 // Canais padrao para BAIXO (Salvo em 40)
input bool            InpCanalPushAlert    = true;               // Notificacao Push no Rompimento
input bool            InpCanalScreenAlert  = true;               // Alerta Sonoro / Pop-up no Rompimento
input color           InpColorChannel      = C'220,50,50';       // Cor das Linhas Principais
input color           InpColorChannelMid   = C'235,185,40';      // Cor das Linhas Medias (50%)

input group "=== INCREMENTOS DOS BOTOES (+ / -) ==="
input double          InpStepRiskCash      = 10.0;               // Passo do Risco Fixo ($)
input double          InpStepRiskPct       = 0.5;                // Passo do Risco Percentual (%)
input int             InpStepPoints        = 20;                 // Passo de Pontos (SL, TP, BE, TS, Parcial)
input double          InpStepParcialCash   = 5.0;                // Passo do Alvo Parcial ($)
input double          InpStepParcialVol    = 10.0;               // Passo do Volume Parcial (%)

input group "=== POSICIONAMENTO DA BOLETA ==="
input int             InpPanelX            = 20;                 // Posicao Inicial X no Grafico
input int             InpPanelY            = 40;                 // Posicao Inicial Y no Grafico

//+------------------------------------------------------------------+
//| Primitivos Graficos Otimizados                                   |
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

void GUI_CreateButton(long chart_id, const string full_name, int x, int y, int w, int h, const string text, color bg_color, color txt_color, int font_size=9, bool bold=true, int zorder=ZORDER_PANEL_CTRL)
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

void GUI_CreateEdit(long chart_id, const string full_name, int x, int y, int w, int h, const string text, color bg_color, color txt_color, bool read_only=false, int font_size=9, int zorder=ZORDER_PANEL_CTRL)
{
   if(ObjectFind(chart_id, full_name) < 0)
      ObjectCreate(chart_id, full_name, OBJ_EDIT, 0, 0, 0);
   
   ObjectSetInteger(chart_id, full_name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(chart_id, full_name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(chart_id, full_name, OBJPROP_XSIZE, w);
   ObjectSetInteger(chart_id, full_name, OBJPROP_YSIZE, h);
   ObjectSetString(chart_id, full_name, OBJPROP_TEXT, text);
   ObjectSetString(chart_id, full_name, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(chart_id, full_name, OBJPROP_FONTSIZE, font_size);
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

void GUI_CreateLabel(long chart_id, const string full_name, int x, int y, const string text, color txt_color, int font_size=9, bool bold=false, int zorder=ZORDER_PANEL_TXT)
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
//| Funcoes Utilitarias de Execucao e Formatacao                     |
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
   
   // Modulo de Canais (Estritamente Manual)
   bool              m_channels_expanded;
   int               m_proj_up;
   int               m_proj_down;
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
   int               m_atr_handle;
   int               m_parcial_target_pts;
   double            m_parcial_target_cash;
   double            m_parcial_vol_pct;
   
   // Metricas Live do Painel
   double            m_today_closed_profit;
   double            m_today_closed_loss;
   double            m_today_closed_net;
   double            m_starting_capital;
   double            m_win_rate;
   int               m_today_wins;
   int               m_today_total_closed;
   double            m_floating_pnl;
   
   CTrade            m_trade;
   
   // Persistencia de Estado entre Tempos Graficos
   string            GetStateGV(const string key) const { return "BSCALP_" + IntegerToString(m_chart_id) + "_" + key; }
   void              SaveState();
   bool              LoadState();
   void              ClearState();
   
   // Primitivos Internos
   void              CreateRectangleLabel(const string name, int x, int y, int w, int h, color bg_color, color border_color, int zorder=ZORDER_PANEL_BG);
   void              CreateButton(const string name, int x, int y, int w, int h, const string text, color bg_color, color txt_color, int font_size=9, bool bold=true);
   void              CreateEdit(const string name, int x, int y, int w, int h, const string text, color bg_color, color txt_color, bool read_only=false, int font_size=9);
   void              CreateLabel(const string name, int x, int y, const string text, color txt_color, int font_size=9, bool bold=false);
   
   void              DesenharHLine(const string name, double price, color clr, int style, int width=0, const string desc="");
   void              CriarLinhaTemporaria(const string nome, double price);
   void              SalvarEstadoCanais(double baseTop, double baseBottom, double amp=0.0);
   void              LimparVariaveisGlobaisCanais();

public:
                     CBoletaMaster();
                    ~CBoletaMaster();
   
   bool              Init(const string symbol, ulong magic, ulong slippage, int x=20, int y=40);
   void              Destroy(const int reason=REASON_REMOVE);
   void              Render();
   void              BringToFront();
   void              CheckForegroundState();
   void              EnforceAbsoluteForeground();
   void              UpdateLiveMetrics();
   void              UpdateLiveSLTPLines();
   void              UpdateFieldValues();
   bool              Contains(int x, int y) const;
   
   // Getters Operacionais
   bool              IsDragging()             const { return m_is_dragging; }
   string            GetSymbol()              const { return m_symbol; }
   bool              IsSLActive()             const { return m_sl_active; }
   bool              IsTPActive()             const { return m_tp_active; }
   bool              IsBEActive()             const { return m_be_active; }
   bool              IsTSActive()             const { return m_ts_active; }
   bool              IsParcialActive()        const { return m_parcial_active; }
   bool              IsParcialCashMode()      const { return m_parcial_is_cash; }
   bool              IsParcialMoveBE()        const { return m_parcial_move_be; }
   int               GetSLPoints()            const { return m_sl_points; }
   int               GetTPPoints()            const { return m_tp_points; }
   void              SetSLPoints(int pts)     { m_sl_points = pts; }
   void              SetTPPoints(int pts)     { m_tp_points = pts; }
   bool              GetATRTargets(int &out_atr_pts, int &out_sug_sl, int &out_sug_tp);
   void              ApplyATRTargets();
   int               GetBEPoints()            const { return m_be_points; }
   int               GetTSPoints()            const { return m_ts_points; }
   int               GetTSStepPoints()        const { return m_ts_step_pts; }
   int               GetParcialTargetPoints() const { return m_parcial_target_pts; }
   double            GetParcialTargetCash()   const { return m_parcial_target_cash; }
   double            GetParcialVolumePct()    const { return m_parcial_vol_pct; }
   double            GetEffectiveLot();
   
   void              RecalculateRiskLot();
   void              CalculateDashboardStats();
   
   // Toggles
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
   
   // Acoes de Canais Manuais
   void              StartChannelMarking();
   void              ProjetarCanais();
   void              ToggleChannelVisibility();
   void              LimparCanais();
   void              RestaurarEstadoCanais();
   void              CheckBreakout();
   
   // Execucoes Ultrarrapidas
   void              ExecuteBuy();
   void              ExecuteSell();
   void              ExecuteInvert();
   void              ExecuteCloseAll();
   void              ExecuteCloseProfit();
   void              ExecuteCloseLoss();
   
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
     m_width(276),
     m_height(510),
     m_header_h(28),
     m_is_minimized(false),
     m_is_dragging(false),
     m_drag_offset_x(0),
     m_drag_offset_y(0),
     m_channels_expanded(false),
     m_proj_up(40),
     m_proj_down(40),
     m_chan_step(0),
     m_chan_visible(true),
     m_highest_proj(0.0),
     m_lowest_proj(0.0),
     m_has_projections(false),
     m_alerted_high(false),
     m_alerted_low(false),
     m_last_alert_time(0),
     m_risk_mode(RISK_MODE_MANUAL),
     m_sl_active(false),
     m_tp_active(false),
     m_be_active(false),
     m_ts_active(false),
     m_parcial_active(false),
     m_parcial_is_cash(false),
     m_parcial_move_be(true),
     m_risk_percent(1.0),
     m_risk_cash(150.0),
     m_manual_lot(0.04),
     m_sl_points(200),
     m_tp_points(300),
     m_be_points(60),
     m_ts_points(150),
     m_ts_step_pts(2),
     m_parcial_target_pts(150),
     m_parcial_target_cash(25.0),
     m_parcial_vol_pct(50.0),
     m_today_closed_profit(0.0),
     m_today_closed_loss(0.0),
     m_today_closed_net(0.0),
     m_starting_capital(0.0),
     m_win_rate(0.0),
     m_today_wins(0),
     m_today_total_closed(0),
     m_floating_pnl(0.0),
     m_atr_handle(INVALID_HANDLE)
{
   m_temp_line1 = PREFIX_CANAL_TEMP + "1";
   m_temp_line2 = PREFIX_CANAL_TEMP + "2";
}

CBoletaMaster::~CBoletaMaster()
{
   Destroy(REASON_REMOVE);
}

//+------------------------------------------------------------------+
//| Persistencia de Estado via MT5 GlobalVariables                   |
//+------------------------------------------------------------------+
void CBoletaMaster::SaveState()
{
   string p = "BSCALP_" + IntegerToString(m_chart_id) + "_";
   GlobalVariableSet(p + "saved", 1.0);
   GlobalVariableSet(p + "risk_mode", (double)m_risk_mode);
   GlobalVariableSet(p + "risk_cash", m_risk_cash);
   GlobalVariableSet(p + "risk_pct", m_risk_percent);
   GlobalVariableSet(p + "manual_lot", m_manual_lot);
   GlobalVariableSet(p + "sl_act", m_sl_active ? 1.0 : 0.0);
   GlobalVariableSet(p + "sl_pts", (double)m_sl_points);
   GlobalVariableSet(p + "tp_act", m_tp_active ? 1.0 : 0.0);
   GlobalVariableSet(p + "tp_pts", (double)m_tp_points);
   GlobalVariableSet(p + "be_act", m_be_active ? 1.0 : 0.0);
   GlobalVariableSet(p + "be_pts", (double)m_be_points);
   GlobalVariableSet(p + "ts_act", m_ts_active ? 1.0 : 0.0);
   GlobalVariableSet(p + "ts_pts", (double)m_ts_points);
   GlobalVariableSet(p + "parc_act", m_parcial_active ? 1.0 : 0.0);
   GlobalVariableSet(p + "parc_cash_mode", m_parcial_is_cash ? 1.0 : 0.0);
   GlobalVariableSet(p + "parc_pts", (double)m_parcial_target_pts);
   GlobalVariableSet(p + "parc_cash", m_parcial_target_cash);
   GlobalVariableSet(p + "parc_vol", m_parcial_vol_pct);
   GlobalVariableSet(p + "parc_be", m_parcial_move_be ? 1.0 : 0.0);
   GlobalVariableSet(p + "proj_up", (double)m_proj_up);
   GlobalVariableSet(p + "proj_down", (double)m_proj_down);
   GlobalVariableSet(p + "chan_exp", m_channels_expanded ? 1.0 : 0.0);
   GlobalVariableSet(p + "chan_vis", m_chan_visible ? 1.0 : 0.0);
   GlobalVariableSet(p + "pos_x", (double)m_x);
   GlobalVariableSet(p + "pos_y", (double)m_y);
   GlobalVariableSet(p + "minimized", m_is_minimized ? 1.0 : 0.0);
}

bool CBoletaMaster::LoadState()
{
   string p = "BSCALP_" + IntegerToString(m_chart_id) + "_";
   if(!GlobalVariableCheck(p + "saved")) return false;
   
   if(GlobalVariableCheck(p + "risk_mode"))       m_risk_mode           = (ENUM_RISK_MODE)(int)GlobalVariableGet(p + "risk_mode");
   if(GlobalVariableCheck(p + "risk_cash"))       m_risk_cash           = GlobalVariableGet(p + "risk_cash");
   if(GlobalVariableCheck(p + "risk_pct"))        m_risk_percent        = GlobalVariableGet(p + "risk_pct");
   if(GlobalVariableCheck(p + "manual_lot"))      m_manual_lot          = GlobalVariableGet(p + "manual_lot");
   if(GlobalVariableCheck(p + "sl_act"))          m_sl_active           = (GlobalVariableGet(p + "sl_act") > 0.5);
   if(GlobalVariableCheck(p + "sl_pts"))          m_sl_points           = (int)GlobalVariableGet(p + "sl_pts");
   if(GlobalVariableCheck(p + "tp_act"))          m_tp_active           = (GlobalVariableGet(p + "tp_act") > 0.5);
   if(GlobalVariableCheck(p + "tp_pts"))          m_tp_points           = (int)GlobalVariableGet(p + "tp_pts");
   if(GlobalVariableCheck(p + "be_act"))          m_be_active           = (GlobalVariableGet(p + "be_act") > 0.5);
   if(GlobalVariableCheck(p + "be_pts"))          m_be_points           = (int)GlobalVariableGet(p + "be_pts");
   if(GlobalVariableCheck(p + "ts_act"))          m_ts_active           = (GlobalVariableGet(p + "ts_act") > 0.5);
   if(GlobalVariableCheck(p + "ts_pts"))          m_ts_points           = (int)GlobalVariableGet(p + "ts_pts");
   if(GlobalVariableCheck(p + "parc_act"))        m_parcial_active      = (GlobalVariableGet(p + "parc_act") > 0.5);
   if(GlobalVariableCheck(p + "parc_cash_mode"))  m_parcial_is_cash     = (GlobalVariableGet(p + "parc_cash_mode") > 0.5);
   if(GlobalVariableCheck(p + "parc_pts"))        m_parcial_target_pts  = (int)GlobalVariableGet(p + "parc_pts");
   if(GlobalVariableCheck(p + "parc_cash"))       m_parcial_target_cash = GlobalVariableGet(p + "parc_cash");
   if(GlobalVariableCheck(p + "parc_vol"))        m_parcial_vol_pct     = GlobalVariableGet(p + "parc_vol");
   if(GlobalVariableCheck(p + "parc_be"))         m_parcial_move_be     = (GlobalVariableGet(p + "parc_be") > 0.5);
   if(GlobalVariableCheck(p + "proj_up"))         m_proj_up             = (int)GlobalVariableGet(p + "proj_up");
   if(GlobalVariableCheck(p + "proj_down"))       m_proj_down           = (int)GlobalVariableGet(p + "proj_down");
   if(GlobalVariableCheck(p + "chan_exp"))        m_channels_expanded   = (GlobalVariableGet(p + "chan_exp") > 0.5);
   if(GlobalVariableCheck(p + "chan_vis"))        m_chan_visible        = (GlobalVariableGet(p + "chan_vis") > 0.5);
   if(GlobalVariableCheck(p + "pos_x"))           m_x                   = (int)GlobalVariableGet(p + "pos_x");
   if(GlobalVariableCheck(p + "pos_y"))           m_y                   = (int)GlobalVariableGet(p + "pos_y");
   if(GlobalVariableCheck(p + "minimized"))       m_is_minimized        = (GlobalVariableGet(p + "minimized") > 0.5);
   
   return true;
}

void CBoletaMaster::ClearState()
{
   string p = "BSCALP_" + IntegerToString(m_chart_id) + "_";
   GlobalVariableDel(p + "saved");
   GlobalVariableDel(p + "risk_mode");
   GlobalVariableDel(p + "risk_cash");
   GlobalVariableDel(p + "risk_pct");
   GlobalVariableDel(p + "manual_lot");
   GlobalVariableDel(p + "sl_act");
   GlobalVariableDel(p + "sl_pts");
   GlobalVariableDel(p + "tp_act");
   GlobalVariableDel(p + "tp_pts");
   GlobalVariableDel(p + "be_act");
   GlobalVariableDel(p + "be_pts");
   GlobalVariableDel(p + "ts_act");
   GlobalVariableDel(p + "ts_pts");
   GlobalVariableDel(p + "parc_act");
   GlobalVariableDel(p + "parc_cash_mode");
   GlobalVariableDel(p + "parc_pts");
   GlobalVariableDel(p + "parc_cash");
   GlobalVariableDel(p + "parc_vol");
   GlobalVariableDel(p + "parc_be");
   GlobalVariableDel(p + "proj_up");
   GlobalVariableDel(p + "proj_down");
   GlobalVariableDel(p + "chan_exp");
   GlobalVariableDel(p + "chan_vis");
   GlobalVariableDel(p + "pos_x");
   GlobalVariableDel(p + "pos_y");
   GlobalVariableDel(p + "minimized");
}

//+------------------------------------------------------------------+
//| Inicializacao CBoletaMaster                                      |
//+------------------------------------------------------------------+
bool CBoletaMaster::Init(const string symbol, ulong magic, ulong slippage, int x=20, int y=40)
{
   m_chart_id   = ChartID();
   m_symbol     = (symbol != "") ? symbol : _Symbol;
   m_magic      = magic;
   m_slippage   = slippage;
   m_width      = 276;
   m_header_h   = 28;
   
   if(!LoadState())
   {
      m_x                   = x;
      m_y                   = y;
      m_risk_mode           = InpDefaultRiskMode; // Manual Desmarcado
      m_risk_cash           = InpRiskCash;        // 150.0 Nativo
      m_risk_percent        = InpRiskPercent;
      m_manual_lot          = InpDefaultLot;       // Nativo 0.04
      m_sl_active           = InpSLActive;         // true (ativo nativo do set)
      m_sl_points           = InpDefaultSL;        // Nativo 200 pts
      m_tp_active           = InpTPActive;         // true (ativo nativo do set)
      m_tp_points           = InpDefaultTP;        // Nativo 300 pts
      m_be_active           = InpBEActive;         // false (desmarcado nativo)
      m_be_points           = InpDefaultBE;        // Nativo 60 pts
      m_ts_active           = InpTSActive;         // false (desmarcado nativo)
      m_ts_points           = InpDefaultTS;        // Nativo 150 pts
      m_ts_step_pts         = InpDefaultTSStep;
      m_parcial_active      = InpParcialActive;    // false (desmarcado nativo)
      m_parcial_is_cash     = InpParcialIsCash;
      m_parcial_target_pts  = InpParcialTargetPts;
      m_parcial_target_cash = InpParcialTargetCash;
      m_parcial_vol_pct     = InpParcialVolumePct;
      m_parcial_move_be     = InpParcialMoveBE;
      m_proj_up             = InpProjUp;           // 40
      m_proj_down           = InpProjDown;         // 40
      m_channels_expanded   = false;
      m_chan_visible        = true;
      m_is_minimized        = false;
   }
   
   m_trade.SetExpertMagicNumber(m_magic);
   m_trade.SetDeviationInPoints(m_slippage);
   m_trade.SetMarginMode();
   SetBestFillingMode(m_trade, m_symbol);
   
   if(InpEnableATRAlvos)
   {
      m_atr_handle = iATR(m_symbol, InpATRTimeframe, InpATRPeriod);
      if(m_atr_handle == INVALID_HANDLE)
         Print("[ATR Engine] Falha ao inicializar o handle do ATR!");
   }
   
   SymbolSelect(m_symbol, true);
   ChartSetInteger(m_chart_id, CHART_FOREGROUND, false);
   ChartSetInteger(m_chart_id, CHART_EVENT_MOUSE_MOVE, true);
   ChartSetInteger(m_chart_id, CHART_SHOW_OBJECT_DESCR, true);
   
   Render();
   RestaurarEstadoCanais();
   UpdateFieldValues();
   UpdateLiveMetrics();
   return true;
}

void CBoletaMaster::Destroy(const int reason)
{
   ChartSetInteger(m_chart_id, CHART_CONTEXT_MENU, true);
   ObjectsDeleteAll(m_chart_id, PREFIX_GUI);
   ObjectDelete(m_chart_id, m_temp_line1);
   ObjectDelete(m_chart_id, m_temp_line2);
   
   if(m_atr_handle != INVALID_HANDLE)
   {
      IndicatorRelease(m_atr_handle);
      m_atr_handle = INVALID_HANDLE;
   }
   
   if(reason == REASON_CHARTCHANGE || reason == REASON_RECOMPILE || reason == REASON_PARAMETERS)
   {
      SaveState();
   }
   else if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE)
   {
      ClearState();
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
   if(ChartGetInteger(m_chart_id, CHART_EVENT_MOUSE_MOVE) == 0)
   {
      ChartSetInteger(m_chart_id, CHART_EVENT_MOUSE_MOVE, true);
   }
   EnforceAbsoluteForeground();
}

void CBoletaMaster::BringToFront()
{
   if(m_is_dragging) return;
   if(ChartGetInteger(m_chart_id, CHART_FOREGROUND) != 0)
      ChartSetInteger(m_chart_id, CHART_FOREGROUND, false);
   ChartSetInteger(m_chart_id, CHART_EVENT_MOUSE_MOVE, true);
   
   Render();
   UpdateFieldValues();
   UpdateLiveMetrics();
   EnforceAbsoluteForeground();
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::EnforceAbsoluteForeground()
{
   if(ChartGetInteger(m_chart_id, CHART_FOREGROUND) != 0)
      ChartSetInteger(m_chart_id, CHART_FOREGROUND, false);
      
   int total = ObjectsTotal(m_chart_id, 0);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(m_chart_id, i, 0);
      if(StringFind(name, PREFIX_GUI) == 0)
      {
         if(name == PREFIX_GUI + "Line_Live_TP" || name == PREFIX_GUI + "Line_Live_SL")
         {
            ObjectSetInteger(m_chart_id, name, OBJPROP_BACK, true);
            ObjectSetInteger(m_chart_id, name, OBJPROP_ZORDER, 0);
         }
         else
         {
            ObjectSetInteger(m_chart_id, name, OBJPROP_BACK, false);
            if(name == PREFIX_GUI + "Panel_BG")
               ObjectSetInteger(m_chart_id, name, OBJPROP_ZORDER, ZORDER_PANEL_BG);
            else if(StringFind(name, "_BG") > 0 || StringFind(name, "Strip_") == (int)StringLen(PREFIX_GUI))
               ObjectSetInteger(m_chart_id, name, OBJPROP_ZORDER, ZORDER_PANEL_STRIP);
            else if(StringFind(name, "Lbl_") == (int)StringLen(PREFIX_GUI) || name == PREFIX_GUI + "Header_Title")
               ObjectSetInteger(m_chart_id, name, OBJPROP_ZORDER, ZORDER_PANEL_TXT);
            else
               ObjectSetInteger(m_chart_id, name, OBJPROP_ZORDER, ZORDER_PANEL_CTRL);
         }
      }
      else if(StringFind(name, PREFIX_CANAL_TEMP) == 0 || StringFind(name, PREFIX_CANAL_LINES) == 0)
      {
         ObjectSetInteger(m_chart_id, name, OBJPROP_BACK, true);
         ObjectSetInteger(m_chart_id, name, OBJPROP_ZORDER, 0);
      }
      else
      {
         ENUM_OBJECT otype = (ENUM_OBJECT)ObjectGetInteger(m_chart_id, name, OBJPROP_TYPE);
         if(otype == OBJ_HLINE || otype == OBJ_VLINE || otype == OBJ_TREND || otype == OBJ_CHANNEL || otype == OBJ_RECTANGLE)
         {
            if((bool)ObjectGetInteger(m_chart_id, name, OBJPROP_BACK) == false)
               ObjectSetInteger(m_chart_id, name, OBJPROP_BACK, true);
            if(ObjectGetInteger(m_chart_id, name, OBJPROP_ZORDER) >= ZORDER_PANEL_BG)
               ObjectSetInteger(m_chart_id, name, OBJPROP_ZORDER, 0);
         }
      }
   }
}

void CBoletaMaster::CreateRectangleLabel(const string name, int x, int y, int w, int h, color bg_color, color border_color, int zorder=ZORDER_PANEL_BG)
{
   GUI_CreateRectangleLabel(m_chart_id, PREFIX_GUI + name, x, y, w, h, bg_color, border_color, zorder);
}

void CBoletaMaster::CreateButton(const string name, int x, int y, int w, int h, const string text, color bg_color, color txt_color, int font_size=9, bool bold=true)
{
   GUI_CreateButton(m_chart_id, PREFIX_GUI + name, x, y, w, h, text, bg_color, txt_color, font_size, bold, ZORDER_PANEL_CTRL);
}

void CBoletaMaster::CreateEdit(const string name, int x, int y, int w, int h, const string text, color bg_color, color txt_color, bool read_only=false, int font_size=9)
{
   GUI_CreateEdit(m_chart_id, PREFIX_GUI + name, x, y, w, h, text, bg_color, txt_color, read_only, font_size, ZORDER_PANEL_CTRL);
}

void CBoletaMaster::CreateLabel(const string name, int x, int y, const string text, color txt_color, int font_size=9, bool bold=false)
{
   GUI_CreateLabel(m_chart_id, PREFIX_GUI + name, x, y, text, txt_color, font_size, bold, ZORDER_PANEL_TXT);
}

//+------------------------------------------------------------------+
//| Calculo Exato das 4 Metricas HUD de Confianca                    |
//+------------------------------------------------------------------+
void CBoletaMaster::CalculateDashboardStats()
{
   m_today_closed_profit = 0.0;
   m_today_closed_loss   = 0.0;
   m_today_closed_net    = 0.0;
   m_today_wins          = 0;
   m_today_total_closed  = 0;
   m_floating_pnl        = 0.0;
   
   MqlDateTime dt;
   datetime cur_time = TimeCurrent();
   TimeToStruct(cur_time, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   datetime start_of_day = StructToTime(dt);
   
   if(HistorySelect(start_of_day, cur_time))
   {
      int deals = HistoryDealsTotal();
      for(int i = 0; i < deals; i++)
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
         {
            m_today_closed_profit += total_deal;
            m_today_wins++;
         }
         else
         {
            m_today_closed_loss += total_deal;
         }
         
         m_today_closed_net += total_deal;
         m_today_total_closed++;
      }
   }
   
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   m_starting_capital = bal - m_today_closed_net;
   if(m_starting_capital <= 0.0) m_starting_capital = bal;
   
   if(m_today_total_closed > 0)
      m_win_rate = ((double)m_today_wins / (double)m_today_total_closed) * 100.0;
   else
      m_win_rate = 0.0;
   
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
//| Renderizacao Procedural Dark Mode Moderna e Fluida               |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Motor Causal de Dimensionamento por ATR (Protocolo Sunrise)       |
//+------------------------------------------------------------------+
bool CBoletaMaster::GetATRTargets(int &out_atr_pts, int &out_sug_sl, int &out_sug_tp)
{
   if(!InpEnableATRAlvos) return false;
   if(m_atr_handle == INVALID_HANDLE)
   {
      m_atr_handle = iATR(m_symbol, InpATRTimeframe, InpATRPeriod);
      if(m_atr_handle == INVALID_HANDLE) return false;
   }
   
   double atr_buf[1];
   // Protocolo Sunrise: estritamente barra fechada shift(1) sem lookahead
   if(CopyBuffer(m_atr_handle, 0, 1, 1, atr_buf) <= 0) return false;
   if(atr_buf[0] <= 0.0) return false;
   
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0.0) return false;
   
   out_atr_pts = (int)MathRound(atr_buf[0] / point);
   out_sug_sl  = (int)MathRound((atr_buf[0] * InpATRMulSL) / point);
   out_sug_tp  = (int)MathRound((atr_buf[0] * InpATRMulTP) / point);
   if(out_sug_sl < 10) out_sug_sl = 10;
   if(out_sug_tp < 10) out_sug_tp = 10;
   return true;
}

void CBoletaMaster::ApplyATRTargets()
{
   int atr_p = 0, sug_sl = 0, sug_tp = 0;
   if(GetATRTargets(atr_p, sug_sl, sug_tp))
   {
      m_sl_points = sug_sl;
      m_tp_points = sug_tp;
      UpdateFieldValues();
      UpdateLiveSLTPLines();
      SaveState();
      PrintFormat("[ATR Target Engine] Alvos Volateis Aplicados: SL = %d pts | TP = %d pts (ATR = %d pts)", sug_sl, sug_tp, atr_p);
   }
}

void CBoletaMaster::Render()
{
   ChartSetInteger(m_chart_id, CHART_FOREGROUND, false);
   ObjectsDeleteAll(m_chart_id, PREFIX_GUI);
   
   int row_w    = m_width - 16; // 260px
   int offset_x = m_x + 8;
   
   // 1. Cabecalho Minimalista e Seguro (com fundo opaco solido total imediato)
   int initial_h = m_is_minimized ? m_header_h : (m_height > m_header_h ? m_height : 600);
   CreateRectangleLabel("Panel_BG", m_x, m_y, m_width, initial_h, COLOR_PANEL_BG, COLOR_BORDER, ZORDER_PANEL_BG);
   CreateRectangleLabel("Header_BG", m_x, m_y, m_width, m_header_h, COLOR_HEADER_BG, COLOR_BORDER, ZORDER_PANEL_STRIP);
   CreateLabel("Header_Title", m_x + 10, m_y + 6, "SCALP PRO v10", COLOR_TEXT_MAIN, 10, true);
   CreateButton("Btn_Min", m_x + 224, m_y + 4, 20, 20, m_is_minimized ? "+" : "-", COLOR_EDIT_BG, COLOR_TEXT_MAIN, 9, true);
   CreateButton("Btn_Close", m_x + 248, m_y + 4, 20, 20, "X", COLOR_SELL_BTN, COLOR_TEXT_MAIN, 9, true);
   
   if(m_is_minimized)
   {
      ChartRedraw(m_chart_id);
      return;
   }
   
   int cur_y = m_y + m_header_h + 4;
   
   // 2. Faixa de Mercado (Ativo / Spread / Relogio Candle)
   if(InpShowMarketStrip)
   {
      CreateRectangleLabel("Strip_Market_BG", offset_x, cur_y, row_w, 24, COLOR_MARKET_BG, COLOR_BORDER, ZORDER_PANEL_STRIP);
      CreateLabel("Lbl_Mkt_Symbol", offset_x + 8, cur_y + 4, m_symbol, clrGold, 9, true);
      CreateLabel("Lbl_Mkt_Spread", offset_x + 115, cur_y + 4, "Sp: --", clrWhite, 9, false);
      CreateLabel("Lbl_Mkt_Timer",  offset_x + 180, cur_y + 4, "[TF] --:--", clrCyan, 9, true);
      cur_y += 28;
   }
   
   // 3. Painel HUD de Confianca (4 Metricas Obrigatorias)
   if(InpShowHUDStats)
   {
      int card_w = (row_w - 6) / 2; // 127px
      CreateRectangleLabel("Card_Cap_BG", offset_x, cur_y, card_w, 26, COLOR_CARD_BG, COLOR_CARD_BORDER, ZORDER_PANEL_STRIP);
      CreateLabel("Lbl_Cap_Title", offset_x + 6, cur_y + 1, "CAP. INICIAL", COLOR_TEXT_MUTED, 7, false);
      CreateLabel("Lbl_Cap_Val",   offset_x + 6, cur_y + 11, "$0.00", clrWhite, 9, true);
      
      CreateRectangleLabel("Card_Lot_BG", offset_x + card_w + 6, cur_y, card_w, 26, COLOR_CARD_BG, COLOR_CARD_BORDER, ZORDER_PANEL_STRIP);
      CreateLabel("Lbl_Lot_Title", offset_x + card_w + 12, cur_y + 1, "LOTE ATUAL", COLOR_TEXT_MUTED, 7, false);
      CreateLabel("Lbl_Lot_Val",   offset_x + card_w + 12, cur_y + 11, DoubleToString(m_manual_lot, 2), COLOR_LOT_GOLD, 9, true);
      cur_y += 29;
      
      CreateRectangleLabel("Card_Pnl_BG", offset_x, cur_y, card_w, 26, COLOR_CARD_BG, COLOR_CARD_BORDER, ZORDER_PANEL_STRIP);
      CreateLabel("Lbl_Pnl_Title", offset_x + 6, cur_y + 1, "LUCRO HOJE", COLOR_TEXT_MUTED, 7, false);
      CreateLabel("Lbl_Pnl_Val",   offset_x + 6, cur_y + 11, "$0.00", COLOR_PROFIT_GREEN, 9, true);
      
      CreateRectangleLabel("Card_Win_BG", offset_x + card_w + 6, cur_y, card_w, 26, COLOR_CARD_BG, COLOR_CARD_BORDER, ZORDER_PANEL_STRIP);
      CreateLabel("Lbl_Win_Title", offset_x + card_w + 12, cur_y + 1, "% ACERTOS", COLOR_TEXT_MUTED, 7, false);
      CreateLabel("Lbl_Win_Val",   offset_x + card_w + 12, cur_y + 11, "0.0%", COLOR_CHECK_ACTIVE, 9, true);
      cur_y += 31;
   }
   
   // 4. Secao Gestao de Risco (Risco $150 Desmarcado por Padrao)
   if(InpShowRiskSection)
   {
      bool is_auto_risk = (m_risk_mode != RISK_MODE_MANUAL);
      CreateButton("Chk_Risk", offset_x, cur_y + 1, 18, 18, is_auto_risk ? "X" : "", is_auto_risk ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 9, true);
      string risk_toggle_text = (m_risk_mode == RISK_MODE_PERCENT) ? "Risco: %" : "Risco: $";
      color risk_toggle_bg    = (m_risk_mode == RISK_MODE_PERCENT) ? COLOR_TOGGLE_PCT : (is_auto_risk ? COLOR_TOGGLE_CASH : COLOR_EDIT_BG);
      CreateButton("Btn_Risk_Toggle", offset_x + 24, cur_y, 96, 20, risk_toggle_text, risk_toggle_bg, COLOR_TEXT_MAIN, 9, true);
      CreateButton("Btn_Risk_Dec", offset_x + 126, cur_y, 22, 20, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      string init_risk_str = (m_risk_mode == RISK_MODE_PERCENT) ? DoubleToString(m_risk_percent, 1) : DoubleToString(m_risk_cash, 2);
      CreateEdit("Edit_Risk", offset_x + 150, cur_y, 64, 20, init_risk_str, COLOR_EDIT_BG, COLOR_TEXT_MAIN, false, 9);
      CreateButton("Btn_Risk_Inc", offset_x + 216, cur_y, 22, 20, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += 25;
   }
   
   // 5. Linha de Lote Operacional (Nativo 0.04)
   if(InpShowLotSection)
   {
      bool is_auto_risk = (m_risk_mode != RISK_MODE_MANUAL);
      int dec = GetLotDecimals(m_symbol);
      CreateLabel("Lbl_Lot", offset_x + 24, cur_y + 3, "Lote Operacional", COLOR_TEXT_MAIN, 9, true);
      CreateButton("Btn_Lot_Dec", offset_x + 126, cur_y, 22, 20, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      CreateEdit("Edit_Lot", offset_x + 150, cur_y, 64, 20, DoubleToString(m_manual_lot, dec), is_auto_risk ? COLOR_EDIT_RO_BG : COLOR_EDIT_BG, is_auto_risk ? COLOR_LOT_GOLD : COLOR_TEXT_MAIN, is_auto_risk, 9);
      CreateButton("Btn_Lot_Inc", offset_x + 216, cur_y, 22, 20, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += 25;
   }
   
   // 6. Badge Interativo de Sugestao ATR (se ativado nas configuracoes)
   if(InpEnableATRAlvos)
   {
      int atr_p = 0, sug_sl = 0, sug_tp = 0;
      string atr_txt = "ATR: Calculando...";
      if(GetATRTargets(atr_p, sug_sl, sug_tp))
         atr_txt = StringFormat("ATR: %d pts | Sug: SL %d / TP %d [Aplicar]", atr_p, sug_sl, sug_tp);
      CreateButton("Btn_ATR_Info", offset_x, cur_y, row_w, 20, atr_txt, C'24,32,45', clrGold, 8, true);
      cur_y += 24;
   }
   
   // 7. Stop Loss (pts)
   if(InpShowSLSection)
   {
      CreateButton("Chk_SL", offset_x, cur_y + 1, 18, 18, m_sl_active ? "X" : "", m_sl_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 9, true);
      CreateLabel("Lbl_SL", offset_x + 24, cur_y + 3, "Stop Loss (pts)", COLOR_TEXT_MAIN, 9, false);
      CreateButton("Btn_SL_Dec", offset_x + 126, cur_y, 22, 20, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      CreateEdit("Edit_SL", offset_x + 150, cur_y, 64, 20, IntegerToString(m_sl_points), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false, 9);
      CreateButton("Btn_SL_Inc", offset_x + 216, cur_y, 22, 20, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += 25;
   }
   
   // 8. Take Profit (pts)
   if(InpShowTPSection)
   {
      CreateButton("Chk_TP", offset_x, cur_y + 1, 18, 18, m_tp_active ? "X" : "", m_tp_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 9, true);
      CreateLabel("Lbl_TP", offset_x + 24, cur_y + 3, "Take Profit (pts)", COLOR_TEXT_MAIN, 9, false);
      CreateButton("Btn_TP_Dec", offset_x + 126, cur_y, 22, 20, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      CreateEdit("Edit_TP", offset_x + 150, cur_y, 64, 20, IntegerToString(m_tp_points), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false, 9);
      CreateButton("Btn_TP_Inc", offset_x + 216, cur_y, 22, 20, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += 25;
   }
   
   // 9. Break Even (pts)
   if(InpShowBESection)
   {
      CreateButton("Chk_BE", offset_x, cur_y + 1, 18, 18, m_be_active ? "X" : "", m_be_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 9, true);
      CreateLabel("Lbl_BE", offset_x + 24, cur_y + 3, "Break Even (pts)", COLOR_TEXT_MAIN, 9, false);
      CreateButton("Btn_BE_Dec", offset_x + 126, cur_y, 22, 20, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      CreateEdit("Edit_BE", offset_x + 150, cur_y, 64, 20, IntegerToString(m_be_points), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false, 9);
      CreateButton("Btn_BE_Inc", offset_x + 216, cur_y, 22, 20, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += 25;
   }
   
   // 10. Trailing Stop (pts)
   if(InpShowTSSection)
   {
      CreateButton("Chk_TS", offset_x, cur_y + 1, 18, 18, m_ts_active ? "X" : "", m_ts_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 9, true);
      CreateLabel("Lbl_TS", offset_x + 24, cur_y + 3, "Trailing Stop (pts)", COLOR_TEXT_MAIN, 9, false);
      CreateButton("Btn_TS_Dec", offset_x + 126, cur_y, 22, 20, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      CreateEdit("Edit_TS", offset_x + 150, cur_y, 64, 20, IntegerToString(m_ts_points), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false, 9);
      CreateButton("Btn_TS_Inc", offset_x + 216, cur_y, 22, 20, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += 27;
   }
   
   // 11. Secao Parcial (Compacta e Uniforme com Checkbox)
   if(InpShowParcialSection)
   {
      CreateButton("Chk_Parcial", offset_x, cur_y + 1, 18, 18, m_parcial_active ? "X" : "", m_parcial_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 9, true);
      CreateButton("Btn_Parcial_Toggle_Mode", offset_x + 24, cur_y, 36, 20, m_parcial_is_cash ? "$" : "Pts", m_parcial_is_cash ? COLOR_TOGGLE_CASH : COLOR_TOGGLE_PCT, COLOR_TEXT_MAIN, 8, true);
      CreateLabel("Lbl_Parcial_Target", offset_x + 64, cur_y + 3, "Alvo Parcial", COLOR_TEXT_MAIN, 9, false);
      CreateButton("Btn_Parcial_Dec", offset_x + 126, cur_y, 22, 20, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      string init_parcial_target = m_parcial_is_cash ? DoubleToString(m_parcial_target_cash, 2) : IntegerToString(m_parcial_target_pts);
      CreateEdit("Edit_Parcial_Target", offset_x + 150, cur_y, 64, 20, init_parcial_target, COLOR_EDIT_BG, COLOR_TEXT_MAIN, false, 9);
      CreateButton("Btn_Parcial_Inc", offset_x + 216, cur_y, 22, 20, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += 24;
      
      CreateLabel("Lbl_Parcial_Vol", offset_x + 24, cur_y + 3, "Vol. Parcial (%)", COLOR_TEXT_MUTED, 8, false);
      CreateButton("Btn_Parcial_Vol_Dec", offset_x + 126, cur_y, 22, 20, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      CreateEdit("Edit_Parcial_Vol", offset_x + 150, cur_y, 64, 20, StringFormat("%.0f%%", m_parcial_vol_pct), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false, 9);
      CreateButton("Btn_Parcial_Vol_Inc", offset_x + 216, cur_y, 22, 20, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += 24;
      
      CreateButton("Chk_Parcial_BE", offset_x, cur_y + 1, 16, 16, m_parcial_move_be ? "X" : "", m_parcial_move_be ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 8, true);
      CreateLabel("Lbl_Parcial_BE", offset_x + 22, cur_y + 3, "Mover SL p/ Zero a Zero pos Parcial", COLOR_TEXT_MUTED, 8, false);
      cur_y += 25;
   }
   
   // 12. Gaveta de Canais de Frequencia (Estritamente Manual)
   if(InpShowChannelsSection)
   {
      string drawer_txt = m_channels_expanded ? "CANAIS DE FREQUENCIA (40x40)  [-]" : "CANAIS DE FREQUENCIA (40x40)  [+]";
      CreateButton("Btn_Channels_Toggle", offset_x, cur_y, row_w, 22, drawer_txt, COLOR_DRAWER_BTN, clrGold, 8, true);
      cur_y += 24;
      
      if(m_channels_expanded)
      {
         CreateRectangleLabel("Chan_Drawer_BG", offset_x, cur_y, row_w, 94, COLOR_SECTION_BG, COLOR_BORDER, ZORDER_PANEL_STRIP);
         
         CreateButton("Btn_Chan_Start", offset_x + 5, cur_y + 4, 122, 22, "1. Marcar 2 Linhas", COLOR_CHAN_START, clrWhite, 8, true);
         CreateButton("Btn_Chan_Project", offset_x + 133, cur_y + 4, 122, 22, "2. Projetar 40 Canais", COLOR_CHAN_PROJ, clrWhite, 8, true);
         
         int y_sub = cur_y + 28;
         CreateLabel("Lbl_Chan_Up", offset_x + 6, y_sub + 2, "Cima:", clrWhite, 8, true);
         CreateButton("Btn_Chan_Up_Dec", offset_x + 40, y_sub, 18, 18, "-", COLOR_STEP_BTN, clrWhite, 7, true);
         CreateEdit("Edit_Chan_Up", offset_x + 60, y_sub, 36, 18, IntegerToString(m_proj_up), COLOR_EDIT_BG, clrWhite, false, 8);
         CreateButton("Btn_Chan_Up_Inc", offset_x + 98, y_sub, 18, 18, "+", COLOR_STEP_BTN, clrWhite, 7, true);
         
         CreateLabel("Lbl_Chan_Dn", offset_x + 130, y_sub + 2, "Baixo:", clrWhite, 8, true);
         CreateButton("Btn_Chan_Dn_Dec", offset_x + 168, y_sub, 18, 18, "-", COLOR_STEP_BTN, clrWhite, 7, true);
         CreateEdit("Edit_Chan_Dn", offset_x + 188, y_sub, 36, 18, IntegerToString(m_proj_down), COLOR_EDIT_BG, clrWhite, false, 8);
         CreateButton("Btn_Chan_Dn_Inc", offset_x + 226, y_sub, 18, 18, "+", COLOR_STEP_BTN, clrWhite, 7, true);
         
         y_sub += 22;
         CreateButton("Btn_Chan_HideShow", offset_x + 5, y_sub, 122, 20, m_chan_visible ? "Ocultar Linhas" : "Mostrar Linhas", C'45,48,60', clrWhite, 7, true);
         CreateButton("Btn_Chan_Clear", offset_x + 133, y_sub, 122, 20, "Limpar Canais", COLOR_CLOSE_LSS_BTN, clrWhite, 7, true);
         
         y_sub += 22;
         CreateLabel("Lbl_Chan_Status", offset_x + 8, y_sub, "Status: Pronto (40 canais manuais)", clrLimeGreen, 8, true);
         
         cur_y += 98;
      }
   }
   
   // 13. Botoes Operacionais (COMPRA e VENDA)
   if(InpShowTradeButtons)
   {
      cur_y += 4;
      int half_btn_w = (row_w - 6) / 2; // 127px
      CreateButton("Btn_Buy", offset_x, cur_y, half_btn_w, 36, "[+] COMPRA", COLOR_BUY_BTN, COLOR_TEXT_MAIN, 11, true);
      CreateButton("Btn_Sell", offset_x + half_btn_w + 6, cur_y, half_btn_w, 36, "[-] VENDA", COLOR_SELL_BTN, COLOR_TEXT_MAIN, 11, true);
      cur_y += 40;
   }
   
   // 14. Botao Inverter Posicao
   if(InpShowInvertButton)
   {
      CreateButton("Btn_Invert", offset_x, cur_y, row_w, 26, "INVERTER POSICAO", COLOR_INVERT_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += 29;
   }
   
   // 15. Botoes Zerar Lucro e Zerar Prejuizo
   if(InpShowCloseButtons)
   {
      int half_btn_w = (row_w - 6) / 2; // 127px
      CreateButton("Btn_CloseProfit", offset_x, cur_y, half_btn_w, 26, "Zerar Lucro", COLOR_CLOSE_PRF_BTN, COLOR_TEXT_MAIN, 9, true);
      CreateButton("Btn_CloseLoss", offset_x + half_btn_w + 6, cur_y, half_btn_w, 26, "Zerar Prejuizo", COLOR_CLOSE_LSS_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += 30;
   }
   
   // 16. Botao ZERAR TODAS (No Rodape)
   if(InpShowCloseAll)
   {
      CreateButton("Btn_CloseAll", offset_x, cur_y, row_w, 36, "ZERAR TODAS AS ORDENS", COLOR_CLOSE_ALL_BTN, clrBlack, 11, true);
      cur_y += 40;
   }
   
   m_height = cur_y - m_y + 4;
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Panel_BG", OBJPROP_YSIZE, m_height);
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::ToggleChannelsDrawer()
{
   m_channels_expanded = !m_channels_expanded;
   SaveState();
   Render();
   UpdateFieldValues();
   UpdateLiveMetrics();
   ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Atualizacao Dinamica das Metricas do Painel                      |
//+------------------------------------------------------------------+
void CBoletaMaster::UpdateLiveMetrics()
{
   if(m_is_minimized) return;
   
   long spread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
   string tf_name = GetPeriodName(_Period);
   string timer_str = GetCandleTimerString(m_symbol, _Period);
   
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Mkt_Symbol", OBJPROP_TEXT, m_symbol);
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Mkt_Spread", OBJPROP_TEXT, StringFormat("Sp: %d", spread));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Mkt_Timer",  OBJPROP_TEXT, StringFormat("[%s] %s", tf_name, timer_str));
   
   CalculateDashboardStats();
   UpdateLiveSLTPLines();
   
   if(InpEnableATRAlvos && ObjectFind(m_chart_id, PREFIX_GUI + "Btn_ATR_Info") >= 0)
   {
      int atr_p = 0, sug_sl = 0, sug_tp = 0;
      if(GetATRTargets(atr_p, sug_sl, sug_tp))
      {
         string atr_txt = StringFormat("ATR: %d pts | Sug: SL %d / TP %d [Aplicar]", atr_p, sug_sl, sug_tp);
         ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_ATR_Info", OBJPROP_TEXT, atr_txt);
      }
   }
   
   // Atualiza os 4 Cartoes de Confianca HUD
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Cap_Val", OBJPROP_TEXT, StringFormat("$%.2f", m_starting_capital));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Lot_Val", OBJPROP_TEXT, DoubleToString(GetEffectiveLot(), 2));
   
   string pnl_str = StringFormat("%s$%.2f", (m_today_closed_net >= 0.0) ? "+" : "-", MathAbs(m_today_closed_net));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Pnl_Val", OBJPROP_TEXT, pnl_str);
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Lbl_Pnl_Val", OBJPROP_COLOR, (m_today_closed_net >= 0.0) ? COLOR_PROFIT_GREEN : COLOR_LOSS_RED);
   
   string win_str = StringFormat("%.1f%% (%d/%d)", m_win_rate, m_today_wins, m_today_total_closed);
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Win_Val", OBJPROP_TEXT, win_str);
   
   if(MathAbs(m_floating_pnl) > 0.001)
   {
      string close_text = StringFormat("ZERAR TODAS (%s$%.2f)", (m_floating_pnl >= 0) ? "+" : "-", MathAbs(m_floating_pnl));
      ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_CloseAll", OBJPROP_TEXT, close_text);
   }
   else
   {
      ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_CloseAll", OBJPROP_TEXT, "ZERAR TODAS AS ORDENS");
   }
   ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Linhas Dinamicas de SL e TP no Grafico (Movimento Simultaneo 24/7)|
//+------------------------------------------------------------------+
void CBoletaMaster::UpdateLiveSLTPLines()
{
   if(!InpLiveSLTPLines || (m_sl_points <= 0 && m_tp_points <= 0))
   {
      ObjectDelete(m_chart_id, PREFIX_GUI + "Line_Live_TP");
      ObjectDelete(m_chart_id, PREFIX_GUI + "Line_Live_SL");
      return;
   }
   
   MqlTick tick;
   if(!SymbolInfoTick(m_symbol, tick)) return;
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0.0) return;
   
   // Inspeciona se ha posicao ativa de venda para inverter os niveis visuais
   CPositionInfo pos;
   bool has_sell = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && (!InpFilterSymbolOnly || pos.Symbol() == m_symbol))
      {
         if(pos.PositionType() == POSITION_TYPE_SELL)
         {
            has_sell = true;
            break;
         }
      }
   }
   
   double tp_price = 0.0, sl_price = 0.0;
   string tp_text = "", sl_text = "";
   double lot = GetEffectiveLot();
   double tick_val = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_val <= 0.0) tick_val = 1.0;
   double tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   double pts_per_tick = (tick_size > 0 && point > 0) ? (tick_size / point) : 1.0;
   if(pts_per_tick <= 0.0) pts_per_tick = 1.0;
   double val_per_pt = (tick_val / pts_per_tick) * lot;
   
   double tp_usd = m_tp_points * val_per_pt;
   double sl_usd = m_sl_points * val_per_pt;
   
   if(has_sell)
   {
      tp_price = tick.bid - (m_tp_points * point);
      sl_price = tick.ask + (m_sl_points * point);
      tp_text  = StringFormat("TAKE [SELL -%d pts | +$%.2f]", m_tp_points, tp_usd);
      sl_text  = StringFormat("STOP [SELL +%d pts | -$%.2f]", m_sl_points, sl_usd);
   }
   else
   {
      tp_price = tick.ask + (m_tp_points * point);
      sl_price = tick.bid - (m_sl_points * point);
      tp_text  = StringFormat("TAKE [BUY +%d pts | +$%.2f]", m_tp_points, tp_usd);
      sl_text  = StringFormat("STOP [BUY -%d pts | -$%.2f]", m_sl_points, sl_usd);
   }
   
   // 1. Linha Dinamica de Take Profit
   if(m_tp_points > 0 && (m_tp_active || InpLiveSLTPLines))
   {
      string line_tp = PREFIX_GUI + "Line_Live_TP";
      if(ObjectFind(m_chart_id, line_tp) < 0)
      {
         ObjectCreate(m_chart_id, line_tp, OBJ_HLINE, 0, 0, tp_price);
         ObjectSetInteger(m_chart_id, line_tp, OBJPROP_SELECTABLE, false);
      }
      else
      {
         ObjectMove(m_chart_id, line_tp, 0, 0, tp_price);
      }
      ObjectSetInteger(m_chart_id, line_tp, OBJPROP_BACK, true);
      ObjectSetInteger(m_chart_id, line_tp, OBJPROP_ZORDER, 0);
      ObjectSetInteger(m_chart_id, line_tp, OBJPROP_COLOR, InpColorLiveTP);
      ObjectSetInteger(m_chart_id, line_tp, OBJPROP_STYLE, InpStyleLiveTP);
      ObjectSetInteger(m_chart_id, line_tp, OBJPROP_WIDTH, InpWidthLiveTP);
      ObjectSetString(m_chart_id, line_tp, OBJPROP_TEXT, tp_text);
      ObjectSetString(m_chart_id, line_tp, OBJPROP_TOOLTIP, tp_text);
   }
   else
   {
      ObjectDelete(m_chart_id, PREFIX_GUI + "Line_Live_TP");
   }
   
   // 2. Linha Dinamica de Stop Loss
   if(m_sl_points > 0 && (m_sl_active || InpLiveSLTPLines))
   {
      string line_sl = PREFIX_GUI + "Line_Live_SL";
      if(ObjectFind(m_chart_id, line_sl) < 0)
      {
         ObjectCreate(m_chart_id, line_sl, OBJ_HLINE, 0, 0, sl_price);
         ObjectSetInteger(m_chart_id, line_sl, OBJPROP_SELECTABLE, false);
      }
      else
      {
         ObjectMove(m_chart_id, line_sl, 0, 0, sl_price);
      }
      ObjectSetInteger(m_chart_id, line_sl, OBJPROP_BACK, true);
      ObjectSetInteger(m_chart_id, line_sl, OBJPROP_ZORDER, 0);
      ObjectSetInteger(m_chart_id, line_sl, OBJPROP_COLOR, InpColorLiveSL);
      ObjectSetInteger(m_chart_id, line_sl, OBJPROP_STYLE, InpStyleLiveSL);
      ObjectSetInteger(m_chart_id, line_sl, OBJPROP_WIDTH, InpWidthLiveSL);
      ObjectSetString(m_chart_id, line_sl, OBJPROP_TEXT, sl_text);
      ObjectSetString(m_chart_id, line_sl, OBJPROP_TOOLTIP, sl_text);
   }
   else
   {
      ObjectDelete(m_chart_id, PREFIX_GUI + "Line_Live_SL");
   }
}

void CBoletaMaster::UpdateFieldValues()
{
   if(m_is_minimized) return;
   int dec = GetLotDecimals(m_symbol);
   
   // Risco ($150 preenchido nativamente, mesmo desmarcado)
   bool is_auto_risk = (m_risk_mode != RISK_MODE_MANUAL);
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_Risk", OBJPROP_TEXT, is_auto_risk ? "X" : "");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_Risk", OBJPROP_BGCOLOR, is_auto_risk ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   
   if(m_risk_mode == RISK_MODE_PERCENT)
   {
      ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Risk", OBJPROP_TEXT, DoubleToString(m_risk_percent, 1));
      ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_Risk_Toggle", OBJPROP_TEXT, "Risco: %");
      ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_Risk_Toggle", OBJPROP_BGCOLOR, COLOR_TOGGLE_PCT);
   }
   else // RISK_MODE_CASH ou RISK_MODE_MANUAL (exibe sempre o valor configurado em dólares, ex: 150.00)
   {
      ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Risk", OBJPROP_TEXT, DoubleToString(m_risk_cash, 2));
      ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_Risk_Toggle", OBJPROP_TEXT, "Risco: $");
      ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_Risk_Toggle", OBJPROP_BGCOLOR, is_auto_risk ? COLOR_TOGGLE_CASH : COLOR_EDIT_BG);
   }
   
   // Lote
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Lot", OBJPROP_TEXT, DoubleToString(m_manual_lot, dec));
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Edit_Lot", OBJPROP_READONLY, is_auto_risk);
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Edit_Lot", OBJPROP_BGCOLOR, is_auto_risk ? COLOR_EDIT_RO_BG : COLOR_EDIT_BG);
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Edit_Lot", OBJPROP_COLOR, is_auto_risk ? COLOR_LOT_GOLD : COLOR_TEXT_MAIN);
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Lot_Val", OBJPROP_TEXT, DoubleToString(GetEffectiveLot(), dec));
   
   // Stop Loss
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_SL", OBJPROP_TEXT, IntegerToString(m_sl_points));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_SL", OBJPROP_TEXT, m_sl_active ? "X" : "");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_SL", OBJPROP_BGCOLOR, m_sl_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   
   // Take Profit
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_TP", OBJPROP_TEXT, IntegerToString(m_tp_points));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_TP", OBJPROP_TEXT, m_tp_active ? "X" : "");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_TP", OBJPROP_BGCOLOR, m_tp_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   
   // Break Even
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_BE", OBJPROP_TEXT, IntegerToString(m_be_points));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_BE", OBJPROP_TEXT, m_be_active ? "X" : "");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_BE", OBJPROP_BGCOLOR, m_be_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   
   // Trailing Stop
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_TS", OBJPROP_TEXT, IntegerToString(m_ts_points));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_TS", OBJPROP_TEXT, m_ts_active ? "X" : "");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_TS", OBJPROP_BGCOLOR, m_ts_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   
   // Parcial (Checkbox unificado)
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_Parcial", OBJPROP_TEXT, m_parcial_active ? "X" : "");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_Parcial", OBJPROP_BGCOLOR, m_parcial_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   
   if(m_parcial_is_cash)
   {
      ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Parcial_Target", OBJPROP_TEXT, DoubleToString(m_parcial_target_cash, 2));
      ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_Parcial_Toggle_Mode", OBJPROP_TEXT, "$");
      ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_Parcial_Toggle_Mode", OBJPROP_BGCOLOR, COLOR_TOGGLE_CASH);
   }
   else
   {
      ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Parcial_Target", OBJPROP_TEXT, IntegerToString(m_parcial_target_pts));
      ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_Parcial_Toggle_Mode", OBJPROP_TEXT, "Pts");
      ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_Parcial_Toggle_Mode", OBJPROP_BGCOLOR, COLOR_TOGGLE_PCT);
   }
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Parcial_Vol", OBJPROP_TEXT, StringFormat("%.0f%%", m_parcial_vol_pct));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_Parcial_BE", OBJPROP_TEXT, m_parcial_move_be ? "X" : "");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_Parcial_BE", OBJPROP_BGCOLOR, m_parcial_move_be ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   
   // Gaveta de Canais
   if(m_channels_expanded)
   {
      ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Chan_Up", OBJPROP_TEXT, IntegerToString(m_proj_up));
      ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Chan_Dn", OBJPROP_TEXT, IntegerToString(m_proj_down));
      ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_Chan_HideShow", OBJPROP_TEXT, m_chan_visible ? "Ocultar Linhas" : "Mostrar Linhas");
   }
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::MovePanel(int new_x, int new_y)
{
   int dx = new_x - m_x;
   int dy = new_y - m_y;
   if(dx == 0 && dy == 0) return;
   
   m_x = new_x;
   m_y = new_y;
   
   int total = ObjectsTotal(m_chart_id, 0);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(m_chart_id, i, 0);
      if(StringFind(name, PREFIX_GUI) == 0)
      {
         if(name == PREFIX_GUI + "Line_Live_TP" || name == PREFIX_GUI + "Line_Live_SL")
            continue;
            
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
   SaveState();
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
   SaveState();
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
   SaveState();
   UpdateFieldValues();
}

void CBoletaMaster::ToggleSL()          { m_sl_active = !m_sl_active; if(m_sl_active && m_risk_mode != RISK_MODE_MANUAL) RecalculateRiskLot(); SaveState(); UpdateFieldValues(); UpdateLiveSLTPLines(); }
void CBoletaMaster::ToggleTP()          { m_tp_active = !m_tp_active; SaveState(); UpdateFieldValues(); UpdateLiveSLTPLines(); }
void CBoletaMaster::ToggleBE()          { m_be_active = !m_be_active; SaveState(); UpdateFieldValues(); }
void CBoletaMaster::ToggleTS()          { m_ts_active = !m_ts_active; SaveState(); UpdateFieldValues(); }
void CBoletaMaster::ToggleParcial()     { m_parcial_active = !m_parcial_active; SaveState(); UpdateFieldValues(); }
void CBoletaMaster::ToggleParcialMode() { m_parcial_is_cash = !m_parcial_is_cash; SaveState(); UpdateFieldValues(); }
void CBoletaMaster::ToggleParcialBE()   { m_parcial_move_be = !m_parcial_move_be; SaveState(); UpdateFieldValues(); }

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
      m_risk_cash += delta;
      if(m_risk_cash < 1.0) m_risk_cash = 1.0;
      if(freeMargin > 0.0)
         m_risk_percent = (m_risk_cash / freeMargin) * 100.0;
   }
   RecalculateRiskLot();
   SaveState();
   UpdateFieldValues();
}

void CBoletaMaster::AdjustLot(double delta)
{
   m_risk_mode = RISK_MODE_MANUAL;
   m_manual_lot = NormalizeLot(m_manual_lot + delta, m_symbol);
   SaveState();
   UpdateFieldValues();
}

void CBoletaMaster::AdjustSL(int delta)
{
   m_sl_points += delta;
   if(m_sl_points < 10) m_sl_points = 10;
   if(m_risk_mode != RISK_MODE_MANUAL) RecalculateRiskLot();
   SaveState();
   UpdateFieldValues();
   UpdateLiveSLTPLines();
}

void CBoletaMaster::AdjustTP(int delta)
{
   m_tp_points += delta;
   if(m_tp_points < 0) m_tp_points = 0;
   SaveState();
   UpdateFieldValues();
   UpdateLiveSLTPLines();
}

void CBoletaMaster::AdjustBE(int delta)
{
   m_be_points += delta;
   if(m_be_points < 0) m_be_points = 0;
   SaveState();
   UpdateFieldValues();
}

void CBoletaMaster::AdjustTS(int delta)
{
   m_ts_points += delta;
   if(m_ts_points < 0) m_ts_points = 0;
   SaveState();
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
   SaveState();
   UpdateFieldValues();
}

void CBoletaMaster::AdjustParcialVol(double delta)
{
   m_parcial_vol_pct += delta;
   if(m_parcial_vol_pct < 5.0)  m_parcial_vol_pct = 5.0;
   if(m_parcial_vol_pct > 95.0) m_parcial_vol_pct = 95.0;
   SaveState();
   UpdateFieldValues();
}

void CBoletaMaster::AdjustChanUp(int delta)
{
   m_proj_up += delta;
   if(m_proj_up < 0) m_proj_up = 0;
   if(m_proj_up > 100) m_proj_up = 100;
   SaveState();
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Chan_Up", OBJPROP_TEXT, IntegerToString(m_proj_up));
   if(m_has_projections) ProjetarCanais();
}

void CBoletaMaster::AdjustChanDown(int delta)
{
   m_proj_down += delta;
   if(m_proj_down < 0) m_proj_down = 0;
   if(m_proj_down > 100) m_proj_down = 100;
   SaveState();
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Chan_Dn", OBJPROP_TEXT, IntegerToString(m_proj_down));
   if(m_has_projections) ProjetarCanais();
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
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Lot_Val", OBJPROP_TEXT, DoubleToString(m_manual_lot, dec));
   ChartRedraw(m_chart_id);
}

double CBoletaMaster::GetEffectiveLot()
{
   return NormalizeLot(m_manual_lot, m_symbol);
}

//+------------------------------------------------------------------+
//| Modulo de Canais Manuais de Frequencia (40x40)                   |
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
   ObjectSetInteger(m_chart_id, nome, OBJPROP_BACK, true);
   ObjectSetInteger(m_chart_id, nome, OBJPROP_ZORDER, 0);
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
      string p = "BSCALP_CHAN_" + IntegerToString(m_chart_id) + "_";
      price1 = GlobalVariableGet(p + "base_top");
      price2 = GlobalVariableGet(p + "base_bottom");
   }
   else
   {
      Alert("Posicione as duas linhas de referencia antes de projetar!");
      return;
   }
   
   double topPrice = MathMax(price1, price2);
   double bottomPrice = MathMin(price1, price2);
   double amplitude = topPrice - bottomPrice;
   
   if(amplitude <= 0)
   {
      Alert("A amplitude entre as linhas de canal nao pode ser zero!");
      return;
   }
   
   ObjectsDeleteAll(m_chart_id, PREFIX_CANAL_LINES);
   
   double midPrice = bottomPrice + (amplitude / 2.0);
   DesenharHLine(PREFIX_CANAL_LINES + "Top", topPrice, InpColorChannel, STYLE_SOLID, 2, "TOPO CANAL MANUAL");
   DesenharHLine(PREFIX_CANAL_LINES + "Bottom", bottomPrice, InpColorChannel, STYLE_SOLID, 2, "FUNDO CANAL MANUAL");
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
   {
      string p = "BSCALP_CHAN_" + IntegerToString(m_chart_id) + "_";
      GlobalVariableSet(p + "visible", m_chan_visible ? 1.0 : 0.0);
   }
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

void CBoletaMaster::SalvarEstadoCanais(double baseTop, double baseBottom, double amp=0.0)
{
   string p = "BSCALP_CHAN_" + IntegerToString(m_chart_id) + "_";
   double save_amp = (amp > 0.0) ? amp : (baseTop - baseBottom);
   GlobalVariableSet(p + "has_proj", 1.0);
   GlobalVariableSet(p + "base_top", baseTop);
   GlobalVariableSet(p + "base_bottom", baseBottom);
   GlobalVariableSet(p + "amplitude", save_amp);
   GlobalVariableSet(p + "proj_up", (double)m_proj_up);
   GlobalVariableSet(p + "proj_down", (double)m_proj_down);
   GlobalVariableSet(p + "visible", m_chan_visible ? 1.0 : 0.0);
}

void CBoletaMaster::LimparVariaveisGlobaisCanais()
{
   string p = "BSCALP_CHAN_" + IntegerToString(m_chart_id) + "_";
   GlobalVariableDel(p + "has_proj");
   GlobalVariableDel(p + "base_top");
   GlobalVariableDel(p + "base_bottom");
   GlobalVariableDel(p + "amplitude");
   GlobalVariableDel(p + "proj_up");
   GlobalVariableDel(p + "proj_down");
   GlobalVariableDel(p + "visible");
}

void CBoletaMaster::RestaurarEstadoCanais()
{
   string p = "BSCALP_CHAN_" + IntegerToString(m_chart_id) + "_";
   if(GlobalVariableCheck(p + "has_proj") && GlobalVariableGet(p + "has_proj") > 0.5)
   {
      double baseTop    = GlobalVariableGet(p + "base_top");
      double baseBottom = GlobalVariableGet(p + "base_bottom");
      m_proj_up         = (int)GlobalVariableGet(p + "proj_up");
      m_proj_down       = (int)GlobalVariableGet(p + "proj_down");
      m_chan_visible    = (GlobalVariableGet(p + "visible") > 0.5);
      
      double amplitude = 0.0;
      if(GlobalVariableCheck(p + "amplitude"))
         amplitude = GlobalVariableGet(p + "amplitude");
      if(amplitude <= 0.0)
         amplitude = baseTop - baseBottom;
         
      ObjectsDeleteAll(m_chart_id, PREFIX_CANAL_LINES);
      if(amplitude > 0.0)
      {
         double midPrice = baseBottom + (amplitude / 2.0);
         DesenharHLine(PREFIX_CANAL_LINES + "Top", baseTop, InpColorChannel, STYLE_SOLID, 2, "TOPO CANAL MANUAL");
         DesenharHLine(PREFIX_CANAL_LINES + "Bottom", baseBottom, InpColorChannel, STYLE_SOLID, 2, "FUNDO CANAL MANUAL");
         DesenharHLine(PREFIX_CANAL_LINES + "Mid", midPrice, InpColorChannelMid, STYLE_DASH);
         
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
         
         m_has_projections = true;
         ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_TEXT, StringFormat("Canal Manual: %d C / %d B", m_proj_up, m_proj_down));
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
//| Execucoes Ultrarrapidas de Mercado                               |
//+------------------------------------------------------------------+
void CBoletaMaster::ExecuteBuy()
{
   MqlTick tick;
   if(!SymbolInfoTick(m_symbol, tick)) return;
   double ask = tick.ask;
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double lot = GetEffectiveLot();
   double sl = (m_sl_active && m_sl_points > 0) ? (ask - m_sl_points * point) : 0.0;
   double tp = (m_tp_active && m_tp_points > 0) ? (ask + m_tp_points * point) : 0.0;
   
   m_trade.Buy(lot, m_symbol, ask, sl, tp, "Scalp Buy");
   UpdateLiveMetrics();
}

void CBoletaMaster::ExecuteSell()
{
   MqlTick tick;
   if(!SymbolInfoTick(m_symbol, tick)) return;
   double bid = tick.bid;
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double lot = GetEffectiveLot();
   double sl = (m_sl_active && m_sl_points > 0) ? (bid + m_sl_points * point) : 0.0;
   double tp = (m_tp_active && m_tp_points > 0) ? (bid - m_tp_points * point) : 0.0;
   
   m_trade.Sell(lot, m_symbol, bid, sl, tp, "Scalp Sell");
   UpdateLiveMetrics();
}

void CBoletaMaster::ExecuteInvert()
{
   MqlTick tick;
   if(!SymbolInfoTick(m_symbol, tick)) return;
   double ask = tick.ask;
   double bid = tick.bid;
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
   ChartRedraw(m_chart_id);
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
   ChartRedraw(m_chart_id);
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
   ChartRedraw(m_chart_id);
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
   ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Gestao de Edicoes e Cliques                                      |
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
      else
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
      UpdateLiveSLTPLines();
   }
   else if(short_name == "Edit_TP")
   {
      int tp = (int)StringToInteger(val_str);
      if(tp >= 0) m_tp_points = tp;
      UpdateLiveSLTPLines();
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
   SaveState();
   UpdateFieldValues();
}

void CBoletaMaster::HandleButtonClick(const string &obj_name)
{
   string short_name = obj_name;
   StringReplace(short_name, PREFIX_GUI, "");
   ObjectSetInteger(m_chart_id, obj_name, OBJPROP_STATE, false);
   
   if(short_name == "Btn_Min")              { ToggleMinimize(); return; }
   if(short_name == "Btn_ATR_Info")         { ApplyATRTargets(); return; }
   if(short_name == "Btn_Close")            { Destroy(REASON_REMOVE); ExpertRemove(); return; }
   
   // Gaveta de Canais
   if(short_name == "Btn_Channels_Toggle")  { ToggleChannelsDrawer(); return; }
   if(short_name == "Btn_Chan_Start")       { StartChannelMarking(); return; }
   if(short_name == "Btn_Chan_Project")     { ProjetarCanais(); return; }
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
   
   // Parcial: Checkbox e Toggles
   if(short_name == "Chk_Parcial")          { ToggleParcial(); return; }
   if(short_name == "Btn_Parcial_Toggle_Mode") { ToggleParcialMode(); return; }
   if(short_name == "Chk_Parcial_BE")       { ToggleParcialBE(); return; }
   
   // Steppers (+ / -)
   if(short_name == "Btn_Risk_Dec")
   {
      AdjustRisk((m_risk_mode == RISK_MODE_PERCENT) ? -InpStepRiskPct : -InpStepRiskCash);
      return;
   }
   if(short_name == "Btn_Risk_Inc")
   {
      AdjustRisk((m_risk_mode == RISK_MODE_PERCENT) ? InpStepRiskPct : InpStepRiskCash);
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
   
   // Acoes de Negociacao Ultrarrapidas
   if(short_name == "Btn_Buy")              { ExecuteBuy(); return; }
   if(short_name == "Btn_Sell")             { ExecuteSell(); return; }
   if(short_name == "Btn_Invert")           { ExecuteInvert(); return; }
   if(short_name == "Btn_CloseProfit")      { ExecuteCloseProfit(); return; }
   if(short_name == "Btn_CloseLoss")        { ExecuteCloseLoss(); return; }
   if(short_name == "Btn_CloseAll")         { ExecuteCloseAll(); return; }
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
   
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int mouse_x = (int)lparam;
      int mouse_y = (int)dparam;
      uint flags  = (uint)StringToInteger(sparam);
      bool lbutton_down = ((flags & 1) == 1);
      
      // Arrastar Painel pelo Cabecalho ou pela Faixa de Mercado (Pegada Ampla de 56px)
      if(lbutton_down)
      {
         if(!m_is_dragging)
         {
            int drag_h = m_is_minimized ? m_header_h : (m_header_h + 30);
            if(mouse_x >= m_x && mouse_x <= m_x + m_width &&
               mouse_y >= m_y && mouse_y <= m_y + drag_h)
            {
               // Nao arrastar se o clique foi nos botoes de minimizar ou fechar
               if(mouse_y <= m_y + m_header_h && mouse_x >= m_x + m_width - 55)
                  return;
               
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
            
            long chart_w = ChartGetInteger(m_chart_id, CHART_WIDTH_IN_PIXELS);
            long chart_h = ChartGetInteger(m_chart_id, CHART_HEIGHT_IN_PIXELS);
            if(chart_w > 0 && next_x > chart_w - 50) next_x = (int)chart_w - 50;
            if(chart_h > 0 && next_y > chart_h - 30) next_y = (int)chart_h - 30;
            
            MovePanel(next_x, next_y);
         }
      }
      else
      {
         if(m_is_dragging)
         {
            m_is_dragging = false;
            SaveState(); // Salva posicao final exata apos soltar o clique
            BringToFront();
         }
         m_is_dragging = false;
      }
      return;
   }
   
   // Captura de Cliques para Marcacao Manual das Linhas de Canal
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
   
   // Teclas de Atalho de Alta Produtividade
   if(id == CHARTEVENT_KEYDOWN)
   {
      if(lparam == 77 || lparam == 109) { ToggleMinimize(); return; }        // M -> Minimizar
      if(lparam == 73 || lparam == 105) { ExecuteInvert(); return; }         // I -> Inverter
   }
}

//+------------------------------------------------------------------+
//| Instancia Global Unica                                           |
//+------------------------------------------------------------------+
CBoletaMaster g_boleta;

//+------------------------------------------------------------------+
//| Controle de Execucao de Parciais                                 |
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
//| Gestao Continua de Posicoes (Parciais, BE & TS)                  |
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
      
      // 1. Execucao de Parcial
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
      
      // 2. Break Even & Trailing Simultaneo de SL e TP (BUY)
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
         
         // Trailing Simultaneo de Take e Stop junto com o movimento do ativo
         int sl_pts = g_boleta.GetSLPoints();
         int tp_pts = g_boleta.GetTPPoints();
         
         if((ts_active || InpSimultaneousTrailing) && sl_pts > 0 && be_atingido)
         {
            int trail_dist = (ts_active && ts_pts > 0) ? ts_pts : sl_pts;
            double desired_sl = bid - (trail_dist * point);
            
            // Move exclusivamente para frente/cima (nunca recua para tras contra a posicao)
            if(desired_sl >= openPrice)
            {
               double min_step = point * ts_step_pts;
               if(curSL == 0.0 || desired_sl >= curSL + min_step)
               {
                  double desired_tp = curTP;
                  if(tp_pts > 0)
                  {
                     // Move o Take simultaneamente junto com o Stop, mantendo a distancia de alvo
                     desired_tp = bid + (tp_pts * point);
                  }
                  trade.PositionModify(ticket, desired_sl, desired_tp);
                  curSL = desired_sl;
                  curTP = desired_tp;
               }
            }
         }
      }
      // 3. Break Even & Trailing Simultaneo de SL e TP (SELL)
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
         
         // Trailing Simultaneo de Take e Stop junto com o movimento do ativo
         int sl_pts = g_boleta.GetSLPoints();
         int tp_pts = g_boleta.GetTPPoints();
         
         if((ts_active || InpSimultaneousTrailing) && sl_pts > 0 && be_atingido)
         {
            int trail_dist = (ts_active && ts_pts > 0) ? ts_pts : sl_pts;
            double desired_sl = ask + (trail_dist * point);
            
            // Move exclusivamente para frente/baixo (nunca recua para tras contra a posicao)
            if(desired_sl <= openPrice)
            {
               double min_step = point * ts_step_pts;
               if(curSL == 0.0 || desired_sl <= curSL - min_step)
               {
                  double desired_tp = curTP;
                  if(tp_pts > 0)
                  {
                     // Move o Take simultaneamente junto com o Stop, mantendo a distancia de alvo
                     desired_tp = ask - (tp_pts * point);
                  }
                  trade.PositionModify(ticket, desired_sl, desired_tp);
                  curSL = desired_sl;
                  curTP = desired_tp;
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
   ChartSetInteger(ChartID(), CHART_FOREGROUND, false);
   ChartSetInteger(ChartID(), CHART_EVENT_MOUSE_MOVE, true);
   
   if(!g_boleta.Init(InpSymbol, InpMagicNumber, InpSlippage, InpPanelX, InpPanelY))
   {
      Print("Erro ao inicializar Boleta Scalping Pro!");
      return INIT_FAILED;
   }
   
   EventSetMillisecondTimer(200);
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
   
   if(InpEnableATRAlvos && InpAutoApplyATR)
   {
      int atr_p = 0, sug_sl = 0, sug_tp = 0;
      if(g_boleta.GetATRTargets(atr_p, sug_sl, sug_tp))
      {
         if(g_boleta.GetSLPoints() != sug_sl || g_boleta.GetTPPoints() != sug_tp)
         {
            g_boleta.SetSLPoints(sug_sl);
            g_boleta.SetTPPoints(sug_tp);
            g_boleta.UpdateFieldValues();
            g_boleta.UpdateLiveSLTPLines();
         }
      }
   }
   
   GerenciarPosicoesAbertas();
   g_boleta.CheckBreakout();
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
