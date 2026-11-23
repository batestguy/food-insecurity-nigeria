# Resolve the estimand: is "severe food insecurity" the Rasch probability or the raw-score cut-off?
# Also verify three structural claims made by the builder.
import pyreadstat, pandas as pd, numpy as np

P = r"data\restricted\dhs-2024\pr\NGPR8BFL.dta"
items = [f"hfs{i}" for i in range(1, 9)]
need = ["hhid", "hvidx", "hv001", "shstate1", "hv005", "hfs_sev", "hv101", "hv218", "hv106", "hv271"]
df, meta = pyreadstat.read_dta(P, usecols=need + items)

print("--- claim checks ---")
print("hvidx present in person file:", "hvidx" in df.columns)
print("hv271 present in person file:", "hv271" in df.columns)
print("hv218 == 1 on every row:", bool((df.hv218 == 1).all()))
print("rows where hv101 == 1 (head):", int((df.hv101 == 1).sum()), "| distinct hhids:", df.hhid.nunique())
print("rows where hvidx == hv218:", int((df.hvidx == df.hv218).sum()))

# item coding
print("\n--- item coding ---")
for it in items[:3]:
    print(f"  {it}: values {sorted(df[it].dropna().unique().tolist())[:6]}")
score_item = df[items].apply(lambda s: (s == 1).astype(int))
df["fies_score"] = score_item.sum(axis=1)
print("fies_score distribution (persons):")
print(df.fies_score.value_counts().sort_index().to_string())

hh = df.drop_duplicates("hhid").copy()
hh = hh[hh.hv005 > 0]
print("\nhouseholds:", len(hh))

w = hh.hv005.values
print("\n--- the two candidate estimands (weighted) ---")
print("mean of hfs_sev/1e8            : %.4f" % np.average(hh.hfs_sev / 1e8, weights=w))
print("prevalence fies_score >= 4     : %.4f" % np.average((hh.fies_score >= 4).astype(float), weights=w))
print("prevalence fies_score >= 5     : %.4f" % np.average((hh.fies_score >= 5).astype(float), weights=w))
print("prevalence fies_score >= 6     : %.4f" % np.average((hh.fies_score >= 6).astype(float), weights=w))
print("prevalence fies_score >= 7     : %.4f" % np.average((hh.fies_score >= 7).astype(float), weights=w))

ct = pd.crosstab(hh.fies_score, (hh.hfs_sev / 1e8).round(6))
print("\ncrosstab cells with a value:", int((ct > 0).sum()), "| rows:", ct.shape[0], "| cols:", ct.shape[1])
print("max probability per raw score:")
print((hh.groupby("fies_score").apply(lambda g: (g.hfs_sev / 1e8).max(), include_groups=False)).round(4).to_string())

# state estimates for both thresholds, for the spatial test
NAME2ISO = {"abia":"NG-AB","adamawa":"NG-AD","akwa ibom":"NG-AK","anambra":"NG-AN","bauchi":"NG-BA",
 "bayelsa":"NG-BY","benue":"NG-BE","borno":"NG-BO","cross river":"NG-CR","delta":"NG-DE","ebonyi":"NG-EB",
 "edo":"NG-ED","ekiti":"NG-EK","enugu":"NG-EN","fct-abuja":"NG-FC","gombe":"NG-GO","imo":"NG-IM",
 "jigawa":"NG-JI","kaduna":"NG-KD","kano":"NG-KN","katsina":"NG-KT","kebbi":"NG-KE","kogi":"NG-KO",
 "kwara":"NG-KW","lagos":"NG-LA","nasarawa":"NG-NA","niger":"NG-NI","ogun":"NG-OG","ondo":"NG-ON",
 "osun":"NG-OS","oyo":"NG-OY","plateau":"NG-PL","rivers":"NG-RI","sokoto":"NG-SO","taraba":"NG-TA",
 "yobe":"NG-YO","zamfara":"NG-ZA"}
labels = meta.variable_value_labels["shstate1"]
MAP = {int(k): NAME2ISO[str(v).strip().lower()] for k, v in labels.items()}
hh["geography"] = hh.shstate1.map(MAP)

rows = []
for iso, g in hh.groupby("geography"):
    ww = g.hv005.values
    rows.append({"geography": iso,
                 "severe_ge6": np.average((g.fies_score >= 6).astype(float), weights=ww),
                 "modsev_ge4": np.average((g.fies_score >= 4).astype(float), weights=ww),
                 "mean_prob": np.average(g.hfs_sev / 1e8, weights=ww)})
out = pd.DataFrame(rows).sort_values("geography")
out.to_csv(r"data\derived\fi_state_estimands.csv", index=False)
print("\nstate estimates written for both estimands")
print("severe_ge6 across states: %.3f to %.3f (median %.3f)" % (out.severe_ge6.min(), out.severe_ge6.max(), out.severe_ge6.median()))
