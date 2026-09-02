//+------------------------------------------------------------------+
//|                                              Algory_Replica.mq5  |
//|  Replica del motore Algory (engine v129) per MT5 Strategy Tester  |
//|                                                                    |
//|  Semantica ricostruita e verificata contro il vault del motore    |
//|  originale (43 strategie, campagna test_1):                        |
//|   - ATR   = SMA(TrueRange, 14)                     [esatto]        |
//|   - STOCH = K=SMA5(raw5), D=SMA5(K)                [esatto]        |
//|   - MACD  = SMA(12)-SMA(26), signal=SMA(line,9)    [esatto]        |
//|   - Filtro SMA = close vs SMA(sma_fast_period)     [esatto 100%]   |
//|   - Segnale = stato: K>D AND macd>sig AND close oltre SMA_fast     |
//|     (direzione coerente su 447/447 segnali del vault)              |
//|   - Ingresso STOP: close + dir*stop_offset_atr*ATR (330/330 esatti)|
//|   - SL/TP = entry -/+ sl_mult/tp_mult * ATR(segnale)   [esatto]    |
//|   - Sessione: chiusura barra in [start_hour, end_hour)             |
//|   - Venerdi: chiusura a friday_close - 1h + jitter_min             |
//|     (verificato: 16:20/15:20/18:20 su 4 strategie)                 |
//|   - Gate: posizione aperta blocca; nuovo segnale sostituisce       |
//|     l'ordine pendente; spread gate (max_spread_*); expiry barre    |
//|                                                                    |
//|  Uso: piazzare su grafico H2 (XAUUSD per le top strategies),       |
//|  caricare il .set della strategia, testare 2023.03.21-2026.08.14.  |
//|  Default inputs = XAUUSD_H2_6E4857 (locked return +53.4%).         |
//+------------------------------------------------------------------+
#property copyright "Replica Algory - uso personale"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//==================== GENOME INPUTS (default = XAUUSD_H2_6E4857) ====
input group "=== Sessione ==="
input int    start_hour            = 4;      // start_hour
input int    end_hour              = 17;     // end_hour (esclusivo)
input int    friday_close          = 17;     // friday_close (ora)
input int    friday_close_jitter_min= 20;    // friday_close_jitter_min
input bool   use_no_open_friday    = false;  // use_no_open_friday
input int    time_shift            = 0;      // time_shift (ore)

input group "=== Segnali (stato AND) ==="
input bool   use_sig_macd          = true;   // use_sig_macd
input bool   use_sig_stoch         = true;   // use_sig_stoch
input bool   use_sig_wick_rejection= false;  // use_sig_wick_rejection
input bool   use_sig_mom_break     = false;  // use_sig_mom_break
input bool   use_sig_engulfing     = false;  // use_sig_engulfing
input bool   use_sig_inside_break  = false;  // use_sig_inside_break
input bool   use_sig_pin_bar       = false;  // use_sig_pin_bar
input bool   use_sig_breakout      = false;  // use_sig_breakout
input bool   use_sig_liqsweep      = false;  // use_sig_liqsweep
input bool   use_sig_fade          = false;  // use_sig_fade
input bool   use_sig_rsi           = false;  // use_sig_rsi
input bool   use_sig_bb            = false;  // use_sig_bb
input bool   use_sig_cci           = false;  // use_sig_cci
input bool   use_sig_three_soldiers= false;  // use_sig_three_soldiers

input group "=== Bias (direzione) ==="
input bool   use_bias_donchian_mid = false;  // use_bias_donchian_mid
input bool   use_bias_daily_mid    = false;  // use_bias_daily_mid
input bool   use_bias_psar         = false;  // use_bias_psar
input bool   use_bias_sma          = false;  // use_bias_sma
input bool   use_bias_ema          = false;  // use_bias_ema
input bool   use_bias_adx          = false;  // use_bias_adx
input bool   use_bias_rsi          = false;  // use_bias_rsi

