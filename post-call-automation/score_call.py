"""
score_call.py  —  Post-call lead scorer in ONE file.

Give it a call transcript. It uses Claude to summarise the call, score the lead
0-100, flag the hot ones, and append a row to leads.csv with these columns:

    Date | Score | Rating | HOT? | Name | Company | Email | Phone | Summary | Next Steps | Why

Then it re-sorts leads.csv so the hottest leads sit on top, and prints exactly
what that one call cost you in Claude API tokens.

────────────────────────────────────────────────────────────────────────────
SETUP (about 2 minutes)
    1. Install Python 3.9+  and the one library this needs:
           pip install anthropic
    2. Put your Anthropic API key where the script can find it, EITHER:
           - create a file called  .env  next to this script containing:
                 ANTHROPIC_API_KEY=sk-ant-...
           - or set it as an environment variable ANTHROPIC_API_KEY

RUN IT
    Test with the built-in sample call (no file of your own needed):
        python score_call.py --demo

    Score one of your own calls from a transcript .txt file:
        python score_call.py --transcript call.txt
        python score_call.py --transcript call.txt --name "Maria Lopez" --email maria@acme.com

    Score a whole folder of transcripts at once:
        python score_call.py --folder ./transcripts

CHANGE WHAT "HOT" MEANS
    Edit SCORING_GUIDE below. Change the hot cut-off with  --hot 80  (default 70).
    Pick a model with  --model  (see MODELS below); default is a cheap, sharp one.
────────────────────────────────────────────────────────────────────────────
"""
import argparse
import csv
import glob
import json
import os
import sys
from datetime import datetime

try:
    import anthropic
except ImportError:
    sys.exit("Missing dependency. Run:  pip install anthropic")


# ── The columns of the output sheet, in order. Do not rename casually. ──
HEADER = [
    "Date", "Score", "Rating", "HOT?", "Name", "Company",
    "Email", "Phone", "Summary", "Next Steps", "Why",
]

OUTPUT_CSV = "leads.csv"

# ── What "a good lead" means to you. Tune this to your business. ──
SCORING_GUIDE = """
Score the lead from 0 to 100 based on:
- Budget (25 pts): do they have money to spend / did they mention a budget?
- Authority (20 pts): are they a decision-maker?
- Need (25 pts): is there a clear, urgent problem we solve?
- Timeline (20 pts): are they looking to buy soon (weeks, not "someday")?
- Engagement (10 pts): were they interested, asking questions, positive?
Higher = hotter. Be honest and a little strict.
"""

# ── Claude models you can pick with --model, and their price per 1M tokens. ──
#    (input $ , output $).  Used to print the exact cost of each call.
MODELS = {
    "haiku":  ("claude-haiku-4-5", 1.00, 5.00),    # cheapest, fast
    "sonnet": ("claude-sonnet-5", 3.00, 15.00),    # balanced (great default)
    "opus":   ("claude-opus-4-8", 5.00, 25.00),    # sharpest, priciest
}
DEFAULT_MODEL = "haiku"

SYSTEM_PROMPT = f"""You are a sales-call analyst. You read a phone call transcript
between a salesperson and a prospect, then return a strict JSON object.

{SCORING_GUIDE}

Return ONLY valid JSON with exactly these keys:
{{
  "contact_name": string,             // prospect's full name, "" if unknown
  "company": string,                  // their company, "" if unknown
  "email": string,                    // "" if not mentioned
  "phone": string,                    // "" if not mentioned
  "summary": string,                  // 2-4 sentence summary of the call
  "next_steps": [string],             // recommended follow-up actions
  "score": integer,                   // 0-100 lead score
  "rating": "Hot" | "Warm" | "Cold",  // your overall read
  "reason": string                    // one sentence: why this score
}}
Do not wrap the JSON in markdown. Do not add any commentary."""


