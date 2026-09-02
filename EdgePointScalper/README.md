# EdgePointScalper

Breakout del canale high/low ultime N barre con pending bilaterali (logica Donchian / NovaScalper). Unico del set a piazzare BuyStop + SellStop insieme.

- TF: M15 (segnale) + filtro EMA50 H4
- Simboli: qualsiasi (`_Symbol`)
- Indicatori: canale HH/LL, ATR14 (opt), ADX14 (opt, OFF default), EMA50 H4

| Input | Default | Nota |
|---|---|---|
| BarsN / EntryDist | 12 / 555 pt | canale + offset pending |
| FixedSL / FixedTP | 915 / 1870 pt | RR ~1:2 |
| ATR scalp/trend | 0.3/0.6, 1.5/3.0 | solo se UseATR=true |
| Risk% / MaxLot / MaxDD | 2% / 1.0 / 30% | sizing su SL, kill-switch |
| Trail trigger/step | 45 / 45 pt | ON default |
| Spread max | 50 pt | filtro |
| Expiry pending | 612 barre | |

Entry a nuova barra M15 se spread ok, nessuna posizione, DD ok → 2 stop. Exit: TP/SL + trailing ogni tick, pending a scadenza.
