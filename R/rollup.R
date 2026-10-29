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

#' Daily rx_share for one year: long data.frame(project_id, date, rx_share)
rx_share_year <- function(inrx_file, W) {
  loadNamespace("Matrix")
  W <- W[Matrix::rowSums(W) > 0, , drop = FALSE]   # drop units with no target area
  r <- terra::rast(inrx_file)
  X <- terra::values(r)
  s <- weighted_share(W, X)
  dates <- terra::time(r)
  data.frame(project_id = rep(as.integer(rownames(W)), times = length(dates)),
             date = rep(dates, each = nrow(W)),
             rx_share = as.vector(s))
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
#' burn_day = rx_share >= threshold. pixel_mean_days = sum of rx_share, i.e.
#' the treatable-area-weighted mean count of in-Rx days across pixels.
burn_day_counts <- function(daily, threshold = 0.5, n_weeks = 52L) {
  d <- dplyr::filter(daily, !is.na(.data$rx_share))
  d <- dplyr::mutate(d,
                     year = as.integer(format(.data$date, "%Y")),
                     week = doy_week(.data$date, n_weeks),
                     burn_day = as.integer(.data$rx_share >= threshold))
  ann <- dplyr::summarise(dplyr::group_by(d, .data$project_id, .data$year),
                          burn_days = sum(.data$burn_day),
                          pixel_mean_days = sum(.data$rx_share),
                          n_days = dplyr::n(), .groups = "drop")
  wk <- dplyr::summarise(dplyr::group_by(d, .data$project_id, .data$year, .data$week),
                         burn_days = sum(.data$burn_day), .groups = "drop")
  list(annual = as.data.frame(ann), weekly = as.data.frame(wk))
}
