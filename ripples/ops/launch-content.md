# Ripple Map launch content (v6)

Owner: WS-E. Status: prepared 2026-09-26. The owner posts by hand (D-3: no automated posting for the first 14 days).

This file replaces VIRAL_PLAYBOOK §3–5 for v6. It keeps the parts that still apply after D-6 (the Ripple Map is an explorer, not a daily game) and drops every puzzle item. **No points, streaks, crowd splits, rarity lines, "players", countdowns, "can you beat it" or "#n" appear in any post.**

Every number in a post must come from the SQL in §8, run on the day you post. If a query returns something different from the example numbers below, post the query's number, not this file's.

---

## 0. Rules for every post

1. **Words.** Use "consistent with", "moved after", "alongside", "probably linked", "stayed flat", "went nowhere". Never use "caused", "drove", "because of", "flooded into" or "went from X to Y". Never give a percentage or amount of anything as "due to" the shock.
2. **Label reconstructed lines.** Any line from the archive says **"reconstructed"** in the post text, and its card and page carry the label. A reconstructed line was computed after the fact with a mechanism library written on 2026-09-25, after these events. Never call it a prediction.
3. **Measured only in headlines.** A headline can only point at a **Measured** stop in an *outcome* channel (air travel, grid demand, jobless claims, FEMA declarations, rates, package downloads). Likely and Watching stops never go in a headline.
4. **Two fluke numbers, two labels.** "A random pairing looks this strong about 1 in N times" is the placebo p. "Links like this turn out to be flukes about 1 in K times" is the decoy fluke rate. Never merge them and never write "the chance this is chance".
5. **Every post carries the disclaimer** "Consistent with, never proof of cause." If there is no room, the card itself carries it and the post links to `/ripples/methods/`.
6. **Sensitive shocks get quiet mode.** Storms, floods, wildfires, heat, cold and M5+ quakes are marked sensitive. For them: no Shock-of-the-day card, no GIF, no playful copy, no emoji jokes. The line and stop cards can still be shared, with plain words.
7. **No tickers, no prices, no stock examples.** MONEY is disabled in v6.0.
8. **Disclose.** Every "I built this" post says Ben built it.
9. **Show the misses.** Where a post shows a line that moved, it also mentions the ones that stayed flat, the control ripple, or the day's expected flukes.

---

## 1. Assets

| Asset | Where it comes from | Use |
|---|---|---|
| **Line card** (1200×630) | `ripples-og` v=line, pre-rendered at publish to `v2/og/line-{event}-v{k}.png` | Unfurls on `/ripples/line/{slug}/v{k}/` links |
| **Stop card** | `ripples-og` v=stop | Unfurls on `/ripples/line/{slug}/stop/{hop}/` |
| **Week card** | `ripples-og` v=week | Unfurls on `/ripples/week/{yyyy-ww}/` |
| **Brand card** | `ripples-og` v=brand | Evergreen `/ripples/` link |
| **Shock-of-the-day card** | `ripples-og` v=shock | Only for non-sensitive shocks |
| **Launch GIF / MP4** | `ripples/ops/launch/launch.gif`, `launch.mp4`, `launch-poster.png`, cut once by hand from one reconstructed archive line (see §1.1) | Day 2 posts, Show HN (as a link, not an attachment), newsletter pitches |
| **Text share** | built by the page (`navigator.share({text})`, clipboard fallback) | Pasting a line into chats |

Text share shape (EXPERIENCE §7), for an archive line add "reconstructed":

```
{emoji} {line label} ━{stop icons}
{N} stop(s) in {D} days, line ended · reconstructed
consistent with, not proof of cause
https://bensunter.com/ripples/line/{slug}/v{k}/
```

### 1.1 The launch GIF

- Cut once, by hand, from a **published, non-sensitive, reconstructed** archive line that has at least one **Measured outcome** stop (quiet mode forbids a GIF of a sensitive shock). The line, version and every number are in `ripples/ops/launch/line.json`, exported by the SQL in §8.4. The renderer is `ripples/ops/launch/render_launch_gif.py` (PIL + a static ffmpeg; not part of the pipeline).
- Frame 1 is the poster: the ticket with the line's title and "From the archive, reconstructed", the stop tiles still "?", and the staircase with its normal bands. "RECONSTRUCTED" is stamped in the corner of every frame and "Consistent with, never proof of cause." is burned into every frame at 18 px.
- The beats (15 fps, about 4.5 s, loops): lanes draw flat → the Measured stop kicks up with its multiple counting to the shrunk value → tier pips → the day line (tested / moved / expected flukes) and the lookalike sentence → crossfade to the poster.
- If no non-sensitive archive line has a Measured outcome stop, **there is no launch GIF**; post the line card instead. Do not cut a GIF from a Likely stop.

---

