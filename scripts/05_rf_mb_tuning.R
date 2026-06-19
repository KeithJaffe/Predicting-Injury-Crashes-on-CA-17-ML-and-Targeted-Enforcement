# rf_mb_tuning.R
# Tunes the ranger Probability Forest using expanding-window (moving block) CV.
# Selection criterion: mean Youden's J across 4 folds — matches XGBoost tuning.
#
# Grid: max.depth x min.node.size x mtry x sample.fraction
# Folds:
#   Fold 1: train 2014-2016  ->  validate 2017
#   Fold 2: train 2014-2017  ->  validate 2018
#   Fold 3: train 2014-2018  ->  validate 2019
#   Fold 4: train 2014-2019  ->  validate 2020
#
# Final model: all pre-2021 with 5000 trees, evaluated on 2021+ test set.

suppressPackageStartupMessages({
  library(ranger)
  library(pROC)
  library(jsonlite)
  library(dplyr)
})

set.seed(18)

# ---- Config ------------------------------------------------------------------
RDS_PATH <- "/Users/keithjaffe/Desktop/grad_school/222_project/222_project/raw merged data/final_master_data_filtered.rds"
OUT_DIR  <- "/Users/keithjaffe/hwy17_xgboost"

FOREST_AUC  <- 0.6615
FOREST_SENS <- 0.6545
FOREST_FLAG <- 17506

FOLD_VAL_YEARS <- c(2017, 2018, 2019, 2020)
CV_TREES       <- 500
FINAL_TREES    <- 5000
N_THREADS      <- max(1L, parallel::detectCores() - 1L)

# ---- Load & prep -------------------------------------------------------------
cat("Loading RDS ...\n")
master_data2 <- readRDS(RDS_PATH)
cat(sprintf("Rows: %d  |  Cols: %d\n", nrow(master_data2), ncol(master_data2)))

options(na.action = "na.pass")
x_matrix <- model.matrix(accident_count ~ . - 1 - Timestamp, data = master_data2)
y_bin    <- ifelse(master_data2$accident_count > 0, 1L, 0L)
years    <- as.integer(format(master_data2$Timestamp, "%Y"))

p <- ncol(x_matrix)
cat(sprintf("Design matrix: %d rows x %d cols\n\n", nrow(x_matrix), p))

# Test set held out throughout
pre21_idx <- which(years < 2021)
test_idx  <- which(years >= 2021)
y_test    <- y_bin[test_idx]
X_test    <- as.data.frame(x_matrix[test_idx, ])

# ---- Tuning grid -------------------------------------------------------------
grid <- expand.grid(
  max.depth     = c(4, 6, 8),
  min.node.size = c(5, 10, 20),
  mtry          = floor(c(0.5, 0.8) * p),
  sample.fraction = c(0.7, 0.8),
  KEEP.OUT.ATTRS   = FALSE,
  stringsAsFactors = FALSE
)
cat(sprintf("Grid: %d combinations x %d folds = %d total fits\n\n",
            nrow(grid), length(FOLD_VAL_YEARS), nrow(grid) * length(FOLD_VAL_YEARS)))

# ---- Helper: Youden's J ------------------------------------------------------
youden_metrics <- function(roc_obj, probs, labels) {
  best   <- coords(roc_obj, "best", ret = c("threshold", "sensitivity", "specificity"),
                   best.method = "youden", transpose = FALSE)
  thresh <- best$threshold[1]
  sens   <- best$sensitivity[1]
  fpr    <- 1 - best$specificity[1]
  list(youden = sens - fpr, sensitivity = sens, fpr = fpr, threshold = thresh)
}

# ---- Main tuning loop --------------------------------------------------------
grid_results <- list()

for (i in seq_len(nrow(grid))) {
  cfg <- grid[i, ]
  fold_joudens <- numeric(length(FOLD_VAL_YEARS))

  for (fi in seq_along(FOLD_VAL_YEARS)) {
    val_year <- FOLD_VAL_YEARS[fi]
    tr_idx   <- which(years < val_year)
    val_idx  <- which(years == val_year)

    X_tr  <- as.data.frame(x_matrix[tr_idx,  ])
    X_val <- as.data.frame(x_matrix[val_idx, ])
    y_tr  <- as.factor(y_bin[tr_idx])
    y_val <- y_bin[val_idx]

    rf_fold <- ranger(
      x               = X_tr,
      y               = y_tr,
      num.trees       = CV_TREES,
      max.depth       = cfg$max.depth,
      min.node.size   = cfg$min.node.size,
      mtry            = cfg$mtry,
      sample.fraction = cfg$sample.fraction,
      probability     = TRUE,
      num.threads     = N_THREADS,
      verbose         = FALSE,
      seed            = 18
    )

    val_prob <- predict(rf_fold, X_val)$predictions[, 2]
    roc_fold <- roc(y_val, val_prob, quiet = TRUE)
    m        <- youden_metrics(roc_fold, val_prob, y_val)
    fold_joudens[fi] <- m$youden
  }

  grid_results[[i]] <- data.frame(
    max.depth       = cfg$max.depth,
    min.node.size   = cfg$min.node.size,
    mtry            = cfg$mtry,
    sample.fraction = cfg$sample.fraction,
    mean_youden     = round(mean(fold_joudens), 4),
    std_youden      = round(sd(fold_joudens),   4)
  )

  if (i %% 6 == 0 || i == nrow(grid)) {
    cat(sprintf("  %d/%d done  (last: depth=%d node=%d mtry=%d sf=%.1f  mean_J=%.4f  sd=%.4f)\n",
                i, nrow(grid),
                cfg$max.depth, cfg$min.node.size, cfg$mtry, cfg$sample.fraction,
                mean(fold_joudens), sd(fold_joudens)))
  }
}

