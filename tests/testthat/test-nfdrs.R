test_that("EMC uses the right Simard branch", {
  # RH < 10
  expect_equal(emc_simard(80, 5), 0.03229 + 0.281073 * 5 - 0.000578 * 5 * 80)
  # 10 <= RH < 50
  expect_equal(emc_simard(70, 30), 2.22749 + 0.160107 * 30 - 0.014784 * 70)
  # RH >= 50
  expect_equal(emc_simard(60, 60),
               21.0606 + 0.005565 * 3600 - 0.00035 * 60 * 60 - 0.483199 * 60)
  # boundaries: RH 10 -> middle branch, RH 50 -> high branch
  expect_equal(emc_simard(70, 10), 2.22749 + 0.160107 * 10 - 0.014784 * 70)
  expect_equal(emc_simard(70, 50),
               21.0606 + 0.005565 * 2500 - 0.00035 * 50 * 70 - 0.483199 * 50)
  expect_equal(emc_simard(70, 9.999),
               0.03229 + 0.281073 * 9.999 - 0.000578 * 9.999 * 70)
})

test_that("hand-checked values", {
  expect_equal(emc_simard(80, 5), 1.206455, tolerance = 1e-6)
  expect_equal(emc_simard(70, 30), 5.99582, tolerance = 1e-6)
  expect_equal(emc_simard(60, 60), 10.84266, tolerance = 1e-6)
  expect_equal(fm1_nfdrs(70, 30), 1.03 * 5.99582, tolerance = 1e-6)
  expect_equal(fm10_nfdrs(70, 30), 1.28 * 5.99582, tolerance = 1e-6)
})

test_that("NA propagates and vectors work", {
  x <- emc_simard(c(70, NA, 70, 70), c(30, 30, NA, 60))
  expect_equal(is.na(x), c(FALSE, TRUE, TRUE, FALSE))
  expect_length(fm1_nfdrs(c(1, 2, 3), c(20, 30, 40)), 3)
})

test_that("state of weather and fuel-level adjustment", {
  expect_equal(sow_from_srad(c(95, 80, 60, 30, NA), 100), c(0L, 1L, 2L, 3L, NA))
  fl <- fuel_level_conditions(c(70, 70), c(40, 40), c(0L, 3L))
  expect_equal(fl$temp_f, c(95, 75))
  expect_equal(fl$rh, c(30, 40))
  expect_equal(fuel_level_conditions(70, 100, 2L)$rh, 92)
})

test_that("clear-sky radiation is plausible", {
  summer <- clear_sky_srad(35, 172)
  winter <- clear_sky_srad(35, 355)
  expect_gt(summer, 330); expect_lt(summer, 390)
  expect_gt(winter, 100); expect_lt(winter, summer)
})
