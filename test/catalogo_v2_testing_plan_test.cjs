'use strict';
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { PGlite } = require('../.dart_tool/commercial_sql_test/node_modules/@electric-sql/pglite');
const { createTestingEnvironment } = require('../catalogo-v2-testing/environment.cjs');

async function main() {
  const browserOrigin = 'http://127.0.0.1:4180';
  const publishableKey = 'sb_publishable_fixture_only_00000000';
  for (const origin of ['http://127.0.0.1:4179','https://distribuidora-alberdi.pages.dev','http://localhost:4180']) {
    assert.throws(() => createTestingEnvironment({ browserOrigin: origin, publishableKey }), /Origen/);
  }
  for (const key of [null, '', 'sb_secret_fixture_only_00000000', 'fixture.token.jwt']) {
    assert.throws(() => createTestingEnvironment({ browserOrigin, publishableKey: key }), /clave publicable/);
  }
  const cfg = createTestingEnvironment({ browserOrigin, publishableKey });
  assert.equal(cfg.project, 'blcgugdeluzxvpwqkhjq');
  for (const url of [...Object.values(cfg.rpc), cfg.photoBase]) {
    assert.equal(new URL(url).origin, 'https://blcgugdeluzxvpwqkhjq.supabase.co');
  }
  const csp = cfg.headers['Content-Security-Policy'];
  assert.match(csp, /connect-src https:\/\/blcgugdeluzxvpwqkhjq\.supabase\.co;/);
  assert.match(csp, /frame-ancestors 'none'/);
  assert.equal(cfg.headers['Cache-Control'], 'no-store');
  assert.match(cfg.storagePrefix, /catalogo-v2:testing:/);
  assert.throws(() => { cfg.rpc.order = 'http://example.invalid/'; }, TypeError);

  // In-memory schema intentionally lacks catalog dependencies to prove they
  // are reported as missing without attempting any RPC.
  const db = new PGlite();
  try {
    await db.exec(`
      create role anon; create role authenticated; create role service_role;
      create schema supabase_migrations; create schema storage;
      create table supabase_migrations.schema_migrations (version text primary key, name text, statements text[]);
      create table storage.buckets (id text, public boolean, file_size_limit bigint);
      create table stock_regimenes (id uuid, protocolo int, automatizacion_activa boolean, fecha_corte timestamptz, cerrado_at timestamptz);
      create table stock_transicion (singleton boolean, regimen_id uuid, mantenimiento boolean, paso_instalacion int);
      create table stock_configuracion (automatizacion_activa boolean, fecha_corte timestamptz, integracion_version int);
      create table stock_preparaciones (solicitud_id uuid, revision boolean);
      create table finalizacion_pedido_solicitudes (solicitud_id uuid);
      create table productos(id uuid, foto_path text);
      alter table productos enable row level security;
      grant select (foto_path) on productos to anon;
    `);
    const results = await db.exec(readFileSync('catalogo-v2-testing/preflight-readonly.sql','utf8'));
    const result = Object.values(results.flatMap(r => r.rows).at(0))[0];
    assert.equal(result.read_only, true);
    assert.equal(result.programacion_registrada, 0);
    assert.equal(result.history_pk, 'PRIMARY KEY (version)');
    assert.equal(result.functions.find(r => r.signature.startsWith('public.crear_pedido_catalogo')).oid, null);
    assert.equal(result.tables.find(r => r.name === 'public.productos').anon_column_access, true);
    assert.equal(result.tables.find(r => r.name === 'public.productos').anon_read, false);
    console.log('PASS: perfil cerrado, CSP, almacenamiento separado y preflight READ ONLY en memoria.');
  } finally {
    await db.close();
  }
}
main().catch(err => { console.error(err); process.exitCode = 1; });
