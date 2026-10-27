//+------------------------------------------------------------------+
//|                                              BoletaHedge.mq5     |
//|                             Copyright 2026, ViniBurgo Developer  |
//|    Travado (compras = vendas): não faz nada sem comando.         |
//|    Perna a mais: quando o lucro da perna paga perdedoras da      |
//|    trava com sobra >= alvo, fecha tudo junto e re-trava o ativo. |
//|    [Versão 1.61 - Auditada e Blindada contra Bugs de Execução]  |
//+------------------------------------------------------------------+
#property copyright "Senior MQL5 Developer & Quant Forensic Auditor"
#property link      "https://www.mql5.com"
#property version   "1.61"
#property description "Boleta de Hedge: trava blindada, fechamento no 0 a 0 sem duplicidade e re-trava segura"
#property strict

#include <Trade\Trade.mqh>

//--- Paleta (mesma da BoletaScalping)
#define COLOR_PANEL_BG        C'22,24,29'
#define COLOR_HEADER_BG       C'16,17,21'
#define COLOR_STRIP_BG        C'28,31,38'
#define COLOR_BORDER          C'38,42,52'
#define COLOR_TEXT_MAIN       C'240,242,245'
#define COLOR_TEXT_MUTED      C'150,155,168'
#define COLOR_EDIT_BG         C'32,35,44'
#define COLOR_CHECK_ACTIVE    C'0,210,130'
#define COLOR_CHECK_INACT     C'55,60,72'
#define COLOR_STEP_BTN        C'44,48,60'
#define COLOR_LOCK_BTN        C'35,90,165'
#define COLOR_BUY_BTN         C'16,160,85'
#define COLOR_SELL_BTN        C'210,45,55'
#define COLOR_PROFIT_GREEN    C'0,230,120'
#define COLOR_LOSS_RED        C'255,85,85'
#define COLOR_WARN            C'255,190,60'

#define PREFIX_GUI            "BHG_"
#define GV_LOCK_PREFIX        "BHedge_LOCK_"   // lido pela BoletaScalping (IsHedgeLocked)

input group "=== ATIVO & ROTEAMENTO ==="
input string   InpSymbol            = "";        // Ativo (Vazio = Gráfico Atual)
input ulong    InpMagic             = 778000;    // Magic das Ordens (Trava, Re-trava e Pernas)
input ulong    InpSlippage          = 50;        // Desvio Máximo (pontos - ajustado para 50 para evitar requote)

input group "=== TRAVA ==="
input bool     InpLockStripStops    = true;      // Remover SL/TP SOMENTE APÓS a Trava Confirmada

input group "=== FECHAMENTO NO 0 A 0 (ATIVO DESTRAVADO) ==="
input bool     InpGroupAuto         = true;      // Monitorar e Fechar Grupo Automático ao Iniciar
input double   InpGroupMinProfit    = 0.50;      // Alvo Líquido do Grupo ($) - folga sobre spread/comissão
input bool     InpUseCloseBy        = true;      // Fechar Compra x Venda por "Close By" (paga 1 spread só)
input bool     InpRelockAfterGroup  = true;      // Re-travar Automático Após Fechar o Grupo
input double   InpLegRelockLoss     = 0.00;      // Re-travar se a Perna Chegar a -$ (0 = desligado)

input group "=== PERNAS ==="
input double   InpLegLot            = 0.01;      // Lote Inicial da Perna
input int      InpLegSLPoints       = 0;         // SL da Perna (pontos, 0 = sem SL)

input group "=== FECHAR CESTA (SOMATÓRIO DO ATIVO) ==="
input bool     InpBasketAuto        = false;     // Fechar TUDO quando Líquido do Ativo >= Alvo
input double   InpBasketMinProfit   = 1.00;      // Alvo Líquido da Cesta ($) - ajustado para cobrir slippage
input bool     InpBasketCancelPend  = false;     // Cancelar Pendentes do Ativo ao Fechar a Cesta

input group "=== ALERTAS & PAINEL ==="
input bool     InpAlert             = true;      // Alerta Pop-up ao Fechar Grupo / Cesta
input bool     InpPush              = true;      // Notificação Push ao Fechar Grupo / Cesta
input double   InpStepCash          = 0.10;      // Passo dos Alvos ($) nos Botões + / -
input int      InpPanelX            = 20;        // Posição X do Painel
input int      InpPanelY            = 40;        // Posição Y do Painel

//--- Posição do ativo já com o líquido estimado (lucro + swap + comissão ida/volta).
struct SPos
{
   ulong  ticket;
   long   id;
   bool   buy;
   double vol;
   double net;
   double sl;
   double tp;
   long   time_msc;
};

string   g_sym;
CTrade   g_trade;
bool     g_inited = false;

// Valores do painel
double   g_leg_lot;
double   g_group_min;
double   g_basket_min;
double   g_leg_relock;
bool     g_group_auto;
bool     g_basket_auto;

// Retrato das posições (Collect)
SPos     g_pos[];
int      g_buys, g_sells;
double   g_buy_vol, g_sell_vol, g_buy_net, g_sell_net, g_total_net;

// Grupo candidato (FindGroup) e grupo em fechamento.
ulong    g_cand[];
double   g_cand_keep[];
int      g_cand_wins, g_cand_losses;
double   g_cand_est, g_cand_gap, g_cand_leg_net;
bool     g_cand_final = false;

// Ciclo de destrava
long     g_cycle_start_msc = 0;
double   g_cycle_base      = 0.0;
long     g_bal_msc         = 0;
double   g_bal_value       = 0.0;
bool     g_bal_seen        = false;
bool     g_group_active    = false;
ulong    g_group[];
double   g_group_keep[];
uint     g_group_sent[];      // evita reenviar antes do terminal refletir o fechamento
double   g_group_est = 0.0;

