//+------------------------------------------------------------------+
//|  MultiAsset_MR_EA_v2.mq5                                         |
//|  Multi-Asset Session Mean Reversion + Momentum — v2              |
//|                                                                  |
//|  FIX APPLICATI DAL BACKTEST (v1 → v2):                           |
//|  [FIX 1] Filtro ATR percentile — no entry se ATR > 65° pct       |
//|  [FIX 2] ADX threshold MR abbassato a 18 (era 24)                |
//|  [FIX 3] SL posizionato su BB(2.5σ) invece di 1.5×ATR            |
//|  [FIX 4] Monthly circuit breaker 3%                              |
//|  [FIX 5] Filtro RSI divergence (prezzo nuovo min, RSI no)        |
//|                                                                  |
//|  Strategia: BB(20,1.8) entry + BB(20,2.5) SL                     |
//|             RSI(14) + RSI divergence                             |
//|             ADX(14) < 18 + ATR percentile < 65°                  |
//|             Donchian(10) momentum                                |
//|  Timeframe: H1                                                   |
//|  Filtri:    Weekly CB + Monthly CB + Adaptive sizing             |
//+------------------------------------------------------------------+
#property copyright "MultiAsset_MR_EA v2"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Input parameters
input group "=== RISK MANAGEMENT ==="
input double   InpRiskPct         = 0.5;    // Rischio per trade (% del conto)
input double   InpWeeklyCB        = 2.5;    // Weekly circuit breaker (% DD)
input double   InpMonthlyCB       = 3.0;    // [FIX 4] Monthly circuit breaker (% DD)
input bool     InpAdaptiveSize    = true;   // Adaptive position sizing
input double   InpAdaptiveDD      = 10.0;   // DD% per ridurre size al 50%
input int      InpMagicNumber     = 202402; // Magic number EA (v2)

input group "=== STRATEGIA A — MEAN REVERSION ==="
input bool     InpUseMR           = true;   // Attiva Mean Reversion
input int      InpBB_Period       = 20;     // BB periodo
input double   InpBB_Entry        = 1.8;    // BB deviazione entry
input double   InpBB_SL_Dev       = 2.5;    // [FIX 3] BB deviazione Stop Loss (era ATR×1.5)
input int      InpRSI_Period      = 14;     // RSI periodo
input double   InpRSI_Long        = 38.0;   // RSI soglia long
input double   InpRSI_Short       = 62.0;   // RSI soglia short
input double   InpADX_MaxMR       = 18.0;   // [FIX 2] ADX max per MR (era 24)
input bool     InpUseRSIDiv       = true;   // [FIX 5] Filtro RSI divergence attivo
input int      InpRSIDiv_Lookback = 5;      // Candele lookback per divergence check
input int      InpMR_MaxHold      = 36;     // Max candele H1 in posizione

input group "=== [FIX 1] FILTRO ATR PERCENTILE ==="
input bool     InpUseATRFilter    = true;   // Attiva filtro ATR percentile
input int      InpATR_PctWindow   = 100;    // Finestra rolling per ATR percentile
input double   InpATR_PctMax      = 65.0;   // [FIX 1] Max percentile ATR per entry MR (0-100)

input group "=== STRATEGIA B — MOMENTUM ==="
input bool     InpUseTF           = true;   // Attiva Trend Following
input int      InpDon_Period      = 10;     // Donchian periodo
input double   InpADX_MinTF       = 20.0;   // ADX min per TF (trending)
input double   InpATR_Pct_TF_Min  = 55.0;   // ATR percentile min per TF entry
input double   InpTF_SL_ATR       = 2.0;    // SL moltiplicatore ATR
input double   InpTF_TP_ATR       = 4.5;    // TP moltiplicatore ATR
input double   InpTF_Trail_ATR    = 1.5;    // Trailing stop moltiplicatore
input int      InpTF_MaxHold      = 80;     // Max candele H1 in posizione

input group "=== SESSION FILTER ==="
input bool     InpSessionFilter   = true;   // Filtro sessione attivo
input int      InpSessionStart    = 8;      // Ora inizio trading (UTC)
input int      InpSessionEnd      = 21;     // Ora fine trading (UTC)

