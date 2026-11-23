"""Extract Table 5 (Combined Urban And Rural State CPI) from NBS monthly publications.

Reads every source file recorded in data/panel/manifest.json and emits

  data/panel/state_food_cpi.csv   one row per (jurisdiction, month, series) for the
                                  FOCUS month of each publication (column t only)
  data/panel/lookbacks.csv        the t-1 and t-12 columns, kept only so qa_panel.py can
                                  compare them against the month they belong to and catch
                                  a restatement. These are cross-check data, not panel data.
  data/reference/state_crosswalk.csv   every raw spelling seen -> canonical name
  data/reference/base_year_evidence.csv  the base-period heading as printed, per file

Rules enforced here, because getting them wrong is silent:
  * the three dates come from the header row, never from the filename;
  * the base year comes from the "(Base Period: YYYY = 100)" heading, never from the file date;
  * a state row must have exactly ten numeric cells in the fixed order documented in the brief;
  * a table whose internal arithmetic does not hold is still written, but flagged.

Usage:  python scripts/extract_cpi.py
"""
from __future__ import annotations

import csv
import datetime as dt
import hashlib
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw" / "nbs"
UNZIP = RAW / "unzipped"
PANEL = ROOT / "data" / "panel"
REF = ROOT / "data" / "reference"
MANIFEST = PANEL / "manifest.json"

CANONICAL = [
    "Abia", "Adamawa", "Akwa Ibom", "Anambra", "Bauchi", "Bayelsa", "Benue", "Borno",
    "Cross River", "Delta", "Ebonyi", "Edo", "Ekiti", "Enugu", "FCT", "Gombe", "Imo",
    "Jigawa", "Kaduna", "Kano", "Katsina", "Kebbi", "Kogi", "Kwara", "Lagos", "Nasarawa",
    "Niger", "Ogun", "Ondo", "Osun", "Oyo", "Plateau", "Rivers", "Sokoto", "Taraba",
    "Yobe", "Zamfara",
]

# Column order is fixed and is asserted against the header dates, not trusted blindly.
COLS = [
    ("food", "t-12", 2), ("all_items", "t-12", 3),
    ("food", "t-1", 4), ("all_items", "t-1", 5),
    ("food", "t", 6), ("all_items", "t", 7),
    ("food", "annual", 8), ("all_items", "annual", 9),
    ("food", "monthly", 10), ("all_items", "monthly", 11),
]

# Arithmetic check tolerance, percentage points. Published changes are computed from
# rounded indices, so exact equality is not expected.
TOL_ANNUAL = 0.15
TOL_MONTHLY = 0.15


def norm_state(name: str) -> str:
    return re.sub(r"[^a-z]", "", name.lower())


STATE_LOOKUP: dict[str, str] = {norm_state(c): c for c in CANONICAL}
STATE_LOOKUP.update({
    "abuja": "FCT", "fctabuja": "FCT", "federalcapitalterritory": "FCT",
    "fct": "FCT", "nassarawa": "Nasarawa", "nasawara": "Nasarawa",
    "akwaibom": "Akwa Ibom", "crossriver": "Cross River", "crosriver": "Cross River",
})


# ----------------------------------------------------------------------------- readers
def read_grid_xlsx(path: Path, sheet: str) -> list[list]:
    import openpyxl
    wb = openpyxl.load_workbook(path, data_only=True)
    ws = wb[sheet]
    grid = []
    for row in ws.iter_rows(min_row=1, max_row=ws.max_row, max_col=max(ws.max_column, 12)):
        grid.append([c.value for c in row])
    return grid


def read_grid_xls(path: Path, sheet: str) -> list[list]:
    import xlrd
    book = xlrd.open_workbook(str(path))
    sh = book.sheet_by_name(sheet)
    grid = []
    for r in range(sh.nrows):
        row = []
        for c in range(sh.ncols):
            cell = sh.cell(r, c)
            if cell.ctype == xlrd.XL_CELL_DATE:
                row.append(xlrd.xldate.xldate_as_datetime(cell.value, book.datemode))
            elif cell.ctype == xlrd.XL_CELL_EMPTY or cell.ctype == xlrd.XL_CELL_BLANK:
                row.append(None)
            else:
                row.append(cell.value)
        grid.append(row)
    return grid


def sheet_names_xlsx(path: Path) -> list[str]:
    import openpyxl
    return openpyxl.load_workbook(path, read_only=True).sheetnames


def sheet_names_xls(path: Path) -> list[str]:
    import xlrd
    return xlrd.open_workbook(str(path)).sheet_names()


def cell(grid, r, c):
    if 0 <= r < len(grid) and 0 <= c < len(grid[r]):
        return grid[r][c]
    return None


def as_datetime(v):
    if isinstance(v, dt.datetime):
        return v
    if isinstance(v, dt.date):
        return dt.datetime(v.year, v.month, v.day)
    return None


def as_number(v):
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    return None


def yyyymm(d: dt.datetime) -> str:
    return f"{d.year:04d}-{d.month:02d}"


# ----------------------------------------------------------------------------- parsing
BASE_RE = re.compile(r"base\s*period\s*:?\s*([A-Za-z]*)\s*(\d{4})\s*=\s*100", re.I)


