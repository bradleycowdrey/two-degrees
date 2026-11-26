// Two Degrees' Mac App Store pictures, made exactly as every Cowdrey app's: the family template
// (design/app-store/store-frame.mjs, a word-for-word copy of the master in bradleycowdrey/cowdrey-one) draws the
// desktop (desktop(): wallpaper, menu bar, the app's real windows and widgets) and shows it on its MacBook
// (compose(..., { device: 'macbook' })), in Two Degrees' sky blue (THEMES.twodegrees), under the family's Mac copy.
// The iPhone and iPad sets are framed by scripts/app-store-screens.mjs with the same template.
//
//   python3 scripts/make-store-screenshots.py <raw> --mac <rawmac> --screens <dir> --only mac
//       the app's windows and widgets at 2x (mac-N-*.png) and the menu bar's reading (mac.json)
//   node scripts/store-frames.mjs --screens <dir> [--out appstore/screenshots]   mac-1..5.png (2880 x 1800 RGB)
//
// Everything on the desktop is in points (1512 x 982, drawn at 2x); the captures are 2x, so each is shown at half
// its pixel size: the app's real size on a 14" MacBook Pro (the menu bar panel, 492 pt wide, is enlarged 1.5x so
// it reads). The clock is the template's one family clock (MAC_CLOCK); the menu bar's reading comes from mac.json.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { THEMES, MACBOOK, compose, desktop, desktopHtml } from '../design/app-store/store-frame.mjs';

const require = createRequire(import.meta.url);
let playwright;
for (const p of ['playwright', '/opt/node22/lib/node_modules/playwright']) {
  try { playwright = require(p); break; } catch { /* next */ }
}
if (!playwright) playwright = require(path.join(require('node:child_process').execSync('npm root -g').toString().trim(), 'playwright'));

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..');
const args = process.argv.slice(2);
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 && i + 1 < args.length ? args[i + 1] : def; };
const SCREENS = opt('--screens');
const OUT = path.resolve(opt('--out', path.join(ROOT, 'appstore', 'screenshots')));
if (!SCREENS) { console.error('Usage: node scripts/store-frames.mjs --screens <dir> [--out <dir>]'); process.exit(2); }

// One idea a picture, in the same order as the iPhone and iPad sets.
const MAC = [
  { head: 'Every temperature in °F and °C', sub: 'Both units, side by side.' },
  { head: 'Ten days, both units', sub: 'Every high and low, in °F and °C.' },
  { head: 'Every detail in both units', sub: 'Visibility in miles and km, rain in inches and mm.' },
  { head: 'Widgets on your desktop', sub: 'Small, medium and large, each in both units.' },
  { head: 'In your menu bar and Dock', sub: 'Both units, always a glance away.' },
];

const b64 = (f) => fs.readFileSync(path.join(ROOT, 'design', 'app-store', f)).toString('base64');
const FONTS = { fraunces: b64('fraunces.woff2'), instrument: b64('instrument-sans.woff2') };
const THEME = THEMES.twodegrees;
const piece = (name) => fs.readFileSync(path.join(SCREENS, `${name}.png`));
const size = (buf) => [buf.readUInt32BE(16) / 2, buf.readUInt32BE(20) / 2]; // 2x pixels -> points
const meta = JSON.parse(fs.readFileSync(path.join(SCREENS, 'mac.json'), 'utf8'));
const [DW, DH] = MACBOOK.desktop, BAR = MACBOOK.menuBar;
const base = { theme: THEME, app: 'Two Degrees', menuExtra: { text: meta.reading, icon: 'sun' }, fonts: FONTS };
const WIDGET_R = 28; // the widget renders' own continuous corners, in points

// One app window, as the app draws it (its own title bar, so macOS's traffic lights over it), centred.
const windowScreen = (name) => { const png = piece(name), [w, h] = size(png); return { windows: [{ png, w, h, chrome: 'none', lights: true }] }; };

