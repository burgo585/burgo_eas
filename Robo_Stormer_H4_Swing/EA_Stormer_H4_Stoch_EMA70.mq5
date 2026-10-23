//+------------------------------------------------------------------+
//|                                  EA_Stormer_H4_Stoch_EMA70.mq5   |
//|               Estrategia Oficial Stormer: H4 Swing Trade         |
//|        Estocastico Lento (8,3,3) + EMA 70 + Setup 1-2-3          |
//|         Versao 2.0: Joe Ross Swing Points + Gestao Avancada      |
//|                    https://github.com/burgo585/burgo_eas         |
//+------------------------------------------------------------------+
#property copyright   "Stormer Strategy - Antigravity Quant Team"
#property link        "https://github.com/burgo585/burgo_eas"
#property version     "2.00"
#property description "Expert Advisor de Swing Trade baseado no setup de Stormer / Joe Ross:"
#property description "1. 1-2-3 Classico por Pontos de Swing (Joe Ross) ou Pivo de 3 Barras."
#property description "2. Alvo Dinamico: Projecao 100% Fibo, Topo Anterior filtrado ou Multiplo R:R."
#property description "3. Execucao nativa por Ordens Pendentes (Buy Stop/Sell Stop) com cancelamento por invalidacao."
#property description "4. Calculo de risco real baseado no preco efetivo (Trigger + Spread + Slippage)."
#property description "5. Arrays dinamicos sem limite fixo para o Estocastico."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Enums
enum ENUM_PATTERN_TYPE
{
   PATTERN_JOE_ROSS_SWING = 0, // 1-2-3 Classico (Pontos de Swing Joe Ross)
   PATTERN_STORMER_3BAR   = 1  // 1-2-3 de 3 Barras (Pivo Rapido de Candles)
};

enum ENUM_TARGET_MODE
{
   TARGET_FIBO_100        = 0, // Projecao 100% da Perna 1-2 a partir de 3 (Recomendado)
   TARGET_SWING_PREVIOUS  = 1, // Topo/Fundo Anterior (com filtro de distancia ATR)
   TARGET_FIXED_RR        = 2  // Multiplo Fixo de Risco:Retorno (ex: 2.0x)
};

enum ENUM_LOT_TYPE
{
   LOT_FIXED = 0,              // Lote Fixo
   LOT_PERCENT_RISK = 1        // Percentual de Risco da Banca (% Equity)
};

//--- Inputs do Sistema
input group "=== TIPO DE PADRAO 1-2-3 ==="
input ENUM_PATTERN_TYPE InpPatternType        = PATTERN_JOE_ROSS_SWING; // Tipo de Padrao 1-2-3
input int               InpSwingStrength      = 2;                      // Forca do Pivo de Swing (barras de cada lado)
input int               InpMaxBarsSearch      = 40;                     // Maximo de Barras para busca dos Pontos 1-2-3

input group "=== PARAMETROS DOS INDICADORES ==="
input ENUM_TIMEFRAMES   InpTimeframe          = PERIOD_H4;              // Tempo Grafico Operacional (Padrao H4)
input int               InpEMAPeriod          = 70;                     // Periodo da Media Exponencial (EMA 70)
input ENUM_APPLIED_PRICE InpEMAPrice          = PRICE_CLOSE;            // Preco Aplicado da EMA
input int               InpStochK             = 8;                      // Estocastico %K
input int               InpStochD             = 3;                      // Estocastico %D
input int               InpStochSlowing       = 3;                      // Estocastico Slowing (Desaceleracao)
input ENUM_MA_METHOD    InpStochMethod        = MODE_SMA;               // Metodo do Estocastico
input ENUM_STO_PRICE    InpStochPrice         = STO_LOWHIGH;            // Preco do Estocastico
input double            InpStochOversold      = 20.0;                   // Nivel de Sobrevenda (Compra)
input double            InpStochOverbought    = 80.0;                   // Nivel de Sobrecompra (Venda)
input int               InpStochLookback      = 10;                     // Barras de Recuo para checagem do Estocastico (Sem limite fixo)

input group "=== REGRAS DE TENDENCIA E FILTROS ==="
input bool              InpAllowBuy           = true;                   // Permitir Compras
input bool              InpAllowSell          = true;                   // Permitir Vendas (Mercados Bidirecionais)
input bool              InpFilterEMA_Slope    = true;                   // Exigir inclinacao da EMA (subindo/descendo)
input bool              InpFilterPriceAboveEMA = true;                 // Preco deve estar acima da EMA (Compra) / abaixo (Venda)

