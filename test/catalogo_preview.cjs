// Servidor local con datos ficticios y la migración real; nunca usa producción.
const {PGlite}=require('../.dart_tool/commercial_sql_test/node_modules/@electric-sql/pglite');
const fs=require('node:fs'); const http=require('node:http'); const path=require('node:path');
(async()=>{
 const db=new PGlite();
 await db.exec(fs.readFileSync('test/fixtures/nc_base_schema.sql','utf8'));
 await db.exec(fs.readFileSync('supabase/migrations/20261001120000_catalogo_clientes.sql','utf8'));
    await db.exec(fs.readFileSync('supabase/migrations/20261001130000_catalogo_vigencia_12h.sql', 'utf8'));
 for(const file of ['test/fixtures/catalogo_storage_schema.sql','supabase/migrations/20261001140000_productos_fotos.sql','supabase/migrations/20261001141000_catalogo_preventista.sql','supabase/migrations/20261001142000_catalogo_asignacion_relacion.sql']) await db.exec(fs.readFileSync(file,'utf8'));
 await db.exec("insert into usuarios(id,nombre,email,rol) values ('00000000-0000-0000-0000-000000000001','Admin','a@test','administrador'); set test.uid='00000000-0000-0000-0000-000000000001'; insert into clientes(id,nombre_comercio,direccion) values ('00000000-0000-0000-0000-000000000002','Almacén San Martín','Calle de prueba'); insert into productos(nombre,categoria,descripcion,codigo,precio_normal,precio_promo,precio_interior) values ('Papas Facu','Snacks','Bolsa de 500 g · por unidad','123',3200.25,2900,3000),('Palitos salados','Snacks','Bolsa de 500 g · por unidad','124',2400,2200,2300),('Alimento para perros','Balanceados','Bolsa de 15 kg · por bolsa','125',21000,18500,20000);");
 const photoFile='build/catalogo_publicacion/nutribon-cachorro-8kg.jpg';
 const photoPath='8b0e7470-1caa-425d-8f36-f4decd614a59/20261001211000.jpg';
 if(fs.existsSync(photoFile)) await db.query("insert into productos(id,nombre,categoria,precio_normal,precio_promo,precio_interior,foto_path) values ($1,'Nutribon Cachorro 8kg','Balanceados',19800,18000,19000,$2)",[photoPath.split('/')[0],photoPath]);
 const token=(await db.query("select configurar_catalogo_cliente('00000000-0000-0000-0000-000000000002','normal','{\"balanceados\":\"promo\"}','{}',true,true) t")).rows[0].t;
 const port=Number(process.env.CATALOGO_PREVIEW_PORT || 4178);
 http.createServer(async(req,res)=>{
  if(req.url==='/storage/v1/object/public/productos-fotos/'+photoPath && fs.existsSync(photoFile)){ res.writeHead(200,{'Content-Type':'image/jpeg'}); res.end(fs.readFileSync(photoFile)); return; }
  if(req.method==='POST'){
   let data=''; for await(const part of req)data+=part;
   try{const args=JSON.parse(data);let result;
    if(req.url==='/rpc/obtener_catalogo_cliente')result=await db.query('select obtener_catalogo_cliente($1) r',[args.p_token]);
    else if(req.url==='/rpc/crear_pedido_catalogo')result=await db.query('select crear_pedido_catalogo($1,$2,$3,$4) r',[args.p_token,args.p_solicitud_id,JSON.stringify(args.p_items),args.p_observacion]);
    else throw Error('Ruta no disponible');
    res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(result.rows[0].r));
   }catch(e){res.writeHead(e.code==='PT410'?410:400,{'Content-Type':'application/json'});res.end(JSON.stringify({message:e.message}));} return;
  }
  const files={'/':'index.html','/index.html':'index.html','/catalogo.css':'catalogo.css','/catalogo.js':'catalogo.js','/catalogo-core.js':'catalogo-core.js'};
  const file=files[req.url];if(!file){res.writeHead(404);res.end();return;}
  let text=fs.readFileSync(path.join('catalogo',file),'utf8');
  text=text.replaceAll('https://vmbncsqapqdyffscwfwo.supabase.co/rest/v1/rpc/',`http://127.0.0.1:${port}/rpc/`).replaceAll('connect-src https://vmbncsqapqdyffscwfwo.supabase.co',"connect-src 'self'");
  text=text.replaceAll("'/rest/v1/rpc/'","'/rpc/'");
  res.writeHead(200,{'Content-Type':file.endsWith('.css')?'text/css':file.endsWith('.js')?'text/javascript':'text/html'});res.end(text);
 }).listen(port,'127.0.0.1',()=>console.log(`PREVIEW http://127.0.0.1:${port}/#token=${token}`));
})().catch(e=>{console.error(e);process.exitCode=1;});
