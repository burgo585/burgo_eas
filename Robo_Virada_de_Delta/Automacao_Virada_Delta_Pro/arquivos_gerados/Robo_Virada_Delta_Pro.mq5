//+------------------------------------------------------------------+
//|                                     Robo_Virada_Delta_Pro.mq5    |
//|               Automação Algorítmica Institucional MetaTrader 5   |
//|        Baseado em Teoria do Leilão (VPVR), PVSRA, Langevin e     |
//|               Deformação Elástica (Paper Mikael Sepaul v6)       |
//+------------------------------------------------------------------+
#property copyright   "Robô Virada de Delta Pro - Metra, Sepaul & Antigravity"
#property link        "https://antigravity.google"
#property version     "3.00"
#property description "Expert Advisor de Alta Frequência e Precisão Microestrutural para XAUUSD, NAS100 e BTCUSD."

#include "Include\PVSRA_Core.mqh"
#include "Include\VAP_Core.mqh"
#include "Include\Nonlinear_Attractor_Core.mqh"
#include "Include\Risk_Manager.mqh"

//--- Modos Operacionais
enum ENUM_STRATEGY_MODE
  {
   MODE_HYBRID_TOTAL,       // Híbrido Campeão: Reversão Elástica + Pullback Pós-BOS
   MODE_REVERSAL_CONFIRMED, // Apenas Reversão / Fade de Extremidade (Delta >= 2.0)
   MODE_BOS_PULLBACK        // Apenas Rompimento Estrutural (BOS) com Tendência
  };

//--- Inputs do Usuário
input group "=== 1. Ativo & Modo Operacional ==="
input ENUM_STRATEGY_MODE   InpStrategyMode         = MODE_HYBRID_TOTAL;      // Modo de Operação
input ENUM_SESSION_FILTER  InpSessionFilter        = SESSION_ALL_DAY;        // Filtro de Sessão (NY mandatório p/ NAS100)
input int                  InpCustomStartHour      = 13;                     // Hora Início (se Personalizado)
input int                  InpCustomStartMin       = 30;                     // Minuto Início
input int                  InpCustomEndHour        = 20;                     // Hora Fim
input int                  InpCustomEndMin         = 0;                      // Minuto Fim

input group "=== 2. Topografia de Leilão (VPVR) ==="
input int                  InpProfileBars          = 288;                    // Barras do Perfil Rolante (288 = 24h M5)
input int                  InpTargetLevels         = 70;                     // Quantidade de Níveis de Preço
input double               InpValueAreaPercent     = 70.0;                   // % da Área de Valor (VAH / VAL)

input group "=== 3. Física de Langevin & Deformação ==="
input double               InpCritStrain           = 2.0;                    // Deformação Elástica Crítica (|Delta_t| >= 2.0)
input double               InpMinHeadroom          = 1.5;                    // Headroom Geométrico Mínimo (R_geo >= 1.5x)
input double               InpMaxOmega             = 2.0;                    // Teto do Índice de Autodestruição (Omega_t)
input double               InpHurstThreshold       = 0.57;                   // Limiar de Hurst (<= 0.57 Fade; > 0.57 BOS)

input group "=== 4. PVSRA & Volume ==="
input int                  InpVolumeLookback       = 10;                     // Lookback da Média de Volume
input double               InpRisingMultiplier     = 1.5;                    // Multiplicador Volume Crescente
input double               InpClimaxMultiplier     = 2.0;                    // Multiplicador Volume Clímax
input bool                 InpUseAbnormalThreshold = true;                   // Ativar Limiar de Volume Anormal v6

input group "=== 5. Gestão de Risco & Quarter-Kelly ==="
input ENUM_LOT_MODE        InpLotMode              = LOT_QUARTER_KELLY;      // Modo de Dimensionamento de Lote
input double               InpFixedLot             = 0.01;                   // Lote Fixo (se selecionado)
input double               InpRiskPercent          = 2.0;                    // Risco % da Conta
input bool                 InpUsePartialExit       = true;                   // Ativar Saída Parcial 70/30
input double               InpPartialRatio         = 0.70;                   // Proporção da Saída Parcial (70%)
input bool                 InpUseTrailingStop      = true;                   // Ativar Trailing Stop Estrutural nos 30%
input double               InpMaxDailyLossPct      = 3.5;                    // Trava de Perda Diária Máxima (%)
input ulong                InpMagicNumber          = 145634;                 // Magic Number Exclusivo

