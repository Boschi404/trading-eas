//+------------------------------------------------------------------+
//|                                                      SuperHMD.mq5 |
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Expert Advisor based on Super HMD strategy"

input int DEMA_Period = 14;
input double DEMA_Offset = 0.5;
input double DEMA_Sensitivity = 0.3;

input int SuperTrend_Fast_Period = 10;
input double SuperTrend_Fast_Multiplier = 3.0;
input int SuperTrend_Slow_Period = 20;
input double SuperTrend_Slow_Multiplier = 2.0;

input double LotSize = 0.1;
input int Slippage = 3;
input int StopLoss = 100;
input int TakeProfit = 200;

ENUM_TRADE_STATE m_tradeState = TRADE_NONE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   EventSetTimer(60);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   double demaValue = iDEMA(Symbol(), Period(), DEMA_Period, DEMA_Offset, 0);
   double demaPrevValue = iDEMA(Symbol(), Period(), DEMA_Period, DEMA_Offset, 1);
   double superTrendFastValue = iCustom(Symbol(), Period(), "SuperTrend", SuperTrend_Fast_Period, SuperTrend_Fast_Multiplier, 0, 0);
   double superTrendSlowValue = iCustom(Symbol(), Period(), "SuperTrend", SuperTrend_Slow_Period, SuperTrend_Slow_Multiplier, 0, 0);

   bool isBullishDEMA = demaValue > demaPrevValue && MathAbs(demaValue - demaPrevValue) > DEMA_Sensitivity;
   bool isBearishDEMA = demaValue < demaPrevValue && MathAbs(demaValue - demaPrevValue) > DEMA_Sensitivity;

   bool isBullishSuperTrend = Bid > superTrendFastValue && Bid > superTrendSlowValue;
   bool isBearishSuperTrend = Bid < superTrendFastValue && Bid < superTrendSlowValue;

   if (isBullishDEMA && isBullishSuperTrend && m_tradeState != TRADE_BUY)
     {
      TradeBuy();
     }
   else if (isBearishDEMA && isBearishSuperTrend && m_tradeState != TRADE_SELL)
     {
      TradeSell();
     }
  }
//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer()
  {
   double demaValue = iDEMA(Symbol(), Period(), DEMA_Period, DEMA_Offset, 0);
   double demaPrevValue = iDEMA(Symbol(), Period(), DEMA_Period, DEMA_Offset, 1);
   double superTrendFastValue = iCustom(Symbol(), Period(), "SuperTrend", SuperTrend_Fast_Period, SuperTrend_Fast_Multiplier, 0, 0);
   double superTrendSlowValue = iCustom(Symbol(), Period(), "SuperTrend", SuperTrend_Slow_Period, SuperTrend_Slow_Multiplier, 0, 0);

   bool isBullishDEMA = demaValue > demaPrevValue && MathAbs(demaValue - demaPrevValue) > DEMA_Sensitivity;
   bool isBearishDEMA = demaValue < demaPrevValue && MathAbs(demaValue - demaPrevValue) > DEMA_Sensitivity;

   bool isBullishSuperTrend = Bid > superTrendFastValue && Bid > superTrendSlowValue;
   bool isBearishSuperTrend = Bid < superTrendFastValue && Bid < superTrendSlowValue;

   if (m_tradeState == TRADE_BUY && (isBearishDEMA || isBearishSuperTrend))
     {
      TradeClose();
     }
   else if (m_tradeState == TRADE_SELL && (isBullishDEMA || isBullishSuperTrend))
     {
      TradeClose();
     }
  }
//+------------------------------------------------------------------+
void TradeBuy()
  {
   if (m_tradeState == TRADE_NONE)
     {
      m_tradeState = TRADE_BUY;
      OrderSend(Symbol(), OP_BUY, LotSize, Ask, Slippage, Ask - StopLoss * _Point, Ask + TakeProfit * _Point, "Buy Order", 0, 0, clrGreen);
     }
  }
//+------------------------------------------------------------------+
void TradeSell()
  {
   if (m_tradeState == TRADE_NONE)
     {
      m_tradeState = TRADE_SELL;
      OrderSend(Symbol(), OP_SELL, LotSize, Bid, Slippage, Bid + StopLoss * _Point, Bid - TakeProfit * _Point, "Sell Order", 0, 0, clrRed);
     }
  }
//+------------------------------------------------------------------+
void TradeClose()
  {
   for (int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if (OrderSelect(i, SELECT_BY_POS))
        {
         if (OrderType() == OP_BUY)
           {
            OrderClose(OrderTicket(), OrderLots(), Bid, Slippage, clrRed);
           }
         else if (OrderType() == OP_SELL)
           {
            OrderClose(OrderTicket(), OrderLots(), Ask, Slippage, clrGreen);
           }
        }
     }
   m_tradeState = TRADE_NONE;
  }
//+------------------------------------------------------------------+
