import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  validarCatalogo,
  describirErrores,
  productosVisibles,
  esWhatsappValido,
  esSlugValido,
  MAX_PRODUCTOS,
} from '../src/core.js';
import { generarCatalogo } from './helpers/generar-500.js';

function catalogoBase() {
  return {
    formato: 1,
    comercio: {
      id: 'kiosco-ejemplo',
      nombre: 'Kiosco de Ejemplo',
      whatsapp: '5490000000000',
      horario: '8 a 22 hs', // campo viejo: se ignora como cualquier campo desconocido
      actualizado: '2026-11-12',
      tema: 'verde',
    },
    productos: [
      {
        id: 'p-001',
        nombre: 'Alfajor triple',
        descripcion: 'Chocolate, 70 g',
        categoria: 'Golosinas',
        precio_centavos: 120000,
        precio_anterior_centavos: 140000,
        unidad: 'unidad',
        miniatura: 'img/p-001.jpg',
        destacado: false,
        visible: true,
      },
    ],
  };
}

function conProducto(cambios) {
  const c = catalogoBase();
  Object.assign(c.productos[0], cambios);
  return c;
}

function rutasDeError(resultado) {
  assert.equal(resultado.ok, false);
  return resultado.errores.map((e) => e.ruta);
}

test('catálogo válido completo', () => {
  const r = validarCatalogo(catalogoBase());
  assert.equal(r.ok, true);
  assert.equal(r.catalogo.comercio.nombre, 'Kiosco de Ejemplo');
  assert.equal(r.catalogo.productos[0].precio_anterior_centavos, 140000);
  assert.equal(r.catalogo.productos[0].miniatura, 'img/p-001.jpg');
});

test('catálogo válido mínimo: aplica valores por defecto', () => {
  const r = validarCatalogo({
    formato: 1,
    comercio: { id: 'a', nombre: 'A', whatsapp: '5491112345678', actualizado: '2026-01-31' },
    productos: [{ id: 'x', nombre: 'Pan', categoria: 'Panadería', unidad: 'kg', precio_centavos: 500 }],
  });
  assert.equal(r.ok, true);
  assert.equal(r.catalogo.comercio.tema, 'verde');
  assert.equal(r.catalogo.comercio.horarios, undefined);
  assert.equal(r.catalogo.comercio.horarios_nota, undefined);
  assert.deepEqual(r.avisos, []);
  const p = r.catalogo.productos[0];
  assert.equal(p.visible, true);
  assert.equal(p.destacado, false);
  assert.equal(p.descripcion, undefined);
  assert.equal(p.miniatura, undefined);
});

test('el campo viejo "horario" se ignora (ya no se usa)', () => {
  const r = validarCatalogo(catalogoBase());
  assert.equal(r.ok, true);
  assert.equal('horario' in r.catalogo.comercio, false);
  assert.deepEqual(r.avisos, []);
});

test('ignora campos desconocidos', () => {
  const c = catalogoBase();
  c.extra = 1;
  c.comercio.color = 'rojo';
  c.productos[0].stock = 10;
  const r = validarCatalogo(c);
  assert.equal(r.ok, true);
  assert.equal('extra' in r.catalogo, false);
  assert.equal('color' in r.catalogo.comercio, false);
  assert.equal('stock' in r.catalogo.productos[0], false);
});

test('tema inválido o ausente cae en verde sin rechazar', () => {
  const c = catalogoBase();
  c.comercio.tema = 'violeta';
  assert.equal(validarCatalogo(c).catalogo.comercio.tema, 'verde');
  delete c.comercio.tema;
  assert.equal(validarCatalogo(c).catalogo.comercio.tema, 'verde');
  c.comercio.tema = 'ambar';
  assert.equal(validarCatalogo(c).catalogo.comercio.tema, 'ambar');
});

