const {PGlite}=require('../.dart_tool/commercial_sql_test/node_modules/@electric-sql/pglite');
const fs=require('fs');const assert=require('node:assert/strict');
(async()=>{const db=new PGlite();try{
await db.exec(fs.readFileSync('test/fixtures/nc_base_schema.sql','utf8'));
await db.exec(fs.readFileSync('supabase/migrations/20260928210000_notas_credito_internas.sql','utf8'));
console.log('Migración compatible con las columnas, vistas y funciones leídas de producción.');
const admin='00000000-0000-0000-0000-000000000001',seller='00000000-0000-0000-0000-000000000002';
await db.exec(`insert into usuarios(id,nombre,email,rol) values ('${admin}','Admin','a@test','administrador'),('${seller}','Vendedor','v@test','preventista'); set test.uid='${admin}';`);
const one=async(sql,params=[])=>(await db.query(sql,params)).rows[0];
const customer=await one("insert into clientes(nombre_comercio,direccion,preventista_id) values ('Cliente','Dirección',$1) returning id",[seller]);
const product=await one("insert into productos(nombre) values ('Producto') returning id");
async function order(q=10,price=100,comm=50){
const p=await one("insert into pedidos(cliente_id,preventista_id,tipo_precio,resultado_entrega,fecha_finalizacion,fecha_entrega,facturado,fecha_facturacion) values ($1,$2,'normal','entregado',now(),current_date,true,now()) returning id",[customer.id,seller]);
const d=await one("insert into pedido_detalles(pedido_id,producto_id,cantidad,cantidad_facturada,cantidad_entregada,precio_unitario,subtotal,costo_unitario,importe_comision) values ($1,$2,$3,$3,$3,$4,$3::numeric*$4::numeric,60,$5) returning id",[p.id,product.id,q,price,comm]);return {p:p.id,d:d.id};}
const create=async(o,q,key)=> (await one('select crear_nota_credito($1,$2,$3,$4) as id',[o.p,'Devolución',JSON.stringify([{detalle_id:o.d,cantidad:q}]),key])).id;
const balance=async(o)=>one('select * from saldos_pendientes_pedidos where pedido_id=$1',[o.p]);
const preview=async(o)=>(await one('select previsualizar_liquidacion_nc($1,$2) as v',[seller,[o.d]])).v;
const settle=async(o,v)=>(await one("select registrar_liquidacion_con_nc($1,current_date,current_date,$2,$3) as id",[seller,[o.d],v.token])).id;
const a=await order();assert.equal(Number((await balance(a)).saldo_pendiente),1000);
const v0=await preview(a);assert.equal(v0.neto,50);
const liq=await settle(a,v0);assert.equal(Number((await one('select comision_total from liquidaciones where id=$1',[liq])).comision_total),50);
await db.query("select * from registrar_pago_cliente($1,1000,'Efectivo',null)",[customer.id]);
const note=await create(a,2,'idempotencia-prueba-0001');assert.equal(await create(a,2,'idempotencia-prueba-0001'),note);
assert.equal(Number((await balance(a)).saldo_a_favor),200);
assert.equal(Number((await one('select comision_total from liquidaciones where id=$1',[liq])).comision_total),50);
await assert.rejects(create(a,9,'exceso-prueba-0001'),/supera/);
const b=await order(1,100,5);await db.query('select aplicar_credito_cliente($1)',[customer.id]);
assert.equal(Number((await balance(b)).saldo_pendiente),0);assert.equal(Number((await balance(a)).saldo_a_favor),100);
const vb=await preview(b);assert.equal(vb.neto,0);assert.equal(vb.remanente,5);await settle(b,vb);
const c=await order(1,100,10);const vc=await preview(c);assert.equal(vc.descuento,5);assert.equal(vc.neto,5);await settle(c,vc);
await assert.rejects(settle(c,vc),/liquidados/);
await db.query("select reintegrar_credito_cliente($1,50,'Efectivo','reintegro-prueba-0001')",[customer.id]);
assert.equal(Number((await balance(a)).saldo_a_favor),50);
await assert.rejects(db.query("select reintegrar_credito_cliente($1,100,'Efectivo','reintegro-prueba-0002')",[customer.id]),/supera/);
const nd=await one('select id from nota_credito_detalles where nota_id=$1',[note]);
await db.query('select recibir_nota_credito($1,true)',[nd.id]);await db.query('select recibir_nota_credito($1,true)',[nd.id]);
assert.equal(Number((await one('select count(*) from recepciones_nota_credito')).count),1);
await assert.rejects(db.query('select recibir_nota_credito($1,false)',[nd.id]),/otro estado/);
await assert.rejects(db.query("select corregir_operacion_finalizada($1,'Corrección','[]')",[a.p]),/notas/);
const d=await order(10,100,50);const vd=await preview(d);await create(d,2,'pendiente-prueba-0001');
await assert.rejects(settle(d,vd),/cambiaron/);const vd2=await preview(d);assert.equal(vd2.descuento,10);await settle(d,vd2);
assert.equal(Number((await balance(d)).total_notas_credito),200);
const r=(await one("select resumen_comercial(now()-interval '1 day',now()+interval '1 day') as r")).r;
assert.equal(r.notas_credito,400);assert.equal(r.reintegros,50);assert.equal(r.costo_recuperado,120);

// Reparto de crédito antes de cobrar una entrega nueva, y comprobación de importe visto.
const nuevoCliente=await one("insert into clientes(nombre_comercio,direccion,preventista_id) values ('Segundo','Calle',$1) returning id",[seller]);
const e=await order(10,100,50);await db.query('update pedidos set cliente_id=$1 where id=$2',[nuevoCliente.id,e.p]);
await db.query("select * from registrar_pago_cliente($1,1000,'Efectivo',null)",[nuevoCliente.id]);
await create(e,2,'credito-gestion-prueba-0001');
const f=await order(5,100,25);
await db.query("update pedidos set cliente_id=$1,resultado_entrega='pendiente',fecha_finalizacion=null where id=$2",[nuevoCliente.id,f.p]);
await db.query('update pedido_detalles set cantidad_entregada=0 where id=$1',[f.d]);
const entrega=JSON.stringify([{id:f.d,cantidad_entregada:5,cantidad_no_entregada:0,precio_unitario:100,costo_unitario:60,porcentaje_comision:5,importe_comision:25}]);
await assert.rejects(db.query("select finalizar_gestion_pedido($1,'entregado','entregado',null,$2,'completo',500,'Efectivo')",[f.p,entrega]),/Cambió/);
assert.equal((await one('select resultado_entrega from pedidos where id=$1',[f.p])).resultado_entrega,'pendiente');
await db.query("select finalizar_gestion_pedido($1,'entregado','entregado',null,$2,'completo',300,'Efectivo')",[f.p,entrega]);
assert.equal(Number((await balance(f)).credito_aplicado),200);
assert.equal(Number((await balance(f)).total_pagado),300);
assert.equal(Number((await balance(f)).saldo_pendiente),0);
// Ninguna escritura directa de notas/ajustes para usuarios autenticados.
for(const table of ['notas_credito','nota_credito_detalles','movimientos_credito_cliente','ajustes_comision_aplicados']) {
 const rights=await one("select has_table_privilege('authenticated',$1,'INSERT') as allowed",[table]);assert.equal(rights.allowed,false);
}
for(const fn of ['registrar_liquidacion_sin_nc(uuid,date,date,numeric,numeric,jsonb)','finalizar_gestion_pedido_sin_nc(uuid,text,text,text,jsonb,text,numeric,text)']) {
 assert.equal((await one("select has_function_privilege('authenticated',$1,'EXECUTE') as allowed",[fn])).allowed,false);
}

// Cobro parcial + nota: conservar cobro y reducir solo el saldo.
const g=await order(10,100,50);const tercer=await one("insert into clientes(nombre_comercio,direccion,preventista_id) values ('Tercero','Calle',$1) returning id",[seller]);
await db.query('update pedidos set cliente_id=$1 where id=$2',[tercer.id,g.p]);
await db.query("select * from registrar_pago_cliente($1,300,'Efectivo',null)",[tercer.id]);
await create(g,2,'parcial-nc-prueba-0001');assert.equal(Number((await balance(g)).saldo_pendiente),500);
assert.equal(Number((await balance(g)).total_pagado),300);
await assert.rejects(db.query("select * from registrar_pago_cliente($1,600,'Efectivo',null)",[tercer.id]),/supera/);
await create(g,8,'total-nc-prueba-0001');assert.equal(Number((await balance(g)).saldo_a_favor),300);
await assert.rejects(create(g,1,'agotado-prueba-0001'),/supera/);
// Tres devoluciones no deben descontar más de la comisión original por redondeo.
const h=await order(3,100,1);for(let i=0;i<3;i++)await create(h,1,'redondeo-prueba-000'+i);
assert.equal(Number((await one('select sum(comision) as total from nota_credito_detalles where pedido_detalle_id=$1',[h.d])).total),1);
await assert.rejects(db.query('select crear_nota_credito($1,$2,$3,$4)',[h.p,'Repetidos',JSON.stringify([{detalle_id:h.d,cantidad:1},{detalle_id:h.d,cantidad:1}]),'duplicados-prueba-0001']),/duplicado/);
// Corrección anterior sin notas sigue funcionando.
const intacto=await order(10,100,50);
const corregido=await one('select corregir_operacion_finalizada($1,$2,$3) as r',[intacto.p,'Error de carga',JSON.stringify([{id:intacto.d,cantidad_entregada:8}])]);
assert.equal(corregido.r.total_nuevo,800);
// Un pedido finalizado sin entrega bloqueaba la selección completa del período.
const elegible=await order(2,100,10), sinEntrega=await order(2,100,0);
await db.query("update pedidos set resultado_entrega='no_entregado' where id=$1",[sinEntrega.p]);
await assert.rejects(db.query('select previsualizar_liquidacion_nc($1,$2)',[seller,[elegible.d,sinEntrega.d]]),/Los detalles cambiaron/);
const candidatos=(await db.query("select d.id from pedido_detalles d join pedidos p on p.id=d.pedido_id where d.id=any($1) and p.preventista_id=$2 and p.resultado_entrega in ('entregado','parcial') and p.estado not in ('cancelado','anulado') and not exists(select 1 from liquidacion_detalles ld where ld.pedido_detalle_id=d.id)",[[elegible.d,sinEntrega.d],seller])).rows.map(r=>r.id);
assert.deepEqual(candidatos,[elegible.d]);
assert.equal((await one('select previsualizar_liquidacion_nc($1,$2) as v',[seller,candidatos])).v.bruto,10);
assert.equal(Number((await one('select comision_total from liquidaciones where id=$1',[liq])).comision_total),50);
console.log('OK: selección con pedido sin entrega reproduce el error; filtrado correcto permite revisar y conserva liquidaciones anteriores.');
// RLS: preventista propio puede leer las notas; otro no obtiene registros.
await db.exec('grant usage on schema public,auth to authenticated; grant select on public.clientes,public.pedidos,public.pedido_detalles,public.pedido_pagos,public.liquidacion_detalles to authenticated;');
await db.exec('set role authenticated');
await db.exec('set test.uid="00000000-0000-0000-0000-000000000002"');
assert.ok(Number((await one('select count(*) from notas_credito')).count)>0);
await db.exec('set test.uid="00000000-0000-0000-0000-000000000099"');
assert.equal(Number((await one('select count(*) from notas_credito')).count),0);
await assert.rejects(db.exec("insert into notas_credito(clave) values ('sin-permiso')"),/permission denied/);
await db.exec('reset role');
await db.exec(`set test.uid='${seller}'`);await assert.rejects(create(a,1,'sin-permiso-prueba-0001'),/administración/);
console.log('OK: deuda, cobro completo, idempotencia, límites, saldo a favor, aplicaciones, reintegros, recepción, comisiones pagadas/pendientes, remanentes, doble liquidación, revisión desactualizada, resumen y permisos.');
}finally{await db.close();}})().catch(e=>{console.error({message:e.message,detail:e.detail,where:e.where,position:e.position});process.exitCode=1;});
