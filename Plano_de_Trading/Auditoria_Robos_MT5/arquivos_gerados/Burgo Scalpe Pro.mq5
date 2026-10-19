//+------------------------------------------------------------------+
//|                                             Burgo Scalpe Pro.mq5 |
//|                                    Copyright 2026, DevMaster Pro |
//|        V41 - SISTEMA INSTITUCIONAL SNIPER XAUUSD (OURO)          |
//|  (CASCATA DE MÉDIAS 25/50/200 + BREAKEVEN + TRAILING DE EXAUSTÃO)|
//+------------------------------------------------------------------+
#property copyright "DevMaster Pro"
#property version   "41.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// --- INPUTS ---
input group "==== 1. GESTÃO DE LOTE E ENTRADA SNIPER ===="
input double  InpLotSize            = 0.04;      // Tamanho do Lote Fixo (Entrada Única)
input int     InpMagicNumber        = 888123;    // Magic Number do Robô

input group "==== 2. PROTEÇÃO DE RISCO E BREAKEVEN ===="
input bool    InpUseBreakeven       = true;      // Ativar Breakeven Automático
input int     InpBreakevenPoints    = 500;       // Avanço a favor para Breakeven (500 pts = $5.00 no Ouro)
input double  InpBreakevenBufferPts = 20.0;      // Buffer de Breakeven em pontos (+Spread)
input double  InpInitialStopATR     = 1.5;       // Stop Loss Inicial (múltiplo do ATR)
input double  InpMaxDailyLossUSD    = 40.00;     // Trava de Perda Máxima Diária ($)

input group "==== 3. TRAILING STOP DE EXAUSTÃO NO PICO ===="
input bool    InpUseTrailingProfit  = true;      // Fechar no recuo de lucro pós-exaustão
input double  InpMinProfitToTrail   = 18.00;     // Lucro mínimo em $ para ativar o Trailing
input double  InpTrailingDropPct    = 15.0;      // % de recuo a partir do lucro máximo para fechar tudo

input group "==== 4. TRÍADE DE MÉDIAS INSTITUCIONAIS (TREND ENGINE) ===="
input ENUM_TIMEFRAMES InpTimeframe  = PERIOD_M15;// Timeframe de Operação
input int     InpFastEMA            = 25;        // Média Rápida (Micro-tendência / Gatilho)
input int     InpMidEMA             = 50;        // Média Intermediária (Meso-tendência)
input int     InpSlowEMA            = 200;       // Média Lenta (Macro Institucional)
input bool    InpUseVolumeFilter    = true;      // Exigir volume institucional acima da média (PVSRA)
input int     InpATRPeriod          = 14;        // Período do ATR

input group "==== 5. SESSÕES INSTITUCIONAIS (LONDRES E NOVA YORK) ===="
input bool    InpUseTimeFilter      = true;      // Operar apenas nos horários de pico
input string  InpStartTime          = "07:00";   // Abertura de Londres (07:00 GMT / 04:00 BRT)
input string  InpEndTime            = "19:00";   // Fechamento de Nova York (19:00 GMT / 16:00 BRT)

// Globais
CTrade        trade;
CPositionInfo posInfo;
int           PM = 1;
string        PREFIX = "BSP_";
int           atrHandle = INVALID_HANDLE;
int           ema25Handle = INVALID_HANDLE;
int           ema50Handle = INVALID_HANDLE;
int           ema200Handle = INVALID_HANDLE;

bool          EA_Active = true;
bool          Panel_Minimized = false;
bool          Daily_Locked = false;

// Cores do Painel Moderno (Dark Slate Theme)
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
double total_profit = 0.0;
double daily_profit = 0.0;
int total_trades = 0;
int win_trades = 0;
int loss_trades = 0;

// Variáveis de Controle da Posição Sniper
double max_trade_profit = 0.0;
bool   be_applied = false;
datetime last_bar_time = 0;

