//+------------------------------------------------------------------+
//|                                             Burgo Scalpe Pro.mq5 |
//|                                    Copyright 2024, DevMaster Pro |
//|      V41 - ANTI-OSCILAÇÃO: ADX + COOLDOWN + RECICLAGEM SMART    |
//+------------------------------------------------------------------+
#property copyright "DevMaster Pro"
#property version   "41.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// --- INPUTS ---
input group "==== MOTOR DE GIRO ===="
input double  InpInitialLot       = 0.02;      
input double  InpTargetSideUSD    = 2.00;      // Alvo de cada giro p/ limpeza
input double  InpTargetGlobalUSD  = 20.00;     // Alvo para reset total da conta
input int     InpMagicNumber      = 888123;

input group "==== LIMITE DE SEGURANÇA ===="
input int     InpBaseDistance     = 600;       
input double  InpLotMultiplier    = 1.5;       
input int     InpMaxMartingale    = 8;         // PARA de aumentar lote após o 8º nível
input int     InpMaxTotalOrders   = 15;        // Máximo absoluto de ordens

input group "==== FILTROS AVANÇADOS ===="
input ENUM_TIMEFRAMES InpTimeframe    = PERIOD_CURRENT; // Timeframe do Gráfico
input bool    InpUseATR           = true;      // Usar ATR para Distância Dinâmica
input int     InpATRPeriod        = 14;        // Período do ATR
input double  InpATRMultiplier    = 1.5;       // Multiplicador do ATR

input group "==== FILTRO ANTI-OSCILAÇÃO ====" // ◄ NOVO
input bool    InpUseADX           = true;      // Usar ADX para bloquear grid em mercado lateral
input int     InpADXPeriod        = 14;        // Período do ADX
input double  InpADXThreshold     = 20.0;      // ADX abaixo disso = mercado lateral (grid pausado)
input int     InpCooldownBars     = 3;         // Barras de espera após fechar um lado
input double  InpMaxDrawdownPct   = 15.0;      // Drawdown máx (%) para pausar grid (0=desativado)

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
int           PM = 1;
string        PREFIX = "BSP_";
int           atrHandle;
int           adxHandle;       // ◄ NOVO

bool          EA_Active = true;
bool          Panel_Minimized = false;
bool          RuntimeUseATR;
bool          RuntimeUseADX;   // ◄ NOVO: toggle dinâmico do ADX

// ◄ NOVO: Anti-Oscilação
datetime      lastBuyCloseTime  = 0;  // Timestamp do último fechamento do lado BUY
datetime      lastSellCloseTime = 0;  // Timestamp do último fechamento do lado SELL
double        currentADX        = 0;  // Valor atual do ADX para exibição no painel
bool          gridBlocked       = false;
string        gridBlockReason   = "";

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
color cor_purple      = C'168,85,247';

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

// Declaração das funções de UI
void CreateRect(string name, int x, int y, int w, int h, color bg, color border);
void DrawLabel(string name, string text, int x, int y, color clr, int size, string font);
void CreateButton(string name, string text, int x, int y, int w, int h, color bg, color fg);
void AtualizarVisibilidadePainel();
void AtualizarValoresPainel(double floating, double bal, double eq, int tBuy, int tSell, double pBuy, double pSell);
void FecharLucrativas();
void ExecutarHedge();

//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(InpMagicNumber);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   PM = (digits >= 3) ? 10 : 1;
   
   // ATR
   atrHandle = iATR(_Symbol, InpTimeframe, InpATRPeriod);
   if(atrHandle == INVALID_HANDLE) {
      Print("Erro ao carregar indicador ATR.");
      return(INIT_FAILED);
   }
   
   // ◄ NOVO: ADX
   adxHandle = iADX(_Symbol, InpTimeframe, InpADXPeriod);
   if(adxHandle == INVALID_HANDLE) {
      Print("Erro ao carregar indicador ADX.");
      return(INIT_FAILED);
   }
   
   RuntimeUseATR = InpUseATR;
   RuntimeUseADX = InpUseADX;  // ◄ NOVO
   
   CriarPainelModerno();
   
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { 
   ObjectsDeleteAll(0, PREFIX); 
   IndicatorRelease(atrHandle);
   IndicatorRelease(adxHandle);  // ◄ NOVO
   ChartRedraw();
}

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
   
   if (start_mins < end_mins) {
      return (current_mins >= start_mins && current_mins <= end_mins);
   } else {
      return (current_mins >= start_mins || current_mins <= end_mins);
   }
}

