# EdgePointRejectionScaler (v5)

Rejection/wick (pin-bar) H4 in trend forte: unico strutturale del set, niente medie/RSI come segnale — solo price action + ADX regime.

- TF: H4 (segnale) + conferma M30 (maggioranza ultime 3)
- Simboli: qualsiasi
- Indicatori: ADX14 (regime), ATR14 (SL/TP)

| Input | Default | Ruolo |
|---|---|---|
| ADX threshold / period | 22 / 14 | solo trend |
| WickBodyRatio / MinImpulsePt | 2.0 / 150 pt | qualità pin-bar |
| MinRecoveryPct / MinClosePos | 30% / 0.50 | chiusura forte |
| UseM30Filter / M30Bars | true / 3 | conferma |
| LotSize / ATR SL/TP1/TP2 | 0.02 / 0.8 / 2.0 / 4.0 | RR 1:2.5 e 1:5 |

Entry a mercato su nuova H4 dopo pin-bar validata + ADX + M30. Exit solo SL/TP (SL = estremo wick ± 0.8×ATR, 2 posizioni TP 2×/4× ATR). Max 1 set (magic 20260725), 1 segnale per barra.
