# Figures. Each function writes a PNG and returns its path.

save_fig <- function(p, file, width = 8, height = 6) {
  ensure_dir(dirname(file))
  ggplot2::ggsave(file, p, width = width, height = height, dpi = 150, bg = "white")
  file
}

rast_df <- function(r, name = "value") {
  d <- terra::as.data.frame(r, xy = TRUE, na.rm = TRUE)
  names(d)[3] <- name
  d
}

fig_project_areas <- function(projects, state, file) {
  p <- ggplot2::ggplot() +
    ggplot2::geom_sf(data = projects, fill = "grey90", color = "grey50", linewidth = 0.1) +
    ggplot2::geom_sf(data = state, fill = NA, color = "black", linewidth = 0.6) +
    ggplot2::labs(title = sprintf("Fireshed Registry subfiresheds intersecting %s (n = %d)",
                                  state$STUSPS, nrow(projects))) +
    ggplot2::theme_minimal()
  save_fig(p, file)
}

fig_raster_map <- function(r, state, title, fill_lab, file, option = "viridis",
                           limits = NULL) {
  d <- rast_df(r)
  st <- sf::st_transform(state, terra::crs(r))
  p <- ggplot2::ggplot() +
    ggplot2::geom_raster(data = d, ggplot2::aes(.data$x, .data$y, fill = .data$value)) +
    ggplot2::geom_sf(data = st, fill = NA, color = "black", linewidth = 0.4) +
    ggplot2::scale_fill_viridis_c(option = option, limits = limits) +
    ggplot2::labs(title = title, fill = fill_lab, x = NULL, y = NULL) +
    ggplot2::theme_minimal()
  save_fig(p, file)
}

fig_weather_day <- function(gm_files, date, state, out_dir) {
  i <- function(f) which(terra::time(terra::rast(f)) == as.Date(date))
  tx <- terra::rast(gm_files$tmmx); tx <- k_to_c(tx[[i(gm_files$tmmx)]])
  rh <- terra::rast(gm_files$rmin); rh <- rh[[i(gm_files$rmin)]]
  c(fig_raster_map(tx, state, paste("gridMET Tmax", date), "degC",
                   file.path(out_dir, "gridmet_tmax_demo.png"), "inferno"),
    fig_raster_map(rh, state, paste("gridMET RHmin", date), "%",
                   file.path(out_dir, "gridmet_rhmin_demo.png"), "mako"))
}

fig_fm1 <- function(fm1_file, gm_files, date, state, out_dir) {
  f1 <- terra::rast(fm1_file)
  m <- fig_raster_map(f1[[which(terra::time(f1) == as.Date(date))]], state,
                      paste("NFDRS 1-hr fuel moisture", date), "%",
                      file.path(out_dir, "nfdrs_fm1_demo.png"), "cividis")
  # time series at the cell with the median FM1 on the demo date
  f100 <- terra::rast(gm_files$fm100)
  v <- terra::values(f1[[which(terra::time(f1) == as.Date(date))]])[, 1]
  cell <- which(!is.na(v))[which.min(abs(v[!is.na(v)] - stats::median(v, na.rm = TRUE)))]
  d <- data.frame(date = terra::time(f1),
                  FM1 = as.numeric(terra::values(f1)[cell, ]),
                  FM100 = as.numeric(terra::values(f100)[cell, ]))
  d <- tidyr::pivot_longer(d, -date, names_to = "var", values_to = "pct")
  xy <- terra::xyFromCell(f1, cell)
  p <- ggplot2::ggplot(d, ggplot2::aes(.data$date, .data$pct, color = .data$var)) +
    ggplot2::geom_line(linewidth = 0.4) +
    ggplot2::labs(title = sprintf("FM1 (NFDRS) vs gridMET FM100 at %.2f, %.2f", xy[1], xy[2]),
                  x = NULL, y = "fuel moisture (%)", color = NULL) +
    ggplot2::theme_minimal()
  c(m, save_fig(p, file.path(out_dir, "nfdrs_fm1_vs_fm100.png"), 9, 4))
}

