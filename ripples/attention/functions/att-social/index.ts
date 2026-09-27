// att-social — Ripples v5 attention layer, SOCIAL channel collector (W7).
// Modes (ATTENTION_STACK §3.3 / §3.5 / §3.6, budgets per DEMARCATION Q6 as seeded in att_sources):
//   jetstream  Bluesky Jetstream cursor replay (bsky.jet). One websocket per run, <= 10 min of stream, stops at the live
//              edge, the processing budget or the wall budget. Aho-Corasick over registry term keys + aliases (active +
//              panel) with word-boundary checks, facet hashtags mapped to the topic's hashtag keys. Posts per term per
//              hour (active topics) and per day (all), distinct authors via HyperLogLog registers merged in SQL
//              (att_social_accum); totals normaliser '__total__' and stream coverage '__coverage__' (seconds).
//              The cursor is saved in the same transaction as the counts (optimistic check), so nothing is double
//              counted. DIDs are hashed into HLL registers in memory and discarded; no text, handle or DID is stored.
//   mastodon   mastodon.social + mstdn.jp: trends/tags (masto.trends rank + discovery candidates + 7-day history),
//              instance/activity weekly statuses ('__total__'), and /api/v1/tags/{name} 7-day uses/accounts for
//              registry hashtags in rotation (masto.tags).
//   hn         HN Algolia strict (typoTolerance=false, advancedSyntax=true, quoted phrase): stories+comments per term
//              per day for the last `hn_days` complete days (rotation), plus the '__total__' normaliser.
//   stackex    Stack Exchange (app key 'stackexchange_key' from Vault at run time, appended as &key= to
//              api.stackexchange.com requests only; honours `backoff`, stops on throttle): question counts per term per
//              relevant site (att_config 'se.sites_by_category'), plus per-site '__total__' questions per day.
//   backfill   400-day history for merged backfill jobs: params.source = 'hn.algolia' | 'se.api'. Resumable per key.
//   ping       no outbound requests; reports version.
// Every HTTP request goes through politeFetch (source row, RED list, kill switch, lease, robots, spacing, budgets).
// The Jetstream websocket is opened by a minimal RFC 6455 client over TLS so the honest User-Agent is sent and the
// upgrade status is visible (401/403 -> permanent kill, 429/503 -> day kill); the same checks run before it.
import {
  ATT_VERSION, addDays, attSecret, configGet, db, errMsg, hostKilled, hostLease, isRed, killHost, politeFetch, robotsAllowed,
  type Run, serve, sourceInfo, stateGet, stateSet, takeBudget, UA, ymd, type ObsRow, ingest, ingestCandidates,
} from "./att.ts";

const FN = "att-social";
export const SOCIAL_VERSION = "2026-09-25.s5";

// ------------------------------------------------------------------ small helpers
const DAY_S = 86400;
const dayTs = (d: string) => Math.floor(Date.parse(d + "T00:00:00Z") / 1000);
const tsDay = (s: number) => new Date(s * 1000).toISOString().slice(0, 10);
const todayUtc = () => ymd(new Date());
function daysBetween(from: string, toExcl: string): string[] {
  const out: string[] = [];
  for (let d = from; d < toExcl; d = addDays(d, 1)) out.push(d);
  return out;
}
async function socialCfg(): Promise<Record<string, any>> {
  try { return ((await configGet("social")) ?? {}) as Record<string, any>; } catch { return {}; }
}

const HEX = Array.from({ length: 256 }, (_, i) => i.toString(16).padStart(2, "0"));
function toHex(u8: Uint8Array): string { let s = ""; for (let i = 0; i < u8.length; i++) s += HEX[u8[i]]; return s; }

/** 32-bit hash (FNV-1a + murmur3 fmix). Used only to feed HLL registers; the input is discarded immediately. */
function h32(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193); }
  h ^= h >>> 16; h = Math.imul(h, 0x85ebca6b); h ^= h >>> 13; h = Math.imul(h, 0xc2b2ae35); h ^= h >>> 16;
  return h >>> 0;
}
/** HyperLogLog registers (p=8: 256 registers, ~6.5% error; p=6 for hashtags). Only registers leave this function. */
class Sketch {
  reg: Uint8Array;
  constructor(readonly p = 8) { this.reg = new Uint8Array(1 << p); }
  add(h: number) {
    const idx = h >>> (32 - this.p);
    const w = (h << this.p) >>> 0;
    const rho = w === 0 ? 32 - this.p + 1 : Math.clz32(w) + 1;
    if (rho > this.reg[idx]) this.reg[idx] = rho;
  }
  hex() { return toHex(this.reg); }
}

// ------------------------------------------------------------------ registry keys
interface SKey {
  key: string; geo: string; metric: string; match: Record<string, any>; series_id: number | null; topic_id: number | null;
  key_type: string; active: boolean; category: string | null; tags: string[];
}
async function socialKeys(run: Run, source: string, limit = 5000): Promise<SKey[]> {
  if (Array.isArray(run.body?.keys) && run.body.keys.length) {
    return run.body.keys.map((k: any) => ({
      key: String(k.key), geo: k.geo ?? "ALL", metric: k.metric ?? "n", match: k.match ?? {}, series_id: k.series_id ?? null,
      topic_id: k.topic_id ?? null, key_type: k.key_type ?? "term", active: k.active === true, category: k.category ?? null,
      tags: Array.isArray(k.tags) ? k.tags : [],
    }));
  }
  const { data, error } = await db.rpc("att_social_keys", { p_source: source, p_limit: limit });
  if (error) throw new Error(`att_social_keys: ${error.message}`);
  return (data ?? []) as SKey[];
}
/** Category -> SE sites (only relevant for backfill keys, which carry topic_id but no category). */
async function keyCategories(keys: SKey[], source: string): Promise<Map<string, string | null>> {
  const m = new Map<string, string | null>();
  const need = keys.some((k) => k.category == null);
  if (!need) { for (const k of keys) m.set(k.key, k.category); return m; }
  const { data } = await db.rpc("att_social_keys", { p_source: source, p_limit: 5000 });
  for (const r of (data ?? []) as SKey[]) m.set(r.key, r.category);
  for (const k of keys) if (k.category != null) m.set(k.key, k.category);
  return m;
}

