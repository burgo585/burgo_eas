//+------------------------------------------------------------------+
//|                                Burgo_Reciclagem_Ativa_V40.mq5   |
//|                                    Copyright 2024, DevMaster Pro |
//|      V40 - SISTEMA DE RECICLAGEM ATIVA (SEM MARTINGALE INFINITO) |
//+------------------------------------------------------------------+
#property copyright "DevMaster Pro"
#property version   "40.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// --- ENUM DE DIREÇÃO ---
enum ENUM_TRADE_DIRECTION {
   TRADE_DIR_BOTH_EMA   = 0, // Ambas Direções com Filtro EMA 200 (Mais Eficiente: +508% / 4.7% DD)
   TRADE_DIR_BUY_ONLY   = 1, // Apenas Compras (Maior Lucratividade no Ouro: +1390% / 17.2% DD)
   TRADE_DIR_BOTH_OPEN  = 2  // Ambas sem filtro (Modo Original)
};

// --- INPUTS ---
input group "==== FILTRO DIRECIONAL DE TENDÊNCIA ===="
input ENUM_TRADE_DIRECTION InpTradeDirection = TRADE_DIR_BOTH_EMA; // Modo Direcional (Otimizado XAUUSD)
input int                  InpEMAPeriod      = 200;                // Período da Média de Tendência

input group "==== MOTOR DE GIRO ===="
input double  InpInitialLot       = 0.01;      // Lote Inicial (Recomendado 0.01 para Ouro)
input double  InpTargetSideUSD    = 3.00;      // Alvo de cada giro p/ limpeza ($)
input double  InpTargetGlobalUSD  = 20.00;     // Alvo para reset total da conta ($)
input int     InpMagicNumber      = 888123;

input group "==== LIMITE DE SEGURANÇA ===="
input int     InpBaseDistance     = 600;       // Distância Base em Pontos ($6.00 no Ouro)
input double  InpLotMultiplier    = 1.25;      // Multiplicador Suave (Recomendado 1.15 a 1.25)
input int     InpMaxMartingale    = 3;         // Limite de aumento de lote
input int     InpMaxTotalOrders   = 4;         // Máximo absoluto de ordens (Recomendado 3 a 5 no Ouro)

input group "==== FILTROS AVANÇADOS ===="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_CURRENT; // Timeframe do Gráfico
input bool    InpUseATR           = true;      // Usar ATR para Distância Dinâmica
input int     InpATRPeriod        = 14;        // Período do ATR
input double  InpATRMultiplier    = 1.5;       // Multiplicador do ATR

input group "==== TRAILING STOP ===="
input bool    InpUseTrailingStop  = true;      // Ativar Trailing Stop
input double  InpTrailingStartUSD = 5.00;      // Iniciar Trailing com este lucro ($)
input double  InpTrailingDropPct  = 10.0;      // Porcentagem de queda para fechar (ex: 10%)

input group "==== HORÁRIOS DE OPERAÇÃO ===="
input string  InpStartTime        = "00:00";   // Horário de Início (HH:MM)
input string  InpEndTime          = "23:59";   // Horário de Término (HH:MM)

// Globais
CTrade        trade;
CPositionInfo posInfo;
string        PREFIX = "BRA40_";
int           atrHandle = INVALID_HANDLE;
int           emaHandle = INVALID_HANDLE;

bool          EA_Active = true;
bool          Panel_Minimized = false;

// Cores do Painel Moderno
color cor_bg_main     = C'15,23,42';    
color cor_bg_panel    = C'30,41,59';    
color cor_border      = C'51,65,85';    
color cor_text_main   = C'241,245,249'; 
color cor_text_muted  = C'148,163,184'; 
color cor_accent      = C'56,189,248';  
color cor_buy         = C'34,197,94';   
color cor_sell        = C'239,68,68';   
color cor_warning     = C'245,158,11';  

// Estatísticas
double total_profit = 0;
double daily_profit = 0;
int total_trades = 0;
int win_trades = 0;
int loss_trades = 0;

// Variáveis de Trailing
double max_buy_profit = 0;
double max_sell_profit = 0;
double max_global_profit = 0;

