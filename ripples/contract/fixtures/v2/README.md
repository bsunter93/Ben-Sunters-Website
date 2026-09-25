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
  line, labelled); `null` when neither exists. The day `line` is WS-B's finalize day line (`source: "engine day line"`) or, when
  that key is absent, the sum over the listed lines (`source: "sum over listed lines"`).
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
`ripples.rm_contract_fixtures`): missing / extra keys and JSON type changes; `null` matches anything. `ok: true` is the
acceptance. `select * from ripples.rm_grant_audit();` must return zero rows.
