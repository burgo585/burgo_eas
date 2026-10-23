//+------------------------------------------------------------------+
//|                                     TRAX_Institutional_EA.mq5     |
//|                        Sistema Quantitativo TRAX - Fábio Valentim|
//|               Modelos IVB (Initial Volume Breakout) & AutoGuardrail|
//|                     Order Flow Institutional Trading Engine       |
//+------------------------------------------------------------------+
#property copyright   "TRAX Quantitative Trading Engine - Fábio Valentim"
#property link        "https://github.com/deepcharts"
#property version     "2.70"
#property description "Expert Advisor Institucional de Order Flow (IVB Modelos 1 e 2)"
#property description "Opera 100% autônomo (entra e sai sozinho) e atua como Sentinela Auto-Guardrail para ordens manuais."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//--- ENUMS DE CONFIGURAÇÃO
enum ENUM_HORARIO_MODE
{
   HORARIO_24H = 0,         // Operar 24 Horas Contínuas (Sem Restrição de Horário)
   HORARIO_JANELA = 1       // Operar Apenas na Janela Horária Personalizada
};

enum ENUM_IB_CALC_MODE
{
   IB_MODE_AUTO = 0,            // Automático (24h = Rolling 20 barras / Janela = Sessão)
   IB_MODE_ROLLING_DYNAMIC = 1, // Faixa Dinâmica das Últimas N Barras M1 (24 Horas)
   IB_MODE_SESSION_FIXED = 2    // Faixa Fixa de Abertura da Sessão
};

enum ENUM_FIM_JANELA_ACTION
{
   FIM_JANELA_SUSPENDER_NOVAS = 0, // Apenas Suspender Novas Entradas (Manter Abertas)
   FIM_JANELA_FECHAR_TUDO = 1      // Encerrar Todas as Posições Abertas no Fim do Horário
};

//+------------------------------------------------------------------+
//| INPUTS DO USUÁRIO (PARÂMETROS F7)                                |
//+------------------------------------------------------------------+

//--- GRUPO 1: GESTÃO GERAL DO ROBÔ & HORÁRIO
input group "=== 1. CONTROLE DO ROBÔ & HORÁRIOS ==="
input bool                    InpBotAtivo              = true;                     // Robô Iniciar Ligado
input ENUM_HORARIO_MODE       InpModoHorario           = HORARIO_24H;              // Modo de Operação (24h ou Janela)
input int                     InpHoraInicio            = 9;                        // Janela: Hora de Início (Corretora)
input int                     InpMinInicio             = 30;                       // Janela: Minuto de Início
input int                     InpHoraFim               = 17;                       // Janela: Hora de Término (Corretora)
input int                     InpMinFim                = 30;                       // Janela: Minuto de Término
input ENUM_FIM_JANELA_ACTION  InpAcaoFimJanela         = FIM_JANELA_SUSPENDER_NOVAS;// Ação ao Final do Horário
input bool                    InpKillSwitchNY_MNQ      = false;                    // Kill-Switch às 15:59:50 NY para Nasdaq

//--- GRUPO 2: MODELOS DE INITIAL BALANCE & ORDER FLOW (FÁBIO VALENTIM)
input group "=== 2. INITIAL BALANCE & ORDER FLOW (FÁBIO VALENTIM) ==="
input ENUM_IB_CALC_MODE       InpModoCalculoIB         = IB_MODE_AUTO;             // Modo de Cálculo da Faixa (IB)
input int                     InpRollingBars           = 20;                       // Barras de Consolidação Prévia (Modo 24h: 15 a 30)
input int                     InpIBDurationMinutes     = 30;                       // Duração do IB da Sessão (Minutos)
input bool                    InpUseModel1_Volume      = true;                     // Modelo 1: Rompimento com Volume Profile & PoC
input bool                    InpUseModel2_Delta       = true;                     // Modelo 2: Rompimento com Spike de Delta Agressor
input double                  InpVolumeMultiplier      = 1.00;                     // Modelo 1: Fator de Volume vs Média (1.0 = igual à média)
input double                  InpDeltaThresholdMult    = 1.00;                     // Modelo 2: Fator de Spike de Delta vs Média (1.0x)

//--- GRUPO 3: GESTÃO DE RISCO, LOTES E SAÍDAS AUTÔNOMAS
input group "=== 3. GESTÃO DE LOTE, ALVOS E SAÍDAS (ENTRA E SAI SOZINHO) ==="
input double                  InpLotSize               = 0.10;                     // Tamanho do Lote Padrão
input double                  InpRiskRewardRatio       = 2.0;                      // Relação Risco:Retorno (ex: 2.0 = 2:1)
input double                  InpATRMulitplier         = 1.5;                      // Multiplicador ATR para Stop Loss
input int                     InpATRPeriod             = 14;                       // Período do ATR
input bool                    InpUseTrailingStop       = true;                     // Trailing Stop Dinâmico (Protege Lucro)
input bool                    InpUseBreakEven          = true;                     // Break-Even (Move Stop para 0x0 ao Atingir 1:1)
input int                     InpMagicNumber           = 100100;                   // Magic Number das Ordens do Robô

//--- GRUPO 4: SENTINELA AUTO-GUARDRAIL PARA ORDENS MANUAIS
input group "=== 4. SENTINELA AUTO-GUARDRAIL (ORDENS MANUAIS) ==="
input bool                    InpAutoGuardrailManual   = true;                     // Blindar Ordens Manuais com SL e TP Automáticos
input double                  InpManualRiskReward      = 2.0;                      // Relação R:R para Ordens Manuais (Take Profit)
input double                  InpManualATRMultiplier   = 1.5;                      // Multiplicador ATR para Stop Loss Manual
input bool                    InpTrailManualOrders     = true;                     // Aplicar Trailing Stop Também em Ordens Manuais

