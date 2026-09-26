// cards.ts — Ripple Map share cards (EXPERIENCE §7, ART_DIRECTION §5). Pure element builders: no I/O, no Deno APIs, so the
// same file renders in the edge function (index.ts) and in a local Node harness.
//
// Every card: 1200×630, flat colour (no grain), top strip at y 40–84 (wordmark left, date / version / stamp right), content from
// y ≥ 106, footer "bensunter.com/ripples ▪ Consistent with, never proof of cause." (Plex 500 30) at the bottom, ≤ 12 words of
// copy besides the footer, no score, no causal wording. Fonts: "Anybody" 800/900 (names, numbers) and "Plex" 500/700 (sentences).

export const W = 1200, H = 630;
export const C = {
  petrol: "#0B3A40", marigold: "#F2AE2E", white: "#FFFFFF", stage: "#EDF1EE",
  panel2: "#114850", onPanel: "#EAF3F0", onPanel2: "#A9C4C1", onPanel3: "#8FB0B2",
  ink2: "#3C5E62", ink3: "#557275", flat: "#7C9C9E", band: "#D3DDDA", hair: "#D3DDDA",
};
export const FOOTER_A = "bensunter.com/ripples";
export const FOOTER_B = "Consistent with, never proof of cause.";

export type El = { type: string; props: Record<string, unknown> };
// deno-lint-ignore no-explicit-any
export const h = (type: string, style: Record<string, unknown> = {}, children?: any, extra: Record<string, unknown> = {}): El =>
  ({ type, props: { ...extra, style: type === "div" ? { display: "flex", ...style } : style, children } });

export const clip = (s: unknown, max: number): string => {
  const t = String(s ?? "").replace(/[\u0000-\u001f\u007f-\u009f]/g, " ").replace(/\s+/g, " ").trim();
  const a = Array.from(t);
  return a.length > max ? a.slice(0, max - 1).join("").trimEnd() + "…" : t;
};
// "0.91×", "3.4×", "12×"; rates in points
export function mult(x: unknown, unit = "x"): string {
  const v = Number(x);
  if (x === null || x === undefined || !isFinite(v)) return "";
  if (unit === "points") return (v >= 0 ? "+" : "") + v.toFixed(2) + " pts";
  if (v <= 0) return "";
  if (v < 1) return v.toFixed(2) + "×";
  if (v < 10) return v.toFixed(1).replace(/\.0$/, "") + "×";
  return String(Math.round(v)) + "×";
}
const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
export const fmtDate = (d: unknown): string => {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(d ?? ""));
  return m ? `${+m[3]} ${MON[+m[2] - 1]} ${m[1]}` : "";
};
export const DOMAIN_ICON: Record<string, string> = {
  reading: "📖", chatter: "💬", markets: "📊", builders: "🧰", real_world: "🛫", jobs: "🧑‍💼", institutions: "🏛", stuff: "🛍",
};
export const DOMAIN_WORD: Record<string, string> = {
  reading: "Reading", chatter: "Chatter", markets: "Markets", builders: "Builders", real_world: "Real world", jobs: "Jobs",
  institutions: "Institutions", stuff: "Stuff",
};

// ---------- data shapes (subsets of the v2 contracts) ----------
export type Node = {
  hop_id: number; depth: number; parent_hop: number | null; label: string; domain: string; kind: string; tier: string;
  provisional?: boolean; attention_ripple?: boolean; rho?: number | null; lag_days?: number | null; onset?: string | null;
  p_1_in?: number | null; spark?: (number | null)[] | null; unit?: string; retracted?: unknown; window_closed?: boolean;
};
export type Cascade = {
  event: { event_id: number; slug: string; label: string; emoji: string; family: string; sensitive: boolean; reconstructed: boolean;
           onset: string; magnitude_x?: number | null; spark?: (number | null)[] | null };
  version: number; as_of: string; status: string; published_at?: string; nodes: Node[]; flat?: unknown[];
  denominators?: { tested: number; moved: number; measured: number };
};
export type Hop = {
  hop_id: number; event: { label: string; emoji: string; reconstructed: boolean; sensitive: boolean }; parent: { label: string };
  node: { label: string; domain: string }; tier: string; provisional: boolean;
  headline: { rho: number | null; rho_lo: number | null; rho_hi: number | null; lag_days: number | null };
  q1_normal: { series: (number | null)[]; band_lo: number[]; band_hi: number[]; onset_index: number; window: number[]; unit?: string } | null;
  q5_luck: { p_1_in: number | null } | null; retracted: { date: string } | null;
};
export type Week = { week: string; ripple_of_week: Cascade | null; qualified: boolean };

