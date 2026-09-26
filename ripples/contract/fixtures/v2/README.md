# Ripple Map v2 contracts (WS-C)

The JSON every Ripple Map page reads. Storage first (`ripples/v2/…`), RPC fallback with the identical shape.
Synthetic fixtures for every contract sit next to this file; WS-D builds against them. Implementation:
`ripples/contract/sql/06_rm_public_rpcs.sql` (Supabase project `kffkasnzqcddpystszch`).

The fixtures are **invented numbers** ("Hurricane Polo" does not exist). Never ship them or fall back to them.

## Routes, Storage paths, RPCs

| Page | Storage (public bucket `ripples`) | Cache | RPC fallback (anon) | Fixture |
|---|---|---|---|---|
| Home, departures | `v2/shocks/latest.json`, `v2/shocks/{day}.json` | 60 s / 1 h | `rm_shocks(p_day date default null)` | `shocks.json` |
| Line (live) | `v2/cascade/{event_id}.json` | 300 s | `rm_cascade(p_event, null)` | `cascade-1201.json` |
| Line version k (shared) | `v2/cascade/{event_id}/v{k}.json` (immutable) | 1 y | `rm_cascade(p_event, k)` | `cascade-1201-v2.json` |
| Stop / evidence card | `v2/hop/{hop_id}.json`, `v2/hop/{hop_id}.csv` | 1 h | `rm_hop(p_hop)` | `hop-9001.json`, `hop-9006-retracted.json` |
| Lands (8 domains) | `v2/lands/{domain}.json` | 300 s | `rm_lands(p_domain, p_days default 30)` | `lands-real_world.json` |
| Map, archive | `v2/archive.json` | 300 s | `rm_archive(p_days default 90, p_status default null)` | `archive.json` |
| Week | `v2/week/{yyyy-ww}.json` | 300 s | `rm_week('YYYY-WW')` | `week-2026-39.json` |
| Methods / Receipts | `v2/calibration.json` | 1 h | `rm_calibration()` | `calibration.json` |
| Health | `v2/health.json` | 60 s | `rm_health()` | `health.json` |
| Count-only event | (none) | | `rm_event(p_kind, p_src, p_client)` POST | `event.json` |
| Feeds | `v2/feed/shocks.xml`, `v2/feed/line-{event_id}.xml` | 300 s | | |
| Calendars | `v2/ics/hop-{hop_id}.ics`, `v2/ics/line-{event_id}.ics` | 1 h | | |
| Open data (CC BY 4.0) | `v2/data/{date}.csv`, `.json`, `v2/data/index.json` | 1 h | | |
| OG PNGs | `v2/og/brand.png`, `line-{e}-v{k}.png`, `stop-{h}.png`, `shock-{day}.png`, `week-{yyyy-ww}.png` | | `ripples-og?v=…&e=&k=&h=&w=` | |

Public slugs are `{label-kebab}-{event_id}`; the trailing id is the key (`ripples.rm_event_from_slug`). Routes:
`/ripples/line/{slug}/`, `/ripples/line/{slug}/v{k}/`, `/ripples/line/{slug}/stop/{hop_id}/`, `/ripples/lands/{domain}/`,
`/ripples/week/{yyyy-ww}/`.

## Decisions the specs left open (binding for WS-D)

* **Domains** are the eight EXPERIENCE §3 codes: `reading chatter markets builders real_world jobs institutions stuff`
  (WS-B's finer codes are folded: search→reading, social/news→chatter, economy→markets, consumption→stuff).
* **Visibility.** A line is public once it has a frozen version. Decoy events and their hops are never addressable (every RPC
  returns `null`); they appear only as the aggregated `control` object. Negative-control hops are never addressable.
  Real lines publish automatically; reconstructed (library / control) lines publish when WS-E adds them
  (`ripples.att_publish_cascade(event_id)` or `att_publish_cascades(day, array[ids])`).
* **Versions.** `att_publish_cascade` freezes a new version only when the line's *substance* changes (tiers, multiples, q, p, f,
  due dates, status, denominators, flat stubs…). Sparklines and bands are excluded from the hash, so a new day of data alone
  never mints a version. Frozen rows are immutable (trigger). Every version is a ledger `version_publish` row (`ledger.seq`).
