test_that("days in year", {
  expect_equal(days_in_year(c(2019, 2020, 1900, 2000)), c(365L, 366L, 365L, 366L))
})

test_that("gridMET checks catch wrong layer counts and ranges", {
  r <- terra::rast(nrows = 2, ncols = 2, nlyrs = 365)
  terra::values(r) <- 290
  expect_silent(check_gridmet(r, "tmmx", 2021))
  expect_error(check_gridmet(r, "tmmx", 2020), "expected 366")
  terra::values(r) <- 400
  expect_error(check_gridmet(r, "tmmx", 2021), "plausible range")
})

test_that("gridMET year file lookup", {
  f <- c("x/tmmx_2020.tif", "x/rmin_2020.tif", "x/tmmx_2021.tif")
  expect_equal(gridmet_year_files(f, 2020), list(tmmx = "x/tmmx_2020.tif",
                                                 rmin = "x/rmin_2020.tif"))
  # names as targets returns them for aggregated file branches
  n <- c(b_1 = "d/fm1_2020.tif", b_2 = "d/fm10_2020.tif", c_1 = "d/fm1_2021.tif")
  expect_equal(nfdrs_year_files(n, 2020), c(fm1 = "d/fm1_2020.tif", fm10 = "d/fm10_2020.tif"))
})

test_that("LANDFIRE tiles cover the bbox", {
  t <- make_lonlat_tiles(c(-109.3, 31.2, -102.8, 37.2), 1)
  b <- do.call(rbind, lapply(t, `[[`, "bbox"))
  expect_equal(min(b[, 1]), -109.3); expect_equal(max(b[, 3]), -102.8)
  expect_equal(min(b[, 2]), 31.2); expect_equal(max(b[, 4]), 37.2)
  expect_true(all(b[, 1] < b[, 3] & b[, 2] < b[, 4]))
  expect_false(anyDuplicated(vapply(t, `[[`, "", "id")) > 0)
})

test_that("project area validation", {
  sq <- function(x0) sf::st_polygon(list(rbind(c(x0, 0), c(x0 + 1, 0), c(x0 + 1, 1),
                                               c(x0, 1), c(x0, 0))))
  x <- sf::st_sf(project_id = 1:2, geom = sf::st_sfc(sq(0), sq(2), crs = 5070))
  expect_true(validate_project_areas(x, 5070))
  x2 <- x; x2$project_id <- c(1L, 1L)
  expect_error(validate_project_areas(x2, 5070), "not unique")
  expect_error(validate_project_areas(x[0, ], 5070), "no project areas")
  expect_error(validate_project_areas(sf::st_transform(x, 4326), 5070), "CRS")
})
