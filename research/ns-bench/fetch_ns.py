#!/usr/bin/env python3
"""Download Nightscout history into compact local CSVs for offline model research.

Reads NS_URL and NS_TOKEN (a read-only "readable" token) from the environment and
pages through the API one week at a time, so years of data never land in a single
response. Only the fields the research needs are kept; the raw devicestatus
documents (which carry full predBGs arrays) are dropped after compaction.

Output (default ~/ns-data, deliberately outside the repo -- this is health data
and must never be committed):
  entries.csv.gz       t_ms, sgv
  devicestatus.csv.gz  t_ms, bg, iob, cob, pred_line, pred30, pred60, predmin60, ztmin60, rate, smb
  treatments.csv.gz    t_ms, event, carbs, insulin, rate, duration

Usage:
  python3 fetch_ns.py --since 2021-01-01 [--until 2026-09-27] [--out ~/ns-data]
Re-running resumes: weeks already downloaded are skipped.
"""
import argparse
import csv
import datetime as dt
import gzip
import json
import os
import sys
import time
import urllib.parse
import urllib.request

WEEK = dt.timedelta(days=7)


def get(base, path, params, token):
    if token:
        params = {**params, "token": token}
    url = f"{base.rstrip('/')}{path}?{urllib.parse.urlencode(params)}"
    for attempt in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"Accept": "application/json"}), timeout=120) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                sys.exit(f"Nightscout refused the request ({e.code}); check NS_TOKEN has the 'readable' role.")
            err = e
        except Exception as e:  # network hiccup: back off and retry
            err = e
        time.sleep(2 ** attempt)
    raise RuntimeError(f"giving up on {path}: {err}")


def iso(d):
    return d.strftime("%Y-%m-%dT%H:%M:%S.000Z")


def ms(d):
    return int(d.timestamp() * 1000)


def parse_time(s):
    try:
        return int(dt.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp() * 1000)
    except (AttributeError, ValueError):
        return None


def compact_entries(docs):
    for e in docs:
        if isinstance(e.get("sgv"), (int, float)) and e.get("date"):
            yield [int(e["date"]), int(e["sgv"])]


def compact_devicestatus(docs):
    for d in docs:
        o = d.get("openaps") or {}
        s = o.get("suggested") or o.get("enacted")
        if not s:
            continue
        t = parse_time(s.get("timestamp") or s.get("deliverAt") or d.get("created_at"))
        if t is None:
            continue
        iob = o.get("iob")
        iob = iob[0] if isinstance(iob, list) and iob else iob
        iob = iob.get("iob") if isinstance(iob, dict) else s.get("IOB")
        cob = s.get("COB")
        preds = s.get("predBGs") or {}
        line = "COB" if (cob or 0) > 0 and preds.get("COB") else next((k for k in ("UAM", "IOB", "ZT") if preds.get(k)), "")
        p = preds.get(line) or []
        zt = preds.get("ZT") or []
        en = o.get("enacted") or {}
        yield [t, s.get("bg", ""), "" if iob is None else iob, "" if cob is None else cob, line,
               p[6] if len(p) > 6 else "", p[12] if len(p) > 12 else "", min(p[:13]) if len(p) > 12 else "",
               min(zt[:13]) if len(zt) > 12 else "", en.get("rate", ""), en.get("units", "")]


def compact_treatments(docs):
    for x in docs:
        t = parse_time(x.get("created_at"))
        if t is not None:
            yield [t, x.get("eventType", ""), x.get("carbs") or "", x.get("insulin") or "",
                   x.get("rate", x.get("absolute", "")), x.get("duration", "")]


KINDS = {
    "entries": ("/api/v1/entries/sgv.json", "date", ms, compact_entries, ["t_ms", "sgv"]),
    "devicestatus": ("/api/v1/devicestatus.json", "created_at", iso, compact_devicestatus,
                     ["t_ms", "bg", "iob", "cob", "pred_line", "pred30", "pred60", "predmin60", "ztmin60", "rate", "smb"]),
    "treatments": ("/api/v1/treatments.json", "created_at", iso, compact_treatments,
                   ["t_ms", "event", "carbs", "insulin", "rate", "duration"]),
}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--since", required=True, help="YYYY-MM-DD")
    ap.add_argument("--until", default=dt.date.today().isoformat(), help="YYYY-MM-DD (exclusive)")
    ap.add_argument("--out", default=os.path.expanduser("~/ns-data"))
    ap.add_argument("--kinds", default="entries,devicestatus,treatments")
    a = ap.parse_args()

    base, token = os.environ.get("NS_URL"), os.environ.get("NS_TOKEN", "")
    if not base:
        sys.exit("Set NS_URL (and NS_TOKEN) in the environment first.")
    start = dt.datetime.fromisoformat(a.since).replace(tzinfo=dt.timezone.utc)
    end = dt.datetime.fromisoformat(a.until).replace(tzinfo=dt.timezone.utc)
    os.makedirs(os.path.join(a.out, "weeks"), exist_ok=True)

    for kind in a.kinds.split(","):
        path, field, fmt, compact, header = KINDS[kind]
        week, n_total = start, 0
        while week < end:
            nxt = min(week + WEEK, end)
            part = os.path.join(a.out, "weeks", f"{kind}-{week:%Y%m%d}.csv.gz")
            if not os.path.exists(part):
                docs = get(base, path, {f"find[{field}][$gte]": fmt(week), f"find[{field}][$lt]": fmt(nxt), "count": 20000}, token)
                rows = list(compact(docs))
                with gzip.open(part + ".tmp", "wt", newline="") as f:
                    csv.writer(f).writerows(rows)
                os.replace(part + ".tmp", part)
                print(f"{kind} {week:%Y-%m-%d}: {len(docs)} docs -> {len(rows)} rows", flush=True)
            week = nxt
        out = os.path.join(a.out, f"{kind}.csv.gz")
        with gzip.open(out, "wt", newline="") as f:
            w = csv.writer(f)
            w.writerow(header)
            week = start
            while week < end:
                with gzip.open(os.path.join(a.out, "weeks", f"{kind}-{week:%Y%m%d}.csv.gz"), "rt") as p:
                    for row in csv.reader(p):
                        w.writerow(row)
                        n_total += 1
                week = min(week + WEEK, end)
        print(f"== {kind}: {n_total} rows -> {out}")


if __name__ == "__main__":
    main()
