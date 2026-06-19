"""
generate_paper_figures.py
Publication-quality figures for the Highway 17 paper.
- Serif fonts, no titles (captions in LaTeX), 300 DPI
- Single-column figures: 3.4 in wide
- Full-width figures:    6.5 in wide
Output: paper_figures/
"""

import json, re, os
import numpy as np
import pandas as pd
import xgboost as xgb
from sklearn.metrics import roc_curve, roc_auc_score, confusion_matrix
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import matplotlib.ticker as mticker
from matplotlib.lines import Line2D

# ── Global style ──────────────────────────────────────────────────────────────
plt.rcParams.update({
    "font.family":        "serif",
    "font.serif":         ["Times New Roman", "Times", "DejaVu Serif"],
    "font.size":          9,
    "axes.labelsize":     9,
    "axes.titlesize":     9,
    "xtick.labelsize":    8,
    "ytick.labelsize":    8,
    "legend.fontsize":    8,
    "legend.framealpha":  0.9,
    "legend.edgecolor":   "#cccccc",
    "axes.spines.top":    False,
    "axes.spines.right":  False,
    "axes.linewidth":     0.6,
    "grid.linewidth":     0.4,
    "grid.color":         "#e0e0e0",
    "xtick.major.width":  0.6,
    "ytick.major.width":  0.6,
    "figure.dpi":         300,
    "savefig.dpi":        300,
    "savefig.bbox":       "tight",
    "savefig.pad_inches": 0.05,
})

# ── Config ────────────────────────────────────────────────────────────────────
SEED     = 18
DATA_DIR = "/Users/keithjaffe/Desktop/grad_school/222_project/222_project/raw merged data"
FEATHER  = f"{DATA_DIR}/xgb_design_matrix.feather"
PROJ_DIR = "/Users/keithjaffe/hwy17_xgboost"
OUT_DIR  = f"{PROJ_DIR}/paper_figures"
os.makedirs(OUT_DIR, exist_ok=True)
np.random.seed(SEED)

SC  = 3.4   # single-column width (inches)
FW  = 6.5   # full-width (inches)

# ── Palette ───────────────────────────────────────────────────────────────────
RF_COLOR   = "#2e7d32"   # green  — Probability Forest
XGB_COLOR  = "#1565c0"   # blue   — XGBoost
RF_LIGHT   = "#e8f5e9"
XGB_LIGHT  = "#e3f2fd"
GRAY       = "#546e7a"
SEV_COLORS = ["#c62828", "#e64a19", "#f9a825", "#1565c0"]

# ── Load & fit XGBoost ────────────────────────────────────────────────────────
print("Loading feather ...")
df = pd.read_feather(FEATHER)
meta_cols     = ["y_outcome_binary", "row_timestamp", "split"]
feature_names = [re.sub(r"[\[\]<`]", "_", c)
                 for c in df.columns if c not in meta_cols]

X  = df[[c for c in df.columns if c not in meta_cols]].to_numpy(dtype=np.float32)
y  = df["y_outcome_binary"].to_numpy(dtype=np.int32)
ts = pd.to_datetime(df["row_timestamp"], utc=True).dt.tz_convert("America/Los_Angeles")
trva = ts.dt.year < 2021
te   = ts.dt.year >= 2021
test_y = y[te]

with open(f"{PROJ_DIR}/xgb_mb_best_params.json") as f:
    xgb_meta = json.load(f)
with open(f"{PROJ_DIR}/rf_mb_best_params.json") as f:
    rf_meta = json.load(f)

dtrva = xgb.DMatrix(X[trva], label=y[trva], feature_names=feature_names)
dtest = xgb.DMatrix(X[te],   label=test_y,  feature_names=feature_names)

print(f"Fitting XGBoost ({xgb_meta['final_rounds']} rounds) ...")
xgb_model = xgb.train(xgb_meta["params"], dtrva,
                       num_boost_round=xgb_meta["final_rounds"],
                       verbose_eval=False)

