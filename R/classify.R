# Daily in-prescription classification per gridMET pixel.

#' Classify in/out of prescription
#'
#' @param layers named list of numeric vectors/matrices of equal size, one per
#'   threshold statistic (internal units)
#' @param thresholds data.frame from load_thresholds()
#' @return integer vector/matrix: 1 in Rx, 0 out, NA if any used input is NA
classify_rx <- function(layers, thresholds) {
  stats <- thresholds$statistic
  missing <- setdiff(stats, names(layers))
  if (length(missing)) stop("missing layers for thresholds: ", paste(missing, collapse = ", "))
  ok <- NULL
  anyna <- NULL
  for (i in seq_len(nrow(thresholds))) {
    x <- layers[[stats[i]]]
    lo <- thresholds$min[i]; hi <- thresholds$max[i]
    inb <- rep(TRUE, length(x))
    if (!is.na(lo)) inb <- inb & x >= lo
    if (!is.na(hi)) inb <- inb & x <= hi
    na <- is.na(x)
    inb[na] <- FALSE
    ok <- if (is.null(ok)) inb else ok & inb
    anyna <- if (is.null(anyna)) na else anyna | na
  }
  out <- as.integer(ok)
  out[anyna] <- NA_integer_
  dim(out) <- dim(layers[[stats[1]]])
  out
}

#' Build threshold layers for one year from cached files (values as matrices
#' [cell, day]) and classify; writes inrx_{year}.tif (INT1U, NA = 255)
classify_rx_year <- function(year, gm_files, nfdrs_files, waf_file, thresholds,
                             wind_cfg, out_dir) {
  ensure_dir(out_dir)
  f <- file.path(out_dir, sprintf("inrx_%d.tif", year))
  ref <- terra::rast(gm_files$tmmx)
  v <- function(path) terra::values(terra::rast(path))
  waf <- terra::values(terra::rast(waf_file, lyrs = "waf"))[, 1]
  need <- thresholds$statistic
  L <- list()
  if ("tmmx" %in% need) L$tmmx <- k_to_c(v(gm_files$tmmx))
  if ("rmin" %in% need) L$rmin <- v(gm_files$rmin)
  if ("fm100" %in% need) L$fm100 <- v(gm_files$fm100)
  if ("fm1000" %in% need) L$fm1000 <- v(gm_files$fm1000)
  if ("fm1" %in% need) L$fm1 <- v(nfdrs_files[["fm1"]])
  if ("fm10" %in% need) L$fm10 <- v(nfdrs_files[["fm10"]])
  if ("midflame" %in% need) {
    af <- if (is.null(wind_cfg$afternoon_factor)) 1 else wind_cfg$afternoon_factor
    L$midflame <- midflame_wind(v(gm_files$vs), waf, wind_cfg$u10_to_u20ft, af)
  }
  cls <- classify_rx(L, thresholds)
  r <- terra::rast(ref)
  terra::values(r) <- cls
  names(r) <- names(ref)
  terra::time(r) <- terra::time(ref)
  terra::writeRaster(r, f, overwrite = TRUE, datatype = "INT1U", NAflag = 255,
                     gdal = c("COMPRESS=DEFLATE"))
  f
}
