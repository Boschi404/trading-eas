//+------------------------------------------------------------------+
//| Opening Range Breakout EA for MT5                               |
//| Strategy: Places buy/sell stop orders at the high/low of the    |
//| Asian session. Trades are closed at 23:00 of the same day.      |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include <ChartObjects/ChartObjectsTxtControls.mqh>

CTrade trade;

//--- input parameters
input double LotSize                = 0.1;
input int    Slippage              = 3;
input string StartAsianSession    = "00:00";
input string EndAsianSession      = "06:00";
input int    CloseHour            = 23;
input int    MagicNumber          = 123456;
input bool   UseStopLoss          = false;
input double StopLossPoints       = 200;    // in points
input bool   UseTakeProfit        = false;
input double TakeProfitPoints     = 200;    // in points
input bool   UseTrailingStop      = false;  // NEW trailing stop flag
input double TrailingStopPoints   = 100;    // trailing stop distance in points
input bool   UseEMAFilter         = false;
input int emaPeriod = 50;
input ENUM_TIMEFRAMES emaTimeframe = PERIOD_CURRENT;
input int emaShift = 0;
input int emaAppliedPrice = PRICE_CLOSE;
input ENUM_TIMEFRAMES EMA_Timeframe = PERIOD_H1;
input bool   UseMartingale        = false;
input double MartingaleFactor     = 2.0;
input double TargetPercent        = 10.0;  // % target for prop firm users
input bool   CloseOrdersAtEnd     = true;
input double MaxDailyDrawdown     = 3.0;   // Max loss % to stop trading

//--- internal variables
double asianHigh = -DBL_MAX;
double asianLow  = DBL_MAX;
datetime asianStartTime, asianEndTime;
bool ordersPlaced = false;
double startingBalance = 0;
bool initialized = false;
bool drawdownBreached = false;
bool positionOpened = false;
int lastOrderDay = -1; // Track day for daily reset

// Martingale tracking
double currentLotSize;
datetime lastCheckTime = 0; // for closed trades check

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   asianStartTime = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " " + StartAsianSession);
   asianEndTime = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " " + EndAsianSession);
   
   startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   currentLotSize = LotSize;

   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   lastOrderDay = t.day;
   lastCheckTime = TimeCurrent();

   CreateInfoPanel();
   return INIT_SUCCEEDED;
   
   int emaHandle;
   emaHandle = iMA(_Symbol, emaTimeframe, emaPeriod, emaShift, MODE_EMA, emaAppliedPrice);
    if (emaHandle == INVALID_HANDLE)
    {
        Print("Errore nella creazione dell'EMA");
        return(INIT_FAILED);
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   datetime now = TimeCurrent();
   MqlDateTime tm;
   TimeToStruct(now, tm);
   
   double emaValue[];

   if (CopyBuffer(emaHandle, 0, 0, 1, emaValue) <= 0)   {
       Print("Errore nella lettura del valore EMA");
   }
   else   {
       double currentEMA = emaValue[0];
       Print("EMA attuale: ", currentEMA);
   }

   if (!initialized) {
      startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      initialized = true;
   }

   // Reset daily variables at start of new day
   if (tm.day != lastOrderDay) {
      ResetDay();
      lastOrderDay = tm.day;
   }

   if (CheckDrawdownLimit()) return;

   // Process closed trades for Martingale
   if (UseMartingale)
      ProcessClosedTrades();

   // Collect Asian session high/low
   if (now >= asianStartTime && now <= asianEndTime) {
      double high = iHigh(_Symbol, PERIOD_M5, 0);
      double low = iLow(_Symbol, PERIOD_M5, 0);
      if (high > asianHigh) asianHigh = high;
      if (low < asianLow) asianLow = low;
   }

   // After Asian session ends, place breakout orders if not placed yet
   if (now > asianEndTime && !ordersPlaced && !drawdownBreached) {
      if (!UseEMAFilter) return;
      PlaceOrders();
      ordersPlaced = true;
   }

   // Manage trailing stops
   if (UseTrailingStop) {
      ManageTrailingStops();
   }

   // Close positions and cancel orders at specified hour
   if (CloseOrdersAtEnd && tm.hour == CloseHour && tm.min == 0) {
      CloseAllPositions();
      CancelPendingOrders();
      ResetDay();
   }
   
   CreateInfoPanel();
   
   string infoText = 
   "Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n" +
   "Equity: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n" +
   "Asian High: " + DoubleToString(asianHigh, _Digits) + "\n" +
   "Asian Low: " + DoubleToString(asianLow, _Digits) + "\n" +
   "Lot Size (Next): " + DoubleToString(currentLotSize, 2) + "\n" +
   "Orders Placed: " + (ordersPlaced ? "Yes" : "No") + "\n" +
   "Drawdown Breached: " + (drawdownBreached ? "Yes" : "No");

   UpdateInfoPanel(infoText);
}

//+------------------------------------------------------------------+
//| Place breakout orders                                            |
//+------------------------------------------------------------------+
void PlaceOrders() {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double slBuy = UseStopLoss ? ask - StopLossPoints * _Point : 0;
   double slSell = UseStopLoss ? bid + StopLossPoints * _Point : 0;
   double buyPrice = asianHigh + _Point;
   double sellPrice = asianLow - _Point;

   trade.SetExpertMagicNumber(MagicNumber);
   
   bool buyOk;
   bool sellOk;

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if (currentPrice > currentEMA)
   {
       buyOk = trade.BuyStop(currentLotSize, buyPrice, _Symbol, slBuy, 0, ORDER_TIME_DAY, 0, clrGreen);
   }
   else
   {
       sellOk = trade.SellStop(currentLotSize, sellPrice, _Symbol, slSell, 0, ORDER_TIME_DAY, 0, clrRed);
   }
   

   if (!buyOk)
      Print("BuyStop order failed: ", GetLastError());
   if (!sellOk)
      Print("SellStop order failed: ", GetLastError());

   if (buyOk || sellOk) {
      positionOpened = true;
   }
}