input group "=== ASSET SELECTION ==="
input bool     InpUse_AUDNZD      = true;   // AUDNZD
input bool     InpUse_AUDCAD      = true;   // AUDCAD
input bool     InpUse_EURGBP      = true;   // EURGBP
input bool     InpUse_EURNZD      = true;   // EURNZD
input bool     InpUse_USDCHF      = true;   // USDCHF
input bool     InpUse_XAUUSD      = true;   // XAUUSD (oro)
input bool     InpUse_US500       = false;  // US500/SP500 (CFD)
input bool     InpUse_USOIL       = false;  // USOIL (petrolio CFD)

input group "=== DASHBOARD ==="
input bool     InpShowPanel       = true;   // Mostra pannello info
input color    InpPanelColor      = clrDarkSlateGray;

//--- Struct per configurazione asset
struct AssetConfig
{
   string   symbol;
   bool     enabled;
   bool     isMR;
   bool     isTF;
   int      handleBB_Entry;   // BB(20, 1.8) — segnale entry
   int      handleBB_SL;      // [FIX 3] BB(20, 2.5) — livello SL
   int      handleRSI;
   int      handleADX;
   int      handleATR;
};

AssetConfig assets[8];
int         nAssets = 0;

//--- Circuit breaker: weekly
double   weeklyStartBal  = 0;
bool     weeklyPaused    = false;
datetime lastWeekStart   = 0;

//--- [FIX 4] Circuit breaker: monthly
double   monthlyStartBal = 0;
bool     monthlyPaused   = false;
datetime lastMonthStart  = 0;

//--- Portfolio tracking
double   portfolioHWM    = 0;   // high water mark

//--- Per-asset last bar time
datetime lastBarTime[8];

//--- Pannello
string   panelPfx = "MR2_EA_";

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   string symList[8]    = {"AUDNZD","AUDCAD","EURGBP","EURNZD","USDCHF","XAUUSD","US500","TXIUSD"};
   bool   enableList[8] = {InpUse_AUDNZD,InpUse_AUDCAD,InpUse_EURGBP,InpUse_EURNZD,
                           InpUse_USDCHF,InpUse_XAUUSD,InpUse_US500,InpUse_USOIL};
   nAssets = 0;

   for(int i = 0; i < 8; i++)
   {
      if(!enableList[i]) continue;
      if(!SymbolSelect(symList[i], true))
      {
         PrintFormat("WARN: simbolo %s non trovato, skipped.", symList[i]);
         continue;
      }

      assets[nAssets].symbol   = symList[i];
      assets[nAssets].enabled  = true;
      assets[nAssets].isMR     = InpUseMR;
      assets[nAssets].isTF     = InpUseTF;
      lastBarTime[nAssets]     = 0;

      //--- Handle indicatori
      assets[nAssets].handleBB_Entry = iBands(symList[i], PERIOD_H1, InpBB_Period, 0, InpBB_Entry,   PRICE_CLOSE);
      assets[nAssets].handleBB_SL    = iBands(symList[i], PERIOD_H1, InpBB_Period, 0, InpBB_SL_Dev,  PRICE_CLOSE); // [FIX 3]
      assets[nAssets].handleRSI      = iRSI  (symList[i], PERIOD_H1, InpRSI_Period, PRICE_CLOSE);
      assets[nAssets].handleADX      = iADX  (symList[i], PERIOD_H1, 14);
      assets[nAssets].handleATR      = iATR  (symList[i], PERIOD_H1, 14);

      if(assets[nAssets].handleBB_Entry == INVALID_HANDLE ||
         assets[nAssets].handleBB_SL    == INVALID_HANDLE ||
         assets[nAssets].handleRSI      == INVALID_HANDLE ||
         assets[nAssets].handleADX      == INVALID_HANDLE ||
         assets[nAssets].handleATR      == INVALID_HANDLE)
      {
         PrintFormat("ERROR: impossibile creare indicatori per %s", symList[i]);
         return INIT_FAILED;
      }
      nAssets++;
   }

   if(nAssets == 0) { Print("ERROR: nessun asset abilitato."); return INIT_FAILED; }

   portfolioHWM    = AccountInfoDouble(ACCOUNT_BALANCE);
   weeklyStartBal  = portfolioHWM;
   monthlyStartBal = portfolioHWM;
   lastWeekStart   = TimeCurrent();
   lastMonthStart  = TimeCurrent();

   PrintFormat("EA v2 inizializzato: %d asset, Magic=%d", nAssets, InpMagicNumber);
   PrintFormat("Fix attivi: ATR pct=%s ADX=%.0f BB_SL=%.1fσ MonthlyCB=%.1f%% RSIDiv=%s",
               InpUseATRFilter?"ON":"OFF", InpADX_MaxMR, InpBB_SL_Dev,
               InpMonthlyCB, InpUseRSIDiv?"ON":"OFF");

   if(InpShowPanel) BuildPanel();
   return INIT_SUCCEEDED;
}

