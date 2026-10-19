//+------------------------------------------------------------------+
//|                                           Burgo Scalpe Pro.mq5 |
//|                                     Copyright 2024, DevMaster Pro |
//|        V40 - SISTEMA DE RECICLAGEM ATIVA E SCALPING M1 (XAUUSD)   |
//+------------------------------------------------------------------+
#property copyright "DevMaster Pro"
#property version   "40.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// --- INPUTS CALIBRADOS INSTITUCIONALMENTE PARA XAUUSD M1 ---
input group "==== MOTOR DE GIRO E RECICLAGEM ===="
input double  InpInitialLot       = 0.02;      // Lote Inicial de Giro
input double  InpTargetSideUSD    = 2.00;      // Alvo financeiro ($) da micro-retração por lado
input double  InpTargetGlobalUSD  = 20.00;     // Alvo total ($) para Reset de Segurança da Conta
input int     InpMagicNumber      = 888123;    // Identificador Magic Number

input group "==== LIMITE DE SEGURANÇA E GRADE ===="
input int     InpBaseDistance     = 200;       // Distância Base em Pontos (200 pts = $2.00 / 20 pips)
input double  InpLotMultiplier    = 1.35;      // Multiplicador Geométrico Suave (1.35x)
input int     InpMaxMartingale    = 6;         // Trava de aumento de lote no 6º nível (controle de margem)
input int     InpMaxTotalOrders   = 12;        // Máximo absoluto de ordens por lado

input group "==== FILTROS DE VOLATILIDADE M1 ===="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M1; // Timeframe Analítico do ATR
input bool    InpUseATR           = true;      // Ativar ATR para Distância Adaptativa
input int     InpATRPeriod        = 14;        // Período do ATR
input double  InpATRMultiplier    = 1.5;       // Multiplicador do ATR (expande em explosões de preço)

input group "==== TRAILING STOP RASTREADOR ===="
input bool    InpUseTrailingStop  = true;      // Ativar Trailing Stop
input double  InpTrailingStartUSD = 1.50;      // Iniciar Trailing Stop ao atingir ($1.50)
input double  InpTrailingStepUSD  = 0.50;      // Recuo tolerado para realização ($0.50)

input group "==== HORÁRIOS DE OPERAÇÃO ===="
input string  InpStartTime        = "00:00";   // Horário de Início (HH:MM)
input string  InpEndTime          = "23:59";   // Horário de Término (HH:MM)

// Instâncias e Objetos Globais de Negociação
CTrade        trade;
CPositionInfo posInfo;
int           PM = 1;
string        PREFIX = "BSP_";
int           atrHandle = INVALID_HANDLE;

bool          EA_Active = true;
bool          Panel_Minimized = false;

// Paleta de Cores do Painel Institucional
color cor_bg_main     = C'15,23,42';    
color cor_bg_panel    = C'30,41,59';    
color cor_border      = C'51,65,85';    
color cor_text_main   = C'241,245,249'; 
color cor_text_muted  = C'148,163,184'; 
color cor_accent      = C'56,189,248';  
color cor_buy         = C'34,197,94';   
color cor_sell        = C'239,68,68';   
color cor_warning     = C'245,158,11';  

// Estatísticas da Sessão
double total_profit = 0.0;
double daily_profit = 0.0;
int total_trades = 0;
int win_trades = 0;
int loss_trades = 0;

// Variáveis de Rastreamento de Trailing Stop
double max_buy_profit = 0.0;
double max_sell_profit = 0.0;

// Declaração Prévia das Funções de UI e Operação
void CreateRect(string name, int x, int y, int w, int h, color bg, color border);
void DrawLabel(string name, string text, int x, int y, color clr, int size, string font);
void CreateButton(string name, string text, int x, int y, int w, int h, color bg, color fg);
void CriarPainelModerno();
void AtualizarVisibilidadePainel();
void AtualizarValoresPainel(double floating, double bal, double eq, int tBuy, int tSell, double pBuy, double pSell);
void FecharLado(ENUM_POSITION_TYPE type);
void FecharTudo();
void FecharLucrativas();
bool TentarReciclarPiorOrdem(double lucroDisponivel, ENUM_POSITION_TYPE ladoPerdedor);
double NormalizeLots(double lot);