//+------------------------------------------------------------------+
//| Manage trailing stop loss                                        |
//+------------------------------------------------------------------+
void ManageTrailingStops() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket)) {
         if (PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double stopLoss = PositionGetDouble(POSITION_SL);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         double newSL = 0;
         if (posType == POSITION_TYPE_BUY) {
            newSL = price - TrailingStopPoints * _Point;
            if (newSL > stopLoss && newSL > openPrice) {
               if (!trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP)))
                  Print("Failed to modify BUY SL: ", GetLastError());
            }
         } 
         else if (posType == POSITION_TYPE_SELL) {
            newSL = price + TrailingStopPoints * _Point;
            if ((stopLoss == 0 || newSL < stopLoss) && newSL < openPrice) {
               if (!trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP)))
                  Print("Failed to modify SELL SL: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for drawdown breach                                        |
//+------------------------------------------------------------------+
bool CheckDrawdownLimit() {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double drawdown = 100.0 * (startingBalance - balance) / startingBalance;
   if (drawdown >= MaxDailyDrawdown) {
      drawdownBreached = true;
      CancelPendingOrders();
      CloseAllPositions();
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Cancel all pending orders                                        |
//+------------------------------------------------------------------+
void CancelPendingOrders() {
   ulong totalOrders = OrdersTotal();
   for (ulong i = 0; i < totalOrders; i++) {
      ulong ticket = OrderGetTicket(i);
      if (OrderGetInteger(ORDER_MAGIC) == MagicNumber) {
         ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         if (orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_SELL_STOP) {
            if (!trade.OrderDelete(ticket))
               Print("Failed to delete pending order: ", GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Reset values for new trading day                                 |
//+------------------------------------------------------------------+
void ResetDay() {
   ordersPlaced = false;
   drawdownBreached = false;
   positionOpened = false;
   asianHigh = -DBL_MAX;
   asianLow = DBL_MAX;
   startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   asianStartTime = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " " + StartAsianSession);
   asianEndTime = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " " + EndAsianSession);
   currentLotSize = LotSize;
   lastCheckTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Close all positions at specified time                            |
//+------------------------------------------------------------------+
void CloseAllPositions() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket)) {
         if (PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
            if (!trade.PositionClose(ticket))
               Print("Failed to close position: ", GetLastError());
         }
      }
   }
   positionOpened = false;
}

//+------------------------------------------------------------------+
//| Process closed trades for Martingale adjustment                  |
//+------------------------------------------------------------------+
void ProcessClosedTrades() {
   HistorySelect(lastCheckTime, TimeCurrent());
   ulong deals = HistoryDealsTotal();

   bool lostLastTrade = false;
   bool wonLastTrade = false;

   for (ulong i = deals - 1; i != (ulong)-1; i--) {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if (HistoryDealSelect(deal_ticket)) {
         ulong magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
         if (magic != MagicNumber) continue;

         datetime deal_time = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
         if (deal_time <= lastCheckTime) break; // older than last check

         double deal_profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);

         if (deal_profit < 0) {
            lostLastTrade = true;
         } else if (deal_profit > 0) {
            wonLastTrade = true;
         }
      }
   }

   // Update last check time
   lastCheckTime = TimeCurrent();

   // Adjust lot size based on last trade result
   if (lostLastTrade) {
      currentLotSize *= MartingaleFactor;
      double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      if (currentLotSize > maxLot)
         currentLotSize = maxLot;
      Print("Martingale applied. New lot size: ", currentLotSize);
   } else if (wonLastTrade) {
      currentLotSize = LotSize;
      Print("Trade won, resetting lot size to base: ", LotSize);
   }
}

//+------------------------------------------------------------------+
//| Create informational panel on chart                              |
//+------------------------------------------------------------------+
CChartObjectLabel infoPanel;
// Global
string infoPanelName = "InfoPanel";

// Create info panel on chart (call in OnInit)
void CreateInfoPanel()
{
    if (!ObjectFind(0, infoPanelName))
    {
        ObjectCreate(0, infoPanelName, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, infoPanelName, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
        ObjectSetInteger(0, infoPanelName, OBJPROP_XDISTANCE, 20);
        ObjectSetInteger(0, infoPanelName, OBJPROP_YDISTANCE, 20);
        ObjectSetInteger(0, infoPanelName, OBJPROP_COLOR, clrWhite);
        ObjectSetInteger(0, infoPanelName, OBJPROP_BACK, true);
        ObjectSetInteger(0, infoPanelName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, infoPanelName, OBJPROP_SELECTED, false);
        ObjectSetInteger(0, infoPanelName, OBJPROP_FONTSIZE, 10);
        ObjectSetString(0, infoPanelName, OBJPROP_FONT, "Arial");
    }
}

// Update info panel text (call in OnTick)
void UpdateInfoPanel(string text)
{
    if (ObjectFind(0, infoPanelName) == -1)
        CreateInfoPanel();
    ObjectSetString(0, infoPanelName, OBJPROP_TEXT, text);
}