//--- GRUPO 5: VISUAL & HUD NO MT5
input group "=== 5. INTERFACE GRÁFICA & LINHAS NO MT5 ==="
input bool                    InpMostrarLinhasNoGrafico= true;                     // Desenhar Linhas IB High/Low/PoC no Gráfico
input color                   InpCorIBHigh             = clrDodgerBlue;            // Cor da Linha IB High
input color                   InpCorIBLow              = clrOrangeRed;             // Cor da Linha IB Low
input color                   InpCorIBPoC              = clrGold;                  // Cor da Linha IB PoC

//+------------------------------------------------------------------+
//| VARIÁVEIS GLOBAIS DE NEGOCIAÇÃO E ESTADO                        |
//+------------------------------------------------------------------+
CTrade         m_trade;
CSymbolInfo    m_symbol;
CPositionInfo  m_position;
CAccountInfo   m_account;

bool           g_robo_ligado           = true;
bool           g_guardrail_ativo       = true;
int            g_atr_handle            = INVALID_HANDLE;
datetime       g_last_bar_time         = 0;
string         g_prefixo_gui           = "TRAX_HUD_";
bool           g_is_tester             = false;

// Níveis de Faixa Institucional
double         g_ib_high               = 0.0;
double         g_ib_low                = 0.0;
double         g_ib_poc                = 0.0;
bool           g_ib_valido             = false;
string         g_diagnostico_status    = "Iniciando sistema...";
string         g_diagnostico_motivo    = "Aguardando primeiro tick...";
double         g_ultimo_delta          = 0.0;
double         g_limiar_delta          = 0.0;
string         g_ultimo_sinal          = "NENHUM";

//+------------------------------------------------------------------+
//| Configuração Automática do Modo de Preenchimento da Corretora   |
//+------------------------------------------------------------------+
void ConfigurarFillingTrade()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) != 0)
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((filling & SYMBOL_FILLING_FOK) != 0)
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      m_trade.SetTypeFilling(ORDER_FILLING_RETURN);
}

//+------------------------------------------------------------------+
//| Normalização Segura de Volume de Lote                           |
//+------------------------------------------------------------------+
double ObterLoteNormalizado(double lote_desejado)
{
   double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(step_lot <= 0) step_lot = 0.01;
   if(min_lot <= 0)  min_lot = 0.01;
   if(max_lot <= 0)  max_lot = 100.0;

   double ajustado = MathMax(lote_desejado, min_lot);
   ajustado = MathMin(ajustado, max_lot);
   ajustado = MathFloor(ajustado / step_lot) * step_lot;

   return NormalizeDouble(ajustado, 2);
}

//+------------------------------------------------------------------+
//| Inicialização do Expert Advisor                                 |
//+------------------------------------------------------------------+
int OnInit()
{
   g_is_tester = (bool)MQLInfoInteger(MQL_TESTER);

   if(!m_symbol.Name(_Symbol))
   {
      Print("❌ [TRAX EA] Erro ao carregar informações do ativo: ", _Symbol);
      return(INIT_FAILED);
   }
   m_symbol.RefreshRates();

   m_trade.SetExpertMagicNumber(InpMagicNumber);
   m_trade.SetMarginMode();
   ConfigurarFillingTrade();

   g_robo_ligado     = InpBotAtivo;
   g_guardrail_ativo = InpAutoGuardrailManual;

   // Handle do indicador ATR
   g_atr_handle = iATR(_Symbol, PERIOD_M1, InpATRPeriod);
   if(g_atr_handle == INVALID_HANDLE)
   {
      Print("❌ [TRAX EA] Falha ao criar handle do ATR.");
      return(INIT_FAILED);
   }

   // Cria o Painel HUD apenas se estiver no gráfico ao vivo
   if(!g_is_tester || MQLInfoInteger(MQL_VISUAL_MODE))
   {
      CriarPainelHUD();
   }

   // Calcula imediatamente a primeira leitura da faixa
   AtualizarFaixaInstitucional();
   AtualizarDiagnostico();

   if(!g_is_tester || MQLInfoInteger(MQL_VISUAL_MODE))
   {
      AtualizarTextosHUD();
   }

   PrintFormat("🚀 [TRAX INSTITUTIONAL EA v2.70] Inicializado em %s | Magic: %d | Modo Horário: %s | Lote: %.2f", 
               _Symbol, InpMagicNumber, (InpModoHorario == HORARIO_24H) ? "24 HORAS" : "JANELA", ObterLoteNormalizado(InpLotSize));

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Desinicialização do Expert Advisor                              |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(!g_is_tester || MQLInfoInteger(MQL_VISUAL_MODE))
   {
      ObjectsDeleteAll(0, g_prefixo_gui);
      ChartRedraw();
   }

   if(g_atr_handle != INVALID_HANDLE)
      IndicatorRelease(g_atr_handle);

   Print("🛑 [TRAX EA] Desinicializado com sucesso.");
}

//+------------------------------------------------------------------+
//| Evento OnTick Principal                                          |
//+------------------------------------------------------------------+
void OnTick()
{
   m_symbol.RefreshRates();

   // 1. Sentinela Auto-Guardrail: Blinda ordens manuais instantaneamente
   if(g_guardrail_ativo && !g_is_tester)
      ExecutarSentinelaAutoGuardrail();

   // 2. Trailing Stop e Break-Even contínuo (Garante lucros e move stop para 0x0)
   ExecutarTrailingStopEBreakEven();

   // 3. Kill-Switch Especial para Nasdaq às 15:59:50 NY (se ativo e em Nasdaq)
   if(InpKillSwitchNY_MNQ && EhAtivoNasdaq())
      VerificarKillSwitchNY();

   // 4. Fechamento compulsório no término de horário se configurado
   if(InpModoHorario == HORARIO_JANELA && InpAcaoFimJanela == FIM_JANELA_FECHAR_TUDO && !DentroDoHorarioOperacional())
   {
      FecharTodasPosicoesRobo("Término da Janela Operacional");
   }

   // 5. Execução do robô em cada nova barra M1
   datetime bar_time = iTime(_Symbol, PERIOD_M1, 0);
   if(bar_time != g_last_bar_time)
   {
      g_last_bar_time = bar_time;
      AtualizarFaixaInstitucional();

      if(g_robo_ligado && DentroDoHorarioOperacional())
      {
         VerificarEExecutarGatilhosAutonomos();
      }
   }

   // 6. Atualização do diagnóstico e HUD (apenas em visual/ao vivo)
   if(!g_is_tester || MQLInfoInteger(MQL_VISUAL_MODE))
   {
      AtualizarDiagnostico();
      AtualizarTextosHUD();
   }
}

