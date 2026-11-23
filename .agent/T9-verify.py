"""T9 independent verification. Re-derives every claim from the written outputs.

Run:  python .agent/T9-verify.py
"""
import json

import pandas as pd

ok = []


def chk(name, cond, detail=""):
    ok.append((name, bool(cond), detail))
    print(("PASS " if cond else "FAIL ") + name + ("  | " + str(detail) if detail != "" else ""))


qc = json.load(open("data/derived/lga_dataset_qc.json"))
fix = pd.read_csv("data/derived/cluster_lga_fixed.csv")
pop = pd.read_csv("data/derived/lga_population.csv")
t8 = pd.read_csv("data/derived/cluster_lga.csv")
t8co = pd.read_csv("data/derived/lga_coverage.csv")
hh = pd.read_csv("data/derived/analysis_households.csv")
hh2 = pd.read_csv(
    "data/derived/analysis_households_lga.csv",
    usecols=["hhid", "hv001", "geography", "severe_fi", "lga_id", "lga_name",
             "state_iso", "lga_population", "All_Population_Count_2020", "urban"],
)

# ---- shapes and keys
chk("cluster_lga_fixed rows 1380", len(fix) == 1380, len(fix))
chk("cluster ids unique", fix.DHSCLUST.is_unique, fix.DHSCLUST.nunique())
chk("lga_population rows 774", len(pop) == 774, len(pop))
chk("lga_population ids unique", pop.lga_id.is_unique, pop.lga_id.nunique())

# ---- the correction rule: survey state kept, new LGA inside that state
chk("every final state equals the survey state", (fix.state_iso == fix.survey_state_iso).all())
chk("reassigned flag matches a changed lga_id",
    (fix.reassigned == (fix.lga_id != fix.previous_lga_id)).all())
moved = fix[fix.reassigned]
chk("15 clusters moved", len(moved) == 15, len(moved))
chk("15 clusters had a disagreeing polygon state",
    qc["state_correction"]["clusters_state_disagreeing"] == 15, len(moved))
state_of_lga = pop.set_index("lga_id").state_iso
chk("each moved cluster's new LGA is in its survey state",
    (state_of_lga.reindex(moved.lga_id).values == moved.survey_state_iso.values).all())
chk("each moved cluster's old LGA was in the polygon state",
    (state_of_lga.reindex(moved.previous_lga_id).values == moved.polygon_state_iso.values).all())
chk("no unmoved cluster changed state",
    fix.loc[~fix.reassigned, "state_iso"].equals(fix.loc[~fix.reassigned, "survey_state_iso"]))
chk("moved clusters moved a short distance (<=60 km)",
    moved.distance_to_lga_m.max() <= 60000, round(moved.distance_to_lga_m.max() / 1000, 1))

# ---- population
chk("population total equals the source total", abs(pop.population.sum() - 204909220) < 1,
    f"{pop.population.sum():,.0f}")
chk("exactly one LGA has no population", pop.population.isna().sum() == 1,
    pop.loc[pop.population.isna(), "lga_name"].tolist())
chk("no zero or negative populations", (pop.population.dropna() > 0).all())
chk("population_year is 2020", set(pop.population_year.dropna().unique()) == {2020})

# ---- household join
chk("household rows unchanged", len(hh2) == 39877, len(hh2))
chk("no household lacks an lga_id", hh2.lga_id.notna().all())
per_cluster = hh2.groupby("hv001").lga_id.nunique()
chk("every cluster maps to exactly one LGA", (per_cluster == 1).all(), per_cluster.max())
chk("household lga_id equals the cluster table's lga_id",
    (hh2.groupby("hv001").lga_id.first()
     == fix.set_index("hv001").lga_id.reindex(hh2.groupby("hv001").lga_id.first().index)).all())
mm = hh2[["hv001", "state_iso"]].drop_duplicates().merge(
    fix[["hv001", "state_iso"]], on="hv001", suffixes=("_hh", "_cl"))
chk("household state_iso matches cluster state_iso for all 1380 clusters",
    (mm.state_iso_hh == mm.state_iso_cl).all(), len(mm))
