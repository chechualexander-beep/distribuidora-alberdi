-- Escenario: stock por producto, vehículo y viaje (copia de producción o TESTING; todo se deshace).
\set ON_ERROR_STOP 1
begin;
select u.id as adm from usuarios u where u.rol='administrador' and u.activo order by u.id limit 1 \gset
select u.id as prev, c.id as cli from usuarios u join clientes c on c.preventista_id=u.id and c.activo
  where u.rol='preventista' and u.activo order by c.nombre_comercio limit 1 \gset
select id as pa, precio_normal as qa from productos where activo and visible_preventistas and precio_normal>1 order by nombre limit 1 \gset
select id as pb, precio_normal as qb from productos where activo and visible_preventistas and precio_normal>1 and id<>:'pa' order by nombre limit 1 \gset
select id as pc, precio_normal as qc from productos where activo and visible_preventistas and precio_normal>1 and id not in (:'pa',:'pb') order by nombre limit 1 \gset
update productos set control_stock=false where id in (:'pa',:'pb',:'pc');
select set_config('e.pa', :'pa', true), set_config('e.pb', :'pb', true), set_config('e.cli', :'cli', true);
select id as dep from ubicaciones_stock where codigo='deposito_alberdi' \gset
select id as veh from ubicaciones_stock where codigo='vehiculo' \gset
-- Partir de cero para estos productos (por si TESTING ya tenía filas).
set session_replication_role = replica;
delete from stock_movimientos where producto_id in (:'pa',:'pb',:'pc');
delete from stock_actual where producto_id in (:'pa',:'pb',:'pc');
update viajes_vehiculo set estado='cerrado', cerrado_at=clock_timestamp() where estado='abierto';
-- El vehículo vacío para la prueba (en TESTING puede tener carga de pruebas a mano).
update stock_actual set cantidad=0 where ubicacion_id=:'veh';
set session_replication_role = origin;
create temp table r(paso text, ok boolean) on commit drop;
grant all on r to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', :'adm', true);
-- 1) Conteo en el depósito: A y B pasan a "con stock". Reenviar no duplica.
select gen_random_uuid() as c1 \gset
select stock_contar(:'c1', 'deposito_alberdi', jsonb_build_array(
  jsonb_build_object('producto_id',:'pa','cantidad',20), jsonb_build_object('producto_id',:'pb','cantidad',10)), now()) as r1 \gset
select stock_contar(:'c1', 'deposito_alberdi', jsonb_build_array(
  jsonb_build_object('producto_id',:'pa','cantidad',20), jsonb_build_object('producto_id',:'pb','cantidad',10)), now()) as r1b \gset
insert into r values ('conteo', (:'r1'::jsonb->>'nuevos_con_stock')::int=2 and :'r1'=:'r1b');
do $$ begin perform stock_contar(current_setting('e.cli')::uuid, 'deposito_alberdi', '[]', now()); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'La lista de productos%' then raise; end if; end $$;

-- 2) Cargar el vehículo (C es "a pedido": no se mueve). Abre el viaje.
select stock_cargar_vehiculo(gen_random_uuid(), jsonb_build_array(
  jsonb_build_object('producto_id',:'pa','cantidad',8), jsonb_build_object('producto_id',:'pb','cantidad',5),
  jsonb_build_object('producto_id',:'pc','cantidad',2)), now(), :'prev') as r2 \gset
select :'r2'::jsonb->>'viaje_id' as viaje \gset
insert into r select 'carga', (:'r2'::jsonb->>'movidos')::int=2 and (:'r2'::jsonb->>'a_pedido')::int=1
  and (select cantidad from stock_actual where ubicacion_id=:'dep' and producto_id=:'pa')=12;

-- 3) El preventista vende (venta directa): queda en el viaje y comprometida.
select set_config('request.jwt.claim.sub', :'prev', true);
select crear_pedido_sin_conexion(gen_random_uuid(), :'cli', 'normal', 'venta_directa', '', current_date,
  jsonb_build_array(
   jsonb_build_object('producto_id',:'pa','cantidad',3,'precio_unitario',:qa,'subtotal',3*:qa,'tipo_precio','normal'),
   jsonb_build_object('producto_id',:'pc','cantidad',1,'precio_unitario',:qc,'subtotal',:qc,'tipo_precio','normal')),
  now()) as v1 \gset
select stock_vehiculo_disponible() as d1 \gset
insert into r select 'disponible', (select viaje_id from pedidos where id=:'v1')=:'viaje'::uuid
  and exists(select 1 from jsonb_array_elements(:'d1'::jsonb->'productos') x where x->>'producto_id'=:'pa'
   and (x->>'en_vehiculo')::numeric=8 and (x->>'ventas')::numeric=3
   and (x->>'disponible')::numeric = 8 - 3 - (x->>'reparto')::numeric)
  and not exists(select 1 from jsonb_array_elements(:'d1'::jsonb->'productos') x where x->>'producto_id'=:'pc');

