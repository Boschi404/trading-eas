//+------------------------------------------------------------------+
//|                                            EdgePointScalper.mq5  |
//| Reconstructed from: ScalpingGengar (original) + log analysis      |
//| Clone of NovaScalper — open-source with all parameters exposed   |
//| Hermes Agent — Reverse Engineering                               |
//+------------------------------------------------------------------+
#property copyright "Hermes Agent — NovaScalper Reconstruction"
#property version   "1.00"
#property description "EdgePointScalper: Breakout of N-bar high/low on H1"
#property description "Reconstructed from NovaScalper backtest analysis + ScalpingGengar source"
#include <Trade\Trade.mqh>

// ===================== STRATEGY =====================
input group "=== STRATEGY ==="
input int      InpBarsN          = 12;      // NovaScalper: 12       // Lookback bars for high/low channel
input int      InpEntryDist_Pts  = 555;     // NovaScalper: 555      // Distance from high/low for pending order (pts)
input int      InpExpiryBars     = 612;     // NovaScalper: 153h on M15 = 612 bars     // Pending order expiration (bars, 0=GTC)
input ENUM_TIMEFRAMES InpTF      = PERIOD_M15;  // NovaScalper: PERIOD_M15

// ===================== TP / SL =====================
input group "=== TARGET & STOP ==="
input bool     InpUseATR         = false;   // Match NovaScalper: fixed-point TP/SL    // ATR-based TP/SL (true) or fixed points (false)
input int      InpATR_Period     = 14;
input double   InpATR_SL_Scalp   = 0.3;     // NovaScalper-style tight     // SL = ATR × this (scalp mode, tight)
input double   InpATR_TP_Scalp   = 0.6;     // NovaScalper: ~2× SL     // TP = ATR × this (scalp mode, symmetric 1:1)
input double   InpATR_SL_Trend   = 1.5;     // SL = ATR × this (trend mode)
input double   InpATR_TP_Trend   = 3.0;     // TP = ATR × this (trend mode, 1:2 R:R)
input int      InpFixedSL_Pts    = 915;     // NovaScalper: 915     // Fixed SL in points (if !UseATR)
input int      InpFixedTP_Pts    = 1870;    // NovaScalper: 1870 (2×SL!)     // Fixed TP in points (if !UseATR)

// --- v1.1 Mode Switch ---
input group "=== MODE SWITCH ==="
input bool     InpUseADX_Mode    = false;   // NovaScalper: no ADX    // Use ADX to switch scalp/trend mode
input int      InpADX_Period     = 14;
input double   InpADX_TrendMin   = 25.0;    // ADX above this → trend mode

// --- Trend Direction Filter ---
input group "=== TREND DIRECTION ==="
input bool     InpUseTrendDir    = true;    // NovaScalper: trend filter ON (from Gengar)    // Only trade in trend direction (EMA filter)
input int      InpTrendMA_Period = 50;      // NovaScalper: EMA50 H4      // MA period for trend direction
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H4; // Trend timeframe (higher TF) (wider TP/SL)
                                              // ADX below this → scalp mode (tight TP/SL)

// ===================== TRAILING STOP =====================
input group "=== TRAILING STOP ==="
input bool     InpUseTrail       = true;    // NovaScalper: trailing ON    // Enable trailing stop
input int      InpTrailTrigger   = 45;      // NovaScalper: 45      // Price must move this many pts in favor to activate
input int      InpTrailStep      = 45;      // NovaScalper: 45      // Trail SL by this many pts

// ===================== RISK =====================
input group "=== RISK MANAGEMENT ==="
input bool     InpUseRiskPct     = true;
input double   InpRiskPct        = 2.0;     // NovaScalper/Gengar: 2%     // % of equity per trade (~matches NovaScalper 0.08lot/€100)
input double   InpFixedLot       = 0.01;
input double   InpMaxLot         = 1.0;
input double   InpMaxDD_Pct      = 30.0;
input int      InpMagic          = 20240501;

// ===================== FILTERS =====================
input group "=== FILTERS ==="
input int      InpMaxSpread_Pts  = 50;
input bool     InpOneTrade       = true;    // Max 1 position at a time
input bool     InpUseSession     = false;   // Session filter (OFF = match NovaScalper behavior)
input int      InpSessionStart   = 0;
input int      InpSessionEnd     = 24;

