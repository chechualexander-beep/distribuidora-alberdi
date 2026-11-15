// Arma los sitios publicables del catálogo: dist/testing y dist/produccion.
// Cada uno es src/ + config.js del entorno + CSP con el servidor de Supabase + vista previa del enlace.
// La clave de TESTING se toma de la variable ALBERDI_TESTING_KEY (no se guarda en el repo).
//
//   node tool/armar.mjs              -> los dos (testing solo si hay ALBERDI_TESTING_KEY)
//   node tool/armar.mjs produccion   -> solo producción

import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { armarMeta, MARCADOR } from './meta.mjs';

const raiz = fileURLToPath(new URL('../', import.meta.url));
const REGEX_CLAVE = /^sb_publishable_[A-Za-z0-9_-]{16,}$/;

export const ENTORNOS = Object.freeze({
  produccion: {
    proyecto: 'vmbncsqapqdyffscwfwo',
    clave: 'sb_publishable_w_nz47b753qQkzv2pr7lhA_Yl4eZsTB',
    urlPublica: 'https://distribuidora-alberdi.pages.dev',
  },
  testing: {
    proyecto: 'blcgugdeluzxvpwqkhjq',
    clave: process.env.ALBERDI_TESTING_KEY ?? '',
    urlPublica: 'https://alberdi-catalogo-testing.pages.dev',
  },
});

/** CSP de src (solo 'self') -> CSP del sitio, que además permite hablar con su Supabase. */
export function cspConSupabase(texto, host) {
  return texto
    .replace("connect-src 'self'", `connect-src ${host}`)
    .replace("img-src 'self' data:", `img-src 'self' data: ${host}`);
}

export function armar(nombre, { destino = join(raiz, 'dist', nombre) } = {}) {
  const entorno = ENTORNOS[nombre];
  if (!entorno) throw new Error(`Entorno desconocido: ${nombre}`);
  if (!REGEX_CLAVE.test(entorno.clave)) {
    throw new Error(`Falta la clave publicable de ${nombre} (para testing: variable ALBERDI_TESTING_KEY).`);
  }
  const host = `https://${entorno.proyecto}.supabase.co`;
  rmSync(destino, { recursive: true, force: true });
  mkdirSync(destino, { recursive: true });
  // Sin datos ni fotos de demo.
  cpSync(join(raiz, 'src'), destino, {
    recursive: true,
    filter: (ruta) => !/[\\/](catalogo\.json|img)([\\/]|$)/.test(ruta.slice(join(raiz, 'src').length)),
  });
  writeFileSync(
    join(destino, 'config.js'),
    `// Generado por tool/armar.mjs (${nombre}). No editar a mano.\n` +
      `export const CONFIG = Object.freeze({\n  entorno: '${nombre}',\n  supabaseUrl: '${host}',\n  clavePublica: '${entorno.clave}',\n});\n`,
  );
  const headers = readFileSync(join(destino, '_headers'), 'utf8');
  writeFileSync(join(destino, '_headers'), cspConSupabase(headers, host).replace(/\n\/catalogo\.json\n {2}Cache-Control: no-cache\n/, '\n'));
  let html = readFileSync(join(destino, 'index.html'), 'utf8');
  html = cspConSupabase(html, host);
  const meta = armarMeta({ nombre: 'Distribuidora Alberdi', urlPublica: entorno.urlPublica, foto: 'vista-previa.jpg', tema: 'alberdi' });
  html = html.replace(MARCADOR, meta).replace(/\s*<title>Catálogo<\/title>/, '');
  if (nombre === 'testing') html = html.replace('<title>', '<title>[TESTING] ');
  writeFileSync(join(destino, 'index.html'), html);
  return destino;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const pedidos = process.argv.slice(2);
  const nombres = pedidos.length ? pedidos : ['produccion', ...(process.env.ALBERDI_TESTING_KEY ? ['testing'] : [])];
  for (const nombre of nombres) console.log(`Listo: ${armar(nombre)}`);
  if (!pedidos.length && !process.env.ALBERDI_TESTING_KEY) {
    console.log('(testing no se armó: falta ALBERDI_TESTING_KEY)');
  }
}