xgb_prob              = xgb_model.predict(dtest)
auc_xgb               = roc_auc_score(test_y, xgb_prob)
fpr_xgb_c, tpr_xgb_c, thr_xgb_c = roc_curve(test_y, xgb_prob)
j                     = np.argmax(tpr_xgb_c - fpr_xgb_c)
thresh_xgb            = float(thr_xgb_c[j])
pred_xgb              = (xgb_prob >= thresh_xgb).astype(int)
tn_xgb, fp_xgb, fn_xgb, tp_xgb = confusion_matrix(test_y, pred_xgb, labels=[0,1]).ravel()
sens_xgb              = tp_xgb / (tp_xgb + fn_xgb)
fpr_xgb               = fp_xgb / (fp_xgb + tn_xgb)
flagged_xgb           = int(tp_xgb + fp_xgb)
youden_xgb            = sens_xgb - fpr_xgb
prec_xgb              = tp_xgb / flagged_xgb
lift_xgb              = sens_xgb / (flagged_xgb / len(test_y))

imp_raw = xgb_model.get_score(importance_type="gain")
xgb_imp = (pd.DataFrame(list(imp_raw.items()), columns=["feature", "importance"])
             .sort_values("importance", ascending=False).reset_index(drop=True))

print("Loading RF ...")
rf_preds   = pd.read_csv(f"{PROJ_DIR}/rf_test_preds.csv")
rf_imp_df  = pd.read_csv(f"{PROJ_DIR}/rf_variable_importance.csv")
rf_prob_arr            = rf_preds["rf_prob"].to_numpy()
rf_y_arr               = rf_preds["y_true"].to_numpy()
auc_rf                 = roc_auc_score(rf_y_arr, rf_prob_arr)
fpr_rf_c, tpr_rf_c, _ = roc_curve(rf_y_arr, rf_prob_arr)
tp_rf    = rf_meta["tp"];  fp_rf   = rf_meta["fp"]
tn_rf    = rf_meta["tn"];  fn_rf   = rf_meta["fn"]
thresh_rf  = rf_meta["threshold"]
sens_rf    = rf_meta["sensitivity"]
fpr_rf     = rf_meta["fpr"]
flagged_rf = rf_meta["flagged"]
youden_rf  = sens_rf - fpr_rf
prec_rf    = tp_rf / flagged_rf
lift_rf    = sens_rf / (flagged_rf / len(test_y))
n_pos      = int(test_y.sum())
prevalence = n_pos / len(test_y)

print(f"XGB  AUC={auc_xgb:.4f}  sens={sens_xgb:.4f}  FPR={fpr_xgb:.4f}")
print(f"RF   AUC={auc_rf:.4f}  sens={sens_rf:.4f}  FPR={fpr_rf:.4f}")


# ═════════════════════════════════════════════════════════════════════════════
# 1. Severity distribution
# ═════════════════════════════════════════════════════════════════════════════
print("\nSeverity distribution ...")
labels_sev = ["Fatal\nInjury", "Suspected\nSerious Injury",
               "Suspected\nMinor Injury", "Possible\nInjury"]
counts_sev = [35, 203, 1020, 1575]

fig, ax = plt.subplots(figsize=(SC, SC * 0.85))
bars = ax.bar(labels_sev, counts_sev, color=SEV_COLORS,
              width=0.55, edgecolor="white", linewidth=0.5)
for bar, n in zip(bars, counts_sev):
    ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 12,
            f"{n:,}", ha="center", va="bottom", fontsize=7.5, fontweight="bold")
ax.set_ylabel("Collisions")
ax.set_xlabel("Severity (KABCO)")
ax.set_ylim(0, 1850)
ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda x, _: f"{int(x):,}"))
ax.tick_params(axis="x", pad=3)
plt.tight_layout()
fig.savefig(f"{OUT_DIR}/fig_severity_distribution.png")
plt.close(); print("  fig_severity_distribution.png")


