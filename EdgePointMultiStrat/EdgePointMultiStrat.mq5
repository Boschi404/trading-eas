//=============================================================================
// MultiStrat Bot v1.0 - MT5 Expert Advisor FINAL VERSION
// 6 Strategie Adattive con Risk Management Martingale Frazionale
// VERSIONE STABILE E FUNZIONANTE
//=============================================================================

#property copyright "MultiStrat Trading Bot"
#property link "https://tradingbot.com"
#property version "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//=============================================================================
// INPUT SETTINGS WITH GROUPS
//=============================================================================

input group "--- GENERAL SETTINGS ---"
input bool UseADXFilter = false;
input int ADX_Period = 14;
input double ADX_TrendLow = 20;
input double ADX_TrendHigh = 25;

input group "--- RISK MANAGEMENT ---"
input double RiskPct = 0.5;
input bool FixedLot = false;
input double FixedLotSize = 0.1;
input bool UseMartingale = true;  // Switch per abilitare/disabilitare Martingale
input double Martingale = 1.3;
input int MaxDrawdown = 25;
input int MaxPos = 10;
input double ATR_Multiplier = 2.0;  // SL = 2x ATR

input group "--- TRAILING STOP ---"
input bool UseTrailingStop = true;
input int TrailingStopPips = 20;

input group "--- UI SETTINGS ---"
input bool ShowUI = false;  // Disabilita per backtest veloce
input int UIX = 20;
input int UIY = 20;

input group "--- STRATEGY 1: WEIGHTED GOLDEN CROSS ---"
input bool WGC = true;  // TEST: disabilitato
input bool WGC_Invert = false;
input int WGC_Fast = 12;
input int WGC_Slow = 50;

input group "--- STRATEGY 2: CHAIKIN MONEY FLOW ---"
input bool CMF = false;  // DISABILITATO
input bool CMF_Invert = false;
input int CMF_Per = 20;
input double CMF_Thr = 0.3;  // Threshold Money Flow (0.1-0.7 è il range ottimale)

input group "--- STRATEGY 3: MACD ---"
input bool MACD_S = true;  // TEST: disabilitato
input bool MACD_Invert = false;
input int MACD_Fast = 12;
input int MACD_Slow = 26;
input int MACD_Sig = 9;

input group "--- STRATEGY 4: DONCHIAN CHANNELS ---"
input bool DC = false;  // DISABILITATO
input bool DC_Invert = false;
input int DC_Per = 20;

input group "--- STRATEGY 5: TEMA GOLDEN CROSS ---"
input bool TGC = true;
input bool TGC_Invert = false;
input int TGC_Fast = 12;
input int TGC_Slow = 50;

input group "--- STRATEGY 6: RSI + SUPERTREND ---"
input bool RSI_S = false;  // DISABILITATO
input bool RSI_Invert = false;
input int RSI_Per = 14;
input double RSI_High = 70;
input double RSI_Low = 30;

//=============================================================================
// ENUMS & STRUCTURES
//=============================================================================

enum STRATEGY_TYPE {
    WGC_ST = 0, CMF_ST = 1, MACD_ST = 2, DC_ST = 3, TGC_ST = 4, RSI_ST = 5
};

enum MARKET_CONDITION {
    MARKET_PESSIMISTIC = 0, MARKET_NORMAL = 1, MARKET_OPTIMISTIC = 2
};

//=============================================================================
// GLOBAL VARIABLES
//=============================================================================

CTrade trade;
CPositionInfo position_info;

int adx_h = INVALID_HANDLE;
int macd_h = INVALID_HANDLE;
int rsi_h = INVALID_HANDLE;
int ema12_h = INVALID_HANDLE;
int ema50_h = INVALID_HANDLE;
int tema_h = INVALID_HANDLE;
int atr_h = INVALID_HANDLE;
int tgc_fast_h = INVALID_HANDLE;  // EMA veloce per TGC
int tgc_slow_h = INVALID_HANDLE;  // EMA lenta per TGC

double adx_buf[3], macd_m[3], macd_s[3], rsi_buf[3], ema12[3], ema50[3], tema[3], atr_buf[3];
double tgc_fast[3], tgc_slow[3];  // Buffer per TGC

