// The App Store screenshots for iPhone 6.9" (1320 x 2868) and iPad 13" (2064 x 2752), on the Cowdrey family
// standard: the real app's screens as the Simulator captured them (dark, at the device's own size), framed with
// the family template design/app-store/store-frame.mjs (a word-for-word copy of the master in
// bradleycowdrey/cowdrey-one; see design/app-store/README.md there) in Two Degrees' sky blue, with a Fraunces
// headline and an Instrument Sans sub-line.
//
// Run: npm install --no-save playwright@1.56.1 && npx playwright install chromium &&
//      node scripts/app-store-screens.mjs --raw=DIR [--out=DIR] [--only=iphone,ipad]
//   DIR holds iphone-1..5.png and ipad-1..5.png as .github/workflows/appstore-screenshots.yml makes them (it
//   runs this script itself and publishes both to the appstore-screenshots branch): four Simulator captures of
//   one session per device, and the Home Screen with the widgets (scripts/appstore-widgets.py).
//   -> OUT (default appstore/screenshots)/{iphone,ipad}-1..5.png, opaque RGB as App Store Connect wants them.
//
// The Mac set (mac-1..5.png) is not made here: the Mac app is a menu bar panel about 492 x 620 pt, and the
// template's Mac window is an app of 1180 x 700 pt (see appstore/listing.md for how the Mac set is made).
import fs from 'node:fs'; import path from 'node:path'; import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module'; import { fileURLToPath } from 'node:url';
import { compose, THEMES } from '../design/app-store/store-frame.mjs';

const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
let pw;
for (const p of ['playwright', path.join(root, 'node_modules/playwright'), '/opt/node22/lib/node_modules/playwright']) {
  try { pw = require(p); break; } catch { /* next */ }
}
if (!pw) pw = require(path.join(execFileSync('npm', ['root', '-g']).toString().trim(), 'playwright'));

const ARG = Object.fromEntries(process.argv.slice(2).map((a) => { const [k, ...v] = a.replace(/^--/, '').split('='); return [k, v.join('=')]; }));
const RAW = ARG.raw;
if (!RAW) { console.error('usage: node scripts/app-store-screens.mjs --raw=DIR [--out=DIR] [--only=iphone,ipad]'); process.exit(2); }
const OUT = path.resolve(ARG.out || path.join(root, 'appstore/screenshots'));
const ONLY = (ARG.only || 'iphone,ipad').split(',');

// The stories, in order, the same on iPhone and iPad: a Fraunces headline of two lines (\n is the break) and one
// sub-line. Captions avoid "color/colour": the app's own en strings use UK spelling.
const STORIES = [
  { head: 'Every temperature\nin °F and °C', sub: 'Both units, always. No switching.' },
  { head: 'Ten days,\nboth units', sub: 'Every high and low, in °F and °C.' },
  { head: 'Every detail\nin both units', sub: 'Feels like, dew point, visibility and more.' },
  { head: 'All your cities,\nboth units', sub: 'Up to 20 places in one list.' },
  { head: 'Both units on\nyour Home Screen', sub: 'Small, medium and large widgets.' },
];
const SIZE = { iphone: [1320, 2868], ipad: [2064, 2752] };

const b64 = (f) => fs.readFileSync(path.join(root, 'design/app-store', f)).toString('base64');
const FONTS = { fraunces: b64('fraunces.woff2'), instrument: b64('instrument-sans.woff2') };

const browser = await pw.chromium.launch();
try {
  fs.mkdirSync(OUT, { recursive: true });
  for (const kind of ONLY) {
    if (!SIZE[kind]) throw new Error(`unknown set ${kind} (iphone or ipad)`);
    const lines = Math.max(...STORIES.map((s) => s.head.split('\n').length));
    for (const [k, story] of STORIES.entries()) {
      const file = `${kind}-${k + 1}.png`;
      const png = fs.readFileSync(path.join(RAW, file));
      // The screen must be the real capture at the device's own size: never stretched to fit.
      const [w, h] = [png.readUInt32BE(16), png.readUInt32BE(20)];
      if (w !== SIZE[kind][0] || h !== SIZE[kind][1]) throw new Error(`${file} is ${w} x ${h}, not ${SIZE[kind].join(' x ')}`);
      const out = await compose(browser, kind, { ...story, png, title: 'Two Degrees', lines, file }, THEMES.twodegrees, FONTS);
      fs.writeFileSync(path.join(OUT, file), out);
      console.log(`wrote ${path.relative(process.cwd(), path.join(OUT, file))}`);
    }
  }
} finally {
  await browser.close();
}
