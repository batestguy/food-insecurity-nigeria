# Direct (design-based) state estimates of food insecurity from NDHS 2024.
# Emits BOTH estimands under explicit names, because conflating them caused two downstream errors:
#   sev_prob_mean  = mean Rasch severe probability (the survey office's construct)
#   sev_prev_all8  = prevalence of hfs_sev >= 0.5, which in this file == all eight items affirmed
# The state-code map was verified once on 2026-11-22 against the project's published aggregates
# (correlation 0.9996, mean abs diff 0.0006); see AGENTS.md. It is re-derived here from the file labels.
import pyreadstat, pandas as pd, numpy as np

P = r"data\restricted\dhs-2024\pr\NGPR8BFL.dta"

NAME2ISO = {
    "abia":"NG-AB","adamawa":"NG-AD","akwa ibom":"NG-AK","anambra":"NG-AN","bauchi":"NG-BA",
    "bayelsa":"NG-BY","benue":"NG-BE","borno":"NG-BO","cross river":"NG-CR","delta":"NG-DE",
    "ebonyi":"NG-EB","edo":"NG-ED","ekiti":"NG-EK","enugu":"NG-EN","fct-abuja":"NG-FC",
    "gombe":"NG-GO","imo":"NG-IM","jigawa":"NG-JI","kaduna":"NG-KD","kano":"NG-KN",
    "katsina":"NG-KT","kebbi":"NG-KE","kogi":"NG-KO","kwara":"NG-KW","lagos":"NG-LA",
    "nasarawa":"NG-NA","niger":"NG-NI","ogun":"NG-OG","ondo":"NG-ON","osun":"NG-OS",
    "oyo":"NG-OY","plateau":"NG-PL","rivers":"NG-RI","sokoto":"NG-SO","taraba":"NG-TA",
    "yobe":"NG-YO","zamfara":"NG-ZA",
}

items = [f"hfs{i}" for i in range(1, 9)]
_, meta = pyreadstat.read_dta(P, metadataonly=True)
labels = meta.variable_value_labels["shstate1"]
MAP = {int(k): NAME2ISO[str(v).strip().lower()] for k, v in labels.items()}
assert len(MAP) == 37, "state label map incomplete"

df, _ = pyreadstat.read_dta(P, usecols=["hhid", "hv001", "shstate1", "hv005", "hfs_sev", "hfs_mod"] + items)
df["iso"] = df.shstate1.map(MAP)
assert df.iso.isna().sum() == 0, "unmapped state codes"

hh = df.drop_duplicates("hhid").copy()
hh["sev_prob"] = hh.hfs_sev / 1e8
hh["mod_prob"] = hh.hfs_mod / 1e8
hh["fies_score"] = hh[items].apply(lambda s: (s == 1).astype(int)).sum(axis=1)
hh = hh[(hh.hv005 > 0) & hh.sev_prob.notna()]

w = hh.hv005.values
print("households: %d | clusters: %d | states: %d" % (len(hh), hh.hv001.nunique(), hh.iso.nunique()))
print("national sev_prob_mean : %.4f" % np.average(hh.sev_prob.values, weights=w))
print("national sev_prev_all8 : %.4f" % np.average((hh.sev_prob.values >= 0.5).astype(float), weights=w))
print("national modsev_prob   : %.4f" % np.average(hh.mod_prob.values, weights=w))
print("national modsev_ge4    : %.4f" % np.average((hh.fies_score.values >= 4).astype(float), weights=w))

rows = []
for iso, g in hh.groupby("iso"):
    ww = g.hv005.values
    rows.append({
        "geography": iso,
        "n_hh": len(g),
        "n_clusters": g.hv001.nunique(),
        "sev_prob_mean": np.average(g.sev_prob.values, weights=ww),
        "sev_prev_all8": np.average((g.sev_prob.values >= 0.5).astype(float), weights=ww),
        "modsev_prob_mean": np.average(g.mod_prob.values, weights=ww),
        "modsev_prev_ge4": np.average((g.fies_score.values >= 4).astype(float), weights=ww),
    })
out = pd.DataFrame(rows).sort_values("geography")
out.to_csv(r"data\derived\fi_state_direct.csv", index=False)
print("\nwritten: data/derived/fi_state_direct.csv (%d states)" % len(out))
print("sev_prev_all8 by state: min %.3f (%s)  median %.3f  max %.3f (%s)" % (
    out.sev_prev_all8.min(), out.loc[out.sev_prev_all8.idxmin(), "geography"],
    out.sev_prev_all8.median(),
    out.sev_prev_all8.max(), out.loc[out.sev_prev_all8.idxmax(), "geography"]))
