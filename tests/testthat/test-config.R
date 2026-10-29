test_that("pipeline config loads with required keys", {
  cfg <- read_pipeline_config(root_file("config/pipeline.yml"))
  expect_true(all(required_pipeline_keys %in% names(cfg)))
  expect_equal(cfg$year_list, seq(cfg$years$start, cfg$years$end))
  expect_equal(cfg$crs, 5070)
})

test_that("pipeline config validation catches bad values", {
  cfg <- yaml::read_yaml(root_file("config/pipeline.yml"))
  f <- tempfile(fileext = ".yml")
  bad <- cfg; bad$years$start <- 2025; bad$years$end <- 2020
  yaml::write_yaml(bad, f)
  expect_error(read_pipeline_config(f), "years")
  bad <- cfg; bad$gridmet <- NULL
  yaml::write_yaml(bad, f)
  expect_error(read_pipeline_config(f), "gridmet")
  bad <- cfg; bad$rollup$burn_day_share <- 1.5
  yaml::write_yaml(bad, f)
  expect_error(read_pipeline_config(f), "burn_day_share")
})

test_that("thresholds load and convert units", {
  th <- load_thresholds(root_file("config/burn_thresholds.yml"), "forest")
  expect_true(all(c("tmmx", "rmin", "midflame", "fm1", "fm10", "fm100", "fm1000") %in%
                    th$statistic))
  expect_false("ic" %in% th$statistic)            # disabled in v1
  expect_equal(th$min[th$statistic == "tmmx"], 7.2)
  expect_equal(th$max[th$statistic == "midflame"], 4.5)
  nf <- load_thresholds(root_file("config/burn_thresholds.yml"), "nonforest")
  expect_false("fm100" %in% nf$statistic)        # "–" in ST1
})

write_thr <- function(entry) {
  f <- tempfile(fileext = ".yml")
  yaml::write_yaml(list(thresholds = list(entry)), f)
  f
}

test_that("threshold validation rejects bad configs", {
  base <- list(variable = "t", statistic = "tmmx", units = "degC", enabled = TRUE,
               forest = list(min = 5, max = 30))
  expect_silent(load_thresholds(write_thr(base)))
  b <- base; b$forest <- list(min = 30, max = 5)
  expect_error(load_thresholds(write_thr(b)), "min must be < max")
  b <- base; b$statistic <- "bogus"
  expect_error(load_thresholds(write_thr(b)), "unknown threshold statistic")
  b <- base; b$units <- "furlongs"
  expect_error(load_thresholds(write_thr(b)), "unknown units")
  b <- base; b$forest <- NULL
  expect_error(load_thresholds(write_thr(b)), "no `forest` bounds")
  expect_error(load_thresholds(write_thr(base), "nope"), "plan_set")
})

test_that("unit conversions", {
  expect_equal(k_to_c(273.15), 0)
  expect_equal(c_to_f(100), 212)
  expect_equal(f_to_c(32), 0)
  expect_equal(mph_to_ms(10), 4.4704)
  expect_equal(ms_to_mph(mph_to_ms(7)), 7)
  expect_equal(m_to_ft(ft_to_m(20)), 20)
  expect_equal(to_internal_units(212, "degF"), 100)
  expect_equal(to_internal_units(10, "mph"), 4.4704)
  b <- list(variable = "t", statistic = "tmmx", units = "degF", enabled = TRUE,
            forest = list(min = 32, max = 212))
  th <- load_thresholds(write_thr(b))
  expect_equal(c(th$min, th$max), c(0, 100))
})

test_that("day-of-year weeks are fixed 7-day bins folding into week 52", {
  d <- as.Date(c("2021-01-01", "2021-01-07", "2021-01-08", "2021-12-30",
                 "2021-12-31", "2020-12-31"))
  expect_equal(doy_week(d), c(1L, 1L, 2L, 52L, 52L, 52L))
})
