// deterministic capture: the page runs on a controlled clock; each output frame advances it by a fixed step
const { chromium } = require(process.argv[2] + '/node_modules/playwright');
const fs = require('fs'), path = require('path');
const OUT = process.argv[3], only = process.argv[4];
const BASE = 'http://127.0.0.1:8748';
const FILM_CSS = `.ctl,.legend,#feed,.foot,footer,#how,.hint,.chooser,header .bar,.topond,.tip{display:none !important}
svg#pond{max-height:700px !important}#sub .rest{display:none !important}#beatline{display:none !important}`;
const shots = [
  { name: 'intro', url: '/ripples/tools/film/card.html?mode=intro', pre: 0, dur: 2000, speed: 1 },
  { name: 'tk_open', url: '/ripples/demo/?m=tiger-king&nointro=1', pre: 0, dur: 9000, speed: 2, vw: 1280, vh: 720, dsf: 3 },
  { name: 'tk_reveal', url: '/ripples/demo/?m=tiger-king&nointro=1', film: true, pre: 21800, dur: 6800, speed: 1.3 , dsf: 2.5 },
  { name: 'sputnik', url: '/ripples/demo/?c=sputnik-nasa-arpa&nointro=1', film: true, pre: 24500, dur: 15000, speed: 4 , dsf: 2.5 },
  { name: 'bambi', url: '/ripples/demo/?w=bambi-c3&nointro=1', film: true, pre: 0, dur: 6000, speed: 1.0, dsf: 2.5 },
  { name: 'take', url: '/ripples/demo/?m=tiger-king&nointro=1', pre: 0, dur: 33000, speed: 1, vw: 1280, vh: 720, dsf: 3 },
  { name: 'end', url: '/ripples/tools/film/card.html?mode=end', pre: 0, dur: 2600, speed: 1 },
];
const sleep = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  const b = await chromium.launch({ headless: true, args: ['--use-angle=metal', '--ignore-gpu-blocklist', '--enable-gpu'] });
  for (const s of shots) {
    if (only && s.name !== only) continue;
    const dir = path.join(OUT, s.name); fs.rmSync(dir, { recursive: true, force: true }); fs.mkdirSync(dir, { recursive: true });
    const p = await b.newPage({ viewport: { width: s.vw || 1600, height: s.vh || 900 }, deviceScaleFactor: s.dsf || 2 });
    await p.clock.install({ time: new Date('2026-10-05T12:00:00Z') }); await p.clock.pauseAt(new Date('2026-10-05T12:00:01Z'));  // time moves only when a frame asks (left running, every screenshot added real time to the story)
    await p.goto(BASE + s.url);
    if (s.film) await p.addStyleTag({ content: FILM_CSS }); else await p.addStyleTag({ content: '.hint,.tip{display:none !important}' });
    // let data load: advance the clock in small steps until the pond exists (cards have no pond)
    for (let i = 0; i < 200; i++) { await p.clock.runFor(16); const ok = await p.evaluate(() => !!document.querySelector('#pond .scene') || !!document.getElementById('wm')); if (ok) break; await sleep(60); }
    if (s.film) await p.evaluate(() => window.dispatchEvent(new Event('resize')));
    // CSS fades run on the browser's own timeline, not the page clock: freeze it, then step each fade to the page clock every frame
    const cdp = await p.context().newCDPSession(p); await cdp.send('Animation.enable'); await cdp.send('Animation.setPlaybackRate', { playbackRate: 0 });
    for (let t = 0; t < s.pre; t += 100) await p.clock.runFor(100);
    const step = 1000 / 30 * s.speed, n = Math.round(s.dur / step), meta = { frames: [] };
    for (let i = 0; i < n; i++) {
      await p.clock.runFor(step);
      await p.evaluate(step => { const now = performance.now(); for (const a of document.getAnimations()) { if (a.__v0 === undefined) a.__v0 = now - step; a.currentTime = Math.max(0, now - a.__v0); } }, step);
      if (s.zoom) { const u = i / Math.max(1, n - 1), z = s.zoom[0] + (s.zoom[1] - s.zoom[0]) * (u * u * (3 - 2 * u));
        await p.evaluate(z => { const w = document.querySelector('.pondbox'); if (!w) return; w.style.transformOrigin = '50% 45%'; w.style.transform = `scale(${z})`;
          // the date and tally ride over the sky: undo the zoom on them so the edges never crop
          const k = w.querySelector(':scope > .clock'); if (!k) return; const cx = w.offsetWidth * 0.5, cy = w.offsetHeight * 0.45, x0 = k.offsetLeft, y0 = k.offsetTop;
          k.style.transformOrigin = '0 0'; k.style.transform = `translate(${((1 - z) * (x0 - cx) / z).toFixed(2)}px,${((1 - z) * (y0 - cy) / z).toFixed(2)}px) scale(${1 / z})`; }, z); }
      await p.screenshot({ path: path.join(dir, String(i).padStart(4, '0') + '.jpg'), type: 'jpeg', quality: 92 });
      if (!s.url.includes('card.html')) meta.frames.push(await p.evaluate(() => {
        const d = document.getElementById('date'), bt = document.querySelector('#pond .nlab.beat');
        return { date: d ? d.textContent : '', beat: bt ? bt.textContent : '', title: (document.getElementById('h1') || {}).textContent || '',
          texts: [...document.querySelectorAll('#pond text, #h1, #sub, .clock .d, .clock .n, .ctl, #beatline, #feed .card')].map(e => {
            let o = 1, n = e; while (n && n.nodeType === 1) { const cs = getComputedStyle(n); if (cs.display === 'none' || cs.visibility === 'hidden') return null; o *= +cs.opacity; n = n.parentNode; }
            const r = e.getBoundingClientRect(); if (o < 0.05 || r.width < 1) return null; return [e.textContent.slice(0, 32), Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)]; }).filter(Boolean),
          vis: [...document.querySelectorAll('#pond g.node')].filter(g => +(g.getAttribute('opacity') || getComputedStyle(g).opacity) > 0.5).map(g => (g.getAttribute('aria-label') || '').split(',')[0]) };
      }));
    }
    // where each step sits on the frame (CSS px): the camera in post aims at these
    if (!s.url.includes('card.html')) {
      Object.assign(meta, await p.evaluate(() => {
        const R = e => { const r = e.getBoundingClientRect(); return [r.left, r.top, r.width, r.height]; };
        const nodes = {}; document.querySelectorAll('#pond g.node').forEach(g => { nodes[(g.getAttribute('aria-label') || '').split(',')[0]] = R(g); });
        const labels = {}; document.querySelectorAll('#pond .nlab').forEach(g => { labels[g.textContent] = R(g); });
        const pondbox = document.querySelector('.pondbox'), feed = document.getElementById('feed');
        return { nodes, labels, pond: R(document.getElementById('pond')), pondbox: pondbox ? R(pondbox) : null, feed: feed ? R(feed) : null, vw: innerWidth, vh: innerHeight };
      }));
      meta.dsf = s.dsf || 2; fs.writeFileSync(path.join(dir, 'meta.json'), JSON.stringify(meta));
    }
    console.log(s.name, n, 'frames');
    await p.close();
  }
  await b.close();
})();
