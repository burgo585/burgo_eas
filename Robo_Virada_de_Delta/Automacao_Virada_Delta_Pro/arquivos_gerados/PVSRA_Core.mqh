//+------------------------------------------------------------------+
//|                                                   PVSRA_Core.mqh |
//|                                  Automação Robô Virada de Delta  |
//|               Motor Matemático e Microestrutural PVSRA Institucional|
//+------------------------------------------------------------------+
#property copyright "Robô Virada de Delta Pro & Antigravity"
#property link      "https://antigravity.google"
#property version   "2.00"

//--- Tipos de Candles PVSRA
enum ENUM_PVSRA_CANDLE_TYPE
  {
   PVSRA_NORMAL_BULL,   // Candle normal de alta
   PVSRA_NORMAL_BEAR,   // Candle normal de baixa
   PVSRA_RISING_BULL,   // Volume crescente touro (Azul / DodgerBlue)
   PVSRA_RISING_BEAR,   // Volume crescente urso (Roxo / Magenta)
   PVSRA_CLIMAX_BULL,   // Volume clímax touro (Verde / LimeGreen)
   PVSRA_CLIMAX_BEAR    // Volume clímax urso (Vermelho / Red)
  };

//+------------------------------------------------------------------+
//| Classe CPvsraCore                                                |
//+------------------------------------------------------------------+
class CPvsraCore
  {
private:
   string             m_symbol;
   ENUM_TIMEFRAMES    m_timeframe;
   int                m_lookback;
   double             m_rising_mult;
   double             m_climax_mult;
   bool               m_use_abnormal;
   int                m_adv_period;
   int                m_dragon_period;
   int                m_trend_period;

   int                m_h_dragon_high;
   int                m_h_dragon_low;
   int                m_h_dragon_mid;
   int                m_h_trend;
   int                m_h_daily_adv;

public:
                     CPvsraCore(void);
                    ~CPvsraCore(void);

   bool              Init(string symbol, ENUM_TIMEFRAMES timeframe,
                          int lookback=10, double rising_mult=1.5, double climax_mult=2.0,
                          bool use_abnormal=true, int adv_period=365,
                          int dragon_period=34, int trend_period=200);

   void              Deinit(void);

   // Análise de Candles e Volume
   ENUM_PVSRA_CANDLE_TYPE GetCandleType(int bar_index);
   bool              IsClimax(int bar_index);
   bool              IsRising(int bar_index);
   bool              IsAbnormal(int bar_index);
   double            GetVolumeRatio(int bar_index);
   double            GetAbnormalThreshold(int bar_index);

   // Médias e Dragon
   double            GetDragonHigh(int bar_index);
   double            GetDragonLow(int bar_index);
   double            GetDragonMid(int bar_index);
   double            GetTrend(int bar_index);

   // Níveis Psicológicos
   void              GetPsychologicalLevels(double price, double whole_size,
                                            double &whole, double &half, double &quarter);
  };

//+------------------------------------------------------------------+
//| Construtor                                                       |
//+------------------------------------------------------------------+
CPvsraCore::CPvsraCore(void)
  : m_symbol(""),
    m_timeframe(PERIOD_M5),
    m_lookback(10),
    m_rising_mult(1.5),
    m_climax_mult(2.0),
    m_use_abnormal(true),
    m_adv_period(365),
    m_dragon_period(34),
    m_trend_period(200),
    m_h_dragon_high(INVALID_HANDLE),
    m_h_dragon_low(INVALID_HANDLE),
    m_h_dragon_mid(INVALID_HANDLE),
    m_h_trend(INVALID_HANDLE),
    m_h_daily_adv(INVALID_HANDLE)
  {
  }

//+------------------------------------------------------------------+
//| Destrutor                                                        |
//+------------------------------------------------------------------+
CPvsraCore::~CPvsraCore(void)
  {
   Deinit();
  }

