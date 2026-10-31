//+------------------------------------------------------------------+
//|                                  BoletaScalpingMentorPro.mq5     |
//|                             Copyright 2026, ViniBurgo Developer  |
//|     Unificação Master: Boleta Scalping Pro v10 + Mentor Price    |
//|     Action Pro (Pivôs V/W, Pavio de Respiro, EMA 200 & Hedge)    |
//+------------------------------------------------------------------+
#property copyright "Senior MQL5 Developer & Quant Forensic Auditor"
#property link      "https://github.com/burgo585/burgo_eas"
#property version   "11.00"
#property description "Boleta Scalping Mentor Pro v11.0: Fusao Scalp Pro v10 + Mentor Price Action"
#property description "Pivos Estruturais V e W Empenado com Linhas Projetadas (Alta/Baixa)"
#property description "Filtro de Pavio de Respiro Anti-Vela Careca e Trava de Hedge Delta Neutro"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//| Paleta Dark Mode Institucional e Cores do Mentor                 |
//+------------------------------------------------------------------+
#define COLOR_PANEL_BG        C'18,21,27'    // Slate Obsidian Fundo Principal
#define COLOR_HEADER_BG       C'13,15,20'    // Grafite Profundo Cabeçalho
#define COLOR_MARKET_BG       C'24,28,36'    // Faixa Ativo & Spread
#define COLOR_CARD_BG         C'25,30,40'    // Cartão HUD Métricas
#define COLOR_CARD_BORDER     C'38,45,60'    // Borda Sutil HUD
#define COLOR_SECTION_BG      C'22,26,34'    // Fundo Gaveta Canais / Mentor
#define COLOR_BORDER          C'42,48,64'    // Borda Principal
#define COLOR_TEXT_MAIN       C'245,248,252' // Texto Primário Branco Puro
#define COLOR_TEXT_MUTED      C'155,162,178' // Texto Secundário Suave
#define COLOR_EDIT_BG         C'28,33,44'    // Campo de Edição
#define COLOR_EDIT_RO_BG      C'38,42,54'    // Campo Read-Only
#define COLOR_CHECK_ACTIVE    C'0,195,105'   // Check Ativo Verde Emerald Institucional
#define COLOR_CHECK_INACT     C'50,55,68'    // Check Inativo Cinza Grafite
#define COLOR_STEP_BTN        C'44,50,65'    // Botões Steppers (- / +)
#define COLOR_DRAWER_BTN      C'30,42,58'    // Gaveta de Canais
#define COLOR_CHAN_START      C'28,60,95'    // Botão Marcar Manual (Azul Safira)
#define COLOR_CHAN_PROJ       C'20,105,70'   // Botão Projetar (Verde Esmeralda)
#define COLOR_BUY_BTN         C'0,175,90'    // Compra Emerald Fluido
#define COLOR_SELL_BTN        C'215,38,50'   // Venda Coral Crimson
#define COLOR_INVERT_BTN      C'195,110,18'  // Inverter Âmbar
#define COLOR_LOCK_BTN        C'35,90,165'   // Trava Hedge Azul Cobalto
#define COLOR_CLOSE_ALL_BTN   C'240,242,250' // Zerar Todas Prata Platina Destaque
#define COLOR_CLOSE_PRF_BTN   C'25,125,65'   // Zerar Lucro Verde Escuro
#define COLOR_CLOSE_LSS_BTN   C'145,35,42'   // Zerar Prejuízo Vermelho Escuro
#define COLOR_PROFIT_GREEN    C'0,225,115'   // Verde Lucro
#define COLOR_LOSS_RED        C'255,75,75'   // Vermelho Prejuízo
#define COLOR_LOT_GOLD        C'255,200,50'  // Âmbar Dourado Lote
#define COLOR_TOGGLE_PCT      C'32,75,140'   // Modo Risco %
#define COLOR_TOGGLE_CASH     C'20,115,80'   // Modo Risco $

// Cores Oficiais da Metodologia Mentor
#define COLOR_MENTOR_BUY_LIME C'0,255,128'   // Verde Neon Rompimento Topo
#define COLOR_MENTOR_SELL_MAG C'255,0,128'   // Magenta Rompimento Fundo
#define COLOR_MENTOR_WARN_BALD C'90,95,105'  // Cinza Alerta Vela Careca
#define COLOR_MENTOR_PREP_GOLD C'255,190,40' // Dourado Preparar Boleta

//--- Prefixos de Objetos Gráficos
#define PREFIX_GUI         "BSCALP_GUI_"
#define PREFIX_CANAL_LINES "BSCALP_CLINE_"
#define PREFIX_CANAL_TEMP  "BSCALP_CTEMP_"
#define PREFIX_MENTOR      "BSCALP_MPA_"

//--- Camadas Z-Order
#define ZORDER_PANEL_BG      1000000
#define ZORDER_PANEL_STRIP   1000010
#define ZORDER_PANEL_CTRL    1000020
#define ZORDER_PANEL_TXT     1000030

//--- Enumeradores
enum ENUM_GUI_SCALE
{
   GUI_SCALE_100,      // 100% (Compacta - 276px)
   GUI_SCALE_115,      // 115% (Médio Confortável - 318px - Recomendado)
   GUI_SCALE_130,      // 130% (Grande - 360px)
   GUI_SCALE_150       // 150% (Extra Grande / 4K - 414px)
};

enum ENUM_STATS_PERIOD
{
   STATS_PERIOD_TODAY,     // Apenas Hoje (Desde 00:00 de Hoje até o Momento)
   STATS_PERIOD_CUSTOM,    // A partir da Data Escolhida até o Momento Atual
   STATS_PERIOD_7D,        // Últimos 7 Dias até o Momento Atual
   STATS_PERIOD_30D,       // Últimos 30 Dias até o Momento Atual
   STATS_PERIOD_ALL        // Todo o Histórico da Conta até o Momento
};

enum ENUM_RISK_MODE
{
   RISK_MODE_MANUAL,   // Lote Fixo Manual (Padrão Desmarcado)
   RISK_MODE_CASH,     // Risco por Valor Financeiro Fixo ($150)
   RISK_MODE_PERCENT   // Risco por Porcentagem da Conta (%)
};

struct SwingPoint
{
   datetime time;
   double   price;
   int      barIndex;
   bool     isHigh;
};

//+------------------------------------------------------------------+
//| Parâmetros de Entrada (.SET / CONFIGURAÇÃO NATIVA)               |
//+------------------------------------------------------------------+
input group "=== CONFIGURAÇÃO DO ATIVO & ROTEAMENTO ==="
input string          InpSymbol            = "";                 // Ativo Operado (Vazio = Gráfico Atual)
input ulong           InpMagicNumber       = 123456;             // Magic Number das Ordens
input ulong           InpSlippage          = 20;                 // Desvio Máximo / Slippage (pontos)
input bool            InpFilterSymbolOnly  = false;              // Filtrar Métricas apenas deste Ativo (false = Toda a Conta)

input group "=== GESTÃO DE LOTE & RISCO ($150 DESMARCADO) ==="
input ENUM_RISK_MODE  InpDefaultRiskMode   = RISK_MODE_MANUAL;   // Modo de Risco Inicial (Manual Desmarcado)
input double          InpRiskCash          = 150.0;              // Risco Financeiro ($150 Nativo do Set)
input double          InpDefaultLot        = 0.04;               // Lote Operacional Nativo do Set
input double          InpRiskPercent       = 1.0;                // Risco Percentual Inicial (%) se ativado

input group "=== ALVOS NATIVOS DO SET (SL 200 PTS / TP 300 PTS) ==="
input bool            InpSLActive          = true;               // Stop Loss Inicial (Ativo por Padrão no Set)
input int             InpDefaultSL         = 200;                // Stop Loss Nativo do Set (pontos)
input bool            InpTPActive          = true;               // Take Profit Inicial (Ativo por Padrão no Set)
input int             InpDefaultTP         = 300;                // Take Profit Nativo do Set (pontos)
input bool            InpLiveSLTPLines     = true;               // Linhas Dinâmicas de SL e TP no Gráfico (24/7)
input bool            InpSimultaneousTrailing = true;            // Trailing Simultâneo SL & TP (Bracket Móvel 24/7)
input bool            InpBEActive          = false;              // Break Even Inicial (Desmarcado por Padrão)
input int             InpDefaultBE         = 60;                 // Break Even Padrão (pontos)
input bool            InpTSActive          = false;              // Trailing Stop Inicial (Desmarcado por Padrão)
input int             InpDefaultTS         = 150;                // Trailing Stop Padrão (pontos)
input int             InpDefaultTSStep     = 2;                  // Passo do Trailing Stop (pontos)

input group "=== MENTOR PRICE ACTION PRO (GEOMETRIA & MICROESTRUTURA) ==="
input bool            InpEnableMentor      = true;               // Ativar Módulo Mentor Price Action
input bool            InpMentorAutoTrading = false;              // Auto Scalper Mentor (Execução Automática)
input double          InpMentorDailyTarget = 15.0;               // Meta Diária ($) - Bateu Meta, Bloqueia Overtrading!
input int             InpSwingStrength     = 2;                  // Sensibilidade dos Pivôs (2=Dinâmico, 3=Padrão)
input int             InpMinWickPoints     = 12;                 // Pavio Mínimo Contrário (Filtro Anti-Vela Careca)
input bool            InpRequireWickFilter = true;               // Exigir Pavio de Respiro (Proibido Vela Careca!)
input int             InpEmaPeriod         = 200;                // Período da Média Bússola / Ímã (EMA 200)
input double          InpMentorRRRatio     = 3.0;                // Relação Retorno:Risco do Mentor (3:1)
input bool            InpDrawMentorLevels  = true;               // Projetar Linhas da Altura do Rompimento (↗ / ↘)
input color           InpColorMentorBuy    = clrGold;            // Cor da Linha de Rompimento de Compra (Topo)
input color           InpColorMentorSell   = clrDeepPink;        // Cor da Linha de Rompimento de Venda (Fundo)

input group "=== ESTILIZAÇÃO DAS LINHAS VISUAIS SL/TP ==="
input color           InpColorLiveTP       = C'34,197,94';       // Cor da Linha Take Profit (Verde Platina)
input ENUM_LINE_STYLE InpStyleLiveTP       = STYLE_DASH;         // Estilo da Linha Take Profit
input int             InpWidthLiveTP       = 1;                  // Espessura da Linha Take Profit (1 a 5)
input color           InpColorLiveSL       = C'239,68,68';       // Cor da Linha Stop Loss (Vermelho Vibrante)
input ENUM_LINE_STYLE InpStyleLiveSL       = STYLE_DASH;         // Estilo da Linha Stop Loss
input int             InpWidthLiveSL       = 1;                  // Espessura da Linha Stop Loss (1 a 5)

input group "=== SUGESTÃO DE ALVOS VIA ATR (DESLIGADO POR PADRÃO) ==="
input bool            InpEnableATRAlvos    = false;              // Ativar Cálculo de Alvos via ATR (Desligado por Padrão)
input ENUM_TIMEFRAMES InpATRTimeframe      = PERIOD_CURRENT;     // Tempo Gráfico do ATR
input int             InpATRPeriod         = 14;                 // Período do ATR (Barras Fechadas)
input double          InpATRMulSL          = 1.5;                // Multiplicador ATR para Stop Loss
input double          InpATRMulTP          = 2.0;                // Multiplicador ATR para Take Profit
input bool            InpAutoApplyATR      = false;              // Aplicar Automaticamente ATR nos Alvos

input group "=== MODULARIDADE DA BOLETA (ESCOLHA O QUE EXIBIR NO SET) ==="
input bool            InpShowMarketStrip   = true;               // Exibir Faixa de Mercado (Ativo, Spread, Timer)
input bool            InpShowHUDStats      = true;               // Exibir 4 Cartões HUD (Capital, Lote, Lucro, Win%)
input bool            InpShowMentorAction  = true;               // Exibir Bloco de Ação Imediata do Mentor
input bool            InpShowRiskSection   = true;               // Exibir Linha de Gestão de Risco ($ / %)
input bool            InpShowLotSection    = true;               // Exibir Linha de Lote Operacional
input bool            InpShowSLSection     = true;               // Exibir Linha de Stop Loss (pts)
input bool            InpShowTPSection     = true;               // Exibir Linha de Take Profit (pts)
input bool            InpShowBESection     = true;               // Exibir Linha de Break Even (pts)
input bool            InpShowTSSection     = true;               // Exibir Linha de Trailing Stop (pts)
input bool            InpShowParcialSection= true;               // Exibir Seção de Realização Parcial
input bool            InpShowChannelsSection= true;              // Exibir Gaveta de Canais Manuais (40x40)
input bool            InpShowTradeButtons  = true;               // Exibir Botões Operacionais (COMPRA e VENDA)
input bool            InpShowInvertButton  = true;               // Exibir Botão Inverter Posição
input bool            InpShowHedgeButton   = true;               // Exibir Botão HEDGE (Trava Delta Neutro)
input bool            InpShowCloseButtons  = true;               // Exibir Botões Zerar Lucro / Zerar Prejuízo
input bool            InpShowCloseAll      = true;               // Exibir Botão Zerar Todas as Ordens (Rodapé)

input group "=== APURAÇÃO DE % ACERTOS E MÉTRICAS ==="
input ENUM_STATS_PERIOD InpStatsPeriod        = STATS_PERIOD_TODAY;       // Período de Apuração (% Acertos: Hoje, Data Escolhida ou Geral)
input datetime          InpStatsCustomDate   = D'2026.10.01 00:00';      // Data Inicial de Apuração (Ano.Mês.Dia)
input bool              InpShowStatsDateBar  = true;                     // Exibir Barra de Seleção de Data no Painel

input group "=== ESCALA VISUAL & ZOOM (TAMANHO DA BOLETA E FONTES) ==="
input ENUM_GUI_SCALE    InpGuiScale          = GUI_SCALE_115;            // Escala Visual da Boleta (Zoom / Proporção)

input group "=== REALIZAÇÃO PARCIAL ==="
input bool            InpParcialActive     = false;              // Parcial Inicial (Desmarcado por Padrão)
input bool            InpParcialIsCash     = false;              // Modo Alvo Parcial (false = Pontos, true = $)
input int             InpParcialTargetPts  = 150;                // Alvo da Parcial Padrão (pontos)
input double          InpParcialTargetCash = 25.0;               // Alvo da Parcial Padrão ($)
input double          InpParcialVolumePct  = 50.0;               // Volume da Parcial (% da Posição)
input bool            InpParcialMoveBE     = true;               // Mover SL p/ Zero a Zero pós Parcial

