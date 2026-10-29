# Configuration loading, validation, and unit conversion helpers.

required_pipeline_keys <- c("years", "aoi", "crs", "units", "gridmet", "nfdrs",
                            "wind", "thresholds", "landfire", "target_area",
                            "burn_days", "rollup", "summaries", "downstream",
                            "results")

#' Read and validate config/pipeline.yml
read_pipeline_config <- function(path = "config/pipeline.yml") {
  cfg <- yaml::read_yaml(path)
  missing <- setdiff(required_pipeline_keys, names(cfg))
  if (length(missing)) {
    stop("pipeline config missing keys: ", paste(missing, collapse = ", "))
  }
  if (cfg$years$start > cfg$years$end) stop("years$start must be <= years$end")
  if (cfg$years$start < 1979) stop("gridMET starts in 1979")
  if (!(cfg$rollup$burn_day_share > 0 && cfg$rollup$burn_day_share <= 1)) {
    stop("rollup$burn_day_share must be in (0, 1]")
  }
  cfg$year_list <- seq.int(cfg$years$start, cfg$years$end)
  cfg
}

# ---- unit conversions ------------------------------------------------------
k_to_c  <- function(k) k - 273.15
c_to_k  <- function(c) c + 273.15
c_to_f  <- function(c) c * 9 / 5 + 32
f_to_c  <- function(f) (f - 32) * 5 / 9
mph_to_ms <- function(mph) mph * 0.44704
ms_to_mph <- function(ms) ms / 0.44704
ft_to_m <- function(ft) ft * 0.3048
m_to_ft <- function(m) m / 0.3048

# Convert a value in `units` to the pipeline's internal units
# (degC, pct, m_s, index).
to_internal_units <- function(x, units) {
  switch(units,
         degC = x,
         degF = f_to_c(x),
         K = k_to_c(x),
         pct = x,
         m_s = x,
         mph = mph_to_ms(x),
         index = x,
         stop("unknown units: ", units))
}

known_threshold_stats <- c("tmmx", "rmin", "midflame", "ic", "fm1", "fm10",
                           "fm100", "fm1000")

#' Load burn-window thresholds for one plan set as a data.frame
#'
#' Returns one row per enabled threshold with min/max in internal units.
#' NA min or max means that side is unbounded; a threshold with both NA is
#' dropped.
load_thresholds <- function(path = "config/burn_thresholds.yml",
                            plan_set = "forest") {
  y <- yaml::read_yaml(path)
  if (is.null(y$thresholds)) stop("thresholds file has no `thresholds` list")
  if (!plan_set %in% c("all", "forest", "nonforest")) {
    stop("plan_set must be one of all, forest, nonforest")
  }
  rows <- lapply(y$thresholds, function(t) {
    for (k in c("variable", "statistic", "units", "enabled")) {
      if (is.null(t[[k]])) stop("threshold entry missing `", k, "`")
    }
    if (!t$statistic %in% known_threshold_stats) {
      stop("unknown threshold statistic: ", t$statistic)
    }
    b <- t[[plan_set]]
    if (is.null(b)) stop("threshold ", t$variable, " has no `", plan_set, "` bounds")
    lo <- if (is.null(b$min)) NA_real_ else as.numeric(b$min)
    hi <- if (is.null(b$max)) NA_real_ else as.numeric(b$max)
    lo <- to_internal_units(lo, t$units)
    hi <- to_internal_units(hi, t$units)
    if (!is.na(lo) && !is.na(hi) && lo >= hi) {
      stop("threshold ", t$variable, ": min must be < max")
    }
    data.frame(variable = t$variable, statistic = t$statistic,
               min = lo, max = hi, enabled = isTRUE(t$enabled),
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  if (anyDuplicated(out$statistic)) stop("duplicate threshold statistics")
  out <- out[out$enabled & !(is.na(out$min) & is.na(out$max)), ]
  rownames(out) <- NULL
  out
}

#' Read downstream (stub) parameters
read_downstream_params <- function(path = "config/downstream_params.yml") {
  p <- yaml::read_yaml(path)
  s <- unlist(p$complexity_share)
  if (abs(sum(s) - 1) > 1e-6) stop("complexity_share must sum to 1")
  p
}

ensure_dir <- function(path) {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  path
}

#' Fixed 7-day day-of-year week (1..n_weeks; trailing days fold into last week)
doy_week <- function(date, n_weeks = 52L) {
  doy <- as.integer(format(as.Date(date), "%j"))
  pmin(as.integer(n_weeks), (doy - 1L) %/% 7L + 1L)
}
