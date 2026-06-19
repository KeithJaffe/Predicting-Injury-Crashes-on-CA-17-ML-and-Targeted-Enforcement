import json, re, itertools
import numpy as np
import pandas as pd
import xgboost as xgb
from sklearn.metrics import roc_auc_score, roc_curve, confusion_matrix

# ---- Cell 1 setup -----------------------------------------------------------
RANDOM_STATE = 18
DATA_DIR     = "/Users/keithjaffe/Desktop/grad_school/222_project/222_project/raw merged data"
FEATHER      = f"{DATA_DIR}/xgb_design_matrix.feather"

FOREST_AUC   = 0.6615
FOREST_SENS  = 0.6545
FOREST_FLAG  = 17506

np.random.seed(RANDOM_STATE)

df = pd.read_feather(FEATHER)

meta_cols     = ["y_outcome_binary", "row_timestamp", "split"]
feature_names = [c for c in df.columns if c not in meta_cols]
feature_names = [re.sub(r"[\[\]<`]", "_", c) for c in feature_names]

X     = df[[c for c in df.columns if c not in meta_cols]].to_numpy(dtype=np.float32)
y     = df["y_outcome_binary"].to_numpy(dtype=np.int32)
split = df["split"].to_numpy()

tr   = split == "train"
va   = split == "valid"
te   = split == "test"
trva = tr | va

test_y = y[te]
dtest  = xgb.DMatrix(X[te], label=test_y, feature_names=feature_names)

print(f"train: {tr.sum():,}  valid: {va.sum():,}  test: {te.sum():,}")

# ---- MB Tuning Grid ---------------------------------------------------------
GRID = {
    "max_depth":        [4, 6, 8],
    "min_child_weight": [5, 10, 20],
    "reg_lambda":       [1.0, 5.0, 10.0],
    "subsample":        [0.7, 0.8],
}

BASE_PARAMS_TG = {
    "objective":        "binary:logistic",
    "eval_metric":      ["logloss", "auc"],
    "colsample_bynode": 0.8,
    "eta":              0.05,
    "tree_method":      "hist",
    "seed":             RANDOM_STATE,
}

FOLD_VAL_YEARS_TG = [2017, 2018, 2019, 2020]
NUM_ROUNDS_TG     = 5000
EARLY_STOP_TG     = 50

ts_tg  = pd.to_datetime(df["row_timestamp"], utc=True).dt.tz_convert("America/Los_Angeles")
keys   = list(GRID.keys())
combos = list(itertools.product(*GRID.values()))
print(f"\nRunning {len(combos)} combinations × {len(FOLD_VAL_YEARS_TG)} folds "
      f"= {len(combos) * len(FOLD_VAL_YEARS_TG)} total fits\n")

grid_results = []

for i, vals in enumerate(combos):
    p = dict(zip(keys, vals))
    fold_joudens = []
    fold_rounds  = []

    for val_year in FOLD_VAL_YEARS_TG:
        tr_mask  = ts_tg.dt.year < val_year
        val_mask = ts_tg.dt.year == val_year

        X_tr  = X[tr_mask];  y_tr  = y[tr_mask]
        X_val = X[val_mask]; y_val = y[val_mask]

        spw_fold = int((y_tr == 0).sum()) / int(y_tr.sum())
        params_i = {**BASE_PARAMS_TG, **p, "scale_pos_weight": spw_fold}

        dtrain_i = xgb.DMatrix(X_tr,  label=y_tr,  feature_names=feature_names)
        dval_i   = xgb.DMatrix(X_val, label=y_val, feature_names=feature_names)

        booster_i = xgb.train(
            params_i, dtrain_i,
            num_boost_round=NUM_ROUNDS_TG,
            evals=[(dval_i, "val")],
            early_stopping_rounds=EARLY_STOP_TG,
            verbose_eval=False,
        )
        val_prob = booster_i.predict(dval_i)

        fpr_v, tpr_v, _ = roc_curve(y_val, val_prob)
        j_v = np.argmax(tpr_v - fpr_v)
        fold_joudens.append(float(tpr_v[j_v] - fpr_v[j_v]))
        fold_rounds.append(booster_i.best_iteration + 1)

    grid_results.append({
        **p,
        "mean_youden": round(float(np.mean(fold_joudens)), 4),
        "std_youden":  round(float(np.std(fold_joudens)),  4),
        "mean_rounds": round(float(np.mean(fold_rounds)),  1),
        "fold_joudens": [round(j, 4) for j in fold_joudens],
        "fold_rounds":  fold_rounds,
    })

    if (i + 1) % 9 == 0 or (i + 1) == len(combos):
        print(f"  {i+1}/{len(combos)} done …")

