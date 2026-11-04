params <- read_downstream_params(root_file("config/downstream_params.yml"))

test_that("Rx target hand calculation and zero-burn-day flag", {
  ps <- data.frame(project_id = 1:3, treatable_ac = c(1000, 0, 500),
                   afn_ac = c(100, 0, 50))
  v <- data.frame(project_id = c(1L, 3L), mean_bd = c(20, 0), p25_bd = c(10, 0),
                  p75_bd = c(25, 0))
  t <- compute_rx_target(ps, v)
  expect_equal(t$mfri_eff_yr[1], 10)
  expect_equal(t$bfn_typical[1], 5)
  expect_equal(t$bfn_poor[1], 10)
  expect_equal(t$bfn_good[1], 4)
  expect_equal(t$flag, c("", "no_treatable_area", "zero_burn_days"))
  expect_true(is.na(t$bfn_typical[3]))
})

# burn units: 2 patches, one WUI-heavy, with AFN proportional to area
bu <- data.frame(
  project_id = c(1L, 1L, 1L),
  patch_id   = c(1L, 1L, 2L),
  owner      = c("USFS", "USFS", "Private"),
  owner_group = c("Federal", "Federal", "Private/Other"),
  wui        = c(TRUE, FALSE, FALSE),
  n_units    = c(1, 2, 1),
  unit_ac    = c(400, 900, 300),
  area_ac    = c(400, 1800, 300),
  afn_ac     = c(40, 180, 30),
  below_min  = c(FALSE, FALSE, TRUE),
  size_bin   = c("201-400", "801-1200", "201-400"),
  stringsAsFactors = FALSE)

test_that("unit size x complexity schema and acre conservation", {
  u <- unit_size_complexity(bu, params)
  expect_named(u, c("project_id", "owner_group", "wui", "complexity", "size_bin",
                    "unit_ac", "acres", "n_units"), ignore.order = TRUE)
  # acres of need conserved across complexity split
  expect_equal(sum(u$acres), sum(bu$afn_ac))
  # complexity shares reproduce config
  cs <- unlist(params$complexity_share)
  expect_equal(sum(u$acres[u$complexity == "low"]) / sum(u$acres), unname(cs["low"]))
})

rx <- data.frame(project_id = 1:2, afn_ac = c(10000, 0), bd_mean = c(30, 0))

test_that("firing rules", {
  fp <- params$firing
  expect_equal(firing_rule(1500, "high", 0, fp), "heli")
  expect_equal(firing_rule(1000, "low", 0, fp), "drone")
  expect_equal(firing_rule(600, "high", 0, fp), "hand")      # no drones, high complexity
  expect_equal(firing_rule(600, "low", 0.9, fp), "hand")     # no drones, heavy fuels
  expect_equal(firing_rule(100, "low", 0, fp), "hand")
  # heli halves the hand-firing time
  expect_equal(firing_days(1500, "heli", fp), 1500 / fp$acres_per_day$hand * 0.5)
  expect_equal(firing_days(10, "hand", fp), 1)               # at least one day
  m <- firing_matrix(params)
  expect_equal(nrow(m), 7 * 3)
  expect_true(all(m$firing_method[m$unit_ac > 1000] == "heli"))
})

test_that("line production and resource mix schemas", {
  ps <- data.frame(project_id = 1L, heavy_fuel_share = 0)
  u <- line_production(firing_method(unit_size_complexity(bu, params), ps, params), params)
  expect_true(all(c("firing_method", "firing_days_per_unit", "line_production_ch_hr") %in%
                    names(u)))
  expect_true(is.numeric(u$line_production_ch_hr))
  r <- resource_mix(u, params)
  expect_named(r, c("project_id", "resource", "resource_days_yr"), ignore.order = TRUE)
  expect_true(all(c("engines", "crews", "helicopters", "drone_teams") %in% r$resource))
  expect_true(all(r$resource_days_yr >= 0))
})

test_that("state rollup equals sum of projects", {
  dates <- as.Date("2020-01-01") + 0:(366 * 2 - 1)
  set.seed(1)
  B <- matrix(rbinom(length(dates) * 3, 1, 0.2), ncol = 3,
              dimnames = list(as.character(dates), c("1", "2", "3")))
  yr <- format(dates, "%Y")
  bd <- colMeans(rowsum(B, yr))
  rxt <- data.frame(project_id = 1:3, bd_mean = bd)
  res <- data.frame(project_id = c(1L, 2L, 3L, 1L), resource = c("engines", "engines",
                    "engines", "crews"), resource_days_yr = c(100, 50, 20, 10))
  D <- daily_state_demand(B, res, rxt)
  n_years <- length(unique(yr))
  expect_equal(sum(D[, "engines"]), (100 + 50 + 20) * n_years)
  expect_equal(sum(D[, "crews"]), 10 * n_years)
  s <- summarise_state_demand(D, B)
  expect_equal(sum(s$annual$resource_days[s$annual$resource == "engines"]), 170 * n_years)
  expect_setequal(unique(s$weekly$week), 1:52)
})
