// Functional + layout tests for the web app (docs/app.html), run with Playwright:
//   node tests/web.test.js [screenshot-dir]
// Exercises every control at phone, tablet and desktop widths and all five sizes, checks
// results, layout (no overlap, no clipping, no sideways scroll) and accessibility labels.
const path = require('path');
const fs = require('fs');
let playwright;
try { playwright = require('playwright'); } catch { playwright = require(path.join(require('child_process').execSync('npm root -g').toString().trim(), 'playwright')); }

const { serveApis } = require('./web-fixtures');
const PAGE = 'file://' + path.resolve(__dirname, '../docs/app.html');
const SHOTS = process.argv[2];
const VIEWPORTS = [['small phone', 320, 640], ['phone', 390, 844], ['tablet', 768, 1024], ['desktop', 1280, 900]];
const SIZES = ['extraSmall', 'small', 'medium', 'large', 'extraLarge'];
const FOOTER = 'Made by Bradley Cowdrey. Free. Forever.';

let passed = 0, failed = 0;
const results = [];
function check(ok, what) { ok ? passed++ : failed++; results.push(`${ok ? 'PASS' : 'FAIL'} ${what}`); }

// Every page gets the live path from tests/web-fixtures.js (slow answers included); `api` changes it,
// e.g. { offline: true } for the sample forecast, or { fail: ['aq'] }.
async function newContext(browser, options, api = {}) {
  const context = await browser.newContext(options);
  await serveApis(context, api);
  return context;
}
async function fresh(browser, w, h, query = '', api = {}) {
  const context = await newContext(browser, { viewport: { width: w, height: h }, permissions: ['clipboard-read', 'clipboard-write'] }, api);
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error' && !/net::|Failed to load|ERR_/.test(m.text())) errors.push(m.text()); });
  await page.goto(PAGE + query);
  await page.waitForSelector('.temps');
  return { context, page, errors };
}

// Layout: sibling blocks on the page must not overlap, and key text must not be clipped.
async function layoutProblems(page) {
  return page.evaluate(() => {
    const problems = [];
    const blocks = [...document.querySelectorAll('.panel > *')].filter((e) => !e.hidden && e.offsetParent !== null && getComputedStyle(e).position !== 'fixed');
    for (let i = 1; i < blocks.length; i++) {
      const a = blocks[i - 1].getBoundingClientRect(), b = blocks[i].getBoundingClientRect();
      if (b.top < a.bottom - 0.5) problems.push(`${blocks[i].className || blocks[i].tagName} overlaps ${blocks[i - 1].className || blocks[i - 1].tagName} by ${(a.bottom - b.top).toFixed(1)}px`);
    }
    for (const sel of ['.hdr h1', '.place h2', '.place .local', '.temps', '.cond', '.hilo', '.summary', '.hour .h', '.hour .f', '.hour .c', '.day .d', '.day .lo', '.day .hi', '.foot .brand', '.foot .status', '#statusText',
      '.chip', '.alert b', '.alert .m', '.soon-line', '#soonAside', '.dt .eyebrow', '.dt .dv', '.dt .ds', '.dt .dn', '.mapcard b', '#mapText']) {
      for (const e of document.querySelectorAll(sel)) {
        if (e.offsetParent === null || getComputedStyle(e).clipPath === 'inset(50%)') continue;   // hidden, or visually hidden on purpose
        if (e.scrollWidth > e.clientWidth + 1 && getComputedStyle(e).textOverflow !== 'ellipsis') problems.push(`${sel} clipped ("${e.textContent.trim().slice(0, 30)}")`);
      }
    }
    // The reading: both units on one line, inside the page.
    const temps = document.querySelector('.temps');
    if (temps) {
      const page = document.querySelector('.panel').getBoundingClientRect(), big = temps.querySelector('.primary').getBoundingClientRect(), small = temps.querySelector('.secondary').getBoundingClientRect();
      if (small.top > big.bottom - 1) problems.push('the second unit has dropped under the reading');
      if (big.left < page.left - 0.5 || small.right > page.right + 0.5) problems.push('the reading runs off the page');
    }
    // 10-day forecast: in each row the low, the bar and the high sit side by side inside the row, the day's
    // range inside its bar, and the bar wide enough to read.
    for (const day of document.querySelectorAll('#days .day')) {
      const r = (s) => day.querySelector(s).getBoundingClientRect();
      const row = day.getBoundingClientRect(), bar = r('.bar'), fill = r('.bar i'), lo = r('.lo'), hi = r('.hi'), ic = r('.ic'), name = day.querySelector('.d').textContent;
      if (fill.left < bar.left - 0.5 || fill.right > bar.right + 0.5) problems.push(`${name}: the range runs out of its bar`);
      if (lo.right > bar.left + 0.5 || hi.left < bar.right - 0.5 || ic.right > lo.left + 0.5) problems.push(`${name}: the icon, low, bar and high overlap`);
      if (lo.left < row.left - 0.5 || hi.right > row.right + 0.5 || ic.bottom > row.bottom + 0.5) problems.push(`${name}: something runs out of the row`);
      if (bar.width < 16) problems.push(`${name}: the bar is only ${bar.width.toFixed(0)}px wide`);
      const dot = day.querySelector('.bar u');
      if (dot && (dot.getBoundingClientRect().left < bar.left - 1.5 || dot.getBoundingClientRect().right > bar.right + 1.5)) problems.push(`${name}: the "now" dot is off its bar`);
    }
    // Tiles: each graphic stays inside its tile, above the note.
    for (const tile of document.querySelectorAll('.dt')) {
      const box = tile.getBoundingClientRect(), g = tile.querySelector('.gfx'), note = tile.querySelector('.dn');
      if (!g) continue;
      const r = g.getBoundingClientRect();
      if (r.left < box.left - 0.5 || r.right > box.right + 0.5) problems.push(`${tile.dataset.tile}: its graphic runs out of the tile`);
      if (note && r.bottom > note.getBoundingClientRect().top + 0.5) problems.push(`${tile.dataset.tile}: its graphic runs into the note`);
    }
    if (document.documentElement.scrollWidth > innerWidth) problems.push(`page scrolls sideways by ${document.documentElement.scrollWidth - innerWidth}px`);
    return problems;
  });
}

// Layout inside a sheet (the day detail): nothing runs out of the sheet, nothing clipped or overlapping,
// the title clear of its buttons, and every chart label inside its chart.
async function sheetProblems(page) {
  return page.evaluate(() => {
    const problems = [], sheet = document.querySelector('#sheet'), sr = sheet.getBoundingClientRect();
    if (sheet.scrollWidth > sheet.clientWidth + 1) problems.push('the sheet scrolls sideways');
    for (const e of sheet.querySelectorAll('.sh-head, .sh-sum, .card, svg.chart, .facts dt, .facts dd')) {
      const r = e.getBoundingClientRect();
      if (r.left < sr.left - 0.5 || r.right > sr.right + 0.5) problems.push(`${e.className.baseVal ?? e.className ?? e.tagName} runs out of the sheet`);
    }
    const blocks = [...sheet.children];
    for (let i = 1; i < blocks.length; i++) {
      const a = blocks[i - 1].getBoundingClientRect(), b = blocks[i].getBoundingClientRect();
      if (b.top < a.bottom - 0.5) problems.push(`sheet block ${i} overlaps the one above`);
    }
    const title = sheet.querySelector('#sheetTitle').getBoundingClientRect();
    for (const b of sheet.querySelectorAll('.sh-head button')) {
      const r = b.getBoundingClientRect();
      if (r.left < title.right - 0.5 && r.right > title.left + 0.5) problems.push('the title runs into a button');
    }
    for (const e of sheet.querySelectorAll('#sheetTitle, .cond, .hl, .eyebrow, .facts dt, .facts dd')) {
      if (e.scrollWidth > e.clientWidth + 1) problems.push(`clipped "${e.textContent.trim().slice(0, 30)}"`);
    }
    for (const svg of sheet.querySelectorAll('svg.chart')) {
      const w = svg.viewBox.baseVal.width, h = svg.viewBox.baseVal.height;
      for (const t of svg.querySelectorAll('text')) {
        const b = t.getBBox();
        if (b.x < 0 || b.x + b.width > w || b.y < 0 || b.y + b.height > h) problems.push(`${svg.dataset.chart} chart label "${t.textContent}" outside the chart`);
      }
    }
    if (document.documentElement.scrollWidth > innerWidth) problems.push(`page scrolls sideways by ${document.documentElement.scrollWidth - innerWidth}px`);
    return problems;
  });
}

async function setSize(page, size) {
  await page.click('#moreBtn');
  await page.click(`#moreMenu [data-size="${size}"]`);
}

