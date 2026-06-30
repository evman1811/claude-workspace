"""Steps 3 + 4 - Claude reads the transcript and returns a structured analysis:
summary, key points, next steps, a 0-100 lead score, a Hot/Warm/Cold rating,
and any contact details it can pull out of the conversation.

>>> Edit SCORING_GUIDE below to match how YOU judge a good lead. <<<
"""
import json

import anthropic

import config

# ── Tune this to your business. This is what "hot" means to you. ──
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
  "contact_name": string,             // prospect's full name, "" if unknown
  "company": string,                  // their company, "" if unknown
  "email": string,                    // "" if not mentioned
  "phone": string,                    // "" if not mentioned
  "summary": string,                  // 2-4 sentence summary of the call
  "key_points": [string],             // the important details
  "next_steps": [string],             // recommended follow-up actions
  "objections": [string],             // concerns the prospect raised
  "score": integer,                   // 0-100 lead score
  "rating": "Hot" | "Warm" | "Cold",  // your overall read
  "reason": string                    // one sentence: why this score
}}
Do not wrap the JSON in markdown. Do not add any commentary."""


def analyze(transcript):
    client = anthropic.Anthropic(api_key=config.ANTHROPIC_API_KEY)
    message = client.messages.create(
        model=config.CLAUDE_MODEL,
        max_tokens=1500,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": f"Call transcript:\n\n{transcript}"}],
    )
    raw = message.content[0].text.strip()
    data = _parse_json(raw)

    # Safety net: clamp the score and decide "hot" using your threshold.
    score = int(data.get("score", 0))
    data["score"] = max(0, min(100, score))
    data["is_hot"] = data["score"] >= config.HOT_THRESHOLD
    return data


def _parse_json(raw):
    # Claude is told to return pure JSON, but strip code fences just in case.
    if raw.startswith("```"):
        raw = raw.strip("`")
    start, end = raw.find("{"), raw.rfind("}")
    if start != -1 and end != -1:
        return json.loads(raw[start:end + 1])
    return json.loads(raw)