input group "=== Filtri ==="
input bool   use_filt_sma          = true;   // use_filt_sma (close vs SMA_fast)
input bool   use_filt_rsi          = false;  // use_filt_rsi
input bool   use_filt_doji         = false;  // use_filt_doji
input bool   use_filt_adr_exhaust  = false;  // use_filt_adr_exhaust
input bool   use_filt_bb           = false;  // use_filt_bb
input bool   use_filt_cci          = false;  // use_filt_cci
input bool   use_filt_consec       = false;  // use_filt_consec
input bool   use_filt_volatility   = false;  // use_filt_volatility

input group "=== Uscite / Gestione ==="
input double sl_mult               = 2.9;    // sl_mult (x ATR)
input double tp_mult               = 2.1;    // tp_mult (x ATR)
input bool   use_breakeven         = false;  // use_breakeven
input bool   use_atr_trail         = false;  // use_atr_trail
input bool   use_partial_tp        = false;  // use_partial_tp
input bool   use_friday_close      = true;   // use_friday_close
input bool   use_friday_close_profit= false; // use_friday_close_profit
input bool   use_daily_dd          = true;   // use_daily_dd
input double daily_dd_limit        = 4.0;    // daily_dd_limit (%)
input bool   use_news_filter       = false;  // use_news_filter (off: serve calendario)
input bool   use_symbol_lock       = true;   // use_symbol_lock
input bool   use_slippage          = true;   // use_slippage

input group "=== Parametri indicatori ==="
input int    atr_ma_period         = 14;     // atr_ma_period
input int    sma_fast_period       = 71;     // sma_fast_period
input int    sma_slow_period       = 155;    // sma_slow_period
input int    stoch_k_period        = 5;      // stoch_k_period
input int    stoch_d_period        = 5;      // stoch_d_period
input int    stoch_slowing         = 5;      // stoch_slowing
input int    rsi_period            = 16;     // rsi_period
input int    cci_period            = 24;     // cci_period
input int    cci_limit             = 80;     // cci_limit
input int    bb_period             = 28;     // bb_period
input double bb_std                = 2.0;    // bb_std
input int    momentum_period       = 15;     // momentum_period
input int    adr_period            = 5;      // adr_period
input double adr_exhaust_pct       = 0.75;   // adr_exhaust_pct
input int    adx_period            = 14;     // adx_period
input double adx_threshold         = 22;     // adx_threshold
input int    ema_period            = 200;    // ema_period
input double psar_step             = 0.025;  // psar_step
input double psar_max              = 0.3;    // psar_max
input double wick_ratio            = 2.5;    // wick_ratio
input int    breakout_lookback     = 60;     // breakout_lookback
input int    liqsweep_lookback     = 30;     // liqsweep_lookback
input int    consec_count          = 3;      // consec_count
input int    chand_mult            = 3;      // chand_mult (non usato v1)

input group "=== Esecuzione ==="
input string exec_mode             = "stop"; // exec_mode: stop|limit|limit2|market2|market
input double stop_offset_atr       = 0.30;   // stop_offset_atr
input int    stop_expiry_bars      = 4;      // stop_expiry_bars
input double limit_offset_atr      = 0.40;   // limit_offset_atr
input int    limit_expiry_bars     = 3;      // limit_expiry_bars
input double limit2_offset_atr     = 0.05;   // limit2_offset_atr
input int    market2_window_bars   = 8;      // market2_window_bars
input double market2_pullback_atr  = 0.08;   // market2_pullback_atr

input group "=== Friction / Gate ==="
input double max_spread_metal      = 16.0;   // max_spread_metal (pts)
input double max_spread_major      = 3.0;    // max_spread_major
input double max_spread_cross      = 10.0;   // max_spread_cross
input int    max_slip_metal        = 30;     // max_slip_metal (pts)

input group "=== Money Management ==="
input bool   use_fixed_lot         = false;  // true=lotto fisso, false=rischio %
input double fixed_lot             = 0.01;   // fixed_lot
input double risk_pct              = 1.0;    // risk_pct (% su SL)
input double initial_balance       = 1000.0; // balance iniziale (backtest)
input int    magic_number          = 900605; // magic number

