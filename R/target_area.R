# Target (treatable) area at 30 m and its aggregation to the gridMET grid
# and to project areas.

pixel_acres <- function(res_m = 30) res_m^2 / 4046.8564224

#' Read a treatable crosswalk and check it covers every key in the data
#'
#' Stops (rather than silently dropping classes) if the data contain keys
#' with no row, or rows without a TRUE/FALSE decision.
read_crosswalk <- function(path, key, data_keys) {
  x <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  if (!all(c(key, "treatable") %in% names(x))) {
    stop(path, " must have columns `", key, "` and `treatable`")
  }
  x$treatable <- as.logical(x$treatable)
  if (anyNA(x$treatable)) {
    stop(path, ": `treatable` must be TRUE or FALSE for every row")
  }
  if (anyDuplicated(x[[key]])) stop(path, ": duplicate ", key)
  miss <- setdiff(unique(data_keys), x[[key]])
  if (length(miss)) {
    stop(path, " has no row for ", length(miss), " ", key, " value(s) present in ",
         "the data: ", paste(utils::head(miss, 10), collapse = ", "),
         ". Run `Rscript tools/build_treatable_crosswalk.R` and review the new rows.")
  }
  x
}

#' Raster values treated as treatable from the BPS and EVT crosswalks
#'
#' BPS rows are keyed on BPS_CODE (consistent across map zones); a raster
#' Value is treatable when its BPS_CODE is. EVT rows are keyed on EVT_PHYS.
#' Returns tables of treatable raster Values for each layer.
treatable_codes <- function(bps_attr, evt_attr, bps_file, evt_file) {
  b <- bps_attr[bps_attr$BPS_CODE > 0, ]
  bx <- read_crosswalk(bps_file, "BPS_CODE", b$BPS_CODE)
  bok <- b[b$BPS_CODE %in% bx$BPS_CODE[bx$treatable], ]
  ex <- read_crosswalk(evt_file, "EVT_PHYS", evt_attr$EVT_PHYS)
  eok <- evt_attr[evt_attr$EVT_PHYS %in% ex$EVT_PHYS[ex$treatable], ]
  list(
    bps = data.frame(code = bok$Value, BPS_CODE = bok$BPS_CODE,
                     BPS_NAME = bok$BPS_NAME, stringsAsFactors = FALSE),
    evt = data.frame(code = eok$Value, EVT_PHYS = eok$EVT_PHYS,
                     EVT_NAME = eok$EVT_NAME, stringsAsFactors = FALSE)
  )
}

#' Pure-matrix helpers (testable without rasters) -------------------------

#' Apply slope/wilderness filters to a 0/1 treatable vector
apply_treatable_filters <- function(treat, slope_deg = NULL, max_slope_pct = NULL,
                                    wilderness = NULL) {
  out <- treat
  if (!is.null(slope_deg) && !is.null(max_slope_pct)) {
    thr <- atan(max_slope_pct / 100) * 180 / pi
    out[!is.na(slope_deg) & slope_deg > thr] <- 0L
  }
  if (!is.null(wilderness)) out[!is.na(wilderness) & wilderness == 1] <- 0L
  out
}

min_patch_cells <- function(acres, res_m = 30) ceiling(acres / pixel_acres(res_m))

#' Remove treatable patches (8-connected) smaller than min_cells
#'
#' Uses GDAL's sieve filter (terra::sieve), which merges polygons below the
#' threshold into their largest neighbour. Sieving also fills small
#' non-treatable holes, so the result is ANDed with the input mask: only
#' removals are kept. On a 19M-cell NM test window this matched
#' terra::patches() to within 2e-6 of cells and ran ~37x faster.
remove_small_patches <- function(treat_r, min_cells, filename = "") {
  s <- terra::sieve(treat_r, threshold = min_cells, directions = 8)
  terra::ifel(is.na(treat_r), NA, terra::ifel(s == 1 & treat_r == 1, 1L, 0L),
              filename = filename, overwrite = TRUE, datatype = "INT1U")
}

#' Aggregate a (zone, treat, fbfm) frequency table to per-zone modal fuel
#' model: modal burnable model among treatable pixels, falling back to all
#' burnable pixels. Returns data.frame(zone, fbfm, from_treatable).
modal_fuel_by_zone <- function(fq, burnable_codes) {
  fq <- fq[fq$fbfm %in% burnable_codes, ]
  pick <- function(d) {
    d <- d[order(d$zone, -d$count, d$fbfm), ]
    d[!duplicated(d$zone), c("zone", "fbfm")]
  }
  tr <- pick(stats::aggregate(count ~ zone + fbfm, fq[fq$treat == 1, ], sum))
  al <- pick(stats::aggregate(count ~ zone + fbfm, fq, sum))
  tr$from_treatable <- TRUE
  fb <- al[!al$zone %in% tr$zone, ]
  fb$from_treatable <- rep(FALSE, nrow(fb))
  out <- rbind(tr, fb)
  out[order(out$zone), ]
}

