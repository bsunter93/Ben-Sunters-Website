# Live predictions v1: registered before the outcome exists

Registered Oct 5, 2026, 07:15 UTC. The commit that adds this file and `docs/results/predictions_v1.json` is the
registration; nothing below is edited after it. Every window starts on Oct 6, 2026, the day after registration, so no
outcome in this file existed when it was written. A weekly workflow (`.github/workflows/ripples-predict.yml`, running
`lab/predict_check.py`) scores each prediction when it falls due and commits `docs/results/predictions_scored_v1.json`.

**Why this exists.** A measured link in the catalog is a placebo test run after the fact. The strongest verification
the engine can offer is a prediction written before its outcome exists, scored by a rule fixed in advance. This is the
first set: 7 live stones and 7 decoy stones, **32 predictions: 10 "this will move", 15 "this will NOT move", 7 decoys**
(all "will not move"). Due dates run from Oct 18, 2026 to Feb 28, 2027.

## The feed

- **The Google Trends archive** (brief, section 1c item 5). It is not a file in the repository: the daily workflow
  `.github/workflows/ripples-gt-archive.yml` copies the public BigQuery `google_trends` lists into the table
  `ripples.att_gt_terms` in the project's database. It was read through the owner's database connector for this
  registration (US refresh dates Aug 25 to Oct 1, international Aug 18 to Oct 3). The scorer never touches it.
- **Wikimedia's top-pageviews API** (en.wikipedia, all-access), one request a day for Sep 20 to Oct 3, 2026, to see
  which articles had just entered the top 1,000 and to cross-check the Trends terms.

A stone qualified when its attention spiked in the last 1 to 14 days in either feed and a plausible downstream exists
that public, keyless data can record: attention to a related topic, a library's borrowing, a parliamentary record, a
bill. Sports fixtures, celebrity items with no mechanism and foreign-language films with no English downstream were
passed over. Decoys are stones with a large feed signal and, on the engine's reading, no mechanism to anything.

## Windows from the lag priors

Windows come from the shape pass's lag priors (`docs/results/lag_priors_v1.json` and `docs/shape_v1.md` on the
`eng-shape` branch, code `187859f`, not yet on main): media -> search days 1 to 20, news -> search days 0 to 2, search -> search (second
hop) days 3 to 15, pooled days 0 to 23. The part of a prior window that had already passed at registration is cut off,
and the cut is stated per prediction (for example, A1's prior window starts Oct 3; its window is Oct 6 to 15). Where
the prior window had fully passed (news echoes), the prediction is about decay or persistence instead, using shape
v1's findings: the median half-life of an attention spike is 10.7 days, a new normal is rare (12 of 454 series), and a
new normal is not called before 21 weeks. A ripple to a law takes years (reported median 598 days), so the one
legislative prediction here is a "will not".

## The tests (fixed now; the scorer implements exactly this)

**wiki_level** (26 predictions). Daily views, user agent, all-access, from the per-article pageviews API; several
articles are summed. With e the stone's date: baseline b = median of days e-120 to e-15 (the checker's baseline);
m = the window's mean; r = m / max(b, 1).
- *Placebo:* the same statistic at pseudo-dates every 14th day of the page's own history (index 130, 144, ... up to
  e-200), each with a complete baseline and window; p = (1 + the count of pseudo-ratios at least r) / (1 + N). Fewer
  than 20 pseudo-dates voids the prediction.
- *Seasonal check:* r must exceed the same ratio at e-365, e-730 and e-1095 wherever those exist (the brief's rule that
  a confirmation must pass the seasonal check).
- *Material:* m - b of at least 20 views a day, and r of at least 1.5.
- **Moved** = p <= 0.05, material, and the seasonal check passed.
- *Order:* the checker's own onset (`editor_trail.onset` searched from e-30, as in `chain_check.wiki_test`). The order
  holds when there is no onset or the onset is no earlier than e-3.