// Cesta em fechamento
bool     g_basket_closing = false;
double   g_basket_est     = 0.0;

// Cache da comissão de entrada por posição
long     g_cm_id[];
double   g_cm_in[];
double   g_cm_vol[];

// Throttle de atualização gráfica (evita sobrecarga de CPU)
uint     g_last_ui_update = 0;

//+------------------------------------------------------------------+
//| Volumes                                                          |
//+------------------------------------------------------------------+
double VolStep() { double s = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP); return (s > 0.0) ? s : 0.01; }
double VolMin()  { double m = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);  return (m > 0.0) ? m : 0.01; }

int LotDigits()
{
   return (int)MathMax(0.0, MathCeil(-MathLog10(VolStep()) - 1e-9));
}

double FloorVol(double v)
{
   double step = VolStep();
   return NormalizeDouble(MathFloor(v / step + 1e-7) * step, LotDigits());
}

double NormalizeLot(double v)
{
   double r = FloorVol(v);
   double mx = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   if(r < VolMin()) r = VolMin();
   if(mx > 0.0 && r > mx) r = mx;
   return NormalizeDouble(r, LotDigits());
}

void SetBestFillingMode(CTrade &trade, const string sym)
{
   uint filling = (uint)SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) != 0)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((filling & SYMBOL_FILLING_FOK) != 0)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
}

bool TradeOk()
{
   uint rc = g_trade.ResultRetcode();
   return (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL || rc == TRADE_RETCODE_PLACED);
}

bool CloseByAllowed()
{
   return InpUseCloseBy && ((SymbolInfoInteger(g_sym, SYMBOL_ORDER_MODE) & SYMBOL_ORDER_CLOSEBY) != 0);
}

void Notify(const string msg)
{
   Print(msg);
   if(InpAlert) Alert(msg);
   if(InpPush)  SendNotification(msg);
}

//+------------------------------------------------------------------+
//| Comissão de ida e volta estimada da posição                      |
//+------------------------------------------------------------------+
double RoundTripCommission(const long position_id, const double cur_volume)
{
   int k = -1;
   for(int i = ArraySize(g_cm_id) - 1; i >= 0; i--)
      if(g_cm_id[i] == position_id) { k = i; break; }

   if(k < 0)
   {
      double comm_in = 0.0, vol_in = 0.0;
      if(!HistorySelectByPosition(position_id)) return 0.0;
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT)
         {
            comm_in += HistoryDealGetDouble(deal, DEAL_COMMISSION);
            vol_in  += HistoryDealGetDouble(deal, DEAL_VOLUME);
         }
      }
      if(vol_in <= 0.0) return 0.0;

      if(ArraySize(g_cm_id) > 500) { ArrayResize(g_cm_id, 0); ArrayResize(g_cm_in, 0); ArrayResize(g_cm_vol, 0); }
      k = ArraySize(g_cm_id);
      ArrayResize(g_cm_id, k + 1); ArrayResize(g_cm_in, k + 1); ArrayResize(g_cm_vol, k + 1);
      g_cm_id[k] = position_id; g_cm_in[k] = comm_in; g_cm_vol[k] = vol_in;
   }
   return 2.0 * g_cm_in[k] * (cur_volume / g_cm_vol[k]);
}

//+------------------------------------------------------------------+
//| Retrato de TODAS as posições do ativo                            |
//+------------------------------------------------------------------+
void Collect()
{
   ArrayResize(g_pos, 0);
   g_buys = 0; g_sells = 0;
   g_buy_vol = 0.0; g_sell_vol = 0.0; g_buy_net = 0.0; g_sell_net = 0.0; g_total_net = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != g_sym) continue;

      SPos p;
      p.ticket   = ticket;
      p.id       = PositionGetInteger(POSITION_IDENTIFIER);
      p.buy      = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      p.vol      = PositionGetDouble(POSITION_VOLUME);
      p.sl       = PositionGetDouble(POSITION_SL);
      p.tp       = PositionGetDouble(POSITION_TP);
      p.time_msc = PositionGetInteger(POSITION_TIME_MSC);
      p.net      = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      p.net     += RoundTripCommission(p.id, p.vol);

      int n = ArraySize(g_pos);
      ArrayResize(g_pos, n + 1);
      g_pos[n] = p;

      g_total_net += p.net;
      if(p.buy) { g_buys++;  g_buy_vol  += p.vol; g_buy_net  += p.net; }
      else      { g_sells++; g_sell_vol += p.vol; g_sell_net += p.net; }
   }
}

bool IsBalanced() { return MathAbs(g_buy_vol - g_sell_vol) < VolStep() / 2.0; }
bool IsLocked()   { return (g_buys > 0 && g_sells > 0 && IsBalanced()); }
bool IsHedged()   { return (g_buys > 0 && g_sells > 0); }

