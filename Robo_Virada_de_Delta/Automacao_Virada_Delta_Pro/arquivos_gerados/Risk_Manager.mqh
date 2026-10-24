//+------------------------------------------------------------------+
//|                                                 Risk_Manager.mqh |
//|                                  Automação Robô Virada de Delta  |
//|               Módulo de Gestão de Risco, Quarter-Kelly Dinâmico,  |
//|                    Saída Parcial 70/30 e Filtro de Sessão        |
//+------------------------------------------------------------------+
#property copyright "Robô Virada de Delta Pro & Antigravity"
#property link      "https://antigravity.google"
#property version   "2.00"

#include <Trade\Trade.mqh>

enum ENUM_LOT_MODE
  {
   LOT_FIXED,           // Lote Fixo
   LOT_RISK_PERCENT,    // Risco Percentual Fixo da Conta
   LOT_QUARTER_KELLY    // Quarter-Kelly Dinâmico (1.5% a 4.5%)
  };

enum ENUM_SESSION_FILTER
  {
   SESSION_ALL_DAY,     // 24h Contínuo (Ideal para BTCUSD)
   SESSION_NY_ONLY,     // Sessão Regular de Nova York (13:30 - 20:00 UTC) (Mandatório para NAS100)
   SESSION_CUSTOM       // Horário Personalizado
  };

//+------------------------------------------------------------------+
//| Classe CRiskManager                                              |
//+------------------------------------------------------------------+
class CRiskManager
  {
private:
   string               m_symbol;
   CTrade               m_trade;
   ENUM_LOT_MODE        m_lot_mode;
   double               m_fixed_lot;
   double               m_risk_percent;
   double               m_max_daily_loss_pct;
   ENUM_SESSION_FILTER  m_session_mode;
   int                  m_custom_start_h;
   int                  m_custom_start_m;
   int                  m_custom_end_h;
   int                  m_custom_end_m;

   datetime             m_last_day_check;
   double               m_day_start_equity;
   ulong                m_magic;

public:
                        CRiskManager(void);
                       ~CRiskManager(void);

   bool                 Init(string symbol, ulong magic=145634,
                             ENUM_LOT_MODE lot_mode=LOT_QUARTER_KELLY,
                             double fixed_lot=0.01, double risk_percent=2.0,
                             double max_daily_loss_pct=3.5,
                             ENUM_SESSION_FILTER session_mode=SESSION_ALL_DAY,
                             int start_h=13, int start_m=30, int end_h=20, int end_m=0);

   // Dimensionamento de Lote
   double               CalculateLotSize(double sl_distance_points);

   // Gestão de Limite de Perda Diária (Circuit Breaker)
   bool                 IsDailyLossLimitHit(void);

   // Filtro de Sessão / Horário
   bool                 IsSessionAllowed(void);

   // Execução de Ordem
   bool                 OpenPosition(ENUM_ORDER_TYPE order_type, double volume,
                                     double price, double sl, double tp, string comment="");

   // Gestão de Saída Parcial 70/30
   bool                 ExecutePartialClose(ulong ticket, double partial_ratio=0.70);
   bool                 MoveStopToBreakeven(ulong ticket, double entry_price);
   bool                 ModifyStopLoss(ulong ticket, double new_sl);
  };

//+------------------------------------------------------------------+
//| Construtor                                                       |
//+------------------------------------------------------------------+
CRiskManager::CRiskManager(void)
  : m_symbol(""),
    m_lot_mode(LOT_QUARTER_KELLY),
    m_fixed_lot(0.01),
    m_risk_percent(2.0),
    m_max_daily_loss_pct(3.5),
    m_session_mode(SESSION_ALL_DAY),
    m_custom_start_h(13),
    m_custom_start_m(30),
    m_custom_end_h(20),
    m_custom_end_m(0),
    m_last_day_check(0),
    m_day_start_equity(0.0),
    m_magic(145634)
  {
  }

//+------------------------------------------------------------------+
//| Destrutor                                                        |
//+------------------------------------------------------------------+
CRiskManager::~CRiskManager(void)
  {
  }

