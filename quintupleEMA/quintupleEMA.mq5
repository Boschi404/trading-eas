#include <Trade/Trade.mqh>
CTrade trade;

input int ema1 = 10;
input int ema2 = 20;
input int ema3 = 50;
input int ema4 = 100;
input int ema5 = 200;
int emaPeriods[] = {ema1, ema2, ema3, ema4, ema5}; // EMA periods
input double lotSize = 0.1; // Lot size for trading

int handleEma1new;
int handleEma2new;
int handleEma3new;

int handleEma1old;
int handleEma2old;
int handleEma3old;

int barsTotal;
bool allUpwards;
bool allDownwards;

int OnInit(){
   barsTotal = iBars(_Symbol, PERIOD_CURRENT);

   handleEma1new = iMA(_Symbol, PERIOD_CURRENT, emaPeriods[0], 0, MODE_EMA, PRICE_CLOSE);
   handleEma2new = iMA(_Symbol, PERIOD_CURRENT, emaPeriods[1], 0, MODE_EMA, PRICE_CLOSE);
   handleEma3new = iMA(_Symbol, PERIOD_CURRENT, emaPeriods[3], 0, MODE_EMA, PRICE_CLOSE);
   
   handleEma1old = iMA(_Symbol, PERIOD_CURRENT, emaPeriods[0], 1, MODE_EMA, PRICE_CLOSE);
   handleEma2old = iMA(_Symbol, PERIOD_CURRENT, emaPeriods[1], 1, MODE_EMA, PRICE_CLOSE);
   handleEma3old = iMA(_Symbol, PERIOD_CURRENT, emaPeriods[3], 1, MODE_EMA, PRICE_CLOSE);
   
   return(INIT_SUCCEEDED);
}

void OnTick()
  {
   int bars = iBars(_Symbol, PERIOD_CURRENT);
   
   //EMAs
   double ema1new[];
   double ema2new[];
   double ema3new[];
   
   double ema1old[];
   double ema2old[];
   double ema3old[];
   
   //Copy Buffer
   CopyBuffer(handleEma1new, MAIN_LINE, 1, 2, ema1new);
   CopyBuffer(handleEma2new, MAIN_LINE, 1, 2, ema2new);
   CopyBuffer(handleEma3new, MAIN_LINE, 1, 2, ema3new);
   
   CopyBuffer(handleEma1old, MAIN_LINE, 1, 2, ema1old);
   CopyBuffer(handleEma2old, MAIN_LINE, 1, 2, ema2old);
   CopyBuffer(handleEma3old, MAIN_LINE, 1, 2, ema3old);
   
   //slope calculation
   double ema1slope = (ema1new[1] - ema1old[1]);
   double ema2slope = (ema2new[1] - ema2old[1]);
   double ema3slope = (ema3new[1] - ema3old[1]);

   if(barsTotal < bars){
      //conditions
      if(ema1slope > 0 && ema2slope > 0 && ema3slope > 0){
         trade.Buy(lotSize, _Symbol, SYMBOL_ASK, 0, 0,"5EMA Buy");
      }
      else if(ema1slope < 0 && ema2slope < 0 && ema3slope < 0){
         trade.Sell(lotSize, _Symbol, SYMBOL_BID, 0, 0,"5EMA Sell");
      }
      else if (!(ema1slope > 0 && ema2slope > 0 && ema3slope > 0) && !(ema1slope < 0 && ema2slope < 0 && ema3slope < 0)){
         CloseAllPositions();
      }
   }
   
     
   Comment("uptrend: ", allUpwards,
           "\ndowntrend: ", allDownwards);
  }
  
 void CloseAllPositions(){
   for(int i = PositionsTotal()-1; i >= 0; i--){
      int ticket = PositionGetTicket(i);
      trade.PositionClose(ticket);
   }
 }