// ---------- shared pieces ----------
// the wordmark: "Knock" + spike hyphen (M0 9.5H5L7.4 1.5L9.8 9.5H15, stroke 2.4 in a 15-unit box) + "On"
export function wordmark(size: number, ink: string, accent: string): El {
  const w = Math.round(size * 0.7), hh = Math.round(size * 0.56);
  return h("div", { alignItems: "center", fontFamily: "Anybody", fontWeight: 900, fontSize: size, color: ink, letterSpacing: -0.012 * size, lineHeight: 1 }, [
    h("div", {}, "Knock"),
    h("svg", { marginLeft: size * 0.04, marginRight: size * 0.04, marginTop: size * 0.12 }, [
      h("path", {}, undefined, { d: "M0 9.5H5L7.4 1.5L9.8 9.5H15", stroke: accent, "stroke-width": 2.4, fill: "none", "stroke-linecap": "round", "stroke-linejoin": "round" }),
    ], { width: w, height: hh, viewBox: "0 0 15 11" }),
    h("div", {}, "On"),
  ]);
}
function topStrip(ink: string, accent: string, right: El | string | null): El {
  return h("div", { position: "absolute", left: 60, right: 60, top: 40, height: 44, justifyContent: "space-between", alignItems: "center" }, [
    wordmark(36, ink, accent),
    typeof right === "string" ? h("div", { fontFamily: "Anybody", fontWeight: 900, fontSize: 30, color: ink }, right) : (right ?? h("div", {}, "")),
  ]);
}
// the one permitted all-caps label: a 4 px bordered stamp (ART §5)
function stamp(word: string, ink: string): El {
  return h("div", { border: `4px solid ${ink}`, color: ink, padding: "4px 12px", fontFamily: "Anybody", fontWeight: 900, fontSize: 24, letterSpacing: 1 }, word);
}
function footer(ink: string, accent: string): El {
  return h("div", { position: "absolute", left: 0, right: 0, bottom: 22, justifyContent: "center", alignItems: "center", fontFamily: "Plex", fontWeight: 500, fontSize: 30, color: ink }, [
    h("div", {}, FOOTER_A),
    h("div", { width: 10, height: 10, background: accent, marginLeft: 14, marginRight: 14 }, ""),
    h("div", {}, FOOTER_B),
  ]);
}
function frame(bg: string, children: El[]): El {
  return h("div", { width: W, height: H, background: bg, position: "relative", fontFamily: "Plex" }, children);
}
const rightTag = (ink: string, text: string, reconstructed: boolean): El =>
  h("div", { alignItems: "center", gap: 14 }, [
    reconstructed ? stamp("RECONSTRUCTED", ink) : null,
    h("div", { fontFamily: "Anybody", fontWeight: 900, fontSize: 30, color: ink }, text),
  ].filter(Boolean));

