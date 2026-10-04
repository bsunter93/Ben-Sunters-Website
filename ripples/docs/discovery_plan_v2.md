# Discovery plan v2: cited-cause corpora (registered Oct 4, 2026, 11:00 UTC)

The owner's direction, Oct 4: "we need to figure out how to crack discovery so the engine can genuinely reliably identify
causal chains." This plan is registered before any of its results exist; deviations will be disclosed in the result docs.
It sits under `discovery_engine.md` (D-26) and does not change the verification layer.

## What the project already knows, and what it implies

1. Attention data finds curiosity, not consequence (clickstream, editor trails and attention second hops, three times:
   brief section 3). It stays the verification instrument for post-2015 steps, not the discovery instrument.
2. The one route that found lasting marks on its own was the records route: a legislator named the work in the debate
   on the bill (Mr Bates, Tiger King, The Jungle). The common shape is **a decision record in which the decision-maker
   names the thing that moved them**, dated at both ends.
3. Timing alone is weak and low-powered; the ordering rule is the best single filter because it falsifies.
4. AI-drafted chains get steps 1 and 2 right and invent steps 4 and 5; human-written, cited text does not invent.

Implication: discovery means finding every corpus with the shape in (2), extracting the cause sentence, dating both
ends, and handing the pair to the checker. The grade of a citation stays **reported**; the ladder (timing, comparison,
exposure) is run automatically where an outcome series exists and can raise a link to measured.

## Corpora, in the order they will be tried

| # | Corpus | Shape of the cause sentence | Access | Dates | First test |
|---|---|---|---|---|---|
| 1 | Wikipedia **Legacy / Impact / Aftermath / Reception** sections of memorable stones | "The documentary led to …", "In response to the film, …", with a citation | Wikipedia API (whitelisted) | the sentence's cited date, or the linked article's date | recall against the 79 chains' marks |
| 2 | **Namesake laws** (Megan's Law, Amber Alert, the Brady Bill, Caylee's Law, Laci and Conner's Law, Kari's Law …) | the law names its cause | Wikipedia category lists as the seed; govinfo for the statute | event date; enactment date | recall on the seed list; precision by hand on 30 |
| 3 | **NTSB recommendations → FAA rules** | every recommendation cites the accident; every final rule cites the recommendation | NTSB CAROL export (CSV); Federal Register API | accident; recommendation; rule | a fully dated, explicitly causal calibration corpus for the pipeline's false-discovery rate |
| 4 | **Regulatory preambles and recalls**: Federal Register (runs already), FDA, NHTSA, CPSC | "following reports of …", "prompted by …" | Federal Register API; agency recall feeds | incident; rule or recall | extend `mark_text` with the causal connectives below |
| 5 | **Court opinions** naming a work or event as a reason | "as depicted in …", "in the wake of …" | CourtListener API (free) | opinion date | precision by hand on 30 hits for 20 stones |
| 6 | **SEC filings** naming a work or event | risk factors and 8-Ks: "following the release of …" | EDGAR full-text search (free; `data_sources_v2.md`) | filing date | the same 20 stones |
| 7 | **State legislatures and city councils** | the records route one level down, where most namesake laws pass | Open States API; Legistar | bill action dates | after 2 shows the class is worth it |

Causal connectives to extract on, in all corpora: *led to, prompted, in response to, in the wake of, following, after
the, because of, spurred, triggered, inspired, named after, in memory of, as a result of*. Each hit is kept with the
sentence, the source, both dates, and the connective; `cite_score` labels it reason / context / aside as today.

## The benchmark (fixed now)

- **Recall set:** the lasting marks in the 79 hand-built chains (`chains/batch*.json`, steps with a `mark`), 63 marks
  across 41 stones as of Oct 4. A corpus's recall is the share of those marks it produces on its own from the stone.
- **Precision:** a blind hand screen of 50 engine pairs per corpus, scored interesting / non-obvious / wrong, the way the
  owner scored the first blind round (14 of 15 interesting, 4 of 15 strictly non-obvious).
- **False-discovery rate:** the whole pipeline run on 50 **decoy stones** (real titles with the stone's date shifted by
  2 to 5 years, and 50 obscure titles of the same kind) counts how many chains it produces. Published beside the recall.
- **"Reliable" means:** at least 7 of 10 engine chains survive the blind screen, at a decoy chain rate under 1 in 10, on
  a held-out set of stones the pipeline was not tuned on.

## Order of work and estimates

1. Corpus 1 over the 41 stones with marks, then 500 memorable stones (lists of the most-watched films and shows, best-
   selling books, major disasters by decade). Recall, then a 50-pair screen. About 1.5 days.
2. Corpus 2 and 3 in parallel: the seed list and the NTSB export. About 1 day.
3. The connectives added to `mark_text` and run over the Federal Register, CourtListener and EDGAR for 20 stones. About 1.5 days.
4. The ladder run automatically on every pair with a series; the decoy run; the benchmark doc. About 1 day.
5. If the benchmark is met: the engine tab fed by the pipeline, every chain labeled engine-found and human-screened,
   and the "It wasn't the only reason" line still written by hand.

Owner's probabilities on Oct 4: about 40% that within a month the engine produces lasting-mark chains at a rate where a
person curates instead of writes; about 15% within three months for hidden impacts in behavior, jobs or health with
measured grades, because that is blocked by data resolution (brief section 3, learning 2), not by method.

## Rules carried over

Honest user agent, one request a second, a stop on any 4xx/5xx; keys only in GitHub secrets, so EDGAR, CourtListener
and NTSB run from workflows if the local machine is not used; a citation is reported, never measured; every test
registered before its result; the ordering rule on every pair; nothing dressed as more certain than its test.