fig_waf <- function(waf_file, state, out_dir) {
  w <- terra::rast(waf_file, lyrs = "waf")
  m <- fig_raster_map(w, state, "Wind adjustment factor (Andrews 2012), modal FBFM40",
                      "WAF", file.path(out_dir, "waf_map.png"), "plasma")
  d <- rast_df(w, "waf")
  p <- ggplot2::ggplot(d, ggplot2::aes(.data$waf)) +
    ggplot2::geom_histogram(bins = 50, fill = "steelblue") +
    ggplot2::labs(title = "WAF per gridMET cell", x = "WAF", y = "cells") +
    ggplot2::theme_minimal()
  c(m, save_fig(p, file.path(out_dir, "waf_hist.png"), 6, 4))
}

fig_inrx_days <- function(inrx_file, state, out_dir) {
  r <- terra::rast(inrx_file)
  yr <- format(terra::time(r)[1], "%Y")
  s <- terra::app(r, sum)
  fig_raster_map(s, state, paste("In-prescription days per pixel,", yr), "days",
                 file.path(out_dir, sprintf("inrx_days_%s.png", yr)))
}

fig_treatable <- function(frac_file, state, out_dir) {
  fig_raster_map(terra::rast(frac_file), state, "Treatable (target) fraction per gridMET cell",
                 "fraction", file.path(out_dir, "treatable_fraction.png"), "viridis", c(0, 1))
}

fig_project_choropleth <- function(projects, values, col, title, lab, file,
                                   trans = "identity") {
  x <- merge(projects, values[, c("project_id", col)], by = "project_id", all.x = TRUE)
  p <- ggplot2::ggplot(x) +
    ggplot2::geom_sf(ggplot2::aes(fill = .data[[col]]), color = NA) +
    ggplot2::scale_fill_viridis_c(trans = trans, na.value = "grey85") +
    ggplot2::labs(title = title, fill = lab) +
    ggplot2::theme_minimal()
  save_fig(p, file)
}

fig_rx_share_ts <- function(daily, annual, project_id, out_dir) {
  d <- daily[daily$project_id == project_id, ]
  p1 <- ggplot2::ggplot(d, ggplot2::aes(.data$date, .data$rx_share)) +
    ggplot2::geom_line(linewidth = 0.3) +
    ggplot2::geom_hline(yintercept = 0.5, linetype = 2, color = "red") +
    ggplot2::labs(title = paste("Daily rx_share, project", project_id), x = NULL,
                  y = "share of target area in Rx") +
    ggplot2::theme_minimal()
  a <- annual[annual$project_id == project_id, ]
  p2 <- ggplot2::ggplot(a, ggplot2::aes(factor(.data$year), .data$burn_days)) +
    ggplot2::geom_col(fill = "darkorange") +
    ggplot2::labs(title = paste("Annual burn days, project", project_id), x = NULL,
                  y = "burn days") +
    ggplot2::theme_minimal()
  c(save_fig(p1, file.path(out_dir, "rx_share_timeseries.png"), 9, 4),
    save_fig(p2, file.path(out_dir, "annual_burn_days_example.png"), 6, 4))
}

fig_exceedance <- function(exc, project_id, out_dir) {
  d <- exc[exc$project_id == project_id, ]
  p <- ggplot2::ggplot(d, ggplot2::aes(.data$week, factor(.data$k), fill = .data$p)) +
    ggplot2::geom_tile() +
    ggplot2::scale_fill_viridis_c(limits = c(0, 1)) +
    ggplot2::labs(title = paste("P(>= k burn days in week), project", project_id),
                  x = "week of year", y = "k", fill = "probability") +
    ggplot2::theme_minimal()
  save_fig(p, file.path(out_dir, "weekly_exceedance_example.png"), 9, 3.5)
}

