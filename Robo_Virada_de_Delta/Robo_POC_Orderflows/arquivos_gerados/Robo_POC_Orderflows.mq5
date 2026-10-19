//+------------------------------------------------------------------+
//|                                        Robo_POC_Orderflows.mq5   |
//|               Motor de Trading Baseado na Dinâmica de POC        |
//|               Especificação Rigorosa & Fiel - Mike Valtos        |
//+------------------------------------------------------------------+
#property copyright   "Orderflows POC Engine - Mike Valtos Mechanics"
#property link        "https://www.mql5.com"
#property version     "2.00"
#property description "Automação institucional baseada na mecânica de migração e alinhamento de POC."
#property description "Filtro de Tendência Ativa, Rompimento de Base 2x4 e Falha de Continuação (Traps)."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_MARKET_TREND
{
   TREND_CHOP     = 0, // LATERAL (Chop / Consolidação)
   TREND_BULLISH  = 1, // MIGRANDO PARA CIMA (Alta - Bloqueio de Vendas)
   TREND_BEARISH  = 2  // MIGRANDO PARA BAIXO (Baixa - Bloqueio de Compras)
};

enum ENUM_PENDING_SIGNAL
{
   SIGNAL_NONE             = 0,
   SIGNAL_WAITING_BREAKOUT = 1, // Aguardando Rompimento da Base
   SIGNAL_TRAP_DETECTED    = 2  // Falha Detectada
};

enum ENUM_LOT_MODE
{
   LOT_FIXED          = 0, // Lote Fixo
   LOT_RISK_PERCENT   = 1  // Percentual de Risco sobre o Balanço
};

//+------------------------------------------------------------------+
//| PARÂMETROS DE ENTRADA (INPUTS)                                   |
//+------------------------------------------------------------------+
input group "=== FILTRO DE TENDÊNCIA & ESTADO DE MERCADO ==="
input int    InpToleranceTicks          = 2;     // Tolerância de Alinhamento 2x4 (em Ticks)
input int    InpConsolidationTicks      = 10;    // Faixa Máxima para Consolidação das 3 Barras (em Ticks)
input bool   InpStrictTrendBlock        = true;  // Bloquear Vendas na Tendência de Alta / Compras na de Baixa

input group "=== OS DOIS ÚNICOS GATILHOS VÁLIDOS ==="
input bool   InpEnableBreakout2x4       = true;  // Gatilho A: Rompimento da Base 2x4
input bool   InpEnableContinuationTrap  = true;  // Gatilho B: Falha de Continuação (Bear/Bull Trap)

input group "=== GESTÃO DE RISCO & ORDENS ==="
input ENUM_LOT_MODE InpLotMode          = LOT_FIXED; // Modo de Lote
input double InpFixedLot                = 1.0;   // Lote Fixo
input double InpRiskPercent             = 1.0;   // Risco por Operação (% do Balanço)
input double InpBufferTicks             = 2.0;   // Folga do Stop Loss além da Base/Extremo (em Ticks)
input double InpRiskRewardRatio         = 1.5;   // Relação Risco:Retorno para Take Profit (Ex: 1.5 ou 2.0)
input double InpTakeProfitFixedTicks    = 0.0;   // TP Fixo em Ticks (se 0, usa Risco:Retorno)
input bool   InpPrematureExit           = true;  // Invalidação: Fecho contra violando POC de entrada

input group "=== FILTROS DE HORÁRIO (DAY TRADE) ==="
input bool   InpUseTimeFilter           = true;  // Ativar Filtro de Horário
input int    InpStartHour               = 9;     // Hora de Início das Operações
input int    InpStartMinute             = 5;     // Minuto de Início das Operações
input int    InpEndHour                 = 17;    // Hora Limite para Novas Entradas
input int    InpEndMinute               = 0;     // Minuto Limite para Novas Entradas
input bool   InpCloseAllAtEOD           = true;  // Fechar Posições Abertas no Fim do Dia
input int    InpCloseAllHour            = 17;    // Hora de Encerramento Compulsório
input int    InpCloseAllMinute          = 45;    // Minuto de Encerramento Compulsório

input group "=== VISUALIZAÇÃO NO GRÁFICO & HUD ==="
input bool   InpShowHUD                 = true;  // Exibir Painel HUD em Tempo Real
input int    InpHUDCorner               = 1;     // Canto do HUD (0=Top-Left, 1=Top-Right, 2=Bottom-Left, 3=Bottom-Right)
input int    InpHUDXOffset              = 20;    // Distância X
input int    InpHUDYOffset              = 30;    // Distância Y
input bool   InpDrawPOCLines            = true;  // Traçar Pequenas Linhas de POC nas Barras
input bool   InpDrawBase2x4Line         = true;  // Traçar Linha Espessa na Base 2x4
input bool   InpDrawSignalArrows        = true;  // Plotar Setas de Entrada Confirmadas

input group "=== NOTIFICAÇÕES & IDENTIFICAÇÃO ==="
input bool   InpUseAlert                = true;  // Alerta sonoro / pop-up no terminal
input bool   InpUsePush                 = true;  // Notificação push no celular
input ulong  InpMagicNumber             = 777204;// Magic Number
input ulong  InpSlippage                = 20;    // Slippage (Pontos)

//+------------------------------------------------------------------+
//| ESTRUTURA DE DADOS DA BARRA                                      |
//+------------------------------------------------------------------+
struct SPOCBar
{
   datetime time;
   double   poc;
   double   open;
   double   high;
   double   low;
   double   close;
   double   volume_total;
   bool     is_calculated;
};

//+------------------------------------------------------------------+
//| CLASSE: MOTOR DE POC & DETECÇÃO ESTRUTURAL                       |
//+------------------------------------------------------------------+
class CPOCEngine
{
private:
   string         m_symbol;
   ENUM_TIMEFRAMES m_period;
   double         m_tick_size;
   double         m_point;
   int            m_digits;

   SPOCBar        m_cache[];
   int            m_cache_size;

