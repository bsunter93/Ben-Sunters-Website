// ripples-og: Knock-On share cards (SPEC §9). Public GET, verify_jwt = false.
//
// Input is IDs only: n (int -60..9999), s (int 0..4), v (teaser|result|reveal|board|latest|brand).
// Every other query parameter is ignored; no free text ever reaches a card. Anything invalid renders the
// brand card with status 200. Card data comes from the service-only RPC ripples_og_data(n) (board rows from
// ripples_board(n)), read with SUPABASE_SERVICE_ROLE_KEY from the function env.
// Test mode: &b64=1 returns the PNG as base64 text, only with a valid x-collector-token header.
import satori from "npm:satori@0.10.14";
import { Resvg, initWasm } from "npm:@resvg/resvg-wasm@2.6.2";
import { createClient } from "jsr:@supabase/supabase-js@2";

const W = 1200, H = 630;
const C = {
  ground: "#0B3A40", deep: "#082C31", gold: "#E0A33C", cream: "#F4EEE1", muted: "#A9C2C0",
  line: "rgba(244,238,225,0.18)", tile: "rgba(244,238,225,0.08)",
};
const FOOTER = "bensunter.com/ripples · Measured attention, not proof of cause.";
const FONT_REG = "https://cdn.jsdelivr.net/gh/rsms/inter@v3.19/docs/font-files/Inter-Regular.woff";
const FONT_XB = "https://cdn.jsdelivr.net/gh/rsms/inter@v3.19/docs/font-files/Inter-ExtraBold.woff";
const WASM = "https://cdn.jsdelivr.net/npm/@resvg/resvg-wasm@2.6.2/index_bg.wasm";
const TWEMOJI = "https://cdn.jsdelivr.net/gh/jdecked/twemoji@latest/assets/svg/";
const FS = "https://cdn.jsdelivr.net/npm/@fontsource/";
// Noto Sans fallbacks for scripts Inter v3.19 lacks (Inter covers Latin, Latin-ext, Greek, Cyrillic, Vietnamese).
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

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

