write_csv_tmp <- function(df) {
  f <- tempfile(fileext = ".csv"); utils::write.csv(df, f, row.names = FALSE); f
}

test_that("treatable codes come from BPS and EVT crosswalks", {
  # two raster Values share BPS_CODE 10540 (different map zones)
  bps <- data.frame(Value = c(1, 2, 3, 4), BPS_CODE = c(10540, 10540, 10590, 11),
                    BPS_NAME = c("PIPO", "PIPO", "PJ", "Water"), stringsAsFactors = FALSE)
  evt <- data.frame(Value = c(10, 20, 30), EVT_PHYS = c("Conifer", "Shrubland", "Developed"),
                    EVT_NAME = c("a", "b", "c"), stringsAsFactors = FALSE)
  bf <- write_csv_tmp(data.frame(BPS_CODE = c(10540, 10590, 11),
                                 treatable = c(TRUE, FALSE, FALSE)))
  ef <- write_csv_tmp(data.frame(EVT_PHYS = c("Conifer", "Shrubland", "Developed"),
                                 treatable = c(TRUE, TRUE, FALSE)))
  cc <- treatable_codes(bps, evt, bf, ef)
  expect_equal(cc$bps$code, c(1, 2))
  expect_equal(cc$evt$code, c(10, 20))      # current shrub stays treatable
})

test_that("crosswalks fail loudly on missing or undecided codes", {
  bf <- write_csv_tmp(data.frame(BPS_CODE = 10540, treatable = TRUE))
  expect_error(read_crosswalk(bf, "BPS_CODE", c(10540, 10590)), "no row for 1")
  bf2 <- write_csv_tmp(data.frame(BPS_CODE = 10540, treatable = NA))
  expect_error(read_crosswalk(bf2, "BPS_CODE", 10540), "TRUE or FALSE")
  bf3 <- write_csv_tmp(data.frame(BPS_CODE = c(1, 1), treatable = TRUE))
  expect_error(read_crosswalk(bf3, "BPS_CODE", 1), "duplicate")
})

test_that("shipped crosswalks encode the agreed decisions", {
  bx <- read_crosswalk(root_file("config/treatable_bps.csv"), "BPS_CODE", integer())
  yes <- c(10540, 10541, 11170, 11171,   # ponderosa woodland / savanna
           10510, 10520,                 # dry-mesic and mesic mixed conifer
           10240, 10260, 10230,          # Madrean pine-oak, conifer-oak, Encinal
           10110, 10610, 10611, 10612)   # aspen, aspen-mixed conifer
  no <- c(10590, 11160, 11190, 10550, 10560)   # PJ, juniper, spruce-fir
  expect_true(all(bx$treatable[match(yes, bx$BPS_CODE)]))
  expect_false(any(bx$treatable[match(no, bx$BPS_CODE)]))
  ex <- read_crosswalk(root_file("config/treatable_evt_phys.csv"), "EVT_PHYS", character())
  t <- stats::setNames(ex$treatable, ex$EVT_PHYS)
  expect_true(all(t[c("Conifer", "Shrubland", "Grassland")]))
  expect_false(any(t[c("Developed", "Agricultural", "Riparian", "Open Water")]))
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
