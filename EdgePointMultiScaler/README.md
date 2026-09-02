# EdgePointMultiScaler

(header interno `MNQ_Cycle_Corrected` v1.01) Scalper direzionale minimalista per indici: segue la candela di riferimento con 2 posizioni gemelle TP1/TP2.

- TF: new-bar su H4 (input `timeframe` non inizializzato — da fixare)
- Simboli: generico, distanze in pt indice → nato per MNQ/US30
- Indicatori: nessuno, solo OHLC

| Input | Default | Stato |
|---|---|---|
| InpTP1_Pt / TP2 | 45 / 85 | ✅ usati |
| InpSLBuffer_Pt | 5 | ✅ buffer su high/low |
| InpLotSize | 0.1 | ✅ fisso x2 |
| InpMinImpulsePt | 25 | ❌ orfano |
| InpMinRecoveryPct | 0.6 | ❌ orfano |

SL = estremo candela prec. ± buffer. Max 1 ciclo, no magic, no trailing/breakeven, no filtri spread/orari. ⚠️ Scheletro: `NormalizeLot()` mai chiamata, RR spesso sfavorevole (SL = intera candela H4).

## Optimization
- `optimization/`: 6 .opt H4 2010-2026 (ESCEURc, NDQUSD, SPIUSD/c, XAGUSD, XAUUSD) + `ndqusd-multiscaler.set`