input group "=== CANAIS DE FREQUÊNCIA MANUAL (40 CIMA / 40 BAIXO) ==="
input int             InpProjUp            = 40;                 // Canais padrão para CIMA (Salvo em 40)
input int             InpProjDown          = 40;                 // Canais padrão para BAIXO (Salvo em 40)
input bool            InpCanalPushAlert    = true;               // Notificação Push no Rompimento
input bool            InpCanalScreenAlert  = true;               // Alerta Sonoro / Pop-up no Rompimento
input color           InpColorChannel      = C'220,50,50';       // Cor das Linhas Principais
input color           InpColorChannelMid   = C'235,185,40';      // Cor das Linhas Médias (50%)

input group "=== INCREMENTOS DOS BOTÕES (+ / -) ==="
input double          InpStepRiskCash      = 10.0;               // Passo do Risco Fixo ($)
input double          InpStepRiskPct       = 0.5;                // Passo do Risco Percentual (%)
input int             InpStepPoints        = 20;                 // Passo de Pontos (SL, TP, BE, TS, Parcial)
input double          InpStepParcialCash   = 5.0;                // Passo do Alvo Parcial ($)
input double          InpStepParcialVol    = 10.0;               // Passo do Volume Parcial (%)

input group "=== POSICIONAMENTO DA BOLETA ==="
input int             InpPanelX            = 20;                 // Posição Inicial X no Gráfico
input int             InpPanelY            = 40;                 // Posição Inicial Y no Gráfico

//+------------------------------------------------------------------+
//| Primitivos Gráficos Otimizados                                   |
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
//| Classe Master: CBoletaMaster                                     |
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
   double            m_gui_scale;
   bool              m_filter_symbol_only;
   
   bool              m_is_minimized;
   bool              m_is_dragging;
   int               m_drag_offset_x;
   int               m_drag_offset_y;
   
   // Parametros Operacionais
   ENUM_RISK_MODE    m_risk_mode;
   double            m_manual_lot;
   double            m_risk_cash;
   double            m_risk_percent;
   
   bool              m_sl_active;
   int               m_sl_points;
   bool              m_tp_active;
   int               m_tp_points;
   bool              m_be_active;
   int               m_be_points;
   bool              m_ts_active;
   int               m_ts_points;
   int               m_ts_step_points;
   
   // Parcial
   bool              m_parcial_active;
   bool              m_parcial_is_cash;
   int               m_parcial_target_pts;
   double            m_parcial_target_cash;
   double            m_parcial_vol_pct;
   bool              m_parcial_move_be;
   
   // Estatisticas & Apuracao
   ENUM_STATS_PERIOD m_stats_period;
   datetime          m_stats_custom_date;
   string            m_stats_date_str;
   
   double            m_initial_capital;
   double            m_today_pnl;
   double            m_win_rate;
   int               m_total_trades;
   int               m_win_trades;
   
   // Canais 40x40
   bool              m_channels_expanded;
   bool              m_marking_mode;
   int               m_mark_step;
   double            m_mark_price1;
   double            m_mark_price2;
   int               m_proj_up;
   int               m_proj_down;
   bool              m_chan_visible;
   
   // Motor Mentor Price Action
   int               m_ema_handle;
   double            m_active_pivot_high;
   datetime          m_active_high_time;
   double            m_active_pivot_low;
   datetime          m_active_low_time;
   string            m_mentor_action_text;
   color             m_mentor_action_color;
   string            m_mentor_wick_status;
   color             m_mentor_wick_color;
   double            m_dist_to_buy_pts;
   double            m_dist_to_sell_pts;
   double            m_dist_to_ema_pts;
   bool              m_mentor_auto_trading;
   bool              m_mentor_daily_locked;
   string            m_mentor_signal_ready;  // "BUY", "SELL", "NONE"
   datetime          m_last_mentor_trade_time;

   CTrade            m_trade;
   
   int Scale(int val) { return (int)MathRound(val * m_gui_scale); }

public:
   CBoletaMaster();
   ~CBoletaMaster() {}
   
   bool Init(const string sym, ulong magic, ulong slippage, int x, int y);
   void Destroy(const int reason);
   
   void Render();
   void UpdateLiveMetrics();
   void UpdateFieldValues();
   void UpdateLiveSLTPLines();
   void CheckForegroundState();
   
   void MovePanel(int new_x, int new_y);
   void ToggleMinimize();
   void CycleScale();
   void ToggleStatsScope();
   void SetStatsPeriod(ENUM_STATS_PERIOD p);
   void CycleStatsPeriod();
   void ApplyStatsCustomDate();
   
   void ToggleRiskAuto();
   void ToggleRiskMode();
   void RecalculateRiskLot();
   
   void ToggleSL()          { m_sl_active = !m_sl_active; if(m_sl_active && m_risk_mode != RISK_MODE_MANUAL) RecalculateRiskLot(); SaveState(); UpdateFieldValues(); UpdateLiveSLTPLines(); }
   void ToggleTP()          { m_tp_active = !m_tp_active; SaveState(); UpdateFieldValues(); UpdateLiveSLTPLines(); }
   void ToggleBE()          { m_be_active = !m_be_active; SaveState(); UpdateFieldValues(); }
   void ToggleTS()          { m_ts_active = !m_ts_active; SaveState(); UpdateFieldValues(); }
   void ToggleParcial()     { m_parcial_active = !m_parcial_active; SaveState(); UpdateFieldValues(); }
   void ToggleParcialMode() { m_parcial_is_cash = !m_parcial_is_cash; SaveState(); UpdateFieldValues(); }
   void ToggleParcialBE()   { m_parcial_move_be = !m_parcial_move_be; SaveState(); UpdateFieldValues(); }
   void ToggleMentorAuto()  { m_mentor_auto_trading = !m_mentor_auto_trading; SaveState(); UpdateFieldValues(); }
   void ToggleChannelsDrawer();

   // Steppers
   void StepLot(bool inc);
   void StepRisk(bool inc);
   void StepSL(bool inc);
   void StepTP(bool inc);
   void StepBE(bool inc);
   void StepTS(bool inc);
   void StepParcialTarget(bool inc);
   void StepParcialVol(bool inc);
   void StepChanUp(bool inc);
   void StepChanDn(bool inc);
   
   // Trading Executions
   void ExecuteBuy();
   void ExecuteSell();
   void ExecuteInvert();
   void ExecuteHedge();
   void ExecuteCloseAll();
   void ExecuteCloseProfit();
   void ExecuteCloseLoss();
   void ExecuteMentorSignal();
   
   // Canais
   void StartChannelMarking();
   void ProjectChannels();
   void ToggleChannelVisibility();
   void ClearChannels();
   void CheckChannelClick(double price);
   
   // Mentor Price Action
   void CalculateMentorPriceAction();
   void UpdateMentorTriggerLines();
   
   // Event Handler
   void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam);

   // Getters
   string GetSymbol()             { return m_symbol; }
   bool   IsBEActive()            { return m_be_active; }
   int    GetBEPoints()           { return m_be_points; }
   bool   IsTSActive()            { return m_ts_active; }
   int    GetTSPoints()           { return m_ts_points; }
   int    GetTSStepPoints()       { return m_ts_step_points; }
   bool   IsParcialActive()       { return m_parcial_active; }
   bool   IsParcialCashMode()     { return m_parcial_is_cash; }
   int    GetParcialTargetPoints(){ return m_parcial_target_pts; }
   double GetParcialTargetCash()  { return m_parcial_target_cash; }
   double GetParcialVolumePct()   { return m_parcial_vol_pct; }
   bool   IsParcialMoveBE()       { return m_parcial_move_be; }
   int    GetSLPoints()           { return m_sl_points; }
   int    GetTPPoints()           { return m_tp_points; }
   void   SetSLPoints(int pts)    { m_sl_points = pts; }
   void   SetTPPoints(int pts)    { m_tp_points = pts; }
   bool   GetATRTargets(int &atr_p, int &sug_sl, int &sug_tp);
   void   ApplyATRTargets();

private:
   void SaveState();
   void LoadState();
   void ClearState();
   void CalculateDashboardStats();
};

//+------------------------------------------------------------------+
//| Construtor                                                       |
//+------------------------------------------------------------------+
CBoletaMaster::CBoletaMaster()
{
   m_symbol             = _Symbol;
   m_magic              = InpMagicNumber;
   m_slippage           = InpSlippage;
   m_chart_id           = 0;
   m_x                  = InpPanelX;
   m_y                  = InpPanelY;
   m_gui_scale          = 1.15;
   m_width              = 318;
   m_height             = 680;
   m_header_h           = 26;
   m_filter_symbol_only = InpFilterSymbolOnly;
   
   m_is_minimized       = false;
   m_is_dragging        = false;
   m_drag_offset_x      = 0;
   m_drag_offset_y      = 0;
   
   m_risk_mode          = InpDefaultRiskMode;
   m_manual_lot         = InpDefaultLot;
   m_risk_cash          = InpRiskCash;
   m_risk_percent       = InpRiskPercent;
   
   m_sl_active          = InpSLActive;
   m_sl_points          = InpDefaultSL;
   m_tp_active          = InpTPActive;
   m_tp_points          = InpDefaultTP;
   m_be_active          = InpBEActive;
   m_be_points          = InpDefaultBE;
   m_ts_active          = InpTSActive;
   m_ts_points          = InpDefaultTS;
   m_ts_step_points     = InpDefaultTSStep;
   
   m_parcial_active     = InpParcialActive;
   m_parcial_is_cash    = InpParcialIsCash;
   m_parcial_target_pts = InpParcialTargetPts;
   m_parcial_target_cash= InpParcialTargetCash;
   m_parcial_vol_pct    = InpParcialVolumePct;
   m_parcial_move_be    = InpParcialMoveBE;
   
   m_stats_period       = InpStatsPeriod;
   m_stats_custom_date  = InpStatsCustomDate;
   m_stats_date_str     = TimeToString(InpStatsCustomDate, TIME_DATE);
   
   m_initial_capital    = 0.0;
   m_today_pnl          = 0.0;
   m_win_rate           = 0.0;
   m_total_trades       = 0;
   m_win_trades         = 0;
   
   m_channels_expanded  = false;
   m_marking_mode       = false;
   m_mark_step          = 0;
   m_mark_price1        = 0.0;
   m_mark_price2        = 0.0;
   m_proj_up            = InpProjUp;
   m_proj_down          = InpProjDown;
   m_chan_visible       = true;
   
   m_ema_handle         = INVALID_HANDLE;
   m_active_pivot_high  = 0.0;
   m_active_high_time   = 0;
   m_active_pivot_low   = 0.0;
   m_active_low_time    = 0;
   m_mentor_action_text = "AGUARDANDO PIVÔ";
   m_mentor_action_color= COLOR_TEXT_MUTED;
   m_mentor_wick_status = "Pavio: -- pts";
   m_mentor_wick_color  = COLOR_TEXT_MUTED;
   m_dist_to_buy_pts    = 9999.0;
   m_dist_to_sell_pts   = 9999.0;
   m_dist_to_ema_pts    = 0.0;
   m_mentor_auto_trading= InpMentorAutoTrading;
   m_mentor_daily_locked= false;
   m_mentor_signal_ready= "NONE";
   m_last_mentor_trade_time = 0;
}

