// Renders the README pictures from the web app (docs/app.html), with Playwright:
//   node scripts/readme-shots.js
// Open-Meteo is answered with a fixed, made-up forecast (an October afternoon) so the pictures
// look the same every time and need no network: docs/screenshot-app.png and docs/screenshot-widgets.png.
const path = require('path');
let playwright;
try { playwright = require('playwright'); } catch { playwright = require(path.join(require('child_process').execSync('npm root -g').toString().trim(), 'playwright')); }

const APP = 'file://' + path.resolve(__dirname, '../docs/app.html');
const OUT = path.resolve(__dirname, '../docs');
const DAY = '2026-10-17';

// One city's forecast in Open-Meteo's shape: a gentle daily curve around `base` °C.
function forecast(base, timezone) {
  const pad = (n) => String(n).padStart(2, '0');
  const date = (d) => { const t = new Date(Date.UTC(2026, 9, 17 + d)); return `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`; };
  const temp = (h) => +(base + 5 * Math.sin((h % 24 - 9) / 24 * 2 * Math.PI) - (h >= 24 ? 2 : 0)).toFixed(1);
  const hourCodes = (h) => (h % 24 >= 13 && h % 24 <= 18 ? 2 : 1);   // partly cloudy through the afternoon, matching "now"
  const hours = Array.from({ length: 48 }, (_, h) => h);
  const days = [0, 1, 2, 3, 4, 5];
  const swing = [0, -3, -4, -1, 1, 2];
  return {
    timezone,
    current: { time: `${DAY}T14:00`, temperature_2m: temp(14), apparent_temperature: temp(14) - 1, relative_humidity_2m: 58, weather_code: 2, wind_speed_10m: 14, is_day: 1 },
    hourly: {
      time: hours.map((h) => `${date(Math.floor(h / 24))}T${pad(h % 24)}:00`),
      temperature_2m: hours.map(temp),
      weather_code: hours.map(hourCodes),
      precipitation_probability: hours.map((h) => (h >= 30 && h <= 34 ? 40 : 5)),
      is_day: hours.map((h) => (h % 24 >= 7 && h % 24 < 18 ? 1 : 0)),
    },
    daily: {
      time: days.map(date),
      weather_code: [2, 61, 0, 3, 1, 2],
      temperature_2m_max: days.map((d) => +(base + 5 + swing[d]).toFixed(1)),
      temperature_2m_min: days.map((d) => +(base - 5 + swing[d] - (d === 2 ? 2 : 0)).toFixed(1)),
      precipitation_probability_max: [10, 60, 0, 5, 10, 0],
      sunrise: days.map((d) => `${date(d)}T07:10`),
      sunset: days.map((d) => `${date(d)}T18:20`),
    },
  };
}
const CITIES = [[40.7, 17, 'America/New_York'], [51.5, 12, 'Europe/London'], [35.7, 19, 'Asia/Tokyo']];

async function page(browser, url, viewport) {
  // New York time, a few minutes after the forecast's 2 PM, so "Updated …" agrees with the city's clock.
  const context = await browser.newContext({ viewport, deviceScaleFactor: 2, timezoneId: 'America/New_York' });
  await context.clock.setFixedTime(new Date('2026-10-17T18:05:00Z'));
  await context.route('**/api.open-meteo.com/**', (route) => {
    const lat = +new URL(route.request().url()).searchParams.get('latitude');
    const [, base, tz] = CITIES.find(([l]) => Math.abs(l - lat) < 1) || CITIES[0];
    route.fulfill({ contentType: 'application/json', body: JSON.stringify(forecast(base, tz)) });
  });
  const p = await context.newPage();
  await p.addInitScript(() => localStorage.setItem('twodegrees.unit', '"F"'));
  await p.goto(url);
  return p;
}

(async () => {
  const browser = await playwright.chromium.launch();

  // The app, forecast open, with room around it for its shadow.
  const app = await page(browser, APP, { width: 600, height: 1400 });
  await app.waitForSelector('.temps');
  await app.click('#daysToggle');
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
