# Post-Call Lead Scorer (phone-free)

You bring the call — a **transcript** or an **audio file** — and this does
everything after it:

1. Transcribes the audio (skipped if you already have the text)
2. Summarizes the call with Claude
3. Scores the lead **0–100** and flags the hot ones
4. Creates/updates a **Salesforce** Lead
5. Saves it to a **weekly Google Sheet**, hottest leads pinned to the top

You're handling how calls get recorded yourself. When you ever want to automate
that too, this same pipeline plugs straight into a webhook — just ask.

---

## The pipeline

```
You provide a call  (transcript .txt  OR  audio .mp3)
        │
        ▼
[1] Transcribe         transcribe.py     audio ─► text   (skipped if you give text)
        │
        ▼
[2+3] Summarize + score   analyze.py     Claude scores 0–100, flags HOT
        │
        ├──► [4] Salesforce      salesforce_sync.py   creates / updates a Lead
        │
        └──► [5] Weekly sheet     weekly_sheet.py      appends + sorts hottest-first
```

---

## What each file is

| File | What it does |
|------|--------------|
| **run_call.py** | What you run. Feed it one call. |
| transcribe.py | Audio → text via OpenAI Whisper. Skipped if you pass a transcript. |
| analyze.py | Claude: summary, key points, next steps, 0–100 score, Hot/Warm/Cold. **Edit the scoring rules here.** |
| salesforce_sync.py | Creates or updates the Salesforce Lead. |
| weekly_sheet.py | Writes to this week's tab, hottest on top. |
| process_call.py | The glue that runs the five steps in order. |
| config.py / .env | Your keys and settings. |
| test_local.py | Runs a built-in sample call so you can test with zero input of your own. |

---

## Setup (about 20 minutes)

**1. Install Python 3.10+ and the libraries**
```
pip install -r requirements.txt
```

**2. Add your keys**
```
cp .env.example .env
```
Open `.env` and paste your keys. Start with just the Anthropic key — the system
skips Salesforce and Google Sheets until you fill those in, so you can set up one
piece at a time.

**3. Test the brain with no input of your own**
```
python test_local.py
```
You should see a sample lead ("Maria Lopez") get scored HOT.

---

## Run one of your own calls

**From a transcript file:**
```
python run_call.py --transcript call.txt --name "Maria Lopez" --email maria@acme.com
```

**From an audio recording:**
```
python run_call.py --audio call.mp3 --name "Maria Lopez" --phone "+1 555 0142"
```

`--name`, `--email`, `--phone` are all optional — whatever you leave out, Claude
tries to pull from the call itself.

---

## Salesforce notes

- New leads use the **standard Rating field** (Hot / Warm / Cold) to flag hotness
  — no setup needed.
- To also store the exact 0–100 number, create a custom number field on the Lead
  object (e.g. `Lead_Score__c`) and put its API name in `SF_SCORE_FIELD` in `.env`.
- Your **security token** comes from Salesforce: Settings → Reset My Security Token.

## Google Sheets notes

1. console.cloud.google.com → new project → enable the **Google Sheets API** and
   **Google Drive API**.
2. Create a **Service Account**, add a **JSON key**, download it, save it here as
   `google-service-account.json`.
3. Create one empty Google Sheet; copy its ID from the URL (between `/d/` and
   `/edit`) into `GOOGLE_SHEET_ID` in `.env`.
4. **Share the sheet** with the service account's email (the `client_email` in the
   JSON) as an Editor.

Each week automatically gets its own tab, sorted hottest-first.

## Make it yours

- **Change what "hot" means:** edit `SCORING_GUIDE` at the top of `analyze.py`.
- **Change the hot cutoff:** set `HOT_THRESHOLD` in `.env` (default 70).
- **Pick a Claude model:** set `CLAUDE_MODEL` in `.env` (`claude-opus-4-8` = sharpest,
  `claude-sonnet-4-6` = balanced default, `claude-haiku-4-5-20251001` = cheapest).

## A quick legal note

If your transcripts/recordings come from real calls, recording requires the other
person's consent in many states and countries (two-party-consent rules). A one-line
"this call may be recorded" disclaimer at the start usually covers it — check the
rules where you and your prospects are based.

## Roughly what it costs

Whisper is ~$0.006/min of audio; Claude analysis is a fraction of a cent per call.
A typical 15-minute call costs about **10–15 cents** to process. (If you feed in
text transcripts, you skip the Whisper cost entirely.)

---

## Deploy to a team (one central machine — recommended)

You don't install this on every rep's computer. Put it on **one** always-on
machine (an office PC or a small cloud server) and let it watch a shared folder.

1. Pick a shared folder everyone can reach — a synced OneDrive / SharePoint /
   Google Drive / Dropbox folder, or a network drive. In `.env`, set
   `INCOMING_DIR` to that folder's path on the central machine, e.g.
   `INCOMING_DIR=C:\Users\you\OneDrive\Call Drop`
2. On the central machine, double-click **run_watcher.bat** (or run
   `python watch_folder.py`) and leave it running.
3. Reps just drop a call into the shared folder — a transcript `.txt` or an
   audio file. No software on their side.
4. The watcher scores each new file, fills Salesforce, and updates the weekly
   sheet. Handled files move to a `processed` subfolder; failures go to `failed`,
   so nothing is lost.

One install, one API key, one place to update your scoring rules. To keep it
running 24/7, set `run_watcher.bat` to launch on startup (Windows Task Scheduler)
or host it on a small always-on server.
