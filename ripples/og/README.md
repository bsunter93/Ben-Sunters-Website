# Knock-On v5: share cards, Storage publishing and the Bluesky bot (W4)

Supabase project `kffkasnzqcddpystszch`. SPEC §5.5, §9, §10 (Storage). The contract (RPC shapes, visibility, ledger)
is in `../contract/README.md`.

## Files

| Path | Deployed as | What |
|---|---|---|
| `functions/ripples-og/index.ts` | edge function `ripples-og`, verify_jwt **false** (public GET) | 1200×630 PNG share cards |
| `functions/ripples-publish/index.ts` | `ripples-publish`, verify_jwt false, **token-gated** (`x-collector-token`) | mirrors `ripples_publish_bundle` to Storage `ripples/v1/`, pre-renders OG PNGs |
| `functions/ripples-bot/index.ts` | `ripples-bot`, verify_jwt false, token-gated | posts yesterday's reveal card to Bluesky; `{"skipped":true}` without vault secrets |
| `functions/probe-gone/index.ts` | deployed over `probe-og`, `probe-og2`, `probe-sources` | 410 `gone` stubs |
| `sql/01_ripples_v5_w4_bot.sql` | migration `ripples_v5_w4_bot` (applied) | `ripples.bot_posts`, `public.ripples_bot_context()`, `public.ripples_bot_log(...)` (service_role only) |
| `sql/02_ripples_v5_w4_cron.sql` | migration `ripples_v5_w4_cron` (applied 2026-09-25) | the four pg_cron jobs (SPEC §5.5); migration `ripples_v5_w4_cron_spec4` removed an earlier extra `ripples-publish-0731` |
| `sql/03_ripples_v5_w4_bot_guard.sql` | migration `ripples_v5_w4_bot_guard` (applied) | `ripples_bot_context()`: no target while yesterday's puzzle is still being served |

The MCP deploy uploads only the files listed in the call, so each function is a single self-contained `index.ts`.
Redeploy with `deploy_edge_function` (name = the function, `verify_jwt: false`, one file `index.ts`).

## ripples-og (SPEC §9)

`GET …/functions/v1/ripples-og?n={n}&s={s}&v={variant}`

* **Input is IDs only.** `n` must match `^-?\d{1,4}$` and lie in −60..9999; `s` must be an integer (clamped to 0..4,
  then to the puzzle's R); `v` ∈ `teaser|result|reveal|board|latest|brand`. Any other parameter is ignored (there is
  no text parameter). A malformed `n`/`s`/`v` renders the **brand** card, status 200.
* Default variant: `teaser` when `n` is given, `result` when `s` is also given, `brand` with no `n`.
* **Data**: `ripples_og_data(n)` (service RPC) via `SUPABASE_SERVICE_ROLE_KEY`; the board variant reads
  `ripples_board(n)` (latest visible live board when `n` is absent). A puzzle that is not visible (future, not
  published, vetoed, unknown n) renders the brand card.
* **Spoilers**: `reveal` renders only when `og_data.past` is true (W1: `puzzle_date` < current puzzle date, 07:30 UTC
  rollover); otherwise it falls back to the teaser. Exception: the fixture n=0 (TEST data whose answers are already
  public in `contract/fixtures/`) may render its reveal so the card can be tested before launch.
* **Watermarks**: fixture → big faint "TEST" + "TEST · fixture data" pill; practice → "PRACTICE" + "PRACTICE ·
  reconstructed"; reserve-bank puzzles → "From {from_date}" pill.
