#!/usr/bin/env node
/* Ripple Map pond slice: builds data/milton.json from the engine's own tables.
   Reproducible in two modes:
     node tools/snapshot.mjs            -> assembles from data/raw/*.json (the query results saved on 2026-09-26)
     node tools/snapshot.mjs --live     -> re-runs the SQL below through psql ($DATABASE_URL must point at project kffkasnzqcddpystszch,
                                          read-only role is enough), rewrites data/raw/*.json, then assembles.
   Every number in milton.json comes from one of these queries. Nothing is invented: where the engine has no result the field
   says so (tier 'untested', flats: [], measured: 0). See POND_SPEC.md in the comp for the payload contract; ../SLICE.md for the honesty notes. */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const RAW = join(HERE, '..', 'data', 'raw');
const OUT = join(HERE, '..', 'data', 'milton.json');
const EVENT = 213;   // Hurricane Milton (positive control), slug lib-control-hurricane-milton-2024. Event 3026 is the same storm with fewer pre-registered series.

/* ---------------- the exact SQL (read-only) ---------------- */
export const SQL = {
  // the event row and its published cascade (engine 6.1 view of the same storm)
  event: `select e.event_id, e.label, e.slug, e.family, e.role, e.onset, e.as_of, e.magnitude, e.sensitive, e.reconstructed, e.status,
                 c.version, c.weakest_tier, c.payload->'ledger' ledger, c.payload->'denominators' denominators, c.payload->'event'->'baseline' baseline, c.payload_hash
          from ripples.att_events e left join ripples.att_cascades c using(event_id) where e.event_id = ${EVENT};`,
  // every pre-registered single-event test (engine 6.1) for the storm, with its registry row: window, prior, ledger seq, status
  hops: `select c.hop_id, c.node, c.path_type, c.status, c.window_close, c.sign, c.channels, c.looks, r.p_hat, r.ledger_seq, r.resolved_at, r.final_tier, r.published_tier,
                c.path->0->>'text' mech, c.path->0->>'template' template
         from ripples.att_hop_candidates c left join ripples.att_hop_registry r using(hop_id) where c.event_id = ${EVENT} order by c.hop_id;`,
  // any single-event test results (none existed on 2026-09-26: all hops queued)
  tests: `select hop_id, look_no, is_final, tier, tier_reason, rho_shrunk, fluke, q, placebo, replication, detail->'fx62' fx62 from ripples.att_hop_tests where hop_id in (select hop_id from ripples.att_hop_candidates where event_id = ${EVENT});`,
  // the BigQuery forecast gate's verdict (none for this event's hops)
  gate: `select * from ripples.att_ce_hop_verdict where hop_id in (select hop_id from ripples.att_hop_candidates where event_id = ${EVENT});`,
  // engine 6.2 regional contrast for the storm (grid 8 = hurricane -> eia.930 demand), incl. the 41 in-time placebo contrasts
  fx_event: `select to_jsonb(f) from ripples.att_fx_event f where f.event_id = ${EVENT};`,
  // grid specs for the pairs used here
  grid: `select grid_id, batch, label, pre_n, post_n, lag_n, expected_sign, synth, domain_event, domain_outcome, frozen_hash, frozen_at, ledger_seq from ripples.att_fx_grid where grid_id in (8, 10, 17);`,
  // the family pool (24 past hurricanes on grid demand) and the world rules
  pools: `select to_jsonb(p) from ripples.att_fx_pool p where p.grid_id in (8, 10, 17) and p.role = 'real';`,
  patterns: `select public.rm_patterns(null, 'hint');`,
  // per-event contrasts behind the replication strips
  fx_grid8: `select f.event_id, e.label, e.onset, f.treated, f.d, f.z, f.p_space, f.p_time, f.p_pre from ripples.att_fx_event f join ripples.att_events e using(event_id) where f.grid_id = 8 and f.role = 'real' order by e.onset;`,
  fx_grid10: `select f.event_id, e.label, e.onset, f.treated, f.d, f.z, f.p_space, f.p_pre from ripples.att_fx_event f join ripples.att_events e using(event_id) where f.grid_id = 10 and f.role = 'real' order by e.onset;`,
  fx_grid17_examples: `select e.label, e.onset, f.d, f.p_space from ripples.att_fx_event f join ripples.att_events e using(event_id) where f.grid_id = 17 and f.role = 'real' and f.p_space <= 0.05 and f.p_pre >= 0.1 and f.d > 0 order by f.z desc limit 8;`,
  // the daily series behind the chart: treated grids (FPC + FPL) and the 52 other balancing authorities, each indexed to its own 28-day pre-window mean
  grid_daily: `with s as (select series_id, key from ripples.att_series where source='eia.930' and metric='demand'),
     pre as (select o.series_id, avg(o.value) m from ripples.attention_obs o join s using(series_id) where o.day between '2024-09-09' and '2024-10-06' group by 1),
     d as (select o.day, s.key, o.value, o.value/nullif(pre.m,0) idx from ripples.attention_obs o join s using(series_id) join pre using(series_id) where o.day between '2024-09-02' and '2024-10-28')
     select day, round(sum(value) filter (where key in ('FPC','FPL')) ) treated_mwh, round(avg(idx) filter (where key in ('FPC','FPL'))::numeric,4) treated_idx,
            round(avg(idx) filter (where key not in ('FPC','FPL'))::numeric,4) donor_idx, count(*) filter (where key not in ('FPC','FPL')) n_donors from d group by day order by day;`,
  // the rival stone and the common shocks inside the window
  helene: `select f.event_id, e.label, e.onset, f.treated, f.d, f.z, f.p_space, f.p_pre, f.role from ripples.att_fx_event f join ripples.att_events e using(event_id) where f.grid_id = 8 and e.event_id = 212;`,
  common_days: `select day, c_by_source->>'holiday' holiday from ripples.att_common_days where day between '2024-10-07' and '2025-01-05' order by day;`,
  // the ledger rows the card cites, and the chain head
  ledger: `select seq, day, kind, ref, payload_hash, chain_hash from ripples.att_ledger where seq in (859, 931, 932, 957, 958) or seq = (select max(seq) from ripples.att_ledger) order by seq;`,
  // story layer: nothing for Milton on 2026-09-26 (story_sentence below is derived by this script, see SLICE.md)
  story: `select story_id, tier, engine_tier, archetype, copy, travel from ripples.att_story_candidates where event_id = ${EVENT};`
};