// halftone fill (Likely): a 6 px dot screen drawn as circles (satori-safe; no pattern elements)
function halftone(size: number, ink: string): El {
  const dots: El[] = [];
  const step = 8;
  for (let y = step / 2; y < size; y += step) {
    for (let x = step / 2; x < size; x += step) dots.push(h("circle", {}, undefined, { cx: x, cy: y, r: 2.4, fill: ink }));
  }
  return h("svg", { position: "absolute", left: 0, top: 0 }, dots, { width: size, height: size, viewBox: `0 0 ${size} ${size}` });
}
// a stop tile: solid (Measured), halftone (Likely), hollow (Watching); domain emoji inside
function stopTile(size: number, tier: string, emoji: string, onDark: boolean): El {
  const ink = onDark ? C.onPanel : C.petrol, ground = onDark ? C.petrol : C.white;
  const base: Record<string, unknown> = { width: size, height: size, borderRadius: 14, position: "relative", alignItems: "center", justifyContent: "center", flexShrink: 0 };
  if (tier === "measured") return h("div", { ...base, background: ink }, [h("div", { fontSize: size * 0.5 }, emoji)]);
  if (tier === "likely") {
    return h("div", { ...base, background: ground, border: `5px solid ${ink}`, overflow: "hidden" }, [
      halftone(size - 10, onDark ? "rgba(234,243,240,0.55)" : "rgba(11,58,64,0.55)"),
      h("div", { fontSize: size * 0.5, width: size * 0.66, height: size * 0.66, background: ground, borderRadius: 10, alignItems: "center", justifyContent: "center" }, emoji),
    ]);
  }
  return h("div", { ...base, border: `5px dashed ${onDark ? C.onPanel3 : C.ink3}` }, [h("div", { fontSize: size * 0.46 }, emoji)]);
}
function track(len: number, dashed: boolean, ink: string): El {
  return h("svg", { flexShrink: 0 }, [
    h("line", {}, undefined, { x1: 0, y1: 5, x2: len, y2: 5, stroke: ink, "stroke-width": 6, "stroke-dasharray": dashed ? "10 8" : "none" }),
  ], { width: len, height: 10, viewBox: `0 0 ${len} 10` });
}

// ---------- stops shown on the line card (frozen with the version) ----------
function stripStops(c: Cascade): { stations: Node[]; watching: Node[]; extra: number } {
  const stations = c.nodes.filter((n) => n.tier === "measured" || n.tier === "likely")
    .sort((a, b) => (a.depth - b.depth) || String(a.onset ?? "").localeCompare(String(b.onset ?? "")) || a.hop_id - b.hop_id);
  // a closed window is not "still watching": it is never drawn as an upcoming (dashed) stop
  const watching = c.nodes.filter((n) => n.tier === "watching" && !n.window_closed);
  const maxTiles = 6;
  const s = stations.slice(0, maxTiles);
  const wv = watching.slice(0, Math.max(0, Math.min(2, maxTiles - s.length)));
  return { stations: s, watching: wv, extra: stations.length - s.length + (watching.length - wv.length) };
}
export function lineMeta(c: Cascade): string {
  const moved = c.nodes.filter((n) => n.tier === "measured" || n.tier === "likely");
  const doms = new Set(moved.map((n) => n.domain));
  const days = Math.max(0, Math.round((Date.parse(c.as_of) - Date.parse(c.event.onset)) / 86400000));
  const st = c.status === "running" ? "still running" : c.status === "nowhere" ? "went nowhere" : "line ended";
  const parts = [`${moved.length} ${moved.length === 1 ? "stop" : "stops"}`];
  if (doms.size) parts.push(`${doms.size} ${doms.size === 1 ? "domain" : "domains"}`);
  parts.push(`${days} ${days === 1 ? "day" : "days"}`, st);
  return parts.join(" ▪ ");
}

