// ripples-resolve (Knock-On v5 / W2). verify_jwt = false; gated by x-collector-token.
// Job payload: {"job":{...}, "budget":n, "items":[{"lang","title"}], "queries":[{"lang","q"}]}
//  * queries (Google Trends / Bluesky text): api.wikimedia.org core search/title on the geo's language wiki; the top hit
//    is accepted only when its title (or the redirect it matched) equals the query, ignoring case and a trailing
//    "(...)" qualifier.
//  * English titles: Action API query (50 titles/request, redirects followed) -> canonical enwiki title, QID, short
//    description, disambiguation flag.
//  * other languages: Wikidata wbgetentities by sitelink (50 titles/request) -> QID -> enwiki sitelink.
//  * facts: wbgetentities (50 ids/request) -> P31, P570, sitelinks; unknown P31 classes -> labels + P279 parents.
// Writes: ripples_ingest_articles (title_map, articles, category_map). SQL computes category, sensitive and blocked.
import { actionApi, Budget, factsFor, kfetch, norm, resolveClasses, rpc, serve, wbEntities, factsFromEntity, type Facts } from "./kn.ts";

const bare = (s: string) => s.toLowerCase().replace(/\s*\([^)]*\)\s*$/, "").replace(/[\s_]+/g, " ").trim();
export const qnorm = (s: string) => s.toLowerCase().replace(/\s+/g, " ").trim();

interface EnInfo { title_en: string; qid: string | null; desc: string | null; disambig: boolean; missing: boolean }

async function enQuery(b: Budget, titles: string[]): Promise<Map<string, EnInfo>> {
  const out = new Map<string, EnInfo>();
  for (let i = 0; i < titles.length; i += 50) {
    const chunk = titles.slice(i, i + 50);
    const j = await actionApi(b, "en.wikipedia.org", {
      action: "query", titles: chunk.join("|"), redirects: "1", prop: "pageprops|description", ppprop: "disambiguation|wikibase_item",
    });
    const q = j.query ?? {};
    const map = new Map<string, string>();
    for (const n of q.normalized ?? []) map.set(n.from, n.to);
    const red = new Map<string, string>();
    for (const r of q.redirects ?? []) red.set(r.from, r.to);
    const pages = new Map<string, any>();
    for (const p of q.pages ?? []) pages.set(p.title, p);
    for (const t of chunk) {
      let x = map.get(t) ?? t;
      for (let k = 0; k < 3 && red.has(x); k++) x = red.get(x)!;
      const p = pages.get(x);
      if (!p || p.missing || p.invalid) { out.set(t, { title_en: x, qid: null, desc: null, disambig: false, missing: true }); continue; }
      out.set(t, {
        title_en: p.title, qid: p.pageprops?.wikibase_item ?? null, desc: p.description ?? null,
        disambig: p.pageprops?.disambiguation !== undefined, missing: false,
      });
    }
  }
  return out;
}

