import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  masCantidad,
  menosCantidad,
  normalizarCantidad,
  formatearCantidad,
  detalleLinea,
  LIMITES_CANTIDAD,
} from '../src/core.js';

test('unidades: paso 1 y tope 9999 (distribuidora)', () => {
  assert.equal(masCantidad('unidad', 0), 1);
  assert.equal(masCantidad('unidad', 9998), 9999);
  assert.equal(masCantidad('unidad', 9999), 9999);
  assert.equal(menosCantidad('unidad', 3), 2);
  assert.equal(menosCantidad('unidad', 1), 0);
  assert.equal(menosCantidad('unidad', 0), 0);
});

test('kilos: pasos de 250 g y tope de 10 kg', () => {
  assert.equal(masCantidad('kg', 0), 250);
  assert.equal(masCantidad('kg', 750), 1000);
  assert.equal(masCantidad('kg', 9750), 10000);
  assert.equal(masCantidad('kg', 10000), 10000);
  assert.equal(menosCantidad('kg', 250), 0);
  assert.equal(menosCantidad('kg', 1250), 1000);
  assert.equal(menosCantidad('kg', 0), 0);
  assert.equal(LIMITES_CANTIDAD.kg.tope, 10000);
});

test('formatearCantidad: kilos con fracciones Unicode', () => {
  assert.equal(formatearCantidad('kg', 250), '¼ kg');
  assert.equal(formatearCantidad('kg', 500), '½ kg');
  assert.equal(formatearCantidad('kg', 750), '¾ kg');
  assert.equal(formatearCantidad('kg', 1000), '1 kg');
  assert.equal(formatearCantidad('kg', 1250), '1 ¼ kg');
  assert.equal(formatearCantidad('kg', 2500), '2 ½ kg');
  assert.equal(formatearCantidad('kg', 10000), '10 kg');
});

test('formatearCantidad: unidades como entero y gramos raros en g', () => {
  assert.equal(formatearCantidad('unidad', 2), '2');
  assert.equal(formatearCantidad('kg', 300), '300 g');
});

test('normalizarCantidad: valores inválidos o fuera de rango', () => {
  assert.equal(normalizarCantidad('unidad', 3), 3);
  assert.equal(normalizarCantidad('unidad', 3.7), 3);
  assert.equal(normalizarCantidad('unidad', 50000), 9999);
  assert.equal(normalizarCantidad('unidad', 0), 0);
  assert.equal(normalizarCantidad('unidad', -2), 0);
  assert.equal(normalizarCantidad('unidad', NaN), 0);
  assert.equal(normalizarCantidad('unidad', '3'), 0);
  assert.equal(normalizarCantidad('kg', 600), 500);
  assert.equal(normalizarCantidad('kg', 100), 0);
  assert.equal(normalizarCantidad('kg', 99999), 10000);
});

test('detalleLinea: unidades y kilos', () => {
  const alfajor = { unidad: 'unidad', precio_centavos: 120000 };
  const queso = { unidad: 'kg', precio_centavos: 800000 };
  assert.equal(detalleLinea(alfajor, 2), '2 unidades × $ 1.200');
  assert.equal(detalleLinea(alfajor, 1), '1 unidad × $ 1.200');
  assert.equal(detalleLinea(queso, 250), '¼ kg × $ 8.000 el kilo');
  assert.equal(detalleLinea(queso, 1250), '1 ¼ kg × $ 8.000 el kilo');
});