double equity = 0, peak_eq = 0, dd = 0;
double mart = 1.0;

int total_t[6], win_t[6], loss_t[6];
double profit_t[6];
string names[6] = {"WGC", "CMF", "MACD", "DC", "TGC", "RSI"};

int last_signal[6];
int consecutive_losses = 0;
int last_bar_open[6];

int prev_TGC_Fast = -1;  // Traccia cambiamenti TGC_Fast
int prev_TGC_Slow = -1;  // Traccia cambiamenti TGC_Slow
int prev_RSI_Per = -1;   // Traccia cambiamenti RSI_Per
int prev_RSI_Low = -1;   // Traccia cambiamenti RSI_Low
int prev_RSI_High = -1;  // Traccia cambiamenti RSI_High

//=============================================================================
// ONINIT
//=============================================================================

int OnInit() {
    trade.SetExpertMagicNumber(123456);

    adx_h = iADX(_Symbol, PERIOD_M5, ADX_Period);
    macd_h = iMACD(_Symbol, PERIOD_M5, MACD_Fast, MACD_Slow, MACD_Sig, PRICE_CLOSE);
    rsi_h = iRSI(_Symbol, PERIOD_M5, RSI_Per, PRICE_CLOSE);
    ema12_h = iMA(_Symbol, PERIOD_M5, WGC_Fast, 0, MODE_EMA, PRICE_CLOSE);
    ema50_h = iMA(_Symbol, PERIOD_M5, WGC_Slow, 0, MODE_EMA, PRICE_CLOSE);
    tema_h = iMA(_Symbol, PERIOD_M5, TGC_Fast, 0, MODE_EMA, PRICE_CLOSE);
    atr_h = iATR(_Symbol, PERIOD_M5, 14);
    tgc_fast_h = iMA(_Symbol, PERIOD_M5, TGC_Fast, 0, MODE_EMA, PRICE_CLOSE);
    tgc_slow_h = iMA(_Symbol, PERIOD_M5, TGC_Slow, 0, MODE_EMA, PRICE_CLOSE);

    if (adx_h == INVALID_HANDLE || macd_h == INVALID_HANDLE || rsi_h == INVALID_HANDLE) {
        return INIT_FAILED;
    }

    for(int i = 0; i < 6; i++) {
        total_t[i] = 0;
        win_t[i] = 0;
        loss_t[i] = 0;
        profit_t[i] = 0;
        last_signal[i] = 0;
        last_bar_open[i] = 0;
    }

    peak_eq = AccountInfoDouble(ACCOUNT_EQUITY);
    mart = 1.0;
    consecutive_losses = 0;
    
    // Inizializza per forzare ricreazione indicatori alla prima run
    prev_TGC_Fast = -1;
    prev_TGC_Slow = -1;
    prev_RSI_Per = -1;
    prev_RSI_Low = -1;
    prev_RSI_High = -1;

    if (ShowUI) CreateUI();

    return INIT_SUCCEEDED;
}

//=============================================================================
// ONTICK
//=============================================================================

void OnTick() {
    // Ricrea indicatori TGC se i parametri sono cambiati (per l'optimization)
    if (TGC_Fast != prev_TGC_Fast || TGC_Slow != prev_TGC_Slow) {
        if (tgc_fast_h != INVALID_HANDLE) IndicatorRelease(tgc_fast_h);
        if (tgc_slow_h != INVALID_HANDLE) IndicatorRelease(tgc_slow_h);
        
        tgc_fast_h = iMA(_Symbol, PERIOD_M5, TGC_Fast, 0, MODE_EMA, PRICE_CLOSE);
        tgc_slow_h = iMA(_Symbol, PERIOD_M5, TGC_Slow, 0, MODE_EMA, PRICE_CLOSE);
        
        prev_TGC_Fast = TGC_Fast;
        prev_TGC_Slow = TGC_Slow;
    }
    
    // Ricrea RSI se i parametri sono cambiati
    if (RSI_Per != prev_RSI_Per || RSI_Low != prev_RSI_Low || RSI_High != prev_RSI_High) {
        if (rsi_h != INVALID_HANDLE) IndicatorRelease(rsi_h);
        
        rsi_h = iRSI(_Symbol, PERIOD_M5, RSI_Per, PRICE_CLOSE);
        
        prev_RSI_Per = RSI_Per;
        prev_RSI_Low = (int)RSI_Low;
        prev_RSI_High = (int)RSI_High;
    }
    
    equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if (equity > peak_eq) peak_eq = equity;
    dd = ((peak_eq - equity) / peak_eq) * 100;

    if (dd > MaxDrawdown) mart = 1.0;

    int retry = 0;
    while (!LoadData() && retry < 3) { retry++; Sleep(100); }
    if (retry >= 3) return;

    MARKET_CONDITION cond = GetCondition();

    UpdateMartingaleOnClosedTrades();
    if (UseTrailingStop) ApplyTrailingStop();
    Execute(cond);

    if (ShowUI) UpdateUI();
}

