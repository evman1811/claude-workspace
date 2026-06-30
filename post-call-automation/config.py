"""Central configuration. Everything is read from your .env file so no secret
ever lives in the code itself."""
import os
from dotenv import load_dotenv

load_dotenv()

# Claude
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")
CLAUDE_MODEL = os.getenv("CLAUDE_MODEL", "claude-sonnet-4-6")

# Whisper / OpenAI (only needed for audio files; not needed if you pass text)
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")

# Salesforce
SF_USERNAME = os.getenv("SF_USERNAME", "")
SF_PASSWORD = os.getenv("SF_PASSWORD", "")
SF_SECURITY_TOKEN = os.getenv("SF_SECURITY_TOKEN", "")
SF_DOMAIN = os.getenv("SF_DOMAIN", "login")
SF_SCORE_FIELD = os.getenv("SF_SCORE_FIELD", "").strip()

# Google Sheets
GOOGLE_SERVICE_ACCOUNT_JSON = os.getenv("GOOGLE_SERVICE_ACCOUNT_JSON", "google-service-account.json")
GOOGLE_SHEET_ID = os.getenv("GOOGLE_SHEET_ID", "")
MY_EMAIL = os.getenv("MY_EMAIL", "")

# Scoring
HOT_THRESHOLD = int(os.getenv("HOT_THRESHOLD", "70"))

# Team / central watch-folder mode (watch_folder.py)
# Point this at a SHARED folder your reps drop call files into.
INCOMING_DIR = os.getenv("INCOMING_DIR", "incoming")
