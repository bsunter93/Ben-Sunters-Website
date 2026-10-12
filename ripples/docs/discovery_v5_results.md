# Discovery v5: results (Oct 12, 2026)

Plan: `docs/discovery_plan_v5.md` (registered Oct 11). Amendments A1 (verification sources) and A2 (findings v4 already
had): `docs/discovery_plan_v5_amendments.md`. The owner rated the blind batch of 36 on Oct 12, 00:59 to 01:07 UTC.

## Bars

| Bar | Threshold | Result | Met |
|---|---|---|---|
| Primary: good per 100 real findings in the owner's batch | at least 40 | **10** (3 of 30) | no |
| Primary, without findings that rest only on OpenAlex's copy of the abstract | | 9 (2 of 22) | no |
| Defensible per 100 entering verification | at least 70 | **89** (57 of 64) | yes |
| Defensible, without OpenAlex-only | | 85 (41 of 48) | yes |
| Spread: outcome domains among good finds | at least 4 | 3 (work, civic acts, crime) | no |
| Law: law or policy outcomes among good finds | at most 20% | 0% | yes |
| Controls: mean surprise on planted obvious items | report | 1.0 (3 items) | |
| Controls: mean belief on planted fabricated items | report | 2.67 (3 items; one believed at 4) | |

Prediction logged before the run: primary 40, defensible 75, the panel's good per 100 below 30. Primary was 10,
defensible 89, the panel's 40.6. Good is surprise 4 or more on the claim alone and belief 4 or more after the evidence.
One rater and 30 items: 3 of 30 has a 95% interval of about 2 to 27 per 100.

The three good finds: violent tornadoes and higher wages two years later (UKnowledge, 2019); the 2011 disaster in Japan
and more people joining political groups (Journal of East Asian Studies, 2019); the 2017 Mexico earthquakes and more
sexual abuse and rape (Feminist Economics, 2024).

## Where it fell

Surprise was there and belief was there, on different findings. 15 of the 30 scored surprise 4 or more and 14 scored
belief 4 or more; 3 did both. The owner's surprise and belief ran against each other at Spearman −0.48 (Oct 11:
−0.03). Belief did not depend on the source: 3.17 for journal articles (18), 3.50 for working papers, theses and
repositories (12). Author why lines, shown on 8, came with lower belief (2.88 against 3.45), the reverse of Oct 11
(+0.37); 8 items is too few to read. "Would tell someone" tracked belief (.58), not surprise (.10); on Oct 11 it
tracked surprise.

The simulated panel's surprise agreed with the owner's at .38 (Oct 11: .35) and its belief at −0.10 (Oct 11: .02).
The panel called 40.6 per 100 good; the owner called 12 per 100 of the same gate passers good. The panel is a
pre-filter only, as the plan says.

## Funnel

| Step | Count |
|---|---|
| Raw pairs | 219 (50 null findings, 18 excluded by the rulings) |
| Usable | 151 |
| Dropped: live stories | 4 |
| Dropped: the same claim as a v4 candidate (A2) | 33 |
| Merged or parts of another row | 24 |
| Candidates | 92 on 67 stones (16 stones reuse v4's predictions) |
| Passed the gate | 64 |
| Verification text: quote found in an independent source | 59 of 84 targets |
| Quote found only in OpenAlex's copy | 16 |
| Text without the quote | 5 |
| No text | 4 (v4: 29 of 138) |
| Defensible | 57 of 64 passers; 19 of 20 audited rejects |

Fetch failures seen in verification: an "open copy" that was a university department's home page (two papers), an
empty repository page, a repository's bot check, and NBER PDFs that came back unreadable.

## What it says about the engine

1. Verification is no longer the loss. 89 per 100 defensible, and only 4 targets got no text.
2. Choosing the families the owner rated highest did not raise his yield. The family is not what made a finding good
   for him; the single finding is.
3. 22% of usable raw pairs were the same claim as a v4 candidate in another copy of the same work. Marking papers by
   id does not stop that; matching by title and authors across runs would.
4. The gate's matcher is not consistent: in one chunk it counted assaults as street crime for the autumn clock change
   and not for the spring one.
5. One person's two batches disagree on how his own surprise and belief relate (−0.03, then −0.48). Neither batch is
   enough to tune a filter on. Across both: 19 good of 74 real findings, 26 per 100.