// ---------- per-isolate caches ----------
let ready: Promise<[ArrayBuffer, ArrayBuffer]> | null = null;
function init() {
  ready ??= (async () => {
    const [wasm, r, b] = await Promise.all([fetch(WASM), fetch(FONT_REG), fetch(FONT_XB)]);
    if (!wasm.ok || !r.ok || !b.ok) throw new Error(`asset fetch ${wasm.status}/${r.status}/${b.status}`);
    await initWasm(wasm);
    return [await r.arrayBuffer(), await b.arrayBuffer()] as [ArrayBuffer, ArrayBuffer];
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
  if (!fontCache.has(path)) {
    fontCache.set(path, fetch(FS + path).then((r) => (r.ok ? r.arrayBuffer() : null)).catch(() => null));
  }
  return fontCache.get(path)!;
}
// deno-lint-ignore no-explicit-any
async function loadAdditionalAsset(code: string, segment: string): Promise<any> {
  if (code === "emoji") return await loadEmoji(segment);
  const pick = NOTO[code] ?? NOTO.unknown;
  const data = await loadFont(pick[1]);
  if (!data) return [];
  return [{ name: pick[0], data, weight: 700, style: "normal" }];
}

// ---------- tiny element helper ----------
type El = { type: string; props: Record<string, unknown> };
// deno-lint-ignore no-explicit-any
const h = (type: string, style: Record<string, unknown> = {}, children?: any, extra: Record<string, unknown> = {}): El =>
  ({ type, props: { ...extra, style: type === "div" ? { display: "flex", ...style } : style, children } });

const clip = (s: unknown, max: number): string => {
  const t = String(s ?? "").replace(/[\u0000-\u001f\u007f-\u009f]/g, " ").replace(/\s+/g, " ").trim();
  const a = Array.from(t);
  return a.length > max ? a.slice(0, max - 1).join("").trimEnd() + "…" : t;
};
const mult = (x: unknown): string => {
  const v = Number(x);
  if (!isFinite(v) || v <= 0) return "";
  return (v >= 10 ? String(Math.round(v)) : v.toFixed(1).replace(/\.0$/, "")) + "×";
};
const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const DOW = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const fmtDate = (d: unknown): string => {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(d ?? ""));
  if (!m) return "";
  const dt = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
  return `${DOW[dt.getUTCDay()]} ${dt.getUTCDate()} ${MON[dt.getUTCMonth()]} ${dt.getUTCFullYear()}`;
};
const titleSize = (t: string, wide = false): number => {
  const n = Array.from(t).length;
  if (n <= 16) return wide ? 76 : 70;
  if (n <= 24) return wide ? 64 : 58;
  if (n <= 34) return 50;
  if (n <= 46) return 42;
  return 36;
};

// ---------- shared pieces ----------
const arrow = (w = 34) =>
  h("svg", {}, [h("path", {}, undefined, { d: `M2 12 H${w - 8} M${w - 18} 3 L${w - 5} 12 L${w - 18} 21`, stroke: C.gold, "stroke-width": 4, fill: "none", "stroke-linecap": "round", "stroke-linejoin": "round" })],
    { width: w, height: 24, viewBox: `0 0 ${w} 24` });

type Og = {
  n: number; kind: string; status?: string; date: string; from_date: string | null; past: boolean; R: number;
  seed: { title: string; emoji: string; biggest_in_days: number | null; since_records: boolean; multiple: number; langs?: number };
  rounds: { i: number; continues: boolean; seed_emoji: string | null; emoji: string; title: string; multiple: number }[];
};

function watermark(kind: string): El | null {
  if (kind !== "fixture" && kind !== "practice") return null;
  const word = kind === "fixture" ? "TEST" : "PRACTICE";
  return h("div", {
    position: "absolute", left: 0, top: 0, width: W, height: H, alignItems: "center", justifyContent: "center",
  }, h("div", { fontSize: kind === "fixture" ? 300 : 190, fontWeight: 800, color: "rgba(244,238,225,0.06)", transform: "rotate(-14deg)", letterSpacing: 12 }, word));
}
function badge(og: { kind: string; from_date?: string | null }): El | null {
  let t = "";
  if (og.kind === "fixture") t = "TEST · fixture data";
  else if (og.kind === "practice") t = "PRACTICE · reconstructed";
  else if (og.from_date) t = `From ${fmtDate(og.from_date)}`;
  if (!t) return null;
  return h("div", { border: `2px solid ${C.gold}`, color: C.gold, borderRadius: 999, padding: "6px 18px", fontSize: 22, fontWeight: 800, letterSpacing: 2 }, t);
}
function header(left: string, sub: string, og: { kind: string; from_date?: string | null } | null): El {
  const b = og ? badge(og) : null;
  return h("div", { justifyContent: "space-between", alignItems: "center", width: "100%" }, [
    h("div", { alignItems: "baseline", gap: 14 }, [
      h("div", { fontSize: 26, fontWeight: 800, letterSpacing: 5, color: C.gold }, left),
      sub ? h("div", { fontSize: 24, color: C.muted }, sub) : null,
    ].filter(Boolean)),
    b ?? h("div", {}, ""),
  ]);
}
const footer = (): El =>
  h("div", { borderTop: `2px solid ${C.line}`, paddingTop: 18, width: "100%", fontSize: 23, color: C.muted, justifyContent: "space-between" }, [
    h("div", {}, FOOTER),
  ]);
function frame(kind: string, children: (El | null)[]): El {
  const wm = watermark(kind);
  return h("div", { width: W, height: H, background: C.ground, color: C.cream, fontFamily: "Inter", position: "relative" }, [
    wm,
    h("div", { position: "absolute", left: 0, top: 0, width: W, height: H, flexDirection: "column", justifyContent: "space-between", padding: "46px 60px 40px" },
      children.filter(Boolean)),
  ].filter(Boolean));
}

// path tiles: seed, then per round an emoji over a "?" box; a fresh ripple is joined with " · " and starts with its seed emoji
function pathTiles(og: Og): El {
  const tiles: El[] = [];
  const nTiles = 1 + og.rounds.length + og.rounds.filter((r) => !r.continues).length;
  const tw = nTiles > 6 ? 70 : 84, th = nTiles > 6 ? 84 : 98, es = nTiles > 6 ? 30 : 36;
  const seedTile = (emoji: string, label: string) =>
    h("div", { width: tw, height: th, borderRadius: 16, background: C.tile, border: `2px solid ${C.line}`, flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 6 }, [
      h("div", { fontSize: es }, emoji || "🔹"),
      h("div", { fontSize: 15, color: C.muted, letterSpacing: 2, fontWeight: 800 }, label),
    ]);
  const qTile = (emoji: string) =>
    h("div", { width: tw, height: th, borderRadius: 16, border: `3px solid ${C.gold}`, flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 2 }, [
      h("div", { fontSize: es - 4 }, emoji || "🔹"),
      h("div", { fontSize: es + 4, fontWeight: 800, color: C.gold, lineHeight: 1 }, "?"),
    ]);
  tiles.push(seedTile(og.seed.emoji, "SEED"));
  for (const r of og.rounds) {
    if (!r.continues) {
      tiles.push(h("div", { width: 12, height: 12, borderRadius: 6, background: C.muted, margin: "0 6px" }, ""));
      tiles.push(seedTile(r.seed_emoji ?? "🔹", "NEW"));
    }
    tiles.push(arrow());
    tiles.push(qTile(r.emoji));
  }
  return h("div", { alignItems: "center", gap: 10 }, tiles);
}

function seedBlock(og: Og, wide: boolean): El[] {
  const title = clip(og.seed.title, 60);
  const big = og.seed.since_records
    ? "Biggest day since records began"
    : og.seed.biggest_in_days
    ? `Biggest day in ${Number(og.seed.biggest_in_days).toLocaleString("en-US")} days`
    : `${mult(og.seed.multiple)} its normal readers`;
  const langs = Number(og.seed.langs ?? 0);
  const sub = [
    mult(og.seed.multiple) ? `${mult(og.seed.multiple)} its normal Wikipedia readers` : "",
    langs > 1 ? `${langs} languages` : "",
    og.seed.since_records ? "records from Jul 2015" : "",
  ].filter(Boolean).join(" · ");
  return [
    h("div", { alignItems: "center", gap: 22, maxWidth: wide ? 1080 : 760 }, [
      h("div", { fontSize: 70 }, og.seed.emoji || "🔹"),
      h("div", { fontSize: titleSize(title, wide), fontWeight: 800, lineHeight: 1.05, color: C.cream, maxWidth: wide ? 980 : 660 }, title),
    ]),
    h("div", { flexDirection: "column", gap: 6, marginTop: 14 }, [
      h("div", { fontSize: 50, fontWeight: 800, color: C.gold, lineHeight: 1.1 }, big),
      sub ? h("div", { fontSize: 27, color: C.cream }, sub) : null,
      // SPEC 12.2: every number names its baseline window
      mult(og.seed.multiple) ? h("div", { fontSize: 19, color: C.muted }, "× normal = peak daily Wikipedia views vs the page's own 91-day baseline") : null,
    ].filter(Boolean)),
  ];
}

// ---------- variants ----------
function teaserCard(og: Og, s: number | null): El {
  const R = og.R || og.rounds.length;
  const right = s === null
    ? h("div", { flexDirection: "column", alignItems: "flex-end", width: 300 }, [
        h("div", { fontSize: 34, fontWeight: 800, color: C.cream, textAlign: "right", lineHeight: 1.15 }, "Where did the internet go next?"),
        h("div", { fontSize: 22, color: C.muted, marginTop: 10, textAlign: "right" }, `${R} rounds · wrong answers stayed flat`),
      ])
    : h("div", { flexDirection: "column", alignItems: "flex-end", width: 300 }, [
        h("div", { alignItems: "baseline", gap: 10 }, [
          h("div", { fontSize: 110, fontWeight: 800, color: C.gold, lineHeight: 1 }, String(s)),
          h("div", { fontSize: 44, fontWeight: 800, color: C.cream }, `of ${R}`),
        ]),
        h("div", { fontSize: 28, color: C.cream, marginTop: 4 }, `Found ${s} of ${R} first try`),
        h("div", { fontSize: 22, color: C.muted, marginTop: 8 }, "Can you beat it?"),
      ]);
  return frame(og.kind, [
    header(`KNOCK-ON #${og.n}`, fmtDate(og.date), og),
    h("div", { justifyContent: "space-between", alignItems: "center", width: "100%" }, [
      h("div", { flexDirection: "column", width: 780 }, seedBlock(og, false)),
      right,
    ]),
    pathTiles(og),
    footer(),
  ]);
}

// fluke meter per hop (SPEC 12.4): "1 in N chance" from reveal evidence.fluke_1_in, else "warming up"
type Fluke = { fluke_1_in: number | null; fluke_warming: boolean };
function flukeLabel(f: Fluke | undefined): string {
  const k = Number(f?.fluke_1_in);
  if (f && !f.fluke_warming && Number.isFinite(k) && k >= 1) return `fluke 1 in ${Math.round(k).toLocaleString("en-US")}`;
  return "fluke: warming up";
}
function revealCard(og: Og, fl: Map<number, Fluke>): El {
  const rows: El[] = [];
  const row = (lead: El | null, emoji: string, title: string, m: string, isSeed: boolean, fluke: string) =>
    h("div", { alignItems: "center", width: "100%", height: 62, borderBottom: `1px solid ${C.line}`, gap: 16 }, [
      h("div", { width: 92, justifyContent: "flex-end", alignItems: "center", gap: 8 }, lead ? [lead] : []),
      h("div", { fontSize: 38 }, emoji || "🔹"),
      h("div", { fontSize: isSeed ? 34 : 30, fontWeight: 800, color: C.cream, flexGrow: 1, flexShrink: 1, maxWidth: 490 }, title),
      h("div", { fontSize: 30, fontWeight: 800, color: C.gold, width: 220, flexShrink: 0, justifyContent: "flex-end", whiteSpace: "nowrap" }, m ? `${m} normal` : ""),
      h("div", { fontSize: 20, color: C.muted, width: 180, flexShrink: 0, justifyContent: "flex-end", whiteSpace: "nowrap" }, fluke),
    ]);
  rows.push(row(h("div", { fontSize: 16, color: C.muted, letterSpacing: 2, fontWeight: 800 }, "SEED"), og.seed.emoji, clip(og.seed.title, 30), mult(og.seed.multiple), true, ""));
  for (const r of og.rounds.slice(0, 4)) {
    const lead = r.continues
      ? arrow()
      : h("div", { alignItems: "center", gap: 6 }, [h("div", { width: 10, height: 10, borderRadius: 5, background: C.muted }, ""), h("div", { fontSize: 26 }, r.seed_emoji ?? "🔹"), arrow(26)]);
    rows.push(row(lead, r.emoji, clip(r.title, 30), mult(r.multiple), false, flukeLabel(fl.get(r.i))));
  }
  return frame(og.kind, [
    header(`KNOCK-ON #${og.n} · THE TRAIL`, fmtDate(og.date), og),
    h("div", { flexDirection: "column", width: "100%" }, rows),
    h("div", { fontSize: 20, color: C.muted, lineHeight: 1.35, maxWidth: 1080 }, "× normal = peak daily Wikipedia views vs the page's own 91-day baseline. Each answer is linked from its parent page and spiked after or alongside it. Fluke 1 in N = about 1 in N passes like this are chance. A dot marks a fresh ripple."),
    footer(),
  ]);
}

const QUAD: Record<string, string> = { big_wave: "Big Wave", sleeper: "Sleeper", belly_flop: "Belly Flop", ripple: "Ripple" };
// deno-lint-ignore no-explicit-any
function boardCard(board: any): El {
  // sensitive rows are never shown on a card (no nicknames or game framing on sensitive topics)
  // deno-lint-ignore no-explicit-any
  const trends = (Array.isArray(board?.trends) ? board.trends : []).filter((t: any) => t && !t.sensitive && t.quadrant)
    // deno-lint-ignore no-explicit-any
    .sort((a: any, b: any) => Number(b.splash_multiple) - Number(a.splash_multiple)).slice(0, 5);
  const kind = Number(board?.n) === 0 ? "fixture" : Number(board?.n) < 0 ? "practice" : "live";
  const cell = (t: string, w: number, st: Record<string, unknown> = {}) => h("div", { width: w, justifyContent: "flex-end", fontSize: 18, color: C.muted, letterSpacing: 2, fontWeight: 800, ...st }, t);
  // deno-lint-ignore no-explicit-any
  const rows = trends.map((t: any) =>
    h("div", { alignItems: "center", width: "100%", height: 66, borderBottom: `1px solid ${C.line}`, gap: 16 }, [
      h("div", { fontSize: 36, width: 50 }, t.emoji || "🔹"),
      h("div", { fontSize: 32, fontWeight: 800, color: C.cream, width: 560 }, clip(t.title, 34)),
      h("div", { fontSize: 32, fontWeight: 800, color: C.gold, width: 120, justifyContent: "flex-end" }, mult(t.splash_multiple)),
      h("div", { fontSize: 30, fontWeight: 800, color: C.cream, width: 110, justifyContent: "flex-end" }, `${Number(t.wake_k)}/${Number(t.wake_of ?? 20)}`),
      h("div", { width: 190, justifyContent: "flex-end" }, h("div", { border: `2px solid ${C.gold}`, borderRadius: 999, padding: "4px 14px", fontSize: 20, fontWeight: 800, color: C.gold }, QUAD[t.quadrant] ?? "")),
    ])
  );
  return frame(kind, [
    header("KNOCK-ON · TODAY'S BOARD", fmtDate(board?.date), { kind, from_date: null }),
    h("div", { flexDirection: "column", width: "100%" }, [
      h("div", { alignItems: "center", width: "100%", gap: 16, paddingBottom: 6 }, [
        cell("", 50), cell("TREND", 560, { justifyContent: "flex-start" }), cell("SPLASH", 120), cell("WAKE", 110), cell("", 190),
      ]),
      ...(rows.length ? rows : [h("div", { fontSize: 30, color: C.muted, paddingTop: 20 }, "No board rows today.")]),
    ]),
    h("div", { fontSize: 20, color: C.muted, lineHeight: 1.35, maxWidth: 1080 }, "Splash = peak daily Wikipedia views vs the page's own 91-day baseline. Wake = how many of 20 linked pages spiked after or alongside it."),
    footer(),
  ]);
}

function brandCard(): El {
  const demo: Og = { n: 0, kind: "live", date: "", from_date: null, past: false, R: 3,
    seed: { title: "", emoji: "👤", biggest_in_days: null, since_records: false, multiple: 0 },
    rounds: [{ i: 1, continues: true, seed_emoji: null, emoji: "📍", title: "", multiple: 0 },
             { i: 2, continues: true, seed_emoji: null, emoji: "🎬", title: "", multiple: 0 },
             { i: 3, continues: true, seed_emoji: null, emoji: "🍎", title: "", multiple: 0 }] };
  return frame("live", [
    header("KNOCK-ON", "a daily game from Today's Ripples", null),
    h("div", { flexDirection: "column", gap: 18, maxWidth: 1040 }, [
      h("div", { fontSize: 72, fontWeight: 800, lineHeight: 1.05, color: C.cream }, "One trend. Where did the internet go next?"),
      h("div", { fontSize: 30, color: C.muted, lineHeight: 1.3 }, "Every right answer is a measured spike. Every wrong answer is a real page that stayed flat."),
    ]),
    pathTiles(demo),
    footer(),
  ]);
}

// ---------- rendering ----------
async function render(el: El): Promise<Uint8Array> {
  const [regular, bold] = await init();
  const svg = await satori(el as never, {
    width: W, height: H,
    fonts: [
      { name: "Inter", data: regular, weight: 400, style: "normal" },
      { name: "Inter", data: bold, weight: 800, style: "normal" },
    ],
    loadAdditionalAsset,
  });
  return new Resvg(svg, { fitTo: { mode: "width", value: W } }).render().asPng();
}
function b64(u8: Uint8Array): string {
  let s = "";
  for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode(...u8.subarray(i, i + 0x8000));
  return btoa(s);
}

// ---------- params ----------
const VARIANTS = new Set(["teaser", "result", "reveal", "board", "brand", "latest"]);
type Req = { n: number | null; s: number | null; v: string | null; bad: boolean };
function parse(url: URL): Req {
  const rn = url.searchParams.get("n"), rs = url.searchParams.get("s"), rv = url.searchParams.get("v");
  const out: Req = { n: null, s: null, v: null, bad: false };
  if (rn !== null) {
    if (!/^-?\d{1,4}$/.test(rn)) out.bad = true;
    else { const n = parseInt(rn, 10); if (n < -60 || n > 9999) out.bad = true; else out.n = n === 0 ? 0 : n; }
  }
  if (rs !== null) {
    if (!/^\d{1,2}$/.test(rs)) out.bad = true;
    else out.s = Math.min(4, Math.max(0, parseInt(rs, 10)));
  }
  if (rv !== null) {
    if (!VARIANTS.has(rv)) out.bad = true; else out.v = rv;
  }
  return out;
}

// deno-lint-ignore no-explicit-any
async function rpc(fn: string, args: Record<string, unknown>): Promise<any> {
  const { data, error } = await db.rpc(fn, args);
  if (error) throw new Error(`${fn}: ${error.message}`);
  return data;
}

type Plan = { el: El; variant: string; maxAge: number };
async function plan(p: Req): Promise<Plan> {
  const brand = (maxAge: number): Plan => ({ el: brandCard(), variant: "brand", maxAge });
  if (p.bad) return brand(3600);
  let v = p.v ?? (p.n === null ? "brand" : p.s !== null ? "result" : "teaser");
  if (v === "brand") return brand(86400);
  if (v === "board") {
    const board = await rpc("ripples_board", { p_n: p.n });
    if (!board) return brand(300);
    return { el: boardCard(board), variant: "board", maxAge: 3600 };
  }
  if (v === "latest") {
    const og = await rpc("ripples_og_data", { p_n: null }) as Og | null;
    if (!og) return brand(300);
    return { el: teaserCard(og, null), variant: "latest", maxAge: 3600 };
  }
  if (p.n === null) return brand(3600);
  const og = await rpc("ripples_og_data", { p_n: p.n }) as Og | null;
  if (!og || !og.seed) return brand(300); // not visible (future, unpublished, vetoed) or unknown n
  let maxAge = og.past ? 86400 : 3600;
  if (v === "result" && p.s === null) v = "teaser";
  // never spoil a puzzle that is still current. The fixture (n=0, TEST data whose answers are published in the
  // repo's contract fixtures) is exempt so the reveal card can be tested before any live puzzle has passed.
  // A live puzzle also needs a NEWER live puzzle to be served: on a delayed day ripples_latest() keeps serving
  // yesterday's puzzle as playable ("Here's yesterday's"), so its reveal must wait even though its date has passed.
  if (v === "reveal" && og.kind !== "fixture") {
    let ok = og.past;
    if (ok && og.kind === "live") {
      const lt = await rpc("ripples_latest", {});
      ok = Number.isInteger(lt?.n) && Number(lt.n) > og.n;
    }
    if (!ok) { v = "teaser"; maxAge = 300; } // short cache: the reveal URL becomes a reveal once the next puzzle is out
  }
  if (v === "reveal") {
    // deno-lint-ignore no-explicit-any
    const rv: any = await rpc("ripples_reveal", { p_n: og.n }).catch(() => null);
    const fl = new Map<number, Fluke>();
    for (const r of Array.isArray(rv?.rounds) ? rv.rounds : []) {
      if (r && Number.isInteger(r.i)) fl.set(r.i, { fluke_1_in: r.evidence?.fluke_1_in ?? null, fluke_warming: r.evidence?.fluke_warming === true });
    }
    return { el: revealCard(og, fl), variant: "reveal", maxAge };
  }
  if (v === "result") {
    const R = og.R || og.rounds.length;
    return { el: teaserCard(og, Math.min(p.s!, R)), variant: "result", maxAge };
  }
  return { el: teaserCard(og, null), variant: "teaser", maxAge };
}

const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, OPTIONS", "Access-Control-Allow-Headers": "x-collector-token" };

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "GET" && req.method !== "HEAD") return new Response("method not allowed", { status: 405, headers: CORS });
  const t0 = performance.now();
  const url = new URL(req.url);
  const p = parse(url);
  let pl: Plan;
  try { pl = await plan(p); } catch (e) {
    console.error("og data error", String(e));
    pl = { el: brandCard(), variant: "brand", maxAge: 300 };
  }
  let png: Uint8Array;
  try { png = await render(pl.el); } catch (e) {
    console.error("render error", pl.variant, String(e));
    try { png = await render(brandCard()); pl = { ...pl, variant: "brand", maxAge: 300 }; }
    catch (e2) { return new Response("render unavailable", { status: 503, headers: { ...CORS, "Cache-Control": "no-store", "Content-Type": "text/plain" } }); }
  }
  const headers: Record<string, string> = {
    ...CORS,
    "X-Card-Variant": pl.variant,
    "X-Render-Ms": String(Math.round(performance.now() - t0)),
  };
  if (url.searchParams.get("b64") === "1") {
    const token = req.headers.get("x-collector-token") ?? "";
    let ok = false;
    if (token) { try { ok = (await rpc("check_collector_token", { t: token })) === true; } catch { ok = false; } }
    if (ok) return new Response(b64(png), { headers: { ...headers, "Content-Type": "text/plain", "Cache-Control": "no-store" } });
  }
  return new Response(req.method === "HEAD" ? null : png, {
    headers: { ...headers, "Content-Type": "image/png", "Cache-Control": `public, max-age=${pl.maxAge}` },
  });
});
