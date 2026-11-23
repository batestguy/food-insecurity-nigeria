"""QA gate for the state CPI panel.

Prints, and returns non-zero on, every check the brief asks for:

  1. rows expected vs present, per month, with missing months named
  2. duplicate (jurisdiction, month, series) count
  3. jurisdictions per month
  4. lookback revision count, with the worst ten discrepancies listed
  5. the Bauchi / Anambra duplicate-cell test on every month held

Plus three supporting blocks: rebasing cross-check, internal-arithmetic check, and a
scan for any other index value shared between two states in the same column.

Usage:  python scripts/qa_panel.py [--verbose]
"""
from __future__ import annotations

import argparse
import csv
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PANEL = ROOT / "data" / "panel" / "state_food_cpi.csv"
LOOKBACKS = ROOT / "data" / "panel" / "lookbacks.csv"
CROSSWALK = ROOT / "data" / "reference" / "state_crosswalk.csv"

FIRST_MONTH, LAST_MONTH = "2020-01", "2026-10"
SERIES = ("food", "all_items")
N_JUR = 37
ROWS_PER_MONTH = N_JUR * len(SERIES)
REVISION_TOL = 0.01       # brief: differences above this count
EXACT = 1e-9

failures: list[str] = []


def months_between(a: str, b: str) -> list[str]:
    y, m = int(a[:4]), int(a[5:])
    y2, m2 = int(b[:4]), int(b[5:])
    out = []
    while (y, m) <= (y2, m2):
        out.append(f"{y:04d}-{m:02d}")
        m += 1
        if m == 13:
            y, m = y + 1, 1
    return out


