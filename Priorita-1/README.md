# Priorità 1 — i più funzionanti

Bot revisionati nel codice + build OK + money management sano (niente martingale). Pronti per ottimizzazione/backtest serio.

| Bot | Perché qui |
|---|---|
| [EdgePointScalper](EdgePointScalper/) | breakout M15, sizing 2% su SL, DD-guard (voto 5.5/10) |
| [EdgePointScalper-v2](EdgePointScalper-v2/) | single-side trend-only, ingegneria migliore (6/10) |
| [EdgePointMultiScaler-FX](EdgePointMultiScaler-FX/) | ATR SL/TP + 7 filtri, il più disciplinato (7/10) |
| [EdgePointRejectionScaler](EdgePointRejectionScaler/) | pin-bar H4, idea migliore, codice onesto (6.5/10) |

Ordine di lavoro: breakeven a TP1 su FX+Rejection → fix barra-0 su Scalper → validazione filtri FX (trade count).