//=============================================================================
// ONDEINIT
//=============================================================================

void OnDeinit(const int reason) {
    if (adx_h != INVALID_HANDLE) IndicatorRelease(adx_h);
    if (macd_h != INVALID_HANDLE) IndicatorRelease(macd_h);
    if (rsi_h != INVALID_HANDLE) IndicatorRelease(rsi_h);
    if (ema12_h != INVALID_HANDLE) IndicatorRelease(ema12_h);
    if (ema50_h != INVALID_HANDLE) IndicatorRelease(ema50_h);
    if (tema_h != INVALID_HANDLE) IndicatorRelease(tema_h);
    if (atr_h != INVALID_HANDLE) IndicatorRelease(atr_h);
    if (tgc_fast_h != INVALID_HANDLE) IndicatorRelease(tgc_fast_h);
    if (tgc_slow_h != INVALID_HANDLE) IndicatorRelease(tgc_slow_h);

    ObjectsDeleteAll(0, "MS_");
}

//=============================================================================
// FUNCTIONS
//=============================================================================

bool LoadData() {
    if (CopyBuffer(adx_h, 0, 0, 3, adx_buf) < 1) return false;
    if (CopyBuffer(macd_h, 0, 0, 3, macd_m) < 1) return false;
    if (CopyBuffer(macd_h, 1, 0, 3, macd_s) < 1) return false;
    if (CopyBuffer(rsi_h, 0, 0, 3, rsi_buf) < 1) return false;
    if (CopyBuffer(ema12_h, 0, 0, 3, ema12) < 1) return false;
    if (CopyBuffer(ema50_h, 0, 0, 3, ema50) < 1) return false;
    if (CopyBuffer(tema_h, 0, 0, 3, tema) < 1) return false;
    if (CopyBuffer(atr_h, 0, 0, 3, atr_buf) < 1) return false;
    if (CopyBuffer(tgc_fast_h, 0, 0, 3, tgc_fast) < 1) return false;
    if (CopyBuffer(tgc_slow_h, 0, 0, 3, tgc_slow) < 1) return false;
    return true;
}

MARKET_CONDITION GetCondition() {
    if (adx_buf[0] < ADX_TrendLow) return MARKET_PESSIMISTIC;
    if (adx_buf[0] < ADX_TrendHigh) return MARKET_NORMAL;
    return MARKET_OPTIMISTIC;
}

void Execute(MARKET_CONDITION cond) {
    int pos = CountPos();
    
    // TEMPORANEAMENTE DISABILITATO per testare DC
    // if (adx_buf[0] < 20) return;
    
    Print("DEBUG Execute: cond=" + IntegerToString(cond) + " pos=" + IntegerToString(pos));
    
    if (cond == MARKET_PESSIMISTIC) {
        if (WGC && pos < MaxPos) ExecWGC();
        if (CMF && pos < MaxPos) ExecCMF();
    } else if (cond == MARKET_NORMAL) {
        Print("DEBUG: MARKET_NORMAL - calling ExecMACD and ExecDC");
        if (MACD_S && pos < MaxPos) ExecMACD();
        if (DC && pos < MaxPos) {
            Print("DEBUG: DC is enabled, calling ExecDC");
            ExecDC();
        }
    } else {
        if (TGC && pos < MaxPos) ExecTGC();
        if (RSI_S && pos < MaxPos) ExecRSI();
    }
}

