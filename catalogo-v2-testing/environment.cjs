'use strict';

// Preparation only. This module creates configuration and does no I/O.
const project = 'blcgugdeluzxvpwqkhjq';
const supabase = 'https://' + project + '.supabase.co';
const origin = 'http://127.0.0.1:4180';

function createTestingEnvironment({ browserOrigin, publishableKey }) {
  if (browserOrigin !== origin) throw new Error('Origen web TESTING incompatible');
  if (typeof publishableKey !== 'string' ||
      !/^sb_publishable_[A-Za-z0-9_-]{16,}$/.test(publishableKey)) {
    throw new Error('Falta una clave publicable de TESTING');
  }
  // Publishable keys are opaque. Their provenance must be checked separately.
  return Object.freeze({
    project,
    origin,
    supabase,
    publishableKey,
    rpc: Object.freeze({
      catalog: supabase + '/rest/v1/rpc/obtener_catalogo_cliente',
      order: supabase + '/rest/v1/rpc/crear_pedido_catalogo',
    }),
    photoBase: supabase + '/storage/v1/object/public/productos-fotos/',
    storagePrefix: 'alberdi:catalogo-v2:testing:' + project + ':',
    headers: Object.freeze({
      'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' " +
        supabase + "; connect-src " + supabase + "; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      'Referrer-Policy': 'no-referrer',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      'X-Robots-Tag': 'noindex, nofollow',
    }),
  });
}

module.exports = { createTestingEnvironment };