# ─────────────────────────────────────────────────────────────────────────────
# Key loading: read .env (if present) then fall back to the environment.
# Kept dependency-free on purpose so the only pip install is `anthropic`.
# ─────────────────────────────────────────────────────────────────────────────
def load_api_key():
    env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")
    if os.path.exists(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, val = line.partition("=")
                if key.strip() == "ANTHROPIC_API_KEY" and not os.environ.get("ANTHROPIC_API_KEY"):
                    os.environ["ANTHROPIC_API_KEY"] = val.strip().strip('"').strip("'")
    key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not key:
        sys.exit(
            "No Anthropic API key found.\n"
            "Put ANTHROPIC_API_KEY=sk-ant-... in a .env file next to this script,\n"
            "or set it as an environment variable."
        )
    return key


def parse_json(raw):
    """Claude is told to return pure JSON; strip stray fences just in case."""
    raw = raw.strip()
    if raw.startswith("```"):
        raw = raw.strip("`")
        if raw.lstrip().lower().startswith("json"):
            raw = raw.lstrip()[4:]
    start, end = raw.find("{"), raw.rfind("}")
    if start != -1 and end != -1:
        return json.loads(raw[start:end + 1])
    return json.loads(raw)


def analyze(client, model_id, transcript):
    """Send one transcript to Claude, return (analysis dict, cost in dollars)."""
    msg = client.messages.create(
        model=model_id,
        max_tokens=1500,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": f"Call transcript:\n\n{transcript}"}],
    )
    data = parse_json(msg.content[0].text)

    # Cost of this one call, from real token usage.
    _, in_price, out_price = next(m for m in MODELS.values() if m[0] == model_id)
    cost = (msg.usage.input_tokens / 1_000_000) * in_price \
        + (msg.usage.output_tokens / 1_000_000) * out_price

    return data, cost, msg.usage.input_tokens, msg.usage.output_tokens


def build_row(data, hot_threshold, overrides):
    """Turn Claude's analysis into one CSV row matching HEADER exactly."""
    score = data.get("score", 0)
    try:
        score = max(0, min(100, int(score)))
    except (ValueError, TypeError):
        score = 0
    is_hot = score >= hot_threshold

    next_steps = data.get("next_steps") or []
    if isinstance(next_steps, str):
        next_steps = [next_steps]

    return {
        "Date": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "Score": score,
        "Rating": data.get("rating", ""),
        "HOT?": "HOT" if is_hot else "",
        "Name": overrides.get("name") or data.get("contact_name", ""),
        "Company": data.get("company", ""),
        "Email": overrides.get("email") or data.get("email", ""),
        "Phone": overrides.get("phone") or data.get("phone", ""),
        "Summary": data.get("summary", ""),
        "Next Steps": " | ".join(str(s) for s in next_steps),
        "Why": data.get("reason", ""),
    }


def save_row(row):
    """Append the row to leads.csv (writing the header first time), then
    re-sort every data row by Score, highest first."""
    rows = []
    if os.path.exists(OUTPUT_CSV):
        with open(OUTPUT_CSV, "r", encoding="utf-8-sig", newline="") as f:
            rows = list(csv.DictReader(f))

    rows.append({k: str(row[k]) for k in HEADER})

    def score_of(r):
        try:
            return int(r.get("Score", 0))
        except (ValueError, TypeError):
            return 0
    rows.sort(key=score_of, reverse=True)

    with open(OUTPUT_CSV, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=HEADER)
        writer.writeheader()
        writer.writerows(rows)


def print_lead(row, cost, in_tok, out_tok):
    flag = "   *** HOT ***" if row["HOT?"] else ""
    print(f"  Name:    {row['Name']}  ({row['Company']})")
    print(f"  Score:   {row['Score']}/100  ->  {row['Rating']}{flag}")
    print(f"  Summary: {row['Summary']}")
    if row["Next Steps"]:
        print(f"  Next:    {row['Next Steps']}")
    print(f"  Cost:    ${cost:.4f}  ({in_tok} in + {out_tok} out tokens)")


SAMPLE_TRANSCRIPT = (
    "Salesperson: Thanks for taking my call, Maria. You mentioned your team "
    "is struggling to keep up with support tickets?\n"
    "Maria: Yes, we're a 40-person company and drowning. We have budget "
    "approved, around 30 thousand for this year, and I'm the VP of Ops so I "
    "can sign off. We'd want to be live within the month.\n"
    "Salesperson: That's very doable. Any concerns?\n"
    "Maria: Just integration with our current CRM, but if that works we're "
    "ready to move fast. Can you send a proposal today? You can reach me at "
    "maria@acme.com or 555-0142."
)


def main():
    p = argparse.ArgumentParser(
        description="Score a sales call and append it to leads.csv.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument("--transcript", help="Path to a .txt transcript of one call")
    src.add_argument("--folder", help="Path to a folder of .txt transcripts")
    src.add_argument("--demo", action="store_true", help="Score a built-in sample call")
    p.add_argument("--name", default="", help="Prospect name (optional override)")
    p.add_argument("--email", default="", help="Prospect email (optional override)")
    p.add_argument("--phone", default="", help="Prospect phone (optional override)")
    p.add_argument("--hot", type=int, default=70, help="Score at/above which a lead is HOT (default 70)")
    p.add_argument("--model", choices=MODELS.keys(), default=DEFAULT_MODEL,
                   help=f"Which Claude model to use (default {DEFAULT_MODEL})")
    args = p.parse_args()

    client = anthropic.Anthropic(api_key=load_api_key())
    model_id = MODELS[args.model][0]
    overrides = {"name": args.name, "email": args.email, "phone": args.phone}

    # Collect the calls to process: (label, transcript_text)
    calls = []
    if args.demo:
        calls.append(("built-in sample", SAMPLE_TRANSCRIPT))
    elif args.transcript:
        try:
            with open(args.transcript, "r", encoding="utf-8") as f:
                calls.append((args.transcript, f.read()))
        except OSError as e:
            sys.exit(f"Could not read transcript: {e}")
    else:
        paths = sorted(glob.glob(os.path.join(args.folder, "*.txt")))
        if not paths:
            sys.exit(f"No .txt transcripts found in {args.folder}")
        for path in paths:
            with open(path, "r", encoding="utf-8") as f:
                calls.append((path, f.read()))

    print(f"Model: {model_id}   Hot cut-off: {args.hot}\n")

    total_cost = 0.0
    processed = 0
    for label, text in calls:
        if not text.strip():
            print(f"- {label}: empty transcript, skipped\n")
            continue
        print(f"- {label}")
        try:
            data, cost, in_tok, out_tok = analyze(client, model_id, text)
        except Exception as e:
            print(f"  FAILED: {e}\n")
            continue
        # Per-file overrides only make sense for a single call; skip for folders.
        row = build_row(data, args.hot, overrides if len(calls) == 1 else {})
        save_row(row)
        print_lead(row, cost, in_tok, out_tok)
        print()
        total_cost += cost
        processed += 1

    if processed:
        print(f"Done. {processed} call(s) scored, saved to {OUTPUT_CSV}.")
        print(f"Total spend: ${total_cost:.4f}   Average per call: ${total_cost / processed:.4f}")


if __name__ == "__main__":
    main()
