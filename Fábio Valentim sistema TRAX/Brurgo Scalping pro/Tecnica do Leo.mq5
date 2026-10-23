//+------------------------------------------------------------------+
//|                                           Burgo Scalpe Pro.mq5 |
//|                                     Copyright 2024, DevMaster Pro |
//|   V41 - MULTI-ATIVO (XAUUSD / GOLD & BTCUSD) - XM GLOBAL 1:500   |
//|       COM CIRCUIT BREAKER (HARD STOP) E PROTEÇÃO DE BANCA $200    |
//+------------------------------------------------------------------+
#property copyright "DevMaster Pro"
#property version   "41.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// --- ENUMS DE CONFIGURAÇÃO ---
enum ENUM_ASSET_TYPE {
   ASSET_AUTO = 0,    // Detecção Automática (GOLD / BTC / Outros)
   ASSET_GOLD = 1,    // XAUUSD / GOLD (Ouro)
   ASSET_CRYPTO = 2,  // BTCUSD (Bitcoin)
   ASSET_CUSTOM = 3   // Personalizado / Forex
};

enum ENUM_TRADE_DIRECTION {
   DIR_BOTH = 0,      // Ambas as Direções (Hedging)
   DIR_EMA_TREND = 1, // Apenas a Favor da Tendência (EMA 200)
   DIR_BUY_ONLY = 2,  // Apenas Compras (Buy-Only)
   DIR_SELL_ONLY = 3  // Apenas Vendas (Sell-Only)
};

// --- INPUTS CALIBRADOS INSTITUCIONALMENTE PARA XM GLOBAL ($200 | 1:500) ---
input group "==== PERFIL DA CONTA E ATIVO ===="
input ENUM_ASSET_TYPE InpAssetType         = ASSET_AUTO; // Tipo de Ativo
input ENUM_TRADE_DIRECTION InpTradeDirection = DIR_EMA_TREND; // Direção Operacional
input int              InpMagicNumber      = 888123;     // Magic Number (Use 888124 no BTC)

input group "==== MOTOR DE GIRO E RECICLAGEM ===="
input double           InpInitialLot       = 0.01;       // Lote Inicial (XM Standard min 0.01)
input double           InpTargetSideUSD    = 2.00;       // Alvo do Giro por Lado ($)
input double           InpTargetGlobalUSD  = 10.00;      // Alvo para Reset Global Total ($)

input group "==== GESTÃO DE RISCO E PROTEÇÃO DE BANCA ($200) ===="
input bool             InpUseHardStop      = true;       // Ativar Circuit Breaker (Hard Stop)
input double           InpHardStopLossUSD  = 35.00;      // Perda Máxima Tolerada por Cesto ($)
input int              InpBaseDistance     = 0;          // Distância Base em Pts (0 = Auto: Ouro=400, BTC=50000)
input double           InpLotMultiplier    = 1.15;       // Multiplicador Suave (1.15x)
input int              InpMaxMartingale    = 2;          // Limite de Multiplicação (Trava no 2º nível)
input int              InpMaxTotalOrders   = 3;          // Máximo de Ordens por Lado (Banca $200 = Max 3)

input group "==== FILTROS TÉCNICOS (M15 / M1) ===="
input ENUM_TIMEFRAMES  InpTimeframe        = PERIOD_M15; // Timeframe Analítico do ATR e EMA
input bool             InpUseATR           = true;       // Distância Dinâmica por ATR
input int              InpATRPeriod        = 14;         // Período do ATR
input double           InpATRMultiplier    = 1.5;        // Multiplicador do ATR
input int              InpEMAPeriod        = 200;        // Período da Média Exponencial de Tendência

input group "==== TRAILING STOP RASTREADOR ===="
input bool             InpUseTrailingStop  = true;       // Ativar Trailing Stop
input double           InpTrailingStartUSD = 2.00;       // Iniciar Trailing ao Atingir ($)
input double           InpTrailingStepUSD  = 0.50;       // Recuo para Fechamento ($)

input group "==== HORÁRIOS DE OPERAÇÃO ===="
input string           InpStartTime        = "00:00";    // Horário de Início (HH:MM)
input string           InpEndTime          = "23:59";    // Horário de Término (HH:MM)