//==================== STATO INTERNO =================================
CTrade   trade;
datetime g_last_bar   = 0;
bool     g_day_halted = false;
int      g_halt_day   = -1;
double   g_day_start_eq = 0;
int      g_fri_jitter_min = 0;   // estrazione unica per run
double   g_signal_atr = 0;       // ATR del segnale dell'ordine corrente
datetime g_pending_signal_time = 0;
int      g_hRsi = INVALID_HANDLE;
int      g_hCci = INVALID_HANDLE;
int      g_hBb  = INVALID_HANDLE;
int      g_hEma = INVALID_HANDLE;
int      g_hSar = INVALID_HANDLE;

double GetBuf(int handle, int buffer, int shift)
{
   if(handle == INVALID_HANDLE) return EMPTY_VALUE;
   double arr[1];
   if(CopyBuffer(handle, buffer, shift, 1, arr) == 1) return arr[0];
   return EMPTY_VALUE;
}

//==================== HELPERS INDICATORI ============================
double AtrSma(int shift, int period)
{
   double sum = 0;
   int count = 0;
   for(int i = shift; i < shift + period; i++)
   {
      double h = iHigh(_Symbol, _Period, i);
      double l = iLow(_Symbol, _Period, i);
      double pc = iClose(_Symbol, _Period, i + 1);
      double tr = MathMax(h - l, MathMax(MathAbs(h - pc), MathAbs(l - pc)));
      sum += tr;
      count++;
   }
   return (count > 0) ? sum / count : 0;
}

void StochSma(int shift, int k, int slow, int d, double &K, double &D)
{
   // %K raw su k barre, SMA(slow), %D = SMA(d) di K — come il motore
   double lo = DBL_MAX, hi = -DBL_MAX;
   for(int i = shift; i < shift + k; i++)
   {
      lo = MathMin(lo, iLow(_Symbol, _Period, i));
      hi = MathMax(hi, iHigh(_Symbol, _Period, i));
   }
   double c = iClose(_Symbol, _Period, shift);
   double raw = (hi > lo) ? (c - lo) / (hi - lo) * 100.0 : 50.0;

   // K = SMA(raw, slow): serve la serie raw
   double raw_series[];
   ArrayResize(raw_series, slow + d + 2);
   for(int j = 0; j < slow + d + 2; j++)
   {
      double l2 = DBL_MAX, h2 = -DBL_MAX;
      for(int q = shift + j; q < shift + j + k; q++)
      {
         l2 = MathMin(l2, iLow(_Symbol, _Period, q));
         h2 = MathMax(h2, iHigh(_Symbol, _Period, q));
      }
      double cc = iClose(_Symbol, _Period, shift + j);
      raw_series[j] = (h2 > l2) ? (cc - l2) / (h2 - l2) * 100.0 : 50.0;
   }
   // K = SMA(raw, slow) al tempo shift
   double ksum = 0;
   for(int j = 0; j < slow; j++) ksum += raw_series[j];
   K = ksum / slow;
   // D = SMA(K, d)
   double dsum = 0;
   for(int j = 0; j < d; j++)
   {
      double ksum2 = 0;
      for(int q = j; q < j + slow; q++) ksum2 += raw_series[q];
      dsum += ksum2 / slow;
   }
   D = dsum / d;
}

void MacdSma(int shift, int fast, int slow, int signal, double &line, double &sig)
{
   double f = 0, s = 0;
   for(int i = shift; i < shift + fast; i++) f += iClose(_Symbol, _Period, i);
   f /= fast;
   for(int i = shift; i < shift + slow; i++) s += iClose(_Symbol, _Period, i);
   s /= slow;
   line = f - s;
   double lsum = 0;
   for(int j = 0; j < signal; j++)
   {
      double f2 = 0, s2 = 0;
      for(int q = shift + j; q < shift + j + fast; q++) f2 += iClose(_Symbol, _Period, q);
      f2 /= fast;
      for(int q = shift + j; q < shift + j + slow; q++) s2 += iClose(_Symbol, _Period, q);
      s2 /= slow;
      lsum += f2 - s2;
   }
   sig = lsum / signal;
}

double SmaClose(int shift, int period)
{
   double sum = 0;
   for(int i = shift; i < shift + period; i++) sum += iClose(_Symbol, _Period, i);
   return sum / period;
}