input group "=== GESTAO DE ALVO (TAKE PROFIT) ==="
input ENUM_TARGET_MODE  InpTargetMode         = TARGET_FIBO_100;        // Modo de Calculo do Alvo
input double            InpTargetRRMultiplier = 2.0;                    // Multiplo de R:R (se modo Fixo RR)
input int               InpSwingLookback      = 20;                     // Barras para buscar Topo/Fundo Anterior
input double            InpMinRiskReward      = 1.0;                    // Risco:Retorno Minimo Real para aceitar entrada
input int               InpBufferPoints       = 50;                     // Buffer de Folga no Stop Loss (pontos)
input int               InpSlippageEstimate   = 20;                     // Estimativa de Slippage para calculo do risco real (pontos)

input group "=== GESTAO DE POSICAO ==="
input bool              InpBreakEvenActive    = true;                   // Mover Stop para 0x0 ao atingir 1:1 de Risco
input bool              InpUseTrailing        = false;                  // Ativar Trailing Stop
input double            InpTrailingPoints     = 300.0;                  // Distancia do Trailing Stop (pontos)
input int               InpPendingExpireBars  = 6;                      // Validade da Ordem Pendente em Barras H4

input group "=== GESTAO DE CAPITAL E LOTE ==="
input ENUM_LOT_TYPE     InpLotType            = LOT_PERCENT_RISK;       // Tipo de Calculo de Lote
input double            InpRiskPercent        = 1.0;                    // Risco por Trade (% do Capital)
input double            InpFixedLot           = 0.01;                   // Lote Fixo (se modo fixo)
input double            InpMaxSpreadPoints    = 50.0;                   // Spread Maximo Permitido (pontos)

input group "=== IDENTIFICACAO ==="
input ulong             InpMagicNumber        = 708123;                 // Magic Number do Robo
input string            InpComment            = "Stormer_H4_v2";        // Comentario da Ordem
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

