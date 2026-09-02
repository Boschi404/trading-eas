
#property copyright "Copyright 2024, Leonardo Boschi"
#property link "www.leonardoboschi.com"
#property version "1.00"

#include <Trade/Trade.mqh>

CTrade trade;
CPositionInfo pos;
COrderInfo ord;




input double RiskPercent = 2;
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5;

input int TpPoints = 200;
input int SlPoints = 200;
input int TslPoints = 10;
input int TslTriggerPoints = 15;


input int BarsN = 5;
input int OderDistPoints = 100;
input int ExpirationBars = 100;

enum StartHour{Inactive=0, _0100=1, _0200=2, _0300=3, _0400=4, _0500=5, _0600=6, _0700=7, _0800=8, _0900=9, _1000=10, _1100=11, _1200=12, _1300=13, _1400=14, _1500=15, _1600=16, _1700=17, _1800=18, _1900=19, _2000=20, _2100=21, _2200=22, _2300=23, _2400=24};
input StartHour SHInput = 0;

enum EndHour{Inactive=0, _0100=1, _0200=2, _0300=3, _0400=4, _0500=5, _0600=6, _0700=7, _0800=8, _0900=9, _1000=10, _1100=11, _1200=12, _1300=13, _1400=14, _1500=15, _1600=16, _1700=17, _1800=18, _1900=19, _2000=20, _2100=21, _2200=22, _2300=23, _2400=24};
input StartHour EHInput = 0;

int SHChoice;
int EHChoice;

input int InpMagic = 696969;
input string TradeComment = "Gengar V1 Bot";


int OnInit(){

   trade.SetExpertMagicNumber(InpMagic));
   
   SHChoice = SHInput;
   EHChoice = EHInput;
   
   ChartSetInteger(0, CHART_SHOW_GRID, false)

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){


}


void OnTick(){
   
   
   if(!IsNewBar()) return;
   
   MqlDateTime time;
   TimeToStruct(TimeCurrent), time);
   int Hournow = time.hour;
   
   if(Hournow<SHChoice){CloseAllOrders(); return;}
   if(Hournow>=EHChoice && EHChoice != 0){CloseAllOrders(); return;}
   
   
   int BuyTotal = 0;
   int SellTotal = 0;
   
   for(int i=OrdersTotal()-1; i>=0; i--){
      ord.SelectByIndex(i);
      if(ord.OrderType()==ORDER_TYPE_BUY_STOP && ord.Symbol() == _Symbol && ord.Magic() == InpMagic) BuyTotal++;
      if(ord.OrderType()==ORDER_TYPE_SELL_STOP && ord.Symbol() == _Symbol && ord.Magic() == InpMagic) SellTotal++;
   }
   
   for(int i=PositionsTotal()-1; i>=0; i--){
      pos.SelectByIndex(i);
      if(pos.PositionType()==POSITION_TYPE_BUY && pos.Symbol() == _Symbol && pos.Magic() == InpMagic) BuyTotal++;
      if(pos.PositionType()==POSITION_TYPE_SELL && pos.Symbol() == _Symbol && pos.Magic() == InpMagic) SellTotal++;
   }
   
   if(BuyTotal <= 0){
      double high = findHigh();
      if(high > 0){
         executeBuy(high);
      }
   }
   
   if(SellTotal <= 0){
      double low = findLow();
      if(low > 0){
         executeSell(low);
      }
   }
   
   
   
   
}


//+--------------------------------------------------------------------------+


bool IsNewBar(){
   static datetime previousTime = 0;
   datetime currentTime = iTime(_Symbol, Timeframe, 0);
   if(previousTime!=currentTime){
      previousTime=currentTime;
      return true;
   }
   return false;
}

double findHigh(){
   double  lowestLow = DBL_MAX;
   for(int i=0;i<total;i++){
      double low = iLow(_Symbol, Timeframe, i);
      if()
   }
}