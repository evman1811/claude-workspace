"""Runs the full pipeline for a single call:
transcript -> Claude analysis -> Salesforce -> weekly Google Sheet.

Each external step is wrapped so a missing or invalid config doesn't crash the
whole run; it just logs and continues. That lets you set up one piece at a time.
"""
import traceback

import config
import transcribe
import analyze
import salesforce_sync
import weekly_sheet


def process_call(call):
    """`call` is a dict with any of:
       transcript, audio_path, recording_url,
       caller_name, caller_phone, caller_email
    """
    # Step 1 - get the transcript
    text = transcribe.transcribe(
        recording_url=call.get("recording_url"),
        existing_transcript=call.get("transcript"),
        audio_path=call.get("audio_path"),
    )
    print(f"[1/4] Transcript ready ({len(text)} characters)")

    # Steps 2 + 3 - Claude summary + score
    analysis = analyze.analyze(text)
    # Prefer details Claude found; fall back to anything you passed in.
    analysis["contact_name"] = analysis.get("contact_name") or call.get("caller_name", "")
    analysis["phone"] = analysis.get("phone") or call.get("caller_phone", "")
    analysis["email"] = analysis.get("email") or call.get("caller_email", "")
    flag = "HOT" if analysis.get("is_hot") else analysis.get("rating", "")
    print(f"[2/4] Scored {analysis['score']}/100  {flag}")

    # Step 4 - Salesforce
    try:
        if config.SF_USERNAME:
            lead_id = salesforce_sync.push_lead(analysis)
            print(f"[3/4] Salesforce lead saved: {lead_id}")
        else:
            print("[3/4] Salesforce not configured - skipped")
    except Exception:
        print("[3/4] Salesforce failed:")
        traceback.print_exc()

    # Step 5 - weekly Google Sheet
    try:
        if config.GOOGLE_SHEET_ID:
            tab = weekly_sheet.save_lead(analysis)
            print(f"[4/4] Saved to Google Sheet tab: {tab}")
        else:
            print("[4/4] Google Sheet not configured - skipped")
    except Exception:
        print("[4/4] Google Sheet failed:")
        traceback.print_exc()

    return analysis
