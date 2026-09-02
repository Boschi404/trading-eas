# trading-eas

qua teniamo organizzati tutti i bot, set files, ottimizazioni, eventuali validazioni

| Bot | Strategia | TF | Simboli | Risk |
|---|---|---|---|---|
| [EdgePointScalper](EdgePointScalper/) | Breakout canale, pending bilaterali | M15 + EMA H4 | qualsiasi | 2%, RR 1:2, trail 45 |
| [EdgePointScalper-v2](EdgePointScalper-v2/) | Come v1, single-side trend-only, tick-opt | M15 + EMA H4 | XAUUSD default | 2%, RR 1:2, trail 45 |
| [EdgePointMultiScaler](EdgePointMultiScaler/) | Direzionale 2 gambe TP1/TP2, ⚠️ scheletro | H4 | indici (MNQ) | lotto fisso 0.1 |
| [EdgePointMultiScaler-FX](EdgePointMultiScaler-FX/) | Breakout impulsivo H4, SL/TP ATR | H4 | EURUSD/GBPUSD/USDJPY | 0.5%, DD 30% |
| [EdgePointMultiStrat](EdgePointMultiStrat/) | 6 engine + ADX regime + martingale 1.3 | M5 | qualsiasi | 0.5%, DD 25% |
| [EdgePointRejectionScaler](EdgePointRejectionScaler/) | Pin-bar rejection, doppio TP ATR | H4 + M30 | qualsiasi | lotto 0.02, RR 1:2.5/5 |

Ogni cartella: `.mq5` sorgente + `.ex5` compilato + `README.md` dettagliato.
