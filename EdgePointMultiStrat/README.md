# EdgePointMultiStrat (v1.0)

EA portafoglio adattivo: 6 engine commutabili, smistati dal filtro ADX. Il più complesso del set (dashboard on-chart + stat per strategia).

- TF: M5 hardcoded | Simboli: qualsiasi, single-chart
- Engine: WGC (EMA 12/50), CMF, MACD (12/26/9), Donchian (20), TGC (EMA 12/50), RSI (14, 70/30) — default ON: WGC, MACD, TGC

| Input | Default | Nota |
|---|---|---|
| RiskPct / FixedLot / Martingale | 0.5% / off / 1.3 ON | rincalzo globale `1.3^loss` |
| MaxDrawdown / MaxPos / ATR_Mult | 25% / 10 / 2.0 | SL/TP = ATR×mult, RR 1:1 |
| Trailing | 20 pip opt | — |
| ADX soglie | 20 / 25 | smista pessimistic/normal/optimistic |

Max 1 posizione per strategia (magic 123456 via comment) + throttle 1 trade/3 barre, flag `*_Invert` per segnale. ⚠️ Note: `UseADXFilter=false` ma `Execute()` lo usa comunque; stat win/loss attribuite male; TGC usa EMA non TEMA; Print debug eccessivi.
