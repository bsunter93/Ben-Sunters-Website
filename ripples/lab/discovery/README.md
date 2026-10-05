# Discovery, corpus 1: Wikipedia as a cited-cause record

The scripts behind `docs/discovery_corpus1_v1.md` (Oct 4, 2026). They read and write JSON in the working directory, so
run them from `ripples/docs/results` with this folder on the path:

```
cd ripples/docs/results
PYTHONPATH=../../lab/discovery python3 ../../lab/discovery/legacy2.py stones_all.json legacy2_all.json   # forward reading
PYTHONPATH=../../lab/discovery python3 ../../lab/discovery/hop3.py recall      # reverse hop on the catalog's stones
PYTHONPATH=../../lab/discovery python3 ../../lab/discovery/hop3.py decoys      # the 50 decoy stones
PYTHONPATH=../../lab/discovery python3 ../../lab/discovery/order.py            # date the marks, apply the ordering rule
PYTHONPATH=../../lab/discovery python3 ../../lab/discovery/heldout.py          # 20 held-out stones, reverse
PYTHONPATH=../../lab/discovery python3 ../../lab/discovery/heldout_fwd.py      # 20 held-out stones, forward
PYTHONPATH=../../lab/discovery python3 ../../lab/discovery/namesake.py         # corpus 2: namesake statutes
```

Every request goes through `legacy.get`: the honest user agent, one request a second, and an exit on any 4xx/5xx.
`resolve.py` built `stones_all.json` from the chains (a stone's article by search, with hand overrides for the ones
search gets wrong) and expects the scratch file it was written against; the result is committed, so it need not run
again. `fedreg.py` is the Federal Register probe (a 404 on an old document's body stopped that host for the day; the
probe's counts are in `fedreg_probe.json`). The builder's two blind screens are `discovery_corpus1_screen.json`.

`surprise.py` is the surprise score of `docs/surprise_plan_v1.md` (result: `docs/surprise_v1.md`). It runs from the
repository root, caches raw API responses in a directory outside the repository, and writes
`docs/results/surprise_v1.json`. A 403, 429, 5xx or timeout writes a dated line to `surprise_blocked_dates.txt` and the
scorer will not contact Wikimedia again that UTC day; `--offline` rescores from the cache, `--no-cocite` is the Oct 5
deviation (u4 dropped).
