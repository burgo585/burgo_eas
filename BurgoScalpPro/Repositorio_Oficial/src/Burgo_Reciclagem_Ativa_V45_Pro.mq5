//+------------------------------------------------------------------+
//|                             Burgo_Reciclagem_Ativa_V45_Pro.mq5   |
//|                                    Copyright 2026, DevMaster Pro |
//|        V45 PRO - SISTEMA INSTITUCIONAL DE RECICLAGEM E SCALPING  |
//|               (REMODELADO COM BASE NA AUDITORIA FORENSE)         |
//+------------------------------------------------------------------+
#property copyright "DevMaster Pro & Auditoria Quant Forense"
#property version   "45.00"
#property description "EA de Scalping e Reciclagem Ativa com Protecao de Margem e Stop de Cesta Dinamico"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// --- ENUMS CONFIGURÁVEIS ---
enum ENUM_TRADE_DIRECTION {
   TRADE_DIR_BOTH_EMA   = 0, // Ambas Direcoes com Filtro EMA 200 (Recomendado)
   TRADE_DIR_BUY_ONLY   = 1, // Apenas Compras (Modo Trend Bull Ouro)
   TRADE_DIR_SELL_ONLY  = 2, // Apenas Vendas (Modo Trend Bear Ouro)
   TRADE_DIR_BOTH_OPEN  = 3  // Ambas sem filtro de tendencia
};

enum ENUM_BASKET_STOP_MODE {
   STOP_PERCENT_BALANCE = 0, // Percentual do Saldo da Conta (ex: 6% a 8%)
   STOP_FIXED_AMOUNT    = 1, // Valor Fixo em Dolares ($)
   STOP_ATR_VOLATILITY  = 2  // Multiplo do ATR M15
};

// --- INPUTS INSTITUCIONAIS ---
input group "==== 1. FILTRO DIRECIONAL & MOMENTUM ===="
input ENUM_TRADE_DIRECTION InpTradeDirection  = TRADE_DIR_BOTH_EMA; // Direcao Permitida
input int                  InpEMAPeriod       = 200;                // Periodo EMA de Tendencia
input ENUM_TIMEFRAMES      InpEMATimeframe    = PERIOD_M15;         // Timeframe da EMA
input bool                 InpUseRSIFilter    = true;               // Usar Filtro RSI contra Facas Caindo
input int                  InpRSIPeriod       = 14;                 // Periodo RSI
input double               InpRSIOverbought   = 70.0;               // Nivel de Sobrecompra (Bloqueia Compras)
input double               InpRSIOversold     = 30.0;               // Nivel de Sobrevenda (Bloqueia Vendas)

input group "==== 2. MOTOR DE GIRO & METAS ECN ===="
input double               InpInitialLot      = 0.01;               // Lote Base (0.01 para contas pequenas)
input double               InpTargetSideNetUSD= 4.00;               // Alvo LIQUIDO por lado ($ apos comissao/spread)
input double               InpTargetGlobalUSD = 25.00;              // Alvo Global para Reset Total ($)
input int                  InpMagicNumber     = 888145;             // Magic Number V45 Pro

input group "==== 3. GRADE ADAPTATIVA ANTI-TENDENCIA ===="
input int                  InpBaseDistance    = 1500;               // Distancia Minima em Pontos ($15.00 no Ouro)
input bool                 InpUseATRDistance  = true;               // Usar ATR para espacamento dinamico
input int                  InpATRPeriod       = 14;                 // Periodo ATR
input ENUM_TIMEFRAMES      InpATRTimeframe    = PERIOD_M15;         // Timeframe ATR
input double               InpATRMultiplier   = 1.8;                // Multiplicador ATR
input double               InpLotMultiplier   = 1.0;                // Multiplicador de Lote (1.0 = Lote Fixo Seguro)
input int                  InpMaxTotalOrders  = 3;                  // Maximo de Ordens por lado (2 a 3 p/ $100)

