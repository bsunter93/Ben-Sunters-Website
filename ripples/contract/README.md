# Knock-On v5 contract (W1)

Everything other workstreams build against. The spec is authoritative
(`SPEC.md` §10); this file records the exact behaviour W1 deployed, including
decisions the spec left open. Supabase project `kffkasnzqcddpystszch`.

## Files

| Path | What |
|---|---|
| `defs.schema.json` | shared `$defs` (date, qid, category, crossItem, ...) |
| `puzzle.schema.json` `reveal.schema.json` `stats.schema.json` `callit.schema.json` `board.schema.json` `archive.schema.json` `brief.schema.json` `latest.schema.json` `health.schema.json` `og-data.schema.json` `answers.schema.json` | strict JSON Schemas (additionalProperties false) |
| `fixtures/puzzle-0.json` `reveal-0.json` `board-0.json` `callit-0.json` `stats-0.json` `archive-fixture.json` `og-data-0.json` `answers-0.json` | byte-for-byte mirrors of the DB fixture n=0 (see md5 check below) |
| `fixtures/latest.json` | `latest.json` as it looks before launch (delayed, puzzle null) |
| `fixtures/*.sample*.json` | synthetic UI-state samples, **not** DB output: `stats-0.sample-shown.json` (≥30 players), `latest.sample-published.json`, `brief.sample.json`, `health.sample.json`. Their `_comment` key is ignored by the validator |
| `tools/build_fixture.py` | regenerates every fixture file and `sql/03_fixture_n0.sql` deterministically |
| `tools/validate.py` | dependency-free validator: schemas + semantic cross-checks + `--md5` in Postgres `jsonb::text` form |
| `sql/01_ripples_v5_core.sql` `sql/02_ripples_v5_public_rpcs.sql` | exact copies of the deployed objects (function bodies md5-verified against `pg_proc.prosrc`) |
| `sql/03_fixture_n0.sql` | the fixture insert |
| `rpc-smoke.sql` | 82 checks over every RPC incl. error paths + a rolled-back live-puzzle lifecycle; cleans up after itself |

```
python3 ripples/contract/tools/validate.py                      # all fixtures + cross-checks + md5 list
python3 ripples/contract/tools/validate.py reveal.schema.json x.json
python3 ripples/contract/tools/validate.py --md5 ripples/contract/fixtures/reveal-0.json
-- in SQL:  select md5(public.ripples_reveal(0)::text);            -- must equal the line above
```

## Cross-source evidence (contract extension)

`PuzzlePayload.seed.cross`, `RevealPayload.rounds[].evidence.cross` and
`BoardPayload.trends[].cross` are arrays of
`{"source":"gtrends|bsky|mastodon|gdelt_tv|autocomplete|polymarket|…","label":"text","multiple":num|null,"z":num|null,"when":"before|alongside|after"|null}`.
Producers emit `[]` until the attention layer fills them. The key is **required** (may be empty).

## Visibility and time

* Puzzle #N goes live 07:30 UTC on its date. "Current puzzle date" = `(now() at time zone 'utc' − 7h30m)::date`; current n = that − epoch (2026-09-25).
* **live**: visible only when `status='published'` and `puzzle_date <= current puzzle date`.
* **practice** (n<0): visible when `status in ('built','published')`.
* **fixture**: n=0 only, always visible, never returned by `ripples_latest`, `ripples_board(null)`, `ripples_brief`, `ripples_archive('live'|'all')`.
* Table constraint: live ⇒ n>0, practice ⇒ n<0, fixture ⇒ n=0 (and only the fixture has status `fixture`).

## Public RPCs (anon + authenticated; GET for STABLE, POST for VOLATILE)

