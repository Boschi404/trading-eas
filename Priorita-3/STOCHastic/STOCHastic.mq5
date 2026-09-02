//+------------------------------------------------------------------+
//|                                                   Stochastic EA  |
//|                                        Copyright 2024, YourName |
//|                                       https://www.yourwebsite.com |
//+------------------------------------------------------------------+
#property strict

input int fastKPeriod = 14;   // Fast %K period
input int slowKPeriod = 3;    // Slow %K period
input int slowDPeriod = 3;    // Slow %D period
input int signalSmoothing = 3;// Signal smoothing for %D
input double overboughtLevel = 80;  // Overbought level
input double oversoldLevel = 20;    // Oversold level
input double lotSize = 0.1;         // Lot size
input int slippage = 3;             // Slippage
input int stopLoss = 50;            // Stop Loss
input int takeProfit = 100;         // Take Profit

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   double stochasticMainLine, stochasticSignalLine;

   // Calculate Stochastic values
   ArraySetAsSeries(stochasticMainLine,true);
   ArraySetAsSeries(stochasticSignalLine,true);
   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);

   int calculatedBars = iStochastic(_Symbol, _Period, fastKPeriod, slowKPeriod, slowDPeriod, MODE_MAIN, 0);
   if (calculatedBars < 1)
       return;

   CopyBuffer(stochastic_main, 0, 0, calculatedBars, stochasticMainLine);
   CopyBuffer(stochastic_signal, 0, 0, calculatedBars, stochasticSignalLine);

   // Check for buy condition
   if (stochasticMainLine[0] < oversoldLevel && stochasticMainLine[1] > oversoldLevel)
   {
      // Buy order
      double price = Ask;
      double stopLossLevel = price - stopLoss * _Point;
      double takeProfitLevel = price + takeProfit * _Point;
      int ticket = OrderSend(_Symbol, OP_BUY, lotSize, price, slippage, stopLossLevel, takeProfitLevel, "Stochastic Buy", 0, 0, clrGreen);
      if (ticket <= 0)
         Print("Error opening buy order: ", GetLastError());
   }

   // Check for sell condition
   if (stochasticMainLine[0] > overboughtLevel && stochasticMainLine[1] < overboughtLevel)
   {
      // Sell order
      double price = Bid;
      double stopLossLevel = price + stopLoss * _Point;
      double takeProfitLevel = price - takeProfit * _Point;
      int ticket = OrderSend(_Symbol, OP_SELL, lotSize, price, slippage, stopLossLevel, takeProfitLevel, "Stochastic Sell", 0, 0, clrRed);
      if (ticket <= 0)
         Print("Error opening sell order: ", GetLastError());
   }
  }
//+------------------------------------------------------------------+
