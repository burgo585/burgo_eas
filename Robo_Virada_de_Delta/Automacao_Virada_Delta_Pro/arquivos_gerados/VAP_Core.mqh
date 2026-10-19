//+------------------------------------------------------------------+
//|                                                     VAP_Core.mqh |
//|                                  Automação Robô Virada de Delta  |
//|               Motor de Volume At Price (VPVR), POC, VAH, VAL,    |
//|                    Nós de Volume (HVN/LVN) e Micro-Delta         |
//+------------------------------------------------------------------+
#property copyright "Robô Virada de Delta Pro & Antigravity"
#property link      "https://antigravity.google"
#property version   "2.00"

struct SVapLevel
  {
   double            price;
   double            volume_total;
   double            volume_buy;
   double            volume_sell;
   bool              is_hvn;
   bool              is_lvn;
  };

//+------------------------------------------------------------------+
//| Classe CVapCore                                                  |
//+------------------------------------------------------------------+
class CVapCore
  {
private:
   string             m_symbol;
   ENUM_TIMEFRAMES    m_timeframe;
   int                m_lookback_bars;
   int                m_target_levels;
   double             m_va_percent;
   double             m_point;
   int                m_digits;

   double             m_poc;
   double             m_vah;
   double             m_val;
   double             m_total_profile_volume;

   SVapLevel          m_levels[];
   int                m_levels_count;

   double             m_naked_pocs[];
   int                m_npoc_count;

public:
                     CVapCore(void);
                    ~CVapCore(void);

   bool              Init(string symbol, ENUM_TIMEFRAMES timeframe,
                          int lookback_bars=288, int target_levels=70, double va_percent=70.0);

   void              Deinit(void);

   // Atualização do Perfil
   bool              UpdateProfile(void);

   // Getters Principais
   double            GetPOC(void) const { return m_poc; }
   double            GetVAH(void) const { return m_vah; }
   double            GetVAL(void) const { return m_val; }
   double            GetTotalVolume(void) const { return m_total_profile_volume; }

   // Consulta de Nós de Volume
   bool              IsNearHVN(double price, double tolerance_points, double &hvn_price);
   bool              IsInsideLVN(double price, double &lvn_bottom, double &lvn_top);
   double            GetNearestHVN(double price, bool search_above);
   double            GetNearestLVN(double price, bool search_above);

   // Naked POCs
   int               GetNakedPocs(double &out_npocs[]);
   void              CheckNakedPocTouches(double high, double low);

   // Micro-Delta do Candle Atual ou Específico
   double            GetCandleDelta(int bar_index, double &buy_vol, double &sell_vol);
  };

//+------------------------------------------------------------------+
//| Construtor                                                       |
//+------------------------------------------------------------------+
CVapCore::CVapCore(void)
  : m_symbol(""),
    m_timeframe(PERIOD_M5),
    m_lookback_bars(288),
    m_target_levels(70),
    m_va_percent(70.0),
    m_point(0.01),
    m_digits(2),
    m_poc(0.0),
    m_vah(0.0),
    m_val(0.0),
    m_total_profile_volume(0.0),
    m_levels_count(0),
    m_npoc_count(0)
  {
  }

//+------------------------------------------------------------------+
//| Destrutor                                                        |
//+------------------------------------------------------------------+
CVapCore::~CVapCore(void)
  {
   Deinit();
  }

//+------------------------------------------------------------------+
//| Inicialização                                                    |
//+------------------------------------------------------------------+
bool CVapCore::Init(string symbol, ENUM_TIMEFRAMES timeframe,
                    int lookback_bars=288, int target_levels=70, double va_percent=70.0)
  {
   m_symbol        = (symbol == "" || symbol == NULL) ? _Symbol : symbol;
   m_timeframe     = timeframe;
   m_lookback_bars = MathMax(20, lookback_bars);
   m_target_levels = MathMax(20, target_levels);
   m_va_percent    = (va_percent > 0 && va_percent < 100) ? va_percent : 70.0;

   m_point         = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   m_digits        = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

   ArrayResize(m_naked_pocs, 0);
   m_npoc_count = 0;

   return(UpdateProfile());
  }

