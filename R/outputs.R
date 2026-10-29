# Small output helpers used by _targets.R

write_table_csv <- function(x, dir, name) {
  ensure_dir(dir)
  f <- file.path(dir, name)
  utils::write.csv(x, f, row.names = FALSE)
  f
}

write_parquet_file <- function(x, path) {
  ensure_dir(dirname(path))
  arrow::write_parquet(x, path)
  path
}

nfdrs_year_files <- function(files, year) {
  f <- files[grepl(sprintf("_%d\\.tif$", year), files)]
  f <- unname(f)
  c(fm1 = f[startsWith(basename(f), "fm1_")],
    fm10 = f[startsWith(basename(f), "fm10_")])
}

write_gridmet_template <- function(gm_files, out) {
  ensure_dir(dirname(out))
  t <- gridmet_template(gm_files[1])
  terra::writeRaster(t, out, overwrite = TRUE, datatype = "INT4U")
  out
}

#' Map requested product codes to band positions in a fuels tile
fuels_band_names <- function(tile, products) {
  nm <- names(terra::rast(tile))
  key <- c(fbfm40 = products$fbfm40, cc = products$cc, ch = products$ch,
           cbh = products$cbh, slope = products$slope)
  out <- vapply(nm, function(n) {
    hit <- names(key)[vapply(key, function(k) startsWith(n, paste0(k, "_")), logical(1))]
    if (length(hit) != 1) stop("cannot map LANDFIRE band name: ", n)
    hit
  }, character(1))
  unname(out)
}

pick_example_project <- function(rx_target) {
  d <- rx_target[!is.na(rx_target$bd_mean), ]
  d$project_id[which.max(d$treatable_ac)]
}

render_report <- function(rmd, out, deps) {
  force(deps)
  knitr::knit(rmd, output = out, quiet = TRUE, envir = new.env())
  out
}
