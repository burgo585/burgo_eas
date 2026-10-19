//+------------------------------------------------------------------+
//|                                             Burgo Scalpe Pro.mq5 |
//|                                    Copyright 2024, DevMaster Pro |
//|      V39.2 - SISTEMA COM CONTROLE ATIVO DE DRAWDOWN PARA XAUUSD  |
//+------------------------------------------------------------------+
#property copyright "DevMaster Pro"
#property version   "39.20"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// --- INPUTS ---
input group "==== MOTOR DE GIRO ===="
input double  InpInitialLot       = 0.02;      // Lote inicial do giro
input double  InpTargetSideUSD    = 3.00;      // Alvo de cada giro p/ limpeza ($)
input double  InpTargetGlobalUSD  = 30.00;     // Alvo para reset total da cesta ($)
input int     InpMagicNumber      = 888123;    // Magic Number do Robô

input group "==== CONTROLE ATIVO DE DRAWDOWN (CIRCUIT BREAKER) ===="
input bool    InpUseMaxDD         = true;      // Ativar Trava Protetora de Drawdown Máximo
input double  InpMaxDrawdownPct   = 15.0;      // Drawdown Máximo Tolerado da Conta (%)
input double  InpMaxLossUSD       = 1000.00;   // Prejuízo Flutuante Máximo Permitido ($)

input group "==== FILTRO DE TENDÊNCIA MACRO (ANTI-CONTRA-TENDÊNCIA) ===="
input bool            InpUseTrendFilter = true;      // Ativar Filtro de Tendência por Média Móvel
input ENUM_TIMEFRAMES InpTrendTF        = PERIOD_H1; // Timeframe da Média (H1 recomendado)
input int             InpTrendPeriod    = 200;       // Período da Média (EMA 200)

input group "==== LIMITE DE SEGURANÇA E GRADE ===="
input int     InpBaseDistance     = 1200;      // Distância base em pontos (1200 pts = $12 no Ouro)
input double  InpLotMultiplier    = 1.25;      // Multiplicador de lote suave (1.25x)
input int     InpMaxMartingale    = 6;         // Limite de aumentos de lote
input int     InpMaxTotalOrders   = 8;         // Máximo absoluto de ordens por lado (teto de risco)
input double  InpMaxAllowedLot    = 0.50;      // Lote máximo absoluto por ordem
input bool    InpUseProgressiveGrid = true;    // Espaçamento progressivo (afasta ordens na expansão)
input double  InpGridProgressionPct = 20.0;    // % de acréscimo de distância por nível (20%)

input group "==== FILTROS DINÂMICOS (ATR) ===="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_CURRENT; // Timeframe do Gráfico / ATR
input bool    InpUseATR           = true;      // Usar ATR para Distância Dinâmica
input int     InpATRPeriod        = 14;        // Período do ATR
input double  InpATRMultiplier    = 1.5;       // Multiplicador do ATR

input group "==== TRAILING STOP DE LUCRO ===="
input bool    InpUseTrailingStop  = true;      // Ativar Trailing Stop
input double  InpTrailingStartUSD = 3.00;      // Iniciar Trailing com este lucro ($)
input double  InpTrailingDropPct  = 12.0;      // Porcentagem de queda para fechar (12%)

input group "==== HORÁRIOS DE OPERAÇÃO ===="
input string  InpStartTime        = "01:00";   // Horário de Início (HH:MM)
input string  InpEndTime          = "23:00";   // Horário de Término (HH:MM)

// Globais
CTrade        trade;
CPositionInfo posInfo;
int           PM = 1;
string        PREFIX = "BSP_";
int           atrHandle = INVALID_HANDLE;
int           trendHandle = INVALID_HANDLE;

bool          EA_Active = true;
bool          Panel_Minimized = false;
bool          EmergencyStopTriggered = false;

