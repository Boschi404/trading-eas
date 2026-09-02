//+------------------------------------------------------------------+
//|                                       EdgePointScalper_minimal.mq5|
//| DEBUG VERSION — no indicators, just pure price action            |
//+------------------------------------------------------------------+
#property copyright "DEBUG"
#property version "1.00"
#include <Trade\Trade.mqh>

input int      InpBarsN          = 12;
input int      InpEntryDist_Pts  = 555;
input int      InpExpiryBars     = 612;
input ENUM_TIMEFRAMES InpTF      = PERIOD_M15;
input int      InpFixedSL_Pts    = 915;
input int      InpFixedTP_Pts    = 1870;
input bool     InpUseTrail       = false;
input int      InpTrailTrigger   = 45;
input int      InpTrailStep      = 45;
input bool     InpUseRiskPct     = false;
input double   InpRiskPct        = 2.0;
input double   InpFixedLot       = 0.01;
input double   InpMaxLot         = 1.0;
input int      InpMaxSpread_Pts  = 3000;
input int      InpMagic          = 20240501;

CTrade trade;
datetime g_lastBarTime = 0;

double PtsToPrice(int pts) { return pts * _Point; }

double NormalizeLot(double lot) {
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lot < mn) lot = mn;
   if(lot > InpMaxLot) lot = InpMaxLot;
   return lot;
}

double FindHigh(int bars) {
   double h = -1;
   for(int i = 1; i <= bars; i++) {
      double hi = iHigh(_Symbol, InpTF, i);
      if(hi > h) h = hi;
   }
   return h;
}

double FindLow(int bars) {
   double l = DBL_MAX;
   for(int i = 1; i <= bars; i++) {
      double lo = iLow(_Symbol, InpTF, i);
      if(lo < l) l = lo;
   }
   return (l == DBL_MAX) ? 0 : l;
}

int OnInit() {
   trade.SetExpertMagicNumber(InpMagic);
   g_lastBarTime = 0;
   Print("EdgePointScalper MINIMAL initialized");
   return INIT_SUCCEEDED;
}

void OnTick() {
   datetime currentBar = iTime(_Symbol, InpTF, 0);
   if(currentBar == g_lastBarTime) return;
   if(g_lastBarTime == 0) { g_lastBarTime = currentBar; return; }
   g_lastBarTime = currentBar;

   if(PositionsTotal() > 0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double highN = FindHigh(InpBarsN);
   double lowN  = FindLow(InpBarsN);
   if(highN <= 0 || lowN <= 0) return;

   double slDist = PtsToPrice(InpFixedSL_Pts);
   double tpDist = PtsToPrice(InpFixedTP_Pts);
   double entryDist = InpEntryDist_Pts * _Point;
   double lot = NormalizeLot(0.01);  // Fixed small lot for safety
   
   datetime expiry = (InpExpiryBars > 0) ? iTime(_Symbol, InpTF, 0) + InpExpiryBars * PeriodSeconds(InpTF) : 0;

   // BUY STOP
   double buyEntry = highN + entryDist;
   double buySL    = buyEntry - slDist;
   double buyTP    = buyEntry + tpDist;
   trade.BuyStop(lot, buyEntry, _Symbol, buySL, buyTP, ORDER_TIME_SPECIFIED, expiry, "DBG_B");

   // SELL STOP
   double sellEntry = lowN - entryDist;
   double sellSL    = sellEntry + slDist;
   double sellTP    = sellEntry - tpDist;
   trade.SellStop(lot, sellEntry, _Symbol, sellSL, sellTP, ORDER_TIME_SPECIFIED, expiry, "DBG_S");
}
