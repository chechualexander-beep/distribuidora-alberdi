import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  validarHorarios,
  validarCatalogo,
  describirErrores,
  leerTramo,
  formatearTramo,
  formatearHorarioDia,
  filasHorarios,
  textoHoy,
  DIAS_SEMANA,
} from '../src/core.js';

const HORARIOS_DEMO = {
  lunes: ['08:00-12:00', '17:00-21:00'],
  martes: ['08:00-21:00'],
  miercoles: ['08:00-21:00'],
  jueves: ['08:00-21:00'],
  viernes: ['08:00-21:00'],
  sabado: ['09:00-14:00'],
  domingo: [],
};

function rutas(resultado) {
  assert.ok(resultado.errores, 'se esperaban errores');
  return resultado.errores.map((e) => e.ruta);
}

/* ---------- Validación del bloque ---------- */

test('horarios válidos: conserva los tramos y completa los 7 días', () => {
  const r = validarHorarios(HORARIOS_DEMO);
  assert.equal(r.errores, undefined);
  assert.deepEqual(r.horarios, HORARIOS_DEMO);
  assert.deepEqual(Object.keys(r.horarios), [...DIAS_SEMANA]);
});

test('día ausente = cerrado (lista vacía)', () => {
  const r = validarHorarios({ lunes: ['08:00-12:00'] });
  assert.deepEqual(r.horarios.martes, []);
  assert.deepEqual(r.horarios.domingo, []);
  assert.equal(validarHorarios({}).horarios.lunes.length, 0);
});

test('día inválido (con tilde, mayúscula o inventado)', () => {
  for (const clave of ['miércoles', 'Lunes', 'sábado', 'feriado', 'lunes ']) {
    assert.deepEqual(rutas(validarHorarios({ [clave]: ['08:00-12:00'] })), [`comercio.horarios.${clave}`], clave);
  }
});

test('no es un objeto, o el día no es una lista', () => {
  for (const basura of ['lunes', 5, [], [['08:00-12:00']], true]) {
    assert.deepEqual(rutas(validarHorarios(basura)), ['comercio.horarios']);
  }
  assert.deepEqual(rutas(validarHorarios({ lunes: '08:00-12:00' })), ['comercio.horarios.lunes']);
  assert.deepEqual(rutas(validarHorarios({ lunes: { a: 1 } })), ['comercio.horarios.lunes']);
});

test('formato de hora inválido', () => {
  const malos = ['8:00-12', '8:00-12:00', '08:00-12', '08:00 - 12:00', '08:00–12:00', '25:00-26:00', '08:60-12:00', '24:00-12:00', '08:00-24:30', '08:00', '', 'abierto', 5, null, undefined];
  for (const tramo of malos) {
    assert.deepEqual(rutas(validarHorarios({ lunes: [tramo] })), ['comercio.horarios.lunes[0]'], String(tramo));
  }
});

test('el error indica el tramo exacto', () => {
  const r = validarHorarios({ martes: ['08:00-12:00', '8:00-12'] });
  assert.match(describirErrores(r.errores), /comercio\.horarios\.martes\[1\]: formato inválido/);
});

test('más de 3 tramos por día', () => {
  const tres = ['06:00-08:00', '10:00-12:00', '14:00-16:00'];
  assert.equal(validarHorarios({ lunes: tres }).errores, undefined);
  const r = validarHorarios({ lunes: [...tres, '18:00-20:00'] });
  assert.deepEqual(rutas(r), ['comercio.horarios.lunes']);
  assert.match(r.errores[0].mensaje, /máximo por día es 3/);
});

test('tramos superpuestos o desordenados', () => {
  assert.deepEqual(rutas(validarHorarios({ lunes: ['08:00-12:00', '11:00-14:00'] })), ['comercio.horarios.lunes[1]']);
  assert.deepEqual(rutas(validarHorarios({ lunes: ['17:00-21:00', '08:00-12:00'] })), ['comercio.horarios.lunes[1]']);
  assert.deepEqual(rutas(validarHorarios({ lunes: ['08:00-12:00', '08:00-12:00'] })), ['comercio.horarios.lunes[1]']);
  // Que se toquen no es pisarse.
  assert.equal(validarHorarios({ lunes: ['08:00-12:00', '12:00-14:00'] }).errores, undefined);
});

