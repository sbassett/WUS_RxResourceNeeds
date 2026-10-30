# targets pipeline: NM Rx resource needs.
# Run with targets::tar_make(); inspect with targets::tar_visnetwork().
library(targets)
library(tarchetypes)

tar_option_set(
  packages = c("terra", "sf", "Matrix"),
  format = "rds",
  error = "stop",
  memory = "transient",
  garbage_collection = TRUE
)

tar_source("R")

list(
  # ---- configuration ------------------------------------------------------
  tar_target(cfg_file, "config/pipeline.yml", format = "file"),
  tar_target(cfg, read_pipeline_config(cfg_file)),
  # Per-section config targets: a change to one section (e.g. years) only
  # invalidates the stages that use it.
  tar_target(cfg_years, cfg$years),
  tar_target(cfg_year_list, cfg$year_list),
  tar_target(cfg_aoi, cfg$aoi),
  tar_target(cfg_crs, cfg$crs),
  tar_target(cfg_units, cfg$units),
  tar_target(cfg_gridmet, cfg$gridmet),
  tar_target(cfg_nfdrs, cfg$nfdrs),
  tar_target(cfg_wind, cfg$wind),
  tar_target(cfg_thresholds, cfg$thresholds),
  tar_target(cfg_landfire, cfg$landfire),
  tar_target(cfg_target_area, cfg$target_area),
  tar_target(cfg_burn_days, cfg$burn_days),
  tar_target(cfg_rollup, cfg$rollup),
  tar_target(cfg_summaries, cfg$summaries),
  tar_target(cfg_results, cfg$results),
  tar_target(st1_file, "config/swain2023_ST1.csv", format = "file"),
  tar_target(thr_file, "config/burn_thresholds.yml", format = "file"),
  tar_target(thresholds, load_thresholds(thr_file, cfg_thresholds$plan_set)),
  tar_target(params_file, "config/downstream_params.yml", format = "file"),
  tar_target(params, read_downstream_params(params_file)),
  tar_target(waf_table_file, "config/waf_fbfm40.csv", format = "file"),
  tar_target(waf_table, read_waf_table(waf_table_file)),
  tar_target(treatable_bps_file, "config/treatable_bps.csv", format = "file"),
  tar_target(treatable_evt_file, "config/treatable_evt_phys.csv", format = "file"),

  # ---- study area and units ------------------------------------------------
  tar_target(state, get_state_boundary(cfg_aoi$state_abbr, cfg_crs)),
  tar_target(projects, build_project_areas(cfg_units, state, cfg_crs)),
  tar_target(projects_gpkg,
             { write_project_areas(projects, cfg_units$out, cfg_units$out_layer)
               cfg_units$out },
             format = "file"),
  tar_target(bbox, units_lonlat_bbox(projects, cfg_aoi$buffer_km)),

  # ---- gridMET -------------------------------------------------------------
  tar_target(gm_var, cfg_gridmet$vars),
  tar_target(gm_year, cfg_year_list),
  tar_target(gm_files,
             fetch_gridmet(gm_var, gm_year, bbox, cfg_gridmet$url_template,
                           cfg_gridmet$cache_dir),
             pattern = cross(gm_var, gm_year), format = "file"),
  # grid template from one fixed var-year so it doesn't change with `years`
  tar_target(gm_template_file,
             write_gridmet_template(
               fetch_gridmet("tmmx", 2020, bbox, cfg_gridmet$url_template,
                             cfg_gridmet$cache_dir),
               "data/processed/gridmet_template.tif"),
             format = "file"),

  # ---- NFDRS fuel moisture -------------------------------------------------
  tar_target(nfdrs_files,
             compute_nfdrs_year(gridmet_year_files(gm_files, gm_year), gm_year,
                                cfg_nfdrs),
             pattern = map(gm_year), format = "file"),

  # ---- LANDFIRE ------------------------------------------------------------
  tar_target(lf_tiles,
             tiles_intersecting(make_lonlat_tiles(bbox, cfg_landfire$tile_deg), projects),
             iteration = "list"),
  tar_target(lf_fuels_tif,
             fetch_landfire_tile(lf_tiles, "fuels", cfg_landfire$products,
                                 cfg_landfire$dir, cfg_landfire$resolution),
             pattern = map(lf_tiles), format = "file"),
  tar_target(lf_evt_tif,
             fetch_landfire_tile(lf_tiles, "evt", cfg_landfire$products,
                                 cfg_landfire$dir, cfg_landfire$resolution),
             pattern = map(lf_tiles), format = "file"),
  tar_target(lf_bps_tif,
             fetch_landfire_tile(lf_tiles, "bps", cfg_landfire$products,
                                 cfg_landfire$dir, cfg_landfire$resolution),
             pattern = map(lf_tiles), format = "file"),
  tar_target(evt_attr, landfire_attributes(lf_evt_tif)),
  tar_target(bps_attr, landfire_attributes(lf_bps_tif)),
  tar_target(fuels_bands, fuels_band_names(lf_fuels_tif[1], cfg_landfire$products)),
  tar_target(fuels_vrt, landfire_vrt(lf_fuels_tif, file.path(cfg_landfire$dir, "fuels.vrt")),
             format = "file"),
  tar_target(evt_vrt, landfire_vrt(lf_evt_tif, file.path(cfg_landfire$dir, "evt.vrt")),
             format = "file"),
  tar_target(bps_vrt, landfire_vrt(lf_bps_tif, file.path(cfg_landfire$dir, "bps.vrt")),
             format = "file"),
  tar_target(lf_derived,
             { force(treatable_bps_file); force(treatable_evt_file)
               build_landfire_derived(fuels_vrt, evt_vrt, bps_vrt, evt_attr, bps_attr,
                                      fuels_bands, gm_template_file, projects,
                                      cfg_target_area, waf_table, cfg_wind) }),
  tar_target(treatable_frac_file, lf_derived$treatable_frac, format = "file"),
  tar_target(waf_file, lf_derived$waf, format = "file"),
  tar_target(project_stats, utils::read.csv(lf_derived$project_stats)),

  # ---- burn-day classification --------------------------------------------
  tar_target(inrx_files,
             classify_rx_year(gm_year, gridmet_year_files(gm_files, gm_year),
                              nfdrs_year_files(nfdrs_files, gm_year), waf_file,
                              thresholds, cfg_wind, cfg_burn_days$out_dir),
             pattern = map(gm_year), format = "file"),

  # ---- project-area rollup -------------------------------------------------
  tar_target(weights, project_cell_weights(projects, treatable_frac_file)),
  tar_target(rx_share_parts, rx_share_year(inrx_files, weights),
             pattern = map(inrx_files), format = "parquet"),
  tar_target(rx_share_file, write_rx_share(list(rx_share_parts), cfg_rollup$out),
             format = "file"),
  tar_target(daily, as.data.frame(arrow::read_parquet(rx_share_file)),
             format = "parquet"),
  tar_target(counts, burn_day_counts(daily, cfg_rollup$burn_day_share,
                                     cfg_rollup$n_weeks)),

  # ---- predictability and synchrony ---------------------------------------
  tar_target(exceedance, weekly_exceedance(counts$weekly, unlist(cfg_summaries$exceedance_k))),
  tar_target(variability, burn_day_variability(counts$annual)),
  tar_target(burn_matrix, burn_day_matrix(daily, cfg_rollup$burn_day_share)),
  tar_target(synchrony, synchrony_table(daily, cfg_rollup$burn_day_share,
                                        cfg_rollup$n_weeks), format = "parquet"),
  tar_target(synchrony_file,
             write_parquet_file(synchrony, "data/processed/synchrony_pairs.parquet"),
             format = "file"),

  # ---- downstream ------------------------------------------------------------
  tar_target(rx_target, compute_rx_target(project_stats, variability)),
  tar_target(units_dist, unit_size_complexity(rx_target, params)),
  tar_target(units_fired, line_production(firing_method(units_dist, project_stats, params),
                                          params)),
  tar_target(fire_matrix, firing_matrix(params)),
  tar_target(resources, resource_mix(units_fired, params)),
  tar_target(state_demand, daily_state_demand(burn_matrix, resources, rx_target)),
  tar_target(state_summary, summarise_state_demand(state_demand, burn_matrix,
                                                   cfg_rollup$n_weeks)),

  # ---- tables --------------------------------------------------------------
  tar_target(tables, {
    d <- cfg_results$tables
    c(write_table_csv(counts$annual, d, "annual_burn_days.csv"),
      write_table_csv(variability, d, "burn_day_variability.csv"),
      write_table_csv(exceedance, d, "weekly_exceedance.csv"),
      write_table_csv(rx_target, d, "rx_target_afn_bfn.csv"),
      write_table_csv(units_fired, d, "unit_size_complexity_firing_STUB.csv"),
      write_table_csv(fire_matrix, d, "firing_method_matrix_STUB.csv"),
      write_table_csv(resources, d, "resource_days_by_project_STUB.csv"),
      write_table_csv(state_summary$weekly, d, "state_weekly_need_STUB.csv"),
      write_table_csv(state_summary$annual, d, "state_annual_need_STUB.csv"),
      write_table_csv(state_summary$peak_season, d, "state_peak_season_STUB.csv"),
      write_table_csv(thresholds, d, "thresholds_applied.csv"))
  }, format = "file"),

  # ---- figures -------------------------------------------------------------
  tar_target(demo_date, sprintf("%d-07-15", cfg_years$start)),
  tar_target(example_project, pick_example_project(rx_target)),
  tar_target(figures, {
    o <- cfg_results$figures
    c(fig_project_areas(projects, state, file.path(o, "project_areas.png")),
      fig_weather_day(gridmet_year_files(gm_files, cfg_years$start), demo_date, state, o),
      fig_fm1(nfdrs_year_files(nfdrs_files, cfg_years$start)[["fm1"]],
              gridmet_year_files(gm_files, cfg_years$start), demo_date, state, o),
      fig_waf(waf_file, state, o),
      fig_inrx_days(inrx_files[1], state, o),
      fig_inrx_climatology(inrx_files, state, o),
      fig_burn_day_trend(counts$annual, o),
      fig_treatable(treatable_frac_file, state, o),
      fig_project_choropleth(projects, rx_target, "treatable_ac",
                             "Treatable (target) acres per subfireshed", "acres",
                             file.path(o, "treatable_acres.png")),
      fig_project_choropleth(projects, variability, "mean_bd",
                             "Mean annual burn days (rx_share >= X)", "days",
                             file.path(o, "mean_burn_days.png")),
      fig_project_choropleth(projects, variability, "cv_bd",
                             "Interannual CV of burn days", "CV",
                             file.path(o, "burn_days_cv.png")),
      fig_project_choropleth(projects, rx_target, "afn_ac",
                             "Annual Rx need (AFN = TA / MFRI)", "ac/yr",
                             file.path(o, "afn.png")),
      fig_project_choropleth(projects, rx_target, "bfn_typical",
                             "Burn-day fire need (BFN = AFN / burn days)", "ac/burn day",
                             file.path(o, "bfn.png"), "log10"),
      fig_rx_share_ts(daily, counts$annual, example_project, o),
      fig_exceedance(exceedance, example_project, o),
      fig_synchrony(synchrony, projects, o),
      fig_state_weekly(state_summary$weekly, o))
  }, format = "file"),

  # ---- report ----------------------------------------------------------------
  tar_target(report_rmd, "docs/report.Rmd", format = "file"),
  tar_target(report, render_report(report_rmd, "docs/report.md",
                                   list(tables, figures)),
             format = "file")
)
