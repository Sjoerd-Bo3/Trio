#!/usr/bin/env python3
"""Episode-level early warning: how many minutes before a low or high starts does each
model warn, when every model may raise exactly as many alarms as oref did?

Reads predictions_seq.csv.gz from seq.py and writes episodes.json.
Research only.
"""
import json
import os
import sys

import numpy as np
import pandas as pd

LOW, HIGH = 70, 250
LOOKBACK = 12  # warn window: up to 60 min before onset
QUIET = 6  # onset only counts after 30 min on the other side of the threshold


def onsets(bg, below, thr):
    cross = bg < thr if below else bg > thr
    prev_quiet = pd.concat([(~cross).shift(k) for k in range(1, QUIET + 1)], axis=1).all(axis=1)
    return cross & prev_quiet


def equal_budget_flags(score, budget):
    flags = np.zeros(len(score), bool)
    flags[np.argsort(-score.values)[:budget]] = True
    return pd.Series(flags, index=score.index)


def leads(flags, onset_idx, bg_index):
    out = []
    have = set(bg_index)
    for i in onset_idx:
        window = [i - k for k in range(LOOKBACK, 0, -1)]
        if not all(j in have for j in window):
            continue
        hit = [j for j in window if flags.get(j, False)]
        out.append(5 * (i - hit[0]) if hit else 0)
    return np.array(out)


def summarise(lead):
    return {"episodes": int(len(lead)), "warned": float((lead > 0).mean()),
            "warned_15": float((lead >= 15).mean()), "warned_30": float((lead >= 30).mean()),
            "median_lead_when_warned": float(np.median(lead[lead > 0])) if (lead > 0).any() else 0.0}


def main(path):
    r = pd.read_csv(os.path.join(path, "predictions_seq.csv.gz"), index_col=0).sort_index()
    bg = r.bg
    # contiguous test slots only; onsets need the preceding readings present
    full = bg.reindex(np.arange(bg.index.min(), bg.index.max() + 1))
    res = {}

    lo_on = onsets(full, True, LOW)
    lo_idx = [i for i in full.index[lo_on.values] if i in r.index]
    oref_low = (-r.oref_lowscore) < LOW
    budget = int(oref_low.sum())
    res["low"] = {"budget_per_day": budget / r.date.nunique(), "threshold": "CGM < 70 mg/dL"}
    for name, score in (("oref", r.oref_lowscore), ("lgbm", r.lgbm_lowscore),
                        ("seq_scratch", r.seq_scratch_lowscore), ("seq_pre", r.seq_pre_lowscore)):
        flags = oref_low if name == "oref" else equal_budget_flags(score, budget)
        res["low"][name] = summarise(leads(flags.to_dict(), lo_idx, r.index))

    hi_on = onsets(full, False, HIGH)
    hi_idx = [i for i in full.index[hi_on.values] if i in r.index]
    oref_hi_score = r[["oref30", "oref60"]].max(axis=1)
    oref_hi = oref_hi_score > HIGH
    budget = int(oref_hi.sum())
    res["high"] = {"budget_per_day": budget / r.date.nunique(), "threshold": "CGM > 250 mg/dL"}
    for name in ("oref", "persist", "lgbm_oref", "seq_scratch", "seq_pre"):
        score = r[[f"{name}30", f"{name}60"]].max(axis=1)
        flags = oref_hi if name == "oref" else equal_budget_flags(score, budget)
        res["high"][name] = summarise(leads(flags.to_dict(), hi_idx, r.index))

    with open(os.path.join(path, "episodes.json"), "w") as f:
        json.dump(res, f, indent=1)
    for kind in ("low", "high"):
        print(kind, f"alarm budget {res[kind]['budget_per_day']:.1f}/day")
        for k, v in res[kind].items():
            if isinstance(v, dict):
                print(f"  {k:12s} episodes {v['episodes']:4d}  warned {v['warned']:.0%}  >=15min {v['warned_15']:.0%}  "
                      f">=30min {v['warned_30']:.0%}  median lead {v['median_lead_when_warned']:.0f} min")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/ns-data"))
