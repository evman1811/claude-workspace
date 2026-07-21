"""
post_call.py — single-file post-call pipeline
=============================================
Drop a transcript .txt (or audio .mp3) in and this does everything:

  1. Transcribe audio → text  (skipped if you give a .txt)
  2. Claude: summary, key points, next steps, objections, 0-100 score, Hot/Warm/Cold
  3. Write a full CRM entry to  crm_entries/<name>_<date>.txt
  4. Append to a local CSV log  call_log.csv  (always works, no setup needed)
  5. Append to Google Sheets    (needs one-time auth — see SETUP below)
  6. Push to Salesforce         (optional — needs SF credentials in .env)

SETUP (Google Sheets — one-time, ~5 min):
  1. console.cloud.google.com → new project → Enable Google Sheets API + Drive API
  2. APIs & Services → Credentials → + Create Credentials → OAuth client ID
     Application type: Desktop app → Create → Download JSON
  3. Rename the downloaded file to  credentials.json  and put it next to this file
  4. Run:  python post_call.py --setup-google
     Your browser opens → log in → click Allow → done.
  After that, every run writes straight to your Google Sheet.

USAGE:
  python post_call.py transcript.txt
  python post_call.py call.mp3 --name "Sarah Bennett" --email sarah@example.com
  python post_call.py --setup-google
"""

import argparse
import csv
import json
import os
import re
import sys
import tempfile
import traceback
from datetime import datetime
from pathlib import Path

# ── Load .env ──────────────────────────────────────────────────────────────────
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass  # fine if python-dotenv not installed; just use real env vars

# ── Config ─────────────────────────────────────────────────────────────────────
ANTHROPIC_API_KEY          = os.getenv("ANTHROPIC_API_KEY", "")
CLAUDE_MODEL               = os.getenv("CLAUDE_MODEL", "claude-sonnet-4-6")
OPENAI_API_KEY             = os.getenv("OPENAI_API_KEY", "")
SF_USERNAME                = os.getenv("SF_USERNAME", "")
SF_PASSWORD                = os.getenv("SF_PASSWORD", "")
SF_SECURITY_TOKEN          = os.getenv("SF_SECURITY_TOKEN", "")
SF_DOMAIN                  = os.getenv("SF_DOMAIN", "login")
SF_SCORE_FIELD             = os.getenv("SF_SCORE_FIELD", "").strip()
GOOGLE_SHEET_ID            = os.getenv("GOOGLE_SHEET_ID", "")
GOOGLE_SERVICE_ACCOUNT_JSON = os.getenv("GOOGLE_SERVICE_ACCOUNT_JSON", "google-service-account.json")
HOT_THRESHOLD              = int(os.getenv("HOT_THRESHOLD", "70"))

HERE = Path(__file__).parent
SERVICE_ACCOUNT_FILE = HERE / GOOGLE_SERVICE_ACCOUNT_JSON
CREDENTIALS_FILE     = HERE / "credentials.json"
AUTHORIZED_USER_FILE = Path.home() / ".config" / "gspread" / "authorized_user.json"
CRM_DIR              = HERE / "crm_entries"
LOCAL_LOG            = HERE / "call_log.csv"

SHEET_HEADER = [
    "Date", "Score", "Rating", "Hot?", "Name", "Company",
    "Email", "Phone", "Summary", "Next Steps", "Why",
]

# ── Scoring guide (edit this to change what "hot" means to you) ────────────────
SCORING_GUIDE = """
Score the lead from 0 to 100 based on:
- Budget (25 pts): do they have money to spend / did they mention a budget?
- Authority (20 pts): are they a decision-maker?
- Need (25 pts): is there a clear, urgent problem we solve?
- Timeline (20 pts): are they looking to buy soon (weeks, not "someday")?
- Engagement (10 pts): were they interested, asking questions, positive?
Higher = hotter. Be honest and a little strict.
"""

SYSTEM_PROMPT = f"""You are a sales-call analyst. You read a phone call transcript
between a salesperson and a prospect, then return a strict JSON object.

{SCORING_GUIDE}

Return ONLY valid JSON with exactly these keys:
{{
  "contact_name": string,
  "company": string,
  "email": string,
  "phone": string,
  "summary": string,
  "key_points": [string],
  "next_steps": [string],
  "objections": [string],
  "score": integer,
  "rating": "Hot" | "Warm" | "Cold",
  "reason": string
}}
Do not wrap the JSON in markdown. Do not add any commentary."""