input group "=== 6. Painel Visual (HUD) ==="
input bool                 InpShowHUD              = true;                   // Exibir Painel Visual no Gráfico
input color                InpHUDColor             = clrDeepSkyBlue;         // Cor de Destaque do HUD

//--- Instâncias dos Motores
CPvsraCore        g_pvsra;
CVapCore          g_vap;
CNonlinearCore    g_physics;
CRiskManager      g_risk;

//--- Variáveis de Estado
datetime          g_last_bar_time = 0;
bool              g_partial_executed = false;
string            g_hud_prefix = "MTR_DELTA_HUD_";

//+------------------------------------------------------------------+
//| Função OnInit                                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   // 1. Inicializa PVSRA Core
   if(!g_pvsra.Init(_Symbol, (ENUM_TIMEFRAMES)_Period, InpVolumeLookback,
                    InpRisingMultiplier, InpClimaxMultiplier,
                    InpUseAbnormalThreshold, 365, 34, 200))
     {
      Print("[ERRO] Falha ao inicializar PVSRA Core.");
      return(INIT_FAILED);
     }

   // 2. Inicializa VAP Core (Volume Profile)
   if(!g_vap.Init(_Symbol, (ENUM_TIMEFRAMES)_Period, InpProfileBars, InpTargetLevels, InpValueAreaPercent))
     {
      Print("[ERRO] Falha ao inicializar VAP Core.");
      return(INIT_FAILED);
     }

   // 3. Inicializa Nonlinear Core (Física & Langevin)
   if(!g_physics.Init(_Symbol, (ENUM_TIMEFRAMES)_Period, InpCritStrain, InpMinHeadroom, InpMaxOmega))
     {
      Print("[ERRO] Falha ao inicializar Nonlinear Core.");
      return(INIT_FAILED);
     }

   // 4. Inicializa Gestão de Risco
   if(!g_risk.Init(_Symbol, InpMagicNumber, InpLotMode, InpFixedLot, InpRiskPercent,
                   InpMaxDailyLossPct, InpSessionFilter,
                   InpCustomStartHour, InpCustomStartMin, InpCustomEndHour, InpCustomEndMin))
     {
      Print("[ERRO] Falha ao inicializar Risk Manager.");
      return(INIT_FAILED);
     }

   // Timer para atualização periódica do perfil (a cada 5 segundos)
   EventSetTimer(5);

   PrintFormat("[INIT] Robô Virada de Delta Pro inicializado com sucesso em %s | Magic: %d", _Symbol, InpMagicNumber);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Função OnDeinit                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_pvsra.Deinit();
   g_vap.Deinit();
   g_physics.Deinit();

   // Limpa objetos do HUD
   ObjectsDeleteAll(0, g_hud_prefix);
   ChartRedraw(0);
   Print("[DEINIT] Robô Virada de Delta Pro finalizado.");
  }

//+------------------------------------------------------------------+
//| Função OnTimer                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   // Atualiza perfil de volume a cada 5 segundos
   g_vap.UpdateProfile();
   if(InpShowHUD)
      UpdateHUD();
  }

//+------------------------------------------------------------------+
//| Função OnTick                                                    |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Gerenciar posições abertas existentes
   ManageOpenPosition();

   // 2. Checa se abriu um novo candle para avaliar novos gatilhos
   datetime cur_time = iTime(_Symbol, _Period, 0);
   bool is_new_bar = (cur_time != g_last_bar_time);

   if(!is_new_bar) return;
   g_last_bar_time = cur_time;

   // 3. Se já estiver posicionado, não abre nova ordem (1 posição por vez)
   if(HasOpenPosition()) return;

   // 4. Checa trava de perda diária e sessão de trading
   if(g_risk.IsDailyLossLimitHit()) return;
   if(!g_risk.IsSessionAllowed()) return;

   // 5. Avalia regras de entrada do leilão
   CheckEntrySignals();
  }

