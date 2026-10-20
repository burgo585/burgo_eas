//+------------------------------------------------------------------+
//|                                             Burgo Scalpe Pro.mq5 |
//|                                    Copyright 2026, DevMaster Pro |
//|  V43.1 - BLINDAGEM DE EXECUÇÃO + CORREÇÃO TRAILING + STOP CESTA  |
//+------------------------------------------------------------------+
#property copyright "DevMaster Pro"
#property version   "43.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// --- INPUTS ---
input group "==== MOTOR DE GIRO ===="
input double  InpInitialLot       = 0.01;      // Lote Inicial de Giro
input double  InpTargetSideUSD    = 5.00;      // Alvo de cada giro p/ limpeza ($)
input double  InpTargetGlobalUSD  = 10.00;     // Alvo para reset total da conta ($)
input int     InpMagicNumber      = 888123;    // Magic Number do Grid
input int     InpHedgeMagicNumber = 888124;    // Magic Number do Hedge

input group "==== LIMITE DE SEGURANÇA E PROGRESSÃO ===="
input int     InpBaseDistance     = 1500;       // Distância base em pontos (500 pts = $5.00 no Ouro)
input double  InpLotMultiplier    = 1.0;       // Multiplicador real de lote do Grid
input int     InpMaxMartingale    = 6;         // Limite máximo de níveis para aumento de lote
input int     InpMaxTotalOrders   = 3;        // Máximo absoluto de ordens por lado
input double  InpMaxAllowedLot    = 1.50;      // Lote máximo absoluto por ordem
input int     InpMaxSpread        = 60;        // Spread Máximo em Pontos (0 = Desativado)

input group "==== STOP LOSS FINANCEIRO DA CESTA (ANTI-QUEBRA) ===="
input bool    InpUseMaxLossUSD    = true;      // Ativar Stop Loss Financeiro Máximo
input double  InpMaxLossUSD       = 10.00;     // Prejuízo Máximo Flutuante ($) para Stop Geral
input int     InpCooldownMinutes  = 60;        // Pausa (Cooldown) em minutos após Stop da Cesta
input double  InpMaxDailyLossUSD  = 160.00;    // Prejuízo Máximo Diário ($) para Trava Anti-Quebra (0=Desativado)
input bool    InpNewBarOnly       = true;      // Abrir novo giro inicial apenas na abertura de nova barra

input group "==== FILTRO DE TENDÊNCIA INSTITUCIONAL (ANTI-CONTRA-TENDÊNCIA) ===="
input bool            InpUseTrendFilter = true;     // Ativar Filtro de Tendência (False p/ Ouro, True p/ Forex)
input ENUM_TIMEFRAMES InpTrendTF        = PERIOD_M15; // Timeframe da Média (H1 recomendado)
input int             InpTrendEMAPeriod = 200;       // Período da Média Móvel (EMA 200)

input group "==== HEDGE DINÂMICO DE RECUPERAÇÃO ===="
input bool    InpUseTrendHedge    = true;      // Ativar Hedge de Defesa
input int     InpHedgeTriggerLvl  = 5;         // Nível do grid que ativa o Hedge
input double  InpHedgeLotRatio    = 0.8;       // Proporção do lote de hedge em relação ao grid preso
input double  InpHedgeTargetUSD   = 8.00;      // Alvo de lucro em $ para encerrar o Hedge com ganho

input group "==== FILTROS DINÂMICOS (ATR) ===="
input ENUM_TIMEFRAMES InpTimeframe= PERIOD_M15;// Timeframe do ATR
input bool    InpUseATR           = true;      // Usar ATR para distância dinâmica
input int     InpATRPeriod        = 14;        // Período do ATR
input double  InpATRMultiplier    = 1.5;       // Multiplicador do ATR

input group "==== TRAILING STOP DE LUCRO ===="
input bool    InpUseTrailingStop  = false;     // Ativar Trailing Stop (False = Alvo Fixo Recomendado no Ouro)
input double  InpTrailingStartUSD = 5.00;      // Lucro mínimo para iniciar trailing ($)
input double  InpTrailingDropPct  = 10.0;      // % de recuo tolerado antes de fechar