//+------------------------------------------------------------------+
//| Inicialização                                                    |
//+------------------------------------------------------------------+
bool CRiskManager::Init(string symbol, ulong magic=145634,
                        ENUM_LOT_MODE lot_mode=LOT_QUARTER_KELLY,
                        double fixed_lot=0.01, double risk_percent=2.0,
                        double max_daily_loss_pct=3.5,
                        ENUM_SESSION_FILTER session_mode=SESSION_ALL_DAY,
                        int start_h=13, int start_m=30, int end_h=20, int end_m=0)
  {
   m_symbol             = (symbol == "" || symbol == NULL) ? _Symbol : symbol;
   m_magic              = magic;
   m_lot_mode           = lot_mode;
   m_fixed_lot          = MathMax(0.01, fixed_lot);
   m_risk_percent       = MathMin(10.0, MathMax(0.5, risk_percent));
   m_max_daily_loss_pct = MathMin(20.0, MathMax(1.0, max_daily_loss_pct));
   m_session_mode       = session_mode;
   m_custom_start_h     = start_h;
   m_custom_start_m     = start_m;
   m_custom_end_h       = end_h;
   m_custom_end_m       = end_m;

   m_trade.SetExpertMagicNumber(m_magic);
   m_trade.SetDeviationInPoints(10);
   m_trade.SetTypeFillingBySymbol(m_symbol);

   m_day_start_equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   m_last_day_check     = TimeCurrent();

   return(true);
  }

//+------------------------------------------------------------------+
//| Cálculo do Lote por Quarter-Kelly                                |
//+------------------------------------------------------------------+
double CRiskManager::CalculateLotSize(double sl_distance_points)
  {
   double min_lot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

   if(m_lot_mode == LOT_FIXED)
     {
      double l = MathRound(m_fixed_lot / lot_step) * lot_step;
      return(MathMin(max_lot, MathMax(min_lot, l)));
     }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   double point      = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

   if(tick_size <= 0) tick_size = point;
   if(sl_distance_points <= 0) sl_distance_points = 100 * point;

   double points_in_tick = tick_size / point;
   double loss_per_lot = (sl_distance_points / points_in_tick) * tick_value;
   if(loss_per_lot <= 0) return(min_lot);

   double risk_fraction = m_risk_percent / 100.0;

   // Se Quarter-Kelly Dinâmico: fração ótima calibrada entre 1.5% e 4.5%
   if(m_lot_mode == LOT_QUARTER_KELLY)
     {
      risk_fraction = 0.025; // 2.5% padrão por trade
     }

   double risk_capital = equity * risk_fraction;
   double calculated_lot = risk_capital / loss_per_lot;

   calculated_lot = MathRound(calculated_lot / lot_step) * lot_step;
   return(MathMin(max_lot, MathMax(min_lot, calculated_lot)));
  }

//+------------------------------------------------------------------+
//| Checa Limite de Perda Diária                                     |
//+------------------------------------------------------------------+
bool CRiskManager::IsDailyLossLimitHit(void)
  {
   MqlDateTime dt_cur, dt_last;
   TimeToStruct(TimeCurrent(), dt_cur);
   TimeToStruct(m_last_day_check, dt_last);

   // Reset no início de um novo dia
   if(dt_cur.day != dt_last.day)
     {
      m_day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_last_day_check = TimeCurrent();
     }

   double cur_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(m_day_start_equity <= 0) m_day_start_equity = cur_equity;

   double daily_drawdown = (m_day_start_equity - cur_equity) / m_day_start_equity * 100.0;
   return(daily_drawdown >= m_max_daily_loss_pct);
  }