test('rechaza lo que no es un objeto o tiene otro formato', () => {
  for (const basura of [null, undefined, 5, 'hola', [], true]) {
    assert.equal(validarCatalogo(basura).ok, false);
  }
  const c = catalogoBase();
  c.formato = 2;
  assert.deepEqual(rutasDeError(validarCatalogo(c)), ['formato']);
  delete c.formato;
  assert.deepEqual(rutasDeError(validarCatalogo(c)), ['formato']);
});

test('comercio: id, nombre, whatsapp y fecha inválidos', () => {
  const casos = [
    [{ id: 'Kiosco Ejemplo' }, 'comercio.id'],
    [{ id: 'kiosco_ejemplo' }, 'comercio.id'],
    [{ id: '-kiosco' }, 'comercio.id'],
    [{ id: undefined }, 'comercio.id'],
    [{ nombre: '' }, 'comercio.nombre'],
    [{ nombre: 'x'.repeat(81) }, 'comercio.nombre'],
    [{ whatsapp: '+54 9 11 1234-5678' }, 'comercio.whatsapp'],
    [{ whatsapp: 5491112345678 }, 'comercio.whatsapp'],
    [{ whatsapp: '123' }, 'comercio.whatsapp'],
    [{ whatsapp: '05491112345678' }, 'comercio.whatsapp'],
    [{ whatsapp: '1234567890123456' }, 'comercio.whatsapp'],
    [{ actualizado: '2026-02-30' }, 'comercio.actualizado'],
    [{ actualizado: '12/11/2026' }, 'comercio.actualizado'],
    [{ actualizado: undefined }, 'comercio.actualizado'],
  ];
  for (const [cambios, ruta] of casos) {
    const c = catalogoBase();
    Object.assign(c.comercio, cambios);
    assert.deepEqual(rutasDeError(validarCatalogo(c)), [ruta], JSON.stringify(cambios));
  }
  const sinComercio = catalogoBase();
  delete sinComercio.comercio;
  assert.deepEqual(rutasDeError(validarCatalogo(sinComercio)), ['comercio']);
});

test('productos: debe ser una lista no vacía', () => {
  const c = catalogoBase();
  c.productos = 'nada';
  assert.deepEqual(rutasDeError(validarCatalogo(c)), ['productos']);
  c.productos = [];
  assert.deepEqual(rutasDeError(validarCatalogo(c)), ['productos']);
  delete c.productos;
  assert.deepEqual(rutasDeError(validarCatalogo(c)), ['productos']);
});

test('producto: campos obligatorios inválidos', () => {
  const casos = [
    [{ id: '' }, 'productos[0].id'],
    [{ id: 'con espacio' }, 'productos[0].id'],
    [{ id: 5 }, 'productos[0].id'],
    [{ nombre: undefined }, 'productos[0].nombre'],
    [{ nombre: '   ' }, 'productos[0].nombre'],
    [{ nombre: 42 }, 'productos[0].nombre'],
    [{ nombre: 'x'.repeat(121) }, 'productos[0].nombre'],
    [{ nombre: 'Hola\u0000mundo' }, 'productos[0].nombre'],
    [{ categoria: undefined }, 'productos[0].categoria'],
    [{ unidad: 'litro' }, 'productos[0].unidad'],
    [{ unidad: undefined }, 'productos[0].unidad'],
    [{ precio_centavos: 0 }, 'productos[0].precio_centavos'],
    [{ precio_centavos: -5 }, 'productos[0].precio_centavos'],
    [{ precio_centavos: 12.5 }, 'productos[0].precio_centavos'],
    [{ precio_centavos: '1200' }, 'productos[0].precio_centavos'],
    [{ precio_centavos: 1e12 }, 'productos[0].precio_centavos'],
    [{ precio_centavos: undefined }, 'productos[0].precio_centavos'],
    [{ precio_anterior_centavos: 'mucho' }, 'productos[0].precio_anterior_centavos'],
    [{ precio_anterior_centavos: 10.5 }, 'productos[0].precio_anterior_centavos'],
    [{ descripcion: 'x'.repeat(201) }, 'productos[0].descripcion'],
    [{ destacado: 'si' }, 'productos[0].destacado'],
    [{ visible: 0 }, 'productos[0].visible'],
  ];
  for (const [cambios, ruta] of casos) {
    assert.deepEqual(rutasDeError(validarCatalogo(conProducto(cambios))), [ruta], JSON.stringify(cambios));
  }
  const c = catalogoBase();
  c.productos[0] = 'no soy objeto';
  assert.deepEqual(rutasDeError(validarCatalogo(c)), ['productos[0]']);
});