//+------------------------------------------------------------------+
//| Inicialização                                                    |
//+------------------------------------------------------------------+
bool CPvsraCore::Init(string symbol, ENUM_TIMEFRAMES timeframe,
                      int lookback=10, double rising_mult=1.5, double climax_mult=2.0,
                      bool use_abnormal=true, int adv_period=365,
                      int dragon_period=34, int trend_period=200)
  {
   m_symbol        = (symbol == "" || symbol == NULL) ? _Symbol : symbol;
   m_timeframe     = timeframe;
   m_lookback      = MathMax(2, lookback);
   m_rising_mult   = MathMax(1.0, rising_mult);
   m_climax_mult   = MathMax(m_rising_mult, climax_mult);
   m_use_abnormal  = use_abnormal;
   m_adv_period    = MathMax(10, adv_period);
   m_dragon_period = MathMax(2, dragon_period);
   m_trend_period  = MathMax(2, trend_period);

   // Handles Dragon
   m_h_dragon_high = iMA(m_symbol, m_timeframe, m_dragon_period, 0, MODE_EMA, PRICE_HIGH);
   m_h_dragon_low  = iMA(m_symbol, m_timeframe, m_dragon_period, 0, MODE_EMA, PRICE_LOW);
   m_h_dragon_mid  = iMA(m_symbol, m_timeframe, m_dragon_period, 0, MODE_EMA, PRICE_MEDIAN);

   // Handle Tendência
   m_h_trend       = iMA(m_symbol, m_timeframe, m_trend_period, 0, MODE_EMA, PRICE_CLOSE);

   // Handle ADV diário (para o cálculo de Volume Anormal v6)
   if(m_use_abnormal)
     {
      // EMA do volume diário no D1
      m_h_daily_adv = iMA(m_symbol, PERIOD_D1, m_adv_period, 0, MODE_EMA, PRICE_CLOSE);
     }

   if(m_h_dragon_high == INVALID_HANDLE || m_h_dragon_low == INVALID_HANDLE ||
      m_h_dragon_mid == INVALID_HANDLE || m_h_trend == INVALID_HANDLE)
     {
      PrintFormat("[CPvsraCore] Erro ao criar handles de indicadores para %s", m_symbol);
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Desinicialização                                                 |
//+------------------------------------------------------------------+
void CPvsraCore::Deinit(void)
  {
   if(m_h_dragon_high != INVALID_HANDLE) { IndicatorRelease(m_h_dragon_high); m_h_dragon_high = INVALID_HANDLE; }
   if(m_h_dragon_low != INVALID_HANDLE)  { IndicatorRelease(m_h_dragon_low);  m_h_dragon_low  = INVALID_HANDLE; }
   if(m_h_dragon_mid != INVALID_HANDLE)  { IndicatorRelease(m_h_dragon_mid);  m_h_dragon_mid  = INVALID_HANDLE; }
   if(m_h_trend != INVALID_HANDLE)       { IndicatorRelease(m_h_trend);       m_h_trend       = INVALID_HANDLE; }
   if(m_h_daily_adv != INVALID_HANDLE)   { IndicatorRelease(m_h_daily_adv);   m_h_daily_adv   = INVALID_HANDLE; }
  }

//+------------------------------------------------------------------+
//| Classificação de Candle PVSRA                                    |
//+------------------------------------------------------------------+
ENUM_PVSRA_CANDLE_TYPE CPvsraCore::GetCandleType(int bar_index)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(m_symbol, m_timeframe, bar_index, m_lookback + 1, rates) < m_lookback + 1)
      return(PVSRA_NORMAL_BULL);

   bool is_bull = (rates[0].close >= rates[0].open);

   // Volume atual (usa tick_volume ou real_volume)
   long vol_atual = (rates[0].real_volume > 0) ? rates[0].real_volume : rates[0].tick_volume;

   // Média de volume nos últimos lookback candles
   double soma_vol = 0;
   double max_spread_vol = 0;

   for(int i = 1; i <= m_lookback; i++)
     {
      long v = (rates[i].real_volume > 0) ? rates[i].real_volume : rates[i].tick_volume;
      soma_vol += (double)v;

      double spread = MathAbs(rates[i].high - rates[i].low);
      double sp_v = spread * (double)v;
      if(sp_v > max_spread_vol)
         max_spread_vol = sp_v;
     }

   double media_vol = soma_vol / (double)m_lookback;
   double cur_spread = MathAbs(rates[0].high - rates[0].low);
   double cur_sp_v = cur_spread * (double)vol_atual;

   // Regra 1: Clímax (Volume >= 2.0x média OU Spread*Vol é máxima dos últimos lookback)
   bool climax = (vol_atual >= media_vol * m_climax_mult) || (cur_sp_v >= max_spread_vol);

   if(climax)
      return(is_bull ? PVSRA_CLIMAX_BULL : PVSRA_CLIMAX_BEAR);

   // Regra 2: Rising (Volume >= 1.5x média)
   bool rising = (vol_atual >= media_vol * m_rising_mult);
   if(rising)
      return(is_bull ? PVSRA_RISING_BULL : PVSRA_RISING_BEAR);

   // Regra 3: Normal
   return(is_bull ? PVSRA_NORMAL_BULL : PVSRA_NORMAL_BEAR);
  }

//+------------------------------------------------------------------+
//| Verifica se é Clímax                                             |
//+------------------------------------------------------------------+
bool CPvsraCore::IsClimax(int bar_index)
  {
   ENUM_PVSRA_CANDLE_TYPE t = GetCandleType(bar_index);
   return(t == PVSRA_CLIMAX_BULL || t == PVSRA_CLIMAX_BEAR);
  }

