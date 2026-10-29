# Run notes: full NM run, 1979–2025

Run on 2026-10-29. Windows, R 4.6.1, 8 logical cores, 64 GB RAM, single-process `targets::tar_make()`.

## Downloads (one-time, cached)

| Input | Volume | Time |
|---|---|---|
| gridMET, 6 vars × 47 years (OPeNDAP subset) | 282 files, 3.2 GB | ~8 s per var-year, ~40 min serial |
| LANDFIRE, 55 one-degree tiles × 3 LFPS requests | 165 files, 1.1 GB | 15–70 s per request; ~35 min using `tools/prefetch_landfire.R` in 4 parallel processes |
| Fireshed Registry 4th ed. | 99 MB zip | < 1 min |

## Compute (full rebuild, downloads cached)

| Stage | Time |
|---|---|
| NFDRS FM1/FM10, 47 years | 7.5 min |
| LANDFIRE 30 m processing (`lf_derived`, ~673M cells) | 26 min |
| Daily classification, 47 years | 4.3 min |
| Project rollup + parquet | 1.2 min |
| Burn-day counts | 4.5 min |
| Synchrony, exceedance, downstream, tables, figures | ~1.5 min |
| **Total** | **~49 min** |

Changing `years` in `config/pipeline.yml` does not rerun the 30 m LANDFIRE step (config is split into per-section targets).

## Disk use

| Path | Size |
|---|---|
| `data/raw/gridmet` | 3.2 GB |
| `data/raw/landfire` | 1.1 GB |
| `data/processed` | 2.4 GB (NFDRS 2.5 GB-equivalent rasters compress; burn-day rasters 25 MB; `rx_share_daily.parquet` 41 MB) |
| `_targets` | 70 MB |

## Completeness checks

- 47 years, 17,167 days, 1979-01-01 to 2025-12-31.
- `rx_share_daily.parquet`: 17.1M rows, 996 units, every unit has every day, no NA, values in [0, 1].
- 996 units receive an rx_share (their polygons overlap gridMET cells with treatable area); 828 of these have treatable 30 m pixels inside their own boundary and a non-zero AFN.

## Notes

- `terra::patches()` on the full 30 m mask ran > 30 min on one core without finishing; replaced by `terra::sieve()` + AND with the input (matched patches to 2e-6 of cells on a 19M-cell test window, ~37× faster).
- LANDFIRE LFPS v2 requires an email (`LANDFIRE_EMAIL` env var).
