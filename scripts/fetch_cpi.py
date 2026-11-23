"""Fetch NBS monthly CPI publications for study NGA-NBS-CPI (catalog 154).

Design
------
* The resource list comes from the catalog's own metadata export, not from guessing
  filenames. If the export is not cached it is fetched once.
* Raw files land in data/raw/nbs/ under their original names and are never rewritten.
  ZIPs are unpacked into data/raw/nbs/unzipped/<zip-stem>/ ; the archive itself is
  left byte-identical.
* Cache-before-download: a resource is skipped when the local file exists and its
  sha256 already matches the recorded one.
* Every download is recorded in data/panel/manifest.json with url, sha256, bytes.
  months_present / parse_status are filled in later by extract_cpi.py.

Usage:  python scripts/fetch_cpi.py [--force]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw" / "nbs"
UNZIP = RAW / "unzipped"
PANEL = ROOT / "data" / "panel"
MANIFEST = PANEL / "manifest.json"
META_CACHE = RAW / "_metadata_154.json"

META_URL = "https://microdata.nigerianstat.gov.ng/index.php/metadata/export/154/json"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) ConferenceMaths-CPI-fetch/1.0"
TIMEOUT = 120

_n_requests = 0


def log(msg: str) -> None:
    print(msg, flush=True)


def http_get(url: str, dest: Path | None = None) -> bytes | None:
    """GET with one retry. Returns bytes when dest is None, else writes to dest."""
    global _n_requests
    for attempt in (1, 2):
        _n_requests += 1
        req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
                if dest is None:
                    return r.read()
                tmp = dest.with_suffix(dest.suffix + ".part")
                with open(tmp, "wb") as fh:
                    while True:
                        chunk = r.read(1 << 16)
                        if not chunk:
                            break
                        fh.write(chunk)
                tmp.replace(dest)
                return None
        except (urllib.error.ContentTooShortError, TimeoutError, OSError) as exc:
            log(f"    attempt {attempt} failed: {type(exc).__name__}: {exc}")
            if attempt == 2:
                raise
            time.sleep(2)
    return None


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_resources() -> list[dict]:
    if not META_CACHE.exists():
        META_CACHE.parent.mkdir(parents=True, exist_ok=True)
        log("fetching catalog metadata export")
        blob = http_get(META_URL)
        META_CACHE.write_bytes(blob)
    meta = json.loads(META_CACHE.read_text(encoding="utf-8-sig", errors="replace"))
    out = []
    for r in meta.get("resources", []):
        url = r.get("filename", "")
        if not url.startswith("http"):
            continue
        parts = [p for p in urllib.parse.urlparse(url).path.split("/") if p]
        # .../download/<id>/<filename>
        rid = parts[-2] if len(parts) >= 2 else ""
        name = urllib.parse.unquote(parts[-1])
        out.append({"id": rid, "url": url, "name": name})
    return out


def unzip(archive: Path) -> list[str]:
    """Unpack into UNZIP/<stem>/, skipping anything already present. Returns written names."""
    target = UNZIP / archive.stem
    target.mkdir(parents=True, exist_ok=True)
    written = []
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            if info.is_dir():
                continue
            # keep the archive's own names, but flatten directory components
            name = os.path.basename(info.filename.replace("\\", "/"))
            if not name:
                continue
            dest = target / name
            if not dest.exists() or dest.stat().st_size != info.file_size:
                with zf.open(info) as src, open(dest, "wb") as fh:
                    fh.write(src.read())
                written.append(name)
    return written


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="re-download even if cached")
    args = ap.parse_args()

    RAW.mkdir(parents=True, exist_ok=True)
    UNZIP.mkdir(parents=True, exist_ok=True)
    PANEL.mkdir(parents=True, exist_ok=True)

    manifest = {}
    if MANIFEST.exists():
        try:
            manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            manifest = {}
    files = manifest.get("files", {})

    resources = load_resources()
    log(f"catalog lists {len(resources)} resources")

    ok = skipped = failed = 0
    for res in resources:
        name = res["name"]
        dest = RAW / name
        rec = files.get(name, {})
        rec.update({"url": res["url"], "catalog_resource_id": res["id"]})

        if dest.exists() and not args.force:
            digest = sha256_of(dest)
            if rec.get("sha256") == digest:
                log(f"  = {name} (cached, {dest.stat().st_size} B)")
                rec["cache"] = "hit"
                files[name] = rec
                skipped += 1
                continue
            log(f"  ! {name} present but hash differs from manifest, re-fetching")

        try:
            log(f"  > {name}")
            http_get(res["url"], dest)
            digest = sha256_of(dest)
            rec.update({"sha256": digest, "bytes": dest.stat().st_size,
                        "cache": "miss", "fetched": time.strftime("%Y-%m-%dT%H:%M:%S")})
            files[name] = rec
            ok += 1
        except Exception as exc:  # noqa: BLE001 - reported, not swallowed
            log(f"  x {name}: {type(exc).__name__}: {exc}")
            rec.update({"fetch_error": f"{type(exc).__name__}: {exc}",
                        "sha256": rec.get("sha256"), "cache": "fail"})
            files[name] = rec
            failed += 1

    # unpack archives that are present
    unzipped = {}
    for name, rec in sorted(files.items()):
        archive = RAW / name
        if not archive.exists() or archive.suffix.lower() != ".zip":
            continue
        try:
            written = unzip(archive)
            unzipped[name] = written
            rec["members"] = sorted(
                p.name for p in (UNZIP / archive.stem).iterdir() if p.is_file()
            )
            log(f"  + {name} -> {len(rec['members'])} member(s)"
                + (f", {len(written)} new" if written else ""))
        except zipfile.BadZipFile as exc:
            rec["unzip_error"] = str(exc)
            log(f"  x {name}: BadZipFile: {exc}")

    manifest = {
        "study": "NGA-NBS-CPI",
        "catalog": "https://microdata.nigerianstat.gov.ng/index.php/catalog/154",
        "generated": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "http_requests": _n_requests,
        "counts": {"downloaded": ok, "cached": skipped, "failed": failed},
        "files": dict(sorted(files.items())),
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    log(f"downloaded {ok}, cached {skipped}, failed {failed}; {_n_requests} HTTP requests")
    log(f"manifest -> {MANIFEST.relative_to(ROOT)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
