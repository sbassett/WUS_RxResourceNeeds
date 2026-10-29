# Downstream stages (STUBS). Each function has a fixed output schema so the
# pipeline runs end to end; parameters are placeholders from
# config/downstream_params.yml and must be calibrated before use.

#' Size bins clipped to allowed unit-size range
clip_bins <- function(bins, lo, hi) {
  b <- bins[bins$max >= lo & bins$min <= hi, ]
  b$min <- pmax(b$min, lo)
  b$max <- pmin(b$max, hi)
  b$unit_ac <- (b$min + b$max) / 2
  b
}

#' Unit size x complexity distribution of annual Rx acres
#'
#' Schema: project_id, wui (lgl), complexity, size_bin, unit_ac, acres, n_units
#' Placeholder: AFN split by wui_share and complexity_share, then spread
#' evenly in acres across allowed size bins (WUI <= wui_max; non-WUI
#' nonwui_min..nonwui_max).
unit_size_complexity <- function(rx_target, params) {
  bins <- do.call(rbind, lapply(params$size_bins, as.data.frame))
  us <- params$unit_size
  b_w <- clip_bins(bins, min(bins$min), us$wui_max)
  b_n <- clip_bins(bins, us$nonwui_min, us$nonwui_max)
  cs <- unlist(params$complexity_share)
  p <- rx_target[!is.na(rx_target$afn_ac) & rx_target$afn_ac > 0, ]
  rows <- list()
  for (wui in c(TRUE, FALSE)) {
    b <- if (wui) b_w else b_n
    share_w <- if (wui) params$wui_share else 1 - params$wui_share
    for (cx in names(cs)) {
      for (j in seq_len(nrow(b))) {
        ac <- p$afn_ac * share_w * cs[[cx]] / nrow(b)
        rows[[length(rows) + 1]] <- data.frame(
          project_id = p$project_id, wui = wui, complexity = cx,
          size_bin = b$bin[j], unit_ac = b$unit_ac[j], acres = ac,
          n_units = ac / b$unit_ac[j], stringsAsFactors = FALSE)
      }
    }
  }
  out <- do.call(rbind, rows)
  out[order(out$project_id, !out$wui, out$complexity, out$unit_ac), ]
}

#' Firing method for a unit size and complexity
firing_rule <- function(unit_ac, complexity, heavy_fuel_share, fp) {
  ifelse(unit_ac > fp$heli_min_acres, "heli",
         ifelse(unit_ac >= fp$drone_min_acres &
                  complexity %in% unlist(fp$drone_complexity) &
                  (is.na(heavy_fuel_share) | heavy_fuel_share < 0.5),
                "drone", "hand"))
}

#' Firing days per unit; heli halves the hand-firing time
firing_days <- function(unit_ac, method, fp) {
  apd <- fp$acres_per_day
  d <- ifelse(method == "heli", unit_ac / apd$hand * fp$heli_time_factor,
              ifelse(method == "drone", unit_ac / apd$drone, unit_ac / apd$hand))
  pmax(1, d)
}

#' Schema: adds firing_method, firing_days_per_unit
firing_method <- function(units, project_stats, params) {
  hf <- project_stats$heavy_fuel_share[match(units$project_id, project_stats$project_id)]
  units$firing_method <- firing_rule(units$unit_ac, units$complexity, hf, params$firing)
  units$firing_days_per_unit <- firing_days(units$unit_ac, units$firing_method,
                                            params$firing)
  units
}

#' Size x complexity firing-method matrix (no heavy fuels), for reporting
firing_matrix <- function(params) {
  bins <- do.call(rbind, lapply(params$size_bins, as.data.frame))
  bins$unit_ac <- (bins$min + bins$max) / 2
  g <- expand.grid(size_bin = bins$bin, complexity = names(params$complexity_share),
                   stringsAsFactors = FALSE)
  g$unit_ac <- bins$unit_ac[match(g$size_bin, bins$bin)]
  g$firing_method <- firing_rule(g$unit_ac, g$complexity, 0, params$firing)
  g
}

#' Schema: adds line_production_ch_hr
line_production <- function(units, params) {
  lp <- unlist(params$line_production_ch_hr)
  units$line_production_ch_hr <- unname(lp[units$complexity])
  units
}

#' Annual resource-days per project and resource type
#'
#' Schema: project_id, resource, resource_days_yr
resource_mix <- function(units, params) {
  units$unit_days <- units$n_units * units$firing_days_per_unit
  rpu <- params$resources_per_unit_day
  types <- unique(c(unlist(lapply(rpu, names)),
                    unlist(lapply(params$aerial_extra, names))))
  out <- lapply(types, function(rt) {
    per <- vapply(units$complexity, function(cx) {
      v <- rpu[[cx]][[rt]]; if (is.null(v)) 0 else v
    }, numeric(1))
    ex <- vapply(units$firing_method, function(m) {
      v <- params$aerial_extra[[m]][[rt]]; if (is.null(v)) 0 else v
    }, numeric(1))
    data.frame(project_id = units$project_id, resource = rt,
               resource_days_yr = units$unit_days * (per + ex))
  })
  out <- do.call(rbind, out)
  out <- stats::aggregate(resource_days_yr ~ project_id + resource, out, sum)
  out[order(out$project_id, out$resource), ]
}
