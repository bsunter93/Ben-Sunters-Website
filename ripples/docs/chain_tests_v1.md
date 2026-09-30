# Chain tests v1: from an event to a behaviour, in time order (registered 2026-09-30, before any chain data is fetched)

**Why:** the owner's ordering rule (ledger 1497). A ripple is an approximate cause-and-effect chain: each step is an
outcome measured in its own data, and each step starts after the one before it. Reader paths (Clickstream) showed
related topics, not outcomes (ledger 1496). Chain tests measure the behaviour step directly.

**These first chains are deliberately obvious.** They test whether the behaviour layer can be measured at all (does an
event move what people actually borrow, and only after the event?). Surprising multi-step chains come after this
layer is shown to work.

## Behaviour data

- Seattle Public Library checkouts (data.seattle.gov dataset `tmmm-ytt6`), monthly, 2005 on, all formats, counted for
  items whose subject headings contain the given heading. Fetched by the existing server-side job (`att_sea_tick`),
  one heading per minute, honest User-Agent, stop on refusal. Aggregates only.
- One city. A miss says little about the country; a hit is one city's behaviour.

## Chains (event month, heading), fixed now

| Event | Month (m0) | Behaviour: checkouts with heading |
|---|---|---|
| The Queen's Gambit (Netflix) | 2020-10 | Chess |
| Chernobyl (HBO) | 2019-05 | Chernobyl |
| Tiger King (Netflix) | 2020-03 | Tigers |
| GameStop short squeeze | 2021-01 | Stocks |
| Wordle goes viral | 2022-01 | Word games |
| Tokyo Olympics (skateboarding debut) | 2021-07 | Skateboarding |
| Tokyo Olympics (sport climbing debut) | 2021-07 | Rock climbing |
| Tidying Up with Marie Kondo (Netflix) | 2019-01 | Orderliness |
| The Last Dance (ESPN/Netflix) | 2020-04 | Basketball |
| Cobra Kai on Netflix | 2020-08 | Karate |
| Oppenheimer (film) | 2023-07 | Atomic bomb |
| Barbie (film) | 2023-07 | Barbie dolls |
| Dune (film) | 2021-10 | Dune (Imaginary place) |

## Test (per chain)

- **Series:** x = log(1 + checkouts) minus the median log(1 + checkouts) of the 1,376-heading Seattle panel that month
  (removes library-wide swings, including the 2020 closures), then minus the median of the same calendar month in the
  previous three years (removes seasons).
- **Effect:** mean x over m0 .. m0+2 minus mean x over m0-6 .. m0-1.
- **Null:** the same effect at every admissible month of the same heading (2008 on, at least 7 months from m0, with 6
  months of history and 3 after; about 200 months). p = (1 + placebo effects ≥ observed) / (1 + placebos).
  (Amended before any data was fetched: fewer than 200 admissible months exist, so all are used instead of a draw.)
- **Time order (owner rule):** the onset month is the first month from m0-3 to m0+6 where x exceeds the pre-period
  mean by 2 MAD (pre-period m0-12 .. m0-1). The chain passes the order rule only if the onset is m0 or later. An onset
  before m0 means the rise preceded the event: the chain fails whatever its p.
- **Pass (chain):** p ≤ 0.05 and time order holds.
- **Overall:** number of passing chains against the 0.65 expected by chance (13 × 0.05); pooled z (sum of per-chain
  placebo z / √13) against the same random-month null.

## Known confounds

- 2020 library closures (March 2020 to 2021) change physical borrowing; the panel median removes the common part but
  Tiger King (2020-03) and The Last Dance (2020-04) fall in the closure itself and are flagged.
- Oppenheimer and Barbie share a month (the "Barbenheimer" weekend).

## Output

- `chain_tests_v1` in `ripples.att_q3_results`, saved as `ripples/docs/results/chain_tests_v1.json`.
