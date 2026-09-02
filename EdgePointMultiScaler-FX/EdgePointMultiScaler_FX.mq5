//+------------------------------------------------------------------+
//|                               EdgePointMultiScaler_FX.mq5        |
//| v4.0 — Mitigated: ADX filter + Loss Cooldown + Session Filter    |
//| Based on: EdgePointMultiScaler (Boschi404) + backtest analysis   |
//+------------------------------------------------------------------+
#property copyright "Hermes Agent — v4.0 Mitigated"
#property version   "4.00"
#property description "H4 Candle Breakout — mitigated with ADX, cooldown, session filter"
#include <Trade\Trade.mqh>

// ===================== STRATEGY =====================
input group "=== STRATEGY ==="
input int      InpMinCandlePts   = 150;     // Min candle range (points)
input double   InpMinRecoveryPct = 0.50;    // Close in top/bottom % of candle (0.5=50%)
input ENUM_TIMEFRAMES InpTF      = PERIOD_H4;

// ===================== RISK =====================
input group "=== RISK MANAGEMENT ==="
input bool     InpUseRiskPct     = true;
input double   InpRiskPct        = 0.5;     // % of equity per trade
input double   InpFixedLot       = 0.01;
input double   InpMaxLot         = 1.0;
input double   InpMaxDD_Pct      = 30.0;
input int      InpMagic          = 20240401;

// ===================== TP / SL =====================
input group "=== TARGET & STOP ==="
input bool     InpUseATR         = true;
input int      InpATR_Period     = 14;
input double   InpSL_ATR_Mult    = 1.5;
input double   InpTP1_ATR_Mult   = 2.0;     // TP1 (50% position)
input double   InpTP2_ATR_Mult   = 4.0;     // TP2 (50% position)
input int      InpFixedSL_Pts    = 200;
input int      InpFixedTP_Pts    = 400;
input int      InpSL_Buffer_Pts  = 20;
input int      InpPendingBars    = 1;

// ===================== FILTERS (v4 NEW) =====================
input group "=== FILTERS ==="
input int      InpMaxSpread_Pts  = 50;
input bool     InpUseTrendMA     = true;
input int      InpMA_Period      = 200;
input bool     InpUseMinATR      = true;
input int      InpMinATR_Pts     = 30;
input bool     InpOneTrade       = true;

// --- v4.0: ADX Filter ---
input group "=== v4.0: MOMENTUM FILTER (ADX) ==="
input bool     InpUseADX         = true;    // Enable ADX trend filter
input int      InpADX_Period     = 14;      // ADX lookback
input double   InpADX_Min        = 22.0;    // Minimum ADX for entry (22+ = trending)

// --- v4.0: Loss Cooldown ---
input group "=== v4.0: LOSS PROTECTION ==="
input bool     InpUseCooldown    = true;    // Pause after consecutive losses
input int      InpMaxConsLoss    = 4;       // Max consecutive losses before cooldown
input int      InpCooldownBars   = 2;       // Bars to skip after hitting max cons losses

// --- v4.0: Session Filter ---
input group "=== v4.0: SESSION FILTER ==="
input bool     InpUseSession     = true;    // Only trade during active sessions
input int      InpSessionStart   = 7;       // Trading start hour (UTC, 7=London open)
input int      InpSessionEnd     = 20;      // Trading end hour (UTC, 20=NY close)

// ===================== GLOBALS =====================
CTrade trade;
datetime g_lastBarTime = 0;
double   g_startBalance = 0;
int      g_atrHandle = INVALID_HANDLE;
int      g_maHandle  = INVALID_HANDLE;
int      g_adxHandle = INVALID_HANDLE;
ulong    g_pending1 = 0, g_pending2 = 0;
int      g_consecutiveLosses = 0;
int      g_cooldownBarsLeft = 0;
double   g_lastEquity = 0;
bool     g_hadPosition = false;

// ===================== HELPERS =====================
double PipSize() {
   if((int)_Digits == 5 || (int)_Digits == 3) return _Point * 10.0;
   return _Point;
}
double PtsToPrice(int pts) { return pts * _Point; }

double NormalizeLot(double lot) {
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lot < mn) lot = mn;
   if(lot > mx) lot = mx;
   if(lot > InpMaxLot) lot = InpMaxLot;
   return MathFloor(lot / st) * st;
}

double CalcLotByRisk(double slPrice, double entryPrice) {
   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0;
   double slDist = MathAbs(entryPrice - slPrice);
   if(slDist <= 0) return NormalizeLot(0.01);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0 || tv <= 0) return NormalizeLot(0.01);
   double lot = (riskMoney * ts) / (slDist * tv);
   return NormalizeLot(lot);
}

