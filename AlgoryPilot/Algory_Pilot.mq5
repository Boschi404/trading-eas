//+------------------------------------------------------------------+
//|                                                 Algory_Pilot.mq5 |
//|                                                           Algory |
//+------------------------------------------------------------------+
//| Chart automation agent for Algory Full Deploy.                   |
//|                                                                  |
//| The Algory dashboard queues commands into MQL5\Files as one      |
//| file per command (algory_pilot_cmd_<ms>_<nnn>.txt, temp-then-    |
//| rename); this EA sweeps the wildcard on a 2s timer, deletes each |
//| file BEFORE executing it (crash safety: a bad command must never |
//| replay on restart), then processes each line:                    |
//|                                                                  |
//|   OPEN|SYMBOL|TF|template.tpl                                    |
//|       select symbol in Market Watch, open a chart on TF, apply   |
//|       \Profiles\Templates\template.tpl (retry loop) so the       |
//|       Algory EA embedded in the template attaches and runs.      |
//|   CLOSE|SYMBOL|TF|ExpertName                                     |
//|       close every open chart matching symbol + period whose      |
//|       attached expert is ExpertName.                             |
//|                                                                  |
//| It also refreshes algory_pilot_status.txt every ~10s (login,     |
//| live/demo, autotrading state) so the dashboard can show account  |
//| context on the Full Deploy screen, and appends results to        |
//| algory_pilot_log.txt.                                            |
//|                                                                  |
//| LIVE TRADE LEDGER (build 6): once a minute it walks the closed   |
//| deal history and appends one row per CLOSED position to          |
//| algory_live_trades.csv - magic, symbol, both fill PRICES, both   |
//| times, volume, profit/swap/commission. Local file only; nothing  |
//| is sent anywhere. It exists to answer one question offline: did  |
//| the live fills match what the backtest predicted. Deals with     |
//| magic 0 (the user's own manual trading) are NEVER recorded.      |
//|                                                                  |
//| This EA NEVER places trades itself. No magic number, no orders.  |
//+------------------------------------------------------------------+
#property copyright   "Algory"
#property version     "1.11"
#property description "Algory Pilot: opens/closes charts and attaches Algory EAs on command from the Algory dashboard. Never trades itself."

// Bumped whenever the Pilot source changes so the dashboard's
// ensure_pilot_installed re-copies + recompiles a stale Pilot on the next
// deploy (older installs would otherwise keep running the old .ex5).
#define ALGORY_PILOT_BUILD 6

#define PILOT_CMD_FILE    "algory_pilot_cmd.txt"
#define PILOT_STATUS_FILE "algory_pilot_status.txt"
#define PILOT_LOG_FILE    "algory_pilot_log.txt"
#define PILOT_LABEL_NAME  "ALGORY_PILOT_LBL"

// ---- live trade ledger ----------------------------------------------------
#define PILOT_LEDGER_FILE     "algory_live_trades.csv"
#define PILOT_LEDGER_TMP      "algory_live_trades.csv.tmp"
#define LEDGER_VER            1
#define LEDGER_SCAN_MS        60000   // one history scan a minute (commands stay 2s)
#define LEDGER_SEED_DAYS      365     // first scan after a start: backfill a year
#define LEDGER_WINDOW_DAYS    45      // every scan after that (matches decay_monitor)
#define LEDGER_MAX_NEW_PASS   25      // rows written per scan - bounded work per timer
#define LEDGER_MAX_ROWS       4000    // compaction trigger
#define LEDGER_KEEP_ROWS      2000    // rows retained on compaction
#define LEDGER_COMMENT_MAX    48

ulong g_last_status_ms = 0;

// Position ids already written, kept SORTED for a binary-search dedupe. Loaded
// from the ledger file at start, so a Pilot restart (which happens constantly)
// can never double-count a trade: the file on disk IS the dedupe state.
ulong g_led_seen[];
int   g_led_seen_n   = 0;
int   g_led_rows     = 0;
long  g_led_floor_ts = 0;     // exit times at/below this were already compacted away
ulong g_led_last_ms  = 0;
bool  g_led_seeded   = false;
long  g_led_scan_ts  = 0;

