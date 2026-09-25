// att-news — news and TV attention collector for the Ripples v5 attention layer (W7).
// Modes (§3.3 / §7.3):
//   gkg       one GDELT GKG 2.1 raw 15-minute file per run (lastupdate.txt, or the next file after att_state
//             'gkg.state' while catching up). Stream-unzips it and counts, per registry term, the documents whose
//             V1Persons / V1Organizations / V1Locations / AllNames (or V1Themes for theme keys) mention it, with the
//             number of distinct source countries (ccTLD of SourceCommonName) as aux; a '__total__' series (documents);
//             the top 200 surging entities (vs an EWMA baseline per file) as discovery candidates; and co-mention pairs
//             where one side is an active topic as att_edges. Never calls the GDELT DOC API (RED for us).
//   thirdeye  IA TV News Archive Third Eye chyrons (archive.org/services/third-eye.php?last=N). Chyron-minutes per
//             registry term per channel for every complete hour in the window; same-hour term co-occurrence edges.
//   sitemaps  BBC, NYT, Guardian and Fox news sitemaps: headline counts per registry term per day, number of outlets
//             (aux), per-outlet totals, 'newsroom' co-mention edges, and cross-outlet news:keywords candidates.
//   backfill  GKG history sampling is not enabled on the free tier (§3.6: GKG enters at 28 days like other warm-up
//             sources); jobs are marked skipped.
//   ping      no outbound calls.
// Stored: counts, ranks and indices only. No headline, chyron or article text, no URLs, no personal data.
import { politeFetch, type Run, serve, stateGet, stateSet, db, jobsDone, WALL_MS } from "./att.ts";

const FN = "att-news";
const NEWS_VERSION = "2026-09-25.n4"; // n2: GKG 404 parking + min file age; sequential sitemaps. n3: size-normalised
// GKG burst baseline; network brands excluded from Third Eye. n4: GKG entity minimisation (photo/byline credits,
// outlet breadth, boilerplate labels) for candidates and edges; parked-file retry by file age; brand-free sitemap keywords
const GKG_BASE = "https://data.gdeltproject.org/gdeltv2/";
const THIRDEYE = "https://archive.org/services/third-eye.php";
const OUTLETS: Record<string, string> = {
  bbc: "https://www.bbc.com/sitemaps/https-sitemap-com-news-1.xml",
  nyt: "https://www.nytimes.com/sitemaps/new/news.xml.gz",
  guardian: "https://www.theguardian.com/sitemaps/news.xml",
  fox: "https://www.foxnews.com/sitemap.xml?type=news",
};

// ------------------------------------------------------------ text normalisation + term matcher
const normMem = new Map<string, string>();
/** lower case, accents stripped, every non letter/digit run -> one space. */
export function norm(s: string): string {
  const c = normMem.get(s);
  if (c !== undefined) return c;
  const v = s.toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "").replace(/[^\p{L}\p{N}]+/gu, " ").trim();
  if (normMem.size < 200_000) normMem.set(s, v);
  return v;
}

export interface Term { key: string; topic_id: number | null; active: boolean; key_type: string; match: any }
/** Whole-word phrase matcher: patterns indexed by first token; text must be norm()-ed. " ~ " separates fields. */
export class Matcher {
  private byFirst = new Map<string, Array<[string, number]>>();
  patterns = 0;
  constructor(public terms: Term[]) {
    terms.forEach((t, i) => {
      if (t.key_type === "theme") return;
      const aliases: string[] = Array.isArray(t.match?.aliases) ? t.match.aliases : [];
      const seen = new Set<string>();
      for (const raw of [t.key, ...aliases]) {
        const p = norm(String(raw));
        // too short / purely numeric patterns are noise in names and headlines
        if (p.length < 3 || /^[\d ]+$/.test(p) || seen.has(p)) continue;
        seen.add(p);
        const first = p.split(" ")[0];
        let arr = this.byFirst.get(first);
        if (!arr) { arr = []; this.byFirst.set(first, arr); }
        arr.push([" " + p + " ", i]);
        this.patterns++;
      }
    });
  }
  match(t: string, out: Set<number>) {
    if (!t) return;
    const padded = " " + t + " ";
    const seenTok = new Set<string>();
    for (const tok of t.split(" ")) {
      if (seenTok.has(tok)) continue;
      seenTok.add(tok);
      const c = this.byFirst.get(tok);
      if (!c) continue;
      for (const [p, i] of c) if (!out.has(i) && (p.length === tok.length + 2 || padded.includes(p))) out.add(i);
    }
  }
}

async function loadTerms(run: Run, source: string): Promise<Term[]> {
  if (Array.isArray(run.body?.keys) && run.body.keys.length) {
    return run.body.keys.map((k: any) => ({ key: String(k.key), topic_id: k.topic_id ?? null, active: k.active === true,
      key_type: k.key_type ?? "term", match: k.match ?? {} }));
  }
  const { data, error } = await db.rpc("att_news_terms", { p_source: source, p_limit: 5000 });
  if (error) throw new Error(`att_news_terms: ${error.message}`);
  return (data ?? []) as Term[];
}

// ------------------------------------------------------------ small helpers
const pad = (n: number) => String(n).padStart(2, "0");
const hourIso = (ms: number) => new Date(Math.floor(ms / 3600e3) * 3600e3).toISOString().slice(0, 13) + ":00:00Z";
const dayOf = (ms: number) => new Date(ms).toISOString().slice(0, 10);
function gkgTsMs(f: string): number {
  return Date.UTC(+f.slice(0, 4), +f.slice(4, 6) - 1, +f.slice(6, 8), +f.slice(8, 10), +f.slice(10, 12), +f.slice(12, 14));
}
function gkgName(ms: number): string {
  const d = new Date(ms);
  return `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}00`;
}
function failStatus(run: Run, host: string): string {
  const s = run.skipped.filter((x) => x.host === host).map((x) => x.reason).join(",");
  if (/robots/.test(s)) return "robots_disallow";
  if (/host_killed_(429|503)/.test(s)) return "host_killed_429";
  if (/budget|per_run_cap/.test(s)) return "budget_exhausted";
  if (/disabled/.test(s)) return "disabled";
  return "http_error";
}
function decodeXml(s: string): string {
  return s.replace(/^<!\[CDATA\[/, "").replace(/\]\]>$/, "")
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(+d))
    .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
}
async function rpcJson(run: Run, fn: string, args: Record<string, unknown>): Promise<any> {
  const { data, error } = await db.rpc(fn, args);
  if (error) { run.errors.push(`${fn}: ${error.message}`); return null; }
  return data;
}
function noteIngest(run: Run, r: any, hourly = 0) {
  if (!r) return;
  const rows = Number(r.rows ?? 0);
  const h = Number(r.hourly ?? Math.min(hourly, rows));
  run.rows.obs_hourly += h;
  run.rows.obs += Math.max(0, rows - h);
  run.rows.series_new += Number(r.series_new ?? 0);
  if (Array.isArray(r.rejected)) {
    const bad = r.rejected.filter((x: any) => x?.reason !== "hourly_active_only");
    if (bad.length) run.rejected.push(...bad.slice(0, 20));
  }
}
async function accum(run: Run, batch: string, rows: any[]) {
  if (!rows.length) return null;
  if (run.dryRun) { run.dryRows.push(...rows.slice(0, Math.max(0, 50 - run.dryRows.length))); return { rows: rows.length }; }
  const r = await rpcJson(run, "att_news_accum", { p_run: { run_id: run.runId }, p_batch: batch, p_rows: rows });
  if (r?.dup) run.extra.duplicate_batch = batch;
  noteIngest(run, r);
  return r;
}
async function edgesAccum(run: Run, batch: string, rows: any[]) {
  if (!rows.length || run.dryRun) return;
  const r = await rpcJson(run, "att_news_edges_accum", { p_batch: batch, p_rows: rows });
  run.rows.edges += Number(r?.rows ?? 0);
}
async function candidatesMerge(run: Run, rows: any[]) {
  if (!rows.length || run.dryRun) return;
  const r = await rpcJson(run, "att_news_candidates_merge", { p_rows: rows });
  run.rows.candidates += Number(r?.rows ?? 0);
}

