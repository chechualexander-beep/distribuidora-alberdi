// Pruebas de la pantalla real (DOM) con Edge/Chrome headless. Si no hay navegador, se saltean.

import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { cpSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buscarNavegador, abrirNavegador } from './helpers/navegador.js';
import { catalogoDemo, catalogoSinHorarios, catalogoConHorariosInvalidos } from './helpers/catalogos.js';

const require = createRequire(import.meta.url);
const { crearServidor } = require('../server.cjs');

const ejecutable = buscarNavegador();
const opciones = ejecutable ? {} : { skip: 'no hay Edge/Chrome instalado (VITRINA_NAVEGADOR para indicar uno)' };

let raiz;
let servidor;
let base;
let navegador;

const sinDuros = (texto) => texto.replaceAll(' ', ' ');

function publicar(catalogo) {
  writeFileSync(join(raiz, 'catalogo.json'), JSON.stringify(catalogo));
}

before(async () => {
  if (!ejecutable) return;
  raiz = mkdtempSync(join(tmpdir(), 'vitrina-pantalla-'));
  cpSync(new URL('../src/', import.meta.url), raiz, { recursive: true });
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

test('con horarios: el desplegable nace cerrado y muestra el resumen de hoy', opciones, async () => {
  publicar(catalogoDemo());
  await navegador.abrir(base, { diaDeLaSemana: 1 }); // lunes
  const r = JSON.parse(
    await navegador.evaluar(`JSON.stringify((() => {
      const d = document.querySelector('details.horarios');
      const resumen = d.querySelector('summary');
      return {
        abierto: d.open,
        titulo: resumen.querySelector('.horarios-titulo').textContent,
        hoy: resumen.querySelector('.horarios-hoy').textContent,
        alto: resumen.getBoundingClientRect().height,
        estiloInline: resumen.getAttribute('style'),
        dentroDeCabecera: !!d.closest('.cabecera'),
        cabecera: document.querySelector('.cabecera').textContent,
      };
    })())`),
  );
  assert.equal(r.abierto, false);
  assert.equal(r.titulo, 'Horarios de atención');
  assert.equal(sinDuros(r.hoy), 'Hoy: 8:00 a 12:00 y 17:00 a 21:00');
  assert.ok(r.alto >= 48, `el resumen mide ${r.alto}px`);
  assert.equal(r.estiloInline, null);
  assert.equal(r.dentroDeCabecera, true);
  assert.doesNotMatch(r.cabecera, /Abierto/);
});

test('con horarios: siete filas de lunes a domingo, hoy en negrita con pastilla y nota', opciones, async () => {
  publicar(catalogoDemo());
  await navegador.abrir(base, { diaDeLaSemana: 3 }); // miércoles
  const r = JSON.parse(
    await navegador.evaluar(`JSON.stringify((() => {
      const filas = [...document.querySelectorAll('.horarios-fila')];
      return {
        dias: filas.map((f) => f.querySelector('dt').firstChild.textContent.trim()),
        tramos: filas.map((f) => f.querySelector('dd').textContent),
        hoy: filas.map((f) => f.classList.contains('es-hoy')),
        pastillas: filas.map((f) => !!f.querySelector('.pastilla-hoy')),
        pesoHoy: getComputedStyle(filas[2].querySelector('dd')).fontWeight,
        pesoOtro: getComputedStyle(filas[1].querySelector('dd')).fontWeight,
        cerradoColor: getComputedStyle(filas[6].querySelector('dd')).color,
        nota: document.querySelector('.horarios-nota').textContent,
      };
    })())`),
  );
  assert.deepEqual(r.dias, ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo']);
  assert.deepEqual(r.tramos.map(sinDuros), ['8:00 a 12:00 y 17:00 a 21:00', '8:00 a 21:00', '8:00 a 21:00', '8:00 a 21:00', '8:00 a 21:00', '9:00 a 14:00', 'Cerrado']);
  assert.deepEqual(r.hoy, [false, false, true, false, false, false, false]);
  assert.deepEqual(r.pastillas, [false, false, true, false, false, false, false]);
  assert.ok(Number(r.pesoHoy) >= 700 && Number(r.pesoOtro) < 700);
  assert.equal(r.cerradoColor, 'rgb(85, 96, 90)'); // #55605A
  assert.equal(r.nota, 'Feriados: consultanos por WhatsApp');
});

test('domingo (índice 0 de JavaScript) marca la última fila y dice "Hoy: cerrado"', opciones, async () => {
  publicar(catalogoDemo());
  await navegador.abrir(base, { diaDeLaSemana: 0 });
  const r = JSON.parse(
    await navegador.evaluar(`JSON.stringify({
      hoy: document.querySelector('.horarios-hoy').textContent,
      fila: [...document.querySelectorAll('.horarios-fila')].findIndex((f) => f.classList.contains('es-hoy')),
    })`),
  );
  assert.equal(r.hoy, 'Hoy: cerrado');
  assert.equal(r.fila, 6);
});

test('abre y cierra con el resumen, y vuelve cerrado tras ir al pedido y volver', opciones, async () => {
  publicar(catalogoDemo());
  await navegador.abrir(base, { diaDeLaSemana: 1 });
  const estado = async () => navegador.evaluar("document.querySelector('details.horarios').open");
  const altoFilas = () =>
    navegador.evaluar("Math.min(...[...document.querySelectorAll('.horarios-fila')].map((f) => f.getBoundingClientRect().height))");

  assert.equal(await estado(), false);
  await navegador.evaluar("document.querySelector('.horarios-resumen').click()");
  assert.equal(await estado(), true);
  assert.ok((await altoFilas()) >= 44, 'las filas miden al menos 44px');
  await navegador.evaluar("document.querySelector('.horarios-resumen').click()");
  assert.equal(await estado(), false);

  await navegador.evaluar("document.querySelector('.horarios-resumen').click()");
  assert.equal(await estado(), true);
  await navegador.evaluar("location.hash = '#/pedido'");
  await new Promise((r) => setTimeout(r, 200));
  await navegador.evaluar("location.hash = '#/'");
  await new Promise((r) => setTimeout(r, 200));
  assert.equal(await estado(), false, 'al volver del pedido el panel está cerrado');
});

test('en 360x640 con letra al 200% no hay scroll horizontal ni filas que se salgan', opciones, async () => {
  publicar(catalogoDemo());
  await navegador.abrir(base, { ancho: 360, alto: 640, diaDeLaSemana: 1, escalaLetra: '200%' });
  await navegador.evaluar("document.querySelector('.horarios-resumen').click()");
  const r = JSON.parse(
    await navegador.evaluar(`JSON.stringify({
      scroll: document.documentElement.scrollWidth,
      ancho: innerWidth,
      sobran: [...document.querySelectorAll('.horarios-fila, .horarios-resumen')].filter((e) => e.scrollWidth > e.clientWidth + 1).length,
    })`),
  );
  assert.equal(r.scroll, r.ancho);
  assert.equal(r.sobran, 0);
});

test('sin horarios: el encabezado queda con el nombre y la pastilla, sin ningún rastro', opciones, async () => {
  publicar(catalogoSinHorarios());
  await navegador.abrir(base, { diaDeLaSemana: 1 });
  const r = JSON.parse(
    await navegador.evaluar(`JSON.stringify({
      detalles: document.querySelectorAll('details').length,
      horarios: !!document.querySelector('.horarios, .horarios-resumen, .horarios-panel, .horarios-nota'),
      cabecera: document.querySelector('.cabecera').innerText.split('\\n').map((l) => l.trim()).filter(Boolean).join('\\n'),
      html: document.documentElement.outerHTML,
    })`),
  );
  assert.equal(r.detalles, 0);
  assert.equal(r.horarios, false);
  assert.equal(r.cabecera, 'Kiosco de Ejemplo\nHola, Cliente de prueba\nPrecios actualizados el 12/11/2026');
  // El HTML (sin los <link> de la hoja de estilos) no menciona horarios en ningún lado.
  assert.doesNotMatch(r.html.replace(/<style[\s\S]*?<\/style>/g, ''), /horario|Abierto/i);
});

test('horarios inválidos: el catálogo carga igual, sin horarios, y se avisa por consola con la ruta', opciones, async () => {
  publicar(catalogoConHorariosInvalidos());
  await navegador.abrir(base, { diaDeLaSemana: 1 });
  const r = JSON.parse(
    await navegador.evaluar(`JSON.stringify({
      error: !!document.querySelector('.error-pantalla'),
      productos: document.querySelectorAll('.fila-caja').length,
      horarios: !!document.querySelector('.horarios'),
    })`),
  );
  assert.equal(r.error, false, 'no se muestra la pantalla de error');
  assert.equal(r.horarios, false);
  assert.ok(r.productos > 0);
  const avisos = navegador.mensajesDeConsola().filter((m) => m.tipo === 'warning').map((m) => m.texto).join('\n');
  assert.match(avisos, /comercio\.horarios\.lunes\[0\]/);
  assert.match(avisos, /comercio\.horarios\.martes\[0\]/);
});
