const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

(async () => {
  const response = await fetch(process.env.SPORTS_METADATA_URL);
  assert.equal(response.status, 200);
  const payload = await response.json();
  const out = process.env.TV_OVERHAUL_SCREENSHOTS || path.resolve('test-results/sportsdb');
  fs.mkdirSync(out, {recursive: true});
  const browser = await chromium.launch({channel: 'chrome', headless: true});
  try {
    for (const badgesOnly of [false, true]) {
      const page = await browser.newPage({viewport: {width: 1672, height: 941}, timezoneId: 'Europe/Amsterdam'});
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      await page.route('**/*', route => {
        const url = new URL(route.request().url());
        if (url.pathname.endsWith('/sports-metadata')) return route.fulfill({json: {...payload, events: payload.events.map(event => ({...event, background: badgesOnly ? null : event.background}))}});
        return ['127.0.0.1', 'r2.thesportsdb.com', 'www.thesportsdb.com'].includes(url.hostname) ? route.continue() : route.abort();
      });
      await page.goto('http://127.0.0.1:3109/dev/sportsdb', {waitUntil: 'domcontentloaded', timeout: 120000});
      const selector = badgesOnly ? '.tv-event-teams' : '.tv-event-image > img';
      await page.waitForFunction(selector => [...document.querySelectorAll(selector)].filter(el => getComputedStyle(el).opacity === '1').length >= 3, selector, {timeout: 45000});
      for (const width of [1672, 768, 390]) {
        await page.setViewportSize({width, height: width === 390 ? 844 : 941});
        await page.waitForTimeout(250);
        assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `No overflow ${width}`);
        const container = await page.locator('.tv-event-art').first().boundingBox();
        const images = await page.locator(`${selector} img`).first().count();
        if (badgesOnly && images) {
          const rect = await page.locator(`${selector} img`).first().boundingBox();
          assert.ok(rect.width > 25 && rect.x >= container.x && rect.x + rect.width <= container.x + container.width, 'Crest fits the card');
        }
        await page.screenshot({path: path.join(out, `${badgesOnly ? 'crests' : 'banners'}-${width}.png`)});
      }
      assert.deepEqual(errors, []);
      await page.close();
    }
    console.log(JSON.stringify({passed: true, realFeedEvents: payload.events.length, viewports: [1672,768,390], screenshots: out}));
  } finally { await browser.close(); }
})().catch(error => {console.error(error); process.exitCode = 1;});