   // Estado de Mercado
   ENUM_MARKET_TREND   m_trend;
   ENUM_PENDING_SIGNAL m_pending_signal;
   double              m_last_base_price;
   datetime            m_last_base_time;
   bool                m_has_active_base;

public:
   CPOCEngine();
   ~CPOCEngine();

   bool           Init(string symbol, ENUM_TIMEFRAMES period);
   void           UpdateBar(int bar_idx);
   void           UpdateRecentHistory(int count);
   bool           GetBar(int bar_idx, SPOCBar &data);

   void           EvaluateMarketState();
   ENUM_MARKET_TREND   GetTrend() const { return m_trend; }
   ENUM_PENDING_SIGNAL GetPendingSignal() const { return m_pending_signal; }
   double         GetLastBasePrice() const { return m_last_base_price; }
   bool           HasActiveBase() const { return m_has_active_base; }
   void           InvalidateBase() { m_has_active_base = false; }

   double         CalculatePOC(datetime bar_time, double high, double low);
};

CPOCEngine::CPOCEngine()
{
   m_cache_size       = 0;
   m_trend            = TREND_CHOP;
   m_pending_signal   = SIGNAL_NONE;
   m_last_base_price  = 0.0;
   m_last_base_time   = 0;
   m_has_active_base  = false;
}

CPOCEngine::~CPOCEngine()
{
   ArrayFree(m_cache);
}

bool CPOCEngine::Init(string symbol, ENUM_TIMEFRAMES period)
{
   m_symbol    = symbol;
   m_period    = period;
   m_digits    = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   m_point     = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   m_tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(m_tick_size <= 0.0) m_tick_size = m_point;

   m_cache_size = 200;
   ArrayResize(m_cache, m_cache_size);
   for(int i = 0; i < m_cache_size; i++)
   {
      m_cache[i].is_calculated = false;
      m_cache[i].time = 0;
   }

   UpdateRecentHistory(50);
   EvaluateMarketState();
   return true;
}

double CPOCEngine::CalculatePOC(datetime bar_time, double high, double low)
{
   if(high <= low || m_tick_size <= 0.0)
      return NormalizeDouble(low, m_digits);

   long start_msc = (long)bar_time * 1000;
   long end_msc   = ((long)bar_time + PeriodSeconds(m_period)) * 1000 - 1;

   datetime current_time = TimeCurrent();
   if(bar_time + PeriodSeconds(m_period) > current_time)
      end_msc = (long)current_time * 1000 + 999;

   MqlTick ticks[];
   int nTicks = CopyTicksRange(m_symbol, ticks, COPY_TICKS_ALL, start_msc, end_msc);

   int steps = (int)MathRound((high - low) / m_tick_size) + 1;
   if(steps < 1) steps = 1;

   if(nTicks > 0 && steps <= 30000)
   {
      double vol_bucket[];
      ArrayResize(vol_bucket, steps);
      ArrayInitialize(vol_bucket, 0.0);

      for(int i = 0; i < nTicks; i++)
      {
         double price = 0.0;
         if(ticks[i].last > 0.0)
            price = ticks[i].last;
         else if(ticks[i].bid > 0.0 && ticks[i].ask > 0.0)
            price = (ticks[i].bid + ticks[i].ask) * 0.5;
         else if(ticks[i].bid > 0.0)
            price = ticks[i].bid;
         else
            price = ticks[i].ask;

         double v = 1.0;
         if(ticks[i].volume > 0)
            v = (double)ticks[i].volume;
         else if(ticks[i].volume_real > 0.0)
            v = ticks[i].volume_real;

         int idx = (int)MathRound((price - low) / m_tick_size);
         if(idx >= 0 && idx < steps)
            vol_bucket[idx] += v;
      }

      double max_v = -1.0;
      int max_idx = 0;
      for(int s = 0; s < steps; s++)
      {
         if(vol_bucket[s] > max_v)
         {
            max_v   = vol_bucket[s];
            max_idx = s;
         }
      }

      ArrayFree(vol_bucket);
      return NormalizeDouble(low + max_idx * m_tick_size, m_digits);
   }

   // Fallback para barras M1 ou preço típico
   if(m_period > PERIOD_M1)
   {
      MqlRates m1[];
      int count = CopyRates(m_symbol, PERIOD_M1, bar_time, bar_time + PeriodSeconds(m_period) - 1, m1);
      if(count > 0)
      {
         double best_vol = -1.0;
         double best_p = (high + low) * 0.5;
         for(int r = 0; r < count; r++)
         {
            double v = (m1[r].real_volume > 0) ? (double)m1[r].real_volume : (double)m1[r].tick_volume;
            if(v > best_vol)
            {
               best_vol = v;
               best_p = (m1[r].high + m1[r].low + m1[r].close) / 3.0;
            }
         }
         int idx = (int)MathRound((best_p - low) / m_tick_size);
         if(idx < 0) idx = 0;
         if(idx >= steps) idx = steps - 1;
         return NormalizeDouble(low + idx * m_tick_size, m_digits);
      }
   }

   double typical = (high + low + iClose(m_symbol, m_period, 0)) / 3.0;
   int idx = (int)MathRound((typical - low) / m_tick_size);
   if(idx < 0) idx = 0;
   if(idx >= steps) idx = steps - 1;
   return NormalizeDouble(low + idx * m_tick_size, m_digits);
}

void CPOCEngine::UpdateBar(int bar_idx)
{
   if(bar_idx < 0 || bar_idx >= m_cache_size)
      return;

   datetime b_time = iTime(m_symbol, m_period, bar_idx);
   if(b_time == 0) return;

   if(bar_idx > 0 && m_cache[bar_idx].is_calculated && m_cache[bar_idx].time == b_time)
      return;

   double h = iHigh(m_symbol, m_period, bar_idx);
   double l = iLow(m_symbol, m_period, bar_idx);
   double o = iOpen(m_symbol, m_period, bar_idx);
   double c = iClose(m_symbol, m_period, bar_idx);

   double poc = CalculatePOC(b_time, h, l);

   m_cache[bar_idx].time          = b_time;
   m_cache[bar_idx].poc           = poc;
   m_cache[bar_idx].open          = o;
   m_cache[bar_idx].high          = h;
   m_cache[bar_idx].low           = l;
   m_cache[bar_idx].close         = c;
   m_cache[bar_idx].is_calculated = true;
}

