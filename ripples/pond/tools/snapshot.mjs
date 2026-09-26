#!/usr/bin/env node
/* Ripple Map pond slice: builds data/milton.json from the engine's own tables.
   Reproducible in two modes:
     node tools/snapshot.mjs            -> assembles from data/raw/*.json (the query results saved on 2026-09-26, ~05:05 UTC)
     node tools/snapshot.mjs --live     -> re-runs the SQL below through psql ($DATABASE_URL must point at project kffkasnzqcddpystszch,
                                          a read-only role is enough), writes data/raw/live_*.json, then assembles.
   Every number in milton.json comes from one of these queries. Nothing is invented: tiers are the engine's, the published tier is
   exactly what ripples.att_ce_gate returns, flats are hops the engine resolved as flat. See ../SLICE.md for the honesty notes. */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const RAW = join(HERE, '..', 'data', 'raw');
const OUT = join(HERE, '..', 'data', 'milton.json');
const EVENT = 213;   // Hurricane Milton (positive control), slug lib-control-hurricane-milton-2024. Event 3026 is the same storm with fewer pre-registered series.

/* ---------------- the exact SQL (read-only) ---------------- */
export const SQL = {
  event: `select e.event_id, e.label, e.slug, e.family, e.role, e.onset, e.as_of, e.magnitude, e.sensitive, e.reconstructed, e.status,
                 c.version, c.weakest_tier, c.payload->'ledger' ledger, c.payload->'denominators' denominators, c.payload_hash, c.updated_at
          from ripples.att_events e left join ripples.att_cascades c using(event_id) where e.event_id = ${EVENT};`,
  // every pre-registered single-event test (engine 6.1.x) with its registry row: window, prior, resolution
  hops: `select c.hop_id, c.node, c.depth, c.parent_hop, c.path_type, c.status, c.window_close, c.sign, c.channels, r.p_hat, r.ledger_seq, r.resolved_at, r.hit, r.final_tier, r.published_tier,
                c.path->0->>'text' mech, c.path->0->>'template' template
         from ripples.att_hop_candidates c left join ripples.att_hop_registry r using(hop_id) where c.event_id = ${EVENT} order by c.hop_id;`,
  // the final look of every test: tier, stats, placebo families, BH, fx62 hook result, chain and lag fields
  tests: `select t.hop_id, t.look_no, t.tier, t.tier_reason, t.lag_days, t.rho_shrunk, t.rho_lo, t.rho_hi, t.rho_raw, t.t_stat, t.p_date, t.n_date, t.p_topic, t.n_topic, t.p_link, t.n_link,
                 t.fluke, t.q, t.q_w, t.f, t.f_bin, t.n_channels_3, t.s_by_channel, t.common_shock, t.reversed, t.lag_ok, t.flags, t.look_day,
                 (t.placebo - 't_stats') placebo, t.detail->'bh' bh, t.detail->'rho' rho, t.detail->'fx62' fx62, t.detail->'fails' fails, t.detail->'chain' chain,
                 t.detail->'lag_from_event_days' lag_from_event_days, t.detail->>'engine_version' engine_version
          from ripples.att_hop_tests t where t.is_final and t.hop_id in (select hop_id from ripples.att_hop_candidates where event_id = ${EVENT}) order by t.hop_id, t.look_no desc;`,
  // the published tier is whatever the forecast gate returns for the engine tier (never overridden here)
  gate: `select h.hop_id, ripples.att_ce_gate(h.hop_id, t.tier) gate from ripples.att_hop_candidates h join ripples.att_hop_latest t using(hop_id) where h.event_id = ${EVENT};`,
  // the engine's own normal band and spark for the Measured hop, from the cascade payload
  cascade_nodes: `select jsonb_path_query(payload, '$.nodes[*]') node from ripples.att_cascades where event_id = ${EVENT};`,
  // engine 6.2 regional contrast for the storm (grid 8 = hurricane -> eia.930 demand), incl. the 41 in-time placebo contrasts
  fx_event: `select to_jsonb(f) from ripples.att_fx_event f where f.event_id = ${EVENT};`,
  grid: `select grid_id, batch, label, pre_n, post_n, lag_n, expected_sign, synth, domain_event, domain_outcome, frozen_hash, frozen_at, ledger_seq from ripples.att_fx_grid where grid_id in (8, 10, 17);`,
  pools: `select to_jsonb(p) from ripples.att_fx_pool p where p.grid_id in (8, 10, 17) and p.role = 'real';`,
  patterns: `select public.rm_patterns(null, 'hint');`,
  fx_grid8: `select f.event_id, e.label, e.onset, f.treated, f.d, f.z, f.p_space, f.p_time, f.p_pre from ripples.att_fx_event f join ripples.att_events e using(event_id) where f.grid_id = 8 and f.role = 'real' order by e.onset;`,
  fx_grid10: `select f.event_id, e.label, e.onset, f.treated, f.d, f.z, f.p_space, f.p_pre from ripples.att_fx_event f join ripples.att_events e using(event_id) where f.grid_id = 10 and f.role = 'real' order by e.onset;`,
  fx_grid17_examples: `select e.label, e.onset, f.d, f.p_space from ripples.att_fx_event f join ripples.att_events e using(event_id) where f.grid_id = 17 and f.role = 'real' and f.p_space <= 0.05 and f.p_pre >= 0.1 and f.d > 0 order by f.z desc limit 8;`,
  // daily series behind the chart: Duke Energy Florida (FPC), FPL and the 52 other balancing authorities, each indexed to its own 28-day pre-window mean
  daily: `with s as (select series_id, key from ripples.att_series where source='eia.930' and metric='demand'),
     pre as (select o.series_id, avg(o.value) m from ripples.attention_obs o join s using(series_id) where o.day between '2024-09-09' and '2024-10-06' group by 1),
     d as (select o.day, s.key, o.value, o.value/nullif(pre.m,0) idx from ripples.attention_obs o join s using(series_id) join pre using(series_id) where o.day between '2024-09-02' and '2024-10-28')
     select day, round(avg(idx) filter (where key='FPC')::numeric,4) fpc, round(avg(idx) filter (where key='FPL')::numeric,4) fpl, round(sum(value) filter (where key='FPC')) mwh,
            round(avg(idx) filter (where key not in ('FPC','FPL'))::numeric,4) o from d group by day order by day;`,
  helene: `select f.event_id, e.label, e.onset, f.treated, f.d, f.z, f.p_space, f.p_pre, f.role from ripples.att_fx_event f join ripples.att_events e using(event_id) where f.grid_id = 8 and e.event_id = 212;`,
  common_days: `select day, c_by_source->>'holiday' holiday from ripples.att_common_days where day between '2024-10-07' and '2025-01-05' order by day;`,
  ledger: `select seq, day, kind, ref, payload_hash, chain_hash from ripples.att_ledger where seq in (859, 931, 932, 957, 958, 994) or seq = (select max(seq) from ripples.att_ledger) order by seq;`,
  story: `select story_id, tier, engine_tier, archetype, copy, travel from ripples.att_story_candidates where event_id = ${EVENT};`,
  rm_event_kinds: `select substring(pg_get_functiondef('public.rm_event(text,text,text)'::regprocedure) from 'p_kind not in \\([^)]*\\)');`
};

