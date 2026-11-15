import { test } from 'node:test';
import assert from 'node:assert/strict';
import { rutaDesdeHash, hashDeFoto, resolverRuta, RUTA_INICIO, RUTA_PEDIDO } from '../src/core.js';

const conFoto = { id: 'p-001', nombre: 'Alfajor', miniatura: 'img/p-001.jpg' };
const sinFoto = { id: 'p-002', nombre: 'Chicles' };
const porId = new Map([[conFoto.id, conFoto], [sinFoto.id, sinFoto]]);

test('constantes de ruta', () => {
  assert.equal(RUTA_INICIO, '#/');
  assert.equal(RUTA_PEDIDO, '#/pedido');
});

test('rutaDesdeHash: inicio, pedido y foto', () => {
  assert.deepEqual(rutaDesdeHash(''), { tipo: 'inicio' });
  assert.deepEqual(rutaDesdeHash('#'), { tipo: 'inicio' });
  assert.deepEqual(rutaDesdeHash('#/'), { tipo: 'inicio' });
  assert.deepEqual(rutaDesdeHash('#/pedido'), { tipo: 'pedido' });
  assert.deepEqual(rutaDesdeHash('#/foto/p-001'), { tipo: 'foto', id: 'p-001' });
  assert.deepEqual(rutaDesdeHash(undefined), { tipo: 'inicio' });
  assert.deepEqual(rutaDesdeHash(null), { tipo: 'inicio' });
});

test('rutaDesdeHash: hashes raros caen en inicio o en foto sin id', () => {
  assert.deepEqual(rutaDesdeHash('#/otra'), { tipo: 'inicio' });
  assert.deepEqual(rutaDesdeHash('#/pedido/'), { tipo: 'inicio' });
  assert.deepEqual(rutaDesdeHash('#/foto'), { tipo: 'inicio' });
  assert.deepEqual(rutaDesdeHash('#/foto/'), { tipo: 'foto', id: null });
  assert.deepEqual(rutaDesdeHash('#/foto/p-001/extra'), { tipo: 'foto', id: null });
  assert.deepEqual(rutaDesdeHash('#/foto/%E0%A4%A'), { tipo: 'foto', id: null });
});

test('hashDeFoto y rutaDesdeHash son inversas (incluso con caracteres raros)', () => {
  assert.equal(hashDeFoto('p-001'), '#/foto/p-001');
  for (const id of ['p-001', 'a.b_c-d', 'con espacio', 'a/b', 'ñandú', '100%']) {
    assert.deepEqual(rutaDesdeHash(hashDeFoto(id)), { tipo: 'foto', id }, id);
  }
});

test('resolverRuta: pantallas normales', () => {
  assert.deepEqual(resolverRuta('', porId), { pantalla: 'inicio', foto: null, corregirA: null });
  assert.deepEqual(resolverRuta('#/', porId), { pantalla: 'inicio', foto: null, corregirA: null });
  assert.deepEqual(resolverRuta('#/pedido', porId), { pantalla: 'pedido', foto: null, corregirA: null });
});

test('resolverRuta: el visor solo se abre si el producto existe y tiene foto', () => {
  assert.deepEqual(resolverRuta('#/foto/p-001', porId), { pantalla: 'inicio', foto: conFoto, corregirA: null });
});

test('resolverRuta: producto inexistente, sin foto o hash roto vuelve al inicio', () => {
  for (const hash of ['#/foto/p-002', '#/foto/nada', '#/foto/', '#/foto/%E0%A4%A', '#/foto/p-001/x']) {
    assert.deepEqual(resolverRuta(hash, porId), { pantalla: 'inicio', foto: null, corregirA: '#/' }, hash);
  }
});

test('resolverRuta: un producto oculto (que no está en el mapa) no abre el visor', () => {
  assert.equal(resolverRuta('#/foto/p-009', porId).foto, null);
  assert.equal(resolverRuta('#/foto/p-009', new Map()).corregirA, '#/');
});