-- 3b) Un pedido facturado del reparto con A x2: lo libre para venta directa baja 2.
select (x->>'reparto')::numeric as rep0 from jsonb_array_elements(:'d1'::jsonb->'productos') x where x->>'producto_id'=:'pa' \gset
select crear_pedido_sin_conexion(gen_random_uuid(), :'cli', 'normal', 'pedido', '', current_date,
  jsonb_build_array(jsonb_build_object('producto_id',:'pa','cantidad',2,'precio_unitario',:qa,'subtotal',2*:qa,'tipo_precio','normal')),
  now()) as rp \gset
reset role;
set session_replication_role = replica;
update pedidos set facturado = true where id = :'rp';
set session_replication_role = origin;
set local role authenticated;
select stock_vehiculo_disponible() as d1b \gset
insert into r select 'reparto', exists(select 1 from jsonb_array_elements(:'d1b'::jsonb->'productos') x
  where x->>'producto_id'=:'pa' and (x->>'reparto')::numeric = :rep0 + 2
   and (x->>'disponible')::numeric = 8 - 3 - :rep0 - 2 and (x->>'comprometido')::numeric = 3 + :rep0 + 2);
reset role;
set session_replication_role = replica;
update pedidos set estado = 'anulado' where id = :'rp';
set session_replication_role = origin;
set local role authenticated;
do $$ begin perform stock_contar(gen_random_uuid(), 'deposito_alberdi', jsonb_build_array(
  jsonb_build_object('producto_id',current_setting('e.pa'),'cantidad',1)), now()); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Solo administración%' then raise; end if; end $$;
-- Otra venta: B x7 (arriba hay 5).
select crear_pedido_sin_conexion(gen_random_uuid(), :'cli', 'normal', 'venta_directa', '', current_date,
  jsonb_build_array(jsonb_build_object('producto_id',:'pb','cantidad',7,'precio_unitario',:qb,'subtotal',7*:qb,'tipo_precio','normal')),
  now()) as v2 \gset
select crear_pedido_sin_conexion(gen_random_uuid(), :'cli', 'normal', 'venta_directa', '', current_date,
  jsonb_build_array(jsonb_build_object('producto_id',:'pa','cantidad',1,'precio_unitario',:qa,'subtotal',:qa,'tipo_precio','normal')),
  now()) as v3 \gset

-- 4) El administrador entrega: descuenta del vehículo; lo que falta de B sale del depósito (no queda en negativo).
select set_config('request.jwt.claim.sub', :'adm', true);
select gen_random_uuid() as s1 \gset
select preparar_finalizacion_contexto(:'s1', :'v1') as x1 \gset
select jsonb_agg(jsonb_build_object('detalle_id',id,'cantidad_entregada',cantidad)) as o1 from pedido_detalles where pedido_id=:'v1' \gset
select finalizar_gestion_pedido_contexto(:'s1', :'v1', (:'x1'::jsonb->>'fecha_fisica')::timestamptz, 'pendiente', :'o1', '[]',
  'sin_pago', (:'x1'::jsonb->>'regimen_id')::uuid, 2, null, null, null) is not null as f1 \gset
select gen_random_uuid() as s2 \gset
select preparar_finalizacion_contexto(:'s2', :'v2') as x2 \gset
select jsonb_agg(jsonb_build_object('detalle_id',id,'cantidad_entregada',cantidad)) as o2 from pedido_detalles where pedido_id=:'v2' \gset
select finalizar_gestion_pedido_contexto(:'s2', :'v2', (:'x2'::jsonb->>'fecha_fisica')::timestamptz, 'pendiente', :'o2', '[]',
  'sin_pago', (:'x2'::jsonb->>'regimen_id')::uuid, 2, null, null, null) is not null as f2 \gset