//+------------------------------------------------------------------+
//| Trava Blindada: iguala compras e vendas com segurança cirúrgica   |
//| [CORREÇÃO FORENSE]: Apenas remove SL/TP APÓS confirmar execução! |
//+------------------------------------------------------------------+
bool Travar(const bool from_button)
{
   Collect();
   if(g_buys + g_sells == 0)
   {
      if(from_button) Alert(StringFormat("%s: nenhuma posição para travar.", g_sym));
      return false;
   }

   double diff = g_buy_vol - g_sell_vol;
   double vol  = FloorVol(MathAbs(diff));
   if(vol < VolMin() - 1e-8)
   {
      if(MathAbs(diff) > 1e-8)
         PrintFormat("TRAVA %s: diferença de %.3f lote é menor que o lote mínimo, não dá para igualar.", g_sym, MathAbs(diff));
      else if(from_button)
         PrintFormat("TRAVA %s: já está travado (%.2f x %.2f).", g_sym, g_buy_vol, g_sell_vol);
      return (MathAbs(diff) <= 1e-8);
   }

   // 1º: Executar a ordem de trava ANTES de remover qualquer Stop Loss
   bool ok = (diff > 0.0) ? g_trade.Sell(vol, g_sym, 0.0, 0.0, 0.0, "HG Trava")
                          : g_trade.Buy(vol, g_sym, 0.0, 0.0, 0.0, "HG Trava");
   if(!ok || !TradeOk())
   {
      Notify(StringFormat("TRAVA %s FALHOU: %s %.2f (%u %s). STOP LOSS MANTIDO PARA SUA SEGURANÇA!", g_sym,
                          (diff > 0.0) ? "venda" : "compra", vol,
                          g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription()));
      return false;
   }

   PrintFormat("TRAVA %s: %s %.2f executada com sucesso para igualar %.2f x %.2f", g_sym, (diff > 0.0) ? "venda" : "compra", vol, g_buy_vol, g_sell_vol);

   // 2º: Somente após a confirmação da ordem no servidor, remove SL/TP se configurado
   if(InpLockStripStops)
   {
      Collect();
      for(int i = 0; i < ArraySize(g_pos); i++)
      {
         if(g_pos[i].sl == 0.0 && g_pos[i].tp == 0.0) continue;
         if(g_trade.PositionModify(g_pos[i].ticket, 0.0, 0.0))
            PrintFormat("TRAVA %s: SL/TP removidos com segurança do #%I64u", g_sym, g_pos[i].ticket);
         else
            PrintFormat("TRAVA %s: falha ao remover SL/TP do #%I64u (%u %s)", g_sym, g_pos[i].ticket,
                        g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      }
   }

   if(MathAbs(diff) - vol > 1e-8)
      PrintFormat("TRAVA %s: sobrou %.3f lote sem trava (abaixo do passo de lote).", g_sym, MathAbs(diff) - vol);
   return true;
}

//+------------------------------------------------------------------+
//| Abertura de Perna Direcional                                     |
//+------------------------------------------------------------------+
void OpenLeg(const bool buy)
{
   double point = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   double sl = 0.0;
   if(InpLegSLPoints > 0)
      sl = buy ? SymbolInfoDouble(g_sym, SYMBOL_BID) - InpLegSLPoints * point
               : SymbolInfoDouble(g_sym, SYMBOL_ASK) + InpLegSLPoints * point;

   bool ok = buy ? g_trade.Buy(g_leg_lot, g_sym, 0.0, sl, 0.0, "HG Perna")
                 : g_trade.Sell(g_leg_lot, g_sym, 0.0, sl, 0.0, "HG Perna");
   if(!ok || !TradeOk())
      PrintFormat("PERNA %s FALHOU: %u %s", g_sym, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Resultado realizado do ativo desde o início do ciclo             |
//+------------------------------------------------------------------+
double CycleRealized()
{
   if(g_cycle_start_msc == 0 || !HistorySelect((datetime)(g_cycle_start_msc / 1000), TimeCurrent() + 1)) return 0.0;
   double sum = 0.0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || HistoryDealGetString(d, DEAL_SYMBOL) != g_sym) continue;
      if(HistoryDealGetInteger(d, DEAL_TIME_MSC) < g_cycle_start_msc) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN) continue;
      sum += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_SWAP);
   }
   return sum;
}

//+------------------------------------------------------------------+
//| Sincronização Temporal do Ciclo de Destrava                      |
//| [CORREÇÃO FORENSE]: Tolerância de timestamp sem somas espúrias   |
//+------------------------------------------------------------------+
void TrackCycle()
{
   if(IsLocked())
   {
      MqlTick tick;
      g_bal_msc = (SymbolInfoTick(g_sym, tick) ? tick.time_msc : (long)TimeCurrent() * 1000);
      g_bal_value = g_total_net;
      g_bal_seen = true;
      g_cycle_start_msc = 0;
   }
   else if(ArraySize(g_pos) == 0)
      g_cycle_start_msc = 0;
   else if(IsHedged() && g_cycle_start_msc == 0)
   {
      g_cycle_start_msc = g_bal_seen ? g_bal_msc : (long)TimeCurrent() * 1000;
      g_cycle_base      = g_bal_seen ? g_bal_value : g_total_net;
   }
}

//+------------------------------------------------------------------+
//| Localização e Montagem do Grupo do 0 a 0                         |
//+------------------------------------------------------------------+
void AddCand(const ulong ticket, const double keep)
{
   int s = ArraySize(g_cand);
   ArrayResize(g_cand, s + 1);
   ArrayResize(g_cand_keep, s + 1);
   g_cand[s]      = ticket;
   g_cand_keep[s] = keep;
}

double FitVol(const double want, const double have)
{
   double v = FloorVol(MathMin(want, have));
   double rest = have - v;
   if(rest > 1e-8 && rest < VolMin() - 1e-8) v = FloorVol(have - VolMin());
   return (v < VolMin() - 1e-8) ? 0.0 : v;
}

