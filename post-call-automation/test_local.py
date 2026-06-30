"""Try the whole brain WITHOUT a phone call.

This feeds a sample transcript straight through the pipeline so you can confirm
your API keys work and watch a lead get scored, pushed to Salesforce, and
written to your weekly Google Sheet.

Run:   python test_local.py
"""
from process_call import process_call

SAMPLE = {
    "recording_url": None,
    "transcript": (
        "Salesperson: Thanks for taking my call, Maria. You mentioned your team "
        "is struggling to keep up with support tickets?\n"
        "Maria: Yes, we're a 40-person company and drowning. We have budget "
        "approved, around 30 thousand for this year, and I'm the VP of Ops so I "
        "can sign off. We'd want to be live within the month.\n"
        "Salesperson: That's very doable. Any concerns?\n"
        "Maria: Just integration with our current CRM, but if that works we're "
        "ready to move fast. Can you send a proposal today?"
    ),
    "caller_name": "Maria Lopez",
    "caller_phone": "+1 555 0142",
    "caller_email": "maria@acme.com",
}

if __name__ == "__main__":
    print("Running a sample call through the pipeline...\n")
    result = process_call(SAMPLE)
    print("\n--- Result ---")
    print(f"Name:    {result.get('contact_name')} ({result.get('company')})")
    print(f"Score:   {result.get('score')}/100  ->  {result.get('rating')}")
    print(f"Hot?:    {result.get('is_hot')}")
    print(f"Summary: {result.get('summary')}")