//--- CTrade instance (deve essere dichiarato dopo gli input)
CTrade       trade;
CPositionInfo posInfo;

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   for(int i = 0; i < nAssets; i++)
   {
      IndicatorRelease(assets[i].handleBB_Entry);
      IndicatorRelease(assets[i].handleBB_SL);
      IndicatorRelease(assets[i].handleRSI);
      IndicatorRelease(assets[i].handleADX);
      IndicatorRelease(assets[i].handleATR);
   }
   DeletePanel();
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance > portfolioHWM) portfolioHWM = balance;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   //--- Weekly CB reset (ogni lunedì mattina)
   if(dt.day_of_week == 1)
   {
      MqlDateTime lastDt;
      TimeToStruct(lastWeekStart, lastDt);
      if(lastDt.day_of_week != 1 || (TimeCurrent() - lastWeekStart) > 86400)
      {
         weeklyStartBal = balance;
         weeklyPaused   = false;
         lastWeekStart  = TimeCurrent();
         PrintFormat("[CB] Weekly reset — start balance: %.2f", weeklyStartBal);
      }
   }

   //--- [FIX 4] Monthly CB reset (ogni 1° del mese)
   if(dt.day == 1)
   {
      MqlDateTime lastMDt;
      TimeToStruct(lastMonthStart, lastMDt);
      if(lastMDt.mon != dt.mon)
      {
         monthlyStartBal = balance;
         monthlyPaused   = false;
         lastMonthStart  = TimeCurrent();
         PrintFormat("[CB] Monthly reset — start balance: %.2f", monthlyStartBal);
      }
   }

   //--- Weekly CB check
   if(weeklyStartBal > 0)
   {
      double wDD = (weeklyStartBal - balance) / weeklyStartBal * 100.0;
      if(wDD >= InpWeeklyCB && !weeklyPaused)
      {
         weeklyPaused = true;
         PrintFormat("[CB WEEKLY] DD settimanale %.2f%% >= %.2f%% — trading sospeso fino a lunedì.", wDD, InpWeeklyCB);
      }
   }

   //--- [FIX 4] Monthly CB check
   if(monthlyStartBal > 0)
   {
      double mDD = (monthlyStartBal - balance) / monthlyStartBal * 100.0;
      if(mDD >= InpMonthlyCB && !monthlyPaused)
      {
         monthlyPaused = true;
         PrintFormat("[CB MONTHLY] DD mensile %.2f%% >= %.2f%% — trading sospeso fino al 1° del mese.", mDD, InpMonthlyCB);
      }
   }

   bool anyPaused = weeklyPaused || monthlyPaused;

   //--- Ciclo asset
   for(int i = 0; i < nAssets; i++)
   {
      if(!assets[i].enabled) continue;

      datetime curBar = iTime(assets[i].symbol, PERIOD_H1, 0);
      if(curBar == lastBarTime[i]) continue;
      lastBarTime[i] = curBar;

      ManageOpenPosition(i);

      if(!anyPaused)
         CheckEntry(i);
   }

   if(InpShowPanel) UpdatePanel();
}

