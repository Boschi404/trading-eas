# trading-eas

qua teniamo organizzati tutti i bot, set files, ottimizazioni, eventuali validazioni

## EdgePoint (nostri, attivi)

| Bot | Strategia | TF | Build 2026-09-03 |
|---|---|---|---|
| [EdgePointScalper](EdgePointScalper/) | Breakout canale, pending bilaterali (+`variants/`: minimal debug, Tick every-tick) | M15 + EMA H4 | OK |
| [EdgePointScalper-v2](EdgePointScalper-v2/) | Come v1, single-side trend-only, tick-opt | M15 + EMA H4 | OK |
| [EdgePointMultiScaler](EdgePointMultiScaler/) | Direzionale 2 gambe TP1/TP2, ⚠️ scheletro | H4 | OK (ma logica da riscrivere) |
| [EdgePointMultiScaler-FX](EdgePointMultiScaler-FX/) | Breakout impulsivo H4, SL/TP ATR | H4 | OK |
| [EdgePointMultiStrat](EdgePointMultiStrat/) | 6 engine + ADX regime + martingale 1.3 | M5 | OK (ma segnali repaint — vedi review) |
| [EdgePointRejectionScaler](EdgePointRejectionScaler/) | Pin-bar rejection, doppio TP ATR | H4 + M30 | OK |

## Algory

| Bot | Nota | Build |
|---|---|---|
| [AlgoryPilot](AlgoryPilot/) | chart-automation via file comandi | OK |
| [AlgoryReplica](AlgoryReplica/) | engine v129 multi-segnale, SL 2.9×ATR TP 3.5×ATR (+`optimization/` .opt) | OK |

## Famiglia Nova

| Bot | Nota | Build |
|---|---|---|
| [NovaBenza](NovaBenza/) | SMC/ICT Pro AlphaMindAI v2.2 | OK |
| [NovaCancer](NovaCancer/) | inversione su soglia equity | OK |
| [NovaGamble](NovaGamble/) | Quasimodo + ZigZag | OK |
| [NovaHedge](NovaHedge/) | Heikin Ashi multi-close / hedge RSI | OK |
| [NovaArbitrage](NovaArbitrage/) | stat-arb z-score | ⚠️ BROKEN (7 errors) |

## Boschi & altri

| Bot | Nota | Build |
|---|---|---|
| [BoschiORB](BoschiORB/) | breakout range asiatica + martingale | ⚠️ BROKEN (2 errors) |
| [SuperHMD](SuperHMD/) | DEMA50 + SuperTrend + HeikenAshi | OK |
| [SuperBoschiTrend](SuperBoschiTrend/) | DEMA + doppio Supertrend (MQL4 da portare) | ⚠️ BROKEN |
| [quintupleEMA](quintupleEMA/) | allineamento 5 EMA | OK |
| [ScalpingGengar](ScalpingGengar/) | channel-breakout M5 (file corrotto?) | ⚠️ BROKEN (45 errors) |
| [ScalpingVez](ScalpingVez/) | trend EMA50 H4 + M1 | ⚠️ BROKEN (8 errors) |
| [MerfolzFX](MerfolzFX/) | Breakout Gold PRO + martingale | OK |
| [EPMultiAssetScalper](EPMultiAssetScalper/) | mean-reversion BB/RSI H1 | OK |
| [STOCHastic](STOCHastic/) | template stocastico MQL4-style | ⚠️ BROKEN |
| [SupaNiga](SupaNiga/) | supertrend (manca indicatore esterno) | ⚠️ BROKEN |

## Supporto

| Cartella | Contenuto |
|---|---|
| [LabTests](LabTests/) | toy di debug (TestBuy, TestMinimal, UltraMinimal) |
| [BinOnly](BinOnly/) | `.ex5` senza sorgente (UT BOSCHI EA) |
| [vendor-stock](vendor-stock/) | MT5 stock + 10 EA Market acquistati |
| [tester-presets](tester-presets/) | 660 preset tester in 72 gruppi per EA |

Ogni cartella bot: `.mq5` + `.ex5` (se compila) + `README.md` + `optimization/` dove presente.
