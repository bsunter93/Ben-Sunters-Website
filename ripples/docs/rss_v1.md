# Relevant Surprise Score, experiment v1: results (Oct 9, 2026, simulated raters)

Spec: the owner's Relevant Surprise Score spec of Oct 8, 2026 (RSS = S^alpha x R^beta; surprise and relevance kept
apart; evidence decides eligibility, never the score; ranking only). Code: `ripples/engine/rank/` (`rss.py`, `eval.py`,
`config_v0.json`, `config_v1_exploratory.json`, the rubrics `relevance_v1.txt` and `types_v1.txt`). The blind
prediction and matching prompts behind S_A are `ripples/engine/gate/predict_v1.txt` and `match_v1.txt`.

Raters: five simulated personas, pass 1 expectations, then claims only (surprise), then evidence. Controls valid:
planted obvious mean surprise 1.0; planted fabricated mean evidence 1.24. Agreement (mean pairwise Spearman): surprise
.84, relevance .65, significance .89, value .83, evidence .79. Accepted = eligible, mean value >= 3.5 and mean surprise
>= 3.5: base rate 6.4% of 220.

## As specified (v0: S = S_A, S_B, S_D equal; R = C, G equal), held-out catalysts, 5 folds

| Ranker | P@10 | P@20 | NDCG@20 | Accepted per 100 | rho value | rho surprise |
|---|---|---|---|---|---|---|
| existing (evidence first) | .16 | .13 | .787 | 13 | .31 | .13 |
| RSS v0 | .18 | .09 | .706 | 9 | .08 | .50 |

Bootstrap RSS minus existing, NDCG@20: -0.056 (95% CI -0.23 to 0.09). Not better.

## Components against their human counterparts (Spearman)

S_A prediction-based surprise .70; S_D prior discoverability .36 (mostly missing); S_B type rarity .02 (no signal);
G significance .65; C catalyst relevance .36 (ceiling). Rated surprise and rated value are nearly unrelated here
(surprise only vs value -0.07); value tracks evidence quality and significance.

## Exploratory, chosen after seeing v0 (must be confirmed on a new batch)

v1 config: S = S_A only, R = 0.25 C + 0.75 G (geometric). Ranker: evidence tier first, then RSS inside each tier.

| Ranker | P@10 | P@20 | NDCG@20 | Accepted per 100 | rho surprise |
|---|---|---|---|---|---|
| evidence tier, then RSS v1 | .20 | .14 | .787 | 13 | .28 |

Same value as the existing ranking, more surprise at the top. Small and within fold noise.

## Limits

The simulated raters and the prediction step come from the same system, so S_A's .70 may be inflated. 220 candidates,
6.4% accepted: ranking can only reorder a pool that holds few surprising, well-evidenced finds. S_D is mostly missing:
the Wikipedia fetch for it stopped on an HTTP 429 after 10 articles on Oct 9.

## Running it

`rss.py` and `eval.py` read one experiment's inputs from a folder given with `--data`: candidates, controls, their
features, the rater forms and the key.

```
python3 ripples/engine/rank/rss.py --data DIR
python3 ripples/engine/rank/eval.py --data DIR                    # the v0 table
python3 ripples/engine/rank/eval.py --data DIR --exploratory --config ripples/engine/rank/config_v1_exploratory.json
```