// Variáveis Globais de Execução
CTrade        trade;
CPositionInfo posInfo;
int           PM = 1;
string        PREFIX = "BSP_";
int           atrHandle = INVALID_HANDLE;
int           emaHandle = INVALID_HANDLE;
ENUM_ASSET_TYPE activeAsset = ASSET_GOLD;

bool          EA_Active = true;
bool          Panel_Minimized = false;

// Cores Institucionais do Painel
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

// Variáveis de Trailing Stop
double max_buy_profit = 0.0;
double max_sell_profit = 0.0;

// Declarações Prévias de Funções
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
double GetDynamicDistance();
bool PermitirEntrada(ENUM_POSITION_TYPE tipo);

//+------------------------------------------------------------------+
//| Identificação Automática do Ativo e Calibração de Parâmetros     |
//+------------------------------------------------------------------+
void DetectarAtivo() {
   string s = _Symbol;
   StringToUpper(s);
   
   if(InpAssetType == ASSET_AUTO) {
      if(StringFind(s, "BTC") >= 0) {
         activeAsset = ASSET_CRYPTO;
      } else if(StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0) {
         activeAsset = ASSET_GOLD;
      } else {
         activeAsset = ASSET_CUSTOM;
      }
   } else {
      activeAsset = InpAssetType;
   }
   
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   PM = (digits >= 3) ? 10 : 1;
   
   Print("INICIALIZAÇÃO ATIVO: ", _Symbol, " | Tipo: ", EnumToString(activeAsset), " | Digits: ", digits);
}

