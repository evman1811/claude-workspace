"""Run this ONCE to connect your Google account.

Your browser will open → log in → click Allow → done.
The token is cached locally and never needs doing again.

Requires credentials.json in this folder (see README for how to get it).
"""
from pathlib import Path
import gspread

CREDENTIALS_FILE = Path(__file__).parent / "credentials.json"
AUTHORIZED_USER_FILE = Path.home() / ".config" / "gspread" / "authorized_user.json"

if not CREDENTIALS_FILE.exists():
    print("ERROR: credentials.json not found in this folder.")
    print()
    print("To get it:")
    print("  1. Go to https://console.cloud.google.com")
    print("  2. Create a project (or pick an existing one)")
    print("  3. APIs & Services → Enable: Google Sheets API + Google Drive API")
    print("  4. APIs & Services → Credentials → + Create Credentials → OAuth client ID")
    print("  5. Application type: Desktop app  →  Create  →  Download JSON")
    print("  6. Rename the downloaded file to  credentials.json")
    print("  7. Put it in this folder, then run this script again.")
    raise SystemExit(1)

print("Opening your browser — log in and click Allow...")
AUTHORIZED_USER_FILE.parent.mkdir(parents=True, exist_ok=True)
gc = gspread.oauth(
    credentials_filename=str(CREDENTIALS_FILE),
    authorized_user_filename=str(AUTHORIZED_USER_FILE),
)
print(f"Success! Token saved to {AUTHORIZED_USER_FILE}")
print("You won't need to do this again.")