void ExecWGC() {
    if (HasOpenPosition(WGC_ST)) return;
    
    // Apri max 1 trade ogni 3 candele
    int current_bar = iBars(_Symbol, PERIOD_M5) - 1;
    if (current_bar - last_bar_open[WGC_ST] < 3) return;
    
    ENUM_ORDER_TYPE buy_type = WGC_Invert ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    ENUM_ORDER_TYPE sell_type = WGC_Invert ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    
    if (ema12[1] <= ema50[1] && ema12[0] > ema50[0]) {
        if (last_signal[WGC_ST] != 1) {
            OpenTrade(WGC_ST, buy_type);
            last_signal[WGC_ST] = 1;
            last_bar_open[WGC_ST] = current_bar;
        }
    } else if (ema12[1] >= ema50[1] && ema12[0] < ema50[0]) {
        if (last_signal[WGC_ST] != -1) {
            OpenTrade(WGC_ST, sell_type);
            last_signal[WGC_ST] = -1;
            last_bar_open[WGC_ST] = current_bar;
        }
    }
}

void ExecCMF() {
    if (HasOpenPosition(CMF_ST)) return;
    
    // Apri max 1 trade ogni 3 candele
    int current_bar = iBars(_Symbol, PERIOD_M5) - 1;
    if (current_bar - last_bar_open[CMF_ST] < 3) return;
    
    ENUM_ORDER_TYPE buy_type = CMF_Invert ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    ENUM_ORDER_TYPE sell_type = CMF_Invert ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    
    // CMF: Money Flow Ratio
    double h = iHigh(_Symbol, PERIOD_M5, 0);
    double l = iLow(_Symbol, PERIOD_M5, 0);
    double c = iClose(_Symbol, PERIOD_M5, 0);
    
    if (h == l) return;
    
    // Money Flow: (close-low)-(high-close) / (high-low)
    double mf = ((c - l) - (h - c)) / (h - l);
    
    // Usa CMF_Thr dai settings (0.0 a 1.0)
    double threshold = CMF_Thr;
    
    if (mf > threshold) {
        if (last_signal[CMF_ST] != 1) {
            OpenTrade(CMF_ST, buy_type);
            last_signal[CMF_ST] = 1;
            last_bar_open[CMF_ST] = current_bar;
        }
    } else if (mf < -threshold) {
        if (last_signal[CMF_ST] != -1) {
            OpenTrade(CMF_ST, sell_type);
            last_signal[CMF_ST] = -1;
            last_bar_open[CMF_ST] = current_bar;
        }
    }
}

void ExecMACD() {
    if (HasOpenPosition(MACD_ST)) return;
    ENUM_ORDER_TYPE buy_type = MACD_Invert ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    ENUM_ORDER_TYPE sell_type = MACD_Invert ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    
    if (macd_m[1] <= macd_s[1] && macd_m[0] > macd_s[0]) {
        if (last_signal[MACD_ST] != 1) {
            OpenTrade(MACD_ST, buy_type);
            last_signal[MACD_ST] = 1;
        }
    } else if (macd_m[1] >= macd_s[1] && macd_m[0] < macd_s[0]) {
        if (last_signal[MACD_ST] != -1) {
            OpenTrade(MACD_ST, sell_type);
            last_signal[MACD_ST] = -1;
        }
    }
}