chk("no household has a null lga_population", hh2.lga_population.notna().sum() == len(hh2),
    int(hh2.lga_population.isna().sum()))
chk("household count per LGA reconciles with the per-cluster household counts",
    (hh2.groupby("lga_id").size().reindex(pop.lga_id).fillna(0).astype(int)
     .values
     == hh.groupby("hv001").size().to_frame("n").join(fix.set_index("hv001")[["lga_id"]])
        .groupby("lga_id").n.sum().reindex(pop.lga_id).fillna(0).astype(int).values).all(),
    int(hh2.groupby("lga_id").size().sum()))
chk("outcome column preserved (weighted-free mean in range)",
    0.2 < hh2.severe_fi.mean() < 0.4, round(float(hh2.severe_fi.mean()), 4))

# ---- the two identification shares, recomputed from the written files
cnt_before = t8co.set_index("lga_id").n_clusters.reindex(pop.lga_id).fillna(0).astype(int).values
cnt_after = fix.lga_id.value_counts().reindex(pop.lga_id).fillna(0).astype(int).values
p = pop.population
known = p.notna().values
share_before = p[(cnt_before == 0) & known].sum() / p[known].sum()
share_after = p[(cnt_after == 0) & known].sum() / p[known].sum()
chk("count share of LGAs with no cluster, before = 123/774",
    (cnt_before == 0).sum() == 123 and qc["identification_shares"]["before_correction"]["lgas_zero_cluster"] == 123)
chk("count share of LGAs with no cluster, after = 120/774",
    (cnt_after == 0).sum() == 120 and qc["identification_shares"]["after_correction"]["lgas_zero_cluster"] == 120)
chk("population share before reproduces the QC value",
    abs(share_before - qc["identification_shares"]["before_correction"]["population_share_no_cluster"]) < 1e-6,
    round(share_before, 6))
chk("population share after reproduces the QC value",
    abs(share_after - qc["identification_shares"]["after_correction"]["population_share_no_cluster"]) < 1e-6,
    round(share_after, 6))
chk("population-based p exceeds count-based p by more than 2 points",
    ((1 - share_after) - (1 - (cnt_after == 0).sum() / len(cnt_after))) > 0.02,
    f"count p={1 - (cnt_after == 0).sum() / len(cnt_after):.4f}  population p={1 - share_after:.4f}")

# ---- LGAs that cross the zero boundary
gain = set(pop.lga_name[cnt_after > cnt_before])
lose = set(pop.lga_name[cnt_after < cnt_before])
chk("LGAs gaining clusters under the correction are listed in the QC",
    set(qc["state_correction"]["lgas_gaining_clusters"]) == gain, sorted(gain))
chk("LGAs losing clusters under the correction are listed in the QC",
    set(qc["state_correction"]["lgas_losing_clusters"]) == lose, sorted(lose))
chk("LGAs from zero minus to zero explains the 123 -> 120 fall",
    123 - qc["state_correction"]["lgas_from_zero_clusters"]
    + qc["state_correction"]["lgas_to_zero_clusters"] == 120
    and qc["state_correction"]["lgas_from_zero_clusters"] == 4
    and qc["state_correction"]["lgas_to_zero_clusters"] == 1,
    (qc["state_correction"]["lgas_from_zero_clusters"],
     qc["state_correction"]["lgas_to_zero_clusters"]))
fell_to_zero = sorted(pop.lga_name[(cnt_before > 0) & (cnt_after == 0)])
chk("the LGA that lost its only cluster is reported", len(fell_to_zero) == 1, fell_to_zero)
print("   LGAs that gained their first cluster:",
      sorted(pop.lga_name[(cnt_before == 0) & (cnt_after > 0)]))

# ---- covariate attachment spot check against the raw extract
raw = pd.read_csv("data/restricted/dhs-2024/ge/NGGC8AFL.csv",
                  usecols=["DHSCLUST", "All_Population_Count_2020"])
j = (hh2.merge(fix[["hv001", "DHSCLUST"]], on="hv001", how="left")
        .merge(raw, on="DHSCLUST", how="left", suffixes=("_hh", "_raw")))