//+------------------------------------------------------------------+
//| Inicializacao                                                    |
//+------------------------------------------------------------------+
bool CBoletaMaster::Init(const string sym, ulong magic, ulong slippage, int x, int y)
{
   m_symbol   = (sym != "") ? sym : _Symbol;
   m_magic    = magic;
   m_slippage = slippage;
   m_chart_id = ChartID();
   m_x        = x;
   m_y        = y;
   
   switch(InpGuiScale)
   {
      case GUI_SCALE_100: m_gui_scale = 1.0;  break;
      case GUI_SCALE_115: m_gui_scale = 1.15; break;
      case GUI_SCALE_130: m_gui_scale = 1.30; break;
      case GUI_SCALE_150: m_gui_scale = 1.50; break;
      default:            m_gui_scale = 1.15; break;
   }
   
   m_width    = Scale(276);
   m_header_h = Scale(26);
   
   m_trade.SetExpertMagicNumber(m_magic);
   m_trade.SetDeviationInPoints(m_slippage);
   SetBestFillingMode(m_trade, m_symbol);
   
   if(InpEnableMentor)
      m_ema_handle = iMA(m_symbol, Period(), InpEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   
   LoadState();
   CalculateDashboardStats();
   CalculateMentorPriceAction();
   Render();
   UpdateFieldValues();
   UpdateLiveMetrics();
   UpdateLiveSLTPLines();
   
   return true;
}

//+------------------------------------------------------------------+
//| Destruidor Seguro                                                |
//+------------------------------------------------------------------+
void CBoletaMaster::Destroy(const int reason)
{
   ObjectsDeleteAll(m_chart_id, PREFIX_GUI);
   ObjectsDeleteAll(m_chart_id, "BSCALP_LIVE_");
   ObjectsDeleteAll(m_chart_id, PREFIX_MENTOR);
   
   if(reason != REASON_CHARTCHANGE && reason != REASON_PARAMETERS && reason != REASON_RECOMPILE)
   {
      ClearChannels();
      ClearState();
   }
   if(m_ema_handle != INVALID_HANDLE)
   {
      IndicatorRelease(m_ema_handle);
      m_ema_handle = INVALID_HANDLE;
   }
   ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Persistencia de Estado Global                                    |
//+------------------------------------------------------------------+
void CBoletaMaster::SaveState()
{
   string pfx = "BSCALP_GV_" + m_symbol + "_";
   GlobalVariableSet(pfx + "Scale",       m_gui_scale);
   GlobalVariableSet(pfx + "X",           (double)m_x);
   GlobalVariableSet(pfx + "Y",           (double)m_y);
   GlobalVariableSet(pfx + "Min",         m_is_minimized ? 1.0 : 0.0);
   GlobalVariableSet(pfx + "RiskMode",    (double)m_risk_mode);
   GlobalVariableSet(pfx + "Lot",         m_manual_lot);
   GlobalVariableSet(pfx + "RiskCash",    m_risk_cash);
   GlobalVariableSet(pfx + "RiskPct",     m_risk_percent);
   GlobalVariableSet(pfx + "SLActive",    m_sl_active ? 1.0 : 0.0);
   GlobalVariableSet(pfx + "SLPts",       (double)m_sl_points);
   GlobalVariableSet(pfx + "TPActive",    m_tp_active ? 1.0 : 0.0);
   GlobalVariableSet(pfx + "TPPts",       (double)m_tp_points);
   GlobalVariableSet(pfx + "BEActive",    m_be_active ? 1.0 : 0.0);
   GlobalVariableSet(pfx + "BEPts",       (double)m_be_points);
   GlobalVariableSet(pfx + "TSActive",    m_ts_active ? 1.0 : 0.0);
   GlobalVariableSet(pfx + "TSPts",       (double)m_ts_points);
   GlobalVariableSet(pfx + "ParcActive",  m_parcial_active ? 1.0 : 0.0);
   GlobalVariableSet(pfx + "ParcMode",    m_parcial_is_cash ? 1.0 : 0.0);
   GlobalVariableSet(pfx + "ParcTarget",  m_parcial_is_cash ? m_parcial_target_cash : (double)m_parcial_target_pts);
   GlobalVariableSet(pfx + "ParcVol",     m_parcial_vol_pct);
   GlobalVariableSet(pfx + "ParcBE",      m_parcial_move_be ? 1.0 : 0.0);
   GlobalVariableSet(pfx + "MentorAuto",  m_mentor_auto_trading ? 1.0 : 0.0);
}

void CBoletaMaster::LoadState()
{
   string pfx = "BSCALP_GV_" + m_symbol + "_";
   if(GlobalVariableCheck(pfx + "Scale"))       m_gui_scale           = GlobalVariableGet(pfx + "Scale");
   if(GlobalVariableCheck(pfx + "X"))           m_x                   = (int)GlobalVariableGet(pfx + "X");
   if(GlobalVariableCheck(pfx + "Y"))           m_y                   = (int)GlobalVariableGet(pfx + "Y");
   if(GlobalVariableCheck(pfx + "Min"))         m_is_minimized        = (GlobalVariableGet(pfx + "Min") > 0.5);
   if(GlobalVariableCheck(pfx + "RiskMode"))    m_risk_mode           = (ENUM_RISK_MODE)(int)GlobalVariableGet(pfx + "RiskMode");
   if(GlobalVariableCheck(pfx + "Lot"))         m_manual_lot          = NormalizeLot(GlobalVariableGet(pfx + "Lot"), m_symbol);
   if(GlobalVariableCheck(pfx + "RiskCash"))    m_risk_cash           = GlobalVariableGet(pfx + "RiskCash");
   if(GlobalVariableCheck(pfx + "RiskPct"))     m_risk_percent        = GlobalVariableGet(pfx + "RiskPct");
   if(GlobalVariableCheck(pfx + "SLActive"))    m_sl_active           = (GlobalVariableGet(pfx + "SLActive") > 0.5);
   if(GlobalVariableCheck(pfx + "SLPts"))       m_sl_points           = (int)GlobalVariableGet(pfx + "SLPts");
   if(GlobalVariableCheck(pfx + "TPActive"))    m_tp_active           = (GlobalVariableGet(pfx + "TPActive") > 0.5);
   if(GlobalVariableCheck(pfx + "TPPts"))       m_tp_points           = (int)GlobalVariableGet(pfx + "TPPts");
   if(GlobalVariableCheck(pfx + "BEActive"))    m_be_active           = (GlobalVariableGet(pfx + "BEActive") > 0.5);
   if(GlobalVariableCheck(pfx + "BEPts"))       m_be_points           = (int)GlobalVariableGet(pfx + "BEPts");
   if(GlobalVariableCheck(pfx + "TSActive"))    m_ts_active           = (GlobalVariableGet(pfx + "TSActive") > 0.5);
   if(GlobalVariableCheck(pfx + "TSPts"))       m_ts_points           = (int)GlobalVariableGet(pfx + "TSPts");
   if(GlobalVariableCheck(pfx + "ParcActive"))  m_parcial_active      = (GlobalVariableGet(pfx + "ParcActive") > 0.5);
   if(GlobalVariableCheck(pfx + "ParcMode"))    m_parcial_is_cash     = (GlobalVariableGet(pfx + "ParcMode") > 0.5);
   if(GlobalVariableCheck(pfx + "ParcTarget"))
   {
      if(m_parcial_is_cash) m_parcial_target_cash = GlobalVariableGet(pfx + "ParcTarget");
      else                  m_parcial_target_pts  = (int)GlobalVariableGet(pfx + "ParcTarget");
   }
   if(GlobalVariableCheck(pfx + "ParcVol"))     m_parcial_vol_pct     = GlobalVariableGet(pfx + "ParcVol");
   if(GlobalVariableCheck(pfx + "ParcBE"))      m_parcial_move_be     = (GlobalVariableGet(pfx + "ParcBE") > 0.5);
   if(GlobalVariableCheck(pfx + "MentorAuto"))  m_mentor_auto_trading = (GlobalVariableGet(pfx + "MentorAuto") > 0.5);
}

void CBoletaMaster::ClearState()
{
   string pfx = "BSCALP_GV_" + m_symbol + "_";
   GlobalVariablesDeleteAll(pfx);
}

//+------------------------------------------------------------------+
//| Calculo Estatistico do HUD                                       |
//+------------------------------------------------------------------+
void CBoletaMaster::CalculateDashboardStats()
{
   datetime start_dt = 0;
   MqlDateTime dt_now;
   TimeCurrent(dt_now);
   
   switch(m_stats_period)
   {
      case STATS_PERIOD_TODAY:
      {
         dt_now.hour = 0; dt_now.min = 0; dt_now.sec = 0;
         start_dt = StructToTime(dt_now);
         break;
      }
      case STATS_PERIOD_CUSTOM:
      {
         start_dt = m_stats_custom_date;
         break;
      }
      case STATS_PERIOD_7D:
      {
         start_dt = TimeCurrent() - (7 * 86400);
         break;
      }
      case STATS_PERIOD_30D:
      {
         start_dt = TimeCurrent() - (30 * 86400);
         break;
      }
      case STATS_PERIOD_ALL:
      default:
      {
         start_dt = 0;
         break;
      }
   }
   
   HistorySelect(start_dt, TimeCurrent() + 60);
   
   m_today_pnl    = 0.0;
   m_total_trades = 0;
   m_win_trades   = 0;
   
   int total_deals = HistoryDealsTotal();
   for(int i = 0; i < total_deals; i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0) continue;
      
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;
      
      if(m_filter_symbol_only && HistoryDealGetString(deal_ticket, DEAL_SYMBOL) != m_symbol)
         continue;
      
      double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
      double comm   = HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
      double swap   = HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
      double net    = profit + comm + swap;
      
      m_today_pnl += net;
      m_total_trades++;
      if(net > 0.00001) m_win_trades++;
   }
   
   m_win_rate = (m_total_trades > 0) ? ((double)m_win_trades / (double)m_total_trades) * 100.0 : 0.0;
   m_initial_capital = AccountInfoDouble(ACCOUNT_BALANCE) - m_today_pnl;
   if(m_initial_capital < 0.0) m_initial_capital = AccountInfoDouble(ACCOUNT_BALANCE);
}

//+------------------------------------------------------------------+
//| Gestao de Risco Dinamica ($ / %)                                 |
//+------------------------------------------------------------------+
void CBoletaMaster::RecalculateRiskLot()
{
   if(m_risk_mode == RISK_MODE_MANUAL || !m_sl_active || m_sl_points <= 0)
      return;
   
   double target_loss = 0.0;
   if(m_risk_mode == RISK_MODE_CASH)
      target_loss = m_risk_cash;
   else if(m_risk_mode == RISK_MODE_PERCENT)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      target_loss   = equity * (m_risk_percent / 100.0);
   }
   
   if(target_loss <= 0.0) return;
   
   double tick_val  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_sz   = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   
   if(tick_sz <= 0.0 || point <= 0.0 || tick_val <= 0.0) return;
   
   double point_value_1lot = (tick_val / tick_sz) * point;
   double total_point_loss_1lot = m_sl_points * point_value_1lot;
   
   if(total_point_loss_1lot > 0.0)
   {
      double calculated_lot = target_loss / total_point_loss_1lot;
      m_manual_lot = NormalizeLot(calculated_lot, m_symbol);
   }
}

//+------------------------------------------------------------------+
//| Motor Mentor Price Action Pro: Pivôs, Pavio & Ação Imediata      |
//+------------------------------------------------------------------+
void CBoletaMaster::CalculateMentorPriceAction()
{
   if(!InpEnableMentor) return;
   
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(m_symbol, Period(), 0, 300, rates);
   if(copied < 100) return;
   
   // 1. Deteccao de Pivôs com Alternancia Estrita
   SwingPoint rawPoints[];
   ArrayResize(rawPoints, 0);
   
   for(int i = 250; i >= 1; i--)
   {
      int swBar = i + InpSwingStrength;
      if(swBar < copied - InpSwingStrength)
      {
         bool isH = true, isL = true;
         double hVal = rates[swBar].high;
         double lVal = rates[swBar].low;
         
         for(int k = 1; k <= InpSwingStrength; k++)
         {
            if(rates[swBar - k].high >= hVal || rates[swBar + k].high > hVal) isH = false;
            if(rates[swBar - k].low <= lVal || rates[swBar + k].low < lVal)   isL = false;
         }
         
         if(isH && isL)
         {
            if(rates[swBar].close >= rates[swBar].open) isL = false;
            else isH = false;
         }
         
         if(isH)
         {
            int sz = ArraySize(rawPoints);
            ArrayResize(rawPoints, sz + 1);
            rawPoints[sz].time     = rates[swBar].time;
            rawPoints[sz].price    = hVal;
            rawPoints[sz].barIndex = swBar;
            rawPoints[sz].isHigh   = true;
         }
         else if(isL)
         {
            int sz = ArraySize(rawPoints);
            ArrayResize(rawPoints, sz + 1);
            rawPoints[sz].time     = rates[swBar].time;
            rawPoints[sz].price    = lVal;
            rawPoints[sz].barIndex = swBar;
            rawPoints[sz].isHigh   = false;
         }
      }
   }
   
   // 2. Filtragem de Alternancia
   SwingPoint cleanPoints[];
   ArrayResize(cleanPoints, 0);
   int rawCount = ArraySize(rawPoints);
   for(int r = 0; r < rawCount; r++)
   {
      int cCount = ArraySize(cleanPoints);
      if(cCount == 0)
      {
         ArrayResize(cleanPoints, 1);
         cleanPoints[0] = rawPoints[r];
      }
      else
      {
         if(rawPoints[r].isHigh == cleanPoints[cCount - 1].isHigh)
         {
            if(rawPoints[r].isHigh)
            {
               if(rawPoints[r].price > cleanPoints[cCount - 1].price) cleanPoints[cCount - 1] = rawPoints[r];
            }
            else
            {
               if(rawPoints[r].price < cleanPoints[cCount - 1].price) cleanPoints[cCount - 1] = rawPoints[r];
            }
         }
         else
         {
            ArrayResize(cleanPoints, cCount + 1);
            cleanPoints[cCount] = rawPoints[r];
         }
      }
   }
   
   // 3. Atualizar Topo e Fundo Ativos
   int cSz = ArraySize(cleanPoints);
   for(int c = cSz - 1; c >= 0; c--)
   {
      if(cleanPoints[c].isHigh && m_active_pivot_high == 0.0)
      {
         m_active_pivot_high = cleanPoints[c].price;
         m_active_high_time  = cleanPoints[c].time;
      }
      else if(!cleanPoints[c].isHigh && m_active_pivot_low == 0.0)
      {
         m_active_pivot_low  = cleanPoints[c].price;
         m_active_low_time   = cleanPoints[c].time;
      }
      if(m_active_pivot_high > 0.0 && m_active_pivot_low > 0.0) break;
   }
   
   double curPrice = rates[0].close;
   double point    = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0.0) point = 0.01;
   
   m_dist_to_buy_pts  = (m_active_pivot_high > 0.0) ? (m_active_pivot_high - curPrice) / point : 9999.0;
   m_dist_to_sell_pts = (m_active_pivot_low > 0.0)  ? (curPrice - m_active_pivot_low) / point  : 9999.0;
   
   // 4. Distancia da EMA 200 (Bússola / Ímã)
   double emaVal[1];
   if(m_ema_handle != INVALID_HANDLE && CopyBuffer(m_ema_handle, 0, 0, 1, emaVal) > 0)
      m_dist_to_ema_pts = MathAbs(curPrice - emaVal[0]) / point;
   else
      m_dist_to_ema_pts = 0.0;
   
   // 5. Auditoria de Microestrutura de Pavio (Candle 0)
   double cLowerWick0 = (MathMin(rates[0].open, rates[0].close) - rates[0].low) / point;
   double cUpperWick0 = (rates[0].high - MathMax(rates[0].open, rates[0].close)) / point;
   bool wickBuyOk  = (cLowerWick0 >= InpMinWickPoints);
   bool wickSellOk = (cUpperWick0 >= InpMinWickPoints);
   
   if(rates[0].close >= rates[0].open)
   {
      if(wickBuyOk)
      {
         m_mentor_wick_status = StringFormat("Pavio Inf: %.0f pts (Mola Pronta)", cLowerWick0);
         m_mentor_wick_color  = clrSpringGreen;
      }
      else
      {
         m_mentor_wick_status = StringFormat("Pavio Inf: %.0f pts (Vela Careca!)", cLowerWick0);
         m_mentor_wick_color  = COLOR_MENTOR_WARN_BALD;
      }
   }
   else
   {
      if(wickSellOk)
      {
         m_mentor_wick_status = StringFormat("Pavio Sup: %.0f pts (Mola Pronta)", cUpperWick0);
         m_mentor_wick_color  = clrSpringGreen;
      }
      else
      {
         m_mentor_wick_status = StringFormat("Pavio Sup: %.0f pts (Vela Careca!)", cUpperWick0);
         m_mentor_wick_color  = COLOR_MENTOR_WARN_BALD;
      }
   }
   
   // 6. Maquina de Estados de Acao Imediata do Mentor
   m_mentor_signal_ready = "NONE";
   
   // Trava de Meta Diaria contra Overtrading
   if(InpMentorDailyTarget > 0.0 && m_today_pnl >= InpMentorDailyTarget)
   {
      m_mentor_daily_locked = true;
      m_mentor_action_text  = "🎯 META BATIDA! FECHE A TELA!";
      m_mentor_action_color = clrAqua;
      return;
   }
   else
   {
      m_mentor_daily_locked = false;
   }
   
   // Rompimento de Topo (Compra)
   if(m_dist_to_buy_pts <= 0.0)
   {
      if(!InpRequireWickFilter || wickBuyOk)
      {
         m_mentor_action_text  = "🚀 EXECUTAR COMPRA PIVÔ! ↗";
         m_mentor_action_color = COLOR_MENTOR_BUY_LIME;
         m_mentor_signal_ready = "BUY";
      }
      else
      {
         m_mentor_action_text  = "⛔ VELA CARECA! (NÃO OPERAR)";
         m_mentor_action_color = COLOR_MENTOR_WARN_BALD;
      }
   }
   // Rompimento de Fundo (Venda)
   else if(m_dist_to_sell_pts <= 0.0)
   {
      if(!InpRequireWickFilter || wickSellOk)
      {
         m_mentor_action_text  = "📉 EXECUTAR VENDA PIVÔ! ↘";
         m_mentor_action_color = COLOR_MENTOR_SELL_MAG;
         m_mentor_signal_ready = "SELL";
      }
      else
      {
         m_mentor_action_text  = "⛔ VELA CARECA! (NÃO OPERAR)";
         m_mentor_action_color = COLOR_MENTOR_WARN_BALD;
      }
   }
   // Preparar Boleta
   else if(m_dist_to_buy_pts <= 45.0)
   {
      m_mentor_action_text  = StringFormat("⚠️ PREPARAR COMPRA (Faltam %.0f pts) ↗", m_dist_to_buy_pts);
      m_mentor_action_color = COLOR_MENTOR_PREP_GOLD;
   }
   else if(m_dist_to_sell_pts <= 45.0)
   {
      m_mentor_action_text  = StringFormat("⚠️ PREPARAR VENDA (Faltam %.0f pts) ↘", m_dist_to_sell_pts);
      m_mentor_action_color = COLOR_MENTOR_PREP_GOLD;
   }
   else
   {
      m_mentor_action_text  = "⏳ AGUARDANDO PIVÔ (CONSOLIDAÇÃO)";
      m_mentor_action_color = COLOR_TEXT_MUTED;
   }
   
   // Auto Scalper Mentor (Execucao Automatizada Opcional)
   if(m_mentor_auto_trading && !m_mentor_daily_locked)
   {
      datetime barTime = rates[0].time;
      if(barTime != m_last_mentor_trade_time)
      {
         if(m_mentor_signal_ready == "BUY")
         {
            m_last_mentor_trade_time = barTime;
            ExecuteMentorSignal();
         }
         else if(m_mentor_signal_ready == "SELL")
         {
            m_last_mentor_trade_time = barTime;
            ExecuteMentorSignal();
         }
      }
   }
   
   UpdateMentorTriggerLines();
}

