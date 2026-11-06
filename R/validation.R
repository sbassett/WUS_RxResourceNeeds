# Comparison of the modelled timing of burn days with the timing of actual
# Forest Service broadcast burns in the TWIGS Treatment Index.
#
# Modelled: share of unit burn days in each month, with each unit weighted by
# its annual need (AFN) so large-need units count more.
# Observed: share of completed broadcast burn acres (and burn counts) by month.
# Observed burning also reflects staffing, smoke management and closures, so
# it is not a pure weather-window benchmark; large mismatches are a prompt to
# look for missing constraints, not proof of error.

season_levels <- c("Dec-Mar (dormant)", "Apr-Jun (spring, green-up)",
                   "Jul-Sep (monsoon)", "Oct-Nov (fall)")

season_of_month <- function(month) {
  s <- ifelse(month %in% c(12, 1, 2, 3), season_levels[1],
       ifelse(month %in% c(4, 5, 6), season_levels[2],
       ifelse(month %in% c(7, 8, 9), season_levels[3], season_levels[4])))
  factor(s, levels = season_levels)
}

#' Monthly comparison of modelled burn days and observed burns
#'
#' @param daily daily rollup table (project_id, date, rx_share, rx_acres)
#' @param rx_target per-unit table with afn_ac
#' @param rollup_cfg `rollup` config (burn-day rule)
#' @param twigs cleaned TWIGS records (acres, date)
#' @return data.frame(month, season, modeled_share, observed_acre_share,
#'   observed_burn_share), shares summing to 1 across months
burn_season_compare <- function(daily, rx_target, rollup_cfg, twigs) {
  d <- daily[, c("project_id", "date", "rx_share", "rx_acres")]
  d$bd <- flag_burn_days(d, rollup_cfg)
  d <- d[!is.na(d$bd) & d$bd == 1, ]
  d$month <- as.integer(format(d$date, "%m"))
  d <- merge(d, rx_target[, c("project_id", "afn_ac")], by = "project_id")
  modeled <- tapply(d$afn_ac, factor(d$month, levels = 1:12), sum)
  modeled[is.na(modeled)] <- 0
  tw_month <- factor(as.integer(format(as.Date(twigs$date), "%m")), levels = 1:12)
  obs_ac <- tapply(twigs$acres, tw_month, sum); obs_ac[is.na(obs_ac)] <- 0
  obs_n <- tapply(twigs$acres, tw_month, length); obs_n[is.na(obs_n)] <- 0
  out <- data.frame(month = 1:12,
                    modeled_share = as.numeric(modeled) / sum(modeled),
                    observed_acre_share = as.numeric(obs_ac) / sum(obs_ac),
                    observed_burn_share = as.numeric(obs_n) / sum(obs_n))
  out$season <- season_of_month(out$month)
  out[, c("month", "season", "modeled_share", "observed_acre_share", "observed_burn_share")]
}

#' Seasonal summary of burn_season_compare()
burn_season_summary <- function(cmp) {
  s <- stats::aggregate(cbind(modeled_share, observed_acre_share, observed_burn_share) ~ season,
                        cmp, sum)
  s$difference <- s$modeled_share - s$observed_acre_share
  s[order(s$season), ]
}