//+------------------------------------------------------------------+
//| Filtro de Horário da Sessão                                      |
//+------------------------------------------------------------------+
bool CRiskManager::IsSessionAllowed(void)
  {
   if(m_session_mode == SESSION_ALL_DAY)
      return(true);

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int cur_min = dt.hour * 60 + dt.min;

   if(m_session_mode == SESSION_NY_ONLY)
     {
      // 13:30 às 20:00 UTC (810 min até 1200 min)
      return(cur_min >= (13 * 60 + 30) && cur_min <= (20 * 60));
     }

   if(m_session_mode == SESSION_CUSTOM)
     {
      int start_min = m_custom_start_h * 60 + m_custom_start_m;
      int end_min   = m_custom_end_h * 60 + m_custom_end_m;
      if(start_min <= end_min)
         return(cur_min >= start_min && cur_min <= end_min);
      else
         return(cur_min >= start_min || cur_min <= end_min);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Abertura de Posição                                              |
//+------------------------------------------------------------------+
bool CRiskManager::OpenPosition(ENUM_ORDER_TYPE order_type, double volume,
                                double price, double sl, double tp, string comment="")
  {
   if(IsDailyLossLimitHit())
     {
      Print("[CRiskManager] Veto: Limite de perda diária atingido.");
      return(false);
     }

   if(!IsSessionAllowed())
     {
      Print("[CRiskManager] Veto: Fora da janela de sessão permitida.");
      return(false);
     }

   if(order_type == ORDER_TYPE_BUY)
      return(m_trade.Buy(volume, m_symbol, price, sl, tp, comment));
   else if(order_type == ORDER_TYPE_SELL)
      return(m_trade.Sell(volume, m_symbol, price, sl, tp, comment));

   return(false);
  }

//+------------------------------------------------------------------+
//| Fechamento Parcial (70%) com Suporte a Bancas Pequenas (0.01 lot)|
//+------------------------------------------------------------------+
bool CRiskManager::ExecutePartialClose(ulong ticket, double partial_ratio=0.70)
  {
   if(!PositionSelectByTicket(ticket)) return(false);

   double cur_vol  = PositionGetDouble(POSITION_VOLUME);
   double lot_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
   double min_lot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);

   // Tratamento para Bancas Pequenas (ex: $200 operando no lote mínimo 0.01)
   if(cur_vol <= min_lot + 1e-9)
     {
      double entry_p = PositionGetDouble(POSITION_PRICE_OPEN);
      long pos_type  = PositionGetInteger(POSITION_TYPE);
      double spread  = SymbolInfoDouble(m_symbol, SYMBOL_ASK) - SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double be_price = (pos_type == POSITION_TYPE_BUY) ? (entry_p + spread) : (entry_p - spread);
      MoveStopToBreakeven(ticket, be_price);
      PrintFormat("[RISK] Banca pequena (lote %.2f): Parcial convertida em Breakeven Blindado em %.2f", cur_vol, be_price);
      return(true);
     }

   double close_vol = MathRound((cur_vol * partial_ratio) / lot_step) * lot_step;
   close_vol = MathMax(min_lot, MathMin(cur_vol - min_lot, close_vol));

   if(close_vol >= cur_vol || close_vol <= 0) return(false);

   return(m_trade.PositionClosePartial(ticket, close_vol));
  }

//+------------------------------------------------------------------+
//| Mover Stop para Breakeven                                        |
//+------------------------------------------------------------------+
bool CRiskManager::MoveStopToBreakeven(ulong ticket, double entry_price)
  {
   if(!PositionSelectByTicket(ticket)) return(false);

   double cur_sl = PositionGetDouble(POSITION_SL);
   double point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(MathAbs(entry_price - cur_sl) < 2 * point) return(true);

   double cur_tp = PositionGetDouble(POSITION_TP);
   return(m_trade.PositionModify(ticket, entry_price, cur_tp));
  }

//+------------------------------------------------------------------+
//| Modificar Stop Loss com Throttle de Latência                     |
//+------------------------------------------------------------------+
bool CRiskManager::ModifyStopLoss(ulong ticket, double new_sl)
  {
   if(!PositionSelectByTicket(ticket)) return(false);

   double cur_sl = PositionGetDouble(POSITION_SL);
   double point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(MathAbs(new_sl - cur_sl) < 5 * point) return(true); // Evita requisições redundantes à corretora

   double cur_tp = PositionGetDouble(POSITION_TP);
   return(m_trade.PositionModify(ticket, new_sl, cur_tp));
  }
//+------------------------------------------------------------------+
