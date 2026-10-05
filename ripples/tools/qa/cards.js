// Share cards: one 1200x630 PNG per featured story in ripples/demo/cards, plus a stub page carrying its og tags in ripples/demo/s/<slug>/.
// node cards.js [page] [listJson]     (list: [[kind, slug, title], ...]; default cards_list.json beside this script)
const { REPO, pageUrl, browser, path, fs } = require('./common');
const esc = s => s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
(async () => {
  const b = await browser(), base = pageUrl(process.argv[2]);
  const list = JSON.parse(fs.readFileSync(process.argv[3] || path.join(__dirname, 'cards_list.json'), 'utf8'));
  const p = await b.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
  for (const [kind, slug, title] of list) {
    await p.goto(`${base}?${kind === 'chain' ? 'c' : 'e'}=${slug}&card=1`); await p.waitForTimeout(2600);
    const sub = await p.$eval('#sub', e => { const c = e.cloneNode(true); c.querySelectorAll('.moreq').forEach(x => x.remove()); return c.textContent.replace(/\s+/g, ' ').trim(); });  // the "more" toggle is page chrome, not description
    await p.screenshot({ path: path.join(REPO, 'ripples/demo/cards', slug + '.png') });
    const q = `${kind === 'chain' ? 'c' : 'e'}=${slug}`, url = `https://bensunter.com/ripples/demo/?${q}`;
    fs.mkdirSync(path.join(REPO, 'ripples/demo/s', slug), { recursive: true });
    fs.writeFileSync(path.join(REPO, 'ripples/demo/s', slug, 'index.html'), `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Ripple: ${esc(title)}</title>
<meta name="description" content="${esc(sub)}">
<meta property="og:type" content="website"><meta property="og:site_name" content="Ripple">
<meta property="og:title" content="Ripple: ${esc(title)}"><meta property="og:description" content="${esc(sub)}">
<meta property="og:url" content="https://bensunter.com/ripples/demo/s/${slug}/">
<meta property="og:image" content="https://bensunter.com/ripples/demo/cards/${slug}.png"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="Ripple: ${esc(title)}"><meta name="twitter:image" content="https://bensunter.com/ripples/demo/cards/${slug}.png">
<link rel="canonical" href="${url}"><meta http-equiv="refresh" content="0; url=${url}">
<style>body{font-family:system-ui;background:#06272d;color:#e6f3f2;display:grid;place-items:center;min-height:100vh;margin:0}a{color:#f2ae2e}</style></head>
<body><p>Opening <a href="${url}">${esc(title)}</a>…</p><script>location.replace(${JSON.stringify(url)})</script></body></html>
`);
    console.log(slug, sub.slice(0, 60));
  }
  await b.close();
})();
