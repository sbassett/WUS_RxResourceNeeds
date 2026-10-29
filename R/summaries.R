# Predictability and synchrony of project burn days.

#' P(>= k burn days in week w) across years, per project
weekly_exceedance <- function(weekly, k = 1:6) {
  out <- lapply(k, function(kk) {
    s <- dplyr::summarise(dplyr::group_by(weekly, .data$project_id, .data$week),
                          p = mean(.data$burn_days >= kk), n_years = dplyr::n(),
                          .groups = "drop")
    s$k <- kk
    s
  })
  as.data.frame(dplyr::bind_rows(out))
}

#' Interannual variability of annual burn days, per project
burn_day_variability <- function(annual) {
  s <- dplyr::summarise(dplyr::group_by(annual, .data$project_id),
                        mean_bd = mean(.data$burn_days),
                        sd_bd = if (dplyr::n() > 1) stats::sd(.data$burn_days) else NA_real_,
                        p25_bd = stats::quantile(.data$burn_days, 0.25, names = FALSE),
                        p75_bd = stats::quantile(.data$burn_days, 0.75, names = FALSE),
                        mean_pixel_days = mean(.data$pixel_mean_days),
                        n_years = dplyr::n(), .groups = "drop")
  s$cv_bd <- ifelse(s$mean_bd > 0, s$sd_bd / s$mean_bd, NA_real_)
  as.data.frame(s)
}

#' Burn-day matrix [day, project] (0/1, NA -> 0) from the daily table
burn_day_matrix <- function(daily, threshold = 0.5) {
  d <- daily
  d$b <- as.integer(!is.na(d$rx_share) & d$rx_share >= threshold)
  ids <- sort(unique(d$project_id))
  dates <- sort(unique(d$date))
  m <- matrix(0L, length(dates), length(ids),
              dimnames = list(as.character(dates), as.character(ids)))
  m[cbind(match(d$date, dates), match(d$project_id, ids))] <- d$b
  m
}

#' Pairwise Jaccard overlap of burn-day series: |A and B| / |A or B|
jaccard_matrix <- function(B) {
  B <- B * 1.0
  I <- crossprod(B)
  n <- colSums(B)
  U <- outer(n, n, `+`) - I
  J <- I / U
  J[U == 0] <- NA_real_
  J
}

#' Pairwise correlation of weekly burn-day counts (year-week series)
weekly_count_cor <- function(B, n_weeks = 52L) {
  dates <- as.Date(rownames(B))
  key <- paste(format(dates, "%Y"), doy_week(dates, n_weeks))
  W <- rowsum(B * 1.0, key, reorder = FALSE)
  suppressWarnings(stats::cor(W))
}

#' Long upper-triangle synchrony table
synchrony_table <- function(daily, threshold = 0.5, n_weeks = 52L) {
  B <- burn_day_matrix(daily, threshold)
  J <- jaccard_matrix(B)
  C <- weekly_count_cor(B, n_weeks)
  ut <- which(upper.tri(J), arr.ind = TRUE)
  ids <- as.integer(colnames(B))
  data.frame(project_a = ids[ut[, 1]], project_b = ids[ut[, 2]],
             jaccard = J[ut], weekly_cor = C[ut])
}
