# Screen plan v1: can a language model replace the hand screen for the first pass? (registered Oct 5, 2026, 06:15 UTC)

Item 2 of the discovery program: today a person screens every candidate the engine finds before it ships. This plan
registers a test of whether a language model applying a fixed rubric can do that first pass. It is committed and
pushed before any label exists; deviations will be disclosed in `docs/screen_v1.md`.

## What is tested

- **The rubric:** `lab/discovery/screen_rubric.md`, **v1**, as committed with this plan. Per candidate it outputs
  `is_mark`, `link_label` (reason / context / aside), `date_ok`, `disputed`, a one-line justification, a `gate`
  (pass / fail), a `decision` (accepted / rejected) with one `reason_code` from the owner's fixed list, `flags`, and four
  scores from 0 to 100 (interest, surprise, evidence, novelty).
- **The labeler:** a language model, run by hand, applying the rubric to each candidate from its text fields alone.
- **The comparison:** the gate against the person's decisions in the same runs.

## The evaluation sets (frozen in `docs/results/screen_candidates_v1.json`, built by `lab/discovery/screen_sets.py`)

| Set | What | Candidates | Class | Where the hand decision lives | "Kept" means |
|---|---|---|---|---|---|
| E1 | the catalog's strict reverse pairs in order (corpus 1, v1) | 23 | 18 events, 5 culture | `discovery_corpus1_screen.json`, `catalog_strict_in_order`, one label per pair | labeled a real mark (not weak, context or wrong) |
| E2 | held-out stones, forward sentences in order (v1) | 47 | 30 events, 17 culture | `discovery_corpus1_screen.json`, `heldout_forward_47`, and the twelve marks listed in `discovery_corpus1_v1.md` | the sentence states one of the twelve marks |
| E3 | discovery v1.1, sixty stones: 15 reverse pairs and 198 forward sentences | 213 | 197 events, 16 culture | the marks from this run in `demo/discovered_wiki.json` | the sentence states a mark that shipped |
| E4 | the culture shelf, 132 stones | 234 | culture | the culture marks in `demo/discovered_wiki.json` | the sentence states a mark that shipped as reported |
| E5 | fifty famous films as decoys | 33 | culture | `roundtable_v2.md`: nothing a screener would keep | nothing is kept |
| E6 | the fifty obscure decoys of v1, the example sentences the run kept | 11 | culture | none (decoys by construction) | nothing is kept |
| S1 | the 22 citation hand grades behind cite_score v1 | 22 | culture | `cite_score_v1.json`, `eval.rows` | truth is reason |

Class is fixed in the script before labeling: culture when the stone is a work, a broadcast, a product, a toy, a game,
a fad or a diet; events otherwise.

**Not usable for per-item scoring:** the catalog's forward loose sample (50 random of 224 sentences, recorded only as
counts), so it is left out of the comparison.

## How the hand decisions are matched (after the labels are pushed)

- E1 and S1: by the pair's name, mechanically.
- E3 and E4: a candidate is hand-kept when a mark for the same stone in `demo/discovered_wiki.json` carries the same
  sentence (normalized text, the shorter contained in the longer, or 60% of word tokens shared), or, failing that, when
  the candidate states that mark (the same law, body or change named). The second step is a judgment made with the
  hand labels visible; every match made that way is listed in the result doc so it can be checked. A product mark with
  `grade: disputed` is a hand "disputed", left out of precision and recall and compared with the `disputed` field.
- E2: by the twelve marks' names, by hand, every match listed.
- Product marks that no candidate in the sets states are counted and left out of the recall denominator.

## Metrics (all fixed now)

1. **Precision** = candidates the gate passes that the person kept / candidates the gate passes.
2. **Recall, mark level** = hand-kept marks (stone, mark) with at least one candidate the gate passes / hand-kept marks
   that some candidate states. Also reported at sentence level.
