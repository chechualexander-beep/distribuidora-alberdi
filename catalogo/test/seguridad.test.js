import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const leer = (ruta) => readFileSync(new URL(`../src/${ruta}`, import.meta.url), 'utf8');

const headers = leer('_headers');
const html = leer('index.html');
const css = leer('vitrina.css');
const js = leer('vitrina.js');
const core = leer('core.js');

const cspHeader = /Content-Security-Policy:\s*(.+)/.exec(headers)[1].trim();
const cspMeta = /<meta http-equiv="Content-Security-Policy" content="([^"]+)"/.exec(html)[1];

test('el <meta> CSP del HTML coincide con el header (menos frame-ancestors, que solo funciona por header)', () => {
  assert.equal(`${cspMeta}; frame-ancestors 'none'`, cspHeader);
});

test('index.html: sin scripts ni estilos inline, sin recursos externos', () => {
  assert.doesNotMatch(html, /<style/i);
  assert.doesNotMatch(html, /\sstyle\s*=/i);
  assert.doesNotMatch(html, /\son[a-z]+\s*=/i);
  assert.doesNotMatch(html, /<script(?![^>]*\ssrc=)/i);
  assert.doesNotMatch(html, /(?:src|href)\s*=\s*["']?(?:https?:)?\/\//i);
});

test('vitrina.css: sin recursos externos ni @import', () => {
  assert.doesNotMatch(css, /@import/);
  assert.doesNotMatch(css, /https?:\/\//);
  const urls = [...css.matchAll(/url\(([^)]+)\)/g)].map((m) => m[1]);
  assert.ok(urls.length >= 5);
  for (const u of urls) assert.match(u, /^fonts\/[\w-]+\.woff2$/, u);
});

test('JS: nada de innerHTML, eval ni escritura de HTML con datos', () => {
  for (const [nombre, codigo] of [['vitrina.js', js], ['core.js', core]]) {
    const sinComentarios = codigo.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
    for (const prohibido of [/\.innerHTML\s*=/, /\.outerHTML\s*=/, /insertAdjacentHTML/, /document\.write/, /\beval\s*\(/, /new Function\(/, /setAttribute\(\s*['"]style['"]/]) {
      assert.doesNotMatch(sinComentarios, prohibido, `${nombre}: ${prohibido}`);
    }
  }
});

test('los colores de tema están solo en vitrina.css', () => {
  for (const color of ['#1B6B4A', '#9B3A2E', '#3A4486', '#8A5A00']) {
    assert.doesNotMatch(js, new RegExp(color, 'i'), `vitrina.js no debe repetir ${color}`);
    assert.doesNotMatch(core, new RegExp(color, 'i'), `core.js no debe repetir ${color}`);
  }
  assert.match(css, /--acento:\s*#1B6B4A/i);
});