//+------------------------------------------------------------------+
//| Linhas de Rompimento Projetadas do Mentor                        |
//+------------------------------------------------------------------+
void CBoletaMaster::UpdateMentorTriggerLines()
{
   if(!InpDrawMentorLevels || !InpEnableMentor)
   {
      ObjectsDeleteAll(m_chart_id, PREFIX_MENTOR);
      return;
   }
   
   string buyLineName = PREFIX_MENTOR + "TRIG_BUY";
   string sellLineName= PREFIX_MENTOR + "TRIG_SELL";
   
   if(m_active_pivot_high > 0.0)
   {
      if(ObjectFind(m_chart_id, buyLineName) < 0)
         ObjectCreate(m_chart_id, buyLineName, OBJ_HLINE, 0, 0, m_active_pivot_high);
      ObjectSetDouble(m_chart_id, buyLineName, OBJPROP_PRICE, m_active_pivot_high);
      ObjectSetInteger(m_chart_id, buyLineName, OBJPROP_COLOR, InpColorMentorBuy);
      ObjectSetInteger(m_chart_id, buyLineName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(m_chart_id, buyLineName, OBJPROP_WIDTH, 2);
      ObjectSetString(m_chart_id, buyLineName, OBJPROP_TOOLTIP, StringFormat("⚡ GATILHO COMPRA PIVÔ: Romper %.2f ↗", m_active_pivot_high));
   }
   
   if(m_active_pivot_low > 0.0)
   {
      if(ObjectFind(m_chart_id, sellLineName) < 0)
         ObjectCreate(m_chart_id, sellLineName, OBJ_HLINE, 0, 0, m_active_pivot_low);
      ObjectSetDouble(m_chart_id, sellLineName, OBJPROP_PRICE, m_active_pivot_low);
      ObjectSetInteger(m_chart_id, sellLineName, OBJPROP_COLOR, InpColorMentorSell);
      ObjectSetInteger(m_chart_id, sellLineName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(m_chart_id, sellLineName, OBJPROP_WIDTH, 2);
      ObjectSetString(m_chart_id, sellLineName, OBJPROP_TOOLTIP, StringFormat("⚡ GATILHO VENDA PIVÔ: Romper %.2f ↘", m_active_pivot_low));
   }
}

//+------------------------------------------------------------------+
//| Renderizacao Completa da Boleta com Bloco Mentor                 |
//+------------------------------------------------------------------+
void CBoletaMaster::Render()
{
   ChartSetInteger(m_chart_id, CHART_FOREGROUND, false);
   ObjectsDeleteAll(m_chart_id, PREFIX_GUI);
   
   int pad_x    = Scale(8);
   int offset_x = m_x + pad_x;
   int row_w    = m_width - (pad_x * 2);
   
   int initial_h = m_is_minimized ? m_header_h : (m_height > m_header_h ? m_height : Scale(720));
   GUI_CreateRectangleLabel(m_chart_id, PREFIX_GUI + "Panel_BG", m_x, m_y, m_width, initial_h, COLOR_PANEL_BG, COLOR_BORDER, ZORDER_PANEL_BG);
   GUI_CreateRectangleLabel(m_chart_id, PREFIX_GUI + "Header_BG", m_x, m_y, m_width, m_header_h, COLOR_HEADER_BG, COLOR_BORDER, ZORDER_PANEL_STRIP);
   GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Header_Title", m_x + Scale(10), m_y + Scale(6), "SCALP MENTOR PRO v11", COLOR_TEXT_MAIN, 9, true);
   
   int btn_h  = Scale(20);
   int gap_h  = Scale(4);
   int zoom_w = Scale(38);
   
   int close_x = m_x + m_width - pad_x - btn_h;
   int min_x   = close_x - gap_h - btn_h;
   int zoom_x  = min_x - gap_h - zoom_w;
   
   string zoom_txt = StringFormat("%.0f%%", m_gui_scale * 100.0);
   GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Zoom", zoom_x, m_y + Scale(4), zoom_w, btn_h, zoom_txt, COLOR_EDIT_BG, COLOR_LOT_GOLD, 8, true);
   GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Min",  min_x,  m_y + Scale(4), btn_h,  btn_h, m_is_minimized ? "+" : "-", COLOR_EDIT_BG, COLOR_TEXT_MAIN, 9, true);
   GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Close",close_x,m_y + Scale(4), btn_h,  btn_h, "X", COLOR_SELL_BTN, COLOR_TEXT_MAIN, 9, true);
   
   if(m_is_minimized)
   {
      ChartRedraw(m_chart_id);
      return;
   }
   
   int cur_y = m_y + m_header_h + Scale(4);
   
   // 2. Faixa de Mercado
   if(InpShowMarketStrip)
   {
      int strip_h = Scale(24);
      GUI_CreateRectangleLabel(m_chart_id, PREFIX_GUI + "Strip_Market_BG", offset_x, cur_y, row_w, strip_h, COLOR_MARKET_BG, COLOR_BORDER, ZORDER_PANEL_STRIP);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Mkt_Symbol", offset_x + Scale(8), cur_y + Scale(4), m_symbol, clrGold, 9, true);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Mkt_Spread", offset_x + (int)(row_w * 0.42), cur_y + Scale(4), "Sp: --", clrWhite, 9, false);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Mkt_Timer",  offset_x + (int)(row_w * 0.68), cur_y + Scale(4), "[TF] --:--", clrCyan, 9, true);
      cur_y += strip_h + Scale(4);
   }
   
   // 3. Cartões HUD de Confiança
   if(InpShowHUDStats)
   {
      int card_gap = Scale(6);
      int card_w   = (row_w - card_gap) / 2;
      int card_h   = Scale(26);
      
      GUI_CreateRectangleLabel(m_chart_id, PREFIX_GUI + "Card_Cap_BG", offset_x, cur_y, card_w, card_h, COLOR_CARD_BG, COLOR_CARD_BORDER, ZORDER_PANEL_STRIP);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Cap_Title", offset_x + Scale(6), cur_y + Scale(1), "CAP. INICIAL", COLOR_TEXT_MUTED, 7, false);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Cap_Val",   offset_x + Scale(6), cur_y + Scale(11), "$0.00", clrWhite, 9, true);
      
      GUI_CreateRectangleLabel(m_chart_id, PREFIX_GUI + "Card_Lot_BG", offset_x + card_w + card_gap, cur_y, card_w, card_h, COLOR_CARD_BG, COLOR_CARD_BORDER, ZORDER_PANEL_STRIP);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Lot_Title", offset_x + card_w + card_gap + Scale(6), cur_y + Scale(1), "LOTE ATUAL", COLOR_TEXT_MUTED, 7, false);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Lot_Val",   offset_x + card_w + card_gap + Scale(6), cur_y + Scale(11), DoubleToString(m_manual_lot, 2), COLOR_LOT_GOLD, 9, true);
      cur_y += card_h + Scale(3);
      
      GUI_CreateRectangleLabel(m_chart_id, PREFIX_GUI + "Card_Pnl_BG", offset_x, cur_y, card_w, card_h, COLOR_CARD_BG, COLOR_CARD_BORDER, ZORDER_PANEL_STRIP);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Pnl_Title", offset_x + Scale(6), cur_y + Scale(1), "LUCRO HOJE", COLOR_TEXT_MUTED, 7, false);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Pnl_Val",   offset_x + Scale(6), cur_y + Scale(11), "$0.00", COLOR_PROFIT_GREEN, 9, true);
      
      GUI_CreateRectangleLabel(m_chart_id, PREFIX_GUI + "Card_Win_BG", offset_x + card_w + card_gap, cur_y, card_w, card_h, COLOR_CARD_BG, COLOR_CARD_BORDER, ZORDER_PANEL_STRIP);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Win_Title", offset_x + card_w + card_gap + Scale(6), cur_y + Scale(1), "% ACERTOS", COLOR_TEXT_MUTED, 7, false);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Win_Val",   offset_x + card_w + card_gap + Scale(6), cur_y + Scale(11), "0.0%", COLOR_CHECK_ACTIVE, 8, true);
      cur_y += card_h + Scale(4);
      
      if(InpShowStatsDateBar)
      {
         color c_today = (m_stats_period == STATS_PERIOD_TODAY)  ? COLOR_CHECK_ACTIVE : COLOR_STEP_BTN;
         color c_7d    = (m_stats_period == STATS_PERIOD_7D)     ? COLOR_CHECK_ACTIVE : COLOR_STEP_BTN;
         color c_all   = (m_stats_period == STATS_PERIOD_ALL)    ? COLOR_CHECK_ACTIVE : COLOR_STEP_BTN;
         color c_cust  = (m_stats_period == STATS_PERIOD_CUSTOM) ? COLOR_CHECK_ACTIVE : COLOR_STEP_BTN;
         color c_scope = (!m_filter_symbol_only)                 ? clrTeal : COLOR_STEP_BTN;
         
         int b_h       = Scale(20);
         int b_today_w = Scale(36);
         int b_7d_w    = Scale(28);
         int b_all_w   = Scale(36);
         int b_scope_w = Scale(42);
         int b_ok_w    = Scale(28);
         int gap_b     = Scale(3);
         
         int x_cur = offset_x;
         GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Stats_Today", x_cur, cur_y, b_today_w, b_h, "Hoje", c_today, (m_stats_period == STATS_PERIOD_TODAY) ? clrBlack : clrWhite, 7, true);
         x_cur += b_today_w + gap_b;
         
         GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Stats_7D",    x_cur, cur_y, b_7d_w, b_h, "7D", c_7d, (m_stats_period == STATS_PERIOD_7D) ? clrBlack : clrWhite, 7, true);
         x_cur += b_7d_w + gap_b;
         
         GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Stats_All",   x_cur, cur_y, b_all_w, b_h, "Geral", c_all, (m_stats_period == STATS_PERIOD_ALL) ? clrBlack : clrWhite, 7, true);
         x_cur += b_all_w + gap_b;
         
         string scope_txt = (!m_filter_symbol_only) ? "Conta" : "Ativo";
         GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Stats_Scope", x_cur, cur_y, b_scope_w, b_h, scope_txt, c_scope, clrWhite, 7, true);
         x_cur += b_scope_w + gap_b;
         
         int right_edge = offset_x + row_w;
         int ok_x = right_edge - b_ok_w;
         int edit_w = ok_x - x_cur - gap_b;
         if(edit_w < Scale(46)) edit_w = Scale(46);
         
         GUI_CreateEdit(m_chart_id, PREFIX_GUI + "Edit_Stats_Date",   x_cur, cur_y, edit_w, b_h, m_stats_date_str, COLOR_EDIT_BG, (m_stats_period == STATS_PERIOD_CUSTOM) ? clrGold : COLOR_TEXT_MAIN, false, 8);
         GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Stats_Apply", ok_x,  cur_y, b_ok_w,  b_h, "OK", c_cust, (m_stats_period == STATS_PERIOD_CUSTOM) ? clrBlack : clrWhite, 7, true);
         cur_y += b_h + Scale(4);
      }
   }
   
   // 4. Bloco de Ação Imediata do Mentor Price Action Pro
   if(InpShowMentorAction && InpEnableMentor)
   {
      int mentor_h = Scale(56);
      GUI_CreateRectangleLabel(m_chart_id, PREFIX_GUI + "Mentor_Box_BG", offset_x, cur_y, row_w, mentor_h, COLOR_SECTION_BG, COLOR_BORDER, ZORDER_PANEL_STRIP);
      
      // Banner de Ação
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Mentor_Action", offset_x + Scale(3), cur_y + Scale(3), row_w - Scale(6), Scale(24), m_mentor_action_text, COLOR_HEADER_BG, m_mentor_action_color, 8, true);
      
      // Sublinha de Microestrutura (Pavio & EMA 200)
      string ema_str = StringFormat("EMA 200: %.0f pts", m_dist_to_ema_pts);
      int half_w = (row_w - Scale(10)) / 2;
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Mentor_Wick", offset_x + Scale(6), cur_y + Scale(32), m_mentor_wick_status, m_mentor_wick_color, 8, true);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Mentor_Ema",  offset_x + half_w + Scale(8), cur_y + Scale(32), ema_str, clrDeepSkyBlue, 8, false);
      cur_y += mentor_h + Scale(3);
      
      // Linha de Execução do Sinal Mentor & Checkbox Auto
      int auto_w = Scale(96);
      int exec_w = row_w - auto_w - Scale(4);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Chk_Mentor_Auto", offset_x, cur_y, auto_w, Scale(22), m_mentor_auto_trading ? "[X] Auto Scalp" : "[ ] Auto Scalp", m_mentor_auto_trading ? COLOR_CHECK_ACTIVE : COLOR_EDIT_BG, clrWhite, 8, true);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Mentor_Execute", offset_x + auto_w + Scale(4), cur_y, exec_w, Scale(22), "⚡ ENTRAR SINAL MENTOR", (m_mentor_signal_ready != "NONE") ? clrGold : COLOR_STEP_BTN, (m_mentor_signal_ready != "NONE") ? clrBlack : COLOR_TEXT_MUTED, 8, true);
      cur_y += Scale(22) + Scale(4);
   }
   
   // Metricas de Controles Bounded e Responsivos
   int row_h      = Scale(24);
   int row_gap    = Scale(4);
   int chk_sz     = Scale(18);
   int step_btn_w = Scale(22);
   int edit_box_w = Scale(62);
   int btn_gap    = Scale(2);
   int controls_w = step_btn_w + btn_gap + edit_box_w + btn_gap + step_btn_w;
   int controls_x = offset_x + row_w - controls_w;
   
   // 5. Gestao de Risco ($150)
   if(InpShowRiskSection)
   {
      bool is_auto_risk = (m_risk_mode != RISK_MODE_MANUAL);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Chk_Risk", offset_x, cur_y + Scale(1), chk_sz, chk_sz, is_auto_risk ? "X" : "", is_auto_risk ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 9, true);
      
      int toggle_x = offset_x + chk_sz + Scale(4);
      int toggle_w = controls_x - Scale(4) - toggle_x;
      string risk_toggle_text = (m_risk_mode == RISK_MODE_PERCENT) ? "Risco: %" : "Risco: $";
      color risk_toggle_bg    = (m_risk_mode == RISK_MODE_PERCENT) ? COLOR_TOGGLE_PCT : (is_auto_risk ? COLOR_TOGGLE_CASH : COLOR_EDIT_BG);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Risk_Toggle", toggle_x, cur_y, toggle_w, row_h, risk_toggle_text, risk_toggle_bg, COLOR_TEXT_MAIN, 9, true);
      
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Risk_Dec", controls_x, cur_y, step_btn_w, row_h, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      string init_risk_str = (m_risk_mode == RISK_MODE_PERCENT) ? DoubleToString(m_risk_percent, 1) : DoubleToString(m_risk_cash, 2);
      GUI_CreateEdit(m_chart_id, PREFIX_GUI + "Edit_Risk", controls_x + step_btn_w + btn_gap, cur_y, edit_box_w, row_h, init_risk_str, COLOR_EDIT_BG, COLOR_TEXT_MAIN, false, 9);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Risk_Inc", controls_x + step_btn_w + btn_gap + edit_box_w + btn_gap, cur_y, step_btn_w, row_h, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += row_h + row_gap;
   }
   
   // 6. Lote Operacional (Nativo 0.04)
   if(InpShowLotSection)
   {
      bool is_auto_risk = (m_risk_mode != RISK_MODE_MANUAL);
      int dec = GetLotDecimals(m_symbol);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Lot", offset_x + chk_sz + Scale(4), cur_y + Scale(3), "Lote Operacional", COLOR_TEXT_MAIN, 9, true);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Lot_Dec", controls_x, cur_y, step_btn_w, row_h, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      GUI_CreateEdit(m_chart_id, PREFIX_GUI + "Edit_Lot", controls_x + step_btn_w + btn_gap, cur_y, edit_box_w, row_h, DoubleToString(m_manual_lot, dec), is_auto_risk ? COLOR_EDIT_RO_BG : COLOR_EDIT_BG, is_auto_risk ? COLOR_LOT_GOLD : COLOR_TEXT_MAIN, is_auto_risk, 9);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Lot_Inc", controls_x + step_btn_w + btn_gap + edit_box_w + btn_gap, cur_y, step_btn_w, row_h, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += row_h + row_gap;
   }
   
   // 7. Stop Loss (pts)
   if(InpShowSLSection)
   {
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Chk_SL", offset_x, cur_y + Scale(1), chk_sz, chk_sz, m_sl_active ? "X" : "", m_sl_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 9, true);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_SL", offset_x + chk_sz + Scale(4), cur_y + Scale(3), "Stop Loss (pts)", COLOR_TEXT_MAIN, 9, false);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_SL_Dec", controls_x, cur_y, step_btn_w, row_h, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      GUI_CreateEdit(m_chart_id, PREFIX_GUI + "Edit_SL", controls_x + step_btn_w + btn_gap, cur_y, edit_box_w, row_h, IntegerToString(m_sl_points), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false, 9);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_SL_Inc", controls_x + step_btn_w + btn_gap + edit_box_w + btn_gap, cur_y, step_btn_w, row_h, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += row_h + row_gap;
   }
   
   // 8. Take Profit (pts)
   if(InpShowTPSection)
   {
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Chk_TP", offset_x, cur_y + Scale(1), chk_sz, chk_sz, m_tp_active ? "X" : "", m_tp_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 9, true);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_TP", offset_x + chk_sz + Scale(4), cur_y + Scale(3), "Take Profit (pts)", COLOR_TEXT_MAIN, 9, false);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_TP_Dec", controls_x, cur_y, step_btn_w, row_h, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      GUI_CreateEdit(m_chart_id, PREFIX_GUI + "Edit_TP", controls_x + step_btn_w + btn_gap, cur_y, edit_box_w, row_h, IntegerToString(m_tp_points), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false, 9);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_TP_Inc", controls_x + step_btn_w + btn_gap + edit_box_w + btn_gap, cur_y, step_btn_w, row_h, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += row_h + row_gap;
   }
   
   // 9. Break Even (pts)
   if(InpShowBESection)
   {
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Chk_BE", offset_x, cur_y + Scale(1), chk_sz, chk_sz, m_be_active ? "X" : "", m_be_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 9, true);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_BE", offset_x + chk_sz + Scale(4), cur_y + Scale(3), "Break Even (pts)", COLOR_TEXT_MAIN, 9, false);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_BE_Dec", controls_x, cur_y, step_btn_w, row_h, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      GUI_CreateEdit(m_chart_id, PREFIX_GUI + "Edit_BE", controls_x + step_btn_w + btn_gap, cur_y, edit_box_w, row_h, IntegerToString(m_be_points), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false, 9);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_BE_Inc", controls_x + step_btn_w + btn_gap + edit_box_w + btn_gap, cur_y, step_btn_w, row_h, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += row_h + row_gap;
   }
   
   // 10. Trailing Stop (pts)
   if(InpShowTSSection)
   {
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Chk_TS", offset_x, cur_y + Scale(1), chk_sz, chk_sz, m_ts_active ? "X" : "", m_ts_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 9, true);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_TS", offset_x + chk_sz + Scale(4), cur_y + Scale(3), "Trailing Stop (pts)", COLOR_TEXT_MAIN, 9, false);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_TS_Dec", controls_x, cur_y, step_btn_w, row_h, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      GUI_CreateEdit(m_chart_id, PREFIX_GUI + "Edit_TS", controls_x + step_btn_w + btn_gap, cur_y, edit_box_w, row_h, IntegerToString(m_ts_points), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false, 9);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_TS_Inc", controls_x + step_btn_w + btn_gap + edit_box_w + btn_gap, cur_y, step_btn_w, row_h, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += row_h + row_gap;
   }
   
   // 11. Realizacao Parcial
   if(InpShowParcialSection)
   {
      int mode_btn_w = Scale(36);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Chk_Parcial", offset_x, cur_y + Scale(1), chk_sz, chk_sz, m_parcial_active ? "X" : "", m_parcial_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 9, true);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Parcial_Toggle_Mode", offset_x + chk_sz + Scale(4), cur_y, mode_btn_w, row_h, m_parcial_is_cash ? "$" : "Pts", m_parcial_is_cash ? COLOR_TOGGLE_CASH : COLOR_TOGGLE_PCT, COLOR_TEXT_MAIN, 8, true);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Parcial_Target", offset_x + chk_sz + Scale(4) + mode_btn_w + Scale(4), cur_y + Scale(3), "Alvo Parcial", COLOR_TEXT_MAIN, 9, false);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Parcial_Dec", controls_x, cur_y, step_btn_w, row_h, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      string init_parcial_target = m_parcial_is_cash ? DoubleToString(m_parcial_target_cash, 2) : IntegerToString(m_parcial_target_pts);
      GUI_CreateEdit(m_chart_id, PREFIX_GUI + "Edit_Parcial_Target", controls_x + step_btn_w + btn_gap, cur_y, edit_box_w, row_h, init_parcial_target, COLOR_EDIT_BG, COLOR_TEXT_MAIN, false, 9);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Parcial_Inc", controls_x + step_btn_w + btn_gap + edit_box_w + btn_gap, cur_y, step_btn_w, row_h, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += row_h + row_gap;
      
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Parcial_Vol", offset_x + chk_sz + Scale(4), cur_y + Scale(3), "Vol. Parcial (%)", COLOR_TEXT_MUTED, 8, false);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Parcial_Vol_Dec", controls_x, cur_y, step_btn_w, row_h, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      GUI_CreateEdit(m_chart_id, PREFIX_GUI + "Edit_Parcial_Vol", controls_x + step_btn_w + btn_gap, cur_y, edit_box_w, row_h, StringFormat("%.0f%%", m_parcial_vol_pct), COLOR_EDIT_BG, COLOR_TEXT_MAIN, false, 9);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Parcial_Vol_Inc", controls_x + step_btn_w + btn_gap + edit_box_w + btn_gap, cur_y, step_btn_w, row_h, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += row_h + row_gap;
      
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Chk_Parcial_BE", offset_x, cur_y + Scale(1), chk_sz, chk_sz, m_parcial_move_be ? "X" : "", m_parcial_move_be ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT, clrWhite, 8, true);
      GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Parcial_BE", offset_x + chk_sz + Scale(4), cur_y + Scale(3), "Mover SL p/ 0 a 0 pós Parcial", COLOR_TEXT_MUTED, 8, false);
      cur_y += row_h + row_gap;
   }
   
   // 12. Gaveta de Canais 40x40
   if(InpShowChannelsSection)
   {
      string drawer_txt = m_channels_expanded ? "CANAIS DE FREQUENCIA (40x40)  [-]" : "CANAIS DE FREQUENCIA (40x40)  [+]";
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Channels_Toggle", offset_x, cur_y, row_w, Scale(22), drawer_txt, COLOR_DRAWER_BTN, clrGold, 8, true);
      cur_y += Scale(22) + Scale(2);
      
      if(m_channels_expanded)
      {
         int chan_h = Scale(94);
         GUI_CreateRectangleLabel(m_chart_id, PREFIX_GUI + "Chan_Drawer_BG", offset_x, cur_y, row_w, chan_h, COLOR_SECTION_BG, COLOR_BORDER, ZORDER_PANEL_STRIP);
         
         int half_chan_w = (row_w - Scale(6)) / 2;
         GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Chan_Start",   offset_x + Scale(3), cur_y + Scale(4), half_chan_w, Scale(22), "1. Marcar 2 Linhas", COLOR_CHAN_START, clrWhite, 8, true);
         GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Chan_Project", offset_x + Scale(3) + half_chan_w + Scale(4), cur_y + Scale(4), half_chan_w, Scale(22), "2. Projetar 40 Canais", COLOR_CHAN_PROJ, clrWhite, 8, true);
         
         int y_sub = cur_y + Scale(28);
         GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Chan_Up", offset_x + Scale(4), y_sub + Scale(2), "Cima:", clrWhite, 8, true);
         GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Chan_Up_Dec", offset_x + Scale(36), y_sub, Scale(18), Scale(18), "-", COLOR_STEP_BTN, clrWhite, 7, true);
         GUI_CreateEdit(m_chart_id, PREFIX_GUI + "Edit_Chan_Up", offset_x + Scale(56), y_sub, Scale(36), Scale(18), IntegerToString(m_proj_up), COLOR_EDIT_BG, clrWhite, false, 8);
         GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Chan_Up_Inc", offset_x + Scale(94), y_sub, Scale(18), Scale(18), "+", COLOR_STEP_BTN, clrWhite, 7, true);
         
         GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Chan_Dn", offset_x + half_chan_w + Scale(4), y_sub + Scale(2), "Baixo:", clrWhite, 8, true);
         GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Chan_Dn_Dec", offset_x + half_chan_w + Scale(38), y_sub, Scale(18), Scale(18), "-", COLOR_STEP_BTN, clrWhite, 7, true);
         GUI_CreateEdit(m_chart_id, PREFIX_GUI + "Edit_Chan_Dn", offset_x + half_chan_w + Scale(58), y_sub, Scale(36), Scale(18), IntegerToString(m_proj_down), COLOR_EDIT_BG, clrWhite, false, 8);
         GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Chan_Dn_Inc", offset_x + half_chan_w + Scale(96), y_sub, Scale(18), Scale(18), "+", COLOR_STEP_BTN, clrWhite, 7, true);
         
         y_sub += Scale(22);
         GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Chan_HideShow", offset_x + Scale(3), y_sub, half_chan_w, Scale(20), m_chan_visible ? "Ocultar Linhas" : "Mostrar Linhas", C'45,48,60', clrWhite, 7, true);
         GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Chan_Clear", offset_x + Scale(3) + half_chan_w + Scale(4), y_sub, half_chan_w, Scale(20), "Limpar Canais", COLOR_CLOSE_LSS_BTN, clrWhite, 7, true);
         
         y_sub += Scale(22);
         GUI_CreateLabel(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", offset_x + Scale(6), y_sub, "Status: Pronto (40 canais)", clrLimeGreen, 8, true);
         
         cur_y += chan_h + Scale(4);
      }
   }
   
   // 13. Botoes Operacionais (COMPRA e VENDA)
   if(InpShowTradeButtons)
   {
      cur_y += Scale(4);
      int half_btn_w = (row_w - Scale(6)) / 2;
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Buy",  offset_x, cur_y, half_btn_w, Scale(36), "[+] COMPRA", COLOR_BUY_BTN, COLOR_TEXT_MAIN, 11, true);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Sell", offset_x + half_btn_w + Scale(6), cur_y, half_btn_w, Scale(36), "[-] VENDA", COLOR_SELL_BTN, COLOR_TEXT_MAIN, 11, true);
      cur_y += Scale(40);
   }
   
   // 14. Inverter e HEDGE [TRAVA]
   if(InpShowInvertButton || InpShowHedgeButton)
   {
      int half_btn_w = (row_w - Scale(6)) / 2;
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Invert", offset_x, cur_y, half_btn_w, Scale(26), "INVERTER", COLOR_INVERT_BTN, COLOR_TEXT_MAIN, 9, true);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_Hedge",  offset_x + half_btn_w + Scale(6), cur_y, half_btn_w, Scale(26), "HEDGE [TRAVA]", COLOR_LOCK_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += Scale(30);
   }
   
   // 15. Zerar Lucro e Zerar Prejuizo
   if(InpShowCloseButtons)
   {
      int half_btn_w = (row_w - Scale(6)) / 2;
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_CloseProfit", offset_x, cur_y, half_btn_w, Scale(26), "Zerar Lucro", COLOR_CLOSE_PRF_BTN, COLOR_TEXT_MAIN, 9, true);
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_CloseLoss",   offset_x + half_btn_w + Scale(6), cur_y, half_btn_w, Scale(26), "Zerar Prejuizo", COLOR_CLOSE_LSS_BTN, COLOR_TEXT_MAIN, 9, true);
      cur_y += Scale(30);
   }
   
   // 16. ZERAR TODAS AS ORDENS (Rodape)
   if(InpShowCloseAll)
   {
      GUI_CreateButton(m_chart_id, PREFIX_GUI + "Btn_CloseAll", offset_x, cur_y, row_w, Scale(36), "ZERAR TODAS AS ORDENS", COLOR_CLOSE_ALL_BTN, clrBlack, 11, true);
      cur_y += Scale(40);
   }
   
   m_height = cur_y - m_y + Scale(6);
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
//| Atualizacao de Metricas em Tempo Real                            |
//+------------------------------------------------------------------+
void CBoletaMaster::UpdateLiveMetrics()
{
   CalculateDashboardStats();
   CalculateMentorPriceAction();
   
   // Faixa de Mercado
   long spread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
   string tf_name = GetPeriodName(Period());
   string timer_str = StringFormat("[%s] %s", tf_name, GetCandleTimerString(m_symbol, Period()));
   
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Mkt_Spread", OBJPROP_TEXT, StringFormat("Sp: %I64d", spread));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Mkt_Timer",  OBJPROP_TEXT, timer_str);
   
   // Cartões HUD
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Cap_Val", OBJPROP_TEXT, StringFormat("$%.2f", m_initial_capital));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Lot_Val", OBJPROP_TEXT, DoubleToString(m_manual_lot, GetLotDecimals(m_symbol)));
   
   string pnl_str = StringFormat("%s$%.2f", (m_today_pnl >= 0.0) ? "+" : "-", MathAbs(m_today_pnl));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Pnl_Val", OBJPROP_TEXT, pnl_str);
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Lbl_Pnl_Val", OBJPROP_COLOR, (m_today_pnl >= 0.0) ? COLOR_PROFIT_GREEN : COLOR_LOSS_RED);
   
   string win_str = StringFormat("%.1f%% (%d/%d)", m_win_rate, m_win_trades, m_total_trades);
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Win_Val", OBJPROP_TEXT, win_str);
   
   // Bloco Mentor
   if(InpShowMentorAction && InpEnableMentor)
   {
      ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_Mentor_Action", OBJPROP_TEXT, m_mentor_action_text);
      ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_Mentor_Action", OBJPROP_COLOR, m_mentor_action_color);
      ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Mentor_Wick", OBJPROP_TEXT, m_mentor_wick_status);
      ObjectSetInteger(m_chart_id, PREFIX_GUI + "Lbl_Mentor_Wick", OBJPROP_COLOR, m_mentor_wick_color);
      
      string ema_str = StringFormat("EMA 200: %.0f pts", m_dist_to_ema_pts);
      ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Mentor_Ema", OBJPROP_TEXT, ema_str);
      
      if(m_mentor_signal_ready != "NONE")
      {
         ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_Mentor_Execute", OBJPROP_BGCOLOR, clrGold);
         ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_Mentor_Execute", OBJPROP_COLOR, clrBlack);
      }
      else
      {
         ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_Mentor_Execute", OBJPROP_BGCOLOR, COLOR_STEP_BTN);
         ObjectSetInteger(m_chart_id, PREFIX_GUI + "Btn_Mentor_Execute", OBJPROP_COLOR, COLOR_TEXT_MUTED);
      }
   }
   
   UpdateLiveSLTPLines();
   ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Linhas Dinamicas no Grafico 24/7 (Bracket Movel)                 |
