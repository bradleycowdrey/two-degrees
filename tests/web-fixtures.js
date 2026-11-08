// Recorded-looking responses for the web app's live path, served through Playwright routes, so
// tests/web.test.js runs the same way everywhere (offline sandboxes and CI alike) and covers the
// live path, slow answers included: Open-Meteo's forecast, air quality and archive, the NWS alerts,
// and the Inter font from Google Fonts (so text measures as it does for visitors).
//
//   await serveApis(context, { delay, alerts, fail, offline })
//     delay:   ms per service, e.g. { forecast: 150, aq: 700, alerts: 400, archive: 2000 }
//     alerts:  NWS alert properties to return for every US point (default none)
//     fail:    services that answer 500, e.g. ['aq', 'archive']
//     offline: true makes every weather service unreachable, so the app shows its sample forecast
const fs = require('fs');
const path = require('path');

const FONTS = path.resolve(__dirname, '../Resources/Fonts');
const DELAY = { forecast: 150, aq: 700, alerts: 400, archive: 2000 };
const pad = (n) => String(n).padStart(2, '0');
const iso = (d) => d.toISOString().slice(0, 16);
const day = (d) => d.toISOString().slice(0, 10);

// A believable day-by-day climate for a place: warmer near the equator, seasons by hemisphere.
function climate(lat, doy) {
  const season = Math.cos(((doy / 365.25) * 12 + (lat < 0 ? 6 : 0) - 6.5) / 12 * 2 * Math.PI);
  return 27 - Math.abs(lat) * 0.42 + season * Math.abs(lat) * 0.26;
}
const doyOf = (d) => (Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - Date.UTC(d.getUTCFullYear(), 0, 1)) / 864e5;

function forecast(lat, lon) {
  const now = new Date(), start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const wobble = Math.sin(lat * 3 + lon), codes = [1, 2, 61, 3, 0, 80];
  const h = { time: [], temperature_2m: [], weather_code: [], precipitation_probability: [], is_day: [], precipitation: [], wind_speed_10m: [], wind_gusts_10m: [], pressure_msl: [], visibility: [], cloud_cover_low: [], cloud_cover_mid: [], cloud_cover_high: [] };
  const d = { time: [], weather_code: [], temperature_2m_max: [], temperature_2m_min: [], precipitation_probability_max: [], sunrise: [], sunset: [], precipitation_sum: [], rain_sum: [], snowfall_sum: [],
    wind_speed_10m_max: [], wind_gusts_10m_max: [], wind_direction_10m_dominant: [], uv_index_max: [] };
  for (let i = 0; i < 6; i++) {
    const date = new Date(start.getTime() + i * 864e5), mid = climate(lat, doyOf(date)) + wobble * 2 + (i % 3) - 1, code = codes[(i + Math.round(Math.abs(lon))) % codes.length];
    const temps = [], winds = [], gusts = [];
    let wet = 0;
    for (let hr = 0; hr < 24; hr++) {
      const t = new Date(date.getTime() + hr * 36e5), rain = code >= 61 && hr >= 12 && hr <= 17;
      const temp = +(mid + 5 * Math.sin((hr - 9) / 24 * 2 * Math.PI)).toFixed(1), wind = +(9 + 6 * Math.sin((hr - 8) / 24 * 2 * Math.PI) + (i % 2) * 4).toFixed(1);
      h.time.push(iso(t)); h.temperature_2m.push(temp); h.weather_code.push(rain ? code : code >= 61 ? 3 : code);
      h.precipitation_probability.push(rain ? 70 : (hr * 7) % 15); h.is_day.push(hr >= 7 && hr < 18 ? 1 : 0);
      h.precipitation.push(rain ? 0.8 : 0); h.wind_speed_10m.push(wind); h.wind_gusts_10m.push(+(wind * 1.7 + 3).toFixed(1));
      h.pressure_msl.push(+(1013 + 6 * Math.sin((i * 24 + hr) / 30) + wobble * 4).toFixed(1)); h.visibility.push(rain ? 8000 : 24140);
      h.cloud_cover_low.push(rain ? 90 : 10); h.cloud_cover_mid.push(rain ? 60 : 35); h.cloud_cover_high.push(rain ? 40 : 45);
      temps.push(temp); winds.push(wind); gusts.push(+(wind * 1.7 + 3).toFixed(1)); if (rain) wet += 0.8;
    }
    d.time.push(day(date)); d.weather_code.push(code); d.temperature_2m_max.push(Math.max(...temps)); d.temperature_2m_min.push(Math.min(...temps));
    d.precipitation_probability_max.push(code >= 61 ? 70 : 10); d.sunrise.push(day(date) + 'T06:52'); d.sunset.push(day(date) + 'T17:41');
    d.precipitation_sum.push(+wet.toFixed(1)); d.rain_sum.push(+wet.toFixed(1)); d.snowfall_sum.push(0);
    d.wind_speed_10m_max.push(Math.max(...winds)); d.wind_gusts_10m_max.push(Math.max(...gusts)); d.wind_direction_10m_dominant.push(225); d.uv_index_max.push(code >= 61 ? 1.8 : 4.6);
  }
  const ci = now.getUTCHours();
  const step0 = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), ci, Math.floor(now.getUTCMinutes() / 15) * 15));
  // A shower on its way for New York; dry elsewhere.
  const shower = lat > 40.5 && lat < 41 ? [0, 0, 0.3, 0.6, 0.4, 0.1, 0, 0] : [0, 0, 0, 0, 0, 0, 0, 0];
  return {
    latitude: lat, longitude: lon, timezone: 'GMT', utc_offset_seconds: 0,
    current: { time: iso(step0), temperature_2m: h.temperature_2m[ci], apparent_temperature: +(h.temperature_2m[ci] - 1.4).toFixed(1), relative_humidity_2m: 64,
      weather_code: h.weather_code[ci], wind_speed_10m: h.wind_speed_10m[ci], is_day: h.is_day[ci], pressure_msl: h.pressure_msl[ci], cloud_cover: 58,
      wind_gusts_10m: h.wind_gusts_10m[ci], visibility: h.visibility[ci], precipitation: 0 },
    hourly: h, daily: d,
    minutely_15: { time: shower.map((_, k) => iso(new Date(step0.getTime() + k * 9e5))), precipitation: shower },
  };
}

