import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  normalizarTexto,
  filtrarProductos,
  obtenerCategorias,
  esOferta,
  productosNovedades,
  productosOfertas,
  obtenerIniciales,
  indiceParejaIniciales,
} from '../src/core.js';

const productos = [
  { id: 'a', nombre: 'Alfajor triple', descripcion: 'Chocolate, 70 g', categoria: 'Golosinas', precio_centavos: 120000, precio_anterior_centavos: 140000 },
  { id: 'b', nombre: 'Queso cremoso', categoria: 'Lácteos', precio_centavos: 800000, destacado: true },
  { id: 'c', nombre: 'Yerba mate suave con palo', categoria: 'Almacén', precio_centavos: 250000, destacado: true },
  { id: 'd', nombre: 'Agua mineral', categoria: 'Bebidas', precio_centavos: 90000, precio_anterior_centavos: 110000 },
  { id: 'e', nombre: 'Pan lactal', categoria: 'Panadería', precio_centavos: 180000, precio_anterior_centavos: 180000 },
  { id: 'f', nombre: 'Café molido', categoria: 'Almacén', precio_centavos: 300000 },
];

test('normalizarTexto: sin tildes ni mayúsculas', () => {
  assert.equal(normalizarTexto('  CAFÉ Molído '), 'cafe molido');
  assert.equal(normalizarTexto('Ñandú'), 'nandu');
  assert.equal(normalizarTexto(undefined), '');
});

test('filtrarProductos: ignora tildes y mayúsculas', () => {
  assert.deepEqual(filtrarProductos(productos, { texto: 'cafe' }).map((p) => p.id), ['f']);
  assert.deepEqual(filtrarProductos(productos, { texto: 'CAFÉ' }).map((p) => p.id), ['f']);
  assert.deepEqual(filtrarProductos(productos, { texto: 'lacteos' }).map((p) => p.id), ['b']); // busca también en la categoría
  assert.deepEqual(filtrarProductos(productos, { texto: 'pan lac' }).map((p) => p.id), ['e']);
});

test('filtrarProductos: busca en nombre, descripción y categoría, y exige todas las palabras', () => {
  assert.deepEqual(filtrarProductos(productos, { texto: 'chocolate' }).map((p) => p.id), ['a']);
  assert.deepEqual(filtrarProductos(productos, { texto: 'alfajor queso' }).map((p) => p.id), []);
});

test('filtrarProductos: categoría y texto vacío', () => {
  assert.equal(filtrarProductos(productos, {}).length, 6);
  assert.deepEqual(
    filtrarProductos(productos, { categoria: 'Almacén' }).map((p) => p.id),
    ['c', 'f'],
  );
  assert.deepEqual(
    filtrarProductos(productos, { categoria: 'Almacén', texto: 'yerba' }).map((p) => p.id),
    ['c'],
  );
  assert.deepEqual(filtrarProductos(productos, { texto: 'zzz' }), []);
});

test('obtenerCategorias: únicas, en orden de aparición', () => {
  assert.deepEqual(obtenerCategorias(productos), ['Golosinas', 'Lácteos', 'Almacén', 'Bebidas', 'Panadería']);
});

test('ofertas y novedades', () => {
  assert.equal(esOferta(productos[0]), true);
  assert.equal(esOferta(productos[4]), false); // anterior igual al actual
  assert.equal(esOferta(productos[1]), false);
  assert.deepEqual(productosOfertas(productos).map((p) => p.id), ['a', 'd']);
  assert.deepEqual(productosNovedades(productos).map((p) => p.id), ['b', 'c']);
});

test('obtenerIniciales', () => {
  assert.equal(obtenerIniciales('Alfajor triple'), 'AT');
  assert.equal(obtenerIniciales('Yerba mate suave con palo, paquete de 500 g'), 'YM');
  assert.equal(obtenerIniciales('Pan'), 'PA');
  assert.equal(obtenerIniciales('  '), '?');
  assert.equal(obtenerIniciales('ñoquis de papa'), 'ÑD');
  assert.equal(obtenerIniciales('7up'), '7U');
});

test('indiceParejaIniciales: determinista y en rango 0..3', () => {
  for (const id of ['p-001', 'p-002', 'x', 'producto-largo-123']) {
    const i = indiceParejaIniciales(id);
    assert.ok(Number.isInteger(i) && i >= 0 && i <= 3);
    assert.equal(indiceParejaIniciales(id), i);
  }
  const usados = new Set(Array.from({ length: 200 }, (_, n) => indiceParejaIniciales(`p-${n}`)));
  assert.equal(usados.size, 4, 'con muchos ids se usan las 4 parejas');
});