// ccTLD of an outlet domain -> ISO 3166 alpha-2 (generic TLDs -> null)
const GENERIC = new Set(["com", "org", "net", "info", "biz", "gov", "edu", "mil", "int", "news", "tv", "fm", "io", "co",
  "me", "ly", "am", "online", "site", "live", "today", "press", "media", "xyz", "blog", "app", "top", "club", "world"]);
function countryOf(domain: string): string | null {
  const i = domain.lastIndexOf(".");
  if (i < 0) return null;
  const tld = domain.slice(i + 1).toLowerCase();
  if (tld.length !== 2 || GENERIC.has(tld)) return null;
  return tld === "uk" ? "GB" : tld.toUpperCase();
}

// ------------------------------------------------------------ zip (single entry, deflate)
function zipEntry(buf: Uint8Array): { start: number; csize: number; method: number } {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65557); i--) {
    if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error("zip: no end of central directory");
  const cd = dv.getUint32(eocd + 16, true);
  if (dv.getUint32(cd, true) !== 0x02014b50) throw new Error("zip: bad central directory");
  const method = dv.getUint16(cd + 10, true);
  const csize = dv.getUint32(cd + 20, true);
  const loc = dv.getUint32(cd + 42, true);
  if (dv.getUint32(loc, true) !== 0x04034b50) throw new Error("zip: bad local header");
  const start = loc + 30 + dv.getUint16(loc + 26, true) + dv.getUint16(loc + 28, true);
  return { start, csize, method };
}

/** Stream text lines out of a byte stream (TextDecoderStream + manual split; no quadratic concatenation). */
async function forEachLine(stream: ReadableStream<any>, fn: (line: string) => void | false, stop: () => boolean) {
  const reader = stream.pipeThrough(new TextDecoderStream()).getReader();
  let carry = "";
  try {
    while (true) {
      if (stop()) return false;
      const { value, done } = await reader.read();
      if (done) break;
      const s = carry ? carry + value : value;
      let start = 0, i: number;
      while ((i = s.indexOf("\n", start)) >= 0) {
        if (fn(s.slice(start, i)) === false) return false;
        start = i + 1;
      }
      carry = s.slice(start);
    }
    if (carry) fn(carry);
    return true;
  } finally {
    reader.cancel().catch(() => undefined);
  }
}

// ------------------------------------------------------------ mode: gkg
interface Pending { first: string; last: string; n: number }
interface GkgState { last_file?: string; files?: number; gaps?: number; pending?: Record<string, Pending> }
/** EWMA baseline of each entity's documents per 1000 documents in a file (unit "per1k"; older states were per file). */
interface Ewma { n_files: number; b: Record<string, number>; unit?: string }
const EWMA_ALPHA = 0.05;
const EWMA_KEEP = 4000;
const CAND_WARMUP_FILES = 4;
// Entity minimisation (n4). A GKG name only becomes a discovery candidate or an edge endpoint when it is reported by
// several outlets and is not mostly a credit: photo and syndication credits ("(AP Photo/Jane Doe)", "Getty Images",
// "Tribune Content Agency") and bylines (Extras <PAGE_AUTHORS>) name journalists and photographers, not news.
const CAND_MIN_OUTLETS = 3;        // distinct SourceCommonName in this file
const EDGE_MIN_OUTLETS = 2;        // org edge endpoints; person-like names need CAND_MIN_OUTLETS
const CREDIT_MAX_SHARE = 0.25;     // an entity whose mentions are > 25% credit-context is a credit
const CREDIT_WINDOW = 60;          // characters between a credit marker and a name (AllNames offsets)
const CREDIT_MARK = new Set(["ap", "ap photo", "ap photos", "associated press", "the associated press", "the associated", "reuters",
  "reuters photo", "getty", "getty images", "afp", "afp via getty images", "afp photo", "pa", "pa media", "pa wire",
  "pa images", "epa", "epa efe", "efe", "shutterstock", "alamy", "alamy stock photo", "nurphoto", "sipa", "sipa usa",
  "zuma", "zuma press", "imagn", "imagn images", "usa today sports", "usa today network", "pool", "pool photo",
  "photo", "photos", "image", "images", "credit", "image credit", "photo credit", "courtesy", "file photo",
  "photographer", "staff photographer", "tribune content agency", "tribune news service", "tns", "cq roll call",
  "bloomberg via getty images", "the canadian press", "canadian press", "aap", "aap image", "anadolu",
  "anadolu agency", "xinhua", "kyodo", "yonhap", "dpa", "ansa", "press association", "wire", "handout"]);
const CREDIT_TOKEN = /(^| )(photo|photos|getty|shutterstock|alamy|nurphoto|imagn|handout)( |$)/;
/** Labels that are site furniture, credits or bylines rather than entities (checked on norm()-ed labels). */
const JUNK_LABEL = new RegExp([
  "(^| )(photo|photos|getty|image|images|shutterstock|alamy|imagn|handout)( |$)",
  "(^| )(content agency|news service|news agency|newswire|wire service|press release|image credit|photo credit)( |$)",
  "(^| )(staff )?(writer|reporter|correspondent|photographer|contributor|columnist|editor)$",
  "[a-z](writer|reporter|photographer)$",                      // byline glued to the next word: "jane doewriter"
  "(^| )(whatsapp|facebook|instagram|youtube|linkedin|twitter|tiktok|telegram|podcast network)( |$)",
  "(^| )(website access|online edition|print edition|latest edition|headline news|daily headlines|newsletter)( |$)",
  "(^| )(contact email|more information|privacy (notice|policy)|terms of (service|use)|cookie|subscribe|sign up)( |$)",
  "(^| )(read more|click here|share this|help someone|donating proceeds|sale notice|plaintiff deadline)( |$)",
  "^(\\S+( \\S+)?) \\1$",                                    // doubled names ("stacker stacker")
].join("|"));
export function junkLabel(n: string): boolean { return JUNK_LABEL.test(n); }
export function isCreditMark(n: string): boolean { return CREDIT_MARK.has(n) || CREDIT_TOKEN.test(n); }

