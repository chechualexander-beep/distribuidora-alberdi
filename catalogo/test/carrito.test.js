import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  reconciliarCarrito,
  mensajesDeAvisos,
  establecerCantidad,
  cantidadEnCarrito,
  lineasDelPedido,
  indexarProductos,
  cantidadDeProductos,
  claveCarrito,
  serializarCarrito,
  leerCarrito,
  crearAlmacen,
  calcularTotal,
  AVISO_PRECIOS,
  AVISO_QUITADOS,
} from '../src/core.js';

const alfajor = { id: 'p-001', nombre: 'Alfajor triple', unidad: 'unidad', precio_centavos: 120000, visible: true };
const queso = { id: 'p-005', nombre: 'Queso cremoso', unidad: 'kg', precio_centavos: 800000, visible: true };
const yerba = { id: 'p-009', nombre: 'Yerba', unidad: 'unidad', precio_centavos: 250000, visible: true };
const productos = [alfajor, queso, yerba];

const item = (p, cantidad, precio = p.precio_centavos) => ({ id: p.id, cantidad, precio_centavos: precio });

test('reconciliar: carrito al día no cambia y no avisa', () => {
  const guardado = [item(alfajor, 2), item(queso, 250)];
  const { carrito, avisos } = reconciliarCarrito(guardado, productos);
  assert.deepEqual(carrito, guardado);
  assert.deepEqual(avisos, { preciosCambiaron: false, productosQuitados: false });
  assert.deepEqual(mensajesDeAvisos(avisos), []);
});

test('reconciliar: producto borrado se quita y avisa', () => {
  const guardado = [item(alfajor, 2), { id: 'p-borrado', cantidad: 1, precio_centavos: 100 }];
  const { carrito, avisos } = reconciliarCarrito(guardado, productos);
  assert.deepEqual(carrito, [item(alfajor, 2)]);
  assert.equal(avisos.productosQuitados, true);
  assert.equal(avisos.preciosCambiaron, false);
  assert.deepEqual(mensajesDeAvisos(avisos), [AVISO_QUITADOS]);
  assert.equal(AVISO_QUITADOS, 'Quitamos productos que ya no están');
});

test('reconciliar: producto que pasó a no visible se quita', () => {
  const oculto = { ...alfajor, visible: false };
  const { carrito, avisos } = reconciliarCarrito([item(alfajor, 1)], [oculto, queso]);
  assert.deepEqual(carrito, []);
  assert.equal(avisos.productosQuitados, true);
});

test('reconciliar: precio cambiado se actualiza y avisa', () => {
  const subio = { ...alfajor, precio_centavos: 150000 };
  const { carrito, avisos } = reconciliarCarrito([item(alfajor, 2, 120000)], [subio, queso]);
  assert.deepEqual(carrito, [item(subio, 2)]);
  assert.equal(carrito[0].precio_centavos, 150000);
  assert.deepEqual(avisos, { preciosCambiaron: true, productosQuitados: false });
  assert.deepEqual(mensajesDeAvisos(avisos), [AVISO_PRECIOS]);
  assert.equal(AVISO_PRECIOS, 'Algunos precios cambiaron');
});

test('reconciliar: ambos avisos a la vez', () => {
  const subio = { ...alfajor, precio_centavos: 150000 };
  const { avisos } = reconciliarCarrito(
    [item(alfajor, 1, 120000), { id: 'fantasma', cantidad: 1, precio_centavos: 1 }],
    [subio],
  );
  assert.deepEqual(mensajesDeAvisos(avisos), [AVISO_PRECIOS, AVISO_QUITADOS]);
});

test('reconciliar: normaliza cantidades inválidas y duplicados', () => {
  const guardado = [
    item(alfajor, 50000), // sobre el tope → 9999
    item(queso, 600), // no múltiplo de 250 → 500
    item(yerba, 0), // cantidad 0 → se quita
    item(alfajor, 3), // duplicado → se ignora
  ];
  const { carrito, avisos } = reconciliarCarrito(guardado, productos);
  assert.deepEqual(carrito, [item(alfajor, 9999), item(queso, 500)]);
  assert.equal(avisos.productosQuitados, true);
});

test('reconciliar: entrada inválida da carrito vacío', () => {
  assert.deepEqual(reconciliarCarrito(null, productos).carrito, []);
  assert.deepEqual(reconciliarCarrito(undefined, productos).carrito, []);
});

