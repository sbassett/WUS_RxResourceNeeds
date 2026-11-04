# Treatable patches: contiguous (8-connected) treatable pixels that share a
# subfireshed and a landowner class, with their WUI area and annual need.
# Each subfireshed is processed in its own small raster window, so the same
# code scales to the whole West (and parallelises by subfireshed).

#' Write a 0/1 WUI raster on the treatable grid (all zeros when WUI is off)
build_wui_raster <- function(wui_cfg, treat_file, out, tmp_dir) {
  ensure_dir(dirname(out)); ensure_dir(tmp_dir)
  ref <- terra::rast(treat_file)
  m <- cwirrz_wui_mask(wui_cfg, ref, tmp_dir)
  if (is.null(m)) m <- terra::ifel(is.na(ref), NA, 0L)
  terra::writeRaster(m, out, overwrite = TRUE, datatype = "INT1U",
                     gdal = "COMPRESS=DEFLATE")
  out
}

#' 1/MFRI lookup for BPS raster values (NA where no fire return interval)
inv_mfri_table <- function(bps_attr) {
  fri <- bps_attr$FRI_ALLFIR
  data.frame(Value = bps_attr$Value,
             inv = ifelse(is.na(fri) | fri <= 0, NA_real_, 1 / fri))
}

#' Patches of one window.
#'
#' All inputs are numeric vectors over the same cells: treat (1 = treatable),
#' inproj (TRUE inside the subfireshed), owner (owner code), wui (0/1),
#' inv (1/MFRI or NA). `nr`/`nc` give the window shape for connectivity.
#' Returns data.frame(owner_code, cells, wui_cells, inv_sum).
window_patches <- function(treat, inproj, owner, wui, inv, nr, nc) {
  sel <- !is.na(treat) & treat == 1 & inproj & !is.na(owner)
  if (!any(sel)) return(NULL)
  # WUI and need only count on selected (in-patch, treatable, owned) cells
  wui_sel <- ifelse(sel, pmin(pmax(wui, 0), 1), 0); wui_sel[is.na(wui_sel)] <- 0
  inv_sel <- ifelse(sel, inv, 0); inv_sel[is.na(inv_sel)] <- 0
  rows <- list()
  for (cl in sort(unique(owner[sel]))) {
    m <- terra::rast(nrows = nr, ncols = nc, xmin = 0, xmax = nc, ymin = 0, ymax = nr)
    terra::values(m) <- ifelse(sel & owner == cl, 1L, NA)
    id <- terra::values(terra::patches(m, directions = 8))[, 1]
    ok <- !is.na(id)
    if (!any(ok)) next
    ids <- id[ok]
    agg <- data.frame(
      owner_code = cl,
      cells    = as.vector(rowsum(rep(1, length(ids)), ids)),
      wui_cells = as.vector(rowsum(wui_sel[ok], ids)),
      inv_sum  = as.vector(rowsum(inv_sel[ok], ids)))
    rows[[length(rows) + 1]] <- agg
  }
  if (!length(rows)) return(NULL)
  out <- do.call(rbind, rows)
  out$wui_cells <- pmin(out$wui_cells, out$cells)   # guard against rounding
  out
}

#' Patch table for all subfiresheds with treatable area
#'
#' @param projects sf with project_id (EPSG:5070)
#' @return data.frame(project_id, patch_id, owner, owner_group, area_ac,
#'   wui_ac, afn_ac)
build_patches <- function(projects, treat_file, owner_file, wui_file, bps_vrt,
                          bps_attr, progress_every = 100) {
  treat <- terra::rast(treat_file)
  owner <- terra::rast(owner_file)
  wui <- terra::rast(wui_file)
  bps <- terra::rast(bps_vrt)
  inv_tab <- inv_mfri_table(bps_attr)
  pa <- pixel_acres(terra::res(treat)[1])
  out <- vector("list", nrow(projects))
  for (i in seq_len(nrow(projects))) {
    if (i %% progress_every == 0) message("patches: ", i, "/", nrow(projects))
    pj <- projects[i, ]
    pv <- terra::vect(pj)
    e <- terra::ext(pv)
    t <- terra::crop(treat, e, snap = "out")
    tv <- terra::values(t)[, 1]
    if (all(is.na(tv) | tv != 1)) next
    p <- terra::rasterize(pv, t, field = 1, background = NA)
    inproj <- !is.na(terra::values(p)[, 1])
    if (!any(inproj & !is.na(tv) & tv == 1)) next
    o <- terra::values(terra::crop(owner, e, snap = "out"))[, 1]
    w <- terra::values(terra::crop(wui, e, snap = "out"))[, 1]
    b <- terra::crop(bps, e, snap = "out")
    if (!terra::compareGeom(b, t, stopOnError = FALSE)) {
      b <- terra::resample(b, t, method = "near")
    }
    inv <- terra::values(terra::classify(b, as.matrix(inv_tab), others = NA))[, 1]
    wp <- window_patches(tv, inproj, o, w, inv, terra::nrow(t), terra::ncol(t))
    if (is.null(wp)) next
    wp$project_id <- pj$project_id
    out[[i]] <- wp
  }
  x <- do.call(rbind, out)
  if (is.null(x)) stop("no patches found")
  x$patch_id <- seq_len(nrow(x))
  x$owner <- owner_levels[x$owner_code]
  x$owner_group <- unname(owner_groups[x$owner])
  x$area_ac <- x$cells * pa
  x$wui_ac <- x$wui_cells * pa
  x$afn_ac <- x$inv_sum * pa
  x[, c("project_id", "patch_id", "owner", "owner_group", "area_ac", "wui_ac", "afn_ac")]
}