interface GkgCtx { terms: Term[]; matcher: Matcher; themeIdx: Map<string, number>; latest: string; forced: boolean }
interface GkgOut { file: string; status: "ok" | "pending" | "deferred" | "failed" | "partial"; note?: string; [k: string]: unknown }
const GKG_SRC = "gdelt.gkg";
const GKG_HOST = "data.gdeltproject.org";
const GKG_MAX_BEHIND_MS = 6 * 3600e3;   // further behind than this: jump to the latest file (the gap is recorded)
// lastupdate.txt can list a file a few minutes before its zip is served, and the CDN then keeps answering 404 for that
// URL for ~45-60 min (observed 2026-09-25: 7 files, each 404 for 3-4 runs, then 200). So: never request a file younger
// than GKG_MIN_AGE_MS; a 404 parks the file in gkg.state.pending and the walk moves on; a parked file is retried once
// due (see gkgRetryDue) and counted as a gap after GKG_GIVE_UP_MS. Parked files observed on 2026-09-25 were served from
// 49-64 min after their timestamp whatever time they were first requested, so (n4) retries follow the file's age
// (retries at ~+40 and ~+55 min, then every ~30 min) rather than a fixed 50 min after the last 404, and each run takes
// the walk's new file first and uses its spare slot for a due retry.
const GKG_MIN_AGE_MS = 8 * 60e3;
const GKG_RETRY_MIN_AGE_MS = 39 * 60e3;   // a parked file is not retried before it is this old
const GKG_RETRY_GAP_MS = 14 * 60e3;       // ... nor sooner than this after its last 404
const GKG_RETRY_GAP_LATE_MS = 29 * 60e3;  // ... nor, once it has had 3 404s, sooner than this
const GKG_GIVE_UP_MS = 4 * 3600e3;
export function gkgRetryDue(file: string, p: Pending, now: number): boolean {
  const since = now - Date.parse(p.last);
  return now - gkgTsMs(file) >= GKG_RETRY_MIN_AGE_MS && since >= (p.n >= 3 ? GKG_RETRY_GAP_LATE_MS : GKG_RETRY_GAP_MS);
}

async function gkg(run: Run) {
  const t0 = Date.now();
  const forced = typeof run.params.file === "string" && /^\d{14}$/.test(run.params.file) ? run.params.file as string : null;
  // up to 2 files per run (3 requests with lastupdate.txt): the walk's next file first, then a due parked retry
  const maxFiles = forced ? 1 : Math.max(1, Math.min(2, Number(run.params.max_files ?? 2)));
  let latest = forced;
  if (!forced) {
    // give up on parked files that never appeared (recorded as gaps)
    const st0 = ((await stateGet("gkg.state")) ?? {}) as GkgState;
    const pend = { ...(st0.pending ?? {}) };
    const lost = Object.keys(pend).filter((f) => Date.now() - Date.parse(pend[f].first) > GKG_GIVE_UP_MS);
    if (lost.length && !run.dryRun) {
      for (const f of lost) delete pend[f];
      await stateSet("gkg.state", { ...st0, pending: pend, gaps: (st0.gaps ?? 0) + lost.length });
      run.extra.given_up = lost;
    }
    // lastupdate.txt is the authority on what is published (file names run ahead of the wall clock)
    const r = await politeFetch(run, GKG_BASE + "lastupdate.txt", { source: GKG_SRC, timeoutMs: 15_000 });
    if (!r) { run.source({ source: GKG_SRC, status: failStatus(run, GKG_HOST), note: "lastupdate.txt not fetched" }); return; }
    if (!r.ok) { await r.body?.cancel(); run.source({ source: GKG_SRC, status: "http_error", note: `lastupdate ${r.status}` }); return; }
    const m = (await r.text()).match(/(\d{14})\.gkg\.csv\.zip/);
    if (!m) { run.errors.push("lastupdate.txt: no gkg file"); run.source({ source: GKG_SRC, status: "http_error" }); return; }
    latest = m[1];
  }
  run.extra.latest = latest;
  const terms = await loadTerms(run, GKG_SRC);
  const themeIdx = new Map<string, number>();
  terms.forEach((t, i) => { if (t.key_type === "theme") themeIdx.set(t.key.toUpperCase(), i); });
  const ctx: GkgCtx = { terms, matcher: new Matcher(terms), themeIdx, latest: latest!, forced: forced !== null };
  const outs: GkgOut[] = [];
  const tried = new Set<string>();
  let walkDone = false;
  for (let k = 0; k < maxFiles; k++) {
    const st = ((await stateGet("gkg.state")) ?? {}) as GkgState;
    let file: string | null = null;
    let retry = false;
    if (forced) file = forced;
    else {
      // 1) the walk towards the latest listed file (freshest data first)
      if (!walkDone) {
        let next: string;
        if (!st.last_file || gkgTsMs(ctx.latest) - gkgTsMs(st.last_file) > GKG_MAX_BEHIND_MS) {
          if (st.last_file) run.extra.gap_files = Math.round((gkgTsMs(ctx.latest) - gkgTsMs(st.last_file)) / (15 * 60e3)) - 1;
          next = ctx.latest;
        } else next = gkgName(gkgTsMs(st.last_file) + 15 * 60e3);
        if (next > ctx.latest) { walkDone = true; run.extra.note = "no new file"; }
        else if (Date.now() - gkgTsMs(next) < GKG_MIN_AGE_MS) { walkDone = true; run.extra.note = `${next} younger than ${GKG_MIN_AGE_MS / 60e3} min; next run`; }
        else file = next;
      }
      // 2) otherwise a parked file whose retry is due (oldest first)
      if (!file) {
        const now = Date.now();
        const due = Object.entries(st.pending ?? {}).filter(([f, p]) => !tried.has(f) && gkgRetryDue(f, p, now))
          .map(([f]) => f).sort();
        if (!due.length) break;
        file = due[0]; retry = true;
      }
    }
    if (k > 0 && run.outOfTime(40_000)) { run.partial = true; break; }
    tried.add(file);
    const out = await gkgFile(run, file, ctx, st, retry);
    outs.push(out);
    if (forced) break;
    if (out.status === "ok" || out.status === "deferred" || out.status === "pending") continue;
    break;
  }
  run.extra.files = outs;
  const done = outs.filter((o) => o.status === "ok");
  run.extra.file = outs.length ? outs[outs.length - 1].file : null;
  const st2 = ((await stateGet("gkg.state")) ?? {}) as GkgState;
  run.extra.pending = Object.keys(st2.pending ?? {});
  // partial = this run left work it could have done: listed files old enough to fetch that the walk has not reached.
  // Waiting for a file younger than GKG_MIN_AGE_MS, or for a parked file GDELT has not served yet, is not partial.
  if (!forced && st2.last_file && st2.last_file < ctx.latest) {
    let behind = 0;
    for (let t = gkgTsMs(st2.last_file) + 15 * 60e3; t <= gkgTsMs(ctx.latest); t += 15 * 60e3) if (Date.now() - t >= GKG_MIN_AGE_MS) behind++;
    if (behind > 0) { run.partial = true; run.nextCursor = { gkg_behind_files: behind }; }
  }
  const bad = outs.find((o) => o.status === "failed");
  run.source({
    source: GKG_SRC, status: bad ? failStatus(run, GKG_HOST) : outs.some((o) => o.status === "partial") ? "partial" : "ok",
    keys: terms.length, rows: done.reduce((a, o) => a + Number(o.rows ?? 0), 0), ms: Date.now() - t0,
    note: outs.map((o) => `${o.file}:${o.status}${o.note ? " " + o.note : ""}`).join("; ") || String(run.extra.note ?? ""),
  });
}