//+------------------------------------------------------------------+
//| Desinicialização                                                 |
//+------------------------------------------------------------------+
void CVapCore::Deinit(void)
  {
   ArrayFree(m_levels);
   ArrayFree(m_naked_pocs);
   m_levels_count = 0;
   m_npoc_count = 0;
  }

//+------------------------------------------------------------------+
//| Atualização do Perfil de Volume (VPVR)                           |
//+------------------------------------------------------------------+
bool CVapCore::UpdateProfile(void)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(m_symbol, m_timeframe, 0, m_lookback_bars, rates);
   if(copied < 20) return(false);

   // Encontra máxima e mínima da janela
   double min_p = DBL_MAX;
   double max_p = -DBL_MAX;

   for(int i = 0; i < copied; i++)
     {
      if(rates[i].low < min_p)  min_p = rates[i].low;
      if(rates[i].high > max_p) max_p = rates[i].high;
     }

   double range = max_p - min_p;
   if(range <= 0) return(false);

   // Calcula tamanho do degrau de preço
   double step = range / (double)m_target_levels;
   double tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0) tick_size = m_point;
   step = MathMax(tick_size, MathRound(step / tick_size) * tick_size);

   int num_bins = (int)MathCeil(range / step) + 1;
   num_bins = MathMax(10, MathMin(200, num_bins));

   ArrayResize(m_levels, num_bins);
   m_levels_count = num_bins;

   for(int b = 0; b < num_bins; b++)
     {
      m_levels[b].price = min_p + (b * step);
      m_levels[b].volume_total = 0;
      m_levels[b].volume_buy = 0;
      m_levels[b].volume_sell = 0;
      m_levels[b].is_hvn = false;
      m_levels[b].is_lvn = false;
     }

   m_total_profile_volume = 0.0;

   // Distribui o volume dos candles nas faixas de preço
   for(int i = 0; i < copied; i++)
     {
      long v = (rates[i].real_volume > 0) ? rates[i].real_volume : rates[i].tick_volume;
      if(v <= 0) continue;

      double c_high = rates[i].high;
      double c_low  = rates[i].low;
      double c_rng  = c_high - c_low;

      int b_start = (int)MathFloor((c_low - min_p) / step);
      int b_end   = (int)MathFloor((c_high - min_p) / step);
      b_start = MathMax(0, MathMin(num_bins - 1, b_start));
      b_end   = MathMax(0, MathMin(num_bins - 1, b_end));

      int span_bins = b_end - b_start + 1;
      double vol_per_bin = (double)v / (double)span_bins;

      // Estimativa micro-delta: fecha acima da abertura = mais compradores
      double buy_ratio = 0.50;
      if(c_rng > 0)
         buy_ratio = MathMin(0.90, MathMax(0.10, (rates[i].close - c_low) / c_rng));

      for(int b = b_start; b <= b_end; b++)
        {
         m_levels[b].volume_total += vol_per_bin;
         m_levels[b].volume_buy   += vol_per_bin * buy_ratio;
         m_levels[b].volume_sell  += vol_per_bin * (1.0 - buy_ratio);
         m_total_profile_volume   += vol_per_bin;
        }
     }

   // 1. Encontra o POC (Pico do perfil)
   int poc_idx = 0;
   double max_vol = -1.0;
   for(int b = 0; b < num_bins; b++)
     {
      if(m_levels[b].volume_total > max_vol)
        {
         max_vol = m_levels[b].volume_total;
         poc_idx = b;
        }
     }
   m_poc = m_levels[poc_idx].price;

   // 2. Calcula Área de Valor (VAH e VAL) expandindo a partir do POC até atingir m_va_percent
   double target_vol = m_total_profile_volume * (m_va_percent / 100.0);
   double cum_vol = m_levels[poc_idx].volume_total;
   int l_idx = poc_idx;
   int h_idx = poc_idx;

   while(cum_vol < target_vol && (l_idx > 0 || h_idx < num_bins - 1))
     {
      double v_above = (h_idx + 1 < num_bins) ? m_levels[h_idx + 1].volume_total : 0.0;
      double v_below = (l_idx - 1 >= 0) ? m_levels[l_idx - 1].volume_total : 0.0;

      if(v_above >= v_below && h_idx + 1 < num_bins)
        {
         h_idx++;
         cum_vol += v_above;
        }
      else if(l_idx - 1 >= 0)
        {
         l_idx--;
         cum_vol += v_below;
        }
      else break;
     }

   m_vah = m_levels[h_idx].price;
   m_val = m_levels[l_idx].price;

   // 3. Classifica Nós HVN (Picos Locais) e LVN (Vales Locais)
   double avg_bin_vol = m_total_profile_volume / (double)num_bins;
   for(int b = 2; b < num_bins - 2; b++)
     {
      double cur_v = m_levels[b].volume_total;
      // HVN: Maior que os 2 vizinhos de cada lado e acima da média
      if(cur_v > m_levels[b-1].volume_total && cur_v > m_levels[b-2].volume_total &&
         cur_v > m_levels[b+1].volume_total && cur_v > m_levels[b+2].volume_total &&
         cur_v >= avg_bin_vol * 1.2)
        {
         m_levels[b].is_hvn = true;
        }
      // LVN: Menor que os 2 vizinhos de cada lado e abaixo de 60% da média
      else if(cur_v < m_levels[b-1].volume_total && cur_v < m_levels[b-2].volume_total &&
              cur_v < m_levels[b+1].volume_total && cur_v < m_levels[b+2].volume_total &&
              cur_v <= avg_bin_vol * 0.6)
        {
         m_levels[b].is_lvn = true;
        }
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Encontra o HVN mais próximo                                      |
//+------------------------------------------------------------------+
double CVapCore::GetNearestHVN(double price, bool search_above)
  {
   double nearest_p = search_above ? DBL_MAX : -DBL_MAX;
   bool found = false;

   for(int b = 0; b < m_levels_count; b++)
     {
      if(m_levels[b].is_hvn || MathAbs(m_levels[b].price - m_poc) < m_point)
        {
         double p = m_levels[b].price;
         if(search_above && p > price && p < nearest_p)
           {
            nearest_p = p;
            found = true;
           }
         else if(!search_above && p < price && p > nearest_p)
           {
            nearest_p = p;
            found = true;
           }
        }
     }

   if(!found)
      return(search_above ? m_vah : m_val);

   return(nearest_p);
  }

//+------------------------------------------------------------------+
//| Encontra o LVN mais próximo                                      |
//+------------------------------------------------------------------+
double CVapCore::GetNearestLVN(double price, bool search_above)
  {
   double nearest_p = search_above ? DBL_MAX : -DBL_MAX;
   bool found = false;

   for(int b = 0; b < m_levels_count; b++)
     {
      if(m_levels[b].is_lvn)
        {
         double p = m_levels[b].price;
         if(search_above && p > price && p < nearest_p)
           {
            nearest_p = p;
            found = true;
           }
         else if(!search_above && p < price && p > nearest_p)
           {
            nearest_p = p;
            found = true;
           }
        }
     }

   return(found ? nearest_p : price);
  }

//+------------------------------------------------------------------+
//| Micro-Delta do Candle                                            |
//+------------------------------------------------------------------+
double CVapCore::GetCandleDelta(int bar_index, double &buy_vol, double &sell_vol)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(m_symbol, m_timeframe, bar_index, 1, rates) < 1)
      return(0.0);

   long v = (rates[0].real_volume > 0) ? rates[0].real_volume : rates[0].tick_volume;
   double rng = rates[0].high - rates[0].low;
   if(rng <= 0)
     {
      buy_vol = (double)v * 0.5;
      sell_vol = (double)v * 0.5;
      return(0.0);
     }

   double buy_ratio = MathMin(0.95, MathMax(0.05, (rates[0].close - rates[0].low) / rng));
   buy_vol = (double)v * buy_ratio;
   sell_vol = (double)v * (1.0 - buy_ratio);
   return(buy_vol - sell_vol);
  }
//+------------------------------------------------------------------+