void CPOCEngine::UpdateRecentHistory(int count)
{
   int limit = MathMin(count, m_cache_size - 1);
   for(int i = limit; i >= 0; i--)
      UpdateBar(i);
}

bool CPOCEngine::GetBar(int bar_idx, SPOCBar &data)
{
   if(bar_idx < 0 || bar_idx >= m_cache_size)
      return false;

   if(!m_cache[bar_idx].is_calculated || bar_idx == 0)
      UpdateBar(bar_idx);

   data = m_cache[bar_idx];
   return data.is_calculated;
}

//+------------------------------------------------------------------+
//| MÓDULO 1: CLASSIFICAÇÃO DO ESTADO DE MERCADO (FILTRO OBRIGATÓRIO)|
//+------------------------------------------------------------------+
void CPOCEngine::EvaluateMarketState()
{
   SPOCBar b1, b2, b3;
   if(!GetBar(1, b1) || !GetBar(2, b2) || !GetBar(3, b3))
      return;

   double tol = InpToleranceTicks * m_tick_size;
   double consol_range = InpConsolidationTicks * m_tick_size;

   // 1. Tendência de Alta Ativa (Bloqueio de Vendas)
   if(b1.poc > b2.poc && b2.poc > b3.poc && b1.close > b2.close)
   {
      m_trend = TREND_BULLISH;
   }
   // 2. Tendência de Baixa Ativa (Bloqueio de Compras)
   else if(b1.poc < b2.poc && b2.poc < b3.poc && b1.close < b2.close)
   {
      m_trend = TREND_BEARISH;
   }
   // 3. Consolidação Detectada (Chop)
   else
   {
      double max_poc = MathMax(b1.poc, MathMax(b2.poc, b3.poc));
      double min_poc = MathMin(b1.poc, MathMin(b2.poc, b3.poc));
      if((max_poc - min_poc) <= consol_range)
         m_trend = TREND_CHOP;
      else
         m_trend = TREND_CHOP;
   }

   // 4. Detecção de Base 2x4 Recente (Barras 2 e 3 ou Barras 1 e 2)
   if(MathAbs(b2.poc - b3.poc) <= tol)
   {
      m_last_base_price = NormalizeDouble((b2.poc + b3.poc) * 0.5, m_digits);
      m_last_base_time  = b3.time;
      m_has_active_base = true;
   }
   else if(MathAbs(b1.poc - b2.poc) <= tol)
   {
      m_last_base_price = NormalizeDouble((b1.poc + b2.poc) * 0.5, m_digits);
      m_last_base_time  = b2.time;
      m_has_active_base = true;
   }

   // 5. Sinal Pendente
   m_pending_signal = SIGNAL_NONE;
   if(m_has_active_base)
   {
      m_pending_signal = SIGNAL_WAITING_BREAKOUT;
   }
   else
   {
      // Verifica se houve tentativa de continuação que possa falhar
      if(b3.close < b3.open && b2.close < b2.open && b3.poc > b2.poc)
         m_pending_signal = SIGNAL_TRAP_DETECTED; // Possível Bear Trap em formação
      else if(b3.close > b3.open && b2.close > b2.open && b3.poc < b2.poc)
         m_pending_signal = SIGNAL_TRAP_DETECTED; // Possível Bull Trap em formação
   }
}

//+------------------------------------------------------------------+
//| CLASSE: RENDERIZADOR GRÁFICO (MÓDULO 3)                          |
//+------------------------------------------------------------------+
class CPOCChartRenderer
{
private:
   string   m_symbol;
   ENUM_TIMEFRAMES m_period;
   string   m_prefix;
   int      m_digits;

public:
   CPOCChartRenderer();
   ~CPOCChartRenderer();

   void Init(string symbol, ENUM_TIMEFRAMES period);
   void ClearAll();
   void DrawBarPOC(datetime bar_time, double poc_price);
   void DrawBase2x4(double base_price, datetime start_time);
   void RemoveBase2x4();
   void DrawSignalArrow(datetime bar_time, double price, bool is_buy, string text);
};

CPOCChartRenderer::CPOCChartRenderer()
{
   m_prefix = "MV_POC_";
}

CPOCChartRenderer::~CPOCChartRenderer()
{
   ClearAll();
}

void CPOCChartRenderer::Init(string symbol, ENUM_TIMEFRAMES period)
{
   m_symbol = symbol;
   m_period = period;
   m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   m_prefix = "MV_POC_" + m_symbol + "_";
}

void CPOCChartRenderer::ClearAll()
{
   ObjectsDeleteAll(0, m_prefix);
   ChartRedraw(0);
}

void CPOCChartRenderer::DrawBarPOC(datetime bar_time, double poc_price)
{
   if(!InpDrawPOCLines) return;

   string obj_name = m_prefix + "BAR_" + TimeToString(bar_time, TIME_DATE|TIME_MINUTES);
   datetime end_time = bar_time + PeriodSeconds(m_period);

   if(ObjectFind(0, obj_name) < 0)
   {
      ObjectCreate(0, obj_name, OBJ_TREND, 0, bar_time, poc_price, end_time, poc_price);
      ObjectSetInteger(0, obj_name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrSilver);
      ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, obj_name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, obj_name, OBJPROP_TOOLTIP, "POC: " + DoubleToString(poc_price, m_digits));
   }
}

void CPOCChartRenderer::DrawBase2x4(double base_price, datetime start_time)
{
   if(!InpDrawBase2x4Line || base_price <= 0.0) return;

   string obj_name = m_prefix + "BASE_2x4";
   datetime end_proj = TimeCurrent() + PeriodSeconds(m_period) * 20;

   if(ObjectFind(0, obj_name) >= 0)
      ObjectDelete(0, obj_name);

   ObjectCreate(0, obj_name, OBJ_TREND, 0, start_time, base_price, end_proj, base_price);
   ObjectSetInteger(0, obj_name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrGold);
   ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 3); // Linha horizontal espessa
   ObjectSetInteger(0, obj_name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, obj_name, OBJPROP_TOOLTIP, "Base 2x4 Consolidada: " + DoubleToString(base_price, m_digits));
}