//+------------------------------------------------------------------+
void CBoletaMaster::UpdateLiveSLTPLines()
{
   if(!InpLiveSLTPLines)
   {
      ObjectsDeleteAll(m_chart_id, "BSCALP_LIVE_");
      return;
   }
   
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0.0) return;
   
   // 1. Linha Live TP
   string tpLine = "BSCALP_LIVE_TP";
   if(m_tp_active && m_tp_points > 0)
   {
      double tp_price = ask + (m_tp_points * point);
      if(ObjectFind(m_chart_id, tpLine) < 0)
         ObjectCreate(m_chart_id, tpLine, OBJ_HLINE, 0, 0, tp_price);
      ObjectSetDouble(m_chart_id, tpLine, OBJPROP_PRICE, tp_price);
      ObjectSetInteger(m_chart_id, tpLine, OBJPROP_COLOR, InpColorLiveTP);
      ObjectSetInteger(m_chart_id, tpLine, OBJPROP_STYLE, InpStyleLiveTP);
      ObjectSetInteger(m_chart_id, tpLine, OBJPROP_WIDTH, InpWidthLiveTP);
      ObjectSetString(m_chart_id, tpLine, OBJPROP_TOOLTIP, StringFormat("Take Profit [%d pts]: +$%.2f", m_tp_points, (m_tp_points * (SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE)/SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE)*point) * m_manual_lot)));
   }
   else ObjectDelete(m_chart_id, tpLine);
   
   // 2. Linha Live SL
   string slLine = "BSCALP_LIVE_SL";
   if(m_sl_active && m_sl_points > 0)
   {
      double sl_price = bid - (m_sl_points * point);
      if(ObjectFind(m_chart_id, slLine) < 0)
         ObjectCreate(m_chart_id, slLine, OBJ_HLINE, 0, 0, sl_price);
      ObjectSetDouble(m_chart_id, slLine, OBJPROP_PRICE, sl_price);
      ObjectSetInteger(m_chart_id, slLine, OBJPROP_COLOR, InpColorLiveSL);
      ObjectSetInteger(m_chart_id, slLine, OBJPROP_STYLE, InpStyleLiveSL);
      ObjectSetInteger(m_chart_id, slLine, OBJPROP_WIDTH, InpWidthLiveSL);
      ObjectSetString(m_chart_id, slLine, OBJPROP_TOOLTIP, StringFormat("Stop Loss [%d pts]: -$%.2f", m_sl_points, (m_sl_points * (SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE)/SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE)*point) * m_manual_lot)));
   }
   else ObjectDelete(m_chart_id, slLine);
}