input group "==== HORÁRIOS E PROTEÇÃO DE FIM DE SEMANA ===="
input string  InpStartTime        = "04:00";   // Início das operações (04:00 server time)
input string  InpEndTime          = "18:00";   // Fim das operações diárias (18:00 server time)
input bool    InpFridayFilter     = true;      // Não abrir novos giros na sexta à tarde (após 17:00)

// Globais
CTrade        trade;
CTrade        tradeHedge;
CPositionInfo posInfo;
string        PREFIX = "BSP_";
int           atrHandle = INVALID_HANDLE;
int           trendEmaHandle = INVALID_HANDLE;

bool          EA_Active = true;
bool          Panel_Minimized = false;
bool          HedgeActive = false;
ulong         lastStatsUpdateTime = 0;
ulong         lastUIUpdate = 0;
datetime      lastOrderTime = 0;
int           lastHedgeTriggerLevel = 0;
datetime      cooldownUntilTime = 0;
datetime      lastBarTime = 0;

// Paleta de Cores do Painel
color cor_bg_main     = C'15,23,42';    
color cor_bg_panel    = C'30,41,59';    
color cor_border      = C'51,65,85';    
color cor_text_main   = C'241,245,249'; 
color cor_text_muted  = C'148,163,184'; 
color cor_accent      = C'56,189,248';  
color cor_buy         = C'34,197,94';   
color cor_sell        = C'239,68,68';   
color cor_warning     = C'245,158,11';  

double total_profit = 0;
double daily_profit = 0;
int total_trades = 0;
int win_trades = 0;
int loss_trades = 0;

double max_buy_profit = 0;
double max_sell_profit = 0;
double max_global_profit = 0;

void CreateRect(string name, int x, int y, int w, int h, color bg, color border);
void DrawLabel(string name, string text, int x, int y, color clr, int size, string font);
void CreateButton(string name, string text, int x, int y, int w, int h, color bg, color fg);
void AtualizarVisibilidadePainel();
void AtualizarValoresPainel(double floating, double bal, double eq, int tBuy, int tSell, double pBuy, double pSell);
void FecharLucrativas();
bool TentarReciclar(double lucroDisponivel, ENUM_POSITION_TYPE ladoPerdedor);
void FecharLado(ENUM_POSITION_TYPE type);
void FecharTudo();
void FecharHedges();
void CriarPainelModerno();
double NormalizarLote(double lot);

double NormalizarLote(double lot) {
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(step <= 0)   step = 0.01;
   if(minLot <= 0) minLot = 0.01;
   if(maxLot <= 0) maxLot = 100.0;
   
   lot = MathFloor(lot / step + 0.0000001) * step;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   
   return NormalizeDouble(lot, 2);
}

double CalcularProximoLote(double lastLot, int totalOrders);

int ObterDirecaoTendencia() {
   if(!InpUseTrendFilter || trendEmaHandle == INVALID_HANDLE) return 0;
   
   double ema[1];
   if(CopyBuffer(trendEmaHandle, 0, 1, 1, ema) <= 0) return 0;
   
   double closePrice = iClose(_Symbol, InpTrendTF, 1);
   if(closePrice > ema[0]) return 1;  // Tendência de Alta
   if(closePrice < ema[0]) return -1; // Tendência de Baixa
   return 0;
}

bool IsTradingTime() {
   datetime time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(time, dt);
   
   // Proteção de Sexta-Feira: Não abre novos giros na sexta à tarde
   if(InpFridayFilter && dt.day_of_week == 5 && dt.hour >= 17) {
      return false;
   }
   
   int current_mins = dt.hour * 60 + dt.min;
   
   string start_arr[];
   StringSplit(InpStartTime, ':', start_arr);
   int start_mins = (int)StringToInteger(start_arr[0]) * 60 + (int)StringToInteger(start_arr[1]);
   
   string end_arr[];
   StringSplit(InpEndTime, ':', end_arr);
   int end_mins = (int)StringToInteger(end_arr[0]) * 60 + (int)StringToInteger(end_arr[1]);
   
   if (start_mins < end_mins) {
      return (current_mins >= start_mins && current_mins <= end_mins);
   } else {
      return (current_mins >= start_mins || current_mins <= end_mins);
   }
}