//+------------------------------------------------------------------+
//| Verifica se é Rising                                             |
//+------------------------------------------------------------------+
bool CPvsraCore::IsRising(int bar_index)
  {
   ENUM_PVSRA_CANDLE_TYPE t = GetCandleType(bar_index);
   return(t == PVSRA_RISING_BULL || t == PVSRA_RISING_BEAR);
  }

//+------------------------------------------------------------------+
//| Razão de Volume em relação à média                               |
//+------------------------------------------------------------------+
double CPvsraCore::GetVolumeRatio(int bar_index)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(m_symbol, m_timeframe, bar_index, m_lookback + 1, rates) < m_lookback + 1)
      return(1.0);

   long vol_atual = (rates[0].real_volume > 0) ? rates[0].real_volume : rates[0].tick_volume;
   double soma_vol = 0;
   for(int i = 1; i <= m_lookback; i++)
     {
      long v = (rates[i].real_volume > 0) ? rates[i].real_volume : rates[i].tick_volume;
      soma_vol += (double)v;
     }
   double media = soma_vol / (double)m_lookback;
   return(media > 0 ? (double)vol_atual / media : 1.0);
  }

//+------------------------------------------------------------------+
//| Limiar de Volume Anormal v6 (baseado em ADV diário)              |
//+------------------------------------------------------------------+
double CPvsraCore::GetAbnormalThreshold(int bar_index)
  {
   if(!m_use_abnormal) return(0.0);

   int period_sec = PeriodSeconds(m_timeframe);
   if(period_sec <= 0) period_sec = 300;
   double min_per_bar = (double)period_sec / 60.0;

   // Minutos por dia padrão de mercado (1440 min)
   double min_per_day = 1440.0;
   double k = MathSqrt(min_per_bar / min_per_day);

   // Pega valor da média do volume diário
   MqlRates daily_rates[];
   ArraySetAsSeries(daily_rates, true);
   if(CopyRates(m_symbol, PERIOD_D1, 1, m_adv_period, daily_rates) < 10)
      return(0.0);

   double adv_sum = 0;
   int cnt = MathMin(m_adv_period, ArraySize(daily_rates));
   for(int i = 0; i < cnt; i++)
     {
      long dv = (daily_rates[i].real_volume > 0) ? daily_rates[i].real_volume : daily_rates[i].tick_volume;
      adv_sum += (double)dv;
     }
   double adv = adv_sum / (double)cnt;

   // Fórmula v6: ADV * 2.0 * sqrt(min_bar / 1440)
   return(adv * 2.0 * k);
  }

//+------------------------------------------------------------------+
//| Verifica se Volume Atual está acima do Limiar Anormal v6         |
//+------------------------------------------------------------------+
bool CPvsraCore::IsAbnormal(int bar_index)
  {
   if(!m_use_abnormal) return(false);
   double limiar = GetAbnormalThreshold(bar_index);
   if(limiar <= 0) return(false);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(m_symbol, m_timeframe, bar_index, 1, rates) < 1)
      return(false);

   long vol = (rates[0].real_volume > 0) ? rates[0].real_volume : rates[0].tick_volume;
   return((double)vol >= limiar);
  }

//+------------------------------------------------------------------+
//| Getters Dragon e Tendência                                       |
//+------------------------------------------------------------------+
double CPvsraCore::GetDragonHigh(int bar_index)
  {
   double buf[1];
   if(CopyBuffer(m_h_dragon_high, 0, bar_index, 1, buf) > 0) return(buf[0]);
   return(0.0);
  }

double CPvsraCore::GetDragonLow(int bar_index)
  {
   double buf[1];
   if(CopyBuffer(m_h_dragon_low, 0, bar_index, 1, buf) > 0) return(buf[0]);
   return(0.0);
  }

double CPvsraCore::GetDragonMid(int bar_index)
  {
   double buf[1];
   if(CopyBuffer(m_h_dragon_mid, 0, bar_index, 1, buf) > 0) return(buf[0]);
   return(0.0);
  }

double CPvsraCore::GetTrend(int bar_index)
  {
   double buf[1];
   if(CopyBuffer(m_h_trend, 0, bar_index, 1, buf) > 0) return(buf[0]);
   return(0.0);
  }

//+------------------------------------------------------------------+
//| Níveis Psicológicos (Inteiros, Meios, Quartos)                   |
//+------------------------------------------------------------------+
void CPvsraCore::GetPsychologicalLevels(double price, double whole_size,
                                        double &whole, double &half, double &quarter)
  {
   if(whole_size <= 0) whole_size = 1.0;
   whole = MathFloor(price / whole_size) * whole_size;
   half = whole + (whole_size * 0.50);

   double q1 = whole + (whole_size * 0.25);
   double q3 = whole + (whole_size * 0.75);

   if(MathAbs(price - q1) < MathAbs(price - q3))
      quarter = q1;
   else
      quarter = q3;
  }
//+------------------------------------------------------------------+
