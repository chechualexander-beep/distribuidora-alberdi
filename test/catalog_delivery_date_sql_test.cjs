const { PGlite } = require('../.dart_tool/commercial_sql_test/node_modules/@electric-sql/pglite');
const { readFileSync } = require('node:fs');
const assert = require('node:assert/strict');

(async () => {
  const db = new PGlite();
  const id = '00000000-0000-4000-8000-000000000001';
  const schedule = () => db.query("select programar_entrega_catalogo($1, '2026-11-12')", [id]);
  try {
    await db.exec(`
      create role anon; create role authenticated; create role service_role;
      create function public.stock_exigir_admin() returns void language plpgsql as $$
      begin if current_setting('test.admin',true) <> 'yes' then
        raise exception 'admin requerido' using errcode='PT403'; end if; end $$;
      create function public.stock_exigir_operativo() returns void language plpgsql as $$
      begin if current_setting('test.operativo',true) <> 'yes' then
        raise exception 'mantenimiento' using errcode='PT409'; end if; end $$;
      create table pedidos (
        id uuid primary key, fecha_entrega date, origen text, tipo_operacion text,
        resultado_entrega text, estado text, facturado boolean, total numeric
      );
      create table stock_preparaciones (pedido_id uuid);
      create table pedido_detalles (pedido_id uuid, precio numeric);
      insert into pedidos values ('${id}',null,'catalogo','pedido','pendiente','pendiente',true,800);
      insert into pedido_detalles values ('${id}',800);
      set test.admin='no'; set test.operativo='yes';
    `);
    await db.exec(readFileSync('supabase/migrations/20261106010000_programar_entrega_catalogo.sql','utf8'));
    const allowed = async (role) => (await db.query(
      "select has_function_privilege($1, 'public.programar_entrega_catalogo(uuid,date)', 'execute') allowed", [role]
    )).rows[0].allowed;
    assert.equal(await allowed('authenticated'), true);
    assert.equal(await allowed('anon'), false);
    assert.equal(await allowed('service_role'), false);
    await db.exec('set role authenticated');
    await assert.rejects(schedule, /admin requerido/);
    await db.exec("reset role; set test.admin='yes'; set test.operativo='no'");
    await assert.rejects(schedule, /mantenimiento/);
    await db.exec("set test.operativo='yes'; update pedidos set estado='cancelado'");
    await assert.rejects(schedule, /no está disponible/);
    await db.exec(`update pedidos set estado='pendiente'; insert into stock_preparaciones values ('${id}')`);
    await assert.rejects(schedule, /no está disponible/);
    await db.exec('delete from stock_preparaciones; update pedidos set origen=\'interno\'');
    await assert.rejects(schedule, /no está disponible/);
    await db.exec("update pedidos set origen='catalogo', resultado_entrega='entregado'");
    await assert.rejects(schedule, /no está disponible/);
    await db.exec("update pedidos set resultado_entrega='pendiente'; set role authenticated");
    await assert.rejects(db.query('select programar_entrega_catalogo($1, null)', [id]), /fecha de entrega válida/);
    await schedule();
    await assert.rejects(db.query("select programar_entrega_catalogo($1, '2026-11-13')", [id]), /no está disponible/);
    await db.exec('reset role');
    const row = (await db.query('select fecha_entrega::text fecha, facturado, total from pedidos')).rows[0];
    assert.deepEqual(row, {fecha:'2026-11-12',facturado:true,total:'800'});
    assert.deepEqual((await db.query('select precio from pedido_detalles')).rows, [{precio:'800'}]);
    console.log('PASS: programación exclusiva, permisos, estados, mantenimiento, preparación y preservación comercial.');
  } finally {
    await db.close();
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
