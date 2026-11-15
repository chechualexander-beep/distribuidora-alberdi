import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  adaptarCatalogo,
  itemsDelPedido,
  tokenDesdeHash,
  clasificarError,
  formatearVencimiento,
  hoyArgentina,
} from '../src/alberdi-core.js';
import { validarCatalogo } from '../src/core.js';

const token = 'a'.repeat(64);
const foto = '0e2b6f1c-1111-4c1a-9a7e-123456789abc/1791152916779031.jpg';
const respuesta = {
  nombre_comercio: 'ADRIANA',
  vence_at: '2026-11-15T15:30:00+00:00',
  productos: [
    { id: 'p1', codigo: 'TUT1', nombre: 'Tutuca S. Cay. x 1kg', descripcion: 'Bolsa', categoria: 'Snacks', precio: 2330.5, foto_path: foto },
    { id: 'p2', codigo: null, nombre: 'Sin categoría', descripcion: null, categoria: null, precio: 100 },
    { id: 'p3', nombre: 'Sin precio', categoria: 'X', precio: 0 },
    { id: 'p4', nombre: 'Foto rara', categoria: 'X', precio: 10, foto_path: '../../etc/passwd' },
  ],
};

test('token: solo 64 hexadecimales en #token=', () => {
  assert.equal(tokenDesdeHash(`#token=${token}`), token);
  assert.equal(tokenDesdeHash('#token=corto'), null);
  assert.equal(tokenDesdeHash('#/pedido'), null);
  assert.equal(tokenDesdeHash(`#token=${token.toUpperCase()}`), null);
  assert.equal(tokenDesdeHash(undefined), null);
});

test('adaptar: formato Vitrina válido, centavos enteros y precio original guardado', () => {
  const r = adaptarCatalogo(respuesta, { token, hoy: '2026-11-15' });
  const v = validarCatalogo(r.json, { whatsappOpcional: true });
  assert.equal(v.ok, true, JSON.stringify(v.errores));
  assert.equal(r.cliente, 'ADRIANA');
  assert.deepEqual(r.json.productos.map((p) => p.id), ['p1', 'p2', 'p4']); // sin precio: afuera
  const [p1, p2, p4] = r.json.productos;
  assert.equal(p1.precio_centavos, 233050);
  assert.equal(p1.descripcion, 'Bolsa · Código TUT1');
  assert.equal(p1.miniatura, foto);
  assert.equal(p2.categoria, 'Otros');
  assert.equal(p4.miniatura, undefined, 'una ruta de foto rara se ignora');
  assert.equal(r.precios.get('p1'), 2330.5);
  assert.equal(r.json.comercio.tema, 'alberdi');
  assert.match(r.json.comercio.id, /^alberdi-[a-f0-9]{16}$/);
});

test('adaptar: respuesta inválida se rechaza', () => {
  assert.throws(() => adaptarCatalogo(null, { token }));
  assert.throws(() => adaptarCatalogo({ productos: 'x' }, { token }));
});

test('validar: sin WhatsApp solo se acepta con la opción de Alberdi', () => {
  const { json } = adaptarCatalogo(respuesta, { token, hoy: '2026-11-15' });
  assert.equal(validarCatalogo(json).ok, false);
  assert.equal(validarCatalogo(json, { whatsappOpcional: true }).ok, true);
});

test('items del pedido: precio_visto es el del servidor, sin redondeos', () => {
  const { json, precios } = adaptarCatalogo(respuesta, { token, hoy: '2026-11-15' });
  const [p1, p2] = json.productos;
  const items = itemsDelPedido([{ producto: p1, cantidad: 3 }, { producto: p2, cantidad: 0 }], precios);
  assert.deepEqual(items, [{ producto_id: 'p1', cantidad: 3, precio_visto: 2330.5 }]);
});

test('errores: vencido, incierto y definitivo', () => {
  assert.equal(clasificarError({ estado: 410, cuerpo: { message: 'Este enlace venció.' } }).tipo, 'vencido');
  assert.equal(clasificarError({ red: true }).tipo, 'incierto');
  assert.equal(clasificarError({ estado: 503, cuerpo: {} }).tipo, 'incierto');
  const d = clasificarError({ estado: 400, cuerpo: { message: 'Los precios cambiaron. Actualizá el catálogo y revisá tu pedido' } });
  assert.equal(d.tipo, 'definitivo');
  assert.match(d.mensaje, /precios cambiaron/);
});

