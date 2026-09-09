const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');

(async () => {
  const output = process.env.TV_OVERHAUL_SCREENSHOTS || path.resolve('test-results/tv-overhaul');
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  const errors = [];
  try {
    const page = await browser.newPage({ viewport: { width: 1672, height: 941 } });
    page.on('pageerror', (error) => errors.push(error.message));
    page.on('console', (message) => {
      if (message.type() === 'error' && /hydrat|React|Unhandled/i.test(message.text())) errors.push(message.text());
    });
    await page.route('**/*', route => {
      const url = new URL(route.request().url());
      if (url.pathname === '/api/proxy' && url.searchParams.get('url')?.startsWith('https://example.invalid/sports/catalog/')) {
        return route.fulfill({ json: require('../app/dev/stabilization/sports-artwork.json') });
      }
      return ['127.0.0.1', 'cdn.highfly.dev'].includes(url.hostname) ? route.continue() : route.abort();
    });
    await page.goto('http://127.0.0.1:3109/dev/stabilization', { waitUntil: 'domcontentloaded', timeout: 120_000 });
    await page.locator('[data-fixture-ready="true"]').waitFor({ timeout: 120_000 });
    await page.getByRole('button', { name: 'All Channels', exact: false }).waitFor();
    await page.waitForTimeout(1200);
    await page.screenshot({ path: path.join(output, 'web-01-guide-open.png') });
    await page.getByRole('button', { name: 'Toggle categories' }).click();
    await page.waitForTimeout(240);
    await page.screenshot({ path: path.join(output, 'web-02-guide-closed.png') });
    await page.getByRole('button', { name: 'Toggle categories' }).click();
    await page.getByRole('button', { name: 'Sports', exact: true }).click();
    await page.locator('.tv-event-card').first().waitFor({ timeout: 30_000 });
    await page.locator('.tv-event-art img').first().waitFor();
    await page.locator('.tv-event-art img').first().evaluate(img => img.decode());
    await page.getByRole('button', { name: 'Toggle categories' }).click();
    await page.waitForTimeout(240);
    await page.screenshot({ path: path.join(output, 'web-03-sports-open.png') });
    await page.locator('.tv-event-card').first().focus();
    await page.waitForTimeout(240);
    await page.screenshot({ path: path.join(output, 'web-04-sports-closed.png') });
    const size = await page.locator('.tv-event-art').first().boundingBox();
    assert.ok(Math.abs(size.width / size.height - 2.25) < 0.03, 'Event artwork must keep its wide ratio');
    assert.ok(await page.locator('.tv-event-art img').first().evaluate((img) => img.complete && img.naturalWidth > 0), 'Sports artwork must render');
    await page.locator('.tv-event-card').first().click();
    await page.locator('.tv-event-picker[open]').waitFor();
    await page.screenshot({ path: path.join(output, 'web-05-event-picker.png') });
    await page.locator('.tv-event-source').first().click();
    assert.equal(await page.locator('.tv-event-picker[open]').count(), 0);
    assert.match(await page.locator('.fixture-toast').innerText(), /Selected:/);
    await page.keyboard.press('ArrowLeft');
    assert.equal(await page.locator('.livetv-cats').getAttribute('inert'), null);
    for (const width of [390, 768]) {
      await page.setViewportSize({ width, height: 900 });
      await page.locator('.tv-event-card').first().focus();
      await page.waitForTimeout(250);
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), `No horizontal overflow at ${width}px`);
      await page.screenshot({ path: path.join(output, `web-sports-${width}.png`) });
      await page.locator('.tv-event-card').first().click();
      const picker = await page.locator('.tv-event-picker').boundingBox();
      assert.ok(picker.width <= width, 'Picker must fit');
      await page.keyboard.press('Escape');
    }
    assert.deepEqual(errors, [], 'No uncaught browser errors');
    console.log(JSON.stringify({ passed: true, viewports: [1672, 768, 390], screenshots: output }, null, 2));
  } finally { await browser.close(); }
})().catch((error) => { console.error(error); process.exitCode = 1; });