double GetDynamicDistance() {
   if(!RuntimeUseATR) return InpBaseDistance * PM * _Point;
   
   double atr[];
   if(CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0) return InpBaseDistance * PM * _Point;
   double dist = atr[0] * InpATRMultiplier;
   
   // ◄ MODIFICADO: Piso aumentado de 50% para 75% da distância base
   double minDist = (InpBaseDistance * 0.75) * PM * _Point;
   if(dist < minDist) dist = minDist;
   
   return dist;
}

//+------------------------------------------------------------------+
//| ◄ NOVO: Verifica se o grid pode expandir (ADX + Drawdown)        |
//+------------------------------------------------------------------+
bool IsGridAllowed(double balance, double totalFloating) {
   gridBlocked = false;
   gridBlockReason = "";
   
   // Leitura do ADX (sempre atualiza para exibição no painel)
   double adxBuf[];
   if(CopyBuffer(adxHandle, 0, 0, 1, adxBuf) > 0)
      currentADX = adxBuf[0];
   else
      currentADX = 0;
   
   // Filtro ADX: mercado lateral bloqueia expansão do grid
   if(RuntimeUseADX) {
      if(currentADX < InpADXThreshold) {
         gridBlocked = true;
         gridBlockReason = StringFormat("ADX %.1f < %.1f", currentADX, InpADXThreshold);
         return false;
      }
   }
   
   // Filtro Drawdown: perda flutuante excessiva bloqueia grid
   if(InpMaxDrawdownPct > 0 && balance > 0 && totalFloating < 0) {
      double ddPct = MathAbs(totalFloating) / balance * 100.0;
      if(ddPct >= InpMaxDrawdownPct) {
         gridBlocked = true;
         gridBlockReason = StringFormat("DD %.1f%% >= %.1f%%", ddPct, InpMaxDrawdownPct);
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| ◄ NOVO: Verifica cooldown após fechamento de um lado             |
//+------------------------------------------------------------------+
bool IsCooldownOk(ENUM_POSITION_TYPE side) {
   if(InpCooldownBars <= 0) return true;
   
   datetime closeTime = (side == POSITION_TYPE_BUY) ? lastBuyCloseTime : lastSellCloseTime;
   if(closeTime == 0) return true;  // Nunca fechou esse lado
   
   int barsPassed = iBarShift(_Symbol, InpTimeframe, closeTime, false);
   if(barsPassed < 0) return true;  // Erro — permite abrir por segurança
   
   return (barsPassed >= InpCooldownBars);
}

void CalculateStats() {
   total_profit = 0;
   daily_profit = 0;
   total_trades = 0;
   win_trades = 0;
   loss_trades = 0;
   
   HistorySelect(0, TimeCurrent());
   int deals = HistoryDealsTotal();
   
   datetime today = TimeCurrent() - (TimeCurrent() % 86400);
   
   for(int i=0; i<deals; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber) {
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_COMMISSION) + HistoryDealGetDouble(ticket, DEAL_SWAP);
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) {
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

void ProcessTrailingStop(double buyProfit, double sellProfit, double totalFloating) {
   if(!InpUseTrailingStop) return;
   
   // Trailing Global
   if(totalFloating >= InpTargetGlobalUSD) {
      if(totalFloating > max_global_profit) max_global_profit = totalFloating;
      
      double dropAmount = max_global_profit * (InpTrailingDropPct / 100.0);
      if(max_global_profit - totalFloating >= dropAmount) {
         FecharTudo();
         max_global_profit = 0;
         Print("Trailing Stop Global Acionado!");
         return;
      }
   } else if(totalFloating < InpTargetGlobalUSD * 0.5) {
      // ◄ MODIFICADO: Só reseta se cair abaixo de 50% do alvo (evita reset prematuro)
      max_global_profit = 0;
   }

   // Trailing Lado Compra
   if(buyProfit >= InpTargetSideUSD) {
      if(buyProfit > max_buy_profit) max_buy_profit = buyProfit;
      
      double dropAmount = max_buy_profit * (InpTrailingDropPct / 100.0);
      if(max_buy_profit - buyProfit >= dropAmount) {
         FecharLado(POSITION_TYPE_BUY);
         max_buy_profit = 0;
         Print("Trailing Stop Acionado: COMPRA");
      }
   } else if(buyProfit < InpTargetSideUSD * 0.5) {
      // ◄ MODIFICADO: Só reseta se cair abaixo de 50% do alvo
      max_buy_profit = 0;
   }
   
   // Trailing Lado Venda
   if(sellProfit >= InpTargetSideUSD) {
      if(sellProfit > max_sell_profit) max_sell_profit = sellProfit;
      
      double dropAmount = max_sell_profit * (InpTrailingDropPct / 100.0);
      if(max_sell_profit - sellProfit >= dropAmount) {
         FecharLado(POSITION_TYPE_SELL);
         max_sell_profit = 0;
         Print("Trailing Stop Acionado: VENDA");
      }
   } else if(sellProfit < InpTargetSideUSD * 0.5) {
      // ◄ MODIFICADO: Só reseta se cair abaixo de 50% do alvo
      max_sell_profit = 0;
   }
}

void OnTick() {
   CalculateStats();
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double totalFloating = equity - balance;

   if(!InpUseTrailingStop && totalFloating >= InpTargetGlobalUSD) { 
       FecharTudo(); 
   }

   int totalBuy=0, totalSell=0;
   double buyProfit=0, sellProfit=0;
   double lastBuyPrice=0, lastSellPrice=0, lastBuyLot=0, lastSellLot=0;

   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==_Symbol && posInfo.Magic()==InpMagicNumber) {
         double p = posInfo.Profit() + posInfo.Commission() + posInfo.Swap();
         if(posInfo.PositionType()==POSITION_TYPE_BUY) {
            totalBuy++; buyProfit += p;
            if(lastBuyPrice==0 || posInfo.PriceOpen()<lastBuyPrice) { lastBuyPrice=posInfo.PriceOpen(); lastBuyLot=posInfo.Volume(); }
         } else {
            totalSell++; sellProfit += p;
            if(lastSellPrice==0 || posInfo.PriceOpen()>lastSellPrice) { lastSellPrice=posInfo.PriceOpen(); lastSellLot=posInfo.Volume(); }
         }
      }
   }

   // ◄ NOVO: Verificar se o grid pode expandir
   bool canExpandGrid = IsGridAllowed(balance, totalFloating);

   if (EA_Active) {
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

      if (IsTradingTime()) {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

         // ◄ MODIFICADO: Abertura inicial agora respeita o cooldown
         if(totalBuy == 0 && IsCooldownOk(POSITION_TYPE_BUY))
            trade.Buy(InpInitialLot, _Symbol, ask, 0, 0, "Giro");
         if(totalSell == 0 && IsCooldownOk(POSITION_TYPE_SELL))
            trade.Sell(InpInitialLot, _Symbol, bid, 0, 0, "Giro");

         if(!InpUseTrailingStop) {
             if(buyProfit >= InpTargetSideUSD)  FecharLado(POSITION_TYPE_BUY);
             if(sellProfit >= InpTargetSideUSD) FecharLado(POSITION_TYPE_SELL);
         }
         
         ProcessTrailingStop(buyProfit, sellProfit, totalFloating);

         double currentDistance = GetDynamicDistance();
         
         // ◄ MODIFICADO: Grid só expande se ADX e Drawdown permitirem
         if(canExpandGrid) {
            if(totalBuy > 0 && totalBuy < InpMaxTotalOrders && ask < (lastBuyPrice - currentDistance)) {
               double nextLot = (totalBuy < InpMaxMartingale) ? NormalizeDouble(lastBuyLot*InpLotMultiplier, 2) : lastBuyLot;
               trade.Buy(nextLot, _Symbol, ask, 0, 0, "Grid");
            }

            if(totalSell > 0 && totalSell < InpMaxTotalOrders && bid > (lastSellPrice + currentDistance)) {
               double nextLot = (totalSell < InpMaxMartingale) ? NormalizeDouble(lastSellLot*InpLotMultiplier, 2) : lastSellLot;
               trade.Sell(nextLot, _Symbol, bid, 0, 0, "Grid");
            }
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
      }
      else if(sparam == PREFIX+"BTN_ATR") {
         RuntimeUseATR = !RuntimeUseATR;
         ObjectSetString(0, PREFIX+"BTN_ATR", OBJPROP_TEXT, RuntimeUseATR ? "ATR:ON" : "ATR:OFF");
         ObjectSetInteger(0, PREFIX+"BTN_ATR", OBJPROP_BGCOLOR, RuntimeUseATR ? cor_buy : cor_sell);
      }
      // ◄ NOVO: Toggle do ADX pelo painel
      else if(sparam == PREFIX+"BTN_ADX") {
         RuntimeUseADX = !RuntimeUseADX;
         ObjectSetString(0, PREFIX+"BTN_ADX", OBJPROP_TEXT, RuntimeUseADX ? "ADX:ON" : "ADX:OFF");
         ObjectSetInteger(0, PREFIX+"BTN_ADX", OBJPROP_BGCOLOR, RuntimeUseADX ? cor_buy : cor_sell);
      }
      else if(sparam == PREFIX+"BTN_HEDGE") {
         ExecutarHedge();
      }
      else if(sparam == PREFIX+"BTN_CLOSE_ALL") {
         FecharTudo();
         Print("CLOSE ALL PRESSED!");
      }
      else if(sparam == PREFIX+"BTN_BUY") {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         trade.Buy(InpInitialLot, _Symbol, ask, 0, 0, "Manual Buy");
      }
      else if(sparam == PREFIX+"BTN_SELL") {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         trade.Sell(InpInitialLot, _Symbol, bid, 0, 0, "Manual Sell");
      }
      else if(sparam == PREFIX+"BTN_CLEAN") {
         FecharLucrativas();
         Print("CLEAN BUTTON PRESSED! Profitable orders closed.");
      }
      else if(sparam == PREFIX+"BTN_PANIC") {
         FecharTudo();
         EA_Active = false;
         ObjectSetString(0, PREFIX+"BTN_POWER", OBJPROP_TEXT, "OFF");
         ObjectSetInteger(0, PREFIX+"BTN_POWER", OBJPROP_BGCOLOR, cor_sell);
         ObjectSetString(0, PREFIX+"VAL_STATUS", OBJPROP_TEXT, "Paused");
         ObjectSetInteger(0, PREFIX+"VAL_STATUS", OBJPROP_COLOR, cor_text_muted);
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

// --- FUNÇÃO HEDGE LOCK DE EMERGÊNCIA ---
void ExecutarHedge() {
   double totalLotsBuy = 0.0;
   double totalLotsSell = 0.0;

   for(int i=0; i<PositionsTotal(); i++) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==_Symbol && posInfo.Magic()==InpMagicNumber) {
         if(posInfo.PositionType() == POSITION_TYPE_BUY) totalLotsBuy += posInfo.Volume();
         else if(posInfo.PositionType() == POSITION_TYPE_SELL) totalLotsSell += posInfo.Volume();
      }
   }

   double deltaLote = NormalizeDouble(MathAbs(totalLotsBuy - totalLotsSell), 2);

   if(deltaLote > 0.0) {
      if(totalLotsBuy > totalLotsSell) {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         trade.Sell(deltaLote, _Symbol, bid, 0, 0, "Hedge Lock Emer.");
      } else {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         trade.Buy(deltaLote, _Symbol, ask, 0, 0, "Hedge Lock Emer.");
      }
      Print("HEDGE LOCK ACIONADO! Volume de balanceamento: ", deltaLote);
   } else {
      Print("HEDGE LOCK: Posição já está neutra.");
   }

   if(EA_Active) {
      EA_Active = false;
      ObjectSetString(0, PREFIX+"BTN_POWER", OBJPROP_TEXT, "OFF");
      ObjectSetInteger(0, PREFIX+"BTN_POWER", OBJPROP_BGCOLOR, cor_sell);
      ObjectSetString(0, PREFIX+"VAL_STATUS", OBJPROP_TEXT, "Paused (Hedge)");
      ObjectSetInteger(0, PREFIX+"VAL_STATUS", OBJPROP_COLOR, cor_warning);
   }
}

//+------------------------------------------------------------------+
//| ◄ MODIFICADO: Reciclagem inteligente — busca menor perda         |
//+------------------------------------------------------------------+
bool TentarReciclar(double lucroDisponivel, ENUM_POSITION_TYPE ladoPerdedor) {
   ulong ticketMelhorOrdem = 0;
   double perdaMelhorOrdem = 0;

   // ◄ MODIFICADO: Percorre TODAS as posições para achar a de menor perda absoluta
   for(int i=0; i<PositionsTotal(); i++) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==_Symbol && posInfo.Magic()==InpMagicNumber && posInfo.PositionType()==ladoPerdedor) {
         double perda = posInfo.Profit() + posInfo.Commission() + posInfo.Swap();
         if(perda < 0) {
            // Seleciona a posição cuja perda absoluta é a MENOR (mais fácil de cobrir)
            if(ticketMelhorOrdem == 0 || MathAbs(perda) < MathAbs(perdaMelhorOrdem)) {
               ticketMelhorOrdem = posInfo.Ticket();
               perdaMelhorOrdem = perda;
            }
         }
      }
   }

   if(ticketMelhorOrdem > 0 && lucroDisponivel > MathAbs(perdaMelhorOrdem)) {
      trade.PositionClose(ticketMelhorOrdem);
      Print("RECICLAGEM SMART: Ordem com menor perda ($", 
            DoubleToString(MathAbs(perdaMelhorOrdem), 2), 
            ") removida usando $", DoubleToString(lucroDisponivel, 2), " do lado oposto.");
      return true;
   }
   return false;
}

// ◄ MODIFICADO: Registra timestamp de cooldown ao fechar lado
void FecharLado(ENUM_POSITION_TYPE type) {
   trade.SetAsyncMode(true);
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==_Symbol && posInfo.Magic()==InpMagicNumber) {
         if(posInfo.PositionType()==type) trade.PositionClose(posInfo.Ticket());
      }
   }
   trade.SetAsyncMode(false);
   
   // ◄ NOVO: Registrar cooldown
   if(type == POSITION_TYPE_BUY)  lastBuyCloseTime  = TimeCurrent();
   else                            lastSellCloseTime = TimeCurrent();
}

