# Project-area daily rollup: rx_share = treatable-area-weighted share of a
# project area's gridMET cells that are in prescription.

#' Sparse weight matrix [project, cell]: coverage fraction x treatable
#' fraction x cell area (km2)
project_cell_weights <- function(projects, frac_file) {
  frac <- terra::rast(frac_file)
  area <- terra::cellSize(frac, unit = "km")
  p <- sf::st_transform(projects, terra::crs(frac))
  cov <- exactextractr::exact_extract(frac, p, include_cell = TRUE,
                                      include_cols = "project_id",
                                      progress = FALSE)
  cov <- do.call(rbind, cov)
  fv <- terra::values(frac)[, 1]
  av <- terra::values(area)[, 1]
  w <- cov$coverage_fraction * fv[cov$cell] * av[cov$cell]
  w[is.na(w)] <- 0
  ids <- sort(unique(projects$project_id))
  Matrix::sparseMatrix(i = match(cov$project_id, ids), j = cov$cell, x = w,
                       dims = c(length(ids), terra::ncell(frac)),
                       dimnames = list(as.character(ids), NULL))
}

#' Weighted share given a weight matrix W [p, cell] and values X [cell, day]
#' (0/1/NA). NA cells are excluded from both numerator and denominator.
weighted_share <- function(W, X) {
  loadNamespace("Matrix")   # S4 methods for sparse W
  V <- !is.na(X)
  X0 <- X; X0[!V] <- 0
  num <- as.matrix(W %*% X0)
  den <- as.matrix(W %*% (V * 1))
  out <- num / den
  out[den <= 0] <- NA_real_
  out
}

km2_to_acres <- function(km2) km2 * 247.1053815

#' Weighted in-Rx area (acres) given W [p, cell] in km2 and X [cell, day]
weighted_acres <- function(W, X) {
  loadNamespace("Matrix")
  X0 <- X; X0[is.na(X0)] <- 0
  km2_to_acres(as.matrix(W %*% X0))
}

#' Daily rollup for one year
#'
#' Long data.frame(project_id, date, rx_share, rx_acres). rx_acres is the
#' treatable area in prescription that day (acres), using the same weights
#' as rx_share (coverage x treatable fraction x cell area), so rx_share =
#' rx_acres / treatable acres with valid data.
rx_share_year <- function(inrx_file, W) {
  loadNamespace("Matrix")
  W <- W[Matrix::rowSums(W) > 0, , drop = FALSE]   # drop units with no target area
  r <- terra::rast(inrx_file)
  X <- terra::values(r)
  s <- weighted_share(W, X)
  a <- weighted_acres(W, X)
  a[is.na(s)] <- NA_real_
  dates <- terra::time(r)
  data.frame(project_id = rep(as.integer(rownames(W)), times = length(dates)),
             date = rep(dates, each = nrow(W)),
             rx_share = as.vector(s),
             rx_acres = as.vector(a))
}

#' Burn-day rule from the `rollup` config section
#'
#' rule "acres" (default): burn day when rx_acres >= burn_day_acres (enough
#' in-Rx treatable area to host one minimum-size burn unit).
#' rule "share": burn day when rx_share >= burn_day_share.
#' A bare number is treated as a share cutoff (used in tests).
burn_day_rule <- function(rollup_cfg) {
  if (is.numeric(rollup_cfg)) return(list(rule = "share", share = rollup_cfg))
  r <- if (is.null(rollup_cfg$burn_day_rule)) "acres" else rollup_cfg$burn_day_rule
  list(rule = r, acres = rollup_cfg$burn_day_acres, share = rollup_cfg$burn_day_share)
}

#' 0/1 burn-day flag for each row of the daily table (NA rx_share -> NA)
flag_burn_days <- function(daily, rule) {
  rule <- burn_day_rule(rule)
  out <- switch(rule$rule,
    acres = {
      if (!"rx_acres" %in% names(daily)) stop("daily table has no rx_acres column")
      daily$rx_acres >= rule$acres - 1e-9
    },
    share = daily$rx_share >= rule$share - 1e-9,
    stop("rollup$burn_day_rule must be 'acres' or 'share'"))
  out <- as.integer(out)
  out[is.na(daily$rx_share)] <- NA_integer_
  out
}

#' Write the combined daily table to parquet
write_rx_share <- function(tables, out) {
  ensure_dir(dirname(out))
  d <- do.call(rbind, tables)
  d <- d[order(d$project_id, d$date), ]
  arrow::write_parquet(d, out)
  out
}

#' Derived counts from the daily table
#'
#' burn_day from flag_burn_days(rule). pixel_mean_days = sum of rx_share,
#' i.e. the treatable-area-weighted mean count of in-Rx days across pixels.
burn_day_counts <- function(daily, rule = 0.5, n_weeks = 52L) {
  daily$burn_day <- flag_burn_days(daily, rule)
  d <- dplyr::filter(daily, !is.na(.data$rx_share))
  d <- dplyr::mutate(d,
                     year = as.integer(format(.data$date, "%Y")),
                     week = doy_week(.data$date, n_weeks))
  ann <- dplyr::summarise(dplyr::group_by(d, .data$project_id, .data$year),
                          burn_days = sum(.data$burn_day),
                          pixel_mean_days = sum(.data$rx_share),
                          n_days = dplyr::n(), .groups = "drop")
  wk <- dplyr::summarise(dplyr::group_by(d, .data$project_id, .data$year, .data$week),
                         burn_days = sum(.data$burn_day), .groups = "drop")
  list(annual = as.data.frame(ann), weekly = as.data.frame(wk))
}
