# LANDFIRE sourcing via LFPS v2 (rlandfire). The AOI is split into lon/lat
# tiles; for each tile three requests are made:
#   fuels: multiband FBFM40, CC, CH, CBH, SlpD (no attribute tables needed)
#   evt:   single product, returns a .vat.dbf with EVT_NAME etc.
#   bps:   single product, returns a .vat.dbf with FRI_ALLFIR etc.
# Requires env var LANDFIRE_EMAIL (LFPS v2 requirement).

landfire_email <- function() {
  e <- Sys.getenv("LANDFIRE_EMAIL")
  if (!grepl("@", e)) {
    stop("Set env var LANDFIRE_EMAIL (required by LANDFIRE LFPS v2), e.g. in ",
         "your user .Renviron: LANDFIRE_EMAIL=you@example.org")
  }
  e
}

#' Split a lon/lat bbox into tiles; returns a list of named lists
make_lonlat_tiles <- function(bbox, tile_deg = 1) {
  xs <- seq(floor(bbox[1] / tile_deg) * tile_deg, bbox[3], by = tile_deg)
  ys <- seq(floor(bbox[2] / tile_deg) * tile_deg, bbox[4], by = tile_deg)
  g <- expand.grid(x = xs, y = ys)
  lapply(seq_len(nrow(g)), function(i) {
    b <- c(max(g$x[i], bbox[1]), max(g$y[i], bbox[2]),
           min(g$x[i] + tile_deg, bbox[3]), min(g$y[i] + tile_deg, bbox[4]))
    list(id = sprintf("x%+07.2f_y%+06.2f", g$x[i], g$y[i]), bbox = round(b, 4))
  })
}

#' Keep tiles that intersect the analysis units
tiles_intersecting <- function(tiles, units) {
  u <- sf::st_union(sf::st_transform(units, 4326))
  keep <- vapply(tiles, function(t) {
    p <- sf::st_as_sfc(sf::st_bbox(c(xmin = t$bbox[1], ymin = t$bbox[2],
                                     xmax = t$bbox[3], ymax = t$bbox[4]),
                                   crs = 4326))
    suppressMessages(lengths(sf::st_intersects(p, u)) > 0)
  }, logical(1))
  tiles[keep]
}

landfire_kinds <- function(products) {
  list(
    fuels = unname(unlist(products[c("fbfm40", "cc", "ch", "cbh", "slope")])),
    evt = products$evt,
    bps = products$bps
  )
}

#' Fetch one tile/kind (cached); returns the GeoTIFF path
fetch_landfire_tile <- function(tile, kind, products, dir, resolution = 30) {
  prods <- landfire_kinds(products)[[kind]]
  out_dir <- file.path(dir, kind, tile$id)
  done <- list.files(out_dir, pattern = "\\.tif$", full.names = TRUE)
  if (length(done) == 1) return(done)
  ensure_dir(out_dir)
  zip <- file.path(dir, kind, paste0(tile$id, ".zip"))
  with_retry(function() {
    resp <- rlandfire::landfireAPIv2(
      products = prods, aoi = tile$bbox, email = landfire_email(),
      projection = 5070, resolution = resolution, path = zip,
      max_time = 7200, verbose = FALSE)
    if (!identical(resp$status, "Succeeded")) stop("LFPS job status: ", resp$status)
    utils::unzip(zip, exdir = out_dir)
    unlink(zip)
  }, tries = 3, wait = 30)
  f <- list.files(out_dir, pattern = "\\.tif$", full.names = TRUE)
  if (length(f) != 1) stop("expected one tif in ", out_dir)
  f
}

#' Union of the per-tile .vat.dbf attribute tables for a kind (evt/bps)
landfire_attributes <- function(tifs) {
  dbfs <- paste0(tifs, ".vat.dbf")
  dbfs <- dbfs[file.exists(dbfs)]
  if (!length(dbfs)) stop("no attribute tables found")
  x <- do.call(rbind, lapply(dbfs, function(d) {
    a <- foreign::read.dbf(d, as.is = TRUE)
    a[, setdiff(names(a), c("Count", "R", "G", "B", "RED", "GREEN", "BLUE"))]
  }))
  x <- x[!duplicated(x$Value), ]
  x[order(x$Value), ]
}

#' Build a VRT mosaic of tiles
landfire_vrt <- function(tifs, out) {
  ensure_dir(dirname(out))
  terra::vrt(tifs, filename = out, overwrite = TRUE)
  out
}
