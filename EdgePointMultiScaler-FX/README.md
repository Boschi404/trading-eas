# EdgePointMultiScaler-FX (v4.0)

Breakout H4 su FX majors (EURUSD/GBPUSD/USDJPY): candela impulsiva → Buy/Sell Stop su max/min. Versione evoluta del MultiScaler base.

- TF: H4 | Simboli: FX majors (simbolo corrente)
- Indicatori: ATR14 (SL/TP), SMA200 (trend), ADX14 (anti-range)

| Input | Default |
|---|---|
| TF / MinCandle / Recovery | H4 / 150 pt / 50% |
| Risk% / MaxLot / MaxDD | 0.5% / 1.0 / 30% |
| SL / TP1 / TP2 (ATR p.14) | 1.5 / 2.0 / 4.0 |
| Filtri | SMA200, ADX≥22, MinATR 30 pt, spread 50, sess. 7-20 UTC, cooldown 4 loss → 2 barre |

Entry solo se close oltre SMA200 + ADX ok + spread/sessione ok. Exit: TP1=2×ATR (50%) + TP2=4×ATR (50%), SL=1.5×ATR oltre estremo + 20 pt. Pending cancellati a nuova barra.

Diff vs base: base = market immediato, lotto fisso, TP fissi; FX = pending + sizing % + SL/TP ATR + 6 filtri.
