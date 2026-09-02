//+------------------------------------------------------------------+
//|                      Pair Trading EA for MT5                    |
//|         Implements statistical arbitrage with CTrade            |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

input string Symbol1 = "EURUSD"; // First symbol
input string Symbol2 = "USDJPY"; // Second symbol
input int LookbackPeriod = 20;   // Lookback period for moving average and std dev
input double EntryThreshold = 2; // Entry threshold (in standard deviations)
input double StopLoss = 3;       // Stop loss (in standard deviations)
input double LotSize = 0.1;      // Lot size for trades

CTrade trade;

double spread_history[]; // Array to store spread history
double spread_mean;      // Mean of the spread
double spread_stddev;    // Standard deviation of the spread

//+------------------------------------------------------------------+
//| Calculate the normalized price                                   |
//+------------------------------------------------------------------+
double NormalizePrice(const string symbol) {
   double price = iClose(symbol, PERIOD_CURRENT, 0);
   double avg = iMA(symbol, PERIOD_CURRENT, LookbackPeriod, 0, MODE_SMA, PRICE_CLOSE);
   double stddev = iStdDev(symbol, PERIOD_CURRENT, LookbackPeriod, 0, MODE_SMA, PRICE_CLOSE,);
   return (price - avg) / stddev;
}

//+------------------------------------------------------------------+
//| Calculate spread, mean, and standard deviation                  |
//+------------------------------------------------------------------+
void CalculateSpread() {
   double normalized1 = NormalizePrice(Symbol1);
   double normalized2 = NormalizePrice(Symbol2);
   double spread = normalized1 - normalized2;

   ArrayResize(spread_history, LookbackPeriod + 1);
   ArrayCopy(spread_history, spread_history, 1, 0, LookbackPeriod);
   spread_history[0] = spread;

   spread_mean = MathMean(spread_history);
   spread_stddev = MathStandardDev(spread_history);
}

//+------------------------------------------------------------------+
//| Check and execute trades                                         |
//+------------------------------------------------------------------+
void CheckSignals() {
   double spread = spread_history[0];
   double upper_bound = spread_mean + EntryThreshold * spread_stddev;
   double lower_bound = spread_mean - EntryThreshold * spread_stddev;
   double stop_loss_upper = spread_mean + StopLoss * spread_stddev;
   double stop_loss_lower = spread_mean - StopLoss * spread_stddev;

   // Check entry conditions
   if (spread > upper_bound) {
      // Sell Symbol1 and Buy Symbol2
      if (!PositionSelect(Symbol1)) trade.Sell(LotSize, Symbol1);
      if (!PositionSelect(Symbol2)) trade.Buy(LotSize, Symbol2);
   } else if (spread < lower_bound) {
      // Buy Symbol1 and Sell Symbol2
      if (!PositionSelect(Symbol1)) trade.Buy(LotSize, Symbol1);
      if (!PositionSelect(Symbol2)) trade.Sell(LotSize, Symbol2);
   }

   // Check exit conditions
   if (spread <= spread_mean && spread >= spread_mean) {
      if (PositionSelect(Symbol1)) trade.PositionClose(Symbol1);
      if (PositionSelect(Symbol2)) trade.PositionClose(Symbol2);
   }

   // Stop loss conditions
   if (spread > stop_loss_upper || spread < stop_loss_lower) {
      if (PositionSelect(Symbol1)) trade.PositionClose(Symbol1);
      if (PositionSelect(Symbol2)) trade.PositionClose(Symbol2);
   }
}

//+------------------------------------------------------------------+
//| OnTick event                                                     |
//+------------------------------------------------------------------+
void OnTick() {
   CalculateSpread();
   CheckSignals();
}

//+------------------------------------------------------------------+
//| OnInit event                                                     |
//+------------------------------------------------------------------+
int OnInit() {
   ArrayResize(spread_history, LookbackPeriod);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit event                                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
}
//+------------------------------------------------------------------+
