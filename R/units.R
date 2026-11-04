# Burn units from treatable patches, and their size distribution.
#
# Within each patch the WUI acres and non-WUI acres form two pools. A pool of
# area A is split into n = ceiling(A / max_size) equal units, the fewest
# units that respect the size cap (WUI <= wui_max; non-WUI <= nonwui_max).
# Real units are usually smaller (fuel breaks, hazards, water, mosaics), so
# this is an upper bound on unit size; compare with TWIGS and calibrate
# `unit_size$nonwui_split_ac` if needed. Pools smaller than the non-WUI
# minimum are kept at their own size and flagged `below_min`.

#' Split a pool of `area` acres into equal units no larger than `max_ac`
split_pool <- function(area, max_ac) {
  n <- ceiling(area / max_ac - 1e-9)
  n[area <= 0] <- 0
  data.frame(n_units = n, unit_ac = ifelse(n > 0, area / n, NA_real_))
}

#' Size bin labels from the config bins, plus "<50" for small remnants
size_bin_labels <- function(unit_ac, size_bins) {
  b <- do.call(rbind, lapply(size_bins, as.data.frame))
  b <- b[order(b$min), ]
  top <- max(b$max)
  idx <- findInterval(unit_ac, b$min)
  lab <- ifelse(idx == 0, paste0("<", b$min[1]), b$bin[pmax(idx, 1)])
  lab[!is.na(unit_ac) & unit_ac > top] <- paste0(">", top)
  lev <- c(paste0("<", b$min[1]), b$bin, paste0(">", top))
  factor(lab, levels = lev)
}

#' Burn-unit pools per patch
#'
#' @param patches from build_patches()
#' @param params downstream params (unit_size, size_bins)
#' @return data.frame(project_id, patch_id, owner, owner_group, wui, n_units,
#'   unit_ac, area_ac, afn_ac, below_min, size_bin)
build_burn_units <- function(patches, params) {
  us <- params$unit_size
  split_nonwui <- if (is.null(us$nonwui_split_ac)) us$nonwui_max else us$nonwui_split_ac
  wui_ac <- pmin(patches$wui_ac, patches$area_ac)
  non_ac <- pmax(patches$area_ac - wui_ac, 0)
  afn_w <- ifelse(patches$area_ac > 0, patches$afn_ac * wui_ac / patches$area_ac, 0)
  afn_n <- patches$afn_ac - afn_w
  mk <- function(area, afn, wui, cap) {
    s <- split_pool(area, cap)
    keep <- s$n_units > 0
    d <- data.frame(project_id = patches$project_id, patch_id = patches$patch_id,
                    owner = patches$owner, owner_group = patches$owner_group,
                    wui = wui, n_units = s$n_units, unit_ac = s$unit_ac,
                    area_ac = area, afn_ac = afn)
    d[keep, ]
  }
  x <- rbind(mk(wui_ac, afn_w, TRUE, us$wui_max),
             mk(non_ac, afn_n, FALSE, split_nonwui))
  x$below_min <- !x$wui & x$unit_ac < us$nonwui_min - 1e-9
  x$size_bin <- size_bin_labels(x$unit_ac, params$size_bins)
  x[order(x$project_id, x$patch_id, x$wui), ]
}

#' Check that patch totals reproduce the per-subfireshed LANDFIRE totals
check_patches <- function(patches, project_stats, tol = 0.005) {
  a <- stats::aggregate(cbind(area_ac, afn_ac) ~ project_id, patches, sum)
  m <- merge(project_stats[, c("project_id", "treatable_ac", "afn_ac")], a,
             by = "project_id", all.x = TRUE, suffixes = c("", "_patch"))
  m <- m[m$treatable_ac > 0, ]
  m$area_ac[is.na(m$area_ac)] <- 0
  rel <- function(x, y) abs(sum(x) - sum(y)) / max(sum(y), 1)
  out <- list(area_rel = rel(m$area_ac, m$treatable_ac),
              afn_rel = rel(m$afn_ac_patch, m$afn_ac),
              n_projects = nrow(m),
              n_missing = sum(m$area_ac == 0))
  if (out$area_rel > tol || out$afn_rel > tol) {
    stop(sprintf("patch totals differ from LANDFIRE stats: area %.3f%%, AFN %.3f%%",
                 100 * out$area_rel, 100 * out$afn_rel))
  }
  out
}