// ------------------------------------------------------------------ Aho-Corasick matcher (registry terms)
const WORD_RE = /[\p{L}\p{N}]/u;
function isWordCode(c: number): boolean {
  if (c < 128) return (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c === 95;
  return WORD_RE.test(String.fromCharCode(c));
}
const NO_SPACE_SCRIPT = /[฀-๿぀-ヿ㐀-䶿一-鿿豈-﫿가-힯]/;
interface Pat { len: number; key: number; bL: boolean; bR: boolean }
class AhoCorasick {
  next: Map<number, number>[] = [new Map()];
  fail: number[] = [0];
  out: number[][] = [[]];
  dict: number[] = [0];
  pats: Pat[] = [];
  add(p: string, key: number) {
    let s = 0;
    for (let i = 0; i < p.length; i++) {
      const c = p.charCodeAt(i);
      let n = this.next[s].get(c);
      if (n === undefined) {
        n = this.next.length;
        this.next.push(new Map()); this.fail.push(0); this.out.push([]); this.dict.push(0);
        this.next[s].set(c, n);
      }
      s = n;
    }
    const cjk = NO_SPACE_SCRIPT.test(p);
    this.out[s].push(this.pats.length);
    this.pats.push({ len: p.length, key, bL: !cjk && isWordCode(p.charCodeAt(0)), bR: !cjk && isWordCode(p.charCodeAt(p.length - 1)) });
  }
  build() {
    const q: number[] = [];
    for (const [, n] of this.next[0]) { this.fail[n] = 0; q.push(n); }
    for (let qi = 0; qi < q.length; qi++) {
      const s = q[qi];
      for (const [c, n] of this.next[s]) {
        let f = this.fail[s];
        while (f !== 0 && !this.next[f].has(c)) f = this.fail[f];
        const g = this.next[f].get(c);
        this.fail[n] = g !== undefined && g !== n ? g : 0;
        this.dict[n] = this.out[this.fail[n]].length ? this.fail[n] : this.dict[this.fail[n]];
        q.push(n);
      }
    }
  }
  /** Calls hit(key) for every whole-word occurrence (keys may repeat; caller dedupes per post). */
  scan(t: string, hit: (key: number) => void) {
    let s = 0;
    for (let i = 0; i < t.length; i++) {
      const c = t.charCodeAt(i);
      let n = this.next[s].get(c);
      while (n === undefined && s !== 0) { s = this.fail[s]; n = this.next[s].get(c); }
      s = n ?? 0;
      for (let o = this.out[s].length ? s : this.dict[s]; o !== 0; o = this.dict[o]) {
        for (const pi of this.out[o]) {
          const p = this.pats[pi];
          const st = i - p.len + 1;
          if (p.bL && st > 0 && isWordCode(t.charCodeAt(st - 1))) continue;
          if (p.bR && i + 1 < t.length && isWordCode(t.charCodeAt(i + 1))) continue;
          hit(p.key);
        }
      }
    }
  }
}
let acCache: { sig: string; ac: AhoCorasick; tagMap: Map<string, number[]>; npat: number } | null = null;
function matcherFor(keys: SKey[]) {
  const sig = keys.length + ":" + keys.map((k) => k.key).join("\u0001").length + ":" + keys.slice(0, 5).map((k) => k.key).join("|");
  if (acCache && acCache.sig === sig) return acCache;
  const ac = new AhoCorasick();
  const tagMap = new Map<string, number[]>();
  let npat = 0;
  keys.forEach((k, i) => {
    const forms = new Set<string>();
    const add = (s: unknown) => {
      if (typeof s !== "string") return;
      const f = s.toLowerCase().replace(/\s+/g, " ").trim();
      if (f.length >= 3) forms.add(f);
    };
    add(k.key);
    if (Array.isArray(k.match?.aliases)) for (const a of k.match.aliases) add(a);
    for (const f of forms) { ac.add(f, i); npat++; }
    for (const t of k.tags ?? []) {
      const tl = String(t).toLowerCase().replace(/^#/, "");
      if (tl.length < 3) continue;
      const arr = tagMap.get(tl) ?? [];
      if (!arr.includes(i)) arr.push(i);
      tagMap.set(tl, arr);
    }
  });
  ac.build();
  acCache = { sig, ac, tagMap, npat };
  return acCache;
}

// ------------------------------------------------------------------ minimal websocket client (RFC 6455, client side)
const enc = new TextEncoder();
class WsClient {
  buf = new Uint8Array(1 << 20);
  s = 0;
  e = 0;
  dead = false;
  constructor(readonly conn: any) {}
  private async fill(timeoutMs: number): Promise<number> {
    if (this.dead) return 0;
    if (this.s === this.e) { this.s = 0; this.e = 0; }
    if (this.buf.length - this.e < 65536) {
      if (this.s > 0) { this.buf.copyWithin(0, this.s, this.e); this.e -= this.s; this.s = 0; }
      if (this.buf.length - this.e < 65536) { const nb = new Uint8Array(this.buf.length * 2); nb.set(this.buf.subarray(0, this.e)); this.buf = nb; }
    }
    let timer: number | undefined;
    const to = new Promise<number>((r) => { timer = setTimeout(() => r(-1), timeoutMs) as unknown as number; });
    const rd = (this.conn.read(this.buf.subarray(this.e)) as Promise<number | null>).then((n) => (n === null ? 0 : n), () => 0);
    const n = await Promise.race([rd, to]);
    clearTimeout(timer);
    if (n === -1) { this.dead = true; return -1; } // a read is still pending: stop using this connection
    if (n === 0) { this.dead = true; return 0; }
    this.e += n;
    return n;
  }
  async write(b: Uint8Array) { let o = 0; while (o < b.length) o += await this.conn.write(b.subarray(o)); }
  /** Send the upgrade request; returns the HTTP status (101 = websocket open). */
  async handshake(host: string, pathAndQuery: string, timeoutMs = 10000): Promise<number> {
    const key = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(16))));
    const req = `GET ${pathAndQuery} HTTP/1.1\r\nHost: ${host}\r\nUser-Agent: ${UA}\r\nUpgrade: websocket\r\n` +
      `Connection: Upgrade\r\nSec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n\r\n`;
    await this.write(enc.encode(req));
    while (true) {
      const view = this.buf.subarray(this.s, this.e);
      let idx = -1;
      for (let i = 3; i < view.length; i++) {
        if (view[i] === 10 && view[i - 1] === 13 && view[i - 2] === 10 && view[i - 3] === 13) { idx = i + 1; break; }
      }
      if (idx > 0) {
        const head = new TextDecoder().decode(view.subarray(0, idx));
        this.s += idx;
        const m = /^HTTP\/1\.[01] (\d{3})/.exec(head);
        return m ? Number(m[1]) : 0;
      }
      if (this.e - this.s > 65536) return 0;
      const n = await this.fill(timeoutMs);
      if (n <= 0) return 0;
    }
  }
  /** Next frame, or 'timeout' / null (closed). The payload view is valid until the next call. */
  async frame(timeoutMs: number): Promise<{ fin: boolean; op: number; data: Uint8Array } | "timeout" | null> {
    while (true) {
      const avail = this.e - this.s;
      if (avail >= 2) {
        const b = this.buf, s = this.s;
        const b1 = b[s + 1];
        const l7 = b1 & 127;
        const masked = (b1 & 128) !== 0;
        const hdr = 2 + (l7 === 126 ? 2 : l7 === 127 ? 8 : 0) + (masked ? 4 : 0);
        if (avail >= hdr) {
          let len = l7;
          if (l7 === 126) len = (b[s + 2] << 8) | b[s + 3];
          else if (l7 === 127) len = (b[s + 6] * 16777216 + ((b[s + 7] << 16) | (b[s + 8] << 8) | b[s + 9])) + b[s + 5] * 2 ** 32;
          if (len > 16 * 1024 * 1024) { this.dead = true; return null; }
          if (avail >= hdr + len) {
            let data = b.subarray(s + hdr, s + hdr + len);
            if (masked) {
              const mk = b.subarray(s + hdr - 4, s + hdr);
              data = data.slice();
              for (let i = 0; i < data.length; i++) data[i] ^= mk[i & 3];
            }
            this.s += hdr + len;
            return { fin: (b[s] & 128) !== 0, op: b[s] & 15, data };
          }
        }
      }
      const n = await this.fill(timeoutMs);
      if (n === -1) return "timeout";
      if (n === 0) return null;
    }
  }
  async send(op: number, payload: Uint8Array) {
    if (this.dead || payload.length > 125) return;
    const mk = crypto.getRandomValues(new Uint8Array(4));
    const f = new Uint8Array(6 + payload.length);
    f[0] = 0x80 | op; f[1] = 0x80 | payload.length; f.set(mk, 2);
    for (let i = 0; i < payload.length; i++) f[6 + i] = payload[i] ^ mk[i & 3];
    try { await this.write(f); } catch { /* closing anyway */ }
  }
  async close() {
    await this.send(8, new Uint8Array([0x03, 0xe8]));
    try { this.conn.close(); } catch { /* already closed */ }
    this.dead = true;
  }
}

// ------------------------------------------------------------------ mode: jetstream (bsky.jet)
interface JetState { cursor: number; until?: number; at?: string; lag_s?: number; host?: string; posts?: number; stream_min?: number }
interface JetHealth { fails: number; fail_until?: string; last_error?: string; host?: string }
interface Bucket { n: number; hll: Sketch; keyN: Int32Array; keyH: Map<number, Sketch> }

