# Spatial conversion of the aspatial Rothermel lookup (R/rothermel.R) using the
# 30 m LANDFIRE fuel model (FBFM40) and slope maps.

#' Slope degrees (LANDFIRE SlpD) to percent
slope_deg_to_pct <- function(deg) tan(deg * pi / 180) * 100

#' 30 m rate of spread and flame length rasters for the treatable area
#'
#' Four layers, in the order cool ROS, hot ROS, cool flame, hot flame
#' (chains/hr and feet), for the configured live-moisture scenario. Cells
#' that are not treatable, or whose fuel model cannot carry fire, are NA.
rx_fire_behavior_raster <- function(fuels_vrt, band_names, treat_file, lookup,
                                    fb_cfg, out_file) {
  ensure_dir(dirname(out_file))
  fu <- terra::rast(fuels_vrt)
  names(fu) <- band_names
  treat <- terra::rast(treat_file)
  if (!terra::compareGeom(treat, fu, stopOnError = FALSE)) {
    stop("treatable mask and fuels mosaic are on different grids")
  }
  live <- fb_cfg$live_default
  tabs <- list(
    ros_cool = fb_table(lookup, "cool", live, "ros_chhr"),
    ros_hot = fb_table(lookup, "hot", live, "ros_chhr"),
    fl_cool = fb_table(lookup, "cool", live, "flame_ft"),
    fl_hot = fb_table(lookup, "hot", live, "flame_ft"))
  fun <- function(t, f, s) {
    out <- matrix(NA_real_, length(t), length(tabs))
    ok <- which(!is.na(t) & t == 1 & !is.na(f))
    if (length(ok)) {
      sp <- slope_deg_to_pct(s[ok])
      for (k in seq_along(tabs)) out[ok, k] <- interp_fb(f[ok], sp, tabs[[k]])
    }
    out
  }
  terra::lapp(c(treat, fu[["fbfm40"]], fu[["slope"]]), fun = fun,
              filename = out_file, overwrite = TRUE,
              wopt = list(datatype = "FLT4S", names = names(tabs),
                          gdal = c("COMPRESS=DEFLATE", "PREDICTOR=3")))
  out_file
}

#' Area-weighted acreage by flame length class and scenario, by owner group
flame_class_summary <- function(patches) {
  cols <- grep("^ac_fl_", names(patches), value = TRUE)
  if (!length(cols)) stop("patches have no flame class columns")
  d <- stats::aggregate(patches[cols], list(owner_group = patches$owner_group), sum)
  long <- do.call(rbind, lapply(cols, function(cn) {
    p <- strsplit(sub("^ac_fl_", "", cn), "_")[[1]]       # e.g. cool 0 4 / hot 8p
    data.frame(owner_group = d$owner_group, scenario = p[1],
               flame_class = unname(c(`0_4` = "0-4 ft", `4_8` = "4-8 ft", `8p` = "> 8 ft")[paste(p[-1], collapse = "_")]),
               acres = d[[cn]], stringsAsFactors = FALSE)
  }))
  long$flame_class <- factor(long$flame_class, levels = c("0-4 ft", "4-8 ft", "> 8 ft"))
  long[order(long$owner_group, long$scenario, long$flame_class), ]
}
