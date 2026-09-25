// ripples-expand (Knock-On v5 / W2). verify_jwt = false; gated by x-collector-token.
// One job per invocation (payload built by SQL ripples._job_payload), <= 100 Wikimedia requests, statistics computed
// here exactly as SPEC §5.2, summaries written through the service RPCs.
//  kind screen : 130-day series for shortlisted seed-source articles -> onset test + calm check (decoy pool)
//  kind expand : parent's outlinks (prop=links) + 60-day prop=pageviews prefilter (+ clickstream top 20 when loaded),
//                fixed candidate set capped at 60, 400-day series per candidate, hop test, time-shift placebo, calm flag
//  kind history: seed's full series since 2015-07-01 -> "biggest day in N days"
//  kind split  : desktop vs mobile multiples (mobile = all-access - desktop) for answer-eligible hops
//  kind refresh: Call It resolution series (baseline frozen at window_start)
import {
  actionApi, addDays, Budget, dayDiff, factsFor, hopTest, LIST_TITLE, logs, baseline, norm, pool, resolveClasses, rpc,
  seedScreen, series, serve, SKIP_TITLE,
} from "./kn.ts";

const r2 = (x: number | null | undefined, k = 4) => (x === null || x === undefined || !isFinite(x) ? null : Number(x.toFixed(k)));

async function screen(body: any, b: Budget) {
  const j = body.job, asOf: string = j.as_of;
  const from = addDays(asOf, -129);
  const items: { qid: string; title: string }[] = body.items ?? [];
  const conc = Number(body.cfg?.aqs_concurrency ?? 4);
  const res = await pool(items.slice(0, Math.max(0, b.left())), conc, async (it) => {
    const v = await series(b, it.title, from, asOf);
    if (!v) return null;
    const s = seedScreen(v, 129);
    const day = (i: number | null) => (i === null ? null : addDays(from, i));
    return {
      qid: it.qid, title: it.title, median_views: r2(s.median_views, 2), onset: day(s.onset), z_peak: r2(s.z_peak, 3),
      peak_multiple: r2(s.peak_multiple, 3), peak_day: day(s.peak_day), max_abs_z14: r2(s.max_abs_z14, 3),
      base_from: day(s.base - 111), base_to: day(s.base - 21), spark: v.slice(-90),
    };
  });
  const rows = res.filter((x) => x && !(x instanceof Error));
  const errs = res.filter((x) => x instanceof Error).length;
  await rpc("ripples_ingest_candidates", { p_job: j.id, p_rows: rows });
  return { screened: rows.length, errors: errs, wm_calls: b.wm };
}

interface PageInfo { title: string; qid: string | null; desc: string | null; disambig: boolean; median60: number | null }

async function prefilter(b: Budget, titles: string[], maxCalls: number): Promise<Map<string, PageInfo>> {
  const out = new Map<string, PageInfo>();
  let calls = 0;
  for (let i = 0; i < titles.length && calls < maxCalls; i += 50) {
    const chunk = titles.slice(i, i + 50);
    const base: Record<string, string> = {
      action: "query", titles: chunk.join("|"), redirects: "1", prop: "pageviews|pageprops|description", pvipdays: "60",
      ppprop: "disambiguation|wikibase_item",
    };
    const pages = new Map<string, any>();
    const normMap = new Map<string, string>(), red = new Map<string, string>();
    let cont: Record<string, string> | null = {};
    for (let k = 0; k < 3 && cont && calls < maxCalls; k++) {
      const jj = await actionApi(b, "en.wikipedia.org", { ...base, ...cont });
      calls++;
      const q = jj.query ?? {};
      for (const n of q.normalized ?? []) normMap.set(n.from, n.to);
      for (const r of q.redirects ?? []) red.set(r.from, r.to);
      for (const p of q.pages ?? []) {
        const prev = pages.get(p.title) ?? {};
        pages.set(p.title, { ...prev, ...p, pageviews: { ...(prev.pageviews ?? {}), ...(p.pageviews ?? {}) } });
      }
      cont = jj.continue ? Object.fromEntries(Object.entries(jj.continue).map(([a, v]) => [a, String(v)])) : null;
    }
    for (const t of chunk) {
      let x = normMap.get(t) ?? t;
      for (let k = 0; k < 3 && red.has(x); k++) x = red.get(x)!;
      const p = pages.get(x);
      if (!p || p.missing || p.invalid || p.ns !== 0) continue;
      const vals = Object.values(p.pageviews ?? {}) as (number | null)[];
      const med = vals.length ? medianOf(vals.map((v) => v ?? 0)) : null;
      out.set(t, { title: p.title, qid: p.pageprops?.wikibase_item ?? null, desc: p.description ?? null, disambig: p.pageprops?.disambiguation !== undefined, median60: med });
    }
  }
  return out;
}
function medianOf(a: number[]) { const s = [...a].sort((x, y) => x - y); const n = s.length; return n % 2 ? s[(n - 1) / 2] : (s[n / 2 - 1] + s[n / 2]) / 2; }
function fnv(s: string) { let h = 0x811c9dc5; for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; } return h; }

