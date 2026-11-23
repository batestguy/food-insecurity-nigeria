# Data in this workspace

Two datasets live here. They have different rules and must not be confused.

## 1. `restricted/dhs-2024/` — NDHS 2024 microdata (LICENSED, NOT PUBLIC)

Copied from `D:\Curb Cut Disability\data\restricted\dhs-2024` on 2026-11-22. Both files were
SHA-256 verified against the original manifest after copying.

| File | Bytes | SHA-256 |
|---|---|---|
| `hr/NGHR8BFL.dta` | 175011845 | c5aea8f61cf74ca5dd83aafd9a0f59f6c46555da81364d3e094f987c5aa98fb0 |
| `pr/NGPR8BFL.dta` | 87072364 | 7e205df03b75a3b1e1ae30e87040c7afd240dfed903fc62898c76574be1c4190 |

**Terms, from the DHS project registration:**
- Registered project: "Curb Cut: disability prevalence and poverty in Nigeria" (survey and GPS access
  approved 2026-10-16). The account holder and registration number are held privately, not here.
- **No redistribution**, directly or inside any tool or dashboard. These files must never enter a
  repository, a site, a package, a container image, or an appendix.
- No attempt at re-identification; the cluster coordinates are displaced by design.
- **A PDF of every publication must be sent to references@dhsprogram.com.**
- Use is scoped to the registered project. A new paper's outcome must sit inside that description,
  or the registration must be amended first. Disability prevalence is inside it; a food-insecurity
  paper would need checking before it starts.

`ge/` is empty: the cluster coordinates (`NGGE8AFL.ZIP`) have not been downloaded. Without them no
spatial model below state level is possible.

## 2. `public/` — open inputs

- `public/boundaries/geoBoundaries-NGA-ADM1_simplified.geojson` — state polygons, CC BY 4.0.
- `public/dhs/dhs2024_state.csv`, `dhs2024_national.csv` — the **direct** survey estimates already
  built in the Curb Cut project. These are derived aggregates, not microdata.

## 3. `derived/` — results already computed elsewhere

- `moran_global.csv` — global Moran's I for eight disability measures at state level.
- `lisa_disability3_18plus.csv`, `neighbours.csv` (172 directed links, 86 pairs, one component).
- `summary.json`, `README.md` — the full record of that analysis.

## The CPI panel

`panel/` and `raw/nbs/` hold the NBS state-month price panel built earlier: 81 of 82 months,
2020-01 to 2026-10, arithmetic-verified. It is unrelated to the DHS work and remains usable as an
area-level covariate. See `AGENTS.md` for its known defects.
