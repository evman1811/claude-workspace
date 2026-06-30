# Lead Cleaning Report — Batch 2026-06-30

**Source file:** `messy_leads.csv` (25 rows)
**Output file:** `clean_leads.csv` (23 rows)
**Processed:** 2026-06-30

## Summary

| Metric | Count |
|---|---|
| Rows in | 25 |
| Exact duplicates removed | 2 |
| Rows out | 23 |
| Rows flagged for review | 6 |
| Clean & ready to use | 17 |

## What was fixed automatically

| Issue | Example in | Normalised to |
|---|---|---|
| `+44` country code | `+447822119045` | `07822 119045` |
| `0044` country code | `0044 7700 118 246` | `07700 118246` |
| Missing leading `0` | `7903 556 218` | `07903 556218` |
| Brackets / dashes | `(07845) 661-220` | `07845 661220` |
| Irregular spacing | `079 1234 5678` | `07912 345678` |
| Exact duplicate rows | Oliver Bennett, Maya Patel | removed |

## Flagged rows (need a human)

| Flag | Name | Phone | Company |
|---|---|---|---|
| unfixable_phone | Thomas Reed | `007911 220 184` | Halcyon Media |
| unfixable_phone | Samuel Adeyemi | `00788863 7705` | Oakhill Consulting |
| unfixable_phone | Jack Sullivan | `07999 ABC 123` | Meridian Labs |
| missing_name | — | `07688 410559` | Kingsley Partners |
| missing_company | Chloe Barnes | `07845 220991` | — |
| missing_phone | Ivy Chamberlain | — | Oakhill Consulting |

## Known limitation surfaced this batch

Amelia Croft appears **twice** in the clean output (`+447822119045` and
`00447822119045`). Deduplication runs on the *raw* values before phone
normalisation, so two different formats of the same number are not caught as
duplicates. Worth fixing in a future version by deduping on the normalised phone.