void CPOCChartRenderer::RemoveBase2x4()
{
   string obj_name = m_prefix + "BASE_2x4";
   if(ObjectFind(0, obj_name) >= 0)
      ObjectDelete(0, obj_name);
}

void CPOCChartRenderer::DrawSignalArrow(datetime bar_time, double price, bool is_buy, string text)
{
   if(!InpDrawSignalArrows) return;

   string obj_name = m_prefix + "SIG_" + TimeToString(bar_time, TIME_DATE|TIME_MINUTES);
   ENUM_OBJECT obj_type = is_buy ? OBJ_ARROW_BUY : OBJ_ARROW_SELL;

   if(ObjectFind(0, obj_name) < 0)
   {
      ObjectCreate(0, obj_name, obj_type, 0, bar_time, price);
      ObjectSetInteger(0, obj_name, OBJPROP_COLOR, is_buy ? clrLime : clrRed);
      ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 3);
      ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, obj_name, OBJPROP_TOOLTIP, text);
   }
}

//+------------------------------------------------------------------+
//| CLASSE: PAINEL HUD EM TEMPO REAL (MÓDULO 4)                      |
//+------------------------------------------------------------------+
class CPOCHUD
{
private:
   string   m_symbol;
   ENUM_TIMEFRAMES m_period;
   string   m_prefix;
   int      m_digits;

   void     CreateLabel(string name, string text, int x, int y, color clr, int font_size=9, bool bold=false);
   void     UpdateLabel(string name, string text, color clr=clrWhite);

public:
   CPOCHUD();
   ~CPOCHUD();

   void     Init(string symbol, ENUM_TIMEFRAMES period);
   void     Destroy();
   void     Update(ENUM_MARKET_TREND trend,
                   double last_base_price, bool has_base,
                   ENUM_PENDING_SIGNAL pending_sig,
                   string pos_type, double lot, double avg_price, double sl, double tp,
                   double floating_pnl, double floating_pts);
};

CPOCHUD::CPOCHUD()
{
   m_prefix = "MV_HUD_";
}

CPOCHUD::~CPOCHUD()
{
   Destroy();
}

void CPOCHUD::Init(string symbol, ENUM_TIMEFRAMES period)
{
   m_symbol = symbol;
   m_period = period;
   m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   m_prefix = "MV_HUD_";

   if(!InpShowHUD) return;

   string bg_name = m_prefix + "BG";
   if(ObjectFind(0, bg_name) < 0)
   {
      ObjectCreate(0, bg_name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg_name, OBJPROP_CORNER, InpHUDCorner);
      ObjectSetInteger(0, bg_name, OBJPROP_XDISTANCE, InpHUDXOffset);
      ObjectSetInteger(0, bg_name, OBJPROP_YDISTANCE, InpHUDYOffset);
      ObjectSetInteger(0, bg_name, OBJPROP_XSIZE, 300);
      ObjectSetInteger(0, bg_name, OBJPROP_YSIZE, 230);
      ObjectSetInteger(0, bg_name, OBJPROP_BGCOLOR, C'16,20,28'); // Dark Blue/Grey elegante
      ObjectSetInteger(0, bg_name, OBJPROP_BORDER_COLOR, C'40,50,68');
      ObjectSetInteger(0, bg_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg_name, OBJPROP_SELECTABLE, false);
   }

   int y = InpHUDYOffset + 10;
   int x = InpHUDXOffset + 14;

   CreateLabel("TITLE",      "ORDERFLOWS - MIKE VALTOS", x, y, clrGold, 10, true);
   CreateLabel("SUB",        m_symbol + " | " + EnumToString(m_period) + " | 2 Gatilhos Válidos", x, y += 18, clrSilver, 8);
   CreateLabel("SEP1",       "--------------------------------------------------", x, y += 12, clrDimGray, 7);

   CreateLabel("TREND",      "Tendência de POC: ---", x, y += 14, clrWhite, 9, true);
   CreateLabel("BASE2x4",    "Último Alinhamento (2x4): ---", x, y += 18, clrWhite, 9);
   CreateLabel("SIGNAL",     "Sinal Pendente: Nenhum", x, y += 18, clrWhite, 9);

   CreateLabel("SEP2",       "--------------------------------------------------", x, y += 12, clrDimGray, 7);

   CreateLabel("POS_DIR",    "Status: SEM POSIÇÃO", x, y += 14, clrLightSkyBlue, 9, true);
   CreateLabel("POS_INFO",   "Lote: 0.00 | Médio: 0.00", x, y += 16, clrSilver, 8);
   CreateLabel("POS_STOPS",  "SL: --- | TP: ---", x, y += 16, clrSilver, 8);
   CreateLabel("POS_PNL",    "Lucro Flutuante: R$ 0.00 (0 pts)", x, y += 16, clrWhite, 9, true);
}

void CPOCHUD::CreateLabel(string name, string text, int x, int y, color clr, int font_size, bool bold)
{
   string full_name = m_prefix + name;
   if(ObjectFind(0, full_name) < 0)
   {
      ObjectCreate(0, full_name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, full_name, OBJPROP_CORNER, InpHUDCorner);
      ObjectSetInteger(0, full_name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, full_name, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, full_name, OBJPROP_TEXT, text);
      ObjectSetString(0, full_name, OBJPROP_FONT, "Segoe UI");
      ObjectSetInteger(0, full_name, OBJPROP_FONTSIZE, font_size);
      ObjectSetInteger(0, full_name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, full_name, OBJPROP_SELECTABLE, false);
   }
}

void CPOCHUD::UpdateLabel(string name, string text, color clr)
{
   string full_name = m_prefix + name;
   if(ObjectFind(0, full_name) >= 0)
   {
      ObjectSetString(0, full_name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, full_name, OBJPROP_COLOR, clr);
   }
}

void CPOCHUD::Destroy()
{
   ObjectsDeleteAll(0, m_prefix);
   ChartRedraw(0);
}