bool FindGroup()
{
   ArrayResize(g_cand, 0);
   ArrayResize(g_cand_keep, 0);
   g_cand_wins = 0; g_cand_losses = 0; g_cand_est = 0.0; g_cand_gap = 0.0; g_cand_leg_net = 0.0;
   g_cand_final = false;
   
   int    n = ArraySize(g_pos);
   double excess = g_buy_vol - g_sell_vol;
   if(MathAbs(excess) < VolStep() / 2.0 || g_cycle_start_msc == 0) return false;
   bool heavy_buy = (excess > 0.0);
   
   double realized = CycleRealized();
   g_cand_leg_net  = realized + g_total_net - g_cycle_base;
   
   double take[];
   bool   is_leg[];
   ArrayResize(take, n);
   ArrayResize(is_leg, n);
   double leg_vol = 0.0, budget = realized - g_group_min;
   for(int i = 0; i < n; i++)
   {
      take[i]   = 0.0;
      // Tolerância temporal de 50ms para evitar rejeição por latência de tick
      is_leg[i] = (g_pos[i].buy == heavy_buy && g_pos[i].time_msc >= (g_cycle_start_msc - 50));
      if(is_leg[i]) { take[i] = g_pos[i].vol; leg_vol += g_pos[i].vol; budget += g_pos[i].net; g_cand_wins++; }
   }
   
   double core_buy  = g_buy_vol  - (heavy_buy ? leg_vol : 0.0);
   double core_sell = g_sell_vol - (heavy_buy ? 0.0 : leg_vol);
   if(leg_vol > 0.0 && core_buy <= VolMin() + 1e-8 && core_sell <= VolMin() + 1e-8)
   {
      g_cand_final = true;
      if(g_total_net < g_group_min) { g_cand_gap = g_group_min - g_total_net; return false; }
      for(int i = 0; i < n; i++)
      {
         AddCand(g_pos[i].ticket, 0.0);
         if(!is_leg[i]) g_cand_losses++;
      }
      g_cand_est = realized + g_total_net;
      return true;
   }
   
   int order[];
   ArrayResize(order, 0);
   for(int i = 0; i < n; i++)
      if(!is_leg[i]) { int k = ArraySize(order); ArrayResize(order, k + 1); order[k] = i; }
   for(int a = 0; a < ArraySize(order) - 1; a++)
      for(int b = a + 1; b < ArraySize(order); b++)
         if(g_pos[order[b]].net / g_pos[order[b]].vol < g_pos[order[a]].net / g_pos[order[a]].vol)
         {
            int t = order[a]; order[a] = order[b]; order[b] = t;
         }
   
   double need = NormalizeDouble(MathAbs(excess) - leg_vol, LotDigits());
   for(int k = 0; k < ArraySize(order) && need > 1e-8; k++)
   {
      int i = order[k];
      if(g_pos[i].buy != heavy_buy) continue;
      double v = FitVol(need, g_pos[i].vol);
      if(v <= 0.0) continue;
      take[i] += v;
      budget  += v * g_pos[i].net / g_pos[i].vol;
      need     = NormalizeDouble(need - v, LotDigits());
      g_cand_losses++;
   }
   if(need > 1e-8) return false;
   if(budget < 0.0 && g_cand_losses > 0) { g_cand_gap = -budget; return false; }
   
   double cheapest_min = -1.0;
   for(int k = 0; k < ArraySize(order); k++)
   {
      int i = order[k];
      if(g_pos[i].net >= 0.0) continue;
      double per_lot = -g_pos[i].net / g_pos[i].vol;
      double left    = g_pos[i].vol - take[i];
      if(left < VolMin() - 1e-8) continue;
      if(cheapest_min < 0.0 || per_lot * VolMin() < cheapest_min) cheapest_min = per_lot * VolMin();
      if(budget <= 0.0) continue;
      double v = FitVol(budget / per_lot, left);
      if(v <= 0.0) continue;
      take[i] += v;
      budget  -= v * per_lot;
      g_cand_losses++;
   }
   
   if(g_cand_losses == 0)
   {
      g_cand_gap = (cheapest_min > 0.0) ? cheapest_min - budget : 0.0;
      return false;
   }
   
   for(int i = 0; i < n; i++)
      if(take[i] > 1e-8)
         AddCand(g_pos[i].ticket, NormalizeDouble(g_pos[i].vol - take[i], LotDigits()));
   g_cand_est = budget + g_group_min;
   return true;
}

//+------------------------------------------------------------------+
//| Sugestão com Aviso de Risco Tendencial                           |
//+------------------------------------------------------------------+
#define SUG_NONE   0
#define SUG_LEG    1
#define SUG_CUT    2

int LegSuggestion(bool &buy)
{
   if(!IsLocked() || MathAbs(g_buy_net - g_sell_net) < 0.01) return SUG_NONE;
   buy = (g_buy_net < g_sell_net);
   double opp = buy ? g_sell_vol : g_buy_vol;
   return (opp - g_leg_lot >= VolMin() - 1e-8) ? SUG_CUT : SUG_LEG;
}

