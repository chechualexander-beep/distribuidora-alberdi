const {PGlite}=require('../.dart_tool/commercial_sql_test/node_modules/@electric-sql/pglite');
const fs=require('node:fs');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
(async()=>{
 const db=new PGlite();
 try {
  for(const file of ['test/fixtures/nc_base_schema.sql','test/fixtures/catalogo_storage_schema.sql',
   'supabase/migrations/20261001120000_catalogo_clientes.sql',
   'supabase/migrations/20261001130000_catalogo_vigencia_12h.sql',
   'supabase/migrations/20261001140000_productos_fotos.sql',
   'supabase/migrations/20261001141000_catalogo_preventista.sql','supabase/migrations/20261001142000_catalogo_asignacion_relacion.sql']) await db.exec(fs.readFileSync(file,'utf8'));
  const one=async(sql,args=[])=>(await db.query(sql,args)).rows[0];
  const admin=randomUUID(), seller=randomUUID(), other=randomUUID();
  await db.query("insert into usuarios(id,nombre,email,rol) values ($1,'Admin','a@test','administrador'),($2,'Mary','b@test','preventista'),($3,'Otro','c@test','preventista')",[admin,seller,other]);
  await db.exec(`set test.uid='${admin}'`);
  const client=(await one("insert into clientes(nombre_comercio,direccion) values ('Prueba','Prueba') returning id")).id;
  const p=(await one("insert into productos(nombre,categoria,precio_normal,precio_promo,precio_interior,comision_normal,comision_promo,comision_interior) values ('Snacks','Snacks',100,80,90,10,5,7) returning id")).id;
  const food=(await one("insert into productos(nombre,categoria,precio_normal,precio_promo,precio_interior,comision_normal,comision_promo,comision_interior) values ('Balanceado','Balanceados',200,150,180,12,6,9) returning id")).id;
  const config=async(s,renew=true)=>(await one("select configurar_catalogo_cliente_v2($1,'interior',$2,'{}',$3,true,$4) t",[client,JSON.stringify({snacks:'promo'}),renew,s])).t;
  const submit=async(t,id=randomUUID())=>(await one("select crear_pedido_catalogo($1,$2,$3,'Prueba') p",[t,id,JSON.stringify([{producto_id:p,cantidad:2,precio_visto:80},{producto_id:food,cantidad:1,precio_visto:180}])])).p;
  const original=await config(null);
  const unassigned=await submit(original);
  assert.equal((await one('select preventista_id from pedidos where id=$1',[unassigned.pedido_id])).preventista_id,admin);
  await assert.rejects(config(seller,false),/Renová/);
  const token=await config(seller);
  await assert.rejects(submit(original),/desactivado/);
  const request=randomUUID();
  await db.exec('set role anon');
  const order=await submit(token,request);
  assert.deepEqual(await submit(token,request),order);
  await assert.rejects(config(other),/permission denied/);
  await db.exec('reset role');
  const row=await one('select * from pedidos where id=$1',[order.pedido_id]);
  assert.equal(row.preventista_id,seller);assert.equal(row.catalogo_preventista_id,seller);
  let detail=await one('select * from pedido_detalles where pedido_id=$1 and producto_id=$2',[order.pedido_id,p]);
  assert.equal(Number(detail.porcentaje_comision),5);assert.equal(Number(detail.importe_comision),0);
  assert.equal(Number((await one('select porcentaje_comision from pedido_detalles where pedido_id=$1 and producto_id=$2',[order.pedido_id,food])).porcentaje_comision),9);
  await db.query('update pedido_detalles set cantidad_entregada=1,porcentaje_comision=99,importe_comision=999 where id=$1',[detail.id]);
  detail=await one('select * from pedido_detalles where id=$1',[detail.id]);
  assert.equal(Number(detail.importe_comision),4);assert.equal(Number(detail.porcentaje_comision),5);
  await db.query('update productos set comision_promo=8 where id=$1',[p]);
  await db.query('update pedido_detalles set cantidad_entregada=2 where id=$1',[detail.id]);
  assert.equal(Number((await one('select importe_comision from pedido_detalles where id=$1',[detail.id])).importe_comision),8);
  const newToken=await config(other);
  assert.equal((await one('select preventista_id from pedidos where id=$1',[order.pedido_id])).preventista_id,seller);
  const newOrder=await submit(newToken);
  assert.equal((await one('select preventista_id from pedidos where id=$1',[newOrder.pedido_id])).preventista_id,other);
  await db.query('update pedido_detalles set cantidad_entregada=1,importe_comision=55 where pedido_id=$1',[unassigned.pedido_id]);
  assert.equal(Number((await one('select sum(importe_comision) s from pedido_detalles where pedido_id=$1',[unassigned.pedido_id])).s),0);
  await db.query('update usuarios set activo=false where id=$1',[other]);
  await assert.rejects(submit(newToken),/necesita actualizarse/);
  await assert.rejects(config(other),/activo/);
  await db.exec(`set test.uid='${seller}'; set role authenticated`);
  await assert.rejects(config(seller),/administrador/);
  await assert.rejects(db.query("insert into storage.objects(bucket_id,name) values ('productos-fotos',$1)",[`${p}/1.jpg`]),/row-level security/);
  await db.exec(`reset role; set test.uid='${admin}'; set role authenticated`);
  await db.query("insert into storage.objects(bucket_id,name) values ('productos-fotos',$1)",[`${p}/1.jpg`]);
  await assert.rejects(db.query("insert into storage.objects(bucket_id,name) values ('productos-fotos','otro/1.jpg')"),/row-level security/);
  await db.exec('reset role');
  await db.query('update productos set foto_path=$1 where id=$2',[`${p}/1.jpg`,p]);
  await assert.rejects(db.query('update productos set foto_path=$1 where id=$2',[`${food}/1.jpg`,p]),/check constraint/);
  const photoToken=await config(null);
  const catalog=(await one('select obtener_catalogo_cliente($1) c',[photoToken])).c;
  const publicProduct=catalog.productos.find(x=>x.id===p);
  assert.equal(publicProduct.foto_path,`${p}/1.jpg`);
  assert.equal(publicProduct.comision_promo,undefined);assert.equal(catalog.preventista_comision_id,undefined);
  await db.exec('set role authenticated');
  assert.equal((await db.query('delete from storage.objects returning id')).rows.length,0,'No borrar una foto en uso');
  await db.exec('reset role');
  await db.query('update productos set foto_path=null where id=$1',[p]);
  await db.exec('set role authenticated');
  assert.equal((await db.query('delete from storage.objects returning id')).rows.length,1);
  await db.exec('reset role; set role anon');
  await assert.rejects(db.query("insert into storage.objects(bucket_id,name) values ('productos-fotos',$1)",[`${p}/2.jpg`]),/row-level security|permission denied/);
  console.log('Fotos y asignación: permisos, rutas, privacidad, preventista, comisiones mixtas sobre entrega, instantáneas, renovación y reintentos OK.');
 }finally{await db.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
