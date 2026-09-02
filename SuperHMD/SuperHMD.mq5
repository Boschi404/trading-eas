//+------------------------------------------------------------------+
//|                        Super_HMD_EA.mq5                          |
//|                Copyright 2024, Leonardo Boschi                   |
//|                 http://www.leonardoboschi.com                    |
//+------------------------------------------------------------------+
#property copyright "2024, Leonardo Boschi"
#property link      "http://www.yourwebsite.com"
#property version   "1.00"
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

// Input parameters
input int demaLength = 50;
input int demaOffset = 0;
input double sensitivity = 10;
input int fastPeriod = 2;
input double fastMultiplier = 1.0;
input int slowPeriod = 14;
input double slowMultiplier = 3.0;
input double lotSize = 0.01;

double BullsBuffer[];
double BearsBuffer[];

// Indicator handles
input string demaIndicator = "DEMA";
input string superTrendIndicator = "SuperTrend";

// Trading variables
bool isBullish, isBearish, isConsolidating;
bool buySignal, sellSignal;
bool lastBuySignal = false;
bool lastSellSignal = false;

int buy_count = 0; 
int sell_count = 0;

// Haiken Ashi
int handleHaikenAshi;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Add indicator buffers and set properties
   SetIndexBuffer(0, BullsBuffer);
   SetIndexBuffer(1, BearsBuffer);
   
   handleHaikenAshi = iCustom(_Symbol, PERIOD_CURRENT, "Examples\\Heiken_Ashi.mq5");

   // Add your initialization code here

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Bid and Ask
   double currentBid = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
   double currentAsk = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
   
   trade.Buy(0.1,_Symbol, currentAsk, 0, 0,NULL);
   
   // Ashi Buffer
   double haOpen[], haClose[];
   CopyBuffer(handleHaikenAshi, 0, 1, 1, haOpen);
   CopyBuffer(handleHaikenAshi, 3, 1, 1, haClose);
   
   double midHa = (haOpen[0] + haClose[0])/2;
   
   double haOpenOld[], haCloseOld[];
   CopyBuffer(handleHaikenAshi, 0, 2, 1, haOpenOld);
   CopyBuffer(handleHaikenAshi, 3, 2, 1, haCloseOld);
   
   double midHaOld = (haOpenOld[0] + haCloseOld[0])/2;
    
   // Calculate DEMA
   double dema = iDEMA(_Symbol, _Period, demaLength, 0, midHa);
   
   // Calculate DEMA
   double demaOld = iDEMA(_Symbol, _Period, demaLength, 0, midHaOld);
   
   double demaSlope = (dema - demaOld) / 1; // Change the denominator for a different length of the slope calculation

   // Calculate SuperTrend
   double atr = iATR(_Symbol,_Period, 14);
   double uptrend = iCustom(_Symbol, 0, superTrendIndicator, fastPeriod, fastMultiplier, 0, 0);
   double downtrend = iCustom(_Symbol, 0, superTrendIndicator, slowPeriod, slowMultiplier, 1, 0);

   // Determine market conditions
   isBullish = demaSlope > sensitivity;
   isBearish = demaSlope < -sensitivity;
   isConsolidating = !isBullish && !isBearish;
   
   if(isBullish){
      Comment("Bullish");
   }
   if(isBearish){
      Comment("Bearish");
   }

   buySignal = (currentBid > uptrend);
   sellSignal = (currentAsk < downtrend);

   // Entry conditions
   if ((isBullish && buySignal) || (isBearish && sellSignal)  )
   {
      if (isBullish)
      {
         if (!lastBuySignal)
         {
            lastBuySignal = true;
            lastSellSignal = false;
            trade.Buy(lotSize,NULL, currentAsk, (currentAsk+100*_Point), 0,"Super HMD Buy");
         }
      }
      else if (isBearish)
      {
         if (!lastSellSignal)
         {
            lastSellSignal = true;
            lastBuySignal = false;
            trade.Sell(lotSize,NULL, currentBid, (currentBid+100*_Point), 0,"Super HMD Sell");
         }
      }
    }

   // Exit conditions
   if ((lastBuySignal && sellSignal) || (lastSellSignal && buySignal))
   {
      trade.PositionClose(PositionGetTicket(0));

      lastBuySignal = false;
      lastSellSignal = false;
   }
      
      
      
      
   Comment("Buy Count : ", buy_count , "\n",
           "Sell Count : ", sell_count , "\n" );
   
   for(int i=PositionsTotal()-1 ; i <= 0 ; i-- )
     {

      if( PositionSelect(_Symbol) == POSITION_TYPE_BUY )
        {
         buy_count++;
        }
      if( PositionSelect(_Symbol) == POSITION_TYPE_SELL)
        {
         sell_count++;
        }
           
     } // for loop end
  }