void ExecDC() {
    if (HasOpenPosition(DC_ST)) return;
    
    int current_bar = iBars(_Symbol, PERIOD_M5) - 1;
    if (current_bar - last_bar_open[DC_ST] < 3) return;
    
    ENUM_ORDER_TYPE buy_type = DC_Invert ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    ENUM_ORDER_TYPE sell_type = DC_Invert ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    
    // Donchian Channels
    int highest_idx = iHighest(_Symbol, PERIOD_M5, MODE_HIGH, DC_Per, 0);
    int lowest_idx = iLowest(_Symbol, PERIOD_M5, MODE_LOW, DC_Per, 0);
    
    double dh = iHigh(_Symbol, PERIOD_M5, highest_idx);
    double dl = iLow(_Symbol, PERIOD_M5, lowest_idx);
    
    double cc = iClose(_Symbol, PERIOD_M5, 0);
    double cp = iClose(_Symbol, PERIOD_M5, 1);
    double ch = iHigh(_Symbol, PERIOD_M5, 0);   // High current
    double cl = iLow(_Symbol, PERIOD_M5, 0);    // Low current
    
    Print("DEBUG DC: dh=" + DoubleToString(dh, 5) + 
          " dl=" + DoubleToString(dl, 5) + 
          " ch=" + DoubleToString(ch, 5) + 
          " cl=" + DoubleToString(cl, 5) + 
          " cc=" + DoubleToString(cc, 5));
    
    // Breakout al rialzo: chiude sopra il massimo Donchian (o tocca e chiude sopra)
    if (cc > dh || (ch >= dh && cc > cp)) {
        Print("DEBUG DC: BUY SIGNAL");
        if (last_signal[DC_ST] != 1) {
            OpenTrade(DC_ST, buy_type);
            last_signal[DC_ST] = 1;
            last_bar_open[DC_ST] = current_bar;
        }
    } 
    // Breakout al ribasso: chiude sotto il minimo Donchian (o tocca e chiude sotto)
    else if (cc < dl || (cl <= dl && cc < cp)) {
        Print("DEBUG DC: SELL SIGNAL");
        if (last_signal[DC_ST] != -1) {
            OpenTrade(DC_ST, sell_type);
            last_signal[DC_ST] = -1;
            last_bar_open[DC_ST] = current_bar;
        }
    }
}

void ExecTGC() {
    if (HasOpenPosition(TGC_ST)) return;
    
    int current_bar = iBars(_Symbol, PERIOD_M5) - 1;
    if (current_bar - last_bar_open[TGC_ST] < 3) return;
    
    ENUM_ORDER_TYPE buy_type = TGC_Invert ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    ENUM_ORDER_TYPE sell_type = TGC_Invert ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    
    Print("DEBUG TGC: TGC_Fast=" + IntegerToString(TGC_Fast) + 
          " TGC_Slow=" + IntegerToString(TGC_Slow) +
          " tgc_fast[0]=" + DoubleToString(tgc_fast[0], 5) +
          " tgc_slow[0]=" + DoubleToString(tgc_slow[0], 5));
    
    // Usa i parametri TGC_Fast e TGC_Slow
    if (tgc_fast[1] <= tgc_slow[1] && tgc_fast[0] > tgc_slow[0]) {
        Print("DEBUG TGC: BUY SIGNAL");
        if (last_signal[TGC_ST] != 1) {
            OpenTrade(TGC_ST, buy_type);
            last_signal[TGC_ST] = 1;
            last_bar_open[TGC_ST] = current_bar;
        }
    } else if (tgc_fast[1] >= tgc_slow[1] && tgc_fast[0] < tgc_slow[0]) {
        Print("DEBUG TGC: SELL SIGNAL");
        if (last_signal[TGC_ST] != -1) {
            OpenTrade(TGC_ST, sell_type);
            last_signal[TGC_ST] = -1;
            last_bar_open[TGC_ST] = current_bar;
        }
    }
}

