//+------------------------------------------------------------------+
//| Advanced Heikin Ashi Trading Expert Advisor                      |
//| With Multiple Closing Conditions and Lot Size Management         |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      "Your Website"
#property version   "1.05"
#property strict

// Include the CTrade library
#include <Trade\Trade.mqh>

// Enum for closing conditions
enum CLOSE_CONDITION {
    CLOSE_ON_OPPOSITE_CANDLE,    // Close on Opposite Candle Color
    CLOSE_ON_PROFIT_TARGET,      // Close on Profit Target
    CLOSE_ON_TIME_EXPIRE         // Close After 24 Hours
};

// Input parameters
input CLOSE_CONDITION InpCloseCondition = CLOSE_ON_OPPOSITE_CANDLE;  // Closing Condition
input double   InpInitialLotSize   = 5.12;   // Initial Lot Size
input int      InpMagicNumber      = 12345;  // Magic Number for Trades
input uint     InpSlippage         = 10;     // Maximum Slippage
input double   InpTakeProfit       = 10;     // Take Profit in Pips
input int      InpMaxTradeTime     = 24;     // Max Trade Duration (Hours)

// Global variables
CTrade         Trade;          // Trading object
double         InitialBalance  = 0;
double         PrevHAOpen      = 0;
double         PrevHAClose     = 0;
double         CurrentLotSize  = 0;
int            TradeCount      = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Configure the Trade object
   Trade.SetExpertMagicNumber(InpMagicNumber);
   Trade.SetDeviationInPoints(InpSlippage);
   
   // Store initial balance and lot size
   InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   CurrentLotSize = InpInitialLotSize;
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Calculate Heikin Ashi Candle Color Manually                      |
//+------------------------------------------------------------------+
bool IsPreviousDayCandelGreen()
{
   // Get daily OHLC data
   double open[] = {0};
   double high[] = {0};
   double low[] = {0};
   double close[] = {0};
   
   // Copy daily candle data
   if(CopyOpen(Symbol(), PERIOD_D1, 1, 1, open) <= 0 ||
      CopyHigh(Symbol(), PERIOD_D1, 1, 1, high) <= 0 ||
      CopyLow(Symbol(), PERIOD_D1, 1, 1, low) <= 0 ||
      CopyClose(Symbol(), PERIOD_D1, 1, 1, close) <= 0)
   {
      Print("Error copying daily candle data");
      return false;
   }
   
   // Manual Heikin Ashi Calculation for previous day
   double haClose = (open[0] + high[0] + low[0] + close[0]) / 4;
   double haOpen = (PrevHAOpen + PrevHAClose) / 2;
   
   // Update global previous HA values for next calculation
   PrevHAOpen = haOpen;
   PrevHAClose = haClose;
   
   // Check if previous day candle is green
   return haClose > haOpen;
}

//+------------------------------------------------------------------+
//| Check if trade should be closed based on conditions              |
//+------------------------------------------------------------------+
bool ShouldClosePosition()
{
   // Check if any positions are open
   if(!PositionSelect(Symbol()))
      return false;
   
   // Get position details
   long magic = 0;
   if(!PositionGetInteger(POSITION_MAGIC, magic) || magic != InpMagicNumber)
      return false;
   
   long posType = 0;
   if(!PositionGetInteger(POSITION_TYPE, posType))
      return false;
   
   datetime openTime = 0;
   if(!PositionGetInteger(POSITION_TIME, openTime))
      return false;
   
   switch(InpCloseCondition)
   {
      case CLOSE_ON_OPPOSITE_CANDLE:
      {
         bool isPreviousDayGreen = IsPreviousDayCandelGreen();
         return (posType == POSITION_TYPE_BUY && !isPreviousDayGreen) || 
                (posType == POSITION_TYPE_SELL && isPreviousDayGreen);
      }
      
      case CLOSE_ON_PROFIT_TARGET:
      {
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = (posType == POSITION_TYPE_BUY) ? 
            SymbolInfoDouble(Symbol(), SYMBOL_BID) : 
            SymbolInfoDouble(Symbol(), SYMBOL_ASK);
         
         double pipValue = SymbolInfoDouble(Symbol(), SYMBOL_POINT) * 10;
         double profitPoints = MathAbs(currentPrice - entry) / pipValue;
         
         return profitPoints >= InpTakeProfit;
      }
      
      case CLOSE_ON_TIME_EXPIRE:
      {
         return (TimeCurrent() - openTime) >= (InpMaxTradeTime * 3600);
      }
      
      default:
         return false;
   }
}

//+------------------------------------------------------------------+
//| Adjust Lot Size for Consecutive Trades                           |
//+------------------------------------------------------------------+
void AdjustLotSize()
{
   // Halve the lot size for consecutive trades
   CurrentLotSize = MathMax(0.01, CurrentLotSize / 2);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if we have an active trade that should be closed
   if(PositionSelect(Symbol()))
   {
      long magic = 0;
      if(PositionGetInteger(POSITION_MAGIC, magic) && magic == InpMagicNumber)
      {
         if(ShouldClosePosition())
         {
            Trade.PositionClose(PositionGetTicket(0));
            AdjustLotSize();
            return;
         }
      }
   }
   
   // Only trade at the start of a new day
   if(!IsNewCandle())
      return;
   
   // Ensure no open positions before opening new trade
   if(PositionsTotal() > 0)
      return;
   
   // Determine trade direction based on previous day's Heikin Ashi candle
   if(IsPreviousDayCandelGreen())
   {
      // Open Long Trade
      OpenLongTrade();
   }
   else
   {
      // Open Short Trade
      OpenShortTrade();
   }
}

//+------------------------------------------------------------------+
//| Open Long Trade                                                  |
//+------------------------------------------------------------------+
void OpenLongTrade()
{
   double entry = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double tp = entry + (InpTakeProfit * SymbolInfoDouble(Symbol(), SYMBOL_POINT) * 10);
   double sl = entry - (InpTakeProfit * SymbolInfoDouble(Symbol(), SYMBOL_POINT) * 10);
   
   Trade.Buy(
      CurrentLotSize,      // Volume
      Symbol(),            // Symbol
      entry,               // Price
      sl,                   // Stop Loss
      tp,                  // Take Profit
      "Long Trade"         // Comment
   );
}

//+------------------------------------------------------------------+
//| Open Short Trade                                                 |
//+------------------------------------------------------------------+
void OpenShortTrade()
{
   double entry = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double tp = entry - (InpTakeProfit * SymbolInfoDouble(Symbol(), SYMBOL_POINT) * 10);
   double sl = entry + (InpTakeProfit * SymbolInfoDouble(Symbol(), SYMBOL_POINT) * 10);
   
   Trade.Sell(
      CurrentLotSize,      // Volume
      Symbol(),            // Symbol
      entry,               // Price
      sl,                   // Stop Loss
      tp,                  // Take Profit
      "Short Trade"        // Comment
   );
}

//+------------------------------------------------------------------+
//| Check if it's a new candle                                       |
//+------------------------------------------------------------------+
bool IsNewCandle()
{
   static datetime PrevTime = 0;
   datetime CurrentTime = iTime(Symbol(), PERIOD_D1, 0);
   
   if(CurrentTime != PrevTime)
   {
      PrevTime = CurrentTime;
      return true;
   }
   return false;
}