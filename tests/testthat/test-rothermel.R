skip_if_not_installed("Rothermel")

mph <- c(0, 2, 4, 6, 8, 10, 12)

# Published SW Coordination Center reference tables for Anderson fuel model 1
# (chains/hr, mid-flame wind in mi/h, rows are 1-hr fuel moisture %).
# Cells at or above the traditional wind limit (asterisked in the source) are
# excluded below, since the package applies the Andrews et al. (2013) limit.
pub_ros_0 <- rbind(`3` = c(5, 22, 77, 172, 307, 446, 446), `6` = c(4, 18, 61, 135, 242, 270, 270),
                   `9` = c(3, 13, 45, 101, 136, 136, 136))
pub_ros_30 <- rbind(`3` = c(25, 42, 97, 191, 327, 446, 446), `6` = c(20, 33, 76, 151, 257, 270, 270),
                    `9` = c(15, 25, 57, 112, 136, 136, 136))
pub_fl_0 <- rbind(`3` = c(1.3, 2.5, 4.5, 6.4, 8.4), `6` = c(1.1, 2.1, 3.8, 5.4, 7.1),
                  `9` = c(0.9, 1.7, 3.0, 4.3, NA))

run_a1 <- function(m1, mph_wind, slope) {
  rothermel_run("A1", c(m1, m1 + 1, m1 + 2, 100, 100), mph_wind * 1.609344, slope)
}

test_that("Rothermel matches published Anderson FM1 rates of spread below the wind limit", {
  for (slope in c(0, 30)) {
    pub <- if (slope == 0) pub_ros_0 else pub_ros_30
    below <- pub < apply(pub, 1, max)
    mine <- t(sapply(rownames(pub), function(r) sapply(mph, function(u)
      run_a1(as.numeric(r), u, slope)$ros_m_min * ch_per_m_min)))
    rel <- (mine - pub)[below] / pub[below]
    expect_lt(max(abs(rel)), 0.06)          # within 6 % (observed <= ~5 %)
  }
})

test_that("fuel moisture above extinction stops spread", {
  r <- run_a1(12, 6, 0)                      # FM1 extinction moisture is 12 %
  expect_equal(r$ros_m_min, 0)
  expect_equal(r$flame_m, 0)
})

test_that("Byram flame length matches published values", {
  fl <- t(sapply(rownames(pub_fl_0), function(r) sapply(mph[1:5], function(u)
    run_a1(as.numeric(r), u, 0)$flame_m * ft_per_m)))
  ok <- !is.na(pub_fl_0)
  expect_lt(max(abs((fl - pub_fl_0)[ok] / pub_fl_0[ok])), 0.05)
})

test_that("rate of spread rises with wind and slope and falls with moisture", {
  sfm <- sfm_table()
  g <- function(m, u, s) rothermel_run("SH5", c(m, m + 2, m + 3, 120, 150), u, s, sfm)$ros_m_min
  expect_gt(g(6, 10, 0), g(6, 0, 0))
  expect_gt(g(6, 10, 20), g(6, 10, 0))
  expect_gt(g(4, 10, 0), g(10, 10, 0))
})

test_that("live moisture matters for grass but not for timber litter", {
  hot <- function(fm, h, w) rothermel_run(fm, c(4, 6, 7.5, h, w), 16.2, 0)$ros_m_min
  expect_gt(hot("GR2", 30, 60), 10 * hot("GR2", 120, 150))     # cured vs green
  expect_equal(hot("TL3", 30, 60), hot("TL3", 120, 150))
})

test_that("scenarios come from the threshold table", {
  th <- load_thresholds(root_file("config/burn_thresholds.yml"), "forest")
  sc <- rx_scenarios(th)
  expect_equal(sc$scenario, c("cool", "mid", "hot"))
  expect_equal(sc$fm1, c(12, 8, 4))
  expect_equal(sc$fm10, c(14, 10, 6))
  expect_equal(sc$fm100, c(15, 11.25, 7.5))
  expect_equal(sc$wind_ms, c(0, 2.25, 4.5))
  expect_equal(sc$wind_kmh, c(0, 8.1, 16.2))
  bad <- th[th$statistic != "fm10", ]
  expect_error(rx_scenarios(bad), "fm10")
})

test_that("lookup has the right shape and cool <= mid <= hot", {
  th <- load_thresholds(root_file("config/burn_thresholds.yml"), "forest")
  wt <- read_waf_table(root_file("config/waf_fbfm40.csv"))
  cfg <- yaml::read_yaml(root_file("config/pipeline.yml"))$fire_behavior
  cfg$slopes_pct <- c(0, 25)
  lk <- rothermel_lookup(th, wt, cfg)
  expect_equal(nrow(lk), sum(wt$burnable) * 3 * 4 * 2)
  expect_false(anyNA(lk$ros_chhr)); expect_false(anyNA(lk$flame_ft))
  expect_true(all(lk$ros_chhr >= 0 & lk$flame_ft >= 0))
  w <- reshape(lk[lk$live == "L1" & lk$slope_pct == 0, c("code", "scenario", "ros_chhr")],
               idvar = "code", timevar = "scenario", direction = "wide")
  expect_true(all(w$ros_chhr.cool <= w$ros_chhr.mid + 1e-9))
  expect_true(all(w$ros_chhr.mid <= w$ros_chhr.hot + 1e-9))
  # flame length is zero exactly when there is no spread
  expect_equal(lk$flame_ft == 0, lk$ros_chhr == 0)
})

test_that("interpolation between slope bins and handling of unknown models", {
  tab <- list(codes = c(101L, 102L), slopes = c(0, 10, 20),
              m = rbind(c(0, 10, 40), c(5, 5, 5)))
  expect_equal(interp_fb(c(101, 101, 101, 102), c(0, 5, 15, 30), tab), c(0, 5, 25, 5))
  expect_true(is.na(interp_fb(91, 5, tab)))          # non-burnable / absent
  expect_equal(interp_fb(101, NA, tab), 0)           # missing slope = flat
  expect_equal(interp_fb(101, 100, tab), 40)         # clamped to table range
})

test_that("flame length classes follow the 4 and 8 ft breaks", {
  expect_equal(flame_class(c(0, 3.9, 4, 4.1, 8, 8.1)), c(1L, 1L, 1L, 2L, 2L, 3L))
})

test_that("slope conversion", {
  expect_equal(slope_deg_to_pct(c(0, 45)), c(0, 100))
})

test_that("patch fire behavior summarises means, classes and modal fuel model", {
  # one patch of 4 cells (ids 1); one cell cannot carry fire (NA)
  ok <- rep(TRUE, 4); ids <- rep(1L, 4)
  attrs <- list(ros_cool = c(1, 2, 3, NA), ros_hot = c(10, 20, 30, NA),
                fl_cool = c(1, 5, 9, NA), fl_hot = c(2, 6, 12, NA), fbfm = c(101, 101, 122, 91))
  p <- patch_fire_behavior(attrs, ok, ids)
  expect_equal(p$ros_hot_chhr, 20)
  expect_equal(p$burnable_cells, 3)
  expect_equal(c(p$cells_fl_cool_0_4, p$cells_fl_cool_4_8, p$cells_fl_cool_8p), c(1, 1, 1))
  expect_equal(p$modal_fbfm, 101L)
})