// ---------- Line card (petrol): shock title, metro strip, one meta line. Frozen with its version ----------
export function lineCard(c: Cascade): El {
  const { stations, watching, extra } = stripStops(c);
  const tiles: El[] = [];
  const T = 104;
  tiles.push(h("div", { width: T, height: T, borderRadius: 18, background: C.marigold, alignItems: "center", justifyContent: "center", flexShrink: 0 },
    [h("div", { fontSize: 58 }, c.event.emoji || "🔹")]));
  const all = [...stations.map((n) => ({ n, dashed: false })), ...watching.map((n) => ({ n, dashed: true }))];
  const gap = all.length ? Math.max(18, Math.min(64, Math.floor((1080 - T * (all.length + 1) - (extra ? 90 : 0)) / Math.max(1, all.length)))) : 0;
  for (const { n, dashed } of all) {
    tiles.push(track(gap, dashed, dashed ? C.onPanel3 : C.onPanel));
    tiles.push(stopTile(T, n.tier, DOMAIN_ICON[n.domain] ?? "◌", true));
  }
  if (extra > 0) tiles.push(h("div", { marginLeft: 16, fontFamily: "Anybody", fontWeight: 900, fontSize: 40, color: C.onPanel2 }, `+${extra}`));
  if (!all.length) tiles.push(h("div", { marginLeft: 28, fontFamily: "Plex", fontWeight: 700, fontSize: 40, color: C.onPanel2, maxWidth: 820 },
    c.status === "running" ? "Watching for the first stop" : "No stop passed the fluke tests"));
  const title = clip(c.event.label, 40);
  return frame(C.petrol, [
    topStrip(C.onPanel, C.marigold, rightTag(C.onPanel, `v${c.version}`, !!c.event.reconstructed)),
    h("div", { position: "absolute", left: 60, right: 60, top: 108, fontFamily: "Anybody", fontWeight: 900, fontSize: Array.from(title).length > 26 ? 52 : 64,
               color: C.onPanel, lineHeight: 1.05, letterSpacing: -1.2 }, title),
    h("div", { position: "absolute", left: 60, right: 60, top: 236, alignItems: "center" }, tiles),
    h("div", { position: "absolute", left: 60, right: 60, top: 390, fontFamily: "Plex", fontWeight: 700, fontSize: 50, color: C.onPanel, lineHeight: 1.15, alignItems: "center", flexWrap: "wrap" },
      lineMeta(c).split(" ▪ ").flatMap((part, i) => i === 0 ? [h("div", {}, part)] : [h("div", { width: 12, height: 12, background: C.marigold, marginLeft: 22, marginRight: 22 }, ""), h("div", {}, part)])),
    footer(C.onPanel2, C.marigold),
  ]);
}

