import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { armarMeta, escaparHtml, COLORES_TEMA, DESCRIPCION, MARCADOR } from '../tool/meta.mjs';
import { catalogoDemo } from './helpers/catalogos.js';

const require = createRequire(import.meta.url);
const { crearServidor } = require('../server.cjs');

const DESCRIPCION_ESPERADA = 'Mirá todos nuestros productos y hacé tu pedido.';
const lineasDe = (bloque) => bloque.split('\n');
const tiene = (bloque, linea) => lineasDe(bloque).includes(linea);

/* ---------- armarMeta ---------- */

test('lista exacta de etiquetas con urlPublica y foto', () => {
  const bloque = armarMeta({ nombre: 'Kiosco de Ejemplo', urlPublica: 'https://kiosco.ejemplo.com', foto: 'img/p-001.jpg', tema: 'azul' });
  assert.equal(
    bloque,
    [
      '<title>Kiosco de Ejemplo · Catálogo</title>',
      `<meta name="description" content="${DESCRIPCION_ESPERADA}">`,
      '<meta property="og:type" content="website">',
      '<meta property="og:site_name" content="Kiosco de Ejemplo">',
      '<meta property="og:title" content="Catálogo de Kiosco de Ejemplo">',
      `<meta property="og:description" content="${DESCRIPCION_ESPERADA}">`,
      '<meta property="og:locale" content="es_AR">',
      '<meta property="og:url" content="https://kiosco.ejemplo.com">',
      '<meta property="og:image" content="https://kiosco.ejemplo.com/img/p-001.jpg">',
      '<meta name="twitter:card" content="summary_large_image">',
      '<meta name="theme-color" content="#3A4486">',
    ].join('\n'),
  );
  assert.equal(DESCRIPCION, DESCRIPCION_ESPERADA);
});

test('sin urlPublica no hay og:url ni og:image, y la tarjeta es summary', () => {
  const bloque = armarMeta({ nombre: 'Kiosco', foto: 'img/p-001.jpg', tema: 'verde' });
  assert.doesNotMatch(bloque, /og:url|og:image/);
  assert.ok(tiene(bloque, '<meta name="twitter:card" content="summary">'));
  assert.equal(lineasDe(bloque).length, 9);
});

test('con urlPublica pero sin foto: og:url sí, og:image no, tarjeta summary', () => {
  const bloque = armarMeta({ nombre: 'Kiosco', urlPublica: 'https://kiosco.ejemplo.com/' });
  assert.ok(tiene(bloque, '<meta property="og:url" content="https://kiosco.ejemplo.com/">'), 'og:url es la urlPublica tal cual');
  assert.doesNotMatch(bloque, /og:image/);
  assert.ok(tiene(bloque, '<meta name="twitter:card" content="summary">'));
});

test('con urlPublica, la imagen es una URL absoluta (con o sin barra final, con ruta o con query)', () => {
  const imagen = (urlPublica) =>
    lineasDe(armarMeta({ nombre: 'K', urlPublica, foto: 'img/a/b.webp' })).find((l) => l.includes('og:image'));
  const esperada = (url) => `<meta property="og:image" content="${url}">`;
  assert.equal(imagen('https://ejemplo.com'), esperada('https://ejemplo.com/img/a/b.webp'));
  assert.equal(imagen('https://ejemplo.com/'), esperada('https://ejemplo.com/img/a/b.webp'));
  assert.equal(imagen('https://ejemplo.com/kiosco/'), esperada('https://ejemplo.com/kiosco/img/a/b.webp'));
  assert.equal(imagen('http://localhost:4180'), esperada('http://localhost:4180/img/a/b.webp'));
  assert.equal(imagen('https://ejemplo.com/kiosco?v=2'), esperada('https://ejemplo.com/kiosco/img/a/b.webp'));
});

test('ruta de foto insegura: se descarta y no hay og:image', () => {
  const inseguras = [
    '../secreto.jpg', 'img/../../secreto.jpg', '/img/foto.jpg', '//evil.com/foto.jpg', 'img//foto.jpg',
    'https://evil.com/foto.jpg', 'javascript:alert(1)', 'data:image/png;base64,AAAA', 'img\\foto.jpg',
    'img/foto.exe', 'img/foto', '', '   ', null, 42, {},
  ];
  for (const foto of inseguras) {
    const bloque = armarMeta({ nombre: 'K', urlPublica: 'https://ejemplo.com', foto });
    assert.doesNotMatch(bloque, /og:image/, String(foto));
    assert.ok(tiene(bloque, '<meta name="twitter:card" content="summary">'), String(foto));
  }
});