def parse_table5(grid, *, source_file: str, container: str, kind: str,
                 sha: str) -> dict:
    """Locate Table 5 inside a grid and return its ten-number matrix plus provenance."""
    # 1. base-period headings anywhere in the sheet (defect 4: leftovers can coexist)
    base_hits = []
    for r, row in enumerate(grid):
        for c, v in enumerate(row):
            if isinstance(v, str) and BASE_RE.search(v):
                m = BASE_RE.search(v)
                base_hits.append({"row": r + 1, "col": c + 1, "text": v.strip(),
                                  "base_year": int(m.group(2))})

    # 2. the date row: a datetime in column C with "Annual Change" in column I
    date_row = None
    for r in range(len(grid)):
        d = as_datetime(cell(grid, r, 2))
        lab = cell(grid, r, 8)
        if d and isinstance(lab, str) and "annual" in lab.lower():
            date_row = r
            break
    if date_row is None:
        return {"ok": False, "reason": "no header row with a date in col C and 'Annual Change' in col I"}

    d_t12 = as_datetime(cell(grid, date_row, 2))
    d_t1 = as_datetime(cell(grid, date_row, 4))
    d_t = as_datetime(cell(grid, date_row, 6))
    for nm, d in (("t-12", d_t12), ("t-1", d_t1), ("t", d_t)):
        if d is None:
            return {"ok": False, "reason": f"header date missing for column {nm}"}

    # column labels on the row below, for the assertion that we read the right pairs
    label_row = [str(cell(grid, date_row + 1, c) or "").strip().lower() for c in range(12)]

    # 3. base period: the heading nearest above the date row, else any heading
    above = [h for h in base_hits if h["row"] - 1 < date_row]
    base = above[-1] if above else (base_hits[0] if base_hits else None)
    if base is None:
        return {"ok": False, "reason": "no '(Base Period: YYYY = 100)' heading found"}

    # 4. title
    title = ""
    for r in range(0, min(date_row, 12)):
        for c in (0, 1):
            v = cell(grid, r, c)
            if isinstance(v, str) and "table" in v.lower() and "5" in v:
                title = v.strip()
                break
        if title:
            break

    # 5. state rows: skip whatever header continuation rows follow the label row, then
    #    collect until a 'Note' or the first non-state row. Nov/Dec 2024 wrap the header
    #    over two rows ('All' / 'Items'), so the offset is found, not assumed.
    rows = []
    problems = []
    r = date_row + 1
    while r < len(grid) and all(as_number(cell(grid, r, c)) is None for c in range(2, 12)):
        r += 1
    header_rows = r - date_row - 1
    while r < len(grid):
        name = cell(grid, r, 1)
        if not isinstance(name, str):
            break
        s = name.strip()
        if not s or s.lower().startswith("note"):
            break
        vals = [as_number(cell(grid, r, c)) for c in range(2, 12)]
        if sum(v is None for v in vals) > 0:
            problems.append(f"row {r+1} ({s!r}) has {sum(v is None for v in vals)} non-numeric cells")
            rows.append({"row": r + 1, "raw_name": s, "values": vals})
        else:
            rows.append({"row": r + 1, "raw_name": s, "values": vals})
        r += 1

    if not rows:
        return {"ok": False, "reason": "no state rows found below the header"}

    return {
        "ok": True,
        "title": title,
        "date_row": date_row + 1,
        "dates": {"t-12": yyyymm(d_t12), "t-1": yyyymm(d_t1), "t": yyyymm(d_t)},
        "dates_raw": {"t-12": d_t12.isoformat(), "t-1": d_t1.isoformat(), "t": d_t.isoformat()},
        "base_year": base["base_year"],
        "base_heading": base["text"],
        "base_headings_in_sheet": base_hits,
        "header_rows": header_rows,
        "column_labels": label_row[2:12],
        "rows": rows,
        "problems": problems,
        "source_file": source_file,
        "container": container,
        "source_kind": kind,
        "sha256": sha,
    }


NUM_RE = re.compile(r"^-?\d+(\.\d+)?$")
DATE_TOKEN_RE = re.compile(r"^([A-Z][a-z]{2})-(\d{2})$")
MONTH_NUM = {m[:3].lower(): i for i, m in enumerate(
    ["January", "February", "March", "April", "May", "June", "July",
     "August", "September", "October", "November", "December"], start=1)}


def _cluster(values, tol):
    """Group sorted scalars into bands no wider than tol. Returns list of (centre, members)."""
    bands = []
    for v in sorted(values):
        if bands and v - bands[-1][-1] <= tol:
            bands[-1].append(v)
        else:
            bands.append([v])
    return [(sum(b) / len(b), b) for b in bands]


def _y_bands(words, tol=4.0):
    rows = []
    for w in sorted(words, key=lambda w: (round(w[1], 1), w[0])):
        if rows and abs(w[1] - rows[-1][-1][1]) <= tol:
            rows[-1].append(w)
        else:
            rows.append([w])
    return rows


KIND_TOKENS = {"mom": "MoM", "m/m": "MoM", "m-o-m": "MoM", "month-on-month": "MoM",
               "yoy": "YoY", "y/y": "YoY", "y-o-y": "YoY", "year-on-year": "YoY"}
SERIES_TOKENS = {"food": "Food", "all": "All Items", "items": "All Items"}


def _change_roles(centres, words, data_top):
    """(kind, series) for each change column, from label x-positions.

    The label block is not one row: some months print `State Food All Food All Food All`
    above `MOM YOY MOM YOY`, put `Items` on a third line, or print MoM/YoY on the same line
    as the dates. Matching by x-position above the first data row tolerates all of that;
    matching by ordinal position or by a fixed label row does not.
    """
    hdr = [w for w in words if w[1] <= data_top]
    kinds = [w for w in hdr
             if KIND_TOKENS.get(w[4].strip().strip("()%").lower())]
    series = [w for w in hdr if SERIES_TOKENS.get(w[4].strip().lower())]
    if not kinds or not series:
        return None
    out = {}
    for cx in centres:
        k = min(kinds, key=lambda w: abs(w[0] - cx))
        s = min(series, key=lambda w: abs(w[0] - cx))
        role = (KIND_TOKENS[k[4].strip().strip("()%").lower()],
                SERIES_TOKENS[s[4].strip().lower()])
        if role in out.values():
            return None                      # two columns claim the same role
        out[cx] = role
    return out if len(set(out.values())) == len(centres) else None


