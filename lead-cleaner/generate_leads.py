import csv
import random

first_names = [
    "James", "Oliver", "Harry", "Jack", "George", "Noah", "Charlie", "Jacob",
    "Alfie", "Freddie", "Emily", "Olivia", "Isla", "Ava", "Mia", "Isabella",
    "Sophie", "Ella", "Grace", "Lily",
]

last_names = [
    "Smith", "Jones", "Williams", "Taylor", "Brown", "Davies", "Evans",
    "Wilson", "Thomas", "Roberts", "Johnson", "Walker", "Wright", "Thompson",
    "White", "Hall", "Green", "Wood", "Harris", "Lewis",
]

companies = [
    "Apex Solutions Ltd", "Northgate Technologies", "Pemberton & Co",
    "Redwood Consulting", "Silverbridge Group", "Tandem Digital",
    "Unity Systems", "Vantage Partners", "Westfield Services",
    "Yarrow Innovations", "Zenith Strategies", "Caldwell Enterprises",
    "Dunmore Trading", "Elmwood Advisory", "Fairfax Logistics",
]

def clean_uk_number():
    """Generate a well-formatted UK mobile number."""
    return f"07{random.randint(100,999)} {random.randint(100,999)} {random.randint(100,999)}"

def messy_uk_number():
    """Generate a badly formatted UK mobile number."""
    digits = f"07{random.randint(100,999)}{random.randint(100,999)}{random.randint(100,999)}"
    style = random.choice([
        lambda d: d,                                    # no spaces at all
        lambda d: f"+44{d[1:]}",                       # +44 prefix, no space
        lambda d: f"+44 (0){d[1:4]} {d[4:7]} {d[7:]}",# +44 (0) style
        lambda d: f"({d[:5]}) {d[5:8]}-{d[8:]}",      # bracketed area code
        lambda d: d.replace("07", "7", 1),             # missing leading 0
        lambda d: f"0{d}",                             # extra leading 0
    ])
    return style(digits)

def make_row(name, phone, company):
    return {"name": name, "phone": phone, "company": company}

rows = []

# 35 clean-ish rows
for _ in range(35):
    name = f"{random.choice(first_names)} {random.choice(last_names)}"
    phone = clean_uk_number()
    company = random.choice(companies)
    rows.append(make_row(name, phone, company))

# 8 rows with badly formatted phone numbers
for _ in range(8):
    name = f"{random.choice(first_names)} {random.choice(last_names)}"
    phone = messy_uk_number()
    company = random.choice(companies)
    rows.append(make_row(name, phone, company))

# 4 rows with missing fields
for _ in range(4):
    name = f"{random.choice(first_names)} {random.choice(last_names)}"
    missing = random.choice(["phone", "company", "name"])
    row = {
        "name": "" if missing == "name" else name,
        "phone": "" if missing == "phone" else clean_uk_number(),
        "company": "" if missing == "company" else random.choice(companies),
    }
    rows.append(row)

# 3 exact duplicate rows (copy existing rows)
for _ in range(3):
    rows.append(random.choice(rows[:35]))

random.shuffle(rows)

output_path = "messy_leads.csv"
with open(output_path, "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=["name", "phone", "company"])
    writer.writeheader()
    writer.writerows(rows)

print(f"Written {len(rows)} rows to {output_path}")

# Print a preview
with open(output_path, encoding="utf-8") as f:
    for i, line in enumerate(f):
        print(line, end="")
        if i >= 10:
            print("...")
            break
