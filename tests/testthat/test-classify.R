th <- data.frame(variable = c("t", "rh", "w"), statistic = c("tmmx", "rmin", "midflame"),
                 min = c(5, 15, NA), max = c(30, 60, 4.5), enabled = TRUE)

test_that("each threshold acts in isolation", {
  ok <- list(tmmx = 20, rmin = 30, midflame = 2)
  expect_equal(classify_rx(ok, th), 1L)
  expect_equal(classify_rx(modifyList(ok, list(tmmx = 31)), th), 0L)
  expect_equal(classify_rx(modifyList(ok, list(tmmx = 4)), th), 0L)
  expect_equal(classify_rx(modifyList(ok, list(rmin = 61)), th), 0L)
  expect_equal(classify_rx(modifyList(ok, list(rmin = 14)), th), 0L)
  expect_equal(classify_rx(modifyList(ok, list(midflame = 4.6)), th), 0L)
})

test_that("bounds are inclusive and NA bound is unbounded", {
  expect_equal(classify_rx(list(tmmx = 5, rmin = 60, midflame = 4.5), th), 1L)
  expect_equal(classify_rx(list(tmmx = 30, rmin = 15, midflame = -100), th), 1L)
})

test_that("NA input gives NA; matrices keep shape", {
  L <- list(tmmx = matrix(c(20, NA, 20, 40), 2), rmin = matrix(30, 2, 2),
            midflame = matrix(c(1, 1, NA, 1), 2))
  out <- classify_rx(L, th)
  expect_equal(dim(out), c(2L, 2L))
  expect_equal(as.vector(out), c(1L, NA, NA, 0L))
})

test_that("missing layer errors", {
  expect_error(classify_rx(list(tmmx = 1), th), "missing layers")
})

test_that("classify_rx_year writes INT1U raster with NA", {
  d <- tempfile(); dir.create(d)
  dates <- as.Date("2021-01-01") + 0:1
  mk <- function(vals, name) {
    r <- terra::rast(nrows = 1, ncols = 2, nlyrs = 2, xmin = 0, xmax = 2, ymin = 0,
                     ymax = 1, crs = "EPSG:4326")
    terra::values(r) <- vals
    terra::time(r) <- dates
    f <- file.path(d, paste0(name, ".tif")); terra::writeRaster(r, f); f
  }
  # values matrix is [cell, layer]: cell1 d1, cell2 d1, cell1 d2, cell2 d2
  gm <- list(tmmx = mk(c(293, 293, 293, 320), "tmmx"), rmin = mk(30, "rmin"),
             vs = mk(c(5, 5, 5, 5), "vs"), fm100 = mk(10, "fm100"),
             fm1000 = mk(15, "fm1000"))
  nf <- c(fm1 = mk(8, "fm1"), fm10 = mk(10, "fm10"))
  w <- terra::rast(nrows = 1, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 1,
                   crs = "EPSG:4326")
  terra::values(w) <- c(0.3, NA); names(w) <- "waf"
  wf <- file.path(d, "waf.tif"); terra::writeRaster(w, wf)
  thr <- load_thresholds(root_file("config/burn_thresholds.yml"), "forest")
  # Andrews: cell 2 has no WAF (non-burnable) -> NA
  f <- classify_rx_year(2021, gm, nf, wf, thr,
                        list(method = "andrews", u10_to_u20ft = 1.15), d)
  v <- terra::values(terra::rast(f))
  expect_equal(unname(v[1, ]), c(1, 1))   # cell 1 in Rx both days
  expect_true(all(is.na(v[2, ])))
  # Swain: vs 5 x 1.5 x 0.4 = 3 m/s, no WAF needed; cell 2 day 2 too hot
  f <- classify_rx_year(2021, gm, nf, wf, thr,
                        list(method = "swain", afternoon_factor = 1.5,
                             swain_midflame_factor = 0.4), d)
  v <- terra::values(terra::rast(f))
  expect_equal(unname(v[1, ]), c(1, 1))
  expect_equal(unname(v[2, ]), c(1, 0))
})
