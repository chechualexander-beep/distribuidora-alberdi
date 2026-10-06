// Ejecutar desde la raíz: node test/commercial_summary_sql_test.cjs
// Requiere @electric-sql/pglite en .dart_tool/commercial_sql_test.
// PostgreSQL en memoria: nunca utiliza credenciales ni datos de producción.
const { PGlite } = require('../.dart_tool/commercial_sql_test/node_modules/@electric-sql/pglite');
const { readFileSync } = require('node:fs');
const assert = require('node:assert/strict');

async function main() {
  const db = new PGlite();
  try {
    await db.exec(`
      create role anon; create role authenticated;
      create function public.es_administrador() returns boolean language sql
      as $$ select current_setting('test.admin', true) = 'true' $$;
      set test.admin = 'true';
      create table pedidos (
        id integer primary key, tipo_operacion text, preventista_id integer,
        estado text default 'entregado', facturado boolean default false,
        resultado_entrega text default 'entregado', fecha_facturacion timestamptz,
        fecha_finalizacion timestamptz, fecha_entrega date
      );
      create table pedido_detalles (
        pedido_id integer, cantidad_facturada numeric, cantidad_entregada numeric,
        precio_unitario numeric, costo_unitario numeric, importe_comision numeric
      );
      create table cobros_cliente (id integer primary key, importe numeric, fecha_pago timestamptz);
      create table pedido_pagos (pedido_id integer, cobro_id integer, importe numeric);
    `);
    await db.exec(readFileSync('supabase/migrations/20260928180000_resumen_comercial_modalidades.sql', 'utf8'));
    const start = '2026-09-28T03:00:00Z';
    const end = '2026-09-29T03:00:00Z';
    async function summary() {
      return (await db.query('select resumen_comercial($1, $2) as resumen', [start, end])).rows[0].resumen;
    }
    const empty = await summary();
    assert.equal(empty.venta_total, 0);
    assert.equal(empty.recaudacion_total, 0);
    assert.deepEqual(empty.comisiones_por_preventista, {});

    await db.exec(`
      insert into pedidos (id, tipo_operacion, preventista_id, facturado, fecha_facturacion, fecha_finalizacion, fecha_entrega) values
      (1, 'pedido', 1, true, '2026-09-28 03:00Z', '2026-09-28 04:00Z', '2026-09-27'),
      (2, 'venta_directa', 1, false, null, '2026-09-28 05:00Z', '2026-09-27'),
      (3, 'pedido', 2, true, '2026-09-27 03:00Z', '2026-09-27 04:00Z', '2026-09-27'),
      (4, 'venta_directa', 2, false, null, null, '2026-09-28'),
      (5, 'pedido', 2, true, '2026-09-29 03:00Z', '2026-09-29 03:00Z', '2026-09-28'),
      (6, 'venta_directa', 2, false, null, '2026-09-28 02:59:59Z', '2026-09-28'),
      (7, 'venta_directa', 2, false, null, '2026-09-28 05:00Z', '2026-09-28'),
      (8, 'pedido', 2, true, '2026-09-28 03:00Z', '2026-09-28 05:00Z', '2026-09-28');
      update pedidos set resultado_entrega = 'parcial' where id = 1;
      update pedidos set resultado_entrega = 'pendiente' where id = 7;
      update pedidos set estado = 'anulado' where id = 8;
      insert into pedido_detalles values
      (1, 10, 8, 100, 60, 40), (1, 0, 2, 50, 20, 5),
      (2, null, 3, 100, 50, 15), (3, 10, 10, 100, 50, 50),
      (4, null, 1, 50, 20, 2.5),
      (5, 99, 99, 100, 50, 100), (6, null, 99, 100, 50, 100),
      (7, null, 99, 100, 50, 100), (8, 99, 99, 100, 50, 100);
      insert into cobros_cliente values
      (1, 500, '2026-09-28 03:00Z'), (2, 50, '2026-09-28 04:00Z'),
      (3, 9000, '2026-09-29 03:00Z'), (4, 9000, '2026-09-28 02:59:59Z');
      insert into pedido_pagos values (3, 1, 200), (2, 1, 300), (1, 3, 9000);
    `);
    const result = await summary();
    for (const [key, expected] of Object.entries({
      venta_total: 1350, venta_preventa: 1000, venta_directa: 350,
      entrega_total: 1250, entrega_preventa: 900, entrega_directa: 350,
      entrega_sin_clasificar: 0, recaudacion_total: 550,
      recaudacion_preventa: 200, recaudacion_directa: 300,
      recaudacion_sin_clasificar: 50, costo_mercaderia: 690,
      comisiones: 62.5, ganancia: 497.5,
    })) assert.equal(result[key], expected, key);
    assert.deepEqual(result.comisiones_por_preventista, { 1: 60, 2: 2.5 });
    await assert.rejects(db.query('select resumen_comercial($1, $2)', [end, start]), /período/);
    await db.exec("set test.admin = 'false'");
    await assert.rejects(summary(), /administrador/);
    console.log('OK: totales, cobro mixto, deuda anterior, sin clasificar, fechas argentinas, histórico, cancelación y permisos.');
  } finally {
    await db.close();
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
