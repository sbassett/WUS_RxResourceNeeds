# Verifies config/burn_thresholds.yml against the ST1 table extracted from
# the Swain et al. 2023 supplement (config/swain2023_ST1.csv).

parse_range <- function(s) {
  s <- trimws(s)
  if (s %in% c("–", "-", "")) return(c(NA_real_, NA_real_))
  as.numeric(strsplit(s, "-", fixed = TRUE)[[1]])
}

test_that("burn_thresholds.yml matches Swain ST1", {
  st1 <- utils::read.csv(root_file("config/swain2023_ST1.csv"), check.names = FALSE,
                         stringsAsFactors = FALSE, encoding = "UTF-8")
  y <- yaml::read_yaml(root_file("config/burn_thresholds.yml"))
  map <- c(temperature = "Air temperature", relative_humidity = "Relative humidity",
           midflame_wind = "wind speed", ignition_component = "Ignition component",
           fm1 = "^1 hour", fm10 = "^10 hour", fm100 = "^100 hour", fm1000 = "^1000 hour")
  cols <- c(all = "All Plans", forest = "Forest Plans", nonforest = "Non-Forest Plans")
  for (t in y$thresholds) {
    row <- grep(map[[t$variable]], st1[[1]])
    expect_length(row, 1)
    for (ps in names(cols)) {
      r <- parse_range(st1[row, cols[[ps]]])
      got <- as.numeric(c(if (is.null(t[[ps]]$min)) NA else t[[ps]]$min,
                          if (is.null(t[[ps]]$max)) NA else t[[ps]]$max))
      expect_equal(got, r, info = paste(t$variable, ps))
    }
  }
})
