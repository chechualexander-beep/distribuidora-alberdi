import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatearPrecio, calcularSubtotal, calcularTotal } from '../src/core.js';

test('formatearPrecio: pesos exactos sin decimales', () => {
  assert.equal(formatearPrecio(0), '$ 0');
  assert.equal(formatearPrecio(100), '$ 1');
  assert.equal(formatearPrecio(120000), '$ 1.200');
  assert.equal(formatearPrecio(690000), '$ 6.900');
  assert.equal(formatearPrecio(100000000), '$ 1.000.000');
});

test('formatearPrecio: con centavos usa coma y dos dígitos', () => {
  assert.equal(formatearPrecio(125050), '$ 1.250,50');
  assert.equal(formatearPrecio(5), '$ 0,05');
  assert.equal(formatearPrecio(99), '$ 0,99');
  assert.equal(formatearPrecio(100001), '$ 1.000,01');
});

test('formatearPrecio: rechaza valores que no son centavos enteros', () => {
  assert.throws(() => formatearPrecio(12.5), TypeError);
  assert.throws(() => formatearPrecio(-1), TypeError);
  assert.throws(() => formatearPrecio('100'), TypeError);
  assert.throws(() => formatearPrecio(NaN), TypeError);
});

test('calcularSubtotal: por unidad', () => {
  assert.equal(calcularSubtotal(120000, 'unidad', 2), 240000);
  assert.equal(calcularSubtotal(99, 'unidad', 99), 9801);
});

test('calcularSubtotal: por kilo redondea como Math.round(precio * gramos / 1000)', () => {
  assert.equal(calcularSubtotal(800000, 'kg', 250), 200000); // ¼ kg a $ 8.000 el kilo
  assert.equal(calcularSubtotal(800000, 'kg', 1000), 800000);
  assert.equal(calcularSubtotal(800000, 'kg', 10000), 8000000);
  // 1001 * 250 / 1000 = 250,25 → 250
  assert.equal(calcularSubtotal(1001, 'kg', 250), 250);
  // 1003 * 250 / 1000 = 250,75 → 251
  assert.equal(calcularSubtotal(1003, 'kg', 250), 251);
  // medio exacto: 1001 * 500 / 1000 = 500,5 → 501 (redondea hacia arriba)
  assert.equal(calcularSubtotal(1001, 'kg', 500), 501);
});

test('calcularSubtotal: coincide con Math.round en muchos casos', () => {
  for (let precio = 1; precio < 5000; precio += 37) {
    for (const gramos of [250, 500, 750, 1000, 1250, 2500, 10000]) {
      assert.equal(
        calcularSubtotal(precio, 'kg', gramos),
        Math.round((precio * gramos) / 1000),
        `precio ${precio}, gramos ${gramos}`,
      );
    }
  }
});

test('calcularTotal: suma subtotales ya redondeados', () => {
  const l1 = calcularSubtotal(1003, 'kg', 250); // 251
  const l2 = calcularSubtotal(1003, 'kg', 250); // 251
  // Sumar y redondear al final daría 501; sumar subtotales redondeados da 502.
  assert.equal(calcularTotal([{ subtotal: l1 }, { subtotal: l2 }]), 502);
  assert.equal(calcularTotal([]), 0);
});

test('el ejemplo del pedido suma $ 6.900', () => {
  const total = calcularTotal([
    { subtotal: calcularSubtotal(120000, 'unidad', 2) },
    { subtotal: calcularSubtotal(800000, 'kg', 250) },
    { subtotal: calcularSubtotal(250000, 'unidad', 1) },
  ]);
  assert.equal(formatearPrecio(total), '$ 6.900');
});