# ---- Sort and display -------------------------------------------------------
display_cols = keys + ["mean_rounds", "mean_youden", "std_youden"]
results_tg = (pd.DataFrame(grid_results)
                .sort_values("mean_youden", ascending=False)
                .reset_index(drop=True))

print("\nTop 10 combinations by mean Youden's J (moving block CV):")
print(results_tg[display_cols].head(10).to_string(index=False))

best_tg = results_tg.iloc[0]
print(f"\nBest params:")
for k in display_cols:
    print(f"  {k}: {best_tg[k]}")

# ---- Refit best model on all pre-2021, evaluate on test ---------------------
spw_pre21 = int((y[trva] == 0).sum()) / int(y[trva].sum())

best_params_tg = {
    **BASE_PARAMS_TG,
    "max_depth":        int(best_tg["max_depth"]),
    "min_child_weight": int(best_tg["min_child_weight"]),
    "reg_lambda":       float(best_tg["reg_lambda"]),
    "subsample":        float(best_tg["subsample"]),
    "scale_pos_weight": spw_pre21,
}
final_rounds_tg = int(round(best_tg["mean_rounds"]))

print(f"\nFitting final model on all pre-2021 for {final_rounds_tg} rounds (mean CV rounds) …")
dtrva_tg    = xgb.DMatrix(X[trva], label=y[trva], feature_names=feature_names)
final_tuned = xgb.train(best_params_tg, dtrva_tg, num_boost_round=final_rounds_tg)

test_prob_tg = final_tuned.predict(dtest)
auc_tg       = roc_auc_score(test_y, test_prob_tg)

fpr_tg, tpr_tg, thr_tg = roc_curve(test_y, test_prob_tg)
j_tg      = np.argmax(tpr_tg - fpr_tg)
thresh_tg = float(thr_tg[j_tg])
pred_tg   = (test_prob_tg >= thresh_tg).astype(int)

tn_tg, fp_tg, fn_tg, tp_tg = confusion_matrix(test_y, pred_tg, labels=[0, 1]).ravel()
sens_tg    = tp_tg / (tp_tg + fn_tg)
fpr_tg_val = fp_tg / (fp_tg + tn_tg)
flagged_tg = int(tp_tg + fp_tg)

print(f"\n{'='*55}")
print(f"  TUNED MODEL (MB CV) — Test Set Results")
print(f"{'='*55}")
print(f"  Rounds      : {final_rounds_tg}")
print(f"  AUC         : {auc_tg:.4f}  (forest: {FOREST_AUC:.4f},  Δ = {auc_tg - FOREST_AUC:+.4f})")
print(f"  Sensitivity : {sens_tg:.4f}  (forest: {FOREST_SENS:.4f},  Δ = {sens_tg - FOREST_SENS:+.4f})")
print(f"  FPR         : {fpr_tg_val:.4f}")
print(f"  Flagged hrs : {flagged_tg:,}  (forest: {FOREST_FLAG:,},  Δ = {flagged_tg - FOREST_FLAG:+,})")
print(f"  TP={tp_tg:,}  FP={fp_tg:,}  TN={tn_tg:,}  FN={fn_tg:,}")
print(f"{'='*55}")

# ---- Save -------------------------------------------------------------------
results_tg[display_cols].to_csv("xgb_mb_tuning_grid.csv", index=False)
with open("xgb_mb_best_params.json", "w") as f:
    json.dump({
        "params":           best_params_tg,
        "final_rounds":     final_rounds_tg,
        "cv_mean_youden":   float(best_tg["mean_youden"]),
        "cv_std_youden":    float(best_tg["std_youden"]),
        "test_auc":         float(auc_tg),
        "test_sensitivity": float(sens_tg),
        "test_fpr":         float(fpr_tg_val),
        "test_flagged":     flagged_tg,
    }, f, indent=2)
print("Saved: xgb_mb_tuning_grid.csv, xgb_mb_best_params.json")
