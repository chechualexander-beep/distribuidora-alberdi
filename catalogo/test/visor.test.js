// Visor de foto, carga de imágenes y línea de confianza, probados en la pantalla real
// con Edge/Chrome headless. Si no hay navegador, se omiten.

import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { cpSync, copyFileSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buscarNavegador, abrirNavegador } from './helpers/navegador.js';
import { catalogoDemo } from './helpers/catalogos.js';

const require = createRequire(import.meta.url);
const { crearServidor } = require('../server.cjs');

const ejecutable = buscarNavegador();
const opciones = ejecutable ? {} : { skip: 'no hay Edge/Chrome instalado (VITRINA_NAVEGADOR para indicar uno)' };

let raiz;
let servidor;
let base;
let navegador;

const pausa = (ms = 250) => new Promise((r) => setTimeout(r, ms));
const json = async (expresion) => JSON.parse(await navegador.evaluar(`JSON.stringify(${expresion})`));
const publicar = (catalogo) => writeFileSync(join(raiz, 'catalogo.json'), JSON.stringify(catalogo));

/** Foto de las filas/tarjetas del demo: p-001 (fila + Ofertas), p-005 (fila), p-009 (fila + Novedades). */
const MINIATURA_FILA = (id) => `document.querySelector('[data-id="${id}"] .miniatura-boton')`;
const MINIATURA_TARJETA = (id) => `document.querySelector('.carril .miniatura-boton[data-foto-id="${id}"]')`;

const estadoVisor = () =>
  json(`({
    abierto: !document.querySelector('.visor').hidden,
    hash: location.hash,
    dentro: location.href.startsWith(${JSON.stringify(base)}),
    inicioVisible: !document.getElementById('pantalla-inicio').hidden,
    focoClase: document.activeElement.className,
    focoFoto: document.activeElement.dataset.fotoId ?? null,
    bloqueado: document.documentElement.classList.contains('con-visor'),
    inerte: document.getElementById('pantalla-inicio').hasAttribute('inert'),
  })`);