input group "==== 4. BLINDAGEM DE RISCO & MARGEM (FORENSE) ===="
input ENUM_BASKET_STOP_MODE InpStopMode       = STOP_PERCENT_BALANCE;// Modo do Stop Loss de Cesta
input double               InpBasketStopPct   = 7.0;                // Perda Maxima da Cesta (% do Saldo - ex: 7%)
input double               InpBasketStopFixed = 10.00;              // Perda Maxima Fixa da Cesta ($)
input double               InpMinMarginLevel  = 350.0;              // Nivel Minimo de Margem p/ Abrir Novas Ordens (%)
input double               InpMaxMarginCommit = 20.0;               // Margem Maxima Comprometida (% do Equity)
input double               InpMaxDailyLossPct = 10.0;               // Perda Maxima Diaria Permitida (% do Saldo)
input int                  InpCooldownMinutes = 45;                 // Cooldown apos Stop Loss (Minutos)

input group "==== 5. TRAILING STOP INTELIGENTE ===="
input bool                 InpUseTrailingStop = true;               // Ativar Trailing Stop
input double               InpTrailingStartUSD= 6.00;               // Ativar Trailing com este lucro ($)
input double               InpTrailingDropPct = 12.0;               // Queda percentual do pico p/ fechar (12%)

input group "==== 6. HORARIOS & PROTECAO DE SWAP ===="
input string               InpStartTime       = "01:00";            // Horario de Inicio (HH:MM)
input string               InpEndTime         = "22:00";            // Horario de Termino (HH:MM)
input bool                 InpAvoidSwapRollover= true;              // Evitar aberturas na virada noturna (23:45-00:15)

// --- OBJETOS GLOBAIS ---
CTrade        trade;
CPositionInfo posInfo;
string        PREFIX = "BRA45_";

int           atrHandle = INVALID_HANDLE;
int           emaHandle = INVALID_HANDLE;
int           rsiHandle = INVALID_HANDLE;

bool          EA_Active = true;
bool          Panel_Minimized = false;
datetime      cooldown_until = 0;
double        start_day_balance = 0;
datetime      current_day_date = 0;

// Cores do Painel
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
int    total_trades = 0;
int    win_trades   = 0;
int    loss_trades  = 0;

// Variáveis de Trailing
double max_buy_profit    = 0;
double max_sell_profit   = 0;
double max_global_profit = 0;

// Declaração de Funções
void   CreateRect(string name, int x, int y, int w, int h, color bg, color border);
void   DrawLabel(string name, string text, int x, int y, color clr, int size, string font);
void   CreateButton(string name, string text, int x, int y, int w, int h, color bg, color fg);
void   AtualizarVisibilidadePainel();
void   AtualizarValoresPainel(double floating, double bal, double eq, int tBuy, int tSell, double pBuy, double pSell, double marginLevel, double marginCommitPct);
void   FecharLucrativas();
void   FecharLado(ENUM_POSITION_TYPE type);
void   FecharTudo();
bool   TentarReciclar(double lucroDisponivel, ENUM_POSITION_TYPE ladoPerdedor);
double NormalizeLot(double lot);
double GetDynamicDistance();
bool   IsTradingTime();
bool   IsSwapRolloverHour();
bool   CanOpenByMargin(double lotToOpen);
bool   CheckBasketStopLoss(double buyProfit, double sellProfit, double bal, int totalBuy, int totalSell);
void   CalculateStats();

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(15);
   trade.SetTypeFillingBySymbol(_Symbol);
   
   start_day_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   current_day_date  = iTime(_Symbol, PERIOD_D1, 0);

   // Indicador ATR
   if(InpUseATRDistance) {
      atrHandle = iATR(_Symbol, InpATRTimeframe, InpATRPeriod);
      if(atrHandle == INVALID_HANDLE) {
         Print("Erro ao inicializar iATR.");
         return(INIT_FAILED);
      }
   }
   
   // Indicador EMA de Tendência
   if(InpTradeDirection == TRADE_DIR_BOTH_EMA || InpTradeDirection == TRADE_DIR_BUY_ONLY || InpTradeDirection == TRADE_DIR_SELL_ONLY) {
      emaHandle = iMA(_Symbol, InpEMATimeframe, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(emaHandle == INVALID_HANDLE) {
         Print("Erro ao inicializar iMA.");
         return(INIT_FAILED);
      }
   }

   // Indicador RSI Anti-Exaustão
   if(InpUseRSIFilter) {
      rsiHandle = iRSI(_Symbol, InpATRTimeframe, InpRSIPeriod, PRICE_CLOSE);
      if(rsiHandle == INVALID_HANDLE) {
         Print("Erro ao inicializar iRSI.");
         return(INIT_FAILED);
      }
   }
   
   CriarPainelModerno();
   PrintFormat("Burgo_Reciclagem_Ativa_V45_Pro Inicializado! Saldo Base: $%.2f | Magic: %d", start_day_balance, InpMagicNumber);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) { 
   ObjectsDeleteAll(0, PREFIX); 
   if(atrHandle != INVALID_HANDLE) { IndicatorRelease(atrHandle); atrHandle = INVALID_HANDLE; }
   if(emaHandle != INVALID_HANDLE) { IndicatorRelease(emaHandle); emaHandle = INVALID_HANDLE; }
   if(rsiHandle != INVALID_HANDLE) { IndicatorRelease(rsiHandle); rsiHandle = INVALID_HANDLE; }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Normalização de Lote                                             |
//+------------------------------------------------------------------+
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
   
   int digits = 2;
   if(step == 0.1) digits = 1;
   else if(step == 0.001) digits = 3;
   
   return NormalizeDouble(lot, digits);
}

