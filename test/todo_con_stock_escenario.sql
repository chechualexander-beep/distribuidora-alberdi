-- Escenario: todos los productos llevan stock y no se pasa más de lo que hay (todo se deshace).
\set ON_ERROR_STOP 1
begin;
select u.id as adm from usuarios u where u.rol='administrador' and u.activo order by u.id limit 1 \gset
select id as pa from productos where activo order by nombre limit 1 \gset
select id as pb from productos where activo and id<>:'pa' order by nombre limit 1 \gset
select id as pc from productos where activo and id not in (:'pa',:'pb') order by nombre limit 1 \gset
select id as veh from ubicaciones_stock where codigo='vehiculo' \gset
select id as dep from ubicaciones_stock where codigo='deposito_alberdi' \gset
set session_replication_role = replica;
delete from stock_movimientos where producto_id in (:'pa',:'pb',:'pc');
delete from stock_actual where producto_id in (:'pa',:'pb',:'pc');
update productos set control_stock=true, se_compra_a_pedido=false, fracciona_de=null, unidades_por_origen=null
 where id in (:'pa',:'pb',:'pc');
update productos set fracciona_de=null, unidades_por_origen=null where fracciona_de in (:'pa',:'pb',:'pc');
update viajes_vehiculo set estado='cerrado', cerrado_at=clock_timestamp() where estado='abierto';
set session_replication_role = origin;
create temp table r(paso text, ok boolean) on commit drop;
grant all on r to authenticated;
select set_config('e.pa', :'pa', true), set_config('e.pb', :'pb', true), set_config('e.pc', :'pc', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', :'adm', true);
do $$ begin perform stock_configurar_fraccion(current_setting('e.pc')::uuid, current_setting('e.pb')::uuid, 4); end $$;
select stock_contar(gen_random_uuid(), 'deposito_alberdi', jsonb_build_array(
  jsonb_build_object('producto_id',:'pa','cantidad',3), jsonb_build_object('producto_id',:'pb','cantidad',1),
  jsonb_build_object('producto_id',:'pc','cantidad',0)), now() - interval '1 hour') is not null as c \gset

-- 1) No se carga más de lo que figura en el depósito.
do $$ begin perform stock_cargar_vehiculo(gen_random_uuid(), jsonb_build_array(
  jsonb_build_object('producto_id', current_setting('e.pa'), 'cantidad', 5)), now()); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'No alcanza en el depósito:%(hay 3, se quiere cargar 5)' then raise; end if; end $$;
insert into r select 'carga_de_mas', (select cantidad from stock_actual where ubicacion_id=:'dep' and producto_id=:'pa')=3;

-- 2) Carga justa, y un suelto que no hay abre una bolsa del depósito.
select stock_cargar_vehiculo(gen_random_uuid(), jsonb_build_array(
  jsonb_build_object('producto_id',:'pa','cantidad',3), jsonb_build_object('producto_id',:'pc','cantidad',2)), now()) as l \gset
insert into r select 'carga', (select cantidad from stock_actual where ubicacion_id=:'dep' and producto_id=:'pa')=0
  and (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pa')=3
  and (select cantidad from stock_actual where ubicacion_id=:'dep' and producto_id=:'pb')=0
  and (select cantidad from stock_actual where ubicacion_id=:'dep' and producto_id=:'pc')=2
  and (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pc')=2;

-- 3) No se baja más de lo que figura en el vehículo.
do $$ begin perform stock_bajar_vehiculo(gen_random_uuid(), jsonb_build_array(
  jsonb_build_object('producto_id', current_setting('e.pa'), 'cantidad', 4)), now()); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'No hay tanto en el vehículo:%' then raise; end if; end $$;
select stock_bajar_vehiculo(gen_random_uuid(), jsonb_build_array(jsonb_build_object('producto_id',:'pa','cantidad',1)), now()) as b \gset
insert into r select 'bajada', (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pa')=2
  and (select cantidad from stock_actual where ubicacion_id=:'dep' and producto_id=:'pa')=1;

-- 4) "A pedido" es una etiqueta: se pone y se saca, y el producto sigue llevando stock.
do $$ begin perform stock_marcar_a_pedido(current_setting('e.pa')::uuid); end $$;
select se_compra_a_pedido as marcado from stock_estado() where producto_id=:'pa' \gset
do $$ begin perform stock_marcar_a_pedido(current_setting('e.pa')::uuid, false); end $$;
insert into r select 'etiqueta', :'marcado'
  and (select control_stock and not se_compra_a_pedido from productos where id=:'pa');
reset role;

-- 5) Los productos nuevos llevan stock.
insert into r select 'nuevo_con_stock', (select column_default from information_schema.columns
  where table_schema='public' and table_name='productos' and column_name='control_stock')='true';
select coalesce(string_agg(paso, ', ') filter (where not ok), '') as fallas,
  bool_and(ok) and count(*) = 5 as todo_ok from r \gset
\if :todo_ok \else \echo 'FALLA en:' :'fallas' \quit \endif
rollback;
\echo ESCENARIO_OK
