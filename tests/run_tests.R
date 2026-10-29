# Run the unit tests from the repo root:  Rscript tests/run_tests.R
r <- as.data.frame(testthat::test_dir("tests/testthat", reporter = "summary",
                                      stop_on_failure = FALSE))
cat("\nexpectations:", sum(r$nb), " failed:", sum(r$failed), " errors:", sum(r$error), "\n")
if (sum(r$failed) > 0 || any(r$error)) quit(status = 1)
