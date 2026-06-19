# Predicting Injury Crashes on California Highway 17

**Author:** Keith Jaffe, University of California, Santa Cruz

This repository contains all code, results, and figures for a paper that asks two questions about California Highway 17: Can machine learning reliably predict the hours when injury crashes are most likely to occur, and would pairing those predictions with targeted CHP enforcement be economically justified?

The full paper is in [docs/Keith_Jaffe_Independent_Research.pdf](docs/Keith_Jaffe_Independent_Research.pdf).

---

## Overview

Highway 17 is a 26.49-mile mountain corridor connecting Santa Clara and Santa Cruz counties. It passes through three distinct climate zones, lacks shoulders on many sections, and handles a concentrated mix of Bay Area commuters and coastal tourists with no practical alternative route. The combination of challenging geometry, variable weather, and high traffic volume makes it one of California's most dangerous roads.

I built an 11.75-year hourly dataset (102,959 observations, January 2014 through September 2025) by merging three sources:

- **Accident records** from the UC Berkeley Transportation Injury Mapping System (TIMS/SWITRS), 2,833 injury-causing collisions geocoded to Highway 17
- **Traffic sensor data** from Caltrans PeMS, 49 stations recording Average Occupancy, Average Speed, and Total Flow at 5-minute intervals (aggregated to hourly)
- **Weather observations** from Visual Crossing at three microclimate locations along the route (Santa Cruz coast, summit, Santa Clara valley)

The response variable is binary: did an injury crash occur in a given hour (1) or not (0)? Only 2,696 of 102,959 hours contain a crash, a prevalence of 2.62 percent, creating severe class imbalance.

---

## Models

### Probability Forest (ranger, R)

A Probability Forest averages leaf-class proportions across trees into a continuous risk score, rather than returning a majority-vote class label. This probability output makes it possible to select an operating threshold rather than accepting a fixed 0.5 cutoff, which is essential when the positive class is rare.

### XGBoost (xgboost, Python)

A gradient-boosted tree ensemble that builds trees sequentially, each correcting the residual error of the previous. `scale_pos_weight = 37.22` up-weights the minority class during training to counteract the 35:1 class imbalance without oversampling.

Both models use identical methodology: expanding-window cross-validation over four folds (2014-2016 through 2014-2019 training windows), hyperparameter selection by mean Youden's J across folds, and a single evaluation on a held-out test set spanning January 2021 through September 2025 (41,615 hours, 1,091 crash-hours).

---

## Results

Threshold-dependent metrics are evaluated at each model's Youden-optimal operating threshold (0.026 for the Probability Forest, 0.452 for XGBoost).

| Metric | Probability Forest | XGBoost |
|--------|-------------------|---------|
| Test AUC | 0.6614 | 0.6786 |
| Sensitivity (TPR) | 0.7131 | 0.6416 |
| False positive rate | 0.4904 | 0.3834 |
| Precision (PPV) | 0.0377 | 0.0431 |
| Youden's J | 0.2227 | 0.2582 |
| Lift over random | 1.437x | 1.644x |
| Flagged hours | 20,652 | 16,238 |
| True positives | 778 | 700 |
| False positives | 19,874 | 15,538 |
| True negatives | 20,650 | 24,986 |
| False negatives | 313 | 391 |
| CV mean Youden's J | 0.2596 (+/- 0.0325) | 0.2791 (+/- 0.0221) |

XGBoost achieves a higher AUC and better targeting efficiency (lift 1.644x vs. 1.437x). The Probability Forest captures 78 more crash-hours (778 vs. 700) at the cost of 4,336 additional false alarms.

### Variable Importance

Both models identify summit precipitation (rain indicators, precipitation type) and 1-hour lagged traffic flow at a small set of sensor locations as the dominant predictors. No 2- or 3-hour lag appears in either model's top 20. The Probability Forest also assigns importance to Santa Clara sea-level pressure in both its current and 24-hour lagged form.

### Cost-Benefit Analysis

Applying USDOT KABCO crash cost values to the 1,143 test-period collisions yields an annualized social cost of $113.9 million on the corridor. Using a 9 percent crash-reduction effect from Phillips, Ulleberg, and Vaa (2011) and 2024 CHP overtime rates from a Santa Barbara County cost proposal:

| Model | 1-Officer BCR (9%) | Annual Net Benefit (9%) |
|-------|-------------------|------------------------|
| Probability Forest | 9.95 | $6.58 million |
| XGBoost | 11.39 | $6.00 million |

All 24 cells in the deployment matrix (4 officer counts x 3 crash-reduction bounds) exceed a BCR of 1.0. XGBoost produces a higher ratio under a fixed budget; the Probability Forest produces a higher total net benefit across most deployment intensities.

---

## Repository Structure

