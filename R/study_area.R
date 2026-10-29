# Study area (state boundary) and analysis units (Fireshed Registry
# 4th ed. subfiresheds).

#' State boundary in the analysis CRS (Census cartographic boundary)
get_state_boundary <- function(state_abbr, crs = 5070,
                               cache = "data/raw/state_boundary.gpkg") {
  if (!file.exists(cache)) {
    ensure_dir(dirname(cache))
    st <- tigris::states(cb = TRUE, year = 2023, progress_bar = FALSE)
    sf::st_write(st, cache, quiet = TRUE, delete_dsn = TRUE)
  }
  st <- sf::st_read(cache, quiet = TRUE)
  out <- st[st$STUSPS == state_abbr, c("STUSPS", "NAME")]
  if (nrow(out) != 1) stop("state not found: ", state_abbr)
  sf::st_transform(out, crs)
}

#' Download and unzip the Fireshed Registry if the gdb is missing
ensure_fireshed_registry <- function(url, gdb) {
  if (dir.exists(gdb)) return(gdb)
  zip <- file.path("data/raw", basename(url))
  ensure_dir(dirname(zip))
  if (!file.exists(zip)) {
    old <- options(timeout = 1800); on.exit(options(old))
    utils::download.file(url, zip, mode = "wb")
  }
  utils::unzip(zip, exdir = sub("\\.zip$", "", zip))
  if (!dir.exists(gdb)) stop("gdb not found after unzip: ", gdb)
  gdb
}

#' Subfiresheds intersecting the state, kept whole, as `project_id` polygons
build_project_areas <- function(units_cfg, state, crs = 5070) {
  gdb <- ensure_fireshed_registry(units_cfg$url, units_cfg$gdb)
  bb <- sf::st_as_text(sf::st_as_sfc(sf::st_bbox(sf::st_transform(state, 5070))))
  x <- sf::st_read(gdb, units_cfg$layer, wkt_filter = bb, quiet = TRUE)
  x <- sf::st_transform(x, crs)
  x <- sf::st_make_valid(x)
  keep <- lengths(sf::st_intersects(x, sf::st_transform(state, crs))) > 0
  x <- x[keep, ]
  x$project_id <- as.integer(x[[units_cfg$id_field]])
  x$area_ac <- as.numeric(sf::st_area(x)) / 4046.8564224
  x <- x[, c("project_id", "Fireshed_ID", "Fireshed_Name", "Fireshed_State",
             "area_ac")]
  sf::st_geometry(x) <- "geom"
  validate_project_areas(x, crs)
  x
}

validate_project_areas <- function(x, crs) {
  if (nrow(x) == 0) stop("no project areas selected")
  if (anyDuplicated(x$project_id)) stop("project_id not unique")
  if (!all(sf::st_is_valid(x))) stop("invalid geometries")
  if (sf::st_crs(x) != sf::st_crs(crs)) stop("unexpected CRS")
  invisible(TRUE)
}

write_project_areas <- function(x, out, layer) {
  ensure_dir(dirname(out))
  sf::st_write(x, out, layer = layer, delete_layer = TRUE, quiet = TRUE)
  paste0(out, "|layername=", layer)
}

#' Lon/lat bbox (xmin, ymin, xmax, ymax) of the units, buffered
units_lonlat_bbox <- function(x, buffer_km = 5) {
  b <- sf::st_buffer(sf::st_as_sfc(sf::st_bbox(x)), buffer_km * 1000)
  as.numeric(sf::st_bbox(sf::st_transform(b, 4326)))
}
