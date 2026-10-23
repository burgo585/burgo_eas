//+------------------------------------------------------------------+
//|                                  EA_Stormer_H4_Stoch_EMA70.mq5   |
//|               Estrategia Oficial Stormer: H4 Swing Trade         |
//|        Estocastico Lento (8,3,3) + EMA 70 + Setup 1-2-3          |
//|                    https://github.com/burgo585/burgo_eas         |
//+------------------------------------------------------------------+
#property copyright   "Stormer Strategy - Antigravity Quant Team"
#property link        "https://github.com/burgo585/burgo_eas"
#property version     "1.00"
#property description "Expert Advisor de Swing Trade baseado no setup de Stormer:"
#property description "Filtro de Tendencia: EMA 70 no H4."
#property description "Filtro de Sobrevenda/Sobrecompra: Estocastico Lento (8,3,3) < 20 (Compra) / > 80 (Venda)."
#property description "Gatilho de Acao de Preco: Setup 1-2-3 (Joe Ross / Stormer)."
#property description "Alvo no Topo/Fundo Anterior e Stop Loss na Minima/Maxima do padrao."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Enums
enum ENUM_LOT_TYPE
{
   LOT_FIXED = 0,         // Lote Fixo
   LOT_PERCENT_RISK = 1   // Percentual de Risco da Banca (% Equity)
};

enum ENUM_TRIGGER_MODE
{
   TRIGGER_NEW_BAR_BREAKOUT = 0, // Entrada a Mercado no Rompimento (Candle fechou confirmando)
   TRIGGER_PENDING_STOP = 1      // Ordem Pendente Stop na Maxima/Minima do Candle 3
};

//--- Inputs do Sistema
input group "=== PARAMETROS DO SETUP STORMER ==="
input ENUM_TIMEFRAMES   InpTimeframe         = PERIOD_H4;         // Tempo Grafico Operacional (Padrao H4)
input int               InpEMAPeriod         = 70;                // Periodo da Media Exponencial (EMA 70)
input ENUM_APPLIED_PRICE InpEMAPrice         = PRICE_CLOSE;       // Preco Aplicado da EMA
input int               InpStochK            = 8;                 // Estocastico %K
input int               InpStochD            = 3;                 // Estocastico %D
input int               InpStochSlowing      = 3;                 // Estocastico Slowing (Desaceleracao)
input ENUM_MA_METHOD    InpStochMethod       = MODE_SMA;          // Metodo do Estocastico
input ENUM_STO_PRICE    InpStochPrice        = STO_LOWHIGH;       // Preco do Estocastico
input double            InpStochOversold     = 20.0;              // Nivel de Sobrevenda (Compra)
input double            InpStochOverbought   = 80.0;              // Nivel de Sobrecompra (Venda)
input int               InpStochLookback     = 6;                 // Barras de Recuo para verificar se esteve sobrevendido

input group "=== REGRAS DE TENDENCIA E FILTROS ==="
input bool              InpAllowBuy          = true;              // Permitir Compras
input bool              InpAllowSell         = true;              // Permitir Vendas (Mercados Bidirecionais)
input bool              InpFilterEMA_Slope   = true;              // Exigir inclinacao da EMA (subindo/descendo)
input bool              InpFilterPriceAboveEMA = true;            // Preco deve estar acima da EMA (Compra) / abaixo (Venda)

input group "=== ALVO (TAKE PROFIT) E STOP LOSS ==="
input int               InpSwingLookback     = 20;                // Barras para buscar Topo/Fundo Anterior
input int               InpBufferPoints      = 50;                // Buffer de Folga no Stop Loss (pontos)
input double            InpMinRiskReward     = 1.0;               // Risco-Retorno Minimo para aceitar trade (ex: 1.0 = 1:1)
input bool              InpBreakEvenActive   = true;              // Mover Stop para 0x0 ao atingir 1:1 de Risco
input bool              InpUseTrailing       = false;             // Ativar Trailing Stop
input double            InpTrailingPoints    = 300.0;             // Distancia do Trailing Stop (pontos)