// mac-4: the widgets in two balanced columns: Tokyo's large over the two small ones (Tokyo, Mumbai); Tokyo's medium
// over Mumbai's large.
function widgetScreen() {
  const g = 24, [L, M, S, S2, L2] = ['mac-4-large', 'mac-4-medium', 'mac-4-small', 'mac-4-small2', 'mac-4-large2'].map(piece);
  const [lw, lh] = size(L), [mw, mh] = size(M), [sw, sh] = size(S), [s2w] = size(S2), [l2w, l2h] = size(L2);
  const tw = lw + g + mw, th = Math.max(lh + g + sh, mh + g + l2h);
  const x0 = (DW - tw) / 2, y0 = BAR + (DH - BAR - th) / 2, x1 = x0 + lw + g;
  const w = (png, x, y, ww, hh) => ({ png, x, y, w: ww, h: hh, radius: WIDGET_R });
  return { extras: [w(L, x0, y0, lw, lh), w(S, x0, y0 + lh + g, sw, sh), w(S2, x0 + lw - s2w, y0 + lh + g, s2w, sh),
    w(M, x1, y0, mw, mh), w(L2, x1, y0 + mh + g, l2w, l2h)] };
}

// A page laid out with desktopHtml, to read where the template put the menu-bar extra and the Dock tile, and to
// take magnified views of them (the same HTML drawn at a higher scale: sharp, not an enlarged screenshot).
async function measure(browser, opts) {
  const ctx = await browser.newContext({ viewport: { width: DW, height: DH }, deviceScaleFactor: 1 });
  const p = await ctx.newPage();
  await p.setContent(desktopHtml(opts), { waitUntil: 'load' });
  await p.evaluate(() => document.fonts.ready);
  const r = await p.evaluate(() => {
    const box = (el) => { const b = el.getBoundingClientRect(); return { x: b.x, y: b.y, w: b.width, h: b.height }; };
    const dock = document.querySelector('.dock img');
    return { extra: box(document.querySelector('.right .st')), dock: dock ? box(dock) : null };
  });
  await ctx.close();
  return r;
}
async function magnify(browser, opts, cx, cy, d, k, top = 0) { // top: points of the circle left to the bezel's black
  const ctx = await browser.newContext({ viewport: { width: DW, height: DH }, deviceScaleFactor: k * 2 });
  const p = await ctx.newPage();
  await p.setContent(desktopHtml(opts), { waitUntil: 'load' });
  await p.evaluate(() => document.fonts.ready);
  await p.waitForTimeout(100);
  const r = d / k / 2;
  const y = Math.max(0, cy - r + top / k);
  const png = await p.screenshot({ type: 'png', clip: { x: cx - r, y, width: 2 * r, height: 2 * r - top / k } });
  await ctx.close();
  return png;
}
// A round magnifier: the view in a circle with a white rim (a transparent PNG at 2x, d points across).
async function loupe(browser, view, d, top = 0, rim = 4) {
  const ctx = await browser.newContext({ viewport: { width: d, height: d }, deviceScaleFactor: 2 });
  const p = await ctx.newPage();
  await p.setContent(`<html><body style="margin:0;background:transparent"><div style="width:${d}px;height:${d}px;border-radius:50%;overflow:hidden;
    box-sizing:border-box;border:${rim}px solid #fff;background:#08080A"><img src="data:image/png;base64,${view.toString('base64')}"
    style="display:block;margin-top:${Math.max(0, top - rim)}px;width:${d - 2 * rim}px;height:${d - 2 * rim - Math.max(0, top - rim)}px"></div></body></html>`);
  const png = await p.screenshot({ type: 'png', omitBackground: true });
  await ctx.close();
  return png;
}
// The leader lines from each magnifier to its item, on a transparent layer the size of the desktop.
async function leaders(browser, lines) {
  const ctx = await browser.newContext({ viewport: { width: DW, height: DH }, deviceScaleFactor: 2 });
  const p = await ctx.newPage();
  const svg = lines.map(([a, b]) => `<line x1="${a[0]}" y1="${a[1]}" x2="${b[0]}" y2="${b[1]}"/><circle cx="${a[0]}" cy="${a[1]}" r="4"/><circle cx="${b[0]}" cy="${b[1]}" r="4"/>`).join('');
  await p.setContent(`<html><body style="margin:0;background:transparent"><svg width="${DW}" height="${DH}" style="display:block;filter:drop-shadow(0 1px 2px rgba(10,20,60,.35))">
    <g stroke="#fff" stroke-width="2.5" stroke-linecap="round" fill="#fff">${svg}</g></svg></body></html>`);
  const png = await p.screenshot({ type: 'png', omitBackground: true });
  await ctx.close();
  return png;
}
const toward = (c, t, r) => { const dx = t[0] - c[0], dy = t[1] - c[1], n = Math.hypot(dx, dy) || 1; return [c[0] + dx / n * r, c[1] + dy / n * r]; };

