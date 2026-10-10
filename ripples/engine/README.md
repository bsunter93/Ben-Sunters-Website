# Ripple's discovery engine

The engine looks for ripples in published research and counts how many are worth showing. It searches from the
outcome side. Each query pairs a kind of event (a big game, a channel reaching a market, a film release, a celebrity's
death, a blackout, an app launch, a clock change, a viral challenge) with a kind of outcome (births, divorce, crime,
sentencing, hospital admissions, crashes, test scores, names, productivity, spending, blood donation) and a design term
such as "natural experiment". A paper becomes a raw pair when it names a datable stone, a measured outcome and a design
that beats a baseline. A blind gate then removes the pairs a reader would have predicted. The rest are checked against
the paper's own pages, rated by a simulated panel and counted.

The one number that matters is the yield: surprising, defensible discoveries per 100 candidates. A candidate is a
(stone, outcome, claimed link) that enters verification. Defensible means verified on the paper's own page, with the
quote found, the stone dated before the outcome window and a comparison design. Surprising means a panel surprise index
of at least 3.5. The yield is reported per 100 candidates entering verification and per 100 raw pairs, so a gate cannot
make it look better than it is.

Python 3.10 or later, standard library only. Run every command from the repository root.

## The five stages

Each step is one of three kinds. A **script** runs on its own. A **judged step** is a fixed prompt applied in a fresh
context that reads only that prompt and its own input file and writes only its output file. A **review** is a person
reading rows and writing a small JSON file.

| Stage | Step | Kind | What it does |
|---|---|---|---|
| Generate | `generate/make_queries.py` | script | builds a query grid; run once per run, then the file is frozen |
| | `generate/harvest.py pubmed`, `openalex` | script | runs the frozen queries; resumable; stops a host on any error |
| | `generate/backfill_abstracts.py` | script | asks Crossref for abstracts the harvest lacks |
| | `generate/build_papers.py` | script | dedupes by DOI, prescreens by word patterns, writes extraction batches |
| | extraction (`generate/extract_prompt.txt`) | judged | reads title and abstract, writes raw pairs and one screen line per paper |
| | `generate/collect_pairs.py` | script | numbers the raw pairs and checks every quote against the harvest |
| | `generate/dedupe_sources.py --check` | script, then review | lists live chains and yield v1 items; a person writes the review files |
| | `generate/build_candidates.py` | script | turns reviewed raw pairs into candidates and stones |
| Gate | `gate/judged_steps.py predict-inputs` | script | batches the new stones, name and date only |
| | prediction (`gate/predict_v1.txt`) | judged | lists each stone's 25 most likely consequences, blind to every candidate |
| | `gate/judged_steps.py assemble-predictions` | script | checks and logs the predictions with the prompt's sha256 |
| | `gate/judged_steps.py match-inputs` | script | pairs each candidate's outcome with its stone's 25 predictions |
| | matching (`gate/match_v1.txt`) | judged | records the best matching rank, or not predicted |
| | `gate/judged_steps.py assemble-matches` | script | logs every rank; a candidate passes when it was not predicted |
| Verify | `verify/selection.py` | script | every gate-passer (a seeded 100 above that) and a seeded audit of 20 rejects |
| | `verify/fetch_text.py` | script | PubMed abstract, Crossref abstract, DOI landing page, then an open copy |
| | `verify/judge.py inputs` | script | packs each candidate with the text fetched for it |
| | verification judgment (`verify/judge_prompt.txt`) | judged | same paper, quote, claim, date order, design, grade, defensible |
| | `verify/judge.py assemble` | script | recomputes the defensible rule and writes each evidence line |
| Rate | `rate/build_controls.py`, `rate/build_items.py` | script | the packet: candidates, planted controls and yield v1 anchors, shuffled |
| | rating (`rate/rater_prompt.txt`, `rate/personas.json`) | judged | five simulated raters, each with a persona and a shuffle seed |
| | `rate/score.py` | script | validity, both yields, the gate audit, spread, yield by cell |
| Yield | `yield/log.py`, `yield/report.py` | script | one ledger line per run and the table against earlier yields |

`python3 ripples/engine/runner.py <step> <input>` prints the exact instructions for one judged run with the real paths
filled in, so every batch gets the same words. `python3 ripples/engine/runner.py list` lists the judged inputs that
have no output yet.