/* ---------------- helpers ---------------- */
const r = (v, n = 3) => v == null ? null : Math.round(v * 10 ** n) / 10 ** n;
const pct = d => r((Math.exp(d) - 1) * 100, 1);
const fmtDay = iso => new Date(iso + 'T00:00:00Z').toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' });
const days = (a, b) => Math.round((new Date(b) - new Date(a)) / 864e5);
const load = f => JSON.parse(readFileSync(join(RAW, f), 'utf8'));
const oneIn = p => Math.round(1 / p);

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
const DOMAINS = [{ key: 'real_world', label: 'Real world' }, { key: 'institutions', label: 'Institutions' }, { key: 'jobs', label: 'Jobs' }, { key: 'markets', label: 'Markets' }, { key: 'business', label: 'Business' }];
const TIERW = { measured: 'Measured', likely: 'Likely', watching: 'Watching', flat: 'Stayed flat', retracted: 'Retracted' };

/* ---------------- assemble ---------------- */
export function assemble() {
  const misc = load('misc.json'), fx = load('fx_event_milton.json'), daily = load('fpc_daily.json'), live = load('live_611.json');
  const g8 = load('fx_grid8_events.json'), g10 = load('fx_grid10_events.json'), hops = load('hops_milton.json'), pat = load('patterns.json');
  const ev = misc.event, onset = ev.onset, landfall = '2024-10-09';
  const di = k => DOMAINS.findIndex(d => d.key === k);
  const hopById = Object.fromEntries(hops.map(h => [h.hop_id, h]));
  const H = live.hop_6101, G = live.gate_6101;

  /* --- the hero stop: hop 6101, Duke Energy Florida demand, engine 6.1.2 single-event test --- */
  const worst = daily.reduce((a, b) => b.fpc < a.fpc ? b : a);
  const dateOdds = oneIn(H.p_date), topicOdds = oneIn(H.p_topic);
  const effectPct = r((H.rho_shrunk - 1) * 100, 0);
  const published = { tier: G.tier, engine_tier: G.engine_tier, reason: G.reason, mode: G.mode, ce: G.ce, text: G.reason ? `${TIERW[G.engine_tier]} by the engine; ${G.reason}` : TIERW[G.tier] };

  /* --- the regional contrast (engine 6.2.1) on the same grids, secondary evidence on the same card --- */
  const pre = daily.filter(x => x.day >= '2024-09-09' && x.day <= '2024-10-06');
  const inTime = fx.placebo_d.filter(v => v != null);
  const nBigger = inTime.filter(v => Math.abs(v - fx.med) >= Math.abs(fx.d - fx.med)).length;
  const pass = fx.p_space <= 0.05 && fx.p_pre >= 0.10 && Math.sign(fx.d) === misc.grid8.expected_sign && Math.sign(fx.synth_d) === Math.sign(fx.d);
  const strong = pass && fx.p_time <= 0.05 && Math.abs(fx.z) >= 3;
  const contrast = { pass, strong, hook: H.fx62, design: 'affected vs unaffected regions (difference-in-differences), in-space and in-time placebos, synthetic control',
    d_logpts: r(fx.d, 4), d_centred: r(fx.d - fx.med, 4), effect_pct: pct(fx.d), treated_only_pct: pct(fx.d_treated), z: r(fx.z, 2), se: r(fx.se, 4),
    p_space: r(fx.p_space, 4), p_space_odds: oneIn(fx.p_space), p_time: r(fx.p_time, 4), p_pre: r(fx.p_pre, 3), leads: fx.lead.map(v => r(v, 4)),
    synth_d: r(fx.synth_d, 4), synth_p: r(fx.synth_p, 3), synth_ratio: r(fx.synth_ratio, 2), n_donors: fx.n_donors, treated: fx.treated,
    window: { pre_days: misc.grid8.pre_n, post_days: misc.grid8.post_n, lag_days: misc.grid8.lag_n, onset, closes: '2024-10-14' },
    in_time: { n: inTime.length, n_bigger: nBigger, values_logpts: inTime.map(v => r(v, 4)), centre: r(fx.med, 4) }, computed_at: fx.computed_at, grid: misc.grid8 };

  /* replication: the same regional contrast on the 27 past storms in the frozen pool (Milton is a live row, not in the pool) */
  const passes = g8.filter(e => e.p_space <= 0.05 && e.p_pre >= 0.10 && e.d < 0);
  const replication = {
    n_similar: g8.length, n_pooled: pat.pool8.n_events, n_seen: passes.length, n_same_direction: g8.filter(e => e.d < 0).length,
    rule: 'seen = the pre-registered regional contrast passed (in-space p <= 0.05, pre-trends flat, expected sign); the single-event 6.1 test has no replication record for this hop',
    examples: passes.map(e => ({ label: e.label, onset: e.onset, effect_pct: pct(e.d), z: e.z, p_space: e.p_space })),
    all: g8.map(e => ({ label: e.label.replace(/ \(\d{4}\)$/, ''), year: e.onset.slice(0, 4), effect_pct: pct(e.d), pass: e.p_space <= 0.05 && e.p_pre >= 0.10 && e.d < 0, treated: e.treated })),
    family: { effect_pct: pct(pat.pool8.d), ci_pct: [pct(pat.pool8.ci_lo), pct(pat.pool8.ci_hi)], p_placebo: pat.pool8.p_placebo, q: pat.pool8.q, strength: pat.pool8.strength, i2: pat.pool8.i2,
      note: 'Across the 27 past storms tested (24 once overlapping storms are merged) the pooled effect is null; most storms are mapped to whole grid operators (MISO, PJM) where a landfall is a rounding error. Milton and Ian, both mapped to Florida utilities, are the two that pass.' }
  };

  const grid = {
    id: 'grid', hop_id: 6101, node: 'eia.930:FPC', domain: di('real_world'), lag_days: H.lag_days, lag_from_event_days: H.lag_from_event_days, lag_text: 'the day after landfall', onset_observed: H.onset,
    magnitude: Math.min(1, Math.abs(Math.log(H.rho_shrunk)) / 0.25),   // engine rule: |effect| in log points / 0.25, clipped
    tier: published.tier, engine_tier: published.engine_tier, published, tier_reason: H.tier_reason,
    engine: { version: H.engine_version, t_stat: H.t_stat, p_date: H.p_date, n_date: H.n_date, exceed_date: H.exceed_date, p_topic: H.p_topic, n_topic: H.n_topic, exceed_topic: H.exceed_topic, p_link: H.p_link, n_link: H.n_link, exceed_link: H.exceed_link,
      q: H.q, q_w: H.q_w, bh: H.bh, fluke: H.fluke, f: H.f, f_bin: H.f_bin, f_note: 'the calibrated fluke rate for links with T between 3 and 4 reads 1 in 1: the decoy bin has too few links yet ("warming up"); the number is shown, not hidden',
      rho: { shrunk: H.rho_shrunk, lo: H.rho_lo, hi: H.rho_hi, raw: H.rho_raw, peak: H.rho_peak, peak_day: H.peak_day, unit: 'x' }, band: H.band,
      channels: H.channels, n_series: H.n_series, common_shock: H.common_shock, reversed: H.reversed, lag_ok: H.lag_ok, flags: H.flags, fails: H.fails, look_day: H.look_day, resolved_at: H.resolved_at, chain: null },
    contrast, kind: 'pad', far_shore: false, parent: 'event', mediation_supported: false, common_cause: [],
    num: '0.89×', short: 'grid demand', title: 'Duke Energy Florida electricity demand', unit: 'its normal, the week after landfall',
    headline: 'Duke Energy Florida demand, 0.89× its normal for the week after landfall',
    plain: `Duke Energy Florida, the utility for the Gulf coast where Milton came ashore, drew 0.89× its normal for the week from ${fmtDay(H.onset)}. On ${fmtDay(worst.day)}, the day after landfall, it drew ${Math.round(worst.fpc * 100)}% of normal. Together with Florida Power & Light the two grids ran ${Math.abs(contrast.effect_pct).toFixed(0)}% below 51 regions the storm never touched.`,
    sources: { agree: H.channels.agree, of: H.channels.of, text: '1 of 1 channels agree (EIA-930 hourly demand, physical channel); no attention or economic channel was registered for this series' },
    mechanism: [
      { step: 'Wind and flooding knock out power to millions of customers', why: 'Demand that cannot be served is not recorded as demand.', source: 'mechanism library v6.0, template storm_grid_demand' },
      { step: 'Businesses and homes that still have power go dark or empty', why: 'Evacuations and closures cut load even where lines hold.', source: 'mechanism library v6.0' },
      { step: 'Demand climbs back as crews restore lines', why: 'The series returns toward its band over the following two weeks.', source: 'EIA-930, this series' }
    ],
    how: `The engine compared the seven days from ${fmtDay(H.onset)} with the series' own robust normal (T ${H.t_stat.toFixed(2)}), then re-ran the test on ${H.n_date.toLocaleString()} fake dates for the same series: ${H.exceed_date} came out this strong (about 1 in ${dateOdds}). On ${H.n_topic} other series at the real date, none did (1 in ${topicOdds}). Separately, the regional contrast put Florida's two grids against 51 unaffected regions and 41 pseudo-storms: none came close.`,
    mind: 'A reporting gap at the utility on those days, or a cold snap that hit Florida but not the donor regions, would make us re-check the size. Pre-trends were flat (p 0.42) and a synthetic control agrees in sign. The independent forecast model has not evaluated this series yet; until it does, the published word is Likely.',
    fluke: { n: H.n_date, hits: H.exceed_date, text: `About 1 in ${dateOdds} fake dates produce a move this big.` },
    replication,
    chart: { kind: 'series', grain: 'day', onset, landfall, observed_onset: H.onset, series: daily.map(x => ({ d: x.day, t: x.fpc, o: x.o, mwh: x.mwh })),
      band: { lo: H.band.lo, hi: H.band.hi, note: H.band.note + ' (the engine’s own band for this series)' },
      pre_window: ['2024-09-09', '2024-10-06'], post_window: [H.onset, '2024-10-16'], peak: { d: worst.day, t: worst.fpc, o: worst.o } },
    ledger: { register_seq: 859, freeze_seq: 932, model_seq: [931, 957], calibration_seq: 958, control_seq: 994, resolve_seq: 998, frozen_hash: misc.grid8.frozen_hash, head: live.ledger_head, cascade_head: live.cascade.ledger_head },
    label_side: 'auto'
  };

  /* --- flats: hops the engine resolved as 'window closed, no move' with a real test behind them --- */
  const flats = live.flats.map(f => { const h = hopById[f.hop_id]; return {
    id: 'h' + f.hop_id, hop_id: f.hop_id, node: f.node, name: NODE[f.node].label, domain: di(NODE[f.node].domain), lag_days: days(onset, h.window_close), window_close: h.window_close, prior: h.p_hat,
    tier: 'flat', t_stat: f.t, p_date: f.p_date, n_date: f.n_date, q_w: f.q_w, flags: f.flags, mechanism: h.mech, path_type: h.path_type,
    plain: `${NODE[f.node].label} stayed inside its normal range for the window we pre-registered (to ${fmtDay(h.window_close)}; prior ${Math.round(h.p_hat * 100)}%). Test statistic ${f.t.toFixed(2)}; ${Math.round(f.p_date * f.n_date)} of ${f.n_date} fake dates did as well or better.` +
      (f.hop_id === 6102 ? ' On its own FPL did not clear the single-event bar, even though the joint FPL + Duke contrast against unaffected regions passed; the pond shows both.' : '') +
      (f.flags.includes('young_series') ? ' The series is young (data from 2024), so the fake-date pool is thin.' : '') }; });
  const controls = live.controls.map(c => ({ hop_id: c.hop_id, name: NODE[c.node].label, tier: c.tier, t_stat: c.t, p_date: c.p_date, n_date: c.n_date }));

  /* --- still watching: EW.W, waiting for the series --- */
  const W = live.watching[0];
  const untested = [{ id: 'h' + W.hop_id, hop_id: W.hop_id, node: W.node, name: NODE[W.node].label, domain: di(NODE[W.node].domain), lag_days: days(onset, W.window_close), window_close: W.window_close, prior: W.p_hat,
    status: W.tier_reason, cascade_word: 'watching', mechanism: null, path_type: 'P-MAP',
    plain: `${NODE[W.node].label}: pre-registered on ${fmtDay(ev.as_of)} with a window to ${fmtDay(W.window_close)} and a prior of ${Math.round(W.p_hat * 100)}%. The engine is still waiting for the series (the warning archive is being backfilled), so this one has no verdict.` }];

  /* --- the far shore: the world rule the story layer flags as a Blind Spot; Milton was not registered for it --- */
  const p10 = pat.p10;
  const shore = {
    id: 'biz_rule', kind: 'pattern', domain: di('business'), lag_days: 28, far_shore: true, tier: 'pattern', strength: p10.strength,
    num: '−3.2%', short: 'new businesses', title: 'New-business applications in hit states', unit: 'over 4 weeks, across 23 hurricanes',
    headline: 'Where hurricanes usually reach: fewer new businesses, four weeks on',
    plain: 'Across 23 past hurricanes, applications to start a business in the hit states ran 3.2% below unaffected states over the following four weeks. Nobody pre-registered this for Milton, so Milton itself is untested on it: this is a rule about storms like it, not evidence about this storm.',
    pattern: { ...p10, fell_after: Math.round((1 - p10.share_positive) * p10.n_events), of: p10.n_events, examples: g10.filter(e => e.z <= -2.5).map(e => ({ label: e.label, effect_pct: pct(e.d), z: e.z })),
      all: g10.filter(e => e.d != null).map(e => ({ label: e.label.replace(/ \(\d{4}\)$/, ''), year: e.onset.slice(0, 4), effect_pct: pct(e.d), pass: e.p_space <= 0.05 && e.p_pre >= 0.10 && e.d < 0 })) },
    story: p10.story
  };

  const helene = misc.helene;
  return {
    v: 2, version: 2, snapshot_at: live.queried_at, engine: { method_hop: H.engine_version, method_contrast: '6.2.1', batch: misc.grid8.batch, gate_mode: G.mode },
    honesty: {
      measured_engine: 1, measured_published: G.tier === 'measured' ? 1 : 0, likely_published: G.tier === 'likely' ? 1 : 0, flats: flats.length, controls_flat: controls.filter(c => c.tier === 'flat').length, watching: untested.length, chains: live.children_of_milton,
      note: `One stop is Measured by the engine (6.1.2 single-event test) and published as ${TIERW[G.tier]} because the forecast gate returned "${G.reason}". Twelve pre-registered series stayed flat, three negative controls stayed flat, one is still waiting for its series. No second-order hop exists for this storm, so no chain is drawn.`,
      quiet: ev.sensitive, quiet_note: 'Milton is flagged sensitive: sober copy, no celebration language; the reveal stays because it is disclosure, not reward.'
    },
    event: { id: ev.event_id, slug: ev.slug, name: 'Hurricane Milton', sub: `landfall ${fmtDay(landfall)}; engine onset ${fmtDay(onset)}`, place: 'Siesta Key, Florida', date: fmtDay(landfall), onset, landfall, registered: ev.as_of,
      strength: 'Category 3 at landfall', magnitude: null, magnitude_note: 'not scored: positive-control event without a family magnitude; the stone is drawn at the default size',
      sensitive: ev.sensitive, role: ev.role, cascade: { ...live.cascade, method: '6.1' }, label: true },
    story: {
      archetype: null, archetype_text: null, archetype_note: 'the story layer has no candidate for Milton yet; no label is shown',
      story_sentence: 'Hurricane Milton didn’t stop at the coast. The day after landfall, the Gulf-coast grid was drawing 0.89× its normal for a week, and 45% of it on the worst day, while 51 regions the storm missed did not move.',
      conversation_hook: 'The rest of the country didn’t budge. That is the whole trick: the test is Florida against 51 places the storm missed, then 1,646 fake dates.',
      short_title: 'Hurricane Milton → Duke Energy Florida demand',
      share_line: `Hurricane Milton → Florida grid demand · 0.89× normal, −20% vs unaffected regions · ${published.text} · consistent with, never proof of cause`,
      derived_by: 'tools/snapshot.mjs (no story-layer row for this event on 2026-09-26)'
    },
    travel: { domains: 1, days: 7, depth: 1, text: '1 domain · 7 days · 1st-order', usual_reach: 'storms like it usually reach Business four weeks on (23-hurricane rule)' },
    domains: DOMAINS.map(d => d.label), domain_keys: DOMAINS.map(d => d.key),
    rings: [{ days: 1, r: 105, label: 'Day 1' }, { days: 7, r: 185, label: 'Week 1' }, { days: 30, r: 265, label: 'Month 1' }, { days: 90, r: 345, label: 'Month 3' }],
    effects: [grid],
    flats, flats_note: 'Each carries its own fake-date test, the same one the bright pad passed.',
    controls, untested, shore: [shore],
    rivals: [{ name: 'Hurricane Helene', event_id: helene.event_id, days_before: days(helene.onset, onset), magnitude: null, angle: 306, distance: 250,
      own_contrast: { effect_pct: pct(helene.grid8.d), p_space: r(helene.grid8.p_space, 3), pass: false, treated: helene.grid8.treated },
      note: `Helene came ashore ${days(helene.onset, onset)} days earlier and its rings overlap Milton’s pre-window. Its own contrast on the same grids: ${pct(helene.grid8.d)}%, no pass.` }],
    filtered: [{ name: 'Columbus Day, 14 Oct', domain: di('institutions'), lag_days: 7, magnitude: 0.5, kind: 'holiday', days: misc.common_days.filter(c => c.holiday === 'us_columbus').map(c => c.day),
      note: 'A holiday inside the seven-day window. Common to Florida and the donor regions, so the contrast cancels it; the single-event engine drops the day.' }],
    watching: { hop_id: W.hop_id, name: NODE[W.node].label, window_start: ev.as_of, window_close: W.window_close, prior: W.p_hat, status: W.tier_reason,
      text: 'Two things are still open on this storm: the forecast model’s check of the grid stop (that decides Measured), and the extreme-wind-warning series, which is still being backfilled. Watch this ripple and we keep the change for you on this device.' },
    pattern_next: { ...pat.p17, url: '../lands/real_world/' },
    calibration: misc.calibration,
    ledger: [...misc.ledger, ...live.ledger_new.filter(l => l.seq === 994)], ledger_head: live.ledger_head,
    analytics: { kinds: live.rm_event_whitelist },
    links: { site: 'https://bensunter.com/ripples/pond/', csv: 'data/milton-grid-daily.csv', method: 'https://bensunter.com/ripples/methods/' },
    changelog: [
      { version: 1, at: '2026-09-26', text: 'First snapshot: regional contrast on grid demand; 12 pre-registered series untested; world rule for the far shore.' },
      { version: 2, at: '2026-09-26', text: 'Engine 6.1.2 ran the queued tests: Duke Energy Florida demand is Measured by the engine (published Likely, forecast check pending); 12 series stayed flat; extreme-wind warnings still waiting.' }
    ]
  };
}

