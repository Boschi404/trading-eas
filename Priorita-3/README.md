# Priorità 3 — rotti o pericolosi, da fixare prima di qualunque uso

| Bot | Problema (build verificata 2026-09-03) |
|---|---|
| [NovaArbitrage](NovaArbitrage/) | 7 errors (`MathMean`/`MathStandardDev` inesistenti) |
| [ScalpingGengar](ScalpingGengar/) | 45 errors (identificatori duplicati — file corrotto?) |
| [ScalpingVez](ScalpingVez/) | 8 errors (CopyBuffer/array) |
| [STOCHastic](STOCHastic/) | 10+ errors (MQL4: `MODE_MAIN`, `high`/`low`) |
| [SupaNiga](SupaNiga/) | 6 errors (manca indicatore esterno + include) |
| [SuperBoschiTrend](SuperBoschiTrend/) | 10+ errors (MQL4: `Bid`, `TRADE_BUY/SELL`) |
| [BoschiORB](BoschiORB/) | 2 errors, 6 warnings |
| [EdgePointMultiStrat](EdgePointMultiStrat/) | compila MA pericoloso: segnali repaint + martingale senza cap |

Regola: niente reale/demo finché non escono dalla P3 con build OK + review.
