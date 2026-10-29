# State rollup of resource needs using burn-day timing (synchrony).
#
# Each project needs rate_p,r = resource_days_yr / mean burn days resources
# on each of its burn days. Statewide daily demand is the sum over projects
# that are in a burn window that day, so projects whose windows do not
# overlap are not double counted.

#' Daily statewide demand matrix [day, resource]
daily_state_demand <- function(B, resources, rx_target) {
  ids <- as.integer(colnames(B))
  bd <- rx_target$bd_mean[match(ids, rx_target$project_id)]
  rt <- sort(unique(resources$resource))
  R <- matrix(0, length(ids), length(rt), dimnames = list(colnames(B), rt))
  i <- match(resources$project_id, ids)
  ok <- !is.na(i)
  R[cbind(i[ok], match(resources$resource[ok], rt))] <- resources$resource_days_yr[ok]
  rate <- R / ifelse(is.na(bd) | bd <= 0, NA, bd)
  rate[is.na(rate)] <- 0
  D <- (B * 1.0) %*% rate
  rownames(D) <- rownames(B)
  D
}

#' Weekly and annual summaries of daily state demand
summarise_state_demand <- function(D, B, n_weeks = 52L) {
  dates <- as.Date(rownames(D))
  yr <- as.integer(format(dates, "%Y"))
  wk <- doy_week(dates, n_weeks)
  long <- data.frame(date = rep(dates, ncol(D)), year = rep(yr, ncol(D)),
                     week = rep(wk, ncol(D)),
                     resource = rep(colnames(D), each = nrow(D)),
                     demand = as.vector(D))
  weekly <- as.data.frame(dplyr::summarise(
    dplyr::group_by(long, .data$resource, .data$week),
    mean = mean(.data$demand),
    p90 = stats::quantile(.data$demand, 0.9, names = FALSE),
    max = max(.data$demand), .groups = "drop"))
  # year classes by statewide total project burn days (terciles)
  tot <- tapply(rowSums(B), yr, sum)
  q <- stats::quantile(tot, c(1 / 3, 2 / 3), names = FALSE)
  cls <- ifelse(tot <= q[1], "poor", ifelse(tot >= q[2], "good", "typical"))
  if (length(tot) < 3) cls[] <- "typical"
  annual <- as.data.frame(dplyr::summarise(
    dplyr::group_by(long, .data$resource, .data$year),
    peak = max(.data$demand),
    p95 = stats::quantile(.data$demand, 0.95, names = FALSE),
    resource_days = sum(.data$demand), .groups = "drop"))
  annual$year_class <- unname(cls[as.character(annual$year)])
  annual$state_burn_days <- as.numeric(tot[as.character(annual$year)])
  peak_season <- as.data.frame(dplyr::summarise(
    dplyr::group_by(weekly, .data$resource),
    peak_week = .data$week[which.max(.data$mean)],
    peak_week_mean = max(.data$mean), .groups = "drop"))
  list(weekly = weekly, annual = annual, peak_season = peak_season)
}
