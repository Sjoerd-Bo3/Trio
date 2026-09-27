#!/usr/bin/env python3
"""Sequence model with self-supervised pretraining on CGM-only history.

1. Pretrain: a GRU reads the last 3 h of CGM and learns to forecast the next hour,
   using every year of CGM data that lies before the first test month (so nothing
   from the test period leaks into pretraining).
2. Fine-tune, walk-forward per month: the pretrained encoder plus a head that also
   sees loop context (IOB, COB, carbs, insulin, oref's forecasts) predicts BG at
   +30/+60 min and P(CGM < 70 within 60 min).
3. The same fine-tune from random weights shows what pretraining adds; LightGBM
   from bench.py is rerun on the exact same moments as reference.

Research only. Nothing here doses or feeds back into Trio.
"""
import argparse
import json
import os

import numpy as np
import pandas as pd
import torch
from torch import nn

import bench

HIST = 36  # 3 h of 5-minute readings
HOR = 12  # 1 h ahead
STATIC = ["iob", "cob", "carbs_12", "carbs_36", "ins_12", "ins_36", "hsin", "hcos",
          "o_pred30", "o_pred60", "o_predmin60", "o_ztmin60", "rate"]
torch.set_num_threads(os.cpu_count() or 4)


def cgm_grid(e):
    e = e[e.sgv >= 39].assign(slot=(e.t_ms / bench.STEP).round().astype(int))
    idx = np.arange(e.slot.min(), e.slot.max() + 1)
    bg = e.groupby("slot").sgv.mean().reindex(idx).interpolate(limit=3, limit_area="inside")
    return idx, bg.values


def seq_inputs(bg, ends):
    """[n, HIST, 2]: normalised BG and 5-min delta for the HIST readings ending at each index."""
    w = np.lib.stride_tricks.sliding_window_view(bg, HIST + 1)[ends - HIST]  # includes one extra past point for deltas
    x = np.stack([(w[:, 1:] - 140) / 50, np.diff(w, axis=1) / 5], axis=-1)
    return x.astype(np.float32)


class Encoder(nn.Module):
    def __init__(self, hidden=64):
        super().__init__()
        self.gru = nn.GRU(2, hidden, num_layers=2, batch_first=True, dropout=0.1)

    def forward(self, x):
        return self.gru(x)[1][-1]


class PretrainNet(nn.Module):
    def __init__(self, enc):
        super().__init__()
        self.enc = enc
        self.head = nn.Sequential(nn.Linear(64 + 2, 64), nn.ReLU(), nn.Linear(64, HOR))

    def forward(self, x, tod):
        return self.head(torch.cat([self.enc(x), tod], 1))


class FineNet(nn.Module):
    def __init__(self, enc, n_static):
        super().__init__()
        self.enc = enc
        self.head = nn.Sequential(nn.Linear(64 + n_static, 64), nn.ReLU(), nn.Dropout(0.1), nn.Linear(64, 3))

    def forward(self, x, s):
        return self.head(torch.cat([self.enc(x), s], 1))  # [delta30, delta60, low logit]


def batches(n, bs, shuffle):
    order = np.random.permutation(n) if shuffle else np.arange(n)
    for i in range(0, n, bs):
        yield order[i:i + bs]