void CBoletaMaster::UpdateFieldValues()
{
   int dec = GetLotDecimals(m_symbol);
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Lot", OBJPROP_TEXT, DoubleToString(m_manual_lot, dec));
   
   string risk_str = (m_risk_mode == RISK_MODE_PERCENT) ? DoubleToString(m_risk_percent, 1) : DoubleToString(m_risk_cash, 2);
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Risk", OBJPROP_TEXT, risk_str);
   
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_SL", OBJPROP_TEXT, IntegerToString(m_sl_points));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_TP", OBJPROP_TEXT, IntegerToString(m_tp_points));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_BE", OBJPROP_TEXT, IntegerToString(m_be_points));
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_TS", OBJPROP_TEXT, IntegerToString(m_ts_points));
   
   string parc_target = m_parcial_is_cash ? DoubleToString(m_parcial_target_cash, 2) : IntegerToString(m_parcial_target_pts);
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Parcial_Target", OBJPROP_TEXT, parc_target);
   ObjectSetString(m_chart_id, PREFIX_GUI + "Edit_Parcial_Vol", OBJPROP_TEXT, StringFormat("%.0f%%", m_parcial_vol_pct));
   
   bool is_auto_risk = (m_risk_mode != RISK_MODE_MANUAL);
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_Risk", OBJPROP_TEXT, is_auto_risk ? "X" : "");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_Risk", OBJPROP_BGCOLOR, is_auto_risk ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_SL", OBJPROP_TEXT, m_sl_active ? "X" : "");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_SL", OBJPROP_BGCOLOR, m_sl_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_TP", OBJPROP_TEXT, m_tp_active ? "X" : "");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_TP", OBJPROP_BGCOLOR, m_tp_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_BE", OBJPROP_TEXT, m_be_active ? "X" : "");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_BE", OBJPROP_BGCOLOR, m_be_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_TS", OBJPROP_TEXT, m_ts_active ? "X" : "");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_TS", OBJPROP_BGCOLOR, m_ts_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_Parcial", OBJPROP_TEXT, m_parcial_active ? "X" : "");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_Parcial", OBJPROP_BGCOLOR, m_parcial_active ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_Parcial_BE", OBJPROP_TEXT, m_parcial_move_be ? "X" : "");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_Parcial_BE", OBJPROP_BGCOLOR, m_parcial_move_be ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
   
   ObjectSetString(m_chart_id, PREFIX_GUI + "Chk_Mentor_Auto", OBJPROP_TEXT, m_mentor_auto_trading ? "[X] Auto Scalp" : "[ ] Auto Scalp");
   ObjectSetInteger(m_chart_id, PREFIX_GUI + "Chk_Mentor_Auto", OBJPROP_BGCOLOR, m_mentor_auto_trading ? COLOR_CHECK_ACTIVE : COLOR_EDIT_BG);
   
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::CheckForegroundState()
{
   ChartSetInteger(m_chart_id, CHART_FOREGROUND, false);
}

void CBoletaMaster::MovePanel(int new_x, int new_y)
{
   m_x = new_x;
   m_y = new_y;
   SaveState();
   Render();
   UpdateFieldValues();
   UpdateLiveMetrics();
}

void CBoletaMaster::ToggleMinimize()
{
   m_is_minimized = !m_is_minimized;
   SaveState();
   Render();
   UpdateFieldValues();
   UpdateLiveMetrics();
}

void CBoletaMaster::CycleScale()
{
   if(m_gui_scale < 1.14)      m_gui_scale = 1.15;
   else if(m_gui_scale < 1.29) m_gui_scale = 1.30;
   else if(m_gui_scale < 1.49) m_gui_scale = 1.50;
   else                        m_gui_scale = 1.00;
   
   m_width    = Scale(276);
   m_header_h = Scale(26);
   SaveState();
   Render();
   UpdateFieldValues();
   UpdateLiveMetrics();
}

void CBoletaMaster::ToggleStatsScope()
{
   m_filter_symbol_only = !m_filter_symbol_only;
   Render();
   UpdateFieldValues();
   UpdateLiveMetrics();
}

void CBoletaMaster::SetStatsPeriod(ENUM_STATS_PERIOD p)
{
   m_stats_period = p;
   Render();
   UpdateFieldValues();
   UpdateLiveMetrics();
}

void CBoletaMaster::CycleStatsPeriod()
{
   if(m_stats_period == STATS_PERIOD_TODAY)       SetStatsPeriod(STATS_PERIOD_7D);
   else if(m_stats_period == STATS_PERIOD_7D)    SetStatsPeriod(STATS_PERIOD_ALL);
   else if(m_stats_period == STATS_PERIOD_ALL)   SetStatsPeriod(STATS_PERIOD_CUSTOM);
   else                                          SetStatsPeriod(STATS_PERIOD_TODAY);
}

void CBoletaMaster::ApplyStatsCustomDate()
{
   string txt = ObjectGetString(m_chart_id, PREFIX_GUI + "Edit_Stats_Date", OBJPROP_TEXT);
   datetime dt = StringToTime(txt);
   if(dt > 0)
   {
      m_stats_custom_date = dt;
      m_stats_date_str    = TimeToString(dt, TIME_DATE);
      SetStatsPeriod(STATS_PERIOD_CUSTOM);
   }
}

void CBoletaMaster::ToggleRiskAuto()
{
   if(m_risk_mode == RISK_MODE_MANUAL) m_risk_mode = RISK_MODE_CASH;
   else                                m_risk_mode = RISK_MODE_MANUAL;
   RecalculateRiskLot();
   SaveState();
   Render();
   UpdateFieldValues();
   UpdateLiveMetrics();
}

void CBoletaMaster::ToggleRiskMode()
{
   if(m_risk_mode == RISK_MODE_CASH)       m_risk_mode = RISK_MODE_PERCENT;
   else if(m_risk_mode == RISK_MODE_PERCENT) m_risk_mode = RISK_MODE_CASH;
   else                                    m_risk_mode = RISK_MODE_CASH;
   RecalculateRiskLot();
   SaveState();
   Render();
   UpdateFieldValues();
   UpdateLiveMetrics();
}

void CBoletaMaster::StepLot(bool inc)
{
   double step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   m_manual_lot = NormalizeLot(inc ? (m_manual_lot + step) : (m_manual_lot - step), m_symbol);
   SaveState();
   UpdateFieldValues();
   UpdateLiveSLTPLines();
}

void CBoletaMaster::StepRisk(bool inc)
{
   if(m_risk_mode == RISK_MODE_PERCENT)
   {
      m_risk_percent += inc ? InpStepRiskPct : -InpStepRiskPct;
      if(m_risk_percent < 0.1) m_risk_percent = 0.1;
   }
   else
   {
      m_risk_cash += inc ? InpStepRiskCash : -InpStepRiskCash;
      if(m_risk_cash < 1.0) m_risk_cash = 1.0;
   }
   RecalculateRiskLot();
   SaveState();
   UpdateFieldValues();
   UpdateLiveSLTPLines();
}

void CBoletaMaster::StepSL(bool inc)
{
   m_sl_points += inc ? InpStepPoints : -InpStepPoints;
   if(m_sl_points < 10) m_sl_points = 10;
   if(m_risk_mode != RISK_MODE_MANUAL) RecalculateRiskLot();
   SaveState();
   UpdateFieldValues();
   UpdateLiveSLTPLines();
}

void CBoletaMaster::StepTP(bool inc)
{
   m_tp_points += inc ? InpStepPoints : -InpStepPoints;
   if(m_tp_points < 10) m_tp_points = 10;
   SaveState();
   UpdateFieldValues();
   UpdateLiveSLTPLines();
}