//+------------------------------------------------------------------+
//| ManageOpenPosition — gestione posizioni aperte                   |
//+------------------------------------------------------------------+
void ManageOpenPosition(int idx)
{
   string sym = assets[idx].symbol;
   if(!posInfo.SelectByMagic(sym, InpMagicNumber)) return;

   long   posType = posInfo.PositionType();
   double posSL   = posInfo.StopLoss();
   double posTP   = posInfo.TakeProfit();
   double posCur  = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_BID)
                                                   : SymbolInfoDouble(sym, SYMBOL_ASK);
   double atr[1];
   if(CopyBuffer(assets[idx].handleATR, 0, 1, 1, atr) <= 0) return;

   string comment  = posInfo.Comment();
   bool   isTFPos  = (StringFind(comment, "TF") >= 0);

   if(isTFPos)
   {
      //--- Trailing stop ATR per posizioni TF
      double newSL = 0;
      if(posType == POSITION_TYPE_BUY)
      {
         newSL = posCur - InpTF_Trail_ATR * atr[0];
         if(newSL > posSL + SymbolInfoDouble(sym, SYMBOL_POINT))
            trade.PositionModify(posInfo.Ticket(), newSL, posTP);
      }
      else
      {
         newSL = posCur + InpTF_Trail_ATR * atr[0];
         if(newSL < posSL - SymbolInfoDouble(sym, SYMBOL_POINT) || posSL == 0)
            trade.PositionModify(posInfo.Ticket(), newSL, posTP);
      }

      //--- Max hold TF
      int barsHeld = (int)((TimeCurrent() - posInfo.Time()) / PeriodSeconds(PERIOD_H1));
      if(barsHeld >= InpTF_MaxHold)
      {
         PrintFormat("%s TF: max hold %d candele, chiusura.", sym, InpTF_MaxHold);
         trade.PositionClose(posInfo.Ticket());
      }
   }
   else
   {
      //--- MR: exit anticipata al BB mid
      double bbMid[1];
      if(CopyBuffer(assets[idx].handleBB_Entry, BASE_LINE, 1, 1, bbMid) <= 0) return;

      bool reachedMid = (posType == POSITION_TYPE_BUY  && posCur >= bbMid[0]) ||
                        (posType == POSITION_TYPE_SELL && posCur <= bbMid[0]);

      if(reachedMid)
      {
         PrintFormat("%s MR: BB mid (%.5f) raggiunto, chiusura.", sym, bbMid[0]);
         trade.PositionClose(posInfo.Ticket());
         return;
      }

      //--- Max hold MR
      int barsHeld = (int)((TimeCurrent() - posInfo.Time()) / PeriodSeconds(PERIOD_H1));
      if(barsHeld >= InpMR_MaxHold)
      {
         PrintFormat("%s MR: max hold %d candele, chiusura.", sym, InpMR_MaxHold);
         trade.PositionClose(posInfo.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//| [FIX 1] ATR Percentile — restituisce true se ATR è sotto soglia  |
//|         ovvero il mercato NON è in espansione di volatilità      |
//+------------------------------------------------------------------+
bool IsATRBelowPercentile(int handleATR, double maxPctile)
{
   if(!InpUseATRFilter) return true;   // filtro disabilitato → sempre ok

   int    w = InpATR_PctWindow;
   double buf[];
   ArrayResize(buf, w);

   if(CopyBuffer(handleATR, 0, 1, w, buf) < w) return true;

   //--- ATR corrente (barra 1)
   double curATR = buf[w-1];

   //--- Ordina la finestra e trova il percentile
   double sorted[];
   ArrayCopy(sorted, buf);
   ArraySort(sorted);

   int cutoffIdx = (int)MathFloor(w * maxPctile / 100.0);
   cutoffIdx = MathMax(0, MathMin(cutoffIdx, w - 1));
   double threshold = sorted[cutoffIdx];

   return (curATR <= threshold);
}

//+------------------------------------------------------------------+
//| [FIX 5] RSI Divergence — true se c'è divergenza bullish/bearish  |
//|  Bullish: prezzo fa nuovo minimo, RSI NON fa nuovo minimo        |
//|  Bearish: prezzo fa nuovo massimo, RSI NON fa nuovo massimo      |
//|  dir = +1 per long (cerca divergenza bullish)                    |
//|  dir = -1 per short (cerca divergenza bearish)                   |
//+------------------------------------------------------------------+
bool HasRSIDivergence(string sym, int handleRSI, int dir)
{
   if(!InpUseRSIDiv) return true;   // filtro disabilitato → sempre ok

   int lb = InpRSIDiv_Lookback;

   double rsiNow[1];
   if(CopyBuffer(handleRSI, 0, 1, 1, rsiNow) <= 0) return false;

   //--- Raccoglie lb barre di close e RSI
   double closes[]; double rsiArr[];
   ArrayResize(closes, lb); ArrayResize(rsiArr, lb);

   for(int b = 0; b < lb; b++)
   {
      closes[b] = iClose(sym, PERIOD_H1, b + 2);  // barre 2..lb+1
      double r[1];
      if(CopyBuffer(handleRSI, 0, b + 2, 1, r) <= 0) return false;
      rsiArr[b] = r[0];
   }

   double close1 = iClose(sym, PERIOD_H1, 1);

   if(dir == 1)   // cerca divergenza BULLISH
   {
      //--- Prezzo fa minimo assoluto nelle ultime lb barre?
      double prevLowClose = closes[0];
      for(int b = 1; b < lb; b++) if(closes[b] < prevLowClose) prevLowClose = closes[b];

      if(close1 >= prevLowClose) return false;  // prezzo non fa nuovo minimo → no div

      //--- RSI fa nuovo minimo?
      double prevLowRSI = rsiArr[0];
      for(int b = 1; b < lb; b++) if(rsiArr[b] < prevLowRSI) prevLowRSI = rsiArr[b];

      //--- Divergenza: prezzo nuovo min ma RSI NO
      return (rsiNow[0] > prevLowRSI);
   }
   else           // cerca divergenza BEARISH
   {
      //--- Prezzo fa massimo assoluto?
      double prevHighClose = closes[0];
      for(int b = 1; b < lb; b++) if(closes[b] > prevHighClose) prevHighClose = closes[b];

      if(close1 <= prevHighClose) return false;

      //--- RSI fa nuovo massimo?
      double prevHighRSI = rsiArr[0];
      for(int b = 1; b < lb; b++) if(rsiArr[b] > prevHighRSI) prevHighRSI = rsiArr[b];

      return (rsiNow[0] < prevHighRSI);
   }
}

//+------------------------------------------------------------------+
//| CheckEntry — segnali di ingresso                                 |
//+------------------------------------------------------------------+
void CheckEntry(int idx)
{
   string sym = assets[idx].symbol;
   if(posInfo.SelectByMagic(sym, InpMagicNumber)) return;

   //--- Session filter
   if(InpSessionFilter)
   {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      if(dt.hour < InpSessionStart || dt.hour >= InpSessionEnd) return;
   }

   //--- Carica indicatori (barra 1 = ultima candela chiusa)
   double bbEntryUp[1], bbEntryLow[1], bbMid[1];
   double bbSLUp[1], bbSLLow[1];
   double rsi[1], adx[1], atr[1];

   if(CopyBuffer(assets[idx].handleBB_Entry, UPPER_BAND, 1, 1, bbEntryUp)  <= 0) return;
   if(CopyBuffer(assets[idx].handleBB_Entry, LOWER_BAND, 1, 1, bbEntryLow) <= 0) return;
   if(CopyBuffer(assets[idx].handleBB_Entry, BASE_LINE,  1, 1, bbMid)      <= 0) return;
   if(CopyBuffer(assets[idx].handleBB_SL,    UPPER_BAND, 1, 1, bbSLUp)     <= 0) return;  // [FIX 3]
   if(CopyBuffer(assets[idx].handleBB_SL,    LOWER_BAND, 1, 1, bbSLLow)    <= 0) return;  // [FIX 3]
   if(CopyBuffer(assets[idx].handleRSI,      0,          1, 1, rsi)         <= 0) return;
   if(CopyBuffer(assets[idx].handleADX,      0,          1, 1, adx)         <= 0) return;
   if(CopyBuffer(assets[idx].handleATR,      0,          1, 1, atr)         <= 0) return;

   double atrVal  = atr[0];
   double close1  = iClose(sym, PERIOD_H1, 1);
   bool mrExecuted = false; // Flag to skip TF logic if MR executed

   // ================================================================
   // STRATEGIA A — MEAN REVERSION (con tutti i fix)
   // ================================================================
   if(assets[idx].isMR && InpUseMR)
   {
      bool mrValid = true;

      // [FIX 2] ADX threshold abbassato a 18
      if(adx[0] >= InpADX_MaxMR) mrValid = false;

      // [FIX 1] Filtro ATR percentile: no entry in alta volatilità
      if(mrValid && !IsATRBelowPercentile(assets[idx].handleATR, InpATR_PctMax)) mrValid = false;

      if(mrValid)
      {
         // Segnale base BB + RSI
         bool longSig  = (close1 <= bbEntryLow[0] && rsi[0] < InpRSI_Long);
         bool shortSig = (close1 >= bbEntryUp[0]  && rsi[0] > InpRSI_Short);

         if(longSig || shortSig)
         {
            int dir = longSig ? 1 : -1;

            // [FIX 5] Filtro RSI divergence
            if(HasRSIDivergence(sym, assets[idx].handleRSI, dir))
            {
               // Entry price
               double entry = (dir == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK)
                                         : SymbolInfoDouble(sym, SYMBOL_BID);

               // [FIX 3] SL posizionato alla BB(2.5σ) invece di 1.5×ATR
               double sl = (dir == 1) ? bbSLLow[0] - SymbolInfoDouble(sym, SYMBOL_POINT) * 5
                                      : bbSLUp[0]  + SymbolInfoDouble(sym, SYMBOL_POINT) * 5;

               // TP = BB midline
               double tp     = bbMid[0];
               double slDist = MathAbs(entry - sl);
               double tpDist = MathAbs(tp    - entry);

               // Validazione RR e distanza minima
               if(slDist > 0 && tpDist >= slDist * 0.4 && slDist >= atrVal * 0.3)
               {
                  sl = NormalizeDouble(sl, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));
                  tp = NormalizeDouble(tp, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));

                  double lots = CalcLotSize(sym, slDist);
                  if(lots > 0)
                  {
                     string comment = StringFormat("MR_%s", sym);
                     bool   sent    = (dir == 1) ? trade.Buy (lots, sym, entry, sl, tp, comment)
                                                 : trade.Sell(lots, sym, entry, sl, tp, comment);

                     if(sent)
                     {
                        PrintFormat("[MR] %s %s | entry=%.5f SL=%.5f(BB%.1fσ) TP=%.5f | lots=%.2f | ADX=%.1f RSI=%.1f ATRpct<%.0f",
                                    sym, dir==1?"BUY":"SELL", entry, sl, InpBB_SL_Dev, tp,
                                    lots, adx[0], rsi[0], InpATR_PctMax);
                        mrExecuted = true;
                     }
                  }
               }
            }
         }
      }
   }

   // ================================================================
   // STRATEGIA B — TREND FOLLOWING (Donchian breakout)
   // ================================================================
   if(!mrExecuted && assets[idx].isTF && InpUseTF && !posInfo.SelectByMagic(sym, InpMagicNumber))
   {
      if(adx[0] <= InpADX_MinTF) return;

      //--- Donchian 10 (barre 2..11)
      double donHigh = 0, donLow = DBL_MAX;
      for(int b = 2; b <= InpDon_Period + 1; b++)
      {
         double h = iHigh(sym, PERIOD_H1, b);
         double l = iLow (sym, PERIOD_H1, b);
         if(h > donHigh) donHigh = h;
         if(l < donLow)  donLow  = l;
      }

      //--- ATR expansion per TF (percentile > 55%)
      double atrBuf[];
      ArrayResize(atrBuf, InpATR_PctWindow);
      bool atrExpand = true;
      if(CopyBuffer(assets[idx].handleATR, 0, 1, InpATR_PctWindow, atrBuf) == InpATR_PctWindow)
      {
         double sorted[];
         ArrayCopy(sorted, atrBuf);
         ArraySort(sorted);
         int cutIdx = (int)MathFloor(InpATR_PctWindow * InpATR_Pct_TF_Min / 100.0);
         cutIdx = MathMax(0, MathMin(cutIdx, InpATR_PctWindow - 1));
         atrExpand = (atrBuf[InpATR_PctWindow - 1] >= sorted[cutIdx]);
      }
      if(!atrExpand) return;

      //--- DI+ e DI-
      double diP[1], diN[1];
      if(CopyBuffer(assets[idx].handleADX, 1, 1, 1, diP) <= 0) return;
      if(CopyBuffer(assets[idx].handleADX, 2, 1, 1, diN) <= 0) return;

      bool longBreak  = (close1 > donHigh && diP[0] > diN[0]);
      bool shortBreak = (close1 < donLow  && diN[0] > diP[0]);

      if(!longBreak && !shortBreak) return;

      int    dir   = longBreak ? 1 : -1;
      double entry = (dir == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK)
                                 : SymbolInfoDouble(sym, SYMBOL_BID);
      double sl    = entry - dir * InpTF_SL_ATR * atrVal;
      double tp    = entry + dir * InpTF_TP_ATR  * atrVal;
      double slDist = MathAbs(entry - sl);

      sl = NormalizeDouble(sl, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));
      tp = NormalizeDouble(tp, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));

      double lots = CalcLotSize(sym, slDist);
      if(lots <= 0) return;

      string comment = StringFormat("TF_%s", sym);
      bool   sent    = (dir == 1) ? trade.Buy (lots, sym, entry, sl, tp, comment)
                                  : trade.Sell(lots, sym, entry, sl, tp, comment);

      if(sent)
         PrintFormat("[TF] %s %s | entry=%.5f SL=%.5f TP=%.5f | lots=%.2f | ADX=%.1f Don_H=%.5f Don_L=%.5f",
                     sym, dir==1?"BUY":"SELL", entry, sl, tp, lots, adx[0], donHigh, donLow);
   }
}