void ExecRSI() {
    if (HasOpenPosition(RSI_ST)) return;
    
    int current_bar = iBars(_Symbol, PERIOD_M5) - 1;
    if (current_bar - last_bar_open[RSI_ST] < 3) return;
    
    ENUM_ORDER_TYPE buy_type = RSI_Invert ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    ENUM_ORDER_TYPE sell_type = RSI_Invert ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    
    double r = rsi_buf[0];
    double r_prev = rsi_buf[1];
    
    Print("DEBUG RSI: RSI=" + DoubleToString(r, 2) + 
          " Low=" + DoubleToString(RSI_Low, 2) + 
          " High=" + DoubleToString(RSI_High, 2));
    
    // BUY: RSI entra in oversold (incrocia la soglia bassa dal basso)
    if (r < RSI_Low && r_prev >= RSI_Low) {
        Print("DEBUG RSI: BUY SIGNAL - RSI oversold");
        if (last_signal[RSI_ST] != 1) {
            OpenTrade(RSI_ST, buy_type);
            last_signal[RSI_ST] = 1;
            last_bar_open[RSI_ST] = current_bar;
        }
    } 
    // SELL: RSI entra in overbought (incrocia la soglia alta dall'alto)
    else if (r > RSI_High && r_prev <= RSI_High) {
        Print("DEBUG RSI: SELL SIGNAL - RSI overbought");
        if (last_signal[RSI_ST] != -1) {
            OpenTrade(RSI_ST, sell_type);
            last_signal[RSI_ST] = -1;
            last_bar_open[RSI_ST] = current_bar;
        }
    }
}

void OpenTrade(STRATEGY_TYPE st, ENUM_ORDER_TYPE ot) {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    // Calcola SL basato su ATR 2x
    double atr_value = atr_buf[0];
    double sl_distance = atr_value * ATR_Multiplier;
    double sl_pips = sl_distance / pt;

    double lot = CalcLot((int)sl_pips);
    if (lot <= 0) return;

    lot = lot * mart;

    double open_price, sl_p, tp_p;
    
    if (ot == ORDER_TYPE_BUY) {
        open_price = ask;
        sl_p = open_price - sl_distance;
        tp_p = open_price + sl_distance;  // RR 1:1: TP = SL distance
    } else {
        open_price = bid;
        sl_p = open_price + sl_distance;
        tp_p = open_price - sl_distance;  // RR 1:1: TP = SL distance
    }

    if (trade.PositionOpen(_Symbol, ot, lot, open_price, sl_p, tp_p, names[st])) {
        total_t[st]++;
    }
}

void ApplyTrailingStop() {
    double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (position_info.SelectByIndex(i)) {
            if (position_info.Magic() == 123456 && position_info.Symbol() == _Symbol) {
                double current_sl = position_info.StopLoss();
                double current_price = position_info.PriceCurrent();
                
                if (position_info.PositionType() == POSITION_TYPE_BUY) {
                    double new_sl = current_price - (TrailingStopPips * pt);
                    if (new_sl > current_sl) {
                        trade.PositionModify(position_info.Ticket(), new_sl, position_info.TakeProfit());
                    }
                } else {
                    double new_sl = current_price + (TrailingStopPips * pt);
                    if (new_sl < current_sl) {
                        trade.PositionModify(position_info.Ticket(), new_sl, position_info.TakeProfit());
                    }
                }
            }
        }
    }
}

void UpdateMartingaleOnClosedTrades() {
    int deals = HistoryDealsTotal();
    static int last_deal = 0;
    
    if (deals > last_deal) {
        for (int i = last_deal; i < deals; i++) {
            ulong t = HistoryDealGetTicket(i);
            if (t <= 0) continue;
            
            ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY);
            if (entry != DEAL_ENTRY_OUT) continue;
            
            double profit = HistoryDealGetDouble(t, DEAL_PROFIT);
            
            // Conta win/loss globalmente (tutte le strategie)
            for (int j = 0; j < 6; j++) {
                if (total_t[j] > 0) {
                    if (profit > 0) {
                        win_t[j]++;
                        profit_t[j] += profit;
                    } else if (profit < 0) {
                        loss_t[j]++;
                        profit_t[j] += profit;
                    }
                    break;
                }
            }
            
            // Aggiorna Martingale GLOBALE
            if (UseMartingale) {
                if (profit > 0) {
                    consecutive_losses = 0;
                    mart = 1.0;
                    Print("WIN - Martingale reset to 1.0");
                } else if (profit < 0) {
                    consecutive_losses++;
                    // Aumenta subito da perdita #1
                    mart = MathPow(Martingale, consecutive_losses);
                    Print("LOSS #" + IntegerToString(consecutive_losses) + " - Martingale = " + DoubleToString(mart, 3));
                }
            } else {
                mart = 1.0;
            }
        }
        last_deal = deals;
    }
}