async function gkgFile(run: Run, file: string, ctx: GkgCtx, st: GkgState, retry = false): Promise<GkgOut> {
  const SRC = GKG_SRC;
  const { terms, matcher, themeIdx } = ctx;
  const t0 = Date.now();
  const ms: Record<string, number> = {};
  // ---- download (one request)
  const res = await politeFetch(run, `${GKG_BASE}${file}.gkg.csv.zip`, { source: SRC, timeoutMs: 60_000 });
  if (!res) return { file, status: "failed", note: "not fetched" };
  if (res.status === 404) {
    await res.body?.cancel();
    if (ctx.forced) return { file, status: "failed", note: "http 404" };
    const nowIso = new Date(Date.now()).toISOString();
    const pend = { ...(st.pending ?? {}) };
    const p = pend[file];
    pend[file] = { first: p?.first ?? nowIso, last: nowIso, n: (p?.n ?? 0) + 1 };
    // park the file and move the walk past it (a retry leaves last_file alone)
    if (!run.dryRun) await stateSet("gkg.state", { ...st, pending: pend, last_file: retry || (st.last_file && st.last_file > file) ? st.last_file : file });
    return retry ? { file, status: "pending", note: `still 404 (try ${pend[file].n})` }
      : { file, status: "deferred", note: `listed but 404; parked, retried from ${GKG_RETRY_MIN_AGE_MS / 60e3} min after the file time` };
  }
  if (!res.ok) { await res.body?.cancel(); return { file, status: "failed", note: `http ${res.status}` }; }
  const zip = new Uint8Array(await res.arrayBuffer());
  ms.download = Date.now() - t0;
  const zipBytes = zip.length;

  // ---- parse
  const tp = Date.now();
  const ent = zipEntry(zip);
  const raw = new Blob([zip.subarray(ent.start, ent.start + ent.csize)]).stream();
  const stream = ent.method === 8 ? raw.pipeThrough(new DecompressionStream("deflate-raw")) : raw;

  const nT = terms.length;
  const termDocs = new Float64Array(nT);
  const termCC: Array<Set<string> | undefined> = new Array(nT);
  const totalCC = new Set<string>();
  const entDocs = new Map<string, number>();      // normalized entity -> documents
  const entLabel = new Map<string, string>();     // normalized -> display label (first seen)
  const entKind = new Map<string, string>();
  const pairs = new Map<string, number>();        // termIdx \u0001 entity -> documents
  const entOutlets = new Map<string, string[]>(); // normalized -> first CAND_MIN_OUTLETS distinct outlets
  const entCredit = new Map<string, number>();    // normalized -> documents where it appears as a credit/byline
  const bylines = new Set<string>();              // names in any document's <PAGE_AUTHORS>
  let N = 0, bad = 0, bytes = 0, creditDocs = 0;
  const matched = new Set<number>();
  const docEnt = new Map<string, string>();       // per document: normalized -> kind
  const docCredit = new Set<string>();            // per document: names in credit context
  const anN: string[] = [];                        // per document: AllNames (normalized) and offsets
  const anO: number[] = [];
  const probe: string[] = run.dryRun && Array.isArray(run.params.probe) ? run.params.probe.map((x: unknown) => norm(String(x))).slice(0, 10) : [];
  const probeOut = probe.map(() => ({ docs: 0, credit: 0, byline: false, outlets: new Set<string>(), ctx: [] as string[][] }));

  const addNames = (field: string | undefined, kind: string, mode: "list" | "allnames" | "loc") => {
    if (!field) return;
    let from = 0;
    while (from <= field.length) {
      let j = field.indexOf(";", from);
      if (j < 0) j = field.length;
      let nm = field.slice(from, j);
      from = j + 1;
      if (!nm) continue;
      let off = -1;
      if (mode === "allnames") { const c = nm.lastIndexOf(","); if (c > 0) { off = +nm.slice(c + 1); nm = nm.slice(0, c); } }
      else if (mode === "loc") { const p = nm.split("#"); nm = (p[1] ?? "").split(",")[0]; }
      if (mode === "allnames" && off >= 0 && nm.length >= 2 && nm.length <= 80) { anN.push(norm(nm)); anO.push(off); }
      if (nm.length < 3 || nm.length > 80) continue;
      const n = norm(nm);
      if (n.length < 3) continue;
      if (!docEnt.has(n)) {
        docEnt.set(n, kind);
        if (!entLabel.has(n) && mode !== "list") entLabel.set(n, nm.trim());
      }
    }
  };

  const ok = await forEachLine(stream, (line) => {
    bytes += line.length;
    const c = line.split("\t");
    if (c.length < 24) { if (line) bad++; return; }
    N++;
    docEnt.clear();
    matched.clear();
    docCredit.clear();
    anN.length = 0; anO.length = 0;
    addNames(c[23], "name", "allnames");   // AllNames: proper-cased, offsets stripped
    // credit context: names within CREDIT_WINDOW characters of a credit marker ("AP Photo", "Getty Images", ...)
    let marks = 0;
    for (let a = 0; a < anN.length; a++) {
      if (!isCreditMark(anN[a])) continue;
      marks++;
      docCredit.add(anN[a]);
      for (let b = 0; b < anN.length; b++) if (b !== a && Math.abs(anO[b] - anO[a]) <= CREDIT_WINDOW) docCredit.add(anN[b]);
    }
    // bylines (Extras <PAGE_AUTHORS>): journalists' names are never discovery candidates or edge endpoints
    const ex = c[26];
    if (ex) {
      const i0 = ex.indexOf("<PAGE_AUTHORS>");
      if (i0 >= 0) {
        const i1 = ex.indexOf("</PAGE_AUTHORS>", i0);
        for (const au of ex.slice(i0 + 14, i1 < 0 ? undefined : i1).split(/[,;|]| and /)) {
          const na = norm(au);
          if (na.length >= 3) { bylines.add(na); docCredit.add(na); }
        }
      }
    }
    if (marks) creditDocs++;
    addNames(c[11], "person", "list");     // V1Persons
    addNames(c[13], "org", "list");        // V1Organizations
    addNames(c[9], "place", "loc");        // V1Locations (feature name before the first comma)
    const outlet = c[3] ?? "";
    const cc = countryOf(outlet);
    if (cc) totalCC.add(cc);
    // registry terms against the document's names (fields separated so phrases never span two names)
    matcher.match([...docEnt.keys()].join(" ~ "), matched);
    if (themeIdx.size && c[7]) for (const th of c[7].split(";")) { const i = themeIdx.get(th); if (i !== undefined) matched.add(i); }
    for (const i of matched) {
      termDocs[i]++;
      if (cc) (termCC[i] ??= new Set()).add(cc);
    }
    for (let q = 0; q < probe.length; q++) {
      if (!docEnt.has(probe[q])) continue;
      const po = probeOut[q];
      po.docs++; po.outlets.add(outlet);
      if (docCredit.has(probe[q])) po.credit++;
      if (bylines.has(probe[q])) po.byline = true;
      if (po.ctx.length < 3) {
        const k0 = anN.indexOf(probe[q]);
        if (k0 >= 0) po.ctx.push(anN.map((x, j) => [x, anO[j] - anO[k0]] as [string, number])
          .filter(([, d]) => Math.abs(d) <= 120).map(([x, d]) => `${d}:${x}`));
      }
    }
    // entity document counts (discovery) and co-mentions with active topics (hop evidence)
    let k = 0;
    for (const [n, kind] of docEnt) {
      entDocs.set(n, (entDocs.get(n) ?? 0) + 1);
      if (!entKind.has(n)) entKind.set(n, kind);
      if (docCredit.has(n)) entCredit.set(n, (entCredit.get(n) ?? 0) + 1);
      const ol = entOutlets.get(n);
      if (!ol) entOutlets.set(n, [outlet]);
      else if (ol.length < CAND_MIN_OUTLETS && !ol.includes(outlet)) ol.push(outlet);
      if (kind === "place" || ++k > 40) continue;
      for (const i of matched) {
        if (!terms[i].active) continue;
        const pk = i + "\u0001" + n;
        pairs.set(pk, (pairs.get(pk) ?? 0) + 1);
      }
    }
  }, () => run.outOfTime(20_000));
  ms.parse = Date.now() - tp;
  if (!ok) {
    // never write a partial file: counts would be wrong; the next run retries this file (state not advanced)
    run.partial = true;
    return { file, status: "partial", note: `out of time after ${N} docs; nothing written`, ms };
  }

  // ---- write observations (daily for every watched term incl. zeros; hourly for active topics' hits)
  const tw = Date.now();
  const fileMs = gkgTsMs(file) - 60e3;   // the 15-minute window ending at the file timestamp
  const day = dayOf(fileMs);
  const hour = hourIso(fileMs);
  const rows: any[] = [];
  let hit = 0;
  for (let i = 0; i < nT; i++) {
    const t = terms[i];
    const v = termDocs[i];
    if (v > 0) hit++;
    rows.push({ source: SRC, key: t.key, day, value: v, members: v > 0 ? [...(termCC[i] ?? [])] : [], topic_id: t.topic_id });
    if (v > 0 && t.active) rows.push({ source: SRC, key: t.key, ts: hour, value: v, members: [...(termCC[i] ?? [])], topic_id: t.topic_id });
  }
  rows.push({ source: SRC, key: "__total__", day, value: N, members: [...totalCC] });
  rows.push({ source: SRC, key: "__total__", ts: hour, value: N, members: [...totalCC] });
  const r = await accum(run, `gkg:${file}`, rows);

  // ---- entity minimisation (n4): credits, bylines, single-outlet names and site furniture never leave the function
  const drop = { credit: 0, byline: 0, outlets: 0, junk: 0 };
  const eligible = (n: string, minOutlets: number, count = true): boolean => {
    const d = entDocs.get(n) ?? 0;
    let why: keyof typeof drop | null = null;
    if (bylines.has(n)) why = "byline";
    else if (d > 0 && (entCredit.get(n) ?? 0) / d > CREDIT_MAX_SHARE) why = "credit";
    else if (junkLabel(n) || isCreditMark(n)) why = "junk";
    else if ((entOutlets.get(n)?.length ?? 0) < minOutlets) why = "outlets";
    if (why && count) drop[why]++;
    return why === null;
  };
  const personLike = (n: string) => { const k = entKind.get(n); return k === "person" || k === "name"; };

  // ---- co-mention edges (at least one side active; top 25 per term with >= 2 shared documents)
  const byTerm = new Map<number, Array<[string, number]>>();
  const edgeOk = new Map<string, boolean>();
  for (const [pk, n] of pairs) {
    if (n < 2) continue;
    const s = pk.indexOf("\u0001");
    const i = +pk.slice(0, s);
    const e = pk.slice(s + 1);
    let ok = edgeOk.get(e);
    if (ok === undefined) { ok = eligible(e, personLike(e) ? CAND_MIN_OUTLETS : EDGE_MIN_OUTLETS, false); edgeOk.set(e, ok); }
    if (!ok) continue;
    // skip the term's own names (the entity is the topic itself)
    const self = new Set<number>(); matcher.match(e, self);
    if (self.has(i)) continue;
    let a = byTerm.get(i); if (!a) { a = []; byTerm.set(i, a); }
    a.push([e, n]);
  }
  const edges: any[] = [];
  for (const [i, arr] of byTerm) {
    arr.sort((x, y) => y[1] - x[1]);
    for (const [e, n] of arr.slice(0, 25)) {
      edges.push({ source: SRC, from_key: terms[i].key, to_key: e, day, n, from_topic: terms[i].topic_id, to_total: entDocs.get(e) ?? n });
    }
  }
  await edgesAccum(run, `edges:gkg:${file}`, edges);

  // ---- discovery: surging entities vs an EWMA baseline of each entity's share of the file's documents
  // (files range from ~900 to ~1500 documents, so a per-file count baseline flags every big name in a big file)
  const ew = ((await stateGet("gkg.ewma")) ?? { n_files: 0, b: {}, unit: "per1k" }) as Ewma;
  const per1k = N > 0 ? 1000 / N : 0;
  if (ew.unit !== "per1k") {
    // one-off conversion of a per-file baseline (approximated with this file's size)
    for (const n of Object.keys(ew.b)) ew.b[n] = ew.b[n] * per1k;
    ew.unit = "per1k";
  }
  const cands: Array<{ n: string; z: number; c: number; e: number }> = [];
  if (ew.n_files >= CAND_WARMUP_FILES && N > 0) {
    for (const [n, c] of entDocs) {
      if (c < 5) continue;
      const e = (ew.b[n] ?? 0) * N / 1000;   // expected documents in this file
      const z = (c - e) / Math.sqrt(e + 1);
      if (z >= 3 && eligible(n, CAND_MIN_OUTLETS)) cands.push({ n, z, c, e });
    }
    cands.sort((a, b) => b.z - a.z);
  }
  const top = cands.slice(0, 200);
  const candRows = top.map((x, k) => ({
    day, source: SRC, geo: "ALL", label: entLabel.get(x.n) ?? x.n, rank: k + 1, value: x.c,
    evidence: Math.max(0, Math.min(1, x.z / 8)),
    meta: { method: "gkg_burst_ewma_v2", n_docs: x.c, k: entKind.get(x.n) ?? "name", q: Math.round(x.z * 100) / 100 },
  }));
  await candidatesMerge(run, candRows);
  if (run.dryRun) {
    // dry-run diagnostics go to the HTTP response only (dry_rows are not persisted in att_runs)
    run.dryRows.push({ candidates_preview: candRows.slice(0, 60).map((r) => `${r.label} (${r.value})`) });
    run.dryRows.push({ edges_preview: edges.slice(0, 40).map((e) => `${e.from_key} -> ${e.to_key} (${e.n})`) });
    probe.forEach((p, q) => run.dryRows.push({ probe: p, docs: probeOut[q].docs, credit_docs: probeOut[q].credit,
      byline: probeOut[q].byline, outlets: probeOut[q].outlets.size, eligible: eligible(p, CAND_MIN_OUTLETS, false),
      ctx: probeOut[q].ctx }));
  }

  // EWMA update (only after a complete, newly written file)
  if (!run.dryRun && !(r?.dup)) {
    const nb: Record<string, number> = {};
    for (const [n, b] of Object.entries(ew.b)) nb[n] = b * (1 - EWMA_ALPHA);
    for (const [n, c] of entDocs) if (c >= 2 || nb[n] !== undefined) nb[n] = (nb[n] ?? 0) + EWMA_ALPHA * c * per1k;
    const keep = Object.entries(nb).filter(([, b]) => b >= 0.05).sort((a, b) => b[1] - a[1]).slice(0, EWMA_KEEP);
    await stateSet("gkg.ewma", { n_files: ew.n_files + 1, unit: "per1k",
      b: Object.fromEntries(keep.map(([n, b]) => [n, Math.round(b * 1000) / 1000])) });
  }
  if (!run.dryRun && !ctx.forced) {
    const cur = ((await stateGet("gkg.state")) ?? st) as GkgState;
    const pend = { ...(cur.pending ?? {}) };
    delete pend[file];
    await stateSet("gkg.state", { ...cur, pending: pend, files: (cur.files ?? 0) + 1,
      last_file: !cur.last_file || file > cur.last_file ? file : cur.last_file });
  }
  ms.write = Date.now() - tw;
  ms.total = Date.now() - t0;
  return { file, status: "ok", note: r?.dup ? "already counted (batch dup)" : undefined, rows: Number(r?.rows ?? 0),
    zip_bytes: zipBytes, articles: N, entities: entDocs.size, text_chars: bytes, bad_lines: bad, terms_hit: hit,
    pairs: edges.length, candidates: candRows.length, credit_docs: creditDocs, bylines: bylines.size, dropped: drop, ms };
}

