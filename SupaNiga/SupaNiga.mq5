#include <Trade\Trade.mqh>
CTrade trade;
// Supertrend indicator function
double iCustom(string symbol, ENUM_TIMEFRAMES timeframe, string indicName, int atrPeriod, double atrMultiplier, int shift);

// Function to calculate ATR
double CalculateATR(int period)
{
    return iATR(_Symbol, 0, period);
}

// Function to open a trade
void OpenTrade(string type, double priceOpen)
{
    double atr = CalculateATR(14) * 2;
    double sl, tp;

    if (type == "buy")
    {
        sl = NormalizeDouble(priceOpen - atr, _Digits);
        tp = NormalizeDouble(priceOpen + atr, _Digits);
        trade.Buy(type, _Symbol, priceOpen, sl, tp, "Supertrend EA");
    }
    else if (type == "sell")
    {
        sl = NormalizeDouble(priceOpen + atr, _Digits);
        tp = NormalizeDouble(priceOpen - atr, _Digits);
        trade.Sell(type, _Symbol, priceOpen, sl, tp, "Supertrend EA");
    }

    
}

// Expert Advisor start function
void OnTick()
{
    // Bid and Ask
    double currentBid = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
    double currentAsk = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
   
    // Supertrend parameters
    ENUM_TIMEFRAMES timeframe = Period();
    string indicName = "SuperTrend";
    int atrPeriod = 14;
    double atrMultiplier = 2.0;
    int shift = 0;

    // Check Supertrend signal
    double atr = iATR(_Symbol,PERIOD_CURRENT, 14);
    double supertrend = iCustom(_Symbol, 0, supertrend, fastPeriod, fastMultiplier, 0, 0);
    if (supertrend == EMPTY_VALUE)
        return;

    if (supertrend > 0)
    {
        // Buy signal
        if (!Trade.PositionSelect(_Symbol))
        {
            OpenTrade("sell", currentAsk);
        }
            
    }
    else if (supertrend < 0)
    {
        // Sell signal
        if (!Trade.PositionSelect(_Symbol))
        {
            OpenTrade("buy", currentBid);
        }
    }
}

//+------------------------------------------------------------------+