def pretrain(idx, bg, cutoff_slot, epochs):
    fut = np.lib.stride_tricks.sliding_window_view(bg, HOR + 1)
    ends = np.arange(HIST, len(bg) - HOR)
    ends = ends[idx[ends] + HOR < cutoff_slot]
    hist_ok = ~np.isnan(np.lib.stride_tricks.sliding_window_view(bg, HIST + 1)[ends - HIST]).any(1)
    fut_ok = ~np.isnan(fut[ends]).any(1)
    ends = ends[hist_ok & fut_ok]
    x = seq_inputs(bg, ends)
    y = ((fut[ends][:, 1:] - bg[ends][:, None]) / 50).astype(np.float32)
    ts = pd.to_datetime(idx[ends] * bench.STEP, unit="ms", utc=True).tz_convert(bench.TZ)
    h = (ts.hour + ts.minute / 60).values / 24 * 2 * np.pi
    tod = np.stack([np.sin(h), np.cos(h)], 1).astype(np.float32)
    n_val = len(ends) // 20
    print(f"pretrain on {len(ends) - n_val:,} windows ({len(ends) / 288:.0f} days of CGM), validate on {n_val:,}", flush=True)
    net = PretrainNet(Encoder())
    opt = torch.optim.Adam(net.parameters(), 2e-3)
    X, Y, T = map(torch.from_numpy, (x, y, tod))
    tr, va = slice(0, len(ends) - n_val), slice(len(ends) - n_val, None)
    best, best_state = 1e9, None
    for ep in range(epochs):
        net.train()
        for b in batches(len(ends) - n_val, 512, True):
            opt.zero_grad()
            loss = ((net(X[tr][b], T[tr][b]) - Y[tr][b]) ** 2).mean()
            loss.backward()
            opt.step()
        net.eval()
        with torch.no_grad():
            pv = net(X[va], T[va])
            v = ((pv - Y[va]) ** 2).mean().item()
            rmse60 = float(np.sqrt(((pv[:, -1] - Y[va][:, -1]) ** 2).mean().item()) * 50)
        print(f"  epoch {ep + 1}: val loss {v:.4f}  (val RMSE +60 {rmse60:.1f} mg/dL, CGM only)", flush=True)
        if v < best:
            best, best_state = v, {k: t.clone() for k, t in net.enc.state_dict().items()}
    return best_state