//+------------------------------------------------------------------+
//| CalcLotSize — Fixed Fractional con adaptive sizing               |
//+------------------------------------------------------------------+
double CalcLotSize(string sym, double slDistance)
{
   if(slDistance <= 0) return 0;

   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);

   //--- Adaptive sizing: riduce size in proporzione al DD corrente
   double sizeMult = 1.0;
   if(InpAdaptiveSize && portfolioHWM > 0)
   {
      double currDD = (portfolioHWM - equity) / portfolioHWM * 100.0;
      sizeMult = MathMax(0.5, 1.0 - currDD / InpAdaptiveDD);
   }

   double riskAmt    = balance * (InpRiskPct / 100.0) * sizeMult;
   double tickVal    = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0 || tickSize <= 0) return 0;

   double pointValue = tickVal / tickSize;
   double lots       = riskAmt / (slDistance * pointValue);

   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lots, lotMin);
   lots = MathMin(lots, lotMax);
   return lots;
}

//+------------------------------------------------------------------+
//| Pannello on-chart                                                |
//+------------------------------------------------------------------+
void BuildPanel()
{
   DeletePanel();
   int x = 10, y = 30, lH = 16;
   int w = 310, h = 22 + lH * (nAssets + 9);

   string bg = panelPfx + "BG";
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE,   x - 5);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE,   y - 5);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE,        h);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,      InpPanelColor);
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE,  BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR,        clrGray);
   ObjectSetInteger(0, bg, OBJPROP_BACK,         false);

   CreateLbl(panelPfx + "Title", "MultiAsset MR+TF EA  v2", x, y, clrWhite, 9, true);
}

