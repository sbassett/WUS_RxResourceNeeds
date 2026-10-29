# Source pipeline functions from R/ for unit tests.
repo_root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
for (f in list.files(file.path(repo_root, "R"), pattern = "\\.R$", full.names = TRUE)) {
  source(f, local = TRUE)
}
root_file <- function(...) file.path(repo_root, ...)
