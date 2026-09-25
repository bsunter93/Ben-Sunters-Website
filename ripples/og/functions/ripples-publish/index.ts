// ripples-publish: mirrors the day's public JSON to Storage (SPEC §5.5, §10 Storage). Token-gated
// (x-collector-token, checked against the vault secret; verify_jwt is off by design, like the collectors).
//
// POST {}            -> ripples_publish_bundle(null): the newest live puzzle dated <= (UTC now - 7h20m)
// POST {"n": 12}     -> ripples_publish_bundle(12) (explicit n; also used for fixture n=0 / practice n<0 tests)
// POST {"prerender": false} skips the OG PNG pre-render.
// Idempotent: every object is upserted; re-running only refreshes files (late captions, callit outcomes).
import { createClient } from "jsr:@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const db = createClient(SB_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const BUCKET = "ripples";
const P = "v1/";
const CSV_COLS = ["date", "n", "round", "parent", "answer", "multiple", "z", "lag_days", "fluke", "p_time", "category"];

type Up = { path: string; body: string | Uint8Array; type: string; cache: number };

function csvCell(v: unknown): string {
  if (v === null || v === undefined) return "";
  const s = String(v);
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}
function toCsv(rows: Record<string, unknown>[]): string {
  return [CSV_COLS.join(","), ...rows.map((r) => CSV_COLS.map((c) => csvCell(r[c])).join(","))].join("\n") + "\n";
}
const json = (x: unknown) => JSON.stringify(x);

async function upload(u: Up): Promise<string | null> {
  const body = new Blob([u.body], { type: u.type });
  const { error } = await db.storage.from(BUCKET).upload(u.path, body, { upsert: true, contentType: u.type, cacheControl: String(u.cache) });
  return error ? `${u.path}: ${error.message}` : null;
}

async function pool<T, R>(items: T[], k: number, fn: (x: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(k, items.length) }, async () => {
    while (i < items.length) { const j = i++; out[j] = await fn(items[j]); }
  }));
  return out;
}

async function listData(): Promise<string[]> {
  const { data, error } = await db.storage.from(BUCKET).list(P + "data", { limit: 1000, sortBy: { column: "name", order: "desc" } });
  if (error || !data) return [];
  return data.map((o) => o.name).filter((n) => /^\d{4}-\d{2}-\d{2}\.json$/.test(n)).map((n) => n.slice(0, 10));
}

async function prerender(n: number, R: number): Promise<{ ok: string[]; err: string[] }> {
  const ok: string[] = [], err: string[] = [];
  const jobs: { q: string; path: string }[] = [{ q: `n=${n}`, path: `${P}og/${n}.png` }];
  for (let s = 0; s <= Math.min(4, R); s++) jobs.push({ q: `n=${n}&s=${s}`, path: `${P}og/${n}-s${s}.png` });
  await pool(jobs, 3, async (j) => {
    try {
      const r = await fetch(`${SB_URL}/functions/v1/ripples-og?${j.q}`);
      const variant = r.headers.get("x-card-variant") ?? "";
      if (!r.ok || r.headers.get("content-type") !== "image/png") { err.push(`${j.path}: og ${r.status}`); return; }
      if (variant === "brand") { err.push(`${j.path}: og returned the brand card (puzzle not visible yet), not stored`); await r.body?.cancel(); return; }
      const png = new Uint8Array(await r.arrayBuffer());
      const e = await upload({ path: j.path, body: png, type: "image/png", cache: 3600 });
      if (e) err.push(e); else ok.push(j.path);
    } catch (e) { err.push(`${j.path}: ${String(e)}`); }
  });
  return { ok, err };
}