double GetDynamicDistance() {
   double baseDist = InpBaseDistance * _Point;
   if(!InpUseATR || atrHandle == INVALID_HANDLE) return baseDist;
   
   double atr[1];
   if(CopyBuffer(atrHandle, 0, 1, 1, atr) <= 0) return baseDist;
   
   double dist = atr[0] * InpATRMultiplier;
   if(dist < baseDist * 0.8) dist = baseDist * 0.8;
   return dist;
}

void CalculateStats(bool force = false) {
   ulong now = GetTickCount64();
   if(!force && (now - lastStatsUpdateTime < 3000)) return;
   lastStatsUpdateTime = now;

   total_profit = 0;
   daily_profit = 0;
   total_trades = 0;
   win_trades = 0;
   loss_trades = 0;
   
   datetime today = TimeCurrent() - (TimeCurrent() % 86400);
   HistorySelect(today - 30 * 86400, TimeCurrent());
   int deals = HistoryDealsTotal();
   
   for(int i=0; i<deals; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if(magic == InpMagicNumber || magic == InpHedgeMagicNumber) {
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

void ProcessTrailingStop(double buyProfit, double sellProfit, double totalFloating, int totalBuy, int totalSell) {
   if(!InpUseTrailingStop) return;
   
   // Trailing Global
   if(totalFloating >= InpTargetGlobalUSD || max_global_profit > 0) {
      if(totalFloating > max_global_profit) max_global_profit = totalFloating;
      double dropAmount = max_global_profit * (InpTrailingDropPct / 100.0);
      if((max_global_profit - totalFloating >= dropAmount) || (totalFloating <= InpTargetGlobalUSD * 0.85)) {
         FecharTudo();
         max_global_profit = 0;
         Print("Trailing Stop Global Acionado!");
         return;
      }
   }
   if(totalBuy == 0 && totalSell == 0) max_global_profit = 0;

   // Trailing Buy (Mantém-se armado uma vez atingido o alvo até fechar)
   if(buyProfit >= InpTrailingStartUSD || max_buy_profit > 0) {
      if(buyProfit > max_buy_profit) max_buy_profit = buyProfit;
      double dropAmount = max_buy_profit * (InpTrailingDropPct / 100.0);
      if((max_buy_profit - buyProfit >= dropAmount) || (buyProfit <= InpTrailingStartUSD * 0.85)) {
         FecharLado(POSITION_TYPE_BUY);
         max_buy_profit = 0;
         Print("Trailing Stop Acionado: COMPRA");
      }
   }
   if(totalBuy == 0) max_buy_profit = 0;
   
   // Trailing Sell (Mantém-se armado uma vez atingido o alvo até fechar)
   if(sellProfit >= InpTrailingStartUSD || max_sell_profit > 0) {
      if(sellProfit > max_sell_profit) max_sell_profit = sellProfit;
      double dropAmount = max_sell_profit * (InpTrailingDropPct / 100.0);
      if((max_sell_profit - sellProfit >= dropAmount) || (sellProfit <= InpTrailingStartUSD * 0.85)) {
         FecharLado(POSITION_TYPE_SELL);
         max_sell_profit = 0;
         Print("Trailing Stop Acionado: VENDA");
      }
   }
   if(totalSell == 0) max_sell_profit = 0;
}

void GerenciarHedgeTendencia(int totalBuy, int totalSell, double totalBuyVol, double totalSellVol) {
   if(!InpUseTrendHedge) return;

   int hedgesAbertos = 0;
   double hedgeProfit = 0;
   ulong hedgeTicket = 0;
   
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpHedgeMagicNumber) {
         hedgesAbertos++;
         hedgeTicket = posInfo.Ticket();
         hedgeProfit += posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
      }
   }
   HedgeActive = (hedgesAbertos > 0);

   // Realização de Lucro do Hedge independente: se o Hedge atingir o alvo, realiza o lucro!
   if(HedgeActive && hedgeProfit >= InpHedgeTargetUSD) {
      tradeHedge.PositionClose(hedgeTicket);
      HedgeActive = false;
      Print("HEDGE REALIZADO COM LUCRO: Ganho de $", hedgeProfit, " colocado no bolso.");
      return;
   }

   // Grid de Vendas sobrecarregado -> abre Hedge de Compra (uma única vez por nível)
   if(totalSell >= InpHedgeTriggerLvl && totalSell > lastHedgeTriggerLevel && !HedgeActive) {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double hedgeLot = NormalizarLote(totalSellVol * InpHedgeLotRatio);
      if(hedgeLot > InpMaxAllowedLot) hedgeLot = InpMaxAllowedLot;
      
      if(tradeHedge.Buy(hedgeLot, _Symbol, ask, 0, 0, "Hedge Trend Buy")) {
         HedgeActive = true;
         lastHedgeTriggerLevel = totalSell;
         Print("HEDGE ATIVADO: Defesa Buy aberta com lote ", hedgeLot);
      }
   }
   
   // Grid de Compras sobrecarregado -> abre Hedge de Venda (uma única vez por nível)
   if(totalBuy >= InpHedgeTriggerLvl && totalBuy > lastHedgeTriggerLevel && !HedgeActive) {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double hedgeLot = NormalizarLote(totalBuyVol * InpHedgeLotRatio);
      if(hedgeLot > InpMaxAllowedLot) hedgeLot = InpMaxAllowedLot;
      
      if(tradeHedge.Sell(hedgeLot, _Symbol, bid, 0, 0, "Hedge Trend Sell")) {
         HedgeActive = true;
         lastHedgeTriggerLevel = totalBuy;
         Print("HEDGE ATIVADO: Defesa Sell aberta com lote ", hedgeLot);
      }
   }

   // Se o grid principal foi zerado, encerra os hedges remanescentes e reseta a trava
   if(totalBuy == 0 && totalSell == 0) {
      if(HedgeActive) FecharHedges();
      HedgeActive = false;
      lastHedgeTriggerLevel = 0;
   }
}

void OnTick() {
   CalculateStats(false);
   
   // Proteção contra Spread Alargado (Roll-over noturno / notícias)
   if(InpMaxSpread > 0 && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpread) {
      return;
   }
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double totalFloating = equity - balance;

   // =================================================================
   // 1. TRAVA DE SEGURANÇA: STOP LOSS FINANCEIRO MÁXIMO DA CESTA
   // =================================================================
   if(InpUseMaxLossUSD && totalFloating <= -MathAbs(InpMaxLossUSD)) {
      PrintFormat("STOP LOSS FINANCEIRO ACIONADO! Flutuante -$%.2f atingiu o limite de -$%.2f. Encerrando cesta.",
                  MathAbs(totalFloating), MathAbs(InpMaxLossUSD));
      FecharTudo();
      if(InpCooldownMinutes > 0) {
         cooldownUntilTime = TimeCurrent() + (InpCooldownMinutes * 60);
         PrintFormat("COOLDOWN ATIVADO: Aguardando %d minutos até %s para novos giros.",
                     InpCooldownMinutes, TimeToString(cooldownUntilTime, TIME_MINUTES|TIME_SECONDS));
      }
      return;
   }

   // Fechamento por Alvo Global Fixo
   if(!InpUseTrailingStop && totalFloating >= InpTargetGlobalUSD) { 
       FecharTudo(); 
       return;
   }

   int totalBuy=0, totalSell=0;
   double buyProfit=0, sellProfit=0;
   double lowestBuyPrice=DBL_MAX, highestSellPrice=0;
   double lastBuyLot=InpInitialLot, lastSellLot=InpInitialLot;
   double totalBuyVol=0, totalSellVol=0;

   // Contabiliza APENAS ordens do Magic Number Principal (Grid)
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==_Symbol && posInfo.Magic()==InpMagicNumber) {
         double p = posInfo.Profit() + posInfo.Commission() + posInfo.Swap();
         if(posInfo.PositionType()==POSITION_TYPE_BUY) {
            totalBuy++; 
            buyProfit += p; 
            totalBuyVol += posInfo.Volume();
            if(posInfo.PriceOpen() < lowestBuyPrice) { 
               lowestBuyPrice = posInfo.PriceOpen(); 
               lastBuyLot = posInfo.Volume(); 
            }
         } else {
            totalSell++; 
            sellProfit += p; 
            totalSellVol += posInfo.Volume();
            if(posInfo.PriceOpen() > highestSellPrice) { 
               highestSellPrice = posInfo.PriceOpen(); 
               lastSellLot = posInfo.Volume(); 
            }
         }
      }
   }

   // Gerenciamento de Hedge Independente
   GerenciarHedgeTendencia(totalBuy, totalSell, totalBuyVol, totalSellVol);

   if (EA_Active) {
      // Reciclagem ativa
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

      // Fechamento de Lucro (Fixo por Lado ou Trailing Stop) - Opera a qualquer momento para proteger o capital
      if(!InpUseTrailingStop) {
          if(buyProfit >= InpTargetSideUSD)  FecharLado(POSITION_TYPE_BUY);
          if(sellProfit >= InpTargetSideUSD) FecharLado(POSITION_TYPE_SELL);
      } else {
          ProcessTrailingStop(buyProfit, sellProfit, totalFloating, totalBuy, totalSell);
      }

      if (IsTradingTime()) {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         int trendDir = ObterDirecaoTendencia();

         // Proteções Anti-Quebra para abertura de NOVOS giros
         bool inCooldown = (cooldownUntilTime > 0 && TimeCurrent() < cooldownUntilTime);
         bool hitDailyLoss = (InpMaxDailyLossUSD > 0 && daily_profit <= -MathAbs(InpMaxDailyLossUSD));
         datetime currentBar = iTime(_Symbol, _Period, 0);
         bool isNewBar = (currentBar != lastBarTime);
         bool canOpenGiro = (!inCooldown && !hitDailyLoss && (!InpNewBarOnly || isNewBar) && (TimeCurrent() - lastOrderTime >= 2));

         // ENTRADAS DE GIRO INICIAL
         if(canOpenGiro && totalBuy == 0 && (trendDir >= 0)) {
            if(trade.Buy(NormalizarLote(InpInitialLot), _Symbol, ask, 0, 0, "Giro Buy")) {
               lastOrderTime = TimeCurrent();
               lastBarTime = currentBar;
            }
         }
         if(canOpenGiro && totalSell == 0 && (trendDir <= 0)) {
            if(trade.Sell(NormalizarLote(InpInitialLot), _Symbol, bid, 0, 0, "Giro Sell")) {
               lastOrderTime = TimeCurrent();
               lastBarTime = currentBar;
            }
         }

         double currentDistance = GetDynamicDistance();
         bool canOpenGrid = (TimeCurrent() - lastOrderTime >= 2);
         
         // GRADE DE COMPRA COM MULTIPLICADOR REAL
         if(canOpenGrid && totalBuy > 0 && totalBuy < InpMaxTotalOrders && ask < (lowestBuyPrice - currentDistance)) {
            double nextLot = CalcularProximoLote(lastBuyLot, totalBuy);
            if(trade.Buy(nextLot, _Symbol, ask, 0, 0, "Grid Buy")) {
               lastOrderTime = TimeCurrent();
            }
         }

         // GRADE DE VENDA COM MULTIPLICADOR REAL
         if(canOpenGrid && totalSell > 0 && totalSell < InpMaxTotalOrders && bid > (highestSellPrice + currentDistance)) {
            double nextLot = CalcularProximoLote(lastSellLot, totalSell);
            if(trade.Sell(nextLot, _Symbol, bid, 0, 0, "Grid Sell")) {
               lastOrderTime = TimeCurrent();
            }
         }
      }
   }

   // Throttling de atualização do Painel Gráfico (máximo a cada 500ms para evitar travamentos)
   if(GetTickCount64() - lastUIUpdate >= 500) {
      AtualizarValoresPainel(totalFloating, balance, equity, totalBuy, totalSell, buyProfit, sellProfit);
      lastUIUpdate = GetTickCount64();
   }
}

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
      }
      else if(sparam == PREFIX+"BTN_BUY") {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         trade.Buy(NormalizarLote(InpInitialLot), _Symbol, ask, 0, 0, "Manual Buy");
      }
      else if(sparam == PREFIX+"BTN_SELL") {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         trade.Sell(NormalizarLote(InpInitialLot), _Symbol, bid, 0, 0, "Manual Sell");
      }
      else if(sparam == PREFIX+"BTN_CLEAN") {
         FecharLucrativas();
      }
      else if(sparam == PREFIX+"BTN_PANIC") {
         FecharTudo();
         EA_Active = false;
         ObjectSetString(0, PREFIX+"BTN_POWER", OBJPROP_TEXT, "OFF");
         ObjectSetInteger(0, PREFIX+"BTN_POWER", OBJPROP_BGCOLOR, cor_sell);
         ObjectSetString(0, PREFIX+"VAL_STATUS", OBJPROP_TEXT, "Paused");
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

bool TentarReciclar(double lucroDisponivel, ENUM_POSITION_TYPE ladoPerdedor) {
   ulong ticketPiorOrdem = 0;
   double maiorPrejuizo = 0;

   for(int i=0; i<PositionsTotal(); i++) {
      if(posInfo.SelectByIndex(i) && posInfo.Magic()==InpMagicNumber && posInfo.PositionType()==ladoPerdedor) {
         double perda = posInfo.Profit() + posInfo.Commission() + posInfo.Swap();
         if(perda < maiorPrejuizo) {
            maiorPrejuizo = perda;
            ticketPiorOrdem = posInfo.Ticket();
         }
      }
   }

   if(ticketPiorOrdem > 0 && lucroDisponivel > MathAbs(maiorPrejuizo)) {
      if(trade.PositionClose(ticketPiorOrdem)) {
         Print("RECICLAGEM SUCESSO: Ordem ticket #", ticketPiorOrdem, " eliminada com lucro oposto.");
         return true;
      }
   }
   return false;
}

void FecharLado(ENUM_POSITION_TYPE type) {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==_Symbol && posInfo.Magic()==InpMagicNumber) {
         if(posInfo.PositionType()==type) trade.PositionClose(posInfo.Ticket());
      }
   }
}

