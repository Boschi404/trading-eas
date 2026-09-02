//+------------------------------------------------------------------+
//|                                  EdgePointRejectionScaler v5     |
//+------------------------------------------------------------------+
#property copyright "Boschi404 + Hermes AI"
#property version "5.00"
#include <Trade/Trade.mqh>

int adxHandle, atrHandle;
datetime lastBarTime=0;

input group "=== REGIME FILTER ==="
input bool     InpUseADXFilter     = true;
input int      InpADXPeriod        = 14;
input double   InpADXThreshold     = 22.0;

input group "=== PIN BAR QUALITY ==="
input double   InpWickBodyRatio    = 2.0;
input int      InpMinImpulsePt     = 150;
input double   InpMinRecoveryPct   = 30.0;
input double   InpMinClosePos      = 0.50;

input group "=== MULTI-TF ==="
input bool     InpUseM30Filter     = true;
input int      InpM30Bars          = 3;

input group "=== TARGETS & RISK ==="
input double   InpLotSize          = 0.02;
input double   InpATRMultSL        = 0.8;
input double   InpATRMultTP1       = 2.0;
input double   InpATRMultTP2       = 4.0;
input int      InpATRPeriod        = 14;

input group "=== TIMEFRAME ==="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_H4;

CTrade trade;

int OnInit(){
   if(InpUseADXFilter){adxHandle=iADX(_Symbol,InpTimeframe,InpADXPeriod);if(adxHandle==INVALID_HANDLE)return INIT_FAILED;}
   atrHandle=iATR(_Symbol,InpTimeframe,InpATRPeriod);if(atrHandle==INVALID_HANDLE)return INIT_FAILED;
   trade.SetExpertMagicNumber(20260725);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int r){if(adxHandle!=INVALID_HANDLE)IndicatorRelease(adxHandle);IndicatorRelease(atrHandle);}

double GetADX(){if(!InpUseADXFilter)return 99;double v[1];CopyBuffer(adxHandle,0,1,1,v);return v[0];}
double GetATR(int s=1){double v[1];CopyBuffer(atrHandle,0,s,1,v);return v[0];}

bool M30Bullish(){
   if(!InpUseM30Filter)return true;
   double c[],o[];ArraySetAsSeries(c,true);ArraySetAsSeries(o,true);
   CopyClose(_Symbol,PERIOD_M30,0,InpM30Bars,c);CopyOpen(_Symbol,PERIOD_M30,0,InpM30Bars,o);
   int b=0;for(int i=0;i<InpM30Bars;i++)if(c[i]>o[i])b++;
   return b>=InpM30Bars/2+1;
}
bool M30Bearish(){
   if(!InpUseM30Filter)return true;
   double c[],o[];ArraySetAsSeries(c,true);ArraySetAsSeries(o,true);
   CopyClose(_Symbol,PERIOD_M30,0,InpM30Bars,c);CopyOpen(_Symbol,PERIOD_M30,0,InpM30Bars,o);
   int b=0;for(int i=0;i<InpM30Bars;i++)if(c[i]<o[i])b++;
   return b>=InpM30Bars/2+1;
}

void TryBuy(double open,double high,double low,double close,double range,double body,double atr){
   double lw=MathMin(open,close)-low;
   if(lw<=0||lw<body*InpWickBodyRatio||lw/_Point<InpMinImpulsePt)return;
   if((close-low)/range*100.0<InpMinRecoveryPct)return;
   if((close-low)/range<InpMinClosePos)return;
   if(!M30Bullish())return;
   double sl=low-atr*InpATRMultSL;
   double tp1=close+atr*InpATRMultTP1;
   double tp2=close+atr*InpATRMultTP2;
   if(SymbolInfoDouble(_Symbol,SYMBOL_ASK)-sl<=0)return;
   trade.Buy(InpLotSize,_Symbol,SymbolInfoDouble(_Symbol,SYMBOL_ASK),sl,tp1,"E1");
   trade.Buy(InpLotSize,_Symbol,SymbolInfoDouble(_Symbol,SYMBOL_ASK),sl,tp2,"E2");
}

void TrySell(double open,double high,double low,double close,double range,double body,double atr){
   double uw=high-MathMax(open,close);
   if(uw<=0||uw<body*InpWickBodyRatio||uw/_Point<InpMinImpulsePt)return;
   if((high-close)/range*100.0<InpMinRecoveryPct)return;
   if((high-close)/range<InpMinClosePos)return;
   if(!M30Bearish())return;
   double sl=high+atr*InpATRMultSL;
   double tp1=close-atr*InpATRMultTP1;
   double tp2=close-atr*InpATRMultTP2;
   if(sl-SymbolInfoDouble(_Symbol,SYMBOL_BID)<=0)return;
   trade.Sell(InpLotSize,_Symbol,SymbolInfoDouble(_Symbol,SYMBOL_BID),sl,tp1,"E1");
   trade.Sell(InpLotSize,_Symbol,SymbolInfoDouble(_Symbol,SYMBOL_BID),sl,tp2,"E2");
}

void OnTick(){
   datetime ct=iTime(_Symbol,InpTimeframe,0);
   if(ct==lastBarTime)return;
   lastBarTime=ct;
   if(GetADX()<InpADXThreshold)return;
   MqlRates r[];ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,InpTimeframe,1,1,r)<1)return;
   double range=r[0].high-r[0].low;
   if(range<=0)return;
   double body=MathAbs(r[0].close-r[0].open);
   double atr=GetATR(1);
   if(atr<=0)return;
   
   // CRITICAL: only one set of trades at a time
   int posTotal=0;
   for(int i=0;i<PositionsTotal();i++){
      ulong ticket=PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetInteger(POSITION_MAGIC)==20260725)
            posTotal++;
   }
   if(posTotal>0)return;
   
   TryBuy(r[0].open,r[0].high,r[0].low,r[0].close,range,body,atr);
   TrySell(r[0].open,r[0].high,r[0].low,r[0].close,range,body,atr);
}