void CutSide(const bool cut_buys)
{
   Collect();
   double need = g_leg_lot;
   for(int guard = 0; guard < 50 && need > 1e-8; guard++)
   {
      int best = -1;
      for(int i = 0; i < ArraySize(g_pos); i++)
         if(g_pos[i].buy == cut_buys && FitVol(need, g_pos[i].vol) > 0.0 &&
            (best < 0 || g_pos[i].net / g_pos[i].vol > g_pos[best].net / g_pos[best].vol))
            best = i;
      if(best < 0) break;
      double v = FitVol(need, g_pos[best].vol);
      bool ok = (v >= g_pos[best].vol - 1e-8) ? g_trade.PositionClose(g_pos[best].ticket)
                                              : g_trade.PositionClosePartial(g_pos[best].ticket, v);
      if(!ok || !TradeOk())
      {
         PrintFormat("RETIRAR %s: falha em %.2f da #%I64u (%u %s)", g_sym, v, g_pos[best].ticket,
                     g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
         break;
      }
      PrintFormat("RETIRAR %s: %.2f da #%I64u (%s %+.2f por lote)", g_sym, v, g_pos[best].ticket,
                  cut_buys ? "compra" : "venda", g_pos[best].net / g_pos[best].vol);
      need = NormalizeDouble(need - v, LotDigits());
      Collect();
   }
}

void ExecuteSuggestion()
{
   Collect();
   bool buy = false;
   int  mode = LegSuggestion(buy);
   if(mode == SUG_CUT)      CutSide(!buy);
   else if(mode == SUG_LEG) OpenLeg(buy);
   else Print("SUGESTÃO: só com o ativo travado e um lado perdendo mais que o outro.");
}

void StartGroup()
{
   g_group_active = true;
   g_group_est    = g_cand_est;
   ArrayCopy(g_group, g_cand);
   ArrayCopy(g_group_keep, g_cand_keep);
   ArrayResize(g_group_sent, ArraySize(g_group));
   for(int i = 0; i < ArraySize(g_group_sent); i++) g_group_sent[i] = 0;
   for(int i = 0; i < ArraySize(g_group); i++)
      if(g_group_keep[i] > 0.0 && PositionSelectByTicket(g_group[i]))
         PrintFormat("GRUPO %s: parcial de %.2f na #%I64u (fica %.2f)", g_sym,
                     PositionGetDouble(POSITION_VOLUME) - g_group_keep[i], g_group[i], g_group_keep[i]);
   PrintFormat("GRUPO %s: %d perna(s) + %d perdedora(s) = %+.2f >= alvo %.2f (compras %.2f x vendas %.2f). Fechando.",
               g_sym, g_cand_wins, g_cand_losses, g_cand_est, g_group_min, g_buy_vol, g_sell_vol);
   GroupStep();
}

double GroupRemaining(const int i)
{
   if(!PositionSelectByTicket(g_group[i])) return 0.0;
   return NormalizeDouble(PositionGetDouble(POSITION_VOLUME) - g_group_keep[i], LotDigits());
}

bool GroupRecentlySent(const int i, const uint now)
{
   return (g_group_sent[i] != 0 && now - g_group_sent[i] <= 3000);
}

//+------------------------------------------------------------------+
//| Fechamento do Grupo Blindado contra Disparos Duplicados          |
//| [CORREÇÃO FORENSE]: Atualiza g_group_sent em CloseBy!           |
//+------------------------------------------------------------------+
void GroupStep()
{
   uint now = GetTickCount();
   int  n   = ArraySize(g_group);
   
   if(CloseByAllowed())
   {
      for(int guard = 0; guard < 100; guard++)
      {
         int bi = -1, si = -1;
         for(int i = 0; i < n && bi < 0; i++)
         {
            double ri = GroupRemaining(i);
            if(ri <= 1e-8 || GroupRecentlySent(i, now)) continue;
            if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) continue;
            double vi = PositionGetDouble(POSITION_VOLUME);
            for(int j = 0; j < n; j++)
            {
               double rj = GroupRemaining(j);
               if(rj <= 1e-8 || GroupRecentlySent(j, now)) continue;
               if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_SELL) continue;
               double by = MathMin(vi, PositionGetDouble(POSITION_VOLUME));
               if(by <= ri + 1e-8 && by <= rj + 1e-8) { bi = i; si = j; break; }
            }
         }
         if(bi < 0) break;
         
         if(g_trade.PositionCloseBy(g_group[bi], g_group[si]) && TradeOk())
         {
            // [CORREÇÃO CRÍTICA]: Registrar imediatamente o envio de ambas as posições para evitar duplicação a mercado!
            g_group_sent[bi] = now;
            g_group_sent[si] = now;
            PrintFormat("GRUPO %s: Close By disparado com sucesso entre #%I64u e #%I64u", g_sym, g_group[bi], g_group[si]);
         }
         else
         {
            PrintFormat("GRUPO %s: Close By #%I64u x #%I64u falhou (%u %s), fechando a mercado",
                        g_sym, g_group[bi], g_group[si], g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
            break;
         }
      }
   }
   
   for(int i = 0; i < n; i++)
   {
      double r = GroupRemaining(i);
      if(r <= 1e-8 || GroupRecentlySent(i, now)) continue;
      bool ok = (g_group_keep[i] <= 1e-8) ? g_trade.PositionClose(g_group[i])
                                          : g_trade.PositionClosePartial(g_group[i], r);
      if(ok && TradeOk()) g_group_sent[i] = now;
      else PrintFormat("GRUPO %s: falha ao fechar %.2f da #%I64u (%u %s), tentando no próximo tick",
                       g_sym, r, g_group[i], g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   }
   
   for(int i = 0; i < n; i++)
      if(GroupRemaining(i) > 1e-8) return;
   
   g_group_active = false;
   Collect();
   bool relocked = false;
   if(InpRelockAfterGroup && g_buys + g_sells > 0 && !IsBalanced())
      relocked = Travar(false);
   Collect();
   Notify(StringFormat("Grupo %s fechado no 0 a 0: líquido estimado %+.2f %s.%s Ficou: %.2f C x %.2f V",
                       g_sym, g_group_est, AccountInfoString(ACCOUNT_CURRENCY),
                       relocked ? " Re-travado." : "", g_buy_vol, g_sell_vol));
}

//+------------------------------------------------------------------+
//| Fechar Cesta                                                     |
//+------------------------------------------------------------------+
void BasketStep()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != g_sym) continue;
      if(!g_trade.PositionClose(ticket))
         PrintFormat("CESTA %s: falha ao fechar #%I64u (%u %s), tentando no próximo tick",
                     g_sym, ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == g_sym) return;
   }

   if(InpBasketCancelPend)
   {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket > 0 && OrderGetString(ORDER_SYMBOL) == g_sym)
            g_trade.OrderDelete(ticket);
      }
   }
   g_basket_closing = false;
   Notify(StringFormat("Cesta %s fechada (todas as ordens). Líquido estimado: %+.2f %s",
                       g_sym, g_basket_est, AccountInfoString(ACCOUNT_CURRENCY)));
}

//+------------------------------------------------------------------+
//| Sinalizador de Hedge Global                                      |
//+------------------------------------------------------------------+
void UpdateLockFlag()
{
   string gv = GV_LOCK_PREFIX + g_sym;
   if(IsHedged() || g_group_active || g_basket_closing)
      GlobalVariableSet(gv, (double)TimeCurrent());
   else if(GlobalVariableCheck(gv))
      GlobalVariableDel(gv);
}