# ══════════════════════════════════════════════════════════════════════════════
# STEP 1 — Transcribe
# ══════════════════════════════════════════════════════════════════════════════

def transcribe(recording_url=None, existing_transcript=None, audio_path=None):
    if existing_transcript:
        return existing_transcript.strip()
    if audio_path:
        return _whisper(audio_path)
    if recording_url:
        import requests as req
        resp = req.get(recording_url, timeout=120)
        resp.raise_for_status()
        with tempfile.NamedTemporaryFile(delete=False, suffix=".mp3") as f:
            f.write(resp.content)
            tmp = f.name
        try:
            return _whisper(tmp)
        finally:
            os.remove(tmp)
    raise ValueError("Provide a transcript, audio file, or recording URL.")

def _whisper(audio_path):
    from openai import OpenAI
    client = OpenAI(api_key=OPENAI_API_KEY)
    with open(audio_path, "rb") as af:
        result = client.audio.transcriptions.create(model="whisper-1", file=af)
    return result.text.strip()


# ══════════════════════════════════════════════════════════════════════════════
# STEP 2 — Analyse with Claude
# ══════════════════════════════════════════════════════════════════════════════

def analyse(transcript_text):
    import anthropic
    client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)
    msg = client.messages.create(
        model=CLAUDE_MODEL,
        max_tokens=1500,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": f"Call transcript:\n\n{transcript_text}"}],
    )
    raw = msg.content[0].text.strip()
    data = _parse_json(raw)
    score = max(0, min(100, int(data.get("score", 0))))
    data["score"] = score
    data["is_hot"] = score >= HOT_THRESHOLD
    return data

def _parse_json(raw):
    if raw.startswith("```"):
        raw = re.sub(r"^```[a-z]*\n?", "", raw).rstrip("`").strip()
    start, end = raw.find("{"), raw.rfind("}")
    if start != -1 and end != -1:
        return json.loads(raw[start:end + 1])
    return json.loads(raw)


# ══════════════════════════════════════════════════════════════════════════════
# STEP 3 — Write CRM entry to disk
# ══════════════════════════════════════════════════════════════════════════════

def write_crm(analysis, call_date=None):
    CRM_DIR.mkdir(exist_ok=True)
    date_str = (call_date or datetime.now()).strftime("%Y-%m-%d")
    name_slug = re.sub(r"[^\w]", "_", analysis.get("contact_name") or "unknown").lower()
    filename = CRM_DIR / f"{name_slug}_{date_str}.txt"

    hot_tag = "★ HOT ★" if analysis.get("is_hot") else analysis.get("rating", "")
    score = analysis.get("score", 0)

    lines = [
        "═" * 59,
        f"CRM ENTRY  |  {date_str}",
        f"LEAD SCORE: {score} / 100  {hot_tag}",
        "═" * 59,
        "",
        "CONTACT DETAILS",
        "─" * 15,
        f"Name:     {analysis.get('contact_name', '')}",
        f"Company:  {analysis.get('company', '')}",
        f"Email:    {analysis.get('email', '')}",
        f"Phone:    {analysis.get('phone', '')}",
        "",
        "SUMMARY",
        "─" * 7,
        analysis.get("summary", ""),
        "",
        "KEY POINTS",
        "─" * 10,
    ]
    for kp in analysis.get("key_points", []):
        lines.append(f"• {kp}")
    lines += ["", "NEXT STEPS", "─" * 10]
    for i, ns in enumerate(analysis.get("next_steps", []), 1):
        lines.append(f"{i}. {ns}")
    lines += ["", "OBJECTIONS RAISED", "─" * 17]
    for ob in analysis.get("objections", []):
        lines.append(f"• {ob}")
    lines += [
        "",
        "WHY THIS SCORE",
        "─" * 14,
        analysis.get("reason", ""),
        "",
        "═" * 59,
        f"Scored by: Claude ({CLAUDE_MODEL})  |  Threshold: {HOT_THRESHOLD}",
        "═" * 59,
    ]

    filename.write_text("\n".join(lines), encoding="utf-8")
    return filename


# ══════════════════════════════════════════════════════════════════════════════
# STEP 4 — Append to local CSV log (always runs, no setup needed)
# ══════════════════════════════════════════════════════════════════════════════

def append_local_log(analysis):
    write_header = not LOCAL_LOG.exists()
    with open(LOCAL_LOG, "a", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=SHEET_HEADER)
        if write_header:
            writer.writeheader()
        writer.writerow(_sheet_row(analysis))