// Declarações UI
void CreateRect(string name, int x, int y, int w, int h, color bg, color border);
void DrawLabel(string name, string text, int x, int y, color clr, int size, string font);
void CreateButton(string name, string text, int x, int y, int w, int h, color bg, color fg);
void AtualizarVisibilidadePainel();
void AtualizarValoresPainel(double floating, double bal, double eq, string statusStr, double maxP);
void FecharTudo();

//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(InpMagicNumber);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   PM = (digits >= 3) ? 10 : 1;
   
   // Carrega Indicadores
   atrHandle    = iATR(_Symbol, InpTimeframe, InpATRPeriod);
   ema25Handle  = iMA(_Symbol, InpTimeframe, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   ema50Handle  = iMA(_Symbol, InpTimeframe, InpMidEMA,  0, MODE_EMA, PRICE_CLOSE);
   ema200Handle = iMA(_Symbol, InpTimeframe, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   
   if(atrHandle == INVALID_HANDLE || ema25Handle == INVALID_HANDLE || ema50Handle == INVALID_HANDLE || ema200Handle == INVALID_HANDLE) {
      Print("Erro ao carregar indicadores tecnicos da Triade de Medias!");
      return(INIT_FAILED);
   }
   
   CriarPainelModerno();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { 
   ObjectsDeleteAll(0, PREFIX); 
   if(atrHandle != INVALID_HANDLE)    IndicatorRelease(atrHandle);
   if(ema25Handle != INVALID_HANDLE)  IndicatorRelease(ema25Handle);
   if(ema50Handle != INVALID_HANDLE)  IndicatorRelease(ema50Handle);
   if(ema200Handle != INVALID_HANDLE) IndicatorRelease(ema200Handle);
   ChartRedraw();
}

bool IsTradingTime() {
   if(!InpUseTimeFilter) return true;
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

double GetATRValue() {
   double atr[1];
   if(CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0) return (100 * _Point * PM);
   return atr[0];
}

void CalculateStats() {
   total_profit = 0.0;
   daily_profit = 0.0;
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
   
   // Verificação da Trava Diária de Segurança
   if(daily_profit <= -InpMaxDailyLossUSD) {
      if(!Daily_Locked) {
         Daily_Locked = true;
         FecharTudo();
         Print("TRAVA DE SEGURANCA ATIVADA: Perda diaria de -$", InpMaxDailyLossUSD, " atingida. EA pausado hoje.");
      }
   }
}

//+------------------------------------------------------------------+
//| Loop Principal de Execução Tick a Tick                           |
//+------------------------------------------------------------------+
void OnTick() {
   CalculateStats();
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double totalFloating = equity - balance;

   // 1. Scanner da Posição Sniper Ativa
   bool hasPosition = false;
   ENUM_POSITION_TYPE posType = POSITION_TYPE_BUY;
   double openPrice = 0.0;
   double currentSL = 0.0;
   ulong  posTicket = 0;
   double posProfit = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber) {
         hasPosition = true;
         posType = posInfo.PositionType();
         openPrice = posInfo.PriceOpen();
         currentSL = posInfo.StopLoss();
         posTicket = posInfo.Ticket();
         posProfit = posInfo.Profit() + posInfo.Commission() + posInfo.Swap();
         break; // Sistema de posição única (Sniper)
      }
   }

   string statusStr = "Aguardando Sinal";
   if(hasPosition) {
      statusStr = (posType == POSITION_TYPE_BUY) ? "BUY SNIPER ATIVA" : "SELL SNIPER ATIVA";
   }

   if (EA_Active && !Daily_Locked) {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // -------------------------------------------------------------
      // 2. GESTÃO DA POSIÇÃO ATIVA (BREAKEVEN E TRAILING STOP)
      // -------------------------------------------------------------
      if(hasPosition) {
         if(posProfit > max_trade_profit) max_trade_profit = posProfit;

         // A. Breakeven Dinâmico (Risco Zero ao avançar InpBreakevenPoints)
         if(InpUseBreakeven && !be_applied) {
            double beDistance = InpBreakevenPoints * PM * _Point;
            if(posType == POSITION_TYPE_BUY) {
               if(ask >= (openPrice + beDistance)) {
                  double targetBE = openPrice + (InpBreakevenBufferPts * PM * _Point);
                  if(currentSL < targetBE) {
                     trade.PositionModify(posTicket, targetBE, 0);
                     be_applied = true;
                     Print("BREAKEVEN ACIONADO: Compra blindada com Risco Zero em ", targetBE);
                  }
               }
            } else {
               if(bid <= (openPrice - beDistance)) {
                  double targetBE = openPrice - (InpBreakevenBufferPts * PM * _Point);
                  if(currentSL == 0 || currentSL > targetBE) {
                     trade.PositionModify(posTicket, targetBE, 0);
                     be_applied = true;
                     Print("BREAKEVEN ACIONADO: Venda blindada com Risco Zero em ", targetBE);
                  }
               }
            }
         }

         // B. Trailing Stop Global de Exaustão (Encerra no recuo de 15% do pico)
         if(InpUseTrailingProfit && max_trade_profit >= InpMinProfitToTrail) {
            double dropThreshold = max_trade_profit * (1.0 - (InpTrailingDropPct / 100.0));
            if(posProfit <= dropThreshold) {
               trade.PositionClose(posTicket);
               Print("TRAILING EXAUSTAO: Lucro recuou ", InpTrailingDropPct, "% a partir do pico ($", max_trade_profit, "). Posição encerrada com lucro!");
               max_trade_profit = 0.0;
               be_applied = false;
               return;
            }
         }

         // C. Saída por Inversão de Média Rápida (EMA 25)
         double ema25[1];
         if(CopyBuffer(ema25Handle, 0, 0, 1, ema25) > 0) {
            if((posType == POSITION_TYPE_BUY && bid < ema25[0] && be_applied) ||
               (posType == POSITION_TYPE_SELL && ask > ema25[0] && be_applied)) {
               trade.PositionClose(posTicket);
               Print("SAIDA TECNICA: Preço cruzou a EMA 25 contra a tendência. Lucro garantido no bolso.");
               max_trade_profit = 0.0;
               be_applied = false;
               return;
            }
         }
      }

      // -------------------------------------------------------------
      // 3. MOTOR DE ENTRADA SNIPER E RE-ENTRADAS EM PULLBACK
      // -------------------------------------------------------------
      else {
         max_trade_profit = 0.0;
         be_applied = false;

         datetime current_bar = (datetime)SeriesInfoInteger(_Symbol, InpTimeframe, SERIES_LASTBAR_DATE);
         if(current_bar != last_bar_time && IsTradingTime()) {
            double e25[2], e50[2], e200[2];
            if(CopyBuffer(ema25Handle, 0, 1, 2, e25) > 0 &&
               CopyBuffer(ema50Handle, 0, 1, 2, e50) > 0 &&
               CopyBuffer(ema200Handle, 0, 1, 2, e200) > 0) {
               
               MqlRates rates[2];
               if(CopyRates(_Symbol, InpTimeframe, 1, 2, rates) > 0) {
                  double cClose = rates[1].close;
                  double cOpen  = rates[1].open;
                  long   cVol   = rates[1].tick_volume;
                  double atrVal = GetATRValue();

                  // Filtro de Volume Institucional
                  bool volOk = true;
                  if(InpUseVolumeFilter) {
                     long avgVol = 0;
                     MqlRates vRates[10];
                     int copied = CopyRates(_Symbol, InpTimeframe, 1, 10, vRates);
                     if(copied > 0) {
                        for(int k=0; k<copied; k++) avgVol += vRates[k].tick_volume;
                        avgVol /= copied;
                        if(cVol < (long)(avgVol * 1.1)) volOk = false;
                     }
                  }

                  // SINAL 1: COMPRA SNIPER (Cascata de Alta 25 > 50 > 200 + Repique na Média)
                  if(cClose > e25[1] && e25[1] > e50[1] && e50[1] > e200[1] && cClose > cOpen && volOk) {
                     double sl = cClose - (InpInitialStopATR * atrVal);
                     trade.Buy(InpLotSize, _Symbol, ask, sl, 0, "Sniper Buy XAU");
                     last_bar_time = current_bar;
                     Print("ORDEM SNIPER COMPRA EXECUTADA: Lote ", InpLotSize, " | SL: ", sl);
                  }
                  // SINAL 2: VENDA SNIPER (Cascata de Baixa 25 < 50 < 200 + Repique na Média)
                  else if(cClose < e25[1] && e25[1] < e50[1] && e50[1] < e200[1] && cClose < cOpen && volOk) {
                     double sl = cClose + (InpInitialStopATR * atrVal);
                     trade.Sell(InpLotSize, _Symbol, bid, sl, 0, "Sniper Sell XAU");
                     last_bar_time = current_bar;
                     Print("ORDEM SNIPER VENDA EXECUTADA: Lote ", InpLotSize, " | SL: ", sl);
                  }
               }
            }
         }
      }
   }

   // Atualização do Painel Moderno
   AtualizarValoresPainel(totalFloating, balance, equity, statusStr, max_trade_profit);
}

//+------------------------------------------------------------------+
//| Eventos do Painel Interativo                                     |
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
      else if(sparam == PREFIX+"BTN_CLOSE_ALL" || sparam == PREFIX+"BTN_PANIC") {
         FecharTudo();
         max_trade_profit = 0.0;
         be_applied = false;
         Print("PANIC/CLOSE ALL ACIONADO MANUALMENTE!");
      }
      else if(sparam == PREFIX+"BTN_BUY") {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = ask - (InpInitialStopATR * GetATRValue());
         trade.Buy(InpLotSize, _Symbol, ask, sl, 0, "Manual Buy");
      }
      else if(sparam == PREFIX+"BTN_SELL") {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = bid + (InpInitialStopATR * GetATRValue());
         trade.Sell(InpLotSize, _Symbol, bid, sl, 0, "Manual Sell");
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

void FecharTudo() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber) {
         trade.PositionClose(posInfo.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//| Interface Gráfica Moderna (Dark Slate Dashboard)                 |
//+------------------------------------------------------------------+
void CriarPainelModerno() {
   int x = 20, y = 20, w = 320, h = 530;

   // Fundo Principal
   CreateRect(PREFIX+"BG_MAIN", x, y, w, h, cor_bg_main, cor_border);
   
   // Cabeçalho
   CreateRect(PREFIX+"BG_HEADER", x, y, w, 40, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"TITLE", "BURGO SCALPE SNIPER V41", x+15, y+12, cor_text_main, 11, "Arial Bold");
   CreateButton(PREFIX+"BTN_MIN", "-", x+w-35, y+10, 20, 20, cor_bg_main, cor_text_main);
   
   // Relógio e Spread
   DrawLabel(PREFIX+"LBL_TIME", "Server Time:", x+15, y+55, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_TIME", "00:00:00", x+15, y+70, cor_accent, 13, "Arial Bold");
   
   DrawLabel(PREFIX+"LBL_CANDLE", "Next Candle:", x+120, y+55, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_CANDLE", "00:00", x+120, y+70, cor_text_main, 10, "Arial Bold");

   DrawLabel(PREFIX+"LBL_SPREAD", "Spread:", x+220, y+55, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_SPREAD", "0", x+220, y+70, cor_warning, 10, "Arial Bold");

   // Botões Rápidos
   int btn_y = y + 100;
   CreateButton(PREFIX+"BTN_BUY", "BUY", x+15, btn_y, 65, 35, cor_buy, clrWhite);
   CreateButton(PREFIX+"BTN_SELL", "SELL", x+85, btn_y, 65, 35, cor_sell, clrWhite);
   CreateButton(PREFIX+"BTN_CLOSE_ALL", "CLOSE ALL", x+155, btn_y, 80, 35, cor_accent, clrWhite);
   CreateButton(PREFIX+"BTN_PANIC", "PANIC", x+240, btn_y, 65, 35, cor_warning, clrWhite);

   // Cards Informativos
   int card_y = btn_y + 50;
   
   // Card 1: Floating & Balance
   CreateRect(PREFIX+"CARD1", x+15, card_y, 140, 70, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_FLOAT", "Floating P/L", x+25, card_y+10, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_FLOAT", "$0.00", x+25, card_y+25, cor_text_main, 12, "Arial Bold");
   DrawLabel(PREFIX+"VAL_BAL", "Bal: $0.00", x+25, card_y+45, cor_text_muted, 9, "Arial");

   // Card 2: Status Sniper & Pico de Lucro
   CreateRect(PREFIX+"CARD2", x+165, card_y, 140, 70, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_CYCLE", "Motor Sniper", x+175, card_y+10, cor_text_muted, 9, "Arial");
   DrawLabel(PREFIX+"VAL_CYCLE", "Aguardando", x+175, card_y+25, cor_accent, 9, "Arial Bold");
   DrawLabel(PREFIX+"VAL_MAXP", "Pico: $0.00", x+175, card_y+45, cor_buy, 9, "Arial Bold");

   // Card 3: Lucro Hoje e Trailing Info
   int card2_y = card_y + 80;
   CreateRect(PREFIX+"CARD3", x+15, card2_y, 290, 75, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_PROFIT", "Performance Diaria", x+25, card2_y+10, cor_text_muted, 9, "Arial Bold");
   DrawLabel(PREFIX+"VAL_PROFIT", "Hoje: $0.00", x+25, card2_y+30, cor_text_main, 10, "Arial Bold");
   DrawLabel(PREFIX+"VAL_TOTAL", "Total: $0.00", x+160, card2_y+30, cor_text_main, 10, "Arial Bold");
   DrawLabel(PREFIX+"VAL_TRAIL_INFO", StringFormat("Sessao: %s-%s | Trava: -$%.0f", InpStartTime, InpEndTime, InpMaxDailyLossUSD), x+25, card2_y+50, cor_text_muted, 9, "Arial");

   // Card 4: Estatísticas e Win Rate
   int card3_y = card2_y + 85;
   CreateRect(PREFIX+"CARD4", x+15, card3_y, 290, 85, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_STATS", "Estatisticas de Operacao", x+25, card3_y+10, cor_text_muted, 9, "Arial Bold");
   DrawLabel(PREFIX+"VAL_TRADES", "Trades: 0", x+25, card3_y+30, cor_text_main, 9, "Arial");
   DrawLabel(PREFIX+"VAL_WINS", "Wins: 0 (0%)", x+25, card3_y+48, cor_buy, 9, "Arial");
   DrawLabel(PREFIX+"VAL_LOSSES", "Losses: 0 (0%)", x+150, card3_y+48, cor_sell, 9, "Arial");
   DrawLabel(PREFIX+"VAL_PROFIT_PCT", "Retorno: 0.00%", x+25, card3_y+66, cor_accent, 9, "Arial Bold");

   // Rodapé com Botão Power
   int footer_y = card3_y + 95;
   CreateRect(PREFIX+"BG_FOOTER", x, footer_y, w, 50, cor_bg_panel, cor_border);
   DrawLabel(PREFIX+"LBL_POWER", "Auto Trading:", x+15, footer_y+18, cor_text_main, 10, "Arial Bold");
   DrawLabel(PREFIX+"VAL_STATUS", "Active", x+105, footer_y+18, cor_accent, 10, "Arial Bold");
   CreateButton(PREFIX+"BTN_POWER", "ON", x+w-70, footer_y+12, 50, 25, cor_buy, clrWhite);
   CreateButton(PREFIX+"BTN_REMOVE", "X", x+w-110, footer_y+12, 30, 25, cor_sell, clrWhite);
}

void AtualizarValoresPainel(double floating, double bal, double eq, string statusStr, double maxP) {
   if (Panel_Minimized) return;

   datetime time = TimeCurrent();
   ObjectSetString(0, PREFIX+"VAL_TIME", OBJPROP_TEXT, TimeToString(time, TIME_MINUTES|TIME_SECONDS));

   long seconds_left = SeriesInfoInteger(_Symbol, InpTimeframe, SERIES_LASTBAR_DATE) + PeriodSeconds(InpTimeframe) - TimeCurrent();
   if(seconds_left < 0) seconds_left = 0;
   ObjectSetString(0, PREFIX+"VAL_CANDLE", OBJPROP_TEXT, StringFormat("%02d:%02d", seconds_left / 60, seconds_left % 60));

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   ObjectSetString(0, PREFIX+"VAL_SPREAD", OBJPROP_TEXT, IntegerToString(spread));

   color floatColor = (floating > 0) ? cor_buy : (floating < 0) ? cor_sell : cor_text_main;
   ObjectSetString(0, PREFIX+"VAL_FLOAT", OBJPROP_TEXT, StringFormat("$%.2f", floating));
   ObjectSetInteger(0, PREFIX+"VAL_FLOAT", OBJPROP_COLOR, floatColor);
   ObjectSetString(0, PREFIX+"VAL_BAL", OBJPROP_TEXT, StringFormat("Bal: $%.2f", bal));

   ObjectSetString(0, PREFIX+"VAL_CYCLE", OBJPROP_TEXT, statusStr);
   ObjectSetString(0, PREFIX+"VAL_MAXP", OBJPROP_TEXT, StringFormat("Pico: $%.2f", maxP));

   color profitColor = (daily_profit > 0) ? cor_buy : (daily_profit < 0) ? cor_sell : cor_text_main;
   ObjectSetString(0, PREFIX+"VAL_PROFIT", OBJPROP_TEXT, StringFormat("Hoje: $%.2f", daily_profit));
   ObjectSetInteger(0, PREFIX+"VAL_PROFIT", OBJPROP_COLOR, profitColor);
   ObjectSetString(0, PREFIX+"VAL_TOTAL", OBJPROP_TEXT, StringFormat("Total: $%.2f", total_profit));

   double win_rate = (total_trades > 0) ? ((double)win_trades / total_trades) * 100.0 : 0;
   double loss_rate = (total_trades > 0) ? ((double)loss_trades / total_trades) * 100.0 : 0;
   double profit_pct = (bal > 0) ? (total_profit / bal) * 100.0 : 0;

   ObjectSetString(0, PREFIX+"VAL_TRADES", OBJPROP_TEXT, StringFormat("Trades: %d", total_trades));
   ObjectSetString(0, PREFIX+"VAL_WINS", OBJPROP_TEXT, StringFormat("Wins: %d (%.1f%%)", win_trades, win_rate));
   ObjectSetString(0, PREFIX+"VAL_LOSSES", OBJPROP_TEXT, StringFormat("Losses: %d (%.1f%%)", loss_trades, loss_rate));
   ObjectSetString(0, PREFIX+"VAL_PROFIT_PCT", OBJPROP_TEXT, StringFormat("Retorno: %.2f%%", profit_pct));
   
   ChartRedraw();
}

void AtualizarVisibilidadePainel() {
   bool show = !Panel_Minimized;
   ObjectSetInteger(0, PREFIX+"BG_MAIN", OBJPROP_YSIZE, show ? 530 : 40);
   
   string objs[] = {"LBL_TIME", "VAL_TIME", "LBL_CANDLE", "VAL_CANDLE", "LBL_SPREAD", "VAL_SPREAD",
                    "LBL_STATUS", "VAL_STATUS", "BTN_BUY", "BTN_SELL", "BTN_CLOSE_ALL", "BTN_PANIC",
                    "CARD1", "LBL_FLOAT", "VAL_FLOAT", "VAL_BAL", 
                    "CARD2", "LBL_CYCLE", "VAL_CYCLE", "VAL_MAXP",
                    "CARD3", "LBL_PROFIT", "VAL_PROFIT", "VAL_TOTAL", "VAL_TRAIL_INFO",
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
