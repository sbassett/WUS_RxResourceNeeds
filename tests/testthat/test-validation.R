test_that("months map to the four seasons", {
  s <- season_of_month(1:12)
  expect_equal(as.character(s[c(1, 3, 4, 6, 7, 9, 10, 11, 12)]),
               season_levels[c(1, 1, 2, 2, 3, 3, 4, 4, 1)])
  expect_equal(levels(s), season_levels)
})

test_that("burn season comparison gives shares that sum to one", {
  # two units; unit 1 has 2 burn days in Jan, unit 2 has 1 in Jul and 1 in Jan
  daily <- data.frame(
    project_id = c(1L, 1L, 2L, 2L, 2L),
    date = as.Date(c("2021-01-05", "2021-01-06", "2021-07-10", "2021-01-07", "2021-03-01")),
    rx_share = c(1, 1, 1, 1, 0.1), rx_acres = c(500, 500, 600, 700, 10))
  rx <- data.frame(project_id = 1:2, afn_ac = c(100, 300))
  twigs <- data.frame(acres = c(1000, 3000), date = as.Date(c("2015-04-10", "2016-10-12")))
  cfg <- list(burn_day_rule = "acres", burn_day_acres = 441)
  cmp <- burn_season_compare(daily, rx, cfg, twigs)
  expect_equal(nrow(cmp), 12)
  expect_equal(sum(cmp$modeled_share), 1)
  expect_equal(sum(cmp$observed_acre_share), 1)
  expect_equal(sum(cmp$observed_burn_share), 1)
  # modelled: Jan = unit1 x2 (100 each) + unit2 x1 (300) = 500; Jul = 300; Mar not a burn day
  expect_equal(cmp$modeled_share[cmp$month == 1], 500 / 800)
  expect_equal(cmp$modeled_share[cmp$month == 7], 300 / 800)
  expect_equal(cmp$modeled_share[cmp$month == 3], 0)
  expect_equal(cmp$observed_acre_share[cmp$month == 10], 0.75)
  s <- burn_season_summary(cmp)
  expect_equal(sum(s$modeled_share), 1)
  expect_equal(as.character(s$season), season_levels)
})
