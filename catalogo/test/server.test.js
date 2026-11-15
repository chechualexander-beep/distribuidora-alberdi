import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createRequire } from 'node:module';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const require = createRequire(import.meta.url);
const { crearServidor, leerReglasHeaders, headersPara } = require('../server.cjs');

// CSP exigida por el proyecto, escrita a mano a propósito: si alguien la cambia en _headers, este test avisa.
const CSP_ESPERADA =
  "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

const HEADERS_REALES = readFileSync(new URL('../src/_headers', import.meta.url), 'utf8');

let raiz;
let servidor;
let base;
let servidorCatalogo;
let baseCatalogo;

function escuchar(s) {
  return new Promise((resolve) => s.listen(0, '127.0.0.1', () => resolve(`http://127.0.0.1:${s.address().port}`)));
}

/** GET crudo: no normaliza "..", así probamos el servidor y no al cliente. */
function pedirCrudo(ruta, metodo = 'GET') {
  const { port } = servidor.address();
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, path: ruta, method: metodo }, (res) => {
      const trozos = [];
      res.on('data', (t) => trozos.push(t));
      res.on('end', () => resolve({ estado: res.statusCode, headers: res.headers, cuerpo: Buffer.concat(trozos).toString('utf8') }));
    });
    req.on('error', reject);
    req.end();
  });
}

before(async () => {
  raiz = mkdtempSync(join(tmpdir(), 'vitrina-test-'));
  mkdirSync(join(raiz, 'fonts'));
  writeFileSync(join(raiz, '_headers'), HEADERS_REALES);
  writeFileSync(join(raiz, 'index.html'), '<!doctype html><title>x</title>');
  writeFileSync(join(raiz, 'catalogo.json'), '{"normal":true}');
  writeFileSync(join(raiz, 'catalogo.500.json'), '{"grande":true}');
  writeFileSync(join(raiz, 'app.js'), 'export {};');
  writeFileSync(join(raiz, 'fonts', 'a.woff2'), 'woff2');
  writeFileSync(join(raiz, 'secreto.txt'), 'no salir');
  // Un archivo fuera de la raíz, para probar el path traversal.
  mkdirSync(join(raiz, 'publico'));
  writeFileSync(join(raiz, 'publico', '_headers'), HEADERS_REALES);
  writeFileSync(join(raiz, 'publico', 'index.html'), 'dentro');
  writeFileSync(join(raiz, 'publico', 'img.png'), 'png');

  servidor = crearServidor({ raiz: join(raiz, 'publico') });
  base = await escuchar(servidor);

  servidorCatalogo = crearServidor({ raiz, catalogo: 'catalogo.500.json' });
  baseCatalogo = await escuchar(servidorCatalogo);
});

after(async () => {
  await new Promise((r) => servidor.close(r));
  await new Promise((r) => servidorCatalogo.close(r));
  rmSync(raiz, { recursive: true, force: true });
});

test('src/_headers contiene exactamente la CSP exigida', () => {
  const reglas = leerReglasHeaders(HEADERS_REALES);
  const csp = headersPara(reglas, '/index.html').find((h) => h.nombre === 'Content-Security-Policy');
  assert.equal(csp.valor, CSP_ESPERADA);
  assert.doesNotMatch(csp.valor, /unsafe-inline|unsafe-eval/);
});

test('leerReglasHeaders y headersPara: comodines y acumulación', () => {
  const reglas = leerReglasHeaders('# comentario\n/*\n  A: 1\n\n/x.json\n  B: 2\n  A: 3\n/fonts/*\n  C: 4\n');
  assert.deepEqual(headersPara(reglas, '/x.json'), [
    { nombre: 'A', valor: '1, 3' },
    { nombre: 'B', valor: '2' },
  ]);
  assert.deepEqual(headersPara(reglas, '/fonts/a.woff2'), [
    { nombre: 'A', valor: '1' },
    { nombre: 'C', valor: '4' },
  ]);
  assert.deepEqual(headersPara(reglas, '/otra'), [{ nombre: 'A', valor: '1' }]);
});