// Estrutura para armazenar os pontos 1-2-3
struct SPoint123
{
   bool     valid;
   datetime time1;
   double   price1; // Fundo ou Topo 1
   datetime time2;
   double   price2; // Topo ou Fundo 2 (Gatilho)
   datetime time3;
   double   price3; // Fundo mais alto ou Topo mais baixo (Stop base)
   double   target; // Alvo calculado
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
      Print("[ERRO] Falha ao criar handle da EMA: ", GetLastError());
      return INIT_FAILED;
   }

   h_stoch = iStochastic(_Symbol, InpTimeframe, InpStochK, InpStochD, InpStochSlowing, InpStochMethod, InpStochPrice);
   if(h_stoch == INVALID_HANDLE)
   {
      Print("[ERRO] Falha ao criar handle do Estocastico: ", GetLastError());
      return INIT_FAILED;
   }

   h_atr = iATR(_Symbol, InpTimeframe, 14);
   if(h_atr == INVALID_HANDLE)
   {
      Print("[ERRO] Falha ao criar handle do ATR: ", GetLastError());
      return INIT_FAILED;
   }

   PrintFormat("[SUCESSO] EA Stormer v2.0 inicializado em %s (%s). Modo: %s", 
               _Symbol, EnumToString(InpTimeframe), 
               (InpPatternType == PATTERN_JOE_ROSS_SWING) ? "Joe Ross Swing" : "Pivo 3 Barras");

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

   if(InpDrawVisuals)
   {
      ObjectsDeleteAll(0, "Stormer_");
   }
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
//| PONTO 4: Calculo do lote com base no RISCO REAL EFETIVO          |
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

   // Lote calculado estritamente sobre os pontos reais de risco
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
//| PONTO 1: Deteccao de Pontos de Swing (Pivots)                    |
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
//| Identifica o Padrao 1-2-3 (Joe Ross Classico ou 3 Barras)        |
//+------------------------------------------------------------------+
SPoint123 FindPatternBuy(const MqlRates &rates[], int total, double atr)
{
   SPoint123 pt;
   pt.valid = false;

   if(InpPatternType == PATTERN_STORMER_3BAR)
   {
      // Pivo Simples de 3 Barras (Barra 1=rates[2], Barra 2=rates[1], Barra 3=rates[0])
      if(total < 3) return pt;
      if(rates[1].low < rates[2].low && rates[0].low > rates[1].low)
      {
         pt.valid = true;
         pt.time1 = rates[2].time;
         pt.price1 = rates[2].low;
         pt.time2 = rates[0].time;
         pt.price2 = rates[0].high; // Gatilho na maxima da barra 3
         pt.time3 = rates[1].time;
         pt.price3 = rates[1].low;  // Stop na minima da barra 2

         // PONTO 2: Calculo do Alvo
         if(InpTargetMode == TARGET_FIBO_100)
         {
            double leg = pt.price2 - pt.price3;
            pt.target = pt.price2 + leg;
         }
         else if(InpTargetMode == TARGET_FIXED_RR)
         {
            double risk = pt.price2 - pt.price3;
            pt.target = pt.price2 + (risk * InpTargetRRMultiplier);
         }
         else // TARGET_SWING_PREVIOUS
         {
            double highest = rates[2].high;
            for(int k = 2; k < MathMin(total, InpSwingLookback); k++)
            {
               if(rates[k].high > highest) highest = rates[k].high;
            }
            pt.target = highest;
         }
      }
      return pt;
   }

   // --- PATTERN_JOE_ROSS_SWING (1-2-3 Classico) ---
   // Procura Ponto 3 (fundo de swing mais recente entre as barras fechadas)
   int idx3 = -1;
   for(int i = 1; i < MathMin(total - InpSwingStrength, 15); i++)
   {
      if(IsSwingLow(rates, i, InpSwingStrength, total))
      {
         idx3 = i;
         break;
      }
   }
   if(idx3 == -1) return pt;

   // Procura Ponto 2 (topo de swing anterior ao Ponto 3)
   int idx2 = -1;
   for(int i = idx3 + 1; i < MathMin(total - InpSwingStrength, idx3 + 20); i++)
   {
      if(IsSwingHigh(rates, i, InpSwingStrength, total))
      {
         idx2 = i;
         break;
      }
   }
   if(idx2 == -1) return pt;

   // Procura Ponto 1 (fundo de swing mais baixo que Ponto 3, anterior ao Ponto 2)
   int idx1 = -1;
   for(int i = idx2 + 1; i < MathMin(total - InpSwingStrength, idx2 + 25); i++)
   {
      if(IsSwingLow(rates, i, InpSwingStrength, total))
      {
         if(rates[i].low < rates[idx3].low) // Ponto 1 deve ser mais baixo que Ponto 3
         {
            idx1 = i;
            break;
         }
      }
   }
   if(idx1 == -1) return pt;

   // Valida estrutura Joe Ross:
   // Ponto 1 (rates[idx1].low) = Fundo mais baixo
   // Ponto 2 (rates[idx2].high) = Topo da reacao
   // Ponto 3 (rates[idx3].low)  = Fundo mais alto (Low[Ponto 3] > Low[Ponto 1])
   if(rates[idx3].low > rates[idx1].low && rates[idx2].high > rates[idx3].low)
   {
      pt.valid = true;
      pt.time1 = rates[idx1].time;
      pt.price1 = rates[idx1].low;
      pt.time2 = rates[idx2].time;
      pt.price2 = rates[idx2].high; // Gatilho no rompimento do Ponto 2
      pt.time3 = rates[idx3].time;
      pt.price3 = rates[idx3].low;  // Stop tecnico na minima do Ponto 3

      // PONTO 2: Alvo Dinamico e Flexivel
      if(InpTargetMode == TARGET_FIBO_100)
      {
         // Projecao 100% da Perna 1-2 a partir de 3
         double leg12 = pt.price2 - pt.price1;
         pt.target = pt.price3 + leg12;
      }
      else if(InpTargetMode == TARGET_FIXED_RR)
      {
         double risk = pt.price2 - pt.price3;
         pt.target = pt.price2 + (risk * InpTargetRRMultiplier);
      }
      else // TARGET_SWING_PREVIOUS com filtro de ATR
      {
         double highest = pt.price2;
         for(int k = idx2 + 1; k < MathMin(total, idx2 + InpSwingLookback); k++)
         {
            if(rates[k].high > highest) highest = rates[k].high;
         }
         // Se o topo anterior for muito distante (> 6 ATR), trava em 3 ATR
         if(highest - pt.price2 > 6.0 * atr)
            highest = pt.price2 + (3.0 * atr);
         pt.target = highest;
      }
   }

   return pt;
}