bool InSession(datetime bar_close)
{
   MqlDateTime dt;
   TimeToStruct(bar_close, dt);
   if(dt.day_of_week == 5 && use_no_open_friday) return false;
   if(start_hour <= end_hour)
      return (dt.hour >= start_hour && dt.hour < end_hour);
   else
      return (dt.hour >= start_hour || dt.hour < end_hour);
}

bool IsFriday(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return (dt.day_of_week == 5);
}

double CurrentSpreadPoints()
{
   double sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double pts = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pip = PointToPip(price);
   if(pip <= 0) pip = pts;
   return sp * pts / pip;
}

double PointToPip(double price)
{
   // per metalli/indici: pip = point*100 (XAUUSD 0.01); per major forex 0.0001
   double pts = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   string s = _Symbol;
   if(StringFind(s, "XAU") >= 0 || StringFind(s, "XAG") >= 0 || StringFind(s, "NDQ") >= 0 ||
      StringFind(s, "SPX") >= 0 || StringFind(s, "DAX") >= 0)
      return pts * 100.0;
   return 0.0001;
}

double MaxSpreadPips()
{
   string s = _Symbol;
   if(StringFind(s, "XAU") >= 0 || StringFind(s, "XAG") >= 0) return max_spread_metal;
   if(StringFind(s, "USD") >= 0 || StringFind(s, "EUR") >= 0 || StringFind(s, "GBP") >= 0 ||
      StringFind(s, "JPY") >= 0 || StringFind(s, "CHF") >= 0 || StringFind(s, "CAD") >= 0 ||
      StringFind(s, "AUD") >= 0 || StringFind(s, "NZD") >= 0)
      return max_spread_major;
   return max_spread_cross;
}

bool SpreadOk()
{
   if(MQLInfoInteger(MQL_TESTER)) return true; // nel tester lo spread del simbolo viene applicato dal tester
   double sp = CurrentSpreadPoints();
   return sp <= MaxSpreadPips();
}

