#!/usr/bin/env python3
"""Walk-forward backtest: learned models vs oref's own forecasts on Nightscout history.

Input: the CSVs written by fetch_ns.py (default ~/ns-data).
Output: results.json next to the data, plus a printed summary.

Every model is scored on the same moments. Walk-forward: for each calendar month
after the warm-up, models train on everything before that month and are tested on
that month only, so nothing from the future leaks into training.

Research only. Nothing here doses or feeds back into Trio.
"""
import argparse
import json
import os

import lightgbm as lgb
import numpy as np
import pandas as pd
from sklearn.metrics import roc_auc_score

STEP = 300_000  # 5 min in ms
HYPO = 70
TZ = "Europe/Amsterdam"
LAGS = 12  # one hour of 5-minute deltas


def load(dirpath):
    e = pd.read_csv(os.path.join(dirpath, "entries.csv.gz"))
    d = pd.read_csv(os.path.join(dirpath, "devicestatus.csv.gz"))
    t = pd.read_csv(os.path.join(dirpath, "treatments.csv.gz"))
    return e, d, t


def build_grid(e, d, t):
    d = d[d.pred60.notna()]
    lo = int(max(e.t_ms.min(), d.t_ms.min() - 86_400_000) // STEP)
    hi = int(e.t_ms.max() // STEP) + 1
    idx = np.arange(lo, hi)
    g = pd.DataFrame(index=idx)

    e = e.assign(slot=(e.t_ms / STEP).round().astype(int))
    e = e[(e.slot >= lo) & (e.slot < hi) & (e.sgv >= 39)]
    g["bg"] = e.groupby("slot").sgv.mean()
    g["bg"] = g.bg.interpolate(limit=3, limit_area="inside")

    d = d.assign(slot=(d.t_ms / STEP).round().astype(int)).sort_values("t_ms")
    d = d[(d.slot >= lo) & (d.slot < hi)].groupby("slot").last()
    for c in ["iob", "cob", "pred30", "pred60", "predmin60", "ztmin60", "rate"]:
        g[c] = d[c]
    g[["iob", "cob", "rate"]] = g[["iob", "cob", "rate"]].ffill(limit=2)

    t = t.assign(slot=(t.t_ms / STEP).round().astype(int))
    t = t[(t.slot >= lo) & (t.slot < hi)]
    g["carbs"] = t.groupby("slot").carbs.sum().reindex(idx).fillna(0)
    g["insulin"] = t.groupby("slot").insulin.sum().reindex(idx).fillna(0)
    for w in (12, 36):  # 1h and 3h, past only
        g[f"carbs_{w}"] = g.carbs.rolling(w, min_periods=1).sum()
        g[f"ins_{w}"] = g.insulin.rolling(w, min_periods=1).sum()

    ts = pd.to_datetime(g.index * STEP, unit="ms", utc=True).tz_convert(TZ)
    hour = ts.hour + ts.minute / 60
    g["hsin"], g["hcos"] = np.sin(hour / 24 * 2 * np.pi), np.cos(hour / 24 * 2 * np.pi)
    g["month"] = ts.strftime("%Y-%m")
    g["date"] = ts.strftime("%Y-%m-%d")
    g["night"] = (ts.hour < 6).astype(int)

    for k in range(1, LAGS + 1):
        g[f"d{k}"] = g.bg.shift(k - 1) - g.bg.shift(k)
    g["y30"], g["y60"] = g.bg.shift(-6), g.bg.shift(-12)
    fut = pd.concat([g.bg.shift(-k) for k in range(1, 13)], axis=1)
    g["futmin"] = fut.min(axis=1, skipna=False)
    g["low60"] = (g.futmin < HYPO).astype(float)
    for c in ["pred30", "pred60", "predmin60", "ztmin60"]:
        g[f"o_{c}"] = g[c] - g.bg
    return g


BASE_FEATS = ["bg"] + [f"d{k}" for k in range(1, LAGS + 1)] + ["iob", "cob", "carbs_12", "carbs_36", "ins_12", "ins_36", "hsin", "hcos"]
OREF_FEATS = ["o_pred30", "o_pred60", "o_predmin60", "o_ztmin60", "rate"]


def usable(g):
    need = BASE_FEATS + ["y30", "y60", "futmin", "pred30", "pred60", "predmin60"]
    return g.dropna(subset=need)


def fit_reg(tr, feats, target):
    m = lgb.LGBMRegressor(n_estimators=400, learning_rate=0.05, num_leaves=31, min_child_samples=50,
                          subsample=0.8, subsample_freq=1, colsample_bytree=0.8, verbose=-1)
    m.fit(tr[feats], tr[target] - tr.bg)
    return m


def fit_clf(tr, feats):
    # Strongly regularised and unweighted: with only a few hundred low events per
    # month, class weighting and deep trees overfit and lose to oref.
    m = lgb.LGBMClassifier(n_estimators=300, learning_rate=0.03, num_leaves=15, min_child_samples=200,
                           subsample=0.8, subsample_freq=1, colsample_bytree=0.8, verbose=-1)
    m.fit(tr[feats], tr.low60)
    return m


def trend(te, h):
    b = te.bg.values
    slope = (3 * (te.d1 + te.d2 + te.d3).values + (te.d2.values)) / 10  # ~LS slope over last 4 points
    return np.clip(b + slope * h / 5, 39, 400)


def walk_forward(g, warmup_months):
    s = usable(g)
    months = sorted(s.month.unique())
    rows = []
    for m in months[warmup_months:]:
        tr, te = s[s.month < m], s[s.month == m]
        if len(te) < 2000:
            continue
        out = te[["bg", "y30", "y60", "low60", "night", "date"]].copy()
        out["month"] = m
        out["persist30"] = out["persist60"] = te.bg
        out["trend30"], out["trend60"] = trend(te, 30), trend(te, 60)
        out["oref30"], out["oref60"] = te.pred30, te.pred60
        out["oref_lowscore"] = -te.predmin60  # higher = more likely low
        for name, feats in (("lgbm", BASE_FEATS), ("lgbm_oref", BASE_FEATS + OREF_FEATS)):
            for h in (30, 60):
                out[f"{name}{h}"] = np.clip(te.bg + fit_reg(tr, feats, f"y{h}").predict(te[feats]), 39, 400)
        out["clf_lowscore"] = fit_clf(tr, BASE_FEATS + OREF_FEATS).predict_proba(te[BASE_FEATS + OREF_FEATS])[:, 1]
        rows.append(out)
        print(f"{m}: train {len(tr):>7}  test {len(te):>6}  lows {int(te.low60.sum())}", flush=True)
    return pd.concat(rows)


REG_MODELS = ["persist", "trend", "oref", "lgbm", "lgbm_oref"]


def score(r):
    res = {"n": int(len(r)), "days": float(r.date.nunique()), "reg": {}, "low": {}}
    for m in REG_MODELS:
        res["reg"][m] = {}
        for h in (30, 60):
            e = r[f"{m}{h}"] - r[f"y{h}"]
            res["reg"][m][h] = {"rmse": float(np.sqrt((e ** 2).mean())), "mae": float(e.abs().mean())}
    y = r.low60.values.astype(bool)
    oref_flag = (-r.oref_lowscore.values) < HYPO
    budget = int(oref_flag.sum())
    order = np.argsort(-r.clf_lowscore.values)
    clf_flag = np.zeros(len(r), bool)
    clf_flag[order[:budget]] = True
    caught_needed = int((oref_flag & y).sum())
    cum = np.cumsum(y[order])
    need = int(np.searchsorted(cum, caught_needed) + 1) if caught_needed else 0
    res["low"] = {
        "events": int(y.sum()),
        "budget": budget,
        "oref_caught": caught_needed,
        "clf_caught": int((clf_flag & y).sum()),
        "clf_alarms_to_match_oref": need,
        "auc_oref": float(roc_auc_score(y, r.oref_lowscore)) if 0 < y.sum() < len(y) else None,
        "auc_clf": float(roc_auc_score(y, r.clf_lowscore)) if 0 < y.sum() < len(y) else None,
        "oref_alarms_per_day": budget / max(res["days"], 1),
    }
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=os.path.expanduser("~/ns-data"))
    ap.add_argument("--warmup", type=int, default=3, help="months of history before the first test month")
    a = ap.parse_args()
    g = build_grid(*load(a.data))
    r = walk_forward(g, a.warmup)
    out = {"overall": score(r), "months": {m: score(x) for m, x in r.groupby("month")}}
    with open(os.path.join(a.data, "results.json"), "w") as f:
        json.dump(out, f, indent=1)
    r.to_csv(os.path.join(a.data, "predictions.csv.gz"))
    o = out["overall"]
    print(f"\n{o['n']} test moments over {o['days']:.0f} days")
    for m in REG_MODELS:
        print(f"  {m:10s} RMSE30 {o['reg'][m][30]['rmse']:6.1f}  RMSE60 {o['reg'][m][60]['rmse']:6.1f} mg/dL")
    print("  lows:", o["low"])


if __name__ == "__main__":
    main()
