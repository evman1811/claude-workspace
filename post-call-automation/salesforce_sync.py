"""Step 5 - push the lead into Salesforce.

We create a Lead (or update an existing one with the same email). The summary
goes in the Description, the Hot/Warm/Cold read goes in the standard Rating
field, and the numeric score goes in a custom field IF you created one.
"""
from simple_salesforce import Salesforce

import config


def _connect():
    return Salesforce(
        username=config.SF_USERNAME,
        password=config.SF_PASSWORD,
        security_token=config.SF_SECURITY_TOKEN,
        domain=config.SF_DOMAIN,  # "login" = production, "test" = sandbox
    )


def push_lead(analysis):
    sf = _connect()

    # Salesforce Leads require a LastName and a Company; fall back gracefully.
    name = (analysis.get("contact_name") or "Unknown Caller").strip()
    parts = name.split()
    last_name = parts[-1] if parts else "Caller"
    first_name = " ".join(parts[:-1]) if len(parts) > 1 else ""

    fields = {
        "LastName": last_name,
        "FirstName": first_name,
        "Company": analysis.get("company") or "Unknown",
        "Email": analysis.get("email") or None,
        "Phone": analysis.get("phone") or None,
        "Description": _build_description(analysis),
        "Rating": analysis.get("rating") or "Cold",   # standard Hot/Warm/Cold
        "LeadSource": "Phone Call",
    }
    # Optional numeric score, only if you created a custom field for it.
    if config.SF_SCORE_FIELD:
        fields[config.SF_SCORE_FIELD] = analysis.get("score", 0)

    # Drop empty values Salesforce would reject.
    fields = {k: v for k, v in fields.items() if v not in (None, "")}

    # Update if a Lead with this email already exists, otherwise create one.
    email = analysis.get("email")
    if email:
        existing = sf.query(f"SELECT Id FROM Lead WHERE Email = '{email}' LIMIT 1")
        if existing["records"]:
            lead_id = existing["records"][0]["Id"]
            sf.Lead.update(lead_id, fields)
            return lead_id

    return sf.Lead.create(fields)["id"]


def _build_description(a):
    parts = [a.get("summary", "")]
    if a.get("key_points"):
        parts.append("\nKey points:\n- " + "\n- ".join(a["key_points"]))
    if a.get("objections"):
        parts.append("\nObjections:\n- " + "\n- ".join(a["objections"]))
    if a.get("next_steps"):
        parts.append("\nNext steps:\n- " + "\n- ".join(a["next_steps"]))
    parts.append(f"\nScore: {a.get('score')}/100 ({a.get('rating')}) - {a.get('reason', '')}")
    return "\n".join(p for p in parts if p)