//+------------------------------------------------------------------+
//| Horário de Negociação                                            |
//+------------------------------------------------------------------+
bool IsTradingTime() {
   datetime time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(time, dt);
   
   int current_mins = dt.hour * 60 + dt.min;
   
   string start_arr[], end_arr[];
   if(StringSplit(InpStartTime, ':', start_arr) < 2 || StringSplit(InpEndTime, ':', end_arr) < 2) return true;
   
   int start_mins = (int)StringToInteger(start_arr[0]) * 60 + (int)StringToInteger(start_arr[1]);
   int end_mins   = (int)StringToInteger(end_arr[0]) * 60 + (int)StringToInteger(end_arr[1]);
   
   if (start_mins <= end_mins) {
      return (current_mins >= start_mins && current_mins <= end_mins);
   } else {
      return (current_mins >= start_mins || current_mins <= end_mins);
   }
}

//+------------------------------------------------------------------+
//| Evita Horário Crítico de Rollover de Swap                        |
//+------------------------------------------------------------------+
bool IsSwapRolloverHour() {
   if(!InpAvoidSwapRollover) return false;
   datetime time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(time, dt);
   
   // Bloqueia entre 23:45 e 00:15 do servidor
   if((dt.hour == 23 && dt.min >= 45) || (dt.hour == 0 && dt.min <= 15)) {
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Distância Dinâmica de Grade                                      |
//+------------------------------------------------------------------+
double GetDynamicDistance() {
   double baseDist = InpBaseDistance * _Point;
   if(!InpUseATRDistance || atrHandle == INVALID_HANDLE) return baseDist;
   
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(atrHandle, 0, 1, 1, atr) <= 0) return baseDist;
   
   double dist = atr[0] * InpATRMultiplier;
   if(dist < baseDist) dist = baseDist;
   
   return dist;
}

//+------------------------------------------------------------------+
//| Validação de Margem Dinâmica (Blindagem Forense)                 |
//+------------------------------------------------------------------+
bool CanOpenByMargin(double lotToOpen) {
   double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity      = AccountInfoDouble(ACCOUNT_EQUITY);
   double marginUsed  = AccountInfoDouble(ACCOUNT_MARGIN);
   double marginFree  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

   // 1. Se já houver nível de margem calculado e for inferior ao mínimo:
   if(marginUsed > 0 && marginLevel < InpMinMarginLevel) {
      PrintFormat("[PROTECAO MARGEM] Nivel de Margem %.1f%% abaixo do minimo permitido (%.1f%%). Ordem bloqueada.",
                  marginLevel, InpMinMarginLevel);
      return false;
   }

   // 2. Cálculo da nova margem necessária
   double marginRequired = 0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lotToOpen, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginRequired)) {
      marginRequired = (lotToOpen * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE) * SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / (double)AccountInfoInteger(ACCOUNT_LEVERAGE);
   }

   double newMarginTotal = marginUsed + marginRequired;

   // 3. Trava de % de comprometimento de margem sobre o Equity
   double commitPct = (equity > 0) ? (newMarginTotal / equity) * 100.0 : 100.0;
   if(commitPct > InpMaxMarginCommit) {
      PrintFormat("[PROTECAO MARGEM] Comprometimento de margem %.1f%% excederia o limite seguro (%.1f%%). Ordem de %.2f lotes bloqueada.",
                  commitPct, InpMaxMarginCommit, lotToOpen);
      return false;
   }

   return (marginFree > marginRequired);
}

