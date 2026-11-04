# Downstream stages (STUBS). Each function has a fixed output schema so the
# pipeline runs end to end; parameters are placeholders from
# config/downstream_params.yml and must be calibrated before use.

#' Unit size x complexity distribution of annual Rx acres
#'
#' Annual need (AFN) is distributed by the real size distribution of burn
#' units from treatable patches (see R/units.R), by owner group and WUI.
#' Complexity is a PLACEHOLDER: the same complexity_share applies to every
#' size bin until the complexity model replaces it.
#'
#' Schema: project_id, owner_group, wui (lgl), complexity, size_bin, unit_ac,
#' acres (annual acres of need), n_units (unit-burns per year)
unit_size_complexity <- function(burn_units, params) {
  cs <- unlist(params$complexity_share)
  bu <- burn_units[!is.na(burn_units$afn_ac) & burn_units$afn_ac > 0, ]
  bu$w <- bu$afn_ac * bu$unit_ac           # for acre-weighted mean unit size
  g <- stats::aggregate(cbind(afn_ac, w) ~ project_id + owner_group + wui + size_bin,
                        bu, sum)
  g$unit_ac <- g$w / g$afn_ac
  g$size_bin <- as.character(g$size_bin)
  rows <- lapply(names(cs), function(cx) {
    data.frame(project_id = g$project_id, owner_group = g$owner_group, wui = g$wui,
               complexity = cx, size_bin = g$size_bin, unit_ac = g$unit_ac,
               acres = g$afn_ac * cs[[cx]], n_units = g$afn_ac * cs[[cx]] / g$unit_ac,
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  out[order(out$project_id, out$owner_group, !out$wui, out$complexity, out$unit_ac), ]
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
