test_that("weighted share for a two-polygon case", {
  # 3 cells; project A covers cells 1-2 (weights 1, 3); B covers cell 3
  W <- Matrix::sparseMatrix(i = c(1, 1, 2), j = c(1, 2, 3), x = c(1, 3, 2),
                            dims = c(3, 3), dimnames = list(c("10", "20", "30"), NULL))
  X <- cbind(d1 = c(1, 0, 1), d2 = c(1, 1, 0), d3 = c(NA, 1, NA))
  s <- weighted_share(W, X)
  expect_equal(s[1, ], c(d1 = 0.25, d2 = 1, d3 = 1))
  expect_equal(unname(s[2, ]), c(1, 0, NA))
  expect_true(all(is.na(s[3, ])))                 # no treatable weight
  expect_true(all(s >= 0 & s <= 1, na.rm = TRUE))
})

test_that("project_cell_weights uses coverage x treatable fraction x area", {
  frac <- terra::rast(nrows = 2, ncols = 2, xmin = -106, xmax = -105.9, ymin = 35,
                      ymax = 35.1, crs = "EPSG:4326")
  terra::values(frac) <- c(1, 0, 0.5, NA)
  f <- tempfile(fileext = ".tif"); terra::writeRaster(frac, f)
  poly <- sf::st_sf(project_id = 7L, geom = sf::st_sfc(sf::st_polygon(list(rbind(
    c(-106, 35), c(-105.95, 35), c(-105.95, 35.1), c(-106, 35.1), c(-106, 35)))),
    crs = 4326))
  W <- project_cell_weights(poly, f)
  expect_equal(dim(W), c(1L, 4L))
  w <- as.vector(W)
  expect_gt(w[1], 0); expect_gt(w[3], 0)
  expect_equal(w[c(2, 4)], c(0, 0))
  expect_equal(w[3] / w[1], 0.5, tolerance = 0.01)
})

test_that("burn day counts", {
  daily <- data.frame(project_id = 1L,
                      date = as.Date("2021-01-01") + 0:9,
                      rx_share = c(0.6, 0.4, 0.5, NA, 1, 0, 0, 0.9, 0.2, 0.7))
  cc <- burn_day_counts(daily, 0.5)
  expect_equal(cc$annual$burn_days, 5)
  expect_equal(cc$annual$pixel_mean_days, sum(daily$rx_share, na.rm = TRUE))
  expect_equal(cc$annual$n_days, 9)
  expect_equal(cc$weekly$burn_days, c(3, 2))
})