SPoint123 FindPatternSell(const MqlRates &rates[], int total, double atr)
{
   SPoint123 pt;
   pt.valid = false;

   if(InpPatternType == PATTERN_STORMER_3BAR)
   {
      if(total < 3) return pt;
      if(rates[1].high > rates[2].high && rates[0].high < rates[1].high)
      {
         pt.valid = true;
         pt.time1 = rates[2].time;
         pt.price1 = rates[2].high;
         pt.time2 = rates[0].time;
         pt.price2 = rates[0].low;  // Gatilho na minima da barra 3
         pt.time3 = rates[1].time;
         pt.price3 = rates[1].high; // Stop na maxima da barra 2

         if(InpTargetMode == TARGET_FIBO_100)
         {
            double leg = pt.price3 - pt.price2;
            pt.target = pt.price2 - leg;
         }
         else if(InpTargetMode == TARGET_FIXED_RR)
         {
            double risk = pt.price3 - pt.price2;
            pt.target = pt.price2 - (risk * InpTargetRRMultiplier);
         }
         else
         {
            double lowest = rates[2].low;
            for(int k = 2; k < MathMin(total, InpSwingLookback); k++)
            {
               if(rates[k].low < lowest) lowest = rates[k].low;
            }
            pt.target = lowest;
         }
      }
      return pt;
   }

   // --- PATTERN_JOE_ROSS_SWING Vendedor ---
   int idx3 = -1;
   for(int i = 1; i < MathMin(total - InpSwingStrength, 15); i++)
   {
      if(IsSwingHigh(rates, i, InpSwingStrength, total))
      {
         idx3 = i;
         break;
      }
   }
   if(idx3 == -1) return pt;

   int idx2 = -1;
   for(int i = idx3 + 1; i < MathMin(total - InpSwingStrength, idx3 + 20); i++)
   {
      if(IsSwingLow(rates, i, InpSwingStrength, total))
      {
         idx2 = i;
         break;
      }
   }
   if(idx2 == -1) return pt;

   int idx1 = -1;
   for(int i = idx2 + 1; i < MathMin(total - InpSwingStrength, idx2 + 25); i++)
   {
      if(IsSwingHigh(rates, i, InpSwingStrength, total))
      {
         if(rates[i].high > rates[idx3].high)
         {
            idx1 = i;
            break;
         }
      }
   }
   if(idx1 == -1) return pt;

   if(rates[idx3].high < rates[idx1].high && rates[idx2].low < rates[idx3].high)
   {
      pt.valid = true;
      pt.time1 = rates[idx1].time;
      pt.price1 = rates[idx1].high;
      pt.time2 = rates[idx2].time;
      pt.price2 = rates[idx2].low;  // Gatilho no rompimento do Ponto 2
      pt.time3 = rates[idx3].time;
      pt.price3 = rates[idx3].high; // Stop na maxima do Ponto 3

      if(InpTargetMode == TARGET_FIBO_100)
      {
         double leg12 = pt.price1 - pt.price2;
         pt.target = pt.price3 - leg12;
      }
      else if(InpTargetMode == TARGET_FIXED_RR)
      {
         double risk = pt.price3 - pt.price2;
         pt.target = pt.price2 - (risk * InpTargetRRMultiplier);
      }
      else
      {
         double lowest = pt.price2;
         for(int k = idx2 + 1; k < MathMin(total, idx2 + InpSwingLookback); k++)
         {
            if(rates[k].low < lowest) lowest = rates[k].low;
         }
         if(pt.price2 - lowest > 6.0 * atr)
            lowest = pt.price2 - (3.0 * atr);
         pt.target = lowest;
      }
   }

   return pt;
}

