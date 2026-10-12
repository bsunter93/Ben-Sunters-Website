# Discovery v5: the families the owner rated highest, scored by a person

Registered Oct 11, 2026 (UTC), before any harvest request. Do not edit the bars after the first request is sent. The
frozen queries are `ripples/engine/generate/queries/discovery_v5.json`, written by
`ripples/engine/generate/make_queries_v5.py` with this file's sha256.

## Objective
Surprising, defensible discoveries per 100 candidates, with surprising decided by a person. A candidate is a (stone,
outcome, claimed link) that enters verification. Report per 100 entering verification and per 100 raw pairs.

## Why this design
- The owner rated 50 findings blind on Oct 11 (`docs/engine_enrich_v1.md`). His surprise and belief were unrelated
  (Spearman -0.03); the simulated panel matched his surprise at .35 and his belief at .02. So the panel is a
  pre-filter only, and the yield comes from his ratings: 36.4 good per 100 real findings, 43.5 per 100 gate passers.
- His highest "would tell someone" findings were mass-attention events against everyday behavior: Uber and drunk-driving
  deaths, Tinder and campus assaults, World Cup and work hours, mass shootings and turnout, mass shootings and alcohol
  sales, Chile's clock change and crashes. "Would tell someone" tracked his surprise (.51), not his belief (.13).
- In v4, celebrity moments (I4) and viral moments (I8) produced no candidate, and courts (O4), schooling (O7) and names
  (O8) produced none that was good.

## Generator
The v4 outcome-side grid, cut to the families that produced finds:
- Event classes: I1 sports results and big games, I2 media arrival and rollout, I3 entertainment releases, I5 one-off
  shocks (mass shootings, attacks, disasters, blackouts), I6 tech and product launches (ride-sharing, dating apps,
  smartphones, platforms), I7 clock and calendar rule changes. I4 and I8 are dropped.
- Outcome domains: O1 births, O2 marriage and family, O3 crime and violence, O5 hospital use and mortality, O6 traffic
  accidents, O9 work and productivity, O10 spending (with drinking, gambling and betting added to its words), O11 civic
  acts (with voter turnout and registration added). O4, O7 and O8 are dropped.
- 48 cells. One OpenAlex query and one PubMed query per cell, each pairing the cell's event words and outcome words with
  a design group ("natural experiment" OR "difference-in-differences" OR "regression discontinuity" OR "event study").
  OpenAlex runs keyless (48 searches of the 1,000 daily credits) after 00:00 UTC Oct 12; PubMed runs at once.
- Papers v4 already sent to extraction (442) are marked sent, so v5 reads only new papers. The prescreen's outcome
  words gain drinking, gambling, betting, turnout and voting, matching the query words.
- Extraction, exclusions (suicide, self-harm and overdose outcomes; party-vote outcomes; topic matches) and the review
  of stones are v4's, unchanged.

## Gate, verification, panel
v4's, unchanged: the blind predictor (`gate/predict_v1.txt`) and matcher (`gate/match_v1.txt`); verification of every
gate passer (a seeded 100 above that, `random.seed(5100)`) and a seeded audit of 20 rejects (`random.seed(5200)`); the
five simulated raters as a pre-filter.

## The person's batch (primary)
`rate/human/pick.py --n 30 --seed 51` over the defensible candidates (gate passers and audited rejects), in thirds by
panel surprise, a why line from the paper's abstract on a seeded half where one exists (no model-written reason on a
real item), and three planted obvious and three planted fabricated controls. The owner rates it blind on the rating
page. Good = surprise 4 or more on the claim alone and belief 4 or more after the evidence.

## Bars
| Bar | Measure | Threshold |
|---|---|---|
| Primary | good per 100 real findings in the owner's batch | at least 40 (his Oct 11 batch: 36.4) |
| Defensible | defensible per 100 entering verification | at least 70 (v4: 75) |
| Spread | outcome domains among good finds | at least 4 |
| Law | law or policy outcomes among good finds | at most 20% |
| Controls | his mean surprise on planted obvious items; his mean belief on planted fabricated items | report only (3 each) |

Prediction, logged before any request: primary 40 (p 0.5); defensible 75; the panel's good per 100 below 30, because
its surprise runs against belief.

## Limits
One rater, 30 items: a 95% interval on 40 per 100 runs from about 23 to 59. Abstract-level verification, as in v4. The
predictor, matcher, verification judge and panel share one model family.
