import csv
import re
from pathlib import Path

INPUT  = Path(__file__).parent / "messy_leads.csv"
OUTPUT = Path(__file__).parent / "clean_leads.csv"


def normalise_phone(raw: str) -> str | None:
    """Return an 11-digit UK number formatted as '07XXX XXXXXX', or None if unfixable."""
    digits = re.sub(r"\D", "", raw)

    # +44... or 0044... → replace country code with leading 0
    if digits.startswith("44") and len(digits) == 12:
        digits = "0" + digits[2:]
    elif digits.startswith("0044") and len(digits) == 14:
        digits = "0" + digits[4:]

    # 7XXXXXXXXX (10 digits, missing leading 0)
    if len(digits) == 10 and digits.startswith("7"):
        digits = "0" + digits

    if len(digits) == 11 and digits.startswith("07"):
        return f"{digits[:5]} {digits[5:]}"

    return None  # can't fix


def main():
    rows_in = []
    with open(INPUT, newline="", encoding="utf-8") as f:
        rows_in = list(csv.DictReader(f))

    total_in = len(rows_in)
    seen = set()
    duplicates_removed = 0
    flagged = 0
    output_rows = []

    for row in rows_in:
        # Deduplicate on the raw original values
        key = (row["name"].strip(), row["phone"].strip(), row["company"].strip())
        if key in seen:
            duplicates_removed += 1
            continue
        seen.add(key)

        name    = row["name"].strip()
        phone   = row["phone"].strip()
        company = row["company"].strip()

        # Fix phone
        fixed_phone = normalise_phone(phone) if phone else None

        # Determine flags
        flags = []
        if not name:
            flags.append("missing_name")
        if not phone:
            flags.append("missing_phone")
        elif fixed_phone is None:
            flags.append("unfixable_phone")
        if not company:
            flags.append("missing_company")

        if flags:
            flagged += 1

        output_rows.append({
            "name":    name,
            "phone":   fixed_phone if fixed_phone else phone,
            "company": company,
            "flags":   "|".join(flags),
        })

    with open(OUTPUT, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["name", "phone", "company", "flags"])
        writer.writeheader()
        writer.writerows(output_rows)

    clean_count = len(output_rows)
    print(f"Rows in:            {total_in}")
    print(f"Duplicates removed: {duplicates_removed}")
    print(f"Rows out:           {clean_count}")
    print(f"Flagged rows:       {flagged}")
    print(f"\nOutput written to: {OUTPUT}")

    flagged_rows = [r for r in output_rows if r["flags"]]
    if flagged_rows:
        print("\nFlagged rows:")
        for r in flagged_rows:
            print(f"  [{r['flags']}]  name={r['name']!r}  phone={r['phone']!r}  company={r['company']!r}")


if __name__ == "__main__":
    main()
