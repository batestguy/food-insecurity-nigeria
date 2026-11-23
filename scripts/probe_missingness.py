# Diagnose missingness before choosing any deletion rule. The previous build lost 30% of households;
# this finds out which variable is responsible.
import pyreadstat, pandas as pd, numpy as np

P = r"data\restricted\dhs-2024\pr\NGPR8BFL.dta"
items = [f"hfs{i}" for i in range(1, 9)]
cols = ["hhid", "hvidx", "hv001", "shstate1", "hv005", "hfs_sev",
        "hv271", "hv009", "hv025", "hv219", "hv220", "hv106", "hv218",
        "hv201", "hv205", "hv225"] + items

df, meta = pyreadstat.read_dta(P, usecols=cols)
vl = meta.variable_value_labels

hh = df.drop_duplicates("hhid").copy()
hh = hh[(hh.hv005 > 0) & hh.hfs_sev.notna()]
print("households with outcome and weight:", len(hh))

def miss(name, s):
    n = s.isna().sum()
    print("  %-10s NA %6d (%5.2f%%)" % (name, n, 100 * n / len(hh)))
    return n

print("\nmissingness on the estimation sample:")
for c in ["hv271", "hv009", "hv025", "hv219", "hv220", "hv106", "hv201", "hv205", "hv225"]:
    miss(c, hh[c])

# head education: the head is line 1 (hv218 == 1 everywhere)
head = df[df.hvidx == df.hv218][["hhid", "hv106"]].rename(columns={"hv106": "head_edu"})
hh = hh.merge(head, on="hhid", how="left", validate="one_to_one")
print("\nafter the head merge:")
miss("head_edu", hh["head_edu"])

# retention if we require complete cases, one covariate added at a time
print("\nretention as covariates are added (ordered by NA, least missing first):")
order = ["hv271", "hv009", "hv025", "hv219", "hv201", "hv205", "hv225", "hv220", "head_edu"]
keep = pd.Series(True, index=hh.index)
prev = keep.sum()
for c in order:
    keep = keep & hh[c].notna()
    print("  + %-10s kept %6d (%5.1f%%)   lost %5d" % (c, keep.sum(), 100 * keep.sum() / len(hh), prev - keep.sum()))
    prev = keep.sum()

print("\nvalue labels that decide the WASH classes:")
for v in ["hv201", "hv205", "hv225", "hv025", "hv219"]:
    if v in vl:
        print("  %s: %s" % (v, dict(sorted(vl[v].items(), key=lambda kv: str(kv[0])))))