# ═════════════════════════════════════════════════════════════════════════════
# 2. Confusion matrices
# ═════════════════════════════════════════════════════════════════════════════
def save_confusion(tn, fp, fn, tp, thresh, color, fname):
    fig, ax = plt.subplots(figsize=(SC * 0.88, SC * 0.88))
    cm = np.array([[tn, fn], [fp, tp]])
    cmap = matplotlib.colors.LinearSegmentedColormap.from_list("c", ["#f9f9f9", color])
    ax.imshow(cm, cmap=cmap, vmin=0, vmax=cm.max(), aspect="auto")

    cell_lbl = [["TN", "FN"], ["FP", "TP"]]
    for i in range(2):
        for j in range(2):
            dark = cm[i, j] > cm.max() * 0.52
            ax.text(j, i, f"{cell_lbl[i][j]}\n{cm[i,j]:,}",
                    ha="center", va="center", fontsize=9, fontweight="bold",
                    color="white" if dark else "#212121")

    ax.set_xticks([0, 1]); ax.set_xticklabels(["No Crash", "Crash"])
    ax.set_yticks([0, 1]); ax.set_yticklabels(["Predicted 0", "Predicted 1"])
    ax.set_xlabel("Actual", labelpad=4)
    ax.tick_params(length=0)
    for spine in ax.spines.values():
        spine.set_visible(False)
    fig.text(0.5, -0.03, f"Youden's J threshold = {thresh:.4f}",
             ha="center", fontsize=7, color=GRAY, style="italic")
    plt.tight_layout()
    fig.savefig(f"{OUT_DIR}/{fname}")
    plt.close(); print(f"  {fname}")

save_confusion(tn_rf,  fp_rf,  fn_rf,  tp_rf,  thresh_rf,  RF_COLOR,  "fig_confusion_pf.png")
save_confusion(tn_xgb, fp_xgb, fn_xgb, tp_xgb, thresh_xgb, XGB_COLOR, "fig_confusion_xgb.png")


# ═════════════════════════════════════════════════════════════════════════════
# 3. ROC curve
# ═════════════════════════════════════════════════════════════════════════════
print("ROC curve ...")
fig, ax = plt.subplots(figsize=(SC, SC))
ax.plot(fpr_xgb_c, tpr_xgb_c, color=XGB_COLOR, lw=1.4,
        label=f"XGBoost (AUC = {auc_xgb:.4f})")
ax.scatter([fpr_xgb], [sens_xgb], color=XGB_COLOR, s=28, zorder=5, marker="D")
ax.plot(fpr_rf_c, tpr_rf_c, color=RF_COLOR, lw=1.4,
        label=f"Prob. Forest (AUC = {auc_rf:.4f})")
ax.scatter([fpr_rf], [sens_rf], color=RF_COLOR, s=28, zorder=5, marker="s")
ax.plot([0, 1], [0, 1], "--", color="#aaaaaa", lw=0.9, label="Random (AUC = 0.50)")

ax.set_xlabel("False Positive Rate")
ax.set_ylabel("True Positive Rate")
ax.set_xlim(-0.01, 1.01); ax.set_ylim(-0.01, 1.01)

# Annotate operating points
ax.annotate(f"J = {youden_xgb:.3f}", xy=(fpr_xgb, sens_xgb),
            xytext=(fpr_xgb + 0.06, sens_xgb - 0.07),
            fontsize=7, color=XGB_COLOR,
            arrowprops=dict(arrowstyle="-", color=XGB_COLOR, lw=0.7))
ax.annotate(f"J = {youden_rf:.3f}", xy=(fpr_rf, sens_rf),
            xytext=(fpr_rf + 0.06, sens_rf - 0.07),
            fontsize=7, color=RF_COLOR,
            arrowprops=dict(arrowstyle="-", color=RF_COLOR, lw=0.7))

