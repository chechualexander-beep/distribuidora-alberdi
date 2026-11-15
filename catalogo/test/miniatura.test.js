import { test } from 'node:test';
import assert from 'node:assert/strict';
import { esMiniaturaSegura, validarCatalogo } from '../src/core.js';

test('rutas relativas seguras dentro de la carpeta del comercio', () => {
  for (const ruta of ['img/p-001.jpg', 'img/sub/carpeta/foto.png', 'foto.webp', 'img/a.b.jpeg', 'IMG/FOTO.JPG', 'img/logo.svg']) {
    assert.equal(esMiniaturaSegura(ruta), true, ruta);
  }
});

test('rutas inseguras se descartan', () => {
  const malas = [
    '../secreto.jpg',
    'img/../../secreto.jpg',
    'img/..%2fsecreto.jpg',
    '/img/foto.jpg',
    '//evil.com/foto.jpg',
    'img//foto.jpg',
    'javascript:alert(1)',
    'JAVASCRIPT:alert(1).jpg',
    'data:image/png;base64,AAAA',
    'http://evil.com/foto.jpg',
    'https://evil.com/foto.jpg',
    'img\\foto.jpg',
    './img/foto.jpg',
    'img/.oculto.jpg',
    'img/foto.exe',
    'img/foto.jpg.html',
    'img/foto',
    'img/foto.jpg?x=1',
    'img/foto.jpg#x',
    'img/fo to.jpg',
    '',
    ' img/foto.jpg',
    'x'.repeat(201) + '.jpg',
    null,
    undefined,
    42,
    {},
  ];
  for (const ruta of malas) {
    assert.equal(esMiniaturaSegura(ruta), false, String(ruta));
  }
});

test('una miniatura insegura se ignora pero no invalida el catálogo', () => {
  const r = validarCatalogo({
    formato: 1,
    comercio: { id: 'a', nombre: 'A', whatsapp: '5491112345678', actualizado: '2026-11-12' },
    productos: [
      { id: 'p1', nombre: 'Uno', categoria: 'X', unidad: 'unidad', precio_centavos: 100, miniatura: '../../etc/passwd.jpg' },
      { id: 'p2', nombre: 'Dos', categoria: 'X', unidad: 'unidad', precio_centavos: 100, miniatura: 'javascript:alert(1)' },
      { id: 'p3', nombre: 'Tres', categoria: 'X', unidad: 'unidad', precio_centavos: 100, miniatura: 'img/p3.jpg' },
    ],
  });
  assert.equal(r.ok, true);
  assert.equal(r.catalogo.productos[0].miniatura, undefined);
  assert.equal(r.catalogo.productos[1].miniatura, undefined);
  assert.equal(r.catalogo.productos[2].miniatura, 'img/p3.jpg');
});
