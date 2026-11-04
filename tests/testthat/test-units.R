params <- read_downstream_params(root_file("config/downstream_params.yml"))

test_that("owner classification prefers Own_Name, falls back to Mang then Type", {
  own_type <- c("FED", "FED", "STAT", "PVT", "LOC", "FED", "TRIB")
  own_name <- c("USFS", "BLM", "SLB", "PVT", "CITY", "UNK", "TRIB")
  mang_name <- c("USFS", "BLM", "SLB", "PVT", "CITY", "NPS", "TRIB")
  o <- classify_owner(own_type, own_name, mang_name)
  expect_equal(o, c("USFS", "BLM", "State", "Private", "Local", "NPS", "Tribal"))
  # unknown name + unknown manager -> fall back to type
  expect_equal(classify_owner("FED", "UNK", "UNK"), "OtherFed")
  expect_equal(classify_owner("PVT", "UNK", "UNK"), "Private")
  expect_true(all(classify_owner("UNK", "UNK", "UNK") == "Unknown"))
  expect_true(all(owner_from_name(c("USBR", "BIA", "DOE")) == "OtherFed"))
})

test_that("owner groups map to coarse federal / state-local / private", {
  expect_equal(unname(owner_groups[c("USFS", "BLM", "NPS")]), rep("Federal", 3))
  expect_equal(unname(owner_groups["Tribal"]), "Tribal")
  expect_equal(unname(owner_groups[c("State", "Local")]), rep("State/Local", 2))
  expect_equal(unname(owner_groups[c("Private", "NGO")]), rep("Private/Other", 2))
  expect_equal(owner_levels[owner_private_code], "Private")
})

test_that("rasterize_owner fills gaps with Private and lets inholdings win", {
  ref <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 300, ymin = 0, ymax = 300,
                     crs = "EPSG:5070")
  big <- sf::st_polygon(list(rbind(c(0, 0), c(300, 0), c(300, 300), c(0, 300), c(0, 0))))
  small <- sf::st_polygon(list(rbind(c(90, 90), c(210, 90), c(210, 210), c(90, 210), c(90, 90))))
  fee <- sf::st_sf(owner = c("USFS", "State"), geom = sf::st_sfc(big, small, crs = 5070))
  r <- rasterize_owner(fee, ref)
  v <- terra::values(r)[, 1]
  expect_true(owner_code("USFS") %in% v)       # big parcel present
  expect_true(owner_code("State") %in% v)      # small inholding not overwritten
  # a parcel covering nothing -> cells stay Private via background? here big
  # covers all, so no Private; test gap separately
  fee2 <- sf::st_sf(owner = "USFS", geom = sf::st_sfc(small, crs = 5070))
  r2 <- rasterize_owner(fee2, ref)
  expect_true(owner_private_code %in% terra::values(r2)[, 1])
})

test_that("split_pool makes fewest units under the cap", {
  s <- split_pool(c(0, 300, 441, 900, 2000, 2001), 2000)
  expect_equal(s$n_units, c(0, 1, 1, 1, 1, 2))
  expect_equal(s$unit_ac[6], 2001 / 2)
  expect_true(all(s$unit_ac[s$n_units > 0] <= 2000 + 1e-9))
})

test_that("size bin labels include under- and over-range bins", {
  lab <- size_bin_labels(c(30, 75, 500, 2500), params$size_bins)
  expect_equal(as.character(lab), c("<50", "50-100", "401-800", ">2000"))
})

test_that("build_burn_units splits WUI and non-WUI pools and conserves acres", {
  patches <- data.frame(project_id = 1L, patch_id = 1:2, owner = c("USFS", "Private"),
                        owner_group = c("Federal", "Private/Other"),
                        area_ac = c(5000, 300), wui_ac = c(1000, 0),
                        afn_ac = c(250, 15))
  u <- build_burn_units(patches, params)
  expect_equal(sum(u$area_ac), sum(patches$area_ac))
  expect_equal(sum(u$afn_ac), sum(patches$afn_ac), tolerance = 1e-8)
  expect_true(all(u$unit_ac[u$wui] <= params$unit_size$wui_max + 1e-9))
  expect_true(all(u$unit_ac[!u$wui] <= params$unit_size$nonwui_split_ac + 1e-9))
  # WUI pool of patch 1: 1000 ac / 441 cap -> 3 units
  w1 <- u[u$patch_id == 1 & u$wui, ]
  expect_equal(w1$n_units, 3)
  # the 300-ac private patch is below the non-WUI minimum
  expect_true(u$below_min[u$patch_id == 2])
})

test_that("check_patches rejects totals that drift from LANDFIRE stats", {
  patches <- data.frame(project_id = c(1L, 1L), area_ac = c(600, 400), afn_ac = c(30, 20))
  ps_ok <- data.frame(project_id = 1L, treatable_ac = 1000, afn_ac = 50)
  expect_silent(check_patches(patches, ps_ok))
  ps_bad <- data.frame(project_id = 1L, treatable_ac = 2000, afn_ac = 50)
  expect_error(check_patches(patches, ps_bad), "differ from LANDFIRE")
})

test_that("window_patches groups by owner and 8-connectivity", {
  # 3x3 window: top row USFS, rest Private; one isolated USFS cell
  nr <- nc <- 3
  treat <- rep(1, 9); inproj <- rep(TRUE, 9)
  owner <- c(1, 1, 2,    # USFS USFS Private
             2, 2, 2,
             1, 2, 2)    # isolated USFS at bottom-left
  wui <- rep(0, 9); inv <- rep(0.1, 9)
  wp <- window_patches(treat, inproj, owner, wui, inv, nr, nc)
  usfs <- wp[wp$owner_code == 1, ]
  expect_equal(sort(usfs$cells), c(1, 2))      # a 2-cell patch and a 1-cell patch
  expect_equal(sum(wp$cells), 9)
})

test_that("twigs cleaning drops impossible dates and non-positive acres", {
  x <- data.frame(acres = c(100, -5, 200, NA, 50, 75),
                  year  = c(2010, 2010, 1899, 2010, 2200, 2005))
  y <- clean_twigs(x, min_year = 1990, max_year = 2026)
  expect_equal(nrow(y), 2)                    # 100 (2010) and 75 (2005)
  expect_equal(sort(y$acres), c(75, 100))
})