input group "=== GESTAO DE CAPITAL E LOTE ==="
input ENUM_LOT_TYPE     InpLotType           = LOT_PERCENT_RISK;  // Tipo de Calculo de Lote
input double            InpRiskPercent       = 1.0;               // Risco por Trade (% do Capital)
input double            InpFixedLot          = 0.01;              // Lote Fixo (se modo fixo)
input double            InpMaxSpreadPoints   = 50.0;              // Spread Maximo Permitido (pontos)

input group "=== CONFIGURACOES DE EXECUCAO ==="
input ENUM_TRIGGER_MODE InpTriggerMode       = TRIGGER_NEW_BAR_BREAKOUT; // Modo de Gatilho de Entrada
input ulong             InpMagicNumber       = 708123;            // Magic Number do Robo
input string            InpComment           = "Stormer_H4_123";  // Comentario da Ordem
input bool              InpDrawVisuals       = true;              // Desenhar niveis no grafico

//--- Objetos Globais
CTrade         trade;
CPositionInfo  posInfo;
CAccountInfo   accInfo;
CSymbolInfo    symInfo;

int            h_ema = INVALID_HANDLE;
int            h_stoch = INVALID_HANDLE;
datetime       lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);

   if(!symInfo.Name(_Symbol))
   {
      Print("[ERRO] Falha ao inicializar CSymbolInfo para: ", _Symbol);
      return INIT_FAILED;
   }
   symInfo.Refresh();

   // Inicializa Indicadores Oficiais
   h_ema = iMA(_Symbol, InpTimeframe, InpEMAPeriod, 0, MODE_EMA, InpEMAPrice);
   if(h_ema == INVALID_HANDLE)
   {
      Print("[ERRO] Falha ao criar handle da EMA 70: ", GetLastError());
      return INIT_FAILED;
   }

   h_stoch = iStochastic(_Symbol, InpTimeframe, InpStochK, InpStochD, InpStochSlowing, InpStochMethod, InpStochPrice);
   if(h_stoch == INVALID_HANDLE)
   {
      Print("[ERRO] Falha ao criar handle do Estocastico Lento (8,3,3): ", GetLastError());
      return INIT_FAILED;
   }

   PrintFormat("[SUCESSO] EA Stormer H4 inicializado no ativo %s. EMA: %d | Stoch: (%d,%d,%d)", 
               _Symbol, InpEMAPeriod, InpStochK, InpStochD, InpStochSlowing);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(h_ema != INVALID_HANDLE) IndicatorRelease(h_ema);
   if(h_stoch != INVALID_HANDLE) IndicatorRelease(h_stoch);

   if(InpDrawVisuals)
   {
      ObjectsDeleteAll(0, "Stormer_");
   }
   Comment("");
}