//+------------------------------------------------------------------+
//| PONTO 3: Gerencia e Cancela Ordens Pendentes Invalidadas         |
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

      // Se for Buy Stop e o preco caiu abaixo do Stop Loss (Ponto 3), o padrao foi violado! Cancela ordem.
      if(oType == ORDER_TYPE_BUY_STOP)
      {
         if(sl > 0 && currentBid <= sl)
         {
            trade.OrderDelete(ticket);
            PrintFormat("[ORDEM CANCELADA] Buy Stop #%d cancelada: padrao invalidado pela quebra do fundo (SL: %.5f)", ticket, sl);
         }
      }
      // Se for Sell Stop e o preco subiu acima do Stop Loss, padrao invalidado! Cancela ordem.
      else if(oType == ORDER_TYPE_SELL_STOP)
      {
         if(sl > 0 && currentAsk >= sl)
         {
            trade.OrderDelete(ticket);
            PrintFormat("[ORDEM CANCELADA] Sell Stop #%d cancelada: padrao invalidado pelo rompimento do topo (SL: %.5f)", ticket, sl);
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
                  PrintFormat("[BREAK-EVEN] Compra #%d protegida no zero a zero (SL: %.5f)", posInfo.Ticket(), newSL);
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
                  PrintFormat("[BREAK-EVEN] Venda #%d protegida no zero a zero (SL: %.5f)", posInfo.Ticket(), newSL);
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

   // Gerenciamento contínuo
   ManageOpenPositions();
   ManagePendingOrders();
   UpdateDashboard();

   // Novos sinais avaliados na abertura de barra fechada
   if(!IsNewBar()) return;

   // Respeita operacao ativa (Swing trade de 1 posicao por vez)
   if(HasOpenOrderOrPosition()) return;

   // Checa spread maximo
   double currentSpread = (symInfo.Ask() - symInfo.Bid()) / _Point;
   if(currentSpread > InpMaxSpreadPoints) return;

   // Leitura da EMA 70 nas barras fechadas (shift 1 e shift 2)
   double emaVal[2];
   if(CopyBuffer(h_ema, 0, 1, 2, emaVal) < 2) return;
   bool emaSubindo  = (emaVal[1] > emaVal[0]);
   bool emaDescendo = (emaVal[1] < emaVal[0]);

   // Leitura do ATR para limites de alvo
   double atrVal[1];
   if(CopyBuffer(h_atr, 0, 1, 1, atrVal) < 1) return;
   double atr = atrVal[0];

   // PONTO 5: Array Dinamico sem limite fixo de 10
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

   // Copia taxas historicas
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int ratesCount = CopyRates(_Symbol, InpTimeframe, 1, InpMaxBarsSearch + 10, rates);
   if(ratesCount < InpMaxBarsSearch) return;

   double spreadReal = symInfo.Spread() * _Point;
   double slippageReal = InpSlippageEstimate * _Point;

   //+---------------------------------------------------------------+
   //| 1. SINAL DE COMPRA 1-2-3 (JOE ROSS OU 3 BARRAS)               |
   //+---------------------------------------------------------------+
   if(InpAllowBuy)
   {
      bool condTrend = (!InpFilterEMA_Slope || emaSubindo) && 
                       (!InpFilterPriceAboveEMA || rates[0].close >= emaVal[1]);

      if(condTrend && stochEstiveOversold)
      {
         SPoint123 buyPt = FindPatternBuy(rates, ratesCount, atr);
         if(buyPt.valid)
         {
            double triggerPrice = buyPt.price2; // Rompimento do Ponto 2
            double rawSL = buyPt.price3 - (InpBufferPoints * _Point);
            double rawTP = buyPt.target;

            // PONTO 4: Preco de Execucao Real e Risco Efetivo
            double estimatedEntry = triggerPrice + spreadReal + slippageReal;
            double estimatedSL    = rawSL - slippageReal;
            double realRiskPoints = (estimatedEntry - estimatedSL) / _Point;
            double realRewardPoints = (rawTP - estimatedEntry) / _Point;

            if(realRiskPoints > 0 && (realRewardPoints / realRiskPoints >= InpMinRiskReward))
            {
               double lot = CalculateRealRiskLot(realRiskPoints);
               datetime expiration = TimeCurrent() + PeriodSeconds(InpTimeframe) * InpPendingExpireBars;

               // PONTO 3: Se o preco Ask ja abriu rompendo, entra a mercado; senao coloca Buy Stop
               double currentAsk = symInfo.Ask();
               if(currentAsk >= triggerPrice)
               {
                  if(trade.Buy(lot, _Symbol, currentAsk, NormalizeDouble(rawSL, symInfo.Digits()), 
                               NormalizeDouble(rawTP, symInfo.Digits()), InpComment))
                  {
                     PrintFormat("[COMPRA 1-2-3 EXECUTADA A MERCADO] Lote: %.2f | Preco: %.5f | SL: %.5f | TP: %.5f | R:R Real: %.2f",
                                 lot, currentAsk, rawSL, rawTP, realRewardPoints / realRiskPoints);
                     DrawSetupLines(buyPt.time2, rawSL, triggerPrice, rawTP, true);
                  }
               }
               else
               {
                  double orderPrice = NormalizeDouble(triggerPrice, symInfo.Digits());
                  if(trade.BuyStop(lot, orderPrice, _Symbol, NormalizeDouble(rawSL, symInfo.Digits()), 
                                   NormalizeDouble(rawTP, symInfo.Digits()), ORDER_TIME_SPECIFIED, expiration, InpComment))
                  {
                     PrintFormat("[BUY STOP 1-2-3 AGENDADA] Lote: %.2f | Gatilho: %.5f | SL: %.5f | TP: %.5f | R:R Real: %.2f",
                                 lot, orderPrice, rawSL, rawTP, realRewardPoints / realRiskPoints);
                     DrawSetupLines(buyPt.time2, rawSL, triggerPrice, rawTP, true);
                  }
               }
            }
         }
      }
   }

   //+---------------------------------------------------------------+
   //| 2. SINAL DE VENDA 1-2-3                                       |
   //+---------------------------------------------------------------+
   if(InpAllowSell)
   {
      bool condTrend = (!InpFilterEMA_Slope || emaDescendo) && 
                       (!InpFilterPriceAboveEMA || rates[0].close <= emaVal[1]);

      if(condTrend && stochEstiveOverbought)
      {
         SPoint123 sellPt = FindPatternSell(rates, ratesCount, atr);
         if(sellPt.valid)
         {
            double triggerPrice = sellPt.price2;
            double rawSL = sellPt.price3 + (InpBufferPoints * _Point);
            double rawTP = sellPt.target;

            // PONTO 4: Preco Real de Venda
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
                     PrintFormat("[VENDA 1-2-3 EXECUTADA A MERCADO] Lote: %.2f | Preco: %.5f | SL: %.5f | TP: %.5f | R:R Real: %.2f",
                                 lot, currentBid, rawSL, rawTP, realRewardPoints / realRiskPoints);
                     DrawSetupLines(sellPt.time2, rawSL, triggerPrice, rawTP, false);
                  }
               }
               else
               {
                  double orderPrice = NormalizeDouble(triggerPrice, symInfo.Digits());
                  if(trade.SellStop(lot, orderPrice, _Symbol, NormalizeDouble(rawSL, symInfo.Digits()), 
                                    NormalizeDouble(rawTP, symInfo.Digits()), ORDER_TIME_SPECIFIED, expiration, InpComment))
                  {
                     PrintFormat("[SELL STOP 1-2-3 AGENDADA] Lote: %.2f | Gatilho: %.5f | SL: %.5f | TP: %.5f | R:R Real: %.2f",
                                 lot, orderPrice, rawSL, rawTP, realRewardPoints / realRiskPoints);
                     DrawSetupLines(sellPt.time2, rawSL, triggerPrice, rawTP, false);
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

   string patStr = (InpPatternType == PATTERN_JOE_ROSS_SWING) ? "Joe Ross (Swing Points)" : "Pivo 3 Barras";
   string tgtStr = (InpTargetMode == TARGET_FIBO_100) ? "100% Expansao Fibo" : 
                   ((InpTargetMode == TARGET_SWING_PREVIOUS) ? "Topo/Fundo Anterior" : "Multiplo Fixo RR");

   string text = "\n" +
      "====================================================\n" +
      "    ROBO STORMER & JOE ROSS H4 SWING TRADE v2.0     \n" +
      "====================================================\n" +
      StringFormat(" Ativo: %s | Timeframe: H4\n", _Symbol) +
      StringFormat(" Estrutura 1-2-3: %s\n", patStr) +
      StringFormat(" Modo de Alvo: %s\n", tgtStr) +
      StringFormat(" Tendencia EMA 70: %s\n", trendStr) +
      StringFormat(" Estocastico Lento (8,3,3): %.2f [%s]\n", stochVal[0], stochState) +
      StringFormat(" Risco Real por Trade: %.1f%% do Capital\n", InpRiskPercent) +
      StringFormat(" Spread: %.1f pts (Max: %.1f pts)\n", (symInfo.Ask() - symInfo.Bid()) / _Point, InpMaxSpreadPoints) +
      StringFormat(" Saldo: %.2f | Equity: %.2f\n", AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY)) +
      "====================================================\n" +
      " 5 Correcoes Forenses Aplicadas com Sucesso\n" +
      "====================================================";

   Comment(text);
}
//+------------------------------------------------------------------+