// Declaração das funções de UI e suporte
void   CreateRect(string name, int x, int y, int w, int h, color bg, color border);
void   DrawLabel(string name, string text, int x, int y, color clr, int size, string font);
void   CreateButton(string name, string text, int x, int y, int w, int h, color bg, color fg);
void   AtualizarVisibilidadePainel();
void   AtualizarValoresPainel(double floating, double bal, double eq, int tBuy, int tSell, double pBuy, double pSell);
void   FecharLucrativas();
void   FecharLado(ENUM_POSITION_TYPE type);
void   FecharTudo();
bool   TentarReciclar(double lucroDisponivel, ENUM_POSITION_TYPE ladoPerdedor);
double NormalizeLot(double lot);

//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFillingBySymbol(_Symbol);
   
   if(InpUseATR) {
      atrHandle = iATR(_Symbol, InpTimeframe, InpATRPeriod);
      if(atrHandle == INVALID_HANDLE) {
         Print("Erro ao carregar indicador ATR.");
         return(INIT_FAILED);
      }
   }
   
   if(InpTradeDirection == TRADE_DIR_BOTH_EMA) {
      emaHandle = iMA(_Symbol, InpTimeframe, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(emaHandle == INVALID_HANDLE) {
         Print("Erro ao carregar indicador EMA de Tendência.");
         return(INIT_FAILED);
      }
   }
   
   CriarPainelModerno();
   
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { 
   ObjectsDeleteAll(0, PREFIX); 
   if(InpUseATR && atrHandle != INVALID_HANDLE) {
      IndicatorRelease(atrHandle);
      atrHandle = INVALID_HANDLE;
   }
   if(emaHandle != INVALID_HANDLE) {
      IndicatorRelease(emaHandle);
      emaHandle = INVALID_HANDLE;
   }
   ChartRedraw();
}

double NormalizeLot(double lot) {
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(step <= 0)   step = 0.01;
   if(minLot <= 0) minLot = 0.01;
   if(maxLot <= 0) maxLot = 100.0;
   
   lot = MathFloor(lot / step + 0.0000001) * step;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   
   int digits = 0;
   if(step == 0.01) digits = 2;
   else if(step == 0.1) digits = 1;
   else if(step == 0.001) digits = 3;
   else {
      double s = step;
      while(s < 1.0 && digits < 4) { s *= 10; digits++; }
   }
   
   return NormalizeDouble(lot, digits);
}

bool IsTradingTime() {
   datetime time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(time, dt);
   
   int current_mins = dt.hour * 60 + dt.min;
   
   string start_arr[], end_arr[];
   if(StringSplit(InpStartTime, ':', start_arr) < 2 || StringSplit(InpEndTime, ':', end_arr) < 2) {
      return true;
   }
   
   int start_mins = (int)StringToInteger(start_arr[0]) * 60 + (int)StringToInteger(start_arr[1]);
   int end_mins   = (int)StringToInteger(end_arr[0]) * 60 + (int)StringToInteger(end_arr[1]);
   
   if (start_mins <= end_mins) {
      return (current_mins >= start_mins && current_mins <= end_mins);
   } else {
      return (current_mins >= start_mins || current_mins <= end_mins);
   }
}

double GetDynamicDistance() {
   double baseDist = InpBaseDistance * _Point;
   if(!InpUseATR || atrHandle == INVALID_HANDLE) return baseDist;
   
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(atrHandle, 0, 1, 1, atr) <= 0) return baseDist;
   
   double dist = atr[0] * InpATRMultiplier;
   double minDist = (InpBaseDistance / 2.0) * _Point;
   if(dist < minDist) dist = minDist;
   
   return dist;
}

