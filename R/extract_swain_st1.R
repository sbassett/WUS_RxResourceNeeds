# One-time helper: extract Supplementary Table ST1 (burn-window thresholds)
# from Swain et al. 2023 (Commun Earth Environ, doi:10.1038/s43247-023-00993-1).
#
# Usage (from repo root):
#   Rscript R/extract_swain_st1.R
#
# Writes the table that follows the "Table ST1" caption to
# config/swain2023_ST1.csv.
# (config/ rather than data/raw/ because data/ is git-ignored and this small
# table is the provenance for config/burn_thresholds.yml.)

# officer reports each cell with its own doc_index; group by table_index and
# lay cells out by row_id / cell_id.
extract_docx_tables <- function(docx_path) {
  s <- officer::docx_summary(officer::read_docx(docx_path))
  cells <- s[s$content_type == "table cell", ]
  lapply(split(cells, cells$table_index), function(x) {
    nr <- max(x$row_id)
    nc <- max(x$cell_id)
    m <- matrix(NA_character_, nr, nc)
    for (i in seq_len(nrow(x))) m[x$row_id[i], x$cell_id[i]] <- x$text[i]
    df <- as.data.frame(m[-1, , drop = FALSE], stringsAsFactors = FALSE)
    names(df) <- make.unique(ifelse(is.na(m[1, ]) | m[1, ] == "",
                                    paste0("V", seq_len(nc)), m[1, ]))
    attr(df, "doc_index") <- min(x$doc_index)
    df
  })
}

# Caption paragraph nearest before each table
table_captions <- function(docx_path, tabs) {
  s <- officer::docx_summary(officer::read_docx(docx_path))
  paras <- s[s$content_type == "paragraph" & !is.na(s$text) & nzchar(s$text), ]
  vapply(tabs, function(t) {
    prev <- paras[paras$doc_index < attr(t, "doc_index"), ]
    if (nrow(prev) == 0) NA_character_ else prev$text[nrow(prev)]
  }, character(1))
}

if (sys.nframe() == 0L) {
  docx <- "docs/References/43247_2023_993_MOESM1_ESM.docx"
  tabs <- extract_docx_tables(docx)
  caps <- table_captions(docx, tabs)
  st1 <- which(grepl("^Table ST1", caps))[1]
  if (is.na(st1)) stop("Could not find Table ST1 caption")
  utils::write.csv(tabs[[st1]], "config/swain2023_ST1.csv", row.names = FALSE)
  cat("Caption:", caps[st1], "\n\n")
  print(tabs[[st1]], right = FALSE)
  cat("\nWrote config/swain2023_ST1.csv\n")
}