ax.legend(loc="lower right", frameon=True)
plt.tight_layout()
fig.savefig(f"{OUT_DIR}/fig_roc.png")
plt.close(); print("  fig_roc.png")


# ═════════════════════════════════════════════════════════════════════════════
# 4. Variable importance
# ═════════════════════════════════════════════════════════════════════════════
def clean_label(name):
    name = name.strip("_`").replace("`", "")   # strip sanitized backticks → underscores
    name = re.sub(r"^_+|_+$", "", name)         # strip any remaining leading/trailing _
    name = re.sub(r"_Total\.Flow", " Flow", name)
    name = re.sub(r"_AVG\.Occupancy", " Occ.", name)
    name = re.sub(r"_AVG\.Speed", " Speed", name)
    name = re.sub(r"_lag1\b", " (lag1)", name)
    name = re.sub(r"_lag24\b", " (lag24)", name)
    name = re.sub(r"^sum_", "Summit ", name)
    name = re.sub(r"^sc_",  "S. Cruz ", name)
    name = re.sub(r"^scl_", "S. Clara ", name)
    return name.strip("_")

def save_importance(imp_df, top_n, color, xlabel, fname):
    top    = imp_df.head(top_n).copy()
    top["feature"] = top["feature"].apply(clean_label)
    labels = top["feature"].tolist()[::-1]
    vals   = top["importance"].tolist()[::-1]

    # Smart x-axis formatter: integers for large values, decimals for small
    max_val = max(vals)
    if max_val >= 50:
        x_fmt = mticker.FuncFormatter(lambda x, _: f"{x:,.0f}")
    elif max_val >= 1:
        x_fmt = mticker.FuncFormatter(lambda x, _: f"{x:.1f}")
    else:
        x_fmt = mticker.FuncFormatter(lambda x, _: f"{x:.3f}")

    fig, ax = plt.subplots(figsize=(FW, top_n * 0.27 + 0.55))
    ax.barh(range(len(labels)), vals, color=color, alpha=0.85,
            height=0.6, edgecolor="none")
    ax.set_yticks(range(len(labels)))
    ax.set_yticklabels(labels, fontsize=8)
    ax.set_xlabel(xlabel)
    ax.xaxis.set_major_formatter(x_fmt)
    ax.xaxis.set_major_locator(mticker.MaxNLocator(6, prune="both"))
    ax.set_ylim(-0.6, len(labels) - 0.4)
    ax.set_xlim(left=0)
    ax.grid(axis="x", linewidth=0.4, color="#e0e0e0")
    ax.set_axisbelow(True)
    plt.tight_layout()
    fig.savefig(f"{OUT_DIR}/{fname}")
    plt.close(); print(f"  {fname}")

save_importance(rf_imp_df, 20, RF_COLOR,  "Mean Decrease in Gini Impurity",
                "fig_importance_pf.png")
save_importance(xgb_imp,   20, XGB_COLOR, "Mean Gain",
                "fig_importance_xgb.png")


# ═════════════════════════════════════════════════════════════════════════════
# 5. Tuning parameters table
# ═════════════════════════════════════════════════════════════════════════════
print("Tuning table ...")

rows = [
    ("Trees (final model)",    "5,000",                    "103"),
    ("Max depth",              "4",                        "4"),
    ("Min node / leaf size",   "5  (min.node.size)",       "20  (min\\_child\\_weight)"),
    ("Feature fraction",       "50\\%  (mtry = 141)",      "80\\%  (colsample\\_bynode)"),
    ("Row fraction",           "70\\%  (sample.fraction)", "70\\%  (subsample)"),
    ("Regularization",         "Bootstrap + random mtry",  "L2 = 10.0  (reg\\_lambda)"),
    ("Learning rate",          "—",                        "0.05  (eta)"),
    ("Class imbalance",        "Probability leaves",       "scale\\_pos\\_weight = 37.22"),
    ("Importance metric",      "Gini impurity reduction",  "Mean gain"),
    ("CV mean Youden's J",     "0.2596  (±0.0325)",        "0.2791  (±0.0221)"),
]
col_labels = ["Parameter", "Probability Forest", "XGBoost"]