void CPOCHUD::Update(ENUM_MARKET_TREND trend,
                     double last_base_price, bool has_base,
                     ENUM_PENDING_SIGNAL pending_sig,
                     string pos_type, double lot, double avg_price, double sl, double tp,
                     double floating_pnl, double floating_pts)
{
   if(!InpShowHUD) return;

   // 1. Tendência de POC
   string trend_text = "LATERAL (Chop)";
   color  trend_clr  = clrLightYellow;
   if(trend == TREND_BULLISH)
   {
      trend_text = "MIGRANDO PARA CIMA (Alta - Bloqueio Venda)";
      trend_clr  = clrLimeGreen;
   }
   else if(trend == TREND_BEARISH)
   {
      trend_text = "MIGRANDO PARA BAIXO (Baixa - Bloqueio Compra)";
      trend_clr  = clrOrangeRed;
   }
   UpdateLabel("TREND", "Tendência POC: " + trend_text, trend_clr);

   // 2. Último Alinhamento 2x4
   string base_str = "Nenhum";
   color  base_clr = clrSilver;
   if(has_base && last_base_price > 0.0)
   {
      base_str = "Base em " + DoubleToString(last_base_price, m_digits);
      base_clr = clrGold;
   }
   UpdateLabel("BASE2x4", "Alinhamento (2x4): " + base_str, base_clr);

   // 3. Sinal Pendente
   string sig_str = "Nenhum";
   color  sig_clr = clrSilver;
   if(pending_sig == SIGNAL_WAITING_BREAKOUT)
   {
      sig_str = "Aguardando Rompimento da Base";
      sig_clr = clrDeepSkyBlue;
   }
   else if(pending_sig == SIGNAL_TRAP_DETECTED)
   {
      sig_str = "Falha Detectada (Armadilha em curso)";
      sig_clr = clrAqua;
   }
   UpdateLabel("SIGNAL", "Sinal Pendente: " + sig_str, sig_clr);

   // 4. Status da Ordem
   color pos_clr = clrLightGray;
   if(pos_type == "COMPRA")  pos_clr = clrLime;
   if(pos_type == "VENDA")   pos_clr = clrRed;
   UpdateLabel("POS_DIR", "Status: " + pos_type, pos_clr);

   if(avg_price > 0.0)
   {
      UpdateLabel("POS_INFO", "Lote: " + DoubleToString(lot, 2) + " | Preço Médio: " + DoubleToString(avg_price, m_digits), clrWhite);
      UpdateLabel("POS_STOPS", "SL: " + DoubleToString(sl, m_digits) + " | TP: " + DoubleToString(tp, m_digits), clrWhite);
   }
   else
   {
      UpdateLabel("POS_INFO", "Lote: 0.00 | Sem ordens em aberto", clrDarkGray);
      UpdateLabel("POS_STOPS", "SL: --- | TP: ---", clrDarkGray);
   }

   // 5. Lucro Flutuante
   color pnl_clr = (floating_pnl >= 0.0) ? clrLimeGreen : clrRed;
   string pts_sgn = (floating_pts >= 0.0) ? "+" : "";
   string pnl_sgn = (floating_pnl >= 0.0) ? "+" : "";
   UpdateLabel("POS_PNL", "Flutuante: " + pnl_sgn + DoubleToString(floating_pnl, 2) + " (" + pts_sgn + DoubleToString(floating_pts, 0) + " pts)", pnl_clr);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| CLASSE: EXECUTOR DE ORDENS E NOTIFICAÇÕES                        |
//+------------------------------------------------------------------+
class CPOCTradeManager
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_period;
   CTrade            m_trade;
   CPositionInfo     m_position;
   int               m_digits;
   double            m_point;
   double            m_tick_size;

   double            m_entry_poc;
   void              SetFillingMode();
   double            NormalizeVolume(double lot);
   double            NormalizePrice(double price);

public:
   CPOCTradeManager();
   ~CPOCTradeManager();

   bool              Init(string symbol, ENUM_TIMEFRAMES period);
   bool              HasPosition(string &dir, double &lot, double &avg_p, double &sl, double &tp, double &profit, double &pts);
   bool              ExecuteBuy(double sl_price, double tp_price, double entry_poc, string trigger_type, string detail);
   bool              ExecuteSell(double sl_price, double tp_price, double entry_poc, string trigger_type, string detail);
   void              CheckPrematureExit(double close_price);
   void              ClosePosition(string reason);
   double            CalculateLot(double sl_pts);
};

CPOCTradeManager::CPOCTradeManager()
{
   m_entry_poc = 0.0;
}

CPOCTradeManager::~CPOCTradeManager()
{
}

bool CPOCTradeManager::Init(string symbol, ENUM_TIMEFRAMES period)
{
   m_symbol    = symbol;
   m_period    = period;
   m_digits    = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   m_point     = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   m_tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(m_tick_size <= 0.0) m_tick_size = m_point;

   m_trade.SetExpertMagicNumber(InpMagicNumber);
   m_trade.SetDeviationInPoints(InpSlippage);
   SetFillingMode();
   return true;
}

void CPOCTradeManager::SetFillingMode()
{
   uint filling = (uint)SymbolInfoInteger(m_symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0)
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      m_trade.SetTypeFilling(ORDER_FILLING_RETURN);
}

double CPOCTradeManager::NormalizeVolume(double lot)
{
   double min_v  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   double max_v  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
   double step_v = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
   if(step_v <= 0.0) step_v = 0.01;

   double norm = MathFloor(lot / step_v) * step_v;
   if(norm < min_v) norm = min_v;
   if(norm > max_v) norm = max_v;
   return norm;
}

double CPOCTradeManager::NormalizePrice(double price)
{
   if(m_tick_size <= 0.0) return NormalizeDouble(price, m_digits);
   return NormalizeDouble(MathRound(price / m_tick_size) * m_tick_size, m_digits);
}