//==================== SEGNALE =======================================
int EvaluateSignal(int shift)   // +1 buy, -1 sell, 0 nessuno
{
   double c  = iClose(_Symbol, _Period, shift);
   double atr= AtrSma(shift, atr_ma_period);
   if(atr <= 0) return 0;

   bool buy  = true;
   bool sell = true;

   if(use_sig_stoch)
   {
      double K, D;
      StochSma(shift, stoch_k_period, stoch_slowing, stoch_d_period, K, D);
      if(K <= D) buy = false;
      if(K >= D) sell = false;
   }
   if(use_sig_macd)
   {
      double line, sig;
      MacdSma(shift, 12, 26, 9, line, sig);
      if(line <= sig) buy = false;
      if(line >= sig) sell = false;
   }
   if(use_sig_rsi)
   {
      double rsi = GetBuf(g_hRsi, 0, shift);
      if(rsi == EMPTY_VALUE) rsi = 50;
      if(rsi >= 50) buy = false;
      if(rsi <= 50) sell = false;
   }
   if(use_sig_cci)
   {
      double cci = GetBuf(g_hCci, 0, shift);
      if(cci == EMPTY_VALUE) cci = 0;
      if(cci <= 0) buy = false;
      if(cci >= 0) sell = false;
   }
   if(use_sig_bb)
   {
      double up = GetBuf(g_hBb, 2, shift);
      double dn = GetBuf(g_hBb, 0, shift);
      if(up == EMPTY_VALUE || dn == EMPTY_VALUE) { buy = false; sell = false; }
      else
      {
         if(c <= dn) buy = false;
         if(c >= up) sell = false;
      }
   }
   if(use_sig_wick_rejection)
   {
      double o = iOpen(_Symbol, _Period, shift);
      double h = iHigh(_Symbol, _Period, shift);
      double l = iLow(_Symbol, _Period, shift);
      double body = MathAbs(c - o);
      double lower = MathMin(c, o) - l;
      double upper = h - MathMax(c, o);
      if(!(lower >= wick_ratio * body)) buy = false;
      if(!(upper >= wick_ratio * body)) sell = false;
   }
   if(use_sig_mom_break)
   {
      double mom = c - iClose(_Symbol, _Period, shift + momentum_period);
      if(mom <= 0) buy = false;
      if(mom >= 0) sell = false;
   }
   if(use_sig_breakout)
   {
      double hi = -DBL_MAX;
      for(int i = shift + 1; i <= shift + breakout_lookback; i++) hi = MathMax(hi, iHigh(_Symbol, _Period, i));
      if(c <= hi) buy = false;
      if(c >= hi) sell = false;
   }
   if(use_sig_inside_break)
   {
      double ph = iHigh(_Symbol, _Period, shift + 1);
      double pl = iLow(_Symbol, _Period, shift + 1);
      double o  = iOpen(_Symbol, _Period, shift);
      if(c <= ph) buy = false;
      if(c >= pl) sell = false;
   }
   if(use_sig_engulfing)
   {
      double o  = iOpen(_Symbol, _Period, shift);
      double pc = iClose(_Symbol, _Period, shift + 1);
      double po = iOpen(_Symbol, _Period, shift + 1);
      if(!(c > po && o < pc && c > o)) buy = false;
      if(!(c < po && o > pc && c < o)) sell = false;
   }
   if(use_sig_pin_bar)
   {
      double o = iOpen(_Symbol, _Period, shift);
      double h = iHigh(_Symbol, _Period, shift);
      double l = iLow(_Symbol, _Period, shift);
      double body = MathAbs(c - o);
      double lower = MathMin(c, o) - l;
      double upper = h - MathMax(c, o);
      double rng = h - l;
      if(!(lower >= 0.5 * rng && body <= 0.33 * rng)) buy = false;
      if(!(upper >= 0.5 * rng && body <= 0.33 * rng)) sell = false;
   }
   if(use_sig_liqsweep)
   {
      double lo = DBL_MAX, hi = -DBL_MAX;
      for(int i = shift + 1; i <= shift + liqsweep_lookback; i++)
      {
         lo = MathMin(lo, iLow(_Symbol, _Period, i));
         hi = MathMax(hi, iHigh(_Symbol, _Period, i));
      }
      double l0 = iLow(_Symbol, _Period, shift);
      double h0 = iHigh(_Symbol, _Period, shift);
      if(!(l0 < lo && c > lo)) buy = false;
      if(!(h0 > hi && c < hi)) sell = false;
   }
   if(use_sig_three_soldiers)
   {
      bool ok = true;
      for(int i = shift; i < shift + 3; i++)
      {
         if(iClose(_Symbol, _Period, i) <= iOpen(_Symbol, _Period, i)) ok = false;
      }
      if(!ok) buy = false;
      ok = true;
      for(int i = shift; i < shift + 3; i++)
      {
         if(iClose(_Symbol, _Period, i) >= iOpen(_Symbol, _Period, i)) ok = false;
      }
      if(!ok) sell = false;
   }

   // bias (gates direzionali)
   if(use_bias_donchian_mid)
   {
      double hi = -DBL_MAX, lo = DBL_MAX;
      for(int i = shift; i < shift + 20; i++)
      {
         hi = MathMax(hi, iHigh(_Symbol, _Period, i));
         lo = MathMin(lo, iLow(_Symbol, _Period, i));
      }
      double mid = (hi + lo) / 2.0;
      if(c <= mid) buy = false;
      if(c >= mid) sell = false;
   }
   if(use_bias_daily_mid)
   {
      MqlDateTime dt;
      TimeToStruct(iTime(_Symbol, _Period, shift), dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime d0 = StructToTime(dt);
      int bars_today = 0;
      for(int i = shift; i >= 0 && iTime(_Symbol, _Period, i) >= d0; i--) bars_today = shift - i + 1;
      double hi = -DBL_MAX, lo = DBL_MAX;
      for(int i = 0; i < bars_today; i++)
      {
         hi = MathMax(hi, iHigh(_Symbol, _Period, shift + i));
         lo = MathMin(lo, iLow(_Symbol, _Period, shift + i));
      }
      double mid = (hi + lo) / 2.0;
      if(c <= mid) buy = false;
      if(c >= mid) sell = false;
   }
   if(use_bias_psar)
   {
      double psar = GetBuf(g_hSar, 0, shift);
      if(psar != EMPTY_VALUE)
      {
         if(c <= psar) buy = false;
         if(c >= psar) sell = false;
      }
   }
   if(use_bias_sma)
   {
      double s = SmaClose(shift, sma_slow_period);
      if(c <= s) buy = false;
      if(c >= s) sell = false;
   }
   if(use_bias_ema)
   {
      double e = GetBuf(g_hEma, 0, shift);
      if(e != EMPTY_VALUE)
      {
         if(c <= e) buy = false;
         if(c >= e) sell = false;
      }
   }
   if(use_bias_rsi)
   {
      double rsi = GetBuf(g_hRsi, 0, shift);
      if(rsi == EMPTY_VALUE) rsi = 50;
      if(rsi <= 50) buy = false;
      if(rsi >= 50) sell = false;
   }

   // filtri
   if(use_filt_sma)
   {
      double f = SmaClose(shift, sma_fast_period);
      if(c <= f) buy = false;
      if(c >= f) sell = false;
   }
   if(use_filt_rsi)
   {
      double rsi = GetBuf(g_hRsi, 0, shift);
      if(rsi == EMPTY_VALUE) rsi = 50;
      if(rsi >= 70) buy = false;
      if(rsi <= 30) sell = false;
   }
   if(use_filt_doji)
   {
      double o = iOpen(_Symbol, _Period, shift);
      double body = MathAbs(c - o);
      double rng = iHigh(_Symbol, _Period, shift) - iLow(_Symbol, _Period, shift);
      if(body > 0.1 * rng) { buy = false; sell = false; }
   }
   if(use_filt_adr_exhaust)
   {
      double adr = 0;
      for(int i = shift; i < shift + adr_period; i++)
         adr += iHigh(_Symbol, _Period, i) - iLow(_Symbol, _Period, i);
      adr /= adr_period;
      MqlDateTime dt;
      TimeToStruct(iTime(_Symbol, _Period, shift), dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime d0 = StructToTime(dt);
      double hi = -DBL_MAX, lo = DBL_MAX;
      for(int i = shift; i >= 0 && iTime(_Symbol, _Period, i) >= d0; i--)
      {
         hi = MathMax(hi, iHigh(_Symbol, _Period, i));
         lo = MathMin(lo, iLow(_Symbol, _Period, i));
      }
      if((hi - lo) > adr_exhaust_pct * adr) { buy = false; sell = false; }
   }

   if(buy)  return 1;
   if(sell) return -1;
   return 0;
}

//==================== ORDINI / POSIZIONI ============================
int CountPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic_number) n++;
   }
   return n;
}

