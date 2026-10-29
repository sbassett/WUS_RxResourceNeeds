# Annual Rx target (AFN) and burn-day fire need (BFN) per project area.
#
# AFN (ac/yr) = sum over treatable 30 m pixels of pixel_acres / MFRI_pixel,
# where MFRI is LANDFIRE BPS FRI_ALLFIR (all-fire mean return interval).
# This equals TA / MFRI_eff with MFRI_eff the area-weighted harmonic mean.
# BFN (ac/burn day) = AFN / burn days, for typical (mean), poor (25th pct),
# and good (75th pct) burn-day years.

safe_div <- function(a, b) ifelse(is.na(b) | b <= 0, NA_real_, a / b)

compute_rx_target <- function(project_stats, variability) {
  d <- merge(project_stats, variability, by = "project_id", all.x = TRUE)
  out <- data.frame(
    project_id = d$project_id,
    treatable_ac = d$treatable_ac,
    afn_ac = ifelse(d$treatable_ac > 0, d$afn_ac, 0),
    mfri_eff_yr = safe_div(d$treatable_ac, d$afn_ac),
    bd_mean = d$mean_bd, bd_poor = d$p25_bd, bd_good = d$p75_bd
  )
  out$bfn_typical = safe_div(out$afn_ac, out$bd_mean)
  out$bfn_poor = safe_div(out$afn_ac, out$bd_poor)
  out$bfn_good = safe_div(out$afn_ac, out$bd_good)
  out$flag <- ifelse(out$treatable_ac <= 0, "no_treatable_area",
              ifelse(is.na(out$bd_mean), "no_burn_day_data",
              ifelse(out$bd_mean <= 0, "zero_burn_days", "")))
  out
}
