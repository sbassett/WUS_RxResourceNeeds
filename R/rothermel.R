# Rate of spread and flame length under prescription conditions, modelled
# ASPATIALLY: one Rothermel (1972) calculation per fuel model x scenario x
# live-moisture scenario x slope, saved as a small lookup table and later
# joined to the fuel model map (R/fire_behavior.R).
#
# Engine: R package `Rothermel` (Vacchiano & Ascoli), which implements
# Rothermel (1972) with the Albini (1976) and Andrews et al. (2013)
# corrections and holds the Scott & Burgan (2005) fuel models. It matches the
# SW Coordination Center reference tables for Anderson fuel model 1 within
# ~4% wherever the traditional wind limit does not bind (see tests).
# Flame length is computed here with Byram (1959) from the package's
# reaction intensity, and matches the same tables within ~3%.

ch_per_m_min <- 60 / 20.1168      # chains per hour per (m/min); 1 chain = 20.1168 m
ft_per_m <- 3.28084

#' Scott & Burgan / Albini fuel model table from the Rothermel package
sfm_table <- function() {
  if (!requireNamespace("Rothermel", quietly = TRUE)) {
    stop("package 'Rothermel' is required (renv::restore())")
  }
  e <- new.env()
  utils::data("SFM_metric", package = "Rothermel", envir = e)
  e$SFM_metric
}

#' One Rothermel run for a named fuel model
#'
#' @param model SFM_metric row name (e.g. "GR2")
#' @param moist numeric(5): 1-hr, 10-hr, 100-hr, live herb, live woody (%)
#' @param u_kmh mid-flame wind speed (km/h)
#' @param slope_pct slope (%)
#' @return list(ros_m_min, reaction_kw_m2, sigma, fireline_kw_m, flame_m)
rothermel_run <- function(model, moist, u_kmh, slope_pct, sfm = sfm_table()) {
  f <- sfm[model, ]
  if (nrow(f) != 1 || is.na(f$Fuel_Bed_Depth)) stop("unknown fuel model: ", model)
  w <- as.numeric(f[, c("Load_1h", "Load_10h", "Load_100h", "Load_Live_Herb", "Load_Live_Woody")])
  s <- as.numeric(f[, c("SA/V_1h", "SA/V_10h", "SA/V_100h", "SA/V_Live_Herb", "SA/V_Live_Woody")])
  h <- as.numeric(f[, c("Heat_1h", "Heat_10h", "Heat_100h", "Heat_Live_Herb", "Heat_Live_Woody")])
  r <- Rothermel::ros(as.character(f$Fuel_Model_Type), w, s, f$Fuel_Bed_Depth,
                      f$Mx_dead, h, moist, u_kmh, slope_pct)
  ros <- r[[15]]; ir <- r[[10]]; sig <- r[[4]]
  if (is.na(ros) || ros <= 0) {
    ros <- 0; ib <- 0; fl <- 0
  } else {
    tr <- 1259.84 / sig               # flame residence time (min) = 384 / sigma[1/ft]
    ib <- ir * ros * tr               # Byram fireline intensity (kW/m)
    fl <- 0.0775 * ib^0.46            # Byram flame length (m)
  }
  list(ros_m_min = ros, reaction_kw_m2 = ir, sigma = sig, fireline_kw_m = ib, flame_m = fl)
}

#' Prescription scenarios from the burn-day thresholds table
#'
#' cool = slowest end of the window (highest dead fuel moisture, lowest
#' wind); hot = fastest end (lowest moisture, highest wind); mid = midpoints.
#' Mid-flame wind is converted from m/s to km/h.
rx_scenarios <- function(thresholds) {
  need <- c("fm1", "fm10", "fm100", "midflame")
  g <- function(stat, col) {
    v <- thresholds[[col]][thresholds$statistic == stat]
    if (length(v) != 1 || is.na(v)) {
      stop("scenario needs a finite '", col, "' bound for threshold '", stat, "'")
    }
    v
  }
  sc <- data.frame(scenario = c("cool", "mid", "hot"), stringsAsFactors = FALSE)
  for (st in c("fm1", "fm10", "fm100")) {
    lo <- g(st, "min"); hi <- g(st, "max")
    sc[[st]] <- c(hi, (lo + hi) / 2, lo)     # cool = wettest, hot = driest
  }
  wlo <- g("midflame", "min"); whi <- g("midflame", "max")
  sc$wind_ms <- c(wlo, (wlo + whi) / 2, whi)
  sc$wind_kmh <- sc$wind_ms * 3.6
  sc
}

