//+------------------------------------------------------------------+
//|                                     Nonlinear_Attractor_Core.mqh |
//|                                  Automação Robô Virada de Delta  |
//|               Motor Matemático de Langevin, Kramers-Moyal,       |
//|         Deformação Elástica, Headroom Geométrico e Trailing Stop |
//+------------------------------------------------------------------+
#property copyright "Robô Virada de Delta Pro & Antigravity"
#property link      "https://antigravity.google"
#property version   "2.00"

enum ENUM_PHYSICS_REGIME
  {
   REGIME_NEUTRAL,     // Dentro da zona harmônica (|Delta_t| < 1.8)
   REGIME_ALPHA_FADE,  // Regime Alfa: Reversão Elástica (|Delta_t| >= 2.0, H <= 0.57)
   REGIME_GAMMA_BOS    // Regime Gama: Colapso de Barreira / Breakout (BOS, H > 0.57)
  };

//+------------------------------------------------------------------+
//| Classe CNonlinearCore                                            |
//+------------------------------------------------------------------+
class CNonlinearCore
  {
private:
   string             m_symbol;
   ENUM_TIMEFRAMES    m_timeframe;
   double             m_crit_strain;     // Limiar crítico de deformação (padrão 2.0 a 2.5)
   double             m_min_headroom;    // R_geo mínimo (padrão 1.5 a 1.8x)
   double             m_max_omega;       // Limite do Índice de Autodestruição (2.0)
   int                m_atr_handle;
   double             m_point;

public:
                     CNonlinearCore(void);
                    ~CNonlinearCore(void);

   bool              Init(string symbol, ENUM_TIMEFRAMES timeframe,
                          double crit_strain=2.0, double min_headroom=1.5, double max_omega=2.0);

   void              Deinit(void);

   // Deformação Elástica Instantânea (Delta_t)
   double            CalculateElasticStrain(double price, double attractor, double atr);

   // Detecção de Regime Físico
   ENUM_PHYSICS_REGIME DetectRegime(double delta_t, double hurst, bool is_abnormal_vol);

   // Estimativa Rápida do Expoente de Hurst / Persistência
   double            EstimateHurst(int lookback=40);

   // Headroom Geométrico Estrutural (R_geo = D_barreira / D_stop)
   double            CalculateHeadroom(double entry, double sl, double target_barrier);
   bool              IsHeadroomValid(double entry, double sl, double target_barrier);

   // Índice de Autodestruição Varejista (Omega_t)
   double            CalculateOmegaIndex(double entry, double sl, double tp, double attractor, double atr);
   bool              IsOmegaSafe(double entry, double sl, double tp, double attractor, double atr);

   // Trailing Stop Estrutural Barra-a-Barra
   double            GetStructuralTrailingStop(bool is_buy, int bar_index, double atr_margin_mult=0.20);

   // Front-Running de Alvo (75% a 80% do caminho para o HVN)
   double            CalculateFrontRunTarget(double entry, double hvn_barrier, double ratio=0.80);

   // ATR Atual
   double            GetATR(int bar_index);
  };

//+------------------------------------------------------------------+
//| Construtor                                                       |
//+------------------------------------------------------------------+
CNonlinearCore::CNonlinearCore(void)
  : m_symbol(""),
    m_timeframe(PERIOD_M5),
    m_crit_strain(2.0),
    m_min_headroom(1.5),
    m_max_omega(2.0),
    m_atr_handle(INVALID_HANDLE),
    m_point(0.01)
  {
  }

//+------------------------------------------------------------------+
//| Destrutor                                                        |
//+------------------------------------------------------------------+
CNonlinearCore::~CNonlinearCore(void)
  {
   Deinit();
  }

