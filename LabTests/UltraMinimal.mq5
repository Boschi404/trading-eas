//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
CTrade trade;
datetime lastBar=0;
input double Lot=0.02;

int OnInit(){trade.SetExpertMagicNumber(99999);return INIT_SUCCEEDED;}

void OnTick(){
   datetime ct=iTime(_Symbol,PERIOD_H4,0);
   if(ct==lastBar) return;
   lastBar=ct;
   
   MqlRates r[]; ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,PERIOD_H4,1,1,r)<1) return;
   
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   
   if(r[0].close>r[0].open){
      trade.Buy(Lot,_Symbol,ask,0,0,"T");
   } else {
      trade.Sell(Lot,_Symbol,bid,0,0,"T");
   }
}
