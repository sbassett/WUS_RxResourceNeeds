# Landowner from PAD-US 4.1 Fee (ownership) polygons, with private land as the
# unmapped remainder (PAD-US has no complete private class).
#
# The USGS-hosted service is queried by bounding box (same code for any state
# or the whole West) and cached as a GeoPackage. Geometries are generalised
# server-side to ~half a 30 m pixel.

owner_levels <- c("USFS", "BLM", "NPS", "FWS", "DOD", "OtherFed", "Tribal",
                  "State", "Local", "NGO", "Private", "Unknown")
owner_groups <- c(USFS = "Federal", BLM = "Federal", NPS = "Federal", FWS = "Federal",
                  DOD = "Federal", OtherFed = "Federal", Tribal = "Tribal",
                  State = "State/Local", Local = "State/Local",
                  NGO = "Private/Other", Private = "Private/Other",
                  Unknown = "Private/Other")
owner_private_code <- match("Private", owner_levels)   # background value

.fed_other <- c("TVA", "BOEM", "USBR", "USACE", "DOE", "NRCS", "ARS", "BIA", "NOAA",
                "BPA", "OTHF")
.state_names <- c("SPR", "SDC", "SLB", "SFW", "SDNR", "SDOL", "OTHS")
.local_names <- c("REG", "RWD", "CITY", "CNTY", "UNKL")

#' Map one PAD-US owner name to an owner class (NA when not informative)
owner_from_name <- function(nm) {
  out <- rep(NA_character_, length(nm))
  out[nm %in% c("USFS", "BLM", "NPS", "FWS", "DOD")] <- nm[nm %in% c("USFS", "BLM", "NPS", "FWS", "DOD")]
  out[nm %in% .fed_other] <- "OtherFed"
  out[nm == "TRIB"] <- "Tribal"
  out[nm %in% .state_names] <- "State"
  out[nm %in% .local_names] <- "Local"
  out[nm == "NGO"] <- "NGO"
  out[nm == "PVT"] <- "Private"
  out
}

#' Owner class from PAD-US Fee attributes
#'
#' Uses Own_Name; where that is unknown/other/joint, falls back to Mang_Name,
#' then to Own_Type. Returns a character vector of owner_levels.
classify_owner <- function(own_type, own_name, mang_name) {
  n <- max(length(own_type), length(own_name), length(mang_name))
  own_type <- rep_len(as.character(own_type), n)
  own_name <- rep_len(as.character(own_name), n)
  mang_name <- rep_len(as.character(mang_name), n)
  out <- owner_from_name(own_name)
  miss <- is.na(out)
  out[miss] <- owner_from_name(mang_name[miss])
  miss <- is.na(out)
  by_type <- c(FED = "OtherFed", TRIB = "Tribal", STAT = "State", LOC = "Local",
               DIST = "Local", NGO = "NGO", PVT = "Private")
  out[miss] <- unname(by_type[own_type[miss]])
  out[is.na(out)] <- "Unknown"
  out
}

owner_code <- function(owner) match(owner, owner_levels)

#' Keep polygon parts only (drops points/lines from geometry collections) and
#' empty geometries; leaves pure polygon layers untouched
polygons_only <- function(x) {
  types <- as.character(sf::st_geometry_type(x))
  if (!all(types %in% c("POLYGON", "MULTIPOLYGON"))) {
    x <- sf::st_collection_extract(x, "POLYGON", warn = FALSE)
  }
  x[!sf::st_is_empty(x), ]
}
#' Page through the PAD-US Fee service for a lon/lat bbox; returns an sf
#' object in EPSG:5070 with owner / owner_group columns
fetch_padus_fee <- function(bbox, lcfg, crs = 5070) {
  fields <- c("Own_Type", "Own_Name", "Mang_Name", "Des_Tp", "Unit_Nm", "GIS_Acres")
  base <- paste0(sub("/$", "", lcfg$url), "/query")
  geom <- paste(bbox, collapse = "%2C")
  page <- 2000L
  out <- list(); off <- 0L
  repeat {
    url <- paste0(base, "?where=1%3D1&geometry=", geom,
                  "&geometryType=esriGeometryEnvelope&inSR=4326",
                  "&spatialRel=esriSpatialRelIntersects",
                  "&outFields=", paste(fields, collapse = "%2C"),
                  "&outSR=", crs, "&maxAllowableOffset=", lcfg$simplify_m,
                  "&orderByFields=OBJECTID&resultOffset=", off,
                  "&resultRecordCount=", page, "&f=geojson")
    raw <- with_retry(function() {
      old <- options(timeout = 900); on.exit(options(old))
      paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "")
    })
    x <- sf::read_sf(raw)
    if (nrow(x) == 0) break
    out[[length(out) + 1]] <- x
    if (nrow(x) < page) break
    off <- off + page
  }
  if (!length(out)) stop("PAD-US query returned no features for bbox ", geom)
  x <- do.call(rbind, out)
  x <- sf::st_set_crs(x, crs)
  x <- sf::st_make_valid(x)
  x <- polygons_only(x)
  x$owner <- classify_owner(x$Own_Type, x$Own_Name, x$Mang_Name)
  x$owner_group <- unname(owner_groups[x$owner])
  x
}

#' Cache the Fee polygons as a GeoPackage; returns the path
padus_fee_file <- function(bbox, lcfg, crs = 5070) {
  ensure_dir(lcfg$cache_dir)
  f <- file.path(lcfg$cache_dir, sprintf("padus41_fee_%s.gpkg",
                                         substr(rlang::hash(round(bbox, 3)), 1, 8)))
  if (file.exists(f)) return(f)
  x <- fetch_padus_fee(bbox, lcfg, crs)
  sf::st_write(x, f, layer = "fee", quiet = TRUE, delete_dsn = TRUE)
  f
}

#' Rasterize owner codes onto `ref`; unmapped cells become Private.
#' Larger parcels are painted first so small inholdings win overlaps.
rasterize_owner <- function(fee, ref, filename = "") {
  fee <- polygons_only(fee)
  fee <- fee[order(-as.numeric(sf::st_area(fee))), ]
  fee$code <- owner_code(fee$owner)
  v <- terra::vect(fee)
  r <- terra::rasterize(v, ref, field = "code", background = owner_private_code,
                        wopt = list(datatype = "INT1U"))
  if (nzchar(filename)) {
    r <- terra::writeRaster(r, filename, overwrite = TRUE, datatype = "INT1U",
                            gdal = "COMPRESS=DEFLATE")
  }
  r
}