//+------------------------------------------------------------------+
//| Inicialização do Expert Advisor                                  |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetAsyncMode(false); // Execução síncrona segura institucional
   
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   PM = (digits >= 3) ? 10 : 1;
   
   if(InpUseATR) {
      atrHandle = iATR(_Symbol, InpTimeframe, InpATRPeriod);
      if(atrHandle == INVALID_HANDLE) {
          Print("Aviso: Falha ao carregar indicador ATR. Usando distância fixa.");
      }
   }
   
   CalculateStats();
   CriarPainelModerno();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Desinicialização e Limpeza de Recursos                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) { 
   ObjectsDeleteAll(0, PREFIX); 
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Normalização Rigorosa do Volume conforme a Corretora             |
//+------------------------------------------------------------------+
double NormalizeLots(double lot) {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(step <= 0.0) step = 0.01;
   
   double normalized = MathFloor(lot / step + 0.0000001) * step;
   if(normalized < minLot) normalized = minLot;
   if(normalized > maxLot) normalized = maxLot;
   
   int digits = 2;
   if(step == 0.1) digits = 1;
   else if(step == 0.01) digits = 2;
   else if(step == 0.001) digits = 3;
   
   return NormalizeDouble(normalized, digits);
}

//+------------------------------------------------------------------+
//| Validação de Janela Operacional                                  |
//+------------------------------------------------------------------+
bool IsTradingTime() {
   datetime time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(time, dt);
   
   int current_mins = dt.hour * 60 + dt.min;
   
   string start_arr[];
   StringSplit(InpStartTime, ':', start_arr);
   int start_mins = (int)StringToInteger(start_arr[0]) * 60 + (int)StringToInteger(start_arr[1]);
   
   string end_arr[];
   StringSplit(InpEndTime, ':', end_arr);
   int end_mins = (int)StringToInteger(end_arr[0]) * 60 + (int)StringToInteger(end_arr[1]);
   
   if(start_mins < end_mins) {
      return (current_mins >= start_mins && current_mins <= end_mins);
   } else {
      return (current_mins >= start_mins || current_mins <= end_mins);
   }
}

//+------------------------------------------------------------------+
//| Cálculo da Distância Adaptativa de Grade (ATR M1)                |
//+------------------------------------------------------------------+
double GetDynamicDistance() {
   double baseDistPrice = InpBaseDistance * PM * _Point;
   if(!InpUseATR || atrHandle == INVALID_HANDLE) return baseDistPrice;
   
   double atr[];
   ArraySetAsSeries(atr, true);
   int copied = CopyBuffer(atrHandle, 0, 0, 1, atr);
   if(copied <= 0) return baseDistPrice;
   
   double dist = atr[0] * InpATRMultiplier;
   double minDist = (InpBaseDistance / 2.0) * PM * _Point;
   if(dist < minDist) dist = minDist;
   
   return dist;
}

//+------------------------------------------------------------------+
//| Atualização Otimizada de Estatísticas da Conta                   |
//+------------------------------------------------------------------+
void CalculateStats() {
   total_profit = 0.0;
   daily_profit = 0.0;
   total_trades = 0;
   win_trades = 0;
   loss_trades = 0;
   
   HistorySelect(0, TimeCurrent());
   int deals = HistoryDealsTotal();
   datetime today = TimeCurrent() - (TimeCurrent() % 86400);
   
   for(int i = 0; i < deals; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber) {
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + 
                            HistoryDealGetDouble(ticket, DEAL_COMMISSION) + 
                            HistoryDealGetDouble(ticket, DEAL_SWAP);
            total_profit += profit;
            total_trades++;
            if(profit > 0.0) win_trades++;
            else if(profit < 0.0) loss_trades++;
            
            datetime deal_time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
            if(deal_time >= today) {
               daily_profit += profit;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Evento de Transação (Execução apenas quando fechar ordens)       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
      CalculateStats();
   }
}

//+------------------------------------------------------------------+
//| Trailing Stop Rastreador de Micro-Retração                       |
//+------------------------------------------------------------------+
void ProcessTrailingStop(double buyProfit, double sellProfit, double totalFloating) {
   if(!InpUseTrailingStop) return;
   
   // Trailing Lado Compra (protege lucros positivos)
   if(InpTrailingStartUSD > 0.0 && buyProfit >= InpTrailingStartUSD) {
      if(buyProfit > max_buy_profit) max_buy_profit = buyProfit;
      if(buyProfit <= (max_buy_profit - InpTrailingStepUSD)) {
         FecharLado(POSITION_TYPE_BUY);
         max_buy_profit = 0.0;
         Print("Trailing Stop Acionado (Compra) em: $", DoubleToString(buyProfit, 2));
      }
   } else if(buyProfit < 0.0) {
      max_buy_profit = 0.0;
   }
   
   // Trailing Lado Venda
   if(InpTrailingStartUSD > 0.0 && sellProfit >= InpTrailingStartUSD) {
      if(sellProfit > max_sell_profit) max_sell_profit = sellProfit;
      if(sellProfit <= (max_sell_profit - InpTrailingStepUSD)) {
         FecharLado(POSITION_TYPE_SELL);
         max_sell_profit = 0.0;
         Print("Trailing Stop Acionado (Venda) em: $", DoubleToString(sellProfit, 2));
      }
   } else if(sellProfit < 0.0) {
      max_sell_profit = 0.0;
   }
}

//+------------------------------------------------------------------+
//| Reciclagem Ativa: Abate a Pior Ordem do Lado Oposto              |
//+------------------------------------------------------------------+
bool TentarReciclarPiorOrdem(double lucroDisponivel, ENUM_POSITION_TYPE ladoPerdedor) {
   ulong ticketPiorOrdem = 0;
   double piorPerda = 0.0;

   // Busca a ordem com a MAIOR perda líquida acumulada
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber) {
         if(posInfo.PositionType() == ladoPerdedor) {
            double pnl = posInfo.Profit() + posInfo.Commission() + posInfo.Swap();
            if(ticketPiorOrdem == 0 || pnl < piorPerda) {
               ticketPiorOrdem = posInfo.Ticket();
               piorPerda = pnl;
            }
         }
      }
   }

   // Se o lucro do giro atual cobre a pior perda com margem líquida positiva:
   if(ticketPiorOrdem > 0 && lucroDisponivel > MathAbs(piorPerda)) {
      if(trade.PositionClose(ticketPiorOrdem)) {
         Print("RECICLAGEM EXECUTADA: Pior ordem ticket ", ticketPiorOrdem, 
               " (Perda: $", DoubleToString(piorPerda, 2), 
               ") eliminada com o lucro de giro de $", DoubleToString(lucroDisponivel, 2));
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Fechamento Síncrono Seguro de um Lado Específico                 |
//+------------------------------------------------------------------+
void FecharLado(ENUM_POSITION_TYPE type) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber) {
         if(posInfo.PositionType() == type) {
            trade.PositionClose(posInfo.Ticket());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Fechamento Síncrono Seguro de Todas as Ordens (Reset Total)      |
//+------------------------------------------------------------------+
void FecharTudo() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber) {
         trade.PositionClose(posInfo.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//| Fechamento de Apenas Ordens Lucrativas                           |
//+------------------------------------------------------------------+
void FecharLucrativas() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber) {
         double p = posInfo.Profit() + posInfo.Commission() + posInfo.Swap();
         if(p > 0.0) trade.PositionClose(posInfo.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//| Loop de Processamento Principal em Tempo Real (OnTick)           |
//+------------------------------------------------------------------+
void OnTick() {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double totalFloating = equity - balance;

   int totalBuy = 0, totalSell = 0;
   double buyProfit = 0.0, sellProfit = 0.0;
   double lastBuyPrice = 0.0, lastSellPrice = 0.0;
   double lastBuyLot = 0.0, lastSellLot = 0.0;

   // Varredura de Posições Abertas
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber) {
         double p = posInfo.Profit() + posInfo.Commission() + posInfo.Swap();
         if(posInfo.PositionType() == POSITION_TYPE_BUY) {
            totalBuy++; 
            buyProfit += p;
            if(lastBuyPrice == 0.0 || posInfo.PriceOpen() < lastBuyPrice) { 
               lastBuyPrice = posInfo.PriceOpen(); 
               lastBuyLot = posInfo.Volume(); 
            }
         } else {
            totalSell++; 
            sellProfit += p;
            if(lastSellPrice == 0.0 || posInfo.PriceOpen() > lastSellPrice) { 
               lastSellPrice = posInfo.PriceOpen(); 
               lastSellLot = posInfo.Volume(); 
            }
         }
      }
   }

   if(EA_Active) {
      // 1. RESET GLOBAL DE SEGURANÇA (Meta combinada da conta)
      if(InpTargetGlobalUSD > 0.0 && totalFloating >= InpTargetGlobalUSD) {
         FecharTudo();
         max_buy_profit = 0.0;
         max_sell_profit = 0.0;
         Print("RESET GLOBAL DA CONTA: Meta de $", DoubleToString(totalFloating, 2), " atingida. Carteira zerada com lucro!");
         AtualizarValoresPainel(totalFloating, balance, equity, 0, 0, 0.0, 0.0);
         return;
      }

      // 2. MOTOR DE RECICLAGEM E REALIZAÇÃO DE LUCROS DAS MICRO-RETRAÇÕES
      // Lado Comprador bateu o alvo de micro-retração:
      if(buyProfit >= InpTargetSideUSD) {
         if(totalSell > 0) {
            TentarReciclarPiorOrdem(buyProfit, POSITION_TYPE_SELL);
         }
         // DESBLOQUEIO CRÍTICO: Fecha as compras garantindo os dólares no saldo
         FecharLado(POSITION_TYPE_BUY); 
         max_buy_profit = 0.0;
         Print("GIRO COMPRADOR CONCLUÍDO: Lucro realizado = $", DoubleToString(buyProfit, 2));
      }

      // Lado Vendedor bateu o alvo de micro-retração:
      if(sellProfit >= InpTargetSideUSD) {
         if(totalBuy > 0) {
            TentarReciclarPiorOrdem(sellProfit, POSITION_TYPE_BUY);
         }
         // DESBLOQUEIO CRÍTICO: Fecha as vendas garantindo os dólares no saldo
         FecharLado(POSITION_TYPE_SELL); 
         max_sell_profit = 0.0;
         Print("GIRO VENDEDOR CONCLUÍDO: Lucro realizado = $", DoubleToString(sellProfit, 2));
      }

      // 3. TRAILING STOP RASTREADOR (Sobe junto com as esticadas a favor)
      ProcessTrailingStop(buyProfit, sellProfit, totalFloating);

      // 4. ABERTURA DE NOVOS GIROS E ADIÇÃO DE GRADE
      if(IsTradingTime()) {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

         // Giro Inicial Desbloqueado
         if(totalBuy == 0) trade.Buy(NormalizeLots(InpInitialLot), _Symbol, ask, 0, 0, "Giro");
         if(totalSell == 0) trade.Sell(NormalizeLots(InpInitialLot), _Symbol, bid, 0, 0, "Giro");

         double currentDistance = GetDynamicDistance();
         
         // Adição de Grade - Compras contra tendência
         if(totalBuy > 0 && totalBuy < InpMaxTotalOrders && ask < (lastBuyPrice - currentDistance)) {
            double nextLot = (totalBuy < InpMaxMartingale) ? NormalizeLots(lastBuyLot * InpLotMultiplier) : lastBuyLot;
            trade.Buy(nextLot, _Symbol, ask, 0, 0, "Grid");
         }

         // Adição de Grade - Vendas contra tendência
         if(totalSell > 0 && totalSell < InpMaxTotalOrders && bid > (lastSellPrice + currentDistance)) {
            double nextLot = (totalSell < InpMaxMartingale) ? NormalizeLots(lastSellLot * InpLotMultiplier) : lastSellLot;
            trade.Sell(nextLot, _Symbol, bid, 0, 0, "Grid");
         }
      }
   }
   
   AtualizarValoresPainel(totalFloating, balance, equity, totalBuy, totalSell, buyProfit, sellProfit);
}

//+------------------------------------------------------------------+
//| Processamento de Eventos Visuais no Gráfico                      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_OBJECT_CLICK) {
      if(sparam == PREFIX+"BTN_POWER") {
         EA_Active = !EA_Active;
         ObjectSetString(0, PREFIX+"BTN_POWER", OBJPROP_TEXT, EA_Active ? "ON" : "OFF");
         ObjectSetInteger(0, PREFIX+"BTN_POWER", OBJPROP_BGCOLOR, EA_Active ? cor_buy : cor_sell);
         ObjectSetString(0, PREFIX+"VAL_STATUS", OBJPROP_TEXT, EA_Active ? "Active" : "Paused");
         ObjectSetInteger(0, PREFIX+"VAL_STATUS", OBJPROP_COLOR, EA_Active ? cor_accent : cor_text_muted);
      }
      else if(sparam == PREFIX+"BTN_CLOSE_ALL") {
         FecharTudo();
         Print("Comando Manual: Fechar Tudo executado.");
      }
      else if(sparam == PREFIX+"BTN_BUY") {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         trade.Buy(NormalizeLots(InpInitialLot), _Symbol, ask, 0, 0, "Manual Buy");
      }
      else if(sparam == PREFIX+"BTN_SELL") {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         trade.Sell(NormalizeLots(InpInitialLot), _Symbol, bid, 0, 0, "Manual Sell");
      }
      else if(sparam == PREFIX+"BTN_CLEAN") {
         FecharLucrativas();
         Print("Comando Manual: Limpeza de ordens lucrativas executada.");
      }
      else if(sparam == PREFIX+"BTN_PANIC") {
         FecharTudo();
         EA_Active = false;
         ObjectSetString(0, PREFIX+"BTN_POWER", OBJPROP_TEXT, "OFF");
         ObjectSetInteger(0, PREFIX+"BTN_POWER", OBJPROP_BGCOLOR, cor_sell);
         ObjectSetString(0, PREFIX+"VAL_STATUS", OBJPROP_TEXT, "Paused");
         ObjectSetInteger(0, PREFIX+"VAL_STATUS", OBJPROP_COLOR, cor_text_muted);
         Print("BOTÃO DE PÂNICO: Todas as posições encerradas e automação pausada.");
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
//| Construção do Painel Gráfico Moderno                             |
//+------------------------------------------------------------------+
void CriarPainelModerno() {
   int x = 20; int y = 20; int w = 320; int h = 520;
   CreateRect(PREFIX+"BG_MAIN", x, y, w, h, cor_bg_main, cor_border);
   CreateRect(PREFIX+"BG_HEADER", x, y, w, 40, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"TITLE", "BURGO SCALPE PRO V40", x+15, y+12, cor_text_main, 12, "Arial Bold");
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

//+------------------------------------------------------------------+
//| Atualização dos Valores Exibidos no Painel                       |
//+------------------------------------------------------------------+
void AtualizarValoresPainel(double floating, double bal, double eq, int tBuy, int tSell, double pBuy, double pSell) {
   if (Panel_Minimized) return;
   datetime time = TimeCurrent();
   ObjectSetString(0, PREFIX+"VAL_TIME", OBJPROP_TEXT, TimeToString(time, TIME_MINUTES|TIME_SECONDS));
   
   long seconds_left = SeriesInfoInteger(_Symbol, InpTimeframe, SERIES_LASTBAR_DATE) + PeriodSeconds(InpTimeframe) - TimeCurrent();
   if(seconds_left < 0) seconds_left = 0;
   ObjectSetString(0, PREFIX+"VAL_CANDLE", OBJPROP_TEXT, StringFormat("%02d:%02d", seconds_left / 60, seconds_left % 60));
   
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   ObjectSetString(0, PREFIX+"VAL_SPREAD", OBJPROP_TEXT, IntegerToString(spread));
   
   color floatColor = (floating > 0.0) ? cor_buy : (floating < 0.0) ? cor_sell : cor_text_main;
   ObjectSetString(0, PREFIX+"VAL_FLOAT", OBJPROP_TEXT, StringFormat("$%.2f", floating));
   ObjectSetInteger(0, PREFIX+"VAL_FLOAT", OBJPROP_COLOR, floatColor);
   
   ObjectSetString(0, PREFIX+"VAL_BAL", OBJPROP_TEXT, StringFormat("Bal: $%.2f", bal));
   
   color profitColor = (daily_profit > 0.0) ? cor_buy : (daily_profit < 0.0) ? cor_sell : cor_text_main;
   ObjectSetString(0, PREFIX+"VAL_PROFIT", OBJPROP_TEXT, StringFormat("$%.2f", daily_profit));
   ObjectSetInteger(0, PREFIX+"VAL_PROFIT", OBJPROP_COLOR, profitColor);
   
   ObjectSetString(0, PREFIX+"VAL_TOTAL", OBJPROP_TEXT, StringFormat("Total: $%.2f", total_profit));
   ObjectSetString(0, PREFIX+"VAL_BUY_ORD", OBJPROP_TEXT, StringFormat("%d ($%.2f)", tBuy, pBuy));
   ObjectSetString(0, PREFIX+"VAL_SELL_ORD", OBJPROP_TEXT, StringFormat("%d ($%.2f)", tSell, pSell));
   
   double win_rate = (total_trades > 0) ? ((double)win_trades / total_trades) * 100.0 : 0.0;
   double loss_rate = (total_trades > 0) ? ((double)loss_trades / total_trades) * 100.0 : 0.0;
   double profit_pct = (bal > 0.0) ? (total_profit / bal) * 100.0 : 0.0;
   
   ObjectSetString(0, PREFIX+"VAL_TRADES", OBJPROP_TEXT, StringFormat("Total Trades: %d", total_trades));
   ObjectSetString(0, PREFIX+"VAL_WINS", OBJPROP_TEXT, StringFormat("Wins: %d (%.1f%%)", win_trades, win_rate));
   ObjectSetString(0, PREFIX+"VAL_LOSSES", OBJPROP_TEXT, StringFormat("Losses: %d (%.1f%%)", loss_trades, loss_rate));
   ObjectSetString(0, PREFIX+"VAL_PROFIT_PCT", OBJPROP_TEXT, StringFormat("Profit %%: %.2f%%", profit_pct));
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Controle de Visibilidade e Minimização do Painel                 |
//+------------------------------------------------------------------+
void AtualizarVisibilidadePainel() {
   bool show = !Panel_Minimized;
   ObjectSetInteger(0, PREFIX+"BG_MAIN", OBJPROP_YSIZE, show ? 520 : 40);
   string objs[] = {"LBL_TIME", "VAL_TIME", "LBL_CANDLE", "VAL_CANDLE", "LBL_SPREAD", "VAL_SPREAD", "LBL_STATUS", "VAL_STATUS", "BTN_BUY", "BTN_SELL", "BTN_CLEAN", "BTN_PANIC", "BTN_CLOSE_ALL", "CARD1", "LBL_FLOAT", "VAL_FLOAT", "VAL_BAL", "CARD2", "LBL_PROFIT", "VAL_PROFIT", "VAL_TOTAL", "CARD3", "LBL_ORDERS", "LBL_BUY_ORD", "VAL_BUY_ORD", "LBL_SELL_ORD", "VAL_SELL_ORD", "CARD4", "LBL_STATS", "VAL_TRADES", "VAL_WINS", "VAL_LOSSES", "VAL_PROFIT_PCT", "BG_FOOTER", "LBL_POWER", "BTN_REMOVE"};
   for(int i = 0; i < ArraySize(objs); i++) {
      if(ObjectFind(0, PREFIX+objs[i]) >= 0) ObjectSetInteger(0, PREFIX+objs[i], OBJPROP_TIMEFRAMES, show ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   }
}

//+------------------------------------------------------------------+
//| Criação de Elementos Gráficos Básicos                            |
//+------------------------------------------------------------------+
void CreateRect(string name, int x, int y, int w, int h, color bg, color border) {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y); ObjectSetInteger(0, name, OBJPROP_XSIZE, w); ObjectSetInteger(0, name, OBJPROP_YSIZE, h); ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg); ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border); ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER); ObjectSetInteger(0, name, OBJPROP_BACK, false); ObjectSetInteger(0, name, OBJPROP_ZORDER, 100); ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawLabel(string name, string text, int x, int y, color clr, int size, string font) {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y); ObjectSetString(0, name, OBJPROP_TEXT, text); ObjectSetInteger(0, name, OBJPROP_COLOR, clr); ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size); ObjectSetString(0, name, OBJPROP_FONT, font); ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER); ObjectSetInteger(0, name, OBJPROP_BACK, false); ObjectSetInteger(0, name, OBJPROP_ZORDER, 101); ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void CreateButton(string name, string text, int x, int y, int w, int h, color bg, color fg) {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y); ObjectSetInteger(0, name, OBJPROP_XSIZE, w); ObjectSetInteger(0, name, OBJPROP_YSIZE, h); ObjectSetString(0, name, OBJPROP_TEXT, text); ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg); ObjectSetInteger(0, name, OBJPROP_COLOR, fg); ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER); ObjectSetInteger(0, name, OBJPROP_BACK, false); ObjectSetInteger(0, name, OBJPROP_ZORDER, 102); ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, name, OBJPROP_HIDDEN, true); ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold"); ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
}
//+------------------------------------------------------------------+