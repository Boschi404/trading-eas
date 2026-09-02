//+------------------------------------------------------------------+
//|                                      EdgePointScalper_Tick.mq5  |
//| Ultra-optimized for tick-data backtests (every_tick model)      |
//| Based on NovaScalper reverse-engineering + ScalpingGengar       |
//+------------------------------------------------------------------+
#property copyright "Hermes Agent — Tick-Optimized"
#property version   "5.00"
#property description "NovaScalper clone — optimized for every_tick backtests"
#property description "Key optimizations: bar caching, single indicator, fast OnTick path"
#include <Trade\Trade.mqh>

// ===================== STRATEGY =====================
input group "=== STRATEGY (NovaScalper params) ==="
input int      InpBarsN          = 12;      // Lookback bars for high/low channel
input int      InpEntryDist_Pts  = 555;     // Distance from high/low for pending order
input int      InpExpiryBars     = 612;     // Pending order expiry (bars, 612=153h on M15)
input ENUM_TIMEFRAMES InpTF      = PERIOD_M15;

// ===================== TP / SL =====================
input group "=== TARGET & STOP ==="
input int      InpFixedSL_Pts    = 915;     // SL in points
input int      InpFixedTP_Pts    = 1870;    // TP in points
input int      InpTrailTrigger   = 45;      // Trail trigger (pts)
input int      InpTrailStep      = 45;      // Trail step (pts)

// ===================== RISK =====================
input group "=== RISK MANAGEMENT ==="
input bool     InpUseRiskPct     = true;
input double   InpRiskPct        = 2.0;     // % of equity per trade
input double   InpFixedLot       = 0.01;
input double   InpMaxLot         = 1.0;
input int      InpMaxSpread_Pts  = 3000;    // XAUUSD spread
input int      InpMagic          = 20240501;

// ===================== TREND FILTER =====================
input group "=== TREND FILTER (NovaScalper: EMA50 H4) ==="
input bool     InpUseTrend       = true;
input int      InpTrendMA_Period = 50;
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H4;

// ===================== GLOBALS (minimized) =====================
CTrade         g_trade;
datetime       g_lastBarTime;       // Last processed bar
double         g_cachedHigh;        // Cached N-bar high (updated once per bar)
double         g_cachedLow;         // Cached N-bar low
double         g_slDist;            // Cached SL distance in price
double         g_tpDist;            // Cached TP distance in price
double         g_entryDist;         // Cached entry distance
int            g_trendMA;           // Trend MA handle (only indicator!)
bool           g_ordersPlaced;      // Whether pending orders are active this bar
ulong          g_buyTicket;         // Buy stop ticket
ulong          g_sellTicket;        // Sell stop ticket
double         g_lastTrailPrice;    // Last price when trailing was checked
double         g_trailTriggerDist;  // Trail trigger in price units
double         g_trailStepDist;     // Trail step in price units

// ===================== ULTRA-FAST HELPERS =====================
inline double PtsToPrice(int pts) { return pts * _Point; }

inline double NormLot(double lot) {
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lot < mn) lot = mn;
   if(lot > InpMaxLot) lot = InpMaxLot;
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return MathFloor(lot / st) * st;
}

inline double CalcLotByRisk(double slPrice, double entryPrice) {
   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct * 0.01;
   double slDist = MathAbs(entryPrice - slPrice);
   if(slDist <= 0) return NormLot(0.01);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0 || tv <= 0) return NormLot(0.01);
   return NormLot((riskMoney * ts) / (slDist * tv));
}

// Cache high/low: use CopyRates ONCE instead of N × iHigh/iLow
void CacheChannel() {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpTF, 1, InpBarsN, rates) < InpBarsN) return;
   
   double h = rates[0].high;
   double l = rates[0].low;
   for(int i = 1; i < InpBarsN; i++) {
      if(rates[i].high > h) h = rates[i].high;
      if(rates[i].low  < l) l = rates[i].low;
   }
   g_cachedHigh = h;
   g_cachedLow  = l;
}

// Delete pending orders quickly
void DeletePending() {
   if(g_buyTicket  > 0) { g_trade.OrderDelete(g_buyTicket);  g_buyTicket  = 0; }
   if(g_sellTicket > 0) { g_trade.OrderDelete(g_sellTicket); g_sellTicket = 0; }
   g_ordersPlaced = false;
}

// Trend check: returns 1=bull, -1=bear, 0=neutral
int GetTrendDir() {
   if(!InpUseTrend || g_trendMA == INVALID_HANDLE) return 0;
   double ma[1], close[1];
   if(CopyBuffer(g_trendMA, 0, 0, 1, ma) < 1) return 0;
   close[0] = iClose(_Symbol, InpTrendTF, 0);
   if(close[0] > ma[0]) return 1;
   if(close[0] < ma[0]) return -1;
   return 0;
}