//+------------------------------------------------------------------+
//| Init: 2s command timer + on-chart presence label                 |
//+------------------------------------------------------------------+
int OnInit()
  {
   EventSetTimer(2);

   if(ObjectFind(0, PILOT_LABEL_NAME) < 0)
      ObjectCreate(0, PILOT_LABEL_NAME, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PILOT_LABEL_NAME, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PILOT_LABEL_NAME, OBJPROP_XDISTANCE, 8);
   ObjectSetInteger(0, PILOT_LABEL_NAME, OBJPROP_YDISTANCE, 16);
   ObjectSetString(0, PILOT_LABEL_NAME, OBJPROP_TEXT, "ALGORY PILOT ACTIVE");
   ObjectSetInteger(0, PILOT_LABEL_NAME, OBJPROP_COLOR, clrCrimson);
   ObjectSetInteger(0, PILOT_LABEL_NAME, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, PILOT_LABEL_NAME, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, PILOT_LABEL_NAME, OBJPROP_HIDDEN, true);
   ChartRedraw(0);

   LedgerLoad();
   WriteStatus();
   g_last_status_ms = GetTickCount64();
   g_led_last_ms = GetTickCount64();
   PilotLog("PILOT started (build " + (string)ALGORY_PILOT_BUILD + ", ledger rows " + (string)g_led_rows + ")");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinit: kill timer, remove label                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectDelete(0, PILOT_LABEL_NAME);
  }

//+------------------------------------------------------------------+
//| Timer: status heartbeat (~10s) + command file processing (2s)    |
//+------------------------------------------------------------------+
void OnTimer()
  {
   // GetTickCount64 instead of TimeCurrent: server time stalls when the
   // market is closed, which would freeze the heartbeat on weekends.
   if(GetTickCount64() - g_last_status_ms >= 10000)
     {
      WriteStatus();
      g_last_status_ms = GetTickCount64();
     }
   ProcessCommands();

   // Ledger LAST and on its own slow clock: executing the dashboard's commands
   // is the Pilot's job, the ledger is strictly secondary. Every step inside is
   // handle-checked and returns quietly on failure - a broken ledger must never
   // cost a deploy.
   if(GetTickCount64() - g_led_last_ms >= LEDGER_SCAN_MS)
     {
      g_led_last_ms = GetTickCount64();
      LedgerScan();
     }
  }

