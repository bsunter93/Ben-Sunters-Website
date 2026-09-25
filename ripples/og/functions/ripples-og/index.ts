// ripples-og: Ripple Map share cards (EXPERIENCE §7, ART_DIRECTION §5). Public GET, verify_jwt = false.
//
// GET …/functions/v1/ripples-og?v={brand|line|stop|shock|week}&e={event_id}&k={version}&h={hop_id}&w={yyyyww}
//   * Inputs are integers only (e, k, h, w); v is a fixed word. Every other parameter is ignored; no free text reaches a card.
//   * Anything invalid, unknown, not public (decoys, unpublished lines, negative controls) or sensitive-for-this-card renders the
//     brand card with status 200. The v5 variants (teaser, result, reveal, board, latest, or any `n`/`s` request) now render the
//     brand card too: the daily puzzle is retired (EXPERIENCE §9) and its unfurls fall back to the evergreen card.
//   * line: the frozen version k (or the latest version when k is absent); stop: the hop's evidence card; shock: the line's
//     shock ticket (never for sensitive shocks: quiet mode); week: the week's Ripple of the week staircase.
// Data: the public contracts (rm_cascade, rm_hop, rm_week) read with the service key; cards.ts turns them into elements.
// Stored cards: ripples-publish pre-renders PNGs into Storage v2/og/ (brand.png, line-{e}-v{k}.png, stop-{h}.png,
// week-{yyyy-ww}.png); a request for a card that exists there is served from Storage without loading fonts or rendering.
// &fresh=1 with a valid x-collector-token bypasses Storage (ripples-publish uses it); &b64=1 with the token returns base64.
// Fonts: the ART §2.2 static TTFs (Anybody 800/900, IBM Plex Sans 500/700), fetched from their pinned Google Fonts URLs and
// checked against the SHA-256 of the files in art/final/fonts/; on a mismatch or fetch failure the @fontsource static WOFFs of the
// same families are used and the response carries X-Font-Source: fallback.
import satori from "npm:satori@0.10.14";
import { Resvg, initWasm } from "npm:@resvg/resvg-wasm@2.6.2";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { brandCard, H, lineCard, shockCard, stopCard, W, weekCard, type El } from "./cards.ts";