def fine_tune(x_tr, s_tr, y_tr, x_te, s_te, enc_state, epochs=12):
    torch.manual_seed(0)
    enc = Encoder()
    if enc_state is not None:
        enc.load_state_dict(enc_state)
    net = FineNet(enc, s_tr.shape[1])
    groups = [{"params": net.head.parameters(), "lr": 2e-3},
              {"params": net.enc.parameters(), "lr": 5e-4 if enc_state is not None else 2e-3}]
    opt = torch.optim.Adam(groups, weight_decay=1e-5)
    n_val = len(x_tr) // 10
    X, S, Y = map(torch.from_numpy, (x_tr, s_tr, y_tr))
    tr, va = slice(0, len(x_tr) - n_val), slice(len(x_tr) - n_val, None)
    bce = nn.BCEWithLogitsLoss()

    def loss_fn(out, y):
        return ((out[:, :2] - y[:, :2]) ** 2).mean() + 0.5 * bce(out[:, 2], y[:, 2])

    best, best_state = 1e9, None
    for _ in range(epochs):
        net.train()
        for b in batches(len(x_tr) - n_val, 256, True):
            opt.zero_grad()
            loss_fn(net(X[tr][b], S[tr][b]), Y[tr][b]).backward()
            opt.step()
        net.eval()
        with torch.no_grad():
            v = loss_fn(net(X[va], S[va]), Y[va]).item()
        if v < best:
            best, best_state = v, {k: t.clone() for k, t in net.state_dict().items()}
    net.load_state_dict(best_state)
    net.eval()
    with torch.no_grad():
        out = net(torch.from_numpy(x_te), torch.from_numpy(s_te)).numpy()
    return out[:, 0] * 50, out[:, 1] * 50, 1 / (1 + np.exp(-out[:, 2]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=os.path.expanduser("~/ns-data"))
    ap.add_argument("--warmup", type=int, default=2)
    ap.add_argument("--pre-epochs", type=int, default=6)
    a = ap.parse_args()
    np.random.seed(0)
    torch.manual_seed(0)

    e, d, t = bench.load(a.data)
    g = bench.build_grid(e, d, t)
    s = bench.usable(g)
    months = sorted(s.month.unique())
    test_months = months[a.warmup:]

    # full-history CGM grid, aligned to the loop grid by slot number
    idx, bg_all = cgm_grid(e)
    slot_pos = pd.Series(np.arange(len(idx)), index=idx)
    pos = slot_pos.reindex(s.index).values
    ok = ~np.isnan(pos)
    ok[ok] = ~np.isnan(np.lib.stride_tricks.sliding_window_view(bg_all, HIST + 1)[pos[ok].astype(int) - HIST]).any(1)
    s = s[ok]
    pos = slot_pos.reindex(s.index).values.astype(int)

    first_test_slot = int(s[s.month == test_months[0]].index.min())
    enc_state = pretrain(idx, bg_all, first_test_slot, a.pre_epochs)

    X = seq_inputs(bg_all, pos)
    rows = []
    for m in test_months:
        trm, tem = (s.month < m).values, (s.month == m).values
        if tem.sum() < 2000:
            continue
        tr, te = s[trm], s[tem]
        st = tr[STATIC].fillna(0)
        mu, sd = st.mean(), st.std().replace(0, 1)
        s_tr = ((st - mu) / sd).values.astype(np.float32)
        s_te = ((te[STATIC].fillna(0) - mu) / sd).values.astype(np.float32)
        y_tr = np.stack([(tr.y30 - tr.bg) / 50, (tr.y60 - tr.bg) / 50, tr.low60], 1).astype(np.float32)
        out = te[["bg", "y30", "y60", "low60", "night", "date"]].copy()
        out["month"] = m
        out["persist30"] = out["persist60"] = te.bg
        out["trend30"], out["trend60"] = bench.trend(te, 30), bench.trend(te, 60)
        out["oref30"], out["oref60"] = te.pred30, te.pred60
        out["oref_lowscore"] = -te.predmin60
        feats = bench.BASE_FEATS + bench.OREF_FEATS
        for h in (30, 60):
            out[f"lgbm_oref{h}"] = np.clip(te.bg + bench.fit_reg(tr, feats, f"y{h}").predict(te[feats]), 39, 400)
        out["lgbm_lowscore"] = bench.fit_clf(tr, feats).predict_proba(te[feats])[:, 1]
        for name, state in (("seq_pre", enc_state), ("seq_scratch", None)):
            d30, d60, p = fine_tune(X[trm], s_tr, y_tr, X[tem], s_te, state)
            out[f"{name}30"], out[f"{name}60"] = np.clip(te.bg + d30, 39, 400), np.clip(te.bg + d60, 39, 400)
            out[f"{name}_lowscore"] = p
        rows.append(out)
        print(f"{m}: train {trm.sum():>6}  test {tem.sum():>5}  "
              + "  ".join(f"{k} {np.sqrt(((out[k + '60'] - out.y60) ** 2).mean()):.1f}" for k in ("persist", "oref", "lgbm_oref", "seq_scratch", "seq_pre")),
              flush=True)
    r = pd.concat(rows)
    r.to_csv(os.path.join(a.data, "predictions_seq.csv.gz"))
    res = {"overall": score(r), "months": {m: score(x) for m, x in r.groupby("month")}}
    with open(os.path.join(a.data, "results_seq.json"), "w") as f:
        json.dump(res, f, indent=1)
    o = res["overall"]
    print(f"\n{o['n']} test moments over {o['days']:.0f} days")
    for k, v in o["reg"].items():
        print(f"  {k:12s} RMSE30 {v['30']['rmse']:5.1f}  RMSE60 {v['60']['rmse']:5.1f} mg/dL")
    for k, v in o["low"].items():
        print(f"  low {k:12s}", v)


REG = ["persist", "trend", "oref", "lgbm_oref", "seq_scratch", "seq_pre"]
LOW = ["oref", "lgbm", "seq_scratch", "seq_pre"]


def score(r):
    from sklearn.metrics import roc_auc_score
    res = {"n": int(len(r)), "days": float(r.date.nunique()), "reg": {}, "low": {}}
    for m in REG:
        res["reg"][m] = {str(h): {"rmse": float(np.sqrt(((r[f"{m}{h}"] - r[f"y{h}"]) ** 2).mean())),
                                  "mae": float((r[f"{m}{h}"] - r[f"y{h}"]).abs().mean())} for h in (30, 60)}
    y = r.low60.values.astype(bool)
    budget = int(((-r.oref_lowscore.values) < bench.HYPO).sum())
    night = r.night.values.astype(bool)
    for m in LOW:
        sc = r[f"{m}_lowscore"].values
        top = np.zeros(len(r), bool)
        top[np.argsort(-sc)[:budget]] = True
        res["low"][m] = {"auc": float(roc_auc_score(y, sc)), "caught": int((top & y).sum()), "events": int(y.sum()),
                         "budget": budget, "night_caught": int((top & y & night).sum()), "night_events": int((y & night).sum())}
    return res


if __name__ == "__main__":
    main()