//+------------------------------------------------------------------+
//| Inicialização                                                    |
//+------------------------------------------------------------------+
bool CNonlinearCore::Init(string symbol, ENUM_TIMEFRAMES timeframe,
                          double crit_strain=2.0, double min_headroom=1.5, double max_omega=2.0)
  {
   m_symbol       = (symbol == "" || symbol == NULL) ? _Symbol : symbol;
   m_timeframe    = timeframe;
   m_crit_strain  = MathMax(1.0, crit_strain);
   m_min_headroom = MathMax(1.0, min_headroom);
   m_max_omega    = MathMax(1.0, max_omega);
   m_point        = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

   m_atr_handle   = iATR(m_symbol, m_timeframe, 14);
   if(m_atr_handle == INVALID_HANDLE)
     {
      PrintFormat("[CNonlinearCore] Erro ao criar handle ATR para %s", m_symbol);
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Desinicialização                                                 |
//+------------------------------------------------------------------+
void CNonlinearCore::Deinit(void)
  {
   if(m_atr_handle != INVALID_HANDLE)
     {
      IndicatorRelease(m_atr_handle);
      m_atr_handle = INVALID_HANDLE;
     }
  }

//+------------------------------------------------------------------+
//| ATR                                                              |
//+------------------------------------------------------------------+
double CNonlinearCore::GetATR(int bar_index)
  {
   double buf[1];
   if(CopyBuffer(m_atr_handle, 0, bar_index, 1, buf) > 0)
      return(buf[0]);
   return(m_point * 10);
  }

//+------------------------------------------------------------------+
//| Cálculo da Deformação Elástica Instantânea (Delta_t)             |
//+------------------------------------------------------------------+
double CNonlinearCore::CalculateElasticStrain(double price, double attractor, double atr)
  {
   if(atr <= 0) atr = m_point * 10;
   return((price - attractor) / atr);
  }

//+------------------------------------------------------------------+
//| Estimativa do Expoente de Hurst (40 barras)                      |
//+------------------------------------------------------------------+
double CNonlinearCore::EstimateHurst(int lookback=40)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(m_symbol, m_timeframe, 0, lookback + 1, rates);
   if(copied < lookback) return(0.50);

   // Log-retornos
   double rets[];
   ArrayResize(rets, lookback);
   double sum = 0.0;
   for(int i = 0; i < lookback; i++)
     {
      double r = MathLog(rates[i].close / rates[i+1].close);
      rets[i] = r;
      sum += r;
     }

   double mean = sum / (double)lookback;

   // Desvios acumulados
   double cum_dev = 0.0;
   double min_dev = 0.0;
   double max_dev = 0.0;
   double sum_sq = 0.0;

   for(int i = 0; i < lookback; i++)
     {
      double diff = rets[i] - mean;
      cum_dev += diff;
      if(cum_dev < min_dev) min_dev = cum_dev;
      if(cum_dev > max_dev) max_dev = cum_dev;
      sum_sq += diff * diff;
     }

   double std_dev = MathSqrt(sum_sq / (double)lookback);
   if(std_dev <= 0) return(0.50);

   double range = max_dev - min_dev;
   double rs = range / std_dev;
   if(rs <= 0) return(0.50);

   // H ~ log(R/S) / log(lookback)
   double h = MathLog(rs) / MathLog((double)lookback);
   return(MathMin(0.95, MathMax(0.15, h)));
  }

//+------------------------------------------------------------------+
//| Detecção de Regime Físico                                        |
//+------------------------------------------------------------------+
ENUM_PHYSICS_REGIME CNonlinearCore::DetectRegime(double delta_t, double hurst, bool is_abnormal_vol)
  {
   double abs_d = MathAbs(delta_t);

   // Regime Alfa (Reversão / Fade): Alta deformação elástica com Hurst antipersistente
   if(abs_d >= m_crit_strain && hurst <= 0.57)
      return(REGIME_ALPHA_FADE);

   // Regime Gama (Colapso de Barreira / BOS): Alta deformação com Hurst persistente e volume explosivo
   if(abs_d >= (m_crit_strain + 0.2) && hurst > 0.57 && is_abnormal_vol)
      return(REGIME_GAMMA_BOS);

   return(REGIME_NEUTRAL);
  }

//+------------------------------------------------------------------+
//| Headroom Geométrico Estrutural (R_geo = D_barreira / D_stop)     |
//+------------------------------------------------------------------+
double CNonlinearCore::CalculateHeadroom(double entry, double sl, double target_barrier)
  {
   double dist_stop = MathAbs(entry - sl);
   double dist_target = MathAbs(target_barrier - entry);
   if(dist_stop <= 0) return(0.0);
   return(dist_target / dist_stop);
  }

bool CNonlinearCore::IsHeadroomValid(double entry, double sl, double target_barrier)
  {
   return(CalculateHeadroom(entry, sl, target_barrier) >= m_min_headroom);
  }

//+------------------------------------------------------------------+
//| Índice de Autodestruição Varejista (Omega_t)                     |
//+------------------------------------------------------------------+
double CNonlinearCore::CalculateOmegaIndex(double entry, double sl, double tp, double attractor, double atr)
  {
   if(atr <= 0) atr = m_point * 10;
   double dist_attr = MathAbs(entry - attractor) / atr;
   double dist_stop = MathAbs(entry - sl);
   double dist_tp   = MathAbs(entry - tp);

   if(dist_tp <= 0) return(99.0);
   double rr_ratio = dist_stop / dist_tp;

   // Omega = (Afastamento do vórtice) * (Risco / Retorno)
   return(dist_attr * rr_ratio);
  }

bool CNonlinearCore::IsOmegaSafe(double entry, double sl, double tp, double attractor, double atr)
  {
   return(CalculateOmegaIndex(entry, sl, tp, attractor, atr) <= m_max_omega);
  }

//+------------------------------------------------------------------+
//| Trailing Stop Estrutural Barra-a-Barra                           |
//+------------------------------------------------------------------+
double CNonlinearCore::GetStructuralTrailingStop(bool is_buy, int bar_index, double atr_margin_mult=0.20)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(m_symbol, m_timeframe, bar_index, 1, rates) < 1)
      return(0.0);

   double cur_atr = GetATR(bar_index);
   double margin = cur_atr * atr_margin_mult;

   if(is_buy)
      return(rates[0].low - margin);
   else
      return(rates[0].high + margin);
  }

//+------------------------------------------------------------------+
//| Front-Running de Alvo (75% a 80% da Barreira)                    |
//+------------------------------------------------------------------+
double CNonlinearCore::CalculateFrontRunTarget(double entry, double hvn_barrier, double ratio=0.80)
  {
   ratio = MathMin(0.95, MathMax(0.50, ratio));
   return(entry + (hvn_barrier - entry) * ratio);
  }
//+------------------------------------------------------------------+