//+------------------------------------------------------------------+
//| Stop Loss de Cesta Dinâmico & Perda Máxima Diária                |
//+------------------------------------------------------------------+
bool CheckBasketStopLoss(double buyProfit, double sellProfit, double bal, int totalBuy, int totalSell) {
   double maxAllowedLoss = 0;

   if(InpStopMode == STOP_PERCENT_BALANCE) {
      maxAllowedLoss = bal * (InpBasketStopPct / 100.0);
   } else if(InpStopMode == STOP_FIXED_AMOUNT) {
      maxAllowedLoss = InpBasketStopFixed;
   } else if(InpStopMode == STOP_ATR_VOLATILITY && atrHandle != INVALID_HANDLE) {
      double atr[];
      ArraySetAsSeries(atr, true);
      if(CopyBuffer(atrHandle, 0, 1, 1, atr) > 0) {
         maxAllowedLoss = (atr[0] * 3.0 / _Point) * 0.01 * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      }
   }
   
   if(maxAllowedLoss <= 0) maxAllowedLoss = 10.0;

   // Stop Loss no Lado da Compra
   if(totalBuy > 0 && buyProfit < 0 && MathAbs(buyProfit) >= maxAllowedLoss) {
      PrintFormat("[STOP LOSS V45 PRO] Cesta BUY atingiu -$%.2f (Limite Seguro: -$%.2f). Liquidando lado comprador.",
                  MathAbs(buyProfit), maxAllowedLoss);
      FecharLado(POSITION_TYPE_BUY);
      cooldown_until = TimeCurrent() + (InpCooldownMinutes * 60);
      return true;
   }

   // Stop Loss no Lado da Venda
   if(totalSell > 0 && sellProfit < 0 && MathAbs(sellProfit) >= maxAllowedLoss) {
      PrintFormat("[STOP LOSS V45 PRO] Cesta SELL atingiu -$%.2f (Limite Seguro: -$%.2f). Liquidando lado vendedor.",
                  MathAbs(sellProfit), maxAllowedLoss);
      FecharLado(POSITION_TYPE_SELL);
      cooldown_until = TimeCurrent() + (InpCooldownMinutes * 60);
      return true;
   }

   // Trava de Perda Diária Global
   if(bal > 0 && daily_profit < 0 && MathAbs(daily_profit) >= (bal * (InpMaxDailyLossPct / 100.0))) {
      PrintFormat("[TRAVA DIARIA V45 PRO] Prejuizo diario de $%.2f excedeu limite de %.1f%%. Encerrando operacoes por hoje.",
                  daily_profit, InpMaxDailyLossPct);
      FecharTudo();
      EA_Active = false;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Trailing Stop Global                                             |
//+------------------------------------------------------------------+
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
         PrintFormat("[TRAILING GLOBAL] Acionado com lucro de $%.2f!", totalFloating);
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Trailing Stop por Lado                                            |
//+------------------------------------------------------------------+
bool ProcessSideTrailing(ENUM_POSITION_TYPE type, double sideProfit) {
   if(!InpUseTrailingStop) return false;
   
   double startUSD = (InpTrailingStartUSD > 0) ? InpTrailingStartUSD : InpTargetSideNetUSD;
   
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
            PrintFormat("[TRAILING BUY] Fechado com $%.2f", sideProfit);
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
            PrintFormat("[TRAILING SELL] Fechado com $%.2f", sideProfit);
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Reciclagem Ativa Segura                                          |
//+------------------------------------------------------------------+
bool TentarReciclar(double lucroDisponivel, ENUM_POSITION_TYPE ladoPerdedor) {
   ulong  ticketCandidato = 0;
   double maiorPerda = 0;

   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Magic() == InpMagicNumber && posInfo.PositionType() == ladoPerdedor) {
         if(posInfo.Symbol() != _Symbol) continue;
         
         double p = posInfo.Profit() + posInfo.Commission() + posInfo.Swap();
         
         if(p < 0) {
            double perdaAbs = MathAbs(p);
            // So recicla se sobrar pelo menos $0.50 liquido de lucro
            if(lucroDisponivel >= (perdaAbs + 0.50)) {
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
         PrintFormat("[RECICLAGEM V45 PRO] Ordem #%d (Perda: $%.2f) resgatada com lucro de $%.2f",
                     ticketCandidato, maiorPerda, lucroDisponivel);
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Funções de Fechamento                                            |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| OnTick Principal                                                 |
//+------------------------------------------------------------------+
void OnTick() {
   CalculateStats();
   
   double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity      = AccountInfoDouble(ACCOUNT_EQUITY);
   double marginUsed  = AccountInfoDouble(ACCOUNT_MARGIN);
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   double totalFloating = equity - balance;
   double marginCommitPct = (equity > 0) ? (marginUsed / equity) * 100.0 : 0.0;

   // 1. FECHAMENTO GLOBAL
   if(!InpUseTrailingStop) { 
       if(totalFloating >= InpTargetGlobalUSD) {
          FecharTudo(); 
          max_global_profit = 0;
          return;
       }
   } else {
       if(ProcessGlobalTrailing(totalFloating)) return;
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

   // 3. STOP LOSS DE CESTA E TRAVA DIÁRIA
   if(CheckBasketStopLoss(buyProfit, sellProfit, balance, totalBuy, totalSell)) {
      AtualizarValoresPainel(totalFloating, balance, equity, totalBuy, totalSell, buyProfit, sellProfit, marginLevel, marginCommitPct);
      return;
   }

   if (EA_Active) {
      // 4. RECICLAGEM ATIVA LÍQUIDA
      if(buyProfit >= InpTargetSideNetUSD && totalSell > 0) {
         if(TentarReciclar(buyProfit, POSITION_TYPE_SELL)) {
            FecharLado(POSITION_TYPE_BUY); 
            max_buy_profit = 0;
            AtualizarValoresPainel(totalFloating, balance, equity, totalBuy, totalSell, buyProfit, sellProfit, marginLevel, marginCommitPct);
            return;
         }
      }
      if(sellProfit >= InpTargetSideNetUSD && totalBuy > 0) {
         if(TentarReciclar(sellProfit, POSITION_TYPE_BUY)) {
            FecharLado(POSITION_TYPE_SELL); 
            max_sell_profit = 0;
            AtualizarValoresPainel(totalFloating, balance, equity, totalBuy, totalSell, buyProfit, sellProfit, marginLevel, marginCommitPct);
            return;
         }
      }

      // 5. TAKE PROFIT INDIVIDUAL / TRAILING LÍQUIDO
      if(!InpUseTrailingStop) {
          if(buyProfit >= InpTargetSideNetUSD)  { FecharLado(POSITION_TYPE_BUY); max_buy_profit = 0; return; }
          if(sellProfit >= InpTargetSideNetUSD) { FecharLado(POSITION_TYPE_SELL); max_sell_profit = 0; return; }
      } else {
          if(ProcessSideTrailing(POSITION_TYPE_BUY, buyProfit))   return;
          if(ProcessSideTrailing(POSITION_TYPE_SELL, sellProfit)) return;
      }

      // 6. VERIFICAÇÃO DE COOLDOWN E HORÁRIO
      if(TimeCurrent() < cooldown_until) {
         AtualizarValoresPainel(totalFloating, balance, equity, totalBuy, totalSell, buyProfit, sellProfit, marginLevel, marginCommitPct);
         return;
      }

      if (IsTradingTime() && !IsSwapRolloverHour()) {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

         // Leitura de Tendência (EMA)
         bool allowBuy = true;
         bool allowSell = true;

         if(InpTradeDirection == TRADE_DIR_BUY_ONLY)  allowSell = false;
         if(InpTradeDirection == TRADE_DIR_SELL_ONLY) allowBuy  = false;

         if(InpTradeDirection == TRADE_DIR_BOTH_EMA && emaHandle != INVALID_HANDLE) {
            double emaArr[];
            ArraySetAsSeries(emaArr, true);
            if(CopyBuffer(emaHandle, 0, 1, 1, emaArr) > 0) {
               double emaVal = emaArr[0];
               allowBuy  = (ask >= emaVal);
               allowSell = (bid <= emaVal);
            }
         }

         // Filtro RSI Anti-Faca Caindo
         if(InpUseRSIFilter && rsiHandle != INVALID_HANDLE) {
            double rsiArr[];
            ArraySetAsSeries(rsiArr, true);
            if(CopyBuffer(rsiHandle, 0, 1, 1, rsiArr) > 0) {
               double rsiVal = rsiArr[0];
               if(rsiVal < InpRSIOversold)   allowSell = false; // Nao vende no fundo
               if(rsiVal > InpRSIOverbought) allowBuy  = false; // Nao compra no topo
            }
         }

         // 7. MOTOR DE GIRO INICIAL
         if(totalBuy == 0 && allowBuy && CanOpenByMargin(InpInitialLot)) {
            double initLot = NormalizeLot(InpInitialLot);
            trade.Buy(initLot, _Symbol, ask, 0, 0, "Giro V45");
         }
         if(totalSell == 0 && allowSell && CanOpenByMargin(InpInitialLot)) {
            double initLot = NormalizeLot(InpInitialLot);
            trade.Sell(initLot, _Symbol, bid, 0, 0, "Giro V45");
         }

         // 8. GRADE CONTROLADA
         double currentDistance = GetDynamicDistance();
         
         if(totalBuy > 0 && totalBuy < InpMaxTotalOrders && ask < (lastBuyPrice - currentDistance)) {
            double nextLot = NormalizeLot(lastBuyLot * InpLotMultiplier);
            if(CanOpenByMargin(nextLot)) {
               trade.Buy(nextLot, _Symbol, ask, 0, 0, "Grid V45");
            }
         }

         if(totalSell > 0 && totalSell < InpMaxTotalOrders && bid > (lastSellPrice + currentDistance)) {
            double nextLot = NormalizeLot(lastSellLot * InpLotMultiplier);
            if(CanOpenByMargin(nextLot)) {
               trade.Sell(nextLot, _Symbol, bid, 0, 0, "Grid V45");
            }
         }
      }
   }

   AtualizarValoresPainel(totalFloating, balance, equity, totalBuy, totalSell, buyProfit, sellProfit, marginLevel, marginCommitPct);
}

//+------------------------------------------------------------------+
//| Eventos de Botões no Gráfico                                     |
//+------------------------------------------------------------------+
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
      else if(sparam == PREFIX+"BTN_CLOSE_ALL" || sparam == PREFIX+"BTN_PANIC") {
         FecharTudo();
         EA_Active = false;
         ObjectSetString(0, PREFIX+"BTN_POWER", OBJPROP_TEXT, "OFF");
         ObjectSetInteger(0, PREFIX+"BTN_POWER", OBJPROP_BGCOLOR, cor_sell);
         ObjectSetString(0, PREFIX+"VAL_STATUS", OBJPROP_TEXT, "PANIC STOP");
         ObjectSetInteger(0, PREFIX+"VAL_STATUS", OBJPROP_COLOR, cor_sell);
         Print("[PANIC] Todas as ordens encerradas e EA pausado manualmente.");
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
      else if(sparam == PREFIX+"BTN_CLEAN") {
         FecharLucrativas();
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
      else if(sparam == PREFIX+"BTN_BUY") {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         trade.Buy(InpInitialLot, _Symbol, ask, 0, 0, "Manual V45");
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
      else if(sparam == PREFIX+"BTN_SELL") {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         trade.Sell(InpInitialLot, _Symbol, bid, 0, 0, "Manual V45");
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

//+------------------------------------------------------------------+
//| Estatísticas                                                     |
//+------------------------------------------------------------------+
void CalculateStats() {
   static int last_deals_count = -1;
   static datetime last_day = 0;
   
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(today != current_day_date) {
      current_day_date = today;
      start_day_balance = AccountInfoDouble(ACCOUNT_BALANCE);
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

//+------------------------------------------------------------------+
//| Interface Visual do Painel                                       |
//+------------------------------------------------------------------+
void CriarPainelModerno() {
   int x = 20;
   int y = 20;
   int w = 330;
   int h = 540;

   CreateRect(PREFIX+"BG_MAIN", x, y, w, h, cor_bg_main, cor_border);
   
   CreateRect(PREFIX+"BG_HEADER", x, y, w, 40, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"TITLE", "BURGO V45 PRO [INSTITUCIONAL]", x+15, y+12, cor_text_main, 11, "Arial Bold");
   CreateButton(PREFIX+"BTN_MIN", "-", x+w-35, y+10, 20, 20, cor_bg_main, cor_text_main);
   
   DrawLabel(PREFIX+"LBL_TIME", "Hora:", x+15, y+50, cor_text_muted, 8, "Arial");
   DrawLabel(PREFIX+"VAL_TIME", "00:00:00", x+15, y+65, cor_accent, 12, "Arial Bold");
   
   DrawLabel(PREFIX+"LBL_CANDLE", "Vela:", x+110, y+50, cor_text_muted, 8, "Arial");
   DrawLabel(PREFIX+"VAL_CANDLE", "00:00", x+110, y+65, cor_text_main, 10, "Arial Bold");

   DrawLabel(PREFIX+"LBL_MARGIN", "Margem:", x+190, y+50, cor_text_muted, 8, "Arial");
   DrawLabel(PREFIX+"VAL_MARGIN", "0.0%", x+190, y+65, cor_buy, 10, "Arial Bold");

   int btn_y = y + 95;
   CreateButton(PREFIX+"BTN_BUY", "BUY", x+15, btn_y, 65, 32, cor_buy, clrWhite);
   CreateButton(PREFIX+"BTN_SELL", "SELL", x+85, btn_y, 65, 32, cor_sell, clrWhite);
   CreateButton(PREFIX+"BTN_CLEAN", "CLEAN", x+155, btn_y, 65, 32, cor_accent, clrWhite);
   CreateButton(PREFIX+"BTN_PANIC", "PANIC", x+225, btn_y, 85, 32, cor_warning, clrWhite);

   int card_y = btn_y + 45;
   
   CreateRect(PREFIX+"CARD1", x+15, card_y, 145, 65, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_FLOAT", "Flutuante P/L", x+25, card_y+8, cor_text_muted, 8, "Arial");
   DrawLabel(PREFIX+"VAL_FLOAT", "$0.00", x+25, card_y+22, cor_text_main, 11, "Arial Bold");
   DrawLabel(PREFIX+"VAL_BAL", "Bal: $0.00", x+25, card_y+42, cor_text_muted, 8, "Arial");

   CreateRect(PREFIX+"CARD2", x+170, card_y, 145, 65, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_PROFIT", "Lucro Hoje", x+180, card_y+8, cor_text_muted, 8, "Arial");
   DrawLabel(PREFIX+"VAL_PROFIT", "$0.00", x+180, card_y+22, cor_text_main, 11, "Arial Bold");
   DrawLabel(PREFIX+"VAL_TOTAL", "Total: $0.00", x+180, card_y+42, cor_text_muted, 8, "Arial");

   int card2_y = card_y + 75;
   CreateRect(PREFIX+"CARD3", x+15, card2_y, 300, 80, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_ORDERS", "Posicoes & Cesta", x+25, card2_y+8, cor_text_muted, 8, "Arial Bold");
   DrawLabel(PREFIX+"LBL_BUY_ORD", "Compras:", x+25, card2_y+28, cor_text_muted, 8, "Arial");
   DrawLabel(PREFIX+"VAL_BUY_ORD", "0 ($0.00)", x+95, card2_y+28, cor_buy, 8, "Arial Bold");
   DrawLabel(PREFIX+"LBL_SELL_ORD", "Vendas:", x+25, card2_y+48, cor_text_muted, 8, "Arial");
   DrawLabel(PREFIX+"VAL_SELL_ORD", "0 ($0.00)", x+95, card2_y+48, cor_sell, 8, "Arial Bold");

   int card3_y = card2_y + 90;
   CreateRect(PREFIX+"CARD4", x+15, card3_y, 300, 95, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_STATS", "Performance & Risco", x+25, card3_y+8, cor_text_muted, 8, "Arial Bold");
   DrawLabel(PREFIX+"VAL_TRADES", "Trades Fechados: 0", x+25, card3_y+28, cor_text_main, 8, "Arial");
   DrawLabel(PREFIX+"VAL_WINS", "Wins: 0", x+25, card3_y+48, cor_buy, 8, "Arial");
   DrawLabel(PREFIX+"VAL_LOSSES", "Losses: 0", x+140, card3_y+48, cor_sell, 8, "Arial");
   DrawLabel(PREFIX+"VAL_MARGIN_COMMIT", "Margem Ocupada: 0.0%", x+25, card3_y+68, cor_warning, 8, "Arial Bold");

   int footer_y = card3_y + 105;
   CreateRect(PREFIX+"BG_FOOTER", x, footer_y, w, 45, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_POWER", "Status:", x+15, footer_y+14, cor_text_main, 9, "Arial Bold");
   DrawLabel(PREFIX+"VAL_STATUS", "Active", x+70, footer_y+14, cor_accent, 9, "Arial Bold");
   CreateButton(PREFIX+"BTN_POWER", "ON", x+w-70, footer_y+10, 45, 25, cor_buy, clrWhite);
   CreateButton(PREFIX+"BTN_REMOVE", "X", x+w-105, footer_y+10, 25, 25, cor_sell, clrWhite);
}

//+------------------------------------------------------------------+
//| Atualização de Valores no Painel                                 |
//+------------------------------------------------------------------+
void AtualizarValoresPainel(double floating, double bal, double eq, int tBuy, int tSell, double pBuy, double pSell, double marginLevel, double marginCommitPct) {
   if (Panel_Minimized) return;

   datetime time = TimeCurrent();
   ObjectSetString(0, PREFIX+"VAL_TIME", OBJPROP_TEXT, TimeToString(time, TIME_MINUTES|TIME_SECONDS));

   datetime bar_open = iTime(_Symbol, _Period, 0);
   long seconds_left = bar_open + PeriodSeconds(_Period) - TimeCurrent();
   if(seconds_left < 0) seconds_left = 0;
   string candle_time = StringFormat("%02d:%02d", (int)(seconds_left / 60), (int)(seconds_left % 60));
   ObjectSetString(0, PREFIX+"VAL_CANDLE", OBJPROP_TEXT, candle_time);

   string marginStr = (marginLevel > 0) ? StringFormat("%.0f%%", marginLevel) : "100%";
   color marginColor = (marginLevel < InpMinMarginLevel && marginLevel > 0) ? cor_sell : cor_buy;
   ObjectSetString(0, PREFIX+"VAL_MARGIN", OBJPROP_TEXT, marginStr);
   ObjectSetInteger(0, PREFIX+"VAL_MARGIN", OBJPROP_COLOR, marginColor);

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
   ObjectSetString(0, PREFIX+"VAL_TRADES", OBJPROP_TEXT, StringFormat("Trades Fechados: %d", total_trades));
   ObjectSetString(0, PREFIX+"VAL_WINS", OBJPROP_TEXT, StringFormat("Wins: %d (%.0f%%)", win_trades, win_rate));
   ObjectSetString(0, PREFIX+"VAL_LOSSES", OBJPROP_TEXT, StringFormat("Losses: %d", loss_trades));
   ObjectSetString(0, PREFIX+"VAL_MARGIN_COMMIT", OBJPROP_TEXT, StringFormat("Margem Ocupada: %.1f%%", marginCommitPct));
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Visibilidade Minimizada                                          |
//+------------------------------------------------------------------+
void AtualizarVisibilidadePainel() {
   bool show = !Panel_Minimized;
   ObjectSetInteger(0, PREFIX+"BG_MAIN", OBJPROP_YSIZE, show ? 540 : 40);
   
   string objs[] = {"LBL_TIME", "VAL_TIME", "LBL_CANDLE", "VAL_CANDLE", "LBL_MARGIN", "VAL_MARGIN",
                    "LBL_STATUS", "VAL_STATUS", "BTN_BUY", "BTN_SELL", "BTN_CLEAN", "BTN_PANIC", 
                    "CARD1", "LBL_FLOAT", "VAL_FLOAT", "VAL_BAL", 
                    "CARD2", "LBL_PROFIT", "VAL_PROFIT", "VAL_TOTAL",
                    "CARD3", "LBL_ORDERS", "LBL_BUY_ORD", "VAL_BUY_ORD", "LBL_SELL_ORD", "VAL_SELL_ORD",
                    "CARD4", "LBL_STATS", "VAL_TRADES", "VAL_WINS", "VAL_LOSSES", "VAL_MARGIN_COMMIT",
                    "BG_FOOTER", "LBL_POWER", "BTN_POWER", "BTN_REMOVE"};
                    
   for(int i=0; i<ArraySize(objs); i++) {
      if(ObjectFind(0, PREFIX+objs[i]) >= 0) {
         ObjectSetInteger(0, PREFIX+objs[i], OBJPROP_TIMEFRAMES, show ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
      }
   }
}

//+------------------------------------------------------------------+
//| Utilitários Gráficos                                             |
//+------------------------------------------------------------------+
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
