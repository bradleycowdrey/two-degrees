// The rain map, live: loads web/radar.html in Chromium at phone and desktop sizes and checks that the
// OpenFreeMap map and RainViewer radar tiles arrive, that no tile service asks for a key, that the time
// bar shows, and that nothing sits in the top-left corner where the apps put their close button.
// Photos go to radar-*.png. Run: node tests/radar.test.js
const path = require('path');
const playwright = require('playwright');

(async () => {
  const browser = await playwright.chromium.launch();
  const url = 'file://' + path.resolve(__dirname, '../web/radar.html') + '?lat=39.74&lon=-104.98&z=7&units=F';
  let failed = 0;
  const check = (ok, name) => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name}`); if (!ok) failed++; };
  for (const [name, w, h] of [['phone', 390, 844], ['desktop', 1280, 800]]) {
    const page = await browser.newPage({ viewport: { width: w, height: h } });
    const seen = { map: 0, radar: 0, bad: [] };
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    page.on('response', async (r) => {
      const u = r.url();
      if (/carto|api[_-]?key/i.test(u)) seen.bad.push(u);
      if (u.includes('tiles.openfreemap.org') && r.ok()) seen.map++;
      if (u.includes('rainviewer.com') && u.endsWith('.png') && r.ok()) seen.radar++;
    });
    await page.goto(url);
    await page.waitForSelector('#bar:not([hidden])', { timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(5000);
    check(await page.isVisible('#bar'), `${name}: the time bar shows`);
    check(seen.map >= 3, `${name}: OpenFreeMap map loaded (${seen.map} responses)`);
    check(seen.radar >= 1, `${name}: RainViewer radar tiles loaded (${seen.radar})`);
    check(seen.bad.length === 0, `${name}: no keyed or CARTO tiles ${seen.bad.slice(0, 2).join(' ')}`);
    check(errors.length === 0, `${name}: no script errors ${errors.join('; ')}`);
    const corner = await page.evaluate(() => {
      const hits = new Set();
      for (let x = 4; x <= 60; x += 8) for (let y = 4; y <= 60; y += 8) {
        const el = document.elementFromPoint(x, y);
        if (el && !el.closest('#map canvas, .maplibregl-canvas-container') && el.id !== 'map' && el.tagName !== 'CANVAS') hits.add(el.className || el.tagName);
      }
      return [...hits];
    });
    check(corner.length === 0, `${name}: top-left corner free for the close button ${corner.join(',')}`);
    await page.screenshot({ path: `radar-${name}.png` });
    await page.close();
  }
  await browser.close();
  console.log(failed ? `${failed} FAILED` : 'ALL PASSED');
  process.exit(failed ? 1 : 0);
})();
