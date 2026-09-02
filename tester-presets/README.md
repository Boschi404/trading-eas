# tester-presets

660 config Strategy Tester (`.ini` = setup test, `.set` = parametri), divise per EA: 72 gruppi. I nomi cartella sono senza spazi (mappa coi nomi file originali).

| Gruppo | File | Sorgente nel repo |
|---|---|---|
| NovaScalper | 149 | no (solo `.ex5` in `EdgePointScalper/optimization/reference-novascalper/`) |
| DarkVenusMT5 | 65 | no (Market, solo `.ex5`) |
| EdgePointMultiScaler | 55 | sì |
| MerfolzFX | 52 | sì |
| EdgePointMultiStrat | 12 | sì |
| NovaBenza | 12 | sì |
| Algory_Replica | 11 | sì |
| UTBOSCHIEA | 10 | no (solo `.ex5` in `BinOnly/`) |
| ExpertMAPSARSizeOptimized | 10 | sì (vendor-stock) |
| BoschiORB | 8 | sì (⚠️ non compila) |
| EdgePointScalper-v2 | 9 | sì |
| NovaCancer | 9 | sì |
| CAPStochasticEAMT5 | 9 | no (Market) |
| AWSuperTrendEAMT5 | 15 | no (Market) |
| ExpertMACD | 8 | sì (vendor-stock) |
| LevelXpertPro_v0.6.11.EN.DD01 | 8 | no (black-box) |
| NovaGPT / NovaGheo / SuperNova / NovaSnapper / NovaRetracements / NovaSR / NovaMartingale / NovaGamble / NovaHedge / NovaCancer | 3-21 | miste (vedi cartelle `Nova*`; per GPT/Gheo/SuperNova/Snapper/Retracements/SR/Martingale solo preset, niente sorgente) |
| GoldNova (18), EAStudio-* (28 tot), BotAGI (6), GPT-4oEA (1) | — | no (black-box, solo config test) |
| EPMultiAssetScalper (+`.US500`) | 7+1 set | sì |
| EdgePointScalper / EdgePointScalper_Tick / quintupleEMA / SuperHMD / SuperBoschiTrend / ScalpingVez / TestBuy / STOCHastic?no | 1-6 | sì (tranne preset orfani di EA senza sorgente) |
| `_meta/` | 4 | txt Groups/Symbols di MT5 |

Dettaglio completo: conta i file in ogni sottocartella.