//+------------------------------------------------------------------+
//| Verifica se tem posição aberta pelo MagicNumber                  |
//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol)
        {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Avalia Gatilhos de Entrada                                       |
//+------------------------------------------------------------------+
void CheckEntrySignals()
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, _Period, 1, 3, rates) < 3) return;

   double close_1 = rates[0].close;
   double open_1  = rates[0].open;
   double high_1  = rates[0].high;
   double low_1   = rates[0].low;
   double spread  = high_1 - low_1;
   double body    = MathAbs(close_1 - open_1);

   // Métricas do candle anterior (fechado)
   double atr        = g_physics.GetATR(1);
   double dragon_mid = g_pvsra.GetDragonMid(1);
   double trend_ema  = g_pvsra.GetTrend(1);
   double poc        = g_vap.GetPOC();
   double vah        = g_vap.GetVAH();
   double val        = g_vap.GetVAL();
   double delta_t    = g_physics.CalculateElasticStrain(close_1, dragon_mid, atr);
   double hurst      = g_physics.EstimateHurst(40);
   bool   is_climax  = g_pvsra.IsClimax(1);
   bool   is_rising  = g_pvsra.IsRising(1);
   bool   is_abnormal= g_pvsra.IsAbnormal(1);

   // Rejeição de pavio
   bool bear_rejection = (high_1 - MathMax(open_1, close_1) >= 1.0 * body) && (close_1 < high_1 - 0.4 * spread);
   bool bull_rejection = (MathMin(open_1, close_1) - low_1 >= 1.0 * body) && (close_1 > low_1 + 0.4 * spread);

   // -------------------------------------------------------------
   // A. SETUP REVERSÃO CONFIRMADA (Regime Alfa: Hurst <= 0.57)
   // -------------------------------------------------------------
   if(InpStrategyMode == MODE_HYBRID_TOTAL || InpStrategyMode == MODE_REVERSAL_CONFIRMED)
     {
      // 1. VENDA EM TOPO ESTICADO
      if(delta_t >= InpCritStrain && (is_climax || is_rising || close_1 >= vah) && bear_rejection && hurst <= InpHurstThreshold)
        {
         // Filtro de tendência: se acima da EMA 200, exige Delta_t maior ou Climax
         if(close_1 <= trend_ema || delta_t >= (InpCritStrain + 0.3) || is_climax)
           {
            double sl = high_1 + (0.25 * atr);
            double target_barrier = (poc < close_1) ? poc : (close_1 - 1.5 * (sl - close_1));

            // Front-running de alvo (80% da distância até o POC)
            double tp = g_physics.CalculateFrontRunTarget(close_1, target_barrier, 0.80);

            if(g_physics.IsHeadroomValid(close_1, sl, tp) && g_physics.IsOmegaSafe(close_1, sl, tp, dragon_mid, atr))
              {
               double pts = MathAbs(sl - close_1);
               double lot = g_risk.CalculateLotSize(pts);
               if(g_risk.OpenPosition(ORDER_TYPE_SELL, lot, SymbolInfoDouble(_Symbol, SYMBOL_BID), sl, tp, "PVSRA_Rev_Sell"))
                 {
                  g_partial_executed = false;
                  PrintFormat("[TRADE] Venda Reversão Aberta | Lote: %.2f | SL: %.2f | TP: %.2f | Delta_t: %.2f", lot, sl, tp, delta_t);
                  return;
                 }
              }
           }
        }

      // 2. COMPRA EM FUNDO ESTICADO
      if(delta_t <= -InpCritStrain && (is_climax || is_rising || close_1 <= val) && bull_rejection && hurst <= InpHurstThreshold)
        {
         if(close_1 >= trend_ema || delta_t <= -(InpCritStrain + 0.3) || is_climax)
           {
            double sl = low_1 - (0.25 * atr);
            double target_barrier = (poc > close_1) ? poc : (close_1 + 1.5 * (close_1 - sl));
            double tp = g_physics.CalculateFrontRunTarget(close_1, target_barrier, 0.80);

            if(g_physics.IsHeadroomValid(close_1, sl, tp) && g_physics.IsOmegaSafe(close_1, sl, tp, dragon_mid, atr))
              {
               double pts = MathAbs(close_1 - sl);
               double lot = g_risk.CalculateLotSize(pts);
               if(g_risk.OpenPosition(ORDER_TYPE_BUY, lot, SymbolInfoDouble(_Symbol, SYMBOL_ASK), sl, tp, "PVSRA_Rev_Buy"))
                 {
                  g_partial_executed = false;
                  PrintFormat("[TRADE] Compra Reversão Aberta | Lote: %.2f | SL: %.2f | TP: %.2f | Delta_t: %.2f", lot, sl, tp, delta_t);
                  return;
                 }
              }
           }
        }
     }

   // -------------------------------------------------------------
   // B. SETUP PULLBACK PÓS-BOS (Regime Gama: Hurst > 0.57)
   // -------------------------------------------------------------
   if(InpStrategyMode == MODE_HYBRID_TOTAL || InpStrategyMode == MODE_BOS_PULLBACK)
     {
      // 1. COMPRA NO PULLBACK DE ALTA (Reteste em VAH com Tendência de Alta)
      if(close_1 > trend_ema && low_1 <= vah && close_1 > vah && (bull_rejection || close_1 > open_1) && hurst > InpHurstThreshold)
        {
         double sl = vah - (0.80 * atr);
         double tp = close_1 + (1.6 * (close_1 - sl));

         if(g_physics.IsHeadroomValid(close_1, sl, tp))
           {
            double pts = MathAbs(close_1 - sl);
            double lot = g_risk.CalculateLotSize(pts);
            if(g_risk.OpenPosition(ORDER_TYPE_BUY, lot, SymbolInfoDouble(_Symbol, SYMBOL_ASK), sl, tp, "BOS_Pullback_Buy"))
              {
               g_partial_executed = false;
               PrintFormat("[TRADE] Compra Pullback BOS Aberta | Lote: %.2f | SL: %.2f | TP: %.2f", lot, sl, tp);
               return;
              }
           }
        }

      // 2. VENDA NO PULLBACK DE BAIXA (Reteste em VAL com Tendência de Baixa)
      if(close_1 < trend_ema && high_1 >= val && close_1 < val && (bear_rejection || close_1 < open_1) && hurst > InpHurstThreshold)
        {
         double sl = val + (0.80 * atr);
         double tp = close_1 - (1.6 * (sl - close_1));

         if(g_physics.IsHeadroomValid(close_1, sl, tp))
           {
            double pts = MathAbs(sl - close_1);
            double lot = g_risk.CalculateLotSize(pts);
            if(g_risk.OpenPosition(ORDER_TYPE_SELL, lot, SymbolInfoDouble(_Symbol, SYMBOL_BID), sl, tp, "BOS_Pullback_Sell"))
              {
               g_partial_executed = false;
               PrintFormat("[TRADE] Venda Pullback BOS Aberta | Lote: %.2f | SL: %.2f | TP: %.2f", lot, sl, tp);
               return;
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Gestão de Posição Aberta (Parcial 70/30 e Trailing Stop)         |
//+------------------------------------------------------------------+
void ManageOpenPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      ulong  ticket    = PositionGetTicket(i);
      long   pos_type  = PositionGetInteger(POSITION_TYPE);
      double entry_p   = PositionGetDouble(POSITION_PRICE_OPEN);
      double cur_sl    = PositionGetDouble(POSITION_SL);
      double cur_tp    = PositionGetDouble(POSITION_TP);
      double cur_price = PositionGetDouble(POSITION_PRICE_CURRENT);

      // 1. CHECAGEM DE SAÍDA PARCIAL 70% NO TP1
      if(InpUsePartialExit && !g_partial_executed)
        {
         bool reached_tp1 = false;
         if(pos_type == POSITION_TYPE_BUY  && cur_price >= cur_tp) reached_tp1 = true;
         if(pos_type == POSITION_TYPE_SELL && cur_price <= cur_tp) reached_tp1 = true;

         if(reached_tp1)
           {
            if(g_risk.ExecutePartialClose(ticket, InpPartialRatio))
              {
               g_partial_executed = true;
               // Move Stop para Breakeven
               g_risk.MoveStopToBreakeven(ticket, entry_p);
               PrintFormat("[GESTAO] Saída Parcial de %.0f%% executada! Stop movido para Breakeven (Ticket %d)", InpPartialRatio*100, ticket);
              }
           }
        }

      // 2. TRAILING STOP ESTRUTURAL BARRA-A-BARRA NOS 30% RESTANTES
      if(InpUseTrailingStop && g_partial_executed)
        {
         if(pos_type == POSITION_TYPE_BUY)
           {
            double new_sl = g_physics.GetStructuralTrailingStop(true, 1, 0.20);
            if(new_sl > cur_sl && new_sl > entry_p)
              {
               g_risk.ModifyStopLoss(ticket, new_sl);
               PrintFormat("[GESTAO] Trailing Stop Buy atualizado para %.2f (Ticket %d)", new_sl, ticket);
              }
           }
         else if(pos_type == POSITION_TYPE_SELL)
           {
            double new_sl = g_physics.GetStructuralTrailingStop(false, 1, 0.20);
            if(new_sl < cur_sl && new_sl < entry_p)
              {
               g_risk.ModifyStopLoss(ticket, new_sl);
               PrintFormat("[GESTAO] Trailing Stop Sell atualizado para %.2f (Ticket %d)", new_sl, ticket);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Atualização do Painel Visual HUD em Tela                         |
//+------------------------------------------------------------------+
void UpdateHUD()
  {
   double atr        = g_physics.GetATR(0);
   double dragon_mid = g_pvsra.GetDragonMid(0);
   double poc        = g_vap.GetPOC();
   double vah        = g_vap.GetVAH();
   double val        = g_vap.GetVAL();
   double delta_t    = g_physics.CalculateElasticStrain(SymbolInfoDouble(_Symbol, SYMBOL_BID), dragon_mid, atr);
   double hurst      = g_physics.EstimateHurst(40);
   ENUM_PVSRA_CANDLE_TYPE c_type = g_pvsra.GetCandleType(0);

   string txt_regime = (hurst <= InpHurstThreshold) ? "Alfa (Reversão / Fade)" : "Gama (BOS / Escape)";
   color  cor_regime = (hurst <= InpHurstThreshold) ? clrLimeGreen : clrGold;

   string txt_pvsra = "Normal";
   color  cor_pvsra = clrLightGray;
   if(c_type == PVSRA_CLIMAX_BULL) { txt_pvsra = "Clímax Touro"; cor_pvsra = clrLimeGreen; }
   if(c_type == PVSRA_CLIMAX_BEAR) { txt_pvsra = "Clímax Urso";  cor_pvsra = clrRed; }
   if(c_type == PVSRA_RISING_BULL) { txt_pvsra = "Rising Touro";  cor_pvsra = clrDodgerBlue; }
   if(c_type == PVSRA_RISING_BEAR) { txt_pvsra = "Rising Urso";   cor_pvsra = clrMagenta; }

   int x = 20, y = 30, step_y = 18;

   DrawHUDLabel("HUD_TITLE", "=== ROBÔ VIRADA DE DELTA PRO v3.0 ===", x, y, InpHUDColor, 10, true);
   DrawHUDLabel("HUD_POC",   StringFormat("POC 24h: %.2f | VAH: %.2f | VAL: %.2f", poc, vah, val), x, y += step_y, clrWhite, 9);
   DrawHUDLabel("HUD_STRAIN",StringFormat("Deformação Elástica Delta_t: %.2f (Crítico: >= %.1f)", delta_t, InpCritStrain), x, y += step_y, (MathAbs(delta_t) >= InpCritStrain ? clrYellow : clrWhite), 9);
   DrawHUDLabel("HUD_REGIME",StringFormat("Regime Langevin: %s (Hurst: %.2f)", txt_regime, hurst), x, y += step_y, cor_regime, 9);
   DrawHUDLabel("HUD_PVSRA", StringFormat("Candle PVSRA ao Vivo: %s", txt_pvsra), x, y += step_y, cor_pvsra, 9);
   DrawHUDLabel("HUD_SESSION",StringFormat("Filtro Sessão: %s", g_risk.IsSessionAllowed() ? "PERMITIDO (Dentro da Janela)" : "BLOQUEADO (Fora do Horário)"), x, y += step_y, (g_risk.IsSessionAllowed() ? clrLimeGreen : clrSalmon), 9);
   DrawHUDLabel("HUD_EQUITY", StringFormat("Capital: $%.2f | Rebaixamento Diário: %s", AccountInfoDouble(ACCOUNT_EQUITY), g_risk.IsDailyLossLimitHit() ? "BLOQUEADO (Limite Atingido)" : "OK (Normal)"), x, y += step_y, clrLightSteelBlue, 9);

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Auxiliar para Criação de Labels no Gráfico                       |
//+------------------------------------------------------------------+
void DrawHUDLabel(string name, string text, int x, int y, color clr, int font_size=9, bool bold=false)
  {
   string obj_name = g_hud_prefix + name;
   if(ObjectFind(0, obj_name) < 0)
     {
      ObjectCreate(0, obj_name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj_name, OBJPROP_HIDDEN, true);
     }
   ObjectSetString(0, obj_name, OBJPROP_TEXT, text);
   ObjectSetString(0, obj_name, OBJPROP_FONT, bold ? "Trebuchet MS Bold" : "Trebuchet MS");
   ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, font_size);
   ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clr);
  }
//+------------------------------------------------------------------+