// mac-5: the menu-bar extra with its panel open under it, and the Dock with the app's live tile; two round
// magnifiers show each at 2.4x, drawn from the template's own menu bar and Dock, with a leader to each.
async function menuBarScreen(browser) {
  // The panel is 492 pt wide, too small to read at its real size, so it is shown at 1.5x (the template allows a
  // window under 600 pt to be enlarged up to 1.5x); pw, ph are its enlarged box.
  const panel = piece('mac-5-panel'), [w0, h0] = size(panel), K = 1.5, [pw, ph] = [w0 * K, h0 * K], dock = { icon: piece('mac-5-dock') };
  const plain = { ...base, dock };
  const at = await measure(browser, plain);
  const ex = at.extra.x + at.extra.w / 2;
  // The panel hangs under the menu bar just left of the extra, so the extra's leader runs clear of it.
  const px = Math.round(ex - 24 - pw), py = BAR + 8;
  const d = 220, k = 2.2;
  const c1 = [DW - 140, 300], c2 = [270, 660]; // c2 clear of the enlarged panel's left edge
  const tile = [at.dock.x + at.dock.w / 2, at.dock.y + at.dock.h / 2];
  const t1 = 80; // the menu bar's magnifier shows the bezel's black above the bar, as the screen's edge is
  const v1 = await magnify(browser, plain, ex, d / k / 2 - t1 / k, d, k, t1);
  const v2 = await magnify(browser, plain, tile[0], tile[1] - 8, d, k);
  const L1 = await loupe(browser, v1, d, t1), L2 = await loupe(browser, v2, d);
  const lines = await leaders(browser, [[toward(c1, [ex, BAR], d / 2), [ex, BAR - 2]], [toward(c2, [tile[0], at.dock.y], d / 2), [tile[0] - 6, at.dock.y + 4]]]);
  return {
    dock,
    windows: [{ png: panel, x: px, y: py, w: w0, h: h0, chrome: 'none', scale: K }],
    extras: [{ png: lines, x: 0, y: 0, w: DW, h: DH, radius: 0 },
      { png: L1, x: c1[0] - d / 2, y: c1[1] - d / 2, w: d, h: d, radius: d / 2 },
      { png: L2, x: c2[0] - d / 2, y: c2[1] - d / 2, w: d, h: d, radius: d / 2 }],
  };
}

const browser = await playwright.chromium.launch();
try {
  fs.mkdirSync(OUT, { recursive: true });
  const scenes = [() => windowScreen('mac-1-window'), () => windowScreen('mac-2-window'), () => windowScreen('mac-3-window'),
    () => widgetScreen(), () => menuBarScreen(browser)];
  for (const [i, copy] of MAC.entries()) {
    const file = `mac-${i + 1}.png`;
    const screen = await desktop(browser, { ...base, ...(await scenes[i]()) });
    const out = await compose(browser, 'mac', { ...copy, file, device: 'macbook', png: screen }, THEME, FONTS);
    fs.writeFileSync(path.join(OUT, file), out);
    console.log(path.join(OUT, file));
  }
} finally {
  await browser.close();
}
