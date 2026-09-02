//+------------------------------------------------------------------+
//|                                  EdgePointScalper_Tick_Ultra.mq5 |
//| Ultra-optimized for tick-data backtests with Extended Checks     |
//+------------------------------------------------------------------+
#property copyright "Hermes Agent — Tick-Optimized & Secured"
#property version   "5.02"
#property description "NovaScalper clone — Max Speed + Extended Safety Checks"
#include <Trade\Trade.mqh>

// ===================== STRATEGY =====================
input group "=== STRATEGY (NovaScalper params) ==="
input int             InpBarsN          = 12;      // Lookback bars for high/low channel
input int             InpEntryDist_Pts  = 555;     // Distance from high/low for pending order
input int             InpExpiryBars     = 612;     // Pending order expiry (bars)
input ENUM_TIMEFRAMES InpTF             = PERIOD_M15;

// ===================== TP / SL =====================
input group "=== TARGET & STOP ==="
input int             InpFixedSL_Pts    = 915;     // SL in points
input int             InpFixedTP_Pts    = 1870;    // TP in points
input int             InpTrailTrigger   = 45;      // Trail trigger (pts)
input int             InpTrailStep      = 45;      // Trail step (pts)

// ===================== RISK =====================
input group "=== RISK MANAGEMENT ==="
input bool            InpUseRiskPct     = true;
input double          InpRiskPct        = 2.0;     // % of equity per trade
input double          InpFixedLot       = 0.01;
input double          InpMaxLot         = 1.0;
input int             InpMaxSpread_Pts  = 3000;    // XAUUSD spread
input int             InpMagic          = 20240501;

// ===================== TREND FILTER =====================
input group "=== TREND FILTER ==="
input bool            InpUseTrend       = true;
input int             InpTrendMA_Period = 50;
input ENUM_TIMEFRAMES InpTrendTF        = PERIOD_H4;

// ===================== GLOBALS =====================
CTrade           g_trade;
datetime         g_lastBarTime;
double           g_cachedHigh, g_cachedLow;
ulong            g_buyTicket, g_sellTicket;
int              g_trendMA;

// --- Cached Distances ---
double           g_slDist, g_tpDist, g_entryDist;
double           g_trailTriggerDist, g_trailStepDist, g_minTrailStepPrice, g_maxSpreadPrice;

// --- Cached Symbol Specs (Massive Speed Boost) ---
double           g_volMin, g_volMax, g_volStep;
double           g_tickSize, g_tickValue, g_point;
double           g_stopsLevelPrice; // Broker min distance

// ===================== HELPERS =====================
inline double NormLot(double lot) {
   if(lot < g_volMin) lot = g_volMin;
   if(lot > InpMaxLot) lot = InpMaxLot;
   if(lot > g_volMax) lot = g_volMax;
   return MathFloor(lot / g_volStep) * g_volStep;
}

inline double CalcLotByRisk(double slPrice, double entryPrice) {
   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct * 0.01;
   double slDist = MathAbs(entryPrice - slPrice);
   if(slDist <= 0 || g_tickSize <= 0 || g_tickValue <= 0) return NormLot(0.01);
   return NormLot((riskMoney * g_tickSize) / (slDist * g_tickValue));
}

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

void DeletePending() {
   if(g_buyTicket > 0) {
      if(OrderSelect(g_buyTicket)) g_trade.OrderDelete(g_buyTicket);
      g_buyTicket = 0;
   }
   if(g_sellTicket > 0) {
      if(OrderSelect(g_sellTicket)) g_trade.OrderDelete(g_sellTicket);
      g_sellTicket = 0;
   }
   
   // Safety check for leftover orders
   int orders = OrdersTotal();
   if(orders > 0) {
      for(int i = orders - 1; i >= 0; i--) {
         ulong ticket = OrderGetTicket(i);
         if(OrderGetInteger(ORDER_MAGIC) == InpMagic && OrderGetString(ORDER_SYMBOL) == _Symbol) {
            g_trade.OrderDelete(ticket);
         }
      }
   }
}

int GetTrendDir() {
   if(!InpUseTrend || g_trendMA == INVALID_HANDLE) return 0;
   double ma[1];
   if(CopyBuffer(g_trendMA, 0, 0, 1, ma) < 1) return 0;
   double close = iClose(_Symbol, InpTrendTF, 0);
   if(close > ma[0]) return 1;
   if(close < ma[0]) return -1;
   return 0;
}

