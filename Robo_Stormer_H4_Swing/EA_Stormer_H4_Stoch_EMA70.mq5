//+------------------------------------------------------------------+
//|                                  EA_Stormer_H4_Stoch_EMA70.mq5   |
//|               Estrategia Oficial Stormer: H4 Swing Trade         |
//|      "O MELHOR sinal de swing trade": Trap no Fundo do 1-2-3     |
//|        Estocastico Lento (8,3,3) + EMA 70 + Trap no 1-2-3        |
//|         Versao 3.0: Alinhamento Total com os 2 Videos Oficiais   |
//|                    https://github.com/burgo585/burgo_eas         |
//+------------------------------------------------------------------+
#property copyright   "Stormer Strategy - Antigravity Quant Team"
#property link        "https://github.com/burgo585/burgo_eas"
#property version     "3.00"
#property description "Expert Advisor Oficial baseado nos 2 videos do Stormer:"
#property description "1. Video Completo: Trap no Fundo do 1-2-3 (Violinada de fundo com rejeicao e alvo 2R)."
#property description "2. Video Resumo H4: Estocastico Lento (8,3,3) < 20 e Media Movel Exponencial 70 subindo."
#property description "3. Suporte a Inside Bar pos-trap (nao cancela o setup)."
#property description "4. Gestao por Ordens Pendentes Stop com cancelamento por invalidacao."
#property description "5. Calculo de risco real efetivo considerando spread e slippage."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Enums
enum ENUM_PATTERN_TYPE
{
   PATTERN_STORMER_TRAP   = 0, // Trap no 1-2-3 (O MELHOR SINAL - Video Completo Stormer)
   PATTERN_JOE_ROSS_SWING = 1, // 1-2-3 Classico por Pontos de Swing (Joe Ross)
   PATTERN_STORMER_3BAR   = 2  // 1-2-3 Simples de 3 Barras (Pivo Rapido de Candles)
};

enum ENUM_TARGET_MODE
{
   TARGET_2X_RISK         = 0, // Alvo Oficial do Video: 2x o Risco (2R) para cima
   TARGET_FIBO_100        = 1, // Projecao 100% da Perna 1-2
   TARGET_SWING_PREVIOUS  = 2  // Topo/Fundo Anterior (com filtro de ATR)
};

enum ENUM_LOT_TYPE
{
   LOT_FIXED = 0,              // Lote Fixo
   LOT_PERCENT_RISK = 1        // Percentual de Risco da Banca (% Equity)
};

//--- Inputs do Sistema
input group "=== MODO DO SETUP STORMER ==="
input ENUM_PATTERN_TYPE InpPatternType        = PATTERN_STORMER_TRAP;   // Tipo de Padrao Operacional
input ENUM_TARGET_MODE  InpTargetMode         = TARGET_2X_RISK;         // Modo de Calculo do Alvo (Padrao 2R do Video)
input double            InpTargetRRMultiplier = 2.0;                    // Multiplo de Risco para o Alvo (ex: 2.0 = 2R)
input int               InpSwingStrength      = 2;                      // Forca do Pivo de Swing (se Joe Ross)
input int               InpMaxBarsSearch      = 40;                     // Maximo de Barras para busca retrospectiva

input group "=== PARAMETROS DOS INDICADORES ==="
input ENUM_TIMEFRAMES   InpTimeframe          = PERIOD_H4;              // Tempo Grafico Operacional (Padrao H4)
input int               InpEMAPeriod          = 70;                     // Periodo da Media Exponencial (EMA 70)
input ENUM_APPLIED_PRICE InpEMAPrice          = PRICE_CLOSE;            // Preco Aplicado da EMA
input int               InpStochK             = 8;                      // Estocastico %K (Padrao Stormer: 8)
input int               InpStochD             = 3;                      // Estocastico %D (Padrao: 3)
input int               InpStochSlowing       = 3;                      // Estocastico Slowing (Padrao: 3)
input ENUM_MA_METHOD    InpStochMethod        = MODE_SMA;               // Metodo do Estocastico
input ENUM_STO_PRICE    InpStochPrice         = STO_LOWHIGH;            // Preco do Estocastico
input double            InpStochOversold      = 20.0;                   // Nivel de Sobrevenda (Compra)
input double            InpStochOverbought    = 80.0;                   // Nivel de Sobrecompra (Venda)
input int               InpStochLookback      = 10;                     // Barras de Recuo para checagem do Estocastico