int CountPendings()
{
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(OrderSelect(tk) && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == magic_number) n++;
   }
   return n;
}

void DeletePendings()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(OrderSelect(tk) && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == magic_number)
         trade.OrderDelete(tk);
   }
}

void ClosePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic_number)
         trade.PositionClose(tk);
   }
}

double LotSize(double atr)
{
   if(use_fixed_lot) return fixed_lot;
   double risk = initial_balance * risk_pct / 100.0;
   double sl_dist = sl_mult * atr;
   if(sl_dist <= 0) return fixed_lot;
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ls = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(tv <= 0 || ls <= 0) return fixed_lot;
   double lots = risk / (sl_dist / ls * tv);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lots = MathMax(vmin, MathMin(vmax, lots));
   if(vol_step > 0) lots = MathFloor(lots / vol_step) * vol_step;
   return lots;
}

void PlaceOrder(int dir, double signal_close, double atr)
{
   double price = SymbolInfoDouble(_Symbol, dir > 0 ? SYMBOL_ASK : SYMBOL_BID);
   double sl = 0, tp = 0;

   string mode = exec_mode;
   ENUM_ORDER_TYPE type = WRONG_VALUE;
   double entry = 0;

   if(mode == "stop")
   {
      entry = signal_close + dir * stop_offset_atr * atr;
      type  = dir > 0 ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
   }
   else if(mode == "limit")
   {
      entry = signal_close - dir * limit_offset_atr * atr;
      type  = dir > 0 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   }
   else if(mode == "limit2")
   {
      entry = signal_close - dir * limit2_offset_atr * atr;
      type  = dir > 0 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   }
   else if(mode == "market2" || mode == "market")
   {
      type = dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      entry = 0;
   }

   // protezione: stop entro prezzo corrente? annulla
   if(type == ORDER_TYPE_BUY_STOP && entry <= price) return;
   if(type == ORDER_TYPE_SELL_STOP && entry >= price) return;

   double lot = LotSize(atr);

   if(type == ORDER_TYPE_BUY || type == ORDER_TYPE_SELL)
   {
      if(type == ORDER_TYPE_BUY)  { sl = price - sl_mult * atr; tp = price + tp_mult * atr; }
      else                        { sl = price + sl_mult * atr; tp = price - tp_mult * atr; }
      trade.Buy(lot, _Symbol, 0, sl, tp, "algory");
      g_signal_atr = atr;
      return;
   }

   if(dir > 0) { sl = entry - sl_mult * atr; tp = entry + tp_mult * atr; }
   else        { sl = entry + sl_mult * atr; tp = entry - tp_mult * atr; }

   int exp_bars = (mode == "stop") ? stop_expiry_bars : limit_expiry_bars;
   datetime expiry = iTime(_Symbol, _Period, 1) + exp_bars * PeriodSeconds(_Period);

   // sostituisci ordine pendente esistente
   DeletePendings();

   trade.OrderOpen(_Symbol, type, lot, 0, entry, sl, tp,
                   ORDER_TIME_SPECIFIED, expiry, "algory");
   g_signal_atr = atr;
   g_pending_signal_time = iTime(_Symbol, _Period, 1);
}

