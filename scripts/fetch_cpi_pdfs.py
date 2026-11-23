"""Fetch the PDF-only NBS monthly CPI reports (2020-01 .. 2024-10) from the e-library.

Why a second fetcher
--------------------
`fetch_cpi.py` reads the *microdata catalog* (study NGA-NBS-CPI), which only carries
November 2024 onwards. Older months exist only as PDFs on the e-library listing, already
saved on disk as `data/raw/nbs/_elibrary_search_cpi.html`. That listing gives one id per
report; `https://nigerianstat.gov.ng/download/<id>` serves the file.

Design
------
* The id comes from the saved listing, so this script makes no discovery requests at all.
* Ids are written to `data/raw/nbs/_pdf_ids.csv` before anything is downloaded: the mapping
  is provenance and belongs in the repo.
* Cache-before-download: a month whose file is already on disk with a matching sha256 is
  skipped. A raw file is never rewritten.
* The response must start with `%PDF-`. Anything else is reported and *not* kept under a
  `.pdf` name, because a 200 that returns HTML is the failure mode that wastes a day.
* Every download is recorded in `data/panel/manifest.json` (url, id, sha256, bytes, title)
  so `extract_cpi.py` picks it up through `discover_sources()` with no extra wiring.

Usage
-----
    python scripts/fetch_cpi_pdfs.py --list                  # ids only, no requests
    python scripts/fetch_cpi_pdfs.py --limit 1               # one probe download
    python scripts/fetch_cpi_pdfs.py                         # all missing months
    python scripts/fetch_cpi_pdfs.py --first 2020-01 --last 2024-10 --max-requests 120
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw" / "nbs"
PANEL = ROOT / "data" / "panel"
LISTING = RAW / "_elibrary_search_cpi.html"
IDS_CSV = RAW / "_pdf_ids.csv"
MANIFEST = PANEL / "manifest.json"

DOWNLOAD = "https://nigerianstat.gov.ng/download/{rid}"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) ConferenceMaths-CPI-fetch/1.0"
TIMEOUT = 180

MONTHS = ["January", "February", "March", "April", "May", "June", "July",
          "August", "September", "October", "November", "December"]
MONTH_NUM = {m.lower(): i for i, m in enumerate(MONTHS, start=1)}
# NBS's own spelling, kept as a typo map so the fix is visible rather than silent
MONTH_NUM["febuary"] = 2
TITLE_RE = re.compile(r"CPI and Inflation Reports?,?\s+([A-Za-z]+)\s+(\d{4})\s*$")

# Months whose listing row carries the generic title "CPI and Inflation Reports", so the id
# cannot be read off the title. Each is inferred from its numeric neighbourhood: the listing
# is ordered newest-first and the report ids are sequential, so the id between month m-1 and
# month m+1 is month m. The PDF's own header row decides the month at parse time, so a wrong
# guess here cannot corrupt the panel - it only mislabels a filename.
EXTRA_IDS = {
    "2020-03": ("1084", "id sits between Feb-2020 (1072) and Apr-2020 (1098)"),
    "2021-08": ("1241068", "id sits between Jul-2021 (1241055) and Oct-2021 (1241090), lower"),
    "2021-09": ("1241081", "id sits between Jul-2021 (1241055) and Oct-2021 (1241090), higher"),
}

_n_requests = 0


def log(msg: str) -> None:
    print(msg, flush=True)


def sha256_of(blob_or_path) -> str:
    h = hashlib.sha256()
    if isinstance(blob_or_path, (bytes, bytearray)):
        h.update(blob_or_path)
        return h.hexdigest()
    with open(blob_or_path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_listing() -> tuple[dict[str, dict], list[str]]:
    """month -> {id, title, row}; plus a list of titles that matched nothing."""
    if not LISTING.exists():
        raise SystemExit(f"missing saved listing {LISTING}")
    html = LISTING.read_text(encoding="utf-8", errors="replace")
    by_month: dict[str, dict] = {}
    skipped: list[str] = []
    for row in re.findall(r"<tr>(.*?)</tr>", html, re.S):
        cells = re.findall(r"<td[^>]*>(.*?)</td>", row, re.S)
        texts = [re.sub(r"<[^>]+>", "", c).replace("&amp;", "&").strip() for c in cells]
        title = next((t for t in texts if "CPI and Inflation Report" in t), None)
        if not title:
            continue
        m = TITLE_RE.search(title)
        rid = re.search(r"elibrary/read/(\d+)", row)
        if not m or not rid:
            skipped.append(title)
            continue
        mon, year = MONTH_NUM.get(m.group(1).lower()), int(m.group(2))
        if mon is None:
            skipped.append(title)
            continue
        ym = f"{year:04d}-{mon:02d}"
        rec = {"month": ym, "report_id": rid.group(1), "title": title,
               "id_evidence": "title"}
        # the listing is newest-first; the first row for a month wins and duplicates are noted
        if ym in by_month:
            by_month[ym].setdefault("duplicates", []).append(rec)
        else:
            by_month[ym] = rec
    for ym, (rid, why) in EXTRA_IDS.items():
        if ym not in by_month:
            by_month[ym] = {"month": ym, "report_id": rid,
                            "title": f"CPI and Inflation Reports ({ym})",
                            "id_evidence": why}
    return by_month, skipped


def month_range(first: str, last: str) -> list[str]:
    y, m = int(first[:4]), int(first[5:])
    y2, m2 = int(last[:4]), int(last[5:])
    out = []
    while (y, m) <= (y2, m2):
        out.append(f"{y:04d}-{m:02d}")
        m += 1
        if m == 13:
            y, m = y + 1, 1
    return out


def fetch(url: str) -> tuple[bytes, str]:
    global _n_requests
    _n_requests += 1
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/pdf,*/*"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return r.read(), r.headers.get("Content-Type", "")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--first", default="2020-01")
    ap.add_argument("--last", default="2024-10")
    ap.add_argument("--limit", type=int, default=0, help="download at most N files")
    ap.add_argument("--max-requests", type=int, default=120)
    ap.add_argument("--list", action="store_true", help="show the plan, make no requests")
    args = ap.parse_args()

    RAW.mkdir(parents=True, exist_ok=True)
    by_month, skipped = parse_listing()
    log(f"listing: {len(by_month)} months with an id; {len(skipped)} titles unparsed")
    if skipped:
        log("  unparsed titles: " + "; ".join(skipped[:8]))

    wanted = month_range(args.first, args.last)
    have_id = [m for m in wanted if m in by_month]
    no_id = [m for m in wanted if m not in by_month]

    with open(IDS_CSV, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["month", "report_id", "title", "url", "id_evidence"])
        for m in wanted:
            if m in by_month:
                r = by_month[m]
                w.writerow([m, r["report_id"], r["title"], DOWNLOAD.format(rid=r["report_id"]),
                            r["id_evidence"]])
            else:
                w.writerow([m, "", "", "", "no row in saved listing"])
    log(f"wrote {IDS_CSV.relative_to(ROOT)} for {len(wanted)} months")

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.exists() else {}
    files = manifest.get("files", {})

    log(f"months wanted   : {len(wanted)}  ({wanted[0]} .. {wanted[-1]})")
    log(f"months with id  : {len(have_id)}")
    if no_id:
        log(f"months with no id: {len(no_id)} -> {no_id}")
    for m in have_id[:3] + have_id[-3:]:
        r = by_month[m]
        log(f"  {m}  id={r['report_id']:>9}  {r['title']}")
    if args.list:
        return 0

    ok = cached = failed = 0
    done = 0
    for m in have_id:
        if args.limit and done >= args.limit:
            break
        name = f"CPI_{m}_Report.pdf"
        dest = RAW / name
        rec = files.get(name, {})
        url = DOWNLOAD.format(rid=by_month[m]["report_id"])
        rec.update({"url": url, "catalog_resource_id": by_month[m]["report_id"],
                    "source": "elibrary", "month": m, "listing_title": by_month[m]["title"],
                    "id_evidence": by_month[m]["id_evidence"]})

        if dest.exists() and not rec.get("fetch_error"):
            digest = sha256_of(dest)
            if rec.get("sha256") in (None, digest):
                rec.update({"sha256": digest, "bytes": dest.stat().st_size, "cache": "hit"})
                files[name] = rec
                cached += 1
                continue

        if _n_requests >= args.max_requests:
            log(f"request cap {args.max_requests} reached at {m}; stopping cleanly")
            break

        log(f"  > {name}  (id {by_month[m]['report_id']})")
        try:
            blob, ctype = fetch(url)
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            log(f"  x {name}: {type(exc).__name__}: {exc}")
            rec.update({"fetch_error": f"{type(exc).__name__}: {exc}", "cache": "fail"})
            files[name] = rec
            failed += 1
            continue
        done += 1
        if not blob.startswith(b"%PDF-"):
            head = blob[:120].decode("utf-8", "replace").replace("\n", " ")
            log(f"  x {name}: not a PDF (content-type={ctype!r}, {len(blob)} B): {head}")
            rec.update({"fetch_error": f"not a PDF: content-type={ctype!r} bytes={len(blob)}",
                        "cache": "fail", "bytes": len(blob)})
            files[name] = rec
            failed += 1
            continue
        tmp = dest.with_suffix(".pdf.part")
        tmp.write_bytes(blob)
        tmp.replace(dest)
        rec.update({"sha256": sha256_of(blob), "bytes": len(blob), "cache": "miss",
                    "content_type": ctype, "fetched": time.strftime("%Y-%m-%dT%H:%M:%S")})
        rec.pop("fetch_error", None)
        files[name] = rec
        ok += 1
        log(f"    ok {len(blob):>9} B  sha={rec['sha256'][:12]}")

    manifest["files"] = dict(sorted(files.items()))
    manifest.setdefault("study", "NGA-NBS-CPI")
    manifest["pdf_sweep"] = {
        "generated": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "first": args.first, "last": args.last,
        "months_requested": wanted, "months_with_id": have_id, "months_without_id": no_id,
        "downloaded": ok, "cached": cached, "failed": failed,
        "http_requests": _n_requests,
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    log(f"\ndownloaded {ok}, cached {cached}, failed {failed}; {_n_requests} HTTP requests")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
