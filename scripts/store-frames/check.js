// Checks a folder of framed App Store screenshots against the Cowdrey family standard before they are uploaded:
// every picture appstore/metadata.json lists exists, is an opaque RGB PNG at its device's exact size, and was made
// by store-frames.js (it is in that folder's measure.json) with the standard's type sizes and positions. It also
// measures the eyebrow's contrast on the sky: the eyebrow is white at 78% (39 px SemiBold on iPhone and Mac, 52 px on
// iPad, which is large text), and WCAG asks 3:1 of large text. The sky and the eyebrow's colour are fixed by the
// standard, so a low contrast is reported as a warning for the owner to decide on, and does not stop an upload.
//
// Usage: node scripts/store-frames/check.js [appstore/screenshots] [appstore/metadata.json]
// No dependencies (Node 20+). Exits 1 if anything but the contrast is off, listing each failure.
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const ROOT = path.resolve(__dirname, '..', '..');
const DIR = path.resolve(process.argv[2] || path.join(ROOT, 'appstore', 'screenshots'));
const META = path.resolve(process.argv[3] || path.join(ROOT, 'appstore', 'metadata.json'));

// STANDARD.md: canvas, type sizes (px) and measured positions.
const STD = {
  iphone: { size: [1320, 2868], eyebrow: 39, headline: 108, subhead: 51, baseline: 184, headlineTop: 213, subheadBottom: 531, deviceTop: 640, lines: 2, side: 70 },
  ipad: { size: [2064, 2752], eyebrow: 52, headline: 144, subhead: 68, baseline: 204, headlineTop: 244, subheadBottom: 513, deviceTop: 600, lines: 1, side: 140 },
  mac: { size: [2880, 1800], eyebrow: 39, headline: 108, subhead: 51, baseline: 144, headlineTop: 173, subheadBottom: 374, deviceTop: 470, lines: 1, side: 200 },
};
const EYEBROW_ALPHA = 0.78;
const MIN_CONTRAST = 3;

function readPng(file) {
  const buf = fs.readFileSync(file);
  let o = 8, ihdr; const idat = [];
  while (o < buf.length) {
    const n = buf.readUInt32BE(o), t = buf.toString('latin1', o + 4, o + 8);
    if (t === 'IHDR') ihdr = buf.subarray(o + 8, o + 8 + n);
    if (t === 'IDAT') idat.push(buf.subarray(o + 8, o + 8 + n));
    o += 12 + n;
  }
  const w = ihdr.readUInt32BE(0), h = ihdr.readUInt32BE(4), depth = ihdr[8], type = ihdr[9];
  return { w, h, depth, type, idat, interlace: ihdr[12] };
}
// The RGB rows of an 8-bit RGB PNG (colour type 2), unfiltered.
function rows(png) {
  const bpp = 3, stride = png.w * bpp, raw = zlib.inflateSync(Buffer.concat(png.idat));
  const out = []; let prev = Buffer.alloc(stride);
  for (let y = 0; y < png.h; y++) {
    const f = raw[y * (stride + 1)], line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)), cur = Buffer.alloc(stride);
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? cur[i - bpp] : 0, b = prev[i], c = i >= bpp ? prev[i - bpp] : 0;
      const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
      cur[i] = (line[i] + [0, a, b, (a + b) >> 1, pa <= pb && pa <= pc ? a : pb <= pc ? b : c][f]) & 255;
    }
    out.push(cur); prev = cur;
  }
  return out;
}
const lum = (rgb) => {
  const [r, g, b] = rgb.map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const contrast = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };

const failures = [];
const fail = (m) => failures.push(m);
const warnings = [];
const meta = JSON.parse(fs.readFileSync(META, 'utf8'));
const listed = [...Object.values(meta.screenshots || {}), ...Object.values(meta.screenshotsMac || {})].flat();
const measureFile = path.join(DIR, 'measure.json');
const measures = fs.existsSync(measureFile) ? JSON.parse(fs.readFileSync(measureFile, 'utf8')) : [];
if (!measures.length) fail(`${measureFile}: missing; frame the screenshots with scripts/store-frames/store-frames.js`);

for (const name of listed) {
  const file = path.join(DIR, name);
  const kind = name.split('-')[0], s = STD[kind];
  if (!s) { fail(`${name}: not an iphone-, ipad- or mac- picture`); continue; }
  if (!fs.existsSync(file)) { fail(`${name}: missing`); continue; }
  const png = readPng(file);
  if (png.w !== s.size[0] || png.h !== s.size[1]) fail(`${name}: ${png.w} x ${png.h}, not ${s.size.join(' x ')}`);
  if (png.type !== 2 || png.depth !== 8 || png.interlace) { fail(`${name}: not an opaque 8-bit RGB PNG (App Store Connect refuses alpha)`); continue; }
  const m = measures.find((x) => x.file === name);
  if (!m) { fail(`${name}: not in measure.json, so not made by store-frames.js`); continue; }
  const got = { eyebrow: m.eyebrow.fontSize, headline: m.headline.fontSize, subhead: m.subhead.fontSize, baseline: m.eyebrowBaseline,
    headlineTop: m.headline.top, subheadBottom: m.subhead.bottom, deviceTop: m.deviceTop, lines: m.headline.lines };
  for (const [k, v] of Object.entries(got)) if (v !== s[k]) fail(`${name}: ${k} ${v}, the standard is ${s[k]}`);
  // The eyebrow's contrast: its colour over the sky beside it, against that sky (the darker side of the line box).
  const px = rows(png);
  let worst = Infinity, white = Infinity;
  // Sampled just above and just below the (uppercase) eyebrow, across its width: the glow makes the middle lightest.
  for (const y of [m.eyebrow.top - 6, m.eyebrowBaseline + 6]) {
    for (const x of [png.w / 2 - 240, png.w / 2, png.w / 2 + 240]) {
      const bg = [...px[y].subarray(x * 3, x * 3 + 3)];
      const fg = bg.map((v) => Math.round(255 * EYEBROW_ALPHA + v * (1 - EYEBROW_ALPHA)));
      worst = Math.min(worst, contrast(fg, bg));
      white = Math.min(white, contrast([255, 255, 255], bg));
    }
  }
  if (worst < MIN_CONTRAST) warnings.push(`${name}: eyebrow contrast ${worst.toFixed(2)}:1 on the sky (white headline ${white.toFixed(2)}:1), under WCAG's ${MIN_CONTRAST}:1 for large text`);
  console.log(`ok ${name}: ${png.w} x ${png.h} RGB, type ${got.eyebrow}/${got.headline}/${got.subhead}, baseline ${got.baseline}, headline top ${got.headlineTop}, device top ${got.deviceTop}, eyebrow contrast ${worst.toFixed(2)}:1 (headline ${white.toFixed(2)}:1)`);
}
if (warnings.length) console.log(warnings.map((w) => `::warning::${w}`).join('\n'));
if (failures.length) { console.error(failures.map((f) => `::error::${f}`).join('\n')); process.exit(1); }
console.log(`${listed.length} screenshots match the family standard`);