#' Full 30 m processing ------------------------------------------------------
#'
#' @return list of output file paths and tables
build_landfire_derived <- function(fuels_vrt, evt_vrt, bps_vrt, evt_attr, bps_attr,
                                   band_names, gm_template_file, projects,
                                   ta_cfg, waf_table, wind_cfg) {
  out_dir <- ensure_dir(ta_cfg$out_dir)
  tmp <- ensure_dir(file.path(out_dir, "tmp"))
  terra::terraOptions(tempdir = tmp, memfrac = 0.6, progress = 0)
  on.exit(unlink(list.files(tmp, full.names = TRUE)), add = TRUE)
  of <- function(x) file.path(out_dir, x)
  g1 <- c("COMPRESS=DEFLATE")

  fuels <- terra::rast(fuels_vrt)
  names(fuels) <- band_names
  evt <- terra::rast(evt_vrt)
  bps <- terra::rast(bps_vrt)
  align <- function(r, nm) {
    if (terra::compareGeom(r, fuels, stopOnError = FALSE)) return(r)
    terra::resample(r, fuels, method = "near",
                    filename = of(paste0("tmp/", nm, "_aligned.tif")), overwrite = TRUE)
  }
  evt <- align(evt, "evt")
  bps <- align(bps, "bps")

  # --- treatable mask ---------------------------------------------------
  # historical dry forest (BPS) AND currently burnable vegetation (EVT)
  codes <- treatable_codes(bps_attr, evt_attr, ta_cfg$bps_file, ta_cfg$evt_file)
  utils::write.csv(codes$bps, of("treatable_bps_codes.csv"), row.names = FALSE)
  utils::write.csv(codes$evt, of("treatable_evt_codes.csv"), row.names = FALSE)
  treat <- terra::classify(bps, cbind(codes$bps$code, 1L), others = 0L) *
    terra::classify(evt, cbind(codes$evt$code, 1L), others = 0L)
  if (isTRUE(ta_cfg$slope$enabled)) {
    thr <- atan(ta_cfg$slope$max_pct / 100) * 180 / pi
    treat <- terra::ifel(fuels[["slope"]] > thr, 0L, treat)
  }
  if (isTRUE(ta_cfg$wilderness$enabled)) {
    if (!file.exists(ta_cfg$wilderness$path)) {
      stop("wilderness exclusion enabled but layer not found: ", ta_cfg$wilderness$path)
    }
    w <- sf::st_transform(sf::st_read(ta_cfg$wilderness$path, quiet = TRUE), 5070)
    wr <- terra::rasterize(terra::vect(w), treat, field = 1, background = 0)
    treat <- terra::ifel(wr == 1, 0L, treat)
  }
  treat <- terra::writeRaster(treat, of("tmp/treat_pre.tif"), overwrite = TRUE,
                              datatype = "INT1U", gdal = g1)
  if (isTRUE(ta_cfg$min_patch$enabled)) {
    treat <- remove_small_patches(treat, min_patch_cells(ta_cfg$min_patch$acres),
                                  filename = of("tmp/treat_patch.tif"))
  }
  treat_f <- of("treatable_30m.tif")
  treat <- terra::writeRaster(treat, treat_f, overwrite = TRUE, datatype = "INT1U",
                              gdal = g1)

  # --- zones: gridMET cell id on the 30 m grid ----------------------------
  gm <- terra::rast(gm_template_file)
  zone <- terra::project(gm, treat, method = "near", filename = of("tmp/zone.tif"),
                         overwrite = TRUE, datatype = "INT4U")

  # treatable fraction per gridMET cell
  zf <- terra::zonal(c(treat, terra::ifel(is.na(treat), NA, 1L)), zone,
                     fun = "sum", na.rm = TRUE)
  names(zf) <- c("zone", "treat_n", "n")
  frac <- terra::rast(gm); terra::values(frac) <- NA_real_
  frac[zf$zone] <- zf$treat_n / zf$n
  names(frac) <- "treatable_frac"
  frac_f <- of("treatable_frac_gridmet.tif")
  terra::writeRaster(frac, frac_f, overwrite = TRUE)

  # modal fuel model per gridMET cell
  burn_codes <- waf_table$code[waf_table$burnable]
  # integer key (exceeds float32 precision, so force INT4U on disk)
  key <- terra::lapp(c(zone, treat, fuels[["fbfm40"]]),
                     fun = function(z, t, f) z * 10000 + t * 1000 + f,
                     filename = of("tmp/key.tif"), overwrite = TRUE,
                     wopt = list(datatype = "INT4U"))
  fq <- terra::freq(key)
  fq <- data.frame(zone = fq$value %/% 10000,
                   treat = (fq$value %% 10000) %/% 1000,
                   fbfm = fq$value %% 1000, count = fq$count)
  modal <- modal_fuel_by_zone(fq, burn_codes)

  # canopy means over treatable-burnable and all-burnable pixels
  burnable <- terra::classify(fuels[["fbfm40"]], cbind(burn_codes, 1L), others = NA)
  can <- fuels[[c("cc", "ch", "cbh")]] * burnable
  m_all <- terra::zonal(can, zone, fun = "mean", na.rm = TRUE)
  m_tr <- terra::zonal(terra::mask(can, treat, maskvalues = c(0, NA)), zone,
                       fun = "mean", na.rm = TRUE)
  names(m_all) <- names(m_tr) <- c("zone", "cc", "ch", "cbh")
  mm <- merge(modal, m_tr, by = "zone", all.x = TRUE)
  use_all <- !mm$from_treatable | is.na(mm$cc)
  ia <- match(mm$zone[use_all], m_all$zone)
  mm[use_all, c("cc", "ch", "cbh")] <- m_all[ia, c("cc", "ch", "cbh")]
  mm$depth_ft <- waf_table$fuel_bed_depth_ft[match(mm$fbfm, waf_table$code)]
  # LANDFIRE CH and CBH are stored as meters x 10
  mm$ch_ft <- m_to_ft(mm$ch / 10)
  mm$cbh_ft <- m_to_ft(mm$cbh / 10)
  mm$waf <- waf_select(mm$depth_ft, mm$cc, mm$ch_ft, mm$cbh_ft,
                       wind_cfg$sheltered_min_f, wind_cfg$sheltered_min_ch_ft)
  mm$sheltered <- crown_fill_portion(mm$cc, mm$ch_ft, mm$cbh_ft) >= wind_cfg$sheltered_min_f &
    mm$ch_ft >= wind_cfg$sheltered_min_ch_ft
  utils::write.csv(mm, of("fuel_by_gridmet_cell.csv"), row.names = FALSE)
  waf <- terra::rast(gm); terra::values(waf) <- NA_real_
  waf[mm$zone] <- mm$waf
  fbr <- terra::rast(gm); terra::values(fbr) <- NA_real_
  fbr[mm$zone] <- mm$fbfm
  wr <- c(waf, fbr); names(wr) <- c("waf", "fbfm40")
  waf_f <- of("waf_gridmet.tif")
  terra::writeRaster(wr, waf_f, overwrite = TRUE)

  # --- project-area stats at 30 m ------------------------------------------
  pv <- terra::vect(sf::st_transform(projects, terra::crs(treat)))
  proj <- terra::rasterize(pv, treat, field = "project_id",
                           filename = of("tmp/proj.tif"), overwrite = TRUE,
                           wopt = list(datatype = "INT4U"))
  fri <- bps_attr$FRI_ALLFIR
  inv <- ifelse(is.na(fri) | fri <= 0, NA_real_, 1 / fri)
  inv_mfri <- terra::classify(bps, cbind(bps_attr$Value, inv), others = NA)
  heavy_codes <- waf_table$code[waf_table$heavy_fuel]
  heavy <- terra::classify(fuels[["fbfm40"]], cbind(heavy_codes, 1L), others = 0L)
  treat_na <- terra::mask(treat, treat, maskvalues = 0)   # 1 or NA
  stk <- c(treat, treat * inv_mfri, treat * heavy, fuels[["slope"]] * treat_na,
           treat_na * terra::ifel(is.na(inv_mfri), 1L, 0L))
  names(stk) <- c("treat_n", "inv_mfri_sum", "heavy_n", "slope_sum", "no_fri_n")
  ps <- terra::zonal(stk, proj, fun = "sum", na.rm = TRUE)
  names(ps)[1] <- "project_id"
  pa <- pixel_acres(terra::res(treat)[1])
  stats <- data.frame(
    project_id = ps$project_id,
    treatable_ac = ps$treat_n * pa,
    afn_ac = ps$inv_mfri_sum * pa,
    heavy_fuel_share = ifelse(ps$treat_n > 0, ps$heavy_n / ps$treat_n, NA),
    mean_slope_deg = ifelse(ps$treat_n > 0, ps$slope_sum / ps$treat_n, NA),
    no_fri_share = ifelse(ps$treat_n > 0, ps$no_fri_n / ps$treat_n, NA)
  )
  stats <- merge(sf::st_drop_geometry(projects)[, "project_id", drop = FALSE],
                 stats, by = "project_id", all.x = TRUE)
  stats$treatable_ac[is.na(stats$treatable_ac)] <- 0
  stats_f <- of("project_landfire_stats.csv")
  utils::write.csv(stats, stats_f, row.names = FALSE)

  list(treatable_30m = treat_f, treatable_frac = frac_f, waf = waf_f,
       fuel_table = of("fuel_by_gridmet_cell.csv"), project_stats = stats_f,
       treatable_bps_codes = of("treatable_bps_codes.csv"),
       treatable_evt_codes = of("treatable_evt_codes.csv"))
}
