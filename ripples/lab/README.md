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