// ===================== INIT =====================
int OnInit() {
   // Extended Check: Terminal & Account
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) {
      Print("Error: AutoTrading is disabled!");
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_lastBarTime = 0;
   g_buyTicket = 0; g_sellTicket = 0;
   
   // Cache Symbol Specs for ultra-fast calculation
   g_point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_volMin    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_volMax    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_volStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   // StopsLevel check (safeguard for pending orders)
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_stopsLevelPrice = stopsLevel * g_point;
   
   // Pre-calculate fixed distances safely
   g_slDist           = MathMax(InpFixedSL_Pts * g_point, g_stopsLevelPrice);
   g_tpDist           = MathMax(InpFixedTP_Pts * g_point, g_stopsLevelPrice);
   g_entryDist        = MathMax(InpEntryDist_Pts * g_point, g_stopsLevelPrice);
   g_trailTriggerDist = InpTrailTrigger * g_point;
   g_trailStepDist    = InpTrailStep * g_point;
   g_maxSpreadPrice   = InpMaxSpread_Pts * g_point;
   g_minTrailStepPrice= 10 * g_point;
   
   if(InpUseTrend) {
      g_trendMA = iMA(_Symbol, InpTrendTF, InpTrendMA_Period, 0, MODE_EMA, PRICE_CLOSE);
      if(g_trendMA == INVALID_HANDLE) return INIT_FAILED;
   }
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   DeletePending();
   if(g_trendMA != INVALID_HANDLE) IndicatorRelease(g_trendMA);
}

// ===================== TICK =====================
void OnTick() {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   
   int posTotal = PositionsTotal();

   // 1. NEW BAR CHECK (Ultra-fast method)
   datetime currentBarTime = (datetime)SeriesInfoInteger(_Symbol, InpTF, SERIES_LASTBAR_DATE);
   
   // If same bar, ONLY do trailing stop
   if(currentBarTime == g_lastBarTime) {
      if(posTotal > 0 && InpTrailTrigger > 0) TrailTick(tick);
      return; 
   }
   
   // --- NEW BAR STARTED ---
   g_lastBarTime = currentBarTime;

   // 2. EXTENDED CHECKS
   // Do not process orders if symbol isn't available for trading
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED) return;

   // Cleanup pending orders from previous bar
   DeletePending();

   // Guard: max 1 active trade
   if(posTotal > 0) {
      if(InpTrailTrigger > 0) TrailTick(tick);
      return; 
   }

   // 3. ENTRY CONDITIONS
   if((tick.ask - tick.bid) > g_maxSpreadPrice) return;

   CacheChannel();
   if(g_cachedHigh <= 0 || g_cachedLow <= 0) return;

   int trend = GetTrendDir();
   if(trend == 0) return;

   datetime expiry = (InpExpiryBars > 0) ? currentBarTime + (InpExpiryBars * PeriodSeconds(InpTF)) : 0;
   ENUM_ORDER_TYPE_TIME timeType = (InpExpiryBars > 0) ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;

   // 4. ORDER PLACEMENT
   if(trend == 1) {
      double buyEntry = g_cachedHigh + g_entryDist;
      double buySL    = buyEntry - g_slDist;
      double buyTP    = buyEntry + g_tpDist;
      double lot      = InpUseRiskPct ? CalcLotByRisk(buySL, buyEntry) : NormLot(InpFixedLot);

      if(g_trade.BuyStop(lot, buyEntry, _Symbol, buySL, buyTP, timeType, expiry, "EPS_B")) {
         g_buyTicket = g_trade.ResultOrder();
      } else {
         PrintFormat("BuyStop failed! Code: %d", g_trade.ResultRetcode());
      }
   }
   else if(trend == -1) {
      double sellEntry = g_cachedLow - g_entryDist;
      double sellSL    = sellEntry + g_slDist;
      double sellTP    = sellEntry - g_tpDist;
      double lot       = InpUseRiskPct ? CalcLotByRisk(sellSL, sellEntry) : NormLot(InpFixedLot);

      if(g_trade.SellStop(lot, sellEntry, _Symbol, sellSL, sellTP, timeType, expiry, "EPS_S")) {
         g_sellTicket = g_trade.ResultOrder();
      } else {
         PrintFormat("SellStop failed! Code: %d", g_trade.ResultRetcode());
      }
   }
}

// ===================== TRAILING =====================
void TrailTick(const MqlTick &tick) {
   static double lastTrailPrice = 0;
   
   // Rate limit: trigger only if price moved enough
   if(MathAbs(tick.bid - lastTrailPrice) < g_minTrailStepPrice) return;
   lastTrailPrice = tick.bid;

   // Freeze level check (extended safety)
   double freezeLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * g_point;

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      bool   isBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double currSL = PositionGetDouble(POSITION_SL);
      double currTP = PositionGetDouble(POSITION_TP);
      double price  = isBuy ? tick.bid : tick.ask;

      double move = isBuy ? (price - entry) : (entry - price);
      if(move < g_trailTriggerDist) continue;

      double newSL = isBuy ? (price - g_trailStepDist) : (price + g_trailStepDist);
      
      // Ensure we don't hit freeze levels
      if(MathAbs(price - newSL) <= freezeLvl) continue;

      if((isBuy && newSL > currSL) || (!isBuy && (newSL < currSL || currSL == 0))) {
         if(!g_trade.PositionModify(ticket, newSL, currTP)) {
             // Only log errors, do not crash tester
             if(g_trade.ResultRetcode() != 10016) Print("Trail modify failed: ", g_trade.ResultRetcode());
         }
      }
   }
}