async function expand(body: any, b: Budget) {
  const j = body.job, asOf: string = j.as_of, cfg = body.cfg ?? {};
  const cap = Number(cfg.candidate_cap ?? 60), minMed = Number(cfg.min_outlink_median ?? 300);
  const blocks: RegExp[] = (body.block_patterns ?? []).map((p: string) => { try { return new RegExp(p, "i"); } catch { return null; } }).filter(Boolean);
  const bad = (t: string) => SKIP_TITLE.test(t) || LIST_TITLE.test(t) || blocks.some((r) => r.test(t));
  const parentTitle = norm(j.parent_title);

  // 1. live outlinks (ns 0), up to 4 requests (2000 links)
  const links: string[] = [];
  let canonParent = parentTitle;
  let cont: Record<string, string> | null = {};
  for (let k = 0; k < 4 && cont; k++) {
    const jj = await actionApi(b, "en.wikipedia.org", { action: "query", titles: parentTitle, redirects: "1", prop: "links", plnamespace: "0", pllimit: "max", ...cont });
    const p = (jj.query?.pages ?? [])[0];
    if (!p || p.missing) throw new Error(`parent page missing: ${parentTitle}`);
    canonParent = p.title;
    for (const l of p.links ?? []) links.push(norm(l.title));
    cont = jj.continue ? Object.fromEntries(Object.entries(jj.continue).map(([a, v]) => [a, String(v)])) : null;
  }
  const linkSet = new Set(links);
  // 2. candidate pool: clickstream top 20 (when loaded) + outlinks, minus disambiguation/list/date/year/parent/blocklist
  const cs: { title: string; clicks: number; rank: number }[] = (body.clickstream ?? []).map((c: any) => ({ title: norm(c.title), clicks: Number(c.clicks), rank: Number(c.rank) }));
  const csTitles = cs.map((c) => c.title).filter((t) => !bad(t) && t !== canonParent);
  let out = [...new Set(links)].filter((t) => !bad(t) && t !== canonParent && !csTitles.includes(t));
  const maxCalls = Number(cfg.expand_prefilter_calls ?? 14);
  const room = Math.max(0, maxCalls * 50 - csTitles.length);
  if (out.length > room) out = out.sort((a, c) => fnv(a) - fnv(c)).slice(0, room);   // unbiased deterministic subset
  const info = await prefilter(b, [...csTitles, ...out], Math.min(maxCalls + 4, Math.max(0, b.left() - 70)));
  const seen = new Set<string>();
  const cands: any[] = [];
  const add = (t: string, csRow: { clicks: number; rank: number } | null) => {
    const p = info.get(t);
    if (!p || !p.qid || p.disambig || bad(p.title) || p.title === canonParent || seen.has(p.qid) || p.qid === j.parent_qid || p.qid === j.root_qid) return;
    seen.add(p.qid);
    cands.push({ qid: p.qid, title: p.title, desc: p.desc, cs_rank: csRow?.rank ?? null, cs_clicks: csRow?.clicks ?? null, linked: linkSet.has(t) || linkSet.has(p.title), median60: p.median60 });
  };
  for (const c of cs) if (csTitles.includes(c.title)) add(c.title, c);
  const outRanked = out.map((t) => [t, info.get(t)?.median60 ?? -1] as [string, number]).filter(([, m]) => m >= minMed).sort((a, c) => c[1] - a[1]);
  for (const [t] of outRanked) { if (cands.length >= cap) break; add(t, null); }
  const set = cands.slice(0, cap).map((c, i) => ({ ...c, set_rank: i + 1 }));

  // 3. 400-day series per candidate and the hop test
  const from = addDays(asOf, -399);
  const a = 399;
  const tp = dayDiff(j.parent_onset, from);
  const budgetForSeries = Math.max(0, b.left() - 4);
  const tested = set.slice(0, budgetForSeries);
  const conc = Number(cfg.aqs_concurrency ?? 4);
  const res = await pool(tested, conc, async (c) => {
    const v = await series(b, c.title, from, asOf);
    if (!v) return null;
    const h = hopTest(v, tp, a);
    if (!h) return null;
    return {
      qid: c.qid, title: c.title, desc: c.desc, cs_rank: c.cs_rank, cs_clicks: c.cs_clicks, set_rank: c.set_rank, linked: c.linked,
      median_views: r2(h.median_views, 2), s_stat: r2(h.s_stat, 4), onset_lag: h.onset_lag, multiple: r2(h.multiple, 4),
      p_time: r2(h.p_time, 5), n_placebo: h.n_placebo, pass_raw: h.pass_raw, calm: h.calm, max_abs_z: r2(h.max_abs_z, 4),
      spark: h.pass_raw || h.calm ? v.slice(-90) : null,
    };
  });
  const rows = res.filter((x) => x && !(x instanceof Error)) as any[];
  const errs = res.filter((x) => x instanceof Error).map((e) => (e as Error).message).slice(0, 3);
  const ing = await rpc("ripples_ingest_candidates", { p_job: j.id, p_rows: rows.map(({ desc: _d, ...r }) => r) });

  // 4. Wikidata facts for pass/calm candidates not yet (or long ago) resolved
  const need: string[] = (ing?.need_articles ?? []) as string[];
  let classes = 0, arts = 0;
  if (need.length && b.left() > 1) {
    const facts = await factsFor(b, need.slice(0, 50 * Math.max(1, Math.min(2, b.left() - 1))));
    const byQ = new Map(rows.map((r) => [r.qid, r]));
    const artRows = [...facts.values()].map((f) => ({
      qid: f.qid, title_en: byQ.get(f.qid)?.title ?? f.enwiki ?? f.label, short_desc: byQ.get(f.qid)?.desc ?? f.desc, p31: f.p31,
      date_of_death: f.date_of_death, is_disambig: false, sitelinks: f.sitelinks,
    })).filter((r) => r.title_en);
    arts = artRows.length;
    if (artRows.length) {
      const ra = await rpc("ripples_ingest_articles", { p_rows: { articles: artRows } });
      const unknown = (ra?.unknown_classes ?? []) as string[];
      if (unknown.length && b.left() > 1) classes = await resolveClasses(b, unknown, 2);
    }
  }
  return { links: links.length, pool: csTitles.length + out.length, set: set.length, tested: rows.length, pass_raw: rows.filter((r) => r.pass_raw).length,
    calm: rows.filter((r) => r.calm).length, series_errors: errs, articles: arts, classes, wm_calls: b.wm };
}