const WASM = "https://cdn.jsdelivr.net/npm/@resvg/resvg-wasm@2.6.2/index_bg.wasm";
const TWEMOJI = "https://cdn.jsdelivr.net/gh/jdecked/twemoji@latest/assets/svg/";
const FS = "https://cdn.jsdelivr.net/npm/@fontsource/";
const FONTS: { name: string; weight: 500 | 700 | 800 | 900; url: string; sha256: string; fallback: string }[] = [
  { name: "Anybody", weight: 800, url: "https://fonts.gstatic.com/s/anybody/v13/VuJbdNvK2Ib2ppdWYq311GH32hxIv0sd5grncSUi2F_Wim4JV2fPrg.ttf",
    sha256: "70c6bbbcedec7d1b7daa697725248ef10764a6d24accf70b723755aa60e4158f", fallback: "anybody@5/files/anybody-latin-800-normal.woff" },
  { name: "Anybody", weight: 900, url: "https://fonts.gstatic.com/s/anybody/v13/VuJbdNvK2Ib2ppdWYq311GH32hxIv0sd5grncSUi2F_Wim4JfmfPrg.ttf",
    sha256: "eff587175f88e97197744d5ff8094778892a20e0dc9430900f03e133e793b1b0", fallback: "anybody@5/files/anybody-latin-900-normal.woff" },
  { name: "Plex", weight: 500, url: "https://fonts.gstatic.com/s/ibmplexsans/v23/zYXGKVElMYYaJe8bpLHnCwDKr932-G7dytD-Dmu1swZSAXcomDVmadSD2FlzAA.ttf",
    sha256: "6f7a8c4219e021ff7c9131bc5f1f7af97bcd1436a59578d444a8cb92e9791742", fallback: "ibm-plex-sans@5/files/ibm-plex-sans-latin-500-normal.woff" },
  { name: "Plex", weight: 700, url: "https://fonts.gstatic.com/s/ibmplexsans/v23/zYXGKVElMYYaJe8bpLHnCwDKr932-G7dytD-Dmu1swZSAXcomDVmadSDDV5zAA.ttf",
    sha256: "e129a20e8ff7c907ffd07124b573e88c323b7b18afc934d4aa539a3e0f2fe100", fallback: "ibm-plex-sans@5/files/ibm-plex-sans-latin-700-normal.woff" },
];
// Noto Sans for scripts the Latin faces lack (satori asks per segment)
const NOTO: Record<string, [string, string]> = {
  "ja-JP": ["Noto Sans JP", "noto-sans-jp@5/files/noto-sans-jp-japanese-700-normal.woff"],
  "zh-CN": ["Noto Sans SC", "noto-sans-sc@5/files/noto-sans-sc-chinese-simplified-700-normal.woff"],
  "zh-TW": ["Noto Sans SC", "noto-sans-sc@5/files/noto-sans-sc-chinese-simplified-700-normal.woff"],
  "zh-HK": ["Noto Sans SC", "noto-sans-sc@5/files/noto-sans-sc-chinese-simplified-700-normal.woff"],
  "ko-KR": ["Noto Sans KR", "noto-sans-kr@5/files/noto-sans-kr-korean-700-normal.woff"],
  "devanagari": ["Noto Sans", "noto-sans@5/files/noto-sans-devanagari-700-normal.woff"],
  "ar-AR": ["Noto Sans Arabic", "noto-sans-arabic@5/files/noto-sans-arabic-arabic-700-normal.woff"],
  "he-IL": ["Noto Sans Hebrew", "noto-sans-hebrew@5/files/noto-sans-hebrew-hebrew-700-normal.woff"],
  "th-TH": ["Noto Sans Thai", "noto-sans-thai@5/files/noto-sans-thai-thai-700-normal.woff"],
  "bn-IN": ["Noto Sans Bengali", "noto-sans-bengali@5/files/noto-sans-bengali-bengali-700-normal.woff"],
  "ta-IN": ["Noto Sans Tamil", "noto-sans-tamil@5/files/noto-sans-tamil-tamil-700-normal.woff"],
  "symbol": ["Noto Sans Symbols 2", "noto-sans-symbols-2@5/files/noto-sans-symbols-2-symbols-400-normal.woff"],
  "math": ["Noto Sans Math", "noto-sans-math@5/files/noto-sans-math-math-400-normal.woff"],
  "unknown": ["Noto Sans", "noto-sans@5/files/noto-sans-latin-ext-700-normal.woff"],
};

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const OG_STORE = `${SB_URL}/storage/v1/object/public/ripples/v2/og/`;
const db = createClient(SB_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

// ---------- per-isolate assets ----------
type FontDef = { name: string; data: ArrayBuffer; weight: 500 | 700 | 800 | 900; style: "normal" };
let ready: Promise<{ fonts: FontDef[]; source: string }> | null = null;
async function sha256(buf: ArrayBuffer): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", buf));
  return Array.from(d).map((b) => b.toString(16).padStart(2, "0")).join("");
}
function init() {
  ready ??= (async () => {
    const wasm = await fetch(WASM);
    if (!wasm.ok) throw new Error(`wasm ${wasm.status}`);
    await initWasm(wasm);
    let source = "pinned";
    const fonts = await Promise.all(FONTS.map(async (f) => {
      try {
        const r = await fetch(f.url);
        if (r.ok) {
          const buf = await r.arrayBuffer();
          if (await sha256(buf) === f.sha256) return { name: f.name, data: buf, weight: f.weight, style: "normal" as const };
          console.error("font hash mismatch", f.name, f.weight);
        } else await r.body?.cancel();
      } catch (e) { console.error("font fetch", f.name, String(e)); }
      source = "fallback";
      const r2 = await fetch(FS + f.fallback);
      if (!r2.ok) throw new Error(`font fallback ${r2.status}`);
      return { name: f.name, data: await r2.arrayBuffer(), weight: f.weight, style: "normal" as const };
    }));
    return { fonts, source };
  })();
  ready.catch(() => { ready = null; });
  return ready;
}
const emojiCache = new Map<string, Promise<string>>();
const fontCache = new Map<string, Promise<ArrayBuffer | null>>();
function twemojiCode(seg: string): string {
  const cps = Array.from(seg).map((c) => c.codePointAt(0)!);
  const keep = cps.includes(0x200d) ? cps : cps.filter((c) => c !== 0xfe0f);
  return keep.map((c) => c.toString(16)).join("-");
}
const BLANK_SVG = "data:image/svg+xml;base64," + btoa('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"/>');
function loadEmoji(seg: string): Promise<string> {
  const code = twemojiCode(seg);
  if (!emojiCache.has(code)) {
    emojiCache.set(code, (async () => {
      try {
        const r = await fetch(TWEMOJI + code + ".svg");
        if (!r.ok) return BLANK_SVG;
        return "data:image/svg+xml;base64," + btoa(unescape(encodeURIComponent(await r.text())));
      } catch { return BLANK_SVG; }
    })());
  }
  return emojiCache.get(code)!;
}
function loadFont(path: string): Promise<ArrayBuffer | null> {
  if (!fontCache.has(path)) fontCache.set(path, fetch(FS + path).then((r) => (r.ok ? r.arrayBuffer() : null)).catch(() => null));
  return fontCache.get(path)!;
}
// deno-lint-ignore no-explicit-any
async function loadAdditionalAsset(code: string, segment: string): Promise<any> {
  if (code === "emoji") return await loadEmoji(segment);
  const pick = NOTO[code] ?? NOTO.unknown;
  const data = await loadFont(pick[1]);
  return data ? [{ name: pick[0], data, weight: 700, style: "normal" }] : [];
}
let fontSource = "pinned";
async function render(el: El): Promise<Uint8Array> {
  const { fonts, source } = await init();
  fontSource = source;
  const svg = await satori(el as never, { width: W, height: H, fonts, loadAdditionalAsset });
  return new Resvg(svg, { fitTo: { mode: "width", value: W } }).render().asPng();
}
function b64(u8: Uint8Array): string {
  let s = "";
  for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode(...u8.subarray(i, i + 0x8000));
  return btoa(s);
}