// ------------------------------------------------------------ mode: thirdeye
const TV_BRANDS = new Set(["cnn", "cnn international", "fox", "fox news", "fox news channel", "msnbc", "ms now", "msnow",
  "bbc", "bbc news", "bbc one", "bbc world news", "cnbc", "abc", "abc news", "cbs", "cbs news", "nbc", "nbc news", "pbs",
  "sky news", "newsmax", "c span", "bloomberg television", "al jazeera"]);
async function thirdeye(run: Run) {
  const SRC = "ia.thirdeye";
  const t0 = Date.now();
  const st = ((await stateGet("thirdeye.state")) ?? {}) as { last_hour?: string; hours?: number };
  const now = Date.now();
  const curHour = Math.floor(now / 3600e3) * 3600e3;
  let last = Math.max(1, Math.min(6, Number(run.params.last ?? 2)));
  // if the previous run missed an hour, widen the window once (still one request)
  if (st.last_hour && Date.parse(st.last_hour) < curHour - 2 * 3600e3) last = Math.min(6, Math.max(last, 3));
  const url = `${THIRDEYE}?last=${last}`;
  const res = await politeFetch(run, url, { source: SRC, timeoutMs: 30_000 });
  if (!res) { run.source({ source: SRC, status: failStatus(run, "archive.org"), note: "not fetched" }); return; }
  if (!res.ok) { await res.body?.cancel(); run.source({ source: SRC, status: "http_error", note: `http ${res.status}` }); return; }
  const txt = await res.text();
  const tDl = Date.now() - t0;
  const lines = txt.split("\n");
  // header (column names only) -> indexes; fall back to the observed layout (0 = time, 1 = channel, last = text)
  const head = (lines[0] ?? "").toLowerCase().split("\t");
  const looksHeader = !/^\d{4}-\d{2}-\d{2}/.test(lines[0] ?? "");
  const iTime = looksHeader ? Math.max(0, head.findIndex((h) => /date|time/.test(h))) : 0;
  const iChan = looksHeader ? Math.max(1, head.findIndex((h) => /chan|network|station/.test(h))) : 1;
  const iTextH = looksHeader ? head.findIndex((h) => /text|chyron|caption/.test(h)) : -1;

  // a network's own name is on its screen all day (logos, tickers, promos): those terms are not counted on Third Eye
  const allTerms = await loadTerms(run, SRC);
  const terms = allTerms.filter((t) => ![t.key, ...(Array.isArray(t.match?.aliases) ? t.match.aliases : [])]
    .some((x: unknown) => TV_BRANDS.has(norm(String(x)))));
  if (terms.length < allTerms.length) run.extra.brand_terms_skipped = allTerms.length - terms.length;
  const matcher = new Matcher(terms);

  // hour -> channel -> term -> set of minutes
  type HourAgg = { total: Map<string, Set<string>>; hits: Map<number, Map<string, Set<string>>> };
  const hours = new Map<number, HourAgg>();
  let minTs = Infinity, rowsN = 0;
  const m = new Set<number>();
  for (let li = looksHeader ? 1 : 0; li < lines.length; li++) {
    const l = lines[li];
    if (!l) continue;
    const c = l.split("\t");
    if (c.length < 3) continue;
    const tRaw = (c[iTime] ?? "").trim();
    const ts = Date.parse(tRaw.replace(" ", "T") + (/[zZ]|[+-]\d\d:?\d\d$/.test(tRaw) ? "" : "Z"));
    if (!Number.isFinite(ts)) continue;
    rowsN++;
    if (ts < minTs) minTs = ts;
    const ch = (c[iChan] ?? "").trim().toUpperCase().replace(/[^A-Z0-9_]/g, "").slice(0, 20) || "UNKNOWN";
    const text = iTextH >= 0 ? c[iTextH] : c[c.length - 1];
    const h = Math.floor(ts / 3600e3) * 3600e3;
    const minute = String(Math.floor(ts / 60e3));
    let agg = hours.get(h);
    if (!agg) { agg = { total: new Map(), hits: new Map() }; hours.set(h, agg); }
    let tot = agg.total.get(ch); if (!tot) { tot = new Set(); agg.total.set(ch, tot); }
    tot.add(minute);
    m.clear();
    matcher.match(norm(text ?? ""), m);
    for (const i of m) {
      let byCh = agg.hits.get(i); if (!byCh) { byCh = new Map(); agg.hits.set(i, byCh); }
      let mins = byCh.get(ch); if (!mins) { mins = new Set(); byCh.set(ch, mins); }
      mins.add(minute);
    }
  }
  run.extra.chyrons = rowsN;
  if (run.params.peek === true) {
    // structure only (no text leaves the function): header names, per-column average length, numeric share
    const sample = lines.slice(looksHeader ? 1 : 0, 200).filter(Boolean).map((l) => l.split("\t"));
    const ncol = Math.max(0, ...sample.map((c) => c.length));
    run.extra.peek = {
      header: looksHeader ? head.map((h) => h.slice(0, 30)) : null, iTime, iChan, iText: iTextH >= 0 ? iTextH : "last",
      cols: Array.from({ length: ncol }, (_, j) => ({
        avg_len: Math.round(sample.reduce((a, c) => a + (c[j]?.length ?? 0), 0) / Math.max(1, sample.length)),
        numeric: Math.round(100 * sample.filter((c) => /^[\d.:\- ]+$/.test(c[j] ?? "")).length / Math.max(1, sample.length)),
      })),
    };
  }
  // complete hours only: fully inside the window and ended at least 2 minutes ago
  const firstFull = Math.ceil((minTs - 90e3) / 3600e3) * 3600e3;
  const complete = [...hours.keys()].filter((h) => h >= firstFull && h + 3600e3 <= now - 120e3).sort();
  const channels = new Set<string>();
  let written = 0, hitsTotal = 0;
  for (const h of complete) {
    const agg = hours.get(h)!;
    const hIso = hourIso(h);
    const day = dayOf(h);
    const rows: any[] = [];
    const hourly: any[] = [];
    for (const ch of agg.total.keys()) channels.add(ch);
    for (let i = 0; i < terms.length; i++) {
      const byCh = agg.hits.get(i);
      let v = 0;
      const chs: string[] = [];
      if (byCh) for (const [ch, mins] of byCh) { v += mins.size; chs.push(ch); rows.push({ source: SRC, key: terms[i].key, geo: ch, day, value: mins.size, topic_id: terms[i].topic_id }); }
      if (v > 0) hitsTotal++;
      rows.push({ source: SRC, key: terms[i].key, day, value: v, members: chs, topic_id: terms[i].topic_id });
      if (v > 0 && terms[i].active) hourly.push({ source: SRC, key: terms[i].key, ts: hIso, value: v, aux: chs.length, topic_id: terms[i].topic_id });
    }
    let all = 0;
    for (const [ch, mins] of agg.total) { all += mins.size; rows.push({ source: SRC, key: "__total__", geo: ch, day, value: mins.size }); }
    rows.push({ source: SRC, key: "__total__", day, value: all, members: [...agg.total.keys()] });
    hourly.push({ source: SRC, key: "__total__", ts: hIso, value: all, aux: agg.total.size });
    const r = await accum(run, `thirdeye:${hIso.slice(0, 13)}`, rows);
    if (r && !r.dup) written++;
    // hourly values are complete per hour: plain overwrite through att_ingest
    if (!run.dryRun) noteIngest(run, await rpcJson(run, "att_ingest", { p_run: { run_id: run.runId }, p_rows: hourly }));
    // same-hour co-occurrence (tv family): shared chyron-minutes = sum over channels of min(minutes_a, minutes_b)
    const act = [...agg.hits.keys()];
    const edges: any[] = [];
    for (const a of act) {
      if (!terms[a].active) continue;
      for (const b of act) {
        if (a === b) continue;
        let n = 0;
        for (const [ch, ma] of agg.hits.get(a)!) { const mb = agg.hits.get(b)!.get(ch); if (mb) n += Math.min(ma.size, mb.size); }
        if (n > 0) edges.push({ source: SRC, from_key: terms[a].key, to_key: terms[b].key, day, n, from_topic: terms[a].topic_id, to_topic: terms[b].topic_id });
      }
    }
    await edgesAccum(run, `edges:thirdeye:${hIso.slice(0, 13)}`, edges);
  }
  if (complete.length && !run.dryRun) {
    const lastH = hourIso(complete[complete.length - 1]);
    if (!st.last_hour || lastH > st.last_hour) await stateSet("thirdeye.state", { last_hour: lastH, hours: (st.hours ?? 0) + written });
  }
  run.extra.channels = channels.size;
  run.extra.hours = complete.map((h) => hourIso(h).slice(0, 13));
  run.extra.terms_hit = hitsTotal;
  run.extra.ms = { download: tDl, total: Date.now() - t0 };
  run.source({ source: SRC, status: "ok", keys: terms.length, rows: run.rows.obs + run.rows.obs_hourly, ms: Date.now() - t0,
    note: complete.length ? null : "no complete hour in window" });
}