void CBoletaMaster::StepBE(bool inc)
{
   m_be_points += inc ? InpStepPoints : -InpStepPoints;
   if(m_be_points < 5) m_be_points = 5;
   SaveState();
   UpdateFieldValues();
}

void CBoletaMaster::StepTS(bool inc)
{
   m_ts_points += inc ? InpStepPoints : -InpStepPoints;
   if(m_ts_points < 10) m_ts_points = 10;
   SaveState();
   UpdateFieldValues();
}

void CBoletaMaster::StepParcialTarget(bool inc)
{
   if(m_parcial_is_cash)
   {
      m_parcial_target_cash += inc ? InpStepParcialCash : -InpStepParcialCash;
      if(m_parcial_target_cash < 1.0) m_parcial_target_cash = 1.0;
   }
   else
   {
      m_parcial_target_pts += inc ? InpStepPoints : -InpStepPoints;
      if(m_parcial_target_pts < 10) m_parcial_target_pts = 10;
   }
   SaveState();
   UpdateFieldValues();
}

void CBoletaMaster::StepParcialVol(bool inc)
{
   m_parcial_vol_pct += inc ? InpStepParcialVol : -InpStepParcialVol;
   if(m_parcial_vol_pct < 10.0) m_parcial_vol_pct = 10.0;
   if(m_parcial_vol_pct > 90.0) m_parcial_vol_pct = 90.0;
   SaveState();
   UpdateFieldValues();
}

void CBoletaMaster::StepChanUp(bool inc)
{
   m_proj_up += inc ? 5 : -5;
   if(m_proj_up < 5) m_proj_up = 5;
   if(m_mark_step == 2) ProjectChannels();
   UpdateFieldValues();
}

void CBoletaMaster::StepChanDn(bool inc)
{
   m_proj_down += inc ? 5 : -5;
   if(m_proj_down < 5) m_proj_down = 5;
   if(m_mark_step == 2) ProjectChannels();
   UpdateFieldValues();
}

//+------------------------------------------------------------------+
//| Execucoes Operacionais Blindadas                                 |
//+------------------------------------------------------------------+
void CBoletaMaster::ExecuteBuy()
{
   MqlTick tick;
   if(!SymbolInfoTick(m_symbol, tick)) return;
   
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double ask   = tick.ask;
   double sl    = (m_sl_active && m_sl_points > 0) ? (ask - m_sl_points * point) : 0.0;
   double tp    = (m_tp_active && m_tp_points > 0) ? (ask + m_tp_points * point) : 0.0;
   
   if(m_trade.Buy(m_manual_lot, m_symbol, ask, sl, tp, "Scalp Mentor Buy"))
      PrintFormat("COMPRA EXECUTADA: %s %.2f lotes | SL: %.2f | TP: %.2f", m_symbol, m_manual_lot, sl, tp);
   else
      PrintFormat("FALHA NA COMPRA: %u %s", m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
}

void CBoletaMaster::ExecuteSell()
{
   MqlTick tick;
   if(!SymbolInfoTick(m_symbol, tick)) return;
   
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   double bid   = tick.bid;
   double sl    = (m_sl_active && m_sl_points > 0) ? (bid + m_sl_points * point) : 0.0;
   double tp    = (m_tp_active && m_tp_points > 0) ? (bid - m_tp_points * point) : 0.0;
   
   if(m_trade.Sell(m_manual_lot, m_symbol, bid, sl, tp, "Scalp Mentor Sell"))
      PrintFormat("VENDA EXECUTADA: %s %.2f lotes | SL: %.2f | TP: %.2f", m_symbol, m_manual_lot, sl, tp);
   else
      PrintFormat("FALHA NA VENDA: %u %s", m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
}

void CBoletaMaster::ExecuteInvert()
{
   MqlTick tick;
   if(!SymbolInfoTick(m_symbol, tick)) return;
   
   double buy_vol = 0.0, sell_vol = 0.0;
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && pos.Symbol() == m_symbol)
      {
         if(pos.PositionType() == POSITION_TYPE_BUY)  buy_vol  += pos.Volume();
         if(pos.PositionType() == POSITION_TYPE_SELL) sell_vol += pos.Volume();
      }
   }
   
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(buy_vol > sell_vol)
   {
      ExecuteCloseAll();
      double sl = (m_sl_active && m_sl_points > 0) ? (tick.bid + m_sl_points * point) : 0.0;
      double tp = (m_tp_active && m_tp_points > 0) ? (tick.bid - m_tp_points * point) : 0.0;
      m_trade.Sell(m_manual_lot, m_symbol, tick.bid, sl, tp, "Inverter para Venda");
   }
   else if(sell_vol > buy_vol)
   {
      ExecuteCloseAll();
      double sl = (m_sl_active && m_sl_points > 0) ? (tick.ask - m_sl_points * point) : 0.0;
      double tp = (m_tp_active && m_tp_points > 0) ? (tick.ask + m_tp_points * point) : 0.0;
      m_trade.Buy(m_manual_lot, m_symbol, tick.ask, sl, tp, "Inverter para Compra");
   }
}

//+------------------------------------------------------------------+
//| Trava de Hedge Delta Neutro Blindada (Protocolo Sunrise)         |
//+------------------------------------------------------------------+
void CBoletaMaster::ExecuteHedge()
{
   double buy_vol = 0.0, sell_vol = 0.0;
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && pos.Symbol() == m_symbol)
      {
         if(pos.PositionType() == POSITION_TYPE_BUY)  buy_vol  += pos.Volume();
         if(pos.PositionType() == POSITION_TYPE_SELL) sell_vol += pos.Volume();
      }
   }
   
   double diff = buy_vol - sell_vol;
   double vol  = NormalizeLot(MathAbs(diff), m_symbol);
   double min_vol = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   
   if(vol < min_vol)
   {
      Alert(StringFormat("%s: Posições já estão equilibradas em Delta Neutro (%.2f C x %.2f V).", m_symbol, buy_vol, sell_vol));
      return;
   }
   
   MqlTick tick;
   if(!SymbolInfoTick(m_symbol, tick)) return;
   
   bool ok = (diff > 0.0) ? m_trade.Sell(vol, m_symbol, tick.bid, 0, 0, "Hedge Trava Compra")
                          : m_trade.Buy(vol, m_symbol, tick.ask, 0, 0, "Hedge Trava Venda");
                          
   if(ok && (m_trade.ResultRetcode() == TRADE_RETCODE_DONE || m_trade.ResultRetcode() == TRADE_RETCODE_PLACED))
      Alert(StringFormat("HEDGE TRAVA ATIVADA em %s: %s de %.2f lotes para igualar delta.", m_symbol, (diff > 0.0) ? "Venda" : "Compra", vol));
   else
      Alert(StringFormat("FALHA AO TRAVAR HEDGE: %u %s", m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
}

void CBoletaMaster::ExecuteCloseAll()
{
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && (!m_filter_symbol_only || pos.Symbol() == m_symbol))
         m_trade.PositionClose(pos.Ticket());
   }
   COrderInfo ord;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(ord.SelectByIndex(i) && (!m_filter_symbol_only || ord.Symbol() == m_symbol))
         m_trade.OrderDelete(ord.Ticket());
   }
}

void CBoletaMaster::ExecuteCloseProfit()
{
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && (!m_filter_symbol_only || pos.Symbol() == m_symbol))
      {
         double net = pos.Profit() + pos.Swap() + pos.Commission();
         if(net > 0.00001) m_trade.PositionClose(pos.Ticket());
      }
   }
}

void CBoletaMaster::ExecuteCloseLoss()
{
   CPositionInfo pos;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && (!m_filter_symbol_only || pos.Symbol() == m_symbol))
      {
         double net = pos.Profit() + pos.Swap() + pos.Commission();
         if(net < -0.00001) m_trade.PositionClose(pos.Ticket());
      }
   }
}

void CBoletaMaster::ExecuteMentorSignal()
{
   if(m_mentor_signal_ready == "BUY")
      ExecuteBuy();
   else if(m_mentor_signal_ready == "SELL")
      ExecuteSell();
}

//+------------------------------------------------------------------+
//| Canais de Frequência 40x40                                       |
//+------------------------------------------------------------------+
void CBoletaMaster::StartChannelMarking()
{
   m_marking_mode = true;
   m_mark_step    = 0;
   m_mark_price1  = 0.0;
   m_mark_price2  = 0.0;
   ObjectsDeleteAll(m_chart_id, PREFIX_CANAL_TEMP);
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_TEXT, "Clique no Grafico: Linha 1 (Topo)");
}

void CBoletaMaster::CheckChannelClick(double price)
{
   if(!m_marking_mode) return;
   
   if(m_mark_step == 0)
   {
      m_mark_price1 = price;
      m_mark_step   = 1;
      string l1 = PREFIX_CANAL_TEMP + "L1";
      ObjectCreate(m_chart_id, l1, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(m_chart_id, l1, OBJPROP_COLOR, clrGold);
      ObjectSetInteger(m_chart_id, l1, OBJPROP_WIDTH, 2);
      ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_TEXT, "Clique no Grafico: Linha 2 (Fundo)");
   }
   else if(m_mark_step == 1)
   {
      m_mark_price2  = price;
      m_mark_step    = 2;
      m_marking_mode = false;
      string l2 = PREFIX_CANAL_TEMP + "L2";
      ObjectCreate(m_chart_id, l2, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(m_chart_id, l2, OBJPROP_COLOR, clrGold);
      ObjectSetInteger(m_chart_id, l2, OBJPROP_WIDTH, 2);
      ProjectChannels();
      ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_TEXT, "40 Canais Projetados com Sucesso!");
   }
}

void CBoletaMaster::ProjectChannels()
{
   if(m_mark_price1 == 0.0 || m_mark_price2 == 0.0) return;
   
   ObjectsDeleteAll(m_chart_id, PREFIX_CANAL_LINES);
   double topPrice = MathMax(m_mark_price1, m_mark_price2);
   double botPrice = MathMin(m_mark_price1, m_mark_price2);
   double channel_size = topPrice - botPrice;
   if(channel_size <= 0.0) return;
   
   // Projeta Canais para Cima
   for(int u = 1; u <= m_proj_up; u++)
   {
      double pMain = topPrice + (u * channel_size);
      double pMid  = pMain - (channel_size * 0.5);
      
      string nameMain = PREFIX_CANAL_LINES + "UP_" + IntegerToString(u);
      string nameMid  = PREFIX_CANAL_LINES + "UP_MID_" + IntegerToString(u);
      
      ObjectCreate(m_chart_id, nameMain, OBJ_HLINE, 0, 0, pMain);
      ObjectSetInteger(m_chart_id, nameMain, OBJPROP_COLOR, InpColorChannel);
      ObjectSetInteger(m_chart_id, nameMain, OBJPROP_WIDTH, 1);
      
      ObjectCreate(m_chart_id, nameMid, OBJ_HLINE, 0, 0, pMid);
      ObjectSetInteger(m_chart_id, nameMid, OBJPROP_COLOR, InpColorChannelMid);
      ObjectSetInteger(m_chart_id, nameMid, OBJPROP_STYLE, STYLE_DOT);
   }
   
   // Projeta Canais para Baixo
   for(int d = 1; d <= m_proj_down; d++)
   {
      double pMain = botPrice - (d * channel_size);
      double pMid  = pMain + (channel_size * 0.5);
      
      string nameMain = PREFIX_CANAL_LINES + "DN_" + IntegerToString(d);
      string nameMid  = PREFIX_CANAL_LINES + "DN_MID_" + IntegerToString(d);
      
      ObjectCreate(m_chart_id, nameMain, OBJ_HLINE, 0, 0, pMain);
      ObjectSetInteger(m_chart_id, nameMain, OBJPROP_COLOR, InpColorChannel);
      ObjectSetInteger(m_chart_id, nameMain, OBJPROP_WIDTH, 1);
      
      ObjectCreate(m_chart_id, nameMid, OBJ_HLINE, 0, 0, pMid);
      ObjectSetInteger(m_chart_id, nameMid, OBJPROP_COLOR, InpColorChannelMid);
      ObjectSetInteger(m_chart_id, nameMid, OBJPROP_STYLE, STYLE_DOT);
   }
   
   m_chan_visible = true;
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::ToggleChannelVisibility()
{
   m_chan_visible = !m_chan_visible;
   int total = ObjectsTotal(m_chart_id, 0, OBJ_HLINE);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(m_chart_id, i, 0, OBJ_HLINE);
      if(StringFind(name, PREFIX_CANAL_LINES) == 0 || StringFind(name, PREFIX_CANAL_TEMP) == 0)
         ObjectSetInteger(m_chart_id, name, OBJPROP_TIMEFRAMES, m_chan_visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   }
   ObjectSetString(m_chart_id, PREFIX_GUI + "Btn_Chan_HideShow", OBJPROP_TEXT, m_chan_visible ? "Ocultar Linhas" : "Mostrar Linhas");
   ChartRedraw(m_chart_id);
}

void CBoletaMaster::ClearChannels()
{
   ObjectsDeleteAll(m_chart_id, PREFIX_CANAL_LINES);
   ObjectsDeleteAll(m_chart_id, PREFIX_CANAL_TEMP);
   m_mark_step    = 0;
   m_mark_price1  = 0.0;
   m_mark_price2  = 0.0;
   m_marking_mode = false;
   ObjectSetString(m_chart_id, PREFIX_GUI + "Lbl_Chan_Status", OBJPROP_TEXT, "Status: Canais Limpos");
   ChartRedraw(m_chart_id);
}

//+------------------------------------------------------------------+
//| Alvos ATR                                                        |
//+------------------------------------------------------------------+
bool CBoletaMaster::GetATRTargets(int &atr_p, int &sug_sl, int &sug_tp)
{
   int handle = iATR(m_symbol, InpATRTimeframe, InpATRPeriod);
   if(handle == INVALID_HANDLE) return false;
   
   double atr_val[1];
   if(CopyBuffer(handle, 0, 1, 1, atr_val) <= 0)
   {
      IndicatorRelease(handle);
      return false;
   }
   IndicatorRelease(handle);
   
   double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0.0) return false;
   
   atr_p  = (int)MathRound(atr_val[0] / point);
   sug_sl = (int)MathRound(atr_p * InpATRMulSL);
   sug_tp = (int)MathRound(atr_p * InpATRMulTP);
   return true;
}

void CBoletaMaster::ApplyATRTargets()
{
   int atr_p = 0, sug_sl = 0, sug_tp = 0;
   if(GetATRTargets(atr_p, sug_sl, sug_tp))
   {
      m_sl_points = sug_sl;
      m_tp_points = sug_tp;
      SaveState();
      UpdateFieldValues();
      UpdateLiveSLTPLines();
   }
}

