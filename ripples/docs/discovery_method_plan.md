# Ripple Map discovery layer: audit and build plan (response to the owner's discovery specs, 2026-09-28)

This file answers the two discovery specs ("Statistical Discovery Engine Expansion" and "Advanced Statistical
Discovery Architecture"). It is grounded in what the cultural lab has already measured on real data (`ripples/lab/`),
not only in theory. Governing direction: `discovery_engine.md` (D-26).

**Principle kept:** the top of the system is curious, the bottom is skeptical. Discovery scores decide what to test.
Evidence tiers decide what may be claimed. Story decides what to show. None of these feeds back into another.

## What the lab has already shown (evidence that shapes this plan)

1. **Verification works.** E9 phase 1 recovered all 4 known ripples, and 1% of 200 fake events passed (ledger 1282).
2. **Blind single-event search fails at scale.** Real run 1: 998 Wikipedia articles × 150 fake events is about
   150,000 pairs per world. Planted lifts up to +50% were almost never found by any method. The false tail is made of
   real multi-day attention bursts (deaths, news) that happen to fall in an event's window, reaching z of 17–38.
   Better single-pair statistics (medians, shape max-statistics) do not beat that tail.
3. **Two ideas beat it** (synthetic data with seasonality, shared swings and bursts; real-data run 2 in progress):
   - **Attention coupling.** A real ripple rises and falls with the event's own attention curve: Kate Bush views
     tracked Stranger Things. Coupling on day-to-day changes rewards responses that start on the event's days, which
     coincident bursts rarely do.
   - **Family pooling.** A coincident burst hits one event's date, not five independent release dates. Pooling each
     outcome's top-k coupled responses within an event family cuts the false tail from about 20 to about 8.
   - Combined: 83% recall at 1 false family per world (72% at 0.1) with family members at only +50%. Single-pair
     methods reach 0–17%.

## Status after lab runs 1–4 (real data, 2026-09-28)

**Discovery v1 is frozen** (ledger 1283; `ripples/lab/RESULTS.md`, run 4). For each event with an
attention curve and each outcome series:
1. Remove the all-outcome daily median.
2. Load the outcome's day-to-day changes over days −14..+90 on the event curve's changes (onset-aligned coupling).
3. Standardize by that outcome's own placebo dates, as a MAD z and as a rank z.
4. Average over the members of a narrow, pre-defined event family (clip at 4).
5. Set the cutoff from fake-event worlds.
6. Promote a (family, outcome) candidate only when both z versions pass.

Measured power: about 67% of 5-event families at +30% per member (1 false family per world), about 42% at +20%.
Single events are found only at large lifts. The next gains come from narrow families (owner input), exposure
gradients, and rival events on the same dates.

## A. Audit of the proposed techniques

| technique | verdict | why |
|---|---|---|
| Rich response profile (level, slope, CAR, peak, persistence, lag) | HIGH | Needed to express delayed and gradual ripples. Built as the shape library and the shape max-statistic. |
| Empirical placebo distributions | HIGH | Already the default null everywhere (per-article placebo dates; phase 1 used 500). |
| Max-statistic over pre-registered shape/lag families | HIGH | Built. Alone it does not beat coincident bursts; it is the right way to search shapes without cherry-picking. |
| Outcome-first anomaly discovery | HIGH (as candidate generation) | Current version is weak (lab: near 0). Rebuild with robust change points (next list). |
| Exposure gradients | HIGH | The strongest attribution evidence. Needs place-level outcomes (state baby names, loaded) and exposure (Google Trends by state/DMA, applied). |
| Event-family replication / meta-analysis | HIGH | The largest measured gain. Built as family pooling. |
| Rival-event controls | HIGH | Same idea as ghosts. Built into the placebo design; extend to "same-type events on the same dates". |
| Common-factor residualization | HIGH | Market (all-article median) removal built. Add 3–5 principal-component factors next. |
| Seasonal adjustment | MEDIUM | 52-week differencing helps seasonal articles but doubles noise elsewhere. Use per outcome where the pre-period shows seasonality. |
| Synthetic control | MEDIUM | Used in phase 1 names. Expensive at screening scale; keep for promoted candidates. |
| Change-point detection (PELT, CUSUM) | MEDIUM | Good for outcome-first anomalies. Dangerous if used to pick the event date (the spec's own warning). |
| Multivariate fingerprints | MEDIUM | Useful once many outcome types exist; with one outcome type (pageviews) family pooling does the same job. |
| Network exposure, spillover rings | MEDIUM | Right for disasters; cultural events rarely have a usable network yet. Wikipedia clickstream (links people actually follow) is a candidate network. |
| Dose-response | MEDIUM | Event attention size is a natural dose. Coupling already uses the dose's time shape. |
| Distributional, composition, substitution effects | MEDIUM (phase 2) | Real ripple types, but they need outcomes with components (industry shares, name shares) we mostly do not have yet. |
| Hierarchical shrinkage | MEDIUM | For ranking only; family pooling already stabilizes ranks. |
| BSTS, state-space | LOW now | Adds a model per series at screening scale for little gain over robust placebo nulls. Candidate for an independent estimator on promoted candidates. |
| Dynamic time warping | DANGEROUS unless tightly bounded | Free alignment lets any burst match any curve. Only allow warps of ±2–3 days, benchmarked on placebos. |
| Causal forests, free subgroup search, large causal ML | DANGEROUS now | Flexibility grows faster than we can measure its false-discovery cost. |
| LLM-written mechanisms | DANGEROUS as evidence; MEDIUM as prediction generator | Only as the spec proposes: mechanism → frozen testable predictions → tests. |

## B. Techniques missing from the specs that solve a real Ripple Map problem

1. **Attention coupling (onset-aligned).** Uses the event's own time series as the template the outcome must match.
   This is the single most useful addition found so far, because it attacks coincident bursts.
2. **Top-k family pooling.** A pre-registered k strongest members of an event family, calibrated against the same
   statistic on non-planted families. Plain mean pooling dilutes, because only some family members carry a ripple.
3. **Clickstream relatedness prior.** Wikimedia publishes monthly counts of reader clicks from article A to article B.
   It measures where attention actually flows. As a candidate-generation prior, and as a "how obvious is this link"
   measure for surprise, it cuts the search space without human guessing.
4. **Knockoff-style or two-stage (split-sample) promotion.** Screen on one half of the event families, confirm on the
   other. Held-out confirmation, made structural.
5. **e-values and alpha-investing for the ongoing screen.** New events keep arriving. Online false-discovery control
   keeps the guarantee valid while the search never stops.

## C. Minimum viable discovery architecture (what is being built)

```
catalog event ──► its own attention curve (enwiki views around release)
                     │
outcome panel ──► market-adjusted series ──► onset-aligned coupling z per (event, outcome)
                     │                         (article's own placebo dates as the null)
                     ▼
            family pooling: top-k coupled z per (event family, outcome)
                     │
                     ▼  cutoff set by fake-event worlds (recall at a fixed false-discovery load)
            ranked candidate families ──► surprise screen (clickstream distance, direct-echo exclusion)
                     │
                     ▼
            freeze in ledger ──► existing evidence engine (placebos, rivals, FDR, held-out families)
```

Single-event candidates are allowed only for very large responses (lab threshold to be set by run 2).

## D. Benchmark (the cultural lab; `ripples/lab/cultural_lab.py`)

- **Planted ripple library:** step, pulse, delayed, gradual, slope, decay, and event-coupled. Also family ripples: k
  events of one type → one outcome.
- **Adversarial by construction:** real Wikipedia series with their own seasonality, bursts, pandemic swings and
  breaks. Fake events keep real attention curves but move to random dates.
- **Metric:** recall at 1 and 0.1 false discoveries per world, overall and by shape. The fake-event null sets the
  cutoff, so every method is judged at the same false-discovery load.
- **Still to add:**
  - Exposure-dependent plants, when place-level outcomes exist.
  - Outcome-first recovery.
  - Diversity of the discovered set (event domain × outcome domain).
- **Rule:** a method is adopted only if it raises recall at the fixed false-discovery load on real-data worlds, then
  passes phase-1-style positive controls.

## E. High-value combinations

1. **Coupling + family pooling:** measured, strongest.
2. **Outcome-first anomaly + coupling:** an anomaly narrows the dates; coupling checks which nearby event's curve it
   follows. Addresses "which of the three things that happened that week?"
3. **Coupling + exposure gradient:** time-shape match plus more response where exposure was higher. Nearly
   impossible to fake by coincidence.
4. **Clickstream prior + surprise:** use clicks to generate candidates and to measure obviousness. Promote pairs with
   a real response but little direct click traffic.

## F. The surprise problem

Surprise is scored separately from evidence and never feeds back into it.

- **Measured obviousness:**
  - Direct clickstream traffic from the event article to the outcome article.
  - Whether the outcome is linked from the event article.
  - Co-mention rate in news (NYT archive tags, GDELT).
  - High values mean obvious. Kate Bush has a direct link from the Stranger Things article, so it is a known echo.
- **Prior expectation, asked before evidence:** a small human panel (the owner first) rates "would you have tested
  this?" on the frozen candidate list, before any confirmation result is shown. That gives the "low prior, high
  posterior" measure the spec proposes.
- **Legibility:** a mechanism sentence that yields a testable prediction. No prediction, no story.

## G. Ripple chains (A → B → C)

Feasible only with strict limits:
- Each edge must be a separately frozen, separately confirmed ripple.
- The onset of C must follow the onset of B, which must follow A, on pre-set lag windows.
- At most one intermediate node, chosen from a pre-listed set of measured intermediates (search, pageviews, news).
- Language: "consistent with a possible pathway", never "mediated".

Not before single edges work.

## H. Adversarial list: ways to fake a ripple, and the defense

| failure mode | defense |
|---|---|
| Search multiplicity | Fake-event worlds set every cutoff; ledger counts every family searched |
| Temporal coincidence (bursts) | Onset-aligned coupling; family pooling; rival events on the same dates |
| Common shocks (pandemic, elections) | Market adjustment; factor removal; same-date rival events cancel year-wide moods |
| Semantic leakage (outcome is the event itself) | Exclude the event's article, cast and links; clickstream-obviousness flag |
| Post-treatment exposure | Exposure measured strictly before release |
| Measurement changes (Wikipedia bot filters, app launches) | User-agent-only views; placebo dates span the change; flag series with breaks |
| Survivor or outcome selection | The outcome panel is fixed (Vital Articles) before any event is looked at |
| Subgroup fishing | Subgroups only from a frozen list; subgroup findings are candidates, not results |
| Seasonal artifacts | Per-article placebo dates across all seasons; seasonal differencing where needed |
| Structural breaks | Robust medians; placebo dates on both sides of breaks |
| Data revisions | Snapshot data versions in the ledger with each freeze |
| LLM hindsight bias | LLMs may only write predictions before results; never label surprise after the fact |

## I. What the owner can do to speed this up

1. **Google Trends access** (applied): unlocks exposure gradients, the strongest attribution evidence.
2. **Run Actions → Ripples NYT archive** once: news co-mention for surprise scoring and outcome-first news spikes.
3. **About 30 remembered events:** the first real family definitions (e.g., "sports films", "true-crime podcasts").
   Narrow families are much more powerful than broad types.
4. **Be the first "would you have tested this?" rater** on frozen candidate lists.