* **Every card** has the footer `bensunter.com/ripples · Measured attention, not proof of cause.` Numbers on the
  reveal and board cards carry a legend naming the baseline ("peak daily Wikipedia views vs the page's own 91-day
  baseline"). Sensitive board rows (`sensitive: true` or `quadrant: null`) never appear on the board card.
* **Headers**: `image/png`; `Cache-Control: public, max-age=86400` when the puzzle has passed, `max-age=3600`
  otherwise (brand for bad input 3600, `v=brand` 86400, and **300** when a valid n is not visible yet or the data read
  failed, so a crawler does not keep a brand card for a puzzle that goes live minutes later);
  `Access-Control-Allow-Origin: *`; `X-Card-Variant` (the variant actually rendered), `X-Card-Source`
  (`storage` or `render`) and `X-Render-Ms`.
* **Render budget (the endpoint is public and not rate-limited).** Every request is planned first (RPC visibility
  checks, cheap). Then:
  * teaser, result, latest and brand cards are served from the PNGs `ripples-publish` pre-rendered into Storage
    (`v1/og/{n}.png`, `v1/og/{n}-s{s}.png`, `v1/og/brand.png`) when the file exists. No WASM, fonts or render run.
    The bytes are identical to a fresh render (md5 checked against the verifier's renders).
  * Otherwise the card is rendered and cached per isolate: the brand card once per isolate, other cards by canonical
    key (variant, n, clamped s) for 5 minutes (at most 48 entries).
  * So every invalid, unknown or not-yet-visible URL costs one RPC plus one Storage read. Only reveal and board cards
    of visible puzzles (about 2 per puzzle) always render on a cold isolate. Each distinct URL is still one request
    to the function (the CDN keys on the full URL); there is no rate limit.
  * `&fresh=1` bypasses Storage only with a valid `x-collector-token`. `ripples-publish` uses it so that it
    re-renders rather than copying the stored file it is replacing.
* **Test mode**: `&b64=1` returns the PNG as base64 `text/plain` (no-store) only when the `x-collector-token` header
  matches the vault secret (`check_collector_token`); without it the parameter is ignored and a PNG is returned.
* **Stack**: `npm:satori@0.10.14` + `npm:@resvg/resvg-wasm@2.6.2`; WASM and full Inter v3.19 Regular + ExtraBold from
  jsDelivr, cached per isolate (a failed init is retried on the next request). Emoji via `loadAdditionalAsset` →
  `cdn.jsdelivr.net/gh/jdecked/twemoji@latest/assets/svg/{codepoint}.svg` (FE0F dropped unless a ZWJ sequence;
  missing emoji → blank, never tofu). Scripts Inter lacks (JP, SC, KR, Devanagari, Arabic, Hebrew, Thai, Bengali,
  Tamil, symbols, math) load a Noto Sans subset from `cdn.jsdelivr.net/npm/@fontsource/…@5` on demand (file names
  taken from the jsDelivr package listings; the Arabic, Hebrew, Thai, Devanagari, Bengali, Tamil, symbols and math
  files fetched 200 `font/woff`; no non-Latin title has been rendered yet because no such data exists). Cold render ≈ 0.8–1.1 s, warm ≈ 0.5 s; a card served from Storage ≈ 0.25–0.65 s; a warm cached brand card ≈ 0.1 s (measured over pg_net, 2026-09-25).
* If rendering fails the function retries with the brand card; only if that also fails (jsDelivr unreachable) does it
  return 503 `no-store`.

### Card design (1200×630, petrol `#0B3A40` ground, marigold `#E0A33C` figures, cream `#F4EEE1` text, Inter)

| Variant | Content |
|---|---|
| teaser / latest | header `KNOCK-ON #n` + date (+ watermark pill); seed emoji + title; **"Biggest day in N days"** (or "since records began"); "41× its normal Wikipedia readers · 6 languages"; right: "Where did the internet go next?"; path row: seed tile → emoji-over-"?" tiles, a fresh ripple is a dot + "NEW" seed tile |
| result (`s`) | as teaser, right block: big "s of R", "Found s of R first try", "Can you beat it?". Only the count is shown (the share link carries only `s`, so no grid order is invented) |
| reveal | "THE TRAIL": seed row + one row per round (arrow, or dot + fresh-seed emoji), emoji, title, "6.2× normal"; baseline legend |
| board | top 5 non-sensitive rows by splash: emoji, title, splash ×, wake k/20, quadrant pill; legend |
| brand | "One trend. Where did the internet go next?" + the hook line + a generic 👤→📍→🎬→🍎 path |

Checked renders from this build (fixture n=0): `scratchpad/v5/og_check_teaser_v1.png`, `og_check_result_s2_v1.png`,
`og_check_hacked_v1.png` (n=abc&text=HACKED → brand), `og_check_reveal_v2.png`, `og_check_board_v2.png`,
`og_check_brand_v2.png`. Re-checked 2026-09-25 against the deployed build: `og_check_teaser_r3.png`,
`og_check_result_s2_r3.png`, `og_check_hacked_r3.png`, `og_check_reveal_r3.png`, `og_check_board_r3.png`.

## ripples-publish

`POST …/functions/v1/ripples-publish` with `x-collector-token` (use `select public.call_collector('ripples-publish', '{}')`).
Body `{}` → `ripples_publish_bundle(null)`; `{"n": 12}` → explicit n (fixture `0` / practice `n<0` for tests);
`{"prerender": false}` skips PNGs. Errors from the bundle: `too_early` / `not_publishable` / `not_found` → 409
`{"ok":false,"error":…}`; a bad `n` → 400; a wrong token → 403. Returns
`{ok,n,kind,date,latest_status,staged,board_latest_removed,uploaded[],og[],og_skipped[],errors[],ledger_head,ms}`
(207 if any upload failed).

### Storage layout (bucket `ripples`, public, CDN-cached)

| Path | Written when | Cache-Control |
|---|---|---|
| `v1/latest.json` | every run: `bundle.latest` = `ripples_latest()` (always the real latest: delayed + previous puzzle, or `n:null` before launch). Shape `{n,date,puzzle,status,next_at}`; `date` is the current puzzle date | `max-age=60` |
| `v1/puzzle/{n}.json`, `v1/reveal/{n}.json` | bundle has a puzzle | 3600 |
| `v1/callit/{n}.json` | that n, plus the last 8 published live puzzles (`recent_callit`), rewritten every run until resolved | 300 |
| `v1/board/{n}.json` | that n's board (any kind) | 3600 |
| `v1/board/latest.json` | `ripples_board(null)`: the latest **visible live** board. Never a fixture/practice board. **Absent** before launch, and **deleted** by the staged 07:25 run until the 07:45 run rewrites it. While it is absent, `load()` falls back to `ripples_board()` | 300 |
| `v1/archive.json` | every run (`ripples_archive(500,'all')`) | 300 |
| `v1/track.json` | every run (`ripples_track_record()`, `null` until W3 deploys it) | 300 |
| `v1/ledger.json` | every run: `bundle.ledger`, a plain array in write order, i.e. exactly what `validate.py --ledger-chain ledger.json` reads | 300 |
| `v1/data/{date}.json`, `v1/data/{date}.csv`, `v1/data/index.json` | live puzzles with `csv_rows` only. **CC BY 4.0**, Wikimedia-derived columns only: `date,n,round,parent,answer,multiple,z,lag_days,fluke,p_time,category`; the JSON adds `license`, `citation`, `columns`, `rows` | 3600 / 300 |
| `v1/og/{n}.png`, `v1/og/{n}-s{0..R}.png`, `v1/og/brand.png` | pre-rendered by calling `ripples-og?…&fresh=1` with the token over HTTP (each render gets its own isolate and CPU budget). A render that comes back as the brand card (puzzle not visible yet, e.g. the 07:25 run before the 07:30 rollover) is **not stored**; the 07:45 run stores it | 3600 |

Only `v1/data/*` is open data. `puzzle/`, `reveal/`, `board/`, `latest.json` can carry non-Wikimedia `cross` items and
are **not** CC BY (contract README, SPEC 12.9).

Notes for readers of these files:
* Files are jsonb-equal to the RPC output, not byte-equal: supabase-js re-serialises numbers (`1.0` → `1`). Compare
  with jsonb `=`, not md5. The ledger hash is unaffected (it canonicalises numbers through float8).
* A missing object returns HTTP 400 with `{"statusCode":"404","error":"not_found"}`; treat any non-200 as missing and
  fall back to the RPC.
* **Staged 07:25 run (no early spoilers, SPEC §12).** The 07:25 run marks today's puzzle published and ledgers it,
  but the puzzle only becomes visible at the 07:30 rollover. While `latest.n < n` the response says `"staged":true`
  and the run writes **no** per-puzzle file for today: no `puzzle|reveal|callit|board/{n}.json`, no
  `data/{date}.json|.csv` (the CSV has the answer column) and no OG PNGs. It refreshes only `latest.json` (still
  yesterday's, `next_at` = today 07:30), archive, track, ledger and older Call It files, and it **deletes**
  `board/latest.json` (`"board_latest_removed":true`). From 07:30 to 07:45 the client
  reads the RPCs: `getLatest()` re-reads `ripples_latest` once `next_at` has passed, and `load()` falls back to the RPC
  for any missing file. That includes `board/latest.json`, so the board follows the rollover through
  `ripples_board()`. The deleted file's 300 s CDN cache runs out by 07:30. The 07:45 run mirrors everything.
* The fixture files (`v1/*/0.json`, `v1/og/0*.png`) are in the production bucket because W4 acceptance requires
  publishing n=0 under `v1/`. They are TEST data (every title says "Test", watermark on every card) and nothing links
  to them. Remove them with the Storage dashboard if unwanted; the next fixture test re-creates them.

## ripples-bot

`POST …/functions/v1/ripples-bot` with the token (`call_collector('ripples-bot','{}')`), daily at 07:35 UTC.
* **Posting is off (OWNER_DECISIONS D-3, deferred to v5.1).** `POSTING_ENABLED = false`, so every normal call,
  including the 07:35 cron job, returns `{"skipped":true,"reason":"deferred_v5_1"}` and posts nothing. The owner posts
  by hand for the first 14 days; `{"dry_run":true}` gives the ready-made text, alt text and reveal image check.
  To switch on in v5.1: set `POSTING_ENABLED = true`, redeploy, add the two vault secrets. The rest of this section
  describes the behaviour once switched on.
* Reads `ripples_bot_context()`: the vault secrets `bsky_handle` + `bsky_app_password` (returned only when both
  exist), the target = the live **published** puzzle dated the day before the current puzzle date whose
  `ripples_og_data(n).past` is true (so it never posts a puzzle that is still current), today's `social` copy, and
  whether that n was already posted.
* No secrets → `{"skipped":true,"reason":"no_secrets"}` (logged). No passed puzzle → `{"skipped":true,"reason":"no_target"}`.
* Text: the `social` copy row stored under **today's n** (SPEC §11: the Routine writes "about yesterday's reveal"
  while captioning today's puzzle), `+ "\nbensunter.com/ripples"`, clipped to 300 graphemes. It falls back to the
  template if the copy is missing, contains a URL, or trips the SPEC 12.1 lint (`CAUSAL_RE`/`FLOW_RE` from
  `contract/tools/validate.py`). Template: `Yesterday's Knock-On #{n}: {seed} → {answer} → … · … → {answer}.
  Measured attention, not proof of cause. Play today: bensunter.com/ripples` (clipped to fit 300 graphemes).
  A link facet covers `bensunter.com/ripples`.
* Image: `ripples-og?n={n}&v=reveal`, only if the function really returned the `reveal` variant. Alt text lists the
  chain and the disclaimer.
* Bluesky: `com.atproto.server.createSession` on `https://bsky.social` → the PDS from the session's `didDoc`
  (falls back to bsky.social) → `com.atproto.repo.uploadBlob` → `com.atproto.repo.createRecord`
  (`app.bsky.feed.post` with an `app.bsky.embed.images` embed, aspect ratio 1200×630).
* One post per n: `ripples_bot_log(n,'claim')` inserts a claim first; `posted` stores the at-uri; `failed` stores the
  error and lets the next run retry. A claim older than 10 minutes can be re-claimed.
* `{"dry_run": true}` builds text, facets, alt and fetches the image without logging in or posting (works without secrets).

## pg_cron (UTC), in `sql/02_ripples_v5_w4_cron.sql` (applied)

| Job | Schedule | Command |
|---|---|---|
| `ripples-publish-0725` | `25 7 * * *` | `select public.call_collector('ripples-publish', '{}'::jsonb)` |
| `ripples-publish-0745` | `45 7 * * *` | same |
| `ripples-publish-0830` | `30 8 * * *` | same |
| `ripples-bot-daily` | `35 7 * * *` | `select public.call_collector('ripples-bot', '{}'::jsonb)` |

## Runbook

* **Republish by hand**: `select public.call_collector('ripples-publish', '{}'::jsonb);` then read the response:
  `select status_code, content from net._http_response where id = <returned id>;`
* **Test a card**: `select net.http_get('https://kffkasnzqcddpystszch.supabase.co/functions/v1/ripples-og?n=12&s=2');`
  check `status_code` and `headers->>'x-card-variant'`. For the PNG bytes add `&b64=1` with header
  `x-collector-token` from the vault, then check `substring(decode(content,'base64') from 1 for 8)` = `\x89PNG…` and
  the IHDR width/height at bytes 17–24.
* **Bot dry run**: `select public.call_collector('ripples-bot', '{"dry_run":true}'::jsonb);`
* **Enable the bot (v5.1, D-3)**: set `POSTING_ENABLED = true` in `functions/ripples-bot/index.ts` and redeploy, then add
  vault secrets `bsky_handle` (e.g. `knockon.bsky.social`) and `bsky_app_password` (an app password, not the account
  password): `select vault.create_secret('<value>', 'bsky_handle');` etc. Remove either secret to stop posting.
* **Probe cleanup**: `probe-og`, `probe-og2` and `probe-sources` now return **410 gone** (verify_jwt false so the 410
  is visible). The Supabase MCP has no delete tool: **the owner must delete them in the dashboard** (Edge Functions →
  function → Delete), together with `probe-cors`. Its deployed source (v2, read with `get_edge_function`) is
  `Deno.serve(() => new Response('gone', { status: 410 }))`. It keeps verify_jwt true, so an anonymous GET gets a 401
  from the gateway before it reaches the stub. `probe-att-*` and `probe-holes-*` belong to the
  attention team and were left untouched.

## Owner actions

1. Delete `probe-og`, `probe-og2`, `probe-sources` and `probe-cors` in the dashboard (the MCP has no delete tool).
2. For v5.1 only: create the Bluesky account, add vault secrets `bsky_handle` + `bsky_app_password`, and set
   `POSTING_ENABLED = true` in `ripples-bot`.
3. The cron jobs are live. To pause publishing: `select cron.unschedule('ripples-publish-0725');` (etc.). Without the
   publish jobs no live puzzle is ever marked `published`, so the page stays on "delayed".
