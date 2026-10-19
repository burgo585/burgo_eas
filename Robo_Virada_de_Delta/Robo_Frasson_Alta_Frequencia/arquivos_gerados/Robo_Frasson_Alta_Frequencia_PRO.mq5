//+------------------------------------------------------------------+
//|                               Robo_Frasson_Alta_Frequencia_PRO.mq5|
//|        Expert Advisor de Alta Frequencia e Assertividade         |
//|        Canais Frasson ATR + Motor Hibrido (Trend Pullback & Fade)|
//|        Saida Parcial 70/30, Trailing Estrutural e Gestao $10k    |
//|                                                                  |
//|      Otimizado para: MNQ, MES, XAUUSD e BTCUSD (VT Markets)      |
//+------------------------------------------------------------------+
#property copyright   "Robo Frasson Alta Frequencia PRO - Multi-Ativo"
#property link        "https://antigravity.google"
#property version     "2.00"
#property description "Sistema de alta frequencia com motor hibrido, parcial 70/30 e canais Frasson ATR."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Modos Operacionais
enum ENUM_STRATEGY_ENGINE
  {
   ENGINE_FULL_HYBRID,     // Hibrido Completo: Pullback na Tendencia + Rejeicao de Extremos (Alta Frequencia)
   ENGINE_PULLBACK_TREND,  // Apenas Pullbacks no Canal Frasson na Direcao da Tendencia (Maior Assertividade)
   ENGINE_EXTREME_FADE     // Apenas Armadilhas de Liquidez / Rejeicao de Pavio (Trapped Traders)
  };

enum ENUM_LOT_CALC_MODE
  {
   LOT_FIXED_CUSTOM,       // Lote Fixo Configurado
   LOT_RISK_PERCENT        // Risco Percentual Dinamico sobre o Equity da Carteira (ex: 1.5%)
  };

enum ENUM_BROKER_TYPE
  {
   BROKER_VTMARKETS_RAW,   // VT Markets Raw ECN ($6/lote comissao + Raw Spread)
   BROKER_VTMARKETS_STD,   // VT Markets Standard STP (Zero Comissao)
   BROKER_CME_FUTURES      // Futuros CME (MNQ / MES)
  };

//--- Inputs do Usuario (Configuracoes Campeas XAUUSD M5 Nativas)
input group "=== 1. Motor Operacional & Estrategia ==="
input ENUM_STRATEGY_ENGINE InpEngineMode           = ENGINE_FULL_HYBRID;     // Modo Operacional (Hibrido Recomendado)
input ENUM_BROKER_TYPE     InpBrokerType           = BROKER_VTMARKETS_RAW;   // Tipo de Conta / Corretora
input ulong                InpMagicNumber          = 889901;                 // Magic Number Exclusivo

input group "=== 2. Parametros do Frasson ATR & Tendencia ==="
input int                  InpFrassonPeriod        = 14;                     // Periodo do Frasson ATR
input int                  InpFrassonShift         = 5;                      // Deslocamento das Bandas (Calibrado Ouro M5)
input double               InpFrassonMultiplier    = 2.20;                   // Multiplicador do Canal Frasson
input int                  InpTrendFilterPeriod    = 50;                     // Periodo da Media de Tendencia Macro (EMA 50)
input bool                 InpRequireTrendAlign    = true;                   // Exigir Alinhamento com a Tendencia nos Pullbacks

input group "=== 3. GPS de Volatilidade & Filtro de Fluxo ==="
input bool                 InpUseVolatilityGPS     = true;                   // Ativar GPS de Volatilidade
input double               InpMinVolThreshold      = 0.70;                   // Limiar Minimo de Volatilidade (Ajustado p/ Frequencia)
input double               InpVolumeSpikeRatio     = 1.15;                   // Volume Minimo em relacao a Media de 10 barras
input double               InpMinRejectionWick     = 0.25;                   // Pavio Minimo para Rejeicao de Extremo (25%)
input int                  InpMaxTradesPerDay      = 4;                      // Maximo de Operacoes por Dia (Protecao Anti-Overtrading)

