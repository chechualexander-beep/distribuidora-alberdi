import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { armar, cspConSupabase } from '../tool/armar.mjs';

test('CSP: solo se agrega el servidor de Supabase del entorno', () => {
  const csp = "default-src 'none'; img-src 'self' data:; connect-src 'self'";
  assert.equal(cspConSupabase(csp, 'https://x.supabase.co'), "default-src 'none'; img-src 'self' data: https://x.supabase.co; connect-src https://x.supabase.co");
});

test('producción: config, CSP, vista previa y sin datos de demo', () => {
  const destino = join(mkdtempSync(join(tmpdir(), 'armar-')), 'produccion');
  try {
    armar('produccion', { destino });
    const config = readFileSync(join(destino, 'config.js'), 'utf8');
    assert.match(config, /entorno: 'produccion'/);
    assert.match(config, /https:\/\/vmbncsqapqdyffscwfwo\.supabase\.co/);
    const html = readFileSync(join(destino, 'index.html'), 'utf8');
    assert.match(html, /connect-src https:\/\/vmbncsqapqdyffscwfwo\.supabase\.co/);
    assert.match(html, /og:image" content="https:\/\/distribuidora-alberdi\.pages\.dev\/vista-previa\.jpg"/);
    assert.doesNotMatch(html, /VITRINA_META|blcgugdeluzxvpwqkhjq/);
    assert.match(readFileSync(join(destino, '_headers'), 'utf8'), /connect-src https:\/\/vmbncsqapqdyffscwfwo\.supabase\.co/);
    assert.equal(existsSync(join(destino, 'catalogo.json')), false);
    assert.equal(existsSync(join(destino, 'img')), false);
    assert.equal(existsSync(join(destino, 'logo.png')), true);
  } finally {
    rmSync(destino, { recursive: true, force: true });
  }
});

test('testing sin clave: error claro, no se arma un sitio a medias', () => {
  if (process.env.ALBERDI_TESTING_KEY) return;
  assert.throws(() => armar('testing', { destino: join(tmpdir(), 'no-deberia-existir') }), /ALBERDI_TESTING_KEY/);
});