before(async () => {
  if (!ejecutable) return;
  raiz = mkdtempSync(join(tmpdir(), 'vitrina-visor-'));
  cpSync(new URL('../src/', import.meta.url), raiz, { recursive: true });
  // 80 fotos distintas para comprobar que no se descargan todas de golpe.
  for (let i = 0; i < 80; i++) copyFileSync(join(raiz, 'img', 'p-001.svg'), join(raiz, 'img', `f-${i}.svg`));
  servidor = crearServidor({ raiz });
  await new Promise((r) => servidor.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${servidor.address().port}/`;
  navegador = await abrirNavegador(ejecutable);
});

after(async () => {
  if (!ejecutable) return;
  await navegador?.cerrar();
  await new Promise((r) => servidor.close(r));
  rmSync(raiz, { recursive: true, force: true });
});

/* ---------- Visor ---------- */

test('abrir el visor desde una fila: diálogo accesible, foco en Cerrar y misma foto', opciones, async () => {
  publicar(catalogoDemo());
  await navegador.abrir(base);
  await navegador.evaluar(`${MINIATURA_FILA('p-005')}.click()`);
  await pausa();
  const v = await json(`(() => {
    const visor = document.querySelector('.visor');
    const cerrar = visor.querySelector('.visor-cerrar').getBoundingClientRect();
    const caja = visor.getBoundingClientRect();
    return {
      role: visor.getAttribute('role'),
      modal: visor.getAttribute('aria-modal'),
      nombre: visor.getAttribute('aria-label'),
      foco: document.activeElement.className,
      hash: location.hash,
      srcVisor: visor.querySelector('img').src,
      srcMiniatura: document.querySelector('[data-id="p-005"] .miniatura img').src,
      ajuste: getComputedStyle(visor.querySelector('img')).objectFit,
      cerrarTexto: visor.querySelector('.visor-cerrar').textContent,
      cerrarAlto: cerrar.height,
      cerrarArriba: cerrar.top < 120,
      cerrarDerecha: cerrar.right > innerWidth - 40,
      leyenda: visor.querySelector('figcaption').textContent,
      cubre: [caja.left, caja.top, caja.width, caja.height],
      ancho: innerWidth,
      alto: innerHeight,
      fondo: getComputedStyle(visor).backgroundColor,
      bloqueado: getComputedStyle(document.documentElement).overflow,
      inerte: document.getElementById('pantalla-inicio').hasAttribute('inert'),
      zoom: document.querySelector('meta[name=viewport]').content,
      toqueVisor: getComputedStyle(visor).touchAction,
    };
  })()`);
  assert.equal(v.role, 'dialog');
  assert.equal(v.modal, 'true');
  assert.equal(v.nombre, 'Foto de Queso cremoso');
  assert.equal(v.foco, 'visor-cerrar');
  assert.equal(v.hash, '#/foto/p-005');
  assert.equal(v.srcVisor, v.srcMiniatura, 'es la misma URL que la miniatura');
  assert.equal(v.ajuste, 'contain');
  assert.equal(v.cerrarTexto, 'Cerrar');
  assert.ok(v.cerrarAlto >= 48, `Cerrar mide ${v.cerrarAlto}px`);
  assert.ok(v.cerrarArriba && v.cerrarDerecha, 'Cerrar está arriba a la derecha');
  assert.match(v.leyenda, /Queso cremoso/);
  assert.match(v.leyenda.replaceAll(' ', ' '), /\$ 8\.000/);
  assert.deepEqual(v.cubre, [0, 0, v.ancho, v.alto], 'cubre toda la pantalla');
  assert.equal(v.fondo, 'rgb(31, 42, 36)');
  assert.equal(v.bloqueado, 'hidden', 'sin scroll de la página de fondo');
  assert.equal(v.inerte, true);
  assert.doesNotMatch(v.zoom, /user-scalable|maximum-scale/, 'no se bloquea el zoom');
  assert.notEqual(v.toqueVisor, 'none', 'el visor no bloquea el zoom con dos dedos');
});

test('abrir el visor desde una tarjeta de Novedades y de Ofertas', opciones, async () => {
  publicar(catalogoDemo());
  await navegador.abrir(base);
  await navegador.evaluar(`${MINIATURA_TARJETA('p-009')}.click()`);
  await pausa();
  let e = await json(`({ n: document.querySelector('.visor').getAttribute('aria-label'), h: location.hash, f: document.activeElement.className })`);
  assert.deepEqual(e, { n: 'Foto de Yerba mate suave con palo, paquete de 500 g', h: '#/foto/p-009', f: 'visor-cerrar' });
  await navegador.evaluar("document.querySelector('.visor-cerrar').click()");
  await pausa();
  await navegador.evaluar(`${MINIATURA_TARJETA('p-001')}.click()`);
  await pausa();
  e = await json(`({ n: document.querySelector('.visor').getAttribute('aria-label'), h: location.hash })`);
  assert.deepEqual(e, { n: 'Foto de Alfajor triple', h: '#/foto/p-001' });
});

for (const [nombre, cerrar] of [
  ['el botón Cerrar', "document.querySelector('.visor-cerrar').click()"],
  ['la tecla Escape', "document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))"],
  ['tocar fuera de la foto', "document.querySelector('.visor').click()"],
  ['tocar la leyenda (fuera de la foto)', "document.querySelector('.visor-nombre').click()"],
  ['el botón Atrás', 'history.back()'],
]) {
  test(`se cierra con ${nombre} sin salir de la vitrina y el foco vuelve a la miniatura`, opciones, async () => {
    publicar(catalogoDemo());
    await navegador.abrir(base);
    await navegador.evaluar(`${MINIATURA_FILA('p-005')}.click()`);
    await pausa();
    assert.equal((await estadoVisor()).abierto, true);

    await navegador.evaluar(cerrar);
    await pausa(350);
    const e = await estadoVisor();
    assert.equal(e.abierto, false);
    assert.equal(e.dentro, true, 'seguimos en la vitrina');
    assert.equal(e.inicioVisible, true);
    assert.ok(e.hash === '' || e.hash === '#/', `hash: ${e.hash}`);
    assert.equal(e.bloqueado, false);
    assert.equal(e.inerte, false);
    assert.equal(e.focoFoto, 'p-005', 'el foco volvió a la miniatura');
  });
}

test('tocar la foto no cierra el visor', opciones, async () => {
  publicar(catalogoDemo());
  await navegador.abrir(base);
  await navegador.evaluar(`${MINIATURA_FILA('p-005')}.click()`);
  await pausa();
  await navegador.evaluar("document.querySelector('.visor-img').click()");
  await pausa();
  assert.equal((await estadoVisor()).abierto, true);
});

test('Tab no saca el foco del visor', opciones, async () => {
  publicar(catalogoDemo());
  await navegador.abrir(base);
  await navegador.evaluar(`${MINIATURA_FILA('p-005')}.click()`);
  await pausa();
  await navegador.evaluar("document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true }))");
  assert.equal((await estadoVisor()).focoClase, 'visor-cerrar');
});

test('entrada directa a #/foto/<id> válido muestra el visor; Cerrar vuelve al inicio sin salir', opciones, async () => {
  publicar(catalogoDemo());
  await navegador.abrir(`${base}#/foto/p-005`);
  await pausa();
  let e = await estadoVisor();
  assert.equal(e.abierto, true);
  assert.equal(e.focoClase, 'visor-cerrar');
  await navegador.evaluar("document.querySelector('.visor-cerrar').click()");
  await pausa(350);
  e = await estadoVisor();
  assert.equal(e.abierto, false);
  assert.equal(e.dentro, true);
  assert.equal(e.hash, '#/');
  assert.equal(e.focoFoto, 'p-005');
});

test('entrada directa a un producto inexistente, sin foto o con hash roto vuelve al inicio', opciones, async () => {
  publicar(catalogoDemo());
  for (const hash of ['#/foto/p-002', '#/foto/no-existe', '#/foto/', '#/foto/%E0%A4%A']) {
    await navegador.abrir(`${base}${hash}`);
    await pausa();
    const e = await estadoVisor();
    assert.equal(e.abierto, false, hash);
    assert.equal(e.hash, '#/', hash);
    assert.equal(e.inicioVisible, true, hash);
    assert.equal(await navegador.evaluar("!!document.querySelector('.error-pantalla')"), false, hash);
  }
});

test('un producto oculto (visible:false) con foto no abre el visor', opciones, async () => {
  const c = catalogoDemo();
  c.productos.find((p) => p.id === 'p-005').visible = false;
  publicar(c);
  await navegador.abrir(`${base}#/foto/p-005`);
  await pausa();
  const e = await estadoVisor();
  assert.equal(e.abierto, false);
  assert.equal(e.hash, '#/');
});

test('solo los productos con foto tienen botón; sin foto muestran iniciales', opciones, async () => {
  publicar(catalogoDemo());
  await navegador.abrir(base);
  const r = await json(`(() => {
    const botones = [...document.querySelectorAll('.miniatura-boton')];
    return {
      total: botones.length,
      etiquetas: botones.map((b) => b.getAttribute('aria-label')).sort(),
      tamanos: botones.map((b) => { const r = b.getBoundingClientRect(); return [Math.round(r.width), Math.round(r.height)]; }),
      sinFotoBoton: !!document.querySelector('[data-id="p-002"] .miniatura-boton'),
      sinFotoIniciales: document.querySelector('[data-id="p-002"] .iniciales')?.textContent,
      botonesFueraDeMiniaturas: document.querySelectorAll('.miniatura:not(:has(img)) .miniatura-boton').length,
    };
  })()`);
  assert.equal(r.total, 5, '3 filas + 1 tarjeta de Novedades + 1 de Ofertas');
  assert.deepEqual(r.etiquetas, [
    'Ver foto de Alfajor triple',
    'Ver foto de Alfajor triple',
    'Ver foto de Queso cremoso',
    'Ver foto de Yerba mate suave con palo, paquete de 500 g',
    'Ver foto de Yerba mate suave con palo, paquete de 500 g',
  ]);
  for (const [ancho, alto] of r.tamanos) assert.ok(ancho >= 48 && alto >= 48, `zona tocable ${ancho}x${alto}`);
  assert.equal(r.sinFotoBoton, false);
  assert.equal(r.sinFotoIniciales, 'CD');
  assert.equal(r.botonesFueraDeMiniaturas, 0);
});

test('si una foto no carga, la miniatura cae a iniciales y el botón desaparece', opciones, async () => {
  const c = catalogoDemo();
  c.productos.find((p) => p.id === 'p-005').miniatura = 'img/no-existe.jpg';
  publicar(c);
  await navegador.abrir(base);
  await pausa(500);
  const r = await json(`({
    boton: !!document.querySelector('[data-id="p-005"] .miniatura-boton'),
    iniciales: document.querySelector('[data-id="p-005"] .iniciales')?.textContent,
  })`);
  assert.deepEqual(r, { boton: false, iniciales: 'QC' });
});

/* ---------- Carga de imágenes ---------- */

test('las imágenes de listas y carriles son perezosas y tienen width y height', opciones, async () => {
  publicar(catalogoDemo());
  await navegador.abrir(base);
  const r = await json(`[...document.querySelectorAll('.miniatura img')].map((i) => ({
    lazy: i.getAttribute('loading'),
    decoding: i.getAttribute('decoding'),
    w: i.getAttribute('width'),
    h: i.getAttribute('height'),
    tarjeta: !!i.closest('.tarjeta'),
  }))`);
  assert.equal(r.length, 5);
  for (const i of r) {
    assert.equal(i.lazy, 'lazy');
    assert.equal(i.decoding, 'async');
    assert.deepEqual([i.w, i.h], i.tarjeta ? ['158', '84'] : ['72', '72']);
  }
});

test('con 80 fotos no se descargan todas de golpe', opciones, async () => {
  const c = catalogoDemo();
  c.productos = Array.from({ length: 80 }, (_, i) => ({
    id: `f-${i}`,
    nombre: `Producto con foto ${i}`,
    categoria: 'Varios',
    unidad: 'unidad',
    precio_centavos: 1000 + i,
    miniatura: `img/f-${i}.svg`,
  }));
  publicar(c);
  await navegador.abrir(base);
  await pausa(600);
  const r = await json(`({
    imagenes: document.querySelectorAll('.miniatura img').length,
    pedidas: performance.getEntriesByType('resource').filter((e) => /\\/img\\/f-\\d+\\.svg/.test(e.name)).length,
    todasLazy: [...document.querySelectorAll('.miniatura img')].every((i) => i.loading === 'lazy'),
  })`);
  assert.equal(r.imagenes, 80);
  assert.equal(r.todasLazy, true);
  assert.ok(r.pedidas < 80, `se pidieron ${r.pedidas} de 80 fotos al cargar`);
});

/* ---------- Línea de confianza ---------- */

test('línea de confianza visible debajo del encabezado, con texto secundario de 14px o más', opciones, async () => {
  publicar(catalogoDemo());
  await navegador.abrir(base);
  const r = await json(`(() => {
    const p = document.querySelector('.confianza');
    const caja = p.getBoundingClientRect();
    const estilo = getComputedStyle(p);
    return {
      texto: p.textContent,
      visible: caja.height > 0 && p.offsetParent !== null && estilo.visibility === 'visible' && estilo.display !== 'none',
      tamano: parseFloat(estilo.fontSize),
      color: estilo.color,
      debajoDeCabecera: caja.top >= document.querySelector('.cabecera').getBoundingClientRect().bottom,
      encimaDelBuscador: caja.bottom <= document.querySelector('.buscador').getBoundingClientRect().top,
    };
  })()`);
  assert.equal(r.texto, 'Este es el catálogo de Kiosco de Ejemplo. Tu pedido llega directo a la distribuidora: no hace falta registrarte ni pagar nada ahora.');
  assert.equal(r.visible, true);
  assert.ok(r.tamano >= 14, `${r.tamano}px`);
  assert.equal(r.color, 'rgb(85, 96, 90)'); // #55605A
  assert.equal(r.debajoDeCabecera, true);
  assert.equal(r.encimaDelBuscador, true);
});

test('línea de confianza: el nombre entra como texto, no como HTML', opciones, async () => {
  const c = catalogoDemo();
  c.comercio.nombre = '<b>Kiosco</b> & "Co" <img src=x>';
  publicar(c);
  await navegador.abrir(base);
  const r = await json(`({
    texto: document.querySelector('.confianza').textContent,
    hijos: document.querySelector('.confianza').children.length,
    imagenesRaras: document.querySelectorAll('img[src="x"]').length,
  })`);
  assert.equal(r.texto, 'Este es el catálogo de <b>Kiosco</b> & "Co" <img src=x>. Tu pedido llega directo a la distribuidora: no hace falta registrarte ni pagar nada ahora.');
  assert.equal(r.hijos, 0);
  assert.equal(r.imagenesRaras, 0);
});

test('línea de confianza en 360x640 con letra al 200% no se corta', opciones, async () => {
  publicar(catalogoDemo());
  await navegador.abrir(base, { ancho: 360, alto: 640, escalaLetra: '200%' });
  const r = await json(`(() => {
    const p = document.querySelector('.confianza');
    const caja = p.getBoundingClientRect();
    return { scroll: document.documentElement.scrollWidth, ancho: innerWidth, cortado: p.scrollWidth > p.clientWidth + 1, izquierda: caja.left, derecha: caja.right };
  })()`);
  assert.equal(r.scroll, r.ancho);
  assert.equal(r.cortado, false);
  assert.ok(r.izquierda >= 0 && r.derecha <= r.ancho + 0.5);
});

/* ---------- Letra al 200% ---------- */

test('el visor en 360x640 con letra al 200% no se corta ni se superpone', opciones, async () => {
  publicar(catalogoDemo());
  await navegador.abrir(base, { ancho: 360, alto: 640, escalaLetra: '200%' });
  await navegador.evaluar(`${MINIATURA_FILA('p-009')}.click()`);
  await pausa();
  const r = await json(`(() => {
    const visor = document.querySelector('.visor');
    const rect = (s) => { const r = visor.querySelector(s).getBoundingClientRect(); return { t: r.top, b: r.bottom, l: r.left, r: r.right, h: r.height }; };
    return {
      scrollPagina: document.documentElement.scrollWidth,
      ancho: innerWidth,
      scrollVisor: visor.scrollWidth,
      anchoVisor: visor.clientWidth,
      cerrar: rect('.visor-cerrar'),
      img: rect('.visor-img'),
      nombre: rect('.visor-nombre'),
      nombreCortado: visor.querySelector('.visor-nombre').scrollWidth > visor.querySelector('.visor-nombre').clientWidth + 1,
    };
  })()`);
  assert.equal(r.scrollPagina, r.ancho, 'sin scroll horizontal de la página');
  assert.ok(r.scrollVisor <= r.anchoVisor, 'sin scroll horizontal del visor');
  assert.ok(r.cerrar.r <= r.ancho + 0.5 && r.cerrar.l >= 0 && r.cerrar.t >= 0, 'Cerrar entra en pantalla');
  assert.ok(r.cerrar.h >= 48);
  assert.ok(r.img.h > 100, `la foto mide ${r.img.h}px de alto`);
  assert.ok(r.cerrar.b <= r.img.t + 1, 'Cerrar no pisa la foto');
  assert.ok(r.img.b <= r.nombre.t + 1, 'el nombre no pisa la foto');
  assert.equal(r.nombreCortado, false);
});