bool CPOCTradeManager::HasPosition(string &dir, double &lot, double &avg_p, double &sl, double &tp, double &profit, double &pts)
{
   if(m_position.Select(m_symbol))
   {
      if(m_position.Magic() == InpMagicNumber || InpMagicNumber == 0)
      {
         dir    = (m_position.PositionType() == POSITION_TYPE_BUY) ? "COMPRA" : "VENDA";
         lot    = m_position.Volume();
         avg_p  = m_position.PriceOpen();
         sl     = m_position.StopLoss();
         tp     = m_position.TakeProfit();
         profit = m_position.Profit() + m_position.Swap();

         double current_p = (dir == "COMPRA") ? SymbolInfoDouble(m_symbol, SYMBOL_BID) : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         pts = (dir == "COMPRA") ? (current_p - avg_p) / m_point : (avg_p - current_p) / m_point;
         return true;
      }
   }
   return false;
}

double CPOCTradeManager::CalculateLot(double sl_pts)
{
   if(InpLotMode == LOT_FIXED || sl_pts <= 0.0)
      return NormalizeVolume(InpFixedLot);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_m  = balance * (InpRiskPercent / 100.0);
   double tick_v  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_v <= 0.0) tick_v = 1.0;

   double ticks_risk = sl_pts / (m_tick_size / m_point);
   if(ticks_risk <= 0.0) ticks_risk = 1.0;

   double lot = risk_m / (ticks_risk * tick_v);
   return NormalizeVolume(lot);
}

bool CPOCTradeManager::ExecuteBuy(double sl_price, double tp_price, double entry_poc, string trigger_type, string detail)
{
   string d; double l, a, s, t, prof, pts;
   if(HasPosition(d, l, a, s, t, prof, pts))
      return false; // Já posicionado

   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   sl_price = NormalizePrice(sl_price);
   tp_price = NormalizePrice(tp_price);

   long stops_lvl = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_dist = stops_lvl * m_point;
   if(ask - sl_price < min_dist)
      sl_price = NormalizePrice(ask - min_dist - 2.0 * m_point);
   if(tp_price - ask < min_dist)
      tp_price = NormalizePrice(ask + min_dist + 2.0 * m_point);

   double sl_pts = (ask - sl_price) / m_point;
   double lot = CalculateLot(sl_pts);

   string comment = "POC Buy [" + trigger_type + "]";
   if(m_trade.Buy(lot, m_symbol, ask, sl_price, tp_price, comment))
   {
      m_entry_poc = entry_poc;

      // Módulo 5: Notificações Oficiais
      string msg = "";
      if(trigger_type == "ROMPIMENTO 2x4")
      {
         msg = StringFormat("[ORDEM EXECUTADA - ROMPIMENTO 2x4] Direção: COMPRA | %s | SL: %s | TP: %s",
                            detail,
                            DoubleToString(sl_price, m_digits),
                            DoubleToString(tp_price, m_digits));
      }
      else
      {
         msg = StringFormat("[ORDEM EXECUTADA - FALHA DE CONTINUAÇÃO] Direção: COMPRA | %s | SL: %s | TP: %s",
                            detail,
                            DoubleToString(sl_price, m_digits),
                            DoubleToString(tp_price, m_digits));
      }

      Print(msg);
      if(InpUseAlert) Alert(msg);
      if(InpUsePush)  SendNotification(msg);
      return true;
   }
   else
   {
      PrintFormat("Erro ao executar Compra: %d - %s", m_trade.ResultRetcode(), m_trade.ResultComment());
      return false;
   }
}

bool CPOCTradeManager::ExecuteSell(double sl_price, double tp_price, double entry_poc, string trigger_type, string detail)
{
   string d; double l, a, s, t, prof, pts;
   if(HasPosition(d, l, a, s, t, prof, pts))
      return false;

   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   sl_price = NormalizePrice(sl_price);
   tp_price = NormalizePrice(tp_price);

   long stops_lvl = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_dist = stops_lvl * m_point;
   if(sl_price - bid < min_dist)
      sl_price = NormalizePrice(bid + min_dist + 2.0 * m_point);
   if(bid - tp_price < min_dist)
      tp_price = NormalizePrice(bid - min_dist - 2.0 * m_point);

   double sl_pts = (sl_price - bid) / m_point;
   double lot = CalculateLot(sl_pts);

   string comment = "POC Sell [" + trigger_type + "]";
   if(m_trade.Sell(lot, m_symbol, bid, sl_price, tp_price, comment))
   {
      m_entry_poc = entry_poc;

      // Módulo 5: Notificações Oficiais
      string msg = "";
      if(trigger_type == "ROMPIMENTO 2x4")
      {
         msg = StringFormat("[ORDEM EXECUTADA - ROMPIMENTO 2x4] Direção: VENDA | %s | SL: %s | TP: %s",
                            detail,
                            DoubleToString(sl_price, m_digits),
                            DoubleToString(tp_price, m_digits));
      }
      else
      {
         msg = StringFormat("[ORDEM EXECUTADA - FALHA DE CONTINUAÇÃO] Direção: VENDA | %s | SL: %s | TP: %s",
                            detail,
                            DoubleToString(sl_price, m_digits),
                            DoubleToString(tp_price, m_digits));
      }

      Print(msg);
      if(InpUseAlert) Alert(msg);
      if(InpUsePush)  SendNotification(msg);
      return true;
   }
   else
   {
      PrintFormat("Erro ao executar Venda: %d - %s", m_trade.ResultRetcode(), m_trade.ResultComment());
      return false;
   }
}

void CPOCTradeManager::CheckPrematureExit(double close_price)
{
   if(!InpPrematureExit || m_entry_poc <= 0.0) return;

   string d; double l, a, s, t, prof, pts;
   if(HasPosition(d, l, a, s, t, prof, pts))
   {
      if(d == "COMPRA" && close_price < m_entry_poc)
      {
         ClosePosition("Invalidação de Fecho abaixo do POC de Entrada");
      }
      else if(d == "VENDA" && close_price > m_entry_poc)
      {
         ClosePosition("Invalidação de Fecho acima do POC de Entrada");
      }
   }
}