bool DD_OK() {
   if(g_startBalance <= 0) g_startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   return ((g_startBalance - eq) / g_startBalance * 100.0) < InpMaxDD_Pct;
}

void DeletePending() {
   if(g_pending1 > 0) { trade.OrderDelete(g_pending1); g_pending1 = 0; }
   if(g_pending2 > 0) { trade.OrderDelete(g_pending2); g_pending2 = 0; }
}

void InitIndicators() {
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_maHandle  != INVALID_HANDLE) IndicatorRelease(g_maHandle);
   if(g_adxHandle != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   g_atrHandle = iATR(_Symbol, InpTF, InpATR_Period);
   if(InpUseTrendMA) g_maHandle = iMA(_Symbol, InpTF, InpMA_Period, 0, MODE_SMA, PRICE_CLOSE);
   if(InpUseADX)     g_adxHandle = iADX(_Symbol, InpTF, InpADX_Period);
}

double GetATR() {
   if(g_atrHandle == INVALID_HANDLE) return 0;
   double buf[]; ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_atrHandle, 0, 1, 1, buf) > 0) return buf[0];
   return 0;
}

double GetMA() {
   if(g_maHandle == INVALID_HANDLE) return 0;
   double buf[]; ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_maHandle, 0, 1, 1, buf) > 0) return buf[0];
   return 0;
}

double GetADX() {
   if(g_adxHandle == INVALID_HANDLE) return 0;
   double buf[]; ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_adxHandle, 0, 1, 1, buf) > 0) return buf[0];
   return 0;
}

// --- v4.2: Track consecutive losses via balance comparison (backtest-safe) ---
void UpdateConsecutiveLosses() {
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   bool hasPosition = (PositionsTotal() > 0);
   
   // Detect position close: had position before, none now
   if(g_hadPosition && !hasPosition && g_lastEquity > 0) {
      if(currentEquity < g_lastEquity)
         g_consecutiveLosses++;
      else if(currentEquity > g_lastEquity)
         g_consecutiveLosses = 0; // Win resets counter
      // If equity unchanged (rare), keep counter
   }
   
   // Update state for next bar
   g_hadPosition = hasPosition;
   if(!hasPosition || g_lastEquity == 0)
      g_lastEquity = currentEquity;
}

// --- v4.0: Check if current time is in allowed session ---
bool IsSessionOk() {
   if(!InpUseSession) return true;
   datetime barTime = iTime(_Symbol, InpTF, 0);
   MqlDateTime dt;
   TimeToStruct(barTime, dt);
   int hour = dt.hour;
   if(InpSessionStart <= InpSessionEnd)
      return (hour >= InpSessionStart && hour < InpSessionEnd);
   else  // Overnight session (e.g., 20 to 7)
      return (hour >= InpSessionStart || hour < InpSessionEnd);
}

// ===================== INIT =====================
int OnInit() {
   trade.SetExpertMagicNumber(InpMagic);
   g_startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_lastBarTime = 0;
   g_consecutiveLosses = 0;
   g_cooldownBarsLeft = 0;
   InitIndicators();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   DeletePending();
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_maHandle  != INVALID_HANDLE) IndicatorRelease(g_maHandle);
   if(g_adxHandle != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
}

