// Shared bits for the QA scripts: the browser, the repo root, the page to test.
const path = require('path'), fs = require('fs');
const { chromium } = require('playwright');
const REPO = path.resolve(__dirname, '..', '..', '..');
// The page under test: a built standalone (python3 ripples/tools/build_portable.py -> ripples/dist/ripple-standalone.html),
// or any URL (the live site, a local server). The standalone needs no server and carries its own data.
function pageUrl(arg) {
  const p = arg || path.join(REPO, 'ripples', 'dist', 'ripple-standalone.html');
  if (/^https?:/.test(p)) return p;
  if (!fs.existsSync(p)) throw new Error(`No page at ${p}. Build one: python3 ripples/tools/build_portable.py`);
  return 'file://' + path.resolve(p);
}
// CHROMIUM=/path/to/chromium overrides Playwright's own browser (the cloud container used /opt/pw-browsers/chromium).
async function browser() { return chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {}); }
// Drag the scrubber to the end so every ripple has landed, then let the pond settle.
async function toEnd(pg, ms = 2500) {
  await pg.evaluate(() => { const s = document.querySelector('#scrub'); if (s) { s.value = s.max; s.dispatchEvent(new Event('input')); s.dispatchEvent(new Event('change')); } });
  await pg.waitForTimeout(ms);
}
module.exports = { REPO, pageUrl, browser, toEnd, path, fs };
