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
const FOOTER = 'Made by Bradley Cowdrey. Free. Forever. · bradcowdrey.com ↗';

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

// Layout: sibling blocks inside the panel must not overlap, and key text must not be clipped.
async function layoutProblems(page) {
  return page.evaluate(() => {
    const problems = [];
    const blocks = [...document.querySelectorAll('.panel > *')].filter((e) => !e.hidden && e.offsetParent !== null && getComputedStyle(e).position !== 'fixed');
    for (let i = 1; i < blocks.length; i++) {
      const a = blocks[i - 1].getBoundingClientRect(), b = blocks[i].getBoundingClientRect();
      if (b.top < a.bottom - 0.5) problems.push(`${blocks[i].className || blocks[i].tagName} overlaps ${blocks[i - 1].className || blocks[i - 1].tagName} by ${(a.bottom - b.top).toFixed(1)}px`);
    }
    for (const sel of ['.hdr h1', '.place h2', '.stat .v', '.stat .s', '.day .d', '.foot .brand', '#statusText', '.chip', '.alert b', '.alert .m', '.soon-line', '#soonAside',
      '.dt .eyebrow', '.dt .dv', '.dt .ds', '.dt .dn', '.mapcard p', '.mapcard .pill', '.mapcard .credit']) {
      for (const e of document.querySelectorAll(sel)) {
        if (e.offsetParent === null || getComputedStyle(e).clipPath === 'inset(50%)') continue;   // hidden, or visually hidden on purpose
        if (e.scrollWidth > e.clientWidth + 1 && getComputedStyle(e).textOverflow !== 'ellipsis') problems.push(`${sel} clipped ("${e.textContent.trim().slice(0, 30)}")`);
      }
    }
    // Open forecast: each low and high sits right at its end of the bar, inside the row, and the scale's labels sit over its ticks.
    for (const day of document.querySelectorAll('#days:not([hidden]) .day')) {
      const r = (s) => day.querySelector(s).getBoundingClientRect();
      const fill = r('.bar i'), lo = r('.lo'), hi = r('.hi'), track = r('.track'), name = day.querySelector('.d').textContent;
      if (Math.abs(lo.right - fill.left) > 1 || Math.abs(hi.left - fill.right) > 1) problems.push(`${name}: low/high labels aren't at the ends of the bar`);
      if (lo.left < track.left - 0.5 || hi.right > track.right + 0.5) problems.push(`${name}: a low/high label runs out of the row`);
    }
    const firstRow = document.querySelector('#days:not([hidden]) .day');
    if (firstRow) {
      const lines = [...firstRow.querySelectorAll('.bar s')].map((s) => s.getBoundingClientRect().left + 0.5);
      const labels = [...document.querySelectorAll('#dayTicks span')].map((s) => { const b = s.getBoundingClientRect(); return b.left + b.width / 2; });
      if (lines.length !== labels.length || labels.some((x, i) => Math.abs(x - lines[i]) > 1)) problems.push('5-day scale labels are not over their ticks');
    }
    const range = document.querySelector('.days-head .range'), title = document.querySelector('#daysTitle');
    if (range && range.offsetParent !== null && range.getBoundingClientRect().left < title.getBoundingClientRect().right - 0.5) problems.push('5-day range runs into the "5-day forecast" title');
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
    for (const e of sheet.querySelectorAll('.sh-head, .tile, svg.chart, .facts dt, .facts dd')) {
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
    check(await page.getAttribute('.status a', 'href') === 'https://open-meteo.com/', t('Open-Meteo credit links to open-meteo.com'));

    // 5-day accordion: closed on open, opens, closes.
    check(await page.getAttribute('#daysToggle', 'aria-expanded') === 'false' && await page.isHidden('#days'), t('5-day forecast starts closed'));
    check(/°F · .*°C/.test(await page.textContent('#dayTicks')), t('closed forecast shows the range in both units'));
    await page.click('#daysToggle');
    check(await page.isVisible('#days') && (await page.$$('#days .day')).length === 5, t('opening shows 5 day rows'));
    check((await page.$$('#dayTicks span')).length >= 1, t('open forecast shows scale ticks'));
    const dots = await page.$$('#days .bar u');
    check(dots.length === 1, t('one "now" dot, on today'));
    await page.click('#daysToggle');
    check(await page.isHidden('#days'), t('clicking again closes it'));

    // Units.
    await page.click('#unitC');
    check((await page.textContent('.temps .primary sup')).includes('°C') && (await page.textContent('.temps .secondary sup')).includes('°F'), t('°C makes Celsius large, Fahrenheit beside it'));
    check(await page.getAttribute('#unitC', 'aria-pressed') === 'true', t('°C button reports pressed'));
    await page.click('#unitF');
    check((await page.textContent('.temps .primary sup')).includes('°F'), t('°F switches back'));
    const label = await page.getAttribute('.temps', 'aria-label');
    check(/degrees Fahrenheit, -?\d+ Celsius/.test(label || ''), t('screen readers hear both units'));
    check((await page.$$('.hour[role="img"][aria-label]')).length === 24, t('24 labelled hours'));

    // More detail tiles: each one present with a value. Air quality and the archive (normals) answer after
    // the forecast, so wait for them as a visitor would; tiles without data show a dash, so every city has the same tiles.
    await page.waitForSelector('.dt[data-tile="aqi"] .aqbar', { timeout: 30000 }).catch(() => {});
    await page.waitForFunction(() => /Normal high/.test((document.querySelector('.dt[data-tile="normal"]') || {}).textContent || ''), null, { timeout: 30000 }).catch(() => {});
    const tiles = await page.$$eval('.dt', (els) => Object.fromEntries(els.map((e) => [e.dataset.tile, e.querySelector('.dv').textContent.trim() + ' | ' + (e.querySelector('.dn') || { textContent: '' }).textContent.trim()])));
    const expect = {
      visibility: /^\d+(\.\d)? mi \| (Clear view|Haze|Fog)$/, cloud: /^\d+% \| (No cloud at any height|Cloud at several heights|Mostly low cloud|Mostly mid-level cloud|Mostly high, thin cloud)\.$/,
      precip: /^(0|\d+\.\d\d) in \| (None expected|Expected in the next 24 hours: .+ in)$/,
      moon: /^(New Moon|Waxing Crescent|First Quarter|Waxing Gibbous|Full Moon|Waning Gibbous|Last Quarter|Waning Crescent) \| (Full|New) moon (today|tomorrow|in \d+ days)\.$/,
      aqi: /^\d+ (Good|Moderate|Unhealthy for Sensitive Groups|Unhealthy|Very Unhealthy|Hazardous) \| (Better than yesterday|Worse than yesterday|About the same as yesterday|Mostly .+)(\. Pollen: [a-z ]+\.)?$/,
      normal: /^(About normal|\d+° (above|below) normal) \| Normal high -?\d+°F · -?\d+°C, low -?\d+°F · -?\d+°C$/,
    };
    for (const [k, re] of Object.entries(expect)) check(re.test(tiles[k] || ''), t(`${k} tile shows a value (${tiles[k]})`));
    check(/^(\d+ mph|Gusts to \d+\u00A0mph)$/.test((await page.textContent('.stat:nth-child(3) .s')).trim()) || /km\/h$/.test(await page.textContent('.stat:nth-child(3) .s')),
      t(`wind shows km/h beside mph, or the gusts (${(await page.textContent('.stat:nth-child(3)')).trim()})`));
    const map = await page.getAttribute('#mapLink', 'href');
    check(/^https:\/\/bradleycowdrey\.github\.io\/two-degrees\/radar\.html\?lat=40\.713&lon=-74\.006&z=7&units=F$/.test(map) && await page.getAttribute('#mapLink', 'target') === '_blank',
      t(`Rain map opens the map page at the city, in a new tab (${map})`));

    // Day detail: a day row opens it, with three charts; previous/next; Escape closes it and focus goes back.
    await page.click('#daysToggle');
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
    await page.keyboard.press('Escape');
    check(await page.isHidden('#sheetBack') && await page.evaluate(() => document.activeElement.dataset.day) === '0', t('Escape closes the day detail, back on its row'));
    await page.click('#daysToggle');
    await page.evaluate(() => scrollTo(0, 0));

    // Switch city. Selecting a chip must not move any chip or the Add | Edit controls.
    const chipBoxes = () => page.$$eval('.chip[data-i], #addBtn', (els) => els.map((e) => { const r = e.getBoundingClientRect(); return [r.x, r.y, r.width].map((v) => v.toFixed(1)).join(','); }).join(' '));
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
      for (const open of [false, true]) {
        if (open !== (await page.getAttribute('#daysToggle', 'aria-expanded') === 'true')) await page.click('#daysToggle');
        const problems = await layoutProblems(page);
        check(problems.length === 0, t(`${size}, forecast ${open ? 'open' : 'closed'}: layout${problems.length ? ' — ' + problems.join('; ') : ' clean'}`));
        if (SHOTS) await page.screenshot({ path: path.join(SHOTS, `web-${vp}-${i}-${size}-${open ? 'open' : 'closed'}.png`), fullPage: true });
        if (open) {
          await page.click('#days [data-day="1"]');
          await page.waitForSelector('#sheet svg.chart');
          const inSheet = await sheetProblems(page);
          check(inSheet.length === 0, t(`${size}, day detail: layout${inSheet.length ? ' — ' + inSheet.join('; ') : ' clean'}`));
          if (SHOTS) await page.screenshot({ path: path.join(SHOTS, `web-${vp}-${i}-${size}-day.png`) });
          await page.keyboard.press('Escape');
        }
      }
    }
    await setSize(page, 'medium');

    // Persistence: settings survive a reload; the forecast is closed again.
    await page.click('#unitC');
    await page.reload();
    await page.waitForSelector('.temps');
    check((await page.textContent('.temps .primary sup')).includes('°C'), t('unit choice survives a reload'));
    check((await page.$$('.chip[data-i]')).length === 1, t('saved cities survive a reload'));
    check(await page.getAttribute('#daysToggle', 'aria-expanded') === 'false', t('forecast is closed again after a reload'));

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
    const wind = () => page.$eval('.stat:nth-child(3)', (e) => e.querySelector('.v').textContent.trim() + ' / ' + e.querySelector('.s').textContent.trim());
    check(/mph \/ /.test(await wind()) && /in \/ .*mm$/.test(await tile('precip')), `units: Automatic with °F is mph and in (${await wind()}; ${await tile('precip')})`);
    await page.click('#unitC');
    check(/km\/h \/ /.test(await wind()) && /mm \/ .*in$/.test(await tile('precip')), `units: Automatic with °C is km/h and mm (${await wind()}; ${await tile('precip')})`);
    const pick = async (attr) => { await page.click('#moreBtn'); await page.click(`#moreMenu [${attr}]`); };
    await pick('data-wind-unit="ms"');
    check(/^\d+ m\/s \/ /.test(await wind()) && / km \/ $/.test(await tile('visibility')), `Wind: m/s stands alone (${await wind()})`);
    await pick('data-wind-unit="kn"');
    check(/^\d+ kn \/ /.test(await wind()), `Wind: knots (${await wind()})`);
    await pick('data-wind-unit="mph"');
    check(/^\d+ mph \/ (\d+ km\/h|Gusts to \d+\u00A0mph)$/.test(await wind()) && / mi \/ $/.test(await tile('visibility')), `Wind: mph, with km/h beside it, and visibility in miles (${await wind()}; ${await tile('visibility')})`);
    await pick('data-rain-unit="in"');
    check(/^(0|\d+\.\d\d) in \/ (0|\d+(\.\d)?) mm$/.test(await tile('precip')), `Rain: in, with mm beside it (${await tile('precip')})`);
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
    const order = await page.evaluate(() => { const a = document.querySelector('#alerts').getBoundingClientRect(), n = document.querySelector('#now').getBoundingClientRect(); return a.bottom <= n.top; });
    check(order, 'alerts sit above the current conditions');
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
    await page.click('#daysToggle');
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
    check(shown === 'aqi,normal,visibility,precip,cloud,sunrise,sunset,moon' && dashes === '–,–' && await page.isHidden('#alerts'), `live: failed air quality and archive keep their tiles with a dash, and NWS shows no alerts (${shown}; ${dashes})`);
    check(/Updated/.test(await page.textContent('#statusText')), 'live: the forecast itself still shows as live');
    await page.click('#daysToggle');
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
    check(/45 Moderate/.test(aq) && /European AQI/.test(aq) && /Mostly PM2\.5/.test(aq), `London's air quality is on the European scale, with the main pollutant (${aq})`);
    check(/Pollen: grass high\./.test(aq) && (await page.$$('.dt[data-tile="pollen"]')).length === 0, `pollen is a line on the air quality tile, not a tile of its own (${aq})`);
    check(await page.$$eval('.dt', (els) => els.length) === 8, 'London has the same eight tiles as New York');
    const sun = await page.textContent('.dt[data-tile="sunset"]').catch(() => '');
    check(/\d:\d\d [AP]M/.test(sun) && /(Great|Good) colour likely|Some colour possible|Little colour expected/.test(sun), `the sunset tile gives the time and how colourful it'll be (${sun.replace(/\s+/g, ' ')})`);
    const rules = await page.evaluate(() => [[0, 20, 50], [20, 0, 50], [0, 0, 0], [0, 95, 95], [80, 30, 30]].map(([l, m, h]) => __twoDegreesTest.skyRule(l, m, h, 0, 2, 24000).r).join(','));
    const nm = await page.evaluate(() => [__twoDegreesTest.moonNext(0.5 - 1 / 29.53), __twoDegreesTest.moonNext(0)].join(' | '));
    check(nm === 'Full moon tomorrow. | New moon today.', `the moon tile says when the next full or new moon is (${nm})`);
    check(rules === '3,2,1,1,0', `sky colour: high cloud great, some low cloud good, clear or overcast fair, low cloud poor (${rules})`);
    await page.evaluate(() => __twoDegreesTest.inject('aq', { us: null, eu: null, pollen: null }));
    check(await page.$eval('.dt[data-tile="aqi"] .dv', (e) => e.textContent.trim()) === '–' && await page.$$eval('.dt', (els) => els.length) === 8, 'no air quality reading: its tile shows a dash and the count stays eight');
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

  // Widget mode (app?widgets, shown on the product page): the Mac widgets, live, at every width.
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
      };
    });
    check(r.sizes.join(',') === 'large,medium,small a,small b' && !r.panelShown, t(`large, medium and two small widgets, without the app (${r.sizes.join(', ')})`));
    check(r.units.length === 2 && r.units[0] !== r.units[1], t(`the two small widgets show different units large (${r.units.join(', ')})`));
    check(r.problems.length === 0 && errors.length === 0, t('layout') + (r.problems.length || errors.length ? ` — ${[...r.problems, ...errors].join('; ')}` : ''));
    await context.close();
  }

  await browser.close();
  const summary = `${failed === 0 ? 'ALL PASSED' : failed + ' FAILED'} (${passed} passed)`;
  console.log([summary, ...results].join('\n'));
  if (SHOTS) fs.writeFileSync(path.join(SHOTS, 'web-report.txt'), [summary, ...results].join('\n'));
  process.exit(failed ? 1 : 0);
})();