function airQuality(lat, lon) {
  const now = new Date(), start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - 1));
  const time = Array.from({ length: 48 }, (_, i) => iso(new Date(start.getTime() + i * 36e5)));
  const us = time.map((_, i) => 30 + (i % 24)), eu = time.map((_, i) => 18 + (i % 24) / 2);
  const i = 24 + now.getUTCHours();
  return {
    latitude: lat, longitude: lon, timezone: 'GMT',
    current: { time: time[i], us_aqi: us[i], european_aqi: eu[i], pm2_5: 9.4, pm10: 15.2, ozone: 58, nitrogen_dioxide: 14,
      alder_pollen: null, birch_pollen: null, grass_pollen: null, mugwort_pollen: null, olive_pollen: null, ragweed_pollen: null },
    hourly: { time, us_aqi: us.map((v, k) => (k < 24 ? v + 9 : v)), european_aqi: eu },
  };
}

const archives = new Map();
function archive(lat, lon, end) {
  const key = `${lat},${lon},${end}`;
  if (!archives.has(key)) {
    const time = [], max = [], min = [];
    for (let t = Date.UTC(1940, 0, 1), stop = Date.parse(end); t <= stop; t += 864e5) {
      const d = new Date(t), base = climate(lat, doyOf(d)), n = Math.sin(t / 864e5 * 1.7) * 4 + Math.sin(t / 864e5 * 0.31) * 3;
      time.push(day(d)); max.push(+(base + 5 + n).toFixed(1)); min.push(+(base - 5 + n * 0.8).toFixed(1));
    }
    archives.set(key, JSON.stringify({ latitude: lat, longitude: lon, timezone: 'GMT', daily: { time, temperature_2m_max: max, temperature_2m_min: min } }));
  }
  return archives.get(key);
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms));
async function serveApis(context, opts = {}) {
  const delay = { ...DELAY, ...(opts.delay || {}) }, fail = new Set(opts.fail || []);
  const json = (route, body, status = 200) => route.fulfill({ status, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: typeof body === 'string' ? body : JSON.stringify(body) });
  const q = (route) => new URL(route.request().url()).searchParams;
  const service = (name, make) => async (route) => {
    if (opts.offline) return route.abort('internetdisconnected');
    await wait(delay[name] || 0);
    if (fail.has(name)) return json(route, { error: true, reason: 'test' }, 500);
    return json(route, make(route));
  };
  // Inter, as Google Fonts serves it, from the copies the Mac app bundles.
  await context.route('https://fonts.googleapis.com/**', (route) => route.fulfill({ contentType: 'text/css', headers: { 'access-control-allow-origin': '*' },
    body: [['400', 'Regular'], ['500', 'Medium'], ['600', 'SemiBold']].map(([w, n]) => `@font-face{font-family:'Inter';font-style:normal;font-weight:${w};font-display:swap;src:url(https://fonts.gstatic.com/inter-${n}.ttf) format('truetype');}`).join('\n') }));
  await context.route('https://fonts.gstatic.com/**', (route) => {
    const n = (route.request().url().match(/inter-(\w+)\.ttf/) || [])[1];
    return n ? route.fulfill({ contentType: 'font/ttf', headers: { 'access-control-allow-origin': '*' }, body: fs.readFileSync(path.join(FONTS, `Inter-${n}.ttf`)) }) : route.abort();
  });
  await context.route('https://api.open-meteo.com/**', service('forecast', (r) => forecast(+q(r).get('latitude'), +q(r).get('longitude'))));
  await context.route('https://air-quality-api.open-meteo.com/**', service('aq', (r) => airQuality(+q(r).get('latitude'), +q(r).get('longitude'))));
  await context.route('https://archive-api.open-meteo.com/**', service('archive', (r) => archive(+q(r).get('latitude'), +q(r).get('longitude'), q(r).get('end_date'))));
  await context.route('https://api.weather.gov/**', service('alerts', () => ({ type: 'FeatureCollection', features: (opts.alerts || []).map((p) => ({ type: 'Feature', properties: p })) })));
  // Search and naming: the built-in lists (geocoding answers vary; the tests don't depend on them).
  await context.route('https://geocoding-api.open-meteo.com/**', (route) => (opts.offline ? route.abort('internetdisconnected') : json(route, {})));
}

module.exports = { serveApis };
