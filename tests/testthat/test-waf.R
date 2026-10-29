test_that("unsheltered WAF matches Andrews 2012 equation values", {
  expect_equal(waf_unsheltered(1), 1.83 / log(20.36 / 0.13))
  expect_equal(waf_unsheltered(1), 0.362, tolerance = 1e-3)
  expect_equal(waf_unsheltered(6), 0.547, tolerance = 1e-3)
  expect_equal(waf_unsheltered(0.4), 0.307, tolerance = 1e-3)
  expect_true(is.na(waf_unsheltered(NA)))
  expect_true(is.na(waf_unsheltered(0)))
})

test_that("sheltered WAF example", {
  # CC 50 %, H 60 ft, crown ratio 0.5 -> f = 0.0833
  expect_equal(crown_fill_portion(50, 60, 30), 0.5 * 0.5 / 3)
  expect_equal(waf_sheltered(50, 60, 30), 0.148, tolerance = 1e-3)
})

test_that("sheltered/unsheltered switch at f = 0.05 and H = 6 ft", {
  # cbh = 0 -> crown ratio 1, f = cc/300
  just_below <- waf_select(1, 14.9, 60, 0)    # f = 0.0497
  just_above <- waf_select(1, 15.1, 60, 0)    # f = 0.0503
  expect_equal(just_below, waf_unsheltered(1))
  expect_equal(just_above, waf_sheltered(15.1, 60, 0))
  expect_equal(waf_select(1, 80, 5, 0), waf_unsheltered(1))   # short canopy
  expect_equal(waf_select(1, NA, NA, NA), waf_unsheltered(1))
})

test_that("non-burnable gives NA", {
  t <- read_waf_table(root_file("config/waf_fbfm40.csv"))
  d <- t$fuel_bed_depth_ft[match(c(91, 99, 101), t$code)]
  w <- waf_select(d, c(80, 80, 0), c(60, 60, 0), c(10, 10, 0))
  expect_true(all(is.na(w[1:2])))
  expect_false(is.na(w[3]))
  expect_true(all(t$burnable == !is.na(t$fuel_bed_depth_ft)))
  expect_equal(nrow(t), 45)
})

test_that("mid-flame wind", {
  expect_equal(midflame_wind(11.5, 0.4), 4)
  expect_equal(midflame_wind(11.5, 0.4, afternoon_factor = 1.5), 6)
})