## 2. What to post, day by day (14 days)

Standing rules: human posts at 12:00–14:00 UTC; Bluesky at any time (manual); nothing automated; never ask for upvotes; the daily publish lands about 08:45 UTC, so never post a live line before 09:00 UTC.

| Day | Channel | What | Asset | Success signal (SQL / counts only) |
|---|---|---|---|---|
| 0 | Internal | Unfurl matrix (iMessage, WhatsApp iOS/Android, Discord, Slack, X, Bluesky, LinkedIn Post Inspector, Meta debugger) on one reconstructed archive line card, one stop card and the brand card. RSS and per-line `.ics` live. `/ripples/methods/` shows the archive section (Σ expected flukes, decoy control, controls). | line / stop / brand cards | Every surface shows the card and the word "reconstructed" is legible |
| 1 | Private soft launch, 30–50 one-to-one messages | The archive hero line (§3.1 copy A), as a link | line card | `rm_event_counts` landings per share tap |
| 2 | Personal Bluesky / Threads / X | §3.1 copy B, with the GIF (if §1.1 produced one) | GIF / MP4 | Landings with `?src=bsky` etc. |
| 3 | Bluesky, X | First **Shock of the day** (non-sensitive shock only; §3.3). If today's shocks are all sensitive, post the Ripple of the week instead | shock card | Landings per post |
| 4 | **Show HN**, 15:00 UTC; stay 6 h for comments | §3.2 | link only | ≥ 10 points or front page |
| 5 | Newsletter pitches: Garbage Day, Kottke, Web Curios (≤ 120 words each) | §3.4 | 2 screenshots: a line page and an evidence card | ≥ 1 reply within 10 days |
| 6 | Bluesky | "The ones that stayed flat": one line's grey stubs and its control ripple (§3.5) | line card | Landings |
| 7 | **Data Is Plural** pitch (the dataset and the null tests, not the site); first weekly **Ripple of the week** post | §3.6, §3.4 | week card | Pitch sent |
| 8 | Bluesky | A Watching stop resolving (flip or stayed flat) from a live line, only if one resolved; otherwise skip | stop card | — |
| 9 | HN retry, only if Day 4 got < 10 points (email hn@ycombinator.com the day before about the second-chance pool) | §3.2, rewritten around the null | link | Same as Day 4 |
| 10 | LinkedIn, aimed at comms / research people | "What moved after {shock}: a line with its misses printed" (one live or archive line) | line card | `/pro/` visits |
| 11 | Product Hunt, 07:01 UTC | "Trace where a shock shows up next, with the misses printed" (feedback, not upvotes) | gallery: 5 screenshots; the MP4 | Comments |
| 12 | Press pitches: Nieman Lab, Boing Boing (confirm any NPR article exists before pitching) | §3.4 | 3 screenshots, archive link | ≥ 1 reply |
| 13 | r/dataisbeautiful [OC], Thursday | One staircase chart from a line with a Measured outcome stop (live if one exists; otherwise the archive, labelled reconstructed) | static PNG | Upvotes / landings |
| 14 | `/methods/` changelog | Public retro: per-channel landings, shares per landing, what we changed | table | Keep or kill each channel by the numbers |

**Dropped from the v5 plan:** daily-game aggregators (dles, Playlin, PuzzleDaily…), creator playthrough DMs, full-screen practice, Call It results posts, streak or crowd copy, "which one spiked?" teasers, the Belly Flop card. **Do not post to r/InternetIsBeautiful.**

---

## 3. Copy

Placeholders in {braces} are filled from §8; the example values in §7 are from the SQL run on 2026-09-26 and must be re-checked on the day.

### 3.1 Soft launch and personal posts

**A (one-to-one):**
> I built a map of knock-on effects. It starts from a shock and checks where it showed up next: air travel, grid demand, jobless claims, package downloads, rates. Every stop has to beat decoys and fake dates, and the ones that stayed flat are printed too. Here's one from the archive (reconstructed, so after the fact): {line url}

**B (public, with the GIF):**
> {Line label}: {lag} day(s) later, {stop label} ran {ρ̃}× its normal. A random pairing looks this strong about 1 in {p_1_in} times. Reconstructed from the archive; consistent with, never proof of cause. I built this: {line url}

### 3.2 Show HN

Title (≤ 80 chars):
> Show HN: Ripple Map – where a shock showed up next, with the misses printed