# ══════════════════════════════════════════════════════════════════════════════
# STEP 5 — Google Sheets (optional; needs one-time OAuth setup)
# ══════════════════════════════════════════════════════════════════════════════

def _gspread_client():
    import gspread
    if SERVICE_ACCOUNT_FILE.exists():
        return gspread.service_account(filename=str(SERVICE_ACCOUNT_FILE))
    # Fall back to OAuth if no service account key is present
    return gspread.oauth(
        credentials_filename=str(CREDENTIALS_FILE),
        authorized_user_filename=str(AUTHORIZED_USER_FILE),
    )

def _week_tab():
    iso = datetime.now().isocalendar()
    return f"Week {iso[0]}-W{iso[1]:02d}"

def _sheet_row(analysis):
    return {
        "Date":       datetime.now().strftime("%Y-%m-%d %H:%M"),
        "Score":      analysis.get("score", 0),
        "Rating":     analysis.get("rating", ""),
        "Hot?":       "HOT" if analysis.get("is_hot") else "",
        "Name":       analysis.get("contact_name", ""),
        "Company":    analysis.get("company", ""),
        "Email":      analysis.get("email", ""),
        "Phone":      analysis.get("phone", ""),
        "Summary":    analysis.get("summary", ""),
        "Next Steps": " | ".join(analysis.get("next_steps", [])),
        "Why":        analysis.get("reason", ""),
    }

def save_to_sheets(analysis):
    if not GOOGLE_SHEET_ID:
        print("[Sheets] GOOGLE_SHEET_ID not set — skipped.")
        return
    if not SERVICE_ACCOUNT_FILE.exists() and not AUTHORIZED_USER_FILE.exists() and not CREDENTIALS_FILE.exists():
        print(f"[Sheets] No credentials found. Add {SERVICE_ACCOUNT_FILE.name} to this folder.")
        return

    import gspread
    gc = _gspread_client()
    sheet = gc.open_by_key(GOOGLE_SHEET_ID)
    tab = _week_tab()
    try:
        ws = sheet.worksheet(tab)
    except gspread.WorksheetNotFound:
        ws = sheet.add_worksheet(title=tab, rows=200, cols=len(SHEET_HEADER))
        ws.append_row(SHEET_HEADER, value_input_option="USER_ENTERED")

    row = _sheet_row(analysis)
    ws.append_row([row[h] for h in SHEET_HEADER], value_input_option="USER_ENTERED")

    # Re-sort by Score (col 2), highest first
    count = len(ws.get_all_values())
    if count > 2:
        last_col = chr(ord("A") + len(SHEET_HEADER) - 1)
        ws.sort((2, "des"), range=f"A2:{last_col}{count}")

    print(f"[Sheets] Saved to tab: {tab}")


# ══════════════════════════════════════════════════════════════════════════════
# STEP 6 — Salesforce (optional)
# ══════════════════════════════════════════════════════════════════════════════

def save_to_salesforce(analysis):
    if not SF_USERNAME:
        print("[Salesforce] Not configured — skipped.")
        return
    from simple_salesforce import Salesforce
    sf = Salesforce(username=SF_USERNAME, password=SF_PASSWORD,
                    security_token=SF_SECURITY_TOKEN, domain=SF_DOMAIN)
    name = (analysis.get("contact_name") or "Unknown").strip()
    parts = name.split()
    fields = {
        "LastName":    parts[-1] if parts else "Caller",
        "FirstName":   " ".join(parts[:-1]) if len(parts) > 1 else "",
        "Company":     analysis.get("company") or "Unknown",
        "Email":       analysis.get("email") or None,
        "Phone":       analysis.get("phone") or None,
        "Description": analysis.get("summary", ""),
        "Rating":      analysis.get("rating") or "Cold",
        "LeadSource":  "Phone Call",
    }
    if SF_SCORE_FIELD:
        fields[SF_SCORE_FIELD] = analysis.get("score", 0)
    fields = {k: v for k, v in fields.items() if v not in (None, "")}
    email = analysis.get("email")
    if email:
        existing = sf.query(f"SELECT Id FROM Lead WHERE Email = '{email}' LIMIT 1")
        if existing["records"]:
            lid = existing["records"][0]["Id"]
            sf.Lead.update(lid, fields)
            print(f"[Salesforce] Updated lead: {lid}")
            return
    lid = sf.Lead.create(fields)["id"]
    print(f"[Salesforce] Created lead: {lid}")


