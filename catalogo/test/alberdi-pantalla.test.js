// Flujo de Alberdi en la pantalla real (modo demo: sin red, confirmación simulada).
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { cpSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buscarNavegador, abrirNavegador } from './helpers/navegador.js';
import { catalogoDemo } from './helpers/catalogos.js';

const require = createRequire(import.meta.url);
const { crearServidor } = require('../server.cjs');
const ejecutable = buscarNavegador();
const opciones = ejecutable ? {} : { skip: 'no hay Edge/Chrome instalado (VITRINA_NAVEGADOR para indicar uno)' };
const esperar = (ms) => new Promise((r) => setTimeout(r, ms));
let raiz, servidor, base, navegador;

before(async () => {
  if (!ejecutable) return;
  raiz = mkdtempSync(join(tmpdir(), 'alberdi-pantalla-'));
  cpSync(new URL('../src/', import.meta.url), raiz, { recursive: true });
  writeFileSync(join(raiz, 'catalogo.json'), JSON.stringify(catalogoDemo()));
  servidor = crearServidor({ raiz });
  await new Promise((r) => servidor.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${servidor.address().port}/`;
  navegador = await abrirNavegador(ejecutable);
});

after(async () => {
  if (!ejecutable) return;
  await navegador?.cerrar();
  await new Promise((r) => servidor.close(r));
  rmSync(raiz, { recursive: true, force: true });
});

test('confirmar pedido: saludo, botón Confirmar, éxito y carrito vacío', opciones, async () => {
  await navegador.abrir(base);
  assert.equal(await navegador.evaluar("document.querySelector('.saludo').textContent"), 'Hola, Cliente de prueba');
  assert.equal(await navegador.evaluar("!!document.querySelector('img.logo')"), true);
  await navegador.evaluar("document.querySelectorAll('.btn-mas')[0].click()");
  await navegador.evaluar("document.querySelectorAll('.btn-mas')[0].click()");
  await navegador.evaluar("location.hash = '#/pedido'");
  await esperar(200);
  assert.equal(await navegador.evaluar("document.querySelector('.btn-enviar').textContent"), 'Confirmar pedido');
  assert.equal(await navegador.evaluar("document.querySelector('a[href^=\"https://wa.me\"]')"), null, 'sin WhatsApp');
  await navegador.evaluar("document.querySelector('#aclaracion').value = 'Después de las 10'");
  await navegador.evaluar("document.querySelector('.btn-enviar').click()");
  await esperar(700);
  const r = JSON.parse(
    await navegador.evaluar(`JSON.stringify({
      exito: document.querySelector('[role=status] h2')?.textContent ?? null,
      exitoVisible: !document.querySelector('[role=status] h2')?.closest('[hidden]'),
      barraOculta: document.querySelector('#pantalla-inicio .barra').hidden,
      pendiente: sessionStorage.getItem('alberdi-pendiente:demo'),
    })`),
  );
  assert.equal(r.exito, '¡Recibimos tu pedido!');
  assert.equal(r.exitoVisible, true);
  assert.equal(r.barraOculta, true);
  assert.equal(r.pendiente, null);
});

test('con un pedido sin confirmar, el carrito no se cambia y el botón ofrece reintentar', opciones, async () => {
  await navegador.abrir(base);
  await navegador.evaluar(`sessionStorage.setItem('alberdi-pendiente:demo', JSON.stringify({
    p_solicitud_id: '11111111-1111-4111-8111-111111111111', p_items: [], p_observacion: '' }))`);
  await navegador.abrir(base);
  await navegador.evaluar("document.querySelectorAll('.btn-mas')[0].click()");
  await esperar(200);
  assert.equal(await navegador.evaluar('location.hash'), '#/pedido');
  assert.equal(await navegador.evaluar("document.querySelector('.btn-enviar').textContent"), 'Reintentar confirmación');
  await navegador.evaluar("sessionStorage.clear()");
});
