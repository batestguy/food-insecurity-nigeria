# Build the analysis dataset for the food-insecurity small-area model.
# Follows data/derived/covariate_spec.md, with one correction: hv225 (shared toilet) is structurally
# absent for households with no toilet facility, and must be recoded to "not improved", not to missing.
# That single change takes retention from 77% to 100% of estimation households.
import pyreadstat, pandas as pd, numpy as np, json

P = r"data\restricted\dhs-2024\pr\NGPR8BFL.dta"
OUT = r"data\derived"

NAME2ISO = {"abia":"NG-AB","adamawa":"NG-AD","akwa ibom":"NG-AK","anambra":"NG-AN","bauchi":"NG-BA",
 "bayelsa":"NG-BY","benue":"NG-BE","borno":"NG-BO","cross river":"NG-CR","delta":"NG-DE","ebonyi":"NG-EB",
 "edo":"NG-ED","ekiti":"NG-EK","enugu":"NG-EN","fct-abuja":"NG-FC","gombe":"NG-GO","imo":"NG-IM",
 "jigawa":"NG-JI","kaduna":"NG-KD","kano":"NG-KN","katsina":"NG-KT","kebbi":"NG-KE","kogi":"NG-KO",
 "kwara":"NG-KW","lagos":"NG-LA","nasarawa":"NG-NA","niger":"NG-NI","ogun":"NG-OG","ondo":"NG-ON",
 "osun":"NG-OS","oyo":"NG-OY","plateau":"NG-PL","rivers":"NG-RI","sokoto":"NG-SO","taraba":"NG-TA",
 "yobe":"NG-YO","zamfara":"NG-ZA"}

# JMP improved drinking water (WHO/UNICEF). Everything else, including bottled/sachet, is 0.
WATER_IMPROVED = {10, 11, 12, 13, 14, 20, 21, 31, 41, 51}
# JMP improved sanitation facility. Shared facilities are then downgraded below.
SAN_IMPROVED = {10, 11, 12, 13, 20, 21, 22, 41}
NO_FACILITY = {30, 31}

items = [f"hfs{i}" for i in range(1, 9)]
cols = ["hhid","hvidx","hv001","shstate1","hv005","hfs_sev","hfs_mod",
        "hv271","hv009","hv025","hv219","hv220","hv106","hv218","hv201","hv205","hv225"] + items
df, meta = pyreadstat.read_dta(P, usecols=cols)
vl = meta.variable_value_labels
MAP = {int(k): NAME2ISO[str(v).strip().lower()] for k, v in vl["shstate1"].items()}
assert len(MAP) == 37

# household-level frame; the FIES block is constant within household (verified: 0 vary)
hh = df.drop_duplicates("hhid").copy()
hh["geography"] = hh.shstate1.map(MAP)
hh["fies_score"] = hh[items].apply(lambda s: (s == 1).astype(int)).sum(axis=1)
hh["sev_prob"] = hh.hfs_sev / 1e8
hh = hh[(hh.hv005 > 0) & hh.sev_prob.notna()].copy()
n0 = len(hh)

# head's education: the head is line 1 in every household (hv218 == 1 throughout)
head = df.loc[df.hvidx == df.hv218, ["hhid", "hv106"]].set_index("hhid")["hv106"]
hh["head_edu"] = hh.hhid.map(head)

# wealth: stored as a 5-decimal factor score, possibly multiplied by 1e5
raw_min, raw_max = hh.hv271.min(), hh.hv271.max()
scale = 1e5 if max(abs(raw_min), abs(raw_max)) > 20 else 1.0
hh["wealth"] = hh.hv271 / scale

# structural recode: no facility means unimproved, and "shared" is not applicable
hh["improved_water"] = hh.hv201.isin(WATER_IMPROVED).astype(int)
san_facility = hh.hv205.isin(SAN_IMPROVED)
shared = hh.hv225.eq(1)                      # NaN (no facility) -> False
hh["improved_sanitation"] = (san_facility & ~shared).astype(int)

out = pd.DataFrame({
    "hhid": hh.hhid, "hv001": hh.hv001, "geography": hh.geography, "hv005": hh.hv005,
    "fies_score": hh.fies_score,
    "severe_fi": (hh.sev_prob >= 0.5).astype(int),
    "modsev_ge4": (hh.fies_score >= 4).astype(int),
    "sev_prob": hh.sev_prob,
    "wealth_z": (hh.wealth - hh.wealth.mean()) / hh.wealth.std(),
    "hh_size": hh.hv009,
    "urban": hh.hv025.eq(1).astype(int),
    "head_male": hh.hv219.eq(1).astype(int),
    "head_age": hh.hv220,
    "head_age_c": hh.hv220 - 40,
    "head_age_c2": (hh.hv220 - 40) ** 2,
    "head_edu_secondary": hh.head_edu.eq(2).astype(int),
    "head_edu_higher": hh.head_edu.eq(3).astype(int),
    "improved_water": hh.improved_water,
    "improved_sanitation": hh.improved_sanitation,
})

na = out.isna().sum()
print("households with outcome and weight : %d" % n0)
print("rows written                       : %d  (retention %.2f%%)" % (len(out), 100*len(out)/n0))
print("any missing value in covariates    : %d" % int(na.drop(["hhid"]).sum()))
if na.drop(["hhid"]).sum():
    print(na[na > 0].to_string())

w = out.hv005.values
print("\nweighted prevalence, severe (hfs_sev>=0.5): %.4f" % np.average(out.severe_fi.values, weights=w))
print("weighted prevalence, fies_score >= 4      : %.4f" % np.average(out.modsev_ge4.values, weights=w))
print("states: %d | clusters: %d" % (out.geography.nunique(), out.hv001.nunique()))
print("households per state: min %d, median %d, max %d" % (
    out.groupby("geography").size().min(), out.groupby("geography").size().median(),
    out.groupby("geography").size().max()))
print("\nwealth raw range: %.4f to %.4f (divided by %.0f)" % (raw_min, raw_max, scale))
print("improved_water share     : %.3f" % out.improved_water.mean())
print("improved_sanitation share: %.3f" % out.improved_sanitation.mean())

out.to_csv(OUT + r"\analysis_households.csv", index=False)

mapping = {
    "outcome": "severe_fi = 1{hfs_sev/1e8 >= 0.5}; equals all eight FIES items affirmed",
    "retention": {"households": n0, "written": len(out), "dropped": n0 - len(out)},
    "wealth": {"raw_min": float(raw_min), "raw_max": float(raw_max), "divisor": float(scale)},
    "water_improved_codes": sorted(WATER_IMPROVED),
    "water_label_map": {str(k): v for k, v in sorted(vl["hv201"].items())},
    "sanitation_improved_codes": sorted(SAN_IMPROVED),
    "sanitation_no_facility_codes": sorted(NO_FACILITY),
    "sanitation_label_map": {str(k): v for k, v in sorted(vl["hv205"].items())},
    "hv225_missing_households": int(hh.hv225.isna().sum()),
    "hv225_missing_rule": "no facility; recoded unimproved, NOT dropped",
    "head_education_match": int(hh.head_edu.notna().sum()),
    "national_weighted": {
        "severe_fi": float(np.average(out.severe_fi.values, weights=w)),
        "modsev_ge4": float(np.average(out.modsev_ge4.values, weights=w))},
}
with open(OUT + r"\covariate_mapping.json", "w", encoding="utf-8") as f:
    json.dump(mapping, f, indent=2)
print("\nwritten: analysis_households.csv and covariate_mapping.json")