async function history(body: any, b: Budget) {
  const j = body.job;
  const items: { qid: string; title: string; onset: string; as_of: string }[] = body.items ?? [];
  const results: any[] = [];
  for (const it of items) {
    const from = "2015-07-01";
    const v = await series(b, it.title, from, it.as_of);
    if (!v) continue;
    const t0 = dayDiff(it.onset, from), a = dayDiff(it.as_of, from);
    let peak = -1, pd = t0;
    for (let d = t0; d <= a; d++) if (v[d] > peak) { peak = v[d]; pd = d; }
    let prev: number | null = null;
    for (let d = t0 - 1; d >= 0; d--) if (v[d] >= peak) { prev = d; break; }
    const row = { qid: it.qid, peak_views: peak, peak_day: addDays(from, pd), biggest_in_days: prev === null ? null : pd - prev, biggest_since_records: prev === null };
    await rpc("ripples_ingest_seed_history", { p_job: j.id, p_row: row });
    results.push(row);
  }
  return { seeds: results.length, wm_calls: b.wm };
}

async function split(body: any, b: Budget) {
  const j = body.job, asOf: string = j.as_of;
  const items: { parent_qid: string; qid: string; title: string; parent_onset: string }[] = body.items ?? [];
  const conc = Number(body.cfg?.aqs_concurrency ?? 4);
  const res = await pool(items.slice(0, Math.floor(b.left() / 2)), Math.max(1, Math.floor(conc / 2)), async (it) => {
    const from = addDays(it.parent_onset, -111);
    const [all, desk] = await Promise.all([series(b, it.title, from, asOf), series(b, it.title, from, asOf, "desktop")]);
    if (!all || !desk) return { parent_qid: it.parent_qid, qid: it.qid, mult_desktop: null, mult_mobile: null };
    const mob = all.map((v, i) => Math.max(0, v - (desk[i] ?? 0)));
    const tp = 111, a = dayDiff(asOf, from), end = Math.min(tp + 3, a);
    const mult = (v: number[]) => {
      const bl = baseline(logs(v), tp);
      if (!bl) return null;
      let mx = 0;
      for (let d = tp; d <= end; d++) mx = Math.max(mx, v[d]);
      return mx / Math.max(bl.med, 1);
    };
    return { parent_qid: it.parent_qid, qid: it.qid, mult_desktop: r2(mult(desk), 4), mult_mobile: r2(mult(mob), 4) };
  });
  const rows = res.filter((x) => x && !(x instanceof Error));
  await rpc("ripples_ingest_candidates", { p_job: j.id, p_rows: rows });
  return { split: rows.length, wm_calls: b.wm };
}