//+------------------------------------------------------------------+
//| Interface Gráfica                                                |
//+------------------------------------------------------------------+
void CreateRect(const string name, int x, int y, int w, int h, color bg)
{
   string obj = PREFIX_GUI + name;
   ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, COLOR_BORDER);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
}

void CreateButton(const string name, int x, int y, int w, int h, const string text, color bg, color fg, int fs = 8)
{
   string obj = PREFIX_GUI + name;
   ObjectCreate(0, obj, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetString(0, obj, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, fs);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, COLOR_BORDER);
   ObjectSetInteger(0, obj, OBJPROP_STATE, false);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
}

void CreateEdit(const string name, int x, int y, int w, int h, const string text)
{
   string obj = PREFIX_GUI + name;
   ObjectCreate(0, obj, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetString(0, obj, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, obj, OBJPROP_ALIGN, ALIGN_CENTER);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, COLOR_EDIT_BG);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, COLOR_TEXT_MAIN);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, COLOR_BORDER);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
}

void CreateLabel(const string name, int x, int y, const string text, color clr, int fs = 8, bool bold = false)
{
   string obj = PREFIX_GUI + name;
   ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetString(0, obj, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, fs);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
}

void SetText(const string name, const string text, color clr)
{
   ObjectSetString(0, PREFIX_GUI + name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, PREFIX_GUI + name, OBJPROP_COLOR, clr);
}

void SetCheck(const string name, const bool on)
{
   ObjectSetString(0, PREFIX_GUI + name, OBJPROP_TEXT, on ? "X" : "");
   ObjectSetInteger(0, PREFIX_GUI + name, OBJPROP_BGCOLOR, on ? COLOR_CHECK_ACTIVE : COLOR_CHECK_INACT);
}

void StepperRow(const string key, int ox, int y, const string label, const string value, bool has_check, bool checked)
{
   if(has_check)
   {
      CreateButton("Chk_" + key, ox, y + 1, 16, 16, "", COLOR_CHECK_INACT, clrWhite);
      SetCheck("Chk_" + key, checked);
   }
   CreateLabel("Lbl_" + key, ox + (has_check ? 20 : 0), y + 3, label, COLOR_TEXT_MAIN, 8);
   CreateButton("Btn_" + key + "_Dec", ox + 128, y, 20, 18, "-", COLOR_STEP_BTN, COLOR_TEXT_MAIN);
   CreateEdit("Edit_" + key, ox + 151, y, 60, 18, value);
   CreateButton("Btn_" + key + "_Inc", ox + 214, y, 20, 18, "+", COLOR_STEP_BTN, COLOR_TEXT_MAIN);
}

void Render()
{
   ObjectsDeleteAll(0, PREFIX_GUI);
   int x = InpPanelX, y = InpPanelY, w = 250;
   int ox = x + 8, row_w = w - 16, half = (row_w - 6) / 2;

   CreateRect("Panel_BG", x, y, w, 100, COLOR_PANEL_BG);
   CreateRect("Header_BG", x, y, w, 26, COLOR_HEADER_BG);
   CreateLabel("Lbl_Title", ox, y + 6, "BOLETA HEDGE  " + g_sym, COLOR_TEXT_MAIN, 9, true);
   int cur_y = y + 32;

   CreateRect("Status_BG", ox, cur_y, row_w, 83, COLOR_STRIP_BG);
   for(int i = 1; i <= 5; i++)
      CreateLabel("Lbl_S" + IntegerToString(i), ox + 6, cur_y + 5 + (i - 1) * 15, "--", COLOR_TEXT_MUTED, 8, i == 3);
   cur_y += 89;

   StepperRow("Lot", ox, cur_y, "Lote da Perna", DoubleToString(g_leg_lot, LotDigits()), false, false);
   cur_y += 23;
   StepperRow("Group", ox, cur_y, "Auto 0 a 0 (+$)", DoubleToString(g_group_min, 2), true, g_group_auto);
   cur_y += 23;
   StepperRow("Relock", ox, cur_y, "Re-travar perna (-$)", DoubleToString(g_leg_relock, 2), false, false);
   cur_y += 23;
   StepperRow("Basket", ox, cur_y, "Fechar Cesta ($)", DoubleToString(g_basket_min, 2), true, g_basket_auto);
   cur_y += 27;

   CreateButton("Btn_Lock", ox, cur_y, row_w, 28, "TRAVAR [T]", COLOR_LOCK_BTN, COLOR_TEXT_MAIN, 9);
   cur_y += 32;
   CreateButton("Btn_LegBuy", ox, cur_y, half, 28, "PERNA COMPRA", COLOR_BUY_BTN, COLOR_TEXT_MAIN, 8);
   CreateButton("Btn_LegSell", ox + half + 6, cur_y, half, 28, "PERNA VENDA", COLOR_SELL_BTN, COLOR_TEXT_MAIN, 8);
   cur_y += 32;
   CreateButton("Btn_Suggest", ox, cur_y, row_w, 24, "EXECUTAR SUGESTÃO [S]", C'120,90,20', COLOR_TEXT_MAIN, 8);
   cur_y += 28;

   ObjectSetInteger(0, PREFIX_GUI + "Panel_BG", OBJPROP_YSIZE, cur_y - y + 4);
   UpdatePanel();
}

string Money(const double v) { return StringFormat("%s%.2f", (v >= 0.0) ? "+" : "-", MathAbs(v)); }
color  PnlColor(const double v) { return (v >= 0.0) ? COLOR_PROFIT_GREEN : COLOR_LOSS_RED; }