// ◄ MODIFICADO: Registra cooldown de ambos os lados
void FecharTudo() {
   trade.SetAsyncMode(true);
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==_Symbol && posInfo.Magic()==InpMagicNumber) {
         trade.PositionClose(posInfo.Ticket());
      }
   }
   trade.SetAsyncMode(false);
   
   // ◄ NOVO: Cooldown em ambos os lados
   lastBuyCloseTime  = TimeCurrent();
   lastSellCloseTime = TimeCurrent();
}

void FecharLucrativas() {
   trade.SetAsyncMode(true);
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol()==_Symbol && posInfo.Magic()==InpMagicNumber) {
         double p = posInfo.Profit() + posInfo.Commission() + posInfo.Swap();
         if(p > 0) trade.PositionClose(posInfo.Ticket());
      }
   }
   trade.SetAsyncMode(false);
}

// --- PAINEL MODERNO ---
void CriarPainelModerno() {
   int x = 20;
   int y = 20;
   int w = 320;
   int h = 600; // ◄ MODIFICADO: Altura expandida para novos elementos

   // Fundo Principal
   CreateRect(PREFIX+"BG_MAIN", x, y, w, h, cor_bg_main, cor_border);
   
   // Cabeçalho
   CreateRect(PREFIX+"BG_HEADER", x, y, w, 40, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"TITLE", "BURGO SCALPE PRO V41", x+15, y+12, cor_text_main, 12, "Arial Bold");
   CreateButton(PREFIX+"BTN_MIN", "-", x+w-35, y+10, 20, 20, cor_bg_main, cor_text_main);
   
   // Status e Relógio
   DrawLabel(PREFIX+"LBL_TIME", "Server Time:", x+15, y+55, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_TIME", "00:00:00", x+15, y+70, cor_accent, 14, "Arial Bold");
   
   DrawLabel(PREFIX+"LBL_CANDLE", "Next Candle:", x+120, y+55, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_CANDLE", "00:00", x+120, y+70, cor_text_main, 10, "Arial Bold");

   DrawLabel(PREFIX+"LBL_SPREAD", "Spread:", x+220, y+55, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_SPREAD", "0", x+220, y+70, cor_warning, 10, "Arial Bold");

   // Botões de Controle Rápidos (Linha 1)
   int btn_y = y + 100;
   CreateButton(PREFIX+"BTN_BUY", "BUY", x+15, btn_y, 65, 35, cor_buy, clrWhite);
   CreateButton(PREFIX+"BTN_SELL", "SELL", x+85, btn_y, 65, 35, cor_sell, clrWhite);
   CreateButton(PREFIX+"BTN_CLEAN", "CLEAN", x+155, btn_y, 65, 35, cor_accent, clrWhite);
   CreateButton(PREFIX+"BTN_PANIC", "PANIC", x+225, btn_y, 80, 35, cor_warning, clrWhite);

   // Botões Táticos (Linha 2) ◄ MODIFICADO: 3 botões agora
   int btn2_y = btn_y + 40;
   CreateButton(PREFIX+"BTN_ATR", RuntimeUseATR ? "ATR:ON" : "ATR:OFF", x+15, btn2_y, 85, 35, RuntimeUseATR ? cor_buy : cor_sell, clrWhite);
   CreateButton(PREFIX+"BTN_ADX", RuntimeUseADX ? "ADX:ON" : "ADX:OFF", x+105, btn2_y, 85, 35, RuntimeUseADX ? cor_buy : cor_sell, clrWhite);
   CreateButton(PREFIX+"BTN_HEDGE", "HEDGE", x+195, btn2_y, 110, 35, cor_purple, clrWhite);

   // ◄ NOVO: Barra de Status do Grid + ADX + Drawdown
   int status_y = btn2_y + 42;
   DrawLabel(PREFIX+"LBL_GRID_STATUS", "GRID:", x+15, status_y, cor_text_muted, 9, "Arial Bold");
   DrawLabel(PREFIX+"VAL_GRID_STATUS", "ACTIVE", x+55, status_y, cor_buy, 9, "Arial Bold");
   DrawLabel(PREFIX+"LBL_ADX_VAL", "ADX:", x+140, status_y, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_ADX_VAL", "0.0", x+165, status_y, cor_text_main, 9, "Arial Bold");
   DrawLabel(PREFIX+"LBL_DD_VAL", "DD:", x+220, status_y, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_DD_VAL", "0.0%", x+240, status_y, cor_text_main, 9, "Arial Bold");

   // Painéis de Informação (Cards)
   int card_y = status_y + 25;
   
   // Card 1: Floating & Balance
   CreateRect(PREFIX+"CARD1", x+15, card_y, 140, 70, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_FLOAT", "Floating P/L", x+25, card_y+10, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_FLOAT", "$0.00", x+25, card_y+25, cor_text_main, 12, "Arial Bold");
   DrawLabel(PREFIX+"VAL_BAL", "Bal: $0.00", x+25, card_y+45, cor_text_muted, 9, "Arial");

   // Card 2: Profit Today
   CreateRect(PREFIX+"CARD2", x+165, card_y, 140, 70, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_PROFIT", "Profit Today", x+175, card_y+10, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_PROFIT", "$0.00", x+175, card_y+25, cor_text_main, 12, "Arial Bold");
   DrawLabel(PREFIX+"VAL_TOTAL", "Total: $0.00", x+175, card_y+45, cor_text_muted, 9, "Arial");

   // Card 3: Orders Info
   int card2_y = card_y + 80;
   CreateRect(PREFIX+"CARD3", x+15, card2_y, 290, 80, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_ORDERS", "Active Orders", x+25, card2_y+10, cor_text_muted, 9, "Arial Bold");
   
   DrawLabel(PREFIX+"LBL_BUY_ORD", "Buy Orders:", x+25, card2_y+30, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_BUY_ORD", "0 ($0.00)", x+100, card2_y+30, cor_buy, 9, "Arial Bold");
   
   DrawLabel(PREFIX+"LBL_SELL_ORD", "Sell Orders:", x+25, card2_y+50, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_SELL_ORD", "0 ($0.00)", x+100, card2_y+50, cor_sell, 9, "Arial Bold");

   // Card 4: Stats
   int card3_y = card2_y + 90;
   CreateRect(PREFIX+"CARD4", x+15, card3_y, 290, 90, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_STATS", "Performance", x+25, card3_y+10, cor_text_muted, 9, "Arial Bold");
   DrawLabel(PREFIX+"VAL_TRADES", "Total Trades: 0", x+25, card3_y+30, cor_text_main, 9, "Arial");
   
   DrawLabel(PREFIX+"VAL_WINS", "Wins: 0 (0%)", x+25, card3_y+50, cor_buy, 9, "Arial");
   DrawLabel(PREFIX+"VAL_LOSSES", "Losses: 0 (0%)", x+150, card3_y+50, cor_sell, 9, "Arial");
   
   DrawLabel(PREFIX+"VAL_PROFIT_PCT", "Profit %: 0.00%", x+25, card3_y+70, cor_accent, 9, "Arial Bold");

   // Rodapé com Botão Power
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

   long seconds_left = SeriesInfoInteger(_Symbol, InpTimeframe, SERIES_LASTBAR_DATE) + PeriodSeconds(InpTimeframe) - TimeCurrent();
   if(seconds_left < 0) seconds_left = 0;
   string candle_time = StringFormat("%02d:%02d", seconds_left / 60, seconds_left % 60);
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
   double profit_pct = (bal > 0) ? (total_profit / bal) * 100.0 : 0;

   ObjectSetString(0, PREFIX+"VAL_TRADES", OBJPROP_TEXT, StringFormat("Total Trades: %d", total_trades));
   ObjectSetString(0, PREFIX+"VAL_WINS", OBJPROP_TEXT, StringFormat("Wins: %d (%.1f%%)", win_trades, win_rate));
   ObjectSetString(0, PREFIX+"VAL_LOSSES", OBJPROP_TEXT, StringFormat("Losses: %d (%.1f%%)", loss_trades, loss_rate));
   ObjectSetString(0, PREFIX+"VAL_PROFIT_PCT", OBJPROP_TEXT, StringFormat("Profit %%: %.2f%%", profit_pct));
   
   // ◄ NOVO: Atualizar status do grid, ADX e drawdown
   if(gridBlocked) {
      ObjectSetString(0, PREFIX+"VAL_GRID_STATUS", OBJPROP_TEXT, "PAUSED");
      ObjectSetInteger(0, PREFIX+"VAL_GRID_STATUS", OBJPROP_COLOR, cor_warning);
   } else {
      ObjectSetString(0, PREFIX+"VAL_GRID_STATUS", OBJPROP_TEXT, "ACTIVE");
      ObjectSetInteger(0, PREFIX+"VAL_GRID_STATUS", OBJPROP_COLOR, cor_buy);
   }
   
   ObjectSetString(0, PREFIX+"VAL_ADX_VAL", OBJPROP_TEXT, StringFormat("%.1f", currentADX));
   color adxColor = (currentADX >= InpADXThreshold) ? cor_buy : cor_sell;
   ObjectSetInteger(0, PREFIX+"VAL_ADX_VAL", OBJPROP_COLOR, adxColor);
   
   double ddPct = (bal > 0 && floating < 0) ? MathAbs(floating) / bal * 100.0 : 0;
   ObjectSetString(0, PREFIX+"VAL_DD_VAL", OBJPROP_TEXT, StringFormat("%.1f%%", ddPct));
   color ddColor = (ddPct >= InpMaxDrawdownPct && InpMaxDrawdownPct > 0) ? cor_sell : (ddPct > InpMaxDrawdownPct * 0.7) ? cor_warning : cor_buy;
   ObjectSetInteger(0, PREFIX+"VAL_DD_VAL", OBJPROP_COLOR, ddColor);
   
   ChartRedraw();
}

void AtualizarVisibilidadePainel() {
   bool show = !Panel_Minimized;
   
   ObjectSetInteger(0, PREFIX+"BG_MAIN", OBJPROP_YSIZE, show ? 600 : 40);
   
   string objs[] = {"LBL_TIME", "VAL_TIME", "LBL_CANDLE", "VAL_CANDLE", "LBL_SPREAD", "VAL_SPREAD",
                    "LBL_STATUS", "VAL_STATUS", "BTN_BUY", "BTN_SELL", "BTN_CLEAN", "BTN_PANIC", 
                    "BTN_ATR", "BTN_ADX", "BTN_HEDGE", "BTN_CLOSE_ALL",
                    "LBL_GRID_STATUS", "VAL_GRID_STATUS", "LBL_ADX_VAL", "VAL_ADX_VAL", "LBL_DD_VAL", "VAL_DD_VAL",
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