// ------------------------------------------------------------ mode: sitemaps
interface Item { day: string; text: string; kws: string[] }
// section labels and function words that publishers put in news:keywords (not discoverable entities)
const KW_SKIP = new Set(["the", "and", "for", "with", "from", "news", "live", "video", "videos", "opinion", "analysis",
  "latest", "update", "updates", "world", "world news", "us news", "uk news", "us", "uk", "media", "politics", "business",
  "sport", "sports", "lifestyle", "entertainment", "culture", "technology", "science", "health", "travel", "fox news",
  // n4: outlet and network brands (a publisher tagging a rival network is not a discovery), pronouns, bare nouns
  "bbc", "bbc news", "new york times", "the new york times", "nyt", "guardian", "the guardian", "fox", "fox business",
  "her", "his", "she", "they", "our", "age", "people", "women", "men", "children", "youth", "students", "schools"]);
async function fetchSitemap(run: Run, outlet: string, url: string): Promise<{ items: Item[]; urls: number; status: string; note?: string }> {
  const host = new URL(url).hostname;
  const res = await politeFetch(run, url, { source: "news.sitemap", timeoutMs: 30_000 });
  if (!res) return { items: [], urls: 0, status: failStatus(run, host) };
  if (!res.ok) { await res.body?.cancel(); return { items: [], urls: 0, status: "http_error", note: `http ${res.status}` }; }
  const buf = new Uint8Array(await res.arrayBuffer());
  let xml: string;
  if (buf[0] === 0x1f && buf[1] === 0x8b) {
    xml = await new Response(new Blob([buf]).stream().pipeThrough(new DecompressionStream("gzip"))).text();
  } else xml = new TextDecoder().decode(buf);
  const items: Item[] = [];
  let urls = 0;
  let from = 0;
  while (true) {
    const a = xml.indexOf("<url>", from);
    if (a < 0) break;
    const b = xml.indexOf("</url>", a);
    if (b < 0) break;
    const blk = xml.slice(a, b);
    from = b + 6;
    urls++;
    const tag = (t: string) => { const m = blk.match(new RegExp(`<${t}>([\\s\\S]*?)</${t}>`)); return m ? decodeXml(m[1].trim()) : ""; };
    const pd = tag("news:publication_date") || tag("lastmod");
    const ms = Date.parse(pd);
    if (!Number.isFinite(ms)) continue;
    const title = tag("news:title");
    const kw = tag("news:keywords");
    const kws = kw ? kw.split(/[,;]/).map((s) => s.trim()).filter((s) => s.length >= 3 && s.length <= 60) : [];
    items.push({ day: dayOf(ms), text: norm(title) + (kws.length ? " ~ " + kws.map(norm).join(" ~ ") : ""), kws });
  }
  return { items, urls, status: "ok" };
}

