# ns-bench — offline research on Nightscout history

Research only. Nothing here is part of the app, touches dosing, or ships in a build.

Question being tested: can a learned model forecast glucose, or classify
"low within 60 min", better than oref's own `predBGs` on real history?

## Getting the data

1. In Nightscout Admin Tools, create a subject with the **readable** role and copy its token.
2. Add `NS_URL` and `NS_TOKEN` to the cloud environment settings (never commit them).
3. `python3 research/ns-bench/fetch_ns.py --since 2021-01-01`

Data is written to `~/ns-data`, outside the repo. It is personal health data:
never commit it, never upload it anywhere.