void CPOCTradeManager::ClosePosition(string reason)
{
   if(m_position.Select(m_symbol))
   {
      double profit = m_position.Profit();
      double price  = m_position.PriceOpen();
      double curr_p = (m_position.PositionType() == POSITION_TYPE_BUY) ? SymbolInfoDouble(m_symbol, SYMBOL_BID) : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double pts    = (m_position.PositionType() == POSITION_TYPE_BUY) ? (curr_p - price)/m_point : (price - curr_p)/m_point;

      if(m_trade.PositionClose(m_position.Ticket()))
      {
         string msg = StringFormat("[POC TRADE FECHADO] Saída por %s | Resultado: %+.0f pts / %+.2f",
                                   reason, pts, profit);
         Print(msg);
         if(InpUseAlert) Alert(msg);
         if(InpUsePush)  SendNotification(msg);
         m_entry_poc = 0.0;
      }
   }
}

//+------------------------------------------------------------------+
//| INSTÂNCIAS GLOBAIS                                               |
//+------------------------------------------------------------------+
CPOCEngine        g_engine;
CPOCChartRenderer g_renderer;
CPOCHUD           g_hud;
CPOCTradeManager  g_trade;

datetime          g_last_bar_time = 0;
ulong             g_last_hud_update = 0;

//+------------------------------------------------------------------+
//| CONTROLE DE HORÁRIO                                              |
//+------------------------------------------------------------------+
bool IsTradingTimeAllowed()
{
   if(!InpUseTimeFilter) return true;

   MqlDateTime dt;
   TimeCurrent(dt);

   int now_mins   = dt.hour * 60 + dt.min;
   int start_mins = InpStartHour * 60 + InpStartMinute;
   int end_mins   = InpEndHour * 60 + InpEndMinute;

   return (now_mins >= start_mins && now_mins <= end_mins);
}

