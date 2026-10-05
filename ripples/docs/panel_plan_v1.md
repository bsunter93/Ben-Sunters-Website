# Surprise panel v1: plan (registered before any rating)

Registered Oct 5, 2026, before any rater saw an item.

## Why

The engine has no labels for surprise from anyone but the owner, and his screen tracked evidence (AUC .83 on the model screen's dimensions) but not surprise (.51) or novelty (.48). Surprise cannot be optimized until it is measured. This panel is a stand-in until real people rate after the public launch.

## Who rates

Five **simulated** raters: separate language-model sessions, each given one persona and the same items in its own shuffled order. They are not people. Every result from this panel is labeled "simulated panel". The personas:

1. Maya, 34, high school history teacher in Ohio.
2. Andre, 45, data journalist who distrusts causal claims.
3. Jordan, 19, college sophomore who gets news from short video.
4. Ruth, 67, retired civil engineer who reads two newspapers a day.
5. Priya, 29, Senate committee staffer who knows legislative history well.

Known limit: all five share one model's knowledge, so their judgments are correlated in ways real raters' are not.

## Items

169 claims of the form "stone led to: outcome", each with one evidence line (`docs/results/panel_v1/items.json`; the source of each item is in `key.json`, which raters never see):

- 102 engine-found lasting marks (`demo/discovered_wiki.json`)
- 38 hand-built catalog stories (the Lasting marks shelf)
- 9 new candidates passed by the model screen (PR #118)
- 10 planted obvious pairs (for example 9/11 led to the TSA)
- 10 planted fabricated pairs with invented evidence (for example a coffee shop law credited to Friends)

## Scales (1 to 5 each)

- predicted: before reading, how likely you would have guessed it
- surprise: how surprising it is
- interest: would you tell a friend
- believable: given the evidence line, how believable the link is

## Analysis

- Item scores: mean across raters; surprise index = mean of surprise and (6 minus predicted).
- Agreement: mean pairwise Spearman between raters per scale.
- Validity checks (the panel counts only if both hold): planted obvious pairs have mean surprise index at most 2.5 and below the engine items' median; planted fabricated pairs have mean believable at most 2.5 and below the real items' median.
- Uses: (1) evaluate surprise score v1 (PR #121) against panel labels by rank correlation; (2) count "surprising and believable" items (surprise index at least 3.5 and believable at least 3.5) per source, as the first estimate of the good-discovery rate; (3) a reading order for leads, never a filter for what is true.