fig, ax = plt.subplots(figsize=(FW, len(rows) * 0.32 + 0.5))
ax.axis("off")

tbl = ax.table(cellText=rows, colLabels=col_labels,
               loc="center", cellLoc="left")
tbl.auto_set_font_size(False)
tbl.set_fontsize(8)
tbl.scale(1, 1.55)

col_w = [0.30, 0.35, 0.35]
for (r, c), cell in tbl.get_celld().items():
    cell.set_linewidth(0.4)
    cell.PAD = 0.05
    cell.set_width(col_w[c])
    if r == 0:
        cell.set_facecolor("#263238")
        cell.set_text_props(color="white", fontweight="bold", fontsize=8.5)
        cell.set_edgecolor("#263238")
    elif r % 2 == 1:
        cell.set_facecolor("#fafafa")
        cell.set_edgecolor("#e0e0e0")
        if c == 1: cell.set_text_props(color=RF_COLOR)
        if c == 2: cell.set_text_props(color=XGB_COLOR)
    else:
        cell.set_facecolor("white")
        cell.set_edgecolor("#e0e0e0")
        if c == 1: cell.set_text_props(color=RF_COLOR)
        if c == 2: cell.set_text_props(color=XGB_COLOR)

# booktabs-style top and bottom rules
for c in range(3):
    tbl[0, c].visible_edges = "T"
    tbl[len(rows), c].visible_edges = "B"

plt.tight_layout(pad=0.2)
fig.savefig(f"{OUT_DIR}/fig_tuning_table.png")
plt.close(); print("  fig_tuning_table.png")


# ═════════════════════════════════════════════════════════════════════════════
# 6. Results metrics table
# ═════════════════════════════════════════════════════════════════════════════
print("Results table ...")

better = {0:2, 1:1, 2:2, 3:2, 4:2, 5:2, 6:2, 7:None, 8:1, 9:2, 10:2, 11:1, 12:None, 13:None}

results_rows = [
    ("AUC",                  f"{auc_rf:.4f}",          f"{auc_xgb:.4f}"),
    ("Sensitivity (TPR)",    f"{sens_rf:.4f}",          f"{sens_xgb:.4f}"),
    ("False Positive Rate",  f"{fpr_rf:.4f}",           f"{fpr_xgb:.4f}"),
    ("Specificity",          f"{1-fpr_rf:.4f}",         f"{1-fpr_xgb:.4f}"),
    ("Precision (PPV)",      f"{prec_rf:.4f}",          f"{prec_xgb:.4f}"),
    ("Youden's J",           f"{youden_rf:.4f}",        f"{youden_xgb:.4f}"),
    ("Lift over random",     f"{lift_rf:.3f}×",         f"{lift_xgb:.3f}×"),
    ("Flagged hours",        f"{flagged_rf:,}",         f"{flagged_xgb:,}"),
    ("True Positives",       f"{tp_rf:,}",              f"{tp_xgb:,}"),
    ("False Positives",      f"{fp_rf:,}",              f"{fp_xgb:,}"),
    ("True Negatives",       f"{tn_rf:,}",              f"{tn_xgb:,}"),
    ("False Negatives",      f"{fn_rf:,}",              f"{fn_xgb:,}"),
    ("Test observations",    f"{len(test_y):,}",        f"{len(test_y):,}"),
    ("Prevalence",           f"{prevalence:.4f}",       f"{prevalence:.4f}"),
]

fig, ax = plt.subplots(figsize=(SC + 0.4, len(results_rows) * 0.27 + 0.5))
ax.axis("off")

tbl = ax.table(cellText=results_rows,
               colLabels=["Metric", "Prob. Forest", "XGBoost"],
               loc="center", cellLoc="center")
tbl.auto_set_font_size(False)
tbl.set_fontsize(8)
tbl.scale(1, 1.45)

