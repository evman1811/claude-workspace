import sys
from pathlib import Path

# Reuse the normalisation/cleaning logic from the main lead-cleaner script,
# but point it at this batch's input/output files.
sys.path.insert(0, str(Path(__file__).parents[2]))
import clean_leads as core

core.INPUT = Path(__file__).parent / "messy_leads.csv"
core.OUTPUT = Path(__file__).parent / "clean_leads.csv"

if __name__ == "__main__":
    core.main()
