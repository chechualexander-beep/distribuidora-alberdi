import { test } from 'node:test';
import assert from 'node:assert/strict';
import { armarMensaje, urlWhatsApp, calcularSubtotal, MAX_MENSAJE } from '../src/core.js';

const alfajor = { id: 'p-001', nombre: 'Alfajor triple', unidad: 'unidad', precio_centavos: 120000 };
const queso = { id: 'p-005', nombre: 'Queso cremoso', unidad: 'kg', precio_centavos: 800000 };
const yerba = { id: 'p-009', nombre: 'Yerba mate suave con palo', unidad: 'unidad', precio_centavos: 250000 };

function linea(producto, cantidad) {
  return { producto, cantidad, subtotal: calcularSubtotal(producto.precio_centavos, producto.unidad, cantidad) };
}

const lineas = [linea(alfajor, 2), linea(queso, 250), linea(yerba, 1)];

test('mensaje completo, con nombre y aclaración', () => {
  const { texto, excedeLimite } = armarMensaje({
    lineas,
    nombre: 'Ana',
    aclaracion: 'Paso a retirar a las 18',
    actualizado: '2026-11-12',
  });
  assert.equal(
    texto,
    [
      'Hola, quiero hacer un pedido:',
      '• 2 × Alfajor triple — $ 2.400',
      '• ¼ kg de Queso cremoso — $ 2.000',
      '• 1 × Yerba mate suave con palo — $ 2.500',
      'Total: $ 6.900',
      'Soy Ana.',
      'Paso a retirar a las 18',
      'Vi tu catálogo · precios al 12/11/2026',
    ].join('\n'),
  );
  assert.equal(excedeLimite, false);
});

test('mensaje sin nombre ni aclaración', () => {
  const { texto } = armarMensaje({ lineas, actualizado: '2026-11-12' });
  assert.equal(
    texto,
    [
      'Hola, quiero hacer un pedido:',
      '• 2 × Alfajor triple — $ 2.400',
      '• ¼ kg de Queso cremoso — $ 2.000',
      '• 1 × Yerba mate suave con palo — $ 2.500',
      'Total: $ 6.900',
      'Vi tu catálogo · precios al 12/11/2026',
    ].join('\n'),
  );
});

test('solo nombre o solo aclaración', () => {
  const soloNombre = armarMensaje({ lineas, nombre: '  Ana   María ', aclaracion: '   ', actualizado: '2026-11-12' }).texto;
  assert.match(soloNombre, /\nSoy Ana María\.\nVi tu catálogo/);
  const soloNota = armarMensaje({ lineas, nombre: '', aclaracion: 'Sin cebolla', actualizado: '2026-11-12' }).texto;
  assert.doesNotMatch(soloNota, /Soy /);
  assert.match(soloNota, /\nSin cebolla\nVi tu catálogo/);
});

test('fracciones de kilo en el mensaje', () => {
  const t = armarMensaje({
    lineas: [linea(queso, 500), linea(queso, 1000), linea(queso, 1250)],
    actualizado: '2026-11-12',
  }).texto;
  assert.match(t, /• ½ kg de Queso cremoso — \$ 4\.000/);
  assert.match(t, /• 1 kg de Queso cremoso — \$ 8\.000/);
  assert.match(t, /• 1 ¼ kg de Queso cremoso — \$ 10\.000/);
});

test('la aclaración conserva saltos de línea pero se limpia', () => {
  const t = armarMensaje({
    lineas,
    aclaracion: 'Linea 1\r\nLinea 2\u0007',
    actualizado: '2026-11-12',
  }).texto;
  assert.match(t, /\nLinea 1\nLinea 2\nVi tu catálogo/);
});

test('límite de 1500 caracteres: exacto no excede, uno más sí, y nunca corta', () => {
  const base = armarMensaje({ lineas, aclaracion: 'x', actualizado: '2026-11-12' });
  // Con "x" de aclaración el largo es base.largo; ajustamos a 1500 exactos.
  const relleno = 'a'.repeat(1500 - base.largo + 1);
  const exacto = armarMensaje({ lineas, aclaracion: relleno, actualizado: '2026-11-12' });
  assert.equal(exacto.largo, MAX_MENSAJE);
  assert.equal(exacto.excedeLimite, false);

  const pasado = armarMensaje({ lineas, aclaracion: relleno + 'a', actualizado: '2026-11-12' });
  assert.equal(pasado.largo, MAX_MENSAJE + 1);
  assert.equal(pasado.excedeLimite, true);
  assert.ok(pasado.texto.endsWith('precios al 12/11/2026'), 'el texto no se corta');
});

test('muchos productos exceden el límite y se avisa', () => {
  const muchos = Array.from({ length: 40 }, (_, i) =>
    linea({ id: `p-${i}`, nombre: `Producto de nombre bastante largo número ${i}`, unidad: 'unidad', precio_centavos: 123456 }, 3),
  );
  const r = armarMensaje({ lineas: muchos, actualizado: '2026-11-12' });
  assert.equal(r.excedeLimite, true);
  assert.ok(r.largo > MAX_MENSAJE);
});

test('armarMensaje es pura: no modifica sus entradas y es determinista', () => {
  const entrada = { lineas, nombre: 'Ana', aclaracion: 'Hola', actualizado: '2026-11-12' };
  const copia = structuredClone(entrada);
  const a = armarMensaje(entrada);
  const b = armarMensaje(entrada);
  assert.deepEqual(entrada, copia);
  assert.deepEqual(a, b);
});

test('urlWhatsApp: bien codificada con encodeURIComponent', () => {
  const { texto } = armarMensaje({ lineas, nombre: 'Ana & Co', aclaracion: '¿Podés 100%?', actualizado: '2026-11-12' });
  const url = urlWhatsApp('5490000000000', texto);
  assert.ok(url.startsWith('https://wa.me/5490000000000?text='));
  const codificado = url.slice(url.indexOf('?text=') + 6);
  assert.equal(codificado, encodeURIComponent(texto));
  assert.equal(decodeURIComponent(codificado), texto);
  assert.doesNotMatch(codificado, /[ \n&#?•¼—×]/);
  assert.match(codificado, /%0A/);
  assert.match(codificado, /%26/); // &
  assert.match(codificado, /%E2%80%A2/); // •
  assert.match(codificado, /%C2%BC/); // ¼
});

test('urlWhatsApp: solo con número válido', () => {
  assert.equal(urlWhatsApp('abc', 'hola'), null);
  assert.equal(urlWhatsApp('', 'hola'), null);
  assert.equal(urlWhatsApp('549000000000/../x', 'hola'), null);
  assert.equal(urlWhatsApp('+5490000000000', 'hola'), null);
  assert.equal(urlWhatsApp(undefined, 'hola'), null);
  assert.equal(urlWhatsApp('5491112345678', 'hola'), 'https://wa.me/5491112345678?text=hola');
});
