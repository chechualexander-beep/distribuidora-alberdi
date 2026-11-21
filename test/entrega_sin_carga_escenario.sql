-- Escenario: entregas con y sin la carga del vehículo registrada (todo se deshace).
\set ON_ERROR_STOP 1
begin;
select u.id as adm from usuarios u where u.rol='administrador' and u.activo order by u.id limit 1 \gset
select u.id as prev, c.id as cli from usuarios u join clientes c on c.preventista_id=u.id and c.activo
  where u.rol='preventista' and u.activo order by c.nombre_comercio limit 1 \gset
select id as pa, precio_normal as qa from productos where activo and visible_preventistas and precio_normal>1 order by nombre limit 1 \gset
select id as pb from productos where activo and visible_preventistas and precio_normal>1 and id<>:'pa' order by nombre limit 1 \gset
select id as pc, precio_normal as qc from productos where activo and visible_preventistas and precio_normal>1 and id not in (:'pa',:'pb') order by nombre limit 1 \gset
select id as veh from ubicaciones_stock where codigo='vehiculo' \gset
select id as dep from ubicaciones_stock where codigo='deposito_alberdi' \gset
set session_replication_role = replica;
delete from stock_movimientos where producto_id in (:'pa',:'pb',:'pc');
delete from stock_actual where producto_id in (:'pa',:'pb',:'pc');
update productos set control_stock=false, fracciona_de=null, unidades_por_origen=null where id in (:'pa',:'pb',:'pc');
update productos set fracciona_de=null, unidades_por_origen=null where fracciona_de in (:'pa',:'pb',:'pc');
update viajes_vehiculo set estado='cerrado', cerrado_at=clock_timestamp() where estado='abierto';
set session_replication_role = origin;
create temp table r(paso text, ok boolean) on commit drop;
grant all on r to authenticated;
select set_config('e.pb', :'pb', true), set_config('e.pc', :'pc', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', :'adm', true);
do $$ begin perform stock_configurar_fraccion(current_setting('e.pc')::uuid, current_setting('e.pb')::uuid, 4); end $$;
select stock_contar(gen_random_uuid(), 'deposito_alberdi', jsonb_build_array(
  jsonb_build_object('producto_id',:'pa','cantidad',10), jsonb_build_object('producto_id',:'pb','cantidad',1),
  jsonb_build_object('producto_id',:'pc','cantidad',0)), now() - interval '1 hour') is not null as c \gset

select set_config('request.jwt.claim.sub', :'prev', true);
select crear_pedido_sin_conexion(gen_random_uuid(), :'cli', 'normal', 'venta_directa', '', current_date,
  jsonb_build_array(jsonb_build_object('producto_id',:'pa','cantidad',3,'precio_unitario',:qa,'subtotal',3*:qa,'tipo_precio','normal'),
                    jsonb_build_object('producto_id',:'pc','cantidad',3,'precio_unitario',:qc,'subtotal',3*:qc,'tipo_precio','normal')),
  now()) as v1 \gset
select set_config('request.jwt.claim.sub', :'adm', true);
-- 1) Sin cargar el vehículo: sale del depósito (y se abre 1 bolsa de B en el depósito para C).
select jsonb_agg(jsonb_build_object('detalle_id',id,'cantidad_entregada',cantidad)) as o1 from pedido_detalles where pedido_id=:'v1' \gset
select finalizar_gestion_sin_conexion(gen_random_uuid(), :'v1', now(), 'pendiente', :'o1', '[]', 'sin_pago', 'sin_senal') is not null as x1 \gset
insert into r select 'sin_carga',
  (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pa')=0
  and (select cantidad from stock_actual where ubicacion_id=:'dep' and producto_id=:'pa')=7
  and (select cantidad from stock_actual where ubicacion_id=:'dep' and producto_id=:'pb')=0
  and (select cantidad from stock_actual where ubicacion_id=:'dep' and producto_id=:'pc')=1
  and (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pc')=0;

-- 2) Con la carga registrada (viaje abierto): lo que no alcanza arriba sale del depósito.
select stock_cargar_vehiculo(gen_random_uuid(), jsonb_build_array(jsonb_build_object('producto_id',:'pa','cantidad',2)), now()) is not null as l \gset
select set_config('request.jwt.claim.sub', :'prev', true);
select crear_pedido_sin_conexion(gen_random_uuid(), :'cli', 'normal', 'venta_directa', '', current_date,
  jsonb_build_array(jsonb_build_object('producto_id',:'pa','cantidad',3,'precio_unitario',:qa,'subtotal',3*:qa,'tipo_precio','normal')),
  now()) as v2 \gset
select set_config('request.jwt.claim.sub', :'adm', true);
select jsonb_agg(jsonb_build_object('detalle_id',id,'cantidad_entregada',cantidad)) as o2 from pedido_detalles where pedido_id=:'v2' \gset
select finalizar_gestion_sin_conexion(gen_random_uuid(), :'v2', now(), 'pendiente', :'o2', '[]', 'sin_pago', 'sin_senal') is not null as x2 \gset
insert into r select 'con_carga',
  (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pa')=0
  and (select cantidad from stock_actual where ubicacion_id=:'dep' and producto_id=:'pa')=4;

-- 3) Si igual quedó en negativo arriba (por ejemplo, de antes): se descuenta del depósito, a lo sumo
--    lo que falta, y repetir la misma operación no mueve dos veces.
reset role;
update stock_actual set cantidad=-2 where ubicacion_id=:'veh' and producto_id=:'pa';
set local role authenticated;
select set_config('request.jwt.claim.sub', :'adm', true);
select gen_random_uuid() as op \gset
select stock_vehiculo_faltante_del_deposito(:'op', jsonb_build_array(jsonb_build_object('producto_id',:'pa','cantidad',5)), now())->>'movidos' as m1 \gset
select stock_vehiculo_faltante_del_deposito(:'op', jsonb_build_array(jsonb_build_object('producto_id',:'pa','cantidad',5)), now())->>'movidos' as m2 \gset
insert into r select 'faltante_del_deposito', :'m1'='1' and :'m2'='1'
  and (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pa')=0
  and (select cantidad from stock_actual where ubicacion_id=:'dep' and producto_id=:'pa')=2;
reset role;
select coalesce(string_agg(paso, ', ') filter (where not ok), '') as fallas,
  bool_and(ok) and count(*) = 3 as todo_ok from r \gset
\if :todo_ok \else \echo 'FALLA en:' :'fallas' \quit \endif
rollback;
\echo ESCENARIO_OK