void CalculateStats() {
   static int last_deals_count = -1;
   static datetime last_day = 0;
   
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(today == 0) {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      today = StructToTime(dt);
   }
   
   if(!HistorySelect(0, TimeCurrent())) return;
   int deals = HistoryDealsTotal();
   
   if(deals == last_deals_count && today == last_day) return;
   last_deals_count = deals;
   last_day = today;

   total_profit = 0;
   daily_profit = 0;
   total_trades = 0;
   win_trades = 0;
   loss_trades = 0;
   
   for(int i=0; i<deals; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0 && HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber) {
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
         
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY) {
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

bool ProcessGlobalTrailing(double totalFloating) {
   if(!InpUseTrailingStop) return false;
   
   if(totalFloating >= InpTargetGlobalUSD) {
      if(totalFloating > max_global_profit) max_global_profit = totalFloating;
   }
   
   if(max_global_profit >= InpTargetGlobalUSD) {
      double dropAmount = max_global_profit * (InpTrailingDropPct / 100.0);
      if((max_global_profit - totalFloating) >= dropAmount) {
         FecharTudo();
         max_global_profit = 0;
         Print("Trailing Stop Global Acionado!");
         return true;
      }
   }
   return false;
}

bool ProcessSideTrailing(ENUM_POSITION_TYPE type, double sideProfit) {
   if(!InpUseTrailingStop) return false;
   
   double startUSD = (InpTrailingStartUSD > 0) ? InpTrailingStartUSD : InpTargetSideUSD;
   
   if(type == POSITION_TYPE_BUY) {
      if(sideProfit >= startUSD) {
         if(sideProfit > max_buy_profit) max_buy_profit = sideProfit;
      }
      if(max_buy_profit >= startUSD) {
         double dropAmount = max_buy_profit * (InpTrailingDropPct / 100.0);
         if((max_buy_profit - sideProfit) >= dropAmount) {
            TentarReciclar(sideProfit, POSITION_TYPE_SELL);
            FecharLado(POSITION_TYPE_BUY);
            max_buy_profit = 0;
            Print("Trailing Stop Acionado: COMPRA");
            return true;
         }
      }
   } else {
      if(sideProfit >= startUSD) {
         if(sideProfit > max_sell_profit) max_sell_profit = sideProfit;
      }
      if(max_sell_profit >= startUSD) {
         double dropAmount = max_sell_profit * (InpTrailingDropPct / 100.0);
         if((max_sell_profit - sideProfit) >= dropAmount) {
            TentarReciclar(sideProfit, POSITION_TYPE_BUY);
            FecharLado(POSITION_TYPE_SELL);
            max_sell_profit = 0;
            Print("Trailing Stop Acionado: VENDA");
            return true;
         }
      }
   }
   return false;
}

void OnTick() {
   CalculateStats();
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double totalFloating = equity - balance;

   // 1. FECHAMENTO GLOBAL
   if(!InpUseTrailingStop) { 
       if(totalFloating >= InpTargetGlobalUSD) {
          FecharTudo(); 
          max_global_profit = 0;
          return;
       }
   } else {
       if(ProcessGlobalTrailing(totalFloating)) {
          return;
       }
   }

   // 2. SCANNER DE POSIÇÕES
   int totalBuy = 0, totalSell = 0;
   double buyProfit = 0, sellProfit = 0;
   double lastBuyPrice = 0, lastSellPrice = 0, lastBuyLot = 0, lastSellLot = 0;

   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==_Symbol && posInfo.Magic()==InpMagicNumber) {
         double p = posInfo.Profit() + posInfo.Commission() + posInfo.Swap();
         if(posInfo.PositionType() == POSITION_TYPE_BUY) {
            totalBuy++; 
            buyProfit += p;
            if(lastBuyPrice == 0 || posInfo.PriceOpen() < lastBuyPrice) { 
               lastBuyPrice = posInfo.PriceOpen(); 
               lastBuyLot   = posInfo.Volume(); 
            }
         } else {
            totalSell++; 
            sellProfit += p;
            if(lastSellPrice == 0 || posInfo.PriceOpen() > lastSellPrice) { 
               lastSellPrice = posInfo.PriceOpen(); 
               lastSellLot   = posInfo.Volume(); 
            }
         }
      }
   }

   if(totalBuy == 0)  max_buy_profit = 0;
   if(totalSell == 0) max_sell_profit = 0;
   if(totalBuy == 0 && totalSell == 0) max_global_profit = 0;

   if (EA_Active) {
      // 3. RECICLAGEM ATIVA
      if(buyProfit >= InpTargetSideUSD && totalSell > 0) {
         if(TentarReciclar(buyProfit, POSITION_TYPE_SELL)) {
            FecharLado(POSITION_TYPE_BUY); 
            max_buy_profit = 0;
            AtualizarValoresPainel(totalFloating, balance, equity, totalBuy, totalSell, buyProfit, sellProfit);
            return;
         }
      }
      if(sellProfit >= InpTargetSideUSD && totalBuy > 0) {
         if(TentarReciclar(sellProfit, POSITION_TYPE_BUY)) {
            FecharLado(POSITION_TYPE_SELL); 
            max_sell_profit = 0;
            AtualizarValoresPainel(totalFloating, balance, equity, totalBuy, totalSell, buyProfit, sellProfit);
            return;
         }
      }

      // 4. REALIZAÇÃO DE LUCRO INDIVIDUAL / TRAILING
      if(!InpUseTrailingStop) {
          if(buyProfit >= InpTargetSideUSD)  { 
             FecharLado(POSITION_TYPE_BUY); 
             max_buy_profit = 0;
             return; 
          }
          if(sellProfit >= InpTargetSideUSD) { 
             FecharLado(POSITION_TYPE_SELL); 
             max_sell_profit = 0;
             return; 
          }
      } else {
          if(ProcessSideTrailing(POSITION_TYPE_BUY, buyProfit))   return;
          if(ProcessSideTrailing(POSITION_TYPE_SELL, sellProfit)) return;
      }

      // 5. MOTOR DE GIRO E GRADE
      if (IsTradingTime()) {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

         // Determina se a direção está autorizada pelo filtro de tendência
         bool allowBuy = true;
         bool allowSell = true;

         if(InpTradeDirection == TRADE_DIR_BUY_ONLY) {
            allowSell = false;
         } else if(InpTradeDirection == TRADE_DIR_BOTH_EMA && emaHandle != INVALID_HANDLE) {
            double emaArr[];
            ArraySetAsSeries(emaArr, true);
            if(CopyBuffer(emaHandle, 0, 1, 1, emaArr) > 0) {
               double emaVal = emaArr[0];
               allowBuy  = (ask >= emaVal);
               allowSell = (bid <= emaVal);
            }
         }

         // Giro Inicial
         if(totalBuy == 0 && allowBuy) {
            double initLot = NormalizeLot(InpInitialLot);
            trade.Buy(initLot, _Symbol, ask, 0, 0, "Giro");
         }
         if(totalSell == 0 && allowSell) {
            double initLot = NormalizeLot(InpInitialLot);
            trade.Sell(initLot, _Symbol, bid, 0, 0, "Giro");
         }

         // Grade Controlada
         double currentDistance = GetDynamicDistance();
         
         if(totalBuy > 0 && totalBuy < InpMaxTotalOrders && ask < (lastBuyPrice - currentDistance)) {
            double nextLot = (totalBuy < InpMaxMartingale) ? NormalizeLot(lastBuyLot * InpLotMultiplier) : lastBuyLot;
            trade.Buy(nextLot, _Symbol, ask, 0, 0, "Grid");
         }

         if(totalSell > 0 && totalSell < InpMaxTotalOrders && bid > (lastSellPrice + currentDistance)) {
            double nextLot = (totalSell < InpMaxMartingale) ? NormalizeLot(lastSellLot * InpLotMultiplier) : lastSellLot;
            trade.Sell(nextLot, _Symbol, bid, 0, 0, "Grid");
         }
      }
   }

   AtualizarValoresPainel(totalFloating, balance, equity, totalBuy, totalSell, buyProfit, sellProfit);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_OBJECT_CLICK) {
      if(sparam == PREFIX+"BTN_POWER") {
         EA_Active = !EA_Active;
         ObjectSetString(0, PREFIX+"BTN_POWER", OBJPROP_TEXT, EA_Active ? "ON" : "OFF");
         ObjectSetInteger(0, PREFIX+"BTN_POWER", OBJPROP_BGCOLOR, EA_Active ? cor_buy : cor_sell);
         ObjectSetString(0, PREFIX+"VAL_STATUS", OBJPROP_TEXT, EA_Active ? "Active" : "Paused");
         ObjectSetInteger(0, PREFIX+"VAL_STATUS", OBJPROP_COLOR, EA_Active ? cor_accent : cor_text_muted);
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
      else if(sparam == PREFIX+"BTN_CLOSE_ALL") {
         FecharTudo();
         Print("CLOSE ALL PRESSED!");
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
      else if(sparam == PREFIX+"BTN_BUY") {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         trade.Buy(NormalizeLot(InpInitialLot), _Symbol, ask, 0, 0, "Manual Buy");
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
      else if(sparam == PREFIX+"BTN_SELL") {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         trade.Sell(NormalizeLot(InpInitialLot), _Symbol, bid, 0, 0, "Manual Sell");
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
      else if(sparam == PREFIX+"BTN_CLEAN") {
         FecharLucrativas();
         Print("CLEAN BUTTON PRESSED! Profitable orders closed.");
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
      else if(sparam == PREFIX+"BTN_PANIC") {
         FecharTudo();
         EA_Active = false;
         ObjectSetString(0, PREFIX+"BTN_POWER", OBJPROP_TEXT, "OFF");
         ObjectSetInteger(0, PREFIX+"BTN_POWER", OBJPROP_BGCOLOR, cor_sell);
         ObjectSetString(0, PREFIX+"VAL_STATUS", OBJPROP_TEXT, "Paused");
         ObjectSetInteger(0, PREFIX+"VAL_STATUS", OBJPROP_COLOR, cor_text_muted);
         Print("PANIC BUTTON PRESSED! All orders closed and EA paused.");
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
      else if(sparam == PREFIX+"BTN_REMOVE") {
         ExpertRemove();
      }
      else if(sparam == PREFIX+"BTN_MIN") {
         Panel_Minimized = !Panel_Minimized;
         ObjectSetString(0, PREFIX+"BTN_MIN", OBJPROP_TEXT, Panel_Minimized ? "+" : "-");
         AtualizarVisibilidadePainel();
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
      ChartRedraw();
   }
}

bool TentarReciclar(double lucroDisponivel, ENUM_POSITION_TYPE ladoPerdedor) {
   ulong  ticketCandidato = 0;
   double maiorPerda = 0;

   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Magic() == InpMagicNumber && posInfo.PositionType() == ladoPerdedor) {
         if(posInfo.Symbol() != _Symbol) continue;
         
         double p = posInfo.Profit() + posInfo.Commission() + posInfo.Swap();
         
         if(p < 0) {
            double perdaAbs = MathAbs(p);
            if(lucroDisponivel >= perdaAbs) {
               if(ticketCandidato == 0 || perdaAbs > MathAbs(maiorPerda)) {
                  ticketCandidato = posInfo.Ticket();
                  maiorPerda = p;
               }
            }
         }
      }
   }

   if(ticketCandidato > 0) {
      if(trade.PositionClose(ticketCandidato)) {
         PrintFormat("RECICLAGEM REALIZADA: Ordem #%d (Perda: $%.2f) resgatada com lucro de $%.2f",
                     ticketCandidato, maiorPerda, lucroDisponivel);
         return true;
      }
   }
   return false;
}

void FecharLado(ENUM_POSITION_TYPE type) {
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber) {
         if(posInfo.PositionType() == type) trade.PositionClose(posInfo.Ticket());
      }
   }
}

void FecharTudo() {
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber) {
         trade.PositionClose(posInfo.Ticket());
      }
   }
}

