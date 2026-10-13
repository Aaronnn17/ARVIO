// Isolated headless regression test of production components with local-only
// fixtures. Never signs into a real account or makes an external payment.
const { chromium } = require('@playwright/test');
const fs = require('node:fs/promises');
const path = require('node:path');
const assert = require('node:assert/strict');
(async () => {
  const browser = await chromium.launch({ ...(process.platform === 'win32' ? { channel: 'msedge' } : {}), headless: true });
  try {
    const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
    await context.route('**/*', route => new URL(route.request().url()).hostname === '127.0.0.1' ? route.continue() : route.abort());
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto('http://127.0.0.1:3098/');
    await page.getByRole('button', { name: /Keep Premium/ }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByRole('link', { name: /Continue to Ko-fi/ }).waitFor();
    assert.match(await dialog.innerText(), /tester@example.test/);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
    assert.equal(await dialog.evaluate(element => element.scrollWidth > element.clientWidth), false);
    await fs.mkdir(path.resolve('../artifacts/payment-flow-20261013'), { recursive: true });
    await page.screenshot({ path: path.resolve('../artifacts/payment-flow-20261013/checkout-mobile.png') });
    await page.keyboard.press('Escape');
    assert.equal(await page.getByRole('dialog').count(), 0);
    assert.match(await page.locator(':focus').innerText(), /Keep Premium/);
    await page.goto('http://127.0.0.1:3098/?case=delayed-payment');
    await page.getByRole('button', { name: /Keep Premium/ }).click();
    await page.getByRole('link', { name: /Continue to Ko-fi/ }).click();
    await page.bringToFront();
    // Local fixture simulates returning from an external tab; no Ko-fi request
    // is permitted by the test context's network allowlist.
    // Focus can leave before React installs the recovery effect. A return must
    // work even when that first blur was not observed by the listener.
    await page.evaluate(() => { window.dispatchEvent(new Event('focus')); });
    await page.getByText('Membership active', { exact: true }).waitFor({ timeout: 20000 });
    assert.equal(await page.getByRole('link', { name: /Continue to Ko-fi/ }).count(), 0);
    await page.goto('http://127.0.0.1:3098/');
    await page.getByRole('button', { name: /Keep Premium/ }).click();
    await page.getByRole('link', { name: /Continue to Ko-fi/ }).waitFor();
    await dialog.getByRole('button', { name: /Paid with a different email/ }).click();
    await dialog.getByLabel('Ko-fi / PayPal email').fill('billing@example.test');
    await dialog.getByRole('button', { name: 'Send verification code' }).click();
    await dialog.getByLabel('Code sent to your billing email').fill('0000000000000000');
    await dialog.getByRole('button', { name: 'Verify email' }).click();
    await dialog.getByRole('alert').filter({ hasText: /Invalid or expired/ }).waitFor();
    await dialog.getByLabel('Code sent to your billing email').fill('1234567890abcdef');
    await dialog.getByRole('button', { name: 'Verify email' }).click();
    await page.getByText('Membership active', { exact: true }).waitFor();
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.goto('http://127.0.0.1:3098/?case=paywall');
    await page.getByRole('button', { name: 'Subscribe on Ko-fi' }).click();
    await page.getByRole('link', { name: /Continue to Ko-fi/ }).waitFor();
    await page.screenshot({ path: path.resolve('../artifacts/payment-flow-20261013/checkout-desktop.png') });
    assert.deepEqual(errors, []);
    console.log('Payment UI passed: mobile/desktop layout, Escape/focus restore, delayed activation, rejected/valid email verification; all external network blocked.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