def infer_base(month: str, median_index: float) -> tuple[int, str]:
    """Base year when a file carries no '(Base Period: YYYY = 100)' heading.

    Two rules must agree, and the evidence string records both: the 2025 rebasing break
    (2024 = 100 from January 2025) and the level itself (the 2024-base series runs 100-130,
    the 2009-base series 300-1,100). Agreement is what makes the inference reportable.
    """
    by_break = 2009 if month < "2025-01" else 2024
    by_level = 2009 if median_index > 200 else 2024
    agree = by_break == by_level
    return by_break, (f"heading absent in file; break rule {by_break}, level rule {by_level} "
                      f"(median index {median_index:.1f}) -> {'agree' if agree else 'DISAGREE'}")


def _date_triple(words):
    """[t-12, t-1, t] read from the three date labels on a table page, else None."""
    dtoks = [w for w in words if DATE_TOKEN_RE.match(w[4].strip())]
    if len(dtoks) != 3:
        return None
    dtoks.sort(key=lambda w: w[0])
    out = []
    for w in dtoks:
        mm = DATE_TOKEN_RE.match(w[4].strip())
        mon = MONTH_NUM.get(mm.group(1).lower())
        if not mon:
            return None
        out.append(f"20{mm.group(2)}-{mon:02d}")
    for cand in out:
        if out[0] == shift(cand, -12) and out[1] == shift(cand, -1) and out[2] == cand:
            return out
    return None


