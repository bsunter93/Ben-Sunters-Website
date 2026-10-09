# Discovery yield v1: results (Oct 8, 2026, simulated panel)

Plan: `docs/yield_plan_v1.md`, registered before any rating (sha256 of the registered file
`5ee3b4859faffa9df223bb99e56f4dce8a81a42ced676359bffeab79f4491bbc`). Data: `docs/results/yield_v1/`.

## Validity

- The first run's control items were mislabeled by the item builder (panel v1's key.json indices do not match its
  items.json), so those checks are void.
- Corrected controls, rated separately by the same five raters: planted obvious mean surprise index 1.02 (bar 2.5),
  planted fabricated mean believable 1.14 (bar 2.5). Both pass, matching panel v1 (1.04, 1.14).
- Ten study items rated twice: mean absolute change in surprise index 0.29. Twenty v1 items re-rated: drift 0.22 (bar 0.5).
- Agreement (mean pairwise Spearman): surprise .76, believable .80.

## Yield (surprising and defensible, per 100 candidates)

| Generator | n | Surprising | Defensible | Good | Per 100 | Forecast |
|---|---|---|---|---|---|---|
| Published studies | 56 | 20 | 53 | 18 | 32 | 35 |
| Busted famous claims | 15 | 2 | 14 | 2 | 13 | 50 |
| Old engine (20 re-rated v1 items) | 20 | 2 | 20 | 1 | 5 | (v1 full set: 12) |

Simulated raters, not people.

Surprise is the binding constraint. 53 of the 56 study links were defensible and 20 were surprising. The surprising
ones cross channels (a home team in the Super Bowl and flu deaths among older people, football upsets and juvenile
sentences, violent-movie weekends and fewer assaults). The unsurprising ones stay in the stone's own channel (a
celebrity's illness and screening for it, a film and tourism to where it was shot). The discovery v4 plan
(`docs/discovery_plan_v4.md`) builds on that.

## Method

- Raters: the five simulated personas of panel v1 (`ripples/engine/rate/personas.json`), each in a fresh context with
  its own shuffle seed, no lookups. Scales 1 to 5: predicted, surprise, interest, believable.
- Surprise index per item: the mean over raters of (surprise + 6 - predicted) / 2. Surprising: at least 3.5.
- Defensible: the studies pilot's verification verdict (`docs/studies_v1.md`).

## Files in `docs/results/yield_v1/`

| File | What it holds |
|---|---|
| `items.json` | the 111 rated items: stone, stone date, claim, evidence line |
| `key.json` | each item's group and id (studies, busted, anchor_v1, planted_obvious, planted_fabricated); raters never saw it. The 20 planted labels here are the void first-run controls |
| `ratings_r1.json` to `ratings_r5.json` | each rater's four scores per item |
| `scores.json` | the mean scores and the surprise index per item |
| `items_ctl.json`, `key_ctl.json`, `ratings_ctl_r1.json` to `ratings_ctl_r5.json` | the corrected control round: 10 planted obvious, 10 planted fabricated, 10 study items rated twice |
