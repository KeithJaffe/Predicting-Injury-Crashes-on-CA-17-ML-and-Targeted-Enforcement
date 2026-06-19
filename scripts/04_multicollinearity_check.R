################################################################################
# Positive-Correlation Redundancy Filter
#
# Drops features that are highly POSITIVELY correlated (r > threshold) with
# another feature in the same sensor block. Negative correlations are preserved
# as they encode meaningful spatial gradients along the Highway 17 corridor
# (e.g., mountain summit conditions inverse to valley conditions on weekends).
#
# When a pair is too positively correlated, the feature with the WEAKER
# bivariate association to the outcome (accident_count) is dropped.
#
# Run AFTER cleaning script: assumes master_data2 is loaded.
################################################################################

library(dplyr)

# ---- Load cleaned data --------------------------------------------------------
setwd("~/Desktop/grad_school/222_project/222_project/raw merged data")
master_data2 <- readRDS("final_master_data_cleaned.rds")

# ---- Core filter function -----------------------------------------------------
# X: data frame of candidate predictors (numeric only)
# outcome: numeric vector, same length as nrow(X), used for tie-breaking
# threshold: drop pairs with Pearson r STRICTLY GREATER than this value
# Returns: list(kept = surviving column names, dropped = data.frame of decisions)

drop_positive_collinear <- function(X, outcome, threshold = 0.9) {
  # Keep numeric columns only; drop zero-variance columns (corr undefined)
  X <- X[, sapply(X, is.numeric), drop = FALSE]
  zero_var <- sapply(X, function(col) sd(col, na.rm = TRUE) == 0)
  if (any(zero_var)) {
    message("Dropping zero-variance columns: ",
            paste(names(X)[zero_var], collapse = ", "))
    X <- X[, !zero_var, drop = FALSE]
  }
  
  # Signed Pearson correlation, pairwise complete to handle any residual NAs
  corr <- cor(X, use = "pairwise.complete.obs")
  
  # Bivariate association of each predictor with the outcome (absolute Pearson)
  assoc <- sapply(X, function(col) {
    suppressWarnings(abs(cor(col, outcome, use = "pairwise.complete.obs")))
  })
  assoc[is.na(assoc)] <- 0  # if a feature has no variation with outcome, treat as 0
  
  # Extract upper-triangle pairs with r > threshold (strictly positive)
  cols <- colnames(corr)
  pair_list <- list()
  for (i in seq_len(length(cols) - 1)) {
    for (j in seq((i + 1), length(cols))) {
      r <- corr[i, j]
      if (!is.na(r) && r > threshold) {
        pair_list[[length(pair_list) + 1]] <-
          data.frame(a = cols[i], b = cols[j], r = r, stringsAsFactors = FALSE)
      }
    }
  }
  
  if (length(pair_list) == 0) {
    return(list(
      kept = colnames(X),
      dropped = data.frame(dropped = character(0),
                           kept_partner = character(0),
                           r = numeric(0),
                           stringsAsFactors = FALSE)
    ))
  }
  
  pairs <- do.call(rbind, pair_list)
  pairs <- pairs[order(-pairs$r), ]  # strongest pair first
  
  # Iteratively drop the weaker-associated member of each surviving pair
  alive <- rep(TRUE, ncol(X))
  names(alive) <- colnames(X)
  dropped_log <- data.frame(dropped = character(0),
                            kept_partner = character(0),
                            r = numeric(0),
                            stringsAsFactors = FALSE)
  
  for (k in seq_len(nrow(pairs))) {
    a <- pairs$a[k]
    b <- pairs$b[k]
    if (!alive[a] || !alive[b]) next  # one of them already dropped
    if (assoc[a] >= assoc[b]) {
      drop_var <- b; keep_var <- a
    } else {
      drop_var <- a; keep_var <- b
    }
    alive[drop_var] <- FALSE
    dropped_log <- rbind(dropped_log,
                         data.frame(dropped = drop_var,
                                    kept_partner = keep_var,
                                    r = pairs$r[k],
                                    stringsAsFactors = FALSE))
  }
  
  list(kept = names(alive)[alive], dropped = dropped_log)
}

# ---- Identify feature blocks --------------------------------------------------
# Weather block: all sc_, scl_, sum_ columns (including their _lag24 variants)
# Traffic block: all columns containing Total.Flow, AVG.Occupancy, AVG.Speed
#                (in your final data these are all _lag1/_lag2/_lag3 versions)

all_cols <- names(master_data2)

weather_cols <- all_cols[grepl("^(sc_|scl_|sum_)", all_cols)]
traffic_cols <- all_cols[grepl("Total\\.Flow|AVG\\.Occupancy|AVG\\.Speed", all_cols)]

# Restrict each block to numeric columns (excludes preciptype/conditions/icon factors)
weather_cols <- weather_cols[sapply(master_data2[weather_cols], is.numeric)]
traffic_cols <- traffic_cols[sapply(master_data2[traffic_cols], is.numeric)]

cat("Weather block candidates:", length(weather_cols), "\n")
cat("Traffic block candidates:", length(traffic_cols), "\n")

# ---- Run filter block-wise ----------------------------------------------------
outcome <- master_data2$accident_count

weather_result <- drop_positive_collinear(
  X         = master_data2[, weather_cols],
  outcome   = outcome,
  threshold = 0.9
)

traffic_result <- drop_positive_collinear(
  X         = master_data2[, traffic_cols],
  outcome   = outcome,
  threshold = 0.9
)

# ---- Report -------------------------------------------------------------------
cat("\n=========== WEATHER BLOCK ===========\n")
cat("Kept:    ", length(weather_result$kept),  "of", length(weather_cols), "\n")
cat("Dropped: ", nrow(weather_result$dropped), "\n\n")
print(weather_result$dropped, row.names = FALSE)

cat("\n=========== TRAFFIC BLOCK ===========\n")
cat("Kept:    ", length(traffic_result$kept),  "of", length(traffic_cols), "\n")
cat("Dropped: ", nrow(traffic_result$dropped), "\n\n")
print(traffic_result$dropped, row.names = FALSE)

# ---- Build filtered dataset ---------------------------------------------------
# Everything that isn't in the weather or traffic block passes through untouched
# (outcome, fixed effects, holiday/COVID indicators, Timestamp)
passthrough_cols <- setdiff(all_cols, c(weather_cols, traffic_cols))

master_data_filtered <- master_data2[, c(
  passthrough_cols,
  weather_result$kept,
  traffic_result$kept
)]

cat("\n=========== FINAL ===========\n")
cat("Original columns: ", ncol(master_data2), "\n")
cat("Filtered columns: ", ncol(master_data_filtered), "\n")
cat("Total dropped:    ", ncol(master_data2) - ncol(master_data_filtered), "\n")

# ---- Save ---------------------------------------------------------------------
saveRDS(master_data_filtered, file = "final_master_data_filtered.rds")

# Save the drop log as CSV for the appendix table in the paper
drop_log <- rbind(
  cbind(block = "weather", weather_result$dropped),
  cbind(block = "traffic", traffic_result$dropped)
)
write.csv(drop_log, "positive_corr_drop_log.csv", row.names = FALSE)

cat("\nSaved:\n")
cat("  final_master_data_filtered.rds\n")
cat("  positive_corr_drop_log.csv\n")
cat(readLines("positive_corr_drop_log.csv"), sep = "\n")


