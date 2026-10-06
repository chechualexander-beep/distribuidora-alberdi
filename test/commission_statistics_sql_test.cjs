const {PGlite}=require('../.dart_tool/commercial_sql_test/node_modules/@electric-sql/pglite');
const fs=require('fs'),assert=require('node:assert/strict');
(async()=>{const db=new PGlite();try{
for(const f of ['test/fixtures/nc_base_schema.sql','supabase/migrations/20260928210000_notas_credito_internas.sql','supabase/migrations/20260929020000_estadisticas_comisiones.sql'])await db.exec(fs.readFileSync(f,'utf8'));
const a='00000000-0000-0000-0000-000000000001',s='00000000-0000-0000-0000-000000000002',other='00000000-0000-0000-0000-000000000003';
await db.exec(`insert into usuarios(id,nombre,email,rol) values ('${a}','Admin','a','administrador'),('${s}','Uno','s','preventista'),('${other}','Dos','o','preventista');set test.uid='${a}';`);
const one=async(q,p=[])=>(await db.query(q,p)).rows[0];
const c=await one("insert into clientes(nombre_comercio,direccion,preventista_id) values ('Cliente','Calle',$1) returning id",[s]);
const product=await one("insert into productos(nombre) values ('Bolsa 10kg') returning id");
async function order(seller,time,q=10){const p=await one("insert into pedidos(cliente_id,preventista_id,tipo_precio,resultado_entrega,fecha_finalizacion) values ($1,$2,'normal','entregado',$3) returning id",[c.id,seller,time]);const d=await one('insert into pedido_detalles(pedido_id,producto_id,cantidad,cantidad_entregada,precio_unitario,subtotal,importe_comision) values ($1,$2,$3,$3,100,$3::numeric*100,$3::numeric*10) returning id',[p.id,product.id,q]);return {p:p.id,d:d.id};}
const first=await order(s,'2026-09-28T03:00:00Z');await order(s,'2026-09-29T02:59:59Z',2);await order(s,'2026-09-29T03:00:00Z',3);await order(other,'2026-09-28T12:00:00Z',20);
const note=await one("select crear_nota_credito($1,'Prueba',$2,'stats-nota-prueba-0001') id",[first.p,JSON.stringify([{detalle_id:first.d,cantidad:2}])]);await db.query("update notas_credito set fecha='2026-09-29T04:00:00Z' where id=$1",[note.id]);
const stats=async(from,to,seller=null,metric='cantidad')=>(await one('select estadisticas_comisiones($1,$2,$3,$4) r',[from,to,seller,metric])).r;
let r=await stats('2026-09-28','2026-09-28',s);assert.equal(r.venta_neta,1200);assert.equal(r.comision_neta,120);assert.equal(r.clientes,1);assert.equal(r.serie.length,1);
r=await stats('2026-09-29','2026-09-29',s);assert.equal(r.venta_neta,100);assert.equal(r.ajustes,20);assert.equal(r.ranking_productos[0].cantidad,1);
r=await stats('2026-09-28','2026-09-29');assert.equal(r.venta_neta,3300);
// Pagar comisiones no cambia estadísticas de generación.
await db.query("insert into liquidaciones(preventista_id,fecha_desde,fecha_hasta,estado,comision_total) values ($1,'2026-09-28','2026-09-28','pagada',100)",[s]);
await db.exec(`set test.uid='${s}'`);assert.equal((await stats('2026-09-28','2026-09-29')).venta_neta,1300);await assert.rejects(stats('2026-09-28','2026-09-29',other),/Solo/);
await db.exec('set role authenticated');assert.equal((await stats('2026-09-28','2026-09-29')).comision_neta,130);await db.exec('reset role');
r=await stats('2026-10-01','2026-10-02');assert.equal(r.hay_movimientos,false);assert.equal(r.promedio,null);assert.equal(r.serie.length,2);
r=await stats('2026-01-01','2026-12-31');assert.equal(r.semanal,true);assert.equal(r.serie.reduce((n,x)=>n+x.venta,0),1300);
await assert.rejects(stats('2026-10-02','2026-10-01'),/Rango/);await assert.rejects(stats('2026-10-01','2026-10-02',null,'incorrecta'),/Métrica/);
await db.exec(`set test.uid='${a}'`);await db.query("update notas_credito set fecha='2026-09-30T04:00:00Z' where id=$1",[note.id]);r=await stats('2026-09-30','2026-09-30',s);assert.equal(r.venta_neta,-200);assert.equal(r.comision_neta,-20);assert.equal(r.promedio,null);assert.equal(r.ranking_clientes[0].operaciones[0].tipo,'Devolución');
// Límites top10 y orden independiente para cada métrica.
for(let i=1;i<=12;i++){const pr=await one('insert into productos(nombre) values ($1) returning id',['Producto '+i]);const cl=await one('insert into clientes(nombre_comercio,direccion) values ($1,\'Calle\') returning id',['Cliente '+i]);const o=await order(s,'2026-10-01T12:00:00Z',i);await db.query('update pedidos set cliente_id=$1 where id=$2',[cl.id,o.p]);await db.query('update pedido_detalles set producto_id=$1,precio_unitario=$2,importe_comision=$3 where id=$4',[pr.id,10000/(i*i),i*3,o.d]);}
r=await stats('2026-10-01','2026-10-01',s,'cantidad');assert.equal(r.ranking_clientes.length,10);assert.equal(r.ranking_productos.length,10);assert.equal(r.ranking_productos[0].nombre,'Producto 12');r=await stats('2026-10-01','2026-10-01',s,'venta');assert.equal(r.ranking_productos[0].nombre,'Producto 1');
await db.exec("set test.uid=''");await assert.rejects(stats('2026-10-01','2026-10-01'),/Sesión/);
assert.equal((await one("select has_function_privilege('anon','estadisticas_comisiones(date,date,uuid,text)','EXECUTE') ok")).ok,false);
console.log('OK: límites argentinos, devoluciones, netos negativos, rankings, períodos vacíos, agregación semanal y permisos.');
}finally{await db.close();}})().catch(e=>{console.error(e);process.exit(1);});
