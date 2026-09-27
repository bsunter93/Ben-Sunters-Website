// v2.ts — Ripple Map publish (ENGINE §10.3 att_publish_cascades, §11 Storage paths). Called by index.ts for POST {"v2": true, …}.
//
// 1. public.rm_publish_bundle_v2(as_of, events, full) freezes new line versions (a new version only when the line's substance
//    hash changed), the day's ShockList, and returns every document to mirror, as jsonb::text so re-publishing is byte-identical.
// 2. Storage `ripples/v2/…` with the ENGINE §11 cache headers. Frozen files (cascade/{id}/v{k}.json, og/line-{id}-v{k}.png) are
//    written once (upsert false); an existing frozen object is left untouched, so a re-publish never changes a shared version.
// 3. Feeds: v2/feed/shocks.xml (every published line version, newest first) and v2/feed/line-{id}.xml (one item per version);
//    calendars: v2/ics/hop-{hop}.ics (a Watching stop's window close) and v2/ics/line-{id}.ics (the line's last open window).
// 4. Open data: v2/data/{date}.csv + .json (CC BY 4.0, GREEN-derived rows only; no tickers) and v2/data/index.json.
// 5. OG PNGs pre-rendered through ripples-og (&fresh=1 with the collector token): the brand card, each new line version, the stop
//    cards of lines that changed, the day's shock card (never for a sensitive shock) and the week card. A PNG over 300 KB is not
//    stored and fails the run (status 500, listed in `oversize`).
// 6. Retry and withdrawal (after the 2026-09-26 verification): the bundle sends the text of every public frozen version whose
//    v{k}.json is missing from Storage (checked against storage.objects), so a failed or interrupted upload is retried by every
//    later run until it lands; and it lists `withdraw` paths — withheld versions (raw identifiers in public labels) with their
//    cards, lines with no public version, hops no longer on a public line, and calendars of windows that have closed — which
//    this run removes. Withheld versions stay frozen in the database and the ledger; they are just never served.
// 7. Story layer and pond (2026-09-26 integration): v2/stories.json, v2/patterns.json, v2/pond/index.json, v2/pond/{slug}.json (see storyFiles).
// 8. Statement timeout (API RPCs run under the 8 s authenticator timeout): freezing runs first in chunks through
//    rm_publish_freeze_v2 (the bundle reuses that result), and HopEvidence is fetched in chunks through rm_publish_hops_v2 when the
//    bundle returns `hop_ids` (att_config publish.hops_external).
// deno-lint-ignore-file no-explicit-any
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const BUCKET = "ripples";
const P = "v2/";
const SITE = "https://bensunter.com/ripples";
const MAX_PNG = 300 * 1024;
const OG_BUDGET = 36;          // renders per run (≈ 1 s each; the 08:40 run picks up whatever the 08:25 run left)

type Up = { path: string; body: string | Uint8Array; type: string; cache: string; frozen?: boolean };

