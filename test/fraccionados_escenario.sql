-- Escenario: productos fraccionados (a mano y automático al entregar). Todo se deshace.
\set ON_ERROR_STOP 1
begin;
select u.id as adm from usuarios u where u.rol='administrador' and u.activo order by u.id limit 1 \gset
select u.id as prev, c.id as cli from usuarios u join clientes c on c.preventista_id=u.id and c.activo
  where u.rol='preventista' and u.activo order by c.nombre_comercio limit 1 \gset
select id as pa from productos where activo and visible_preventistas and precio_normal>1 order by nombre limit 1 \gset
select id as pb, precio_normal as qb from productos where activo and visible_preventistas and precio_normal>1 and id<>:'pa' order by nombre limit 1 \gset
select id as pc from productos where activo and visible_preventistas and precio_normal>1 and id not in (:'pa',:'pb') order by nombre limit 1 \gset
select id as veh from ubicaciones_stock where codigo='vehiculo' \gset
set session_replication_role = replica;
delete from stock_movimientos where producto_id in (:'pa',:'pb',:'pc');
delete from stock_actual where producto_id in (:'pa',:'pb',:'pc');
update productos set control_stock=false, fracciona_de=null, unidades_por_origen=null where id in (:'pa',:'pb',:'pc');
update productos set fracciona_de=null, unidades_por_origen=null where fracciona_de in (:'pa',:'pb',:'pc');
set session_replication_role = origin;
create temp table r(paso text, ok boolean) on commit drop;
grant all on r to authenticated;
select set_config('e.pa', :'pa', true), set_config('e.pb', :'pb', true), set_config('e.pc', :'pc', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', :'adm', true);
-- B sale de A: 1 de A → 4 de B.
do $$ begin perform stock_configurar_fraccion(current_setting('e.pb')::uuid, current_setting('e.pa')::uuid, 4); end $$;
do $$ begin perform stock_configurar_fraccion(current_setting('e.pa')::uuid, current_setting('e.pb')::uuid, 2); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Un producto no puede ser%' then raise; end if; end $$;
select stock_contar(gen_random_uuid(), 'vehiculo', jsonb_build_array(
  jsonb_build_object('producto_id',:'pa','cantidad',2), jsonb_build_object('producto_id',:'pb','cantidad',1)),
  now() - interval '1 hour') is not null as c \gset
-- 1) A mano: abro 1 de A.
select stock_fraccionar(gen_random_uuid(), :'pb', 1, 'vehiculo', now()) as f1 \gset
insert into r select 'a_mano', (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pa')=1
  and (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pb')=5
  and (select fracciona_de from stock_estado() where producto_id=:'pb')=:'pa'::uuid;

-- 2) Venta de 7 de B (hay 5): al entregar se abre 1 de A sola → quedan 2.
select set_config('request.jwt.claim.sub', :'prev', true);
select crear_pedido_sin_conexion(gen_random_uuid(), :'cli', 'normal', 'venta_directa', '', current_date,
  jsonb_build_array(jsonb_build_object('producto_id',:'pb','cantidad',7,'precio_unitario',:qb,'subtotal',7*:qb,'tipo_precio','normal')),
  now()) as v1 \gset
select crear_pedido_sin_conexion(gen_random_uuid(), :'cli', 'normal', 'venta_directa', '', current_date,
  jsonb_build_array(jsonb_build_object('producto_id',:'pb','cantidad',5,'precio_unitario',:qb,'subtotal',5*:qb,'tipo_precio','normal')),
  now()) as v2 \gset
select set_config('request.jwt.claim.sub', :'adm', true);
select jsonb_agg(jsonb_build_object('detalle_id',id,'cantidad_entregada',cantidad)) as o1 from pedido_detalles where pedido_id=:'v1' \gset
select finalizar_gestion_sin_conexion(gen_random_uuid(), :'v1', now(), 'pendiente', :'o1', '[]', 'sin_pago', 'sin_senal') is not null as x1 \gset
insert into r select 'automatico', (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pa')=0
  and (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pb')=2
  and exists(select 1 from stock_movimientos where producto_id=:'pa' and tipo='fraccion_salida'
   and motivo='Fraccionado automático al entregar');

-- 3) Otra de 5 (hay 2 y no quedan de A) sin viaje abierto: lo que falta se toma del depósito
--    (que queda en negativo para revisar); el vehículo queda en 0.
select jsonb_agg(jsonb_build_object('detalle_id',id,'cantidad_entregada',cantidad)) as o2 from pedido_detalles where pedido_id=:'v2' \gset
select finalizar_gestion_sin_conexion(gen_random_uuid(), :'v2', now(), 'pendiente', :'o2', '[]', 'sin_pago', 'sin_senal') is not null as x2 \gset
insert into r select 'sin_origen', (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pb')=0
  and (select cantidad from stock_actual s join ubicaciones_stock u on u.id=s.ubicacion_id
   where u.codigo='deposito_alberdi' and s.producto_id=:'pb')=-3
  and (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pa')=0;
-- 4) Un suelto que se vincula a un cerrado con stock pasa a llevar stock solo (en 0) y no se
--    puede dejar "a pedido".
do $$ begin perform stock_configurar_fraccion(current_setting('e.pc')::uuid, current_setting('e.pa')::uuid, 3); end $$;
insert into r select 'suelto_automatico', (select control_stock from productos where id=:'pc');
do $$ begin perform stock_marcar_a_pedido(current_setting('e.pc')::uuid); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Este producto sale de otro%' then raise; end if; end $$;
reset role;
select coalesce(string_agg(paso, ', ') filter (where not ok), '') as fallas,
  bool_and(ok) and count(*) = 4 as todo_ok from r \gset
\if :todo_ok \else \echo 'FALLA en:' :'fallas' \quit \endif
rollback;
\echo ESCENARIO_OK