void UpdatePanel()
{
   int ld = LotDigits();
   SetText("Lbl_S1", StringFormat("Compras: %d  |  %s lt  |  %s", g_buys, DoubleToString(g_buy_vol, ld), Money(g_buy_net)),
           (g_buys > 0) ? PnlColor(g_buy_net) : COLOR_TEXT_MUTED);
   SetText("Lbl_S2", StringFormat("Vendas:  %d  |  %s lt  |  %s", g_sells, DoubleToString(g_sell_vol, ld), Money(g_sell_net)),
           (g_sells > 0) ? PnlColor(g_sell_net) : COLOR_TEXT_MUTED);

   if(!IsHedged())
      SetText("Lbl_S3", "SEM TRAVA", COLOR_TEXT_MUTED);
   else if(IsBalanced())
      SetText("Lbl_S3", "TRAVADO - aguardando comando", COLOR_CHECK_ACTIVE);
   else
      SetText("Lbl_S3", StringFormat("PERNA A MAIS  (%+.2f lt)", g_buy_vol - g_sell_vol), COLOR_WARN);

   if(g_group_active)
      SetText("Lbl_S4", "FECHANDO GRUPO...", clrYellow);
   else if(g_basket_closing)
      SetText("Lbl_S4", "FECHANDO CESTA...", clrYellow);
   else if(IsLocked())
   {
      bool sug_buy = false;
      int  mode = LegSuggestion(sug_buy);
      if(mode == SUG_CUT)
         SetText("Lbl_S4", StringFormat("Melhor: RETIRAR %.2f das %s (perna %s)", g_leg_lot,
                                        sug_buy ? "VENDAS" : "COMPRAS", sug_buy ? "COMPRA" : "VENDA"), COLOR_WARN);
      else if(mode == SUG_LEG)
         SetText("Lbl_S4", StringFormat("Melhor: PERNA %s %.2f (%s perdendo %s)", sug_buy ? "COMPRA" : "VENDA", g_leg_lot,
                                        sug_buy ? "compras" : "vendas", Money(sug_buy ? g_buy_net : g_sell_net)), COLOR_WARN);
      else
         SetText("Lbl_S4", "Sugestão: --", COLOR_TEXT_MUTED);
   }
   else if(!IsHedged())
      SetText("Lbl_S4", "0 a 0: parado", COLOR_TEXT_MUTED);
   else if(!g_group_auto)
      SetText("Lbl_S4", "0 a 0: desligado", COLOR_TEXT_MUTED);
   else if(FindGroup() && g_cand_final)
      SetText("Lbl_S4", StringFormat("Saída final: fechando TUDO %s", Money(g_total_net)), COLOR_PROFIT_GREEN);
   else if(g_cand_final)
      SetText("Lbl_S4", StringFormat("Saída final: somatório %s | alvo %.2f", Money(g_total_net), g_group_min), PnlColor(g_total_net));
   else if(FindGroup())
      SetText("Lbl_S4", StringFormat("Grupo pronto: perna + %d perdedora(s) %s", g_cand_losses, Money(g_cand_est)), COLOR_PROFIT_GREEN);
   else if(g_cand_gap > 0.0)
      SetText("Lbl_S4", StringFormat("Perna %s | faltam $%.2f%s", Money(g_cand_leg_net), g_cand_gap,
                                     (g_leg_relock > 0.0) ? StringFormat(" | trava em -%.2f", g_leg_relock) : ""), PnlColor(g_cand_leg_net));
   else
      SetText("Lbl_S4", StringFormat("Perna %s | aguardando ficar > alvo", Money(g_cand_leg_net)), PnlColor(g_cand_leg_net));

   bool sug_buy = false;
   bool has_sug = (LegSuggestion(sug_buy) != SUG_NONE);
   ObjectSetInteger(0, PREFIX_GUI + "Btn_LegBuy",  OBJPROP_BORDER_COLOR, (has_sug && sug_buy)  ? clrGold : COLOR_BORDER);
   ObjectSetInteger(0, PREFIX_GUI + "Btn_LegSell", OBJPROP_BORDER_COLOR, (has_sug && !sug_buy) ? clrGold : COLOR_BORDER);
   ObjectSetString(0, PREFIX_GUI + "Btn_LegBuy",  OBJPROP_TEXT, (has_sug && sug_buy)  ? "> PERNA COMPRA <" : "PERNA COMPRA");
   ObjectSetString(0, PREFIX_GUI + "Btn_LegSell", OBJPROP_TEXT, (has_sug && !sug_buy) ? "> PERNA VENDA <"  : "PERNA VENDA");
   
   SetText("Lbl_S5", StringFormat("Líquido do ativo: %s %s%s", Money(g_total_net), AccountInfoString(ACCOUNT_CURRENCY),
                                  g_basket_auto ? StringFormat("  (cesta %.2f)", g_basket_min) : ""),
           (ArraySize(g_pos) > 0) ? PnlColor(g_total_net) : COLOR_TEXT_MUTED);
   
   ChartRedraw(0);
}

void UpdateFieldValues()
{
   ObjectSetString(0, PREFIX_GUI + "Edit_Lot", OBJPROP_TEXT, DoubleToString(g_leg_lot, LotDigits()));
   ObjectSetString(0, PREFIX_GUI + "Edit_Group", OBJPROP_TEXT, DoubleToString(g_group_min, 2));
   ObjectSetString(0, PREFIX_GUI + "Edit_Basket", OBJPROP_TEXT, DoubleToString(g_basket_min, 2));
   ObjectSetString(0, PREFIX_GUI + "Edit_Relock", OBJPROP_TEXT, DoubleToString(g_leg_relock, 2));
   SetCheck("Chk_Group", g_group_auto);
   SetCheck("Chk_Basket", g_basket_auto);
   UpdatePanel();
}