**library_month** (4). Seattle Public Library's public Checkouts by Title (data.seattle.gov, `tmmm-ytt6`), October
2026, all formats, titles starting with the listed words whose creator contains the author's surname.
s(M) = ln(c(M) + 1) - ln(mean of the 3 months before + 1). Placebo pool: every month from Jan 2013 to two months
before, excluding Mar 2020 to Jun 2021 (closures). Seasonal check: s beats the same calendar month of every prior year.
Material: at least 10 more checkouts than the 3-month mean. Order: the same test on September 2026 must not move.
October's counts are published in early December (August's were the latest on Oct 5), so these fall due Dec 14 and are
void if unpublished on Jan 31, 2027.

**hansard_mention** (1). The UK Parliament Hansard API, spoken contributions naming the term with sitting dates in the
window. **uk_bill_first_reading** (1). The UK Parliament Bills API, bills whose short title matches the registered
expression, dated by the first sitting of their first stage.

## Verdicts

| Kind | Hit | Miss | Bust |
|---|---|---|---|
| Will move | moved, in order | did not move | moved, but began more than 3 days before the stone (library: in September): the ordering rule |
| Will NOT move (and decoys) | did not move | moved, in order | moved, in order, p <= 0.01 and at least 10 times the baseline: a strong ripple where none was predicted |
| Record, will happen | at least one record in the window | none | none possible for this test |
| Record, will not happen | none in the window | one or more | none possible for this test |

**Void:** an article missing or renamed, fewer than 20 placebo windows, data unpublished by the deadline, or (for a
"will not move") a rise that began before the stone, which can neither credit nor blame it. A source that refuses
(403, 429 or 5xx) stops the run for the week with no retry; it is tried again the next week. A void is never rescored
with a different series. Each prediction also carries a stated confidence, so the set can be scored for calibration
(Brier score) as well as hits.

## The predictions

### Christa Pike's failed execution (stone Sep 30, 2026)

Two failed lethal injections on Sep 30; the governor halted the state's one other 2026 execution and ordered a
third-party review; the corrections commissioner resigned on Oct 3. Feed: Trends US rising, 210 of 210 regions, week
of Sep 27; the article had 4.31 million views on Oct 1.

