import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const css = readFileSync(new URL('../src/vitrina.css', import.meta.url), 'utf8');

function luminancia(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
  const lineal = (c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  return 0.2126 * lineal(r) + 0.7152 * lineal(g) + 0.0722 * lineal(b);
}

function contraste(a, b) {
  const [claro, oscuro] = [luminancia(a), luminancia(b)].sort((x, y) => y - x);
  return (claro + 0.05) / (oscuro + 0.05);
}

// La primera aparición de cada variable es la de :root.
const variable = (nombre) => new RegExp(`--${nombre}:\\s*(#[0-9A-Fa-f]{6})`).exec(css)[1];

const base = {
  fondo: variable('fondo'),
  texto: variable('texto'),
  textoSec: variable('texto-sec'),
  insignia: variable('insignia'),
  blanco: variable('blanco'),
};

const temas = { verde: variable('acento') };
for (const t of ['rojo', 'azul', 'ambar', 'alberdi']) {
  temas[t] = new RegExp(`data-tema="${t}"\\]\\s*\\{\\s*--acento:\\s*(#[0-9A-Fa-f]{6})`).exec(css)[1];
}

const MINIMO = 4.5; // texto (WCAG 1.4.3)
const MINIMO_CONTROL = 3; // bordes de controles interactivos (WCAG 1.4.11)
const bordeControl = variable('borde-control');

test('tabla de contraste: cada par cumple su mínimo', () => {
  const pares = [
    // [descripción, color 1, color 2, mínimo]
    ['texto / fondo', base.texto, base.fondo, MINIMO],
    ['texto / blanco', base.texto, base.blanco, MINIMO],
    ['texto secundario / fondo', base.textoSec, base.fondo, MINIMO],
    ['texto secundario / blanco', base.textoSec, base.blanco, MINIMO],
    ['borde de control / fondo', bordeControl, base.fondo, MINIMO_CONTROL],
    ['borde de control / blanco', bordeControl, base.blanco, MINIMO_CONTROL],
    // Línea de confianza y visor de foto (ver también la prueba de que el CSS usa estos pares).
    ['confianza: texto secundario (14px) / fondo', base.textoSec, base.fondo, MINIMO],
    ['visor: nombre y precio (blanco) / fondo del visor (#1F2A24)', base.blanco, base.texto, MINIMO],
    ['visor: texto del botón Cerrar / fondo blanco del botón', base.texto, base.blanco, MINIMO],
    ['visor: anillo de foco amarillo / fondo del visor', base.insignia, base.texto, MINIMO_CONTROL],
    // Horarios de atención (ver también la prueba de que el CSS usa estos pares).
    ['horarios: texto del panel / fondo blanco', base.texto, base.blanco, MINIMO],
    ['horarios: "Cerrado" y nota / fondo blanco', base.textoSec, base.blanco, MINIMO],
    ...Object.entries(temas).flatMap(([tema, acento]) => [
      [`horarios ${tema}: resumen "Hoy:" y chevron (blanco / ${tema})`, base.blanco, acento, MINIMO],
      [`horarios ${tema}: pastilla "Hoy" (blanco / ${tema})`, base.blanco, acento, MINIMO],
    ]),
    ...Object.entries(temas).flatMap(([tema, acento]) => [
      [`acento ${tema} / blanco (texto blanco sobre el color)`, acento, base.blanco, MINIMO],
      [`acento ${tema} / blanco (control con borde del color)`, acento, base.blanco, MINIMO_CONTROL],
    ]),
  ];
  const fallas = pares
    .map(([nombre, a, b, minimo]) => ({ nombre, minimo, valor: contraste(a, b) }))
    .filter((p) => p.valor < p.minimo)
    .map((p) => `${p.nombre}: ${p.valor.toFixed(2)}:1 (mínimo ${p.minimo}:1)`);
  assert.deepEqual(fallas, []);
});

test('horarios: el CSS usa exactamente los pares de colores verificados', () => {
  const regla = (selector) => {
    const m = new RegExp(`${selector.replace(/[.[\]]/g, '\\$&')}\\s*\\{([^}]*)\\}`).exec(css);
    assert.ok(m, `falta la regla ${selector}`);
    return m[1];
  };
  assert.match(regla('.cabecera'), /background:\s*var\(--acento\)/);
  assert.match(regla('.cabecera'), /color:\s*var\(--blanco\)/);
  const resumen = regla('.horarios-resumen');
  assert.match(resumen, /color:\s*var\(--blanco\)/);
  assert.match(resumen, /min-height:\s*3rem/);
  const panel = regla('.horarios-panel');
  assert.match(panel, /background:\s*var\(--blanco\)/);
  assert.match(panel, /color:\s*var\(--texto\)/);
  assert.match(regla('.horarios-cerrado'), /color:\s*var\(--texto-sec\)/);
  assert.match(regla('.horarios-nota'), /color:\s*var\(--texto-sec\)/);
  const pastilla = regla('.pastilla-hoy');
  assert.match(pastilla, /background:\s*var\(--acento\)/);
  assert.match(pastilla, /color:\s*var\(--blanco\)/);
  // Texto de las filas: mínimo 1rem y alto mínimo de 2.75rem (44px), sin alturas fijas.
  const fila = regla('.horarios-fila');
  assert.match(fila, /min-height:\s*2\.75rem/);
  assert.match(fila, /font-size:\s*1rem/);
  assert.doesNotMatch(fila, /[^-]height:\s*\d/);
});

test('línea de confianza y visor: el CSS usa exactamente los pares de colores verificados', () => {
  const regla = (selector) => {
    const m = new RegExp(`${selector.replace(/[.[\]]/g, '\\$&')}\\s*\\{([^}]*)\\}`).exec(css);
    assert.ok(m, `falta la regla ${selector}`);
    return m[1];
  };
  const confianza = regla('.confianza');
  assert.match(confianza, /color:\s*var\(--texto-sec\)/);
  assert.match(confianza, /font-size:\s*\.875rem/, 'al menos 14px');

  const visor = regla('.visor');
  assert.match(visor, /background:\s*var\(--texto\)/);
  assert.match(visor, /color:\s*var\(--blanco\)/);
  const cerrar = regla('.visor-cerrar');
  assert.match(cerrar, /background:\s*var\(--blanco\)/);
  assert.match(cerrar, /color:\s*var\(--texto\)/);
  assert.match(cerrar, /min-height:\s*3rem/);
  // Sobre fondo oscuro, el gris secundario no alcanza: el visor fuerza blanco.
  assert.match(regla('.visor .precio-unidad, .visor .precio-antes'), /color:\s*var\(--blanco\)/);
  assert.match(regla('.visor :focus-visible'), /outline:\s*3px solid var\(--insignia\)/);
  // La insignia sobre las miniaturas no captura el toque (el botón de la foto tiene que recibirlo).
  assert.match(regla('.insignia'), /pointer-events:\s*none/);
});

test('los controles usan --borde-control y no los bordes decorativos', () => {
  const declaraciones = [...css.matchAll(/border(?:-color)?:\s*[^;]*var\(--(borde(?:-fuerte|-control)?)\)/g)];
  const usos = declaraciones.map((m) => m[1]);
  assert.ok(usos.includes('borde-control'), 'hay controles con --borde-control');
  assert.ok(!usos.includes('borde-fuerte'), '--borde-fuerte no debe usarse como borde (solo en barras de scroll)');
  // Los 6 controles: buscador, campos de texto, chips, "-", "Quitar" y botones secundarios.
  assert.ok(usos.filter((u) => u === 'borde-control').length >= 6);
});

test('la paleta base coincide con el diseño aprobado', () => {
  assert.deepEqual(
    { ...base },
    { fondo: '#FAFAF7', texto: '#1F2A24', textoSec: '#55605A', insignia: '#F5B82E', blanco: '#FFFFFF' },
  );
  assert.deepEqual(temas, { verde: '#1B6B4A', rojo: '#9B3A2E', azul: '#3A4486', ambar: '#8A5A00', alberdi: '#1A1A1A' });
});

test('contraste de texto >= 4.5:1 en la paleta base', () => {
  const pares = [
    ['texto sobre fondo', base.texto, base.fondo],
    ['texto sobre blanco', base.texto, base.blanco],
    ['texto secundario sobre fondo', base.textoSec, base.fondo],
    ['texto secundario sobre blanco', base.textoSec, base.blanco],
    ['texto sobre insignia', base.texto, base.insignia],
    ['blanco sobre texto (aviso de deshacer)', base.blanco, base.texto],
  ];
  for (const [nombre, a, b] of pares) {
    assert.ok(contraste(a, b) >= MINIMO, `${nombre}: ${contraste(a, b).toFixed(2)}`);
  }
});

test('contraste >= 4.5:1 en los 4 temas (blanco sobre color principal y al revés)', () => {
  for (const [tema, acento] of Object.entries(temas)) {
    assert.ok(contraste(base.blanco, acento) >= MINIMO, `blanco sobre ${tema}: ${contraste(base.blanco, acento).toFixed(2)}`);
  }
});

test('contraste >= 4.5:1 en las 4 parejas de iniciales', () => {
  const parejas = [...css.matchAll(/\.ini-(\d)\s*\{\s*background:\s*(#[0-9A-Fa-f]{6});\s*color:\s*(#[0-9A-Fa-f]{6});/g)];
  assert.equal(parejas.length, 4);
  assert.deepEqual(
    parejas.map((m) => [m[2].toUpperCase(), m[3].toUpperCase()]),
    [['#E6F0EA', '#1B6B4A'], ['#FBEBD0', '#8A5A00'], ['#E8EAF6', '#3A4486'], ['#F9E1DE', '#9B3A2E']],
  );
  for (const [, n, fondo, letra] of parejas) {
    assert.ok(contraste(fondo, letra) >= MINIMO, `ini-${n}: ${contraste(fondo, letra).toFixed(2)}`);
  }
});