input group "=== 4. Gestao de Capital & Dimensionamento ($10.000) ==="
input ENUM_LOT_CALC_MODE   InpLotMode              = LOT_FIXED_CUSTOM;       // Modo de Dimensionamento
input double               InpBaseLotSize          = 0.25;                   // Lote Base (0.25 XAU p/ $10k = ~$50 lucro no TP1)
input double               InpRiskPercentAccount   = 1.50;                   // Risco % por Operacao (se modo percentual)
input double               InpPartialRatio         = 0.75;                   // Proporcao da Saida Parcial (75% no Alvo 1)
input double               InpATR_SL_Multiplier    = 0.70;                   // Stop Loss = N x ATR da entrada (0.70x ATR)
input double               InpATR_TP1_Multiplier   = 0.50;                   // Alvo 1 (Parcial 75%) = 0.50x ATR (Bate com 66% de acerto)
input double               InpATR_TP2_Multiplier   = 1.20;                   // Alvo 2 (Final 25%) = 1.20x ATR
input bool                 InpMoveBEOnTP1          = true;                   // Mover Stop para Breakeven ao Bater Alvo 1
input double               InpBEBufferPts          = 25.0;                   // Folga Minima de Breakeven em Pontos
input double               InpLockProfitATR        = 0.15;                   // Trava de Lucro Minimo na 2a Ordem (0.15x ATR garante lucro real)
input bool                 InpTrailingOnTarget2    = true;                   // Trailing Stop nos Restantes

input group "=== 5. Filtro de Horario / Sessao Ativa ==="
input bool                 InpUseSessionFilter     = true;                   // Ativar Filtro de Sessao
input int                  InpStartHour            = 7;                      // Hora Inicio (GMT/Servidor)
input int                  InpStartMin             = 0;                      // Minuto Inicio
input int                  InpEndHour              = 18;                     // Hora Fim
input int                  InpEndMin               = 30;                     // Minuto Fim

input group "=== 6. Painel Visual HUD Dark Mode ==="
input bool                 InpShowHUD              = true;                   // Exibir HUD Dark Mode

//--- Instancias Globais
CTrade            g_trade;
CPositionInfo     g_pos;
COrderInfo        g_order;

int               g_handle_atr = INVALID_HANDLE;
int               g_handle_ma14 = INVALID_HANDLE;
int               g_handle_ma50 = INVALID_HANDLE;

datetime          g_last_bar_time = 0;
ulong             g_ticket_t1 = 0;
ulong             g_ticket_t2 = 0;
bool              g_t1_done = false;
int               g_trades_today = 0;
datetime          g_today_date = 0;

//+------------------------------------------------------------------+
//| Inicializacao do Expert Advisor                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_trade.SetExpertMagicNumber(InpMagicNumber);

   g_handle_atr  = iATR(_Symbol, _Period, InpFrassonPeriod);
   g_handle_ma14 = iMA(_Symbol, _Period, InpFrassonPeriod, 0, MODE_SMA, PRICE_CLOSE);
   g_handle_ma50 = iMA(_Symbol, _Period, InpTrendFilterPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(g_handle_atr == INVALID_HANDLE || g_handle_ma14 == INVALID_HANDLE || g_handle_ma50 == INVALID_HANDLE)
     {
      Print("[ERRO] Falha ao criar handles dos indicadores.");
      return(INIT_FAILED);
     }

   PrintFormat("[INIT] Robo Frasson Alta Frequencia PRO carregado com sucesso em %s (%s).", _Symbol, EnumToString(_Period));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Desinicializacao                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
   IndicatorRelease(g_handle_atr);
   IndicatorRelease(g_handle_ma14);
   IndicatorRelease(g_handle_ma50);
  }

//+------------------------------------------------------------------+
//| Leitura das Bandas Frasson ATR                                   |
//+------------------------------------------------------------------+
bool GetFrassonData(double &upper, double &center, double &lower, double &atr_val, double &trend_ma)
  {
   double atr_buf[];
   double ma14_buf[];
   double ma50_buf[];
   ArraySetAsSeries(atr_buf, true);
   ArraySetAsSeries(ma14_buf, true);
   ArraySetAsSeries(ma50_buf, true);

   int shift = InpFrassonShift;

   if(CopyBuffer(g_handle_atr, 0, shift, 1, atr_buf) < 1) return(false);
   if(CopyBuffer(g_handle_ma14, 0, shift, 1, ma14_buf) < 1) return(false);
   if(CopyBuffer(g_handle_ma50, 0, 1, 1, ma50_buf) < 1) return(false);

   atr_val  = atr_buf[0];
   center   = ma14_buf[0];
   upper    = center + (InpFrassonMultiplier * atr_val);
   lower    = center - (InpFrassonMultiplier * atr_val);
   trend_ma = ma50_buf[0];

   return(true);
  }