test('GET / sirve index.html con la CSP y headers de seguridad', async () => {
  const r = await pedirCrudo('/');
  assert.equal(r.estado, 200);
  assert.equal(r.cuerpo, 'dentro');
  assert.match(r.headers['content-type'], /^text\/html; charset=utf-8/);
  assert.equal(r.headers['content-security-policy'], CSP_ESPERADA);
  assert.equal(r.headers['x-content-type-options'], 'nosniff');
});

test('la CSP también viaja en los 404', async () => {
  const r = await pedirCrudo('/no-existe.js');
  assert.equal(r.estado, 404);
  assert.equal(r.headers['content-security-policy'], CSP_ESPERADA);
});

test('tipos MIME', async () => {
  const { port } = servidorCatalogo.address();
  const pedir = (ruta) => fetch(`http://127.0.0.1:${port}${ruta}`);
  assert.match((await pedir('/app.js')).headers.get('content-type'), /^text\/javascript/);
  assert.match((await pedir('/catalogo.500.json')).headers.get('content-type'), /^application\/json/);
  assert.equal((await pedir('/fonts/a.woff2')).headers.get('content-type'), 'font/woff2');
});

test('caché: catalogo.json no-cache y fuentes immutable', async () => {
  const { port } = servidorCatalogo.address();
  const cat = await fetch(`http://127.0.0.1:${port}/catalogo.500.json`);
  const normal = await fetch(`http://127.0.0.1:${port}/app.js`);
  const fuente = await fetch(`http://127.0.0.1:${port}/fonts/a.woff2`);
  assert.equal(cat.headers.get('cache-control'), 'no-cache');
  assert.equal(normal.headers.get('cache-control'), 'no-cache');
  assert.match(fuente.headers.get('cache-control'), /immutable/);
});

test('path traversal bloqueado (con y sin codificar)', async () => {
  const intentos = [
    '/../secreto.txt',
    '/..%2fsecreto.txt',
    '/%2e%2e/secreto.txt',
    '/%2e%2e%2fsecreto.txt',
    '/..\\secreto.txt',
    '/publico/../../secreto.txt',
    '/%2e%2e/%2e%2e/etc/passwd',
  ];
  for (const ruta of intentos) {
    const r = await pedirCrudo(ruta);
    assert.notEqual(r.estado, 200, ruta);
    assert.ok(!r.cuerpo.includes('no salir'), ruta);
  }
  const malCodificado = await pedirCrudo('/%E0%A4%A');
  assert.equal(malCodificado.estado, 400);
});

test('_headers no se sirve', async () => {
  const { port } = servidorCatalogo.address();
  const r = await fetch(`http://127.0.0.1:${port}/_headers`);
  assert.equal(r.status, 404);
});

test('solo GET y HEAD', async () => {
  const post = await pedirCrudo('/', 'POST');
  assert.equal(post.estado, 405);
  const head = await pedirCrudo('/img.png', 'HEAD');
  assert.equal(head.estado, 200);
  assert.equal(head.cuerpo, '');
  assert.equal(head.headers['content-type'], 'image/png');
});

test('VITRINA_CATALOGO: /catalogo.json sirve el archivo indicado', async () => {
  const r = await fetch(`${baseCatalogo}/catalogo.json`);
  assert.equal(await r.text(), '{"grande":true}');
  const normal = await fetch(`${base}/img.png`);
  assert.equal(normal.status, 200);
});

test('VITRINA_CATALOGO rechaza nombres con carpetas', () => {
  assert.throws(() => crearServidor({ raiz, catalogo: '../x.json' }));
  assert.throws(() => crearServidor({ raiz, catalogo: 'a/b.json' }));
  assert.throws(() => crearServidor({ raiz, catalogo: 'x.txt' }));
});