async function refresh(body: any, b: Budget) {
  const j = body.job;
  const items: { n: number; qid: string; title: string; window_start: string; window_end: string }[] = body.items ?? [];
  const res = await pool(items.slice(0, b.left()), 2, async (it) => {
    const from = addDays(it.window_start, -111);
    const v = await series(b, it.title, from, it.window_end);
    if (!v) return { n: it.n, qid: it.qid, max_z: null, hit: false, max_multiple: null };
    const x = logs(v);
    const bl = baseline(x, 111)!;          // baseline frozen at window_start
    let maxZ = -Infinity, maxM = 0, hit = false;
    for (let d = 111; d < v.length; d++) {
      const z = (x[d] - bl.m) / bl.s, m = v[d] / Math.max(bl.med, 1);
      maxZ = Math.max(maxZ, z); maxM = Math.max(maxM, m);
      if (z >= 3 && m >= 1.5) hit = true;
    }
    return { n: it.n, qid: it.qid, max_z: r2(maxZ, 3), hit, max_multiple: r2(maxM, 3) };
  });
  const rows = res.filter((x) => x && !(x instanceof Error));
  await rpc("ripples_ingest_candidates", { p_job: j.id, p_rows: rows });
  return { resolved: rows.length, wm_calls: b.wm };
}

serve(async (body, b) => {
  const kind = body?.job?.kind;
  if (kind === "screen") return await screen(body, b);
  if (kind === "expand") return await expand(body, b);
  if (kind === "history") return await history(body, b);
  if (kind === "split") return await split(body, b);
  if (kind === "refresh") return await refresh(body, b);
  throw new Error(`unknown job kind ${kind}`);
});
