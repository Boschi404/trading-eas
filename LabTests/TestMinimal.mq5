//+------------------------------------------------------------------+
//|                                                TestMinimal.mq5   |
//+------------------------------------------------------------------+
#property copyright "Debug"
#property version "1.00"
#include <Trade/Trade.mqh>

input double InpLotSize = 0.02;
CTrade trade;
datetime lastBar = 0;

int OnInit() {
   trade.SetExpertMagicNumber(99999);
   return INIT_SUCCEEDED;
}

void OnTick() {
   datetime ct = iTime(_Symbol, PERIOD_H4, 0);
   if(ct == lastBar) return;
   lastBar = ct;
   
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, PERIOD_H4, 1, 1, r) < 1) return;
   
   if(PositionsTotal() > 0) return;
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if(r[0].close > r[0].open) {
      double sl = r[0].low - 100 * _Point;
      double tp = ask + 200 * _Point;
      trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "MIN_BUY");
   } else {
      double sl = r[0].high + 100 * _Point;
      double tp = bid - 200 * _Point;
      trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "MIN_SELL");
   }
}
