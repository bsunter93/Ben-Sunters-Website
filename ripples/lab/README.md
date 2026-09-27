# Ripple Lab

Protocol registered at ledger 1279. The lab is where the discovery model gets tweaked, as often as needed, **without
looking at any real hypothesis**.

- **Fake worlds.** Real FEMA declaration dates and states, but the "treated" counties are drawn from that event's clean
  same-state donors, so no real effect exists. Effects of known size (1%, 2%, 3%) are planted in random
  (shock group × outcome × window) cells.
- **Full pipeline, end to end.**
  1. Screen on events before 2016, with calibrated p-values and BH q ≤ 0.10 across all cells.
  2. Confirm on 2016+ events, with a calibrated one-sided p ≤ 0.05 in the screen's direction.
- **Scorecard.**
  - False discoveries per run with nothing planted (target ≤ 0.05).
  - Recall of planted cells.
  - The share of cells with screen p ≤ 0.05 in a null world (calibration, should be about 0.05).
- **Real data** is used only for the registered positive controls, which are obvious by construction and are never
  findings:
  - hurricane → construction up
  - hurricane → leisure and hospitality down
- A design **graduates** when it keeps false discoveries ≤ 0.05 per run with useful recall. Only then is it frozen
  (code hash in the ledger) and run on the real question.

Files:
- `data.py` builds the county × quarter panel from BLS QCEW bulk files (all private supersectors) and OpenFEMA DR
  declarations, then caches both.
- `lab.py` holds the pipeline and the scorecard.
- `run_args.txt` holds the settings used by the GitHub workflow `ripples-lab.yml`. That workflow runs automatically
  when lab code changes on a `claude/` branch.

Run log: `ripples/lab/RESULTS.md`.

## Cultural lab (next; direction D-26)

This is the same idea on the product's real territory. It compares discovery methods D1–D4 head to head on how many
planted ripples each recovers, at a fixed false-discovery rate. It still never looks at a real cultural hypothesis.

- **Events:** a Wikidata catalog of films, TV series, songs and books from 2008–2024, with day-precise release or
  start dates. Prominence is the number of language Wikipedias covering each work. `ripples.att_cult_events` is
  built from Wikidata via the database, with no key.
- **Outcomes:**
  - US baby names by year, national and **by state**, from the SSA data via BigQuery.
  - English Wikipedia daily pageviews for a broad article panel via BigQuery (2015+).
  - Later: GDELT news coverage by place.
- **Fake events:** real release dates are shuffled onto fake "titles", so real timing structure is kept but no real
  effect exists. Planted ripples are then added to randomly chosen outcomes, with a shape (jump, rise-then-decay) and
  size drawn from a range.
- **Methods compared, each surfacing a ranked candidate list:**
  - **D1 fingerprints:** each event's response vector across all outcomes, relative to its ghosts. Candidates are the
    outcomes most out of line with the ghost distribution.
  - **D2 outcome-first:** outcome anomalies (breaks in trend) matched to events released just before.
  - **D3 exposure gradients:** state names only. Response by state is regressed on pre-event exposure (initially the
    prior popularity of the related theme by state; Google Trends by state if the owner gets API access).
  - **D4 ghost events:** the same test as D1, with explicit matched ghosts (same type, same year, similar prominence)
    as the null.
- **Scorecard:** for each method, recall of planted ripples in its top-k candidates, and false discoveries per run
  after the shared verification step (screen → held-out confirmation).