col_w2 = [0.44, 0.28, 0.28]
for (r, c), cell in tbl.get_celld().items():
    cell.set_linewidth(0.4)
    cell.PAD = 0.04
    cell.set_width(col_w2[c])
    if r == 0:
        cell.set_facecolor("#263238")
        cell.set_text_props(color="white", fontweight="bold", fontsize=8.5)
        cell.set_edgecolor("#263238")
    else:
        ri = r - 1
        cell.set_edgecolor("#e0e0e0")
        cell.set_facecolor("#fafafa" if r % 2 == 1 else "white")
        if c == 0:
            cell.set_text_props(ha="left", fontsize=7.5)
        elif c == 1:
            bw = better.get(ri) == 1
            cell.set_text_props(fontweight="bold" if bw else "normal",
                                color=RF_COLOR if bw else "#212121")
        elif c == 2:
            bw = better.get(ri) == 2
            cell.set_text_props(fontweight="bold" if bw else "normal",
                                color=XGB_COLOR if bw else "#212121")

plt.tight_layout(pad=0.2)
fig.savefig(f"{OUT_DIR}/fig_results_table.png")
plt.close(); print("  fig_results_table.png")


# ═════════════════════════════════════════════════════════════════════════════
# 7. BCR table
# ═════════════════════════════════════════════════════════════════════════════
print("BCR table ...")

C_BASE  = 113_896_653.0
WINDOW  = 4.75

def ann_cost(flagged, n_off):
    return (flagged * 122.51 + flagged * (1/8.6) * 149.05 + flagged * 20 * 1.45) * n_off / WINDOW

cmfs      = [0.06, 0.09, 0.12]
officers  = [1, 2, 3, 4]
cmf_labs  = ["6% reduction", "9% reduction", "12% reduction"]
off_labs  = ["1 officer", "2 officers", "3 officers", "4 officers"]

def bcr_grid(cap, flagged):
    return [[C_BASE * cap * cmf / ann_cost(flagged, n) for cmf in cmfs] for n in officers]

rf_bcr  = bcr_grid(sens_rf,  flagged_rf)
xgb_bcr = bcr_grid(sens_xgb, flagged_xgb)

# Combined table: rows = officer counts, cols = (PF 6/9/12, XGB 6/9/12)
combined_rows = []
for i, off_lab in enumerate(off_labs):
    row = [off_lab]
    row += [f"{rf_bcr[i][j]:.2f}"  for j in range(3)]
    row += [f"{xgb_bcr[i][j]:.2f}" for j in range(3)]
    combined_rows.append(row)

col_labels_bcr = ["Deployment",
                  "PF 6%", "PF 9%", "PF 12%",
                  "XGB 6%", "XGB 9%", "XGB 12%"]

fig, ax = plt.subplots(figsize=(FW, len(combined_rows) * 0.38 + 0.9))
ax.axis("off")

tbl = ax.table(cellText=combined_rows, colLabels=col_labels_bcr,
               loc="center", cellLoc="center")
tbl.auto_set_font_size(False)
tbl.set_fontsize(8.5)
tbl.scale(1, 1.7)

col_w3 = [0.19] + [0.135] * 6
for (r, c), cell in tbl.get_celld().items():
    cell.set_linewidth(0.4)
    cell.PAD = 0.05
    cell.set_width(col_w3[c])
    if r == 0:
        if c == 0:
            cell.set_facecolor("#263238")
            cell.set_text_props(color="white", fontweight="bold")
        elif c in [1, 2, 3]:
            cell.set_facecolor(RF_COLOR)
            cell.set_text_props(color="white", fontweight="bold")
        else:
            cell.set_facecolor(XGB_COLOR)
            cell.set_text_props(color="white", fontweight="bold")
        cell.set_edgecolor("white")
    else:
        ri = r - 1
        cell.set_edgecolor("#e0e0e0")
        cell.set_facecolor("#fafafa" if r % 2 == 1 else "white")
        if c == 0:
            cell.set_text_props(ha="left", fontweight="bold", fontsize=8)
        elif 1 <= c <= 3:
            val = rf_bcr[ri][c - 1]
            cell.set_text_props(color=RF_COLOR,
                                fontweight="bold" if val >= 5.0 else "normal")
        else:
            val = xgb_bcr[ri][c - 4]
            cell.set_text_props(color=XGB_COLOR,
                                fontweight="bold" if val >= 5.0 else "normal")