## Commands, start to finish

The work directory holds everything a run produces. It defaults to `ripples/engine/work/`, which git ignores. Use one
work directory per run.

```
export RIPPLE_ENGINE_WORK=ripples/engine/work/v5        # or pass --work DIR to any script

# Generate
python3 ripples/engine/generate/make_queries.py --out ripples/engine/generate/queries/<run>.json --plan <plan.md>
python3 ripples/engine/generate/harvest.py pubmed --queries ripples/engine/generate/queries/<run>.json
python3 ripples/engine/generate/harvest.py openalex --queries ripples/engine/generate/queries/<run>.json
python3 ripples/engine/generate/harvest.py summary
python3 ripples/engine/generate/build_papers.py w1
python3 ripples/engine/generate/backfill_abstracts.py
python3 ripples/engine/generate/build_papers.py w1b      # picks up the backfilled abstracts
python3 ripples/engine/runner.py extract data/extract_in/w1_b01.json        # one fresh context per batch
python3 ripples/engine/generate/collect_pairs.py
python3 ripples/engine/generate/dedupe_sources.py --check
#   review: write data/stone_map.json, data/stone_defs.json and data/review.json in the work directory
python3 ripples/engine/generate/build_candidates.py

# Gate
python3 ripples/engine/gate/judged_steps.py predict-inputs w1
python3 ripples/engine/runner.py predict blind/predict_in/w1_b01.json        # one fresh context per batch
python3 ripples/engine/gate/judged_steps.py assemble-predictions --cache <earlier predictions.jsonl>
python3 ripples/engine/gate/judged_steps.py match-inputs w1
python3 ripples/engine/runner.py match blind/match_in/w1_c01.json            # one fresh context per chunk
python3 ripples/engine/gate/judged_steps.py assemble-matches
python3 ripples/engine/gate/judged_steps.py status

# Verify
python3 ripples/engine/verify/selection.py
python3 ripples/engine/verify/fetch_text.py
python3 ripples/engine/verify/judge.py inputs w1
python3 ripples/engine/runner.py verify verify/judge_in/w1_j01.json          # one fresh context per file
python3 ripples/engine/verify/judge.py assemble

# Rate
python3 ripples/engine/rate/build_controls.py
python3 ripples/engine/rate/build_items.py
python3 ripples/engine/runner.py rate 1                                      # and 2, 3, 4, 5, each in its own fresh context
python3 ripples/engine/rate/score.py

# Yield
python3 ripples/engine/yield/log.py --run <run> --generator "outcome-side grid, blind gate" --plan <plan.md> \
    --queries ripples/engine/generate/queries/<run>.json
python3 ripples/engine/yield/report.py
python3 ripples/engine/yield/report.py --cells <run>
```

`--cache` is only needed when `data/stone_defs.json` gives a stone a `cache_id` from an earlier run's predictions.
The harvest, selection, fetch and logging scripts take `--dry-run`, and every script takes `--help`.

## Judged steps

Five steps need judgment: extraction, prediction, matching, verification judgment and rating. Each one is a fixed
prompt in this folder, applied in a fresh context that reads only the prompt and its own input file. The prediction
step sees stone names and dates and nothing else, and every prediction is made before any candidate text reaches it.
The matching step sees one candidate's outcome and claim and its stone's 25 predictions. Raters see the claim and its
evidence line, never the gate result, the cell or the generator. The assemble scripts check the outputs (order, counts,
ranks, fields) and log each one with the prompt's sha256 and the start and finish times.

The prompts are frozen with their runs. `gate/predict_v1.txt` has sha256
`2ffd436b34cde3d91ee2855f9eec2b5212036d72c3aabca9ca22bd1cf4af8010` and `gate/match_v1.txt` has
`0d5c44b396f8750b4079aa96631696bd265601de10c6064300d17cb30588f35e`, the same files the RSS v1 experiment and the
discovery v4 pilot used. A changed prompt is a new version with a new name.

Simulated raters are not people. Every panel number is labeled "simulated panel". Real raters replace them when they
exist.

## Rules

