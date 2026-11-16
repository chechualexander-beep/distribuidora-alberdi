-- Escenario: pedidos cargados sin señal (copia de producción o TESTING; todo se deshace).
\set ON_ERROR_STOP 1
begin;
select u.id as prev, c.id as cli from usuarios u join clientes c on c.preventista_id=u.id and c.activo
  where u.rol='preventista' and u.activo order by c.nombre_comercio limit 1 \gset
select id as prod, precio_normal as pn from productos
  where activo and visible_preventistas and precio_normal>1 order by nombre limit 1 \gset
select set_config('e.prod', :'prod', true), set_config('e.cli', :'cli', true), set_config('e.pn', :'pn'::text, true);
set session_replication_role = replica;  -- sin avisos de "pedido nuevo" durante la prueba

set local role authenticated;
select set_config('request.jwt.claim.sub', :'prev', true);
-- 1) Precio actual: se crea; repetir la misma solicitud devuelve el mismo pedido.
select gen_random_uuid() as s1 \gset
select crear_pedido_sin_conexion(:'s1', :'cli', 'normal', 'pedido', 'Prueba', current_date,
  jsonb_build_array(jsonb_build_object('producto_id',:'prod','cantidad',2,'precio_unitario',:pn,'subtotal',2*:pn,'tipo_precio','normal')),
  now()) as p1 \gset
select crear_pedido_sin_conexion(:'s1', :'cli', 'normal', 'pedido', 'Prueba', current_date,
  jsonb_build_array(jsonb_build_object('producto_id',:'prod','cantidad',2,'precio_unitario',:pn,'subtotal',2*:pn,'tipo_precio','normal')),
  now() - interval '5 hours') as p1b \gset
select :'p1' = :'p1b' and :'p1' = :'s1' as idem \gset
\if :idem \else \echo 'FALLA idempotencia' \quit \endif

-- 2) Sube el precio (lo hace el administrador): queda el anterior en el historial.
reset role;
set session_replication_role = origin;
update productos set precio_normal = precio_normal + 1 where id=:'prod';
set session_replication_role = replica;
select count(*)=1 as hist from productos_precios_historial where producto_id=:'prod' and tipo='normal' and precio=:pn \gset
\if :hist \else \echo 'FALLA historial' \quit \endif

set local role authenticated;
select set_config('request.jwt.claim.sub', :'prev', true);
-- 3) Pedido cargado sin señal hace 1 hora con el precio viejo: se respeta y queda anotado.
select gen_random_uuid() as s2 \gset
select crear_pedido_sin_conexion(:'s2', :'cli', 'normal', 'venta_directa', '', current_date,
  jsonb_build_array(jsonb_build_object('producto_id',:'prod','cantidad',3,'precio_unitario',:pn,'subtotal',3*:pn,'tipo_precio','normal')),
  now() - interval '1 hour') as p2 \gset
-- 4) Más de 72 horas: ya no se respeta el precio viejo.
do $$ begin perform crear_pedido_sin_conexion(gen_random_uuid(), current_setting('e.cli')::uuid, 'normal', 'pedido', '', current_date,
  jsonb_build_array(jsonb_build_object('producto_id',current_setting('e.prod'),'cantidad',1,'precio_unitario',current_setting('e.pn')::numeric,'subtotal',1,'tipo_precio','normal')),
  now() - interval '80 hours'); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Los precios cambiaron%' then raise; end if; end $$;
-- 5) Un precio que nunca existió: rechazado.
do $$ begin perform crear_pedido_sin_conexion(gen_random_uuid(), current_setting('e.cli')::uuid, 'normal', 'pedido', '', current_date,
  jsonb_build_array(jsonb_build_object('producto_id',current_setting('e.prod'),'cantidad',1,'precio_unitario',0.5,'subtotal',0.5,'tipo_precio','normal')),
  now()); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Los precios cambiaron%' then raise; end if; end $$;
-- 6) Otro preventista no puede cargarle pedidos a un cliente ajeno.
reset role;
select id as otro from usuarios where rol='preventista' and activo and id<>:'prev' limit 1 \gset
set local role authenticated;
select set_config('request.jwt.claim.sub', :'otro', true);
do $$ begin perform crear_pedido_sin_conexion(gen_random_uuid(), current_setting('e.cli')::uuid, 'normal', 'pedido', '', current_date,
  jsonb_build_array(jsonb_build_object('producto_id',current_setting('e.prod'),'cantidad',1,'precio_unitario',current_setting('e.pn')::numeric + 1,'subtotal',1,'tipo_precio','normal')),
  now()); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Cliente no asignado%' then raise; end if; end $$;
reset role;
select (select precio_unitario from pedido_detalles where pedido_id=:'p2') = :pn
   and (select observacion like '%[Sin señal] Se respetó el precio%' from pedidos where id=:'p2')
   and (select tipo_operacion from pedidos where id=:'p2') = 'venta_directa'
   and (select total from pedidos where id=:'p2') = 3 * :pn as ok \gset
\if :ok \else \echo 'FALLA precio respetado' \quit \endif
rollback;
\echo ESCENARIO_OK