3. **Agreement** = raw agreement and Cohen's kappa between gate pass and hand kept, per candidate.
4. Each of 1 to 3 **pooled over E1 to E4, per set, and per class (events, culture)**.
5. **Decoys passed** = candidates in E5 the gate passes (E6 reported beside it).
6. **The four scores against the owner's keep or reject:** for each of interest, surprise, evidence and novelty, the
   mean for kept and for rejected candidates, and the area under the ROC curve for the score as a predictor of keep
   (0.5 is no relation), pooled and per class; on E1, the mean by the four hand labels (mark, weak, context, wrong).
7. **Disputed:** hand-disputed product marks against the `disputed` field.
8. **Sensitivity lines, not part of the bar:** E1 with "weak" counted as kept; precision against the person's looser
   count where a doc gives one (v1.1: "about 70" forward sentences stated a mark; culture: "about 30" real marks), as a
   ratio of counts only.
9. **S1:** `link_label == "reason"` against truth `reason`, precision and recall beside cite_score v1's .73 and .89.
   Not blind, so not part of the bar.

## The bar: "the screen can replace the person for first pass"

All three, pooled over the blind sets:

1. **Precision >= 0.61**, the hand-screened strict set's own precision (the strict reverse rule, 14 of 23 clean on the
   catalog, `discovery_corpus1_v1.md`; v1.1's reverse pairs were 9 of 15, 60%). Pooled over E1 to E4.
2. **Recall >= 0.80 on kept marks**, mark level, pooled over E1 to E4.
3. **0 decoys passed** in E5.

A per-class verdict (events, culture) against the same three numbers is reported as secondary; the headline is the
pooled verdict. A failed bar is reported as failed, with the diagnosis (which reason codes the misses and the false
passes carry), and the confusion cases quoted.

## Blindness, and what the labeler saw first

The labels are written to `docs/results/screen_labels_v1.json` from `screen_candidates_v1.json` alone and committed and
pushed **before** any hand-decision file is opened for comparison. What the labeler had already seen, disclosed now:

- The result docs the brief required reading first (`discovery_corpus1_v1.md`, `discovery_corpus1_v1_1.md`,
  `discovery_culture_v1.md`) quote about fifty kept marks by name (the "non-obvious" lists, the fourteen strict marks,
  the twelve held-out marks) and about ten rejected ones (Vietnam's Barbie ban, Wallkill's permit law, Cathy Come Home
  and Shelter, Top Gun as Disputed). Each label carries `seen_in_docs: true` when the labeler recognizes the specific
  stone and mark from those docs, and every metric is also reported on the unseen subset.
- `roundtable_v2.md` summarizes the famous-decoy screen (three one-country bans and one industry claim, none kept).
- `lab/cite_score.py` hard-codes the 26 calibration labels behind S1 in its source, which was read in the setup pass.
  **S1 is therefore not blind.** It is labeled and reported, and it does not count toward the bar.
- A key listing of `demo/discovered_wiki.json` showed the stones' slugs (which stones shipped), not their marks or
  sentences.
- The rubric was written after reading the project's definitions and these docs. It mirrors the definitions; it was not
  checked against any hand label.

## The labeled corpus

`docs/results/screen_corpus_v1.json`, for every candidate in the sets: id, set, class, stone, the sentence, `decision`
(accepted / rejected), `reason_code` (from the owner's list: not_a_mark, attention_only, context, aside, bad_timing,
undated, weak_evidence, duplicate, confounded, obvious, wrong_entity, disputed), `flags`, the four scores, and, added
after the comparison, the hand decision. It is the start of a labeled corpus of what a good ripple is.

## Automation

`lab/discovery/screen.py` runs the same rubric through a language-model API, the key from an environment variable and
the model from `RIPPLE_SCREEN_MODEL` (no default, no name in the file). It is not run in this pass and no workflow is
added: the repository's secrets hold no key for such an API.

## Exploratory, after the comparison (not part of the bar)

If time remains, the rubric is applied to candidates no person screened item by item: the catalog's loose forward pool
(224 causal sentences in `legacy2_all.json`; a random 50 were screened in v1 and recorded only as counts). Passes are
listed in `docs/results/screen_new_v1.json`, labeled "screened by a language model, not by a person", and nothing
enters the product from it without a person.