const xml = (s: unknown) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const ics = (s: unknown) => String(s ?? "").replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\r?\n/g, "\\n");
const rfc822 = (t: string) => new Date(t).toUTCString();
const ymd = (d: string) => d.replaceAll("-", "");
const csvCell = (v: unknown) => {
  if (v === null || v === undefined) return "";
  const s = String(v);
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
// fold ICS lines at 75 octets
function icsFold(line: string): string {
  const enc = new TextEncoder();
  if (enc.encode(line).length <= 75) return line;
  const out: string[] = []; let cur = "";
  for (const ch of Array.from(line)) {
    if (enc.encode(cur + ch).length > (out.length ? 74 : 75)) { out.push(cur); cur = ch; } else cur += ch;
  }
  out.push(cur);
  return out.join("\r\n ");
}
function calendar(uid: string, date: string, summary: string, desc: string, url: string, stamp: string): string {
  const next = new Date(Date.parse(date + "T00:00:00Z") + 86400000).toISOString().slice(0, 10);
  const lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//bensunter.com//Ripple Map v6//EN", "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
    "BEGIN:VEVENT", `UID:${uid}@bensunter.com`, `DTSTAMP:${stamp}`, `DTSTART;VALUE=DATE:${ymd(date)}`, `DTEND;VALUE=DATE:${ymd(next)}`,
    `SUMMARY:${ics(summary)}`, `DESCRIPTION:${ics(desc)}`, `URL:${url}`, "TRANSP:TRANSPARENT", "END:VEVENT", "END:VCALENDAR"];
  return lines.map(icsFold).join("\r\n") + "\r\n";
}
function rss(title: string, link: string, self: string, desc: string, items: { title: string; link: string; guid: string; date: string; desc: string }[]): string {
  return `<?xml version="1.0" encoding="UTF-8"?>\n<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom"><channel>` +
    `<title>${xml(title)}</title><link>${xml(link)}</link><description>${xml(desc)}</description><language>en</language>` +
    `<atom:link href="${xml(self)}" rel="self" type="application/rss+xml"/>` +
    items.map((i) => `<item><title>${xml(i.title)}</title><link>${xml(i.link)}</link><guid isPermaLink="true">${xml(i.guid)}</guid>` +
      `<pubDate>${rfc822(i.date)}</pubDate><description>${xml(i.desc)}</description></item>`).join("") +
    `</channel></rss>\n`;
}

async function pool<T, R>(items: T[], k: number, fn: (x: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(k, items.length) }, async () => {
    while (i < items.length) { const j = i++; out[j] = await fn(items[j]); }
  }));
  return out;
}

// v2/stories.json (public.rm_stories: the story layer's featured list, archive-wide), v2/patterns.json (public.rm_patterns: 6.2 world
// rules), v2/pond/index.json + v2/pond/{slug}.json (public.rm_pond: the pond page's payload per public line; the RPC returns null when a
// line is not public or any raw identifier would leak, and such a slug is skipped and its file removed).
async function storyFiles(db: SupabaseClient, ups: Up[], J: string, cache: string) {
  const out = { stories: 0, patterns: 0, index: false, written: new Set<string>(), skipped: [] as string[], removed: 0, errors: [] as string[] };
  const st = await db.rpc("rm_stories", { p_limit: 50, p_days: 36500, p_kind: null });
  if (st.error) out.errors.push(`rm_stories: ${st.error.message}`);
  else if (st.data) { ups.push({ path: P + "stories.json", body: JSON.stringify(st.data), type: J, cache }); out.stories = (st.data.featured ?? []).length; }
  const pt = await db.rpc("rm_patterns", {});
  if (pt.error) out.errors.push(`rm_patterns: ${pt.error.message}`);
  else if (pt.data) { ups.push({ path: P + "patterns.json", body: JSON.stringify(pt.data), type: J, cache }); out.patterns = Array.isArray(pt.data) ? pt.data.length : 0; }
  const ix = await db.rpc("rm_pond", { p_slug: null });
  if (ix.error || !ix.data) { out.errors.push(`rm_pond index: ${ix.error?.message ?? "empty"}`); return out; }
  const slugs: string[] = (ix.data.ponds ?? []).map((p: any) => p.slug).filter((s: unknown) => typeof s === "string" && /^[a-z0-9-]+$/.test(s as string));
  const got = await pool(slugs, 4, async (slug) => {
    const r = await db.rpc("rm_pond", { p_slug: slug });
    return { slug, data: r.error ? null : r.data, err: r.error?.message };
  });
  for (const g of got) {
    if (!g.data) { out.skipped.push(`${g.slug}: ${g.err ?? "not public or leaking"}`); continue; }
    ups.push({ path: `${P}pond/${g.slug}.json`, body: JSON.stringify(g.data), type: J, cache });
    out.written.add(g.slug);
  }
  // the index lists only ponds that were actually written
  const idx = { ...ix.data, ponds: (ix.data.ponds ?? []).filter((p: any) => out.written.has(p.slug)) };
  ups.push({ path: P + "pond/index.json", body: JSON.stringify(idx), type: J, cache });
  out.index = true;
  return out;
}