// ===================== TICK =====================
void OnTick() {
   // --- DELETE EXPIRED PENDING ORDERS ---
   if(g_pending1 > 0 || g_pending2 > 0) {
      datetime barTime = iTime(_Symbol, InpTF, 0);
      if(barTime != g_lastBarTime && g_lastBarTime > 0) {
         DeletePending();
      }
   }

   // --- BAR DETECTION ---
   datetime currentBar = iTime(_Symbol, InpTF, 0);
   if(currentBar == g_lastBarTime) return;
   if(g_lastBarTime == 0) { g_lastBarTime = currentBar; InitIndicators(); return; }
   g_lastBarTime = currentBar;

   // --- v4.0: Update consecutive loss counter ---
   if(InpUseCooldown) UpdateConsecutiveLosses();
   
   // --- v4.0: Cooldown check ---
   if(g_cooldownBarsLeft > 0) {
      g_cooldownBarsLeft--;
      return; // Skip this bar
   }
   if(InpUseCooldown && g_consecutiveLosses >= InpMaxConsLoss) {
      g_cooldownBarsLeft = InpCooldownBars;
      g_consecutiveLosses = 0; // Reset counter
      return; // Start cooldown
   }

   // --- GUARDS ---
   if(!DD_OK()) return;
   if(InpOneTrade && PositionsTotal() > 0) return;
   DeletePending();

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spreadPts = (ask - bid) / _Point;
   if(spreadPts > InpMaxSpread_Pts) return;

   // --- v4.0: Session filter ---
   if(!IsSessionOk()) return;

   // --- CANDLE DATA ---
   MqlRates r[]; ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, InpTF, 1, 1, r) < 1) return;
   double o = r[0].open, h = r[0].high, l = r[0].low, c = r[0].close;
   double range = h - l;
   int candlePts = (int)(range / _Point);

   // --- INDICATORS ---
   double atr = GetATR();
   double atrPts = atr / _Point;

   // --- FILTER: Min candle size ---
   if(candlePts < InpMinCandlePts) return;

   // --- FILTER: Min ATR ---
   if(InpUseMinATR && atr > 0 && atrPts < InpMinATR_Pts) return;

   // --- v4.0: ADX filter ---
   if(InpUseADX) {
      double adx = GetADX();
      if(adx > 0 && adx < InpADX_Min) return; // Skip ranging markets
   }

   // --- FILTER: MA trend ---
   if(InpUseTrendMA) {
      double ma = GetMA();
      if(ma > 0) {
         bool bullTrend = (c > ma);
         bool bearTrend = (c < ma);
         if(!bullTrend && !bearTrend) return;
      }
   }

   // --- SIGNAL ---
   bool bullish = (c > o);
   bool bearish = (c < o);
   if(InpMinRecoveryPct > 0 && range > 0) {
      if(bullish) bullish = ((c - l) / range >= InpMinRecoveryPct);
      if(bearish) bearish = ((h - c) / range >= InpMinRecoveryPct);
   }
   if(!bullish && !bearish) return;

   // --- TP/SL DISTANCES ---
   double slDist, tp1Dist, tp2Dist;
   if(InpUseATR && atr > 0) {
      slDist  = MathMax(atr * InpSL_ATR_Mult, range * 1.0);
      tp1Dist = atr * InpTP1_ATR_Mult;
      tp2Dist = atr * InpTP2_ATR_Mult;
   } else {
      slDist  = PtsToPrice(InpFixedSL_Pts);
      tp1Dist = PtsToPrice(InpFixedTP_Pts);
      tp2Dist = PtsToPrice(InpFixedTP_Pts * 2);
   }

   // --- EXECUTION ---
   double lot;
   if(InpUseRiskPct) {
      double estEntry = bullish ? h : l;
      double estSL = bullish ? l - PtsToPrice(InpSL_Buffer_Pts) : h + PtsToPrice(InpSL_Buffer_Pts);
      if(MathAbs(estEntry - estSL) < slDist) estSL = bullish ? estEntry - slDist : estEntry + slDist;
      lot = CalcLotByRisk(estSL, estEntry);
   } else {
      lot = NormalizeLot(InpFixedLot);
   }

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   datetime expiry = (InpPendingBars > 0) ? iTime(_Symbol, InpTF, 0) + InpPendingBars * PeriodSeconds(InpTF) : 0;
   
   if(bullish) {
      double entry = h + PtsToPrice(5);
      double sl    = l - PtsToPrice(InpSL_Buffer_Pts);
      if(entry - sl < slDist) sl = entry - slDist;
      
      if(lot >= minLot * 2.0) {
         double lot1 = NormalizeLot(lot * 0.5);
         double lot2 = NormalizeLot(lot - lot1);
         trade.BuyStop(lot1, entry, _Symbol, sl, entry + tp1Dist, ORDER_TIME_SPECIFIED, expiry, "EPS_TP1");
         trade.BuyStop(lot2, entry, _Symbol, sl, entry + tp2Dist, ORDER_TIME_SPECIFIED, expiry, "EPS_TP2");
      } else {
         double avgTP = (tp1Dist + tp2Dist) / 2.0;
         trade.BuyStop(lot,  entry, _Symbol, sl, entry + avgTP, ORDER_TIME_SPECIFIED, expiry, "EPS_BUY");
      }
   }
   else if(bearish) {
      double entry = l - PtsToPrice(5);
      double sl    = h + PtsToPrice(InpSL_Buffer_Pts);
      if(sl - entry < slDist) sl = entry + slDist;
      
      if(lot >= minLot * 2.0) {
         double lot1 = NormalizeLot(lot * 0.5);
         double lot2 = NormalizeLot(lot - lot1);
         trade.SellStop(lot1, entry, _Symbol, sl, entry - tp1Dist, ORDER_TIME_SPECIFIED, expiry, "EPS_TP1");
         trade.SellStop(lot2, entry, _Symbol, sl, entry - tp2Dist, ORDER_TIME_SPECIFIED, expiry, "EPS_TP2");
      } else {
         double avgTP = (tp1Dist + tp2Dist) / 2.0;
         trade.SellStop(lot,  entry, _Symbol, sl, entry - avgTP, ORDER_TIME_SPECIFIED, expiry, "EPS_SELL");
      }
   }
}