//+------------------------------------------------------------------+
//| Ciclo Principal com Throttling Gráfico                           |
//+------------------------------------------------------------------+
void Process()
{
   Collect();
   TrackCycle();
   if(g_group_active)
      GroupStep();
   else if(g_basket_closing)
      BasketStep();
   else if(g_basket_auto && ArraySize(g_pos) > 0 && g_total_net >= g_basket_min)
   {
      PrintFormat("CESTA %s: líquido %+.2f >= alvo %.2f. Fechando TODAS.", g_sym, g_total_net, g_basket_min);
      g_basket_closing = true;
      g_basket_est     = g_total_net;
      BasketStep();
   }
   else if(g_group_auto && IsHedged() && !IsBalanced())
   {
      if(FindGroup())
         StartGroup();
      else if(g_leg_relock > 0.0 && g_cand_leg_net <= -g_leg_relock)
      {
         PrintFormat("PERNA %s: %+.2f <= -%.2f. Re-travando.", g_sym, g_cand_leg_net, g_leg_relock);
         if(Travar(false))
         {
            Collect();
            Notify(StringFormat("Perna %s re-travada em %+.2f %s. Trava: %.2f C x %.2f V",
                                g_sym, g_cand_leg_net, AccountInfoString(ACCOUNT_CURRENCY), g_buy_vol, g_sell_vol));
         }
      }
   }

   Collect();
   UpdateLockFlag();

   // [CORREÇÃO FORENSE]: Throttling de redesenho da tela (máx 10 FPS / 100ms) para poupar CPU
   uint now = GetTickCount();
   if(now - g_last_ui_update >= 100)
   {
      UpdatePanel();
      g_last_ui_update = now;
   }
}

int OnInit()
{
   g_sym = (InpSymbol != "") ? InpSymbol : _Symbol;
   if(!SymbolSelect(g_sym, true))
   {
      Alert("BoletaHedge: ativo inválido: " + g_sym);
      return INIT_PARAMETERS_INCORRECT;
   }
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Alert("BoletaHedge: a conta é NETTING. Trava só existe em conta HEDGING.");
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippage);
   SetBestFillingMode(g_trade, g_sym);

   if(!g_inited)
   {
      g_leg_lot     = NormalizeLot(InpLegLot);
      g_group_min   = MathMax(0.0, InpGroupMinProfit);
      g_basket_min  = (InpBasketMinProfit > 0.0) ? InpBasketMinProfit : 0.01;
      g_leg_relock  = MathMax(0.0, InpLegRelockLoss);
      g_group_auto  = InpGroupAuto;
      g_basket_auto = InpBasketAuto;
      g_inited      = true;
   }

   if(InpUseCloseBy && !CloseByAllowed())
      PrintFormat("BoletaHedge: %s não aceita Close By nesta corretora, o grupo fecha a mercado.", g_sym);

   Collect();
   Render();
   UpdateLockFlag();
   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, PREFIX_GUI);
   if(reason != REASON_CHARTCHANGE && reason != REASON_PARAMETERS && reason != REASON_RECOMPILE)
      GlobalVariableDel(GV_LOCK_PREFIX + g_sym);
   ChartRedraw(0);
}

void OnTick()
{
   Process();
}

void OnTimer()
{
   Process();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_KEYDOWN)
   {
      if(lparam == 84 || lparam == 116) { Travar(true); Process(); }          // T
      if(lparam == 83 || lparam == 115) { ExecuteSuggestion(); Process(); }   // S
      return;
   }

   if(id == CHARTEVENT_OBJECT_ENDEDIT && StringFind(sparam, PREFIX_GUI) == 0)
   {
      string key = StringSubstr(sparam, StringLen(PREFIX_GUI));
      double val = StringToDouble(ObjectGetString(0, sparam, OBJPROP_TEXT));
      if(key == "Edit_Lot"    && val > 0.0)   g_leg_lot    = NormalizeLot(val);
      if(key == "Edit_Group"  && val >= 0.0)  g_group_min  = NormalizeDouble(val, 2);
      if(key == "Edit_Basket" && val >= 0.01) g_basket_min = NormalizeDouble(val, 2);
      if(key == "Edit_Relock" && val >= 0.0)  g_leg_relock = NormalizeDouble(val, 2);
      UpdateFieldValues();
      return;
   }

   if(id != CHARTEVENT_OBJECT_CLICK || StringFind(sparam, PREFIX_GUI) != 0) return;
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   string key = StringSubstr(sparam, StringLen(PREFIX_GUI));

   if(key == "Btn_Lock")          { Travar(true); Process(); return; }
   if(key == "Btn_LegBuy")        { OpenLeg(true);  Process(); return; }
   if(key == "Btn_LegSell")       { OpenLeg(false); Process(); return; }
   if(key == "Btn_Suggest")       { ExecuteSuggestion(); Process(); return; }

   if(key == "Chk_Group")            g_group_auto  = !g_group_auto;
   else if(key == "Chk_Basket")      g_basket_auto = !g_basket_auto;
   else if(key == "Btn_Lot_Dec")     g_leg_lot     = NormalizeLot(g_leg_lot - VolStep());
   else if(key == "Btn_Lot_Inc")     g_leg_lot     = NormalizeLot(g_leg_lot + VolStep());
   else if(key == "Btn_Group_Dec")   g_group_min   = MathMax(0.0, NormalizeDouble(g_group_min - InpStepCash, 2));
   else if(key == "Btn_Group_Inc")   g_group_min   = NormalizeDouble(g_group_min + InpStepCash, 2);
   else if(key == "Btn_Relock_Dec")  g_leg_relock  = MathMax(0.0, NormalizeDouble(g_leg_relock - InpStepCash, 2));
   else if(key == "Btn_Relock_Inc")  g_leg_relock  = NormalizeDouble(g_leg_relock + InpStepCash, 2);
   else if(key == "Btn_Basket_Dec")  g_basket_min  = MathMax(0.01, NormalizeDouble(g_basket_min - InpStepCash, 2));
   else if(key == "Btn_Basket_Inc")  g_basket_min  = NormalizeDouble(g_basket_min + InpStepCash, 2);
   else return;
   UpdateFieldValues();
}
//+------------------------------------------------------------------+