export async function publishV2(db: SupabaseClient, sbUrl: string, token: string, b: any): Promise<{ status: number; body: any }> {
  const t0 = performance.now();
  const asOf = typeof b.as_of === "string" && /^\d{4}-\d{2}-\d{2}$/.test(b.as_of) ? b.as_of : null;
  const events = Array.isArray(b.events) && b.events.every((x: unknown) => Number.isInteger(x)) ? b.events : null;
  const full = b.full === true;
  // 0. freeze in chunks (each RPC stays well inside the API statement timeout); the bundle reuses this freeze instead of repeating it
  const freezeRuns: any[] = [];
  for (let i = 0; i < 20; i++) {
    const { data: fz, error: fe } = await db.rpc("rm_publish_freeze_v2", { p_as_of: asOf, p_events: events, p_cap: 12 });
    if (fe) { console.error("rm_publish_freeze_v2", fe.message); freezeRuns.push({ error: fe.message }); break; }   // the bundle then freezes itself
    freezeRuns.push({ processed: fz?.processed, fresh: fz?.fresh, seen: fz?.seen, candidates: fz?.candidates });
    if (fz?.done) break;
  }
  const { data: bundle, error } = await db.rpc("rm_publish_bundle_v2", { p_as_of: asOf, p_events: events, p_full: full });
  if (error) { console.error("rm_publish_bundle_v2", error.message); return { status: 500, body: { ok: false, error: "bundle_error", detail: error.message } }; }
  const day: string = bundle.as_of;
  const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
  const ups: Up[] = [];
  const J = "application/json; charset=utf-8";
  const C60 = "60", C300 = "300", C3600 = "3600", IMM = "31536000";

  if (bundle.shocks) {
    ups.push({ path: P + "shocks/latest.json", body: bundle.shocks, type: J, cache: C60 });
    ups.push({ path: `${P}shocks/${day}.json`, body: bundle.shocks, type: J, cache: C3600 });
  }
  const newVersions: { e: number; k: number }[] = [];
  const retried: string[] = [];
  const changedEvents = new Set<number>();
  for (const c of bundle.cascades ?? []) {
    if (c.latest) ups.push({ path: `${P}cascade/${c.event_id}.json`, body: c.latest, type: J, cache: C300 });
    const vs: any[] = c.versions ?? [];
    for (const v of vs) {
      if (v.text) {
        ups.push({ path: `${P}cascade/${c.event_id}/v${v.version}.json`, body: v.text, type: J, cache: IMM, frozen: true });
        if (!v.new) retried.push(`${c.event_id}/v${v.version}`);   // missing from Storage (or full): uploaded again
      }
      if (v.new) { newVersions.push({ e: c.event_id, k: v.version }); changedEvents.add(c.event_id); }
    }
    // per-line feed: one item per version
    const latest = c.latest ? JSON.parse(c.latest) : null;
    if (latest?.event) {
      const slug = latest.event.slug, label = latest.event.label;
      const items = vs.slice().reverse().map((v) => ({
        title: `${label}, version ${v.version}: ${v.stops} ${v.stops === 1 ? "stop" : "stops"}, ${v.status === "running" ? "still running" : v.status === "nowhere" ? "went nowhere" : "line ended"}`,
        link: `${SITE}/line/${slug}/v${v.version}/`, guid: `${SITE}/line/${slug}/v${v.version}/`, date: v.published_at,
        desc: `${v.measured} Measured. Consistent with, never proof of cause.${latest.event.reconstructed ? " Reconstructed line." : ""}`,
      }));
      ups.push({ path: `${P}feed/line-${c.event_id}.xml`, body: rss(`Ripple Map: ${label}`, `${SITE}/line/${slug}/`, `${sbUrl}/storage/v1/object/public/${BUCKET}/${P}feed/line-${c.event_id}.xml`,
        "New stops on this line as they pass the fluke tests. Consistent with, never proof of cause.", items), type: "application/rss+xml; charset=utf-8", cache: C300 });
      // calendars: each Watching stop's window close, and the line's last open window
      let last: string | null = null;
      for (const w of c.watching ?? []) {
        if (!w.window_close) continue;
        if (!last || w.window_close > last) last = w.window_close;
        ups.push({ path: `${P}ics/hop-${w.hop_id}.ics`, type: "text/calendar; charset=utf-8", cache: C3600,
          body: calendar(`rm-hop-${w.hop_id}`, w.window_close, `Window closes: ${w.label} (${label})`,
            `The pre-registered window for this stop closes today; the line page shows whether it moved or stayed flat. Consistent with, never proof of cause.`,
            `${SITE}/line/${slug}/stop/${w.hop_id}/`, stamp) });
      }
      if (last) ups.push({ path: `${P}ics/line-${c.event_id}.ics`, type: "text/calendar; charset=utf-8", cache: C3600,
        body: calendar(`rm-line-${c.event_id}`, last, `Last window closes: ${label}`, `The last open window on this line closes today.`, `${SITE}/line/${slug}/`, stamp) });
    }
  }
  // HopEvidence: with att_config publish.hops_external the bundle sends only the prioritised hop ids; fetch them in chunks
  const hopDocs: any[] = [...(bundle.hops ?? [])];
  const hopErrors: string[] = [];
  if (Array.isArray(bundle.hop_ids) && bundle.hop_ids.length) {
    const ids: number[] = bundle.hop_ids.filter((x: unknown) => Number.isInteger(x));
    const chunks: number[][] = [];
    for (let i = 0; i < ids.length; i += 20) chunks.push(ids.slice(i, i + 20));
    const res = await pool(chunks, 3, async (c) => {
      const r = await db.rpc("rm_publish_hops_v2", { p_hops: c });
      if (r.error) hopErrors.push(`rm_publish_hops_v2: ${r.error.message}`);
      return r.data ?? [];
    });
    for (const r of res) hopDocs.push(...r);
  }
  for (const hp of hopDocs) {
    if (hp.json) ups.push({ path: `${P}hop/${hp.hop_id}.json`, body: hp.json, type: J, cache: C3600 });
    if (hp.csv) ups.push({ path: `${P}hop/${hp.hop_id}.csv`, body: hp.csv, type: "text/csv; charset=utf-8", cache: C3600 });
  }
  for (const [dom, txt] of Object.entries(bundle.lands ?? {})) if (txt) ups.push({ path: `${P}lands/${dom}.json`, body: txt as string, type: J, cache: C300 });
  if (bundle.archive) ups.push({ path: P + "archive.json", body: bundle.archive, type: J, cache: C300 });
  if (bundle.calibration) ups.push({ path: P + "calibration.json", body: bundle.calibration, type: J, cache: C3600 });
  if (bundle.week?.text) ups.push({ path: `${P}week/${bundle.week.week}.json`, body: bundle.week.text, type: J, cache: C300 });
  if (bundle.health) ups.push({ path: P + "health.json", body: bundle.health, type: J, cache: C60 });
  // the shocks feed: every published line version, newest first
  ups.push({ path: P + "feed/shocks.xml", type: "application/rss+xml; charset=utf-8", cache: C300,
    body: rss("Ripple Map: new and grown lines", `${SITE}/`, `${sbUrl}/storage/v1/object/public/${BUCKET}/${P}feed/shocks.xml`,
      "Upstream shocks and where they showed up next. Consistent with, never proof of cause.",
      (bundle.feed ?? []).map((f: any) => ({
        title: `${f.emoji ?? ""} ${f.label}: ${f.stops} ${f.stops === 1 ? "stop" : "stops"}${f.reconstructed ? " (reconstructed)" : ""}`.trim(),
        link: `${SITE}/line/${f.slug}/v${f.version}/`, guid: `${SITE}/line/${f.slug}/v${f.version}/`, date: f.published_at, desc: f.text ?? "",
      }))) });
  // open data (CC BY 4.0): GREEN-derived rows only (rm_open_data drops every row touching any other source)
  const od = bundle.open_data;
  if (od && Array.isArray(od.rows)) {
    const cols: string[] = od.columns;
    const csv = [`# ${od.citation}. License: CC BY 4.0. ${od.source}`, cols.join(","), ...od.rows.map((r: unknown[]) => r.map(csvCell).join(","))].join("\n") + "\n";
    ups.push({ path: `${P}data/${day}.csv`, body: csv, type: "text/csv; charset=utf-8", cache: C3600 });
    ups.push({ path: `${P}data/${day}.json`, body: JSON.stringify(od), type: J, cache: C3600 });
  }

  // story layer + 6.2 world rules + pond payloads (separate RPCs: each call stays well inside the API statement timeout)
  const ponds = await storyFiles(db, ups, J, C300);

  const errors: string[] = [];
  const kept: string[] = [];
  const upload = async (u: Up): Promise<void> => {
    const { error } = await db.storage.from(BUCKET).upload(u.path, new Blob([u.body as BlobPart], { type: u.type }),
      { upsert: !u.frozen, contentType: u.type, cacheControl: u.cache });
    if (error) {
      if (u.frozen && /exists|duplicate|409/i.test(error.message + String((error as any).statusCode ?? ""))) { kept.push(u.path); return; }
      errors.push(`${u.path}: ${error.message}`);
    }
  };
  await pool(ups, 8, upload);
  errors.push(...ponds.errors, ...hopErrors);

  // data/index.json from the bucket listing
  if (od) {
    const { data: ls } = await db.storage.from(BUCKET).list(P + "data", { limit: 1000, sortBy: { column: "name", order: "desc" } });
    const days = (ls ?? []).map((o) => o.name).filter((n) => /^\d{4}-\d{2}-\d{2}\.csv$/.test(n)).map((n) => n.slice(0, 10));
    if (!days.includes(day)) days.unshift(day);
    await upload({ path: P + "data/index.json", body: JSON.stringify({ license: "CC BY 4.0", method: "6.0", days: days.sort().reverse() }), type: J, cache: C300 });
  }

  // ---- OG pre-render ----
  const og = { ok: [] as string[], skipped: [] as string[], oversize: [] as string[], err: [] as string[] };
  if (b.prerender !== false) {
    const { data: have } = await db.storage.from(BUCKET).list(P + "og", { limit: 10000 });
    const exists = new Set((have ?? []).map((o) => o.name));
    const jobs: { q: string; name: string; frozen: boolean; cache: string }[] = [];
    if (!exists.has("brand.png") || full) jobs.push({ q: "v=brand", name: "brand.png", frozen: false, cache: "86400" });
    for (const nv of newVersions) jobs.push({ q: `v=line&e=${nv.e}&k=${nv.k}`, name: `line-${nv.e}-v${nv.k}.png`, frozen: true, cache: IMM });
    // frozen line cards that are missing (a previous run ran out of budget)
    for (const c of bundle.cascades ?? []) for (const v of c.versions ?? []) {
      const n = `line-${c.event_id}-v${v.version}.png`;
      if (!exists.has(n) && !jobs.some((j) => j.name === n)) jobs.push({ q: `v=line&e=${c.event_id}&k=${v.version}`, name: n, frozen: true, cache: IMM });
    }
    for (const c of bundle.cascades ?? []) {
      const latest = c.latest ? JSON.parse(c.latest) : null;
      for (const n of latest?.nodes ?? []) {
        if (!["measured", "likely", "retracted"].includes(n.tier)) continue;
        const name = `stop-${n.hop_id}.png`;
        if (changedEvents.has(c.event_id) || !exists.has(name) || full) jobs.push({ q: `v=stop&h=${n.hop_id}`, name, frozen: false, cache: C3600 });
      }
    }
    if (bundle.shock_card?.event_id) jobs.push({ q: `v=shock&e=${bundle.shock_card.event_id}`, name: `shock-${day}.png`, frozen: false, cache: C3600 });
    if (bundle.week?.week) jobs.push({ q: `v=week&w=${bundle.week.week.replace("-", "")}`, name: `week-${bundle.week.week}.png`, frozen: false, cache: C3600 });
    const run = jobs.slice(0, OG_BUDGET);
    for (const j of jobs.slice(OG_BUDGET)) og.skipped.push(j.name + ": over this run's render budget");
    await pool(run, 3, async (j) => {
      try {
        const r = await fetch(`${sbUrl}/functions/v1/ripples-og?${j.q}&fresh=1`, { headers: { "x-collector-token": token } });
        const variant = r.headers.get("x-card-variant") ?? "";
        if (!r.ok || r.headers.get("content-type") !== "image/png") { og.err.push(`${j.name}: og ${r.status}`); await r.body?.cancel(); return; }
        const want = j.name.split("-")[0].replace(".png", "");
        if (variant !== want) {
          og.skipped.push(`${j.name}: og served the ${variant} card (not public / quiet mode / no edition), not stored`); await r.body?.cancel();
          if (!j.frozen && exists.has(j.name)) await db.storage.from(BUCKET).remove([P + "og/" + j.name]);   // never leave a stale card behind
          return;
        }
        const png = new Uint8Array(await r.arrayBuffer());
        if (png.length > MAX_PNG) { og.oversize.push(`${j.name}: ${png.length} bytes`); return; }
        const { error } = await db.storage.from(BUCKET).upload(P + "og/" + j.name, new Blob([png as BlobPart], { type: "image/png" }),
          { upsert: !j.frozen, contentType: "image/png", cacheControl: j.cache });
        if (error && !(j.frozen && /exists|duplicate/i.test(error.message))) og.err.push(`${j.name}: ${error.message}`); else og.ok.push(j.name);
      } catch (e) { og.err.push(`${j.name}: ${String(e)}`); }
    });
  }
  // pond payloads that are no longer public (line withdrawn, off-limits, or leaking) are removed
  if (ponds.index) {
    const { data: pl } = await db.storage.from(BUCKET).list(P + "pond", { limit: 1000 });
    const stale = (pl ?? []).map((o) => o.name).filter((n) => /^[a-z0-9-]+\.json$/.test(n) && n !== "index.json" && !ponds.written.has(n.slice(0, -5)));
    if (stale.length) {
      const { error } = await db.storage.from(BUCKET).remove(stale.map((n) => P + "pond/" + n));
      if (error) errors.push(`pond remove: ${error.message}`); else ponds.removed = stale.length;
    }
  }
  // ---- withdrawal: objects that must not stay public (computed in SQL from storage.objects; paths only under v2/) ----
  const withdraw: string[] = (Array.isArray(bundle.withdraw) ? bundle.withdraw : [])
    .filter((x: unknown) => typeof x === "string" && /^v2\/(cascade|feed|hop|og|ics)\/[A-Za-z0-9._\/-]+$/.test(x as string));
  let removed = 0;
  for (let i = 0; i < withdraw.length; i += 100) {
    const chunk = withdraw.slice(i, i + 100);
    const { data, error } = await db.storage.from(BUCKET).remove(chunk);
    if (error) errors.push(`remove: ${error.message}`); else removed += (data ?? []).length;
  }
  const ok = errors.length === 0 && og.oversize.length === 0 && og.err.length === 0;
  const res = {
    ok, as_of: day, freeze: bundle.freeze, lines_frozen: bundle.lines_frozen, new_versions: newVersions,
    frozen_retried: retried.length, held: bundle.held ?? [], grants_fixed: bundle.grants_fixed ?? 0,
    freeze_chunks: freezeRuns, hops: hopDocs.length, hops_deferred: bundle.hops_deferred ?? 0, withdrawn: removed,
    stories: ponds.stories, patterns: ponds.patterns, ponds: ponds.written.size, ponds_skipped: ponds.skipped, ponds_removed: ponds.removed,
    uploaded: ups.length - errors.length - kept.length, frozen_kept: kept.length, errors, og,
    ms: Math.round(performance.now() - t0),
  };
  await db.rpc("rm_publish_log", { p_as_of: day, p_stage: ok ? "published" : "published_with_errors",
    p_result: { ...res, og: { ok: og.ok.length, skipped: og.skipped.length, oversize: og.oversize, err: og.err } } });
  console.log(JSON.stringify({ ...res, og: { ok: og.ok.length, skipped: og.skipped.length, oversize: og.oversize.length, err: og.err.length } }));
  return { status: ok ? 200 : (og.oversize.length ? 500 : 207), body: res };
}