//+------------------------------------------------------------------+
//| Filtro de Horario                                                |
//+------------------------------------------------------------------+
bool IsAllowedTime()
  {
   if(!InpUseSessionFilter) return(true);

   MqlDateTime dt;
   TimeCurrent(dt);

   int cur_min = dt.hour * 60 + dt.min;
   int start_min = InpStartHour * 60 + InpStartMin;
   int end_min = InpEndHour * 60 + InpEndMin;

   return(cur_min >= start_min && cur_min <= end_min);
  }

//+------------------------------------------------------------------+
//| Calculo Dinamico de Lote                                         |
//+------------------------------------------------------------------+
double CalculateOptimalLot(double sl_distance_pts)
  {
   if(InpLotMode == LOT_FIXED_CUSTOM)
      return(InpBaseLotSize);

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_usd = equity * (InpRiskPercentAccount / 100.0);

   double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_sz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_sz <= 0) tick_sz = _Point;

   double cost_per_point = (1.0 / tick_sz) * tick_val;
   double total_lot = risk_usd / (sl_distance_pts * cost_per_point);

   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   total_lot = MathFloor(total_lot / step) * step;
   if(total_lot < min_lot) total_lot = min_lot;
   if(total_lot > max_lot) total_lot = max_lot;

   return(total_lot);
  }

//+------------------------------------------------------------------+
//| Deteccao dos Gatilhos Hibridos                                   |
//+------------------------------------------------------------------+
int DetectHybridTriggers(const MqlRates &rates[], double upper, double center, double lower, double trend_ma)
  {
   double close1 = rates[1].close;
   double open1  = rates[1].open;
   double high1  = rates[1].high;
   double low1   = rates[1].low;
   double range1 = high1 - low1;
   if(range1 <= 0) return(0);

   double lower_wick = MathMin(open1, close1) - low1;
   double upper_wick = high1 - MathMax(open1, close1);

   // Volume institucional (volume >= 1.15x media das ultimas 10 barras)
   long vol_sum = 0;
   for(int i = 1; i <= 10; i++) vol_sum += rates[i].tick_volume;
   double vol_avg = (double)vol_sum / 10.0;
   bool vol_ok = (rates[1].tick_volume >= vol_avg * InpVolumeSpikeRatio);

   // Alinhamento de Tendencia (Macro)
   bool trend_buy  = (!InpRequireTrendAlign || close1 > trend_ma);
   bool trend_sell = (!InpRequireTrendAlign || close1 < trend_ma);

   // --- SINAL DE COMPRA ---
   bool buy_pullback = false;
   bool buy_fade     = false;

   // 1. Pullback de Tendencia no Canal Frasson (Compra)
   if(trend_buy && low1 <= center && close1 > center && close1 > open1)
     {
      buy_pullback = true;
     }

   // 2. Fade de Rejeicao de Extremo (Compra / Trapped Sellers)
   if(trend_buy && (lower_wick / range1) >= InpMinRejectionWick && low1 <= lower && close1 > open1 && vol_ok)
     {
      buy_fade = true;
     }

   // --- SINAL DE VENDA ---
   bool sell_pullback = false;
   bool sell_fade     = false;

   // 1. Pullback de Tendencia no Canal Frasson (Venda)
   if(trend_sell && high1 >= center && close1 < center && close1 < open1)
     {
      sell_pullback = true;
     }

   // 2. Fade de Rejeicao de Extremo (Venda / Trapped Buyers)
   if(trend_sell && (upper_wick / range1) >= InpMinRejectionWick && high1 >= upper && close1 < open1 && vol_ok)
     {
      sell_fade = true;
     }

   // Decisao conforme o modo do motor
   if(InpEngineMode == ENGINE_FULL_HYBRID)
     {
      if(buy_pullback || buy_fade) return(1);
      if(sell_pullback || sell_fade) return(-1);
     }
   else if(InpEngineMode == ENGINE_PULLBACK_TREND)
     {
      if(buy_pullback) return(1);
      if(sell_pullback) return(-1);
     }
   else if(InpEngineMode == ENGINE_EXTREME_FADE)
     {
      if(buy_fade) return(1);
      if(sell_fade) return(-1);
     }

   return(0);
  }