test('tramo que cruza la medianoche: solo como último del día', () => {
  assert.deepEqual(validarHorarios({ viernes: ['20:00-02:00'] }).horarios.viernes, ['20:00-02:00']);
  assert.deepEqual(validarHorarios({ viernes: ['08:00-12:00', '20:00-02:00'] }).errores, undefined);
  assert.deepEqual(rutas(validarHorarios({ viernes: ['20:00-02:00', '03:00-05:00'] })), ['comercio.horarios.viernes[0]']);
  assert.deepEqual(rutas(validarHorarios({ viernes: ['20:00-02:00', '21:00-23:00'] })), ['comercio.horarios.viernes[0]']);
});

test('desde igual a hasta', () => {
  assert.deepEqual(rutas(validarHorarios({ lunes: ['08:00-08:00'] })), ['comercio.horarios.lunes[0]']);
  assert.deepEqual(rutas(validarHorarios({ lunes: ['00:00-00:00'] })), ['comercio.horarios.lunes[0]']);
});

test('00:00-24:00 es válido solo y no admite otros tramos', () => {
  assert.deepEqual(validarHorarios({ sabado: ['00:00-24:00'] }).horarios.sabado, ['00:00-24:00']);
  assert.deepEqual(rutas(validarHorarios({ sabado: ['00:00-24:00', '10:00-12:00'] })), ['comercio.horarios.sabado[1]']);
  assert.deepEqual(rutas(validarHorarios({ sabado: ['08:00-12:00', '00:00-24:00'] })), ['comercio.horarios.sabado[1]']);
});

test('24:00 solo vale como "hasta"', () => {
  assert.deepEqual(validarHorarios({ lunes: ['20:00-24:00'] }).horarios.lunes, ['20:00-24:00']);
  assert.equal(leerTramo('24:00-24:00'), null);
});

/* ---------- Formateo ---------- */

test('formatearTramo: sin cero a la izquierda en la hora', () => {
  assert.equal(formatearTramo('08:00-12:00'), '8:00 a 12:00');
  assert.equal(formatearTramo('09:30-14:05'), '9:30 a 14:05');
  assert.equal(formatearTramo('20:00-02:00'), '20:00 a 2:00');
  assert.equal(formatearTramo('00:00-06:00'), '0:00 a 6:00');
  assert.throws(() => formatearTramo('8:00-12'), TypeError);
});

test('formatearHorarioDia', () => {
  assert.equal(formatearHorarioDia(['08:00-12:00', '17:00-21:00']), '8:00 a 12:00 y 17:00 a 21:00');
  assert.equal(formatearHorarioDia(['08:00-21:00']), '8:00 a 21:00');
  assert.equal(formatearHorarioDia(['06:00-08:00', '10:00-12:00', '14:00-16:00']), '6:00 a 8:00, 10:00 a 12:00 y 14:00 a 16:00');
  assert.equal(formatearHorarioDia(['00:00-24:00']), 'Las 24 hs');
  assert.equal(formatearHorarioDia([]), 'Cerrado');
  assert.equal(formatearHorarioDia(undefined), 'Cerrado');
});

/* ---------- "Hoy" (domingo = 0 en JavaScript; la lista empieza en lunes) ---------- */