* **grown_since** (in every frozen document) compares this version with the previous one: `{"version": k-1, "stops_added": n}`,
  `null` for v1. **grown_to** is `null` in Storage files; `rm_cascade(e, k)` for an older k fills it live:
  `{"version": latest, "stops_added": n, "url": live line}`. From Storage, compute it by comparing `v{k}.json` with
  `cascade/{id}.json` (`stops` = Measured + Likely nodes). `stops_added` can be negative after a retraction.
* **text_share** follows EXPERIENCE §7 (emoji line, count line, "consistent with, not proof of cause", the v{k} URL);
  **text_plain** is the accessible variant. Both are frozen with the version.
* **sensitive** = the engine's flag OR any `hazard.*` family (quiet mode: no shock card, no playful copy, no Wander landing).
* **hero** in ShockList is WS-E's `att_hero_pick` (live line with a Measured outcome stop, else the best reconstructed archive
  line, labelled); `null` when neither exists. The day `line` is WS-B's finalize day line (`source: "engine day line"`); when that
  key is absent every number in `line` is `null` and `source` is `"not available"` (render "today's tests are not in yet", never
  a number). `listed_lines_sum` is a separate object: the sum of the listed lines' denominators over **all their days**, with
  `lines` and a `scope` sentence. Never label it as today's tests.
* **biggest_in_days** comes with `biggest_basis`: `days_since_higher` (the number is how long since the attention series was last
  this high), `highest_in_window` (`biggest_in_days` is null and `biggest_window_days` says how many stored days it beats; render
  "highest in the {n} days we store", never "a record"), or `no_data` (render nothing).
* **Public names (added 2026-09-26).** A stop is shown only under a human name. A node whose label is still a raw Wikidata QID is
  held back together with its subtree and counted in `held_back: {stops, flat, reason: "waiting for a public name"}` (render
  "{n} more tested paths are not listed yet: waiting for a public name"). If a Likely-or-better stop has no name the line's next
  version is held instead. Names come from the article / topic titles or Wikidata labels (`att_wd_claims`, filled by WS-A's
  att-wikidata once its Wikimedia contact gate opens); the stop then appears in a new version.
  The same rule covers source-local nodes (`source:key`): a bare key is an identifier, not a name (`e:1061358`, `topic:403`,
  `DGS10`, `CISO`, `__total__`). Such a node is shown only under a curated name from `ripples.rm_node_names` (284 rows, each with
  its `basis`, e.g. `fred:DGS10` → "10-year Treasury yield", `eia.930:CISO` → "California ISO power grid") or a WS-B label that
  is not its own key; otherwise it is held back and counted like an unnamed QID. Polymarket event/market ids have no stored
  title, so they are always held back.
* **Due dates are never in the past when published.** A `due` that has already passed while the window is still open moves to
  the next scheduled look on or after the publish day, or `null`. Frozen versions age, so clients still compare `due` with today.