//+------------------------------------------------------------------+
//| Sentinela Auto-Guardrail: Blinda Ordens Manuais com SL e TP       |
//+------------------------------------------------------------------+
void ExecutarSentinelaAutoGuardrail()
{
   int total_pos = PositionsTotal();
   for(int i = total_pos - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() != _Symbol)
            continue;

         // Se a ordem for manual ou estiver desprotegida (sem Stop Loss ou sem Take Profit)
         if(m_position.StopLoss() == 0.0 || m_position.TakeProfit() == 0.0)
         {
            double atr_val = ObterValorATR();
            double spread_pts = (double)m_symbol.Spread() * _Point;
            double stop_level = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

            double dist_sl = MathMax(atr_val * InpManualATRMultiplier, spread_pts * 2.5);
            dist_sl = MathMax(dist_sl, stop_level + spread_pts * 2.0);
            dist_sl = MathMax(dist_sl, 50 * _Point);

            double novo_sl = m_position.StopLoss();
            double novo_tp = m_position.TakeProfit();
            double preco_abertura = m_position.PriceOpen();

            if(m_position.PositionType() == POSITION_TYPE_BUY)
            {
               if(novo_sl <= 0.0)
                  novo_sl = NormalizeDouble(preco_abertura - dist_sl, _Digits);
               if(novo_tp <= 0.0)
               {
                  double risco = preco_abertura - novo_sl;
                  novo_tp = NormalizeDouble(preco_abertura + (risco * InpManualRiskReward), _Digits);
               }
            }
            else if(m_position.PositionType() == POSITION_TYPE_SELL)
            {
               if(novo_sl <= 0.0)
                  novo_sl = NormalizeDouble(preco_abertura + dist_sl, _Digits);
               if(novo_tp <= 0.0)
               {
                  double risco = novo_sl - preco_abertura;
                  novo_tp = NormalizeDouble(preco_abertura - (risco * InpManualRiskReward), _Digits);
               }
            }

            if(novo_sl > 0.0 && novo_tp > 0.0)
            {
               ConfigurarFillingTrade();
               if(m_trade.PositionModify(m_position.Ticket(), novo_sl, novo_tp))
               {
                  PrintFormat("🛡 [Auto-Guardrail] Ticket manual #%d blindado! SL=%.*f | TP=%.*f (R:R %.1f:1)", 
                              m_position.Ticket(), _Digits, novo_sl, _Digits, novo_tp, InpManualRiskReward);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trailing Stop e Break-Even Dinâmico                             |
//+------------------------------------------------------------------+
void ExecutarTrailingStopEBreakEven()
{
   if(!InpUseTrailingStop && !InpUseBreakEven)
      return;

   double atr_val = ObterValorATR();
   double dist_gatilho = atr_val * InpATRMulitplier;
   double dist_trail   = atr_val * InpATRMulitplier * 0.75;
   double stop_level   = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   int total_pos = PositionsTotal();
   for(int i = total_pos - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() != _Symbol)
            continue;

         if(m_position.Magic() == 0 && !InpTrailManualOrders)
            continue;

         ulong ticket = m_position.Ticket();
         double preco_open = m_position.PriceOpen();
         double sl_atual = m_position.StopLoss();
         double tp_atual = m_position.TakeProfit();

         if(m_position.PositionType() == POSITION_TYPE_BUY)
         {
            double ganho = m_symbol.Bid() - preco_open;

            // 1. Break-Even: Se o preço andou 1x ATR a favor, move o Stop para o preço de entrada + spread
            if(InpUseBreakEven && ganho >= dist_gatilho && (sl_atual < preco_open))
            {
               double be_sl = NormalizeDouble(preco_open + ((double)m_symbol.Spread() * _Point), _Digits);
               if((m_symbol.Bid() - be_sl) > stop_level)
               {
                  ConfigurarFillingTrade();
                  m_trade.PositionModify(ticket, be_sl, tp_atual);
                  PrintFormat("🎯 [Break-Even] Ticket #%d movido para 0x0 garantido!", ticket);
                  continue;
               }
            }

            // 2. Trailing Stop
            if(InpUseTrailingStop && ganho >= dist_gatilho)
            {
               double novo_sl = NormalizeDouble(m_symbol.Bid() - dist_trail, _Digits);
               if(novo_sl > sl_atual && novo_sl > preco_open && (m_symbol.Bid() - novo_sl) > stop_level)
               {
                  ConfigurarFillingTrade();
                  m_trade.PositionModify(ticket, novo_sl, tp_atual);
               }
            }
         }
         else if(m_position.PositionType() == POSITION_TYPE_SELL)
         {
            double ganho = preco_open - m_symbol.Ask();

            // 1. Break-Even
            if(InpUseBreakEven && ganho >= dist_gatilho && (sl_atual == 0.0 || sl_atual > preco_open))
            {
               double be_sl = NormalizeDouble(preco_open - ((double)m_symbol.Spread() * _Point), _Digits);
               if((be_sl - m_symbol.Ask()) > stop_level)
               {
                  ConfigurarFillingTrade();
                  m_trade.PositionModify(ticket, be_sl, tp_atual);
                  PrintFormat("🎯 [Break-Even] Ticket #%d movido para 0x0 garantido!", ticket);
                  continue;
               }
            }

            // 2. Trailing Stop
            if(InpUseTrailingStop && ganho >= dist_gatilho)
            {
               double novo_sl = NormalizeDouble(m_symbol.Ask() + dist_trail, _Digits);
               if((sl_atual == 0.0 || novo_sl < sl_atual) && novo_sl < preco_open && (novo_sl - m_symbol.Ask()) > stop_level)
               {
                  ConfigurarFillingTrade();
                  m_trade.PositionModify(ticket, novo_sl, tp_atual);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Cálculo Dinâmico e Institucional da Faixa (IB / Rolling Range)   |
//+------------------------------------------------------------------+
void AtualizarFaixaInstitucional()
{
   ENUM_IB_CALC_MODE modo = InpModoCalculoIB;
   if(modo == IB_MODE_AUTO)
   {
      modo = (InpModoHorario == HORARIO_24H) ? IB_MODE_ROLLING_DYNAMIC : IB_MODE_SESSION_FIXED;
   }

   if(modo == IB_MODE_ROLLING_DYNAMIC)
   {
      // MODO 24 HORAS: Calcula a consolidação prévia das últimas N barras
      // Copia das barras 2 até N+1 (excluindo a barra 1 que tentará romper)
      int qtd = MathMax(InpRollingBars, 10);
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copiado = CopyRates(_Symbol, PERIOD_M1, 2, qtd, rates);
      if(copiado < qtd)
      {
         g_ib_valido = false;
         return;
      }

      double max_h = rates[0].high;
      double min_l = rates[0].low;
      double soma_ponderada = 0.0;
      double soma_vol = 0.0;

      for(int i = 0; i < copiado; i++)
      {
         if(rates[i].high > max_h) max_h = rates[i].high;
         if(rates[i].low < min_l)  min_l = rates[i].low;

         double preco_med = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
         double vol = MathMax((double)rates[i].tick_volume, 1.0);
         soma_ponderada += (preco_med * vol);
         soma_vol += vol;
      }

      g_ib_high   = max_h;
      g_ib_low    = min_l;
      g_ib_poc    = (soma_vol > 0) ? (soma_ponderada / soma_vol) : ((max_h + min_l) / 2.0);
      g_ib_valido = (g_ib_high > g_ib_low);
   }
   else
   {
      // MODO SESSÃO FIXA: Varre o histórico do dia atual
      datetime t_agora = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(t_agora, dt);

      int min_inicio = InpHoraInicio * 60 + InpMinInicio;
      int min_fim    = min_inicio + InpIBDurationMinutes;
      int min_atual  = dt.hour * 60 + dt.min;

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copiado = CopyRates(_Symbol, PERIOD_M1, 0, 500, rates);
      if(copiado < 30) return;

      double max_h = 0.0;
      double min_l = 9999999.0;
      int barras_encontradas = 0;
      double soma_ponderada = 0.0;
      double soma_vol = 0.0;

      for(int i = 0; i < copiado; i++)
      {
         MqlDateTime r_dt;
         TimeToStruct(rates[i].time, r_dt);
         if(r_dt.day != dt.day) continue;

         int r_min = r_dt.hour * 60 + r_dt.min;
         if(r_min >= min_inicio && r_min < min_fim)
         {
            if(rates[i].high > max_h) max_h = rates[i].high;
            if(rates[i].low < min_l)  min_l = rates[i].low;

            double preco_med = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
            double vol = MathMax((double)rates[i].tick_volume, 1.0);
            soma_ponderada += (preco_med * vol);
            soma_vol += vol;
            barras_encontradas++;
         }
      }

      if(barras_encontradas >= 5)
      {
         g_ib_high   = max_h;
         g_ib_low    = min_l;
         g_ib_poc    = (soma_vol > 0) ? (soma_ponderada / soma_vol) : ((max_h + min_l) / 2.0);
         g_ib_valido = (min_atual >= min_fim);
      }
      else
      {
         // Fallback inteligente para garantir operação imediata
         g_ib_valido = false;
      }
   }

   if(InpMostrarLinhasNoGrafico && (!g_is_tester || MQLInfoInteger(MQL_VISUAL_MODE)))
   {
      DesenharLinhasIB();
   }
}

//+------------------------------------------------------------------+
//| Verificação dos Gatilhos Autônomos (Entra e Sai Sozinho)         |
//+------------------------------------------------------------------+
void VerificarEExecutarGatilhosAutonomos()
{
   if(!g_robo_ligado)
      return;

   // Evita sobre-posicionar: Máximo 1 trade simultâneo do robô no ativo
   if(PossuiPosicaoAbertaRobo())
      return;

   if(!g_ib_valido || g_ib_high <= 0.0 || g_ib_low <= 0.0)
      return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   // Copia a barra 1 (recém-fechada) e as 20 anteriores
   if(CopyRates(_Symbol, PERIOD_M1, 1, 22, rates) < 20)
      return;

   MqlRates candle_romp = rates[0];     // Barra anterior recém-fechada (shift 1)
   MqlRates candle_ant  = rates[1];     // Barra shift 2

   // Volume médio das últimas 15 barras
   double soma_vol = 0;
   for(int k = 1; k <= 15; k++)
      soma_vol += (double)rates[k].tick_volume;
   double media_vol = MathMax(soma_vol / 15.0, 1.0);

   // Decomposição de Fluxo de Agressão e Delta (Estimador de Order Flow)
   double amplitude = candle_romp.high - candle_romp.low;
   if(amplitude <= 0) amplitude = _Point;
   double corpo = candle_romp.close - candle_romp.open;
   double prop_alta = MathMin(MathMax((corpo / amplitude) * 0.5 + 0.5, 0.05), 0.95);
   double buy_vol   = (double)candle_romp.tick_volume * prop_alta;
   double sell_vol  = (double)candle_romp.tick_volume - buy_vol;
   double delta     = buy_vol - sell_vol;
   double poc_barra = (candle_romp.open + candle_romp.high + candle_romp.low + 2.0 * candle_romp.close) / 5.0;

   g_ultimo_delta = delta;
   g_limiar_delta = media_vol * 0.15 * InpDeltaThresholdMult;

   // ================================================================
   // GATILHO COMPRADOR (BUY) - MODELOS 1 E 2
   // ================================================================
   // Rompimento do topo da consolidação prévia
   bool rompimento_alta = (candle_romp.close > g_ib_high && candle_ant.close <= (g_ib_high + 2.0 * _Point));
   bool m1_buy = InpUseModel1_Volume && rompimento_alta && ((double)candle_romp.tick_volume >= media_vol * InpVolumeMultiplier) && (candle_romp.close >= poc_barra);
   bool m2_buy = InpUseModel2_Delta  && rompimento_alta && (delta > 0) && (MathAbs(delta) >= g_limiar_delta);

   if(m1_buy || m2_buy)
   {
      double atr_val = ObterValorATR();
      double spread_pts = (double)m_symbol.Spread() * _Point;
      double stop_level = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

      double dist_sl = MathMax(atr_val * InpATRMulitplier, spread_pts * 2.5);
      dist_sl = MathMax(dist_sl, stop_level + spread_pts * 2.0);
      dist_sl = MathMax(dist_sl, 50 * _Point);

      double sl = NormalizeDouble(m_symbol.Ask() - dist_sl, _Digits);
      double tp = NormalizeDouble(m_symbol.Ask() + (dist_sl * InpRiskRewardRatio), _Digits);

      string modelo = m2_buy ? "IVB Modelo 2 (Delta Flow)" : "IVB Modelo 1 (Volume Profile)";
      g_ultimo_sinal = "COMPRA (" + modelo + ")";

      ConfigurarFillingTrade();
      double lote = ObterLoteNormalizado(InpLotSize);

      if(m_trade.Buy(lote, _Symbol, m_symbol.Ask(), sl, tp, "TRAX: " + modelo))
      {
         if(!g_is_tester || MQLInfoInteger(MQL_VISUAL_MODE))
         {
            DesenharSetaSinal("BUY", candle_romp.time, candle_romp.low);
         }
         PrintFormat("🚀 [TRAX AUTO BUY] %s executado em %s @ %.5f! Lote: %.2f | SL: %.5f | TP: %.5f", 
                     modelo, _Symbol, m_symbol.Ask(), lote, sl, tp);
      }
      else
      {
         PrintFormat("❌ [ERRO COMPRA] Falha ao enviar ordem Buy: Retcode %d (%s)", 
                     m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
      }
      return;
   }

   // ================================================================
   // GATILHO VENDEDOR (SELL) - MODELOS 1 E 2
   // ================================================================
   // Rompimento do fundo da consolidação prévia
   bool rompimento_baixa = (candle_romp.close < g_ib_low && candle_ant.close >= (g_ib_low - 2.0 * _Point));
   bool m1_sell = InpUseModel1_Volume && rompimento_baixa && ((double)candle_romp.tick_volume >= media_vol * InpVolumeMultiplier) && (candle_romp.close <= poc_barra);
   bool m2_sell = InpUseModel2_Delta  && rompimento_baixa && (delta < 0) && (MathAbs(delta) >= g_limiar_delta);

   if(m1_sell || m2_sell)
   {
      double atr_val = ObterValorATR();
      double spread_pts = (double)m_symbol.Spread() * _Point;
      double stop_level = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

      double dist_sl = MathMax(atr_val * InpATRMulitplier, spread_pts * 2.5);
      dist_sl = MathMax(dist_sl, stop_level + spread_pts * 2.0);
      dist_sl = MathMax(dist_sl, 50 * _Point);

      double sl = NormalizeDouble(m_symbol.Bid() + dist_sl, _Digits);
      double tp = NormalizeDouble(m_symbol.Bid() - (dist_sl * InpRiskRewardRatio), _Digits);

      string modelo = m2_sell ? "IVB Modelo 2 (Delta Flow)" : "IVB Modelo 1 (Volume Profile)";
      g_ultimo_sinal = "VENDA (" + modelo + ")";

      ConfigurarFillingTrade();
      double lote = ObterLoteNormalizado(InpLotSize);

      if(m_trade.Sell(lote, _Symbol, m_symbol.Bid(), sl, tp, "TRAX: " + modelo))
      {
         if(!g_is_tester || MQLInfoInteger(MQL_VISUAL_MODE))
         {
            DesenharSetaSinal("SELL", candle_romp.time, candle_romp.high);
         }
         PrintFormat("🔻 [TRAX AUTO SELL] %s executado em %s @ %.5f! Lote: %.2f | SL: %.5f | TP: %.5f", 
                     modelo, _Symbol, m_symbol.Bid(), lote, sl, tp);
      }
      else
      {
         PrintFormat("❌ [ERRO VENDA] Falha ao enviar ordem Sell: Retcode %d (%s)", 
                     m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| Atualização do Diagnóstico Operacional em Tempo Real             |
//+------------------------------------------------------------------+
void AtualizarDiagnostico()
{
   if(!g_robo_ligado)
   {
      g_diagnostico_status = "⏸ ROBÔ DESLIGADO (PAUSADO)";
      g_diagnostico_motivo = "Clique no botão 'ROBÔ: ON' para ativar a automação.";
      return;
   }

   if(!DentroDoHorarioOperacional())
   {
      g_diagnostico_status = "⛔ FORA DO HORÁRIO PERMITIDO";
      g_diagnostico_motivo = StringFormat("Janela: %02d:%02d às %02d:%02d (Corretora).", InpHoraInicio, InpMinInicio, InpHoraFim, InpMinFim);
      return;
   }

   if(PossuiPosicaoAbertaRobo())
   {
      g_diagnostico_status = "🛡 POSIÇÃO ABERTA EM ANDAMENTO";
      g_diagnostico_motivo = "Gerenciando risco com Trailing Stop e Break-Even ativos.";
      return;
   }

   if(!g_ib_valido)
   {
      g_diagnostico_status = "🟡 CALCULANDO FAIXA INSTITUCIONAL";
      g_diagnostico_motivo = "Aguardando formação das barras de referência da faixa.";
      return;
   }

   double preco_bid = m_symbol.Bid();
   if(preco_bid > g_ib_high)
   {
      g_diagnostico_status = "⚡ PREÇO ACIMA DA FAIXA (HIGH)";
      g_diagnostico_motivo = StringFormat("Aguardando confirmação de Delta (> %.1f) ou Volume.", g_limiar_delta);
   }
   else if(preco_bid < g_ib_low)
   {
      g_diagnostico_status = "⚡ PREÇO ABAIXO DA FAIXA (LOW)";
      g_diagnostico_motivo = StringFormat("Aguardando confirmação de Delta (< -%.1f) ou Volume.", g_limiar_delta);
   }
   else
   {
      g_diagnostico_status = "🟢 MONITORANDO FAIXA (DENTRO DO RANGE)";
      g_diagnostico_motivo = StringFormat("Aguardando romper High (%.2f) ou Low (%.2f).", g_ib_high, g_ib_low);
   }
}

//+------------------------------------------------------------------+
//| Kill-Switch Especial para Nasdaq às 15:59:50 NY                  |
//+------------------------------------------------------------------+
void VerificarKillSwitchNY()
{
   datetime t_agora = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(t_agora, dt);

   // Converte hora corretora para hora NY estimada (-7 horas)
   int hora_ny = (dt.hour - 7 + 24) % 24;

   if(hora_ny == 15 && dt.min == 59 && dt.sec >= 50)
   {
      FecharTodasPosicoesRobo("Kill-Switch NY 15:59:50 (MOC Imbalance Protection)");
   }
}

void FecharTodasPosicoesRobo(string motivo)
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() == _Symbol && (m_position.Magic() == InpMagicNumber || m_position.Magic() == 0))
         {
            ConfigurarFillingTrade();
            m_trade.PositionClose(m_position.Ticket());
            PrintFormat("🚨 [ENCERRAMENTO COMPULSÓRIO] Ticket #%d encerrado! Motivo: %s", m_position.Ticket(), motivo);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Funções Utilitárias                                              |
//+------------------------------------------------------------------+
bool DentroDoHorarioOperacional()
{
   if(InpModoHorario == HORARIO_24H)
      return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int minutos_agora  = dt.hour * 60 + dt.min;
   int minutos_inicio = InpHoraInicio * 60 + InpMinInicio;
   int minutos_fim    = InpHoraFim * 60 + InpMinFim;

   if(minutos_inicio <= minutos_fim)
      return (minutos_agora >= minutos_inicio && minutos_agora <= minutos_fim);
   else
      return (minutos_agora >= minutos_inicio || minutos_agora <= minutos_fim);
}

bool PossuiPosicaoAbertaRobo()
{
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() == _Symbol && m_position.Magic() == InpMagicNumber)
            return true;
      }
   }
   return false;
}

double ObterLucroPosicoesAtivo()
{
   double lucro = 0.0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() == _Symbol)
            lucro += m_position.Profit() + m_position.Swap();
      }
   }
   return lucro;
}

double ObterValorATR()
{
   double atr_buf[];
   ArraySetAsSeries(atr_buf, true);
   if(CopyBuffer(g_atr_handle, 0, 0, 2, atr_buf) > 0)
      return atr_buf[0];
   return(1.0);
}

bool EhAtivoNasdaq()
{
   string sym = _Symbol;
   StringToUpper(sym);
   return (StringFind(sym, "NAS") >= 0 || StringFind(sym, "MNQ") >= 0 || StringFind(sym, "NQ") >= 0 || StringFind(sym, "USTEC") >= 0 || StringFind(sym, "US100") >= 0);
}

//+------------------------------------------------------------------+
//| Interface Visual: Criação do Painel HUD no Gráfico              |
//+------------------------------------------------------------------+
void CriarPainelHUD()
{
   int x = 20;
   int y = 30;
   int largura = 340;
   int altura  = 300;

   // Caixa de Fundo Principal
   string bg = g_prefixo_gui + "BG";
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, largura);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, altura);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'16,20,26');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_COLOR, C'41,50,60');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);

   // Cabeçalho
   CriarLabel("TITULO",   "⚡ TRAX INSTITUTIONAL ENGINE v2.70", x + 15, y + 10, clrAqua, 10, true);
   CriarLabel("SUBTIT",   StringFormat("%s | Saldo: $%.2f | Spread: %d pts", _Symbol, m_account.Balance(), m_symbol.Spread()), x + 15, y + 28, clrSilver, 8, false);

   // Botão LIGAR/DESLIGAR ROBÔ
   string btn_robo = g_prefixo_gui + "BTN_ROBO";
   ObjectCreate(0, btn_robo, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, btn_robo, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, btn_robo, OBJPROP_XDISTANCE, x + 15);
   ObjectSetInteger(0, btn_robo, OBJPROP_YDISTANCE, y + 48);
   ObjectSetInteger(0, btn_robo, OBJPROP_XSIZE, 150);
   ObjectSetInteger(0, btn_robo, OBJPROP_YSIZE, 30);
   ObjectSetInteger(0, btn_robo, OBJPROP_BGCOLOR, g_robo_ligado ? C'34,139,34' : C'178,34,34');
   ObjectSetInteger(0, btn_robo, OBJPROP_COLOR, clrWhite);
   ObjectSetString(0, btn_robo, OBJPROP_TEXT, g_robo_ligado ? "🟢 ROBÔ: LIGADO" : "🔴 ROBÔ: DESLIGADO");
   ObjectSetInteger(0, btn_robo, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, btn_robo, OBJPROP_FONT, "Arial Bold");

   // Botão AUTO-GUARDRAIL
   string btn_guard = g_prefixo_gui + "BTN_GUARD";
   ObjectCreate(0, btn_guard, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, btn_guard, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, btn_guard, OBJPROP_XDISTANCE, x + 175);
   ObjectSetInteger(0, btn_guard, OBJPROP_YDISTANCE, y + 48);
   ObjectSetInteger(0, btn_guard, OBJPROP_XSIZE, 150);
   ObjectSetInteger(0, btn_guard, OBJPROP_YSIZE, 30);
   ObjectSetInteger(0, btn_guard, OBJPROP_BGCOLOR, g_guardrail_ativo ? C'30,70,160' : C'70,75,85');
   ObjectSetInteger(0, btn_guard, OBJPROP_COLOR, clrWhite);
   ObjectSetString(0, btn_guard, OBJPROP_TEXT, g_guardrail_ativo ? "🛡 GUARDRAIL: ON" : "⚪ GUARDRAIL: OFF");
   ObjectSetInteger(0, btn_guard, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, btn_guard, OBJPROP_FONT, "Arial Bold");

   // Seção de Status e Diagnóstico em Tempo Real
   CriarLabel("LBL_STATUS_TIT",  "RAIO-X DE DECISÃO DA MÁQUINA:", x + 15, y + 88, clrGold, 8, true);
   CriarLabel("INFO_STATUS",     "Status: Iniciando...",            x + 15, y + 104, clrLime, 8, true);
   CriarLabel("INFO_MOTIVO",     "Motivo: Carregando...",           x + 15, y + 122, clrSilver, 7, false);

   // Métricas de Faixa e Order Flow
   CriarLabel("LBL_METRICAS_TIT","MÉTRICAS INSTITUCIONAIS (M1):",   x + 15, y + 144, clrDodgerBlue, 8, true);
   CriarLabel("INFO_FAIXA",      "Faixa: High: 0.00 | Low: 0.00",   x + 15, y + 160, clrWhite, 8, false);
   CriarLabel("INFO_POC",        "PoC Central: 0.00 | Range: 0.00", x + 15, y + 176, clrGold, 8, false);
   CriarLabel("INFO_DELTA",      "Delta Flow: 0.00 | Volat: 0.00",  x + 15, y + 192, clrDeepSkyBlue, 8, false);
   CriarLabel("INFO_HORARIO",    "Horário: 24h Liberado",           x + 15, y + 208, clrLime, 8, false);
   CriarLabel("INFO_SINAL",      "Último Sinal: Nenhum",            x + 15, y + 224, clrKhaki, 8, false);

   // Lucro Aberto no Ativo
   CriarLabel("INFO_LUCRO",      "PnL Aberto no Ativo: $0.00 USD",  x + 15, y + 242, clrLightGreen, 8, true);

   // Botão ZERAR TUDO (CLOSE ALL)
   string btn_close = g_prefixo_gui + "BTN_CLOSE";
   ObjectCreate(0, btn_close, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, btn_close, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, btn_close, OBJPROP_XDISTANCE, x + 15);
   ObjectSetInteger(0, btn_close, OBJPROP_YDISTANCE, y + 262);
   ObjectSetInteger(0, btn_close, OBJPROP_XSIZE, 310);
   ObjectSetInteger(0, btn_close, OBJPROP_YSIZE, 26);
   ObjectSetInteger(0, btn_close, OBJPROP_BGCOLOR, C'200,30,40');
   ObjectSetInteger(0, btn_close, OBJPROP_COLOR, clrWhite);
   ObjectSetString(0, btn_close, OBJPROP_TEXT, "🚨 ZERAR TODAS AS POSIÇÕES (CLOSE ALL)");
   ObjectSetInteger(0, btn_close, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, btn_close, OBJPROP_FONT, "Arial Bold");
}

//+------------------------------------------------------------------+
//| Atualização dos Textos e Status no HUD                           |
//+------------------------------------------------------------------+
void AtualizarTextosHUD()
{
   double range = (g_ib_high > 0 && g_ib_low > 0) ? (g_ib_high - g_ib_low) : 0.0;
   double atr_val = ObterValorATR();
   double lucro_ativo = ObterLucroPosicoesAtivo();

   AtualizarLabel("SUBTIT", StringFormat("%s | Saldo: $%.2f | Spread: %d pts", _Symbol, m_account.Balance(), m_symbol.Spread()));

   AtualizarLabel("INFO_STATUS", g_diagnostico_status);
   AtualizarLabel("INFO_MOTIVO", g_diagnostico_motivo);

   AtualizarLabel("INFO_FAIXA", StringFormat("Faixa: High: %.*f | Low: %.*f", _Digits, g_ib_high, _Digits, g_ib_low));
   AtualizarLabel("INFO_POC",   StringFormat("PoC: %.*f | Range: %.2f pts", _Digits, g_ib_poc, range));
   AtualizarLabel("INFO_DELTA", StringFormat("Delta M1: %+.1f (Limiar: %.1f) | ATR: %.2f", g_ultimo_delta, g_limiar_delta, atr_val));

   string txt_horario = (InpModoHorario == HORARIO_24H) ? "Horário: 24h Liberado" : StringFormat("Janela: %02d:%02d - %02d:%02d (%s)", InpHoraInicio, InpMinInicio, InpHoraFim, InpMinFim, DentroDoHorarioOperacional() ? "ABERTA" : "FECHADA");
   AtualizarLabel("INFO_HORARIO", txt_horario);

   AtualizarLabel("INFO_SINAL", StringFormat("Último Sinal: %s", g_ultimo_sinal));

   color cor_pnl = (lucro_ativo > 0) ? clrLime : ((lucro_ativo < 0) ? clrTomato : clrWhite);
   AtualizarLabel("INFO_LUCRO", StringFormat("PnL Aberto no Ativo: %+$%.2f USD", lucro_ativo));
   ObjectSetInteger(0, g_prefixo_gui + "INFO_LUCRO", OBJPROP_COLOR, cor_pnl);
}

//+------------------------------------------------------------------+
//| Evento de Clique nos Botões do Gráfico                          |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      // Botão Robô LIGAR/DESLIGAR
      if(sparam == g_prefixo_gui + "BTN_ROBO")
      {
         g_robo_ligado = !g_robo_ligado;
         ObjectSetInteger(0, sparam, OBJPROP_BGCOLOR, g_robo_ligado ? C'34,139,34' : C'178,34,34');
         ObjectSetString(0, sparam, OBJPROP_TEXT, g_robo_ligado ? "🟢 ROBÔ: LIGADO" : "🔴 ROBÔ: DESLIGADO");
         Print("⚡ [TRAX] Robô alternado para: ", g_robo_ligado ? "LIGADO (OPERANDO)" : "DESLIGADO (PAUSADO)");
         AtualizarDiagnostico();
         AtualizarTextosHUD();
         ChartRedraw();
      }
      // Botão Auto-Guardrail
      else if(sparam == g_prefixo_gui + "BTN_GUARD")
      {
         g_guardrail_ativo = !g_guardrail_ativo;
         ObjectSetInteger(0, sparam, OBJPROP_BGCOLOR, g_guardrail_ativo ? C'30,70,160' : C'70,75,85');
         ObjectSetString(0, sparam, OBJPROP_TEXT, g_guardrail_ativo ? "🛡 GUARDRAIL: ON" : "⚪ GUARDRAIL: OFF");
         Print("🛡 [TRAX] Auto-Guardrail alternado para: ", g_guardrail_ativo ? "LIGADO" : "DESLIGADO");
         ChartRedraw();
      }
      // Botão Zerar Posições (Close All)
      else if(sparam == g_prefixo_gui + "BTN_CLOSE")
      {
         int total = PositionsTotal();
         int fechadas = 0;
         for(int i = total - 1; i >= 0; i--)
         {
            if(m_position.SelectByIndex(i))
            {
               if(m_position.Symbol() == _Symbol)
               {
                  ConfigurarFillingTrade();
                  if(m_trade.PositionClose(m_position.Ticket()))
                     fechadas++;
               }
            }
         }
         PrintFormat("🚨 [TRAX] Fechamento total executado pelo operador! (%d ordens encerradas)", fechadas);
         AtualizarDiagnostico();
         AtualizarTextosHUD();
         ChartRedraw();
      }
   }
}