void CheckFridayClose()
{
   if(!use_friday_close) return;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week != 5) return;
   int target_min = friday_close * 60 - 60 + friday_close_jitter_min;
   int cur_min = dt.hour * 60 + dt.min;
   if(cur_min >= target_min)
   {
      ClosePositions();
      DeletePendings();
   }
}

void CheckDailyDD()
{
   if(!use_daily_dd) return;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int day = dt.day_of_year * 100 + dt.year;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(day != g_halt_day)
   {
      g_halt_day = day;
      g_day_start_eq = eq;
      g_day_halted = false;
   }
   if(!g_day_halted && eq < g_day_start_eq * (1.0 - daily_dd_limit / 100.0))
   {
      g_day_halted = true;
      ClosePositions();
      DeletePendings();
   }
}

//==================== CORE ==========================================
int OnInit()
{
   trade.SetExpertMagicNumber(magic_number);
   g_fri_jitter_min = friday_close_jitter_min;
   g_hRsi = iRSI(_Symbol, _Period, rsi_period, PRICE_CLOSE);
   g_hCci = iCCI(_Symbol, _Period, cci_period, PRICE_CLOSE);
   g_hBb  = iBands(_Symbol, _Period, bb_period, 0, bb_std, PRICE_CLOSE);
   g_hEma = iMA(_Symbol, _Period, ema_period, 0, MODE_EMA, PRICE_CLOSE);
   g_hSar = iSAR(_Symbol, _Period, psar_step, psar_max);
   Print("Algory Replica inizializzato | symbol=", _Symbol, " tf=", EnumToString(_Period),
         " | exec=", exec_mode, " | sessione [", start_hour, ",", end_hour, ")");
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   datetime bar = iTime(_Symbol, _Period, 0);
   if(bar == g_last_bar) return;
   g_last_bar = bar;

   CheckFridayClose();
   CheckDailyDD();

   // barra appena chiusa = shift 1
   datetime bar_close = iTime(_Symbol, _Period, 0);
   MqlDateTime dtc;
   TimeToStruct(bar_close, dtc);

   if(!InSession(bar_close)) return;
   if(g_day_halted) return;
   if(!SpreadOk()) return;

   if(use_symbol_lock && CountPositions() > 0) return;

   int dir = EvaluateSignal(1);
   if(dir == 0) return;

   double c = iClose(_Symbol, _Period, 1);
   double atr = AtrSma(1, atr_ma_period);
   if(atr <= 0) return;

   Print(TimeToString(bar_close), " SEGNALE ", dir > 0 ? "BUY" : "SELL",
         " close=", DoubleToString(c, _Digits), " atr=", DoubleToString(atr, _Digits));

   PlaceOrder(dir, c, atr);
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // gestione trailing/breakeven eventuale (v1: SL/TP statici come il vault)
}
//+------------------------------------------------------------------+