plt.tight_layout(pad=0.2)
fig.savefig(f"{OUT_DIR}/fig_bcr.png")
plt.close(); print("  fig_bcr.png")


# ═════════════════════════════════════════════════════════════════════════════
# 8. Expanding-window CV diagram
# ═════════════════════════════════════════════════════════════════════════════
print("CV diagram ...")

fig, ax = plt.subplots(figsize=(FW, 2.4))
ax.axis("off")
ax.set_xlim(-0.5, 12.5)
ax.set_ylim(-0.8, 5.2)

years  = list(range(2014, 2026))
yr_x   = {yr: i for i, yr in enumerate(years)}

TR_C   = "#90caf9"
VAL_C  = "#ffcc02"
TEST_C = "#ef9a9a"
HOLD_C = "#eeeeee"
BH     = 0.52

folds = [
    ("Fold 1", 2014, 2017),
    ("Fold 2", 2014, 2018),
    ("Fold 3", 2014, 2019),
    ("Fold 4", 2014, 2020),
]

for fi, (label, tr_start, val_yr) in enumerate(folds):
    yp = fi + 1
    x0 = yr_x[tr_start]; x1 = yr_x[val_yr]
    ax.barh(yp, x1 - x0, left=x0, height=BH, color=TR_C,
            edgecolor="#1565c0", linewidth=0.5, align="center")
    x2 = yr_x[val_yr + 1] if val_yr + 1 in yr_x else x1 + 1
    ax.barh(yp, x2 - x1, left=x1, height=BH, color=VAL_C,
            edgecolor="#f57f17", linewidth=0.5, align="center")
    ax.barh(yp, yr_x[2025] - x2, left=x2, height=BH, color=HOLD_C,
            edgecolor="#bdbdbd", linewidth=0.4, alpha=0.5, align="center")
    ax.text(-0.55, yp, label, va="center", ha="right", fontsize=8, color="#37474f")

# Test bar
tx = yr_x[2021]
ax.barh(0, yr_x[2025] - tx, left=tx, height=BH, color=TEST_C,
        edgecolor="#c62828", linewidth=0.5, align="center")
ax.text(-0.55, 0, "Test set", va="center", ha="right", fontsize=8,
        color="#c62828", fontweight="bold")

# Year labels
for yr in range(2014, 2026):
    ax.text(yr_x[yr], -0.42, str(yr), ha="center", va="top",
            fontsize=7, color=GRAY, rotation=45)

legend_items = [
    mpatches.Patch(facecolor=TR_C,   edgecolor="#1565c0", label="Training"),
    mpatches.Patch(facecolor=VAL_C,  edgecolor="#f57f17", label="Validation"),
    mpatches.Patch(facecolor=TEST_C, edgecolor="#c62828", label="Test (held out)"),
]
ax.legend(handles=legend_items, loc="upper left", fontsize=8,
          frameon=True, bbox_to_anchor=(0.01, 1.05))

plt.tight_layout(pad=0.3)
fig.savefig(f"{OUT_DIR}/fig_cv_diagram.png")
plt.close(); print("  fig_cv_diagram.png")


# ── Summary ───────────────────────────────────────────────────────────────────
print(f"\nAll figures saved to {OUT_DIR}/")
for f in sorted(os.listdir(OUT_DIR)):
    kb = os.path.getsize(f"{OUT_DIR}/{f}") // 1024
    print(f"  {f:<40} {kb} KB")
