# EdgePointScalper-v2 (v5.02 Tick-Ultra)

Come v1 ma single-side trend-only + ottimizzato tick (CopyRates, trailing rate-limited). Default spread pensato per XAUUSD.

- TF: M15 (segnale) + EMA50 H4 (filtro)
- Simboli: qualsiasi, default XAUUSD
- Indicatori: solo EMA50 H4, canale via CopyRates

| Gruppo | Input | Default |
|---|---|---|
| Strategy | BarsN / EntryDist / Expiry / TF | 12 / 555 pt / 612 / M15 |
| Target | SL / TP / TrailTrig / TrailStep | 915 / 1870 / 45 / 45 pt |
| Risk | Risk% / FixedLot / MaxLot / Spread / Magic | 2% / 0.01 / 1.0 / 3000 pt / 20240501 |

Diff vs v1: un solo lato (direzione trend), niente ATR/ADX dual-mode, niente session filter e max-DD guard; più controlli stops/freeze-level e AutoTrading.

## Optimization
- `optimization/`: .opt XAUUSD M15 2020-2026
