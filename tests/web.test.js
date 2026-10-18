// Functional + layout tests for the web app (docs/app.html), run with Playwright:
//   node tests/web.test.js [screenshot-dir]
// Exercises every control at phone, tablet and desktop widths and all five sizes, checks
// results, layout (no overlap, no clipping, no sideways scroll) and accessibility labels.
const path = require('path');
const fs = require('fs');
let playwright;
try { playwright = require('playwright'); } catch { playwright = require(path.join(require('child_process').execSync('npm root -g').toString().trim(), 'playwright')); }

const PAGE = 'file://' + path.resolve(__dirname, '../docs/app.html');
const SHOTS = process.argv[2];
const VIEWPORTS = [['phone', 390, 844], ['tablet', 768, 1024], ['desktop', 1280, 900]];
const SIZES = ['extraSmall', 'small', 'medium', 'large', 'extraLarge'];
const FOOTER = 'Made by Bradley Cowdrey. Free. Forever. · bradcowdrey.com ↗';

let passed = 0, failed = 0;
const results = [];
function check(ok, what) { ok ? passed++ : failed++; results.push(`${ok ? 'PASS' : 'FAIL'} ${what}`); }

async function fresh(browser, w, h, query = '') {
  const context = await browser.newContext({ viewport: { width: w, height: h }, permissions: ['clipboard-read', 'clipboard-write'] });
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
    for (const sel of ['.hdr h1', '.place h2', '.stat .v', '.stat .s', '.day .d', '.foot .brand', '#statusText', '.chip']) {
      for (const e of document.querySelectorAll(sel)) {
        if (e.offsetParent === null) continue;
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

    // Switch city.
    await page.click('.chip[data-i="1"]');
    check((await page.textContent('.place h2')).trim() === 'London' && await page.getAttribute('.chip[data-i="1"]', 'aria-current') === 'true', t('switching to London'));

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

    // City limit.
    for (const q of ['Rome']) { await page.click('#addBtn'); await page.fill('#searchInput', q); await page.keyboard.press('Enter'); }
    check((await page.$$('.chip[data-i]')).length === 5 && await page.isDisabled('#addBtn'), t('limit of 5 cities disables Add'));

    // Edit: remove, can't remove the last one.
    await page.click('#editBtn');
    check(await page.isVisible('.chip-x'), t('Edit shows remove buttons'));
    await page.click('.chip-x[data-x="4"]');
    check((await page.$$('.chip[data-i]')).length === 4 && !(await page.isDisabled('#addBtn')), t('removing a city re-enables Add'));
    while ((await page.$$('.chip[data-i]')).length > 1) await page.click('.chip-x[data-x="0"]');
    check((await page.$$('.chip-x')).length === 0, t('the last city cannot be removed'));
    check(await page.getAttribute('#editBtn', 'aria-pressed') === 'false', t('Edit turns itself off at one city'));

    // Share menu.
    await page.click('#shareBtn');
    check(await page.isVisible('#shareMenu') && (await page.$$('#shareMenu [data-share]')).length >= 3, t('Share opens its menu'));
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
    const reading = await page.evaluate(() => navigator.clipboard.readText()).catch(() => '');
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
    check(chips.length === 5, `malformed link: keeps at most 5 valid cities (${chips.length})`);
    check(!(await page.evaluate(() => window.pwned)) && chips[0].startsWith('<img'), 'malformed link: a city name with HTML is shown as text');
    await context.close();
  }

  // Shared links open with their cities.
  {
    const { context, page } = await fresh(browser, 1280, 900, '?c=Denver~39.739~-104.990|Tokyo~35.676~139.650');
    const chips = await page.$$eval('.chip[data-i]', (els) => els.map((e) => e.textContent.trim()));
    check(chips.length === 2 && chips[0].startsWith('Denver') && chips[1].startsWith('Tokyo'), `shared link opens Denver and Tokyo (${chips.join(', ')})`);
    await context.close();
  }

  // Widget mode (app?widgets, shown on the product page): the Mac widgets, live, at every width.
  for (const [vp, w, h] of VIEWPORTS) {
    const context = await browser.newContext({ viewport: { width: w, height: h } });
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