#' Fuel x scenario x live-moisture x slope lookup
#'
#' @param thresholds from load_thresholds()
#' @param waf_table fuel model table (code, model, burnable)
#' @param fb_cfg config `fire_behavior` section
#' @return data.frame(code, model, scenario, live, slope_pct, wind_kmh,
#'   ros_chhr, flame_ft, fireline_kw_m)
rothermel_lookup <- function(thresholds, waf_table, fb_cfg) {
  sc <- rx_scenarios(thresholds)
  live <- fb_cfg$live_scenarios
  slopes <- unlist(fb_cfg$slopes_pct)
  fm <- waf_table[waf_table$burnable, c("code", "model")]
  sfm <- sfm_table()
  miss <- setdiff(fm$model, rownames(sfm))
  if (length(miss)) stop("fuel models not in Rothermel::SFM_metric: ", paste(miss, collapse = ", "))
  g <- expand.grid(i = seq_len(nrow(fm)), scenario = sc$scenario, live = names(live),
                   slope_pct = slopes, stringsAsFactors = FALSE)
  out <- data.frame(code = fm$code[g$i], model = fm$model[g$i], scenario = g$scenario,
                    live = g$live, slope_pct = g$slope_pct, stringsAsFactors = FALSE)
  out$wind_kmh <- sc$wind_kmh[match(out$scenario, sc$scenario)]
  res <- vapply(seq_len(nrow(out)), function(k) {
    s <- sc[match(out$scenario[k], sc$scenario), ]
    lv <- live[[out$live[k]]]
    r <- rothermel_run(out$model[k], c(s$fm1, s$fm10, s$fm100, lv$herb, lv$woody),
                       out$wind_kmh[k], out$slope_pct[k], sfm)
    c(r$ros_m_min, r$flame_m, r$fireline_kw_m)
  }, numeric(3))
  out$ros_chhr <- res[1, ] * ch_per_m_min
  out$flame_ft <- res[2, ] * ft_per_m
  out$fireline_kw_m <- res[3, ]
  out[order(out$code, out$scenario, out$live, out$slope_pct), ]
}

#' Matrices (fuel model x slope) for one scenario / live-moisture scenario
fb_table <- function(lookup, scenario, live, what = c("ros_chhr", "flame_ft")) {
  what <- match.arg(what)
  d <- lookup[lookup$scenario == scenario & lookup$live == live, ]
  if (nrow(d) == 0) stop("no lookup rows for scenario '", scenario, "', live '", live, "'")
  codes <- sort(unique(d$code)); slopes <- sort(unique(d$slope_pct))
  m <- matrix(NA_real_, length(codes), length(slopes))
  m[cbind(match(d$code, codes), match(d$slope_pct, slopes))] <- d[[what]]
  list(codes = codes, slopes = slopes, m = m)
}

#' Interpolate a lookup matrix at fuel model codes and slopes (%)
#'
#' Linear interpolation between slope bins; slopes are clamped to the table
#' range. Codes not in the table (e.g. non-burnable models) give NA, and a
#' missing slope is treated as flat.
interp_fb <- function(code, slope_pct, tab) {
  i <- match(code, tab$codes)
  s <- slope_pct; s[is.na(s)] <- 0
  s <- pmin(pmax(s, min(tab$slopes)), max(tab$slopes))
  j <- findInterval(s, tab$slopes, rightmost.closed = TRUE, all.inside = TRUE)
  f <- (s - tab$slopes[j]) / (tab$slopes[j + 1] - tab$slopes[j])
  lo <- tab$m[cbind(i, j)]; hi <- tab$m[cbind(i, j + 1L)]
  out <- (1 - f) * lo + f * hi
  out[is.na(i)] <- NA_real_
  out
}

#' Flame length class (SWCC convention): 1 = 0-4 ft, 2 = 4-8 ft, 3 = > 8 ft
flame_class <- function(flame_ft, breaks = c(4, 8)) {
  findInterval(flame_ft, breaks, left.open = TRUE) + 1L
}