void FecharLucrativas() {
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber) {
         double p = posInfo.Profit() + posInfo.Commission() + posInfo.Swap();
         if(p > 0) trade.PositionClose(posInfo.Ticket());
      }
   }
}

void CriarPainelModerno() {
   int x = 20;
   int y = 20;
   int w = 320;
   int h = 520;

   CreateRect(PREFIX+"BG_MAIN", x, y, w, h, cor_bg_main, cor_border);
   
   CreateRect(PREFIX+"BG_HEADER", x, y, w, 40, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"TITLE", "RECICLAGEM ATIVA V40", x+15, y+12, cor_text_main, 12, "Arial Bold");
   CreateButton(PREFIX+"BTN_MIN", "-", x+w-35, y+10, 20, 20, cor_bg_main, cor_text_main);
   
   DrawLabel(PREFIX+"LBL_TIME", "Server Time:", x+15, y+55, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_TIME", "00:00:00", x+15, y+70, cor_accent, 14, "Arial Bold");
   
   DrawLabel(PREFIX+"LBL_CANDLE", "Next Candle:", x+120, y+55, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_CANDLE", "00:00", x+120, y+70, cor_text_main, 10, "Arial Bold");

   DrawLabel(PREFIX+"LBL_SPREAD", "Spread:", x+220, y+55, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_SPREAD", "0", x+220, y+70, cor_warning, 10, "Arial Bold");

   int btn_y = y + 100;
   CreateButton(PREFIX+"BTN_BUY", "BUY", x+15, btn_y, 65, 35, cor_buy, clrWhite);
   CreateButton(PREFIX+"BTN_SELL", "SELL", x+85, btn_y, 65, 35, cor_sell, clrWhite);
   CreateButton(PREFIX+"BTN_CLEAN", "CLEAN", x+155, btn_y, 65, 35, cor_accent, clrWhite);
   CreateButton(PREFIX+"BTN_PANIC", "PANIC", x+225, btn_y, 80, 35, cor_warning, clrWhite);

   int card_y = btn_y + 50;
   
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
   DrawLabel(PREFIX+"LBL_ORDERS", "Active Orders", x+25, card2_y+10, cor_text_muted, 9, "Arial Bold");
   
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
   
   DrawLabel(PREFIX+"VAL_PROFIT_PCT", "Profit %: 0.00%", x+25, card3_y+70, cor_accent, 9, "Arial Bold");

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

   datetime bar_open = iTime(_Symbol, InpTimeframe, 0);
   long seconds_left = bar_open + PeriodSeconds(InpTimeframe) - TimeCurrent();
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

   double win_rate   = (total_trades > 0) ? ((double)win_trades / total_trades) * 100.0 : 0;
   double loss_rate  = (total_trades > 0) ? ((double)loss_trades / total_trades) * 100.0 : 0;
   double profit_pct = (bal > 0) ? (total_profit / bal) * 100.0 : 0;

   ObjectSetString(0, PREFIX+"VAL_TRADES", OBJPROP_TEXT, StringFormat("Total Trades: %d", total_trades));
   ObjectSetString(0, PREFIX+"VAL_WINS", OBJPROP_TEXT, StringFormat("Wins: %d (%.1f%%)", win_trades, win_rate));
   ObjectSetString(0, PREFIX+"VAL_LOSSES", OBJPROP_TEXT, StringFormat("Losses: %d (%.1f%%)", loss_trades, loss_rate));
   ObjectSetString(0, PREFIX+"VAL_PROFIT_PCT", OBJPROP_TEXT, StringFormat("Profit %%: %.2f%%", profit_pct));
   
   ChartRedraw();
}

void AtualizarVisibilidadePainel() {
   bool show = !Panel_Minimized;
   
   ObjectSetInteger(0, PREFIX+"BG_MAIN", OBJPROP_YSIZE, show ? 520 : 40);
   
   string objs[] = {"LBL_TIME", "VAL_TIME", "LBL_CANDLE", "VAL_CANDLE", "LBL_SPREAD", "VAL_SPREAD",
                    "LBL_STATUS", "VAL_STATUS", "BTN_BUY", "BTN_SELL", "BTN_CLEAN", "BTN_PANIC", "BTN_CLOSE_ALL", 
                    "CARD1", "LBL_FLOAT", "VAL_FLOAT", "VAL_BAL", 
                    "CARD2", "LBL_PROFIT", "VAL_PROFIT", "VAL_TOTAL",
                    "CARD3", "LBL_ORDERS", "LBL_BUY_ORD", "VAL_BUY_ORD", "LBL_SELL_ORD", "VAL_SELL_ORD",
                    "CARD4", "LBL_STATS", "VAL_TRADES", "VAL_WINS", "VAL_LOSSES", "VAL_PROFIT_PCT",
                    "BG_FOOTER", "LBL_POWER", "BTN_POWER", "BTN_REMOVE"};
                    
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