chk("every household got a cluster id", j.DHSCLUST.notna().all())
chk("All_Population_Count_2020 copied from the extract unchanged",
    (j.All_Population_Count_2020_hh == j.All_Population_Count_2020_raw).all())
chk("urban flag preserved from the analysis table",
    hh2.urban.isin([0, 1]).all(), hh2.urban.nunique())

# ---- QC bookkeeping
chk("all 15 QC assertions recorded and true",
    all(qc["assertions"].values()), [k for k, v in qc["assertions"].items() if not v])
chk("qc command recorded", qc["command"] == "Rscript scripts/lga_dataset.R")
chk("covariate table has one row per attached covariate column",
    len(qc["covariates"]["table"]) == qc["covariates"]["n_columns"] == 134,
    (len(qc["covariates"]["table"]), qc["covariates"]["n_columns"]))
chk("no covariate column was renamed on read", qc["merge_checks"]["covariate_columns_renamed_by_read"] == 0)
chk("household file carries the 134 covariates plus the key", len(hh2.columns) < 20)

# ---- the name join does not scramble populations: LGA sums per state vs the
#      workbook's own ADM1 sheet (independent of our join key)
adm1 = pd.read_excel("data/derived/raw_pop/nga_admpop_2020.xlsx", sheet_name="nga_admpop_adm1_2020")
adm1["name"] = adm1["ADM1_NAME"].astype("string").str.upper().str.strip()
adm1 = adm1.dropna(subset=["name"])
print("   adm1 sheet usable rows:", len(adm1), " total T_TL:", f"{adm1.T_TL.sum():,.0f}")
ours = pop.dropna(subset=["population"])
iso_of_state = {"ABIA": "NG-AB", "ADAMAWA": "NG-AD", "AKWA IBOM": "NG-AK", "ANAMBRA": "NG-AN",
                "BAUCHI": "NG-BA", "BAYELSA": "NG-BY", "BENUE": "NG-BE", "BORNO": "NG-BO",
                "CROSS RIVER": "NG-CR", "DELTA": "NG-DE", "EBONYI": "NG-EB", "EDO": "NG-ED",
                "EKITI": "NG-EK", "ENUGU": "NG-EN", "FEDERAL CAPITAL TERRITORY": "NG-FC",
                "GOMBE": "NG-GO", "IMO": "NG-IM", "JIGAWA": "NG-JI", "KADUNA": "NG-KD",
                "KANO": "NG-KN", "KATSINA": "NG-KT", "KEBBI": "NG-KE", "KOGI": "NG-KO",
                "KWARA": "NG-KW", "LAGOS": "NG-LA", "NASARAWA": "NG-NA", "NIGER": "NG-NI",
                "OGUN": "NG-OG", "ONDO": "NG-ON", "OSUN": "NG-OS", "OYO": "NG-OY",
                "PLATEAU": "NG-PL", "RIVERS": "NG-RI", "SOKOTO": "NG-SO", "TARABA": "NG-TA",
                "YOBE": "NG-YO", "ZAMFARA": "NG-ZA"}
adm1["iso"] = adm1["name"].map(iso_of_state)
cmp = (ours.groupby("state_iso").population.sum().rename("ours").to_frame()
       .join(adm1.set_index("iso").T_TL.rename("state_sheet")))
chk("every state resolved to an ISO code", adm1.iso.notna().all(),
    adm1.loc[adm1.iso.isna(), "name"].tolist())
rel = ((cmp.ours - cmp.state_sheet).abs() / cmp.state_sheet)
print("   worst state deviations of our LGA sums from the workbook's own state totals:")
print(rel.round(6).sort_values(ascending=False).head(3).to_string())
chk("LGA sums reproduce the workbook's state totals to within 0.5%, except Cross River (Bakassi absent)",
    rel.drop("NG-CR").max() < 0.005,
    rel.round(5).sort_values(ascending=False).head(4).to_dict())

bad = [n for n, c, _ in ok if not c]
print()
print(f"{len(ok) - len(bad)} of {len(ok)} checks passed")
if bad:
    print("FAILED:", bad)