def parse_pdf_table(path: Path, container: str) -> dict:
    """Parse the State CPI table out of an NBS CPI PDF.

    Four layouts exist across 2020-2026 and all four are handled here, because guessing one
    and failing the rest would have cost 43 months:

      * six numeric columns (2020-01 .. 2021-03): index levels only, no change block;
      * ten columns with the two change blocks labelled over two or three text rows;
      * a table whose only heading is on another page - the base period is searched for
        across the whole document, not just this page;
      * a table with no date labels at all: that month is refused here and recovered from a
        neighbouring file's lookback column, because a date taken from a filename is exactly
        what the project forbids.

    The PDF prints MoM before YoY; the workbook prints annual before monthly. Column roles
    are therefore read from the header geometry here, and the workbook order is fixed in
    parse_table5. The two orders are never assumed to match.
    """
    import pymupdf

    doc = pymupdf.open(path)
    total_text = 0
    cands = []
    for i, page in enumerate(doc):
        text = page.get_text()
        total_text += len(text)
        if "Kebbi" not in text or "Borno" not in text:
            continue
        words_pg = page.get_text("words")
        if sum(1 for w in words_pg if NUM_RE.match(w[4].strip())) < 30:
            continue
        trip = _date_triple(words_pg)
        if trip:
            cands.append((trip[2], i, trip))
    if not cands:
        if total_text < 2000:
            return {"ok": False, "reason": f"image-only: {doc.page_count} pages, "
                                          f"{total_text} characters of text, no text layer"}
        return {"ok": False, "reason": "no page carries a state table with a readable "
                                       "t-12/t-1/t triple - recoverable from a neighbouring "
                                       "file's lookback column"}
    # a document can carry more than one such table (leftover months occur, as they do for
    # base years); the latest month is the publication's own
    cands.sort()
    _, anchor, dates = cands[-1]

    # base period: anywhere in the document (defect 4 - leftovers can coexist, so keep all)
    base_hits = []
    for i, pg in enumerate(doc):
        for line in pg.get_text().splitlines():
            m = BASE_RE.search(line)
            if m:
                base_hits.append({"row": None, "col": None, "text": m.group(0).strip(),
                                  "base_year": int(m.group(2)), "page": i + 1})
    base_note = ""
    if base_hits:
        base = base_hits[0]
        base_year, base_heading = base["base_year"], base["text"]
    else:
        base_year, base_heading = None, "(no base-period heading in this file)"
        base_note = "heading absent"

    page = doc[anchor]
    words = page.get_text("words")
    dtoks = sorted([w for w in words if DATE_TOKEN_RE.match(w[4].strip())],
                   key=lambda w: w[0])
    date_y = max(w[3] for w in dtoks)
    num_words = [w for w in words if NUM_RE.match(w[4].strip()) and w[1] > date_y]
    if not num_words:
        return {"ok": False, "reason": "no numbers below the date labels"}
    # a real column is printed once per state row; a stray figure in the right margin is not.
    # Counting members per cluster is what separates the two - assuming ten columns did not.
    cols = [(c, len(m)) for c, m in _cluster([w[0] for w in num_words], 14.0)]
    cols = [(c, n) for c, n in cols if n >= 5]
    centres = [c for c, _ in cols]
    if len(centres) not in (6, 10):
        return {"ok": False, "reason": f"expected 6 or 10 numeric columns, found "
                                      f"{len(centres)} at {[(round(c), n) for c, n in cols]}"}

    bands = _y_bands(num_words)
    data_top = bands[0][0][1] if bands else date_y
    roles = {cx: "index" for cx in centres[:6]}
    if len(centres) == 10:
        change = _change_roles(centres[6:], words, data_top)
        if change is None:
            return {"ok": False, "reason": "the four change columns could not each be "
                                           "labelled MoM/YoY x Food/All Items from the header"}
        roles.update(change)

    # rows: from the anchor page forward until all 37 jurisdictions are collected
    rows, problems, seen = [], [], set()
    for pi in range(anchor, min(anchor + 6, doc.page_count)):
        for band in _y_bands(doc[pi].get_text("words")):
            # the name column is everything left of the first number column; a fixed x
            # cutoff clips short right-aligned names (Abia, Edo, Imo, Oyo, Kogi)
            names = [w for w in band if w[0] < centres[0] - 4
                     and re.match(r"^[A-Za-z][A-Za-z .\-']*$", w[4].strip())]
            nums = [w for w in band if NUM_RE.match(w[4].strip())
                    and w[0] > centres[0] - 10]
            if not names or len(nums) < len(centres):
                continue
            raw = " ".join(w[4].strip() for w in sorted(names, key=lambda w: w[0]))
            canon = STATE_LOOKUP.get(norm_state(raw))
            if canon is None or canon in seen:
                continue
            got = {}
            for w in nums:
                k = min(centres, key=lambda c: abs(c - w[0]))
                got.setdefault(k, float(w[4]))
            if len(got) != len(centres):
                problems.append(f"page {pi + 1} {raw}: resolved {len(got)} of "
                                f"{len(centres)} columns")
                continue
            idx = [got[cx] for cx in sorted(roles, key=lambda c: (roles[c] != "index", c))
                   if roles[cx] == "index"]
            if len(idx) != 6:
                problems.append(f"page {pi + 1} {raw}: {len(idx)} index columns")
                continue
            food12, all12, food1, all1, food, allv = idx
            slot = {r: got[cx] for cx, r in roles.items() if r != "index"}
            v = [food12, all12, food1, all1, food, allv,
                 slot.get(("YoY", "Food")), slot.get(("YoY", "All Items")),
                 slot.get(("MoM", "Food")), slot.get(("MoM", "All Items"))]
            if len(centres) == 10 and any(x is None for x in v[6:]):
                problems.append(f"page {pi + 1} {raw}: missing a change cell")
                continue
            seen.add(canon)
            rows.append({"row": None, "raw_name": raw, "values": v})
        if len(seen) >= len(CANONICAL):
            break

    if not rows:
        return {"ok": False, "reason": f"no state rows resolved ({problems[:3]})"}

    if base_year is None:
        med = sorted(v[4] for v in (r["values"] for r in rows))[len(rows) // 2]
        base_year, note = infer_base(dates[2], med)
        base_heading = f"(none in file; inferred) {note}"
        if "DISAGREE" in note:
            return {"ok": False, "reason": f"base year unreadable and inference "
                                          f"inconsistent: {note}"}

    labels = []
    for cx, role in sorted(roles.items()):
        labels.append("index" if role == "index" else f"{role[0]} {role[1]}")
    return {
        "ok": True,
        "title": "State CPI table (from PDF)",
        "date_row": None,
        "dates": {"t-12": dates[0], "t-1": dates[1], "t": dates[2]},
        "dates_raw": {"t-12": dates[0], "t-1": dates[1], "t": dates[2]},
        "base_year": base_year,
        "base_heading": base_heading,
        "base_headings_in_sheet": base_hits or [{"row": None, "text": base_heading,
                                                 "base_year": base_year}],
        "column_labels": labels,
        "column_roles": {round(k): (v if isinstance(v, str) else "/".join(v))
                         for k, v in roles.items()},
        "change_columns_present": len(centres) == 10,
        "rows": rows,
        "problems": problems,
        "source_file": path.name,
        "container": container,
        "source_kind": "pdf",
        "sha256": sha256_file(path),
        "header_rows": 1,
        "sheet": f"page {anchor + 1}",
        "base_note": base_note,
    }

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def sheets_for(path: Path) -> list[str]:
    if path.suffix.lower() == ".xls":
        return sheet_names_xls(path)
    return sheet_names_xlsx(path)


def parse_workbook(path: Path, container: str) -> dict:
    kind = "xls" if path.suffix.lower() == ".xls" else "xlsx"
    names = sheets_for(path)
    cands = [s for s in names if re.sub(r"[^a-z0-9]", "", s.lower()) == "table5"]
    if not cands:
        return {"ok": False, "reason": f"no Table-5 sheet; sheets={names}"}
    sha = sha256_file(path)
    results = []
    for s in cands:
        grid = read_grid_xls(path, s) if kind == "xls" else read_grid_xlsx(path, s)
        res = parse_table5(grid, source_file=path.name, container=container, kind=kind, sha=sha)
        res["sheet"] = s
        results.append(res)
    good = [r for r in results if r.get("ok")]
    if not good:
        return results[0]
    # if a workbook ever holds two Table-5 sheets, the newest focus month wins and we say so
    good.sort(key=lambda r: r["dates"]["t"], reverse=True)
    out = good[0]
    out["candidate_sheets"] = [r["sheet"] for r in results]
    out["ambiguous_sheets"] = len(good) > 1
    return out


# ----------------------------------------------------------------------------- driving
def discover_sources() -> list[tuple[Path, str]]:
    """(path, container) pairs: container is the raw download the bytes came from."""
    out: list[tuple[Path, str]] = []
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.exists() else {"files": {}}
    for name in sorted(manifest.get("files", {})):
        p = RAW / name
        if p.exists() and p.suffix.lower() in (".xlsx", ".xls", ".pdf"):
            out.append((p, name))
    if UNZIP.exists():
        for d in sorted(UNZIP.iterdir()):
            if not d.is_dir():
                continue
            container = f"{d.name}.zip"
            for f in sorted(d.iterdir()):
                if f.suffix.lower() in (".xlsx", ".xls"):
                    out.append((f, container))
    return out


def derive_changes(index_t: float, index_t12: float, index_t1: float):
    ann = (index_t / index_t12 - 1.0) * 100 if index_t12 else None
    mon = (index_t / index_t1 - 1.0) * 100 if index_t1 else None
    return ann, mon

# ----------------------------------------------------------------------------- panel build
# Rules the assembly stage enforces. Each one exists because violating it is silent.
KIND_RANK = {"xlsx": 3, "xls": 2, "pdf": 1}   # a machine-readable table beats a typeset one
AGREE_TOL = 0.05      # half the PDF's 0.1 printing step; exact equality would be too strict
MIN_PAIRS = 10        # a comparison on fewer cells is reported but never decisive
AGREE_FLOOR = 0.90    # the gate the brief sets
FIRST_MONTH, LAST_MONTH = "2020-01", "2026-10"


def shift(ym: str, n: int) -> str:
    y, m = int(ym[:4]), int(ym[5:])
    m += n
    while m <= 0:
        m += 12
        y -= 1
    while m > 12:
        m -= 12
        y += 1
    return f"{y:04d}-{m:02d}"


def file_records(res: dict) -> dict:
    """Normalise one parsed publication to (jurisdiction, series) -> column role -> value."""
    values, raws, rows, repeated = {}, {}, {}, []
    for row in res["rows"]:
        raw = row["raw_name"]
        canon = STATE_LOOKUP.get(norm_state(raw)) or raw
        if canon in raws:
            repeated.append(raw)
            continue
        v = row["values"]
        if any(x is None for x in v[:6]):
            continue                 # an index cell is missing: this row cannot be used
        food12, all12, food1, all1, food, allv, fa, aa, fm, am = v
        values[(canon, "food")] = {"t-12": food12, "t-1": food1, "t": food,
                                   "annual": fa, "monthly": fm}
        values[(canon, "all_items")] = {"t-12": all12, "t-1": all1, "t": allv,
                                        "annual": aa, "monthly": am}
        raws[canon] = raw
        rows[canon] = row["row"]
    return {"values": values, "raw_names": raws, "row_numbers": rows, "repeated": repeated}


def pick(files: list[dict], month: str) -> dict:
    """One publication per month: workbook first, then the canonically named file, then sha."""
    canonical = f"CPI_{month}_Report.pdf"
    return sorted(files, key=lambda e: (-KIND_RANK.get(e["kind"], 0),
                                        0 if e["name"] == canonical else 1,
                                        e["sha"], e["file"]))[0]


def build_candidates(by_month: dict[str, list[dict]]) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for m, files in by_month.items():
        ent = pick(files, m)
        vals: dict[tuple, dict] = {}
        printed = True
        for k, v in ent["values"].items():
            ann, mon = v["annual"], v["monthly"]
            if ann is None or mon is None:
                # the 2020-2021 tables print no change columns; the row still carries all
                # three index levels, so the change is computable from the row itself
                printed = False
                ann, mon = derive_changes(v["t"], v["t-12"], v["t-1"])
            vals[k] = {"index": v["t"], "annual": ann, "monthly": mon}
        out[m] = {
            "month": m, "file": ent["file"], "name": ent["name"], "kind": ent["kind"],
            "base": ent["base"], "sha": ent["sha"], "title": ent["title"],
            "published_in": ent["dates"]["t"],
            "changes_printed": printed,
            "focus": {k: v["index"] for k, v in vals.items()},
            "annual": {k: v["annual"] for k, v in vals.items()},
            "monthly": {k: v["monthly"] for k, v in vals.items()},
            "lag1": {k: v["t-1"] for k, v in ent["values"].items()},
            "lag12": {k: v["t-12"] for k, v in ent["values"].items()},
            "raw_names": ent["raw_names"], "row_numbers": ent["row_numbers"],
            "superseded": [e["file"] for e in files if e["file"] != ent["file"]],
        }
    return out


def compare(a: dict, b: dict) -> tuple[int, list[tuple]]:
    """Cells compared, and the ones further apart than AGREE_TOL, worst first."""
    common = sorted(set(a) & set(b))
    bad = [(k, a[k], b[k], abs(a[k] - b[k])) for k in common
           if a[k] is not None and b[k] is not None and abs(a[k] - b[k]) > AGREE_TOL]
    bad.sort(key=lambda t: -t[3])
    return len(common), bad


def chain_rows(cand: dict[str, dict]) -> list[dict]:
    """file(t).previous_month against the value carried for month t-1, for every pair."""
    rows = []
    months = sorted(cand)
    for a, b in zip(months, months[1:]):
        if shift(a, 1) != b:
            continue                      # a gap, not a consecutive pair
        if cand[a]["base"] != cand[b]["base"]:
            rows.append({"pair": f"{a}->{b}", "status": "skipped_cross_base",
                         "pairs": 0, "agree": 0, "bad": [],
                         "note": f"base {cand[a]['base']} -> {cand[b]['base']}"})
            continue
        n, bad = compare(cand[b]["lag1"], cand[a]["focus"])
        rows.append({"pair": f"{a}->{b}", "status": "tested", "pairs": n,
                     "agree": n - len(bad), "bad": bad, "reference": a, "from_file": b})
    return rows


def annual_rows(cand: dict[str, dict]) -> list[dict]:
    """file(t).year_ago against the value published for month t-12, skipping cross-base pairs."""
    rows = []
    for t in sorted(cand):
        y = shift(t, -12)
        if y not in cand:
            rows.append({"month": t, "status": "skipped_absent", "pairs": 0, "agree": 0,
                         "bad": [], "year_ago": y})
            continue
        if cand[y]["base"] != cand[t]["base"]:
            rows.append({"month": t, "status": "skipped_cross_base", "pairs": 0, "agree": 0,
                         "bad": [], "year_ago": y,
                         "note": f"base {cand[y]['base']} -> {cand[t]['base']}"})
            continue
        n, bad = compare(cand[t]["lag12"], cand[y]["focus"])
        rows.append({"month": t, "status": "tested", "pairs": n, "agree": n - len(bad),
                     "bad": bad, "year_ago": y, "from_file": t})
    return rows


def gate(rows: list[dict]) -> tuple[set[str], list[dict]]:
    """Months whose own published values a succeeding file contradicts, and the verdict list."""
    quarantined, verdicts = set(), []
    for r in rows:
        if r["status"] != "tested" or r["pairs"] < MIN_PAIRS:
            verdicts.append({**r, "verdict": r["status"]})
            if r["status"] == "tested":
                verdicts[-1]["verdict"] = "too_few_pairs"
            continue
        share = r["agree"] / r["pairs"]
        ok = share >= AGREE_FLOOR
        verdicts.append({**r, "share": round(share, 4), "verdict": "pass" if ok else "FAIL"})
        if not ok:
            quarantined.add(r["reference"])
    return quarantined, verdicts


def recover_months(cand: dict[str, dict], ents: dict[str, dict]) -> dict[str, dict]:
    """Months with no publication recovered from a neighbour's lookback column.

    Two independent columns can print the same month: the next publication's previous-month
    column, and a publication twelve months later. When both exist they must agree, or the
    month is not recovered at all.
    """
    present = set(cand)
    wanted = []
    y, m = int(FIRST_MONTH[:4]), int(FIRST_MONTH[5:])
    y2, m2 = int(LAST_MONTH[:4]), int(LAST_MONTH[5:])
    while (y, m) <= (y2, m2):
        ym = f"{y:04d}-{m:02d}"
        if ym not in present:
            wanted.append(ym)
        m += 1
        if m == 13:
            y, m = y + 1, 1

    out: dict[str, dict] = {}
    for target in wanted:
        via_prev = [e for e in ents.values() if e["dates"]["t-1"] == target]
        via_year = [e for e in ents.values() if e["dates"]["t-12"] == target]
        if not via_prev and not via_year:
            continue
        sources = {}
        for label, pool, role in (("previous_month_column", via_prev, "t-1"),
                                  ("year_ago_column", via_year, "t-12")):
            if not pool:
                continue
            ent = sorted(pool, key=lambda e: (-KIND_RANK.get(e["kind"], 0), e["file"]))[0]
            sources[label] = {
                "file": ent["file"], "kind": ent["kind"], "base": ent["base"],
                "published_in": ent["dates"]["t"], "role": role,
                "values": {k: v[role] for k, v in ent["values"].items()},
            }
        bases = {s["base"] for s in sources.values()}
        if len(bases) != 1:
            out[target] = {"month": target, "status": "refused_base_disagreement",
                           "sources": sources, "agreement": None}
            continue
        agreement = None
        keys = list(sources)
        if len(keys) == 2:
            n, bad = compare(sources[keys[0]]["values"], sources[keys[1]]["values"])
            agreement = {"pairs": n, "disagree": len(bad), "worst": bad[:3]}
        head = sources[keys[0] if "previous_month_column" in sources
                       else "year_ago_column"] if keys else None
        out[target] = {
            "month": target, "status": "recovered",
            "sources": sources, "agreement": agreement,
            "base": bases.pop(), "values": head["values"],
            "file": head["file"], "published_in": head["published_in"],
            "kind": head["kind"],
        }
    return out


def main() -> int:
    PANEL.mkdir(parents=True, exist_ok=True)
    REF.mkdir(parents=True, exist_ok=True)

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    files_meta = manifest.get("files", {})

    sources = discover_sources()
    print(f"sources on disk: {len(sources)}")

    ents: dict[str, dict] = {}
    status: dict[str, dict] = {}
    warnings: list[str] = []
    base_rows: list[dict] = []
    crosswalk: dict[str, dict] = {}

    for path, container in sources:
        res = parse_pdf_table(path, container) if path.suffix.lower() == ".pdf" \
            else parse_workbook(path, container)
        key = path.name if container == path.name else f"{container}!{path.name}"
        if not res.get("ok"):
            print(f"  FAIL {key}: {res.get('reason')}")
            status[key] = {"parse_status": f"failed: {res.get('reason')}"}
            continue

        months = res["dates"]
        print(f"  ok   {key}: t={months['t']} t-1={months['t-1']} t-12={months['t-12']} "
              f"base={res['base_year']} rows={len(res['rows'])}")
        if res.get("ambiguous_sheets"):
            warnings.append(f"{key}: several Table-5 sheets {res['candidate_sheets']}, "
                            f"used {res['sheet']!r}")
        if len(res["base_headings_in_sheet"]) > 1:
            warnings.append(f"{key}: {len(res['base_headings_in_sheet'])} base-period headings "
                            + str([h["text"].strip() for h in res["base_headings_in_sheet"]]))
        warnings.extend(f"{key}: {p}" for p in res["problems"])

        rec = file_records(res)
        if rec["repeated"]:
            warnings.append(f"{key}: repeated state rows {rec['repeated']} - first kept")
        ents[key] = {
            "file": key, "name": path.name, "kind": res["source_kind"],
            "base": res["base_year"], "sha": res["sha256"], "container": container,
            "dates": months, "title": res.get("title", ""), "sheet": res["sheet"],
            "values": rec["values"], "raw_names": rec["raw_names"],
            "row_numbers": rec["row_numbers"], "states": len(res["rows"]),
        }
        for canon, raw in rec["raw_names"].items():
            if canon == raw:
                continue
            cw = crosswalk.setdefault(raw, {"canonical": canon, "source_files": set()})
            cw["source_files"].add(key)
        for canon in rec["raw_names"]:
            if STATE_LOOKUP.get(norm_state(canon)) is None:
                warnings.append(f"{key}: unmapped state spelling {canon!r} - kept verbatim")

        base_rows.append({
            "source_file": key, "sheet": res["sheet"], "base_year": res["base_year"],
            "base_heading": res["base_heading"], "title": res["title"],
            "date_t12": months["t-12"], "date_t1": months["t-1"], "date_t": months["t"],
            "date_t12_raw": res["dates_raw"]["t-12"], "date_t1_raw": res["dates_raw"]["t-1"],
            "date_t_raw": res["dates_raw"]["t"],
            "headings_in_sheet": len(res["base_headings_in_sheet"]),
            "states": len(res["rows"]),
        })
        status[key] = {"parse_status": "ok", "focus_month": months["t"],
                       "base_year": res["base_year"], "states_parsed": len(res["rows"]),
                       "source_kind": res["source_kind"]}

    # ------------------------------------------------------------------ one file per month
    by_month: dict[str, list[dict]] = defaultdict(list)
    for ent in ents.values():
        by_month[ent["dates"]["t"]].append(ent)
    cand = build_candidates(by_month)
    superseded = {m: c["superseded"] for m, c in cand.items() if c["superseded"]}
    print(f"\nparsed publications : {len(ents)}")
    print(f"distinct focus months: {len(cand)}  ({min(cand)}..{max(cand)})" if cand else "none")
    if superseded:
        print(f"months with more than one file (one chosen, rest recorded): {len(superseded)}")
        for m, fl in sorted(superseded.items())[:6]:
            print(f"  {m}: chose {cand[m]['name']}; also {fl}")

    # ------------------------------------------------------------------ chain gate
    chain = chain_rows(cand)
    verdicts = gate(chain)[1]
    quarantined = gate(chain)[0]
    tested = [v for v in verdicts if v["verdict"] in ("pass", "FAIL")]
    skipped = [v for v in verdicts if v["verdict"] not in ("pass", "FAIL")]
    print(f"\nchain gate: {len(tested)} pairs tested, {len(skipped)} skipped "
          f"({sum(1 for v in skipped if v['verdict'] == 'too_few_pairs')} on too few cells, "
          f"{sum(1 for v in skipped if v['verdict'] == 'skipped_cross_base')} cross-base)")
    for v in tested:
        line = f"  {v['pair']}  {v['agree']:>3}/{v['pairs']:<3} {v['share'] * 100:5.1f}%"
        if v["verdict"] == "FAIL":
            line += "  FAIL -> quarantine " + v["reference"]
            for (jur, ser), av, bv, d in v["bad"][:4]:
                line += f"\n      {jur} {ser}: published {av:.4f} vs succeeding file {bv:.4f} (d={d:.4f})"
        print(line)

    # ------------------------------------------------------------------ recovery
    recovered = recover_months(cand, ents)
    for m, r in sorted(recovered.items()):
        if r["status"] == "recovered":
            ag = r["agreement"]
            extra = (f", two sources agree {ag['pairs'] - ag['disagree']}/{ag['pairs']}"
                     if ag else ", single source")
            print(f"\nrecovered {m} from {r['file']} ({r['kind']}, base {r['base']}){extra}")
            for k, s in r["sources"].items():
                print(f"  via {k}: {s['file']} (published {s['published_in']})")
            cand[m] = {
                "month": m, "file": r["file"], "name": Path(r["file"]).name,
                "kind": r["kind"], "base": r["base"], "sha": "", "title": "",
                "published_in": r["published_in"],
                "focus": r["values"], "annual": {}, "monthly": {},
                "lag1": {}, "lag12": {}, "raw_names": {}, "row_numbers": {},
                "superseded": [], "recovered": True,
            }
        else:
            print(f"\nNOT recovered {m}: {r['status']}")

    # ------------------------------------------------------------------ assemble panel
    panel_rows, quarantined_rows, lookback_rows = [], [], []
    for m in sorted(cand):
        c = cand[m]
        is_recovered = c.get("recovered", False)
        bad_here = m in quarantined
        for (jur, ser), idx in sorted(c["focus"].items()):
            ann = c["annual"].get((jur, ser))
            mon = c["monthly"].get((jur, ser))
            row = {
                "jurisdiction": jur, "month": m, "series": ser, "index": round(idx, 6),
                "annual_change_pct": "" if ann is None else round(ann, 4),
                "monthly_change_pct": "" if mon is None else round(mon, 4),
                "base_year": c["base"], "source_file": c["name"],
                "published_in": c.get("published_in") or c["month"],
                "raw_name": c["raw_names"].get(jur, jur), "source_kind": c["kind"],
                "source_sha256": c["sha"], "container": c["file"],
                "header_row": "", "state_row": c["row_numbers"].get(jur, ""),
                "value_source": ("previous_month_column" if is_recovered
                                 else f"focus_column_{c['kind']}"
                                 + ("" if c.get("changes_printed", True)
                                    else "_changes_recomputed_from_row")),
            }
            if is_recovered:
                row.update({"annual_change_pct": "", "monthly_change_pct": "",
                            "annual_change_recomputed": "", "monthly_change_recomputed": ""})
            if bad_here:
                row["quarantine_reason"] = (
                    "a succeeding publication's previous-month column disagrees with this "
                    "month's own published values")
                quarantined_rows.append(row)
            else:
                panel_rows.append(row)
    # recompute changes from the panel itself, for the arithmetic check in qa_panel.py
    idx_of = {(r["jurisdiction"], r["month"], r["series"]): float(r["index"])
              for r in panel_rows}
    for r in panel_rows:
        k = (r["jurisdiction"], r["month"], r["series"])
        a, b = idx_of.get((k[0], shift(r["month"], -1), k[2])), \
            idx_of.get((k[0], shift(r["month"], -12), k[2]))
        r["monthly_change_recomputed"] = ("" if b is None or r["monthly_change_pct"] == ""
                                          else round((float(r["index"]) / b - 1) * 100, 4))
        r["annual_change_recomputed"] = ("" if a is None or r["annual_change_pct"] == ""
                                         else round((float(r["index"]) / a - 1) * 100, 4))

    # lookbacks: every column of every file, quarantined months included - this is the
    # evidence base for the chain test, not panel data
    for ent in ents.values():
        for (jur, ser), v in ent["values"].items():
            for role in ("t-12", "t-1"):
                lookback_rows.append({
                    "jurisdiction": jur, "month": ent["dates"][role], "series": ser,
                    "index": round(v[role], 6), "column_role": role,
                    "base_year": ent["base"], "source_file": ent["name"],
                    "published_in": ent["dates"]["t"], "container": ent["file"],
                    "raw_name": ent["raw_names"].get(jur, jur),
                })

    # ------------------------------------------------------------------ write
    panel_cols = ["jurisdiction", "month", "series", "index", "annual_change_pct",
                  "monthly_change_pct", "base_year", "source_file", "published_in",
                  "raw_name", "source_kind", "source_sha256", "container", "header_row",
                  "state_row", "value_source", "annual_change_recomputed",
                  "monthly_change_recomputed"]
    panel_rows.sort(key=lambda r: (r["month"], r["jurisdiction"], r["series"]))
    with open(PANEL / "state_food_cpi.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=panel_cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(panel_rows)

    q_cols = panel_cols[:15] + ["quarantine_reason", "value_source"]
    quarantined_rows.sort(key=lambda r: (r["month"], r["jurisdiction"], r["series"]))
    with open(PANEL / "quarantined.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=q_cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(quarantined_rows)

    lb_cols = ["jurisdiction", "month", "series", "index", "column_role", "base_year",
               "source_file", "published_in", "container", "raw_name"]
    lookback_rows.sort(key=lambda r: (r["source_file"], r["jurisdiction"], r["series"],
                                      r["column_role"]))
    with open(PANEL / "lookbacks.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=lb_cols)
        w.writeheader()
        w.writerows(lookback_rows)

    with open(REF / "state_crosswalk.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["raw_name", "canonical", "source_files"])
        for raw in sorted(crosswalk):
            w.writerow([raw, crosswalk[raw]["canonical"],
                        ";".join(sorted(crosswalk[raw]["source_files"]))])

    with open(REF / "base_year_evidence.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(base_rows[0].keys()))
        w.writeheader()
        w.writerows(base_rows)

    # ------------------------------------------------------------------ manifest
    for name, rec_ in files_meta.items():
        months = sorted({e["dates"]["t"] for e in ents.values()
                         if e["container"] == name or e["file"] == name})
        member_status = {k: v["parse_status"] for k, v in status.items()
                         if k.startswith(name + "!")}
        rec_["months_present"] = months
        if name in status:
            rec_["parse_status"] = status[name]["parse_status"]
        elif member_status:
            rec_["parse_status"] = ("ok (via unzipped member)"
                                    if all(v == "ok" for v in member_status.values())
                                    else f"partial: {member_status}")
        elif name.lower().endswith(".pdf"):
            rec_["parse_status"] = rec_.get("parse_status") or "not parsed (pdf)"
        else:
            rec_["parse_status"] = rec_.get("parse_status") or "not parsed"

    manifest["files"] = dict(sorted(files_meta.items()))
    manifest["panel"] = {
        "generated": dt.datetime.now().isoformat(timespec="seconds"),
        "gate": {"agree_floor": AGREE_FLOOR, "agree_tolerance": AGREE_TOL,
                 "min_pairs": MIN_PAIRS},
        "rows": len(panel_rows), "quarantined_rows": len(quarantined_rows),
        "lookback_rows": len(lookback_rows),
        "months": sorted(cand), "months_in_panel": sorted({r["month"] for r in panel_rows}),
        "quarantined_months": sorted(quarantined),
        "recovered_months": {m: {"from": r["file"], "via": list(r["sources"])}
                             for m, r in recovered.items() if r["status"] == "recovered"},
        "months_with_multiple_files": sorted(superseded),
        "chain": [{k: v for k, v in r.items() if k != "bad"} |
                  {"bad_count": len(r.get("bad", []))} for r in verdicts],
        "annual": annual_rows(cand),
        "warnings": warnings,
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    pm = sorted({r["month"] for r in panel_rows})
    print(f"\npanel rows: {len(panel_rows)}  months in panel: {len(pm)}  ({pm[0]}..{pm[-1]})")
    print(f"quarantined: {len(quarantined_rows)} rows in {len(quarantined)} month(s) "
          f"{sorted(quarantined)}")
    print(f"lookback rows: {len(lookback_rows)}   warnings: {len(warnings)}")
    for w_ in warnings[:15]:
        print("  !", w_)
    return 0


if __name__ == "__main__":
    sys.exit(main())