# ---- Sort and display --------------------------------------------------------
results_df <- bind_rows(grid_results) %>%
  arrange(desc(mean_youden)) %>%
  as.data.frame()

cat(sprintf("\n%s\n", strrep("=", 65)))
cat("Top 10 combinations by mean Youden's J (moving block CV):\n\n")
print(head(results_df, 10), row.names = FALSE)

best <- results_df[1, ]
cat(sprintf("\nBest params:\n"))
cat(sprintf("  max.depth       : %d\n",   best$max.depth))
cat(sprintf("  min.node.size   : %d\n",   best$min.node.size))
cat(sprintf("  mtry            : %d\n",   best$mtry))
cat(sprintf("  sample.fraction : %.1f\n", best$sample.fraction))
cat(sprintf("  mean_youden     : %.4f\n", best$mean_youden))
cat(sprintf("  std_youden      : %.4f\n", best$std_youden))

# ---- Final model: all pre-2021, 5000 trees -----------------------------------
X_pre21 <- as.data.frame(x_matrix[pre21_idx, ])
y_pre21 <- as.factor(y_bin[pre21_idx])

cat(sprintf("\nFitting final model on all pre-2021 (%d rows) with %d trees ...\n",
            length(pre21_idx), FINAL_TREES))

rf_final <- ranger(
  x               = X_pre21,
  y               = y_pre21,
  num.trees       = FINAL_TREES,
  max.depth       = best$max.depth,
  min.node.size   = best$min.node.size,
  mtry            = best$mtry,
  sample.fraction = best$sample.fraction,
  importance      = "impurity",
  probability     = TRUE,
  num.threads     = N_THREADS,
  seed            = 18
)

# ---- Test set evaluation -----------------------------------------------------
test_prob <- predict(rf_final, X_test)$predictions[, 2]
roc_test  <- roc(y_test, test_prob, quiet = TRUE)
auc_test  <- as.numeric(auc(roc_test))
m_test    <- youden_metrics(roc_test, test_prob, y_test)

pred   <- ifelse(test_prob >= m_test$threshold, 1L, 0L)
tp     <- sum(pred == 1L & y_test == 1L)
fp     <- sum(pred == 1L & y_test == 0L)
tn     <- sum(pred == 0L & y_test == 0L)
fn     <- sum(pred == 0L & y_test == 1L)
flagged <- tp + fp

cat(sprintf("\n%s\n", strrep("=", 55)))
cat("  TUNED PF (MB CV) — Test Set Results\n")
cat(sprintf("%s\n", strrep("=", 55)))
cat(sprintf("  Threshold   : %.4f\n", m_test$threshold))
cat(sprintf("  AUC         : %.4f  (benchmark: %.4f,  delta = %+.4f)\n",
            auc_test, FOREST_AUC, auc_test - FOREST_AUC))
cat(sprintf("  Sensitivity : %.4f  (benchmark: %.4f,  delta = %+.4f)\n",
            m_test$sensitivity, FOREST_SENS, m_test$sensitivity - FOREST_SENS))
cat(sprintf("  FPR         : %.4f\n", m_test$fpr))
cat(sprintf("  Flagged hrs : %d  (benchmark: %d,  delta = %+d)\n",
            flagged, FOREST_FLAG, flagged - FOREST_FLAG))
cat(sprintf("  TP=%d  FP=%d  TN=%d  FN=%d\n", tp, fp, tn, fn))
cat(sprintf("%s\n", strrep("=", 55)))

# ---- Save --------------------------------------------------------------------
write.csv(results_df, file.path(OUT_DIR, "rf_mb_tuning_grid.csv"), row.names = FALSE)

results_out <- list(
  cv_trees        = CV_TREES,
  final_trees     = FINAL_TREES,
  best_params     = list(
    max.depth       = best$max.depth,
    min.node.size   = best$min.node.size,
    mtry            = best$mtry,
    sample.fraction = best$sample.fraction
  ),
  cv_mean_youden  = best$mean_youden,
  cv_std_youden   = best$std_youden,
  threshold       = m_test$threshold,
  auc_test        = round(auc_test, 4),
  sensitivity     = round(m_test$sensitivity, 4),
  fpr             = round(m_test$fpr, 4),
  flagged         = flagged,
  tp = tp, fp = fp, tn = tn, fn = fn
)
write_json(results_out, file.path(OUT_DIR, "rf_mb_best_params.json"),
           pretty = TRUE, auto_unbox = TRUE)

cat(sprintf("\nSaved: rf_mb_tuning_grid.csv, rf_mb_best_params.json\n"))
