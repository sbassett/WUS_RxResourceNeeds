# gridMET daily data via THREDDS OPeNDAP (ncdf4), subset to the AOI and
# cached as one multi-layer GeoTIFF per variable-year.

gridmet_url <- function(var, template) gsub("{var}", var, template, fixed = TRUE)

# Plausible value ranges (pipeline units after ncdf4 scale/offset)
gridmet_ranges <- list(
  tmmx = c(220, 330), tmmn = c(200, 320),  # K
  rmax = c(0, 100), rmin = c(0, 100),      # %
  vs = c(0, 40),                           # m/s
  sph = c(0, 0.05),                        # kg/kg
  srad = c(0, 450),                        # W/m2
  pr = c(0, 600),                          # mm
  fm100 = c(0, 60), fm1000 = c(0, 60),     # %
  erc = c(0, 200)
)

with_retry <- function(expr_fun, tries = 4, wait = 10) {
  for (i in seq_len(tries)) {
    r <- try(expr_fun(), silent = TRUE)
    if (!inherits(r, "try-error")) return(r)
    if (i < tries) Sys.sleep(wait * i)
  }
  stop("failed after ", tries, " tries: ", conditionMessage(attr(r, "condition")))
}

#' Read one variable-year for a lon/lat bbox; returns a SpatRaster (EPSG:4326)
read_gridmet_opendap <- function(var, year, bbox, template) {
  url <- gridmet_url(var, template)
  with_retry(function() {
    nc <- ncdf4::nc_open(url)
    on.exit(ncdf4::nc_close(nc))
    vname <- setdiff(names(nc$var), "crs")[1]
    lon <- as.numeric(ncdf4::ncvar_get(nc, "lon"))
    lat <- as.numeric(ncdf4::ncvar_get(nc, "lat"))
    day <- as.Date(as.numeric(ncdf4::ncvar_get(nc, "day")), origin = "1900-01-01")
    ix <- which(lon >= bbox[1] & lon <= bbox[3])
    iy <- which(lat >= bbox[2] & lat <= bbox[4])
    it <- which(format(day, "%Y") == as.character(year))
    if (!length(ix) || !length(iy) || !length(it)) {
      stop("empty subset for ", var, " ", year)
    }
    dims <- vapply(nc$var[[vname]]$dim, `[[`, "", "name")
    idx <- list(lon = ix, lat = iy, day = it)
    start <- vapply(dims, function(d) min(idx[[d]]), 1)
    count <- vapply(dims, function(d) length(idx[[d]]), 1)
    v <- ncdf4::ncvar_get(nc, vname, start = start, count = count,
                          collapse_degen = FALSE)
    # reorder to [lat, lon, day] for terra (rows = lat)
    v <- aperm(v, match(c("lat", "lon", "day"), dims))
    lat_s <- lat[iy]; lon_s <- lon[ix]
    if (lat_s[1] < lat_s[length(lat_s)]) {   # ensure north-up
      v <- v[rev(seq_along(lat_s)), , , drop = FALSE]
      lat_s <- rev(lat_s)
    }
    rx <- abs(diff(lon_s[1:2])); ry <- abs(diff(lat_s[1:2]))
    r <- terra::rast(v, extent = terra::ext(min(lon_s) - rx / 2, max(lon_s) + rx / 2,
                                           min(lat_s) - ry / 2, max(lat_s) + ry / 2),
                     crs = "EPSG:4326")
    names(r) <- format(day[it])
    terra::time(r) <- day[it]
    r
  })
}

#' Fetch (or reuse cached) gridMET var-year; returns cache file path
fetch_gridmet <- function(var, year, bbox, template, cache_dir) {
  ensure_dir(cache_dir)
  f <- file.path(cache_dir, sprintf("%s_%d.tif", var, year))
  if (file.exists(f)) {
    ok <- try(terra::nlyr(terra::rast(f)) == days_in_year(year), silent = TRUE)
    if (isTRUE(ok)) return(f)
  }
  r <- read_gridmet_opendap(var, year, bbox, template)
  check_gridmet(r, var, year)
  terra::writeRaster(r, f, overwrite = TRUE, datatype = "FLT4S",
                     gdal = c("COMPRESS=DEFLATE", "PREDICTOR=3"))
  f
}

days_in_year <- function(year) {
  ifelse((year %% 4 == 0 & year %% 100 != 0) | year %% 400 == 0, 366L, 365L)
}

check_gridmet <- function(r, var, year) {
  if (terra::nlyr(r) != days_in_year(year)) {
    stop(var, " ", year, ": expected ", days_in_year(year), " layers, got ",
         terra::nlyr(r))
  }
  rng <- gridmet_ranges[[var]]
  if (!is.null(rng)) {
    mm <- range(terra::values(r), na.rm = TRUE)
    if (mm[1] < rng[1] || mm[2] > rng[2]) {
      stop(var, " ", year, ": values outside plausible range: ",
           paste(signif(mm, 4), collapse = " - "))
    }
  }
  invisible(TRUE)
}

#' Grid template (single layer, cell id values) from any cached gridMET file
gridmet_template <- function(file) {
  r <- terra::rast(file, lyrs = 1)
  t <- terra::rast(r)
  terra::values(t) <- seq_len(terra::ncell(t))
  names(t) <- "cell"
  t
}

#' Paths of cached files for one year as a named list by variable
gridmet_year_files <- function(files, year) {
  f <- files[grepl(sprintf("_%d\\.tif$", year), files)]
  stats::setNames(as.list(f), sub("_\\d{4}\\.tif$", "", basename(f)))
}