//+------------------------------------------------------------------+
//| Desenho das Linhas no Gráfico                                    |
//+------------------------------------------------------------------+
void DesenharLinhasIB()
{
   if(g_ib_high <= 0.0 || g_ib_low <= 0.0) return;

   CriarOuAtualizarLinha("LINE_HIGH", g_ib_high, InpCorIBHigh, STYLE_SOLID, 2, "IB High");
   CriarOuAtualizarLinha("LINE_LOW",  g_ib_low,  InpCorIBLow,  STYLE_SOLID, 2, "IB Low");
   CriarOuAtualizarLinha("LINE_POC",  g_ib_poc,  InpCorIBPoC,  STYLE_DOT,   1, "PoC Volume");
}

void CriarOuAtualizarLinha(string id, double preco, color cor, ENUM_LINE_STYLE estilo, int largura, string descricao)
{
   string nome = g_prefixo_gui + id;
   if(ObjectFind(0, nome) < 0)
   {
      ObjectCreate(0, nome, OBJ_HLINE, 0, 0, preco);
      ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
      ObjectSetInteger(0, nome, OBJPROP_STYLE, estilo);
      ObjectSetInteger(0, nome, OBJPROP_WIDTH, largura);
      ObjectSetString(0, nome, OBJPROP_TEXT, descricao);
      ObjectSetInteger(0, nome, OBJPROP_SELECTABLE, false);
   }
   else
   {
      ObjectSetDouble(0, nome, OBJPROP_PRICE, preco);
   }
}

void DesenharSetaSinal(string tipo, datetime tempo, double preco)
{
   string nome = g_prefixo_gui + "SETA_" + (string)tempo;
   bool buy = (tipo == "BUY");
   ObjectCreate(0, nome, OBJ_ARROW, 0, tempo, preco);
   ObjectSetInteger(0, nome, OBJPROP_ARROWCODE, buy ? 233 : 234);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, buy ? clrLime : clrRed);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, 3);
}

void CriarLabel(string id, string texto, int x, int y, color cor, int tamanho, bool negrito)
{
   string nome = g_prefixo_gui + id;
   if(ObjectFind(0, nome) < 0)
   {
      ObjectCreate(0, nome, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nome, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nome, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, nome, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, nome, OBJPROP_TEXT, texto);
      ObjectSetString(0, nome, OBJPROP_FONT, negrito ? "Arial Bold" : "Arial");
      ObjectSetInteger(0, nome, OBJPROP_FONTSIZE, tamanho);
      ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
   }
}

void AtualizarLabel(string id, string texto)
{
   string nome = g_prefixo_gui + id;
   ObjectSetString(0, nome, OBJPROP_TEXT, texto);
}
//+------------------------------------------------------------------+