Deno.serve(async (req: Request) => {
  const t0 = performance.now();
  const token = req.headers.get("x-collector-token") ?? "";
  const { data: authed } = await db.rpc("check_collector_token", { t: token });
  if (authed !== true) return new Response("forbidden", { status: 403 });
  // deno-lint-ignore no-explicit-any
  const b: any = await req.json().catch(() => ({}));
  let pn: number | null = null;
  if (b && b.n !== undefined && b.n !== null) {
    if (!Number.isInteger(b.n) || b.n < -60 || b.n > 9999) return Response.json({ ok: false, error: "invalid n" }, { status: 400 });
    pn = b.n;
  }
  const { data: bundle, error } = await db.rpc("ripples_publish_bundle", { p_n: pn });
  if (error) {
    const code = /too_early|not_publishable|not_found/.exec(error.message)?.[0] ?? "bundle_error";
    console.error("publish_bundle", error.message);
    return Response.json({ ok: false, error: code, detail: error.message }, { status: code === "bundle_error" ? 500 : 409 });
  }

  const n: number | null = bundle.n;
  const kind: string | null = bundle.kind;
  const ups: Up[] = [];
  // latest.json is always the real latest (delayed + previous puzzle, or delayed + null before launch)
  ups.push({ path: P + "latest.json", body: json(bundle.latest), type: "application/json", cache: 60 });
  if (n !== null && bundle.puzzle) {
    ups.push({ path: `${P}puzzle/${n}.json`, body: json(bundle.puzzle), type: "application/json", cache: 3600 });
    if (bundle.reveal) ups.push({ path: `${P}reveal/${n}.json`, body: json(bundle.reveal), type: "application/json", cache: 3600 });
    if (bundle.callit) ups.push({ path: `${P}callit/${n}.json`, body: json(bundle.callit), type: "application/json", cache: 300 });
    if (bundle.board) ups.push({ path: `${P}board/${n}.json`, body: json(bundle.board), type: "application/json", cache: 3600 });
  }
  // rewrite the Call It files of the last 8 published live puzzles (outcomes resolve on day +8)
  for (const rc of bundle.recent_callit ?? []) {
    if (rc && Number.isInteger(rc.n) && rc.callit && rc.n !== n) {
      ups.push({ path: `${P}callit/${rc.n}.json`, body: json(rc.callit), type: "application/json", cache: 300 });
    }
  }
  // board/latest.json = the latest VISIBLE live board (same rule as latest.json); never a fixture/practice board
  const { data: latestBoard } = await db.rpc("ripples_board", { p_n: null });
  if (latestBoard) ups.push({ path: P + "board/latest.json", body: json(latestBoard), type: "application/json", cache: 300 });
  ups.push({ path: P + "archive.json", body: json(bundle.archive ?? []), type: "application/json", cache: 300 });
  ups.push({ path: P + "track.json", body: json(bundle.track ?? null), type: "application/json", cache: 300 });
  // ledger rows in write order, exactly the shape `validate.py --ledger-chain ledger.json` reads; head = last row
  ups.push({ path: P + "ledger.json", body: json(Array.isArray(bundle.ledger) ? bundle.ledger : []), type: "application/json", cache: 300 });

  // open data (CC BY 4.0): live puzzles only, Wikimedia-derived columns only (csv_rows never carries cross/Google data)
  const rows: Record<string, unknown>[] = Array.isArray(bundle.csv_rows) ? bundle.csv_rows : [];
  let dataDate: string | null = null;
  if (kind === "live" && n !== null && rows.length) {
    dataDate = String(bundle.date);
    const cite = `Knock-On / Today's Ripples, bensunter.com/ripples, ${dataDate}, method v5.0`;
    const doc = {
      date: dataDate, n, method: "5.0", license: "CC BY 4.0", citation: cite,
      source: "Derived from Wikimedia pageviews (agent=user) and Wikipedia link structure. Wikimedia-derived fields only.",
      columns: CSV_COLS,
      rows: rows.map((r) => Object.fromEntries(CSV_COLS.map((c) => [c, r[c] ?? null]))),
    };
    ups.push({ path: `${P}data/${dataDate}.json`, body: json(doc), type: "application/json", cache: 3600 });
    ups.push({ path: `${P}data/${dataDate}.csv`, body: toCsv(rows), type: "text/csv; charset=utf-8", cache: 3600 });
  }

  const errors = (await pool(ups, 6, upload)).filter((e): e is string => !!e);

  // data/index.json (list of open-data days), rebuilt from the bucket listing
  if (dataDate) {
    const days = await listData();
    if (!days.includes(dataDate)) days.unshift(dataDate);
    const e = await upload({ path: P + "data/index.json", body: json({ license: "CC BY 4.0", days: days.sort().reverse() }), type: "application/json", cache: 300 });
    if (e) errors.push(e);
  }

  let og: { ok: string[]; err: string[] } = { ok: [], err: [] };
  if (n !== null && b?.prerender !== false) {
    const R = Array.isArray(bundle.puzzle?.rounds) ? bundle.puzzle.rounds.length : 4;
    og = await prerender(n, R);
  }
  const res = {
    ok: errors.length === 0, n, kind, date: bundle.date ?? null, latest_status: bundle.latest?.status ?? null,
    uploaded: ups.map((u) => u.path).filter((p) => !errors.some((e) => e.startsWith(p + ":"))),
    og: og.ok, og_skipped: og.err, errors, ledger_head: bundle.ledger_head ?? null,
    ms: Math.round(performance.now() - t0),
  };
  console.log(JSON.stringify({ ...res, uploaded: res.uploaded.length }));
  return Response.json(res, { status: errors.length ? 207 : 200 });
});
