# T1 — report, written by the secretary

The builder hit its step cap and did not write this file. Its account is corrected below where I
found it wrong. Everything here I re-ran myself.

## Changed

Owned by the builder, verified by me:

- `scripts/fetch_cpi.py` — catalog scraper, 31 resources, sha256 cache
- `scripts/extract_cpi.py` — Table 5 parser, xlsx and PDF
- `scripts/qa_panel.py` — panel checks
- `data/panel/state_food_cpi.csv` — 1,702 rows, 23 months, 37 jurisdictions
- `data/panel/lookbacks.csv` — 3,404 lookback rows
- `data/panel/manifest.json` — 31 raw files with url, sha256, bytes
- `data/reference/state_crosswalk.csv`, `data/reference/base_year_evidence.csv`
- `data/raw/nbs/**` — 31 downloads, 16 ZIPs unpacked

Mine:

- `data/panel/qc_flags.csv` — five flags, created
- `scripts/_probe_*.py` — eleven scratch files, deleted
- `.agent/T1-report.md` — this file

## Verified

`python scripts/qa_panel.py` → 1,702 rows; 23 of 82 target months; "months with != 37
jurisdictions: 0 PASS"; "duplicate keys: 0 PASS" (**this check is wrong, see below**); Bauchi
collision present in 13 of 23 workbooks.

Independent chain test (my own code, not the builder's): for every consecutive pair of months, compare
file(t)'s previous-month column against file(t−1)'s focus column, across 37 states × 2 series.

```
2024-11 -> 2024-12: 74/74      2025-05 -> 2025-06: 72/72
2025-02 -> 2025-03: 74/74      2025-06 -> 2025-07: 74/74
2025-03 -> 2025-04: 74/74      ... all remaining pairs 72-74/74
2025-04 -> 2025-05: 13/72   <== only break in the series
```

PDF against xlsx calibration, December 2024, 74 pairs: all agree within 0.05, the PDF printing one
decimal. **The PDF parser therefore reads Table 5 correctly**, which matters before we spend a
hundred downloads on PDF-only months.

Metadata probes: `nigerianstat.gov.ng/download/<id>` returns `application/pdf` for both a 2022 report
and a 2020-era one; the saved e-library listing holds 1,695 report ids including 152 CPI reports back
past 2020.

## Deviations, and two corrections to the builder's account

1. The builder said `fetch_cpi.py` was left broken mid-edit and would "currently fail to run". It
   compiles and `--help` works; no reference to `--pdf-sweep`, `--max-requests` or `PDF_ROOT0` exists
   in the file. Nothing was broken.
2. The builder said April 2025's defect is "not a row or column offset". It is a row-level
   contamination: 59 of 72 values disagree with the May 2025 file's lookback, and the Benue and Borno
   rows carry each other's numbers.
3. The builder said February 2025 and February 2026 "disagree on all 37 states", implying a
   restatement to hand to the analyst. The chain shows February 2025 is corroborated twice (by the
   March 2025 file and by itself), so the odd one out is the February 2026 file's year-ago column, not
   the month. The November and December 2024 disagreements are not revisions at all — they are base
   2009 against base 2024.

## Defect the builder's own QA missed

`qa_panel.py` reports "duplicate keys: 0 PASS", but December 2024 appears **148 times**, twice for
every state and series, because the month was parsed from both the PDF and the xlsx. The check passes
only because its key includes the source file. Keyed properly on (jurisdiction, month, series) there
are 74 duplicate observations. Any count, mean or model built on this table without deduping
double-weights December 2024.

## Coverage

23 of 82 months held: 2024-11 through 2026-10, with two gaps inside that span (2025-01 absent from
the catalog; 2026-03 present but as legacy `.xls`).

59 months missing, all 2020-01..2024-10. They are recoverable: the ids are known and the download
endpoint is confirmed.

## Unproven

- Whether the pre-2024 PDFs have a text layer at all. December 2023 to March 2024 are on disk but
  were not parsed; older ones are untested.
- Whether the 2025-02 discrepancy is an NBS revision or an NBS error. The files cannot settle it.
- My chain test covers 22 of 23 workbooks; the legacy `.xls` month was skipped by my checker, so
  2026-03 to 2026-04 is untested by me (the builder's extractor did read that month).