- The user agent is `ripple-research (bensunter.com)`, the one the studies pilot and the discovery v4 plan registered.
- At most one request a second per host. OpenAlex gets one every 2 seconds and NCBI three a second.
- A 5xx, a 429, a timeout or a connection error gets one retry after a wait (Retry-After up to 300 s, otherwise 60 s).
  A second failure, or any other 4xx, stops that host for the rest of the UTC day. Never more than one retry, never
  another agent.
- No Wikipedia, Wikimedia, Wikidata, Reddit, Merriam-Webster or Etymonline requests. `fetch.py` refuses them.
- No email address and no key goes in any request, with one exception. When `OPENALEX_API_KEY` is set, `fetch.py` adds
  it as the `api_key` parameter to requests whose host is exactly `api.openalex.org`, at the moment of sending. It never
  appears in a logged URL, a cache file or an error line, and it is stripped from any redirect target. Without a key,
  OpenAlex allows 1,000 credits a day and a search costs 10; the harvester stops before it would run out.
- Outcomes of suicide, self-harm or overdose and party-vote outcomes are excluded at extraction (owner rulings of
  10/05/2026 and 10/08/2026), as are topic matches, where the outcome is the stone's own subject, aim or product.
- Every run registers its plan and bars before the first request. The query file is frozen before the first request,
  and a work directory refuses a second query file.
- Nothing in the work directory is committed. It holds abstracts, publisher pages and full judged outputs, which are
  other people's words. Records go to `ripples/docs/` as plain-language summaries with short quotes only.

## The GitHub workflow

`.github/workflows/ripples-engine.yml` runs the script-only harvest: the frozen queries on PubMed, then on OpenAlex,
then the metadata summary. It starts only by hand (Actions, "Ripples engine (harvest)", Run workflow), with the query
file and an optional cap on searches. The weekly schedule is written in and commented out. It stays off until the
discovery v4 pilot meets its bars. `OPENALEX_API_KEY` is a repository secret passed only to the OpenAlex step. The run
uploads an artifact with the metadata (ids, DOIs, titles, years, venues, citation counts, abstract lengths) and the
request logs. Abstracts stay on the runner. The judged steps never run in the workflow.

## Ranking experiment (`rank/`)

`rank/rss.py` scores candidates by the Relevant Surprise Score from the owner's spec of 10/08/2026:
RSS = S^alpha x R^beta, where S averages the surprise signals (S_A, the rank among 25 blind predictions; S_B,
relationship-type rarity; S_D, prior discoverability) and R is the geometric mean of catalyst relevance C and
consequence significance G. Evidence eligibility, a relevance floor and duplicates order the list without changing the
score. `rank/eval.py` compares rankers against rater labels on held-out catalysts. `config_v0.json` is the starting
point the spec set. `config_v1_exploratory.json` was chosen after seeing the v0 results and must be confirmed on a new
batch (`eval.py --exploratory --config ripples/engine/rank/config_v1_exploratory.json`). `relevance_v1.txt` and
`types_v1.txt` are the rubrics behind C, G and the types. The v1 result is in `ripples/docs/rss_v1.md`: as specified,
RSS did not beat the evidence-first ranking. It is not part of the pipeline.

```
python3 ripples/engine/rank/rss.py --data <experiment dir>
python3 ripples/engine/rank/eval.py --data <experiment dir>
```

## Records

| Record | What it holds |
|---|---|
| `ripples/docs/studies_plan_v1.md`, `studies_plan_v1_addendum.md` | the studies pilot's registered plan (sha256 `00bc8253...4379`) and its supplemental round |
| `ripples/docs/studies_v1.md` | the studies pilot's results and what shipped |
| `ripples/docs/yield_plan_v1.md`, `yield_v1.md`, `results/yield_v1/` | the first yield measurement: plan, results, items and ratings |
| `ripples/docs/rss_v1.md` | the Relevant Surprise Score experiment, v1 |
| `ripples/docs/discovery_plan_v4.md` | the discovery v4 pilot's plan: this engine's first run |
| `generate/queries/discovery_v4.json` | the v4 pilot's frozen queries, 86 cells (sha256 `b377d9e8...d37f`) |
| `generate/queries/studies_v1.json` | the studies pilot's 64 query families in the same cell format |
| `yield/baselines.json` | the yields measured before this package |