// ---------- band chart (Stop card): grey normal band, petrol line, marigold segment in the window, upright onset line ----------
function bandChart(q: NonNullable<Hop["q1_normal"]>, w: number, hgt: number): El {
  const n = q.series.length;
  const unitX = q.unit !== "points";
  const tr = (v: number) => unitX ? Math.log(Math.max(v, 1e-3)) : v;
  const vals: number[] = [];
  q.series.forEach((v) => { if (v !== null && isFinite(v)) vals.push(tr(v)); });
  q.band_lo.forEach((v) => vals.push(tr(v))); q.band_hi.forEach((v) => vals.push(tr(v)));
  let lo = Math.min(...vals), hi = Math.max(...vals);
  if (!isFinite(lo) || !isFinite(hi) || hi - lo < 1e-6) { lo = -0.1; hi = 0.1; }
  const pad = (hi - lo) * 0.08; lo -= pad; hi += pad;
  const X = (i: number) => (n <= 1 ? 0 : (i / (n - 1)) * w);
  const Y = (v: number) => hgt - ((tr(v) - lo) / (hi - lo)) * hgt;
  const bandPts = q.band_hi.map((v, i) => `${X(i).toFixed(1)},${Y(v).toFixed(1)}`).join(" ") + " " +
    q.band_lo.map((v, i) => [i, v] as [number, number]).reverse().map(([i, v]) => `${X(i).toFixed(1)},${Y(v).toFixed(1)}`).join(" ");
  const seg = (from: number, to: number) => {
    const out: string[] = [];
    for (let i = Math.max(0, from); i <= Math.min(n - 1, to); i++) { const v = q.series[i]; if (v !== null && isFinite(v as number)) out.push(`${X(i).toFixed(1)},${Y(v as number).toFixed(1)}`); }
    return out.join(" ");
  };
  const w0 = q.window?.[0] ?? q.onset_index, w1 = q.window?.[1] ?? q.onset_index + 7;
  const els: El[] = [
    h("polygon", {}, undefined, { points: bandPts, fill: C.band }),
    h("polyline", {}, undefined, { points: seg(0, w0), fill: "none", stroke: C.petrol, "stroke-width": 4, "stroke-linejoin": "round", "stroke-linecap": "round" }),
    h("polyline", {}, undefined, { points: seg(w0, w1), fill: "none", stroke: C.marigold, "stroke-width": 7, "stroke-linejoin": "round", "stroke-linecap": "round" }),
    h("polyline", {}, undefined, { points: seg(w1, n - 1), fill: "none", stroke: C.petrol, "stroke-width": 4, "stroke-linejoin": "round", "stroke-linecap": "round" }),
    h("line", {}, undefined, { x1: X(q.onset_index), y1: 0, x2: X(q.onset_index), y2: hgt, stroke: C.petrol, "stroke-width": 3 }),
  ];
  return h("svg", {}, els, { width: w, height: hgt, viewBox: `0 0 ${w} ${hgt}` });
}
const TIER_WORD: Record<string, string> = { measured: "Measured", likely: "Likely", watching: "Watching", retracted: "Retracted", flat: "Stayed flat" };
const PIP_N: Record<string, number> = { measured: 3, likely: 2, watching: 1, retracted: 0, flat: 0 };
function pips(tier: string, ink: string): El {
  const n = PIP_N[tier] ?? 0;
  return h("svg", {}, [0, 1, 2].map((i) => h("rect", {}, undefined, { x: i * 20 + 2, y: 2, width: 14, height: 30, fill: i < n ? ink : "none", stroke: ink, "stroke-width": 3 })),
    { width: 62, height: 34, viewBox: "0 0 62 34" });
}
// a multiple as a flap: Anybody numerals, the × in Plex 700 at 0.9em (ART §2.3)
function multEls(x: unknown, unit: string, size: number): El[] {
  const m = mult(x, unit);
  if (!m.endsWith("×")) return [h("div", {}, m || "—")];
  return [h("div", {}, m.slice(0, -1)), h("div", { fontFamily: "Plex", fontWeight: 700, fontSize: size * 0.9 * 0.62, marginLeft: 4, marginTop: size * 0.18 }, "×")];
}

