# Wind adjustment factors (Andrews 2012, RMRS-GTR-266; Albini & Baughman
# 1979), implemented as in BehavePlus:
#   unsheltered: WAF = 1.83 / ln((20 + 0.36 d) / (0.13 d)),  d = fuel bed depth (ft)
#   sheltered:   WAF = 0.555 / (sqrt(f H) ln((20 + 0.36 H) / (0.13 H))),
#                H = canopy height (ft), f = crown fill portion = CR * CC / 3
#                (CR = crown ratio, CC = canopy cover, both as fractions)
# Sheltered applies when f >= 0.05 and H >= 6 ft (BehavePlus rule).

waf_unsheltered <- function(depth_ft) {
  out <- 1.83 / log((20 + 0.36 * depth_ft) / (0.13 * depth_ft))
  out[is.na(depth_ft) | depth_ft <= 0] <- NA_real_
  out
}

crown_fill_portion <- function(cc_pct, ch_ft, cbh_ft) {
  cr <- ifelse(ch_ft > 0, pmax(0, (ch_ft - cbh_ft) / ch_ft), 0)
  cr * (cc_pct / 100) / 3
}

waf_sheltered <- function(cc_pct, ch_ft, cbh_ft) {
  f <- crown_fill_portion(cc_pct, ch_ft, cbh_ft)
  0.555 / (sqrt(f * ch_ft) * log((20 + 0.36 * ch_ft) / (0.13 * ch_ft)))
}

#' WAF choosing sheltered vs unsheltered per element
waf_select <- function(depth_ft, cc_pct, ch_ft, cbh_ft,
                       min_f = 0.05, min_ch_ft = 6) {
  cc_pct[is.na(cc_pct)] <- 0
  ch_ft[is.na(ch_ft)] <- 0
  cbh_ft[is.na(cbh_ft)] <- 0
  f <- crown_fill_portion(cc_pct, ch_ft, cbh_ft)
  sheltered <- f >= min_f & ch_ft >= min_ch_ft
  out <- waf_unsheltered(depth_ft)
  out[sheltered] <- waf_sheltered(cc_pct[sheltered], ch_ft[sheltered],
                                  cbh_ft[sheltered])
  out[is.na(depth_ft)] <- NA_real_   # non-burnable stays NA
  out
}

read_waf_table <- function(path = "config/waf_fbfm40.csv") {
  t <- utils::read.csv(path, stringsAsFactors = FALSE)
  t$burnable <- as.logical(t$burnable)
  t$heavy_fuel <- as.logical(t$heavy_fuel)
  t
}

#' Mid-flame wind (m/s) from gridMET daily-mean 10 m wind
#'
#' afternoon_factor scales the daily mean to afternoon wind (Swain et al.
#' 2023 use 1.5); u10_to_u20ft converts 10 m to 20 ft wind; WAF reduces 20 ft
#' wind to mid-flame height.
midflame_wind <- function(vs_10m, waf, u10_to_u20ft = 1.15, afternoon_factor = 1) {
  vs_10m * afternoon_factor / u10_to_u20ft * waf
}