insert into r select 'entrega', (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pa')=5
  and (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pb')=0
  and (select cantidad from stock_actual where ubicacion_id=:'dep' and producto_id=:'pb')=3
  and not exists(select 1 from stock_actual where producto_id=:'pc');

-- 5) Entrega preparada ANTES de un conteo y enviada después: el conteo ya la incluye.
select gen_random_uuid() as s3 \gset
select preparar_finalizacion_contexto(:'s3', :'v3') as x3 \gset
select stock_contar(gen_random_uuid(), 'vehiculo', jsonb_build_array(jsonb_build_object('producto_id',:'pa','cantidad',4)),
  clock_timestamp()) as r5 \gset
select jsonb_agg(jsonb_build_object('detalle_id',id,'cantidad_entregada',cantidad)) as o3 from pedido_detalles where pedido_id=:'v3' \gset
select finalizar_gestion_pedido_contexto(:'s3', :'v3', (:'x3'::jsonb->>'fecha_fisica')::timestamptz, 'pendiente', :'o3', '[]',
  'sin_pago', (:'x3'::jsonb->>'regimen_id')::uuid, 2, null, null, null) is not null as f3 \gset
insert into r select 'conteo_posterior', (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pa')=4
  and (:'r5'::jsonb->'diferencias'->0->>'antes')::numeric=5;

-- 6) Compra en el camino: B entra al vehículo; C ("a pedido") pasa a llevar stock con lo comprado.
select stock_registrar_compra(gen_random_uuid(), 'vehiculo', jsonb_build_array(
  jsonb_build_object('producto_id',:'pb','cantidad',3,'costo_unitario',50),
  jsonb_build_object('producto_id',:'pc','cantidad',2,'costo_unitario',100)), now(), 'Almacén del camino') as r6 \gset
insert into r select 'compra', (:'r6'::jsonb->>'total')::numeric=350 and (:'r6'::jsonb->>'con_stock')::int=2
  and (:'r6'::jsonb->>'nuevos_con_stock')::int=1
  and (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pc')=2
  and (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pb')=3
  and (select viaje_id from stock_operaciones where id=(:'r6'::jsonb->>'operacion_id')::uuid)=:'viaje'::uuid;

-- 7) Bajar algo al depósito y fechas inválidas.
select stock_bajar_vehiculo(gen_random_uuid(), jsonb_build_array(jsonb_build_object('producto_id',:'pa','cantidad',1)), now()) as r7 \gset
do $$ begin perform stock_bajar_vehiculo(gen_random_uuid(), jsonb_build_array(
  jsonb_build_object('producto_id',current_setting('e.pa'),'cantidad',1)), now() - interval '80 hours'); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'La operación tiene más de 72 horas%' then raise; end if; end $$;

-- 7b) Cambiar el preventista del viaje abierto (sacarlo y volver a ponerlo).
select stock_viaje_preventista(:'viaje', null) as p1 \gset
select preventista_id is null as sinprev from viajes_vehiculo where id=:'viaje' \gset
select stock_viaje_preventista(:'viaje', :'prev') as p2 \gset
insert into r select 'preventista', :'sinprev' and (select preventista_id from viajes_vehiculo where id=:'viaje')=:'prev'::uuid;

-- 8) Cerrar el viaje: el conteo tiene que incluir todo lo de arriba; muestra diferencias y baja.
do $$ begin perform stock_cerrar_viaje(gen_random_uuid(), (select id from viajes_vehiculo where estado='abierto'),
  jsonb_build_array(jsonb_build_object('producto_id',current_setting('e.pa'),'cantidad',3)), true, now()); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Falta contar:%' then raise; end if; end $$;
select stock_cerrar_viaje(gen_random_uuid(), :'viaje', jsonb_build_array(
  jsonb_build_object('producto_id',:'pa','cantidad',3), jsonb_build_object('producto_id',:'pb','cantidad',2),
  jsonb_build_object('producto_id',:'pc','cantidad',2)), true, now()) as r8 \gset
insert into r select 'cierre', jsonb_array_length(:'r8'::jsonb->'diferencias')=1
  and (:'r8'::jsonb->'diferencias'->0->>'diferencia')::numeric=-1
  and (:'r8'::jsonb->>'ventas')::int=3 and (:'r8'::jsonb->>'pendientes_de_entrega')::int=0
  and (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pa')=0
  and (select cantidad from stock_actual where ubicacion_id=:'dep' and producto_id=:'pa')=16
  and (select estado from viajes_vehiculo where id=:'viaje')='cerrado';

do $$ begin perform stock_viaje_preventista((select id from viajes_vehiculo order by abierto_at desc limit 1), null);
  raise exception 'debió fallar';
exception when others then if sqlerrm <> 'El viaje ya está cerrado' then raise; end if; end $$;

-- 9) Sin viaje abierto la venta directa no queda en ningún viaje; "a pedido" deja de mover stock.
select set_config('request.jwt.claim.sub', :'prev', true);
select crear_pedido_sin_conexion(gen_random_uuid(), :'cli', 'normal', 'venta_directa', '', current_date,
  jsonb_build_array(jsonb_build_object('producto_id',:'pa','cantidad',1,'precio_unitario',:qa,'subtotal',:qa,'tipo_precio','normal')),
  now()) as v4 \gset
select stock_vehiculo_disponible()->>'viaje' is null as sinviaje \gset
select set_config('request.jwt.claim.sub', :'adm', true);
do $$ begin perform stock_marcar_a_pedido(current_setting('e.pa')::uuid); end $$;
insert into r select 'fin', (select viaje_id from pedidos where id=:'v4') is null and :'sinviaje'
  and not (select control_stock from productos where id=:'pa')
  and (select count(*) from stock_estado())>0;
reset role;
select coalesce(string_agg(paso, ', ') filter (where not ok), '') as fallas,
  bool_and(ok) and count(*) = 10 as todo_ok from r \gset
\if :todo_ok \else \echo 'FALLA en:' :'fallas' \quit \endif
rollback;
\echo ESCENARIO_OK