// Cores do Painel Moderno
color cor_bg_main     = C'15,23,42';    // Slate 900
color cor_bg_panel    = C'30,41,59';    // Slate 800
color cor_border      = C'51,65,85';    // Slate 700
color cor_text_main   = C'241,245,249'; // Slate 50
color cor_text_muted  = C'148,163,184'; // Slate 400
color cor_accent      = C'56,189,248';  // Sky 400
color cor_buy         = C'34,197,94';   // Emerald 500
color cor_sell        = C'239,68,68';   // Red 500
color cor_warning     = C'245,158,11';  // Amber 500

// Estatísticas
double total_profit = 0;
double daily_profit = 0;
int total_trades = 0;
int win_trades = 0;
int loss_trades = 0;
datetime last_stats_calc = 0;

// Variáveis de Trailing
double max_buy_profit = 0;
double max_sell_profit = 0;
double max_global_profit = 0;

// Declarações antecipadas
void CriarPainelModerno();
void AtualizarVisibilidadePainel();
void AtualizarValoresPainel(double floating, double bal, double eq, int tBuy, int tSell, double pBuy, double pSell);
void CreateRect(string name, int x, int y, int w, int h, color bg, color border);
void DrawLabel(string name, string text, int x, int y, color clr, int size, string font);
void CreateButton(string name, string text, int x, int y, int w, int h, color bg, color fg);
void FecharTudo();
void FecharLado(ENUM_POSITION_TYPE type);
void FecharLucrativas();
bool TentarReciclar(double lucroDisponivel, ENUM_POSITION_TYPE ladoPerdedor);
double GetDynamicDistance();
double NormalizeVolume(double lot);
bool IsTradingTime();
void CalculateStats();
void ProcessTrailingStop(double buyProfit, double sellProfit, double totalFloating);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50);
   
   // Detecção de preenchimento automática (Essencial para XAUUSD / ECN)
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) != 0) {
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   } else if((filling & SYMBOL_FILLING_FOK) != 0) {
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   } else {
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   PM = (digits == 3 || digits == 5) ? 10 : 1;
   
   // Indicador ATR
   if(InpUseATR) {
      ENUM_TIMEFRAMES tf = (InpTimeframe == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpTimeframe;
      atrHandle = iATR(_Symbol, tf, InpATRPeriod);
   }
   
   // Indicador de Tendência EMA 200
   if(InpUseTrendFilter) {
      trendHandle = iMA(_Symbol, InpTrendTF, InpTrendPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(trendHandle == INVALID_HANDLE) {
         Print("Aviso: Falha ao carregar indicador de tendência. Filtro desativado.");
      }
   }
   
   EmergencyStopTriggered = false;
   CriarPainelModerno();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) { 
   ObjectsDeleteAll(0, PREFIX); 
   if(InpUseATR && atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(InpUseTrendFilter && trendHandle != INVALID_HANDLE) IndicatorRelease(trendHandle);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Normalização rigorosa de volume de lote                          |
//+------------------------------------------------------------------+
double NormalizeVolume(double lot) {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   if(minLot <= 0) minLot = 0.01;
   if(maxLot <= 0) maxLot = 100.0;
   
   if(lot > InpMaxAllowedLot) lot = InpMaxAllowedLot;
   
   double normalized = MathFloor(lot / step) * step;
   if(normalized < minLot) normalized = minLot;
   if(normalized > maxLot) normalized = maxLot;
   
   int dec = 0;
   if(step == 0.01) dec = 2;
   else if(step == 0.1) dec = 1;
   
   return NormalizeDouble(normalized, dec);
}

//+------------------------------------------------------------------+
//| Verificação do horário de operação                               |
//+------------------------------------------------------------------+
bool IsTradingTime() {
   datetime time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(time, dt);
   
   int current_mins = dt.hour * 60 + dt.min;
   
   string start_arr[];
   if(StringSplit(InpStartTime, ':', start_arr) != 2) return true;
   int start_mins = (int)StringToInteger(start_arr[0]) * 60 + (int)StringToInteger(start_arr[1]);
   
   string end_arr[];
   if(StringSplit(InpEndTime, ':', end_arr) != 2) return true;
   int end_mins = (int)StringToInteger(end_arr[0]) * 60 + (int)StringToInteger(end_arr[1]);
   
   if (start_mins <= end_mins) {
      return (current_mins >= start_mins && current_mins <= end_mins);
   } else {
      return (current_mins >= start_mins || current_mins <= end_mins);
   }
}

//+------------------------------------------------------------------+
//| Distância Dinâmica ATR segura contra 'Array out of range'        |
//+------------------------------------------------------------------+
double GetDynamicDistance() {
   double baseDist = InpBaseDistance * PM * _Point;
   if(!InpUseATR || atrHandle == INVALID_HANDLE) return baseDist;
   
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0) return baseDist;
   
   double dist = atr[0] * InpATRMultiplier;
   
   double minDist = (InpBaseDistance / 2.0) * PM * _Point;
   if(dist < minDist) dist = minDist;
   
   return dist;
}

//+------------------------------------------------------------------+
//| Cálculo de estatísticas com limitação de frequência              |
//+------------------------------------------------------------------+
void CalculateStats() {
   datetime now = TimeCurrent();
   if(now - last_stats_calc < 1) return;
   last_stats_calc = now;

   total_profit = 0;
   daily_profit = 0;
   total_trades = 0;
   win_trades = 0;
   loss_trades = 0;
   
   HistorySelect(0, now);
   int deals = HistoryDealsTotal();
   datetime today = now - (now % 86400);
   
   for(int i=0; i<deals; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber &&
         HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol) {
         
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + 
                            HistoryDealGetDouble(ticket, DEAL_COMMISSION) + 
                            HistoryDealGetDouble(ticket, DEAL_SWAP);
            total_profit += profit;
            total_trades++;
            if(profit > 0) win_trades++;
            else if(profit < 0) loss_trades++;
            
            datetime deal_time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
            if(deal_time >= today) {
               daily_profit += profit;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trailing Stop em Dólar com proteção no piso de lucro             |
//+------------------------------------------------------------------+
void ProcessTrailingStop(double buyProfit, double sellProfit, double totalFloating) {
   if(!InpUseTrailingStop) return;
   
   double triggerSide = (InpTrailingStartUSD > 0) ? InpTrailingStartUSD : InpTargetSideUSD;

   // 1. Trailing Global
   if(totalFloating >= InpTargetGlobalUSD) {
      if(totalFloating > max_global_profit) max_global_profit = totalFloating;
      
      double dropAmount = max_global_profit * (InpTrailingDropPct / 100.0);
      if((max_global_profit - totalFloating) >= dropAmount) {
         FecharTudo();
         max_global_profit = 0;
         Print("Trailing Stop Global Acionado!");
         return;
      }
   } else if(max_global_profit > 0) {
      FecharTudo();
      max_global_profit = 0;
      return;
   }

   // 2. Trailing Compra
   if(buyProfit >= triggerSide) {
      if(buyProfit > max_buy_profit) max_buy_profit = buyProfit;
      
      double dropAmount = max_buy_profit * (InpTrailingDropPct / 100.0);
      if((max_buy_profit - buyProfit) >= dropAmount) {
         FecharLado(POSITION_TYPE_BUY);
         max_buy_profit = 0;
         Print("Trailing Stop Acionado: COMPRA");
      }
   } else if(max_buy_profit > 0) {
      FecharLado(POSITION_TYPE_BUY);
      max_buy_profit = 0;
   }
   
   // 3. Trailing Venda
   if(sellProfit >= triggerSide) {
      if(sellProfit > max_sell_profit) max_sell_profit = sellProfit;
      
      double dropAmount = max_sell_profit * (InpTrailingDropPct / 100.0);
      if((max_sell_profit - sellProfit) >= dropAmount) {
         FecharLado(POSITION_TYPE_SELL);
         max_sell_profit = 0;
         Print("Trailing Stop Acionado: VENDA");
      }
   } else if(max_sell_profit > 0) {
      FecharLado(POSITION_TYPE_SELL);
      max_sell_profit = 0;
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   CalculateStats();
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double totalFloating = equity - balance;

   // 1. TRAVA PROTETORA DE DRAWDOWN MÁXIMO (CIRCUIT BREAKER)
   if(InpUseMaxDD && !EmergencyStopTriggered) {
      bool triggerLoss = (InpMaxLossUSD > 0 && totalFloating <= -InpMaxLossUSD);
      bool triggerPct  = (InpMaxDrawdownPct > 0 && balance > 0 && ((-totalFloating / balance) * 100.0) >= InpMaxDrawdownPct);
      
      if(triggerLoss || triggerPct) {
         FecharTudo();
         EmergencyStopTriggered = true;
         EA_Active = false;
         PrintFormat("TRAVA DE DRAWDOWN ACIONADA! Perda flutuante: $%.2f (%.1f%%). Todas as posições foram fechadas para salvar a conta.", 
                     totalFloating, (-totalFloating / balance) * 100.0);
         return;
      }
   }

   // 2. SCANNER DE POSIÇÕES
   int totalBuy = 0, totalSell = 0;
   double buyProfit = 0, sellProfit = 0;
   double lastBuyPrice = 0, lastSellPrice = 0;
   double lastBuyLot = 0, lastSellLot = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber) {
         double p = posInfo.Profit() + posInfo.Commission() + posInfo.Swap();
         if(posInfo.PositionType() == POSITION_TYPE_BUY) {
            totalBuy++; 
            buyProfit += p;
            if(lastBuyPrice == 0 || posInfo.PriceOpen() < lastBuyPrice) { 
               lastBuyPrice = posInfo.PriceOpen(); 
               lastBuyLot = posInfo.Volume(); 
            }
         } else {
            totalSell++; 
            sellProfit += p;
            if(lastSellPrice == 0 || posInfo.PriceOpen() > lastSellPrice) { 
               lastSellPrice = posInfo.PriceOpen(); 
               lastSellLot = posInfo.Volume(); 
            }
         }
      }
   }

   if(totalBuy == 0) max_buy_profit = 0;
   if(totalSell == 0) max_sell_profit = 0;
   if(totalBuy == 0 && totalSell == 0) max_global_profit = 0;

   if (EA_Active && !EmergencyStopTriggered) {
      // 3. RECICLAGEM ATIVA INTELIGENTE
      if(buyProfit >= InpTargetSideUSD && totalSell > 0) {
         if(TentarReciclar(buyProfit, POSITION_TYPE_SELL)) {
            FecharLado(POSITION_TYPE_BUY); 
         }
      }
      if(sellProfit >= InpTargetSideUSD && totalBuy > 0) {
         if(TentarReciclar(sellProfit, POSITION_TYPE_BUY)) {
            FecharLado(POSITION_TYPE_SELL); 
         }
      }

      // 4. MOTOR DE GIRO
      if (IsTradingTime()) {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

         // FILTRO DE TENDÊNCIA MACRO (EMA 200)
         bool canBuy = true;
         bool canSell = true;
         if(InpUseTrendFilter && trendHandle != INVALID_HANDLE) {
            double ma[];
            ArraySetAsSeries(ma, true);
            if(CopyBuffer(trendHandle, 0, 0, 1, ma) > 0) {
               if(bid < ma[0]) canBuy = false;  // Preço abaixo da média: Não abre compra nova
               if(ask > ma[0]) canSell = false; // Preço acima da média: Não abre venda nova
            }
         }

         // Abertura de giro inicial seguro
         if(totalBuy == 0 && canBuy) trade.Buy(NormalizeVolume(InpInitialLot), _Symbol, ask, 0, 0, "Giro");
         if(totalSell == 0 && canSell) trade.Sell(NormalizeVolume(InpInitialLot), _Symbol, bid, 0, 0, "Giro");

         // 5. REALIZAÇÃO DE LUCRO INDIVIDUAL
         if(!InpUseTrailingStop) {
             if(buyProfit >= InpTargetSideUSD)  FecharLado(POSITION_TYPE_BUY);
             if(sellProfit >= InpTargetSideUSD) FecharLado(POSITION_TYPE_SELL);
         }
         
         // 5.1 TRAILING STOP EM DÓLAR
         ProcessTrailingStop(buyProfit, sellProfit, totalFloating);

         // 6. GRADE COM ESPAÇAMENTO PROGRESSIVO E LIMITAÇÃO DE RISCO
         double currentDistance = GetDynamicDistance();
         
         // Distância progressiva para compra
         double reqDistBuy = currentDistance;
         if(InpUseProgressiveGrid) reqDistBuy *= (1.0 + (totalBuy * (InpGridProgressionPct / 100.0)));

         // Distância progressiva para venda
         double reqDistSell = currentDistance;
         if(InpUseProgressiveGrid) reqDistSell *= (1.0 + (totalSell * (InpGridProgressionPct / 100.0)));

         if(totalBuy > 0 && totalBuy < InpMaxTotalOrders && ask < (lastBuyPrice - reqDistBuy)) {
            double nextLot = (totalBuy < InpMaxMartingale) ? NormalizeVolume(lastBuyLot * InpLotMultiplier) : lastBuyLot;
            trade.Buy(nextLot, _Symbol, ask, 0, 0, "Grid");
         }

         if(totalSell > 0 && totalSell < InpMaxTotalOrders && bid > (lastSellPrice + reqDistSell)) {
            double nextLot = (totalSell < InpMaxMartingale) ? NormalizeVolume(lastSellLot * InpLotMultiplier) : lastSellLot;
            trade.Sell(nextLot, _Symbol, bid, 0, 0, "Grid");
         }
      }
   }

   // Atualização do painel
   AtualizarValoresPainel(totalFloating, balance, equity, totalBuy, totalSell, buyProfit, sellProfit);
}

//+------------------------------------------------------------------+
//| Eventos do Gráfico                                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_OBJECT_CLICK) {
      if(sparam == PREFIX+"BTN_POWER") {
         EA_Active = !EA_Active;
         EmergencyStopTriggered = false; // Reset ao clicar em Power
         ObjectSetString(0, PREFIX+"BTN_POWER", OBJPROP_TEXT, EA_Active ? "ON" : "OFF");
         ObjectSetInteger(0, PREFIX+"BTN_POWER", OBJPROP_BGCOLOR, EA_Active ? cor_buy : cor_sell);
         ObjectSetString(0, PREFIX+"VAL_STATUS", OBJPROP_TEXT, EA_Active ? "Active" : "Paused");
         ObjectSetInteger(0, PREFIX+"VAL_STATUS", OBJPROP_COLOR, EA_Active ? cor_accent : cor_text_muted);
      }
      else if(sparam == PREFIX+"BTN_CLOSE_ALL") {
         FecharTudo();
         Print("CLOSE ALL PRESSED!");
      }
      else if(sparam == PREFIX+"BTN_BUY") {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         trade.Buy(NormalizeVolume(InpInitialLot), _Symbol, ask, 0, 0, "Manual Buy");
      }
      else if(sparam == PREFIX+"BTN_SELL") {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         trade.Sell(NormalizeVolume(InpInitialLot), _Symbol, bid, 0, 0, "Manual Sell");
      }
      else if(sparam == PREFIX+"BTN_CLEAN") {
         FecharLucrativas();
         Print("CLEAN BUTTON PRESSED! Profitable orders closed.");
      }
      else if(sparam == PREFIX+"BTN_PANIC") {
         FecharTudo();
         EA_Active = false;
         EmergencyStopTriggered = true;
         ObjectSetString(0, PREFIX+"BTN_POWER", OBJPROP_TEXT, "OFF");
         ObjectSetInteger(0, PREFIX+"BTN_POWER", OBJPROP_BGCOLOR, cor_sell);
         ObjectSetString(0, PREFIX+"VAL_STATUS", OBJPROP_TEXT, "STOPPED");
         ObjectSetInteger(0, PREFIX+"VAL_STATUS", OBJPROP_COLOR, cor_sell);
         Print("PANIC BUTTON PRESSED! All orders closed and EA paused.");
      }
      else if(sparam == PREFIX+"BTN_REMOVE") {
         ExpertRemove();
      }
      else if(sparam == PREFIX+"BTN_MIN") {
         Panel_Minimized = !Panel_Minimized;
         ObjectSetString(0, PREFIX+"BTN_MIN", OBJPROP_TEXT, Panel_Minimized ? "+" : "-");
         AtualizarVisibilidadePainel();
      }
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
//| Reciclagem Ativa Otimizada                                       |
//+------------------------------------------------------------------+
bool TentarReciclar(double lucroDisponivel, ENUM_POSITION_TYPE ladoPerdedor) {
   ulong ticketReciclar = 0;
   double perdaReciclar = 0;

   for(int i = 0; i < PositionsTotal(); i++) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber && posInfo.PositionType() == ladoPerdedor) {
         double p = posInfo.Profit() + posInfo.Commission() + posInfo.Swap();
         if(p < 0 && lucroDisponivel > MathAbs(p)) {
            if(ticketReciclar == 0 || MathAbs(p) > MathAbs(perdaReciclar)) {
               ticketReciclar = posInfo.Ticket();
               perdaReciclar = p;
            }
         }
      }
   }

   if(ticketReciclar > 0) {
      if(trade.PositionClose(ticketReciclar)) {
         PrintFormat("RECICLAGEM SUCESSO: Ordem #%d removida (Perda: $%.2f) abatida com Lucro de $%.2f.", 
                     ticketReciclar, perdaReciclar, lucroDisponivel);
         return true;
      }
   }
   return false;
}

void FecharLado(ENUM_POSITION_TYPE type) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber) {
         if(posInfo.PositionType() == type) trade.PositionClose(posInfo.Ticket());
      }
   }
}

