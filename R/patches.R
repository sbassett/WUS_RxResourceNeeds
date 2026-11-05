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
#' `attrs` optionally holds fire behavior vectors (ros_cool, ros_hot,
#' fl_cool, fl_hot, fbfm) used to add per-patch summaries.
#' Returns data.frame(owner_code, cells, wui_cells, inv_sum[, fire behavior]).
window_patches <- function(treat, inproj, owner, wui, inv, nr, nc, attrs = NULL) {
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
    if (!is.null(attrs)) agg <- cbind(agg, patch_fire_behavior(attrs, ok, ids))
    rows[[length(rows) + 1]] <- agg
  }
  if (!length(rows)) return(NULL)
  out <- do.call(rbind, rows)
  out$wui_cells <- pmin(out$wui_cells, out$cells)   # guard against rounding
  out
}

#' Per-patch fire behavior from cell vectors
#'
#' Means are over cells that can carry fire (non-NA); `burnable_cells` counts
#' them. Flame length class cell counts use the SWCC breaks (4 and 8 ft).
patch_fire_behavior <- function(attrs, ok, ids) {
  nm_mean <- function(x) {
    v <- x[ok]; has <- !is.na(v)
    num <- as.vector(rowsum(ifelse(has, v, 0), ids))
    den <- as.vector(rowsum(has * 1, ids))
    ifelse(den > 0, num / den, NA_real_)
  }
  burnable <- as.vector(rowsum((!is.na(attrs$ros_hot[ok])) * 1, ids))
  out <- data.frame(
    burnable_cells = burnable,
    ros_cool_chhr = nm_mean(attrs$ros_cool), ros_hot_chhr = nm_mean(attrs$ros_hot),
    flame_cool_ft = nm_mean(attrs$fl_cool), flame_hot_ft = nm_mean(attrs$fl_hot))
  for (sc in c("cool", "hot")) {
    cls <- flame_class(attrs[[paste0("fl_", sc)]][ok])
    for (k in 1:3) {
      nmk <- c("0_4", "4_8", "8p")[k]
      out[[paste0("cells_fl_", sc, "_", nmk)]] <-
        as.vector(rowsum(ifelse(is.na(cls), 0, (cls == k) * 1), ids))
    }
  }
  # modal fuel model (ties -> lowest code)
  f <- attrs$fbfm[ok]
  tb <- table(factor(ids, levels = sort(unique(ids))), f)
  modal <- if (ncol(tb)) as.integer(colnames(tb)[max.col(tb, ties.method = "first")]) else rep(NA_integer_, nrow(out))
  if (ncol(tb)) modal[rowSums(tb) == 0] <- NA_integer_
  out$modal_fbfm <- modal
  out
}

#' Patch table for all subfiresheds with treatable area
#'
#' @param projects sf with project_id (EPSG:5070)
#' @param fb_file optional 4-layer fire behavior raster (rx_fire_behavior_raster)
#' @param fuels_vrt,fbfm_layer optional fuels mosaic and the layer holding FBFM40
#' @return data.frame(project_id, patch_id, owner, owner_group, area_ac,
#'   wui_ac, afn_ac[, ros_*, flame_*, ac_fl_*, modal_fbfm, burnable_share])
build_patches <- function(projects, treat_file, owner_file, wui_file, bps_vrt,
                          bps_attr, fb_file = NULL, fuels_vrt = NULL, fbfm_layer = 1L,
                          progress_every = 100) {
  treat <- terra::rast(treat_file)
  owner <- terra::rast(owner_file)
  wui <- terra::rast(wui_file)
  bps <- terra::rast(bps_vrt)
  fb <- if (!is.null(fb_file)) terra::rast(fb_file) else NULL
  fbfm <- if (!is.null(fb_file)) terra::rast(fuels_vrt)[[fbfm_layer]] else NULL
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
    attrs <- NULL
    if (!is.null(fb)) {
      fv <- terra::values(terra::crop(fb, e, snap = "out"))
      attrs <- list(ros_cool = fv[, 1], ros_hot = fv[, 2], fl_cool = fv[, 3],
                    fl_hot = fv[, 4],
                    fbfm = terra::values(terra::crop(fbfm, e, snap = "out"))[, 1])
    }
    wp <- window_patches(tv, inproj, o, w, inv, terra::nrow(t), terra::ncol(t), attrs)
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
  keep <- c("project_id", "patch_id", "owner", "owner_group", "area_ac", "wui_ac", "afn_ac")
  if (!is.null(fb)) {
    x$burnable_share <- x$burnable_cells / x$cells
    for (cn in grep("^cells_fl_", names(x), value = TRUE)) {
      x[[sub("^cells_", "ac_", cn)]] <- x[[cn]] * pa
    }
    keep <- c(keep, "ros_cool_chhr", "ros_hot_chhr", "flame_cool_ft", "flame_hot_ft",
              "burnable_share", "modal_fbfm", grep("^ac_fl_", names(x), value = TRUE))
  }
  x[, keep]
}