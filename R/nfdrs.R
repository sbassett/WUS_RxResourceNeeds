# NFDRS 1-hr and 10-hr dead fuel moisture (Cohen & Deeming 1985, PSW-GTR-82;
# Deeming et al. 1977). Equilibrium moisture content uses the Simard (1968)
# regressions with temperature in degF and RH in percent:
#   RH < 10      : EMC = 0.03229 + 0.281073 H - 0.000578 H T
#   10 <= RH < 50: EMC = 2.22749 + 0.160107 H - 0.014784 T
#   RH >= 50     : EMC = 21.0606 + 0.005565 H^2 - 0.00035 H T - 0.483199 H
# MC1 = 1.03 EMC; MC10 = 1.28 EMC (no fuel-stick observation).
# Afternoon (basic observation time) conditions are approximated by daily
# Tmax and RHmin. Fuel-level temperature/RH are adjusted for state of weather
# (SOW 0-3): +25/+19/+12/+5 degF and RH x 0.75/0.83/0.92/1.00.

emc_simard <- function(temp_f, rh) {
  out <- rep(NA_real_, length(rh))
  a <- !is.na(rh) & !is.na(temp_f)
  lo <- a & rh < 10
  md <- a & rh >= 10 & rh < 50
  hi <- a & rh >= 50
  out[lo] <- 0.03229 + 0.281073 * rh[lo] - 0.000578 * rh[lo] * temp_f[lo]
  out[md] <- 2.22749 + 0.160107 * rh[md] - 0.014784 * temp_f[md]
  out[hi] <- 21.0606 + 0.005565 * rh[hi]^2 - 0.00035 * rh[hi] * temp_f[hi] -
    0.483199 * rh[hi]
  out
}

fm1_nfdrs <- function(temp_f, rh) 1.03 * emc_simard(temp_f, rh)
fm10_nfdrs <- function(temp_f, rh) 1.28 * emc_simard(temp_f, rh)

sow_temp_add_f <- c(25, 19, 12, 5)
sow_rh_mult <- c(0.75, 0.83, 0.92, 1.00)

#' Fuel-level temperature (degF) and RH (%) for state of weather 0-3
fuel_level_conditions <- function(temp_f, rh, sow) {
  i <- sow + 1L
  list(temp_f = temp_f + sow_temp_add_f[i],
       rh = pmin(100, rh * sow_rh_mult[i]))
}

#' Clear-sky shortwave (W/m2, daily mean): 0.75 x extraterrestrial (FAO-56)
clear_sky_srad <- function(lat_deg, doy) {
  phi <- lat_deg * pi / 180
  dr <- 1 + 0.033 * cos(2 * pi * doy / 365)
  delta <- 0.409 * sin(2 * pi * doy / 365 - 1.39)
  ws <- acos(pmin(1, pmax(-1, -tan(phi) * tan(delta))))
  ra <- (24 * 60 / pi) * 0.0820 * dr *
    (ws * sin(phi) * sin(delta) + cos(phi) * cos(delta) * sin(ws))  # MJ/m2/day
  0.75 * ra / 0.0864
}

#' State of weather (0 clear .. 3 overcast) from srad / clear-sky ratio
sow_from_srad <- function(srad, srad_clear, breaks = c(0.9, 0.7, 0.5)) {
  ratio <- srad / srad_clear
  sow <- ifelse(ratio >= breaks[1], 0L,
                ifelse(ratio >= breaks[2], 1L,
                       ifelse(ratio >= breaks[3], 2L, 3L)))
  sow
}

#' Compute FM1 and FM10 rasters for one year from cached gridMET files
#'
#' @param files named list with tmmx, rmin, srad file paths
#' @return character vector of written file paths (fm1, fm10)
compute_nfdrs_year <- function(files, year, nfdrs_cfg) {
  out_dir <- ensure_dir(nfdrs_cfg$out_dir)
  f1 <- file.path(out_dir, sprintf("fm1_%d.tif", year))
  f10 <- file.path(out_dir, sprintf("fm10_%d.tif", year))
  tmx <- terra::rast(files$tmmx)
  rmn <- terra::rast(files$rmin)
  t_f <- c_to_f(k_to_c(terra::values(tmx)))
  rh <- terra::values(rmn)
  if (identical(nfdrs_cfg$cloud_adjust, "srad")) {
    srd <- terra::rast(files$srad)
    lat <- terra::yFromCell(tmx, seq_len(terra::ncell(tmx)))
    doy <- as.integer(format(terra::time(tmx), "%j"))
    clear <- outer(lat, doy, clear_sky_srad)
    sow <- sow_from_srad(terra::values(srd), clear, unlist(nfdrs_cfg$sow_breaks))
    sow[is.na(sow)] <- 0L
    fl <- fuel_level_conditions(t_f, rh, sow)
  } else if (identical(nfdrs_cfg$cloud_adjust, "none")) {
    fl <- list(temp_f = t_f, rh = rh)
  } else {
    stop("nfdrs$cloud_adjust must be 'srad' or 'none'")
  }
  emc <- emc_simard(as.vector(fl$temp_f), as.vector(fl$rh))
  r1 <- terra::rast(tmx); r10 <- terra::rast(tmx)
  terra::values(r1) <- matrix(1.03 * emc, ncol = terra::nlyr(tmx))
  terra::values(r10) <- matrix(1.28 * emc, ncol = terra::nlyr(tmx))
  names(r1) <- names(r10) <- names(tmx)
  terra::time(r1) <- terra::time(r10) <- terra::time(tmx)
  g <- c("COMPRESS=DEFLATE", "PREDICTOR=3")
  terra::writeRaster(r1, f1, overwrite = TRUE, datatype = "FLT4S", gdal = g)
  terra::writeRaster(r10, f10, overwrite = TRUE, datatype = "FLT4S", gdal = g)
  c(fm1 = f1, fm10 = f10)
}