//+------------------------------------------------------------------+
//| Inicialização do Expert Advisor                                  |
//+------------------------------------------------------------------+
int OnInit() {
   DetectarAtivo();
   
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetAsyncMode(false); // Execução síncrona segura
   trade.SetDeviationInPoints(15);
   
   if(InpUseATR) {
      atrHandle = iATR(_Symbol, InpTimeframe, InpATRPeriod);
      if(atrHandle == INVALID_HANDLE) {
         Print("Aviso: Falha ao carregar indicador ATR.");
      }
   }
   
   if(InpTradeDirection == DIR_EMA_TREND) {
      emaHandle = iMA(_Symbol, InpTimeframe, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(emaHandle == INVALID_HANDLE) {
         Print("Aviso: Falha ao carregar indicador EMA 200.");
      }
   }
   
   CalculateStats();
   CriarPainelModerno();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Desinicialização e Liberação de Recursos                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) { 
   ObjectsDeleteAll(0, PREFIX); 
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Normalização Rigorosa do Lote Conforme Regras da Corretora       |
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
//| Validação de Janela de Horário                                   |
//+------------------------------------------------------------------+
bool IsTradingTime() {
   datetime time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(time, dt);
   
   int current_mins = dt.hour * 60 + dt.min;
   
   string start_arr[], end_arr[];
   StringSplit(InpStartTime, ':', start_arr);
   int start_mins = (int)StringToInteger(start_arr[0]) * 60 + (int)StringToInteger(start_arr[1]);
   
   StringSplit(InpEndTime, ':', end_arr);
   int end_mins = (int)StringToInteger(end_arr[0]) * 60 + (int)StringToInteger(end_arr[1]);
   
   if(start_mins < end_mins) {
      return (current_mins >= start_mins && current_mins <= end_mins);
   } else {
      return (current_mins >= start_mins || current_mins <= end_mins);
   }
}

//+------------------------------------------------------------------+
//| Cálculo de Distância Adaptativa Específica por Ativo             |
//+------------------------------------------------------------------+
double GetDynamicDistance() {
   double effectiveBasePts = InpBaseDistance;
   
   // Se configurado como 0 (automático), define distância base segura por ativo
   if(effectiveBasePts <= 0) {
      if(activeAsset == ASSET_GOLD) {
         effectiveBasePts = 400; // 400 pontos = $4.00 de ouro
      } else if(activeAsset == ASSET_CRYPTO) {
         effectiveBasePts = 50000; // 50.000 pontos = $500.00 no Bitcoin
      } else {
         effectiveBasePts = 300;
      }
   }
   
   double baseDistPrice = effectiveBasePts * _Point;
   if(!InpUseATR || atrHandle == INVALID_HANDLE) return baseDistPrice;
   
   double atr[];
   ArraySetAsSeries(atr, true);
   int copied = CopyBuffer(atrHandle, 0, 1, 1, atr);
   if(copied <= 0) return baseDistPrice;
   
   double dist = atr[0] * InpATRMultiplier;
   double minDist = (effectiveBasePts / 2.0) * _Point;
   if(dist < minDist) dist = minDist;
   
   return dist;
}

//+------------------------------------------------------------------+
//| Filtro de Tendência EMA 200 (Shift 1 Causal)                    |
//+------------------------------------------------------------------+
bool PermitirEntrada(ENUM_POSITION_TYPE tipo) {
   if(InpTradeDirection == DIR_BUY_ONLY)  return (tipo == POSITION_TYPE_BUY);
   if(InpTradeDirection == DIR_SELL_ONLY) return (tipo == POSITION_TYPE_SELL);
   if(InpTradeDirection == DIR_BOTH)      return true;
   
   if(InpTradeDirection == DIR_EMA_TREND && emaHandle != INVALID_HANDLE) {
      double ema[];
      ArraySetAsSeries(ema, true);
      if(CopyBuffer(emaHandle, 0, 1, 1, ema) > 0) {
         double close1 = iClose(_Symbol, InpTimeframe, 1);
         if(tipo == POSITION_TYPE_BUY)  return (close1 > ema[0]);
         if(tipo == POSITION_TYPE_SELL) return (close1 < ema[0]);
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Estatísticas da Conta (Disparado apenas em fechamento)          |
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

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
      CalculateStats();
   }
}

//+------------------------------------------------------------------+
//| Trailing Stop Rastreador por Lado                                |
//+------------------------------------------------------------------+
void ProcessTrailingStop(double buyProfit, double sellProfit) {
   if(!InpUseTrailingStop) return;
   
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
//| Reciclagem Ativa por Abatimento da Pior Ordem                    |
//+------------------------------------------------------------------+
bool TentarReciclarPiorOrdem(double lucroDisponivel, ENUM_POSITION_TYPE ladoPerdedor) {
   ulong ticketPiorOrdem = 0;
   double piorPerda = 0.0;

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

   if(ticketPiorOrdem > 0 && lucroDisponivel > MathAbs(piorPerda)) {
      if(trade.PositionClose(ticketPiorOrdem)) {
         Print("RECICLAGEM EXECUTADA: Pior ordem ticket ", ticketPiorOrdem, 
               " (Perda: $", DoubleToString(piorPerda, 2), 
               ") abatida com lucro do giro de $", DoubleToString(lucroDisponivel, 2));
         return true;
      }
   }
   return false;
}

void FecharLado(ENUM_POSITION_TYPE type) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber) {
         if(posInfo.PositionType() == type) {
            trade.PositionClose(posInfo.Ticket());
         }
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
         if(p > 0.0) trade.PositionClose(posInfo.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//| Loop de Processamento em Tempo Real (OnTick)                     |
//+------------------------------------------------------------------+
void OnTick() {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double totalFloating = equity - balance;

   int totalBuy = 0, totalSell = 0;
   double buyProfit = 0.0, sellProfit = 0.0;
   double lastBuyPrice = 0.0, lastSellPrice = 0.0;
   double lastBuyLot = 0.0, lastSellLot = 0.0;

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
      // 1. CIRCUIT BREAKER / HARD STOP LOSS DE PROTEÇÃO DA BANCA ($200)
      if(InpUseHardStop && InpHardStopLossUSD > 0.0 && totalFloating <= -InpHardStopLossUSD) {
         FecharTudo();
         max_buy_profit = 0.0;
         max_sell_profit = 0.0;
         Print("CIRCUIT BREAKER ACIONADO: Prejuízo flutuante atingiu -$", DoubleToString(MathAbs(totalFloating), 2), 
               ". Todas as ordens foram liquidadas para proteger o saldo de $", DoubleToString(equity, 2), " da conta!");
         AtualizarValoresPainel(totalFloating, balance, equity, 0, 0, 0.0, 0.0);
         return;
      }

      // 2. RESET GLOBAL TOTAL (Ao atingir meta combinada)
      if(InpTargetGlobalUSD > 0.0 && totalFloating >= InpTargetGlobalUSD) {
         FecharTudo();
         max_buy_profit = 0.0;
         max_sell_profit = 0.0;
         Print("RESET GLOBAL DA CARTEIRA: Meta de $", DoubleToString(totalFloating, 2), " atingida! Risco zerado.");
         AtualizarValoresPainel(totalFloating, balance, equity, 0, 0, 0.0, 0.0);
         return;
      }

      // 3. MOTOR DE GIRO E RECICLAGEM DESBLOQUEADO
      if(buyProfit >= InpTargetSideUSD) {
         if(totalSell > 0) {
            TentarReciclarPiorOrdem(buyProfit, POSITION_TYPE_SELL);
         }
         FecharLado(POSITION_TYPE_BUY); 
         max_buy_profit = 0.0;
         Print("GIRO COMPRADOR CONCLUÍDO: Lucro realizado = $", DoubleToString(buyProfit, 2));
      }

      if(sellProfit >= InpTargetSideUSD) {
         if(totalBuy > 0) {
            TentarReciclarPiorOrdem(sellProfit, POSITION_TYPE_BUY);
         }
         FecharLado(POSITION_TYPE_SELL); 
         max_sell_profit = 0.0;
         Print("GIRO VENDEDOR CONCLUÍDO: Lucro realizado = $", DoubleToString(sellProfit, 2));
      }

      // 4. TRAILING STOP RASTREADOR
      ProcessTrailingStop(buyProfit, sellProfit);

      // 5. ENTRADAS E GRADE COM LIMITES RÍGIDOS PARA BANCA DE $200
      if(IsTradingTime()) {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

         // Giro Inicial com Filtro de Tendência
         if(totalBuy == 0 && PermitirEntrada(POSITION_TYPE_BUY)) {
            trade.Buy(NormalizeLots(InpInitialLot), _Symbol, ask, 0, 0, "Giro");
         }
         if(totalSell == 0 && PermitirEntrada(POSITION_TYPE_SELL)) {
            trade.Sell(NormalizeLots(InpInitialLot), _Symbol, bid, 0, 0, "Giro");
         }

         double currentDistance = GetDynamicDistance();
         
         // Adição de Grade Compras (Máximo rígido de InpMaxTotalOrders = 3)
         if(totalBuy > 0 && totalBuy < InpMaxTotalOrders && ask < (lastBuyPrice - currentDistance)) {
            double nextLot = (totalBuy < InpMaxMartingale) ? NormalizeLots(lastBuyLot * InpLotMultiplier) : lastBuyLot;
            trade.Buy(nextLot, _Symbol, ask, 0, 0, "Grid");
         }

         // Adição de Grade Vendas (Máximo rígido de InpMaxTotalOrders = 3)
         if(totalSell > 0 && totalSell < InpMaxTotalOrders && bid > (lastSellPrice + currentDistance)) {
            double nextLot = (totalSell < InpMaxMartingale) ? NormalizeLots(lastSellLot * InpLotMultiplier) : lastSellLot;
            trade.Sell(nextLot, _Symbol, bid, 0, 0, "Grid");
         }
      }
   }
   
   AtualizarValoresPainel(totalFloating, balance, equity, totalBuy, totalSell, buyProfit, sellProfit);
}

//+------------------------------------------------------------------+
//| Eventos de Interface Gráfica                                     |
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
//| Interface Visual Moderna                                         |
//+------------------------------------------------------------------+
void CriarPainelModerno() {
   int x = 20; int y = 20; int w = 320; int h = 530;
   CreateRect(PREFIX+"BG_MAIN", x, y, w, h, cor_bg_main, cor_border);
   CreateRect(PREFIX+"BG_HEADER", x, y, w, 40, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"TITLE", "BURGO SCALPE V41 XM $200", x+15, y+12, cor_text_main, 11, "Arial Bold");
   CreateButton(PREFIX+"BTN_MIN", "-", x+w-35, y+10, 20, 20, cor_bg_main, cor_text_main);
   
   DrawLabel(PREFIX+"LBL_TIME", "Server Time:", x+15, y+55, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_TIME", "00:00:00", x+15, y+70, cor_accent, 14, "Arial Bold");
   DrawLabel(PREFIX+"LBL_CANDLE", "Ativo:", x+120, y+55, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_CANDLE", _Symbol, x+120, y+70, cor_text_main, 10, "Arial Bold");
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
   DrawLabel(PREFIX+"LBL_ORDERS", "Posições Abertas", x+25, card2_y+10, cor_text_muted, 9, "Arial Bold");
   DrawLabel(PREFIX+"LBL_BUY_ORD", "Compras:", x+25, card2_y+30, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_BUY_ORD", "0 ($0.00)", x+100, card2_y+30, cor_buy, 9, "Arial Bold");
   DrawLabel(PREFIX+"LBL_SELL_ORD", "Vendas:", x+25, card2_y+50, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_SELL_ORD", "0 ($0.00)", x+100, card2_y+50, cor_sell, 9, "Arial Bold");
   
   int card3_y = card2_y + 90;
   CreateRect(PREFIX+"CARD4", x+15, card3_y, 290, 95, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_STATS", "Performance & Risco ($200)", x+25, card3_y+10, cor_text_muted, 9, "Arial Bold");
   DrawLabel(PREFIX+"VAL_TRADES", "Total Trades: 0", x+25, card3_y+30, cor_text_main, 9, "Arial");
   DrawLabel(PREFIX+"VAL_WINS", "Wins: 0 (0%)", x+25, card3_y+50, cor_buy, 9, "Arial");
   DrawLabel(PREFIX+"VAL_LOSSES", "Losses: 0 (0%)", x+150, card3_y+50, cor_sell, 9, "Arial");
   DrawLabel(PREFIX+"VAL_PROFIT_PCT", "Proteção Hard Stop: Ativa ($35.00)", x+25, card3_y+72, cor_accent, 8, "Arial Bold");
   
   int footer_y = card3_y + 105;
   CreateRect(PREFIX+"BG_FOOTER", x, footer_y, w, 50, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_POWER", "Automação:", x+15, footer_y+18, cor_text_main, 10, "Arial Bold");
   DrawLabel(PREFIX+"VAL_STATUS", "Active", x+100, footer_y+18, cor_accent, 10, "Arial Bold");
   CreateButton(PREFIX+"BTN_POWER", "ON", x+w-70, footer_y+12, 50, 25, cor_buy, clrWhite);
   CreateButton(PREFIX+"BTN_REMOVE", "X", x+w-110, footer_y+12, 30, 25, cor_sell, clrWhite);
}

void AtualizarValoresPainel(double floating, double bal, double eq, int tBuy, int tSell, double pBuy, double pSell) {
   if (Panel_Minimized) return;
   datetime time = TimeCurrent();
   ObjectSetString(0, PREFIX+"VAL_TIME", OBJPROP_TEXT, TimeToString(time, TIME_MINUTES|TIME_SECONDS));
   
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
   
   ObjectSetString(0, PREFIX+"VAL_TRADES", OBJPROP_TEXT, StringFormat("Total Trades: %d", total_trades));
   ObjectSetString(0, PREFIX+"VAL_WINS", OBJPROP_TEXT, StringFormat("Wins: %d (%.1f%%)", win_trades, win_rate));
   ObjectSetString(0, PREFIX+"VAL_LOSSES", OBJPROP_TEXT, StringFormat("Losses: %d (%.1f%%)", loss_trades, loss_rate));
   
   ChartRedraw();
}

void AtualizarVisibilidadePainel() {
   bool show = !Panel_Minimized;
   ObjectSetInteger(0, PREFIX+"BG_MAIN", OBJPROP_YSIZE, show ? 530 : 40);
   string objs[] = {"LBL_TIME", "VAL_TIME", "LBL_CANDLE", "VAL_CANDLE", "LBL_SPREAD", "VAL_SPREAD", "LBL_STATUS", "VAL_STATUS", "BTN_BUY", "BTN_SELL", "BTN_CLEAN", "BTN_PANIC", "BTN_CLOSE_ALL", "CARD1", "LBL_FLOAT", "VAL_FLOAT", "VAL_BAL", "CARD2", "LBL_PROFIT", "VAL_PROFIT", "VAL_TOTAL", "CARD3", "LBL_ORDERS", "LBL_BUY_ORD", "VAL_BUY_ORD", "LBL_SELL_ORD", "VAL_SELL_ORD", "CARD4", "LBL_STATS", "VAL_TRADES", "VAL_WINS", "VAL_LOSSES", "VAL_PROFIT_PCT", "BG_FOOTER", "LBL_POWER", "BTN_REMOVE"};
   for(int i = 0; i < ArraySize(objs); i++) {
      if(ObjectFind(0, PREFIX+objs[i]) >= 0) ObjectSetInteger(0, PREFIX+objs[i], OBJPROP_TIMEFRAMES, show ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   }
}

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