// ---------- Stop card (white ground, petrol ink) ----------
export function stopCard(p: Hop): El {
  const unit = p.q1_normal?.unit ?? "x";
  const lag = p.headline.lag_days;
  const lagTxt = lag === null || lag === undefined ? "after" : Math.round(lag) === 0 ? "the same day as" : `+${Math.round(lag)} ${Math.round(lag) === 1 ? "day" : "days"} after`;
  const retracted = p.tier === "retracted";
  const tierWord = (TIER_WORD[p.tier] ?? p.tier) + (retracted && p.retracted?.date ? ` ${fmtDate(p.retracted.date)}` : "") + (p.provisional ? " (provisional)" : "");
  // rates are differences in points: the flap shows the size, the words say above / below (never "+0.40 pts its normal")
  const pts = unit === "points" && p.headline.rho !== null && p.headline.rho !== undefined;
  const normalWords = pts ? `${Number(p.headline.rho) < 0 ? "below" : "above"} its normal, ${lagTxt}` : `its normal, ${lagTxt}`;
  const luck = p.q5_luck?.p_1_in ? `lookalikes ≈ 1 in ${p.q5_luck.p_1_in}` : "";
  const title = clip(p.node.label, 34);
  return frame(C.white, [
    topStrip(C.petrol, C.marigold, rightTag(C.petrol, clip(p.event.label, 22), !!p.event.reconstructed)),
    h("div", { position: "absolute", left: 60, right: 60, top: 106, fontFamily: "Anybody", fontWeight: 900, fontSize: Array.from(title).length > 22 ? 54 : 64, color: C.petrol, lineHeight: 1.02 }, title),
    h("div", { position: "absolute", left: 60, right: 60, top: 190, alignItems: "center", gap: 28 }, [
      // a retracted stop keeps its old number visible but struck through, on a grey flap (the tier line says "Retracted {date}")
      h("div", { background: retracted ? C.band : C.marigold, border: `3px solid ${C.petrol}`, borderRadius: 10, padding: "4px 22px", fontFamily: "Anybody", fontWeight: 900, fontSize: 96,
                 color: C.petrol, lineHeight: 1.1, alignItems: "flex-start", textDecoration: retracted ? "line-through" : "none" },
        p.headline.rho === null || p.headline.rho === undefined ? "—" : pts ? Math.abs(Number(p.headline.rho)).toFixed(2) + " pts" : multEls(p.headline.rho, unit, 96)),
      h("div", { flexDirection: "column", fontFamily: "Plex", fontWeight: 700, fontSize: 40, color: C.petrol, lineHeight: 1.15, maxWidth: 640 }, [
        h("div", {}, normalWords),
        h("div", { alignItems: "center", gap: 10 }, [h("div", {}, p.event.emoji || "🔹"), h("div", {}, clip(p.parent.label, 26))]),
      ]),
    ]),
    p.q1_normal && p.q1_normal.series.length > 1
      ? h("div", { position: "absolute", left: 100, top: 346 }, [bandChart(p.q1_normal, 1000, 150)])
      : h("div", { position: "absolute", left: 100, top: 400, fontFamily: "Plex", fontWeight: 500, fontSize: 30, color: C.ink3 }, "Series chart on the evidence card"),
    h("div", { position: "absolute", left: 60, right: 60, top: 512, alignItems: "center", gap: 24, fontFamily: "Plex", fontWeight: 700, fontSize: 36, color: C.petrol }, [
      pips(p.tier, C.petrol),
      h("div", {}, tierWord),
      luck ? h("div", { width: 10, height: 10, background: C.marigold, border: `2px solid ${C.petrol}` }, "") : null,
      luck ? h("div", {}, luck) : null,
    ].filter(Boolean)),
    footer(C.ink3, C.marigold),
  ]);
}

// ---------- Shock of the day (marigold ground, petrol ink). Never for sensitive shocks (the caller serves brand) ----------
export function shockCard(c: Cascade): El {
  const meas = c.nodes.filter((n) => n.tier === "measured");
  const watch = c.nodes.filter((n) => n.tier === "watching" && !n.window_closed).slice(0, Math.max(0, 5 - meas.length));
  const title = clip(c.event.label, 30);
  const sp = (c.event.spark ?? []).filter((v): v is number => v !== null && isFinite(v));
  // needle-kick trace along the bottom (ART teaser trace): the event's own ×normal, flat then the kick
  const tw = 1200, th = 120;
  let trace: El | null = null;
  if (sp.length > 4) {
    const lg = sp.map((v) => Math.log(Math.max(v, 0.2)));
    const mn = Math.min(0, ...lg), mx = Math.max(...lg, 0.5);
    const pts = lg.map((v, i) => `${((i / (lg.length - 1)) * (tw - 120) + 20).toFixed(1)},${(th - 8 - ((v - mn) / (mx - mn)) * (th - 20)).toFixed(1)}`).join(" ");
    trace = h("svg", { position: "absolute", left: 0, top: 418 }, [
      h("polyline", {}, undefined, { points: pts, fill: "none", stroke: C.petrol, "stroke-width": 6, "stroke-linejoin": "round", "stroke-linecap": "round" }),
    ], { width: tw, height: th, viewBox: `0 0 ${tw} ${th}` });
  }
  const reached: El[] = meas.map((n) => stopTile(84, "measured", DOMAIN_ICON[n.domain] ?? "◌", false));
  for (const _ of watch) reached.push(h("div", { width: 84, height: 84, borderRadius: 12, border: `5px dashed ${C.petrol}`, alignItems: "center", justifyContent: "center",
                                             fontFamily: "Anybody", fontWeight: 900, fontSize: 48, color: C.petrol }, "?"));
  return frame(C.marigold, [
    topStrip(C.petrol, C.petrol, rightTag(C.petrol, fmtDate(c.as_of), !!c.event.reconstructed)),
    h("div", { position: "absolute", left: 60, right: 60, top: 112, alignItems: "center", gap: 24 }, [
      h("div", { fontSize: 88 }, c.event.emoji || "🔹"),
      h("div", { fontFamily: "Anybody", fontWeight: 900, fontSize: Array.from(title).length > 16 ? 72 : 96, color: C.petrol, lineHeight: 1, letterSpacing: -2 }, title),
    ]),
    c.event.magnitude_x ? h("div", { position: "absolute", left: 60, top: 240, fontFamily: "Plex", fontWeight: 700, fontSize: 56, color: C.petrol },
      `${mult(c.event.magnitude_x)} its normal readers`) : null,
    h("div", { position: "absolute", left: 60, right: 60, top: 322, alignItems: "center", gap: 16 }, [
      h("div", { fontFamily: "Plex", fontWeight: 700, fontSize: 40, color: C.petrol, marginRight: 8 }, reached.length ? "Already reached:" : "Watching for the first stop"),
      ...reached,
    ]),
    trace,
    footer(C.petrol, C.petrol),
  ].filter(Boolean) as El[]);
}

