// Record the launch clips and stills. Writes raw .webm recordings and 2400x1260 stills to outDir; encode.sh turns a recording into the kit's files.
// node reel.js [page] [outDir]
const { pageUrl, browser, path, fs } = require('./common');
const STILLS = [['tiger-king', '?m=tiger-king&card=1'], ['tiger-king-act', '?e=tiger-king&card=1'], ['sputnik', '?c=sputnik-nasa-arpa&card=1'], ['prohibition', '?c=america-and-alcohol&card=1'], ['mr-bates', '?c=mr-bates-horizon&card=1'], ['the-jungle', '?c=the-jungle-fda&card=1'], ['dust-bowl', '?c=dust-bowl-soil&card=1']];
const CLIPS = [  // name, query, viewport, recording size. A reel plays the story once, rests two seconds, then moves to the next story: cut before that (see encode.sh).
  ['tiger-king-wide', '?m=tiger-king&reel=1', [1280, 720], [1280, 720]],
  ['sputnik-wide', '?c=sputnik-nasa-arpa&reel=1', [1280, 720], [1280, 720]],
  ['tiger-king-vertical', '?m=tiger-king&reel=1', [1080, 1920], [1080, 1920]],  // portrait: the page centers the story and zooms its layout to 720 px
  ['sputnik-vertical', '?c=sputnik-nasa-arpa&reel=1', [1080, 1920], [1080, 1920]],
];
(async () => {
  const b = await browser(), base = pageUrl(process.argv[2]), out = process.argv[3] || 'reel'; fs.mkdirSync(path.join(out, 'vid'), { recursive: true });
  let p = await b.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 2 });
  for (const [name, q] of STILLS) { await p.goto(base + q); await p.waitForTimeout(2800); await p.screenshot({ path: path.join(out, `ripple-${name}-2400x1260.png`) }); }
  await p.close();
  const made = {};
  for (const [name, q, [vw, vh], [rw, rh]] of CLIPS) {
    const ctx = await b.newContext({ viewport: { width: vw, height: vh }, deviceScaleFactor: 1, recordVideo: { dir: path.join(out, 'vid'), size: { width: rw, height: rh } } });
    p = await ctx.newPage(); await p.goto(base + q); await p.waitForTimeout(22000);
    const v = await p.video().path(); await ctx.close();
    const dest = path.join(out, 'vid', name + '.webm'); fs.renameSync(v, dest); made[name] = dest;
  }
  console.log(JSON.stringify(made, null, 1)); await b.close();
})();