* **Withheld versions.** Versions whose public text carried raw identifiers (QIDs, or source keys since the second 2026-09-26
  fix; the audit re-checks every public version whenever the guard learns a pattern) are withheld: they stay frozen in the
  database and the ledger (a `version_publish` row with `withheld: true`), but `rm_cascade(e, k)` returns `null` for them, their
  Storage files and cards are removed, and no stub, feed item or card points at them. Version numbers therefore have gaps
  (a line's first public version may be v3). `grown_since` compares with the previous **public** version.
* **Closed windows.** Every node carries `window_closed` (its `window_close` is before the day the version was built). A closed
  Watching stop reads in the past tense ("Its window closed {date} before enough data arrived to test it; the result is
  pending." / "… with no measurable move so far; the final look is pending."), has `due: null`, is never in `next_due`, never
  gets a calendar file, and is not drawn as an upcoming (dashed) stop on cards. HopEvidence `look` adds `window_close` and
  `window_closed` (`next` is `null` once the window closed). Both keys are absent from versions frozen before 2026-09-26.
* **Units.** `unit: "points"` (rate series: unemployment rate, a market's probability) means `rho` is a difference in points,
  not a multiple: write "0.40 points above its normal", never "0.40×". Lands rows carry `unit` too.
* **Node fields** beyond ENGINE §11: `unit` (`x` or `points` for rate series), `p_hat` (a Watching stop's pre-registered base
  rate), `path` (public wording, source-labelled; internal edge metadata never leaves the DB), `sentence` (ENGINE §8 template).
  Flat stubs carry `hop_id`, `rho` (window-average multiple) and a `spark`.
* **HopEvidence** extras: `q1_normal.from/unit`, `q3_who.channels[].sources`, `q3_who.excluded[]` objects, `q4_why.rival_note`,
  `math.z_by_source` keyed **by channel** (the engine stores per-channel combined ž and the best single series, not per-source z),
  `math.q/p_h/look_day/fails`, `sr_sentence` (the one screen-reader sentence). `bh.rank` is recomputed among the tests of the
  same finalize (same look day and m). `rho1` is `null` (not stored by the engine).
* **Calibration** is WS-B's `att_calibration_public` payload passed through (fixture mirrors its real structure); WS-E adds an
  `archive` section.
* **Week** is WS-E's `att_week_editions` payload, slugs rewritten to public slugs; lines are `{…, stops: {measured, likely,
  watching, flat}, domains, …}`. Without an edition: `ripple_of_week: null`, `note: "No edition for this week yet."`.
* **rm_archive(p_days)** counts days from a line's first publication (reconstructed lines published at launch are listed);
  `p_days = null` returns every public line. `v2/archive.json` is the full list.
* **Count-only events** (`rm_event`): `kind ∈ {share_tap, landing}`, `src` matches `^[a-z0-9_-]{1,24}$` (else `other`), `client`
  is the browser's random `ko.client` id (`^[A-Za-z0-9_-]{8,64}$`). Stored: a per-day count and a same-day unique count per
  kind × src. The client id is hashed with a daily salt that is deleted with the day and the hashes are purged after 2 days. No IP,
  no page URL, no user agent. Capped at 50,000 events a day.
* **Privacy line** (for WS-D's pages; replaces the v5 line): "We keep no accounts and no play history. If you tap Share or arrive
  from a shared link, we count it: a daily count per source, with a random browser ID hashed under a salt we delete each day. No
  IP address, no page history. Waitlist emails are stored only for that list and can't be read back through the site. Your theme,
  last visit and private hunches stay in your browser."

## Stub contract (ripples/tools/gen-stubs.mjs)

The generator writes `line/{slug}/`, `line/{slug}/v{k}/`, `line/{slug}/stop/{hop}/`, `lands/{domain}/`, `week/{yyyy-ww}/`
stubs from WS-D's shells (`ripples/line/index.html`, `lands/index.html`, `week/index.html`; a built-in page until they exist).
It replaces `<title>`, description, canonical, og:* and twitter:* (with `og:image:alt`), inserts
`<script type="application/json" id="rm-data">` (the route's document: cascade, frozen version, HopEvidence, lands or week) before
`</head>`, puts the no-JS stop list between `<!--rm:nojs-->` and `<!--/rm:nojs-->` (or right after `<body>`), and sets
`data-route/event/version/hop/domain/week` on `<body>`. Version stubs carry the canonical of the live line (indexable; the canonical folds duplicates).
`--check` validates each stub (own head, ≤ 300 KB, no-JS list, footer line, no causal words). Run it after each publish
(GitHub Action or by hand): `node ripples/tools/gen-stubs.mjs --check`.

## Tests

`select ripples.rm_contract_test();` diffs every RPC's live output against these fixtures (loaded, arrays truncated, in
`ripples.rm_contract_fixtures`): missing / extra keys and JSON type changes; `null` matches anything. Because a null matches
anything, each result also carries `coverage: {compared, vacuous, vacuous_paths}`: the fixture fields the live data actually
filled and the ones it left null or empty (unchecked). Part 2 (`synthetic`) builds a line from `cascade-1201.json` inside a
rolled-back block (Measured, Likely, retracted, provisional depth-2, flat stubs, a rate-unit Measured stop, a closed and an
open Watching window, an unnamed QID stop with a child), diffs it strictly and asserts the wording rules (points not ×, past
tense after the window, held-back names, no raw identifiers, both fluke labels, rows gone after rollback). `ok: true` needs the
live diffs, the synthetic diffs and every assert to pass. `select * from ripples.rm_grant_audit();` must return zero rows; every
publish also runs `ripples.rm_enforce_grants()`, which revokes anything the audit lists (e.g. after an older SQL file is
re-applied) and reports the count as `grants_fixed`.

## Stories (story layer, 2026-09-26; OWNER_DECISIONS D-14/D-15/D-16)

| Page | Storage | RPC (anon) | Fixture |
|---|---|---|---|
| Home featured list, weekly edition supporting stories, Wander | (none yet; RPC only) | `rm_stories(p_limit default 12, p_days default 90, p_kind default null)` — `p_kind` ∈ `cascade`, `watching`, `non_event`, `pattern` | `stories.json` |

`rm_stories` is a **separate RPC** (the existing payloads' contract test reports extra keys, so nothing was added to `rm_cascade`/`rm_hop`).
It returns `{v, as_of, rule, featured[], counts, pool, note}`; every `featured[]` item has the same keys whatever its `kind` (`event`, `hero`,
`pattern`, `watching`, `replication` are `null` where the kind has none). Binding reading rules:

* `tier` is the **public** tier (engine tier after the BigQuery forecast gate); `engine_tier` is the engine's; when they differ `demoted` is
  true and `gate_reason` says why. Story fields (`scores`, `archetype`, `story_sentence`, …) never change a tier — render the tier from `tier` only.
* `graph.edges[].kind` is `chain` (event → A → B) **only** when the engine's mediation check supports A → B; otherwise `fork` (event → A,
  event → B) and `mediation_supported` is false. Never draw a fork as a chain.
* `story_sentence`, `short_title`, `conversation_hook` (null in quiet mode), `share_line` are first-class copy from the DB: use them for hero
  copy, share text, OG metadata and the weekly headline; never compose them in the frontend.
* `travel` = "How far did it travel?" (`domains_crossed`, `days`, `depth`). `next` = rabbit-hole pointers (`same_event`, `same_stop`,
  `stop_connections`, `same_domain`, `one_more`). `share` = canonical `slug`, frozen line `version`, `created_at`, `grown_since`, `og`, `reopen`.
* `archetype` ∈ Detour, Echo, Delay, Funnel, Bounce, Amplifier, Blind Spot, Branch, Shared Stop, Dead end (= Collapse), Ghost, or null
  ("Ripple"); presentation label only. Watching stories carry no archetype; `watching` holds `window_close`, `next_look`, `days_to_resolve`,
  `p_hat`, `expected_1_in` ("expected to resolve in N days; we expect a move about 1 in K times").
* `kind = pattern` items are engine-6.2 family patterns (`pattern.*` mirrors `rm_patterns`); `kind = non_event` items are pre-registered expected
  stops that stayed flat ("the ripple that died"); `is_control` items are never returned.

Test: `select ripples.rm_story_contract_test();` (shape diff against `stories.json`, leak guard, causal-word lint, gate reasons) and
`select ripples.att_test_story();` (T30–T37 invariants).
