// Two Degrees' App Store pictures in the Cowdrey family's template (scripts/store-frame.mjs, the one Cowdrey.MD
// and Cowdrey.PDF share): Cowdrey One's Fraunces headline, an Instrument Sans sub-line, the same sizes and
// places on every app's pictures, and Two Degrees' blue ground.
//
//   python3 scripts/make-store-screenshots.py --screens <dir>     the finished screens and MacBooks
//   node scripts/store-frames.mjs --screens <dir> [--out appstore/screenshots]
//
// Writes iphone-1..5.png (1320 x 2868), ipad-1..5.png (2064 x 2752) and mac-1..5.png (2880 x 1800), opaque RGB.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { THEMES, compose } from './store-frame.mjs';

const require = createRequire(import.meta.url);
let playwright;
try { playwright = require('playwright'); } catch {
  playwright = require(path.join(require('node:child_process').execSync('npm root -g').toString().trim(), 'playwright'));
}

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..');
const args = process.argv.slice(2);
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 && i + 1 < args.length ? args[i + 1] : def; };
const SCREENS = opt('--screens');
const OUT = path.resolve(opt('--out', path.join(ROOT, 'appstore', 'screenshots')));
if (!SCREENS) { console.error('Usage: node scripts/store-frames.mjs --screens <dir> [--out <dir>]'); process.exit(2); }

// One idea a picture, in the same order on every device. iPhone and iPad share the words.
const IOS = [
  { head: 'Every temperature\nin °F and °C', sub: 'Both units, always. No switching.' },
  { head: 'Ten days,\nboth units', sub: 'Every high and low, in °F and °C.' },
  { head: 'Every detail\nin both units', sub: 'Feels like, dew point, visibility and more.' },
  { head: 'All your cities,\nboth units', sub: 'Up to 20 places in one list.' },
  { head: 'Both units on\nyour Home Screen', sub: 'Small, medium and large widgets.' },
];
const MAC = [
  { head: 'Every temperature in °F and °C', sub: 'Both units, side by side.' },
  { head: 'Ten days, both units', sub: 'Every high and low, in °F and °C.' },
  { head: 'Every detail in both units', sub: 'Visibility in miles and km, rain in inches and mm.' },
  { head: 'Widgets on your desktop', sub: 'Small, medium and large, each in both units.' },
  { head: 'In your menu bar and Dock', sub: 'Both units, always a glance away.' },
];

const b64 = (f) => fs.readFileSync(path.join(HERE, 'store-fonts', f)).toString('base64');
const FONTS = { fraunces: b64('fraunces.woff2'), instrument: b64('instrument-sans.woff2') };
const pngSize = (buf) => [buf.readUInt32BE(16), buf.readUInt32BE(20)];

const browser = await playwright.chromium.launch();
fs.mkdirSync(OUT, { recursive: true });
for (const [kind, copy] of [['iphone', IOS], ['ipad', IOS], ['mac', MAC]]) {
  for (let k = 1; k <= copy.length; k++) {
    const src = path.join(SCREENS, `${kind}-${k}.png`);
    if (!fs.existsSync(src)) { console.log(`skip ${kind}-${k}: no ${src}`); continue; }
    const png = fs.readFileSync(src);
    const story = { ...copy[k - 1], png, file: `${kind}-${k}.png`, title: 'Two Degrees' };
    if (kind === 'mac') story.bare = pngSize(png);
    const out = await compose(browser, kind, story, THEMES.td, FONTS);
    fs.writeFileSync(path.join(OUT, `${kind}-${k}.png`), out);
    console.log(path.join(OUT, `${kind}-${k}.png`));
  }
}
await browser.close();