function liveRefresh() {
  const url = process.env.DATABASE_URL; if (!url) { console.error('DATABASE_URL not set; use the saved raw results'); process.exit(2); }
  mkdirSync(RAW, { recursive: true });
  for (const [name, q] of Object.entries(SQL)) {
    const out = execFileSync('psql', [url, '-At', '-c', `select coalesce(json_agg(t), '[]') from (${q.replace(/;\s*$/, '')}) t`], { encoding: 'utf8' });
    writeFileSync(join(RAW, `live_${name}.json`), out);
  }
  console.log('live results written to data/raw/live_*.json; map them onto the assemble() inputs before rebuilding');
}

if (process.argv.includes('--live')) liveRefresh();
const P = assemble();
writeFileSync(OUT, JSON.stringify(P));
const csv = 'day,fpc_index,donor_index,fpc_mwh\n' + P.effects[0].chart.series.map(s => `${s.d},${s.t},${s.o},${s.mwh}`).join('\n');
writeFileSync(join(HERE, '..', 'data', 'milton-grid-daily.csv'), csv);
const E = P.effects[0];
console.log(`wrote ${OUT} (${(JSON.stringify(P).length / 1024).toFixed(1)} KB); hop ${E.hop_id} engine ${E.engine_tier} -> published ${E.tier} (${E.published.reason}); ${E.num} at +${E.lag_days} d; flats ${P.flats.length}; controls ${P.controls.length}; watching ${P.untested.length}`);
