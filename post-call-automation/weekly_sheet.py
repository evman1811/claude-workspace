"""Step 6 - save the lead into THIS WEEK's tab of your Google Sheet and keep the
hottest leads pinned to the top.

Each ISO week gets its own tab (e.g. "Week 2026-W26"). After every write we
re-sort that tab by score, highest first.

Auth: uses OAuth 2.0 (your Google account) via credentials.json.
      Run  python setup_google_auth.py  once to authenticate.
"""
import os
from datetime import datetime
from pathlib import Path

import gspread

import config

SCOPES = [
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive",
]

HEADER = [
    "Date", "Score", "Rating", "Hot?", "Name", "Company",
    "Email", "Phone", "Summary", "Next Steps", "Why",
]

CREDENTIALS_FILE = Path(__file__).parent / "credentials.json"
AUTHORIZED_USER_FILE = Path.home() / ".config" / "gspread" / "authorized_user.json"


def _client():
    # If already authorised (token cached) use it directly.
    if AUTHORIZED_USER_FILE.exists():
        return gspread.oauth(
            credentials_filename=str(CREDENTIALS_FILE),
            authorized_user_filename=str(AUTHORIZED_USER_FILE),
        )

    # First run: credentials.json must exist to open the browser auth flow.
    if not CREDENTIALS_FILE.exists():
        raise FileNotFoundError(
            "Google auth not set up yet.\n"
            "Run:  python setup_google_auth.py\n"
            "See the README for how to get credentials.json."
        )

    return gspread.oauth(
        credentials_filename=str(CREDENTIALS_FILE),
        authorized_user_filename=str(AUTHORIZED_USER_FILE),
    )


def _week_tab_name(when):
    iso = when.isocalendar()
    return f"Week {iso[0]}-W{iso[1]:02d}"


def save_lead(analysis):
    gc = _client()
    sheet = gc.open_by_key(config.GOOGLE_SHEET_ID)

    tab_name = _week_tab_name(datetime.now())
    try:
        ws = sheet.worksheet(tab_name)
    except gspread.WorksheetNotFound:
        ws = sheet.add_worksheet(title=tab_name, rows=200, cols=len(HEADER))
        ws.append_row(HEADER, value_input_option="USER_ENTERED")

    row = [
        datetime.now().strftime("%Y-%m-%d %H:%M"),
        analysis.get("score", 0),
        analysis.get("rating", ""),
        "HOT" if analysis.get("is_hot") else "",
        analysis.get("contact_name", ""),
        analysis.get("company", ""),
        analysis.get("email", ""),
        analysis.get("phone", ""),
        analysis.get("summary", ""),
        " | ".join(analysis.get("next_steps", [])),
        analysis.get("reason", ""),
    ]
    ws.append_row(row, value_input_option="USER_ENTERED")

    # Re-sort everything below the header by Score (col 2), highest first.
    row_count = len(ws.get_all_values())
    if row_count > 2:
        last_col = chr(ord("A") + len(HEADER) - 1)  # "K" for 11 columns
        ws.sort((2, "des"), range=f"A2:{last_col}{row_count}")

    return tab_name