#' Size distribution tables
#'
#' @return data.frame by owner_group x wui x size_bin: patches, units,
#'   area_ac (treatable) and afn_ac (annual need)
unit_size_distribution <- function(burn_units) {
  d <- stats::aggregate(cbind(n_units, area_ac, afn_ac) ~ owner_group + wui + size_bin,
                        burn_units, sum)
  d[order(d$owner_group, d$wui, d$size_bin), ]
}

# ---- TWIGS comparison ----------------------------------------------------

#' Past broadcast burns from the TWIGS Treatment Index (attributes only)
fetch_twigs_burns <- function(tcfg) {
  ensure_dir(dirname(tcfg$cache))
  if (file.exists(tcfg$cache)) return(utils::read.csv(tcfg$cache, stringsAsFactors = FALSE))
  base <- paste0(sub("/$", "", tcfg$url), "/query")
  where <- utils::URLencode(sprintf("state='%s' AND activity LIKE 'Broadcast Burning%%'",
                                    tcfg$state), reserved = TRUE)
  page <- 1000L; off <- 0L; out <- list()
  repeat {
    url <- paste0(base, "?where=", where, "&outFields=objectid%2Cacres%2Ctreatment_date",
                  "%2Cagency%2Cstatus%2Cmethod%2Cname&returnGeometry=false",
                  "&orderByFields=objectid&resultOffset=", off,
                  "&resultRecordCount=", page, "&f=json")
    r <- with_retry(function() jsonlite::fromJSON(url))
    a <- r$features$attributes
    if (is.null(a) || nrow(a) == 0) break
    out[[length(out) + 1]] <- a
    if (nrow(a) < page) break
    off <- off + page
  }
  x <- do.call(rbind, out)
  x$date <- as.Date(as.POSIXct(x$treatment_date / 1000, origin = "1970-01-01", tz = "UTC"))
  x$year <- as.integer(format(x$date, "%Y"))
  utils::write.csv(x, tcfg$cache, row.names = FALSE)
  x
}

#' Clean TWIGS records: plausible dates, positive acres
clean_twigs <- function(x, min_year = 1990, max_year = as.integer(format(Sys.Date(), "%Y"))) {
  x <- x[!is.na(x$acres) & x$acres > 0 & !is.na(x$year) &
           x$year >= min_year & x$year <= max_year, ]
  x
}

#' Acre-weighted share by size bin: model (by owner) vs TWIGS
twigs_size_compare <- function(burn_units, twigs, params, owner = "USFS") {
  lev <- levels(size_bin_labels(1, params$size_bins))
  m <- burn_units[burn_units$owner == owner & !burn_units$wui, ]
  model <- tapply(m$area_ac, m$size_bin, sum)
  model[is.na(model)] <- 0
  tw <- twigs
  tw$bin <- size_bin_labels(tw$acres, params$size_bins)
  tw_ac <- tapply(tw$acres, tw$bin, sum); tw_ac[is.na(tw_ac)] <- 0
  tw_n <- tapply(tw$acres, tw$bin, length); tw_n[is.na(tw_n)] <- 0
  out <- data.frame(size_bin = factor(lev, levels = lev),
                    model_ac = as.numeric(model[lev]),
                    twigs_ac = as.numeric(tw_ac[lev]),
                    twigs_n = as.numeric(tw_n[lev]))
  out$model_share <- out$model_ac / sum(out$model_ac)
  out$twigs_share <- out$twigs_ac / sum(out$twigs_ac)
  out
}