//+------------------------------------------------------------------+
//| Status file: login / live / autotrading / ts                     |
//+------------------------------------------------------------------+
void WriteStatus()
  {
   int h = FileOpen(PILOT_STATUS_FILE, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   bool is_live = (AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO);
   FileWrite(h, "login=" + (string)AccountInfoInteger(ACCOUNT_LOGIN));
   FileWrite(h, "live=" + (is_live ? "1" : "0"));
   FileWrite(h, "autotrading=" + (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0 ? "1" : "0"));
   FileWrite(h, "build=" + (string)ALGORY_PILOT_BUILD);
   FileWrite(h, "ts=" + (string)(long)TimeCurrent());
   // Ledger liveness rides the existing beacon rather than a second file. The
   // csv only changes when a trade closes, so its mtime cannot say "scanning".
   FileWrite(h, "ledger=" + (string)g_led_rows);
   FileWrite(h, "ledger_ts=" + (string)g_led_scan_ts);
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| Append one line to the pilot log                                 |
//+------------------------------------------------------------------+
void PilotLog(string msg)
  {
   int h = FileOpen(PILOT_LOG_FILE, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + " " + msg);
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| Map M1/M5/H1/D1-style strings to ENUM_TIMEFRAMES                 |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES TfFromString(string tf)
  {
   StringToUpper(tf);
   if(tf == "M1")   return PERIOD_M1;
   if(tf == "M2")   return PERIOD_M2;
   if(tf == "M3")   return PERIOD_M3;
   if(tf == "M4")   return PERIOD_M4;
   if(tf == "M5")   return PERIOD_M5;
   if(tf == "M6")   return PERIOD_M6;
   if(tf == "M10")  return PERIOD_M10;
   if(tf == "M12")  return PERIOD_M12;
   if(tf == "M15")  return PERIOD_M15;
   if(tf == "M20")  return PERIOD_M20;
   if(tf == "M30")  return PERIOD_M30;
   if(tf == "H1")   return PERIOD_H1;
   if(tf == "H2")   return PERIOD_H2;
   if(tf == "H3")   return PERIOD_H3;
   if(tf == "H4")   return PERIOD_H4;
   if(tf == "H6")   return PERIOD_H6;
   if(tf == "H8")   return PERIOD_H8;
   if(tf == "H12")  return PERIOD_H12;
   if(tf == "D1")   return PERIOD_D1;
   if(tf == "W1")   return PERIOD_W1;
   if(tf == "MN1")  return PERIOD_MN1;
   return PERIOD_CURRENT; // sentinel: unknown timeframe
  }

//+------------------------------------------------------------------+
//| Sweep per-command files (one command per file eliminates the     |
//| shared-file race where a dashboard append lands between our read |
//| and delete). Names are timestamped fixed-width, so a string sort |
//| = chronological order. Legacy shared file handled last.          |
//+------------------------------------------------------------------+
void ProcessCommands()
  {
   string files[];
   int n = 0;

   string fname;
   long search = FileFindFirst("algory_pilot_cmd_*.txt", fname);
   if(search != INVALID_HANDLE)
     {
      do
        {
         ArrayResize(files, n + 1);
         files[n] = fname;
         n++;
        }
      while(FileFindNext(search, fname));
      FileFindClose(search);
     }

   SortStrings(files, n);
   for(int i = 0; i < n; i++)
      ProcessCommandFile(files[i]);

   // Legacy single shared file (older dashboard builds append here).
   if(FileIsExist(PILOT_CMD_FILE))
      ProcessCommandFile(PILOT_CMD_FILE);
  }

//+------------------------------------------------------------------+
//| Insertion sort (ArraySort has no string overload)                |
//+------------------------------------------------------------------+
void SortStrings(string &arr[], int n)
  {
   for(int i = 1; i < n; i++)
     {
      string key = arr[i];
      int j = i - 1;
      while(j >= 0 && StringCompare(arr[j], key) > 0)
        {
         arr[j + 1] = arr[j];
         j--;
        }
      arr[j + 1] = key;
     }
  }

//+------------------------------------------------------------------+
//| Read one command file, delete it, then execute each line         |
//+------------------------------------------------------------------+
void ProcessCommandFile(string fname)
  {
   int h = FileOpen(fname, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;

   string lines[];
   int n = 0;
   while(!FileIsEnding(h))
     {
      string line = FileReadString(h);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(StringLen(line) == 0)
         continue;
      ArrayResize(lines, n + 1);
      lines[n] = line;
      n++;
     }
   FileClose(h);

   // Delete BEFORE executing. If a command crashes the terminal, the
   // batch must not replay on the next start.
   FileDelete(fname);

   for(int i = 0; i < n; i++)
      ExecuteCommand(lines[i]);
  }

//+------------------------------------------------------------------+
//| Dispatch a single command line                                   |
//+------------------------------------------------------------------+
void ExecuteCommand(string line)
  {
   string parts[];
   int k = StringSplit(line, '|', parts);
   if(k < 1)
      return;

   if(parts[0] == "OPEN" && k >= 4)
      CmdOpen(parts[1], parts[2], parts[3]);
   else if(parts[0] == "CLOSE" && k >= 4)
      CmdClose(parts[1], parts[2], parts[3]);
   else
      PilotLog("FAIL unknown command: " + line);
  }

//+------------------------------------------------------------------+
//| Strategy id (SID) embedded in the tpl name. The dashboard builds |
//| the template as algory_<SYM>_<TF>_<build>_<SID>_R..._....tpl, so |
//| the SID is the 4th underscore-delimited token of the expert name |
//| (tpl minus the "algory_" prefix and ".tpl" suffix). Returns ""   |
//| when the name doesn't parse (then the caller just opens a chart, |
//| same as before - safe degradation).                              |
//+------------------------------------------------------------------+
string SidFromTpl(string tpl)
  {
   string s = tpl;
   if(StringFind(s, "algory_") == 0)
      s = StringSubstr(s, 7);
   int dot = StringFind(s, ".tpl");
   if(dot >= 0)
      s = StringSubstr(s, 0, dot);
   string parts[];
   int k = StringSplit(s, '_', parts);
   if(k >= 4)
      return parts[3];
   return "";
  }

//+------------------------------------------------------------------+
//| Find an already-open chart running this strategy (same symbol +  |
//| period + SID). The deployed EA's name carries the SID as         |
//| "..._<SID>_...", so a substring match on "_<SID>_" identifies the |
//| strategy across recompiles (the build number changes, the SID    |
//| does not). Returns 0 when none is open. Skips the Pilot's own     |
//| chart.                                                            |
//+------------------------------------------------------------------+
// SID from a deployed expert name (SYM_TF_<build>_<SID>_...): token index 3.
string SidFromExpert(string expert)
  {
   string parts[];
   int k = StringSplit(expert, '_', parts);
   if(k >= 4)
      return parts[3];
   return "";
  }

// Per-chart strategy stamp. MT5 returns an EMPTY CHART_EXPERT_NAME for an EA
// attached via ChartApplyTemplate (verified live 2026-07-08), so we can't
// identify a chart's strategy from its expert. Instead the Pilot stamps each
// chart it opens with a hidden object named ALGORY_SID_<sid> that IT controls -
// set immediately, independent of the EA - and matches on that. The object is
// re-created after every template apply (ChartApplyTemplate can clear objects).
string SidMark(string sid) { return "ALGORY_SID_" + sid; }

void StampChart(long chart_id, string sid)
  {
   if(StringLen(sid) == 0)
      return;
   string mark = SidMark(sid);
   if(ObjectFind(chart_id, mark) < 0)
      ObjectCreate(chart_id, mark, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(chart_id, mark, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS); // never drawn
   ObjectSetInteger(chart_id, mark, OBJPROP_HIDDEN, true);
   ObjectSetInteger(chart_id, mark, OBJPROP_SELECTABLE, false);
  }

// A chart belongs to strategy `sid` if it carries our stamp. Fallback to the
// expert-name SID substring for charts opened by a pre-stamp Pilot that still
// happen to expose a name (harmless when the name is empty).
bool ChartHasSid(long chart_id, string sid)
  {
   if(StringLen(sid) == 0)
      return false;
   if(ObjectFind(chart_id, SidMark(sid)) >= 0)
      return true;
   return StringFind(ChartGetString(chart_id, CHART_EXPERT_NAME), sid) >= 0;
  }

// Diagnostic: dump every open chart so we can see symbol / period / expert /
// stamp when a match misses.
void LogOpenCharts(string context, string sid)
  {
   long own = ChartID();
   long id = ChartFirst();
   while(id >= 0)
     {
      if(id != own)
         PilotLog("  [charts] " + context + " id=" + (string)id
                  + " sym=" + ChartSymbol(id)
                  + " period=" + (string)ChartPeriod(id)
                  + " expert='" + ChartGetString(id, CHART_EXPERT_NAME) + "'"
                  + " stamped=" + (ObjectFind(id, SidMark(sid)) >= 0 ? "Y" : "N"));
      id = ChartNext(id);
     }
  }

long FindChartForSid(string sym, ENUM_TIMEFRAMES period, string sid)
  {
   if(StringLen(sid) == 0)
      return 0;
   long own = ChartID();
   long id = ChartFirst();
   while(id >= 0)
     {
      if(id != own && ChartHasSid(id, sid))
         return id;
      id = ChartNext(id);
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| OPEN|SYMBOL|TF|template.tpl                                      |
//+------------------------------------------------------------------+
void CmdOpen(string sym, string tf, string tpl)
  {
   ResetLastError();
   if(!SymbolSelect(sym, true))
     {
      PilotLog("FAIL OPEN " + sym + " " + tf + ": SymbolSelect error " + (string)GetLastError());
      return;
     }

   ENUM_TIMEFRAMES period = TfFromString(tf);
   if(period == PERIOD_CURRENT)
     {
      PilotLog("FAIL OPEN " + sym + " " + tf + ": unknown timeframe");
      return;
     }

   // Dedupe: if a chart already runs THIS strategy, REUSE it (re-apply the
   // template) instead of opening a second one. ChartOpen always creates a
   // NEW chart, so without this a re-deploy stacks a duplicate chart running
   // the same EA = duplicate positions on the same signal.
   bool reused = false;
   long chart_id = FindChartForSid(sym, period, SidFromTpl(tpl));
   if(chart_id != 0)
      reused = true;
   else
     {
      ResetLastError();
      chart_id = ChartOpen(sym, period);
      if(chart_id == 0)
        {
         PilotLog("FAIL OPEN " + sym + " " + tf + ": ChartOpen error " + (string)GetLastError());
         return;
        }
     }

   // Template path starting with a backslash resolves against the terminal
   // data directory, i.e. <data>\Profiles\Templates\<tpl>. Short retry loop:
   // a freshly opened chart can reject the first apply while it initialises.
   // Sleep() is legal here (EA timer context; only indicators forbid it).
   string tpl_path = "\\Profiles\\Templates\\" + tpl;
   bool applied = false;
   int last_err = 0;
   for(int attempt = 0; attempt < 5 && !applied; attempt++)
     {
      ResetLastError();
      applied = ChartApplyTemplate(chart_id, tpl_path);
      if(!applied)
        {
         last_err = GetLastError();
         Sleep(500);
        }
     }

   if(applied)
     {
      // Stamp AFTER applying (the template apply can clear objects), so this
      // chart is identifiable as this strategy's regardless of the (empty)
      // expert name MT5 reports for template-attached EAs.
      StampChart(chart_id, SidFromTpl(tpl));
      ChartRedraw(chart_id);
      PilotLog("OK " + (reused ? "REUSE" : "OPEN") + " " + sym + " " + tf + " tpl=" + tpl + " chart=" + (string)chart_id);
     }
   else
      PilotLog("FAIL OPEN " + sym + " " + tf + " tpl=" + tpl + ": ChartApplyTemplate error " + (string)last_err);
  }

//+------------------------------------------------------------------+
//| CLOSE|SYMBOL|TF|ExpertName                                       |
//+------------------------------------------------------------------+
void CmdClose(string sym, string tf, string expert)
  {
   ENUM_TIMEFRAMES period = TfFromString(tf);
   long own_id = ChartID();
   int closed = 0;
   // Match by SID token (stable across recompiles + robust to whatever
   // CHART_EXPERT_NAME actually returns) rather than the exact expert name.
   string sid = SidFromExpert(expert);

   long chart_id = ChartFirst();
   while(chart_id >= 0)
     {
      long next_id = ChartNext(chart_id); // fetch BEFORE closing this chart
      if(chart_id != own_id && ChartHasSid(chart_id, sid))
        {
         ResetLastError();
         if(ChartClose(chart_id))
            closed++;
         else
            PilotLog("FAIL CLOSE " + sym + " " + tf + " " + expert + ": ChartClose error " + (string)GetLastError());
        }
      chart_id = next_id;
     }

   if(closed > 0)
      PilotLog("OK CLOSE " + sym + " " + tf + " " + expert + " charts=" + (string)closed);
   else
     {
      PilotLog("FAIL CLOSE " + sym + " " + tf + " " + expert + " (sid=" + sid + "): no matching chart found");
      LogOpenCharts("close-miss", sid);
     }
  }

//+==================================================================+
//|                      LIVE TRADE LEDGER                           |
//|                                                                  |
//| WHAT: one append-only csv row per CLOSED position, written to    |
//| MQL5\Files\algory_live_trades.csv. Read back by                  |
//| app\algory_full_deploy.py read_live_ledger().                    |
//|                                                                  |
//| WHY: the tester-side parity grade compares Algory's answer key   |
//| against a Strategy Tester run. It is blind to what a real broker |
//| actually filled at. The prices in these rows are the only place  |
//| live fill divergence can be measured.                            |
//|                                                                  |
//| The deal walk mirrors the generated EA's parity self-check       |
//| (app\Algory_Engine_v129.py:8509-8550): pair deals by             |
//| DEAL_POSITION_ID, entry = DEAL_ENTRY_IN, exit = DEAL_ENTRY_OUT,  |
//| exit reason from DEAL_REASON. Two deliberate differences:        |
//|   - costs are summed over EVERY deal of the position as          |
//|     profit + swap + commission (commission is usually charged on |
//|     the ENTRY deal, so the parity report's exit-only DEAL_PROFIT |
//|     would under-report it live). Same convention as              |
//|     _user\scripts\decay_monitor.py:216-220.                      |
//|   - prices are volume-weighted, so partial fills are exact.      |
//|                                                                  |
//| CRASH SAFE + IDEMPOTENT: the dedupe key is DEAL_POSITION_ID (the |
//| ticket of the deal that opened the position) and the key set is  |
//| rebuilt FROM THE FILE at every start. Re-reading the same        |
//| history after a restart therefore writes nothing. A position     |
//| that is only partially closed is skipped until its volume        |
//| balances, so a partial close never lands as a whole trade.       |
//|                                                                  |
//| BOUNDED: LEDGER_WINDOW_DAYS of history per scan, at most         |
//| LEDGER_MAX_NEW_PASS rows per scan, and the file is compacted to  |
//| LEDGER_KEEP_ROWS once it passes LEDGER_MAX_ROWS. Compaction      |
//| stamps a floor= timestamp in the header so dropped trades are    |
//| never rediscovered and re-appended.                              |
//|                                                                  |
//| PRIVACY: magic 0 is the user trading by hand. Never recorded.    |
//| Nothing here leaves the machine - there is no network call in    |
//| this EA.                                                         |
//+==================================================================+

// Column order is the contract with the Python reader. Never reorder; add new
// columns at the END only (the reader tolerates extra trailing fields).
string LedgerHeader()
  {
   return "# algory_live_trades v" + (string)LEDGER_VER + " floor=" + (string)g_led_floor_ts
          + " cols=account,magic,symbol,comment,dir,entry_ts,exit_ts,entry_price,"
          + "exit_price,volume,profit,swap,commission,exit_reason,pos_id,exit_ticket";
  }

// Binary search over the sorted seen-set. >=0 = found at index;
// <0 = -(insertion point + 1).
int LedgerSeenFind(ulong id)
  {
   int lo = 0, hi = g_led_seen_n - 1;
   while(lo <= hi)
     {
      int mid = (lo + hi) / 2;
      if(g_led_seen[mid] == id)
         return mid;
      if(g_led_seen[mid] < id)
         lo = mid + 1;
      else
         hi = mid - 1;
     }
   return -(lo + 1);
  }

bool LedgerSeenHas(ulong id)
  {
   return LedgerSeenFind(id) >= 0;
  }

void LedgerSeenAdd(ulong id)
  {
   int at = LedgerSeenFind(id);
   if(at >= 0)
      return;
   at = -at - 1;
   if(ArrayResize(g_led_seen, g_led_seen_n + 1, 512) < 0)
      return;
   for(int i = g_led_seen_n; i > at; i--)
      g_led_seen[i] = g_led_seen[i - 1];
   g_led_seen[at] = id;
   g_led_seen_n++;
  }

//| Rebuild the dedupe state from the file on disk. Called at OnInit and
//| after a compaction. A torn final line (terminal killed mid-append) simply
//| fails the field count and is ignored.
void LedgerLoad()
  {
   ArrayResize(g_led_seen, 0);
   g_led_seen_n   = 0;
   g_led_rows     = 0;
   g_led_floor_ts = 0;
   if(!FileIsExist(PILOT_LEDGER_FILE))
      return;
   int h = FileOpen(PILOT_LEDGER_FILE, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   while(!FileIsEnding(h))
     {
      string line = FileReadString(h);
      if(StringLen(line) == 0)
         continue;
      if(StringGetCharacter(line, 0) == '#')
        {
         int fp = StringFind(line, "floor=");
         if(fp >= 0)
            g_led_floor_ts = (long)StringToInteger(StringSubstr(line, fp + 6));
         continue;
        }
      string parts[];
      if(StringSplit(line, ',', parts) < 16)
         continue;
      ulong pid = (ulong)StringToInteger(parts[14]);
      if(pid == 0)
         continue;
      LedgerSeenAdd(pid);
      g_led_rows++;
     }
   FileClose(h);
  }

bool LedgerAppend(string line)
  {
   bool fresh = !FileIsExist(PILOT_LEDGER_FILE);
   int h = FileOpen(PILOT_LEDGER_FILE, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;
   FileSeek(h, 0, SEEK_END);
   if(fresh)
      FileWrite(h, LedgerHeader());
   FileWrite(h, line);
   FileClose(h);
   g_led_rows++;
   return true;
  }

//| Keep the file bounded on a terminal that runs for years: retain the newest
//| LEDGER_KEEP_ROWS and stamp floor= with the newest exit time being dropped,
//| so the next scan cannot rediscover a dropped trade and append it again.
//| Written to a temp file and moved into place, so a crash mid-compaction
//| leaves the original intact.
void LedgerCompact()
  {
   int h = FileOpen(PILOT_LEDGER_FILE, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   string rows[];
   int n = 0;
   while(!FileIsEnding(h))
     {
      string line = FileReadString(h);
      if(StringLen(line) == 0 || StringGetCharacter(line, 0) == '#')
         continue;
      if(ArrayResize(rows, n + 1, 512) < 0)
         break;
      rows[n] = line;
      n++;
     }
   FileClose(h);
   if(n <= LEDGER_KEEP_ROWS)
     {
      g_led_rows = n;
      return;
     }

   int start = n - LEDGER_KEEP_ROWS;
   long floor_ts = g_led_floor_ts;
   for(int i = 0; i < start; i++)
     {
      string p[];
      if(StringSplit(rows[i], ',', p) < 16)
         continue;
      long ex = (long)StringToInteger(p[6]);
      if(ex > floor_ts)
         floor_ts = ex;
     }
   g_led_floor_ts = floor_ts;

   FileDelete(PILOT_LEDGER_TMP);
   int w = FileOpen(PILOT_LEDGER_TMP, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(w == INVALID_HANDLE)
      return;
   FileWrite(w, LedgerHeader());
   for(int i = start; i < n; i++)
      FileWrite(w, rows[i]);
   FileClose(w);

   if(FileMove(PILOT_LEDGER_TMP, 0, PILOT_LEDGER_FILE, FILE_REWRITE))
     {
      LedgerLoad();   // seen-set + floor now come from what actually survived
      PilotLog("LEDGER compacted to " + (string)g_led_rows + " rows (floor=" + (string)g_led_floor_ts + ")");
     }
   else
      FileDelete(PILOT_LEDGER_TMP);
  }

//| Fold one position's deals into a single row and append it. Returns quietly
//| without writing when the position is still open, only partly closed, or was
//| reversed (DEAL_ENTRY_INOUT) - a half-truth row is worse than no row.
void LedgerWritePosition(ulong pid, int total)
  {
   double in_vol = 0.0, out_vol = 0.0, w_entry = 0.0, w_exit = 0.0;
   double profit = 0.0, swap = 0.0, comm = 0.0;
   long   entry_ts = 0, exit_ts = 0, magic = 0, reason = -1;
   ulong  exit_ticket = 0;
   string sym = "", comment = "", dir = "";

   for(int i = 0; i < total; i++)
     {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0)
         continue;
      if((ulong)HistoryDealGetInteger(t, DEAL_POSITION_ID) != pid)
         continue;
      long entry = HistoryDealGetInteger(t, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_INOUT)
         return;                                   // reversal: not one trade
      long dtype = HistoryDealGetInteger(t, DEAL_TYPE);
      if(dtype != DEAL_TYPE_BUY && dtype != DEAL_TYPE_SELL)
         continue;                                 // balance/credit/correction

      double vol   = HistoryDealGetDouble(t, DEAL_VOLUME);
      double price = HistoryDealGetDouble(t, DEAL_PRICE);
      long   dt    = HistoryDealGetInteger(t, DEAL_TIME);
      profit += HistoryDealGetDouble(t, DEAL_PROFIT);
      swap   += HistoryDealGetDouble(t, DEAL_SWAP);
      comm   += HistoryDealGetDouble(t, DEAL_COMMISSION);

      if(entry == DEAL_ENTRY_IN)
        {
         in_vol  += vol;
         w_entry += price * vol;
         if(entry_ts == 0 || dt < entry_ts)
            entry_ts = dt;
         if(magic == 0)
            magic = HistoryDealGetInteger(t, DEAL_MAGIC);
         if(StringLen(sym) == 0)
            sym = HistoryDealGetString(t, DEAL_SYMBOL);
         if(StringLen(dir) == 0)
            dir = (dtype == DEAL_TYPE_BUY) ? "LONG" : "SHORT";
         if(StringLen(comment) == 0)
            comment = HistoryDealGetString(t, DEAL_COMMENT);
        }
      else
        {
         out_vol += vol;
         w_exit  += price * vol;
         if(dt >= exit_ts)
           {
            exit_ts     = dt;
            exit_ticket = t;
            reason      = HistoryDealGetInteger(t, DEAL_REASON);
           }
        }
     }

   if(in_vol <= 0.0 || out_vol + 0.00000001 < in_vol)
      return;                                      // still open / partly closed
   if(exit_ts <= 0 || StringLen(sym) == 0)
      return;

   // Broker close comments ("[sl 1.23456]") overwrite the EA's comment on the
   // EXIT deal, so the entry comment is preferred above; fall back to the exit
   // one only when the entry carried none. Mirrors decay_monitor.py:222.
   if(StringLen(comment) == 0 && exit_ticket != 0)
      comment = HistoryDealGetString(exit_ticket, DEAL_COMMENT);
   StringReplace(comment, ",", " ");
   StringReplace(comment, "\r", " ");
   StringReplace(comment, "\n", " ");
   if(StringLen(comment) > LEDGER_COMMENT_MAX)
      comment = StringSubstr(comment, 0, LEDGER_COMMENT_MAX);

   string rstr = "CLOSE";
   if(reason == DEAL_REASON_SL)          rstr = "SL";
   else if(reason == DEAL_REASON_TP)     rstr = "TP";
   else if(reason == DEAL_REASON_EXPERT) rstr = "EA";
   else if(reason == DEAL_REASON_SO)     rstr = "STOPOUT";

   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(digits <= 0 || digits > 10)
      digits = 5;

   string line = (string)AccountInfoInteger(ACCOUNT_LOGIN) + ","
                 + (string)magic + ","
                 + sym + ","
                 + comment + ","
                 + dir + ","
                 + (string)entry_ts + ","
                 + (string)exit_ts + ","
                 + DoubleToString(w_entry / in_vol, digits) + ","
                 + DoubleToString(w_exit / out_vol, digits) + ","
                 + DoubleToString(in_vol, 3) + ","
                 + DoubleToString(profit, 2) + ","
                 + DoubleToString(swap, 2) + ","
                 + DoubleToString(comm, 2) + ","
                 + rstr + ","
                 + (string)pid + ","
                 + (string)exit_ticket;

   if(LedgerAppend(line))
      LedgerSeenAdd(pid);
  }

//| One scan: select a bounded slice of history, collect the position ids that
//| have a closing deal we have not written yet, fold each, compact if needed.
void LedgerScan()
  {
   if(MQLInfoInteger(MQL_TESTER))
      return;                                      // the Pilot never runs there

   long now  = (long)TimeCurrent();
   if(now <= 0)
      return;
   int  days = g_led_seeded ? LEDGER_WINDOW_DAYS : LEDGER_SEED_DAYS;
   if(!HistorySelect((datetime)(now - (long)days * 86400), (datetime)(now + 86400)))
      return;
   g_led_seeded = true;
   g_led_scan_ts = now;

   int total = HistoryDealsTotal();
   ulong cand[];
   int nc = 0;
   for(int i = 0; i < total && nc < LEDGER_MAX_NEW_PASS; i++)
     {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0)
         continue;
      long entry = HistoryDealGetInteger(t, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
         continue;
      long dtype = HistoryDealGetInteger(t, DEAL_TYPE);
      if(dtype != DEAL_TYPE_BUY && dtype != DEAL_TYPE_SELL)
         continue;
      if(HistoryDealGetInteger(t, DEAL_MAGIC) == 0)
         continue;                                 // hand-placed trade: not ours
      if((long)HistoryDealGetInteger(t, DEAL_TIME) <= g_led_floor_ts)
         continue;                                 // already compacted away
      ulong pid = (ulong)HistoryDealGetInteger(t, DEAL_POSITION_ID);
      if(pid == 0 || LedgerSeenHas(pid))
         continue;
      bool dup = false;
      for(int c = 0; c < nc; c++)
         if(cand[c] == pid)
           {
            dup = true;
            break;
           }
      if(dup)
         continue;
      if(ArrayResize(cand, nc + 1, LEDGER_MAX_NEW_PASS) < 0)
         break;
      cand[nc] = pid;
      nc++;
     }

   int before = g_led_rows;
   for(int c = 0; c < nc; c++)
      LedgerWritePosition(cand[c], total);

   // Only log rows actually WRITTEN: a position that is still partly open stays
   // a candidate every minute until it fully closes, and logging that would
   // spam the Pilot log for the life of the trade.
   if(g_led_rows > before)
      PilotLog("LEDGER +" + (string)(g_led_rows - before) + " closed trade(s), " + (string)g_led_rows + " rows");
   if(g_led_rows > LEDGER_MAX_ROWS)
      LedgerCompact();
  }
//+------------------------------------------------------------------+