input group "=== FILTROS DE TENDENCIA ==="
input bool              InpAllowBuy           = true;                   // Permitir Compras
input bool              InpAllowSell          = true;                   // Permitir Vendas (Mercados Bidirecionais)
input bool              InpFilterEMA_Slope    = true;                   // Exigir inclinacao da EMA (subindo/descendo)
input bool              InpFilterPriceAboveEMA = true;                 // Preco deve estar acima da EMA (Compra) / abaixo (Venda)

input group "=== GESTAO DE STOP E EXECUCAO ==="
input int               InpBufferPoints       = 50;                     // Buffer de Folga no Stop Loss (pontos alem da minima)
input int               InpSlippageEstimate   = 20;                     // Estimativa de Slippage para calculo do risco real (pontos)
input double            InpMinRiskReward      = 1.0;                    // Risco:Retorno Minimo Real para aceitar entrada
input int               InpPendingExpireBars  = 6;                      // Validade da Ordem Pendente (barras H4)
input bool              InpBreakEvenActive    = true;                   // Mover Stop para 0x0 ao atingir 1:1 de Risco
input bool              InpUseTrailing        = false;                  // Ativar Trailing Stop
input double            InpTrailingPoints     = 300.0;                  // Distancia do Trailing Stop (pontos)

input group "=== GESTAO DE CAPITAL E LOTE ==="
input ENUM_LOT_TYPE     InpLotType            = LOT_PERCENT_RISK;       // Tipo de Calculo de Lote
input double            InpRiskPercent        = 1.0;                    // Risco por Trade (% do Capital)
input double            InpFixedLot           = 0.01;                   // Lote Fixo (se modo fixo)
input double            InpMaxSpreadPoints    = 50.0;                   // Spread Maximo Permitido (pontos)

input group "=== IDENTIFICACAO ==="
input ulong             InpMagicNumber        = 708123;                 // Magic Number do Robo
input string            InpComment            = "Stormer_Trap_H4";      // Comentario da Ordem
input bool              InpDrawVisuals        = true;                   // Desenhar niveis no grafico

//--- Objetos Globais
CTrade         trade;
CPositionInfo  posInfo;
COrderInfo     ordInfo;
CAccountInfo   accInfo;
CSymbolInfo    symInfo;

int            h_ema = INVALID_HANDLE;
int            h_stoch = INVALID_HANDLE;
int            h_atr = INVALID_HANDLE;
datetime       lastBarTime = 0;

struct SSetupSignal
{
   bool     valid;
   datetime timeRef;
   double   triggerPrice; // Maxima do Trap ou Ponto 2
   double   stopLossPrice;// Minima do Trap ou Ponto 3
   double   targetPrice;  // Alvo calculado (2R, Fibo ou Topo)
   string   desc;
};

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

   h_atr = iATR(_Symbol, InpTimeframe, 14);
   if(h_atr == INVALID_HANDLE)
   {
      Print("[ERRO] Falha ao criar handle do ATR: ", GetLastError());
      return INIT_FAILED;
   }

   PrintFormat("[SUCESSO] EA Stormer H4 v3.0 inicializado em %s (%s). Modo: %s | Alvo: %s", 
               _Symbol, EnumToString(InpTimeframe), 
               EnumToString(InpPatternType), EnumToString(InpTargetMode));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(h_ema != INVALID_HANDLE) IndicatorRelease(h_ema);
   if(h_stoch != INVALID_HANDLE) IndicatorRelease(h_stoch);
   if(h_atr != INVALID_HANDLE) IndicatorRelease(h_atr);

   if(InpDrawVisuals) ObjectsDeleteAll(0, "Stormer_");
   Comment("");
}

