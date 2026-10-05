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

## Multi-hop ripples v1 (Oct 4 to 5, 2026)

`multihop.py`, `multihop_compose.py` and `multihop_gov.py` compose stone → intermediate → lasting mark under the plan
registered in `docs/multihop_plan_v1.md`; the result is `docs/multihop_v1.md`. Run from the repository root:

```
python3 ripples/lab/discovery/multihop.py stage1 all     # candidates, the specificity filter, hop 1 (writes multihop_stage1_v1.json)
python3 ripples/lab/discovery/multihop.py stage2 all     # hop 2: Hansard bill debates and the Wikipedia reverse hop
python3 ripples/lab/discovery/multihop.py resolve        # a later day: bill -> Act for hits that waited on a stopped resolver
python3 ripples/lab/discovery/multihop.py compose        # automated chains, the D1 wrong-stone decoys
python3 ripples/lab/discovery/multihop.py build          # with docs/results/multihop_hand_v1.json: multihop_v1.json
```

The Congressional Record hop runs only as `.github/workflows/ripples-multihop-gov.yml` (the GovInfo key is an Actions
secret). One limiter keeps request starts a second apart across every host; responses are cached outside the repository
(`MULTIHOP_CACHE`), and a 403, 429 or 5xx stops that host for the UTC day (`MULTIHOP_STOPS`). `stage2` picks up where it
stopped, including survivors whose Hansard search waited for a later day.