// ---------- params: integers only ----------
const VARIANTS = new Set(["brand", "line", "stop", "shock", "week"]);
const LEGACY = new Set(["teaser", "result", "reveal", "board", "latest"]);
type Req = { v: string; e: number | null; k: number | null; h: number | null; w: string | null; bad: boolean };
function int(s: string | null, max: number): number | null | undefined {   // undefined = malformed
  if (s === null) return null;
  if (!/^\d{1,15}$/.test(s)) return undefined;
  const n = Number(s);
  return n >= 1 && n <= max ? n : undefined;
}
function parse(url: URL): Req {
  const q = url.searchParams;
  const rv = q.get("v");
  const out: Req = { v: "brand", e: null, k: null, h: null, w: null, bad: false };
  if (rv !== null && !VARIANTS.has(rv) && !LEGACY.has(rv)) out.bad = true;
  if (rv !== null && VARIANTS.has(rv)) out.v = rv;
  if (q.get("n") !== null || q.get("s") !== null || (rv !== null && LEGACY.has(rv))) { out.v = "brand"; return out; }
  const e = int(q.get("e"), 9e15), k = int(q.get("k"), 9999), hh = int(q.get("h"), 9e15), w = int(q.get("w"), 999999);
  if (e === undefined || k === undefined || hh === undefined || w === undefined) { out.bad = true; return out; }
  out.e = e; out.k = k; out.h = hh;
  if (w !== null) {
    const s = String(w).padStart(6, "0"), wk = Number(s.slice(4));
    if (wk < 1 || wk > 53) { out.bad = true; return out; }
    out.w = `${s.slice(0, 4)}-${s.slice(4)}`;
  }
  return out;
}

// deno-lint-ignore no-explicit-any
async function rpc(fn: string, args: Record<string, unknown>): Promise<any> {
  const { data, error } = await db.rpc(fn, args);
  if (error) throw new Error(`${fn}: ${error.message}`);
  return data;
}

type Plan = { el: El; variant: string; maxAge: number; key: string; stored?: string };
const brand = (maxAge: number): Plan => ({ el: brandCard(), variant: "brand", maxAge, key: "brand", stored: "brand.png" });
async function plan(p: Req): Promise<Plan> {
  if (p.bad) return brand(3600);
  if (p.v === "brand") return brand(86400);
  if (p.v === "line") {
    if (p.e === null) return brand(3600);
    const c = await rpc("rm_cascade", { p_event: p.e, p_version: p.k });
    if (!c || !c.event) return brand(300);
    const k = c.version as number;
    // a frozen version never changes (immutable cache); the latest-version URL follows new versions (1 h)
    return { el: lineCard(c), variant: "line", maxAge: p.k !== null ? 31536000 : 3600, key: `line:${p.e}:${k}`, stored: `line-${p.e}-v${k}.png` };
  }
  if (p.v === "stop") {
    if (p.h === null) return brand(3600);
    const hop = await rpc("rm_hop", { p_hop: p.h });
    if (!hop || !hop.node) return brand(300);
    return { el: stopCard(hop), variant: "stop", maxAge: 3600, key: `stop:${p.h}:${hop.tier}`, stored: `stop-${p.h}.png` };
  }
  if (p.v === "shock") {
    if (p.e === null) return brand(3600);
    const c = await rpc("rm_cascade", { p_event: p.e, p_version: null });
    if (!c || !c.event || c.event.sensitive) return brand(c ? 86400 : 300);   // quiet mode: never a shock card for a sensitive shock
    return { el: shockCard(c), variant: "shock", maxAge: 3600, key: `shock:${p.e}:${c.version}` };
  }
  if (p.v === "week") {
    if (p.w === null) return brand(3600);
    const wk = await rpc("rm_week", { p_week: p.w });
    if (!wk || (!wk.ripple_of_week && (wk.edition === null || wk.edition === undefined))) return brand(300);   // no edition yet
    const ev = wk.ripple_of_week?.event?.event_id ?? 0;
    return { el: weekCard(wk), variant: "week", maxAge: 3600, key: `week:${p.w}:${ev}:${wk.ripple_of_week?.version ?? 0}`, stored: `week-${p.w}.png` };
  }
  return brand(3600);
}

