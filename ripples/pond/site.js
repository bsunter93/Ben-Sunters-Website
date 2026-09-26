/* Ripple Map v1: shared runtime. Data loader (live v2/ Storage files, falling back to the local snapshots), the story -> pond adapter,
   tier words, archetype glyphs, nav, analytics (aggregate counts only), the device-local Watch store and "While you were gone",
   and Send / Share. Every page loads this after pond.js. No number is typed here: copy comes from the payloads. */
(function (global) {
  const $ = (s, r = document) => r.querySelector(s);
  const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const ls = { get(k) { try { return localStorage.getItem(k); } catch { return null; } }, set(k, v) { try { localStorage.setItem(k, v); } catch { /* private mode */ } }, json(k, d) { try { return JSON.parse(ls.get(k) || 'null') ?? d; } catch { return d; } } };
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const compact = innerWidth <= 900;

  /* ---------- config (mirrors ../config.js; the publishable key only reaches the anon RPCs) ---------- */
  const SB_URL = 'https://kffkasnzqcddpystszch.supabase.co';
  const SB_KEY = 'sb_publishable_3UtNDc2vPbCIcG1t5K4YEQ_KUyTKucv';
  const STORAGE = SB_URL + '/storage/v1/object/public/ripples/v2/';
  const SITE = 'https://bensunter.com';
  // ROOT: the pond folder, whatever depth this page sits at (r/{slug}/, p/, lands/ ...). Later /ripples/ replaces /ripples/pond/.
  const ROOT = (() => { const m = location.pathname.match(/^(.*\/pond\/)/); return m ? m[1] : location.pathname.replace(/[^/]*$/, ''); })();
  const CANON = SITE + '/ripples/pond/';
  const DOMAINS = [['reading', 'Reading'], ['chatter', 'Chatter'], ['markets', 'Markets'], ['builders', 'Builders'], ['real_world', 'Real world'], ['jobs', 'Jobs'], ['institutions', 'Institutions'], ['stuff', 'Stuff'], ['business', 'Business']];
  const DLABEL = Object.fromEntries(DOMAINS);
  const RINGS = [{ days: 1, r: 105, label: 'Day 1' }, { days: 7, r: 185, label: 'Week 1' }, { days: 30, r: 265, label: 'Month 1' }, { days: 90, r: 345, label: 'Month 3' }];
  const TIER = { measured: 'Measured', likely: 'Likely', watching: 'Watching', flat: 'Stayed flat', retracted: 'Retracted', pattern: 'World rule', 'strong pattern': 'Strong pattern', 'unexpected direction': 'Unexpected direction', hint: 'Hint', 'no pattern': 'No pattern' };
  const fmtDay = iso => iso ? new Date(String(iso).slice(0, 10) + 'T00:00:00Z').toLocaleDateString('en-GB', { day: 'numeric', month: 'short', timeZone: 'UTC' }) : '';
  const fmtDayY = iso => iso ? new Date(String(iso).slice(0, 10) + 'T00:00:00Z').toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' }) : '';
  const today = () => new Date().toISOString().slice(0, 10);
  const daysUntil = iso => Math.ceil((new Date(String(iso).slice(0, 10) + 'T00:00:00Z') - new Date(today() + 'T00:00:00Z')) / 864e5);
  const ord = n => n + (['th', 'st', 'nd', 'rd'][(n % 100 - 20) % 10] || ['th', 'st', 'nd', 'rd'][n % 100] || 'th');

  /* ---------- data: live v2/ file first (short timeout), then the local snapshot ---------- */
  const cache = {};
  async function getJSON(url, ms = 2500) {
    const c = new AbortController(); const t = setTimeout(() => c.abort(), ms);
    try { const r = await fetch(url, { signal: c.signal, cache: 'no-cache', credentials: 'omit' }); if (!r.ok) throw new Error(r.status); return await r.json(); } finally { clearTimeout(t); }
  }
  async function load(name, live, local) {
    if (cache[name]) return cache[name];
    const q = new URLSearchParams(location.search);
    const p = (async () => {
      if (live && !q.has('local') && location.protocol !== 'file:') { try { const d = await getJSON(STORAGE + live); d._src = 'live'; return d; } catch { /* fall through */ } }
      const d = await getJSON(ROOT + local, 8000); d._src = 'snapshot'; return d;
    })();
    cache[name] = p; return p;
  }
  const data = {
    registry: () => load('registry', null, 'data/index.json'),
    stories: async () => { const q = new URLSearchParams(location.search); if (q.get('data') === 'fixture') return load('stories-fx', null, '../contract/fixtures/v2/stories.json').then(d => (d._fixture = true, d)); return load('stories', 'stories.json', 'data/stories.json'); },
    patterns: () => load('patterns', 'patterns.json', 'data/patterns.json'),
    async pond(slug) {
      const reg = await data.registry(); const ev = reg.events.find(e => e.slug === slug || (e.aliases || []).includes(slug));
      if (ev) { try { return await load('pond:' + ev.slug, ev.live, ev.file); } catch { /* snapshot missing */ } }
      // no published pond payload: build one from the story layer (watching floats, dead-end reeds, any measured / likely pads)
      const S = await data.stories(); const items = S.featured.filter(s => s.event && s.event.slug === slug);
      if (!items.length) return null;
      const P = fromStories(items, reg); P._src = 'stories'; return P;
    }
  };

  /* ---------- the story -> pond adapter: a graph node becomes a pad, a float or a reed by its tier; edges chain only when mediation is supported ---------- */
  function fromStories(items, reg) {
    const ev = items[0].event, doms = [], di = k => { let i = doms.indexOf(k); if (i < 0) { doms.push(k); i = doms.length - 1; } return i; };
    const nodes = {}; items.forEach(s => (s.graph.nodes || []).forEach(n => { nodes[n.hop_id] = { ...n, _story: s }; }));
    const edges = {}; items.forEach(s => (s.graph.edges || []).forEach(e => { edges[e.to] = e; }));
    // fix the angular order: the 8 public domains in their canonical order, only those present
    DOMAINS.forEach(([k]) => { if (Object.values(nodes).some(n => n.domain === k)) doms.push(k); });
    const effects = [], flats = [], untested = [];
    Object.values(nodes).forEach(n => {
      const s = n._story, edge = edges[n.hop_id] || { from: 'event', kind: 'fork' };
      const base = { id: 'h' + n.hop_id, hop_id: n.hop_id, node: n.node || null, name: n.label, domain: di(n.domain), domain_key: n.domain, lag_days: n.lag_days ?? 0, window_close: n.window_close, prior: n.p_hat ?? (s.watching && s.watching.p_hat) ?? null, story_id: s.story_id, story: s };
      if (n.tier === 'measured' || n.tier === 'likely') {
        const rho = n.rho ?? 1, mag = Math.min(1, Math.abs(Math.log(rho)) / 0.25);
        effects.push({ ...base, tier: n.tier, engine_tier: n.tier, published: { tier: n.tier, engine_tier: s.engine_tier, reason: s.demoted ? s.gate_reason : null, text: s.demoted && s.gate_reason ? `${TIER[n.tier]}, ${s.gate_reason}` : TIER[n.tier], detail: s.demoted && s.gate_reason ? `${TIER[s.engine_tier]} by the engine; ${s.gate_reason}` : TIER[n.tier] },
          magnitude: mag, kind: 'pad', far_shore: false, parent: edge.kind === 'chain' ? 'h' + edge.from : 'event', mediation_supported: edge.kind === 'chain', common_cause: [],
          num: rho.toFixed(2) + '×', short: n.label, title: n.label, unit: 'its normal', headline: `${n.label}, ${rho.toFixed(2)}× its normal ${n.lag_days != null ? n.lag_days + ' days after ' + ev.label : ''}`.trim(),
          lag_text: n.lag_days != null ? `${n.lag_days} days after` : '', plain: s.hero && s.hero.hop_id === n.hop_id ? s.hero.sentence : `${n.label} ran ${rho.toFixed(2)}× its normal${n.lag_days != null ? `, starting ${n.lag_days} days after ${ev.label}` : ''}. ${s.tier_wording || ''}`.trim(),
          sources: n.channels ? { agree: n.channels.agree, of: n.channels.of, text: `${n.channels.agree} of ${n.channels.of} independent channels agree` } : null,
          fluke: n.p_1_in ? { text: `A random pairing looks this strong about 1 in ${n.p_1_in} times.`, p_1_in: n.p_1_in, f_1_in: n.f_1_in } : null,
          replication: s.replication && s.hero && s.hero.hop_id === n.hop_id ? s.replication : null, mechanism: null, why: s.why, onset_observed: n.onset, depth: n.depth, label_side: 'auto' });
      } else if (n.tier === 'watching') {
        untested.push({ ...base, lag_days: n.lag_days ?? Math.max(1, Math.min(90, daysUntil(n.window_close) > 0 ? Math.max(1, (new Date(n.window_close) - new Date(ev.onset)) / 864e5 / 2) : 7)), status: 'watching', cascade_word: 'watching', watch: s.watching, plain: s.hero && s.hero.hop_id === n.hop_id ? s.hero.sentence : `${n.label}: too early to tell. Window closes ${fmtDayY(n.window_close)}.` });
      } else if (n.tier === 'flat') {
        flats.push({ ...base, lag_days: Math.max(1, Math.min(90, (new Date(n.window_close) - new Date(ev.onset)) / 864e5 || 7)), tier: 'flat', plain: s.hero && s.hero.hop_id === n.hop_id ? s.hero.sentence : `${n.label} stayed inside its normal range for the window we pre-registered.`, flags: [], watch: s.watching });
      }
    });
    const best = items.slice().sort((a, b) => (b.scores?.story || 0) - (a.scores?.story || 0))[0];
    const version = Math.max(...items.map(s => s.version || 0));
    return {
      v: 2, version, snapshot_at: null, source: 'story layer (rm_stories)', engine: null,
      event: { id: ev.event_id, slug: ev.slug, name: ev.label, sub: `onset ${fmtDayY(ev.onset)}`, date: fmtDayY(ev.onset), onset: ev.onset, registered: ev.onset, strength: '', magnitude: best.scores ? best.scores.shock : null, sensitive: !!ev.sensitive, family: ev.family, label: true },
      honesty: { quiet: !!ev.sensitive || !!best.quiet, measured_published: effects.filter(e => e.tier === 'measured').length, likely_published: effects.filter(e => e.tier === 'likely').length, flats: flats.length, watching: untested.length, chains: effects.filter(e => e.mediation_supported).length,
        note: `Built from the story layer: ${effects.length} stop${effects.length === 1 ? '' : 's'} that moved, ${untested.length} still being watched, ${flats.length} that stayed flat. The full evidence card for each stop (series chart, placebo families, ledger) arrives with the event's pond payload.` },
      story: { archetype: best.archetype, archetype_text: null, story_sentence: best.story_sentence, conversation_hook: best.conversation_hook, short_title: best.short_title, share_line: best.share_line, hook: best.headline ? best.headline.replace(/^[^:]+:\s*/, '') : best.story_sentence, story_id: best.story_id, scores: best.scores, next: best.next, share: best.share, url: best.url, kind: best.kind, tier: best.tier, tier_wording: best.tier_wording },
      travel: best.travel ? { domains: best.travel.domains_crossed, days: best.travel.days, depth: best.travel.depth, text: travelText(best.travel) } : null,
      domains: doms.map(k => DLABEL[k] || k), domain_keys: doms, rings: RINGS,
      effects, flats, controls: [], untested, shore: [], rivals: [], filtered: [], stories: items,
      watching: untested.length ? { name: untested[0].name, window_start: ev.onset, window_close: untested[0].window_close, prior: untested[0].prior, text: untested.length === 1 ? 'One series is still being watched on this event.' : `${untested.length} series are still being watched on this event; each resolves on its own date.` } : null,
      analytics: { kinds: KINDS }, links: { site: CANON + 'r/' + ev.slug + '/', csv: null, method: ROOT + 'how/' }, changelog: []
    };
  }
  const travelText = t => t ? `${t.domains_crossed ?? t.domains ?? 0} domain${(t.domains_crossed ?? t.domains) === 1 ? '' : 's'} · ${t.days ?? '?'} days · ${ord(t.depth || 1)}-order` : '';

  /* ---------- tiers and archetypes ---------- */
  const tierGlyph = t => `<svg aria-hidden="true" viewBox="0 0 14 14">${t === 'measured' ? '<circle cx="7" cy="7" r="6" fill="currentColor"/>' : t === 'likely' ? '<circle cx="7" cy="7" r="5.5" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M7 1.5 A5.5 5.5 0 0 1 7 12.5Z" fill="currentColor"/>' : t === 'flat' ? '<g fill="currentColor"><path d="M4 13 Q3 8 5 3 Q5.5 8 5 13Z"/><path d="M7 13 Q6.5 7 7.5 2 Q8.5 7 8 13Z"/><path d="M10 13 Q10 8 11.5 4 Q11 9 10.8 13Z"/></g>' : /pattern|hint|rule|strong/.test(t) ? '<ellipse cx="7" cy="10.5" rx="5.5" ry="2.4" fill="currentColor"/><ellipse cx="7.4" cy="6.6" rx="3.8" ry="1.9" fill="currentColor"/><ellipse cx="6.8" cy="3.4" rx="2.4" ry="1.4" fill="currentColor"/>' : '<circle cx="7" cy="7" r="5.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-dasharray="2.4 2.4"/>'}</svg>`;
  const tierPill = (t, word) => `<span class="tier ${esc(t === 'strong pattern' ? 'strong' : t)}">${tierGlyph(t)}${esc(word || TIER[t] || t)}</span>`;
  const ARCH = {
    Detour: ['M1 10 Q5 2 9 6 T15 3', 'The ripple reached a shore nobody was watching.'], Echo: ['M3 6 a4 4 0 0 1 8 0 M1 6 a6 6 0 0 1 12 0', 'Several shores moved at once.'],
    Delay: ['M1 9 H8 Q11 9 12 4 T15 2', 'Nothing, then a late swell.'], Funnel: ['M1 2 L8 6 L15 2 M8 6 V10', 'Several stops landed on the same shore.'], Bounce: ['M1 8 Q5 1 8 6 T15 9', 'A rise, then a reversal.'],
    Amplifier: ['M1 8 Q4 8 6 3 Q9 9 15 1', 'A small stone, a big wave.'], 'Blind Spot': ['M2 6 Q8 -1 14 6 Q8 13 2 6 Z M6 6 h4', 'It moved where nobody was looking.'], Branch: ['M1 10 L8 6 L15 10 M8 6 V1', 'Three shores from one stone.'],
    'Shared Stop': ['M1 3 Q8 6 15 3 M1 9 Q8 6 15 9', 'Two stones, one stop: a common cause is possible.'], 'Dead end': ['M1 6 H10 M10 2 V10', 'Expected to move; it stayed flat.'], Collapse: ['M1 6 H10 M10 2 V10', 'Expected to move; it stayed flat.'],
    Ghost: ['M2 10 Q8 -2 14 10 M5 7 h6', 'Every expected stop stayed flat: the ripple that died.'], 'Non-Event': ['M1 6 H15', 'A big stone; the pond stayed still.'] };
  const archTag = a => a && ARCH[a] ? `<span class="a-tag" title="${esc(ARCH[a][1])} A story label, not evidence."><svg viewBox="0 0 16 12" aria-hidden="true"><path d="${ARCH[a][0]}" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>${esc(a)}</span>` : `<span class="a-tag none">Ripple</span>`;
  const archText = a => a && ARCH[a] ? ARCH[a][1] : '';

  /* ---------- links: canonical objects ---------- */
  const url = {
    ripple: (slug, q) => ROOT + 'r/?e=' + encodeURIComponent(slug) + (q ? '&' + q : ''),
    stop: (slug, hop, q) => ROOT + 'r/?e=' + encodeURIComponent(slug) + '&stop=' + hop + (q ? '&' + q : ''),
    pattern: id => ROOT + 'p/?id=' + id, land: d => ROOT + 'lands/?d=' + d, wander: () => ROOT + 'wander/', watch: () => ROOT + 'watch/', how: () => ROOT + 'how/',
    canon: { ripple: slug => CANON + 'r/' + slug + '/', stop: (slug, hop) => CANON + 'r/' + slug + '/?stop=' + hop, pattern: id => CANON + 'p/?id=' + id }
  };
  const storyHref = s => s.kind === 'pattern' ? url.pattern(s.pattern.id) : s.kind === 'cascade' && s.hero ? url.stop(s.event.slug, s.hero.hop_id) : s.kind === 'watching' || s.kind === 'non_event' ? url.stop(s.event.slug, s.hero ? s.hero.hop_id : (s.spine || [])[0]) : url.ripple(s.event.slug);

  /* ---------- nav ---------- */
  function nav(current) {
    const items = [['now', 'Now', ROOT], ['wander', 'Wander', ROOT + 'wander/'], ['watch', 'Watch', ROOT + 'watch/'], ['lands', 'Lands', ROOT + 'lands/'], ['how', 'How it works', ROOT + 'how/']];
    const h = `<div class="top-in"><a class="brand" href="${ROOT}"><svg viewBox="0 0 24 24" aria-hidden="true"><ellipse cx="12" cy="12" rx="3" ry="2.4" fill="#C8B48E"/><circle cx="12" cy="12" r="6.5" fill="none" stroke="#A9EAD9" stroke-width="1.2"/><circle cx="12" cy="12" r="10.5" fill="none" stroke="#A9EAD9" stroke-width="1.2" opacity=".45"/></svg>Ripple Map</a>
      <nav class="nav" aria-label="Site">${items.map(([k, l, h]) => `<a href="${h}" class="${k}"${k === current ? ' aria-current="page"' : ''}>${l}</a>`).join('')}</nav></div>`;
    const top = $('header.top'); if (top) top.innerHTML = h;
  }

  /* ---------- analytics: aggregate counts only, through rm_event; kinds are whitelisted server-side ---------- */
  const KINDS = ['share_tap', 'landing', 'send', 'hero_view', 'trace', 'stop_open', 'why_open', 'luck_open', 'seen_before_open', 'one_more', 'watch', 'wander', 'second_ripple'];
  let ALLOWED = new Set(KINDS), SRC = 'pond';
  const REPEAT = new Set(['stop_open', 'one_more', 'share_tap']);
  const depth = new Set();
  function clientId() { let c = ls.get('ko.client'); if (!c) { const a = new Uint8Array(12); crypto.getRandomValues(a); c = btoa(String.fromCharCode(...a)).replace(/[+/=]/g, m => ({ '+': '-', '/': '_', '=': '' })[m]); ls.set('ko.client', c); } return c; }
  function track(kind) {
    if (depth.has(kind) && !REPEAT.has(kind)) return;
    depth.add(kind);
    // discovery depth: a second ripple in this session is its own count
    try { const seen = JSON.parse(sessionStorage.getItem('rm.ripples') || '[]'); if (kind === 'hero_view' && seen.length >= 2 && !depth.has('second_ripple')) { depth.add('second_ripple'); send('second_ripple'); } } catch { /* ignore */ }
    send(kind);
  }
  function send(kind) {
    if (!ALLOWED.has(kind) || location.protocol === 'file:') return;
    try { fetch(`${SB_URL}/rest/v1/rpc/rm_event`, { method: 'POST', credentials: 'omit', keepalive: true, headers: { apikey: SB_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_kind: kind, p_src: SRC, p_client: clientId() }) }).catch(() => {}); } catch { /* never block */ }
  }
  function analytics(src, kinds) { SRC = src; if (kinds) ALLOWED = new Set(kinds); try { const q = new URLSearchParams(location.search); const ext = document.referrer && !/bensunter\.com/.test(document.referrer); if ((q.get('src') || ext) && !sessionStorage.getItem('ko.land')) { sessionStorage.setItem('ko.land', '1'); track('landing'); } } catch { /* ignore */ } }
  function sawRipple(slug) { try { const s = JSON.parse(sessionStorage.getItem('rm.ripples') || '[]'); if (!s.includes(slug)) { s.push(slug); sessionStorage.setItem('rm.ripples', JSON.stringify(s)); } } catch { /* ignore */ } }

  /* ---------- watch (device-local) and while you were gone ---------- */
  const WK = 'rm.watch', VK = 'rm.seen';
  const watchAll = () => ls.json(WK, {});
  const watched = id => !!watchAll()[id];
  function toggleWatch(id, meta) { const w = watchAll(); if (w[id]) delete w[id]; else { w[id] = { ...meta, at: today() }; track('watch'); } ls.set(WK, JSON.stringify(w)); return !!w[id]; }
  function setWatchVersion(id, version) { const w = watchAll(); if (w[id]) { w[id].version = version; w[id].seen_at = today(); ls.set(WK, JSON.stringify(w)); } }
  // the seen ledger: story id -> {version, tier, kind} at the last visit, keyed on payload versions
  const seen = () => ls.json(VK, null);
  function noteSeen(S) {
    const cur = seen() || { at: today(), items: {} };
    const items = {}; (S.featured || []).forEach(s => { items[s.story_id] = { v: s.share && s.share.version != null ? s.share.version : s.version, tier: s.tier, kind: s.kind, t: s.short_title }; });
    ls.set(VK, JSON.stringify({ at: today(), prev_at: cur.at, items, first: cur.first || today() }));
    return cur;
  }
  /* diff the current story list against the last visit: new ripples, changes to watched items, resolved mysteries, new patterns */
  function gone(S, prev) {
    if (!prev || !prev.items) return null;
    const out = [], w = watchAll();
    (S.featured || []).forEach(s => {
      const id = s.story_id, was = prev.items[id], v = s.share && s.share.version != null ? s.share.version : s.version;
      const href = storyHref(s), isW = !!(w[id] || (s.event && w['ripple:' + s.event.slug]) || (s.kind === 'pattern' && w['pattern:' + s.pattern.id]));
      if (!was) { out.push({ kind: s.kind === 'pattern' ? 'pattern' : 'new', text: s.kind === 'pattern' ? `New world rule: ${s.short_title}` : s.kind === 'watching' ? `New mystery: ${s.short_title}` : s.kind === 'non_event' ? `New dead end: ${s.short_title}` : `New ripple: ${s.short_title}`, href, watched: isW, s }); return; }
      if (was.tier !== s.tier) out.push({ kind: s.tier === 'flat' ? 'flat' : 'moved', text: s.tier === 'flat' ? `${s.short_title.replace(/\?$/, '')}: stayed flat. The window closed without a detectable move.` : `${s.short_title.replace(/\?$/, '')}: it moved. ${TIER[was.tier] || was.tier} became ${TIER[s.tier] || s.tier}.`, href, watched: isW, s });
      else if (was.v != null && v != null && v > was.v) out.push({ kind: 'grew', text: `${s.short_title} grew${s.share && s.share.grown_since && s.share.grown_since.stops_added ? `: +${s.share.grown_since.stops_added} stop${s.share.grown_since.stops_added === 1 ? '' : 's'}` : ''} (v${was.v} → v${v}).`, href, watched: isW, s });
    });
    // watched things that fell off the featured list are reported, not lost
    Object.keys(prev.items).forEach(id => { if (!(S.featured || []).some(s => s.story_id === id) && w[id]) out.push({ kind: 'gone', text: `${prev.items[id].t}: no longer featured; it is still on its ripple page.`, href: w[id].url || ROOT, watched: true }); });
    out.sort((a, b) => (b.watched - a.watched));
    return out;
  }

  /* ---------- send / share ---------- */
  let tt; function toast(msg) { let t = $('#toast'); if (!t) { t = document.createElement('div'); t.className = 'toast'; t.id = 'toast'; t.setAttribute('role', 'status'); t.setAttribute('aria-live', 'polite'); document.body.appendChild(t); } t.textContent = msg; t.classList.add('on'); clearTimeout(tt); tt = setTimeout(() => t.classList.remove('on'), 2400); }
  function copy(text) { const ok = () => toast('Copied. Paste it anywhere.'); if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text).then(ok, () => fallbackCopy(text, ok)); fallbackCopy(text, ok); }
  function fallbackCopy(text, ok) { const ta = document.createElement('textarea'); ta.value = text; ta.setAttribute('aria-hidden', 'true'); ta.style.cssText = 'position:fixed;top:-100px;opacity:0'; document.body.append(ta); ta.select(); try { document.execCommand('copy'); ok(); } catch { toast('Select the text to copy it'); } ta.remove(); }
  /* a share object: {title, text, url}; text = story_sentence + hook + share_line + frozen url (first-class copy from the story layer, D-16) */
  function shareText(o) { return [o.sentence, o.hook, o.line, o.url].filter(Boolean).join('\n'); }
  function sendObj(o, kind = 'send') {
    track(kind);
    if (navigator.share) { navigator.share({ title: o.title, text: shareText(o), url: o.url }).catch(err => { if (!err || err.name !== 'AbortError') copy(shareText(o)); }); return; }
    copy(shareText(o));
  }
  const frozen = (u, v) => v != null ? u + (u.includes('?') ? '&' : '?') + 'v=' + v : u;

  /* ---------- mini pond thumbnail for a story (pads by tier, floats for watching, reeds for flat) ---------- */
  function thumb(svg, s, opt = {}) {
    const doms = []; const di = k => { let i = doms.indexOf(k); if (i < 0) { doms.push(k); i = doms.length - 1; } return i; };
    DOMAINS.forEach(([k]) => { if ((s.graph?.nodes || []).some(n => n.domain === k) || (s.hero && s.hero.domain === k)) doms.push(k); });
    while (doms.length < 3) doms.push('_' + doms.length);
    const P = { event: { name: s.event ? s.event.label : '', magnitude: s.scores ? s.scores.shock : (s.pattern && s.pattern.pond ? s.pattern.pond.stone : .5), label: false }, domains: doms.map(k => DLABEL[k] || ''), rings: RINGS, effects: [], flats: [], untested: [] };
    if (s.kind === 'pattern') {
      P.effects.push({ id: 'p', domain: 0, lag_days: s.pattern.window.grain === 'week' ? s.pattern.window.post * 7 : s.pattern.window.post, magnitude: Math.min(1, Math.abs(s.pattern.effect) / 25), tier: 'likely', kind: 'pad', far_shore: true, num: '', short: '', headline: '', plain: '' });
    } else (s.graph?.nodes || []).forEach(n => {
      const b = { id: 'n' + n.hop_id, name: n.label, domain: di(n.domain), lag_days: n.lag_days ?? 7 };
      if (n.tier === 'measured' || n.tier === 'likely') P.effects.push({ ...b, tier: n.tier, kind: 'pad', magnitude: Math.min(1, Math.abs(Math.log(n.rho || 1)) / 0.25), num: '', short: '', headline: '', plain: '' });
      else if (n.tier === 'watching') P.untested.push({ ...b, lag_days: 7, window_close: n.window_close });
      else if (n.tier === 'flat') P.flats.push(b);
    });
    global.Pond.render(svg, P, { thumb: true, reduceMotion: true, viewBox: opt.viewBox || [-470, -470, 940, 940] });
    svg.setAttribute('aria-hidden', 'true');
  }

  /* ---------- watching window bar ---------- */
  function winBar(start, close, labelA, labelB) {
    const a = new Date(start), b = new Date(close), now = new Date(), total = Math.max(1, (b - a) / 864e5), done = Math.min(1, Math.max(0, (now - a) / 864e5 / total));
    return `<div class="winbar" aria-hidden="true"><span class="fill" style="width:${Math.round(done * 100)}%"></span><i style="left:0"></i>${done > 0 && done < 1 ? `<i class="now" style="left:${Math.round(done * 100)}%"></i>` : ''}<i class="q" style="left:100%"></i></div><div style="display:flex;justify-content:space-between;font-size:11.5px;color:var(--text-3)"><span>${esc(labelA || fmtDayY(start))}</span><span>${esc(labelB || 'window closes ' + fmtDayY(close))}</span></div>`;
  }
  function countdown(close) { const d = daysUntil(close); return d > 1 ? `${d} days` : d === 1 ? '1 day' : d === 0 ? 'today' : `closed ${-d} day${d === -1 ? '' : 's'} ago`; }

  global.RM = { $, esc, ls, reduce, compact, ROOT, CANON, SITE, STORAGE, DOMAINS, DLABEL, RINGS, TIER, KINDS, fmtDay, fmtDayY, today, daysUntil, ord, data, fromStories, travelText, tierGlyph, tierPill, archTag, archText, ARCH, url, storyHref, nav, track, analytics, sawRipple, watchAll, watched, toggleWatch, setWatchVersion, seen, noteSeen, gone, toast, copy, shareText, sendObj, frozen, thumb, winBar, countdown };
})(window);
