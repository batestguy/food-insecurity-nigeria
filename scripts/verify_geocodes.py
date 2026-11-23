# Verify the geocoded files: does DHSCLUST join the microdata's hv001 for all 1,380 clusters?
import csv, struct, sys
from pathlib import Path

GE = Path(r"data\restricted\dhs-2024\ge")
PR = r"D:\Curt Cut Disability\data\restricted\dhs-2024\pr\NGPR8BFL.dta"

def read_dbf(path):
    """Minimal dBASE reader: returns list of dicts. Avoids depending on pyshp."""
    with open(path, "rb") as f:
        data = f.read()
    nrec = struct.unpack("<I", data[4:8])[0]
    hlen = struct.unpack("<H", data[8:10])[0]
    rlen = struct.unpack("<H", data[10:12])[0]
    fields, off = [], 32
    while data[off] != 0x0D:
        name = data[off:off + 11].split(b"\x00")[0].decode("latin-1")
        ftype = chr(data[off + 11])
        flen = data[off + 16]
        fields.append((name, ftype, flen))
        off += 32
    out = []
    pos = hlen
    for _ in range(nrec):
        rec = data[pos:pos + rlen]
        if not rec or rec[:1] == b"\x1a":
            break
        pos += rlen
        p = 1
        row = {}
        for name, ftype, flen in fields:
            raw = rec[p:p + flen].decode("latin-1").strip()
            p += flen
            row[name] = raw
        out.append(row)
    return fields, out

fields, recs = read_dbf(GE / "NGGE8AFL.dbf")
print("shapefile fields:", [f[0] for f in fields])
print("shapefile records:", len(recs))
print("first record:", {k: v for k, v in list(recs[0].items())[:8]})

# clusters in the geocoded file
keys = ["DHSCLUST", "DHSCLUS", "CLUSTER", "cluster"]
key = next((k for k in keys if k in recs[0]), None)
print("cluster key used:", key)
geo_ids = {r[key] for r in recs}
print("distinct clusters in geocoded file:", len(geo_ids))

# clusters in the microdata
try:
    import pyreadstat
    df, _ = pyreadstat.read_dta(PR, usecols=["hv001"])
    micro_ids = {str(int(v)) for v in df.hv001.dropna().unique()}
    print("distinct clusters in microdata  :", len(micro_ids))
    missing = micro_ids - geo_ids
    extra = geo_ids - micro_ids
    print("microdata clusters WITH coordinates:", len(micro_ids & geo_ids))
    print("microdata clusters WITHOUT         :", len(missing), sorted(list(missing))[:8])
    print("geocoded clusters not in microdata :", len(extra))
except Exception as e:
    print("microdata check failed:", type(e).__name__, e)

# coordinates present?
latf = next((k for k in recs[0] if "LAT" in k.upper()), None)
lonf = next((k for k in recs[0] if "LON" in k.upper()), None)
print("lat/lon fields:", latf, lonf)
if latf and lonf:
    bad = sum(1 for r in recs if not r[latf] or not r[lonf])
    print("records with missing coordinates:", bad)
    print("lat range:", min(float(r[latf]) for r in recs if r[latf]),
          "to", max(float(r[latf]) for r in recs if r[latf]))

# covariates csv
with open(GE / "NGGC8AFL.csv", newline="", encoding="utf-8-sig") as f:
    rdr = csv.reader(f)
    hdr = next(rdr)
    n = sum(1 for _ in rdr)
print("\ncovariates csv: rows", n, "| columns", len(hdr))
print("first columns:", hdr[:12])
ckey = next((h for h in hdr if h.upper() == "DHSCLUST"), None)
print("covariates cluster key:", ckey)