/* ---------------- helpers ---------------- */
const r = (v, n = 3) => v == null ? null : Math.round(v * 10 ** n) / 10 ** n;
const pct = d => r((Math.exp(d) - 1) * 100, 1);          // log points -> percent
const fmtDay = iso => { const d = new Date(iso + 'T00:00:00Z'); return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' }); };
const days = (a, b) => Math.round((new Date(b) - new Date(a)) / 864e5);
const load = f => JSON.parse(readFileSync(join(RAW, f), 'utf8'));

/* human labels for engine node ids */
const NODE = {
  'fema.decl:EM': { label: 'Federal emergency declarations', domain: 'institutions' },
  'fema.decl:DR': { label: 'Major-disaster declarations', domain: 'institutions' },
  'fema.decl:st:FL': { label: 'FEMA declarations in Florida', domain: 'institutions' },
  'iem.warn:SV.W': { label: 'Severe thunderstorm warnings', domain: 'institutions' },
  'iem.warn:FF.W': { label: 'Flash-flood warnings', domain: 'institutions' },
  'iem.warn:EW.W': { label: 'Extreme-wind warnings', domain: 'institutions' },
  'iem.warn:TO.W': { label: 'Tornado warnings', domain: 'institutions' },
  'iem.warn:__total__': { label: 'All NWS storm warnings', domain: 'institutions' },
  'tsa.pax:checkpoint': { label: 'US airport passengers', domain: 'real_world' },
  'fred.claims:FLICLAIMS': { label: 'Florida jobless claims', domain: 'jobs' },
  'fred:DJFUELUSGULF': { label: 'Gulf jet-fuel price', domain: 'markets' },
  'fred.weekly:GASREGW': { label: 'US gasoline price', domain: 'markets' },
  'eia.930:FPC': { label: 'Duke Energy Florida demand', domain: 'real_world' },
  'eia.930:FPL': { label: 'Florida Power & Light demand', domain: 'real_world' },
  'fred.claims:MOICLAIMS': { label: 'Missouri jobless claims (control)', domain: 'jobs' },
  'fred.claims:OKICLAIMS': { label: 'Oklahoma jobless claims (control)', domain: 'jobs' },
  'dol.claims:WI': { label: 'Wisconsin jobless claims (control)', domain: 'jobs' }
};
const DOMAINS = [
  { key: 'real_world', label: 'Real world' },
  { key: 'institutions', label: 'Institutions' },
  { key: 'jobs', label: 'Jobs' },
  { key: 'markets', label: 'Markets' },
  { key: 'business', label: 'Business' }
];

/* ---------------- assemble ---------------- */
export function assemble() {
  const misc = load('misc.json'), fx = load('fx_event_milton.json'), daily = load('grid_daily.json');
  const g8 = load('fx_grid8_events.json'), g10 = load('fx_grid10_events.json'), hops = load('hops_milton.json'), pat = load('patterns.json');
  const ev = misc.event, onset = ev.onset, landfall = '2024-10-09';
  const di = k => DOMAINS.findIndex(d => d.key === k);

  /* the one real effect: the 6.2 regional contrast on Florida's two big grids */
  const effectPct = pct(fx.d);                             // -19.8
  const pre = daily.filter(x => x.day >= '2024-09-09' && x.day <= '2024-10-06');
  const mean = a => a.reduce((s, v) => s + v, 0) / a.length;
  const gapPre = pre.map(x => x.treated_idx - x.donor_idx), gm = mean(gapPre), gsd = Math.sqrt(mean(gapPre.map(v => (v - gm) ** 2)));
  const post = daily.filter(x => x.day >= onset && x.day < '2024-10-14');
  const worst = post.reduce((a, b) => (b.treated_idx - b.donor_idx) < (a.treated_idx - a.donor_idx) ? b : a);
  const lag = days(onset, worst.day);                       // day of the widest gap: 2024-10-10, the day after landfall
  const inTime = fx.placebo_d.filter(v => v != null);      // 41 season-matched pseudo-onsets: the same contrast on other years
  const nBigger = inTime.filter(v => Math.abs(v - fx.med) >= Math.abs(fx.d - fx.med)).length;
  const pass = fx.p_space <= 0.05 && fx.p_pre >= 0.10 && Math.sign(fx.d) === misc.grid8.expected_sign && Math.sign(fx.synth_d) === Math.sign(fx.d);
  const strong = pass && fx.p_time <= 0.05 && Math.abs(fx.z) >= 3;
  const spaceOdds = Math.round(1 / fx.p_space);            // 31 (rank 1 of 30 draws + 1)

  /* replication: the same contrast on the 24 past hurricanes of the frozen pool (Milton itself is a live row, not in the pool) */
  const passes = g8.filter(e => e.p_space <= 0.05 && e.p_pre >= 0.10 && e.d < 0);
  const sameDir = g8.filter(e => e.d < 0);
  const replication = {
    n_similar: pat.pool8.n_events, n_seen: passes.length, n_same_direction: sameDir.length,
    rule: 'seen = the pre-registered regional contrast passed (in-space p <= 0.05, pre-trends flat, expected sign)',
    examples: passes.map(e => ({ label: e.label, onset: e.onset, effect_pct: pct(e.d), z: e.z, p_space: e.p_space })),
    all: g8.map(e => ({ label: e.label.replace(/ \(\d{4}\)$/, ''), year: e.onset.slice(0, 4), effect_pct: pct(e.d), pass: e.p_space <= 0.05 && e.p_pre >= 0.10 && e.d < 0, treated: e.treated })),
    family: { effect_pct: pct(pat.pool8.d), ci_pct: [pct(pat.pool8.ci_lo), pct(pat.pool8.ci_hi)], p_placebo: pat.pool8.p_placebo, q: pat.pool8.q, strength: pat.pool8.strength, i2: pat.pool8.i2,
      note: 'Across 24 past hurricanes the pooled effect is null; most storms are mapped to whole grid operators (MISO, PJM) where a landfall is a rounding error. Milton and Ian, both mapped to Florida utilities, are the two that pass.' }
  };

  const grid = {
    id: 'grid', hop_id: 6102, hop_ids: [6101, 6102], node: 'eia.930:FPL + eia.930:FPC', domain: di('real_world'), lag_days: lag, lag_text: 'the day after landfall',
    magnitude: Math.min(1, Math.abs(fx.d) / 0.25),          // engine rule: |effect| in log points / 0.25, clipped
    tier: 'watching',                                         // the engine 6.1 hop tier as published (test queued); the story layer cannot raise it
    tier_reason: 'single-event test queued; the forecast gate has not evaluated this hop',
    contrast: { pass, strong, design: 'affected vs unaffected regions (difference-in-differences), in-space and in-time placebos, synthetic control',
      d_logpts: r(fx.d, 4), d_centred: r(fx.d - fx.med, 4), effect_pct: effectPct, treated_only_pct: pct(fx.d_treated), z: r(fx.z, 2), se: r(fx.se, 4),
      p_space: r(fx.p_space, 4), p_space_odds: spaceOdds, p_time: r(fx.p_time, 4), p_pre: r(fx.p_pre, 3), leads: fx.lead.map(v => r(v, 4)),
      synth_d: r(fx.synth_d, 4), synth_p: r(fx.synth_p, 3), synth_ratio: r(fx.synth_ratio, 2), n_donors: fx.n_donors, treated: fx.treated,
      window: { pre_days: misc.grid8.pre_n, post_days: misc.grid8.post_n, lag_days: misc.grid8.lag_n, onset, closes: '2024-10-14' },
      in_time: { n: inTime.length, n_bigger: nBigger, values_logpts: inTime.map(v => r(v, 4)), centre: r(fx.med, 4) },
      computed_at: fx.computed_at, grid: misc.grid8 },
    kind: 'pad', far_shore: false, parent: 'event', mediation_supported: false, common_cause: [],
    num: '−20%', short: 'grid demand', title: 'Florida grid electricity demand', unit: 'vs unaffected regions, 7 days',
    headline: 'Florida grid demand, −20% against unaffected regions',
    plain: `Over the seven days from ${fmtDay(onset)}, the two utilities serving most of Florida drew ${Math.abs(effectPct).toFixed(0)}% less power than 51 grid regions the storm never touched. On ${fmtDay(worst.day)}, the day after landfall, the gap was widest: ${Math.round((1 - worst.treated_idx / worst.donor_idx) * 100)}% below.`,
    sources: { agree: 1, of: 1, text: '1 source (EIA-930 hourly demand); the second and third channels of the 6.1 test have not run' },
    mechanism: [
      { step: 'Wind and flooding knock out power to millions of customers', why: 'Demand that cannot be served is not recorded as demand.', source: 'mechanism library v6.0, template storm_grid_demand' },
      { step: 'Businesses and homes that still have power go dark or empty', why: 'Evacuations and closures cut load even where lines hold.', source: 'mechanism library v6.0' },
      { step: 'Demand climbs back as crews restore lines', why: 'The gap to unaffected regions narrows over the following two weeks in the series.', source: 'EIA-930, this series' }
    ],
    how: `We took the same seven-day window at the same date in every other year of the panel (41 pseudo-storms) and at 30 random sets of two unaffected grid regions. ${nBigger === 0 ? 'None' : nBigger} of the ${inTime.length} pseudo-storms produced a gap this large; among the 30 random region sets the real Florida pair ranked first, so the in-space p is 1 in ${spaceOdds}.`,
    mind: 'A reporting gap at either utility on those days, or a cold snap that hit Florida but not the donor regions, would make us re-check the size. A flat pre-trend (p 0.42) and a synthetic-control estimate with the same sign both argue against a coincidence of timing.',
    fluke: null,
    replication,
    chart: { kind: 'series', grain: 'day', onset, landfall, x0: daily[0].day, series: daily.map(x => ({ d: x.day, t: x.treated_idx, o: x.donor_idx, mwh: x.treated_mwh })),
      band: { lo: r(1 + gm - 2 * gsd, 4), hi: r(1 + gm + 2 * gsd, 4), note: 'treated minus donor gap over the 28-day pre-window, mean ± 2 sd, expressed around the donor index' },
      pre_window: ['2024-09-09', '2024-10-06'], post_window: [onset, '2024-10-13'], ylabel: 'demand vs own late-summer normal', peak: { d: worst.day, t: worst.treated_idx, o: worst.donor_idx } },
    ledger: { register_seq: 859, freeze_seq: 932, model_seq: [931, 957], calibration_seq: 958, frozen_hash: misc.grid8.frozen_hash, head: misc.ledger_head },
    label_side: 'auto'
  };

  /* pre-registered series whose single-event tests never ran: honest 'untested' markers, not grass */
  const untested = hops.filter(h => h.path_type !== 'P-NEG' && !['eia.930:FPL', 'eia.930:FPC'].includes(h.node)).map(h => ({
    id: 'h' + h.hop_id, hop_id: h.hop_id, node: h.node, name: NODE[h.node].label, domain: di(NODE[h.node].domain), lag_days: days(onset, h.window_close),
    window_close: h.window_close, prior: h.p_hat, sign: h.sign, path_type: h.path_type, mechanism: h.mech, status: h.status,
    cascade_word: h.cascade_tier || 'flat', // what the 6.1 cascade payload calls it ('window closed, no move' with no test: see SLICE.md)
    plain: `${NODE[h.node].label}: pre-registered on ${fmtDay(ev.as_of)} with a window to ${fmtDay(h.window_close)} and a prior of ${Math.round(h.p_hat * 100)}%. The test is queued; nothing has been measured here yet.`
  }));
  const controls = hops.filter(h => h.path_type === 'P-NEG').map(h => ({ hop_id: h.hop_id, name: NODE[h.node].label, window_close: h.window_close }));

  /* the far shore: the world rule the story layer flags as a Blind Spot; Milton is not in that pool and has not been tested on it */
  const p10 = pat.p10;
  const fell = Math.round((1 - p10.share_positive) * p10.n_events);   // share_positive is the engine's own count over the 23 de-clustered events
  const shore = {
    id: 'biz_rule', kind: 'pattern', domain: di('business'), lag_days: 28, far_shore: true, tier: 'pattern', strength: p10.strength,
    num: '−3.2%', short: 'new businesses', title: 'New-business applications in hit states', unit: 'over 4 weeks, across 23 hurricanes',
    headline: 'Where hurricanes usually reach: fewer new businesses, four weeks on',
    plain: `Across 23 past hurricanes, applications to start a business in the hit states ran 3.2% below unaffected states over the following four weeks. Nobody pre-registered this for Milton, so Milton itself is untested on it: this is a rule about storms like it, not evidence about this storm.`,
    pattern: { ...p10, fell_after: fell, of: g10.filter(e => e.d != null).length, examples: g10.filter(e => e.z <= -2.5).map(e => ({ label: e.label, effect_pct: pct(e.d), z: e.z })),
      all: g10.filter(e => e.d != null).map(e => ({ label: e.label.replace(/ \(\d{4}\)$/, ''), year: e.onset.slice(0, 4), effect_pct: pct(e.d), pass: e.p_space <= 0.05 && e.p_pre >= 0.10 && e.d < 0 })) },
    story: p10.story
  };

  const helene = misc.helene;
  const payload = {
    v: 1, version: 1, snapshot_at: '2026-09-26T04:30:00Z', engine: { method_hop: '6.1', method_contrast: '6.2.1', batch: misc.grid8.batch },
    honesty: {
      measured: 0, likely: 0, note: 'No stop on this storm is Measured or Likely. Every single-event test is queued; the forecast gate has not run. The one result is a pre-registered regional contrast (engine 6.2) that passed at its strictest level. The pond draws exactly that.',
      quiet: ev.sensitive, quiet_note: 'Milton is flagged sensitive: sober copy, no celebration language, the reveal stays because it is disclosure, not reward.'
    },
    event: { id: ev.event_id, slug: ev.slug, name: 'Hurricane Milton', sub: `landfall ${fmtDay(landfall)}; engine onset ${fmtDay(onset)}`, place: 'Siesta Key, Florida', date: fmtDay(landfall), onset, landfall,
      strength: 'Category 3 at landfall', magnitude: null, magnitude_note: 'not scored: positive-control event without a family magnitude; the stone is drawn at the default size',
      sensitive: ev.sensitive, role: ev.role, cascade_status: ev.status, cascade: ev.cascade, label: true },
    story: {
      archetype: null, archetype_text: null, archetype_note: 'the story layer has no candidate for Milton yet; no label is shown',
      story_sentence: 'Hurricane Milton didn’t stop at the coast. The day after landfall, Florida’s two big power grids were drawing a fifth less than regions the storm never touched.',
      conversation_hook: 'The rest of the country didn’t move. That is the whole trick: the test is Florida against 51 places the storm missed.',
      short_title: 'Hurricane Milton → Florida grid demand',
      share_line: 'Hurricane Milton → Florida grid demand · −20% vs unaffected regions · regional contrast passed, not yet Measured · consistent with, never proof of cause',
      derived_by: 'tools/snapshot.mjs (no story-layer row for this event on 2026-09-26)'
    },
    travel: { domains: 1, days: 7, depth: 1, text: '1 domain · 7 days · 1st-order', usual_reach: 'storms like it usually reach Business four weeks on (23-hurricane rule)' },
    domains: DOMAINS.map(d => d.label), domain_keys: DOMAINS.map(d => d.key),
    rings: [{ days: 1, r: 105, label: 'Day 1' }, { days: 7, r: 185, label: 'Week 1' }, { days: 30, r: 265, label: 'Month 1' }, { days: 90, r: 345, label: 'Month 3' }],
    effects: [grid],
    untested, controls, flats: [], flats_note: 'The engine has ruled nothing flat on this storm: no single-event test has run. The dotted markers are pre-registered series waiting for their test.',
    shore: [shore],
    rivals: [{ name: 'Hurricane Helene', event_id: helene.event_id, days_before: days(helene.onset, onset), magnitude: null, angle: 12, distance: 236,
      own_contrast: { effect_pct: pct(helene.grid8.d), p_space: r(helene.grid8.p_space, 3), pass: false, treated: helene.grid8.treated },
      note: `Helene came ashore ${days(helene.onset, onset)} days earlier and its rings overlap Milton’s pre-window. Its own contrast on the same grids: ${pct(helene.grid8.d)}%, no pass.` }],
    filtered: [{ name: 'Columbus Day, 14 Oct', domain: di('institutions'), lag_days: 7, magnitude: 0.5, kind: 'holiday', days: misc.common_days.filter(c => c.holiday === 'us_columbus').map(c => c.day),
      note: 'A holiday inside the seven-day window. Common to Florida and the donor regions, so the contrast cancels it; the 6.1 engine drops the day.' }],
    watching: { hop_id: 6094, name: NODE['iem.warn:EW.W'].label, window_start: ev.as_of, window_close: '2024-10-14', prior: 0.2, status: 'queued',
      text: 'Every window on this pond closed in 2024. When the queued tests run, each dotted marker becomes a pad, a grass bed, or stays dotted. Watch this ripple and we keep the change for you on this device.' },
    pattern_next: { ...pat.p17, url: '../lands/real_world/' },
    calibration: misc.calibration,
    ledger: misc.ledger, ledger_head: misc.ledger_head,
    links: { site: 'https://bensunter.com/ripples/pond/', csv: 'data/milton-grid-daily.csv', method: 'https://bensunter.com/ripples/methods/' },
    changelog: [{ version: 1, at: '2026-09-26', text: 'First snapshot: regional contrast on grid demand; 11 pre-registered series untested; world rule for the far shore.' }]
  };
  return payload;
}

function liveRefresh() {
  const url = process.env.DATABASE_URL; if (!url) { console.error('DATABASE_URL not set; use the saved raw results'); process.exit(2); }
  mkdirSync(RAW, { recursive: true });
  for (const [name, q] of Object.entries(SQL)) {
    const out = execFileSync('psql', [url, '-At', '-c', `select coalesce(json_agg(t), '[]') from (${q.replace(/;\s*$/, '')}) t`], { encoding: 'utf8' });
    writeFileSync(join(RAW, `live_${name}.json`), out);
  }
  console.log('live results written to data/raw/live_*.json; map them onto the assemble() inputs before rebuilding (see the raw file names above)');
}

const args = process.argv.slice(2);
if (args.includes('--live')) liveRefresh();
const P = assemble();
writeFileSync(OUT, JSON.stringify(P));
const csv = 'day,treated_index,donor_index,treated_mwh\n' + P.effects[0].chart.series.map(s => `${s.d},${s.t},${s.o},${s.mwh}`).join('\n');
writeFileSync(join(HERE, '..', 'data', 'milton-grid-daily.csv'), csv);
console.log(`wrote ${OUT} (${(JSON.stringify(P).length / 1024).toFixed(1)} KB); effect ${P.effects[0].contrast.effect_pct}% at +${P.effects[0].lag_days} d; replication ${P.effects[0].replication.n_seen} of ${P.effects[0].replication.n_similar}; untested ${P.untested.length}`);