// ---------- Week card (petrol): the staircase drawn large, lanes labelled ----------
// x = days since the shock onset, linear to +7 then log to +90; each lane is its own band (log × its own normal)
function xDays(d: number, maxD: number, w: number): number {
  const f = (t: number) => t <= 7 ? t : 7 + Math.log(t / 7) / Math.log(90 / 7) * 7;   // +7 → 7 units, +90 → 14 units
  const lo = f(-14), hi = f(Math.max(8, maxD));
  return ((f(d) - lo) / (hi - lo)) * w;
}
export function weekCard(wk: Week): El {
  const c = wk.ripple_of_week;
  const W2 = 1100, H2 = 360;
  const lanes: { label: string; spark: (number | null)[]; onsetDay: number; kick: boolean }[] = [];
  if (c) {
    const asOf = Date.parse(c.as_of), on = Date.parse(c.event.onset);
    const dayOf = (s?: string | null) => s ? Math.round((Date.parse(s) - on) / 86400000) : 0;
    lanes.push({ label: c.event.label, spark: c.event.spark ?? [], onsetDay: 0, kick: true });
    for (const n of c.nodes.filter((x) => x.tier === "measured" || x.tier === "likely").slice(0, 5)) {
      lanes.push({ label: n.label, spark: n.spark ?? [], onsetDay: dayOf(n.onset), kick: true });
    }
    const maxD = Math.max(8, Math.round((asOf - on) / 86400000));
    const laneH = H2 / Math.max(lanes.length, 1);
    const els: El[] = [];
    lanes.forEach((ln, li) => {
      const y0 = li * laneH, pad = 8;
      const vals = ln.spark;
      const len = vals.length;
      // spark index i ↔ day (as_of − (len − 1 − i)) relative to the onset
      const pts: [number, number, number][] = [];   // x, y, day
      const lg = vals.map((v) => (v === null || !isFinite(v as number) ? null : Math.log(Math.max(v as number, 0.2))));
      const ok = lg.filter((v): v is number => v !== null);
      const mn = Math.min(0, ...ok), mx = Math.max(0.4, ...ok);
      lg.forEach((v, i) => {
        if (v === null) return;
        const d = maxD - (len - 1 - i);
        if (d < -14) return;
        pts.push([xDays(d, maxD, W2), y0 + laneH - pad - ((v - mn) / (mx - mn || 1)) * (laneH - 2 * pad), d]);
      });
      const before = pts.filter((p) => p[2] <= ln.onsetDay);
      const after = pts.filter((p) => p[2] >= ln.onsetDay);
      els.push(h("line", {}, undefined, { x1: 0, y1: y0 + laneH - 1, x2: W2, y2: y0 + laneH - 1, stroke: "rgba(234,243,240,0.14)", "stroke-width": 2 }));
      if (before.length > 1) els.push(h("polyline", {}, undefined, { points: before.map((p) => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(" "), fill: "none", stroke: C.onPanel, "stroke-width": 3 }));
      if (after.length > 1) els.push(h("polyline", {}, undefined, { points: after.map((p) => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(" "), fill: "none", stroke: C.marigold, "stroke-width": 5 }));
      const ox = xDays(ln.onsetDay, maxD, W2);
      els.push(h("line", {}, undefined, { x1: ox, y1: y0 + 4, x2: ox, y2: y0 + laneH - 4, stroke: C.onPanel2, "stroke-width": 2 }));
    });
    const labels = lanes.map((ln, li) => h("div", { position: "absolute", left: 50 + Math.min(W2 - 360, xDays(ln.onsetDay, maxD, W2) + 12), top: 170 + li * laneH + 4,
      fontFamily: "Plex", fontWeight: 700, fontSize: Math.min(26, Math.max(18, laneH * 0.32)), color: C.onPanel2 }, clip(ln.label, 28)));
    return frame(C.petrol, [
      topStrip(C.onPanel, C.marigold, rightTag(C.onPanel, `Week ${wk.week.slice(5)}`, !!c.event.reconstructed)),
      h("div", { position: "absolute", left: 60, top: 106, fontFamily: "Plex", fontWeight: 700, fontSize: 48, color: C.onPanel }, "Ripple of the week"),
      h("div", { position: "absolute", left: 50, top: 170 }, [h("svg", {}, els, { width: W2, height: H2, viewBox: `0 0 ${W2} ${H2}` })]),
      ...labels,
      footer(C.onPanel2, C.marigold),
    ]);
  }
  return frame(C.petrol, [
    topStrip(C.onPanel, C.marigold, `Week ${wk.week.slice(5)}`),
    h("div", { position: "absolute", left: 60, right: 60, top: 220, fontFamily: "Plex", fontWeight: 700, fontSize: 56, color: C.onPanel, lineHeight: 1.2 },
      "No line reached a Measured stop this week"),
    footer(C.onPanel2, C.marigold),
  ]);
}

// ---------- Brand card (petrol; evergreen, never dated) ----------
export function brandCard(): El {
  const tile = (kick: boolean) => {
    const pts = kick ? "10,96 44,96 58,96 70,36 82,96 122,96" : "10,90 40,88 70,92 100,89 122,90";
    return h("div", { width: 132, height: 132, borderRadius: 14, background: C.panel2, border: kick ? `5px solid ${C.marigold}` : "none", alignItems: "center", justifyContent: "center" }, [
      h("svg", {}, [h("polyline", {}, undefined, { points: pts, fill: "none", stroke: kick ? C.marigold : C.onPanel3, "stroke-width": kick ? 6 : 4, "stroke-linejoin": "round", "stroke-linecap": "round" })],
        { width: 132, height: 132, viewBox: "0 0 132 132" }),
    ]);
  };
  return frame(C.petrol, [
    h("div", { position: "absolute", left: 0, right: 0, top: 108, justifyContent: "center" }, [wordmark(120, C.onPanel, C.marigold)]),
    h("div", { position: "absolute", left: 0, right: 0, top: 268, justifyContent: "center", gap: 28 }, [tile(false), tile(false), tile(true), tile(false)]),
    h("div", { position: "absolute", left: 0, right: 0, top: 438, justifyContent: "center", fontFamily: "Plex", fontWeight: 700, fontSize: 56, color: C.onPanel }, "Where did it ripple?"),
    footer(C.onPanel2, C.marigold),
  ]);
}
