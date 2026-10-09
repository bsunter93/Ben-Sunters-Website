# Discovery v4 pilot: cross-channel generator + blind predictability gate

Registered Oct 9, 2026, before any harvest request. Do not edit the bars after the first request is sent.

Record copy. The registered file's sha256 is `b90dbbd669168c1898862e9c081fd0d9ed792fb646ae3aeb61e185e050cced69`. This
copy replaces local file paths with repository paths, words the notes on how the judged steps run in the engine's
terms, and drops two notes about the run's local files and git use, so its own hash differs. The objective, design,
pipeline, bars and rules are unchanged. The frozen queries are `ripples/engine/generate/queries/discovery_v4.json`
(sha256 `b377d9e8e7dc6c0d2a869fc97d0ca6117d6bc949ca280489f684e8d5eb9fd37f`), and the code is `ripples/engine/`.
Status on 10/09/2026: running. The PubMed leg is harvested; the OpenAlex leg waits for its daily budget.

## Objective (owner, Oct 9)
Surprising, defensible discoveries per 100 candidates. A candidate is a (stone, outcome, claimed link) that enters
verification. Report two denominators so the gate cannot fake the number: per 100 entering verification, and per 100
raw harvested pairs.

## Why this design (evidence on record)
- Yield v1 (`docs/yield_v1.md`): studies 32 per 100; 53 of 56 defensible but only 20 of 56 surprising.
  Surprise is the binding constraint.
- Retro on RSS v1 data (`docs/rss_v1.md`; post hoc, and the predictor and the raters come from the same system):
  among 220 rated candidates, those the blind predictor did NOT list among the stone's 25 predicted consequences were
  accepted at 10 of 64 (16 per 100); predicted ones at 4 of 156 (3 per 100). Studies only: unpredicted 8 of 12 accepted, predicted 2 of 44. Rank 6 to 25 matches: 0 of 48.
- Studies v1 query families (`docs/studies_plan_v1.md`) were stone-first and mostly topic-matched (celebrity illness to
  screening, film to tourism, celebrity suicide to suicides). Those are the stone's own channel and rate unsurprising.
  The surprising ones cross channels: Super Bowl team to flu deaths, football upsets to juvenile sentences, violent
  movie weekends to fewer assaults, Salah to fewer hate crimes, TV arrival to fertility, Oklahoma City bombing to births.

## Change A: generator (outcome side, channel crossing)
Search the outcome domain's literature for quasi-experimental studies whose exposure is a dated cultural event.

Event classes:
- I1 sports results and big games (Super Bowl, World Cup, upsets, home-team wins and losses, star signings)
- I2 media arrival and rollout (TV, radio, cable, satellite, broadband, mobile coverage, a channel entering a market)
- I3 entertainment releases (blockbuster films, video games, series, albums, books)
- I4 celebrity moments (deaths, scandals, weddings, births, coming out)
- I5 one-off shocks (blackouts, outages, attacks, disasters, eclipses), outcomes other than policy
- I6 tech and product launches (smartphones, apps, game launches, platforms)
- I7 dated clock and calendar rule changes (e.g., the 2007 US DST extension, Samoa's 2011 date-line switch)
- I8 viral moments, memes, challenges

Outcome domains:
- O1 births and fertility; O2 marriage, divorce, family; O3 crime and violence (incl. domestic, hate crime);
  O4 courts, judges, sentencing, juries; O5 hospital admissions, injuries, mortality; O6 traffic and transport
  accidents; O7 school attendance, test scores, education choices; O8 names and language; O9 work, productivity,
  absenteeism; O10 spending outside the stone's own product category; O11 civic acts (blood or organ donation,
  volunteering, census response)

Each (I, O) cell is a query family. Queries pair the cell's event words with its outcome words and one design term
("natural experiment", "difference-in-differences", "regression discontinuity", "event study", "quasi-experimental",
"exogenous"). Two OpenAlex queries per cell; cells with O5 also run on PubMed. Write the frozen query list to
`queries.json` before the first request.

Excluded up front (owner rulings and topic match):
- Outcomes of suicide, self-harm or overdose (Oct 5 and Oct 8 rulings). Party-vote outcomes.
- Topic match: the outcome is the stone's own subject, stated aim or product. Illness disclosure to screening for
  that illness; place on screen to tourism there; product to its own sales; sport event to that sport's participation;
  campaign or documentary to its stated cause; celebrity suicide to suicides.

## Change B: blind predictability gate before verification
Reuse the RSS v1 prompts `predict_v1.txt` and `match_v1.txt` unchanged (log their sha256). Predictions for each new
stone are made in a fresh context that receives only the prompt and the stone names and dates (a judged step). Reuse
cached predictions from the RSS v1 run for stones already there.
Matching also runs in fresh contexts. **Pass the gate = the outcome is not matched at any rank.** Log rank and level for
every candidate either way.

## Pipeline
1. Harvest (OpenAlex works search, PubMed E-utilities; Crossref only as a backup for missing abstracts or dates).
   Reuse the studies pilot's scripts where they fit. Dedupe by DOI.
2. Extract raw pairs: the paper names a specific datable stone, a measured outcome, and a quasi-experimental or
   experimental design. Log every raw pair with its cell. This is the raw denominator.
3. Drop pairs already live (`ripples/chains/*.json`) or in yield v1's 56 study items; log the overlap count.
4. Gate (Change B).
5. Verify every gate-passer (cap 100) plus a random 20 gate-rejects (the audit sample), with the studies pilot method:
   the paper's landing page, PubMed abstract or an open copy; quote check; stone date before outcome window; the design
   is what the abstract claims. Save verified text under `verify/`.
6. Rate with the simulated panel, the v1 protocol unchanged (`docs/yield_plan_v1.md`, the same five personas): all verified gate-passers, the 20 audit rejects, the same 10 planted obvious and 10 planted
   fabricated controls, and 10 anchors from yield v1 for drift. Raters see claim and evidence only, never the gate
   result, cell or generator. Select planted items from `panel_v1.json['items']` by `source`, not by key index.
7. Score.

## Bars
- Validity: planted obvious mean surprise index at most 2.5; planted fabricated mean believable at most 2.5; anchor
  drift under 0.5.
- Primary: at least 45 good per 100 gate-passers entering verification. Baseline 32. Forecast 55, p 0.6.
- Gate audit: at most 5 of the 20 audited rejects rate good.
- Spread: good finds span at least 5 outcome domains; law or policy outcomes at most 20% of good finds.
- Reported without a bar: good per 100 raw pairs; yield by cell; surprise and defensible rates separately.

## Rules
- User agent `ripple-research (bensunter.com)`. No email address or key in any request. At most 1 request per second
  per host (OpenAlex 1 per 2 s; NCBI 3 per s). Any 4xx or 5xx stops that host for the UTC day; log it in
  `logs/blocked_hosts.log` and continue on the other hosts.
- No Wikipedia, Wikimedia, Wikidata, Reddit, Merriam-Webster or Etymonline requests.
- Plain American English, US dates, no em dashes in any file.

## Outputs
`results.md` (bars, both yields, by cell, audit, limits), `candidates.jsonl` (every raw pair with cell, gate rank,
verdicts, ratings), `good.jsonl` (build-ready: stone, stone date, outcome, direction, effect size, design, citation,
quoted sentence, grade Measured or On the record), `logs/`.