test('fechas en hora argentina', () => {
  assert.equal(formatearVencimiento('2026-11-15T15:30:00+00:00'), '15/11 a las 12:30');
  assert.equal(formatearVencimiento('nada'), '');
  assert.equal(hoyArgentina(new Date('2026-11-15T02:00:00Z')), '2026-11-14');
});

import { enlaceDesdeHash, adaptarCatalogoGeneral, mensajeGeneral, MAX_MENSAJE_ALBERDI } from '../src/alberdi-core.js';

test('enlace: cliente (#token=) y general (#general=)', () => {
  assert.deepEqual(enlaceDesdeHash(`#token=${token}`), { tipo: 'cliente', token });
  assert.deepEqual(enlaceDesdeHash(`#general=${token}`), { tipo: 'general', token });
  assert.equal(enlaceDesdeHash('#general=corto'), null);
  assert.equal(enlaceDesdeHash('#/pedido'), null);
  assert.equal(tokenDesdeHash(`#general=${token}`), null, 'un enlace general nunca se usa como de cliente');
});

const general = {
  nombre: 'Ofertas',
  vendedor: 'Juan Pérez',
  whatsapp: '5493794000000',
  vence_at: '2026-11-22T13:00:00+00:00',
  productos: respuesta.productos,
};

test('adaptar general: WhatsApp del preventista, códigos y otro carrito que el del cliente', () => {
  const r = adaptarCatalogoGeneral(general, { token, hoy: '2026-11-15' });
  assert.equal(validarCatalogo(r.json).ok, true, 'con WhatsApp no hace falta la opción de Alberdi');
  assert.equal(r.json.comercio.whatsapp, '5493794000000');
  assert.match(r.json.comercio.id, /^alberdi-g-[a-f0-9]{16}$/);
  assert.notEqual(r.json.comercio.id, adaptarCatalogo(respuesta, { token }).json.comercio.id);
  assert.equal(r.vendedor, 'Juan Pérez');
  assert.equal(r.codigos.get('p1'), 'TUT1');
  assert.equal(r.codigos.has('p2'), false);
  assert.throws(() => adaptarCatalogoGeneral({ ...general, whatsapp: '0379' }, { token }), /WhatsApp/);
});

test('mensaje general: saludo al preventista, código, total, quién pide y aclaración', () => {
  const { json, codigos } = adaptarCatalogoGeneral(general, { token, hoy: '2026-11-15' });
  const [p1, p2] = json.productos;
  const lineas = [
    { producto: p1, cantidad: 2, subtotal: 466100 },
    { producto: p2, cantidad: 1, subtotal: 10000 },
  ];
  const { texto, excedeLimite } = mensajeGeneral({
    lineas, codigos, vendedor: 'Juan Pérez', nombre: '  Kiosco   Lola ', aclaracion: 'Martes\n\n  a la tarde ',
  });
  assert.equal(excedeLimite, false);
  const filas = texto.split('\n');
  assert.equal(filas[0], 'Hola Juan Pérez, quiero hacer un pedido:');
  assert.match(filas[1], /^• 2 × Tutuca S\. Cay\. x 1kg \(TUT1\) — \$\s?4\.661$/);
  assert.match(filas[2], /^• 1 × Sin categoría — \$\s?100$/);
  assert.match(filas[3], /^Total: \$\s?4\.761$/);
  assert.equal(filas[4], 'Soy Kiosco Lola.');
  assert.deepEqual(filas.slice(5), ['Martes', 'a la tarde', 'Catálogo de Distribuidora Alberdi']);
  const largo = mensajeGeneral({ lineas: Array.from({ length: 80 }, () => lineas[0]), codigos });
  assert.equal(largo.excedeLimite, largo.texto.length > MAX_MENSAJE_ALBERDI);
  assert.equal(largo.excedeLimite, true);
});
