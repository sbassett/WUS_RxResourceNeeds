# Optional: prefetch gridMET var-years into the cache used by fetch_gridmet()
# so a long tar_make() run reuses them.
#   Rscript tools/prefetch_gridmet.R 1979 2025
# Requires that the bbox target has been built.
args <- as.integer(commandArgs(trailingOnly = TRUE))
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
cfg <- read_pipeline_config()
bbox <- targets::tar_read(bbox)
for (y in seq(args[1], args[2])) for (v in cfg$gridmet$vars) {
  t0 <- Sys.time()
  fetch_gridmet(v, y, bbox, cfg$gridmet$url_template, cfg$gridmet$cache_dir)
  message(sprintf("[%s %d] %.0fs", v, y, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}