bool IsEndOfDayCloseTime()
{
   if(!InpUseTimeFilter || !InpCloseAllAtEOD) return false;

   MqlDateTime dt;
   TimeCurrent(dt);

   int now_mins   = dt.hour * 60 + dt.min;
   int close_mins = InpCloseAllHour * 60 + InpCloseAllMinute;

   return (now_mins >= close_mins);
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== INICIANDO ORDERFLOWS POC (MIKE VALTOS - ESPECIFICAÇÃO RIGOROSA) ===");

   if(!g_engine.Init(_Symbol, _Period))
   {
      Print("Falha ao inicializar Motor de POC!");
      return INIT_FAILED;
   }

   g_renderer.Init(_Symbol, _Period);
   g_hud.Init(_Symbol, _Period);
   g_trade.Init(_Symbol, _Period);

   // Desenha as linhas de POC nas barras anteriores para acompanhamento
   for(int i = 1; i <= 30; i++)
   {
      SPOCBar b;
      if(g_engine.GetBar(i, b))
         g_renderer.DrawBarPOC(b.time, b.poc);
   }

   if(g_engine.HasActiveBase())
      g_renderer.DrawBase2x4(g_engine.GetLastBasePrice(), iTime(_Symbol, _Period, 2));

   g_last_bar_time = iTime(_Symbol, _Period, 0);
   g_last_hud_update = GetTickCount64();

   Print("Robô inicializado com sucesso em ", _Symbol, " | Timeframe: ", EnumToString(_Period));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Encerrando Robô POC. Motivo: ", reason);
   g_renderer.ClearAll();
   g_hud.Destroy();
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime current_bar_time = iTime(_Symbol, _Period, 0);

   // 1. Fechamento Compulsório de Fim de Dia
   if(IsEndOfDayCloseTime())
   {
      string d; double l, a, s, t, prof, pts;
      if(g_trade.HasPosition(d, l, a, s, t, prof, pts))
      {
         g_trade.ClosePosition("Fim de Dia (Day Trade)");
      }
   }

   // 2. DETECÇÃO ATÔMICA DE NOVA BARRA (Bar[1] acabou de fechar)
   if(current_bar_time != g_last_bar_time)
   {
      g_last_bar_time = current_bar_time;

      // Atualiza o POC da barra 1 recém fechada
      g_engine.UpdateBar(1);
      g_engine.EvaluateMarketState();

      SPOCBar bar1, bar2, bar3;
      bool b1_ok = g_engine.GetBar(1, bar1);
      bool b2_ok = g_engine.GetBar(2, bar2);
      bool b3_ok = g_engine.GetBar(3, bar3);

      if(b1_ok && b2_ok && b3_ok)
      {
         // Módulo 3: Desenho do POC da barra anterior
         g_renderer.DrawBarPOC(bar1.time, bar1.poc);

         // Módulo 3: Desenho da Base 2x4 se houver
         if(g_engine.HasActiveBase())
            g_renderer.DrawBase2x4(g_engine.GetLastBasePrice(), bar2.time);

         // Invalidação prematura por violação do POC de entrada
         g_trade.CheckPrematureExit(bar1.close);

         // AVALIAÇÃO DOS DOIS ÚNICOS GATILHOS VÁLIDOS
         if(IsTradingTimeAllowed())
         {
            ENUM_MARKET_TREND trend = g_engine.GetTrend();
            double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
            if(tick_size <= 0.0) tick_size = _Point;

            double tol    = InpToleranceTicks * tick_size;
            double buffer = InpBufferTicks * tick_size;

            bool buy_triggered  = false;
            bool sell_triggered = false;
            string trig_type    = "";
            string trig_detail  = "";
            double sl_calc      = 0.0;
            double tp_calc      = 0.0;

            // ===================================================================
            // GATILHO A: ROMPIMENTO DA BASE "2x4" (Consolidação de POCs)
            // ===================================================================
            if(InpEnableBreakout2x4)
            {
               // Condição: Duas ou mais barras consecutivas compartilham o mesmo nível de POC
               if(MathAbs(bar2.poc - bar3.poc) <= tol)
               {
                  double base_level = NormalizeDouble((bar2.poc + bar3.poc) * 0.5, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

                  // Entrada de Compra: Bar[1] fecha acima da base 2x4
                  // Filtro Obrigatório: Proibido comprar se estiver em Tendência de Baixa Ativa
                  if(bar1.close > base_level && (!InpStrictTrendBlock || trend != TREND_BEARISH))
                  {
                     buy_triggered = true;
                     trig_type     = "ROMPIMENTO 2x4";
                     trig_detail   = "Base rompida: " + DoubleToString(base_level, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
                     // Stop Loss: Mínima das barras da base menos buffer
                     sl_calc       = MathMin(bar2.low, bar3.low) - buffer;
                  }
                  // Entrada de Venda: Bar[1] fecha abaixo da base 2x4
                  // Filtro Obrigatório: Proibido vender se estiver em Tendência de Alta Ativa
                  else if(bar1.close < base_level && (!InpStrictTrendBlock || trend != TREND_BULLISH))
                  {
                     sell_triggered = true;
                     trig_type      = "ROMPIMENTO 2x4";
                     trig_detail    = "Base rompida: " + DoubleToString(base_level, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
                     // Stop Loss: Máxima das barras da base mais buffer
                     sl_calc        = MathMax(bar2.high, bar3.high) + buffer;
                  }

                  // Se rompeu, a base cumpriu seu papel
                  if(buy_triggered || sell_triggered)
                  {
                     g_engine.InvalidateBase();
                     g_renderer.RemoveBase2x4();
                  }
               }
            }

            // ===================================================================
            // GATILHO B: FALHA DE CONTINUAÇÃO (Armadilha / Reversão Real)
            // ===================================================================
            if(!buy_triggered && !sell_triggered && InpEnableContinuationTrap)
            {
               // --- Cenário de Compra (Bear Trap demonstrada no vídeo) ---
               // 1. Ocorrem 2 barras vermelhas consecutivas com POCs decrescentes (POC[3] > POC[2])
               bool two_red_bars = (bar3.close < bar3.open && bar2.close < bar2.open);
               bool pocs_falling = (bar3.poc > bar2.poc);

               if(two_red_bars && pocs_falling)
               {
                  // 2. Bar[1] tenta renovar mínima mas não tem continuidade: fecha VERDE e com preço acima de POC[2]
                  bool bar1_green = (bar1.close > bar1.open);
                  bool bar1_above_poc2 = (bar1.close > bar2.poc);

                  // Filtro Obrigatório: Não comprar contra forte expansão vendedora
                  if(bar1_green && bar1_above_poc2 && (!InpStrictTrendBlock || trend != TREND_BEARISH))
                  {
                     buy_triggered = true;
                     trig_type     = "FALHA DE CONTINUAÇÃO";
                     trig_detail   = "Vendedores presos abaixo de " + DoubleToString(bar2.poc, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
                     // Stop Loss: Mínima absoluta do movimento recente
                     sl_calc       = MathMin(bar1.low, MathMin(bar2.low, bar3.low)) - buffer;
                  }
               }

               // --- Cenário de Venda (Bull Trap) ---
               // 1. Ocorrem 2 barras verdes consecutivas com POCs crescentes (POC[3] < POC[2])
               bool two_green_bars = (bar3.close > bar3.open && bar2.close > bar2.open);
               bool pocs_rising    = (bar3.poc < bar2.poc);

               if(!buy_triggered && two_green_bars && pocs_rising)
               {
                  // 2. Bar[1] tenta renovar máxima mas falha: fecha VERMELHA e com preço abaixo de POC[2]
                  bool bar1_red = (bar1.close < bar1.open);
                  bool bar1_below_poc2 = (bar1.close < bar2.poc);

                  // Filtro Obrigatório: Não vender contra forte expansão compradora
                  if(bar1_red && bar1_below_poc2 && (!InpStrictTrendBlock || trend != TREND_BULLISH))
                  {
                     sell_triggered = true;
                     trig_type      = "FALHA DE CONTINUAÇÃO";
                     trig_detail    = "Compradores presos acima de " + DoubleToString(bar2.poc, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
                     // Stop Loss: Máxima absoluta do movimento recente
                     sl_calc        = MathMax(bar1.high, MathMax(bar2.high, bar3.high)) + buffer;
                  }
               }
            }

            // ===================================================================
            // EXECUÇÃO DE ORDENS
            // ===================================================================
            if(buy_triggered)
            {
               double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               double risk = ask - sl_calc;
               if(InpTakeProfitFixedTicks > 0.0)
                  tp_calc = ask + InpTakeProfitFixedTicks * tick_size;
               else
                  tp_calc = ask + (risk * InpRiskRewardRatio);

               if(g_trade.ExecuteBuy(sl_calc, tp_calc, bar1.poc, trig_type, trig_detail))
               {
                  // Módulo 3: Seta plotada apenas após confirmação do fechamento
                  g_renderer.DrawSignalArrow(bar1.time, bar1.low, true, trig_type + " - " + trig_detail);
               }
            }
            else if(sell_triggered)
            {
               double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               double risk = sl_calc - bid;
               if(InpTakeProfitFixedTicks > 0.0)
                  tp_calc = bid - InpTakeProfitFixedTicks * tick_size;
               else
                  tp_calc = bid - (risk * InpRiskRewardRatio);

               if(g_trade.ExecuteSell(sl_calc, tp_calc, bar1.poc, trig_type, trig_detail))
               {
                  // Módulo 3: Seta plotada apenas após confirmação do fechamento
                  g_renderer.DrawSignalArrow(bar1.time, bar1.high, false, trig_type + " - " + trig_detail);
               }
            }
         }
      }
   }

   // 3. ATUALIZAÇÃO DO PAINEL HUD (Módulo 4)
   ulong now_ms = GetTickCount64();
   if(now_ms - g_last_hud_update >= 250)
   {
      g_last_hud_update = now_ms;

      string dir; double lot, avg_p, sl, tp, pnl, pts;
      string pos_text = "SEM POSIÇÃO";
      if(g_trade.HasPosition(dir, lot, avg_p, sl, tp, pnl, pts))
         pos_text = dir;

      g_hud.Update(g_engine.GetTrend(),
                   g_engine.GetLastBasePrice(),
                   g_engine.HasActiveBase(),
                   g_engine.GetPendingSignal(),
                   pos_text, lot, avg_p, sl, tp, pnl, pts);
   }
}
//+------------------------------------------------------------------+
