// Vista previa del enlace (WhatsApp, Telegram, redes): etiquetas <meta> del <head>.
//
// Estas aplicaciones leen el HTML estático y NO ejecutan JavaScript, así que la vista previa
// no se puede completar desde catalogo.json en el navegador: la completa quien arma el sitio
// (Super POS al exportar; en desarrollo, server.cjs). Este archivo define el contrato y NO se
// publica con el sitio (vive fuera de src/).
//
// Uso: reemplazar el marcador <!--VITRINA_META--> de src/index.html por el resultado de
// armarMeta({ nombre, urlPublica, foto, tema }) (y sacar el <title>Catálogo</title> genérico).

import { esMiniaturaSegura } from '../src/core.js';

export const MARCADOR = '<!--VITRINA_META-->';
export const DESCRIPCION = 'Mirá todos nuestros productos y hacé tu pedido.';
export const TEMA_POR_DEFECTO = 'verde';

/** Colores de acento de cada tema: los mismos de src/vitrina.css (un test los compara). */
export const COLORES_TEMA = Object.freeze({
  verde: '#1B6B4A',
  rojo: '#9B3A2E',
  azul: '#3A4486',
  ambar: '#8A5A00',
  alberdi: '#1A1A1A',
});

/** Escapa & < > " ' para usar un valor dentro de HTML o de un atributo. Emojis y tildes pasan intactos. */
export function escaparHtml(valor) {
  return String(valor)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

/** URL pública válida (http/https, sin usuario ni contraseña) o null. */
function leerUrlPublica(valor) {
  if (typeof valor !== 'string') return null;
  const texto = valor.trim();
  try {
    const url = new URL(texto);
    if ((url.protocol !== 'http:' && url.protocol !== 'https:') || url.username || url.password) return null;
    return { texto, url };
  } catch {
    return null;
  }
}

/**
 * Devuelve el bloque de etiquetas para el <head> (una por línea, sin sangría).
 *
 * - `nombre` (obligatorio): nombre del comercio.
 * - `urlPublica`: dirección pública del sitio (ej. "https://kiosco.ejemplo.com"). Sin ella no hay
 *   `og:url` ni `og:image`.
 * - `foto`: ruta relativa y segura de la imagen (las mismas reglas que `miniatura` del formato 1).
 *   Se publica como `urlPublica + "/" + foto`; si no es segura se descarta.
 * - `tema`: "verde", "rojo", "azul" o "ambar" (otro valor o falta: verde).
 */
export function armarMeta({ nombre, urlPublica, foto, tema } = {}) {
  const nombreLimpio = typeof nombre === 'string' ? nombre.replace(/[\u0000-\u001f\u007f]/g, ' ').trim() : '';
  if (nombreLimpio === '') throw new TypeError('armarMeta: falta el nombre del comercio');
  const n = escaparHtml(nombreLimpio);

  const publica = leerUrlPublica(urlPublica);
  const imagen =
    publica && typeof foto === 'string' && esMiniaturaSegura(foto)
      ? `${publica.url.origin}${publica.url.pathname.replace(/\/+$/, '')}/${foto}`
      : null;
  const color = COLORES_TEMA[tema] ?? COLORES_TEMA[TEMA_POR_DEFECTO];
  const descripcion = escaparHtml(DESCRIPCION);

  const lineas = [
    `<title>${n} · Catálogo</title>`,
    `<meta name="description" content="${descripcion}">`,
    '<meta property="og:type" content="website">',
    `<meta property="og:site_name" content="${n}">`,
    `<meta property="og:title" content="Catálogo de ${n}">`,
    `<meta property="og:description" content="${descripcion}">`,
    '<meta property="og:locale" content="es_AR">',
  ];
  if (publica) lineas.push(`<meta property="og:url" content="${escaparHtml(publica.texto)}">`);
  if (imagen) lineas.push(`<meta property="og:image" content="${escaparHtml(imagen)}">`);
  lineas.push(
    `<meta name="twitter:card" content="${imagen ? 'summary_large_image' : 'summary'}">`,
    `<meta name="theme-color" content="${color}">`,
  );
  return lineas.join('\n');
}
