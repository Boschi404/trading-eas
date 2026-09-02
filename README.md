# trading-eas

qua teniamo organizzati tutti i bot, set files, ottimizazioni, eventuali validazioni

## Priorità 1 — funzionanti ([dettagli](Priorita-1/))

| Bot | Strategia | Build |
|---|---|---|
| [EdgePointScalper](Priorita-1/EdgePointScalper/) | Breakout canale M15, pending bilaterali (+`variants/` minimal/Tick) | OK |
| [EdgePointScalper-v2](Priorita-1/EdgePointScalper-v2/) | Single-side trend-only, tick-opt | OK |
| [EdgePointMultiScaler-FX](Priorita-1/EdgePointMultiScaler-FX/) | Breakout H4 FX, SL/TP ATR + 7 filtri | OK |
| [EdgePointRejectionScaler](Priorita-1/EdgePointRejectionScaler/) | Pin-bar H4 + M30, doppio TP ATR | OK |

## Priorità 2 — compilano, da revisionare ([dettagli](Priorita-2/))

| Bot | Build |
|---|---|
| [EdgePointMultiScaler](Priorita-2/EdgePointMultiScaler/) | OK (scheletro) |
| [AlgoryPilot](Priorita-2/AlgoryPilot/) | OK |
| [AlgoryReplica](Priorita-2/AlgoryReplica/) | OK 1w (+`optimization/` .opt) |
| [NovaBenza](Priorita-2/NovaBenza/) | OK |
| [NovaCancer](Priorita-2/NovaCancer/) | OK 2w |
| [NovaGamble](Priorita-2/NovaGamble/) | OK 2w |
| [NovaHedge](Priorita-2/NovaHedge/) | OK |
| [MerfolzFX](Priorita-2/MerfolzFX/) | OK (⚠️ martingale) |
| [EPMultiAssetScalper](Priorita-2/EPMultiAssetScalper/) | OK |
| [quintupleEMA](Priorita-2/quintupleEMA/) | OK 1w |
| [SuperHMD](Priorita-2/SuperHMD/) | OK 2w |

## Priorità 3 — rotti o pericolosi ([dettagli](Priorita-3/))

| Bot | Problema |
|---|---|
| [NovaArbitrage](Priorita-3/NovaArbitrage/) | 7 errors |
| [ScalpingGengar](Priorita-3/ScalpingGengar/) | 45 errors |
| [ScalpingVez](Priorita-3/ScalpingVez/) | 8 errors |
| [STOCHastic](Priorita-3/STOCHastic/) | MQL4 da portare |
| [SupaNiga](Priorita-3/SupaNiga/) | manca indicatore |
| [SuperBoschiTrend](Priorita-3/SuperBoschiTrend/) | MQL4 da portare |
| [BoschiORB](Priorita-3/BoschiORB/) | 2 errors |
| [EdgePointMultiStrat](Priorita-3/EdgePointMultiStrat/) | repaint + martingale senza cap |

## Supporto (fuori priorità)

| Cartella | Contenuto |
|---|---|
| [LabTests](LabTests/) | toy di debug |
| [vendor-stock](vendor-stock/) | MT5 stock + EA Market |
| [tester-presets](tester-presets/) | 660 preset in 72 gruppi |

Build verificate 2026-09-03 via metaeditor64 (log, non exit code).
