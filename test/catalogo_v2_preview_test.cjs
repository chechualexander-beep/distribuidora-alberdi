'use strict';
const assert = require('node:assert/strict');
const { mkdir } = require('node:fs/promises');
const { resolve } = require('node:path');
const { once } = require('node:events');
const { chromium } = require('playwright');
const { createPreviewServer } = require('../catalogo-v2-preview/server.cjs');

async function main() {
  const server = createPreviewServer().listen(0, '127.0.0.1');
  await once(server, 'listening');
  const origin = 'http://127.0.0.1:' + server.address().port;
  let browser;
  const screenshots = process.env.CATALOGO_PREVIEW_EVIDENCIA;
  const capture = async (page, name) => {
    if (screenshots) await page.screenshot({ path: resolve(screenshots, name) });
  };
  const external = [];
  try {
    if (screenshots) await mkdir(screenshots, { recursive: true });
    browser = await chromium.launch({
      executablePath: process.env.CATALOGO_PREVIEW_CHROME,
      headless: true,
    });
    const context = await browser.newContext({ viewport: { width: 390, height: 900 }, hasTouch: true });
    await context.route('**/*', route => {
      const url = new URL(route.request().url());
      if (url.origin === origin) return route.continue();
      external.push(url.origin);
      return route.abort();
    });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const noOverflow = () => page.evaluate(() =>
      document.documentElement.scrollWidth === document.documentElement.clientWidth);
    await page.goto(origin);
    await page.locator('#products [data-product]').first().waitFor();
    assert.equal(await noOverflow(), true);
    assert.equal(await page.locator('#promo-rail article').count(), 4);
    assert.equal(await page.locator('#featured-rail article').count(), 3);
    assert.equal(await page.locator('#products [data-product=P08] .thumb').innerText(), 'Sin foto');
    assert.equal(await page.locator('#products img').first().getAttribute('loading'), 'lazy');
    const moveRail = id => page.locator(id).evaluate(rail => {
      rail.scrollLeft = rail.scrollWidth;
      return rail.scrollLeft;
    });
    const featuredStart = await page.locator('#featured-rail').evaluate(rail => rail.scrollLeft);
    assert.ok(await moveRail('#promo-rail') > 0);
    assert.equal(await page.locator('#featured-rail').evaluate(rail => rail.scrollLeft), featuredStart);
    assert.ok(await moveRail('#featured-rail') > 0);
    await page.locator('#promo-rail').evaluate(rail => { rail.scrollLeft = 0; });
    await page.locator('#featured-rail').evaluate(rail => { rail.scrollLeft = 0; });
    const promo = page.locator('#promo-rail [data-product=P01]');
    const list = page.locator('#products [data-product=P01]');
    await list.evaluate(row => { row.dataset.testIdentity = 'same-node'; });
    await promo.locator('.plus').click();
    assert.equal(await list.locator('output').innerText(), '1');
    assert.equal(await list.getAttribute('data-test-identity'), 'same-node');
    await page.locator('#featured-rail [data-product=P05] .plus').click();
    assert.equal(await page.locator('#products [data-product=P05] output').innerText(), '1');
    assert.match(await page.locator('#cart-total').innerText(), /5\.010/);
    await capture(page, 'catalogo-390.png');
    await list.locator('.plus').click();
    assert.equal(await promo.locator('output').innerText(), '2');
    await list.locator('.minus').click();
    assert.equal(await promo.locator('output').innerText(), '1');
    await page.locator('#categories').getByRole('button', { name: 'Bebidas' }).click();
    assert.equal(await page.locator('#products article').count(), 2);
    assert.match(await page.locator('#cart-count').innerText(), /· 2/);
    await page.locator('#search').fill('ACEITE');
    assert.equal(await page.locator('#showcase').isVisible(), false);
    assert.equal(await page.locator('#products article').count(), 0);
    await page.locator('#categories').getByRole('button', { name: 'Todos' }).click();
    assert.equal(await page.locator('#products article').count(), 1);
    await page.locator('#search').fill('a');
    await page.evaluate(() => window.scrollTo(0, 250));
    const savedScroll = await page.evaluate(() => scrollY);
    assert.ok(savedScroll > 0);
    await page.locator('#open-cart').click();
    await page.locator('#review-title').waitFor();
    assert.equal(await page.locator('#cart-items article').count(), 2);
    await capture(page, 'carrito-390.png');
    await page.locator('#back').click();
    await page.locator('#quick-title').waitFor();
    assert.equal(await page.locator('#search').inputValue(), 'a');
    assert.equal(await page.evaluate(() => scrollY), savedScroll);
    assert.match(await page.locator('#cart-count').innerText(), /· 2/);
    await page.reload();
    assert.match(await page.locator('#cart-count').innerText(), /· 2/);
    await page.locator('#open-cart').click();
    await page.locator('#confirm').click();
    assert.match(await page.locator('#receipt').innerText(), /Referencia local: [\da-f]{8}/);
    await page.locator('#new-order').click();
    await page.locator('#quick-title').waitFor();
    assert.equal(await page.locator('#open-cart').isDisabled(), true);

    for (const width of [320, 360, 420]) {
      await page.setViewportSize({ width, height: 900 });
      await page.goto(origin);
      assert.equal(await noOverflow(), true, 'desborde a ' + width);
      assert.equal(await page.locator('#promo-rail .plus').first().evaluate(button =>
        button.getBoundingClientRect().height >= 44 && button.getBoundingClientRect().width >= 44), true);
      if (width === 320) await capture(page, 'catalogo-320.png');
    }
    await page.goto(origin + '/?sin-bloques=1');
    assert.equal(await page.locator('#promotions').isVisible(), false);
    assert.equal(await page.locator('#featured').isVisible(), false);
    assert.ok(await page.locator('#products article').count() > 0);
    await page.goto(origin + '/?modo=general');
    assert.equal(await page.locator('#greeting').innerText(), 'Catálogo general');
    assert.equal(await page.locator('.quantity').count(), 0);
    assert.equal(await page.locator('#cart-bar').isVisible(), false);
    const policy = await page.evaluate(() => new Promise(resolve => {
      addEventListener('securitypolicyviolation', event => resolve(event.effectiveDirective), { once: true });
      fetch('/prueba-bloqueo-csp').catch(() => {});
      setTimeout(() => resolve('timeout'), 1500);
    }));
    assert.equal(policy, 'connect-src');
    assert.equal((await fetch(origin + '/catalogo.js')).status, 404);
    assert.equal((await fetch(origin + '/preview.js', { method: 'POST' })).status, 404);
    assert.deepEqual(external, []);
    assert.deepEqual(errors, []);
    console.log('PASS: 320–420 px, carruseles, búsqueda, cantidades, carrito y confirmación ficticia, variantes, CSP y cero solicitudes externas.');
  } finally {
    try { if (browser) await browser.close(); } finally { server.close(); }
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