| ID | Kind | Claim | Window | Prior | Conf. | Due |
|---|---|---|---|---|---|---|
| A1 | move | Capital punishment in Tennessee stays above chance | Oct 6 to 15 | search -> search 3 to 15 (Oct 3 to 5 passed) | 0.60 | Oct 18 |
| A2 | move | Lethal injection stays above chance | Oct 6 to 15 | search -> search 3 to 15 | 0.50 | Oct 18 |
| A3 | not move | Nitrogen execution (Inert gas asphyxiation) does not rise | Oct 6 to 15 | search -> search 3 to 15 | 0.65 | Oct 18 |
| A4 | not move | Job Corps (the victim's 1995 classmates: curiosity, not consequence) is back within chance | Oct 14 to Nov 4 | after the 0 to 2-day news prior | 0.75 | Nov 7 |
| A5 | not move | No raised floor for Christa Pike in weeks 13 to 21 | Dec 30 to Feb 24, 2027 | shape v1's 21-week rule | 0.60 | Feb 27, 2027 |

### Esther Rantzen's death (stone Sep 30, 2026)

Founder of Childline and the most visible campaigner for assisted dying in England; she died 19 days after the Commons
rejected the reintroduced Terminally Ill Adults (End of Life) Bill (286 to 270, Sep 11). Feed: international Trends,
rising first in France and fifth in Hungary; 157,605 views on Sep 30.

| ID | Kind | Claim | Window | Prior | Conf. | Due |
|---|---|---|---|---|---|---|
| B1 | move (record) | She is named in at least one Commons or Lords spoken contribution | Oct 6 to Nov 30 | record; the first sitting weeks after the recess | 0.85 | Dec 3 |
| B2 | not move (record) | No bill on assisted dying, assisted suicide, the end of life, terminally ill adults or euthanasia gets a first reading in either House | Oct 6 to Dec 31 | attention -> law: reported median 598 days | 0.80 | Jan 4, 2027 |
| B3 | not move | Assisted suicide in the United Kingdom does not rise | Oct 6 to 15 | search -> search 3 to 15 | 0.70 | Oct 18 |

### East of Eden, the Netflix limited series (stone Oct 1, 2026)

Feed: international Trends (New Zealand, rising); the series' article 171,814 views on Oct 2 and the novel's 193,513 on
Oct 3.

| ID | Kind | Claim | Window | Prior | Conf. | Due |
|---|---|---|---|---|---|---|
| C1 | move | John Steinbeck stays above chance, past the seasonal check | Oct 6 to 21 | media -> search 1 to 20 (Oct 2 to 5 passed) | 0.75 | Oct 24 |
| C2 | move | The 1955 film East of Eden stays above chance | Oct 6 to 21 | media -> search 1 to 20 | 0.60 | Oct 24 |
| C3 | not move | The article titled Timshel (a 2012 Hell on Wheels episode sharing the novel's key word) does not rise: a check on word collisions in attention data | Oct 6 to 21 | media -> search 1 to 20 | 0.60 | Oct 24 |
| C4 | move (behavior) | Seattle library checkouts of East of Eden rise in October beyond chance and beyond every prior October | Oct 2026 | the stone's month | 0.60 | Dec 14 |
| C5 | not move | The Grapes of Wrath does not rise, past the seasonal check | Oct 6 to 21 | media -> search 1 to 20 | 0.60 | Oct 24 |
| C6 | not move | Salinas, California (the setting) does not rise | Oct 6 to 21 | media -> search 1 to 20 | 0.70 | Oct 24 |
| C7 | not move | No raised floor for John Steinbeck in weeks 13 to 21 | Dec 31 to Feb 25, 2027 | shape v1's 21-week rule | 0.75 | Feb 28, 2027 |
| C8 | not move (behavior) | Seattle library checkouts of The Grapes of Wrath do not rise in October | Oct 2026 | the stone's month | 0.65 | Dec 14 |

### Verity, the film (stone Oct 2, 2026, the US release)

Feed: international Trends top lists in India, Mexico, Brazil, Hungary and the Philippines; the film's article 151,519
views on Oct 2. The London premiere on Sep 24 is before the stone date, which is why D3's order is at risk.

| ID | Kind | Claim | Window | Prior | Conf. | Due |
|---|---|---|---|---|---|---|
| D1 | move (behavior) | Seattle library checkouts of Verity rise in October beyond chance and beyond every prior October; September does not already rise | Oct 2026 | the stone's month | 0.50 | Dec 14 |
| D2 | not move (behavior) | Seattle library checkouts of It Ends with Us do not rise in October | Oct 2026 | the stone's month | 0.70 | Dec 14 |
| D3 | move | Colleen Hoover stays above chance, with the rise starting no earlier than Sep 29 | Oct 6 to 22 | media -> search 1 to 20 (Oct 3 to 5 passed) | 0.55 | Oct 25 |

### Unabomber, the Netflix film (stone Sep 25, 2026)

Feed: Ted Kaczynski 438,924 views on Sep 27 (from about 14,000 before the release).

| ID | Kind | Claim | Window | Prior | Conf. | Due |
|---|---|---|---|---|---|---|
| E1 | move | Industrial Society and Its Future (the manifesto) stays above chance | Oct 6 to 15 | media -> search 1 to 20 (Sep 26 to Oct 5 passed) | 0.65 | Oct 18 |
| E2 | not move | Anarcho-primitivism does not rise | Oct 6 to 15 | media -> search 1 to 20 | 0.60 | Oct 18 |
| E3 | move | Henry Murray (whose Harvard experiments Kaczynski underwent) stays above chance | Oct 6 to 15 | media -> search 1 to 20 | 0.60 | Oct 18 |

### Flydubai Flight 1073 (stone Sep 30, 2026)

A Dubai to Tel Aviv flight squawked a hijack code and diverted after the first officer attacked the captain. Feed:
Trends US top list, 163 regions; 133,927 views on Oct 1.

| ID | Kind | Claim | Window | Prior | Conf. | Due |
|---|---|---|---|---|---|---|
| F1 | not move | Boeing 737 MAX (the type played no part) does not rise | Oct 6 to 15 | search -> search 3 to 15 | 0.70 | Oct 18 |
| F2 | not move | Germanwings Flight 9525 (the sibling pilot-caused crash) is back within chance | Oct 6 to 15 | search -> search 3 to 15 | 0.55 | Oct 18 |

### The Cornell civil suit (national attention Sep 30, 2026)

Feed: Trends US top list, second, 185 regions. No individual is named here.

| ID | Kind | Claim | Window | Prior | Conf. | Due |
|---|---|---|---|---|---|---|
| G1 | not move | Title IX does not rise | Oct 6 to 15 | search -> search 3 to 15 | 0.70 | Oct 18 |

### Decoy stones (all "will not move")

| ID | Decoy stone (date, feed) | Claimed companion that should not move | Window | Conf. | Due |
|---|---|---|---|---|---|
| X1 | Passenger pigeon (Sep 27; one day in the top 1,000, 76,003 views) | De-extinction | Oct 6 to 20 | 0.80 | Oct 23 |
| X2 | Hydraulic ram (Sep 29; two days, 84,323) | Hydraulic shock (water hammer) | Oct 6 to 22 | 0.85 | Oct 25 |
| X3 | Theory of mind (Sep 30; one day, 183,160) | Sally–Anne test | Oct 6 to 23 | 0.80 | Oct 26 |
| X4 | Anti-lock braking system (Oct 2; one day, 90,185) | Electronic stability control | Oct 6 to 25 | 0.85 | Oct 28 |
| X5 | National Day for Truth and Reconciliation (Sep 30; annual) | Canadian Indian residential school system, past the seasonal check | Oct 6 to 23 | 0.80 | Oct 26 |
| X6 | TJ Maxx store closures (Trends US rising, 201 regions, week of Sep 27; no announcement found) | TJX | Oct 6 to 20 | 0.70 | Oct 23 |
| X7 | Hunger stone (Sep 28; two days, 111,489) | Elbe | Oct 6 to 21 | 0.85 | Oct 24 |

## Disclosures

- **Exposure before registration.** Reading the top-1,000 lists to pick stones showed same-day echoes in some outcome
  articles, all before any window: Lethal injection, Job Corps, Henry Murray, Industrial Society and Its Future, John
  Steinbeck, East of Eden (film), Germanwings Flight 9525, Colleen Hoover, Capital punishment in Tennessee, the
  Sally–Anne test, Inert gas asphyxiation and the Canadian Indian residential school system each appeared in the list
  on 1 to 9 days between Sep 27 and Oct 3 (peaks and dates in the JSON). That is why every window is a later window.
  No per-article series, library count, Hansard count or bill list was read for any window or baseline.
- **The stone date is a choice.** For releases the stone is the public release (Verity: the US opening, not the
  London premiere); for news it is the day of the event. The ordering rule is applied from that date as registered.
- **Confidence is mine,** stated so the set can be scored for calibration. Expected hits at these confidences: about 22
  of 32.
- **The scorer is written after this registration,** to the specification above; any departure from it will be
  disclosed in the scored file, never folded in.

## What this set does not do

No prediction here reaches a lasting mark. The marks these stones could leave (a Tennessee law on execution methods, a
new assisted-dying bill) have reported lags of years and need legislative records that are not reachable without a
key (Congress.gov and govinfo need one; Tennessee's legislature has no public API). They belong in a later set scored
by a registered hand screen. Everything here is attention, borrowing in one city's library, and two parliamentary
records.
