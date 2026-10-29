test_that("Jaccard overlap", {
  B <- cbind(a = c(1, 1, 0, 0), b = c(1, 0, 1, 0), c = c(0, 0, 0, 0))
  J <- jaccard_matrix(B)
  expect_equal(J["a", "b"], 1 / 3)
  expect_equal(J["a", "a"], 1)
  expect_true(is.na(J["c", "c"]))
  expect_equal(J["a", "c"], 0)
})

test_that("burn-day matrix and synchrony table", {
  dates <- as.Date("2021-01-01") + 0:13
  daily <- rbind(
    data.frame(project_id = 1L, date = dates, rx_share = rep(c(1, 0), 7)),
    data.frame(project_id = 2L, date = dates, rx_share = rep(c(1, 0), 7)),
    data.frame(project_id = 3L, date = dates, rx_share = rep(c(0, 1), 7)))
  B <- burn_day_matrix(daily, 0.5)
  expect_equal(dim(B), c(14L, 3L))
  s <- synchrony_table(daily, 0.5)
  expect_equal(nrow(s), 3)
  expect_equal(s$jaccard[s$project_a == 1 & s$project_b == 2], 1)
  expect_equal(s$jaccard[s$project_a == 1 & s$project_b == 3], 0)
})

test_that("weekly exceedance probabilities", {
  weekly <- data.frame(project_id = 1L, year = 2001:2004, week = 10L,
                       burn_days = c(0, 2, 3, 6))
  e <- weekly_exceedance(weekly, 1:6)
  expect_equal(e$p[order(e$k)], c(0.75, 0.75, 0.5, 0.25, 0.25, 0.25))
  expect_equal(unique(e$n_years), 4L)
})

test_that("interannual variability", {
  annual <- data.frame(project_id = 1L, year = 2001:2004, burn_days = c(10, 20, 30, 40),
                       pixel_mean_days = c(12, 18, 33, 37))
  v <- burn_day_variability(annual)
  expect_equal(v$mean_bd, 25)
  expect_equal(v$cv_bd, sd(c(10, 20, 30, 40)) / 25)
  expect_equal(v$p25_bd, 17.5)
})