//+------------------------------------------------------------------+
//| Roteamento de Eventos da GUI e Atalhos de Teclado                |
//+------------------------------------------------------------------+
void CBoletaMaster::OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CLICK && m_marking_mode)
   {
      int subwindow = 0;
      datetime dt;
      double price;
      if(ChartXYToTimePrice(m_chart_id, (int)lparam, (int)dparam, subwindow, dt, price))
         CheckChannelClick(price);
      return;
   }
   
   // Arraste Fluido da Boleta
   if(id == CHARTEVENT_OBJECT_CLICK && (sparam == PREFIX_GUI + "Header_BG" || sparam == PREFIX_GUI + "Header_Title"))
   {
      m_is_dragging   = true;
      m_drag_offset_x = (int)lparam - m_x;
      m_drag_offset_y = (int)dparam - m_y;
      return;
   }
   
   if(id == CHARTEVENT_MOUSE_MOVE && m_is_dragging)
   {
      if((int)sparam == 1) // Botao esquerdo pressionado
      {
         int new_x = (int)lparam - m_drag_offset_x;
         int new_y = (int)dparam - m_drag_offset_y;
         MovePanel(new_x, new_y);
      }
      else
      {
         m_is_dragging = false;
      }
      return;
   }
   
   // Atalhos de Teclado
   if(id == CHARTEVENT_KEYDOWN)
   {
      if(lparam == 66 || lparam == 98)   { ExecuteBuy(); return; }          // B -> Compra
      if(lparam == 83 || lparam == 115)  { ExecuteSell(); return; }         // S -> Venda
      if(lparam == 73 || lparam == 105)  { ExecuteInvert(); return; }       // I -> Inverter
      if(lparam == 72 || lparam == 104)  { ExecuteHedge(); return; }        // H -> Hedge [Trava]
      if(lparam == 90 || lparam == 122)  { ExecuteCloseAll(); return; }     // Z -> Zerar Todas
      if(lparam == 77 || lparam == 109)  { ToggleMinimize(); return; }      // M -> Minimizar
      return;
   }
   
   // Edicao de Campos
   if(id == CHARTEVENT_OBJECT_ENDEDIT && StringFind(sparam, PREFIX_GUI) == 0)
   {
      string key = StringSubstr(sparam, StringLen(PREFIX_GUI));
      string valStr = ObjectGetString(m_chart_id, sparam, OBJPROP_TEXT);
      double val = StringToDouble(valStr);
      
      if(key == "Edit_Lot" && val > 0.0) m_manual_lot = NormalizeLot(val, m_symbol);
      if(key == "Edit_Risk" && val > 0.0)
      {
         if(m_risk_mode == RISK_MODE_PERCENT) m_risk_percent = val;
         else                                 m_risk_cash    = val;
         RecalculateRiskLot();
      }
      if(key == "Edit_SL" && val >= 10.0) m_sl_points = (int)val;
      if(key == "Edit_TP" && val >= 10.0) m_tp_points = (int)val;
      if(key == "Edit_BE" && val >= 5.0)  m_be_points = (int)val;
      if(key == "Edit_TS" && val >= 10.0) m_ts_points = (int)val;
      if(key == "Edit_Parcial_Target" && val > 0.0)
      {
         if(m_parcial_is_cash) m_parcial_target_cash = val;
         else                  m_parcial_target_pts  = (int)val;
      }
      if(key == "Edit_Parcial_Vol" && val >= 10.0 && val <= 90.0) m_parcial_vol_pct = val;
      
      SaveState();
      UpdateFieldValues();
      UpdateLiveSLTPLines();
      return;
   }
   
   // Cliques nos Botoes
   if(id != CHARTEVENT_OBJECT_CLICK || StringFind(sparam, PREFIX_GUI) != 0) return;
   string name = StringSubstr(sparam, StringLen(PREFIX_GUI));
   
   if(name == "Btn_Close")             { Destroy(REASON_REMOVE); return; }
   if(name == "Btn_Min")               { ToggleMinimize(); return; }
   if(name == "Btn_Zoom")              { CycleScale(); return; }
   if(name == "Btn_Stats_Today")       { SetStatsPeriod(STATS_PERIOD_TODAY); return; }
   if(name == "Btn_Stats_7D")          { SetStatsPeriod(STATS_PERIOD_7D); return; }
   if(name == "Btn_Stats_All")         { SetStatsPeriod(STATS_PERIOD_ALL); return; }
   if(name == "Btn_Stats_Scope")       { ToggleStatsScope(); return; }
   if(name == "Btn_Stats_Apply")       { ApplyStatsCustomDate(); return; }
   
   if(name == "Chk_Risk" || name == "Btn_Risk_Toggle") { ToggleRiskAuto(); return; }
   if(name == "Btn_Risk_Dec")          { StepRisk(false); return; }
   if(name == "Btn_Risk_Inc")          { StepRisk(true); return; }
   
   if(name == "Btn_Lot_Dec")           { StepLot(false); return; }
   if(name == "Btn_Lot_Inc")           { StepLot(true); return; }
   
   if(name == "Chk_SL" || name == "Lbl_SL") { ToggleSL(); return; }
   if(name == "Btn_SL_Dec")            { StepSL(false); return; }
   if(name == "Btn_SL_Inc")            { StepSL(true); return; }
   
   if(name == "Chk_TP" || name == "Lbl_TP") { ToggleTP(); return; }
   if(name == "Btn_TP_Dec")            { StepTP(false); return; }
   if(name == "Btn_TP_Inc")            { StepTP(true); return; }
   
   if(name == "Chk_BE" || name == "Lbl_BE") { ToggleBE(); return; }
   if(name == "Btn_BE_Dec")            { StepBE(false); return; }
   if(name == "Btn_BE_Inc")            { StepBE(true); return; }
   
   if(name == "Chk_TS" || name == "Lbl_TS") { ToggleTS(); return; }
   if(name == "Btn_TS_Dec")            { StepTS(false); return; }
   if(name == "Btn_TS_Inc")            { StepTS(true); return; }
   
   if(name == "Chk_Parcial")           { ToggleParcial(); return; }
   if(name == "Btn_Parcial_Toggle_Mode"){ ToggleParcialMode(); return; }
   if(name == "Btn_Parcial_Dec")       { StepParcialTarget(false); return; }
   if(name == "Btn_Parcial_Inc")       { StepParcialTarget(true); return; }
   if(name == "Btn_Parcial_Vol_Dec")   { StepParcialVol(false); return; }
   if(name == "Btn_Parcial_Vol_Inc")   { StepParcialVol(true); return; }
   if(name == "Chk_Parcial_BE")        { ToggleParcialBE(); return; }
   
   if(name == "Chk_Mentor_Auto")       { ToggleMentorAuto(); return; }
   if(name == "Btn_Mentor_Execute")    { ExecuteMentorSignal(); return; }
   if(name == "Btn_ATR_Info")          { ApplyATRTargets(); return; }
   
   if(name == "Btn_Channels_Toggle")   { ToggleChannelsDrawer(); return; }
   if(name == "Btn_Chan_Start")        { StartChannelMarking(); return; }
   if(name == "Btn_Chan_Project")      { ProjectChannels(); return; }
   if(name == "Btn_Chan_Up_Dec")       { StepChanUp(false); return; }
   if(name == "Btn_Chan_Up_Inc")       { StepChanUp(true); return; }
   if(name == "Btn_Chan_Dn_Dec")       { StepChanDn(false); return; }
   if(name == "Btn_Chan_Dn_Inc")       { StepChanDn(true); return; }
   if(name == "Btn_Chan_HideShow")     { ToggleChannelVisibility(); return; }
   if(name == "Btn_Chan_Clear")        { ClearChannels(); return; }
   
   if(name == "Btn_Buy")               { ExecuteBuy(); return; }
   if(name == "Btn_Sell")              { ExecuteSell(); return; }
   if(name == "Btn_Invert")            { ExecuteInvert(); return; }
   if(name == "Btn_Hedge")             { ExecuteHedge(); return; }
   if(name == "Btn_CloseProfit")       { ExecuteCloseProfit(); return; }
   if(name == "Btn_CloseLoss")         { ExecuteCloseLoss(); return; }
   if(name == "Btn_CloseAll")          { ExecuteCloseAll(); return; }
}

//+------------------------------------------------------------------+
//| Instancia Global & Eventos MQL5 do Expert                        |
//+------------------------------------------------------------------+
CBoletaMaster g_master;
ulong         g_partial_tickets[];

bool IsPartialExecuted(ulong ticket)
{
   int size = ArraySize(g_partial_tickets);
   for(int i = 0; i < size; i++)
      if(g_partial_tickets[i] == ticket) return true;
   return false;
}

void MarkPartialExecuted(ulong ticket)
{
   int size = ArraySize(g_partial_tickets);
   ArrayResize(g_partial_tickets, size + 1);
   g_partial_tickets[size] = ticket;
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

void GerenciarPosicoesAbertas()
{
   bool be_active       = g_master.IsBEActive();
   bool ts_active       = g_master.IsTSActive();
   bool parcial_active  = g_master.IsParcialActive();
   
   if(!be_active && !ts_active && !parcial_active) return;
   
   int be_pts           = g_master.GetBEPoints();
   int ts_pts           = g_master.GetTSPoints();
   int ts_step_pts      = g_master.GetTSStepPoints();
   if(ts_step_pts <= 0) ts_step_pts = 1;
   bool parcial_is_cash = g_master.IsParcialCashMode();
   int parcial_pts      = g_master.GetParcialTargetPoints();
   double parcial_cash  = g_master.GetParcialTargetCash();
   double parcial_pct   = g_master.GetParcialVolumePct();
   
   string sym = g_master.GetSymbol();
   CTrade trade;
   trade.SetExpertMagicNumber(InpMagicNumber);
   SetBestFillingMode(trade, sym);
   CPositionInfo pos;
   
   double ask   = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(sym, SYMBOL_BID);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(point <= 0.0) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i) || pos.Symbol() != sym) continue;
      
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
            if(parcial_cash > 0.0 && lucro_liquido >= parcial_cash) atingiu_parcial = true;
         }
         else
         {
            if(parcial_pts > 0)
            {
               if(posType == POSITION_TYPE_BUY  && (bid - openPrice) / point >= parcial_pts) atingiu_parcial = true;
               if(posType == POSITION_TYPE_SELL && (openPrice - ask) / point >= parcial_pts) atingiu_parcial = true;
            }
         }
         
         if(atingiu_parcial)
         {
            double close_vol = NormalizeLot(curVol * (parcial_pct / 100.0), sym);
            double min_vol   = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
            if(close_vol < min_vol) close_vol = min_vol;
            if(close_vol >= curVol) close_vol = (curVol > min_vol) ? NormalizeLot(curVol - min_vol, sym) : curVol;
            
            if(close_vol > 0.0 && trade.PositionClosePartial(ticket, close_vol))
            {
               MarkPartialExecuted(ticket);
               if(g_master.IsParcialMoveBE() && pos.SelectByTicket(ticket))
               {
                  double rem_sl = pos.StopLoss();
                  double rem_tp = pos.TakeProfit();
                  bool need_modify = false;
                  if(posType == POSITION_TYPE_BUY  && rem_sl < openPrice)                need_modify = true;
                  if(posType == POSITION_TYPE_SELL && (rem_sl == 0.0 || rem_sl > openPrice)) need_modify = true;
                  if(need_modify) trade.PositionModify(ticket, openPrice, rem_tp);
               }
               PrintFormat("PARCIAL EXECUTADA: #%I64u | Vol: %.2f", ticket, close_vol);
            }
         }
      }
      
      // 2. Break Even e Trailing Stop
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
         
         int sl_pts = g_master.GetSLPoints();
         int tp_pts = g_master.GetTPPoints();
         if((ts_active || InpSimultaneousTrailing) && sl_pts > 0 && be_atingido)
         {
            int trail_dist = (ts_active && ts_pts > 0) ? ts_pts : sl_pts;
            double desired_sl = bid - (trail_dist * point);
            if(desired_sl >= openPrice)
            {
               double min_step = point * ts_step_pts;
               if(curSL == 0.0 || desired_sl >= curSL + min_step)
               {
                  double desired_tp = (tp_pts > 0) ? (bid + tp_pts * point) : curTP;
                  trade.PositionModify(ticket, desired_sl, desired_tp);
               }
            }
         }
      }
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
         
         int sl_pts = g_master.GetSLPoints();
         int tp_pts = g_master.GetTPPoints();
         if((ts_active || InpSimultaneousTrailing) && sl_pts > 0 && be_atingido)
         {
            int trail_dist = (ts_active && ts_pts > 0) ? ts_pts : sl_pts;
            double desired_sl = ask + (trail_dist * point);
            if(desired_sl <= openPrice)
            {
               double min_step = point * ts_step_pts;
               if(curSL == 0.0 || desired_sl <= curSL - min_step)
               {
                  double desired_tp = (tp_pts > 0) ? (ask - tp_pts * point) : curTP;
                  trade.PositionModify(ticket, desired_sl, desired_tp);
               }
            }
         }
      }
   }
   CleanPartialTickets();
}

int OnInit()
{
   ChartSetInteger(ChartID(), CHART_FOREGROUND, false);
   ChartSetInteger(ChartID(), CHART_EVENT_MOUSE_MOVE, true);
   
   if(!g_master.Init(InpSymbol, InpMagicNumber, InpSlippage, InpPanelX, InpPanelY))
   {
      Print("Erro ao inicializar Boleta Scalping Mentor Pro!");
      return INIT_FAILED;
   }
   
   EventSetMillisecondTimer(200);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   g_master.Destroy(reason);
}

void OnTimer()
{
   g_master.CheckForegroundState();
   g_master.UpdateLiveMetrics();
}

void OnTick()
{
   g_master.CheckForegroundState();
   g_master.UpdateLiveMetrics();
   
   if(InpEnableATRAlvos && InpAutoApplyATR)
   {
      int atr_p = 0, sug_sl = 0, sug_tp = 0;
      if(g_master.GetATRTargets(atr_p, sug_sl, sug_tp))
      {
         if(g_master.GetSLPoints() != sug_sl || g_master.GetTPPoints() != sug_tp)
         {
            g_master.SetSLPoints(sug_sl);
            g_master.SetTPPoints(sug_tp);
            g_master.UpdateFieldValues();
            g_master.UpdateLiveSLTPLines();
         }
      }
   }
   
   GerenciarPosicoesAbertas();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   g_master.OnChartEvent(id, lparam, dparam, sparam);
}
//+------------------------------------------------------------------+
