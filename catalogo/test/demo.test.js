import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import {
  validarCatalogo,
  describirErrores,
  esOferta,
  productosNovedades,
  productosOfertas,
  obtenerCategorias,
} from '../src/core.js';

const crudo = JSON.parse(readFileSync(new URL('../src/catalogo.json', import.meta.url), 'utf8'));
const resultado = validarCatalogo(crudo);

test('el catálogo demo es válido', () => {
  assert.equal(resultado.ok, true, resultado.ok ? '' : describirErrores(resultado.errores));
});

test('el catálogo demo cubre los casos pedidos', () => {
  const { productos } = resultado.catalogo;
  assert.ok(productos.length >= 12);
  const porNombre = (n) => productos.find((p) => p.nombre === n);

  const queso = porNombre('Queso cremoso');
  assert.equal(queso.unidad, 'kg');
  assert.equal(queso.precio_centavos, 800000);

  const alfajor = porNombre('Alfajor triple');
  assert.equal(alfajor.precio_centavos, 120000);
  assert.equal(alfajor.precio_anterior_centavos, 140000);
  const agua = porNombre('Agua mineral');
  assert.equal(agua.precio_centavos, 90000);
  assert.equal(agua.precio_anterior_centavos, 110000);
  assert.deepEqual(productosOfertas(productos).map((p) => p.nombre), ['Alfajor triple', 'Agua mineral']);
  assert.ok(productos.filter(esOferta).length === 2);

  assert.deepEqual(
    productosNovedades(productos).map((p) => p.nombre).sort(),
    ['Pan lactal', 'Papas fritas', 'Yerba mate suave con palo, paquete de 500 g'],
  );

  assert.ok(productos.some((p) => p.miniatura === undefined), 'hay productos sin foto');
  assert.ok(productos.some((p) => p.miniatura !== undefined), 'hay productos con foto');
  assert.ok(productos.some((p) => p.nombre.length >= 40), 'hay un nombre largo');
  assert.deepEqual(obtenerCategorias(productos), ['Golosinas', 'Lácteos', 'Bebidas', 'Almacén', 'Panadería']);
});

test('las miniaturas del demo existen en src/img', () => {
  for (const p of resultado.catalogo.productos) {
    if (p.miniatura) assert.ok(existsSync(new URL(`../src/${p.miniatura}`, import.meta.url)), p.miniatura);
  }
});

test('las 5 fuentes .woff2 y sus licencias están en src/fonts', () => {
  const archivos = readdirSync(new URL('../src/fonts/', import.meta.url));
  for (const f of [
    'inter-latin-400-normal.woff2',
    'inter-latin-600-normal.woff2',
    'inter-latin-700-normal.woff2',
    'space-grotesk-latin-600-normal.woff2',
    'space-grotesk-latin-700-normal.woff2',
    'LICENSE-inter.txt',
    'LICENSE-space-grotesk.txt',
  ]) {
    assert.ok(archivos.includes(f), f);
  }
});
