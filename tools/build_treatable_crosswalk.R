# Build / update the treatable-area crosswalks from the LANDFIRE attribute
# tables of the current study area:
#   config/treatable_bps.csv       one row per BPS_CODE (historical dry forest)
#   config/treatable_evt_phys.csv  one row per EVT_PHYS (current condition)
#
#   Rscript tools/build_treatable_crosswalk.R
#
# Existing rows (your reviewed decisions) are kept unchanged. Codes not yet in
# a file are appended with the default rule and review = "new" so they are
# easy to find. The pipeline stops if the data contain a code that has no row.
# Requires the bps_attr and evt_attr targets to be built.
#
# Default rules (decisions of 2026-10-29):
#   BPS treatable = forest/woodland GROUPVEG (Conifer, Hardwood,
#     Hardwood-Conifer) in Fire Regime Group I (FRG_NEW I-A/I-B/I-C, <= 35 yr),
#     excluding pinyon-juniper, juniper, and shrubland BPS. This includes
#     ponderosa pine, dry-mesic and mesic montane mixed conifer, Madrean
#     pine-oak and conifer-oak, Madrean Encinal, aspen and aspen-mixed conifer.
#   EVT treatable = current vegetation that can carry fire, including shrub and
#     grass (e.g. post-fire or fire-excluded conversions). Excluded: developed,
#     agriculture, water, snow/ice, barren/quarries, sparse, riparian/wetland.

source("R/utils_config.R")
source("R/target_area.R")

bps <- targets::tar_read(bps_attr)
evt <- targets::tar_read(evt_attr)

# ---- BPS -------------------------------------------------------------------
b <- bps[bps$BPS_CODE > 0, ]
by_code <- split(b, b$BPS_CODE)
bps_tab <- do.call(rbind, lapply(by_code, function(d) {
  frg <- sort(unique(d$FRG_NEW[d$FRG_NEW != "-9999"]))
  fri <- d$FRI_ALLFIR[d$FRI_ALLFIR > 0]
  data.frame(
    BPS_CODE = d$BPS_CODE[1],
    BPS_NAME = d$BPS_NAME[1],
    GROUPVEG = d$GROUPVEG[1],
    FRG_NEW = paste(frg, collapse = ";"),
    FRI_ALLFIR = if (length(fri)) paste(range(fri), collapse = "-") else NA,
    stringsAsFactors = FALSE)
}))
default_bps <- function(t) {
  forest <- t$GROUPVEG %in% c("Conifer", "Hardwood", "Hardwood-Conifer")
  frg1 <- grepl("(^|;)I-[ABC]", t$FRG_NEW)
  pj <- grepl("Pinyon|Juniper|Shrubland", t$BPS_NAME)
  ok <- forest & frg1 & !pj
  reason <- ifelse(ok, "forest/woodland, FRG I",
            ifelse(forest & frg1 & pj, "FRG I but pinyon-juniper/juniper/shrubland (excluded)",
            ifelse(forest, "forest/woodland, not FRG I", "non-forest BPS")))
  data.frame(treatable = ok, reason = reason, stringsAsFactors = FALSE)
}

# ---- EVT physiognomy --------------------------------------------------------
phys <- sort(unique(evt$EVT_PHYS))
evt_tab <- data.frame(EVT_PHYS = phys, stringsAsFactors = FALSE)
evt_tab$n_classes <- as.integer(table(evt$EVT_PHYS)[phys])
default_evt <- function(t) {
  bad <- grepl("^Developed|Agricultural|Open Water|Snow-Ice|Quarries|Sparse|Riparian|Barren",
               t$EVT_PHYS)
  data.frame(treatable = !bad,
             reason = ifelse(bad, "cannot be treated with Rx fire now",
                             "current vegetation can carry fire"),
             stringsAsFactors = FALSE)
}

merge_crosswalk <- function(new, key, path, default_fun) {
  if (file.exists(path)) {
    old <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
    add <- new[!new[[key]] %in% old[[key]], , drop = FALSE]
    if (nrow(add)) {
      add <- cbind(add, default_fun(add), review = "new")
      old <- rbind(old, add[, names(old)])
    }
    out <- old
    cat(path, ": kept", nrow(out) - nrow(add), "rows, added", nrow(add), "\n")
  } else {
    out <- cbind(new, default_fun(new), review = "")
    cat(path, ": wrote", nrow(out), "rows\n")
  }
  out <- out[order(!out$treatable, out[[key]]), ]
  utils::write.csv(out, path, row.names = FALSE)
  invisible(out)
}

bx <- merge_crosswalk(bps_tab, "BPS_CODE", "config/treatable_bps.csv", default_bps)
ex <- merge_crosswalk(evt_tab, "EVT_PHYS", "config/treatable_evt_phys.csv", default_evt)
cat("\nTreatable BPS:\n"); print(bx[bx$treatable, c("BPS_CODE", "BPS_NAME", "FRG_NEW", "FRI_ALLFIR")],
                                 row.names = FALSE, right = FALSE)
cat("\nEVT_PHYS:\n"); print(ex[, c("EVT_PHYS", "treatable")], row.names = FALSE, right = FALSE)