First comment (post it yourself, immediately):
> I built this. It starts from a shock (a storm, a heat wave, a macro release, a model release, today's trending pages) and tests a pre-registered set of downstream series: TSA checkpoint counts, EIA-930 grid demand, FRED rates, state jobless claims, FEMA declarations, npm downloads, prediction markets, Wikipedia reading. Each stop is tested against its own weekday/seasonal baseline, with three placebo families (fake dates, other events, lookalike series) through the same code, one weighted Benjamini–Hochberg run per day, and decoy "shocks" that go through everything. A stop is Measured only if an outcome series moved; attention-only co-moves are labelled and capped.
>
> What it can't say: that anything caused anything. Every card says "consistent with". Live lines are still young (the pipeline started on {first live day}), so the home page shows a reconstructed archive line, labelled as such: {archive numbers sentence from §8.2}.
>
> The first version of this idea failed publicly: 0 of 120 hops held up once decoys were added. That post-mortem is on /ripples/methods/, next to the decoy false-discovery rate, the positive controls (including the ones that fail) and a hash-chained ledger of every pre-registration.
>
> No accounts, no tracking beyond a count of share taps, open CSVs. Feedback on the statistics is especially welcome.

### 3.3 Shock of the day (non-sensitive shocks only)

> {emoji} {shock label}: {magnitude}× its normal readers today, the biggest day in {N} days. Already reached: {Measured domains, or "nothing measured yet"}. Watching: {domains with Watching stops} (due {date}). Consistent with, never proof of cause. {url}

If the shock has no Measured stop, the line reads "Nothing measured yet; {n} paths are being watched." Never name a Watching endpoint as where it "went".

### 3.4 Newsletter / press pitch (≤ 120 words)

> Ripple Map traces where a shock shows up next (air travel, grid demand, jobless claims, package downloads, rates) and prints the misses: every stop is tested against fake dates, other events, lookalike series and decoy shocks through the same code, and a stop counts as Measured only if a real-world series moved. The archive of reconstructed lines is labelled as such; across it, {measured} stops reached Measured and about {expected_flukes} of them are expected to be flukes. Free, no login, open CSVs, methods and misses on one page: https://bensunter.com/ripples/methods/. Built by Ben Sunter.

For Data Is Plural, lead with the dataset: daily per-hop statistics, placebo counts and the ledger, CC BY, GREEN-sourced fields only.

### 3.5 "The ones that stayed flat"

> {Line label}: {tested} paths tested, {moved} moved, {flat} stayed flat, and a decoy page that wasn't trending got {control measured} Measured stops. The flat ones are on the map too. {url}

### 3.6 Ripple of the week

> Ripple of the week ({week}): {line label}. Picked by the published rule: most Measured stops, reaching at least 3 domains, hiddenness breaks ties. {qualified sentence}. {week url}

Where `{qualified sentence}` is either "It reached {domains}." or, when nothing qualified, the edition's own note ("Nothing this week reached 3 domains with a Measured stop; showing the best single-stop line." / "No line that started this week reached a Measured stop.").

---

## 4. The weekly editions

`ripples.att_week_edition('YYYY-WW')` writes `att_week_editions` (the `rm_week` source) every Monday 09:05 UTC for the week just closed, publishing every line of the week (duds included). The first four editions and their picks are listed in §7.

---

## 5. Things we never post

- A chain probability, a "total effect", a dollar or job amount.
- A ticker, a price or anything about trades.
- A Likely or Watching stop in a headline.
- A reconstructed line without the word "reconstructed".
- Player counts, rarity, "X people watching", streaks, scores.
- A share GIF or Shock-of-the-day card for a sensitive shock.

---

## 6. Measurement (SQL only)

- Landings and share taps: `select day, kind, src, n, uniq from ripples.rm_event_counts order by day desc;`
- Per-post attribution: links carry `?src=bsky|x|hn|nl|li|ph|rss|ics`.
- Publish freshness: `select public.rm_health();`

---

## 7. Numbers on 2026-09-26 (from §8; re-run before posting)

(filled below by WS-E from SQL)

---

## 8. SQL for every number

```sql
-- 8.1 Archive lines: run, published, with a Measured outcome stop, by domain
select count(*) filter (where status = 'done' and tier <> 'twin') run from ripples.att_archive_plan;
select event_id, version, why, measured_outcome, domains, status from ripples.att_archive_published order by measured_outcome desc, event_id;

-- 8.2 The archive sentence for /methods/ and posts (Σ expected flukes, decoy control, controls)
select payload -> 'archive' from ripples.att_calibration_public order by as_of desc limit 1;

-- 8.3 The hero (cold start) and this week's edition
select ripples.att_hero_pick(current_date);
select public.rm_week(to_char(current_date - 7, 'IYYY-IW'));

-- 8.4 The launch-GIF line (export to ripples/ops/launch/line.json with the query in ripples/ops/launch/README.md)
select * from ripples.att_archive_lines where not sensitive and measured_outcome > 0 order by measured_outcome desc, hidden_max desc nulls last limit 5;

-- 8.5 A line's day line (tested / moved / Measured / expected flukes)
select public.rm_cascade(:event_id) -> 'denominators';
```