void UpdatePanel()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   int    x = 15, y = 48, lH = 16;

   double wDD = (weeklyStartBal  > 0) ? (weeklyStartBal  - balance) / weeklyStartBal  * 100.0 : 0;
   double mDD = (monthlyStartBal > 0) ? (monthlyStartBal - balance) / monthlyStartBal * 100.0 : 0;
   double pDD = (portfolioHWM    > 0) ? (portfolioHWM    - equity)  / portfolioHWM    * 100.0 : 0;

   string wSt = weeklyPaused  ? "PAUSED" : "OK";
   string mSt = monthlyPaused ? "PAUSED" : "OK";

   CreateLbl(panelPfx+"L0", StringFormat("Bal: %.2f  Eq: %.2f", balance, equity),            x, y,      clrSilver);
   CreateLbl(panelPfx+"L1", StringFormat("Weekly DD: %.2f%%  [%s]", wDD, wSt),               x, y+lH,   weeklyPaused  ? clrRed : clrLime);
   CreateLbl(panelPfx+"L2", StringFormat("Monthly DD: %.2f%%  [%s]", mDD, mSt),              x, y+lH*2, monthlyPaused ? clrRed : clrLime);
   CreateLbl(panelPfx+"L3", StringFormat("Portfolio DD: %.2f%%  HWM: %.2f", pDD, portfolioHWM), x, y+lH*3, clrSilver);

   int nOpen = 0;
   for(int i = 0; i < nAssets; i++)
      if(posInfo.SelectByMagic(assets[i].symbol, InpMagicNumber)) nOpen++;

   CreateLbl(panelPfx+"L4", StringFormat("Pos aperte: %d / %d  Risk: %.1f%%", nOpen, nAssets, InpRiskPct), x, y+lH*4, clrSilver);
   CreateLbl(panelPfx+"L5", StringFormat("ADX max MR: %.0f  BB_SL: %.1fσ  ATR<%.0f%%", InpADX_MaxMR, InpBB_SL_Dev, InpATR_PctMax), x, y+lH*5, clrAqua);

   for(int i = 0; i < nAssets; i++)
   {
      bool hasPos = posInfo.SelectByMagic(assets[i].symbol, InpMagicNumber);
      string posStr = "—"; color posCol = clrGray;
      if(hasPos)
      {
         double pnl = posInfo.Profit();
         bool   isBuy = (posInfo.PositionType() == POSITION_TYPE_BUY);
         string cmt   = posInfo.Comment();
         posStr = StringFormat("%s %s %.2f€", isBuy ? "▲" : "▼", StringFind(cmt,"TF")>=0?"TF":"MR", pnl);
         posCol = (pnl >= 0) ? clrLime : clrRed;
      }
      CreateLbl(panelPfx + "A" + IntegerToString(i),
                StringFormat("%-8s %s", assets[i].symbol, posStr),
                x, y + lH * (6 + i), posCol);
   }
}

void CreateLbl(string name, string text, int x, int y, color clr, int sz=8, bool bold=false)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  sz);
   ObjectSetString (0, name, OBJPROP_FONT,      bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
}

void DeletePanel() { ObjectsDeleteAll(0, panelPfx); }

//+------------------------------------------------------------------+
//| OnTradeTransaction — log deals                                   |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest&     req,
                        const MqlTradeResult&      res)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD &&
      (trans.deal_type == DEAL_TYPE_BUY || trans.deal_type == DEAL_TYPE_SELL))
   {
      // Seleziona il deal dallo storico per recuperare il profitto effettivo
      double dealProfit = 0.0;
      if(HistoryDealSelect(trans.deal))
      {
         dealProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      }

      PrintFormat("[DEAL] %s %s %.2f @ %.5f  profit=%.2f",
                  trans.symbol,
                  trans.deal_type == DEAL_TYPE_BUY ? "BUY" : "SELL",
                  trans.volume, trans.price, dealProfit);
   }
}
//+------------------------------------------------------------------+