// ===================== GLOBALS =====================
CTrade trade;
datetime g_lastBarTime = 0;
double   g_startBalance = 0;
int      g_atrHandle = INVALID_HANDLE;
int      g_adxHandle = INVALID_HANDLE;
int      g_trendMAHandle = INVALID_HANDLE;
ulong    g_pendingBuy = 0, g_pendingSell = 0;

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
   return NormalizeLot((riskMoney * ts) / (slDist * tv));
}

bool DD_OK() {
   if(g_startBalance <= 0) g_startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   return ((g_startBalance - eq) / g_startBalance * 100.0) < InpMaxDD_Pct;
}

void DeletePending() {
   if(g_pendingBuy > 0)  { trade.OrderDelete(g_pendingBuy);  g_pendingBuy = 0; }
   if(g_pendingSell > 0) { trade.OrderDelete(g_pendingSell); g_pendingSell = 0; }
}

void InitIndicators() {
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_adxHandle != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   if(g_trendMAHandle != INVALID_HANDLE) IndicatorRelease(g_trendMAHandle);
   g_atrHandle = iATR(_Symbol, InpTF, InpATR_Period);
   if(InpUseADX_Mode) g_adxHandle = iADX(_Symbol, InpTF, InpADX_Period);
   if(InpUseTrendDir) g_trendMAHandle = iMA(_Symbol, InpTrendTF, InpTrendMA_Period, 0, MODE_EMA, PRICE_CLOSE);
}

double GetATR() {
   if(g_atrHandle == INVALID_HANDLE) return 0;
   double buf[]; ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_atrHandle, 0, 1, 1, buf) > 0) return buf[0];
   return 0;
}

double GetADX() {
   if(g_adxHandle == INVALID_HANDLE) return 0;
   double buf[]; ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_adxHandle, 0, 1, 1, buf) > 0) return buf[0];
   return 0;
}

double GetTrendMA() {
   if(g_trendMAHandle == INVALID_HANDLE) return 0;
   double buf[]; ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_trendMAHandle, 0, 1, 1, buf) > 0) return buf[0];
   return 0;
}

// Find highest high over last N completed bars
double FindHigh(int bars) {
   double h = -1;
   for(int i = 1; i <= bars; i++) {
      double hi = iHigh(_Symbol, InpTF, i);
      if(hi > h) h = hi;
   }
   return h;
}

// Find lowest low over last N completed bars
double FindLow(int bars) {
   double l = DBL_MAX;
   for(int i = 1; i <= bars; i++) {
      double lo = iLow(_Symbol, InpTF, i);
      if(lo < l) l = lo;
   }
   return (l == DBL_MAX) ? 0 : l;
}

bool IsSessionOk() {
   if(!InpUseSession) return true;
   MqlDateTime dt;
   TimeToStruct(iTime(_Symbol, InpTF, 0), dt);
   return (dt.hour >= InpSessionStart && dt.hour < InpSessionEnd);
}

// ===================== TRAILING =====================
void ManageTrailing() {
   if(!InpUseTrail) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      
      double entry   = PositionGetDouble(POSITION_PRICE_OPEN);
      double currSL   = PositionGetDouble(POSITION_SL);
      double currTP   = PositionGetDouble(POSITION_TP);
      bool   isBuy    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double price    = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double trailTrigger = InpTrailTrigger * _Point;
      double trailStep    = InpTrailStep * _Point;
      
      if(isBuy) {
         double newSL = price - trailStep;
         if(price - entry >= trailTrigger && newSL > currSL) {
            trade.PositionModify(ticket, newSL, currTP);
         }
      } else {
         double newSL = price + trailStep;
         if(entry - price >= trailTrigger && (newSL < currSL || currSL == 0)) {
            trade.PositionModify(ticket, newSL, currTP);
         }
      }
   }
}

// ===================== INIT =====================
int OnInit() {
   trade.SetExpertMagicNumber(InpMagic);
   g_startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_lastBarTime = 0;
   InitIndicators();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   DeletePending();
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_adxHandle != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   if(g_trendMAHandle != INVALID_HANDLE) IndicatorRelease(g_trendMAHandle);
}