async function modeJetstream(run: Run) {
  const SRC = "bsky.jet";
  const t0 = Date.now();
  const cfg = await socialCfg();
  const src = await sourceInfo(SRC);
  if (!src?.enabled) { run.source({ source: SRC, status: "disabled" }); return; }
  // lanes: 'live' follows the present (state jet.cursor); 'backfill' replays the Jetstream buffer from jet.bf.cursor up
  // to jet.bf.until (= where the live lane started), so the two never overlap and nothing is counted twice.
  const lane = run.params.lane === "backfill" ? "backfill" : "live";
  const stateKey = lane === "live" ? "jet.cursor" : "jet.bf";
  const st = (await stateGet(stateKey)) as JetState | null;
  if (lane === "backfill" && !(typeof st?.cursor === "number" && typeof st?.until === "number" && st.cursor < st.until)) {
    run.source({ source: SRC, status: "ok", note: "backfill lane: nothing to replay" });
    return;
  }
  const lagNow = typeof st?.cursor === "number" ? (Date.now() * 1000 - st.cursor) / 1e6 : 0;
  // normal runs stream <= 10 min (§3.3); catch-up (lag > 30 min, or the backfill lane) may stream up to
  // jet_catchup_max_min (default 20) — the processing budget still stops the run first if needed
  const catchup = lane === "backfill" || lagNow > 1800;
  const capMin = catchup ? Math.min(30, Number(cfg.jet_catchup_max_min ?? 20)) : 10;
  const maxMin = Math.min(capMin, Math.max(0.25, Number(run.params.max_stream_min ?? (catchup ? capMin : cfg.jet_max_stream_min ?? 10))));
  const procBudget = Math.max(100, Number(run.params.proc_ms ?? cfg.jet_proc_ms ?? 1100));
  const readWallMs = Math.max(5000, run.timeLeft() - 30000);
  const health = ((await stateGet("jet.health")) ?? { fails: 0 }) as JetHealth;
  if (health.fail_until && Date.parse(health.fail_until) > Date.now() && run.params.force !== true) {
    run.source({ source: SRC, status: "partial", note: `backoff until ${health.fail_until} after ${health.fails} failures` });
    return;
  }
  const hosts: string[] = (Array.isArray(cfg.jet_hosts) && cfg.jet_hosts.length ? cfg.jet_hosts : src.hosts).map(String);
  const host = String(run.params.host ?? health.host ?? cfg.jet_host ?? hosts[0]).toLowerCase();
  if (!src.hosts.map((h) => h.toLowerCase()).includes(host)) { run.source({ source: SRC, status: "disabled", note: `host ${host} not in att_sources.hosts` }); return; }
  const httpsUrl = new URL(`https://${host}/subscribe`);
  if (isRed(httpsUrl)) { run.skip(host, "red_source"); run.source({ source: SRC, status: "disabled", note: "red" }); return; }
  const killed = await hostKilled(run, host);
  if (killed) { run.skip(host, killed); run.source({ source: SRC, status: killed.startsWith("host_killed_429") ? "host_killed_429" : "http_error", note: killed }); return; }
  // one replay at a time across all invocations (both Jetstream hosts share one cursor)
  if (!(await hostLease(run, "jetstream.bsky.network"))) { run.source({ source: SRC, status: "partial", note: "another jetstream run holds the lease" }); return; }
  if (!(await robotsAllowed(run, httpsUrl))) { run.skip(host, "robots_disallow"); run.source({ source: SRC, status: "robots_disallow" }); return; }
  const startNowUs = Date.now() * 1000;
  const backMin = Number(run.params.start_back_min ?? cfg.jet_start_back_min ?? 10);
  const cursorFrom = typeof st?.cursor === "number" ? st.cursor : Math.floor(startNowUs - backMin * 60e6);
  const stopAtUs = Math.min(cursorFrom + maxMin * 60e6, startNowUs - 5e6, lane === "backfill" ? st!.until! : Infinity);
  if (stopAtUs <= cursorFrom + 1e6) { run.source({ source: SRC, status: "ok", note: "already at live edge" }); return; }
  const g = await takeBudget(SRC, 1); // one websocket connection = one unit of the daily cap
  run.granted += g;
  if (g <= 0) { run.partial = true; run.source({ source: SRC, status: "budget_exhausted" }); return; }
  run.reqBySource[SRC] = (run.reqBySource[SRC] ?? 0) + 1;

  const keys = await socialKeys(run, SRC);
  const { ac, tagMap, npat } = matcherFor(keys);
  const nk = keys.length;

  const hours = new Map<number, Bucket>();
  const days = new Map<string, Bucket>();
  const newBucket = (): Bucket => ({ n: 0, hll: new Sketch(8), keyN: new Int32Array(nk), keyH: new Map() });
  const tagAgg = new Map<string, { day: string; tag: string; n: number; sk: Sketch | null }>();
  let nMsgs = 0, nPosts = 0, firstT = 0, lastT = 0, procMs = 0, stop = "";
  const hit = new Set<number>();

  const onMessage = (m: string) => {
    const ti = m.indexOf('"time_us":');
    if (ti < 0) return;
    let t = 0;
    for (let i = ti + 10; i < m.length; i++) { const c = m.charCodeAt(i); if (c < 48 || c > 57) break; t = t * 10 + (c - 48); }
    if (t >= stopAtUs) { stop = lane === "backfill" && stopAtUs === st!.until ? "lane_done" : t >= startNowUs - 5e6 ? "live_edge" : "window"; return; }
    nMsgs++;
    if (!firstT) firstT = t;
    lastT = t;
    if (m.indexOf('"operation":"create"') < 0 || m.indexOf('"app.bsky.feed.post"') < 0) return;
    let j: any;
    try { j = JSON.parse(m); } catch { return; }
    const rec = j?.commit?.record;
    if (!rec || typeof rec !== "object" || j?.commit?.collection !== "app.bsky.feed.post") return;
    const ah = h32(typeof j.did === "string" ? j.did : ""); // author hashed for HLL only, never stored
    nPosts++;
    const hIdx = Math.floor(t / 3600e6);
    let hb = hours.get(hIdx);
    if (!hb) { hb = newBucket(); hours.set(hIdx, hb); }
    const day = new Date(hIdx * 3600000).toISOString().slice(0, 10);
    let db_ = days.get(day);
    if (!db_) { db_ = newBucket(); days.set(day, db_); }
    hb.n++; hb.hll.add(ah); db_.n++; db_.hll.add(ah);
    hit.clear();
    const text = typeof rec.text === "string" ? rec.text.toLowerCase() : "";
    if (text) ac.scan(text, (k) => hit.add(k));
    if (Array.isArray(rec.facets)) {
      for (const f of rec.facets) {
        if (!Array.isArray(f?.features)) continue;
        for (const ft of f.features) {
          if (ft?.$type !== "app.bsky.richtext.facet#tag" || typeof ft.tag !== "string") continue;
          const tag = ft.tag.toLowerCase().replace(/^#+/, "").trim();
          if (!tag || tag.length > 64) continue;
          const km = tagMap.get(tag);
          if (km) for (const k of km) hit.add(k);
          const tk = day + "\t" + tag;
          let ta = tagAgg.get(tk);
          if (!ta) { ta = { day, tag, n: 0, sk: null }; tagAgg.set(tk, ta); }
          ta.n++;
          if (!ta.sk) ta.sk = new Sketch(6);
          ta.sk.add(ah);
        }
      }
    }
    for (const k of hit) {
      hb.keyN[k]++; db_.keyN[k]++;
      let s1 = hb.keyH.get(k); if (!s1) { s1 = new Sketch(8); hb.keyH.set(k, s1); } s1.add(ah);
      let s2 = db_.keyH.get(k); if (!s2) { s2 = new Sketch(8); db_.keyH.set(k, s2); } s2.add(ah);
    }
  };

  // ---- connect (manual websocket so the honest UA is sent and the upgrade status is visible)
  const path = `/subscribe?wantedCollections=app.bsky.feed.post&cursor=${cursorFrom}`;
  let ws: WsClient | null = null;
  let status = 0;
  try {
    const conn = await (globalThis as any).Deno.connectTls({ hostname: host, port: 443 });
    ws = new WsClient(conn);
    status = await ws.handshake(host, path);
  } catch (e) {
    run.errors.push(`jetstream connect ${host}: ${errMsg(e)}`);
  }
  run.count(host, status);
  if (status !== 101) {
    try { ws?.conn.close(); } catch { /* ignore */ }
    if ([401, 403, 429, 503].includes(status)) await killHost(run, host, status, SRC);
    const fails = (health.fails ?? 0) + 1;
    const alt = hosts.find((h) => h.toLowerCase() !== host) ?? host;
    await stateSet("jet.health", {
      fails, host: alt, last_error: `upgrade status ${status}`,
      fail_until: new Date(Date.now() + Math.min(60, 5 * 2 ** Math.min(fails - 1, 4)) * 60000).toISOString(),
    });
    run.partial = true;
    run.source({ source: SRC, status: status === 429 ? "host_killed_429" : "http_error", note: `websocket upgrade status ${status}` });
    return;
  }

  // ---- read the replay
  const dec = new TextDecoder();
  const frags: Uint8Array[] = [];
  const readUntil = Date.now() + readWallMs;
  while (!stop) {
    if (Date.now() > readUntil) { stop = "wall"; break; }
    if (procMs > procBudget) { stop = "proc_budget"; break; }
    const f = await ws!.frame(6000);
    if (f === "timeout") { stop = "idle"; break; }
    if (f === null) { stop = "closed"; break; }
    const p0 = performance.now();
    if (f.op === 9) { await ws!.send(10, f.data.slice(0, 125)); continue; }
    if (f.op === 8) { stop = "server_close"; break; }
    if (f.op === 10) continue;
    if (f.op === 0 || !f.fin) {
      frags.push(f.data.slice());
      if (!f.fin) continue;
      const tot = frags.reduce((a, b) => a + b.length, 0);
      const all = new Uint8Array(tot);
      let o = 0;
      for (const x of frags) { all.set(x, o); o += x.length; }
      frags.length = 0;
      onMessage(dec.decode(all));
    } else if (f.op === 1 || f.op === 2) {
      onMessage(dec.decode(f.data));
    }
    procMs += performance.now() - p0;
  }
  await ws!.close();

  // ---- next cursor and coverage
  let nextCursor: number;
  if (stop === "window" || stop === "live_edge" || stop === "lane_done") nextCursor = stopAtUs;
  else nextCursor = lastT ? lastT + 1 : cursorFrom;
  let coverFrom = cursorFrom;
  let gapNote: string | null = null;
  if (firstT && firstT - cursorFrom > 120e6) { coverFrom = firstT; gapNote = `replay started ${Math.round((firstT - cursorFrom) / 60e6)} min after cursor (buffer gap)`; }
  const coverage = new Map<number, number>(); // hour idx -> seconds
  if (nextCursor > coverFrom && nMsgs > 0) {
    for (let a = coverFrom; a < nextCursor;) {
      const hIdx = Math.floor(a / 3600e6);
      const b = Math.min(nextCursor, (hIdx + 1) * 3600e6);
      coverage.set(hIdx, (coverage.get(hIdx) ?? 0) + (b - a) / 1e6);
      a = b;
    }
  }
  const covDays = new Map<string, number>();
  for (const [h, s] of coverage) { const d = new Date(h * 3600000).toISOString().slice(0, 10); covDays.set(d, (covDays.get(d) ?? 0) + s); }

  // ---- rows (added to existing values in SQL)
  const rows: Record<string, unknown>[] = [];
  const hourIdx = new Set<number>([...hours.keys(), ...coverage.keys()]);
  for (const h of hourIdx) {
    const ts = new Date(h * 3600000).toISOString();
    const b = hours.get(h);
    rows.push({ source: SRC, key: "__total__", ts, add: b?.n ?? 0, ...(b && b.n ? { reg: b.hll.hex() } : {}) });
    rows.push({ source: SRC, key: "__coverage__", metric: "s", ts, add: Math.round(coverage.get(h) ?? 0) });
    keys.forEach((k, i) => {
      if (!k.active) return; // free tier: hourly series only for active topics
      const n = b ? b.keyN[i] : 0;
      rows.push({ source: SRC, key: k.key, ts, add: n, ...(n ? { reg: b!.keyH.get(i)!.hex() } : {}) });
    });
  }
  const dayIdx = new Set<string>([...days.keys(), ...covDays.keys()]);
  for (const d of dayIdx) {
    const b = days.get(d);
    rows.push({ source: SRC, key: "__total__", day: d, add: b?.n ?? 0, ...(b && b.n ? { reg: b.hll.hex() } : {}) });
    rows.push({ source: SRC, key: "__coverage__", metric: "s", day: d, add: Math.round(covDays.get(d) ?? 0) });
    keys.forEach((k, i) => {
      const n = b ? b.keyN[i] : 0;
      rows.push({ source: SRC, key: k.key, day: d, add: n, ...(n ? { reg: b!.keyH.get(i)!.hex() } : {}) });
    });
  }
  const tagRows = [...tagAgg.values()].sort((a, b) => b.n - a.n).slice(0, 3000)
    .map((t) => ({ day: t.day, tag: t.tag, n: t.n, ...(t.n >= 2 && t.sk ? { reg: t.sk.hex() } : {}) }));

  const lagS = Math.max(0, Math.round((Date.now() * 1000 - nextCursor) / 1e6));
  const streamMin = Math.round(((nextCursor - cursorFrom) / 60e6) * 100) / 100;
  const matchedKeys = new Set<number>();
  for (const b of days.values()) b.keyN.forEach((n, i) => { if (n) matchedKeys.add(i); });
  const top = [...matchedKeys].map((i) => [keys[i].key, [...days.values()].reduce((a, b) => a + b.keyN[i], 0)] as [string, number])
    .sort((a, b) => b[1] - a[1]).slice(0, 10);
  Object.assign(run.extra, {
    cursor_from: cursorFrom, cursor_to: nextCursor, posts: nPosts, messages: nMsgs, stream_min: streamMin, lag_s: lagS,
    stop, proc_ms: Math.round(procMs), keys: nk, patterns: npat, keys_matched: matchedKeys.size, top_keys: top,
    hashtags_seen: tagAgg.size, social_version: SOCIAL_VERSION, host, lane, catchup, ...(gapNote ? { gap: gapNote } : {}),
  });

  if (run.dryRun) {
    run.source({ source: SRC, status: "ok", keys: nk, rows: rows.length, ms: Date.now() - t0, note: "dry_run" });
    return;
  }
  if (nMsgs === 0) {
    run.partial = true;
    run.source({ source: SRC, status: "partial", keys: nk, rows: 0, ms: Date.now() - t0, note: `no messages (${stop})` });
    await stateSet("jet.health", { fails: (health.fails ?? 0) + 1, host, last_error: `no messages (${stop})` });
    return;
  }
  const newState: JetState = {
    cursor: nextCursor, ...(lane === "backfill" ? { until: st!.until } : {}), at: new Date().toISOString(), lag_s: lagS, host,
    posts: nPosts, stream_min: streamMin,
  };
  const { data, error } = await db.rpc("att_social_accum", {
    p_rows: rows,
    p_state: { k: stateKey, v: newState, expect: typeof st?.cursor === "number" ? st.cursor : null },
    p_tags: { source: SRC, rows: tagRows },
  });
  if (error) {
    run.errors.push(`att_social_accum: ${error.message}`);
    run.source({ source: SRC, status: "http_error", keys: nk, rows: 0, ms: Date.now() - t0, note: "accumulate failed; cursor not advanced" });
    return;
  }
  const d = data as { daily?: number; hourly?: number; series_new?: number; rejected?: unknown[]; tags?: number };
  run.rows.obs += d?.daily ?? 0;
  run.rows.obs_hourly += d?.hourly ?? 0;
  run.rows.series_new += d?.series_new ?? 0;
  if (Array.isArray(d?.rejected) && d!.rejected.length) run.rejected.push(...d!.rejected.slice(0, 20));
  run.extra.tags_upserted = d?.tags ?? 0;
  if ((health.fails ?? 0) > 0 || health.host !== host) await stateSet("jet.health", { fails: 0, host });
  if (lane === "live" && lagS > 6 * 3600) run.extra.lag_alert = true; // §8: lag > 6 h

  // hashtag discovery candidates (burst z vs trailing 7 days), about once an hour and after each day rolls over
  const lastDay = tsDay(Math.floor((nextCursor - 1) / 1e6));
  const prevState = st?.cursor ? tsDay(Math.floor(st.cursor / 1e6)) : lastDay;
  if (lane === "live" && (new Date().getUTCMinutes() < 5 || prevState !== lastDay || run.params.candidates === true)) {
    const dd = prevState !== lastDay ? [prevState, lastDay] : [lastDay];
    for (const day of dd) {
      const { data: c, error: ce } = await db.rpc("att_social_tag_cands", { p_source: SRC, p_day: day, p_limit: 100, p_min_distinct: 50 });
      if (ce) run.errors.push(`att_social_tag_cands: ${ce.message}`);
      else { run.extra[`candidates_${day}`] = c; run.rows.candidates += Number((c as any)?.rows ?? 0); }
    }
  }
  const partial = stop !== "window" && stop !== "live_edge" && stop !== "lane_done";
  if (partial) run.partial = true;
  run.nextCursor = nextCursor;
  run.source({ source: SRC, status: partial ? "partial" : "ok", keys: nk, rows: (d?.daily ?? 0) + (d?.hourly ?? 0), ms: Date.now() - t0, note: `stop=${stop}` });
}

// ------------------------------------------------------------------ mode: mastodon (masto.tags, masto.trends)
async function jsonOf(res: Response | null): Promise<any | null> {
  if (!res) return null;
  if (!res.ok) { await res.body?.cancel(); return null; }
  try { return await res.json(); } catch { return null; }
}
function slot(key: string, n: number): number { return h32(key) % n; }

async function modeMastodon(run: Run) {
  const t0 = Date.now();
  const cfg = await socialCfg();
  const instances: string[] = (run.params.instances ?? cfg.masto_instances ?? ["mastodon.social", "mstdn.jp"]).map(String);
  const split: Record<string, number> = cfg.masto_split ?? {};
  const today = todayUtc();
  const slice = Number.isFinite(Number(run.params.slice)) ? Number(run.params.slice) : null;
  let keys = (await socialKeys(run, "masto.tags")).filter((k) => /^[\p{L}\p{N}_]+$/u.test(k.key));
  if (slice) keys = keys.filter((k) => slot(k.key, 3) === (slice - 1) % 3);
  const rows: ObsRow[] = [];
  const cands: Record<string, unknown>[] = [];
  let tagsFetched = 0, trendsN = 0;
  const hist = (inst: string, name: string, h: any[], key: string) => {
    for (const x of h ?? []) {
      const d = tsDay(Number(x?.day));
      if (!/^\d{4}-\d{2}-\d{2}$/.test(d) || d >= today) continue; // complete days only
      const uses = Number(x?.uses), acc = Number(x?.accounts);
      if (!Number.isFinite(uses)) continue;
      rows.push({ source: "masto.tags", key, geo: inst, day: d, value: uses, aux: Number.isFinite(acc) ? acc : null });
    }
    void name;
  };
  for (const inst of instances) {
    if (run.outOfTime(8000)) { run.partial = true; break; }
    // 1) trending tags (rank + discovery + free 7-day history)
    const tr = await jsonOf(await politeFetch(run, `https://${inst}/api/v1/trends/tags?limit=20`, { source: "masto.trends" }));
    if (Array.isArray(tr)) {
      const N = tr.length;
      tr.forEach((t: any, i: number) => {
        const name = String(t?.name ?? "").toLowerCase();
        if (!name || !/^[\p{L}\p{N}_]+$/u.test(name)) return;
        const rank = i + 1;
        trendsN++;
        rows.push({ source: "masto.trends", metric: "rank", key: name, geo: inst, day: today, value: rank });
        hist(inst, name, t?.history, name);
        const h = (t?.history ?? []).map((x: any) => Number(x?.uses) || 0); // newest first
        const last3 = h.slice(0, 3).reduce((a: number, b: number) => a + b, 0);
        const prior4 = h.slice(3, 7).reduce((a: number, b: number) => a + b, 0);
        const ratio = prior4 > 0 ? (last3 / 3) / (prior4 / 4) : null;
        const accts = (t?.history ?? []).slice(0, 3).reduce((a: number, x: any) => a + (Number(x?.accounts) || 0), 0);
        cands.push({
          day: today, source: "masto.trends", geo: inst, label: "#" + name, rank, value: last3,
          evidence: Math.max(0, Math.min(1, 1 - Math.log(rank) / Math.log(N + 1))),
          meta: { rank, q: ratio === null ? null : Math.round(ratio * 100) / 100, n_posts: last3, total: accts },
        });
      });
    }
    // 2) instance activity (weekly statuses) as the '__total__' normaliser, once a day per instance
    const ak = `masto.activity:${inst}`;
    const last = (await stateGet(ak)) as { day?: string } | null;
    if (last?.day !== today) {
      const act = await jsonOf(await politeFetch(run, `https://${inst}/api/v1/instance/activity`, { source: "masto.tags" }));
      if (Array.isArray(act)) {
        act.slice(1).forEach((w: any) => { // [0] is the current, incomplete week
          const d = tsDay(Number(w?.week));
          const v = Number(w?.statuses);
          if (/^\d{4}-\d{2}-\d{2}$/.test(d) && Number.isFinite(v)) {
            rows.push({ source: "masto.tags", metric: "statuses", key: "__total__", geo: inst, day: d, value: v, meta: { weekly: true } });
          }
        });
        if (!run.dryRun) await stateSet(ak, { day: today });
      }
    }
    // 3) registry hashtags in rotation
    if (!keys.length) continue;
    const want = Math.max(0, Math.floor(Number(run.params.per_instance ?? split[inst] ?? 16)));
    const rk = `masto.rot:${inst}:${slice ?? 0}`;
    const rot = (await stateGet(rk)) as { off?: number } | null;
    let off = Math.max(0, Number(rot?.off ?? 0)) % keys.length;
    let done = 0;
    for (; done < Math.min(want, keys.length); done++) {
      if (run.outOfTime(6000)) { run.partial = true; break; }
      const k = keys[(off + done) % keys.length];
      const res = await politeFetch(run, `https://${inst}/api/v1/tags/${encodeURIComponent(k.key)}`, { source: "masto.tags" });
      if (!res) break; // cap, budget, kill or robots: stop this instance for the run
      if (res.status === 404) {
        await res.body?.cancel();
        for (let i = 1; i <= 7; i++) rows.push({ source: "masto.tags", key: k.key, geo: inst, day: addDays(today, -i), value: 0, aux: 0 });
        tagsFetched++;
        continue;
      }
      const j = await jsonOf(res);
      if (j && Array.isArray(j.history)) { hist(inst, k.key, j.history, k.key); tagsFetched++; }
    }
    off = (off + done) % keys.length;
    if (!run.dryRun) await stateSet(rk, { off, at: new Date().toISOString(), n: keys.length });
  }
  const r = await ingest(run, rows);
  await ingestCandidates(run, cands);
  Object.assign(run.extra, { tags: tagsFetched, trends: trendsN, instances, social_version: SOCIAL_VERSION });
  run.source({ source: "masto.tags", status: run.partial ? "partial" : "ok", keys: tagsFetched, rows: r.rows, ms: Date.now() - t0 });
  run.source({ source: "masto.trends", status: trendsN ? "ok" : "partial", keys: trendsN, rows: trendsN, ms: Date.now() - t0 });
}

// ------------------------------------------------------------------ HN Algolia (strict)
const HN = "https://hn.algolia.com/api/v1/search_by_date";
interface HnRes { nbHits: number; times: number[]; exhaustive: boolean }
function hnTerm(term: string): string {
  const t = term.replace(/["“”]/g, " ").replace(/^[-\s]+/, "").replace(/\s+/g, " ").trim();
  return `"${t}"`;
}
async function hnQuery(run: Run, term: string | null, a: number, b: number, hitsPerPage: number): Promise<HnRes | null> {
  const q = new URLSearchParams({
    tags: "(story,comment)", numericFilters: `created_at_i>=${a},created_at_i<${b}`, hitsPerPage: String(hitsPerPage),
    // strict: exact quoted phrase, no typos, no prefix matching ("jev" must not match "jevons"), no plural folding
    typoTolerance: "false", advancedSyntax: "true", queryType: "prefixNone", ignorePlurals: "false",
    removeStopWords: "false", removeWordsIfNoResults: "none", attributesToRetrieve: "created_at_i",
    // text fields only: an author name (e.g. user "jev") or a username prefix must not count as a mention
    restrictSearchableAttributes: "title,story_text,comment_text,url",
    attributesToHighlight: run.params.debug === true ? "title,story_text,comment_text,url" : "", attributesToSnippet: "",
    analytics: "false",
  });
  q.set("query", term === null ? "" : hnTerm(term));
  const res = await politeFetch(run, `${HN}?${q}`, { source: "hn.algolia" });
  if (!res) return null;
  if (!res.ok) { run.errors.push(`hn.algolia http ${res.status}`); await res.body?.cancel(); return null; }
  const j = await res.json().catch(() => null);
  if (!j || typeof j.nbHits !== "number") { run.errors.push("hn.algolia bad json"); return null; }
  const times = Array.isArray(j.hits) ? j.hits.map((h: any) => Number(h?.created_at_i)).filter((x: number) => Number.isFinite(x)) : [];
  if (run.params.debug === true && term !== null && Array.isArray(j.hits)) {
    // diagnostics only: which attribute and which words matched (never the text itself)
    const dbg = (run.extra.hn_debug ??= {}) as Record<string, unknown>;
    if (!dbg[term]) {
      dbg[term] = { nbHits: j.nbHits, params_echo: typeof j.params === "string" ? j.params.slice(0, 400) : null,
        matches: j.hits.slice(0, 5).map((h: any) => Object.entries(h?._highlightResult ?? {})
          .filter(([, v]: [string, any]) => v?.matchLevel && v.matchLevel !== "none")
          .map(([k, v]: [string, any]) => ({ attr: k, words: v.matchedWords, full: v.fullyHighlighted ?? null }))) };
    }
  }
  return { nbHits: j.nbHits, times, exhaustive: j.exhaustiveNbHits !== false && j.exhaustive?.nbHits !== false };
}
/**
 * Daily counts for [a, b) (unix seconds on day boundaries), newest windows first. Returns counts for days >= doneFrom
 * (contiguous, complete) — resumable: call again with b = doneFrom.
 */
async function hnCount(run: Run, term: string, a: number, b: number, maxCalls: number) {
  const counts = new Map<string, number>();
  const est = new Set<string>();
  let calls = 0;
  let doneFrom = b;
  const stack: Array<{ a: number; b: number; exp: number | null }> = [{ a, b, exp: null }];
  let complete = true;
  while (stack.length) {
    const w = stack.pop()!;
    const nd = Math.round((w.b - w.a) / DAY_S);
    if (calls >= maxCalls || run.outOfTime(4000)) { complete = false; break; }
    const dense1 = nd <= 1 && w.exp !== null && w.exp > 1000;
    const r = await hnQuery(run, term, w.a, w.b, dense1 ? 0 : 1000);
    calls++;
    if (!r) { complete = false; break; }
    if (!dense1 && r.nbHits <= r.times.length) {
      for (let d = w.a; d < w.b; d += DAY_S) counts.set(tsDay(d), 0);
      for (const t of r.times) if (t >= w.a && t < w.b) { const d = tsDay(t); counts.set(d, (counts.get(d) ?? 0) + 1); }
      doneFrom = w.a;
      continue;
    }
    if (nd <= 1) {
      counts.set(tsDay(w.a), r.nbHits);
      if (!r.exhaustive) est.add(tsDay(w.a));
      doneFrom = w.a;
      continue;
    }
    // split into k day-aligned parts expected <= ~700 hits each; push oldest first so the newest is processed first
    const k = Math.min(nd, Math.max(2, Math.ceil(r.nbHits / 700)));
    const step = Math.max(1, Math.floor(nd / k));
    const parts: Array<{ a: number; b: number; exp: number }> = [];
    for (let s = w.a; s < w.b; s += step * DAY_S) {
      const e = Math.min(w.b, s + step * DAY_S);
      parts.push({ a: s, b: e, exp: (r.nbHits * (e - s)) / (w.b - w.a) });
    }
    for (const p of parts) stack.push(p); // last pushed (newest) is popped first
  }
  // keep only the complete, contiguous newest part
  for (const d of [...counts.keys()]) if (dayTs(d) < doneFrom) counts.delete(d);
  return { counts, est, doneFrom, complete: complete && doneFrom <= a, calls };
}
function hnRows(term: string, counts: Map<string, number>, est: Set<string>, topic: number | null): ObsRow[] {
  return [...counts].map(([d, n]) => ({
    source: "hn.algolia", key: term, day: d, value: n, topic_id: topic ?? null, ...(est.has(d) ? { meta: { est: true } } : {}),
  }));
}
/** '__total__' (stories + comments per day), for days [from, toExcl), newest first; resumable progress in state. */
async function hnTotals(run: Run, from: string, toExcl: string, maxCalls: number): Promise<number> {
  const rows: ObsRow[] = [];
  let calls = 0;
  for (let d = addDays(toExcl, -1); d >= from; d = addDays(d, -1)) {
    if (calls >= maxCalls || run.outOfTime(5000)) break;
    const r = await hnQuery(run, null, dayTs(d), dayTs(d) + DAY_S, 0);
    calls++;
    if (!r) break;
    rows.push({ source: "hn.algolia", key: "__total__", day: d, value: r.nbHits, ...(r.exhaustive ? {} : { meta: { est: true } }) });
  }
  await ingest(run, rows);
  return rows.length ? dayTs(rows[rows.length - 1].day!) : dayTs(toExcl);
}

async function modeHn(run: Run) {
  const t0 = Date.now();
  const cfg = await socialCfg();
  const nDays = Math.max(1, Math.min(14, Number(run.params.days ?? cfg.hn_days ?? 3)));
  const today = todayUtc();
  const from = addDays(today, -nDays);
  // totals for the window (once a day), then extend the totals history backwards (<= 10 calls per run)
  const tl = (await stateGet("hn.total.last")) as { day?: string } | null;
  if (tl?.day !== today) {
    const got = await hnTotals(run, from, today, nDays);
    if (got <= dayTs(from) && !run.dryRun) await stateSet("hn.total.last", { day: today });
  }
  await hnTotalsBackfill(run, 10);
  const keys = await socialKeys(run, "hn.algolia");
  const rot = (await stateGet("hn.rot")) as { off?: number } | null;
  let off = keys.length ? Math.max(0, Number(rot?.off ?? 0)) % keys.length : 0;
  const rows: ObsRow[] = [];
  let done = 0;
  const cap = Math.max(1, Number(run.params.max_calls_per_term ?? 6));
  for (; done < keys.length; done++) {
    if (run.outOfTime(6000)) { run.partial = true; break; }
    const k = keys[(off + done) % keys.length];
    const r = await hnCount(run, k.key, dayTs(from), dayTs(today), cap);
    for (const row of hnRows(k.key, r.counts, r.est, k.topic_id)) rows.push(row);
    if (!r.complete) { run.partial = true; if (r.counts.size === 0) break; }
    if (rows.length >= 1500) { await ingest(run, rows.splice(0)); }
    if (run.skipped.some((s) => s.host === "hn.algolia.com")) break; // cap / budget / kill: stop
  }
  await ingest(run, rows);
  off = keys.length ? (off + done) % keys.length : 0;
  if (!run.dryRun) await stateSet("hn.rot", { off, at: new Date().toISOString(), n: keys.length });
  Object.assign(run.extra, { terms: done, window: [from, today], social_version: SOCIAL_VERSION });
  run.source({ source: "hn.algolia", status: run.partial ? "partial" : "ok", keys: done, rows: run.rows.obs, ms: Date.now() - t0 });
}

/** Extend the '__total__' history back to 400 days before today (resumable; state 'hn.total.bf'). */
async function hnTotalsBackfill(run: Run, maxCalls: number) {
  const today = todayUtc();
  const floor = addDays(today, -401);
  const st = (await stateGet("hn.total.bf")) as { done_from?: string } | null;
  const doneFrom = st?.done_from ?? addDays(today, -3);
  if (doneFrom <= floor || maxCalls <= 0) return;
  const got = await hnTotals(run, floor, doneFrom, maxCalls);
  if (!run.dryRun && got < dayTs(doneFrom)) await stateSet("hn.total.bf", { done_from: tsDay(got), at: new Date().toISOString() });
}

// ------------------------------------------------------------------ Stack Exchange (keyed quota: 10,000/day)
const SE = "https://api.stackexchange.com/2.3";
const SE_FILTER_INCLUDE = ".backoff;.has_more;.items;.quota_remaining;.total;question.creation_date";
interface SeCtx { filter: string | null; backoffUntil: number; stop: string | null; quota: number | null; minQuota: number; key: string | null }
async function seGet(run: Run, ctx: SeCtx, path: string, params: Record<string, string>): Promise<any | null> {
  if (ctx.stop) return null;
  if (ctx.backoffUntil > Date.now()) {
    const w = ctx.backoffUntil - Date.now();
    if (w > 15000 || run.timeLeft() - w < 8000) { ctx.stop = "backoff"; run.partial = true; return null; }
    await new Promise((r) => setTimeout(r, w));
  }
  // the app key only ever goes to api.stackexchange.com (SE is a fixed https://api.stackexchange.com base)
  const q = new URLSearchParams(params);
  if (ctx.key) q.set("key", ctx.key);
  const res = await politeFetch(run, `${SE}${path}?${q}`, { source: "se.api" });
  if (!res) { ctx.stop = "not_fetched"; return null; }
  const j = await res.json().catch(() => null);
  if (j && typeof j.backoff === "number" && j.backoff > 0) {
    ctx.backoffUntil = Date.now() + j.backoff * 1000;
    if (!run.dryRun) await stateSet("se.backoff", { until: new Date(ctx.backoffUntil).toISOString(), path });
  }
  if (j && typeof j.quota_remaining === "number") {
    ctx.quota = j.quota_remaining;
    run.extra.quota_remaining = j.quota_remaining;
    if (j.quota_remaining < ctx.minQuota) { ctx.stop = "quota_low"; run.partial = true; }
  }
  if (!res.ok || j?.error_id) {
    const eid = Number(j?.error_id);
    if (eid === 502) { await killHost(run, "api.stackexchange.com", 429, "se.api"); ctx.stop = "throttle_violation"; }
    else run.errors.push(`se.api ${path} http ${res.status} ${j?.error_name ?? ""}`);
    return null;
  }
  return j;
}
async function seContext(run: Run, cfg: Record<string, any>): Promise<SeCtx> {
  const b = (await stateGet("se.backoff")) as { until?: string } | null;
  const ctx: SeCtx = { filter: null, backoffUntil: b?.until ? Date.parse(b.until) : 0, stop: null, quota: null, minQuota: Number(cfg.se_min_quota ?? 20),
    key: await attSecret(run, "stackexchange_key") };
  run.extra.se_keyed = ctx.key !== null;
  const f = (await stateGet("se.filter")) as { filter?: string; include?: string } | null;
  if (f?.filter && f.include === SE_FILTER_INCLUDE) ctx.filter = f.filter;
  else {
    const j = await seGet(run, ctx, "/filters/create", { include: SE_FILTER_INCLUDE, base: "none", unsafe: "false" });
    const id = j?.items?.[0]?.filter;
    if (typeof id === "string") { ctx.filter = id; if (!run.dryRun) await stateSet("se.filter", { filter: id, include: SE_FILTER_INCLUDE }); }
  }
  return ctx;
}
async function seSitesMap(): Promise<Record<string, string[]>> {
  try { return ((await configGet("se.sites_by_category")) ?? {}) as Record<string, string[]>; } catch { return {}; }
}
function sitesFor(map: Record<string, string[]>, cat: string | null): string[] {
  const s = (cat && map[cat]) ?? map["*"] ?? [];
  return Array.isArray(s) ? s.map(String) : [];
}
/**
 * Question counts per day for (term, site) over [fromDay, toDay] inclusive, newest first, up to maxPages pages of 100.
 * Returns counts for the complete part of the window (from the oldest page boundary when truncated).
 */
async function seTermCounts(run: Run, ctx: SeCtx, term: string, site: string, fromDay: string, toDay: string, maxPages: number) {
  const counts = new Map<string, number>();
  for (const d of daysBetween(fromDay, addDays(toDay, 1))) counts.set(d, 0);
  let oldest: number | null = null;
  let page = 1, more = true, ok = true;
  while (more && page <= maxPages) {
    const j = await seGet(run, ctx, "/search/advanced", {
      q: `"${term.replace(/"/g, " ").trim()}"`, site, fromdate: String(dayTs(fromDay)), todate: String(dayTs(toDay) + DAY_S - 1),
      sort: "creation", order: "desc", pagesize: "100", page: String(page), filter: ctx.filter ?? "default",
    });
    if (!j) { ok = false; break; }
    for (const it of j.items ?? []) {
      const t = Number(it?.creation_date);
      if (!Number.isFinite(t)) continue;
      const d = tsDay(t);
      if (counts.has(d)) counts.set(d, counts.get(d)! + 1);
      oldest = oldest === null ? t : Math.min(oldest, t);
    }
    more = j.has_more === true;
    page++;
  }
  if (!ok && page === 1) return null;
  let truncated = false;
  if (more || !ok) {
    // incomplete: only days strictly after the oldest seen question's day are complete
    truncated = true;
    const cut = oldest === null ? toDay : tsDay(oldest);
    for (const d of [...counts.keys()]) if (d <= cut) counts.delete(d);
  }
  return { counts, truncated };
}
function seRows(term: string, site: string, counts: Map<string, number>, topic: number | null): ObsRow[] {
  return [...counts].map(([d, n]) => ({ source: "se.api", key: term, geo: site, day: d, value: n, topic_id: topic ?? null }));
}
async function seTotals(run: Run, ctx: SeCtx, sites: string[], day: string) {
  const rows: ObsRow[] = [];
  for (const site of sites) {
    const j = await seGet(run, ctx, "/questions", { site, fromdate: String(dayTs(day)), todate: String(dayTs(day) + DAY_S - 1), filter: "total" });
    if (!j || typeof j.total !== "number") break;
    rows.push({ source: "se.api", key: "__total__", geo: site, day, value: j.total });
  }
  await ingest(run, rows);
  return rows.length;
}
/** Weekly totals backwards to 400 days (value = weekly total / 7 per day, meta est/window) — resumable per site. */
async function seTotalsBackfill(run: Run, ctx: SeCtx, sites: string[], maxCalls: number) {
  let calls = 0;
  const today = todayUtc();
  const floor = addDays(today, -401);
  for (const site of sites) {
    const k = `se.total.bf:${site}`;
    const st = (await stateGet(k)) as { done_from?: string } | null;
    let doneFrom = st?.done_from ?? addDays(today, -1);
    const rows: ObsRow[] = [];
    while (doneFrom > floor && calls < maxCalls && !ctx.stop && !run.outOfTime(8000)) {
      const a = addDays(doneFrom, -7);
      const j = await seGet(run, ctx, "/questions", { site, fromdate: String(dayTs(a)), todate: String(dayTs(doneFrom) - 1), filter: "total" });
      calls++;
      if (!j || typeof j.total !== "number") break;
      for (const d of daysBetween(a, doneFrom)) rows.push({ source: "se.api", key: "__total__", geo: site, day: d, value: j.total / 7, meta: { est: true, window: 7 } });
      doneFrom = a;
    }
    await ingest(run, rows);
    if (!run.dryRun && rows.length) await stateSet(k, { done_from: doneFrom, at: new Date().toISOString() });
    if (calls >= maxCalls || ctx.stop) break;
  }
}

async function modeStackex(run: Run) {
  const t0 = Date.now();
  const cfg = await socialCfg();
  const src = await sourceInfo("se.api");
  if (!src?.enabled) { run.source({ source: "se.api", status: "disabled" }); return; }
  const cap = Math.max(1, Number(run.params.max_requests ?? cfg.se_daily_cap ?? 60));
  const map = await seSitesMap();
  const asOf = run.asOf;
  const keys = await socialKeys(run, "se.api");
  const pairs: Array<{ k: SKey; site: string }> = [];
  for (const k of keys) for (const site of sitesFor(map, k.category)) pairs.push({ k, site });
  const allSites = [...new Set(Object.values(map).flat().map(String))];
  const sites: string[] = run.params.sites ?? allSites;
  const ctx = await seContext(run, cfg);
  const startMade = run.reqBySource["se.api"] ?? 0;
  const used = () => (run.reqBySource["se.api"] ?? 0) - startMade;
  const tl = (await stateGet("se.total.last")) as { day?: string } | null;
  if (tl?.day !== asOf) {
    const n = await seTotals(run, ctx, sites, asOf);
    if (n === sites.length && !run.dryRun) await stateSet("se.total.last", { day: asOf });
  }
  const last = ((await stateGet("se.pairs")) ?? {}) as Record<string, string>;
  const rot = (await stateGet("se.rot")) as { off?: number } | null;
  let off = pairs.length ? Math.max(0, Number(rot?.off ?? 0)) % pairs.length : 0;
  const rows: ObsRow[] = [];
  let done = 0;
  for (; done < pairs.length; done++) {
    if (ctx.stop || used() >= cap || run.outOfTime(6000)) { run.partial = true; break; }
    const { k, site } = pairs[(off + done) % pairs.length];
    const pk = `${site}\t${k.key}`;
    const from = last[pk] && last[pk] >= addDays(asOf, -13) ? addDays(last[pk], 1) : addDays(asOf, -13);
    if (from > asOf) continue;
    const r = await seTermCounts(run, ctx, k.key, site, from, asOf, 3);
    if (!r) { run.partial = true; break; }
    rows.push(...seRows(k.key, site, r.counts, k.topic_id));
    if (!r.truncated) last[pk] = asOf;
  }
  await ingest(run, rows);
  if (!run.dryRun) {
    off = pairs.length ? (off + done) % pairs.length : 0;
    await stateSet("se.rot", { off, at: new Date().toISOString(), n: pairs.length });
    await stateSet("se.pairs", last);
  }
  Object.assign(run.extra, { pairs: pairs.length, pairs_done: done, sites, stop: ctx.stop, social_version: SOCIAL_VERSION });
  run.source({ source: "se.api", status: ctx.stop === "throttle_violation" ? "host_killed_429" : run.partial ? "partial" : "ok",
    keys: done, rows: run.rows.obs, ms: Date.now() - t0, note: ctx.stop });
}

// ------------------------------------------------------------------ backfill (merged jobs, resumable per key)
async function bfDone(run: Run, keys: string[], status: "done" | "skipped" | "failed", err?: string) {
  const ids = run.jobIds();
  if (!ids.length || !keys.length || run.dryRun) return;
  const { error } = await db.rpc("att_social_bf_done", { p_ids: ids, p_keys: keys, p_status: status, p_error: err ?? null });
  if (error) run.errors.push(`att_social_bf_done: ${error.message}`);
}

/** Next UTC day at 00:10, when the daily budgets reset and day kills expire. */
function nextUtcDayIso(): string { const d = new Date(); d.setUTCHours(24, 10, 0, 0); return d.toISOString(); }
/**
 * If the source's host is closed for the rest of the UTC day (daily budget spent, 429/503 day kill, permanent kill),
 * requeue this dispatch's remaining jobs for the next UTC day instead of letting Run.finish() requeue them for +1 h
 * (att_tick would otherwise keep dispatching no-op runs every 2 min). Jobs already marked done/skipped are untouched.
 */
async function deferIfHostClosed(run: Run, host: string): Promise<void> {
  const hit = run.skipped.find((s) => s.host === host && /^(daily_budget_spent|host_killed_)/.test(s.reason));
  const ids = run.jobIds();
  if (!hit || !ids.length || run.dryRun) return;
  const until = nextUtcDayIso();
  const { data, error } = await db.rpc("att_jobs_done", { p_jobs: ids, p_status: "requeue", p_error: `deferred: ${hit.reason}`, p_not_before: until });
  if (error) { run.errors.push(`att_jobs_done(defer): ${error.message}`); return; }
  // Run.finish() must not requeue them again with the default +1 h
  if (run.body && typeof run.body === "object") { run.body.job_ids = []; delete run.body.job_id; }
  run.extra.deferred = { jobs: Number(data ?? 0), until, reason: hit.reason };
}

async function modeBackfill(run: Run) {
  const source = String(run.params.source ?? "");
  const bf = run.body?.backfill ?? {};
  const to: string = /^\d{4}-\d{2}-\d{2}$/.test(bf.to ?? "") ? bf.to : run.asOf;
  const from: string = /^\d{4}-\d{2}-\d{2}$/.test(bf.from ?? "") ? bf.from : addDays(to, -399);
  if (source === "hn.algolia") return await backfillHn(run, from, to);
  if (source === "se.api") return await backfillSe(run, from, to);
  run.errors.push(`backfill: unsupported source '${source}' (hn.algolia | se.api)`);
}

async function backfillHn(run: Run, from: string, to: string) {
  const t0 = Date.now();
  const cfg = await socialCfg();
  const src = await sourceInfo("hn.algolia");
  if (!src?.enabled) { run.source({ source: "hn.algolia", status: "disabled" }); return; }
  await hnTotalsBackfill(run, Number(run.params.total_calls ?? 30));
  const keys = await socialKeys(run, "hn.algolia");
  const maxPerTerm = Number(run.params.max_calls_per_term ?? cfg.hn_max_calls_per_term ?? 150);
  const a0 = dayTs(from), b0 = dayTs(to) + DAY_S;
  let completed = 0, rowsN = 0;
  const doneKeys: string[] = [];
  for (const k of keys) {
    if (run.outOfTime(6000) || run.skipped.some((s) => s.host === "hn.algolia.com")) { run.partial = true; break; }
    const sk = `bf:hn.algolia:${k.key}`;
    const st = (await stateGet(sk)) as { done_from?: number; from?: number; complete?: boolean } | null;
    if (st?.complete && (st.from ?? Infinity) <= a0) { doneKeys.push(k.key); completed++; continue; }
    const b = st?.done_from && st.done_from > a0 ? Math.min(st.done_from, b0) : b0;
    const r = await hnCount(run, k.key, a0, b, maxPerTerm);
    const rows = hnRows(k.key, r.counts, r.est, k.topic_id);
    const ir = await ingest(run, rows);
    rowsN += ir.rows;
    if (!run.dryRun && r.doneFrom < b) await stateSet(sk, { done_from: r.doneFrom, from: a0, complete: r.complete, at: new Date().toISOString() });
    if (r.complete) {
      doneKeys.push(k.key); completed++;
    } else if (r.calls >= maxPerTerm && !run.outOfTime(6000)) {
      // very dense term: keep what we have (newest part is complete) and move on; resumes on the next dispatch
      run.partial = true;
    } else { run.partial = true; break; }
  }
  await bfDone(run, doneKeys, "done");
  await deferIfHostClosed(run, "hn.algolia.com");
  Object.assign(run.extra, { keys_in: keys.length, keys_complete: completed, window: [from, to], social_version: SOCIAL_VERSION });
  run.source({ source: "hn.algolia", status: run.partial ? "partial" : "ok", keys: completed, rows: rowsN, ms: Date.now() - t0 });
}

async function backfillSe(run: Run, from: string, to: string) {
  const t0 = Date.now();
  const cfg = await socialCfg();
  const src = await sourceInfo("se.api");
  if (!src?.enabled) { run.source({ source: "se.api", status: "disabled" }); return; }
  const map = await seSitesMap();
  const keys = await socialKeys(run, "se.api");
  const cats = await keyCategories(keys, "se.api");
  const ctx = await seContext(run, cfg);
  const doneKeys: string[] = [];
  const skipKeys: string[] = [];
  let rowsN = 0;
  for (const k of keys) {
    const sites = sitesFor(map, cats.get(k.key) ?? null);
    if (!sites.length) { skipKeys.push(k.key); continue; }
    let allDone = true;
    for (const site of sites) {
      if (ctx.stop || run.outOfTime(8000)) { allDone = false; break; }
      const sk = `bf:se.api:${site}:${k.key}`;
      const st = (await stateGet(sk)) as { complete?: boolean } | null;
      if (st?.complete) continue;
      const r = await seTermCounts(run, ctx, k.key, site, from, to, 10);
      if (!r) { allDone = false; break; }
      const ir = await ingest(run, seRows(k.key, site, r.counts, k.topic_id));
      rowsN += ir.rows;
      if (!run.dryRun) await stateSet(sk, { complete: true, truncated: r.truncated, at: new Date().toISOString() });
    }
    if (allDone) doneKeys.push(k.key); else { run.partial = true; break; }
  }
  if (!ctx.stop && !run.outOfTime(15000)) await seTotalsBackfill(run, ctx, [...new Set(Object.values(map).flat().map(String))], 10);
  await bfDone(run, skipKeys, "skipped", "se.api: no relevant Stack Exchange site for this topic category");
  await bfDone(run, doneKeys, "done");
  if (ctx.stop === "quota_low" && !run.skipped.some((x) => x.host === "api.stackexchange.com")) run.skip("api.stackexchange.com", "daily_budget_spent:se.api(quota_low)");
  await deferIfHostClosed(run, "api.stackexchange.com");
  Object.assign(run.extra, { keys_in: keys.length, keys_done: doneKeys.length, keys_skipped: skipKeys.length, stop: ctx.stop, social_version: SOCIAL_VERSION });
  run.source({ source: "se.api", status: ctx.stop === "throttle_violation" ? "host_killed_429" : run.partial ? "partial" : "ok",
    keys: doneKeys.length, rows: rowsN, ms: Date.now() - t0, note: ctx.stop });
}

// ------------------------------------------------------------------ ping
async function modePing(run: Run) {
  Object.assign(run.extra, { att_version: ATT_VERSION, social_version: SOCIAL_VERSION, deno: (globalThis as any).Deno?.version ?? null });
  run.source({ source: "bsky.jet", status: "ok", note: "ping (no outbound requests)" });
}

serve(FN, {
  jetstream: modeJetstream,
  mastodon: modeMastodon,
  hn: modeHn,
  stackex: modeStackex,
  backfill: modeBackfill,
  ping: modePing,
});