(async () => {
  const browser = await playwright.chromium.launch();
  if (SHOTS) fs.mkdirSync(SHOTS, { recursive: true });

  for (const [vp, w, h] of VIEWPORTS) {
    const { context, page, errors } = await fresh(browser, w, h);
    const t = (what) => `${vp}: ${what}`;

    // Loads cleanly, with the creator's footer verbatim and honest status.
    check((await page.textContent('.foot .brand')).trim() === FOOTER, t('footer text is exact'));
    check(/Sample forecast|Updated|Offline/.test(await page.textContent('#statusText')), t('status line says where the data came from'));
    check(await page.getAttribute('.status a', 'href') === 'https://open-meteo.com/' && (await page.textContent('.foot .status')).replace(/\s+/g, ' ').trim() === 'Weather for New York · Open-Meteo',
      t('the footer says whose weather it is, and credits Open-Meteo with a link'));

    // 10-day forecast: one card, always open, a row a day, on one shared scale.
    check((await page.textContent('#daysTitle')).trim() === '10-day forecast' && await page.isVisible('#days') && (await page.$$('#daysToggle')).length === 0, t('the 10-day forecast is open, with nothing to toggle'));
    const dayRows = await page.$$eval('#days .day', (els) => els.map((e) => [e.querySelector('.d').textContent, e.querySelector('.lo').textContent, e.querySelector('.hi').textContent].join(' ')));
    check(dayRows.length === 10 && /^Today /.test(dayRows[0]), t(`10 day rows, from Today (${dayRows.length})`));
    check(dayRows.every((r) => /^\w+ -?\d+°-?\d+°C -?\d+°-?\d+°C$/.test(r)), t(`each day gives its low and high in both units (${dayRows[1]})`));
    const scale = await page.$$eval('#days .day', (els) => {
      const edge = (e, s) => { const b = e.querySelector('.bar').getBoundingClientRect(), f = e.querySelector(s).getBoundingClientRect(); return [(f.left - b.left) / b.width, (f.right - b.left) / b.width]; };
      const fills = els.map((e) => edge(e, '.bar i'));
      return { min: Math.min(...fills.map((f) => f[0])), max: Math.max(...fills.map((f) => f[1])), same: new Set(els.map((e) => e.querySelector('.bar').getBoundingClientRect().width.toFixed(1))).size };
    });
    check(scale.same === 1 && Math.abs(scale.min) < 0.02 && Math.abs(scale.max - 1) < 0.02, t(`the bars share one scale, from the coldest low to the warmest high (${scale.min.toFixed(2)}–${scale.max.toFixed(2)})`));
    const dots = await page.$$('#days .bar u');
    check(dots.length === 1 && (await page.$$('#days .day:first-child .bar u')).length === 1, t('one "now" dot, on today'));
    check(/^(Rain|Snow|Storms) likely around \d+ [AP]M \(\d+%\)\.$|^(Warming|Cooling) to -?\d+°F \/ -?\d+°C by \d+ [AP]M\.$|^Today -?\d+°F \/ -?\d+°C to -?\d+°F \/ -?\d+°C\.$/.test((await page.textContent('#summary')).trim()),
      t(`the next 24 hours start with a line about what's coming (${(await page.textContent('#summary')).trim()})`));

    // The reading: centred, the city, both units on one baseline, the sky, today's high and low in each unit.
    const hilo = await page.$$eval('.hilo', (els) => els.map((e) => [...e.children].map((c) => c.textContent).join(' ')));
    check(/^H:-?\d+°F L:-?\d+°F$/.test(hilo[0]) && /^H:-?\d+°C L:-?\d+°C$/.test(hilo[1]), t(`today's high and low, in the larger unit then the other (${hilo.join(' | ')})`));
    const centred = await page.evaluate(() => { const p = document.querySelector('.panel').getBoundingClientRect(), mid = (e) => { const r = e.getBoundingClientRect(); return r.left + r.width / 2; };
      return ['.place h2', '.temps', '.cond', '.hilo'].every((s) => Math.abs(mid(document.querySelector(s)) - (p.left + p.width / 2)) < 2); });
    check(centred, t('the reading is centred on the page'));

    // Units.
    await page.click('#unitC');
    check((await page.textContent('.temps .primary sup')).includes('°C') && (await page.textContent('.temps .secondary')).includes('°F'), t('°C makes Celsius large, Fahrenheit beside it'));
    check(await page.getAttribute('#unitC', 'aria-pressed') === 'true', t('°C button reports pressed'));
    await page.click('#unitF');
    check((await page.textContent('.temps .primary sup')).includes('°F'), t('°F switches back'));
    const label = await page.getAttribute('.temps', 'aria-label');
    check(/degrees Fahrenheit, -?\d+ Celsius/.test(label || ''), t('screen readers hear both units'));
    check((await page.$$('.hour[role="img"][aria-label]')).length === 24, t('24 labelled hours'));

    // Detail tiles: twelve, in the apps' order, each with a value. Air quality and the archive (normals) answer after
    // the forecast, so wait for them as a visitor would; tiles without data show a dash, so every city has the same tiles.
    await page.waitForSelector('.dt[data-tile="aqi"] .aqbar', { timeout: 30000 }).catch(() => {});
    await page.waitForFunction(() => /Normal high/.test((document.querySelector('.dt[data-tile="normal"]') || {}).textContent || ''), null, { timeout: 30000 }).catch(() => {});
    const order = await page.$$eval('.dt', (els) => els.map((e) => e.dataset.tile).join(','));
    check(/^feels,humidity,wind,rain,(sunrise|sunset),uv,aqi,normal,visibility,precip,cloud,moon$/.test(order), t(`twelve tiles, in the apps' order (${order})`));
    const tiles = await page.$$eval('.dt', (els) => Object.fromEntries(els.map((e) => [e.dataset.tile.replace(/^sun(rise|set)$/, 'sun'), ['.dv', '.ds', '.dn'].map((s) => (e.querySelector(s) || { textContent: '' }).textContent.trim()).join(' | ')])));
    const expect = {
      feels: /^-?\d+°F \| -?\d+°C \| (Wind is making it feel cooler|It feels cooler than it is|Humidity is making it feel warmer|Similar to the actual temperature)\.$/,
      humidity: /^\d+% \|  \| The dew point is -?\d+°F · -?\d+°C right now\.$/,
      wind: /^\d+ mph \| \d+ km\/h \| (Calm|(A light breeze|A moderate breeze|A strong breeze|Gale-force wind) from the southwest)\.( Gusts to \d+ mph\.)?$/,
      rain: /^\d+% \| chance today \| (None expected in the next 12 hours|(Rain|Snow|Storms) likely around \d+ [AP]M)\.$/,
      sun: /^\d{1,2}:\d\d [AP]M \| ((Great|Good) colour likely|Some colour possible|Little colour expected) \| .+\. (Sunrise|Sunset) \d{1,2}:\d\d [AP]M\.$/,
      uv: /^\d+ \| (Low|Moderate|High|Very high|Extreme) \| (Use sun protection around midday|Low for the rest of the day)\.$/,
      visibility: /^\d+(\.\d)? mi \| \d+(\.\d)? km \| (Clear view|Haze is cutting the view|Fog is cutting the view)\.$/,
      cloud: /^\d+% \| (Clear|Mostly clear|Partly cloudy|Mostly cloudy|Overcast) \| (No cloud at any height|Cloud at several heights|Mostly low cloud|Mostly mid-level cloud|Mostly high, thin cloud)\.$/,
      precip: /^(0|\d+\.\d\d) in \| (0|\d+(\.\d)?) mm today \| (None expected in the next 24 hours|Expected in the next 24 hours: .+ in)\.$/,
      moon: /^(New Moon|Waxing Crescent|First Quarter|Waxing Gibbous|Full Moon|Waning Gibbous|Last Quarter|Waning Crescent) \| \d+% lit \| (Full|New) moon (today|tomorrow|in \d+ days)\.$/,
      aqi: /^\d+ \| (Good|Moderate|Unhealthy for Sensitive Groups|Unhealthy|Very Unhealthy|Hazardous) \| US AQI\. (Better than yesterday|Worse than yesterday|About the same as yesterday|Mostly .+)\.( Pollen: [a-z ]+\.)?$/,
      normal: /^(About normal|\d+° (above|below) normal) \|  \| Normal high -?\d+°F · -?\d+°C, low -?\d+°F · -?\d+°C\.$/,
    };
    for (const [k, re] of Object.entries(expect)) check(re.test(tiles[k] || ''), t(`${k} tile shows a value (${tiles[k]})`));
    // Graphics: the wind compass, the sun's path, the UV and air quality scales, the averages range bar, the cloud
    // layers and the moon; all drawn, and hidden from screen readers.
    const gfx = await page.evaluate(() => Object.fromEntries([['wind', '.compass .arrow'], ['sun', '.sunpath svg'], ['uv', '.uvbar u'], ['aqi', '.aqbar u'], ['normal', '.rbar b'], ['cloud', '.clbars i'], ['moon', 'svg.moon path']].map(([k, sel]) => {
      const e = document.querySelector(`.dt[data-tile${k === 'sun' ? '^' : ''}="${k}"] ${sel}`), box = e && e.closest('[aria-hidden="true"]');
      return [k, !!e && !!box && e.getBoundingClientRect().width > 0];
    })));
    for (const [k, ok] of Object.entries(gfx)) check(ok, t(`${k} tile has its graphic, hidden from screen readers`));
    // The wind comes from the southwest (225°) in the fixtures, so the arrow points northeast: its head up and to the right, its tail opposite.
    const arrow = await page.$eval('.dt[data-tile="wind"] .compass', (svg) => {
      const mid = (e) => { const r = e.getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2]; };
      const c = mid(svg), h = mid(svg.querySelector('.head')), tl = mid(svg.querySelector('.tail'));
      return { toward: svg.querySelector('.arrow').dataset.toward, head: [Math.sign(Math.round(h[0] - c[0])), Math.sign(Math.round(h[1] - c[1]))].join(), tail: [Math.sign(Math.round(tl[0] - c[0])), Math.sign(Math.round(tl[1] - c[1]))].join(), letters: [...svg.querySelectorAll('text')].map((x) => x.textContent).join('') };
    });
    check(arrow.toward === '45' && arrow.head === '1,-1' && arrow.tail === '-1,1' && arrow.letters === 'NESW', t(`the compass arrow points where the wind is blowing (toward ${arrow.toward}°, head ${arrow.head}, tail ${arrow.tail})`));
    const uvDot = await page.$eval('.dt[data-tile="uv"]', (e) => { const b = e.querySelector('.uvbar').getBoundingClientRect(), d = e.querySelector('.uvbar u').getBoundingClientRect(); return [(d.left + d.width / 2 - b.left) / b.width, +e.querySelector('.dv').textContent]; });
    check(Math.abs(uvDot[0] - Math.min(1, uvDot[1] / 11)) < 0.08, t(`the UV dot sits at its place on the scale (${uvDot[0].toFixed(2)} for UV ${uvDot[1]})`));
    // Air quality, as in the apps: one smooth bar in the scale's colours, the dot at the reading out of 300 (US AQI).
    const aqDot = await page.$eval('.dt[data-tile="aqi"]', (e) => { const bar = e.querySelector('.aqbar'), b = bar.getBoundingClientRect(), d = bar.querySelector('u').getBoundingClientRect();
      return [(d.left + d.width / 2 - b.left) / b.width, +e.querySelector('.dv').textContent, getComputedStyle(bar).backgroundImage]; });
    check(Math.abs(aqDot[0] - Math.min(1, aqDot[1] / 300)) < 0.03 && aqDot[2] === 'linear-gradient(90deg, rgb(0, 228, 0), rgb(255, 255, 0), rgb(255, 126, 0), rgb(255, 0, 0), rgb(143, 63, 151), rgb(126, 0, 35))',
      t(`the air quality dot sits at its place on a smooth scale (${aqDot[0].toFixed(2)} for AQI ${aqDot[1]})`));
    const looks = await page.$$eval('.dt', (els) => els.map((e) => { const cs = getComputedStyle(e), head = getComputedStyle(e.querySelector('.eyebrow'));
      return { id: e.dataset.tile, acc: cs.getPropertyValue('--acc').trim().toUpperCase(), glow: /gradient/.test(cs.backgroundImage), caps: head.textTransform === 'uppercase', icon: !!e.querySelector('.eyebrow svg[aria-hidden="true"]') }; }));
    const fixed = { humidity: '#6FC8D6', wind: '#9EDCC2', rain: '#8DB4E2', sunrise: '#F2C66D', sunset: '#F39A72', visibility: '#B4D2F0', precip: '#8DB4E2', cloud: '#B9C3CF', moon: '#EFE3CC' };
    check(looks.every((l) => l.glow && l.caps && l.icon && /^#[0-9A-F]{6}$/.test(l.acc) && (!fixed[l.id] || fixed[l.id] === l.acc)), t(`each tile has an icon, an uppercase title and its own accent glow (${looks.map((l) => l.acc).join(' ')})`));
    const uneven = await page.$$eval('.dgrid .dt', (els) => els.map((e) => e.getBoundingClientRect()).filter((r, i, a) => i > 0 && Math.abs(r.top - a[i - 1].top) < 1 && Math.abs(r.height - a[i - 1].height) > 0.5).length);
    check(uneven === 0, t('detail tiles side by side are the same height'));
    const across = await page.$$eval('.dgrid .dt', (els) => els.filter((e) => Math.abs(e.getBoundingClientRect().top - els[0].getBoundingClientRect().top) < 1).length);
    check(across === (w >= 700 ? 3 : 2), t(`tiles are ${w >= 700 ? 'three' : 'two'} across (${across})`));
    // Cards: frosted, on the city's sky, with small uppercase titles.
    const card = await page.$eval('#hourly', (e) => { const cs = getComputedStyle(e), head = getComputedStyle(e.querySelector('.eyebrow'));
      return { filter: cs.backdropFilter || cs.webkitBackdropFilter || '', fill: cs.backgroundColor.replace(/\s/g, ''), radius: cs.borderRadius, caps: head.textTransform, size: head.fontSize };
    });
    // The frost is the Mac's mix (white 0.23 at 0.55), blurred but not tinted: no added saturation.
    check(card.filter === 'blur(24px)' && card.fill === 'rgba(59,59,59,0.55)' && card.radius === '16px' && card.caps === 'uppercase' && card.size === '12px', t(`cards are frosted, with small uppercase titles (${JSON.stringify(card)})`));
    const map = await page.getAttribute('#mapLink', 'href');
    check(/^https:\/\/bradleycowdrey\.github\.io\/two-degrees\/radar\.html\?lat=40\.713&lon=-74\.006&z=7&units=F$/.test(map) && await page.getAttribute('#mapLink', 'target') === '_blank',
      t(`Rain map opens the map page at the city, in a new tab (${map})`));

    // Day detail: a day row opens it, with three charts; previous/next; Escape closes it and focus goes back.
    await page.click('#days [data-day="0"]');
    await page.waitForSelector('#sheet svg.chart');
    check(await page.isVisible('#sheet[role="dialog"][aria-modal="true"]') && /^Today, /.test(await page.textContent('#sheetTitle')), t('a day row opens its detail, as a dialog'));
    check(await page.evaluate(() => document.activeElement.id) === 'sheetClose', t('the day detail takes focus (its close button)'));
    const charts = await page.$$eval('#sheet svg.chart[role="img"][aria-label]', (els) => els.map((e) => e.dataset.chart).join(','));
    check(charts === 'temp,rain,wind', t(`the day detail has three labelled charts (${charts})`));
    const facts = await page.textContent('#sheet .facts');
    check(/Sunrise.*Sunset.*UV max.*Max gust.*Normal.*High .*Record high.*\(\d{4}\).*Record low.*\(\d{4}\)/s.test(facts), t('the facts list sunrise, sunset, UV, gust, normals and records'));
    check(await page.isDisabled('#sheetPrev'), t('no previous day before today'));
    await page.click('#sheetNext');
    check(!/^Today/.test(await page.textContent('#sheetTitle')) && !(await page.isDisabled('#sheetPrev')), t(`next goes to the next day (${await page.textContent('#sheetTitle')})`));
    await page.keyboard.press('ArrowLeft');
    check(/^Today/.test(await page.textContent('#sheetTitle')), t('the left arrow key goes back a day'));
    const swipeBy = (dx) => page.evaluate((dx) => {
      const el = document.getElementById('sheet');
      const touch = (x) => new Touch({ identifier: 1, target: el, clientX: x, clientY: 300 });
      el.dispatchEvent(new TouchEvent('touchstart', { touches: [touch(200)], changedTouches: [touch(200)], bubbles: true }));
      el.dispatchEvent(new TouchEvent('touchend', { touches: [], changedTouches: [touch(200 + dx)], bubbles: true }));
    }, dx);
    await swipeBy(-120);
    const swiped = await page.textContent('#sheetTitle');
    await swipeBy(120);
    check(!/^Today/.test(swiped) && /^Today/.test(await page.textContent('#sheetTitle')), t(`swiping left goes to the next day and right comes back (${swiped})`));
    await page.keyboard.press('Escape');
    await page.waitForSelector('#sheetBack', { state: 'hidden', timeout: 3000 }).catch(() => {});   // it closes with a short animation
    await page.waitForFunction(() => document.activeElement && document.activeElement.dataset.day === '0', null, { timeout: 2000 }).catch(() => {});
    const closed = await page.isHidden('#sheetBack'), onRow = await page.evaluate(() => { const a = document.activeElement; return a ? (a.dataset.day ?? a.tagName + (a.id ? '#' + a.id : '')) : 'none'; });
    check(closed && onRow === '0', t(`Escape closes the day detail, back on its row (closed ${closed}, focus ${onRow})`));
    await page.evaluate(() => scrollTo(0, 0));

    // Switch city. Selecting a chip must not move any chip or the Add | Edit controls.
    // (Measured along the row itself: on a phone the row may scroll to bring the chosen city into view.)
    const chipBoxes = () => page.$$eval('.chip[data-i], #addBtn', (els) => els.map((e) => { const r = e.getBoundingClientRect(), row = e.closest('#chips'); return [r.x + (row ? row.scrollLeft : 0), r.y + scrollY, r.width].map((v) => v.toFixed(1)).join(','); }).join(' '));
    // Wait until every city's temperature has arrived, so a chip growing as it loads isn't counted as a move.
    await page.waitForFunction(() => [...document.querySelectorAll('.chip[data-i]')].every((c) => c.querySelector('.t')), null, { timeout: 15000 }).catch(() => {});
    const boxesBefore = await chipBoxes();
    await page.click('.chip[data-i="1"]');
    check((await page.textContent('.place h2')).trim() === 'London' && await page.getAttribute('.chip[data-i="1"]', 'aria-current') === 'true', t('switching to London'));
    const boxesAfter = await chipBoxes();
    check(boxesBefore === boxesAfter, t(`selecting a city moves nothing in the city row (${boxesBefore} → ${boxesAfter})`));

    // Add a city from search, no duplicates, Escape closes.
    await page.click('#addBtn');
    check(await page.isVisible('#searchInput') && await page.evaluate(() => document.activeElement.id) === 'searchInput', t('Add opens a focused search'));
    await page.fill('#searchInput', 'Par');
    await page.waitForSelector('.result');
    check((await page.textContent('#results')).includes('Paris'), t('search finds Paris'));
    await page.click('.result:has-text("Paris")');
    check((await page.$$('.chip[data-i]')).length === 4 && (await page.textContent('.place h2')).trim() === 'Paris', t('adding Paris selects it'));
    await page.click('#addBtn');
    await page.fill('#searchInput', 'Paris');
    await page.keyboard.press('Enter');
    check((await page.$$('.chip[data-i]')).length === 4, t('adding Paris again does not duplicate it'));
    await page.click('#addBtn');
    await page.keyboard.press('Escape');
    check(await page.isHidden('#search'), t('Escape closes search'));
    await page.click('#addBtn');
    await page.fill('#searchInput', 'zzzzqx');
    check((await page.textContent('#results')).includes('No match'), t('a search with no results says so'));
    await page.keyboard.press('Escape');

    // City limit: 20 of your own.
    for (const q of ['Rome', 'Berlin', 'Madrid', 'Dublin', 'Amsterdam', 'Stockholm', 'Seoul', 'Sydney', 'Toronto', 'Chicago', 'Denver', 'Boston', 'Miami', 'Cairo', 'Dubai', 'Singapore']) {
      await page.click('#addBtn'); await page.fill('#searchInput', q); await page.keyboard.press('Enter');
    }
    check((await page.$$('.chip[data-i]')).length === 20 && await page.isDisabled('#addBtn'), t('limit of 20 cities disables Add'));
    check(await page.getAttribute('#addBtn', 'aria-label') === 'You can track up to 20 cities', t('the disabled Add says the limit is 20'));

    // Edit: remove, can't remove the last one.
    await page.click('#editBtn');
    check(await page.isVisible('.chip-x'), t('Edit shows remove buttons'));
    await page.click('.chip-x[data-x="1"]');
    check((await page.$$('.chip[data-i]')).length === 19 && !(await page.isDisabled('#addBtn')), t('removing a city re-enables Add'));
    while ((await page.$$('.chip[data-i]')).length > 1) await page.click('.chip-x[data-x="0"]');
    check((await page.$$('.chip-x')).length === 0, t('the last city cannot be removed'));
    check(await page.getAttribute('#editBtn', 'aria-pressed') === 'false', t('Edit turns itself off at one city'));

    // Share menu, from the header's left.
    check(await page.$eval('.hdr', (h) => h.contains(document.querySelector('#shareBtn')) && h.scrollWidth <= h.clientWidth), t('Share is in the header, and the header fits'));
    await page.click('#shareBtn');
    check(await page.isVisible('#shareMenu') && (await page.$$('#shareMenu [data-share]')).length >= 3, t('Share opens its menu'));
    const shareBox = await page.locator('#shareMenu').boundingBox();
    check(shareBox.x >= 0 && shareBox.x + shareBox.width <= w, t(`the Share menu stays on screen (${Math.round(shareBox.x)}–${Math.round(shareBox.x + shareBox.width)} of ${w})`));
    await page.click('[data-share="web"]');
    await page.waitForSelector('#toast:not([hidden])');
    const copied = await page.evaluate(() => navigator.clipboard.readText()).catch(() => '');
    check(/two-degrees\?c=/.test(copied), t(`copied link carries the cities (${copied.slice(0, 60)}…)`));
    await page.click('#shareBtn');
    await page.click('[data-share="mac"]');
    check(/releases\/latest\/download\/TwoDegrees\.dmg$/.test(await page.evaluate(() => navigator.clipboard.readText()).catch(() => '')), t('Copy Mac download link'));
    await page.click('#shareBtn');
    await page.click('[data-share="message"]');
    const message = await page.evaluate(() => navigator.clipboard.readText()).catch(() => '');
    check(message.includes('°F and °C') && message.includes('two-degrees?c=') && message.includes('TwoDegrees.dmg'), t('Copy a message to send'));
    await page.click('#shareBtn');
    await page.keyboard.press('Escape');
    check(await page.isHidden('#shareMenu'), t('Escape closes the Share menu'));

    // More menu: copy reading, font, every size with layout checks and screenshots.
    await page.click('#moreBtn');
    await page.click('[data-act="copy"]');
    // The copy is asynchronous: wait for the clipboard to hold the reading.
    let reading = '';
    for (let i = 0; i < 20 && !/°F \/ -?\d+°C/.test(reading); i++) {
      reading = await page.evaluate(() => navigator.clipboard.readText()).catch(() => '');
      if (!/°F \/ -?\d+°C/.test(reading)) await page.waitForTimeout(100);
    }
    check(/°F \/ -?\d+°C/.test(reading), t('Copy Current Reading copies both units'));
    await page.click('#moreBtn');
    await page.click('[data-font="system"]');
    check(await page.evaluate(() => document.querySelector('.panel').classList.contains('system')), t('Font: System applies'));
    await page.click('#moreBtn');
    await page.click('[data-font="inter"]');
    check(!(await page.evaluate(() => document.querySelector('.panel').classList.contains('system'))), t('Font: Inter applies'));
    for (const [i, size] of SIZES.entries()) {
      await setSize(page, size);
      for (const unit of ['F', 'C']) {
        await page.click('#unit' + unit);
        const problems = await layoutProblems(page);
        check(problems.length === 0, t(`${size}, °${unit} large: layout${problems.length ? ' — ' + problems.join('; ') : ' clean'}`));
        if (SHOTS) await page.screenshot({ path: path.join(SHOTS, `web-${vp}-${i}-${size}-${unit}.png`), fullPage: true });
        if (unit === 'C') {
          await page.click('#days [data-day="1"]');
          await page.waitForSelector('#sheet svg.chart');
          const inSheet = await sheetProblems(page);
          check(inSheet.length === 0, t(`${size}, day detail: layout${inSheet.length ? ' — ' + inSheet.join('; ') : ' clean'}`));
          if (SHOTS) await page.screenshot({ path: path.join(SHOTS, `web-${vp}-${i}-${size}-day.png`) });
          await page.keyboard.press('Escape');
        }
      }
    }
    await page.click('#unitF');
    await setSize(page, 'medium');

    // Persistence: settings survive a reload, and the forecast is all there again.
    await page.click('#unitC');
    await page.reload();
    await page.waitForSelector('.temps');
    check((await page.textContent('.temps .primary sup')).includes('°C'), t('unit choice survives a reload'));
    check((await page.$$('.chip[data-i]')).length === 1, t('saved cities survive a reload'));
    check((await page.$$('#days .day')).length === 10 && (await page.$$('.dt')).length === 12, t('the 10 days and twelve tiles are there again after a reload'));

    check(errors.length === 0, t(`no script errors${errors.length ? ': ' + errors.join(' | ') : ''}`));
    await context.close();
  }

  // Rounding matches the Mac app: halves round away from zero.
  {
    const { context, page } = await fresh(browser, 1280, 900);
    const r = await page.evaluate(() => [__twoDegreesTest.deg(-2.5, 'C'), __twoDegreesTest.deg(2.5, 'C'), __twoDegreesTest.deg(-19.7, 'F'), __twoDegreesTest.deg(37, 'F')]);
    check(JSON.stringify(r) === '[-3,3,-3,99]', `rounding matches the Mac app (${r})`);
    await context.close();
  }

  // The sky: behind the page is the showing city's sky for its weather and time of day, across the whole
  // window, in the apps' colours (Sky.swift). No panel, and no rule across the top.
  {
    const look = async (now, w = 390, h = 844) => {
      const { context, page } = await fresh(browser, w, h, '', { now });
      const r = await page.evaluate(() => {
        const sky = getComputedStyle(document.body, '::before'), panel = document.querySelector('.panel'), tone = (s) => getComputedStyle(document.querySelector(s)).color.replace(/\s/g, '');
        return { image: sky.backgroundImage, fixed: sky.position, w: parseFloat(sky.width), h: parseFloat(sky.height), panel: getComputedStyle(panel).backgroundColor, rule: getComputedStyle(panel, '::before').content,
          tones: ['.place h2', '.dt .dn', '.dt .ds', '#hoursTitle', '.foot'].map(tone).join(' '),
          foot: [...document.querySelectorAll('.foot > *')].map((e) => getComputedStyle(e).fontSize + ' ' + getComputedStyle(e).textAlign).join(','),
          chips: [...document.querySelectorAll('.chip[data-i]')].map((c) => getComputedStyle(c).backgroundColor.replace(/\s/g, '') + '/' + getComputedStyle(c).color.replace(/\s/g, '')) };
      });
      await context.close();
      return r;
    };
    const day = await look({ code: 0, isDay: true }), night = await look({ code: 63, isDay: false }), wide = await look({ code: 0, isDay: true }, 1280, 900);
    check(day.image === 'linear-gradient(rgb(61, 116, 176), rgb(28, 58, 94))', `sky: a clear day is blue (${day.image})`);
    check(night.image === 'linear-gradient(rgb(37, 44, 54), rgb(16, 19, 23))' && night.image !== day.image, `sky: a rainy night is dark slate, not the clear day's sky (${night.image})`);
    check(wide.fixed === 'fixed' && wide.w >= 1260 && wide.h === 900 && wide.image === day.image, `sky: it fills the whole window on a desktop (${wide.w}×${wide.h})`);
    check(day.panel === 'rgba(0, 0, 0, 0)' && day.rule === 'none', `sky: no panel behind the page and no rule across its top (${day.panel}, ${day.rule})`);
    check(day.tones === 'rgb(255,255,255) rgba(255,255,255,0.85) rgba(255,255,255,0.7) rgba(255,255,255,0.6) rgba(255,255,255,0.6)', `text is white at 1, 0.85, 0.7 and 0.6 (${day.tones})`);
    check(day.foot === '13px center,13px center,13px center', `the footer is three centred 13px lines (${day.foot})`);
    check(day.chips[0] === 'rgb(255,255,255)/rgb(21,24,30)' && day.chips.slice(1).every((c) => /^rgba\(255,255,255,0\.\d+\)\/rgba?\(255,255,255/.test(c)), `the city showing is a solid white capsule, the others translucent (${day.chips.join(' ')})`);
    const { context, page } = await fresh(browser, 390, 844);
    const table = await page.evaluate(() => [[0, true], [1, false], [2, true], [3, true], [3, false], [45, true], [63, true], [63, false], [73, true], [86, false], [95, true]].map(([code, isDay]) => __twoDegreesTest.sky(code, isDay).join('>')).join(' '));
    check(table === '#3D74B0>#1C3A5E #141E3C>#0A0E1C #4F78A3>#24384F #667585>#2E3640 #262A33>#111317 #667585>#2E3640 #4F5E70>#232A33 #252C36>#101317 #7C8EA0>#3E4A57 #323B47>#14181E #3A3346>#16131B',
      `sky: the same colours as the apps for clear, cloudy, fog, rain, snow and storms (${table})`);
    await context.close();
  }

  // Menus drop over the page. Browsers where a container also contains layout (Safari 16–17) make the top bar
  // a layer of its own, so it must sit above the cards: emulated here with contain: layout.
  for (const [vp, w, h] of [VIEWPORTS[1], VIEWPORTS[3]]) {
    const { context, page } = await fresh(browser, w, h);
    await page.waitForSelector('.dt[data-tile="aqi"] .aqbar', { timeout: 30000 }).catch(() => {});
    await page.addStyleTag({ content: '.hdr, .now, .daily, .details, .dt { contain: layout }' });
    for (const [btn, menu] of [['#shareBtn', '#shareMenu'], ['#moreBtn', '#moreMenu']]) {
      await page.click(btn);
      const covered = await page.$eval(menu, (m) => { const r = m.getBoundingClientRect(); let n = 0;
        for (let i = 0; i < 10; i++) for (let j = 0; j < 10; j++) { const y = r.top + (j + 0.5) * r.height / 10; if (y < innerHeight && !m.contains(document.elementFromPoint(r.left + (i + 0.5) * r.width / 10, y))) n++; }
        return n; });
      check(covered === 0, `${vp}: the ${menu === '#shareMenu' ? 'Share' : '⋯'} menu opens over the cards, nothing painted on top of it (${covered} of 100 points covered)`);
      await page.keyboard.press('Escape');
    }
    await context.close();
  }

  // A deep freeze: two wide numbers (-27°F -33°C) still share one line, at phone widths and every size.
  for (const [vp, w, h] of VIEWPORTS.slice(0, 2)) {
    const { context, page } = await fresh(browser, w, h, '', { offset: -40 });
    for (const size of SIZES) {
      await setSize(page, size);
      for (const unit of ['F', 'C']) {
        await page.click('#unit' + unit);
        const reading = (await page.$eval('.temps', (e) => [...e.children].map((c) => c.textContent).join(' '))).trim(), problems = await layoutProblems(page);
        check(/^-\d\d°[FC] -\d\d°[FC]$/.test(reading) && problems.length === 0, `${vp}: ${size}, a deep freeze, °${unit} large (${reading}): layout${problems.length ? ' — ' + problems.join('; ') : ' clean'}`);
      }
    }
    if (SHOTS) await page.screenshot({ path: path.join(SHOTS, `web-${vp}-deep-freeze.png`), fullPage: true });
    await context.close();
  }

  // Malformed shared links: bad numbers and empty names are skipped, more than 5 cities are cut,
  // and names are shown as text, never run as HTML.
  {
    const bad = '?c=' + encodeURIComponent('Nowhere~abc~1|~10~10|<img src=x onerror=window.pwned=1>~1~1|A~1~1|B~2~2|C~3~3|D~4~4|E~5~5');
    const { context, page } = await fresh(browser, 1280, 900, bad);
    const chips = await page.$$eval('.chip[data-i]', (els) => els.map((e) => e.textContent.trim()));
    check(chips.length === 6, `malformed link: keeps the 6 valid cities (${chips.length})`);
    check(!(await page.evaluate(() => window.pwned)) && chips[0].startsWith('<img'), 'malformed link: a city name with HTML is shown as text');
    await context.close();
  }

  // A link with more than 20 cities keeps the first 20.
  {
    const many = '?c=' + Array.from({ length: 25 }, (_, i) => `C${i}~${i}~${i}`).join('|');
    const { context, page } = await fresh(browser, 1280, 900, many);
    check((await page.$$('.chip[data-i]')).length === 20, `a link with 25 cities keeps 20 (${(await page.$$('.chip[data-i]')).length})`);
    await context.close();
  }

  // Unit choices: wind and rain follow the ⋯ menu, show the other system beside them where there is one, and are saved.
  {
    const { context, page } = await fresh(browser, 390, 844);
    const tile = (k) => page.$eval(`.dt[data-tile="${k}"]`, (e) => [e.querySelector('.dv').textContent.trim(), (e.querySelector('.ds') || { textContent: '' }).textContent.trim()].join(' / '));
    const wind = () => tile('wind');
    check(/mph \/ /.test(await wind()) && /in \/ .*mm today$/.test(await tile('precip')), `units: Automatic with °F is mph and in (${await wind()}; ${await tile('precip')})`);
    await page.click('#unitC');
    check(/km\/h \/ /.test(await wind()) && /mm \/ .*in today$/.test(await tile('precip')), `units: Automatic with °C is km/h and mm (${await wind()}; ${await tile('precip')})`);
    const pick = async (attr) => { await page.click('#moreBtn'); await page.click(`#moreMenu [${attr}]`); };
    await pick('data-wind-unit="ms"');
    check(/^\d+ m\/s \/ $/.test(await wind()) && / km \/ [\d.,]+ (mi|ft)$/.test(await tile('visibility')), `Wind: m/s stands alone; visibility in km with miles beside it (${await wind()}; ${await tile('visibility')})`);
    await pick('data-wind-unit="kn"');
    check(/^\d+ kn \/ $/.test(await wind()), `Wind: knots (${await wind()})`);
    await pick('data-wind-unit="mph"');
    check(/^\d+ mph \/ \d+ km\/h$/.test(await wind()) && / mi \/ [\d.,]+ (km|m)$/.test(await tile('visibility')), `Wind: mph, with km/h beside it, and visibility in miles (${await wind()}; ${await tile('visibility')})`);
    await pick('data-rain-unit="in"');
    check(/^(0|\d+\.\d\d) in \/ (0|\d+(\.\d)?) mm today$/.test(await tile('precip')), `Rain: in, with mm beside it (${await tile('precip')})`);
    await page.click('#moreBtn');
    check(await page.getAttribute('#moreMenu [data-wind-unit="mph"]', 'aria-checked') === 'true' && (await page.textContent('#moreMenu')).includes('Severe weather alerts: United States only, from the National Weather Service.'),
      'the ⋯ menu shows the unit chosen, and where alerts come from');
    await page.keyboard.press('Escape');
    const saved = await page.evaluate(() => ['windUnit', 'rainUnit'].map((k) => localStorage.getItem('twodegrees.' + k)).join(','));
    check(saved === '"mph","in"', `unit choices are saved as windUnit and rainUnit (${saved})`);
    await page.reload();
    await page.waitForSelector('.temps');
    check(/^\d+ mph/.test(await wind()) && /^(0|\d+\.\d\d) in \//.test(await tile('precip')), 'unit choices survive a reload');
    await context.close();
  }

  // Next 2 hours, from the live 15-minute forecast (a shower on its way for New York) and from the sample
  // (a shower coming for some places): the card shows 8 steps and a plain line.
  for (const [mode, api] of [['live', {}], ['sample', { offline: true }]]) {
    const { context, page, errors } = await fresh(browser, 390, 844, '', api);
    const t = (what) => `${mode}: ${what}`;
    let found = null;
    for (const i of [0, 1, 2]) {
      await page.click(`.chip[data-i="${i}"]`);
      if (await page.isVisible('#soon')) { found = (await page.textContent('.place h2')).trim(); break; }
    }
    check(!!found && (mode === 'sample' || found === 'New York'), t(`the Next 2 hours card shows for a city with rain coming (${found})`));
    if (found) {
      const line = (await page.textContent('#soonLine')).trim();
      check((mode === 'live' ? /^Rain starting around \d{1,2}:\d\d [AP]M$/ : /^((Rain|Snow) (starting|stopping) around \d{1,2}:\d\d [AP]M|(Rain|Snow) for the next two hours|Light (rain|snow) on and off)$/).test(line), t(`Next 2 hours says what's coming (${line})`));
      check((await page.$$('#soonBars .b')).length === 8 && (await page.textContent('#soonBars .b .t')).trim() === 'Now', t('Next 2 hours has 8 bars, from Now'));
      check(/^(0|\d+\.\d\d) in · (0|\d+(\.\d)?) mm$/.test((await page.textContent('#soonAside')).trim()), t(`Next 2 hours totals it in the rain unit (${await page.textContent('#soonAside')})`));
      check(/Now: /.test(await page.getAttribute('#soonBars', 'aria-label')), t('Next 2 hours is read out step by step'));
    }
    check(errors.length === 0, t(`Next 2 hours: no script errors${errors.length ? ': ' + errors.join(' | ') : ''}`));
    await context.close();
  }

  // Severe weather alerts: cards above everything, most severe first, coloured by severity; the full text opens.
  {
    const { context, page, errors } = await fresh(browser, 390, 844);
    await page.waitForFunction(() => /Normal high/.test((document.querySelector('.dt[data-tile="normal"]') || {}).textContent || ''), null, { timeout: 30000 }).catch(() => {});   // the slowest answer: everything else is in
    check(await page.isHidden('#alerts'), 'no alerts show when the NWS has none');
    const soon = new Date(Date.now() + 3 * 36e5).toISOString(), past = new Date(Date.now() - 36e5).toISOString();
    await page.evaluate(([soon, past]) => __twoDegreesTest.inject('alerts', [
      { id: 'a', event: 'Frost Advisory', severity: 'Minor', headline: 'Frost Advisory until 9 AM', description: 'Temperatures as low as 30.', instruction: 'Cover plants.', expires: soon, senderName: 'NWS New York NY' },
      { id: 'b', event: 'Tornado Warning', severity: 'Extreme', headline: 'Tornado Warning until 6:15 PM', description: 'A tornado was seen.', instruction: 'Take cover now.', expires: soon, senderName: 'NWS New York NY' },
      { id: 'c', event: 'Wind Advisory', severity: 'Moderate', headline: 'Wind Advisory', description: 'Gusty winds.', expires: soon, senderName: 'NWS New York NY' },
      { id: 'd', event: 'Expired Warning', severity: 'Severe', headline: 'Old', description: 'Over.', expires: past, senderName: 'NWS New York NY' },
    ]), [soon, past]);
    const cards = await page.$$eval('.alert', (els) => els.map((e) => [e.querySelector('b').textContent, getComputedStyle(e).getPropertyValue('--sev').trim(), e.querySelector('.m').textContent]));
    check(cards.map((c) => c[0]).join(',') === 'Tornado Warning,Wind Advisory,Frost Advisory', `alerts: most severe first, expired ones left out (${cards.map((c) => c[0]).join(', ')})`);
    check(cards.map((c) => c[1].toUpperCase()).join(',') === '#E5484D,#F2A65A,#E9C98A', `alerts: red, orange, yellow by severity (${cards.map((c) => c[1]).join(', ')})`);
    check(/^Until \d{1,2}:\d\d [AP]M · NWS New York NY$/.test(cards[0][2]), `an alert says until when, and who sent it (${cards[0][2]})`);
    // As in the apps: right under the reading, above every card.
    const order = await page.evaluate(() => { const top = (s) => document.querySelector(s).getBoundingClientRect().top, a = document.querySelector('#alerts').getBoundingClientRect();
      return a.top >= document.querySelector('#now').getBoundingClientRect().bottom && ['#soon', '#hourly', '#daily', '#mapLink', '#details'].every((s) => document.querySelector(s).hidden || a.bottom <= top(s)); });
    check(order, 'alerts sit right under the reading, above every card');
    check((await page.$$('.chip[data-i="0"] svg.warn')).length === 1 && (await page.$$('.chip[data-i="1"] svg.warn')).length === 0, 'the city with an alert has a warning triangle in the city list');
    const problems = await layoutProblems(page);
    check(problems.length === 0, `alerts: layout${problems.length ? ' — ' + problems.join('; ') : ' clean'}`);
    if (SHOTS) await page.screenshot({ path: path.join(SHOTS, 'web-phone-alerts.png'), fullPage: true });
    await page.click('.alert[data-alert="0"]');
    const text = await page.textContent('#sheet');
    check(await page.isVisible('#sheet[role="dialog"]') && (await page.textContent('#sheetTitle')) === 'Tornado Warning' && text.includes('Tornado Warning until 6:15 PM') && text.includes('Take cover now.'),
      'an alert opens its full text');
    check(text.includes('From the US National Weather Service. Alerts can be late or missing: follow official warnings.') && /weather\.gov/.test(await page.getAttribute('#sheet a.al-link', 'href')) && (await page.textContent('#sheet a.al-link')).includes('More at weather.gov'),
      'the alert links to weather.gov, with the note about official warnings');
    if (SHOTS) await page.screenshot({ path: path.join(SHOTS, 'web-phone-alert-detail.png') });
    await page.keyboard.press('Escape');
    check(await page.isHidden('#sheetBack') && await page.evaluate(() => document.activeElement.dataset.alert) === '0', 'Escape closes the alert, back on its card');
    await page.evaluate(() => __twoDegreesTest.inject('alerts', []));
    check(await page.isHidden('#alerts'), 'no alerts: no empty card');
    check(errors.length === 0, `alerts: no script errors${errors.length ? ': ' + errors.join(' | ') : ''}`);
    await context.close();
  }

  // The live path's extras: NWS alerts parsed from the feed; air quality showing before the slow archive;
  // and services that fail hide just their tiles, the way the app falls back.
  {
    const soon = new Date(Date.now() + 2 * 36e5).toISOString(), past = new Date(Date.now() - 36e5).toISOString();
    const alerts = [
      { id: 'urn:oid:1', event: 'Winter Storm Warning', severity: 'Severe', urgency: 'Expected', headline: 'Winter Storm Warning issued by NWS', description: 'Heavy snow expected.', instruction: 'Travel could be very difficult.', effective: past, expires: soon, senderName: 'NWS New York NY' },
      { id: 'urn:oid:2', event: 'Special Weather Statement', severity: 'Moderate', headline: 'Old statement', description: 'Over.', expires: past, senderName: 'NWS New York NY' },
    ];
    const { context, page, errors } = await fresh(browser, 390, 844, '', { alerts, delay: { archive: 5000 } });
    await page.waitForSelector('.alert', { timeout: 15000 }).catch(() => {});
    const cards = await page.$$eval('.alert b', (els) => els.map((e) => e.textContent));
    check(cards.join(',') === 'Winter Storm Warning', `live: the NWS alerts for New York show, expired ones left out (${cards.join(', ')})`);
    check((await page.$$('.chip[data-i="0"] svg.warn')).length === 1 && (await page.$$('.chip[data-i="1"] svg.warn')).length === 0, 'live: New York has the warning triangle, London (no NWS) none');
    await page.waitForSelector('.dt[data-tile="aqi"] .aqbar', { timeout: 15000 }).catch(() => {});
    const early = await page.evaluate(() => [!!document.querySelector('.dt[data-tile="aqi"] .aqbar'), /Normal high/.test((document.querySelector('.dt[data-tile="normal"]') || {}).textContent || '')]);
    check(early[0] && !early[1], `live: air quality shows without waiting for the slow archive (aqi ${early[0]}, normals ${early[1]})`);
    const aq = await page.textContent('.dt[data-tile="aqi"]');
    check(/US AQI/.test(aq) && /Better than yesterday/.test(aq), `live: air quality in New York on the US scale, against yesterday (${aq})`);
    await page.waitForFunction(() => /Normal high/.test((document.querySelector('.dt[data-tile="normal"]') || {}).textContent || ''), null, { timeout: 30000 }).catch(() => {});
    check(/Normal high/.test(await page.textContent('.dt[data-tile="normal"]').catch(() => '')), 'live: the averages tile appears when the archive answers');
    await page.click('#days [data-day="0"]');
    check(/Record high.*\(\d{4}\).*Record low.*\(\d{4}\)/s.test(await page.textContent('#sheet .facts')), 'live: the day detail has the records from the archive');
    await page.keyboard.press('Escape');
    check(errors.length === 0, `live extras: no script errors${errors.length ? ': ' + errors.join(' | ') : ''}`);
    await context.close();
  }
  {
    const { context, page, errors } = await fresh(browser, 390, 844, '', { fail: ['aq', 'archive', 'alerts'] });
    await page.waitForTimeout(3500);   // every answer (and failure) is in
    const shown = await page.$$eval('.dt', (els) => els.map((e) => e.dataset.tile).join(','));
    const dashes = await page.$$eval('.dt[data-tile="aqi"] .dv, .dt[data-tile="normal"] .dv', (els) => els.map((e) => e.textContent.trim()).join(','));
    const notes = await page.$$eval('.dt[data-tile="aqi"] .dn, .dt[data-tile="normal"] .dn', (els) => els.map((e) => e.textContent.trim()).join(','));
    check(/^feels,humidity,wind,rain,(sunrise|sunset),uv,aqi,normal,visibility,precip,cloud,moon$/.test(shown) && dashes === '–,–' && notes === 'Not available right now.,Not available right now.' && await page.isHidden('#alerts'),
      `live: failed air quality and archive keep their tiles with a dash, and NWS shows no alerts (${shown}; ${dashes}; ${notes})`);
    check(/Updated/.test(await page.textContent('#statusText')), 'live: the forecast itself still shows as live');
    await page.click('#days [data-day="0"]');
    const facts = await page.textContent('#sheet .facts');
    check(/Sunrise/.test(facts) && !/Normal|Record/.test(facts) && (await page.$$('#sheet svg.chart')).length === 3, 'live: without the archive, the day detail leaves out normals and records');
    await page.keyboard.press('Escape');
    check(errors.length === 0, `failed extras: no script errors${errors.length ? ': ' + errors.join(' | ') : ''}`);
    await context.close();
  }

  // The sample forecast (no internet): sample air quality, normals and records, labelled as a sample.
  {
    const { context, page, errors } = await fresh(browser, 390, 844, '', { offline: true });
    const shown = await page.$$eval('.dt', (els) => els.map((e) => e.dataset.tile).join(','));
    check(/aqi/.test(shown) && /normal/.test(shown) && !/pressure/.test(shown) && /moon/.test(shown) && (await page.textContent('#statusText')) === 'Sample forecast', `sample: the tiles come with sample data, labelled Sample forecast (${shown})`);
    check(errors.length === 0, `sample: no script errors${errors.length ? ': ' + errors.join(' | ') : ''}`);
    await context.close();
  }

  // Pollen (Europe, in season) and the air quality scale, from injected readings.
  {
    const { context, page } = await fresh(browser, 1280, 900);
    await page.click('.chip[data-i="1"]');   // London: the European AQI
    await page.waitForFunction(() => document.querySelector('.place h2').textContent.trim() === 'London' && document.querySelector('.dt[data-tile="aqi"] .aqbar') && /Normal high/.test(document.querySelector('.dt[data-tile="normal"]').textContent), null, { timeout: 30000 });
    await page.evaluate(() => __twoDegreesTest.inject('aq', { us: 60, eu: 45, usY: null, euY: null, pm25: 30, pm10: 20, o3: 50, no2: 10, pollen: { grass: 120, birch: 30, alder: 2 } }));
    const aq = await page.textContent('.dt[data-tile="aqi"]');
    check(/45\s*Moderate/.test(aq) && /European AQI/.test(aq) && /Mostly PM2\.5/.test(aq), `London's air quality is on the European scale, with the main pollutant (${aq})`);
    const euDot = await page.$eval('.dt[data-tile="aqi"] .aqbar', (bar) => { const b = bar.getBoundingClientRect(), d = bar.querySelector('u').getBoundingClientRect(); return [(d.left + d.width / 2 - b.left) / b.width, getComputedStyle(bar).backgroundImage]; });
    check(Math.abs(euDot[0] - 0.45) < 0.03 && /^linear-gradient\(90deg, rgb\(80, 240, 230\), .+rgb\(125, 33, 129\)\)$/.test(euDot[1]) && !/%/.test(euDot[1]), `the European scale's bar is smooth, its dot at the reading out of 100 (${euDot[0].toFixed(2)} for 45)`);
    check(/Pollen: grass high\./.test(aq) && (await page.$$('.dt[data-tile="pollen"]')).length === 0, `pollen is a line on the air quality tile, not a tile of its own (${aq})`);
    check(await page.$$eval('.dt', (els) => els.length) === 12, 'London has the same twelve tiles as New York');
    const sun = await page.textContent('.dt[data-tile^="sun"]').catch(() => '');
    check(/^(Sunrise|Sunset)/.test(sun.trim()) && /\d:\d\d [AP]M/.test(sun) && /(Great|Good) colour likely|Some colour possible|Little colour expected/.test(sun) && /(Sunrise|Sunset) \d{1,2}:\d\d [AP]M\.$/.test(sun.trim()),
      `the sun tile gives the next sunrise or sunset, how colourful it'll be, and the other's time (${sun.replace(/\s+/g, ' ')})`);
    const rules = await page.evaluate(() => [[0, 20, 50], [20, 0, 50], [0, 0, 0], [0, 95, 95], [80, 30, 30]].map(([l, m, h]) => __twoDegreesTest.skyRule(l, m, h, 0, 2, 24000).r).join(','));
    const nm = await page.evaluate(() => [__twoDegreesTest.moonNext(0.5 - 1 / 29.53), __twoDegreesTest.moonNext(0)].join(' | '));
    check(nm === 'Full moon tomorrow. | New moon today.', `the moon tile says when the next full or new moon is (${nm})`);
    const dist = await page.evaluate(() => [[24000, false], [24000, true], [12875, true], [12875, false], [490, true], [490, false]].map(([m, i]) => __twoDegreesTest.distance(m, i)).join(', '));
    check(dist === '24 km, 15 mi, 8 mi, 13 km, 1,600 ft, 490 m', `visibility in miles and kilometres, and feet and metres in fog (${dist})`);
    check(rules === '3,2,1,1,0', `sky colour: high cloud great, some low cloud good, clear or overcast fair, low cloud poor (${rules})`);
    await page.evaluate(() => __twoDegreesTest.inject('aq', { us: null, eu: null, pollen: null }));
    check(await page.$eval('.dt[data-tile="aqi"] .dv', (e) => e.textContent.trim()) === '–' && await page.$$eval('.dt', (els) => els.length) === 12, 'no air quality reading: its tile shows a dash and the count stays twelve');
    const m = await page.evaluate(() => [__twoDegreesTest.moonPhase(new Date(Date.UTC(2000, 0, 6, 18, 14))).name, __twoDegreesTest.moonPhase(new Date(Date.UTC(2000, 0, 21, 4, 40))).name, __twoDegreesTest.moonPhase(new Date(Date.UTC(2026, 9, 26, 4, 12))).lit]);
    check(m[0] === 'New Moon' && m[1] === 'Full Moon' && m[2] >= 99, `the moon phase is computed from the 2000-01-06 new moon (${m.join(', ')})`);
    await context.close();
  }

  // Inside the product page's frame: the day detail takes the panel's place, then gives it back.
  {
    const context = await newContext(browser, { viewport: { width: 1280, height: 900 } });
    const page = await context.newPage();
    await page.goto('file://' + path.resolve(__dirname, '../docs/index.html'));
    const frame = page.frameLocator('#app');
    await frame.locator('.temps').waitFor();
    await frame.locator('#days [data-day="2"]').click();
    await frame.locator('#sheet svg.chart').first().waitFor();
    const shown = await frame.locator('body').evaluate(() => [getComputedStyle(document.querySelector('main.panel')).display, document.querySelectorAll('#sheet svg.chart').length, document.querySelector('#sheet').getBoundingClientRect().height]);
    check(shown[0] === 'none' && shown[1] === 3 && shown[2] > 300, `in the product page, the day detail shows in place of the panel (${shown.join(', ')})`);
    await frame.locator('#sheetClose').click();
    check(await frame.locator('main.panel').isVisible() && await frame.locator('#sheetBack').isHidden(), 'in the product page, closing the day detail brings the panel back');
    await context.close();
  }

  // Shared links open with their cities.
  {
    const { context, page } = await fresh(browser, 1280, 900, '?c=Denver~39.739~-104.990|Tokyo~35.676~139.650');
    const chips = await page.$$eval('.chip[data-i]', (els) => els.map((e) => e.textContent.trim()));
    check(chips.length === 2 && chips[0].startsWith('Denver') && chips[1].startsWith('Tokyo'), `shared link opens Denver and Tokyo (${chips.join(', ')})`);
    await context.close();
  }

  // Use My Location: on at load (the browser allows it here), first and shown; off from the ⋯ menu.
  {
    const context = await newContext(browser, { viewport: { width: 390, height: 844 }, permissions: ['geolocation', 'clipboard-read', 'clipboard-write'], geolocation: { latitude: 39.7392, longitude: -104.9847 } });
    const page = await context.newPage();
    await page.goto(PAGE);
    await page.waitForSelector('#askLoc:not([hidden])', { timeout: 10000 }).catch(() => {});
    check(await page.isVisible('#askLoc') && (await page.$$('.chip svg.here')).length === 0, 'first visit asks "Show the weather where you are?" before using it');
    await page.click('#askLocYes');
    await page.waitForSelector('.chip svg.here', { timeout: 30000 }).catch(() => {});
    check(!(await page.isVisible('#askLoc')), 'answering hides the question');
    const chips = await page.$$eval('.chip[data-i]', (els) => els.map((e) => ({ here: !!e.querySelector('svg.here'), on: e.getAttribute('aria-current') === 'true', name: e.querySelector('.n').dataset.n })));
    check(chips.length === 4 && chips[0].here && chips[0].on, `Use My Location adds where you are first and shows it (${chips.map((c) => (c.here ? '➤' : '') + c.name).join(', ')})`);
    const saved = await page.evaluate(() => JSON.parse(localStorage.getItem('twodegrees.cities') || '[]')[0] || {});
    check(saved.here === true && Math.abs(saved.lat - 39.74) < 0.001 && Math.abs(saved.lon + 104.98) < 0.001, `its coordinates are rounded to about a kilometre (${saved.lat}, ${saved.lon})`);
    await page.click('#shareBtn');
    await page.click('#shareMenu [data-share="web"]');
    const link = await page.evaluate(() => navigator.clipboard.readText()).catch(() => '');
    check(/two-degrees\?c=New/.test(link) && !/39\.7/.test(link), 'a shared link leaves out where you are');
    await page.click('#moreBtn');
    check(await page.getAttribute('#moreMenu [data-act="locate"]', 'aria-checked') === 'true', 'the ⋯ menu shows Use My Location on');
    await page.click('#moreMenu [data-act="locate"]');
    const after = await page.$$eval('.chip[data-i]', (els) => els.filter((e) => e.querySelector('svg.here')).length);
    check(after === 0 && (await page.evaluate(() => localStorage.getItem('twodegrees.useLocation'))) === 'false', 'turning it off removes it, and stays off');
    await context.close();
  }

  // Where you are matches a saved city: one chip, labelled with the arrow, not two.
  {
    const context = await newContext(browser, { viewport: { width: 390, height: 844 }, permissions: ['geolocation'], geolocation: { latitude: 51.5074, longitude: -0.1278 } });
    const page = await context.newPage();
    await page.goto(PAGE);
    await page.waitForSelector('#askLoc:not([hidden])', { timeout: 10000 }).catch(() => {});
    await page.click('#askLocYes');
    await page.waitForSelector('.chip svg.here', { timeout: 30000 }).catch(() => {});
    const chips = await page.$$eval('.chip[data-i]', (els) => els.map((e) => (e.querySelector('svg.here') ? '➤' : '') + e.querySelector('.n').dataset.n));
    check(chips.length === 3 && chips.filter((c) => c.startsWith('➤')).length === 1,
      `in London with London saved: one London chip, marked as where you are (${chips.join(', ')})`);
    await context.close();
  }

  // Not Now: turned off, never asked again.
  {
    const context = await newContext(browser, { viewport: { width: 390, height: 844 }, permissions: ['geolocation'], geolocation: { latitude: 39.7392, longitude: -104.9847 } });
    const page = await context.newPage();
    await page.goto(PAGE);
    await page.waitForSelector('#askLoc:not([hidden])', { timeout: 10000 }).catch(() => {});
    await page.click('#askLocNo');
    await page.reload();
    await page.waitForSelector('.temps');
    await page.waitForTimeout(1500);
    check(!(await page.isVisible('#askLoc')) && (await page.$$('.chip svg.here')).length === 0 && (await page.evaluate(() => localStorage.getItem('twodegrees.useLocation'))) === 'false',
      'Not Now turns it off, and the question isn’t asked again');
    await context.close();
  }

  // Widget mode (app?widgets, shown on the product page): the widgets, live, at every width.
  for (const [vp, w, h] of VIEWPORTS) {
    const context = await newContext(browser, { viewport: { width: w, height: h } });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    await page.goto(PAGE + '?widgets');
    await page.waitForSelector('.w.large .wd-row');
    await page.waitForSelector('.w.small.b .wn-temp');   // the second city loads after the first
    const t = (what) => `${vp} widgets: ${what}`;
    const r = await page.evaluate(() => {
      const problems = [];
      for (const e of document.querySelectorAll('.w *')) {
        if (!e.children.length && e.scrollWidth > e.clientWidth + 1 && getComputedStyle(e).textOverflow !== 'ellipsis') problems.push(`clipped "${e.textContent.trim().slice(0, 20)}"`);
      }
      for (const wd of document.querySelectorAll('.w')) if (wd.scrollHeight > wd.clientHeight + 1) problems.push(`${wd.className} is too short for its content`);
      for (const row of document.querySelectorAll('.wd-row')) {
        const q = (s) => row.querySelector(s).getBoundingClientRect();
        const fill = q('.wd-bar i'), lo = q('.wd-lo'), hi = q('.wd-hi'), track = q('.wd-track');
        if (Math.abs(lo.right - fill.left) > 1 || Math.abs(hi.left - fill.right) > 1) problems.push('a low/high is not at the end of its bar');
        if (lo.left < track.left - 0.5 || hi.right > track.right + 0.5) problems.push('a low/high runs out of its row');
      }
      if (document.documentElement.scrollWidth > innerWidth) problems.push('widgets scroll sideways');
      return {
        problems,
        sizes: [...document.querySelectorAll('.w')].map((e) => e.className.replace('w ', '')),
        panelShown: getComputedStyle(document.querySelector('main.panel')).display !== 'none',
        units: [...document.querySelectorAll('.w.small .wn-temp small')].map((e) => e.textContent.slice(-1)),
        skies: [...document.querySelectorAll('.w')].map((e) => /^linear-gradient\(rgb/.test(getComputedStyle(e).backgroundImage) && getComputedStyle(e, '::before').content === 'none' && getComputedStyle(e.querySelector('.wn-city')).color === 'rgb(255, 255, 255)'),
        raised: [...document.querySelectorAll('.wn-temp')].every((e) => /^°[FC]$/.test(e.querySelector('sup').textContent)),
        days: document.querySelectorAll('.w.large .wd-row').length,
      };
    });
    check(r.sizes.join(',') === 'large,medium,small a,small b' && !r.panelShown, t(`large, medium and two small widgets, without the app (${r.sizes.join(', ')})`));
    check(r.units.length === 2 && r.units[0] !== r.units[1], t(`the two small widgets show different units large (${r.units.join(', ')})`));
    check(r.skies.length === 4 && r.skies.every(Boolean) && r.raised && r.days === 6, t(`each widget sits on its city's sky, in white, the unit raised beside the reading, six days on the large one (${r.skies.join(', ')}; ${r.days} days)`));
    check(r.problems.length === 0 && errors.length === 0, t('layout') + (r.problems.length || errors.length ? ` — ${[...r.problems, ...errors].join('; ')}` : ''));
    await context.close();
  }

  await browser.close();
  const summary = `${failed === 0 ? 'ALL PASSED' : failed + ' FAILED'} (${passed} passed)`;
  console.log([summary, ...results].join('\n'));
  if (SHOTS) fs.writeFileSync(path.join(SHOTS, 'web-report.txt'), [summary, ...results].join('\n'));
  process.exit(failed ? 1 : 0);
})();
