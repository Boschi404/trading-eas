//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
input int EMA_Period = 50;              // EMA period for trend determination on 4H
input ENUM_TIMEFRAMES TrendTimeframe = PERIOD_H4; // Trend timeframe
input ENUM_TIMEFRAMES TradeTimeframe = PERIOD_M1; // Trade timeframe (1M, 5M, 15M)
input double LotSize = 0.01;            // Fixed lot size
input double ProfitTargetPercent = 1.0; // Profit target as a percent of balance
input double MaxSpread = 20.0;          // Maximum allowable spread (in points)
double account_start_balance;           // Starting account balance

// EMA handles
int handle_ema;

int OnInit() {
    // Initialize EMA indicator for 4H timeframe
    handle_ema = iMA(NULL, TrendTimeframe, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    if (handle_ema == INVALID_HANDLE) {
        Print("Error creating EMA indicator");
        return INIT_FAILED;
    }

    account_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    IndicatorRelease(handle_ema);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Check spread
    if (SymbolInfoDouble(Symbol(), SYMBOL_SPREAD) > MaxSpread) return;

    // Get 4H EMA value for trend direction
    double ema_value;
    CopyBuffer(handle_ema, 0, 0, 1, ema_value);
    
    double close_price = iClose(NULL, TrendTimeframe, 0);
    
    // Determine trend direction
    bool is_uptrend = close_price > ema_value[0];
    bool is_downtrend = close_price < ema_value[0];

    // Check existing positions and close them if profit target is met
    double current_profit = AccountInfoDouble(ACCOUNT_BALANCE) - account_start_balance;
    if ((current_profit / account_start_balance) * 100 >= ProfitTargetPercent) {
        CloseAllPositions();
        return;
    }

    // Place a buy or sell order if trend conditions are met
    if (is_uptrend) {
        if (!PositionExists("Buy")) OpenTrade(ORDER_TYPE_BUY);
    } else if (is_downtrend) {
        if (!PositionExists("Sell")) OpenTrade(ORDER_TYPE_SELL);
    }
}

//+------------------------------------------------------------------+
//| Opens a trade in the specified direction                         |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE order_type) {
    double price = (order_type == ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double slippage = 3; // Slippage in points

    // Send order
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = Symbol();
    request.volume = LotSize;
    request.type = order_type;
    request.price = price;
    request.slippage = slippage;
    request.deviation = slippage;
    request.magic = 123456; // Magic number for the EA

    if (!OrderSend(request, result)) {
        Print("Error opening order: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Check if there are open positions in a given direction           |
//+------------------------------------------------------------------+
bool PositionExists(string direction) {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (PositionGetSymbol(i) == Symbol() && 
            (direction == "Buy" && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ||
            (direction == "Sell" && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)) 
        {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Close all positions in the symbol                                |
//+------------------------------------------------------------------+
void CloseAllPositions() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (PositionGetSymbol(ticket) == Symbol()) {
            MqlTradeRequest request;
            MqlTradeResult result;
            ZeroMemory(request);
            ZeroMemory(result);

            request.action = TRADE_ACTION_DEAL;
            request.position = ticket;
            request.symbol = Symbol();
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = (request.type == ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);
            request.deviation = 3;

            OrderSend(request, result);
        }
    }
}
