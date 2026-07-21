"""
webhook_server.py — auto-receives transcripts from any phone system
===================================================================
Phone call ends → phone system POSTs transcript here → pipeline runs automatically.

START:
  python webhook_server.py

USAGE:
  Point your phone system's webhook to:
    http://<your-ip>:5000/webhook

  The server accepts JSON payloads and tries common field names used by
  Aircall, Dialpad, JustCall, RingCentral, Twilio, CallRail, etc.
  It also accepts plain-text bodies as a fallback.

  Minimum payload (works with any system):
    { "transcript": "Full call text here..." }

  Optional extra fields (used if Claude can't extract them from the transcript):
    { "transcript": "...", "name": "John Smith", "phone": "07700900000", "email": "j@co.com" }
"""

import sys
from pathlib import Path
from flask import Flask, request, jsonify

# Import pipeline functions from post_call.py (same folder)
sys.path.insert(0, str(Path(__file__).parent))
import post_call

app = Flask(__name__)


def _extract_transcript(data: dict) -> str:
    """Pull transcript text from whatever shape the phone system sends."""

    # ── Flat string fields (most systems) ──────────────────────────────────────
    for key in ("transcript", "transcription", "transcript_text",
                "call_transcript", "text", "content", "body", "message"):
        val = data.get(key)
        if isinstance(val, str) and val.strip():
            return val.strip()

    # ── Array of segment objects  e.g. Dialpad, Aircall ────────────────────────
    for key in ("transcript", "transcription", "segments", "utterances", "words"):
        val = data.get(key)
        if isinstance(val, list):
            parts = []
            for seg in val:
                if isinstance(seg, dict):
                    text = seg.get("text") or seg.get("content") or seg.get("transcript") or ""
                    speaker = seg.get("speaker") or seg.get("user") or seg.get("role") or ""
                    if text:
                        parts.append(f"{speaker}: {text}".strip(": "))
                elif isinstance(seg, str):
                    parts.append(seg)
            joined = "\n".join(parts).strip()
            if joined:
                return joined

    # ── Nested under a "call" or "recording" object ────────────────────────────
    for wrapper in ("call", "recording", "payload", "data", "result"):
        nested = data.get(wrapper)
        if isinstance(nested, dict):
            result = _extract_transcript(nested)
            if result:
                return result

    return ""


def _extract_meta(data: dict) -> dict:
    """Pull optional name / phone / email hints from the payload."""
    flat = {}
    for wrapper in (data, data.get("call", {}), data.get("contact", {}),
                    data.get("payload", {}), data.get("data", {})):
        if not isinstance(wrapper, dict):
            continue
        flat.update(wrapper)

    name = (flat.get("contact_name") or flat.get("name") or
            flat.get("caller_name") or flat.get("prospect_name") or "")
    phone = (flat.get("phone") or flat.get("caller_phone") or
             flat.get("from_number") or flat.get("from") or "")
    email = (flat.get("email") or flat.get("caller_email") or
             flat.get("prospect_email") or "")
    return {"name": name, "phone": phone, "email": email}


@app.route("/webhook", methods=["POST"])
def webhook():
    # Accept JSON or plain-text body
    if request.is_json:
        data = request.get_json(force=True, silent=True) or {}
    else:
        raw = request.get_data(as_text=True).strip()
        data = {"transcript": raw} if raw else {}

    transcript = _extract_transcript(data)
    if not transcript:
        return jsonify({"error": "No transcript found in payload"}), 400

    meta = _extract_meta(data)

    try:
        analysis = post_call.analyse(transcript)
        analysis["contact_name"] = analysis.get("contact_name") or meta["name"]
        analysis["phone"]        = analysis.get("phone")        or meta["phone"]
        analysis["email"]        = analysis.get("email")        or meta["email"]

        post_call.write_crm(analysis)
        post_call.append_local_log(analysis)

        try:
            post_call.save_to_sheets(analysis)
        except Exception as e:
            app.logger.warning(f"Sheets skipped: {e}")

        try:
            post_call.save_to_salesforce(analysis)
        except Exception as e:
            app.logger.warning(f"Salesforce skipped: {e}")

        hot = analysis.get("is_hot", False)
        return jsonify({
            "status":  "ok",
            "score":   analysis["score"],
            "rating":  analysis["rating"],
            "hot":     hot,
            "name":    analysis.get("contact_name", ""),
            "company": analysis.get("company", ""),
            "summary": analysis.get("summary", ""),
        }), 200

    except Exception as e:
        app.logger.error(f"Pipeline error: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200


if __name__ == "__main__":
    print("Webhook server running on http://0.0.0.0:5000")
    print("Point your phone system to: http://<your-ip>:5000/webhook")
    app.run(host="0.0.0.0", port=5000, debug=False)
