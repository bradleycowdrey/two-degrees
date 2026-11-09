// Renders the README pictures from the web app (docs/app.html), with Playwright:
//   node scripts/readme-shots.js
// The weather services are answered by the tests' simulated ones (tests/web-fixtures.js), so the
// pictures need no network: docs/screenshot-app.png and docs/screenshot-widgets.png.
const path = require('path');
let playwright;
try { playwright = require('playwright'); } catch { playwright = require(path.join(require('child_process').execSync('npm root -g').toString().trim(), 'playwright')); }

const APP = 'file://' + path.resolve(__dirname, '../docs/app.html');
const OUT = path.resolve(__dirname, '../docs');

const { serveApis } = require('../tests/web-fixtures.js');

async function page(browser, url, viewport) {
  const context = await browser.newContext({ viewport, deviceScaleFactor: 2, timezoneId: 'America/New_York' });
  await serveApis(context, { delay: { forecast: 0, aq: 0, alerts: 0, archive: 0 }, now: { code: 2, isDay: true } });
  const p = await context.newPage();
  await p.addInitScript(() => localStorage.setItem('twodegrees.unit', '"F"'));
  await p.goto(url);
  return p;
}

(async () => {
  const browser = await playwright.chromium.launch();

  // The app, with room around it for its shadow.
  const app = await page(browser, APP, { width: 600, height: 2600 });
  await app.waitForSelector('.temps');
  await app.waitForTimeout(1500);
  if (await app.isVisible('#askLocNo')) await app.click('#askLocNo');
  await app.waitForTimeout(300);
  const box = await app.locator('main.panel').boundingBox();
  await app.screenshot({ path: path.join(OUT, 'screenshot-app.png'), clip: { x: box.x - 40, y: box.y - 32, width: box.width + 80, height: box.height + 72 } });

  // The widgets, on the product page's desktop backdrop.
  const w = await page(browser, APP + '?widgets', { width: 820, height: 600 });
  await w.waitForSelector('.w.small.b .wn-temp');
  await w.addStyleTag({ content: `html.widgets-mode, html.widgets-mode body { padding: 32px 30px 12px !important; background:
    radial-gradient(120% 90% at 15% 0%, rgba(224,74,122,.30), transparent 55%),
    radial-gradient(90% 80% at 100% 100%, rgba(242,166,90,.22), transparent 60%),
    linear-gradient(160deg, #2B211E, #1E1A17 55%, #241B1F) !important; }
    html.widgets-mode { padding: 0 !important; }` });
  await w.waitForTimeout(200);
  const h = await w.evaluate(() => Math.ceil(document.body.getBoundingClientRect().height));
  await w.screenshot({ path: path.join(OUT, 'screenshot-widgets.png'), clip: { x: 0, y: 0, width: 820, height: h } });

  await browser.close();
  console.log('Wrote docs/screenshot-app.png and docs/screenshot-widgets.png');
})();