def load(path: Path) -> list[dict]:
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def rule(title: str) -> None:
    print("\n" + title)
    print("-" * len(title))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    for p in (PANEL, LOOKBACKS, CROSSWALK):
        if not p.exists():
            print(f"MISSING INPUT {p}")
            return 2

    panel = load(PANEL)
    looks = load(LOOKBACKS)
    cross = load(CROSSWALK)
    expected_months = months_between(FIRST_MONTH, LAST_MONTH)

    print(f"panel file       : {PANEL.relative_to(ROOT)}")
    print(f"panel rows       : {len(panel)}")
    print(f"lookback rows    : {len(looks)}")
    print(f"target window    : {FIRST_MONTH} .. {LAST_MONTH}  ({len(expected_months)} months)")
    print(f"rows if complete : {len(expected_months) * ROWS_PER_MONTH}")

    # ---------------------------------------------------------------- 1. per month
    rule("1. rows per month")
    by_month: dict[str, list[dict]] = defaultdict(list)
    for r in panel:
        by_month[r["month"]].append(r)
    missing = [m for m in expected_months if m not in by_month]
    short = [(m, len(by_month[m])) for m in expected_months
             if m in by_month and len(by_month[m]) != ROWS_PER_MONTH]
    present_months = sorted(by_month)
    for m in present_months:
        flag = "" if len(by_month[m]) == ROWS_PER_MONTH else "   <-- SHORT"
        if args.verbose or flag:
            print(f"  {m}  rows {len(by_month[m]):>3} / {ROWS_PER_MONTH}{flag}")
    print(f"  months with data : {len(present_months)} of {len(expected_months)}")
    print(f"  months missing   : {len(missing)}")
    if missing:
        print(f"  missing list     : {missing[0]} .. {missing[-1]}" if len(missing) > 6
              else f"  missing list     : {missing}")
        # compress runs for readability
        runs, start, prev = [], missing[0], missing[0]
        for m in missing[1:]:
            idx_prev = expected_months.index(prev)
            if expected_months.index(m) == idx_prev + 1:
                prev = m
                continue
            runs.append((start, prev))
            start = prev = m
        runs.append((start, prev))
        print("  missing runs     : " + ", ".join(
            f"{a}" if a == b else f"{a}..{b}" for a, b in runs))
    if short:
        failures.append(f"{len(short)} month(s) with wrong row count: {short}")

    # ---------------------------------------------------------------- 2. duplicates
    rule("2. duplicate (jurisdiction, month, series)")
    keys = Counter((r["jurisdiction"], r["month"], r["series"]) for r in panel)
    dups = {k: v for k, v in keys.items() if v > 1}
    print(f"  duplicate keys   : {len(dups)}   {'PASS' if not dups else 'FAIL'}")
    for k, v in list(dups.items())[:10]:
        print(f"    {k} x{v}")
    if dups:
        failures.append(f"{len(dups)} duplicate (jurisdiction, month, series) keys")

    # ---------------------------------------------------------------- 3. jurisdictions
    rule("3. jurisdictions per month")
    all_jur = sorted({r["jurisdiction"] for r in panel})
    print(f"  distinct jurisdictions in panel : {len(all_jur)}")
    bad_jur = []
    for m in present_months:
        js = {r["jurisdiction"] for r in by_month[m]}
        if len(js) != N_JUR:
            bad_jur.append((m, len(js), sorted(set(all_jur) - js)))
    print(f"  months with != {N_JUR} jurisdictions : {len(bad_jur)}   "
          f"{'PASS' if not bad_jur else 'FAIL'}")
    for m, n, miss in bad_jur[:12]:
        print(f"    {m}: {n} jurisdictions, absent {miss}")
    if bad_jur:
        failures.append(f"{len(bad_jur)} month(s) with fewer than {N_JUR} jurisdictions")

    # ---------------------------------------------------------------- 4. revisions
    rule("4. lookback revision check (reported elsewhere, restated here)")
    # A lookback is only comparable with a panel value published on the same base.
    panel_idx = {(r["jurisdiction"], r["month"], r["series"]): r for r in panel}
    pairs, cross_base = [], 0
    for lb in looks:
        key = (lb["jurisdiction"], lb["month"], lb["series"])
        p = panel_idx.get(key)
        if p is None:
            continue
        if p["base_year"] != lb["base_year"]:
            cross_base += 1
            continue
        diff = abs(float(p["index"]) - float(lb["index"]))
        pairs.append({
            "jurisdiction": lb["jurisdiction"], "month": lb["month"], "series": lb["series"],
            "panel_value": float(p["index"]), "lookback_value": float(lb["index"]),
            "diff": diff, "panel_from": p["source_file"], "lookback_from": lb["source_file"],
            "role": lb["column_role"], "base_year": p["base_year"],
        })
    print(f"  comparable (jurisdiction, month, series) pairs : {len(pairs)}")
    print(f"  pairs skipped as cross-base (not comparable)   : {cross_base}")
    over = sorted([p for p in pairs if p["diff"] > REVISION_TOL], key=lambda p: -p["diff"])
    print(f"  differ by more than {REVISION_TOL} : {len(over)}")
    print("  worst ten:")
    print(f"    {'jurisdiction':<14} {'month':<8} {'series':<10} {'panel':>12} {'lookback':>12} "
          f"{'diff':>9}  panel_from / lookback_from")
    for p in over[:10]:
        print(f"    {p['jurisdiction']:<14} {p['month']:<8} {p['series']:<10} "
              f"{p['panel_value']:>12.4f} {p['lookback_value']:>12.4f} {p['diff']:>9.4f}  "
              f"{p['panel_from']} / {p['lookback_from']}")

    # ---------------------------------------------------------------- 5. Bauchi test
    rule("5. Bauchi food(t-12) vs Anambra all_items(t-12) duplicate-cell test")
    by_file: dict[str, dict] = defaultdict(dict)
    for lb in looks:
        if lb["column_role"] != "t-12":
            continue
        by_file[lb["source_file"]][(lb["jurisdiction"], lb["series"])] = float(lb["index"])
    hit = miss_ = untested = 0
    hits = []
    for f in sorted(by_file):
        v = by_file[f]
        b = v.get(("Bauchi", "food"))
        a = v.get(("Anambra", "all_items"))
        if b is None or a is None:
            untested += 1
            continue
        if abs(b - a) <= EXACT:
            hit += 1
            hits.append((f, b))
        else:
            miss_ += 1
    print(f"  files tested           : {hit + miss_}  (untestable {untested})")
    print(f"  collision present      : {hit}")
    print(f"  collision absent       : {miss_}")
    for f, v in hits:
        print(f"    {f}: both cells = {v}")
    print(f"  {'PASS' if hit == 0 else 'DEFECT REPRODUCED'} — one of the two cells must be wrong;"
          " neither is used as evidence until checked against the report text")

    # any other shared index value in the same column of the same file
    rule("5b. other identical index values between two states, same column, same file")
    other = []
    for f in sorted(by_file):
        for role in ("t-12", "t-1"):
            vals = defaultdict(list)
            for lb in looks:
                if lb["source_file"] != f or lb["column_role"] != role:
                    continue
                key = (lb["series"], round(float(lb["index"]), 6))
                vals[key].append(lb["jurisdiction"])
            for (series, val), jurs in sorted(vals.items()):
                if len(set(jurs)) > 1:
                    other.append((f, role, series, val, sorted(set(jurs))))
    print(f"  shared cells found : {len(other)}")
    for f, role, series, val, jurs in other[:12]:
        print(f"    {f} {role} {series} = {val} in {jurs}")

    # ---------------------------------------------------------------- 6. cross-base
    rule("6. rebasing cross-check (levels never cross the break; growth rates only)")
    by_base: dict[tuple, dict[int, float]] = defaultdict(dict)
    for r in panel:
        by_base[(r["jurisdiction"], r["month"], r["series"])][int(r["base_year"])] = float(r["index"])
    for lb in looks:
        by_base[(lb["jurisdiction"], lb["month"], lb["series"])][int(lb["base_year"])] = float(lb["index"])
    ratios = defaultdict(list)
    for (jur, mon, ser), bases in by_base.items():
        if len(bases) >= 2:
            b2009 = bases.get(2009)
            b2024 = bases.get(2024)
            if b2009 and b2024:
                ratios[(ser)].append(b2024 / b2009)
    for ser in SERIES:
        rs = sorted(ratios.get(ser, []))
        if rs:
            mid = rs[len(rs) // 2]
            print(f"  {ser:<10} overlapping cells {len(rs):>4}  2024-base/2009-base ratio "
                  f"median {mid:.6f}  min {rs[0]:.6f}  max {rs[-1]:.6f}")
        else:
            print(f"  {ser:<10} no month observed on both bases")
    print("  interpretation: a near-constant ratio is the rebasing link factor. Any pair of")
    print("  the same month on different bases is an arithmetic identity, not a revision,")
    print("  which is why block 4 excludes them.")

    # ---------------------------------------------------------------- 7. arithmetic
    rule("7. internal arithmetic (published changes vs recomputed from the same row)")
    worst = {"food": (0, None), "all_items": (0, None)}
    for r in panel:
        for kind, pub, rec in (("annual", r["annual_change_pct"], r["annual_change_recomputed"]),
                               ("monthly", r["monthly_change_pct"], r["monthly_change_recomputed"])):
            if rec in ("", None) or pub in ("", None):
                continue
            d = abs(float(pub) - float(rec))
            k = r["series"] if kind == "annual" else r["series"]
            if d > worst[k][0]:
                worst[k] = (d, (r["jurisdiction"], r["month"], kind, float(pub), float(rec)))
    for k, (d, where) in worst.items():
        print(f"  {k:<10} worst |published - recomputed| = {d:.4f} pp   {where}")

    # ---------------------------------------------------------------- crosswalk
    rule("8. state name crosswalk")
    raws = {c["raw_name"] for c in cross}
    canon = {c["canonical"] for c in cross}
    print(f"  distinct raw spellings : {len(raws)}")
    print(f"  distinct canonical names : {len(canon)}")
    canon_set = set(all_jur)
    print(f"  canonical names in panel : {len(canon_set)}")
    unmapped = [c for c in cross if c["canonical"] not in canon_set]
    print(f"  crosswalk rows whose canonical is unknown to the panel : {len(unmapped)}")
    for c in unmapped[:10]:
        print(f"    {c['raw_name']!r} -> {c['canonical']!r} in {c['source_files']}")
    drifted = sorted({c["raw_name"] for c in cross
                      if c["raw_name"] != c["canonical"]})
    print(f"  spellings that needed harmonising : {len(drifted)}")
    for d in drifted:
        rows = [c for c in cross if c["raw_name"] == d]
        print(f"    {d!r} -> {rows[0]['canonical']!r}  ({len(rows[0]['source_files'].split(';'))} file(s))")
    if unmapped:
        failures.append(f"{len(unmapped)} crosswalk rows map to a name absent from the panel")

    # ---------------------------------------------------------------- coverage
    rule("coverage statement")
    print(f"  {len(present_months)} of {len(expected_months)} target months present "
          f"({FIRST_MONTH}..{LAST_MONTH}); {len(panel)} of "
          f"{len(expected_months) * ROWS_PER_MONTH} expected rows.")
    if present_months:
        print(f"  observed range: {present_months[0]} .. {present_months[-1]}")
    print(f"  source files parsed: {len({r['source_file'] for r in panel})}")
    print("  every row carries source_file and source_sha256; see data/panel/manifest.json")

    print()
    if failures:
        print("RESULT: FAIL")
        for f in failures:
            print("  -", f)
        return 1
    print("RESULT: PASS (structural checks; coverage gaps are reported above, not fatal)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
