# rf_variable_importance.R
# Re-fits the final tuned Probability Forest using best params from
# rf_mb_best_params.json. Prints full test-set evaluation, saves variable
# importance and test predictions.  Used by generate_paper_assets.py.

suppressPackageStartupMessages({
  library(ranger)
  library(pROC)
  library(jsonlite)
  library(dplyr)
})

set.seed(18)

RDS_PATH    <- "/Users/keithjaffe/Desktop/grad_school/222_project/222_project/raw merged data/final_master_data_filtered.rds"
PARAMS_PATH <- "/Users/keithjaffe/hwy17_xgboost/rf_mb_best_params.json"
OUT_DIR     <- "/Users/keithjaffe/hwy17_xgboost"
N_THREADS   <- max(1L, parallel::detectCores() - 1L)
FINAL_TREES <- 5000

# ---- Load & prep -------------------------------------------------------------
cat("Loading RDS ...\n")
master_data2 <- readRDS(RDS_PATH)
options(na.action = "na.pass")
x_matrix <- model.matrix(accident_count ~ . - 1 - Timestamp, data = master_data2)
y_bin    <- ifelse(master_data2$accident_count > 0, 1L, 0L)
years    <- as.integer(format(master_data2$Timestamp, "%Y"))

pre21_idx <- which(years < 2021)
test_idx  <- which(years >= 2021)

X_pre21 <- as.data.frame(x_matrix[pre21_idx, ])
X_test  <- as.data.frame(x_matrix[test_idx,  ])
y_pre21 <- as.factor(y_bin[pre21_idx])
y_test  <- y_bin[test_idx]

# ---- Load best params --------------------------------------------------------
bp <- fromJSON(PARAMS_PATH)$best_params
cat(sprintf("Best params: depth=%d  node=%d  mtry=%d  sf=%.1f\n",
            bp$max.depth, bp$min.node.size, bp$mtry, bp$sample.fraction))

# ---- Fit final model ---------------------------------------------------------
cat(sprintf("Fitting %d trees on %d pre-2021 rows ...\n", FINAL_TREES, nrow(X_pre21)))

rf_final <- ranger(
  x               = X_pre21,
  y               = y_pre21,
  num.trees       = FINAL_TREES,
  max.depth       = bp$max.depth,
  min.node.size   = bp$min.node.size,
  mtry            = bp$mtry,
  sample.fraction = bp$sample.fraction,
  importance      = "impurity",
  probability     = TRUE,
  num.threads     = N_THREADS,
  seed            = 18,
  verbose         = TRUE
)

# ---- Variable importance -----------------------------------------------------
imp <- sort(rf_final$variable.importance, decreasing = TRUE)
imp_df <- data.frame(feature = names(imp), importance = as.numeric(imp))
write.csv(imp_df, file.path(OUT_DIR, "rf_variable_importance.csv"), row.names = FALSE)
cat(sprintf("\nSaved rf_variable_importance.csv  (%d features)\n", nrow(imp_df)))

cat("\nTop 20 features:\n")
print(head(imp_df, 20), row.names = FALSE)

# ---- Test set evaluation -----------------------------------------------------
test_prob <- predict(rf_final, X_test)$predictions[, 2]
roc_test  <- roc(y_test, test_prob, quiet = TRUE)
auc_test  <- as.numeric(auc(roc_test))

best_coords <- coords(roc_test, "best", ret = c("threshold","sensitivity","specificity"),
                      best.method = "youden", transpose = FALSE)
thresh   <- best_coords$threshold[1]
sens     <- best_coords$sensitivity[1]
fpr      <- 1 - best_coords$specificity[1]

pred     <- ifelse(test_prob >= thresh, 1L, 0L)
tp       <- sum(pred == 1L & y_test == 1L)
fp       <- sum(pred == 1L & y_test == 0L)
tn       <- sum(pred == 0L & y_test == 0L)
fn       <- sum(pred == 0L & y_test == 1L)
flagged  <- tp + fp

BENCH_AUC  <- 0.6615
BENCH_SENS <- 0.6545
BENCH_FLAG <- 17506L

cat(sprintf("\n%s\n", strrep("=", 55)))
cat("  TUNED PF (MB CV) — Test Set Results\n")
cat(sprintf("%s\n", strrep("=", 55)))
cat(sprintf("  Threshold   : %.4f\n", thresh))
cat(sprintf("  AUC         : %.4f  (benchmark: %.4f,  delta = %+.4f)\n",
            auc_test, BENCH_AUC, auc_test - BENCH_AUC))
cat(sprintf("  Sensitivity : %.4f  (benchmark: %.4f,  delta = %+.4f)\n",
            sens, BENCH_SENS, sens - BENCH_SENS))
cat(sprintf("  FPR         : %.4f\n", fpr))
cat(sprintf("  Flagged hrs : %d  (benchmark: %d,  delta = %+d)\n",
            flagged, BENCH_FLAG, flagged - BENCH_FLAG))
cat(sprintf("  TP=%d  FP=%d  TN=%d  FN=%d\n", tp, fp, tn, fn))
cat(sprintf("%s\n", strrep("=", 55)))

# ---- Save predictions --------------------------------------------------------
preds_df  <- data.frame(y_true = y_test, rf_prob = test_prob)
write.csv(preds_df, file.path(OUT_DIR, "rf_test_preds.csv"), row.names = FALSE)
cat(sprintf("Saved rf_test_preds.csv  (%d rows)\n", nrow(preds_df)))
