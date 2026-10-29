# Optional: prefetch LANDFIRE tiles for one kind in a separate process so
# downloads run in parallel with tar_make(). Tiles land in the same cache that
# fetch_landfire_tile() checks, so targets then reuses them.
#   Rscript tools/prefetch_landfire.R evt
#   Rscript tools/prefetch_landfire.R fuels 1 2   # part 1 of 2 (disjoint tiles)
# Requires that the lf_tiles target has been built.
args <- commandArgs(trailingOnly = TRUE)
kind <- args[1]
part <- if (length(args) >= 3) as.integer(args[2:3]) else c(1L, 1L)
stopifnot(kind %in% c("fuels", "evt", "bps"))
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
cfg <- read_pipeline_config()
tiles <- targets::tar_read(lf_tiles)
idx <- seq_along(tiles)
idx <- idx[(idx - 1L) %% part[2] == part[1] - 1L]
for (i in idx) {
  t0 <- Sys.time()
  f <- fetch_landfire_tile(tiles[[i]], kind, cfg$landfire$products, cfg$landfire$dir,
                           cfg$landfire$resolution)
  message(sprintf("[%s %d/%d] %s %.0fs", kind, i, length(tiles), basename(dirname(f)),
                  as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}