```
CA17-Probability-Forest/
+-- scripts/
|   +-- data_cleaning/
|   |   +-- 00_accident_data_cleaning.R     # SWITRS/TIMS accident records
|   |   +-- 01_cleaning_traffic_volume.R    # Caltrans PeMS .gz files to pems_rough.csv
|   |   +-- 02_cleaning_weather_data.R      # Visual Crossing CSVs by microclimate
|   |
|   +-- 03_Final_Master_Data.R              # Merge all sources; add lags, FE, imputation
|   +-- 04_multicollinearity_check.R        # Positive-correlation block filter; 196 retained
|   +-- 05_rf_mb_tuning.R                   # Probability Forest MB CV grid search (36 combos)
|   +-- 06_rf_variable_importance.R         # Final tuned PF; writes rf_test_preds.csv
|   +-- 07_xgboost_mb_tuning.py             # XGBoost MB CV grid search (54 combos)
|   +-- 08_generate_paper_figures.py        # All publication figures; reads rf_test_preds.csv
|
+-- results/
|   +-- rf_mb_best_params.json              # Tuned PF hyperparameters + test metrics
|   +-- rf_mb_tuning_grid.csv               # All 36 PF grid combinations with Youden scores
|   +-- rf_variable_importance.csv          # 283 features ranked by mean Gini impurity decrease
|   +-- xgb_mb_best_params.json             # Tuned XGBoost hyperparameters + test metrics
|   +-- xgb_mb_tuning_grid.csv              # All 54 XGBoost grid combinations with Youden scores
|
+-- figures/                                # Publication-quality figures (300 DPI)
|   +-- fig_severity_distribution.png
|   +-- fig_cv_diagram.png
|   +-- fig_roc.png
|   +-- fig_confusion_pf.png
|   +-- fig_confusion_xgb.png
|   +-- fig_importance_pf.png
|   +-- fig_importance_xgb.png
|   +-- fig_bcr.png
|   +-- fig_results_table.png
|   +-- fig_tuning_table.png
|
+-- docs/
|   +-- Keith_Jaffe_Independent_Research.pdf
|
+-- requirements.txt                        # Python dependencies
+-- .gitignore
+-- README.md
```

---

## Reproduction

Raw data files (PeMS .gz archives, Visual Crossing CSVs, SWITRS Excel exports) are not tracked in this repository due to size and licensing. The scripts document exactly where each source was obtained.

**Run order:**

1. `scripts/data_cleaning/00_accident_data_cleaning.R` -- cleans SWITRS records
2. `scripts/data_cleaning/01_cleaning_traffic_volume.R` -- reads PeMS .gz files, writes `pems_rough.csv`
3. `scripts/data_cleaning/02_cleaning_weather_data.R` -- aggregates Visual Crossing CSVs by location
4. `scripts/03_Final_Master_Data.R` -- merges all sources; adds 1/2/3-hour traffic lags, 24-hour weather lags, hour/day/month/year fixed effects, and COVID/holiday indicators; writes `final_master_data_cleaned.rds`
5. `scripts/04_multicollinearity_check.R` -- applies the positive-correlation block filter; writes `final_master_data_filtered.rds` (196 predictors retained from 326)
6. `scripts/05_rf_mb_tuning.R` -- 36-combination grid search over 4 expanding-window CV folds (~3 hours); writes `rf_mb_best_params.json` and `rf_mb_tuning_grid.csv`
7. `scripts/06_rf_variable_importance.R` -- fits the 5,000-tree final Probability Forest; writes `rf_test_preds.csv` and `rf_variable_importance.csv` (~10 minutes)
8. `scripts/07_xgboost_mb_tuning.py` -- 54-combination grid search over 4 folds; writes `xgb_mb_best_params.json` and `xgb_mb_tuning_grid.csv` (~20 minutes)
9. `scripts/08_generate_paper_figures.py` -- re-fits XGBoost from `xgb_mb_best_params.json`, reads `rf_test_preds.csv`, writes all figures to `figures/` (~2 minutes)

**Environment:**

- R (packages: ranger, pROC, jsonlite, dplyr, caret, lubridate, readr, readxl, R.utils, data.table, tidyr)
- Python 3 (see `requirements.txt`; packages: xgboost, pandas, numpy, scikit-learn, matplotlib, pyarrow)
- Random seed: 18 throughout

---

## Multicollinearity Filter

The 49 PeMS stations each contribute three measures (Flow, Occupancy, Speed) across three lags, plus three microclimate weather sources with overlapping spatial coverage. This creates near-certain multicollinearity that does not hurt predictive accuracy but dilutes variable importance scores by distributing signal across redundant features.

The filter uses a block-wise approach similar to Kuhn and Johnson (2013), with two modifications. First, it restricts dropping to positively correlated pairs (Pearson r > 0.90). Negative pairs such as occupancy and speed (r near -0.91) encode physically real traffic flow relationships and are preserved. Second, within each correlated pair the weaker predictor of accident hours is dropped. The result is 130 features dropped, 196 retained (283 design matrix columns after dummy expansion).

---

## Citation

Jaffe, Keith. "Predicting Injury Crashes on California Highway 17: Machine Learning and the Economics of Targeted Enforcement." University of California, Santa Cruz, 2026.

---

## Data Sources

- Transportation Injury Mapping System (TIMS). UC Berkeley SafeTREC. https://tims.berkeley.edu
- Caltrans Performance Measurement System (PeMS). https://pems.dot.ca.gov
- Visual Crossing Corporation. Historical Weather Data, 2014-2025. https://www.visualcrossing.com
