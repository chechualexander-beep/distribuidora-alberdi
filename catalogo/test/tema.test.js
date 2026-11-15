import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolverTema, esFechaValida, formatearFecha } from '../src/core.js';

test('resolverTema: valores válidos', () => {
  for (const t of ['verde', 'rojo', 'azul', 'ambar', 'alberdi']) assert.equal(resolverTema(t), t);
});

test('resolverTema: faltante o inválido usa verde', () => {
  assert.equal(resolverTema(undefined), 'verde');
  assert.equal(resolverTema(null), 'verde');
  assert.equal(resolverTema(''), 'verde');
  assert.equal(resolverTema('violeta'), 'verde');
  assert.equal(resolverTema('ROJO'), 'verde');
  assert.equal(resolverTema(5), 'verde');
  assert.equal(resolverTema({}), 'verde');
});

test('formatearFecha: dd/mm/aaaa sin zonas horarias', () => {
  assert.equal(formatearFecha('2026-11-12'), '12/11/2026');
  assert.equal(formatearFecha('2026-01-01'), '01/01/2026');
  assert.equal(formatearFecha('2024-12-31'), '31/12/2024');
});

test('esFechaValida: calendario real', () => {
  assert.equal(esFechaValida('2024-02-29'), true);
  assert.equal(esFechaValida('2026-02-29'), false);
  assert.equal(esFechaValida('2026-13-01'), false);
  assert.equal(esFechaValida('2026-00-10'), false);
  assert.equal(esFechaValida('2026-04-31'), false);
  assert.equal(esFechaValida('2026-4-3'), false);
  assert.equal(esFechaValida('12/11/2026'), false);
  assert.equal(esFechaValida(20261112), false);
  assert.equal(esFechaValida(undefined), false);
  assert.throws(() => formatearFecha('basura'), TypeError);
});