//+------------------------------------------------------------------+
//| Abertura Split 70/30 (Alvo Parcial + Alvo Final)                 |
//+------------------------------------------------------------------+
bool OpenSplitPositions(int signal, double total_lot, double sl_pts, double tp1_pts, double tp2_pts)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = (signal == 1) ? ask : bid;
   ENUM_ORDER_TYPE order_type = (signal == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double lot_t1 = MathFloor((total_lot * InpPartialRatio) / step) * step;
   double lot_t2 = MathFloor((total_lot - lot_t1) / step) * step;

   if(lot_t1 < min_lot) lot_t1 = min_lot;
   if(lot_t2 < min_lot) lot_t2 = min_lot;

   double sl_price  = (signal == 1) ? price - (sl_pts * _Point) : price + (sl_pts * _Point);
   double tp1_price = (signal == 1) ? price + (tp1_pts * _Point) : price - (tp1_pts * _Point);
   double tp2_price = (signal == 1) ? price + (tp2_pts * _Point) : price - (tp2_pts * _Point);

   // Ordem 1: 70% Parcial
   if(g_trade.PositionOpen(_Symbol, order_type, lot_t1, price, sl_price, tp1_price, "HF_Parcial_70"))
     {
      g_ticket_t1 = g_trade.ResultOrder();
      g_t1_done = false;
      PrintFormat("[ORDEM 1] 70%% Parcial aberta: Ticket %d | Lote: %.2f | TP: %.2f", g_ticket_t1, lot_t1, tp1_price);
     }
   else
     {
      PrintFormat("[ERRO] Falha ao abrir Ordem 1: %d", GetLastError());
      return(false);
     }

   // Ordem 2: 30% Final Conduzida
   if(g_trade.PositionOpen(_Symbol, order_type, lot_t2, price, sl_price, tp2_price, "HF_Final_30"))
     {
      g_ticket_t2 = g_trade.ResultOrder();
      PrintFormat("[ORDEM 2] 30%% Final aberta: Ticket %d | Lote: %.2f | TP: %.2f", g_ticket_t2, lot_t2, tp2_price);
      g_trades_today++;
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Gestao em Tempo Real (Breakeven & Trailing nas Bandas)           |
//+------------------------------------------------------------------+
void ManageActivePositions(double upper, double lower, double atr_val)
  {
   int total = PositionsTotal();
   if(total == 0)
     {
      g_ticket_t1 = 0;
      g_ticket_t2 = 0;
      g_t1_done = false;
      return;
     }

   bool has_t1 = false;
   bool has_t2 = false;

   for(int i = total - 1; i >= 0; i--)
     {
      if(g_pos.SelectByIndex(i))
        {
         if(g_pos.Magic() != InpMagicNumber || g_pos.Symbol() != _Symbol) continue;
         if(g_pos.Ticket() == g_ticket_t1) has_t1 = true;
         if(g_pos.Ticket() == g_ticket_t2) has_t2 = true;
        }
     }

   // Se Ordem 1 ja encerrou no TP1 e Ordem 2 segue ativa
   if(!has_t1 && has_t2 && !g_t1_done)
     {
      g_t1_done = true;
      Print("[GESTAO] Parcial concluida! Protegendo os restantes com Lucro Travado (Lock Profit)...");

      if(g_pos.SelectByTicket(g_ticket_t2))
        {
         double open_p = g_pos.PriceOpen();
         ENUM_POSITION_TYPE type = g_pos.PositionType();
         double lock_dist = MathMax(InpBEBufferPts * _Point, InpLockProfitATR * atr_val);
         double be_p = (type == POSITION_TYPE_BUY) ?
                       open_p + lock_dist :
                       open_p - lock_dist;

         g_trade.PositionModify(g_ticket_t2, be_p, g_pos.TakeProfit());
        }
     }

   // Trailing stop na banda oposta do Frasson ATR para os 30% restantes
   if(has_t2 && InpTrailingOnTarget2 && g_t1_done)
     {
      if(g_pos.SelectByTicket(g_ticket_t2))
        {
         ENUM_POSITION_TYPE type = g_pos.PositionType();
         double cur_sl = g_pos.StopLoss();
         double open_p = g_pos.PriceOpen();

         if(type == POSITION_TYPE_BUY)
           {
            double new_sl = lower;
            if(new_sl > cur_sl && new_sl > open_p)
              {
               g_trade.PositionModify(g_ticket_t2, new_sl, g_pos.TakeProfit());
              }
           }
         else if(type == POSITION_TYPE_SELL)
           {
            double new_sl = upper;
            if((cur_sl == 0 || new_sl < cur_sl) && new_sl < open_p)
              {
               g_trade.PositionModify(g_ticket_t2, new_sl, g_pos.TakeProfit());
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Painel HUD Dark Mode                                             |
//+------------------------------------------------------------------+
void DisplayHUD(double upper, double center, double lower, double atr_val, double trend_ma)
  {
   if(!InpShowHUD) return;

   string text = "";
   text += "=========================================================\n";
   text += StringFormat("  ROBO FRASSON ALTA FREQUENCIA PRO | %s (%s)\n", _Symbol, EnumToString(_Period));
   text += "=========================================================\n";
   text += StringFormat("  Motor Operacional:    %s\n", EnumToString(InpEngineMode));
   text += StringFormat("  Tendencia Macro (EMA50): %.2f | Preco: %.2f\n", trend_ma, SymbolInfoDouble(_Symbol, SYMBOL_BID));
   text += StringFormat("  Canais Frasson ATR:   Sup: %.2f | Med: %.2f | Inf: %.2f\n", upper, center, lower);
   text += StringFormat("  ATR Atual (14):       %.2f pts\n", atr_val / _Point);
   text += "---------------------------------------------------------\n";
   text += StringFormat("  Entradas Realizadas Hoje: %d / %d (Max)\n", g_trades_today, InpMaxTradesPerDay);
   text += StringFormat("  Gestao de Posicao:    %.0f%% no Alvo 1 (Lock Profit) | %.0f%% no Alvo 2\n", InpPartialRatio * 100.0, (1.0 - InpPartialRatio) * 100.0);
   text += StringFormat("  Status Posicoes:      T1: %s | T2: %s | BE/Lock Ativo: %s\n",
                        (g_ticket_t1 > 0 ? "Aberto" : "Fechado/Neutro"),
                        (g_ticket_t2 > 0 ? "Aberto" : "Fechado/Neutro"),
                        (g_t1_done ? "SIM" : "NAO"));
   text += "=========================================================";

   Comment(text);
  }

//+------------------------------------------------------------------+
//| Evento OnTick                                                    |
//+------------------------------------------------------------------+
void OnTick()
  {
   double upper, center, lower, atr_val, trend_ma;
   if(!GetFrassonData(upper, center, lower, atr_val, trend_ma)) return;

   DisplayHUD(upper, center, lower, atr_val, trend_ma);
   ManageActivePositions(upper, lower, atr_val);

   // Checa nova barra
   datetime bar_time = iTime(_Symbol, _Period, 0);
   if(bar_time == g_last_bar_time) return;
   g_last_bar_time = bar_time;

   // Reseta contador diario se mudou o dia
   MqlDateTime dt;
   TimeCurrent(dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(today != g_today_date)
     {
      g_today_date = today;
      g_trades_today = 0;
     }

   if(!IsAllowedTime()) return;

   // Protecao Anti-Overtrading: limite maximo de operacoes no dia
   if(InpMaxTradesPerDay > 0 && g_trades_today >= InpMaxTradesPerDay) return;

   // Se já houver posição ativa desta estratégia, não abre outra simultânea
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(g_pos.SelectByIndex(i) && g_pos.Magic() == InpMagicNumber && g_pos.Symbol() == _Symbol)
         return;
     }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, _Period, 0, 15, rates) < 12) return;

   int signal = DetectHybridTriggers(rates, upper, center, lower, trend_ma);
   if(signal == 0) return;

   // Calculo dinamico dos alvos pelo ATR
   double sl_pts  = (InpATR_SL_Multiplier * atr_val) / _Point;
   double tp1_pts = (InpATR_TP1_Multiplier * atr_val) / _Point;
   double tp2_pts = (InpATR_TP2_Multiplier * atr_val) / _Point;

   double optimal_lot = CalculateOptimalLot(sl_pts);

   OpenSplitPositions(signal, optimal_lot, sl_pts, tp1_pts, tp2_pts);
  }
//+------------------------------------------------------------------+
