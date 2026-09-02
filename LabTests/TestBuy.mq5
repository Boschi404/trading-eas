#include <Trade\Trade.mqh>
CTrade trade;

void OnTick(){
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   ask = NormalizeDouble(ask, _Digits);
   trade.Buy(0.01, _Symbol, ask, 0, 0, NULL);
}  