test('establecerCantidad: agrega, cambia, quita y respeta topes', () => {
  let c = [];
  c = establecerCantidad(c, alfajor, 1);
  c = establecerCantidad(c, queso, 250);
  assert.deepEqual(c, [item(alfajor, 1), item(queso, 250)]);
  c = establecerCantidad(c, alfajor, 3);
  assert.deepEqual(c, [item(alfajor, 3), item(queso, 250)], 'conserva el orden');
  assert.equal(cantidadEnCarrito(c, 'p-001'), 3);
  assert.equal(cantidadEnCarrito(c, 'nada'), 0);
  c = establecerCantidad(c, queso, 50000);
  assert.equal(cantidadEnCarrito(c, 'p-005'), 10000);
  const antes = c;
  c = establecerCantidad(c, alfajor, 0);
  assert.deepEqual(c.map((i) => i.id), ['p-005']);
  assert.equal(antes.length, 2, 'no muta el carrito original');
  assert.equal(cantidadDeProductos(c), 1);
});

test('lineasDelPedido y total: subtotales redondeados por línea', () => {
  const carrito = [item(alfajor, 2), item(queso, 250), item(yerba, 1)];
  const lineas = lineasDelPedido(carrito, indexarProductos(productos));
  assert.deepEqual(lineas.map((l) => l.subtotal), [240000, 200000, 250000]);
  assert.equal(calcularTotal(lineas), 690000);
  assert.deepEqual(lineasDelPedido([{ id: 'x', cantidad: 1, precio_centavos: 1 }], indexarProductos(productos)), []);
});

test('clave de localStorage', () => {
  assert.equal(claveCarrito('kiosco-ejemplo'), 'vitrina:kiosco-ejemplo');
});

test('serializar y leer el carrito', () => {
  const c = [item(alfajor, 2), item(queso, 250)];
  assert.deepEqual(leerCarrito(serializarCarrito(c)), c);
});

test('leerCarrito: basura da carrito vacío', () => {
  for (const basura of [null, undefined, '', 'no es json', '{', '[]', '{"v":2,"items":[]}', '{"v":1}', '{"v":1,"items":5}', 42]) {
    assert.deepEqual(leerCarrito(basura), [], String(basura));
  }
  const mezcla = JSON.stringify({
    v: 1,
    items: [{ id: 'p-001', c: 2, p: 100 }, { id: 5, c: 1, p: 1 }, { id: 'a', c: 1.5, p: 1 }, null, 'x'],
  });
  assert.deepEqual(leerCarrito(mezcla), [{ id: 'p-001', cantidad: 2, precio_centavos: 100 }]);
});

function storageFalso() {
  const datos = new Map();
  return {
    datos,
    getItem: (k) => (datos.has(k) ? datos.get(k) : null),
    setItem: (k, v) => void datos.set(k, v),
  };
}

test('almacén: guarda y lee con la clave "vitrina:" + id', () => {
  const storage = storageFalso();
  const almacen = crearAlmacen(storage, claveCarrito('kiosco-ejemplo'));
  assert.deepEqual(almacen.leer(), []);
  almacen.guardar([item(alfajor, 2)]);
  assert.ok(storage.datos.has('vitrina:kiosco-ejemplo'));
  assert.deepEqual(crearAlmacen(storage, 'vitrina:kiosco-ejemplo').leer(), [item(alfajor, 2)]);
});

test('almacén: sin storage funciona en memoria', () => {
  for (const sinStorage of [null, undefined]) {
    const almacen = crearAlmacen(sinStorage, 'vitrina:x');
    almacen.guardar([item(alfajor, 1)]);
    assert.deepEqual(almacen.leer(), [item(alfajor, 1)]);
  }
});

test('almacén: si el storage está bloqueado (lanza), sigue en memoria', () => {
  const bloqueado = {
    getItem() { throw new Error('SecurityError'); },
    setItem() { throw new Error('QuotaExceededError'); },
  };
  const almacen = crearAlmacen(bloqueado, 'vitrina:x');
  assert.deepEqual(almacen.leer(), []);
  almacen.guardar([item(yerba, 4)]);
  assert.deepEqual(almacen.leer(), [item(yerba, 4)]);
});

test('almacén: si falla al guardar, el carrito no se pierde', () => {
  const storage = storageFalso();
  storage.setItem = () => { throw new Error('QuotaExceededError'); };
  const almacen = crearAlmacen(storage, 'vitrina:x');
  almacen.guardar([item(alfajor, 5)]);
  assert.deepEqual(almacen.leer(), [item(alfajor, 5)]);
});