async function sitemaps(run: Run) {
  const SRC = "news.sitemap";
  const t0 = Date.now();
  const want: string[] = Array.isArray(run.params.outlets) ? run.params.outlets.filter((o: string) => o in OUTLETS) : Object.keys(OUTLETS);
  const terms = await loadTerms(run, SRC);
  const matcher = new Matcher(terms);
  // one outlet at a time: parallel politeFetch calls each drew a budget chunk before any was spent, which filled the
  // day's news.sitemap budget on the first run (and att_budget_refund keeps a bucket at its cap spent). ~1 s per outlet.
  const got: Array<{ o: string; items: Item[]; urls: number; status: string; note?: string }> = [];
  for (const o of want) got.push({ o, ...(await fetchSitemap(run, o, OUTLETS[o])) });
  const tFetch = Date.now() - t0;
  const urls: Record<string, number> = {};
  const cells: any[] = [];
  const zeroFill = new Set<string>();
  const kwStats = new Map<string, { label: string; outlets: Set<string>; n: number }>();
  const pairN = new Map<string, { n: number; outlets: Set<string>; day: string }>();
  const m = new Set<number>();
  for (const g of got) {
    urls[g.o] = g.urls;
    run.source({ source: SRC, status: g.status, keys: g.status === "ok" ? terms.length : 0, rows: g.items.length, note: g.note ? `${g.o}: ${g.note}` : g.o });
    if (g.status !== "ok") continue;
    const perDay = new Map<string, Map<number, number>>();
    const totals = new Map<string, number>();
    for (const it of g.items) {
      totals.set(it.day, (totals.get(it.day) ?? 0) + 1);
      m.clear();
      matcher.match(it.text, m);
      let dm = perDay.get(it.day); if (!dm) { dm = new Map(); perDay.set(it.day, dm); }
      for (const i of m) dm.set(i, (dm.get(i) ?? 0) + 1);
      // newsroom co-mention: two registry terms in the same headline (one side active)
      const hit = [...m];
      for (const a of hit) {
        if (!terms[a].active) continue;
        for (const b of hit) {
          if (a === b) continue;
          const pk = `${it.day}\u0001${a}\u0001${b}`;
          const p = pairN.get(pk) ?? { n: 0, outlets: new Set<string>(), day: it.day };
          p.n++; p.outlets.add(g.o); pairN.set(pk, p);
        }
      }
      for (const k of it.kws) {
        const nk = norm(k);
        if (nk.length < 3 || KW_SKIP.has(nk) || TV_BRANDS.has(nk)) continue;
        const s = kwStats.get(nk) ?? { label: k, outlets: new Set<string>(), n: 0 };
        s.outlets.add(g.o); s.n++; kwStats.set(nk, s);
      }
    }
    for (const [day, dm] of perDay) {
      zeroFill.add(day);
      for (const [i, n] of dm) cells.push({ outlet: g.o, key: terms[i].key, day, n, topic_id: terms[i].topic_id });
    }
    for (const [day, n] of totals) cells.push({ outlet: g.o, key: "__total__", day, n });
  }
  // zero-fill every watched term for the days seen (outlet null = "write the cross-outlet total")
  const today = dayOf(Date.now());
  for (const day of zeroFill) {
    if (day > today) continue;
    for (const t of terms) cells.push({ outlet: null, key: t.key, day, n: 0, topic_id: t.topic_id });
    cells.push({ outlet: null, key: "__total__", day, n: 0 });
  }
  const keep = cells.filter((c) => c.day <= today && c.day >= dayOf(Date.now() - 3 * 86400e3));
  if (!run.dryRun && keep.length) {
    noteIngest(run, await rpcJson(run, "att_news_sitemap_merge", { p_run: { run_id: run.runId }, p_rows: keep }));
  } else if (run.dryRun) run.dryRows.push(...keep.filter((c) => c.n > 0).slice(0, 50));

  // keywords seen in >= 2 outlets' keywords or headlines -> discovery candidates (rank-list evidence, §6.5)
  if (kwStats.size) {
    const kwTerms: Term[] = [...kwStats.keys()].map((k) => ({ key: k, topic_id: null, active: false, key_type: "term", match: {} }));
    const km = new Matcher(kwTerms);
    const outl = kwTerms.map(() => new Set<string>());
    for (const g of got) for (const it of g.items) { m.clear(); km.match(it.text, m); for (const i of m) outl[i].add(g.o); }
    const ranked = kwTerms.map((t, i) => ({ t, s: kwStats.get(t.key)!, o: new Set([...outl[i], ...kwStats.get(t.key)!.outlets]) }))
      .filter((x) => x.o.size >= 2 && x.s.n >= 2)
      .sort((a, b) => b.o.size - a.o.size || b.s.n - a.s.n)
      .slice(0, 50);
    const N = ranked.length;
    await candidatesMerge(run, ranked.map((x, k) => ({
      day: today, source: SRC, geo: "ALL", label: x.s.label, rank: k + 1, value: x.s.n,
      evidence: Math.max(0, Math.min(1, 1 - Math.log(k + 1) / Math.log(N + 1))),
      meta: { method: "sitemap_keywords", n_docs: x.s.n, q: x.o.size },
    })));
    run.extra.candidates = ranked.length;
  }
  const edges = [...pairN.entries()].filter(([, p]) => p.outlets.size >= 1).map(([pk, p]) => {
    const parts = pk.split("\u0001");
    const a = +parts[1], b = +parts[2];
    return { source: SRC, from_key: terms[a].key, to_key: terms[b].key, period: p.day, grain: "day", n: p.n,
      from_topic: terms[a].topic_id, to_topic: terms[b].topic_id, meta: { q: p.outlets.size } };
  });
  if (edges.length && !run.dryRun) {
    const r = await rpcJson(run, "att_ingest_edges", { p_rows: edges });
    run.rows.edges += Number(r?.rows ?? 0);
  }
  run.extra.urls = urls;
  run.extra.ms = { fetch: tFetch, total: Date.now() - t0 };
}

// ------------------------------------------------------------ mode: backfill (not enabled)
async function backfill(run: Run) {
  const ids = run.jobIds();
  if (ids.length && !run.dryRun) await jobsDone(ids, "skipped", "att-news backfill disabled: GKG history sampling is not cheap on the free tier (§3.6)");
  run.body.job_ids = []; // already closed
  run.source({ source: "gdelt.gkg", status: "disabled", note: "backfill disabled on free tier; GKG enters the score at 28 days" });
}

serve(FN, {
  gkg, thirdeye, sitemaps, backfill,
  ping: async (run: Run) => {
    run.extra.pong = true;
    run.extra.wall_ms = WALL_MS;
    run.extra.news_version = NEWS_VERSION;
  },
});