test('filasHorarios: siete filas de lunes a domingo, con tildes', () => {
  const filas = filasHorarios(HORARIOS_DEMO, 3);
  assert.deepEqual(filas.map((f) => f.dia), ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo']);
  assert.equal(filas[0].texto, '8:00 a 12:00 y 17:00 a 21:00');
  assert.equal(filas[6].texto, 'Cerrado');
  assert.equal(filas[6].cerrado, true);
  assert.equal(filas[0].cerrado, false);
});

test('filasHorarios: marca "hoy" con el índice de Date.getDay()', () => {
  const hoyPorIndice = (i) => filasHorarios(HORARIOS_DEMO, i).findIndex((f) => f.esHoy);
  assert.equal(hoyPorIndice(0), 6, 'domingo (0) es la última fila');
  assert.equal(hoyPorIndice(1), 0, 'lunes (1) es la primera fila');
  assert.equal(hoyPorIndice(3), 2, 'miércoles');
  assert.equal(hoyPorIndice(6), 5, 'sábado');
  for (let i = 0; i <= 6; i++) assert.equal(filasHorarios(HORARIOS_DEMO, i).filter((f) => f.esHoy).length, 1);
});

test('textoHoy', () => {
  assert.equal(textoHoy(HORARIOS_DEMO, 1), 'Hoy: 8:00 a 12:00 y 17:00 a 21:00');
  assert.equal(textoHoy(HORARIOS_DEMO, 6), 'Hoy: 9:00 a 14:00');
  assert.equal(textoHoy(HORARIOS_DEMO, 0), 'Hoy: cerrado');
  assert.equal(textoHoy({ ...HORARIOS_DEMO, sabado: ['00:00-24:00'] }, 6), 'Hoy: las 24 hs');
});

test('día de hoy indeterminado: no hay línea "Hoy" ni fila marcada', () => {
  for (const malo of [undefined, null, NaN, -1, 7, 1.5, '1', {}]) {
    assert.equal(textoHoy(HORARIOS_DEMO, malo), null, String(malo));
    assert.equal(filasHorarios(HORARIOS_DEMO, malo).some((f) => f.esHoy), false, String(malo));
  }
});

/* ---------- Dentro del catálogo ---------- */

function catalogoConComercio(extra) {
  return {
    formato: 1,
    comercio: { id: 'a', nombre: 'A', whatsapp: '5491112345678', actualizado: '2026-11-12', ...extra },
    productos: [{ id: 'p1', nombre: 'Pan', categoria: 'X', unidad: 'unidad', precio_centavos: 100 }],
  };
}

test('catálogo con horarios y nota válidos', () => {
  const r = validarCatalogo(catalogoConComercio({ horarios: HORARIOS_DEMO, horarios_nota: '  Feriados: consultanos por WhatsApp ' }));
  assert.equal(r.ok, true);
  assert.deepEqual(r.catalogo.comercio.horarios, HORARIOS_DEMO);
  assert.equal(r.catalogo.comercio.horarios_nota, 'Feriados: consultanos por WhatsApp');
  assert.deepEqual(r.avisos, []);
});

test('un bloque de horarios inválido NO rompe el catálogo: se ignora y se avisa con la ruta', () => {
  const r = validarCatalogo(catalogoConComercio({ horarios: { lunes: ['8:00-12'], martes: ['08:00-21:00'] }, horarios_nota: 'Hola' }));
  assert.equal(r.ok, true);
  assert.equal(r.catalogo.comercio.horarios, undefined);
  assert.equal(r.catalogo.comercio.horarios_nota, undefined, 'sin horarios válidos tampoco hay nota');
  assert.deepEqual(r.avisos.map((a) => a.ruta), ['comercio.horarios.lunes[0]']);
  assert.equal(r.catalogo.productos.length, 1);
});

test('horarios que no son un objeto no rompen el catálogo', () => {
  for (const basura of ['abierto todos los días', 5, ['08:00-12:00']]) {
    const r = validarCatalogo(catalogoConComercio({ horarios: basura }));
    assert.equal(r.ok, true);
    assert.equal(r.catalogo.comercio.horarios, undefined);
    assert.deepEqual(r.avisos.map((a) => a.ruta), ['comercio.horarios']);
  }
});

test('horarios_nota inválida: se ignora solo la nota', () => {
  for (const nota of ['x'.repeat(121), 'con\u0000control', 42]) {
    const r = validarCatalogo(catalogoConComercio({ horarios: HORARIOS_DEMO, horarios_nota: nota }));
    assert.equal(r.ok, true);
    assert.deepEqual(r.catalogo.comercio.horarios, HORARIOS_DEMO, 'los horarios siguen');
    assert.equal(r.catalogo.comercio.horarios_nota, undefined);
    assert.deepEqual(r.avisos.map((a) => a.ruta), ['comercio.horarios_nota'], String(nota).slice(0, 10));
  }
  const justo = validarCatalogo(catalogoConComercio({ horarios: HORARIOS_DEMO, horarios_nota: 'x'.repeat(120) }));
  assert.equal(justo.catalogo.comercio.horarios_nota.length, 120);
  assert.deepEqual(justo.avisos, []);
});

test('sin horarios: el comercio no tiene rastro de horarios', () => {
  const r = validarCatalogo(catalogoConComercio({ horarios_nota: 'Suelta' }));
  assert.equal(r.ok, true);
  assert.equal('horarios' in r.catalogo.comercio, false);
  assert.equal('horarios_nota' in r.catalogo.comercio, false);
  assert.equal('horario' in r.catalogo.comercio, false);
});
