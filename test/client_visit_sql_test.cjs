// PostgreSQL en memoria; no usa datos ni credenciales de producción.
// Dependencia de prueba: @electric-sql/pglite@0.5.8 en .dart_tool/commercial_sql_test.
const { PGlite } = require('../.dart_tool/commercial_sql_test/node_modules/@electric-sql/pglite');
const { readFileSync } = require('node:fs');
const assert = require('node:assert/strict');
(async () => {
  const db = new PGlite();
  try {
    await db.exec('create table clientes (id int primary key); insert into clientes values (1);');
    await db.exec(readFileSync('supabase/migrations/20260928190000_clientes_dia_visita.sql', 'utf8'));
    const day = async () => (await db.query('select dia_visita from clientes where id = 1')).rows[0].dia_visita;
    assert.equal(await day(), null);
    for (let i = 1; i <= 7; i++) {
      await db.query('update clientes set dia_visita = $1 where id = 1', [i]);
      assert.equal(await day(), i);
    }
    for (const invalid of [0, 8, -1]) {
      await assert.rejects(db.query('update clientes set dia_visita = $1 where id = 1', [invalid]), /clientes_dia_visita_check/);
    }
    await db.exec('update clientes set dia_visita = null where id = 1');
    assert.equal(await day(), null);
    console.log('OK: cliente existente sin día, lunes a domingo, cambio de día, quitar día y rechazo de días inválidos.');
  } finally { await db.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