#' Fireshed-level mean pairwise Jaccard, ordered by fireshed centroid latitude
fig_synchrony <- function(sync, projects, out_dir) {
  cen <- suppressWarnings(sf::st_coordinates(sf::st_centroid(
    sf::st_transform(projects, 4326))))
  pr <- data.frame(project_id = projects$project_id, fs = projects$Fireshed_ID,
                   lat = cen[, 2])
  s <- sync
  s$fa <- pr$fs[match(s$project_a, pr$project_id)]
  s$fb <- pr$fs[match(s$project_b, pr$project_id)]
  a <- pmin(s$fa, s$fb); b <- pmax(s$fa, s$fb)
  agg <- stats::aggregate(jaccard ~ a + b, data.frame(a, b, jaccard = s$jaccard), mean)
  agg <- rbind(agg, data.frame(a = agg$b, b = agg$a, jaccard = agg$jaccard))
  fl <- stats::aggregate(lat ~ fs, pr, mean)
  lv <- as.character(fl$fs[order(fl$lat)])
  agg$a <- factor(agg$a, lv); agg$b <- factor(agg$b, lv)
  p <- ggplot2::ggplot(agg, ggplot2::aes(.data$a, .data$b, fill = .data$jaccard)) +
    ggplot2::geom_raster() +
    ggplot2::scale_fill_viridis_c(limits = c(0, 1)) +
    ggplot2::labs(title = "Burn-day synchrony between firesheds (mean subfireshed Jaccard)",
                  subtitle = "Firesheds ordered south to north", x = NULL, y = NULL,
                  fill = "Jaccard") +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text = ggplot2::element_blank(), panel.grid = ggplot2::element_blank())
  save_fig(p, file.path(out_dir, "synchrony_firesheds.png"), 8, 7)
}

fig_state_weekly <- function(weekly, out_dir) {
  p <- ggplot2::ggplot(weekly, ggplot2::aes(.data$week)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = 0, ymax = .data$p90), fill = "grey80") +
    ggplot2::geom_line(ggplot2::aes(y = .data$mean)) +
    ggplot2::facet_wrap(~resource, scales = "free_y") +
    ggplot2::labs(title = "Statewide daily resource need by week (PLACEHOLDER parameters)",
                  subtitle = "line = mean daily need; band = 90th percentile",
                  x = "week of year", y = "resources per day") +
    ggplot2::theme_minimal()
  save_fig(p, file.path(out_dir, "state_weekly_resource_need.png"), 10, 6)
}

#' Pixel climatology: mean and CV of annual in-Rx days across years
fig_inrx_climatology <- function(inrx_files, state, out_dir) {
  ann <- terra::rast(lapply(inrx_files, function(f) terra::app(terra::rast(f), sum)))
  m <- terra::app(ann, mean)
  cv <- terra::app(ann, function(x) {
    m <- mean(x)
    if (is.na(m) || m <= 0) NA_real_ else stats::sd(x) / m
  })
  yrs <- range(as.integer(sub("\\D*(\\d{4})\\.tif$", "\\1", basename(inrx_files))))
  lab <- sprintf("%d-%d", yrs[1], yrs[2])
  c(fig_raster_map(m, state, paste("Mean annual in-prescription days per pixel,", lab),
                   "days", file.path(out_dir, "inrx_days_mean.png")),
    fig_raster_map(cv, state, paste("Interannual CV of in-prescription days,", lab),
                   "CV", file.path(out_dir, "inrx_days_cv.png"), "magma"))
}

#' Trend in annual burn days (mean across units with target area)
fig_burn_day_trend <- function(annual, out_dir) {
  d <- stats::aggregate(cbind(burn_days, pixel_mean_days) ~ year, annual, mean)
  p <- ggplot2::ggplot(d, ggplot2::aes(.data$year, .data$burn_days)) +
    ggplot2::geom_line() + ggplot2::geom_point(size = 1) +
    ggplot2::geom_smooth(method = "lm", formula = y ~ x, se = TRUE, color = "firebrick") +
    ggplot2::labs(title = "Annual burn days, mean across subfiresheds with target area",
                  x = NULL, y = "burn days") +
    ggplot2::theme_minimal()
  save_fig(p, file.path(out_dir, "burn_days_trend.png"), 8, 4)
}