//+------------------------------------------------------------------+
//| Checa se abriu uma nova barra no timeframe operacional           |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = (datetime)SeriesInfoInteger(_Symbol, InpTimeframe, SERIES_LASTBAR_DATE);
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calcula o lote com base no risco financeiro e distancia do SL   |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl_distance_points)
{
   if(InpLotType == LOT_FIXED)
      return InpFixedLot;

   if(sl_distance_points <= 0)
      return symInfo.LotsMin();

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (InpRiskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(tickSize <= 0 || point <= 0 || tickValue <= 0)
      return symInfo.LotsMin();

   double pointsPerTick = tickSize / point;
   double moneyPerPointPerLot = tickValue / pointsPerTick;

   double rawLot = riskMoney / (sl_distance_points * moneyPerPointPerLot);

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(step > 0)
      rawLot = MathFloor(rawLot / step) * step;

   if(rawLot < minLot) rawLot = minLot;
   if(rawLot > maxLot) rawLot = maxLot;

   return NormalizeDouble(rawLot, 2);
}

//+------------------------------------------------------------------+
//| Gerencia posicoes abertas (Break-Even e Trailing Stop)           |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber) continue;

      double openPrice = posInfo.PriceOpen();
      double currentSL = posInfo.StopLoss();
      double currentTP = posInfo.TakeProfit();
      double currentPrice = (posInfo.PositionType() == POSITION_TYPE_BUY) ? 
                            SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // 1. Break-Even: Quando alcanca 1:1 de Risco
      if(InpBreakEvenActive && currentSL > 0)
      {
         if(posInfo.PositionType() == POSITION_TYPE_BUY)
         {
            double riskDist = openPrice - currentSL;
            if(riskDist > 0 && currentPrice >= openPrice + riskDist)
            {
               // Se o SL ainda esta abaixo do preco de entrada
               if(currentSL < openPrice)
               {
                  double newSL = openPrice + 2 * _Point;
                  trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
                  PrintFormat("[BREAK-EVEN] Compra #%d movida para 0x0 (Preco: %.5f)", posInfo.Ticket(), newSL);
               }
            }
         }
         else if(posInfo.PositionType() == POSITION_TYPE_SELL)
         {
            double riskDist = currentSL - openPrice;
            if(riskDist > 0 && currentPrice <= openPrice - riskDist)
            {
               // Se o SL ainda esta acima do preco de entrada
               if(currentSL > openPrice)
               {
                  double newSL = openPrice - 2 * _Point;
                  trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
                  PrintFormat("[BREAK-EVEN] Venda #%d movida para 0x0 (Preco: %.5f)", posInfo.Ticket(), newSL);
               }
            }
         }
      }

      // 2. Trailing Stop
      if(InpUseTrailing && InpTrailingPoints > 0)
      {
         double trailDist = InpTrailingPoints * _Point;
         if(posInfo.PositionType() == POSITION_TYPE_BUY)
         {
            if(currentPrice - openPrice > trailDist)
            {
               double proposedSL = currentPrice - trailDist;
               if(proposedSL > currentSL + 5 * _Point)
               {
                  trade.PositionModify(posInfo.Ticket(), proposedSL, currentTP);
               }
            }
         }
         else if(posInfo.PositionType() == POSITION_TYPE_SELL)
         {
            if(openPrice - currentPrice > trailDist)
            {
               double proposedSL = currentPrice + trailDist;
               if(currentSL == 0 || proposedSL < currentSL - 5 * _Point)
               {
                  trade.PositionModify(posInfo.Ticket(), proposedSL, currentTP);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Checa se ja temos posicao aberta ou ordem pendente               |
//+------------------------------------------------------------------+
bool HasOpenOrderOrPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
            return true;
      }
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Funcao OnTick: Execucao Causal com Zero Lookahead Bias           |
//+------------------------------------------------------------------+
void OnTick()
{
   symInfo.Refresh();
   symInfo.RefreshRates();

   // Gerencia posicoes existentes a cada tick
   ManageOpenPositions();

   // Exibe painel em tela
   UpdateDashboard();

   // Avaliacao de novos setups apenas na abertura de nova barra fechada
   if(!IsNewBar()) return;

   // Se ja estiver posicionado, respeita a operacao em andamento (Swing Trade)
   if(HasOpenOrderOrPosition()) return;

   // Checa filtro de spread
   double currentSpread = (symInfo.Ask() - symInfo.Bid()) / _Point;
   if(currentSpread > InpMaxSpreadPoints)
   {
      PrintFormat("[FILTRO] Spread atual (%.1f pts) excede o maximo permitido (%.1f pts)", currentSpread, InpMaxSpreadPoints);
      return;
   }

   // Copia dados dos indicadores nas barras FECHADAS (shift 1, 2, 3...)
   double emaVal[3];
   if(CopyBuffer(h_ema, 0, 1, 3, emaVal) < 3) return;
   // emaVal[2] = shift 1, emaVal[1] = shift 2, emaVal[0] = shift 3

   double stochMain[10];
   double stochSig[10];
   int stochRead = CopyBuffer(h_stoch, 0, 1, InpStochLookback + 3, stochMain);
   CopyBuffer(h_stoch, 1, 1, InpStochLookback + 3, stochSig);
   if(stochRead < InpStochLookback) return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int ratesCount = CopyRates(_Symbol, InpTimeframe, 1, InpSwingLookback + 10, rates);
   if(ratesCount < InpSwingLookback + 5) return;

   // Indexacao das velas fechadas:
   // rates[0] = Candle 3 (Barra 1 fechada recentemente)
   // rates[1] = Candle 2 (Barra 2 - Fundo/Topo do padrao 1-2-3)
   // rates[2] = Candle 1 (Barra 3 - Referencia do padrao 1-2-3)

   bool emaSubindo = (emaVal[2] > emaVal[1]); // EMA shift 1 > EMA shift 2
   bool emaDescendo = (emaVal[2] < emaVal[1]); // EMA shift 1 < EMA shift 2

   // Checa se o estocastico esteve sobrevendido (< 20) ou sobrecomprado (> 80)
   bool stochEstiveOversold = false;
   bool stochEstiveOverbought = false;

   for(int i = 0; i < InpStochLookback; i++)
   {
      if(stochMain[stochRead - 1 - i] < InpStochOversold) stochEstiveOversold = true;
      if(stochMain[stochRead - 1 - i] > InpStochOverbought) stochEstiveOverbought = true;
   }

   //+---------------------------------------------------------------+
   //| 1. SETUP 1-2-3 DE COMPRA (STORMER)                           |
   //+---------------------------------------------------------------+
   if(InpAllowBuy)
   {
      bool condTrend = (!InpFilterEMA_Slope || emaSubindo) && 
                       (!InpFilterPriceAboveEMA || rates[0].close >= emaVal[2]);

      bool condStoch = stochEstiveOversold;

      // Padrao 1-2-3 de Fundo:
      // Candle 2 (rates[1]) tem a menor minima entre Candle 1 e 3
      bool cond123Buy = (rates[1].low < rates[2].low) && (rates[0].low > rates[1].low);

      if(condTrend && condStoch && cond123Buy)
      {
         // Gatilho: Rompimento da maxima do Candle 3 (rates[0].high)
         double triggerPrice = rates[0].high;
         double stopLossPrice = rates[1].low - (InpBufferPoints * _Point);

         // Take Profit: Topo anterior antes do recuo para o fundo
         double highestHigh = rates[2].high;
         for(int k = 2; k < InpSwingLookback; k++)
         {
            if(rates[k].high > highestHigh) highestHigh = rates[k].high;
         }
         double takeProfitPrice = highestHigh;

         double riskPoints = (triggerPrice - stopLossPrice) / _Point;
         double rewardPoints = (takeProfitPrice - triggerPrice) / _Point;

         if(riskPoints > 0 && (rewardPoints / riskPoints >= InpMinRiskReward))
         {
            double lot = CalculateLotSize(riskPoints);

            if(InpTriggerMode == TRIGGER_NEW_BAR_BREAKOUT)
            {
               // Entrada a mercado se a barra atual abrir rompendo ou se preco Ask atual >= trigger
               double ask = symInfo.Ask();
               if(ask >= triggerPrice)
               {
                  if(trade.Buy(lot, _Symbol, ask, stopLossPrice, takeProfitPrice, InpComment))
                  {
                     PrintFormat("[COMPRA 1-2-3 EXECUTADA] Lote: %.2f | Gatilho: %.5f | SL: %.5f | TP: %.5f | R:R: %.2f",
                                 lot, ask, stopLossPrice, takeProfitPrice, rewardPoints / riskPoints);
                     DrawSetupLines(rates[1].time, stopLossPrice, triggerPrice, takeProfitPrice, true);
                  }
               }
               else
               {
                  // Se ainda nao rompeu, coloca ordem Buy Stop na maxima
                  double buyStopPrice = NormalizeDouble(triggerPrice + symInfo.Spread() * _Point, symInfo.Digits());
                  datetime expiration = TimeCurrent() + PeriodSeconds(InpTimeframe) * 2;
                  trade.BuyStop(lot, buyStopPrice, _Symbol, stopLossPrice, takeProfitPrice, ORDER_TIME_SPECIFIED, expiration, InpComment);
                  PrintFormat("[BUY STOP 1-2-3 AGENDADA] Lote: %.2f | Preco: %.5f | SL: %.5f | TP: %.5f", lot, buyStopPrice, stopLossPrice, takeProfitPrice);
               }
            }
            else
            {
               double buyStopPrice = NormalizeDouble(triggerPrice + symInfo.Spread() * _Point, symInfo.Digits());
               datetime expiration = TimeCurrent() + PeriodSeconds(InpTimeframe) * 2;
               trade.BuyStop(lot, buyStopPrice, _Symbol, stopLossPrice, takeProfitPrice, ORDER_TIME_SPECIFIED, expiration, InpComment);
            }
         }
      }
   }

   //+---------------------------------------------------------------+
   //| 2. SETUP 1-2-3 DE VENDA (SIMETRICO STORMER)                  |
   //+---------------------------------------------------------------+
   if(InpAllowSell)
   {
      bool condTrend = (!InpFilterEMA_Slope || emaDescendo) && 
                       (!InpFilterPriceAboveEMA || rates[0].close <= emaVal[2]);

      bool condStoch = stochEstiveOverbought;

      // Padrao 1-2-3 de Topo:
      // Candle 2 (rates[1]) tem a maior maxima entre Candle 1 e 3
      bool cond123Sell = (rates[1].high > rates[2].high) && (rates[0].high < rates[1].high);

      if(condTrend && condStoch && cond123Sell)
      {
         // Gatilho: Perda da minima do Candle 3 (rates[0].low)
         double triggerPrice = rates[0].low;
         double stopLossPrice = rates[1].high + (InpBufferPoints * _Point);

         // Take Profit: Fundo anterior antes da alta
         double lowestLow = rates[2].low;
         for(int k = 2; k < InpSwingLookback; k++)
         {
            if(rates[k].low < lowestLow) lowestLow = rates[k].low;
         }
         double takeProfitPrice = lowestLow;

         double riskPoints = (stopLossPrice - triggerPrice) / _Point;
         double rewardPoints = (triggerPrice - takeProfitPrice) / _Point;

         if(riskPoints > 0 && (rewardPoints / riskPoints >= InpMinRiskReward))
         {
            double lot = CalculateLotSize(riskPoints);

            if(InpTriggerMode == TRIGGER_NEW_BAR_BREAKOUT)
            {
               double bid = symInfo.Bid();
               if(bid <= triggerPrice)
               {
                  if(trade.Sell(lot, _Symbol, bid, stopLossPrice, takeProfitPrice, InpComment))
                  {
                     PrintFormat("[VENDA 1-2-3 EXECUTADA] Lote: %.2f | Gatilho: %.5f | SL: %.5f | TP: %.5f | R:R: %.2f",
                                 lot, bid, stopLossPrice, takeProfitPrice, rewardPoints / riskPoints);
                     DrawSetupLines(rates[1].time, stopLossPrice, triggerPrice, takeProfitPrice, false);
                  }
               }
               else
               {
                  double sellStopPrice = NormalizeDouble(triggerPrice, symInfo.Digits());
                  datetime expiration = TimeCurrent() + PeriodSeconds(InpTimeframe) * 2;
                  trade.SellStop(lot, sellStopPrice, _Symbol, stopLossPrice, takeProfitPrice, ORDER_TIME_SPECIFIED, expiration, InpComment);
                  PrintFormat("[SELL STOP 1-2-3 AGENDADA] Lote: %.2f | Preco: %.5f | SL: %.5f | TP: %.5f", lot, sellStopPrice, stopLossPrice, takeProfitPrice);
               }
            }
            else
            {
               double sellStopPrice = NormalizeDouble(triggerPrice, symInfo.Digits());
               datetime expiration = TimeCurrent() + PeriodSeconds(InpTimeframe) * 2;
               trade.SellStop(lot, sellStopPrice, _Symbol, stopLossPrice, takeProfitPrice, ORDER_TIME_SPECIFIED, expiration, InpComment);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Desenha linhas visuais do Setup no Grafico                       |
//+------------------------------------------------------------------+
void DrawSetupLines(datetime timeRef, double sl, double entry, double tp, bool isBuy)
{
   if(!InpDrawVisuals) return;

   string prefix = "Stormer_" + TimeToString(timeRef) + "_";
   color clrSL = clrRed;
   color clrEntry = isBuy ? clrDodgerBlue : clrOrangeRed;
   color clrTP = clrLimeGreen;

   ObjectCreate(0, prefix + "SL", OBJ_HLINE, 0, 0, sl);
   ObjectSetInteger(0, prefix + "SL", OBJPROP_COLOR, clrSL);
   ObjectSetInteger(0, prefix + "SL", OBJPROP_STYLE, STYLE_DASH);

   ObjectCreate(0, prefix + "Entry", OBJ_HLINE, 0, 0, entry);
   ObjectSetInteger(0, prefix + "Entry", OBJPROP_COLOR, clrEntry);
   ObjectSetInteger(0, prefix + "Entry", OBJPROP_STYLE, STYLE_SOLID);

   ObjectCreate(0, prefix + "TP", OBJ_HLINE, 0, 0, tp);
   ObjectSetInteger(0, prefix + "TP", OBJPROP_COLOR, clrTP);
   ObjectSetInteger(0, prefix + "TP", OBJPROP_STYLE, STYLE_DASH);
}

//+------------------------------------------------------------------+
//| Atualiza Dashboard de Informacoes no Canto da Tela               |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   double emaVal[2];
   CopyBuffer(h_ema, 0, 1, 2, emaVal);

   double stochVal[1];
   CopyBuffer(h_stoch, 0, 1, 1, stochVal);

   string trendStr = (emaVal[1] > emaVal[0]) ? "ALTA (Subindo)" : "BAIXA (Descendo)";
   color trendColor = (emaVal[1] > emaVal[0]) ? clrLimeGreen : clrRed;

   string stochState = "NEUTRO";
   if(stochVal[0] < InpStochOversold) stochState = "SOBREVENDIDO (< 20)";
   else if(stochVal[0] > InpStochOverbought) stochState = "SOBRECOMPRADO (> 80)";

   string text = "\n" +
      "====================================================\n" +
      "       ROBO STORMER H4 SWING TRADE (MQL5)           \n" +
      "====================================================\n" +
      StringFormat(" Ativo: %s | Timeframe: H4\n", _Symbol) +
      StringFormat(" Tendencia EMA 70: %s (Val: %.5f)\n", trendStr, emaVal[1]) +
      StringFormat(" Estocastico Lento (8,3,3): %.2f [%s]\n", stochVal[0], stochState) +
      StringFormat(" Risco por Trade: %.1f%% do Capital\n", InpRiskPercent) +
      StringFormat(" Spread Atual: %.1f pts (Max: %.1f pts)\n", (symInfo.Ask() - symInfo.Bid()) / _Point, InpMaxSpreadPoints) +
      StringFormat(" Saldo: %.2f | Equity: %.2f\n", AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY)) +
      "====================================================\n" +
      " Regra de Ouro Stormer: Baixo DD e Alta Assimetria\n" +
      "====================================================";

   Comment(text);
}
//+------------------------------------------------------------------+