double CalcLot(int sl) {
    if (FixedLot) return FixedLotSize;

    double bal = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk = bal * (RiskPct / 100.0);
    double pv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    
    double lot = 0;
    if (pv > 0) lot = risk / (sl * pv);

    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    lot = MathRound(lot / lot_step) * lot_step;
    lot = (lot < min_lot) ? min_lot : lot;
    lot = (lot > max_lot) ? max_lot : lot;

    return lot;
}

int CountPos() {
    int c = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (position_info.SelectByIndex(i)) {
            if (position_info.Magic() == 123456 && position_info.Symbol() == _Symbol) c++;
        }
    }
    return c;
}

bool HasOpenPosition(STRATEGY_TYPE st) {
    string strategy_name = names[st];
    
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (position_info.SelectByIndex(i)) {
            if (position_info.Magic() == 123456 && position_info.Symbol() == _Symbol) {
                string comment = position_info.Comment();
                if (StringFind(comment, strategy_name) >= 0) {
                    return true; // Questa strategia ha una posizione aperta
                }
            }
        }
    }
    return false;
}

//=============================================================================
// UI
//=============================================================================

void CreateUI() {
    ObjectCreate(0, "MS_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "MS_BG", OBJPROP_XDISTANCE, UIX);
    ObjectSetInteger(0, "MS_BG", OBJPROP_YDISTANCE, UIY);
    ObjectSetInteger(0, "MS_BG", OBJPROP_XSIZE, 500);
    ObjectSetInteger(0, "MS_BG", OBJPROP_YSIZE, 250);
    ObjectSetInteger(0, "MS_BG", OBJPROP_BGCOLOR, 0x1a1a1a);
    ObjectSetInteger(0, "MS_BG", OBJPROP_BORDER_COLOR, 0x00ff00);
    ObjectSetInteger(0, "MS_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, "MS_BG", OBJPROP_HIDDEN, true);

    MakeLabel("MS_Title", UIX + 10, UIY + 8, "MULTISTRAT BOT v1.0", 12, 0x00ff00);

    for (int i = 0; i < 6; i++) {
        int y = UIY + 40 + (i * 20);
        MakeLabel("MS_S" + IntegerToString(i), UIX + 10, y, names[i], 10, 0x00ffff);
        MakeLabel("MS_T" + IntegerToString(i), UIX + 110, y, "0", 10, 0xffffff);
        MakeLabel("MS_W" + IntegerToString(i), UIX + 170, y, "0%", 10, 0xffffff);
    }

    MakeLabel("MS_EqL", UIX + 10, UIY + 180, "Equity: ", 9, 0xffffff);
    MakeLabel("MS_EqV", UIX + 120, UIY + 180, "0", 9, 0x00ff00);
    
    MakeLabel("MS_DL", UIX + 10, UIY + 200, "DD: ", 9, 0xffffff);
    MakeLabel("MS_DV", UIX + 120, UIY + 200, "0%", 9, 0xff9900);
}

void MakeLabel(string n, int x, int y, string t, int sz, color c) {
    ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, n, OBJPROP_TEXT, t);
    ObjectSetInteger(0, n, OBJPROP_FONTSIZE, sz);
    ObjectSetInteger(0, n, OBJPROP_COLOR, c);
    ObjectSetString(0, n, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
}

void UpdateUI() {
    if (!ShowUI) return;
    
    for (int i = 0; i < 6; i++) {
        ObjectSetString(0, "MS_T" + IntegerToString(i), OBJPROP_TEXT, IntegerToString(total_t[i]));
        double wr = (total_t[i] > 0) ? (double)win_t[i] / total_t[i] * 100 : 0;
        ObjectSetString(0, "MS_W" + IntegerToString(i), OBJPROP_TEXT, DoubleToString(wr, 1) + "%");
    }
    
    ObjectSetString(0, "MS_EqV", OBJPROP_TEXT, DoubleToString(equity, 2));
    ObjectSetString(0, "MS_DV", OBJPROP_TEXT, DoubleToString(dd, 2) + "%");
}

//=============================================================================
// END
//=============================================================================