// ---------- per-isolate render cache ----------
const RENDER_TTL_MS = 300_000, RENDER_MAX = 48;
let brandPng: Promise<Uint8Array> | null = null;
const renderCache = new Map<string, { at: number; png: Promise<Uint8Array> }>();
function cachedRender(pl: Plan): Promise<Uint8Array> {
  if (pl.key === "brand") {
    brandPng ??= render(brandCard());
    brandPng.catch(() => { brandPng = null; });
    return brandPng;
  }
  const now = Date.now();
  const hit = renderCache.get(pl.key);
  if (hit && now - hit.at < RENDER_TTL_MS) return hit.png;
  const png = render(pl.el);
  renderCache.delete(pl.key);
  renderCache.set(pl.key, { at: now, png });
  png.catch(() => renderCache.delete(pl.key));
  while (renderCache.size > RENDER_MAX) renderCache.delete(renderCache.keys().next().value!);
  return png;
}
async function fromStore(name: string): Promise<Uint8Array | null> {
  try {
    const r = await fetch(OG_STORE + name);
    if (!r.ok || r.headers.get("content-type") !== "image/png") { await r.body?.cancel(); return null; }
    const u = new Uint8Array(await r.arrayBuffer());
    return u.length > 24 && u[0] === 0x89 && u[1] === 0x50 && u[2] === 0x4e && u[3] === 0x47 ? u : null;
  } catch { return null; }
}

const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS", "Access-Control-Allow-Headers": "x-collector-token" };

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "GET" && req.method !== "HEAD") return new Response("method not allowed", { status: 405, headers: CORS });
  const t0 = performance.now();
  const url = new URL(req.url);
  const p = parse(url);
  let pl: Plan;
  try { pl = await plan(p); } catch (e) { console.error("og data error", String(e)); pl = brand(300); }
  const token = req.headers.get("x-collector-token") ?? "";
  let authed: boolean | null = null;
  const isAuthed = async () => {
    if (authed === null) { authed = false; if (token) { try { authed = (await rpc("check_collector_token", { t: token })) === true; } catch { authed = false; } } }
    return authed;
  };
  const fresh = url.searchParams.get("fresh") === "1" && await isAuthed();
  let png: Uint8Array | null = null;
  let source = "render";
  if (pl.stored && !fresh) { png = await fromStore(pl.stored); if (png) source = "storage"; }
  if (!png) try { png = await cachedRender(pl); } catch (e) {
    console.error("render error", pl.variant, String(e));
    try { png = await cachedRender(brand(300)); pl = { ...brand(300), stored: undefined }; }
    catch { return new Response("render unavailable", { status: 503, headers: { ...CORS, "Cache-Control": "no-store", "Content-Type": "text/plain" } }); }
  }
  const headers: Record<string, string> = {
    ...CORS, "X-Card-Variant": pl.variant, "X-Card-Source": source, "X-Font-Source": source === "render" ? fontSource : "stored",
    "X-Render-Ms": String(Math.round(performance.now() - t0)),
  };
  if (url.searchParams.get("b64") === "1" && await isAuthed()) {
    return new Response(b64(png as Uint8Array), { headers: { ...headers, "Content-Type": "text/plain", "Cache-Control": "no-store" } });
  }
  return new Response(req.method === "HEAD" ? null : png as unknown as BodyInit, {
    headers: { ...headers, "Content-Type": "image/png", "Cache-Control": `public, max-age=${pl.maxAge}${pl.maxAge >= 31536000 ? ", immutable" : ""}` },
  });
});
