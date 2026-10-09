# Discovery yield v1: plan (registered before any rating)

Registered Oct 8, 2026, 10:05 PM PT, before any rater saw an item. The registered file's sha256 is
`5ee3b4859faffa9df223bb99e56f4dce8a81a42ced676359bffeab79f4491bbc`. This copy points its one local path at the
repository and changes one word, so its own hash differs. Results: `docs/yield_v1.md`.

## The one objective (owner, Oct 8)
Surprising, defensible discoveries per 100 candidates. A **candidate** is a (stone, outcome, claimed link) that enters
verification. **Defensible:** checked at its source; a record or a peer-reviewed study names every edge; dates in order.
For a "strong" discovery it also passes the causal gate below. A famous claim that a source refutes counts (busted).
**Surprising:** panel surprise index at least 3.5, the v1 panel protocol unchanged (`docs/panel_plan_v1.md`). **Yield**
= candidates that are both, per 100, reported by generator and by query family.

## Instruments
- Surprise: five simulated raters, the same personas, scales and validity checks as panel v1. Items here: 56 study
  links, 15 busted claims, 20 anchors re-used from panel v1 (to check drift: mean absolute change in surprise index
  under 0.5), the same 10 planted obvious and 10 planted fabricated pairs. Labeled "simulated panel" everywhere.
  Real people's labels (Reddit, the "New to you?" taps) replace it when they exist.
- Defensible: the studies pilot's verification (`docs/studies_v1.md`), one verdict per candidate.

## Baseline
Old engine (legislative text and Wikipedia), panel v1: 12 good of 102 = 12 per 100 (believable used as the
defensible proxy then).

## Bars for this measurement
- Validity: planted obvious mean surprise index at most 2.5; planted fabricated mean believable at most 2.5.
- Studies generator yield, forecast now: 35 per 100 (p 0.5 that it is at least 30).
- Busted claims yield, forecast now: 50 per 100.

## Levers, in the order they will be built (each measured in yield per 100)
1. Generator mix: published studies, busted famous claims (Skeptics, fact-checks), records that name a cultural cause.
   Stop outcome-first scans with no record path (breeds, degrees, words without a dictionary record): about 0 to 2 per
   100 on Oct 8.
2. Ranking before verification (owner's item 1): generate broadly, score each candidate on novelty, evidence quality,
   causal plausibility and relevance (a fixed rubric plus features: domain distance, stone fame, outcome reach, a
   same-domain disaster-to-law flag, whether the stone's own page already states the link). Calibrate on the labeled
   sets (panel v1's 169, this panel's 111, the owner's screens). Adopt only if held-out AUC is at least .70 for surprise
   and .80 for defensible; surprise score v1 managed .60.
3. Multi-hop chains with documented edges (owner's item 2), e.g. a show, then a hearing, then a law. Every edge needs
   a record naming both ends; inferred edges are labeled and never count as defensible. Multi-hop v1 failed because hop
   1 rested on an attention rise (3 of 124 wrong pairs passed). Start with congressional hearings (govinfo, the
   DATA_GOV_KEY secret) and Hansard.
4. Causal gate before "strong" (owner's item 3): background trend (did the rise start before the stone; the CSI check
   on Oct 8 failed this), placebo dates, comparison events (similar stones that moved nothing), named alternative
   explanations checked. A candidate that fails stays a lead or becomes busted.
5. Allocation: each batch of 100 moves budget toward the query families with the highest observed yield, keeping 20%
   for exploration, and expands around every hit (same mechanism, other stones).

First new batch after this measurement: 100 candidates from the new mix, target at least 30 good per 100.