void FecharTudo() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber) {
         trade.PositionClose(posInfo.Ticket());
      }
   }
}

void FecharLucrativas() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber) {
         double p = posInfo.Profit() + posInfo.Commission() + posInfo.Swap();
         if(p > 0) trade.PositionClose(posInfo.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//| Painel Moderno                                                   |
//+------------------------------------------------------------------+
void CriarPainelModerno() {
   int x = 20;
   int y = 20;
   int w = 320;
   int h = 550;

   CreateRect(PREFIX+"BG_MAIN", x, y, w, h, cor_bg_main, cor_border);
   CreateRect(PREFIX+"BG_HEADER", x, y, w, 40, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"TITLE", "BURGO SCALPE PRO (PROTECTED)", x+15, y+12, cor_text_main, 11, "Arial Bold");
   CreateButton(PREFIX+"BTN_MIN", "-", x+w-35, y+10, 20, 20, cor_bg_main, cor_text_main);
   
   DrawLabel(PREFIX+"LBL_TIME", "Server Time:", x+15, y+55, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_TIME", "00:00:00", x+15, y+70, cor_accent, 14, "Arial Bold");
   
   DrawLabel(PREFIX+"LBL_CANDLE", "Next Candle:", x+120, y+55, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_CANDLE", "00:00", x+120, y+70, cor_text_main, 10, "Arial Bold");

   DrawLabel(PREFIX+"LBL_SPREAD", "Spread:", x+220, y+55, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_SPREAD", "0", x+220, y+70, cor_warning, 10, "Arial Bold");

   int btn_y = y + 100;
   CreateButton(PREFIX+"BTN_BUY", "BUY", x+15, btn_y, 65, 30, cor_buy, clrWhite);
   CreateButton(PREFIX+"BTN_SELL", "SELL", x+85, btn_y, 65, 30, cor_sell, clrWhite);
   CreateButton(PREFIX+"BTN_CLEAN", "CLEAN", x+155, btn_y, 65, 30, cor_accent, clrWhite);
   CreateButton(PREFIX+"BTN_PANIC", "PANIC", x+225, btn_y, 80, 30, cor_warning, clrWhite);

   CreateButton(PREFIX+"BTN_CLOSE_ALL", "CLOSE ALL (FECHAR TUDO)", x+15, btn_y+35, 290, 25, cor_sell, clrWhite);

   int card_y = btn_y + 70;
   CreateRect(PREFIX+"CARD1", x+15, card_y, 140, 70, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_FLOAT", "Floating P/L", x+25, card_y+10, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_FLOAT", "$0.00", x+25, card_y+25, cor_text_main, 12, "Arial Bold");
   DrawLabel(PREFIX+"VAL_BAL", "Bal: $0.00", x+25, card_y+45, cor_text_muted, 9, "Arial");

   CreateRect(PREFIX+"CARD2", x+165, card_y, 140, 70, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_PROFIT", "Profit Today", x+175, card_y+10, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_PROFIT", "$0.00", x+175, card_y+25, cor_text_main, 12, "Arial Bold");
   DrawLabel(PREFIX+"VAL_TOTAL", "Total: $0.00", x+175, card_y+45, cor_text_muted, 9, "Arial");

   int card2_y = card_y + 80;
   CreateRect(PREFIX+"CARD3", x+15, card2_y, 290, 80, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_ORDERS", "Active Orders & Risk Limit", x+25, card2_y+10, cor_text_muted, 9, "Arial Bold");
   
   DrawLabel(PREFIX+"LBL_BUY_ORD", "Buy Orders:", x+25, card2_y+30, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_BUY_ORD", "0 ($0.00)", x+100, card2_y+30, cor_buy, 9, "Arial Bold");
   
   DrawLabel(PREFIX+"LBL_SELL_ORD", "Sell Orders:", x+25, card2_y+50, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_SELL_ORD", "0 ($0.00)", x+100, card2_y+50, cor_sell, 9, "Arial Bold");

   int card3_y = card2_y + 90;
   CreateRect(PREFIX+"CARD4", x+15, card3_y, 290, 90, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_STATS", "Performance", x+25, card3_y+10, cor_text_muted, 9, "Arial Bold");
   DrawLabel(PREFIX+"VAL_TRADES", "Total Trades: 0", x+25, card3_y+30, cor_text_main, 9, "Arial");
   
   DrawLabel(PREFIX+"VAL_WINS", "Wins: 0 (0%)", x+25, card3_y+50, cor_buy, 9, "Arial");
   DrawLabel(PREFIX+"VAL_LOSSES", "Losses: 0 (0%)", x+150, card3_y+50, cor_sell, 9, "Arial");
   
   DrawLabel(PREFIX+"VAL_PROFIT_PCT", "Max DD Lock: Active (15%)", x+25, card3_y+70, cor_accent, 9, "Arial Bold");

   int footer_y = card3_y + 100;
   CreateRect(PREFIX+"BG_FOOTER", x, footer_y, w, 50, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_POWER", "Auto Trading:", x+15, footer_y+18, cor_text_main, 10, "Arial Bold");
   DrawLabel(PREFIX+"VAL_STATUS", "Active", x+100, footer_y+18, cor_accent, 10, "Arial Bold");
   CreateButton(PREFIX+"BTN_POWER", "ON", x+w-70, footer_y+12, 50, 25, cor_buy, clrWhite);
   CreateButton(PREFIX+"BTN_REMOVE", "X", x+w-110, footer_y+12, 30, 25, cor_sell, clrWhite);
}

void AtualizarValoresPainel(double floating, double bal, double eq, int tBuy, int tSell, double pBuy, double pSell) {
   if (Panel_Minimized) return;

   datetime time = TimeCurrent();
   ObjectSetString(0, PREFIX+"VAL_TIME", OBJPROP_TEXT, TimeToString(time, TIME_MINUTES|TIME_SECONDS));

   ENUM_TIMEFRAMES tf = (InpTimeframe == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpTimeframe;
   long lastBarTime = SeriesInfoInteger(_Symbol, tf, SERIES_LASTBAR_DATE);
   long barSecs = PeriodSeconds(tf);
   long seconds_left = (lastBarTime > 0 && barSecs > 0) ? (lastBarTime + barSecs - TimeCurrent()) : 0;
   if(seconds_left < 0) seconds_left = 0;
   string candle_time = StringFormat("%02d:%02d", (int)(seconds_left / 60), (int)(seconds_left % 60));
   ObjectSetString(0, PREFIX+"VAL_CANDLE", OBJPROP_TEXT, candle_time);

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   ObjectSetString(0, PREFIX+"VAL_SPREAD", OBJPROP_TEXT, IntegerToString(spread));

   color floatColor = (floating > 0) ? cor_buy : (floating < 0) ? cor_sell : cor_text_main;
   ObjectSetString(0, PREFIX+"VAL_FLOAT", OBJPROP_TEXT, StringFormat("$%.2f", floating));
   ObjectSetInteger(0, PREFIX+"VAL_FLOAT", OBJPROP_COLOR, floatColor);
   
   ObjectSetString(0, PREFIX+"VAL_BAL", OBJPROP_TEXT, StringFormat("Bal: $%.2f", bal));

   color profitColor = (daily_profit > 0) ? cor_buy : (daily_profit < 0) ? cor_sell : cor_text_main;
   ObjectSetString(0, PREFIX+"VAL_PROFIT", OBJPROP_TEXT, StringFormat("$%.2f", daily_profit));
   ObjectSetInteger(0, PREFIX+"VAL_PROFIT", OBJPROP_COLOR, profitColor);
   ObjectSetString(0, PREFIX+"VAL_TOTAL", OBJPROP_TEXT, StringFormat("Total: $%.2f", total_profit));

   ObjectSetString(0, PREFIX+"VAL_BUY_ORD", OBJPROP_TEXT, StringFormat("%d ($%.2f)", tBuy, pBuy));
   ObjectSetString(0, PREFIX+"VAL_SELL_ORD", OBJPROP_TEXT, StringFormat("%d ($%.2f)", tSell, pSell));

   double win_rate = (total_trades > 0) ? ((double)win_trades / total_trades) * 100.0 : 0;
   double loss_rate = (total_trades > 0) ? ((double)loss_trades / total_trades) * 100.0 : 0;
   
   ObjectSetString(0, PREFIX+"VAL_TRADES", OBJPROP_TEXT, StringFormat("Total Trades: %d", total_trades));
   ObjectSetString(0, PREFIX+"VAL_WINS", OBJPROP_TEXT, StringFormat("Wins: %d (%.1f%%)", win_trades, win_rate));
   ObjectSetString(0, PREFIX+"VAL_LOSSES", OBJPROP_TEXT, StringFormat("Losses: %d (%.1f%%)", loss_trades, loss_rate));
   
   ChartRedraw();
}

void AtualizarVisibilidadePainel() {
   bool show = !Panel_Minimized;
   ObjectSetInteger(0, PREFIX+"BG_MAIN", OBJPROP_YSIZE, show ? 550 : 40);
   
   string objs[] = {"LBL_TIME", "VAL_TIME", "LBL_CANDLE", "VAL_CANDLE", "LBL_SPREAD", "VAL_SPREAD",
                    "BTN_BUY", "BTN_SELL", "BTN_CLEAN", "BTN_PANIC", "BTN_CLOSE_ALL", 
                    "CARD1", "LBL_FLOAT", "VAL_FLOAT", "VAL_BAL", 
                    "CARD2", "LBL_PROFIT", "VAL_PROFIT", "VAL_TOTAL",
                    "CARD3", "LBL_ORDERS", "LBL_BUY_ORD", "VAL_BUY_ORD", "LBL_SELL_ORD", "VAL_SELL_ORD",
                    "CARD4", "LBL_STATS", "VAL_TRADES", "VAL_WINS", "VAL_LOSSES", "VAL_PROFIT_PCT",
                    "BG_FOOTER", "LBL_POWER", "VAL_STATUS", "BTN_POWER", "BTN_REMOVE"};
                    
   for(int i=0; i<ArraySize(objs); i++) {
      if(ObjectFind(0, PREFIX+objs[i]) >= 0) {
         ObjectSetInteger(0, PREFIX+objs[i], OBJPROP_TIMEFRAMES, show ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
      }
   }
}

void CreateRect(string name, int x, int y, int w, int h, color bg, color border) {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 100);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawLabel(string name, string text, int x, int y, color clr, int size, string font) {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 101);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void CreateButton(string name, string text, int x, int y, int w, int h, color bg, color fg) {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 102);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
}