// ===================== TICK =====================
void OnTick() {
   // --- Trailing stop on every tick ---
   ManageTrailing();
   
   // --- Delete expired pending orders ---
   if(g_pendingBuy > 0 || g_pendingSell > 0) {
      datetime barTime = iTime(_Symbol, InpTF, 0);
      if(barTime != g_lastBarTime && g_lastBarTime > 0) {
         DeletePending();
      }
   }

   // --- Bar detection ---
   datetime currentBar = iTime(_Symbol, InpTF, 0);
   if(currentBar == g_lastBarTime) return;
   if(g_lastBarTime == 0) { g_lastBarTime = currentBar; InitIndicators(); return; }
   g_lastBarTime = currentBar;

   // --- Guards ---
   if(!DD_OK()) return;
   if(InpOneTrade && PositionsTotal() > 0) return;
   DeletePending();

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if((ask - bid) / _Point > InpMaxSpread_Pts) return;
   if(!IsSessionOk()) return;

   // --- Find channel levels ---
   double highN = FindHigh(InpBarsN);
   double lowN  = FindLow(InpBarsN);
   if(highN <= 0 || lowN <= 0) return;
   
   // Price proximity: only place orders when price is reasonably near the channel
   // (NovaScalper doesn't have this restriction — removed to match behavior)

   // --- ATR & ADX ---
   double atr = GetATR();
   double adx = InpUseADX_Mode ? GetADX() : 0;

   // --- Choose TP/SL mode ---
   double slMult, tpMult;
   if(InpUseADX_Mode && adx >= InpADX_TrendMin) {
      slMult = InpATR_SL_Trend;
      tpMult = InpATR_TP_Trend;
   } else {
      slMult = InpATR_SL_Scalp;
      tpMult = InpATR_TP_Scalp;
   }

   double slDist, tpDist;
   if(InpUseATR && atr > 0) {
      slDist = atr * slMult;
      tpDist = atr * tpMult;
   } else {
      slDist = PtsToPrice(InpFixedSL_Pts);
      tpDist = PtsToPrice(InpFixedTP_Pts);
   }

   // --- Trend direction filter ---
   bool allowBuy = true, allowSell = true;
   if(InpUseTrendDir) {
      double trendMA = GetTrendMA();
      if(trendMA > 0) {
         double trendClose = iClose(_Symbol, InpTrendTF, 0);
         allowBuy  = (trendClose > trendMA);
         allowSell = (trendClose < trendMA);
      }
   }
   
   // --- Place pending orders ---
   double entryDist = InpEntryDist_Pts * _Point;
   datetime expiry = (InpExpiryBars > 0) ? iTime(_Symbol, InpTF, 0) + InpExpiryBars * PeriodSeconds(InpTF) : 0;

   // BUY STOP above N-bar high (only if uptrend)
   double buyEntry = highN + entryDist;
   double buySL    = buyEntry - slDist;
   double buyTP    = buyEntry + tpDist;
   
   double lotBuy;
   if(InpUseRiskPct) lotBuy = CalcLotByRisk(buySL, buyEntry);
   else lotBuy = NormalizeLot(InpFixedLot);
   
   if(allowBuy && lotBuy >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
      trade.BuyStop(lotBuy, buyEntry, _Symbol, buySL, buyTP, 
                    InpExpiryBars > 0 ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC, 
                    expiry, "EPScalper_B");
   }

   // SELL STOP below N-bar low (only if downtrend) (only if downtrend)
   double sellEntry = lowN - entryDist;
   double sellSL    = sellEntry + slDist;
   double sellTP    = sellEntry - tpDist;
   
   double lotSell;
   if(InpUseRiskPct) lotSell = CalcLotByRisk(sellSL, sellEntry);
   else lotSell = NormalizeLot(InpFixedLot);
   
   if(allowSell && lotSell >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
      trade.SellStop(lotSell, sellEntry, _Symbol, sellSL, sellTP,
                     InpExpiryBars > 0 ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC,
                     expiry, "EPScalper_S");
   }
}