serve(async (body, b) => {
  const items: { lang: string; title: string }[] = (body.items ?? []).map((x: any) => ({ lang: String(x.lang), title: norm(String(x.title)) }));
  const queries: { lang: string; q: string }[] = (body.queries ?? []).map((x: any) => ({ lang: String(x.lang ?? "en"), q: String(x.q) }));
  const titleRows: any[] = [];
  const out: Record<string, number> = { items: items.length, queries: queries.length };

  // 1. queries -> a wiki title in the query's language
  const qTitle = new Map<string, { lang: string; title: string }>();
  for (const { lang, q } of queries) {
    if (b.left() < 20) break;
    try {
      const u = `https://api.wikimedia.org/core/v1/wikipedia/${lang}/search/title?q=${encodeURIComponent(q)}&limit=5`;
      const res = await kfetch(b, u);
      if (!res.ok) { await res.body?.cancel(); continue; }
      const j = await res.json();
      const hit = (j.pages ?? []).find((p: any) => bare(p.title) === bare(q) || (p.matched_title && bare(p.matched_title) === bare(q)));
      if (hit) { qTitle.set(`${lang}|${q}`, { lang, title: norm(hit.title) }); items.push({ lang, title: norm(hit.title) }); }
      else titleRows.push({ lang: `q:${lang}`, title: qnorm(q), qid: null, title_en: null, status: "no_match" });
    } catch (e) { if (b.stopped) throw e; }
  }

  // 2. English titles
  const info = new Map<string, EnInfo & { from: string }>(); // key lang|title
  const enTitles = [...new Set(items.filter((x) => x.lang === "en").map((x) => x.title))];
  const en = await enQuery(b, enTitles);
  for (const [t, v] of en) info.set(`en|${t}`, { ...v, from: t });

  // 3. other languages via Wikidata sitelinks
  const facts = new Map<string, Facts>();
  const byLang = new Map<string, string[]>();
  for (const x of items) if (x.lang !== "en") byLang.set(x.lang, [...(byLang.get(x.lang) ?? []), x.title]);
  const needEn: string[] = [];
  for (const [lang, ts0] of byLang) {
    const ts = [...new Set(ts0)];
    for (let i = 0; i < ts.length && b.left() > 12; i += 50) {
      const chunk = ts.slice(i, i + 50);
      const ents = await wbEntities(b, { sites: `${lang}wiki`, titles: chunk.join("|"), props: "claims|sitelinks|descriptions|labels", languages: "en", redirects: "yes" });
      const bySite = new Map<string, any>();
      for (const e of Object.values(ents) as any[]) {
        const st = e?.sitelinks?.[`${lang}wiki`]?.title;
        if (st && e.id) bySite.set(norm(st).toLowerCase(), e);
      }
      for (const t of chunk) {
        const e = bySite.get(t.toLowerCase());
        const f = e ? factsFromEntity(e) : null;
        if (!f) { titleRows.push({ lang, title: t, qid: null, title_en: null, status: "missing" }); continue; }
        facts.set(f.qid, f);
        if (!f.enwiki) { titleRows.push({ lang, title: t, qid: f.qid, title_en: null, status: "no_en" }); continue; }
        info.set(`${lang}|${t}`, { title_en: f.enwiki, qid: f.qid, desc: null, disambig: false, missing: false, from: t });
        needEn.push(f.enwiki);
      }
    }
  }
  // enwiki short descriptions / disambiguation for titles that came through Wikidata
  const en2 = await enQuery(b, [...new Set(needEn)].filter((t) => !en.has(t)).slice(0, 50 * Math.max(0, Math.floor((b.left() - 10) / 2))));
  for (const [k, v] of info) {
    if (k.startsWith("en|")) continue;
    const e2 = en2.get(v.title_en) ?? en.get(v.title_en);
    if (e2 && !e2.missing) { v.desc = e2.desc; v.disambig = e2.disambig; v.title_en = e2.title_en; }
  }

  // 4. title_map rows
  for (const [k, v] of info) {
    const lang = k.slice(0, k.indexOf("|"));
    titleRows.push({ lang, title: v.from, qid: v.qid, title_en: v.qid ? v.title_en : null, status: v.qid ? "ok" : "missing" });
  }
  for (const [k, v] of qTitle) {
    const lang = k.slice(0, k.indexOf("|"));
    const q = k.slice(k.indexOf("|") + 1);
    const i2 = info.get(`${v.lang}|${v.title}`);
    titleRows.push({ lang: `q:${lang}`, title: qnorm(q), qid: i2?.qid ?? null, title_en: i2?.qid ? i2.title_en : null, status: i2?.qid ? "ok" : "missing" });
  }
  const r1 = await rpc("ripples_ingest_articles", { p_rows: { titles: titleRows } });
  out.titles = titleRows.length;

  // 5. facts for QIDs that are new or stale in ripples.articles
  const need: string[] = (r1?.need_facts ?? []) as string[];
  const missingFacts = need.filter((q) => !facts.has(q));
  const maxFetch = 50 * Math.max(0, Math.floor((b.left() - 6) / 1.2));
  const fetched = await factsFor(b, missingFacts.slice(0, maxFetch));
  for (const [q, f] of fetched) facts.set(q, f);
  const meta = new Map<string, { title_en: string; desc: string | null; disambig: boolean }>();
  for (const v of info.values()) if (v.qid) meta.set(v.qid, { title_en: v.title_en, desc: v.desc, disambig: v.disambig });
  const arts = need.filter((q) => facts.has(q) && meta.has(q)).map((q) => {
    const f = facts.get(q)!, m = meta.get(q)!;
    return { qid: q, title_en: m.title_en, short_desc: m.desc ?? f.desc, p31: f.p31, date_of_death: f.date_of_death, is_disambig: m.disambig, sitelinks: f.sitelinks };
  });
  let unknown: string[] = [];
  if (arts.length) {
    const r2 = await rpc("ripples_ingest_articles", { p_rows: { articles: arts } });
    unknown = (r2?.unknown_classes ?? []) as string[];
  }
  out.articles = arts.length;
  out.classes = unknown.length ? await resolveClasses(b, unknown) : 0;
  out.wm_calls = b.wm;
  return out;
});