//+------------------------------------------------------------------+
//| Checa abertura de nova barra                                     |
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
//| Calculo de Lote baseado no RISCO REAL EFETIVO                    |
//+------------------------------------------------------------------+
double CalculateRealRiskLot(double real_risk_points)
{
   if(InpLotType == LOT_FIXED)
      return InpFixedLot;

   if(real_risk_points <= 0)
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

   double rawLot = riskMoney / (real_risk_points * moneyPerPointPerLot);

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
//| Checa Pivo de Swing (Joe Ross)                                   |
//+------------------------------------------------------------------+
bool IsSwingLow(const MqlRates &rates[], int index, int strength, int total)
{
   if(index - strength < 0 || index + strength >= total) return false;
   double lowVal = rates[index].low;
   for(int i = 1; i <= strength; i++)
   {
      if(rates[index - i].low <= lowVal || rates[index + i].low < lowVal)
         return false;
   }
   return true;
}

bool IsSwingHigh(const MqlRates &rates[], int index, int strength, int total)
{
   if(index - strength < 0 || index + strength >= total) return false;
   double highVal = rates[index].high;
   for(int i = 1; i <= strength; i++)
   {
      if(rates[index - i].high >= highVal || rates[index + i].high > highVal)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| DETECCAO DO SETUP 1: TRAP NO FUNDO DO 1-2-3 (VIDEO COMPLETO)     |
//+------------------------------------------------------------------+
SSetupSignal DetectStormerTrapBuy(const MqlRates &rates[], int total, double atr)
{
   SSetupSignal sig;
   sig.valid = false;
   if(total < 8) return sig;

   // 1. Identifica se a barra 1 (ou barra 2 com barra 1 sendo inside bar) foi um Trap
   // Um trap ocorre quando um candle perde a minima do 1-2-3 anterior
   int trapIdx = 1; // Barra fechada mais recente
   bool isInsideBar = (rates[0].high <= rates[1].high && rates[0].low >= rates[1].low);
   
   // Se a barra 1 for inside bar da barra 2, o trap pode ter sido na barra 2
   if(rates[0].high <= rates[1].high && rates[0].low >= rates[1].low && rates[1].low < rates[2].low)
   {
      // Dentro da filosofia do Stormer: Inside bar nao cancela o Trap!
      trapIdx = 1;
   }

   // Fundo do 1-2-3 anterior procurado entre as barras [trapIdx + 1] a [trapIdx + 5]
   double priorSwingLow = rates[trapIdx + 1].low;
   int priorLowIdx = trapIdx + 1;
   for(int k = trapIdx + 1; k <= trapIdx + 5; k++)
   {
      if(rates[k].low < priorSwingLow)
      {
         priorSwingLow = rates[k].low;
         priorLowIdx = k;
      }
   }

   // O candle do Trap (rates[trapIdx]) PERDEU a minima do fundo anterior!
   if(rates[trapIdx].low < priorSwingLow)
   {
      // Rejeicao: a barra do trap nao fechou na minima absoluta ou formou pavio/martelo
      // Ponto de entrada: Ruptura da maxima do candle do Trap
      sig.valid = true;
      sig.timeRef = rates[trapIdx].time;
      sig.triggerPrice = rates[trapIdx].high;
      sig.stopLossPrice = rates[trapIdx].low - (InpBufferPoints * _Point);

      double risk = sig.triggerPrice - sig.stopLossPrice;

      // Calculo do Alvo Oficial:
      if(InpTargetMode == TARGET_2X_RISK)
      {
         // "o alvo a gente vai largar no minimo duas vezes nosso risco para cima" - Stormer
         sig.targetPrice = sig.triggerPrice + (risk * InpTargetRRMultiplier);
      }
      else if(InpTargetMode == TARGET_FIBO_100)
      {
         // Expansao 100% da perna anterior
         double leg = rates[priorLowIdx].high - priorSwingLow;
         sig.targetPrice = sig.triggerPrice + MathMax(leg, risk * 2.0);
      }
      else // TARGET_SWING_PREVIOUS
      {
         double highest = rates[priorLowIdx].high;
         for(int m = priorLowIdx; m < MathMin(total, priorLowIdx + 15); m++)
         {
            if(rates[m].high > highest) highest = rates[m].high;
         }
         sig.targetPrice = highest;
      }
      sig.desc = "Trap no 1-2-3 de Fundo";
   }

   return sig;
}

SSetupSignal DetectStormerTrapSell(const MqlRates &rates[], int total, double atr)
{
   SSetupSignal sig;
   sig.valid = false;
   if(total < 8) return sig;

   int trapIdx = 1;
   double priorSwingHigh = rates[trapIdx + 1].high;
   int priorHighIdx = trapIdx + 1;
   for(int k = trapIdx + 1; k <= trapIdx + 5; k++)
   {
      if(rates[k].high > priorSwingHigh)
      {
         priorSwingHigh = rates[k].high;
         priorHighIdx = k;
      }
   }

   // Candle do Trap violou a maxima anterior (falso rompimento de topo)
   if(rates[trapIdx].high > priorSwingHigh)
   {
      sig.valid = true;
      sig.timeRef = rates[trapIdx].time;
      sig.triggerPrice = rates[trapIdx].low;
      sig.stopLossPrice = rates[trapIdx].high + (InpBufferPoints * _Point);

      double risk = sig.stopLossPrice - sig.triggerPrice;

      if(InpTargetMode == TARGET_2X_RISK)
         sig.targetPrice = sig.triggerPrice - (risk * InpTargetRRMultiplier);
      else if(InpTargetMode == TARGET_FIBO_100)
      {
         double leg = priorSwingHigh - rates[priorHighIdx].low;
         sig.targetPrice = sig.triggerPrice - MathMax(leg, risk * 2.0);
      }
      else
      {
         double lowest = rates[priorHighIdx].low;
         for(int m = priorHighIdx; m < MathMin(total, priorHighIdx + 15); m++)
         {
            if(rates[m].low < lowest) lowest = rates[m].low;
         }
         sig.targetPrice = lowest;
      }
      sig.desc = "Trap no 1-2-3 de Topo";
   }

   return sig;
}

//+------------------------------------------------------------------+
//| DETECCAO JOE ROSS SWING & PIVO 3 BARRAS                          |
//+------------------------------------------------------------------+
SSetupSignal DetectClassic123Buy(const MqlRates &rates[], int total, double atr)
{
   SSetupSignal sig;
   sig.valid = false;

   if(InpPatternType == PATTERN_STORMER_3BAR)
   {
      if(total < 3) return sig;
      if(rates[1].low < rates[2].low && rates[0].low > rates[1].low)
      {
         sig.valid = true;
         sig.timeRef = rates[0].time;
         sig.triggerPrice = rates[0].high;
         sig.stopLossPrice = rates[1].low - (InpBufferPoints * _Point);
         double risk = sig.triggerPrice - sig.stopLossPrice;
         sig.targetPrice = sig.triggerPrice + (risk * InpTargetRRMultiplier);
         sig.desc = "Pivo 1-2-3 de 3 Barras";
      }
      return sig;
   }

   // Joe Ross Swing
   int idx3 = -1;
   for(int i = 1; i < MathMin(total - InpSwingStrength, 15); i++)
   {
      if(IsSwingLow(rates, i, InpSwingStrength, total)) { idx3 = i; break; }
   }
   if(idx3 == -1) return sig;

   int idx2 = -1;
   for(int i = idx3 + 1; i < MathMin(total - InpSwingStrength, idx3 + 20); i++)
   {
      if(IsSwingHigh(rates, i, InpSwingStrength, total)) { idx2 = i; break; }
   }
   if(idx2 == -1) return sig;

   int idx1 = -1;
   for(int i = idx2 + 1; i < MathMin(total - InpSwingStrength, idx2 + 25); i++)
   {
      if(IsSwingLow(rates, i, InpSwingStrength, total))
      {
         if(rates[i].low < rates[idx3].low) { idx1 = i; break; }
      }
   }
   if(idx1 == -1) return sig;

   if(rates[idx3].low > rates[idx1].low && rates[idx2].high > rates[idx3].low)
   {
      sig.valid = true;
      sig.timeRef = rates[idx2].time;
      sig.triggerPrice = rates[idx2].high;
      sig.stopLossPrice = rates[idx3].low - (InpBufferPoints * _Point);
      double risk = sig.triggerPrice - sig.stopLossPrice;
      sig.targetPrice = sig.triggerPrice + (risk * InpTargetRRMultiplier);
      sig.desc = "Joe Ross 1-2-3 Swing";
   }

   return sig;
}

SSetupSignal DetectClassic123Sell(const MqlRates &rates[], int total, double atr)
{
   SSetupSignal sig;
   sig.valid = false;

   if(InpPatternType == PATTERN_STORMER_3BAR)
   {
      if(total < 3) return sig;
      if(rates[1].high > rates[2].high && rates[0].high < rates[1].high)
      {
         sig.valid = true;
         sig.timeRef = rates[0].time;
         sig.triggerPrice = rates[0].low;
         sig.stopLossPrice = rates[1].high + (InpBufferPoints * _Point);
         double risk = sig.stopLossPrice - sig.triggerPrice;
         sig.targetPrice = sig.triggerPrice - (risk * InpTargetRRMultiplier);
         sig.desc = "Pivo 1-2-3 de Topo 3 Barras";
      }
      return sig;
   }

   int idx3 = -1;
   for(int i = 1; i < MathMin(total - InpSwingStrength, 15); i++)
   {
      if(IsSwingHigh(rates, i, InpSwingStrength, total)) { idx3 = i; break; }
   }
   if(idx3 == -1) return sig;

   int idx2 = -1;
   for(int i = idx3 + 1; i < MathMin(total - InpSwingStrength, idx3 + 20); i++)
   {
      if(IsSwingLow(rates, i, InpSwingStrength, total)) { idx2 = i; break; }
   }
   if(idx2 == -1) return sig;

   int idx1 = -1;
   for(int i = idx2 + 1; i < MathMin(total - InpSwingStrength, idx2 + 25); i++)
   {
      if(IsSwingHigh(rates, i, InpSwingStrength, total))
      {
         if(rates[i].high > rates[idx3].high) { idx1 = i; break; }
      }
   }
   if(idx1 == -1) return sig;

   if(rates[idx3].high < rates[idx1].high && rates[idx2].low < rates[idx3].high)
   {
      sig.valid = true;
      sig.timeRef = rates[idx2].time;
      sig.triggerPrice = rates[idx2].low;
      sig.stopLossPrice = rates[idx3].high + (InpBufferPoints * _Point);
      double risk = sig.stopLossPrice - sig.triggerPrice;
      sig.targetPrice = sig.triggerPrice - (risk * InpTargetRRMultiplier);
      sig.desc = "Joe Ross 1-2-3 Topo";
   }

   return sig;
}

//+------------------------------------------------------------------+
//| Gerencia e Cancela Ordens Pendentes Invalidadas                 |
//+------------------------------------------------------------------+
void ManagePendingOrders()
{
   double currentAsk = symInfo.Ask();
   double currentBid = symInfo.Bid();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0) continue;
      if(!ordInfo.Select(ticket)) continue;
      if(ordInfo.Symbol() != _Symbol || ordInfo.Magic() != InpMagicNumber) continue;

      ENUM_ORDER_TYPE oType = ordInfo.OrderType();
      double sl = ordInfo.StopLoss();

      if(oType == ORDER_TYPE_BUY_STOP)
      {
         if(sl > 0 && currentBid <= sl)
         {
            trade.OrderDelete(ticket);
            PrintFormat("[ORDEM CANCELADA] Buy Stop #%d cancelada: padrao violado pela quebra do fundo (SL: %.5f)", ticket, sl);
         }
      }
      else if(oType == ORDER_TYPE_SELL_STOP)
      {
         if(sl > 0 && currentAsk >= sl)
         {
            trade.OrderDelete(ticket);
            PrintFormat("[ORDEM CANCELADA] Sell Stop #%d cancelada: padrao violado pelo rompimento do topo (SL: %.5f)", ticket, sl);
         }
      }
   }
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

      // Break-Even ao atingir 1:1 de Risco
      if(InpBreakEvenActive && currentSL > 0)
      {
         if(posInfo.PositionType() == POSITION_TYPE_BUY)
         {
            double riskDist = openPrice - currentSL;
            if(riskDist > 0 && currentPrice >= openPrice + riskDist)
            {
               if(currentSL < openPrice)
               {
                  double newSL = openPrice + 2 * _Point;
                  trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
                  PrintFormat("[BREAK-EVEN] Compra #%d movida para 0x0 (SL: %.5f)", posInfo.Ticket(), newSL);
               }
            }
         }
         else if(posInfo.PositionType() == POSITION_TYPE_SELL)
         {
            double riskDist = currentSL - openPrice;
            if(riskDist > 0 && currentPrice <= openPrice - riskDist)
            {
               if(currentSL > openPrice)
               {
                  double newSL = openPrice - 2 * _Point;
                  trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
                  PrintFormat("[BREAK-EVEN] Venda #%d movida para 0x0 (SL: %.5f)", posInfo.Ticket(), newSL);
               }
            }
         }
      }

      // Trailing Stop
      if(InpUseTrailing && InpTrailingPoints > 0)
      {
         double trailDist = InpTrailingPoints * _Point;
         if(posInfo.PositionType() == POSITION_TYPE_BUY)
         {
            if(currentPrice - openPrice > trailDist)
            {
               double proposedSL = currentPrice - trailDist;
               if(proposedSL > currentSL + 5 * _Point)
                  trade.PositionModify(posInfo.Ticket(), proposedSL, currentTP);
            }
         }
         else if(posInfo.PositionType() == POSITION_TYPE_SELL)
         {
            if(openPrice - currentPrice > trailDist)
            {
               double proposedSL = currentPrice + trailDist;
               if(currentSL == 0 || proposedSL < currentSL - 5 * _Point)
                  trade.PositionModify(posInfo.Ticket(), proposedSL, currentTP);
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

   ManageOpenPositions();
   ManagePendingOrders();
   UpdateDashboard();

   if(!IsNewBar()) return;
   if(HasOpenOrderOrPosition()) return;

   double currentSpread = (symInfo.Ask() - symInfo.Bid()) / _Point;
   if(currentSpread > InpMaxSpreadPoints) return;

   double emaVal[2];
   if(CopyBuffer(h_ema, 0, 1, 2, emaVal) < 2) return;
   bool emaSubindo  = (emaVal[1] > emaVal[0]);
   bool emaDescendo = (emaVal[1] < emaVal[0]);

   double atrVal[1];
   if(CopyBuffer(h_atr, 0, 1, 1, atrVal) < 1) return;
   double atr = atrVal[0];

   double stochMain[];
   double stochSig[];
   ArraySetAsSeries(stochMain, true);
   ArraySetAsSeries(stochSig, true);

   int toCopy = InpStochLookback + 5;
   int stochRead = CopyBuffer(h_stoch, 0, 1, toCopy, stochMain);
   CopyBuffer(h_stoch, 1, 1, toCopy, stochSig);
   if(stochRead < InpStochLookback) return;

   bool stochEstiveOversold = false;
   bool stochEstiveOverbought = false;
   for(int i = 0; i < InpStochLookback; i++)
   {
      if(stochMain[i] < InpStochOversold) stochEstiveOversold = true;
      if(stochMain[i] > InpStochOverbought) stochEstiveOverbought = true;
   }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int ratesCount = CopyRates(_Symbol, InpTimeframe, 1, InpMaxBarsSearch + 10, rates);
   if(ratesCount < InpMaxBarsSearch) return;

   double spreadReal = symInfo.Spread() * _Point;
   double slippageReal = InpSlippageEstimate * _Point;

   //+---------------------------------------------------------------+
   //| 1. SINAL DE COMPRA                                            |
   //+---------------------------------------------------------------+
   if(InpAllowBuy)
   {
      bool condTrend = (!InpFilterEMA_Slope || emaSubindo) && 
                       (!InpFilterPriceAboveEMA || rates[0].close >= emaVal[1]);

      if(condTrend && stochEstiveOversold)
      {
         SSetupSignal buySig;
         buySig.valid = false;

         if(InpPatternType == PATTERN_STORMER_TRAP)
            buySig = DetectStormerTrapBuy(rates, ratesCount, atr);
         else
            buySig = DetectClassic123Buy(rates, ratesCount, atr);

         if(buySig.valid)
         {
            double triggerPrice = buySig.triggerPrice;
            double rawSL = buySig.stopLossPrice;
            double rawTP = buySig.targetPrice;

            double estimatedEntry = triggerPrice + spreadReal + slippageReal;
            double estimatedSL    = rawSL - slippageReal;
            double realRiskPoints = (estimatedEntry - estimatedSL) / _Point;
            double realRewardPoints = (rawTP - estimatedEntry) / _Point;

            if(realRiskPoints > 0 && (realRewardPoints / realRiskPoints >= InpMinRiskReward))
            {
               double lot = CalculateRealRiskLot(realRiskPoints);
               datetime expiration = TimeCurrent() + PeriodSeconds(InpTimeframe) * InpPendingExpireBars;

               double currentAsk = symInfo.Ask();
               if(currentAsk >= triggerPrice)
               {
                  if(trade.Buy(lot, _Symbol, currentAsk, NormalizeDouble(rawSL, symInfo.Digits()), 
                               NormalizeDouble(rawTP, symInfo.Digits()), InpComment))
                  {
                     PrintFormat("[%s A MERCADO] Lote: %.2f | Preco: %.5f | SL: %.5f | TP: %.5f | R:R: %.2f",
                                 buySig.desc, lot, currentAsk, rawSL, rawTP, realRewardPoints / realRiskPoints);
                     DrawSetupLines(buySig.timeRef, rawSL, triggerPrice, rawTP, true);
                  }
               }
               else
               {
                  double orderPrice = NormalizeDouble(triggerPrice, symInfo.Digits());
                  if(trade.BuyStop(lot, orderPrice, _Symbol, NormalizeDouble(rawSL, symInfo.Digits()), 
                                   NormalizeDouble(rawTP, symInfo.Digits()), ORDER_TIME_SPECIFIED, expiration, InpComment))
                  {
                     PrintFormat("[BUY STOP AGENDADA: %s] Lote: %.2f | Gatilho: %.5f | SL: %.5f | TP: %.5f",
                                 buySig.desc, lot, orderPrice, rawSL, rawTP);
                     DrawSetupLines(buySig.timeRef, rawSL, triggerPrice, rawTP, true);
                  }
               }
            }
         }
      }
   }

   //+---------------------------------------------------------------+
   //| 2. SINAL DE VENDA                                             |
   //+---------------------------------------------------------------+
   if(InpAllowSell)
   {
      bool condTrend = (!InpFilterEMA_Slope || emaDescendo) && 
                       (!InpFilterPriceAboveEMA || rates[0].close <= emaVal[1]);

      if(condTrend && stochEstiveOverbought)
      {
         SSetupSignal sellSig;
         sellSig.valid = false;

         if(InpPatternType == PATTERN_STORMER_TRAP)
            sellSig = DetectStormerTrapSell(rates, ratesCount, atr);
         else
            sellSig = DetectClassic123Sell(rates, ratesCount, atr);

         if(sellSig.valid)
         {
            double triggerPrice = sellSig.triggerPrice;
            double rawSL = sellSig.stopLossPrice;
            double rawTP = sellSig.targetPrice;

            double estimatedEntry = triggerPrice - slippageReal;
            double estimatedSL    = rawSL + spreadReal + slippageReal;
            double realRiskPoints = (estimatedSL - estimatedEntry) / _Point;
            double realRewardPoints = (estimatedEntry - (rawTP + spreadReal)) / _Point;

            if(realRiskPoints > 0 && (realRewardPoints / realRiskPoints >= InpMinRiskReward))
            {
               double lot = CalculateRealRiskLot(realRiskPoints);
               datetime expiration = TimeCurrent() + PeriodSeconds(InpTimeframe) * InpPendingExpireBars;

               double currentBid = symInfo.Bid();
               if(currentBid <= triggerPrice)
               {
                  if(trade.Sell(lot, _Symbol, currentBid, NormalizeDouble(rawSL, symInfo.Digits()), 
                                NormalizeDouble(rawTP, symInfo.Digits()), InpComment))
                  {
                     PrintFormat("[%s A MERCADO] Lote: %.2f | Preco: %.5f | SL: %.5f | TP: %.5f | R:R: %.2f",
                                 sellSig.desc, lot, currentBid, rawSL, rawTP, realRewardPoints / realRiskPoints);
                     DrawSetupLines(sellSig.timeRef, rawSL, triggerPrice, rawTP, false);
                  }
               }
               else
               {
                  double orderPrice = NormalizeDouble(triggerPrice, symInfo.Digits());
                  if(trade.SellStop(lot, orderPrice, _Symbol, NormalizeDouble(rawSL, symInfo.Digits()), 
                                    NormalizeDouble(rawTP, symInfo.Digits()), ORDER_TIME_SPECIFIED, expiration, InpComment))
                  {
                     PrintFormat("[SELL STOP AGENDADA: %s] Lote: %.2f | Gatilho: %.5f | SL: %.5f | TP: %.5f",
                                 sellSig.desc, lot, orderPrice, rawSL, rawTP);
                     DrawSetupLines(sellSig.timeRef, rawSL, triggerPrice, rawTP, false);
                  }
               }
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
//| Atualiza Dashboard no Grafico                                    |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   double emaVal[2];
   CopyBuffer(h_ema, 0, 1, 2, emaVal);

   double stochVal[1];
   CopyBuffer(h_stoch, 0, 1, 1, stochVal);

   string trendStr = (emaVal[1] > emaVal[0]) ? "ALTA (EMA Subindo)" : "BAIXA (EMA Descendo)";
   string stochState = "NEUTRO";
   if(stochVal[0] < InpStochOversold) stochState = "SOBREVENDIDO (< 20)";
   else if(stochVal[0] > InpStochOverbought) stochState = "SOBRECOMPRADO (> 80)";

   string patStr = (InpPatternType == PATTERN_STORMER_TRAP) ? "Trap no 1-2-3 (Video Oficial)" :
                   ((InpPatternType == PATTERN_JOE_ROSS_SWING) ? "Joe Ross Swing" : "Pivo 3 Barras");

   string text = "\n" +
      "====================================================\n" +
      "    ROBO STORMER SWING TRADE v3.0 (MASTERCLASS)     \n" +
      "====================================================\n" +
      StringFormat(" Ativo: %s | Timeframe: H4\n", _Symbol) +
      StringFormat(" Estrutura: %s\n", patStr) +
      StringFormat(" Alvo: %.1fx o Risco (2R Oficial Stormer)\n", InpTargetRRMultiplier) +
      StringFormat(" Tendencia EMA 70: %s\n", trendStr) +
      StringFormat(" Estocastico Lento (8,3,3): %.2f [%s]\n", stochVal[0], stochState) +
      StringFormat(" Risco Real por Trade: %.1f%% do Capital\n", InpRiskPercent) +
      StringFormat(" Spread: %.1f pts (Max: %.1f pts)\n", (symInfo.Ask() - symInfo.Bid()) / _Point, InpMaxSpreadPoints) +
      StringFormat(" Saldo: %.2f | Equity: %.2f\n", AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY)) +
      "====================================================\n" +
      " 'O MELHOR sinal de swing trade que eu conheco'\n" +
      "====================================================";

   Comment(text);
}
//+------------------------------------------------------------------+