| RPC | Returns / behaviour |
|---|---|
| `ripples_latest()` | `{n,date,status,puzzle,next_at}`. Newest visible live puzzle; `status='published'` when its date is the current puzzle date, else `'delayed'` with the previous puzzle. No live puzzle ever: `{n:null,date:<current>,status:'delayed',puzzle:null}`. `next_at` = next 07:30 UTC rollover (extension, for the countdown) |
| `ripples_puzzle(p_n)` / `ripples_reveal(p_n)` | PuzzlePayload / RevealPayload or `null`. Copy overlay: `ripples.copy` headline replaces `payload.headline`, caption rows replace `reveal.rounds[i].caption` (the unique key keeps one row per slot, so an `ai` row that replaced a `template` row wins). Never applied to the fixture |
| `ripples_stats(p_n)` | StatsPayload, `you:null`. Below `config.min_players` (30): `shown:false`, `rounds/score_hist/mag_median_x` null, `players` still reported |
| `ripples_callit(p_n)` | CallItPayload; `resolves_on = window_start + 8`; `crowd_pct` only at ≥30 calls; `max_z` and `url` only once resolved; option order follows `payload.callit.options` |
| `ripples_board(p_n default null)` | BoardPayload; null → latest visible live board (null before launch) |
| `ripples_archive(p_limit 60, p_kind 'live')` | `p_kind` ∈ `live|practice|all|fixture` (`all` = live+practice, live first). `path` = seed emoji + each answer emoji; a fresh-ripple round is prefixed `·` + its seed emoji, e.g. `👤📍🎬·🎵🏅` |
| `ripples_brief(p_days 7, p_category null)` | Live answer hops with `puzzle_date` in `[current−days, current−1]` (today's puzzle never appears). If no live puzzle is in range, falls back to the newest reconstructed practice puzzles and sets `"reconstructed": true` (extension — label it on the page). Unknown category → empty items. `intro` = newest `brief_intro` copy in range |
| `ripples_health()` | `{latest_n,published_at,stale,expected_n,stage,wm_calls,errors,clickstream_month}`; `stage/wm_calls/errors` read `ripples.runs` (W2), `clickstream_month` reads `ripples.clickstream` (W3) when those tables exist |
| `ripples_submit_play(p_client,p_n,p_picks,p_mag)` | see below |
| `ripples_submit_call(p_client,p_n,p_qid)` | `{"ok":true,"split":[{qid,pct}]|null}` (split only at ≥30 calls) |
| `ripples_join(p_email,p_role,p_price,p_topics,p_source)` | always `{"ok":true}` |

`ripples_track_record()` is W3's; `publish_bundle` calls it if it exists.

### ripples_submit_play
* Errors (PostgREST 400, `message` = code): `invalid` (client not `^[A-Za-z0-9_-]{16,64}$`; picks not an array of length R; a round not 1–2 distinct ids in a–d; a second pick after a correct first pick; `p_mag` outside 1.5–100), `closed` (unknown/invisible n, practice n, or live n outside `current−7..current`), `rate_limited` (21st call from one IP-hash per UTC day; invalid calls are not counted).
* Scoring on the server from `ripples.puzzles.answers` and `final_multiple`: codes 2/1/0 per round; slider `e=|log10(guess/actual)|` → 2 if e≤0.176, 1 if e≤0.477; max = 2R+2.
* One row per `(n, client_hash)`; a duplicate returns current stats with the **stored** score.
* `you = {score,max,percentile}`; `percentile` (share below + half of ties, 0–100) is `null` below 30 players.
* The fixture n=0 accepts plays (for testing); practice puzzles do not.

### ripples_submit_call
`invalid` (bad client, QID not `^Q\d+$`, or not one of that n's Call It options), `closed` (invisible/practice n, or live and UTC date > `window_start + 1`), `rate_limited` (20/IP/day). One call per client per n; later calls are ignored.

### ripples_join enums (anything else → silently ignored, still `{"ok":true}`)
* email: lower-cased, trimmed, ≤254, `local@domain.tld` regex.
* `p_role`: `player creator newsletter pr_comms seo_content journalist researcher brand analyst other` or null.
* `p_price`: `free radar5 radar19 team149 report149 partner500 api` (null → free).
* `p_topics`: subset of the 13 categories. `p_source`: `^[a-z0-9_-]{1,32}$` or null.
* 5 attempts per IP per day (all attempts count). Upsert on `email_norm`: role/price/topics take the latest non-null value; source keeps the first. No function ever returns an email.

## Service-only RPCs (service_role)
* `ripples_og_data(p_n default null)` → `{n,kind,status,date,from_date,past,seed{title,emoji,biggest_in_days,since_records,multiple,langs},rounds[{i,continues,seed_emoji,emoji,title,multiple}],R}`; null n → latest live; null when not visible. `past` = `puzzle_date < UTC today` (gate the reveal variant on it). Note `past` flips for the fixture after 2026-09-25, so `fixtures/og-data-0.json` only matches on the fixture date.
* `ripples_publish_bundle(p_n default null)` → `{n,kind,date,latest,puzzle,reveal,callit,board,archive,track,csv_rows,recent_callit,ledger_head}`.
  * null n → newest live puzzle with status built/published and `puzzle_date <= UTC today` (so the 07:25 run pre-stages today's files; `latest` flips at 07:30 and is rewritten by the 07:45 run).
  * live/practice: sets `status='published'`, `published_at`. Fixture: never changes status. `vetoed`/`delayed` with explicit n → error `not_publishable`.
  * live only: writes the ledger row if missing and returns `csv_rows` (`date,n,round,parent,answer,multiple,z,lag_days,fluke,p_time,category`; Wikimedia-derived only). Fixture/practice → `csv_rows: []`.
  * `archive` = `ripples_archive(500,'all')`; `recent_callit` = `[{n,callit}]` for the last 8 published live puzzles (for rewriting `v1/callit/{n}.json`); `track` = `ripples_track_record()` or null.
  * No live puzzle: `n:null`, `puzzle/reveal/callit:null`, `latest` = delayed.

## Ledger
`payload_hash = sha256(jsonb_build_object('n',n,'payload',payload,'reveal',reveal,'callit',[[qid,model_p],… ordered by qid])::text)` over the **stored** columns (before copy overlay);
`chain_hash = sha256(prev_hash || payload_hash)` (hex text concatenation); `prev_hash` = chain_hash of the highest earlier n, or 64 zeros for the first row. Live puzzles only. W2 may call `ripples._ledger_write(n)` at build time; it is idempotent.

## Privacy
`ripples._hash(text, day)` = `sha256(salt(day) || '|' || text)`; salts are 16 random bytes per UTC day, created lazily. IP = `cf-connecting-ip`, else the first `x-forwarded-for`; country = `cf-ipcountry` (2 letters). `ip_hash` uses today's salt; `client_hash` uses the salt of the **puzzle date**, so dedup per n is stable across days while hashes cannot be linked across puzzles.

## Internal helpers other workstreams may call (as postgres / security definer)
`ripples._cfg(key)`, `_epoch()`, `_current_date()`, `_current_n()`, `_visible(n)`, `_latest_live_n()`, `_cat(emoji)`, `_categories()`, `_wiki_url(title)`, `_puzzle_json(n)`, `_reveal_json(n)`, `_callit_json(n)`, `_stats(n,you)`, `_ledger_write(n)`, `_salt/_hash/_ip/_country/_rate`. None are executable by anon/authenticated (no schema usage).

## Answer hash
`answer_h = hex(sha256(utf8(n + '|' + i + '|' + qid)))`, e.g. `sha256("0|1|Q999990013")`. In SQL: `encode(extensions.digest(n||'|'||i||'|'||qid,'sha256'),'hex')`.

## Fixture n=0 (every title says "Test"; QIDs Q99999xxxx; news links on example.com)
3 rounds: 1 continues from the seed (answer c, **flowed** badge with a clickstream edge, one `cross` item), 2 continues from round-1's answer (answer a, "alongside", fluke 1 in 50, `shared_trigger_stop: true`), 3 is a **fresh ripple** from "Test Second Seed" (answer d, fluke meter warming up, `ai` caption, one `cross` item). Decoys are calm with flat sparks, medians within 0.5–2× the answer, ≥2 share the answer category. Call It: 1 hit, 1 miss, 2 pending. Board: big_wave ×2, sleeper, belly_flop, ripple, and one sensitive row with `quadrant: null`. `final_multiple` 3.8 (a perfect play scores 8/8).
