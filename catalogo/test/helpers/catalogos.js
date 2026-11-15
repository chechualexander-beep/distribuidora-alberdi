// Catálogos de prueba derivados del demo (src/catalogo.json). No se guardan como archivos:
// se arman acá para que siempre estén al día con el demo.

import { readFileSync } from 'node:fs';

export function catalogoDemo() {
  return JSON.parse(readFileSync(new URL('../../src/catalogo.json', import.meta.url), 'utf8'));
}

/** El demo sin ningún rastro de horarios (ni el campo viejo "horario"). */
export function catalogoSinHorarios() {
  const c = catalogoDemo();
  delete c.comercio.horarios;
  delete c.comercio.horarios_nota;
  delete c.comercio.horario;
  return c;
}

/** El demo con un bloque de horarios inválido ("8:00-12" y "25:00-26:00"): el catálogo tiene que seguir cargando. */
export function catalogoConHorariosInvalidos() {
  const c = catalogoDemo();
  c.comercio.horarios = { lunes: ['8:00-12'], martes: ['25:00-26:00'], miercoles: ['08:00-21:00'] };
  return c;
}