void FecharHedges() {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==_Symbol && posInfo.Magic()==InpHedgeMagicNumber) {
         tradeHedge.PositionClose(posInfo.Ticket());
      }
   }
}

void FecharTudo() {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==_Symbol) {
         if(posInfo.Magic()==InpMagicNumber || posInfo.Magic()==InpHedgeMagicNumber) {
            trade.PositionClose(posInfo.Ticket());
         }
      }
   }
   HedgeActive = false;
   max_global_profit = 0;
   max_buy_profit = 0;
   max_sell_profit = 0;
}

void FecharLucrativas() {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==_Symbol && posInfo.Magic()==InpMagicNumber) {
         double p = posInfo.Profit() + posInfo.Commission() + posInfo.Swap();
         if(p > 0) trade.PositionClose(posInfo.Ticket());
      }
   }
}

void CriarPainelModerno() {
   int x = 20, y = 20, w = 320, h = 520;
   CreateRect(PREFIX+"BG_MAIN", x, y, w, h, cor_bg_main, cor_border);
   CreateRect(PREFIX+"BG_HEADER", x, y, w, 40, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"TITLE", "BURGO SCALPE V43 PRO", x+15, y+12, cor_text_main, 12, "Arial Bold");
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

   long seconds_left = SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE) + PeriodSeconds(_Period) - TimeCurrent();
   if(seconds_left < 0) seconds_left = 0;
   ObjectSetString(0, PREFIX+"VAL_CANDLE", OBJPROP_TEXT, StringFormat("%02d:%02d", seconds_left / 60, seconds_left % 60));

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
                    "LBL_STATUS", "VAL_STATUS", "BTN_BUY", "BTN_SELL", "BTN_CLEAN", "BTN_PANIC", 
                    "CARD1", "LBL_FLOAT", "VAL_FLOAT", "VAL_BAL", 
                    "CARD2", "LBL_PROFIT", "VAL_PROFIT", "VAL_TOTAL",
                    "CARD3", "LBL_ORDERS", "LBL_BUY_ORD", "VAL_BUY_ORD", "LBL_SELL_ORD", "VAL_SELL_ORD",
                    "CARD4", "LBL_STATS", "VAL_TRADES", "VAL_WINS", "VAL_LOSSES", "VAL_PROFIT_PCT",
                    "BG_FOOTER", "LBL_POWER", "BTN_REMOVE"};
                    
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