test('urlPublica inválida: no hay og:url ni og:image', () => {
  for (const urlPublica of ['javascript:alert(1)', 'ftp://ejemplo.com', 'ejemplo.com', 'no es una url', '', '   ', 'https://usuario:clave@ejemplo.com', null, undefined, 5]) {
    const bloque = armarMeta({ nombre: 'K', urlPublica, foto: 'img/a.jpg' });
    assert.doesNotMatch(bloque, /og:url|og:image/, String(urlPublica));
  }
});

test('escapa comillas y símbolos en todos los valores', () => {
  const nombre = `Pepe's "Café" <b>&</b> <script>alert(1)</script>`;
  const bloque = armarMeta({ nombre, urlPublica: 'https://ejemplo.com/a?x=1&y="2"', foto: 'img/a.jpg' });
  assert.doesNotMatch(bloque, /<script|<b>|<\/b>/, 'ningún tag del nombre queda sin escapar');
  assert.match(bloque, /Pepe&#39;s &quot;Café&quot; &lt;b&gt;&amp;&lt;\/b&gt; &lt;script&gt;alert\(1\)&lt;\/script&gt;/);
  // Cada atributo content="..." no contiene comillas, < ni > sin escapar.
  for (const linea of lineasDe(bloque)) {
    const m = /^<meta [^>]*?content="(.*)">$/.exec(linea);
    if (m) assert.doesNotMatch(m[1], /["<>]/, linea);
  }
  assert.ok(tiene(bloque, '<meta property="og:url" content="https://ejemplo.com/a?x=1&amp;y=&quot;2&quot;">'));
  assert.equal(escaparHtml(`&<>"'`), '&amp;&lt;&gt;&quot;&#39;');
});

test('nombre con emoji y tildes pasa intacto', () => {
  const bloque = armarMeta({ nombre: 'Kiosco Ñandú 🍬 Panadería' });
  assert.ok(tiene(bloque, '<title>Kiosco Ñandú 🍬 Panadería · Catálogo</title>'));
  assert.ok(tiene(bloque, '<meta property="og:site_name" content="Kiosco Ñandú 🍬 Panadería">'));
  assert.ok(tiene(bloque, '<meta property="og:title" content="Catálogo de Kiosco Ñandú 🍬 Panadería">'));
});

test('theme-color: color del tema; tema inválido o ausente usa verde', () => {
  for (const [tema, color] of Object.entries(COLORES_TEMA)) {
    assert.ok(tiene(armarMeta({ nombre: 'K', tema }), `<meta name="theme-color" content="${color}">`), tema);
  }
  for (const tema of [undefined, null, '', 'violeta', 'ROJO', 5, {}]) {
    assert.ok(tiene(armarMeta({ nombre: 'K', tema }), '<meta name="theme-color" content="#1B6B4A">'), String(tema));
  }
});

test('los colores de los temas coinciden con vitrina.css', () => {
  const css = readFileSync(new URL('../src/vitrina.css', import.meta.url), 'utf8');
  const leidos = { verde: /--acento:\s*(#[0-9A-Fa-f]{6})/.exec(css)[1] };
  for (const t of ['rojo', 'azul', 'ambar', 'alberdi']) {
    leidos[t] = new RegExp(`data-tema="${t}"\\]\\s*\\{\\s*--acento:\\s*(#[0-9A-Fa-f]{6})`).exec(css)[1];
  }
  assert.deepEqual(leidos, { ...COLORES_TEMA });
});

test('falta el nombre: error claro', () => {
  for (const nombre of [undefined, null, '', '   ', 5]) assert.throws(() => armarMeta({ nombre }), TypeError);
  assert.throws(() => armarMeta(), TypeError);
});

test('armarMeta es pura y determinista', () => {
  const entrada = { nombre: 'K', urlPublica: 'https://e.com', foto: 'img/a.jpg', tema: 'rojo' };
  const copia = structuredClone(entrada);
  assert.equal(armarMeta(entrada), armarMeta(entrada));
  assert.deepEqual(entrada, copia);
});

/* ---------- index.html y server.cjs (modo desarrollo) ---------- */

const htmlReal = readFileSync(new URL('../src/index.html', import.meta.url), 'utf8');

test('src/index.html: marcador una sola vez dentro del <head>, antes del <title> genérico', () => {
  assert.equal(htmlReal.split(MARCADOR).length - 1, 1);
  const cabeza = /<head>([\s\S]*)<\/head>/.exec(htmlReal)[1];
  assert.ok(cabeza.includes(MARCADOR));
  assert.ok(cabeza.indexOf(MARCADOR) < cabeza.indexOf('<title>Catálogo</title>'), 'el marcador va antes del título genérico');
  assert.equal(htmlReal.match(/<title>/g).length, 1);
  assert.doesNotMatch(htmlReal, /<meta name="theme-color"/, 'el theme-color lo trae el bloque o lo crea el JS');
  assert.doesNotMatch(htmlReal, /(?:src|href)\s*=\s*["']?(?:https?:)?\/\//i, 'sin recursos externos');
});

let raiz;
let servidor;
let servidorUrl;
const obtener = async (servidorConPuerto, ruta = '/') => {
  const r = await fetch(`http://127.0.0.1:${servidorConPuerto.address().port}${ruta}`);
  return { estado: r.status, headers: r.headers, texto: await r.text() };
};
const escuchar = (s) => new Promise((r) => s.listen(0, '127.0.0.1', r));

before(async () => {
  raiz = mkdtempSync(join(tmpdir(), 'vitrina-meta-'));
  cpSync(new URL('../src/', import.meta.url), raiz, { recursive: true });
  servidor = crearServidor({ raiz });
  servidorUrl = crearServidor({ raiz, urlPublica: 'https://kiosco.ejemplo.com' });
  await escuchar(servidor);
  await escuchar(servidorUrl);
});

after(async () => {
  await new Promise((r) => servidor.close(r));
  await new Promise((r) => servidorUrl.close(r));
  rmSync(raiz, { recursive: true, force: true });
});

test('server.cjs reemplaza el marcador con los datos de catalogo.json (sin urlPublica)', async () => {
  const demo = catalogoDemo();
  writeFileSync(join(raiz, 'catalogo.json'), JSON.stringify(demo));
  const r = await obtener(servidor, '/');
  assert.equal(r.estado, 200);
  assert.doesNotMatch(r.texto, /VITRINA_META/);
  assert.equal(r.texto.match(/<title>/g).length, 1, 'un solo <title>');
  assert.match(r.texto, /<title>Kiosco de Ejemplo · Catálogo<\/title>/);
  assert.match(r.texto, /<meta property="og:title" content="Catálogo de Kiosco de Ejemplo">/);
  assert.match(r.texto, /<meta name="theme-color" content="#1B6B4A">/);
  assert.doesNotMatch(r.texto, /og:url|og:image/);
  assert.match(r.texto, /<meta name="twitter:card" content="summary">/);
  // El resto del HTML no cambió.
  assert.match(r.texto, /<script type="module" src="vitrina\.js"><\/script>/);
});

test('server.cjs con urlPublica: og:url y og:image absolutos con la primera foto', async () => {
  writeFileSync(join(raiz, 'catalogo.json'), JSON.stringify(catalogoDemo()));
  const r = await obtener(servidorUrl, '/index.html');
  assert.match(r.texto, /<meta property="og:url" content="https:\/\/kiosco\.ejemplo\.com">/);
  assert.match(r.texto, /<meta property="og:image" content="https:\/\/kiosco\.ejemplo\.com\/img\/p-001\.svg">/);
  assert.match(r.texto, /<meta name="twitter:card" content="summary_large_image">/);
});

test('server.cjs: nombre con HTML se escapa, el tema se respeta y mantiene CSP y largo correcto', async () => {
  const c = catalogoDemo();
  c.comercio.nombre = '<b>Kiosco</b> & "Co" 🍬';
  c.comercio.tema = 'rojo';
  writeFileSync(join(raiz, 'catalogo.json'), JSON.stringify(c));
  const r = await obtener(servidor, '/');
  assert.doesNotMatch(r.texto, /<b>Kiosco/);
  assert.match(r.texto, /<title>&lt;b&gt;Kiosco&lt;\/b&gt; &amp; &quot;Co&quot; 🍬 · Catálogo<\/title>/);
  assert.match(r.texto, /<meta name="theme-color" content="#9B3A2E">/);
  assert.match(r.headers.get('content-security-policy'), /^default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:/);
  assert.equal(Number(r.headers.get('content-length')), Buffer.byteLength(r.texto, 'utf8'));
});

test('server.cjs: si el catálogo es inválido o no existe, sirve el HTML genérico', async () => {
  writeFileSync(join(raiz, 'catalogo.json'), '{ esto no es json');
  let r = await obtener(servidor, '/');
  assert.equal(r.estado, 200);
  assert.match(r.texto, /<title>Catálogo<\/title>/);
  writeFileSync(join(raiz, 'catalogo.json'), JSON.stringify({ formato: 2 }));
  r = await obtener(servidor, '/');
  assert.match(r.texto, /<title>Catálogo<\/title>/);
});

test('server.cjs: los demás archivos no cambian', async () => {
  const r = await obtener(servidor, '/vitrina.js');
  assert.equal(r.texto, readFileSync(new URL('../src/vitrina.js', import.meta.url), 'utf8'));
});