test('producto: ids repetidos se rechazan', () => {
  const c = catalogoBase();
  c.productos.push({ ...c.productos[0] });
  assert.deepEqual(rutasDeError(validarCatalogo(c)), ['productos[1].id']);
});

test('precio anterior que no es mayor al actual se ignora (no es oferta)', () => {
  for (const anterior of [120000, 100000]) {
    const r = validarCatalogo(conProducto({ precio_anterior_centavos: anterior }));
    assert.equal(r.ok, true);
    assert.equal(r.catalogo.productos[0].precio_anterior_centavos, undefined);
  }
});

test('mensajes claros: dicen qué campo y qué se espera', () => {
  const r = validarCatalogo(conProducto({ precio_centavos: 12.5 }));
  const texto = describirErrores(r.errores);
  assert.match(texto, /productos\[0\]\.precio_centavos/);
  assert.match(texto, /centavos/);
});

test('tope de 2000 productos', () => {
  const c = catalogoBase();
  const armar = (n) =>
    Array.from({ length: n }, (_, i) => ({
      id: `p-${i}`,
      nombre: `Producto ${i}`,
      categoria: 'Varios',
      unidad: 'unidad',
      precio_centavos: 1000 + i,
    }));
  c.productos = armar(MAX_PRODUCTOS);
  assert.equal(validarCatalogo(c).ok, true);
  c.productos = armar(MAX_PRODUCTOS + 1);
  const r = validarCatalogo(c);
  assert.deepEqual(rutasDeError(r), ['productos']);
  assert.match(r.errores[0].mensaje, /2000/);
});

test('limita la cantidad de errores informados', () => {
  const c = catalogoBase();
  c.productos = Array.from({ length: 500 }, () => ({}));
  const r = validarCatalogo(c);
  assert.equal(r.ok, false);
  assert.ok(r.errores.length <= 50);
});

test('productosVisibles: oculta visible:false', () => {
  const c = catalogoBase();
  c.productos.push({ id: 'p-2', nombre: 'Oculto', categoria: 'X', unidad: 'unidad', precio_centavos: 100, visible: false });
  const r = validarCatalogo(c);
  assert.equal(r.catalogo.productos.length, 2);
  assert.deepEqual(productosVisibles(r.catalogo).map((p) => p.id), ['p-001']);
});

test('esWhatsappValido y esSlugValido', () => {
  assert.equal(esWhatsappValido('5490000000000'), true);
  assert.equal(esWhatsappValido('549000000000a'), false);
  assert.equal(esWhatsappValido(''), false);
  assert.equal(esWhatsappValido(null), false);
  assert.equal(esSlugValido('kiosco-ejemplo'), true);
  assert.equal(esSlugValido('Kiosco'), false);
  assert.equal(esSlugValido('a--b'), false);
  assert.equal(esSlugValido('a'.repeat(65)), false);
});

test('el catálogo generado de 500 productos es válido', () => {
  const r = validarCatalogo(generarCatalogo(500));
  assert.equal(r.ok, true, r.ok ? '' : describirErrores(r.errores));
  assert.equal(r.catalogo.productos.length, 500);
});

test('una pasada con 2000 productos es rápida', () => {
  const c = catalogoBase();
  c.productos = Array.from({ length: 2000 }, (_, i) => ({
    id: `p-${i}`,
    nombre: `Producto ${i}`,
    categoria: 'Varios',
    unidad: 'unidad',
    precio_centavos: 1000 + i,
  }));
  const t0 = performance.now();
  assert.equal(validarCatalogo(c).ok, true);
  assert.ok(performance.now() - t0 < 200, 'validar 2000 productos tarda menos de 200 ms');
});