// ===================== INIT (minimal work) =====================
int OnInit() {
   g_trade.SetExpertMagicNumber(InpMagic);
   g_lastBarTime   = 0;
   g_cachedHigh    = 0;
   g_cachedLow     = 0;
   g_ordersPlaced  = false;
   g_buyTicket     = 0;
   g_sellTicket    = 0;
   g_lastTrailPrice = 0;
   
   // Pre-calculate distances (do once, reuse forever)
   g_slDist    = PtsToPrice(InpFixedSL_Pts);
   g_tpDist    = PtsToPrice(InpFixedTP_Pts);
   g_entryDist = PtsToPrice(InpEntryDist_Pts);
   g_trailTriggerDist = PtsToPrice(InpTrailTrigger);
   g_trailStepDist    = PtsToPrice(InpTrailStep);
   
   // Create the ONLY indicator we need (trend MA)
   if(InpUseTrend) {
      g_trendMA = iMA(_Symbol, InpTrendTF, InpTrendMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   }
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   DeletePending();
   if(g_trendMA != INVALID_HANDLE) IndicatorRelease(g_trendMA);
}

// ===================== TICK — ULTRA-FAST PATH =====================
void OnTick() {
   // ── FASTEST POSSIBLE BAR CHECK ──
   static datetime barTime = 0;
   datetime t = iTime(_Symbol, InpTF, 0);  // Series access — cached by MT5
   if(t == barTime) {
      // SAME BAR — only do trailing stop (cheap)
      if(InpTrailTrigger > 0) TrailTick();
      return;
   }
   
   // ── NEW BAR: do ALL the heavy work ──
   barTime = t;
   
   // Cleanup: delete any leftover pending orders
   DeletePending();
   
   // Guard: one trade at a time
   if(PositionsTotal() > 0) return;
   
   // Spread check (only on new bar, cheap)
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if((ask - bid) > PtsToPrice(InpMaxSpread_Pts)) return;
   
   // ── Cache channel levels (one CopyRates call) ──
   CacheChannel();
   if(g_cachedHigh <= 0 || g_cachedLow <= 0) return;
   
   // ── Trend direction ──
   int trend = GetTrendDir();
   
   // ── Place pending orders ──
   datetime expiry = 0;
   if(InpExpiryBars > 0) {
      expiry = t + InpExpiryBars * PeriodSeconds(InpTF);
   }
   
   // Place ONE pending order based on trend direction
   // trend: 1=bull, -1=bear, 0=neutral → skip (no trade)
   if(trend == 1) {
      double buyEntry = g_cachedHigh + g_entryDist;
      double buySL    = buyEntry - g_slDist;
      double buyTP    = buyEntry + g_tpDist;
      
      double lot = InpUseRiskPct ? CalcLotByRisk(buySL, buyEntry) : NormLot(InpFixedLot);
      if(lot >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
         g_trade.BuyStop(lot, buyEntry, _Symbol, buySL, buyTP, 
                         InpExpiryBars > 0 ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC,
                         expiry, "EPS_B");
         g_ordersPlaced = true;
      }
   }
   else if(trend == -1) {
      double sellEntry = g_cachedLow - g_entryDist;
      double sellSL    = sellEntry + g_slDist;
      double sellTP    = sellEntry - g_tpDist;
      
      double lot = InpUseRiskPct ? CalcLotByRisk(sellSL, sellEntry) : NormLot(InpFixedLot);
      if(lot >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
         g_trade.SellStop(lot, sellEntry, _Symbol, sellSL, sellTP,
                          InpExpiryBars > 0 ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC,
                          expiry, "EPS_S");
         g_ordersPlaced = true;
      }
   }
   // trend==0: neutral — skip bar entirely
}

// ===================== TRAILING (on-tick, ultra-slim) =====================
void TrailTick() {
   if(InpTrailTrigger <= 0) return;
   if(PositionsTotal() == 0) return;
   
   // Rate-limit: only check trailing every ~10 price points to save CPU
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(MathAbs(bid - g_lastTrailPrice) < PtsToPrice(10)) return;
   g_lastTrailPrice = bid;
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      bool   isBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double currSL = PositionGetDouble(POSITION_SL);
      double currTP = PositionGetDouble(POSITION_TP);
      double price  = isBuy ? bid : ask;
      
      double move = isBuy ? (price - entry) : (entry - price);
      if(move < g_trailTriggerDist) continue;  // Not triggered yet
      
      double newSL = isBuy ? (price - g_trailStepDist) : (price + g_trailStepDist);
      
      if((isBuy && newSL > currSL) || (!isBuy && (newSL < currSL || currSL == 0))) {
         g_trade.PositionModify(ticket, newSL, currTP);
      }
   }
}