# ══════════════════════════════════════════════════════════════════════════════
# One-time Google auth setup
# ══════════════════════════════════════════════════════════════════════════════

def setup_google():
    if not CREDENTIALS_FILE.exists():
        print("ERROR: credentials.json not found in this folder.")
        print()
        print("To get it:")
        print("  1. Go to https://console.cloud.google.com")
        print("  2. Create a project → APIs & Services → Enable:")
        print("     Google Sheets API  and  Google Drive API")
        print("  3. Credentials → + Create Credentials → OAuth client ID")
        print("     Application type: Desktop app → Create → Download JSON")
        print("  4. Rename the file to  credentials.json  and put it here")
        print("  5. Run this script again with --setup-google")
        sys.exit(1)
    AUTHORIZED_USER_FILE.parent.mkdir(parents=True, exist_ok=True)
    print("Opening browser — log in and click Allow...")
    import gspread
    gspread.oauth(
        credentials_filename=str(CREDENTIALS_FILE),
        authorized_user_filename=str(AUTHORIZED_USER_FILE),
    )
    print(f"Done. Token saved to {AUTHORIZED_USER_FILE}")
    print("You will not need to do this again.")


# ══════════════════════════════════════════════════════════════════════════════
# Main
# ══════════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(description="Score one sales call end-to-end.")
    parser.add_argument("--setup-google", action="store_true",
                        help="One-time Google Sheets authentication setup.")
    src = parser.add_mutually_exclusive_group()
    src.add_argument("--transcript", help="Path to a .txt transcript")
    src.add_argument("--audio",      help="Path to an audio file (mp3/wav/m4a)")
    parser.add_argument("--name",  default="", help="Prospect name (optional)")
    parser.add_argument("--email", default="", help="Prospect email (optional)")
    parser.add_argument("--phone", default="", help="Prospect phone (optional)")

    # Allow positional shorthand: post_call.py transcript.txt
    parser.add_argument("file", nargs="?", help="Transcript or audio file (positional shorthand)")
    args = parser.parse_args()

    if args.setup_google:
        setup_google()
        return

    # Resolve positional shorthand
    source_file = args.transcript or args.audio or args.file
    if not source_file:
        parser.error("Provide a transcript or audio file.")
    source_path = Path(source_file)
    if not source_path.exists():
        sys.exit(f"File not found: {source_path}")

    is_audio = source_path.suffix.lower() in {".mp3", ".wav", ".m4a", ".ogg", ".flac"}

    # ── Step 1: Transcribe ──
    print("[1/5] Getting transcript...")
    if is_audio:
        text = transcribe(audio_path=str(source_path))
    else:
        text = transcribe(existing_transcript=source_path.read_text(encoding="utf-8"))
    print(f"      {len(text)} characters")

    # ── Step 2: Analyse ──
    print("[2/5] Scoring with Claude...")
    analysis = analyse(text)
    analysis["contact_name"] = analysis.get("contact_name") or args.name
    analysis["phone"]        = analysis.get("phone")        or args.phone
    analysis["email"]        = analysis.get("email")        or args.email
    hot = "  ★ HOT ★" if analysis.get("is_hot") else ""
    print(f"      {analysis['score']}/100  {analysis.get('rating', '')}{hot}")

    # ── Step 3: Write CRM file ──
    print("[3/5] Writing CRM entry...")
    crm_path = write_crm(analysis)
    print(f"      {crm_path}")

    # ── Step 4: Local CSV log ──
    print("[4/5] Appending to local log...")
    append_local_log(analysis)
    print(f"      {LOCAL_LOG}")

    # ── Step 5: Google Sheets ──
    print("[5/5] Saving to Google Sheets...")
    try:
        save_to_sheets(analysis)
    except Exception:
        print("      Google Sheets failed:")
        traceback.print_exc()

    # ── Salesforce (bonus step, silent if not configured) ──
    try:
        save_to_salesforce(analysis)
    except Exception:
        print("[SF]  Salesforce failed:")
        traceback.print_exc()

    # ── Summary ──
    print()
    print("═" * 50)
    print(f"  {analysis.get('contact_name', 'Unknown')}  ({analysis.get('company', '')})")
    print(f"  Score: {analysis['score']}/100  →  {analysis.get('rating', '')}{hot}")
    print(f"  {analysis.get('summary', '')[:120]}...")
    if analysis.get("next_steps"):
        print(f"  Next:  {analysis['next_steps'][0]}")
    print("═" * 50)


if __name__ == "__main__":
    main()
