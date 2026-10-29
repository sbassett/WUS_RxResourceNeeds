test_that("treatable EVT codes follow include/exclude patterns", {
  evt <- data.frame(Value = 1:6, EVT_NAME = c(
    "Southern Rocky Mountain Ponderosa Pine Woodland",
    "Southern Rocky Mountain Dry-Mesic Montane Mixed Conifer Forest and Woodland",
    "Southern Rocky Mountain Pinyon-Juniper Woodland",
    "Rocky Mountain Subalpine Dry-Mesic Spruce-Fir Forest and Woodland",
    "Developed-Upland Evergreen Forest",
    "Madrean Pine-Oak Forest and Woodland"), stringsAsFactors = FALSE)
  codes <- treatable_evt_codes(evt, root_file("config/treatable_classes.csv"))
  expect_equal(codes$code, c(1L, 2L, 6L))
})

test_that("slope and wilderness filters", {
  treat <- c(1L, 1L, 1L, 0L, 1L)
  slope <- c(5, 14, 15, 5, NA)        # 25 % = 14.04 deg
  w <- c(0, 0, 0, 0, 1)
  expect_equal(apply_treatable_filters(treat, slope, 25), c(1L, 1L, 0L, 0L, 1L))
  expect_equal(apply_treatable_filters(treat, wilderness = w), c(1L, 1L, 1L, 0L, 0L))
  expect_equal(apply_treatable_filters(treat), treat)
})

test_that("minimum patch size", {
  expect_equal(min_patch_cells(20), 90)            # 20 ac / 0.2224 ac
  r <- terra::rast(nrows = 6, ncols = 6, xmin = 0, xmax = 180, ymin = 0, ymax = 180,
                   crs = "EPSG:5070")
  m <- matrix(0L, 6, 6)
  m[1:3, 1:3] <- 1L      # 9-cell patch
  m[6, 6] <- 1L          # 1-cell patch
  m[5, 1] <- NA
  terra::values(r) <- as.vector(t(m))
  out <- remove_small_patches(r, 5)
  o <- matrix(terra::values(out)[, 1], 6, byrow = TRUE)
  expect_equal(sum(o, na.rm = TRUE), 9)
  expect_equal(o[6, 6], 0)
  expect_true(is.na(o[5, 1]))
})

test_that("modal fuel by zone prefers treatable pixels and falls back", {
  fq <- data.frame(zone = c(1, 1, 1, 2, 2, 3),
                   treat = c(1, 0, 0, 0, 0, 1),
                   fbfm = c(165, 102, 102, 102, 91, 91),
                   count = c(10, 50, 50, 5, 100, 10))
  m <- modal_fuel_by_zone(fq, burnable_codes = c(102, 165))
  expect_equal(m$zone, c(1, 2))
  expect_equal(m$fbfm, c(165, 102))           # treatable modal; fallback ignores NB
  expect_equal(m$from_treatable, c(TRUE, FALSE))
})
