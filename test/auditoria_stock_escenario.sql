-- Escenario: liquidación del viaje por producto, motivos, stock a revisar, historial y movimientos
-- del día (todo se deshace).
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
update productos set control_stock=true, se_compra_a_pedido=false, fracciona_de=null, unidades_por_origen=null
 where id in (:'pa',:'pb',:'pc');
update productos set fracciona_de=null, unidades_por_origen=null where fracciona_de in (:'pa',:'pb',:'pc');
update viajes_vehiculo set estado='cerrado', cerrado_at=clock_timestamp() where estado='abierto';
-- Lo que haya arriba de pruebas anteriores no entra en este viaje (el cierre pide contar todo).
update stock_actual set cantidad = 0 where ubicacion_id = :'veh' and cantidad <> 0;
set session_replication_role = origin;
create temp table r(paso text, ok boolean) on commit drop;
grant all on r to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'adm', true);

-- Antes del viaje: depósito A 10, B 5, C 3; el vehículo ya tenía 1 de B.
select stock_contar(gen_random_uuid(), 'deposito_alberdi', jsonb_build_array(
  jsonb_build_object('producto_id',:'pa','cantidad',10), jsonb_build_object('producto_id',:'pb','cantidad',5),
  jsonb_build_object('producto_id',:'pc','cantidad',3)), now() - interval '2 hours') is not null as c1 \gset
select stock_contar(gen_random_uuid(), 'vehiculo', jsonb_build_array(
  jsonb_build_object('producto_id',:'pb','cantidad',1)), now() - interval '2 hours') is not null as c2 \gset
reset role;
-- (en la vida real cada cosa pasa en otro momento; acá todo es la misma transacción)
update stock_movimientos set created_at = now() - interval '2 hours' where producto_id in (:'pa',:'pb',:'pc');
set local role authenticated;
select set_config('request.jwt.claim.sub', :'adm', true);

-- El viaje: carga A 4 y B 2; compra 1 de A arriba; se venden 3 de A y 1 de C (C no estaba arriba:
-- se toma del depósito).
select stock_cargar_vehiculo(gen_random_uuid(), jsonb_build_array(jsonb_build_object('producto_id',:'pa','cantidad',4),
  jsonb_build_object('producto_id',:'pb','cantidad',2)), now()) ->> 'viaje_id' as viaje \gset
select set_config('e.viaje', :'viaje', true), set_config('e.pb', :'pb', true);
select stock_registrar_compra(gen_random_uuid(), 'vehiculo', jsonb_build_array(
  jsonb_build_object('producto_id',:'pa','cantidad',1,'costo_unitario',100)), now(), 'Proveedor QA', false, null) is not null as co \gset
select set_config('request.jwt.claim.sub', :'prev', true);
select crear_pedido_sin_conexion(gen_random_uuid(), :'cli', 'normal', 'venta_directa', '', current_date,
  jsonb_build_array(jsonb_build_object('producto_id',:'pa','cantidad',3,'precio_unitario',:qa,'subtotal',3*:qa,'tipo_precio','normal'),
                    jsonb_build_object('producto_id',:'pc','cantidad',1,'precio_unitario',:qc,'subtotal',:qc,'tipo_precio','normal')),
  now()) as v1 \gset
select set_config('request.jwt.claim.sub', :'adm', true);
select jsonb_agg(jsonb_build_object('detalle_id',id,'cantidad_entregada',cantidad)) as o1 from pedido_detalles where pedido_id=:'v1' \gset
select finalizar_gestion_sin_conexion(gen_random_uuid(), :'v1', now(), 'pendiente', :'o1', '[]', 'sin_pago', 'sin_senal') is not null as x1 \gset

-- Cierre: se cuentan A 1 (debía 2), B 3 y C 0; se baja lo que sobró.
select stock_cerrar_viaje(gen_random_uuid(), :'viaje', jsonb_build_array(
  jsonb_build_object('producto_id',:'pa','cantidad',1), jsonb_build_object('producto_id',:'pb','cantidad',3),
  jsonb_build_object('producto_id',:'pc','cantidad',0)), true, now()) is not null as ci \gset

-- 1) Liquidación por producto.
select stock_liquidacion_viaje(:'viaje') as liq \gset
select (select x from jsonb_array_elements((:'liq'::jsonb)->'filas') x where x->>'producto_id' = :'pa') as fa \gset
select (select x from jsonb_array_elements((:'liq'::jsonb)->'filas') x where x->>'producto_id' = :'pb') as fb \gset
select (select x from jsonb_array_elements((:'liq'::jsonb)->'filas') x where x->>'producto_id' = :'pc') as fc \gset
insert into r select 'liquidacion_a',
  (:'fa'::jsonb->>'tenia')::numeric = 0 and (:'fa'::jsonb->>'cargo')::numeric = 5
  and (:'fa'::jsonb->>'vendido')::numeric = 3 and (:'fa'::jsonb->>'deberia')::numeric = 2
  and (:'fa'::jsonb->>'contado')::numeric = 1 and (:'fa'::jsonb->>'diferencia')::numeric = -1
  and (:'fa'::jsonb->>'otros')::numeric = 0 and (:'fa'::jsonb->>'bajado_al_cierre')::numeric = 1;
insert into r select 'liquidacion_b',
  (:'fb'::jsonb->>'tenia')::numeric = 1 and (:'fb'::jsonb->>'cargo')::numeric = 2
  and (:'fb'::jsonb->>'deberia')::numeric = 3 and (:'fb'::jsonb->>'diferencia')::numeric = 0;
insert into r select 'tomado_del_deposito',
  (:'fc'::jsonb->>'deposito')::numeric = 1 and (:'fc'::jsonb->>'vendido')::numeric = 1
  and (:'fc'::jsonb->>'deberia')::numeric = 0
  and (:'liq'::jsonb->'filas'->0->>'producto_id') = :'pa'
  and ((:'liq'::jsonb)->'ventas'->>'cantidad')::int >= 1;

-- 2) Motivos: sin motivo aparece en "a revisar"; con motivo, no. Sin diferencia no se puede.
select jsonb_array_length(stock_a_revisar()->'sin_motivo') as antes \gset
do $$ begin perform stock_liquidacion_motivos_guardar(current_setting('e.viaje')::uuid,
  jsonb_build_array(jsonb_build_object('producto_id', current_setting('e.pb'), 'motivo', 'rotura'))); raise exception 'debió fallar';
exception when others then if sqlerrm <> 'Ese producto no tiene diferencia en este viaje' then raise; end if; end $$;
select stock_liquidacion_motivos_guardar(:'viaje', jsonb_build_array(jsonb_build_object('producto_id',:'pa','motivo','rotura'))) as g \gset
select jsonb_array_length(stock_a_revisar()->'sin_motivo') as despues \gset
select (stock_liquidacion_viaje(:'viaje')->'filas'->0->>'motivo') as mot \gset
select (x->>'sin_motivo')::int as sm from jsonb_array_elements(stock_viajes_recientes(5)) x where x->>'id' = :'viaje' \gset
insert into r select 'motivos', :antes = 1 and :despues = 0 and :'mot' = 'rotura' and :sm = 0;

-- 3) Negativos con lugar y desde cuándo; lo que no se cuenta hace más de 30 días.
reset role;
set session_replication_role = replica;
insert into stock_movimientos(ubicacion_id, producto_id, tipo, cantidad_anterior, cantidad_delta, cantidad_nueva, motivo, usuario_id)
 values (:'dep', :'pb', 'ajuste_salida', 2, -4, -2, 'QA', :'adm');
update stock_actual set cantidad = -2 where ubicacion_id = :'dep' and producto_id = :'pb';
update stock_actual set contado_at = now() - interval '40 days' where producto_id = :'pc';
update stock_actual set cantidad = 2 where ubicacion_id = :'dep' and producto_id = :'pc';
set session_replication_role = origin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'adm', true);
select stock_a_revisar() as rev \gset
insert into r select 'a_revisar',
  exists(select 1 from jsonb_array_elements((:'rev'::jsonb)->'negativos') x
   where x->>'producto_id' = :'pb' and x->>'ubicacion' = 'deposito_alberdi' and x->>'desde' is not null)
  and exists(select 1 from jsonb_array_elements((:'rev'::jsonb)->'sin_contar'->'productos') x where x->>'producto_id' = :'pc');

-- 4) Historial del producto y movimientos del día.
select stock_historial_producto(:'pa') as his \gset
select stock_movimientos_dia(null) as dia \gset
insert into r select 'historial_y_dia',
  jsonb_array_length(:'his'::jsonb) >= 6
  and exists(select 1 from jsonb_array_elements(:'his'::jsonb) x where x->>'operacion' = 'compra' and x->>'contraparte' = 'Proveedor QA')
  and exists(select 1 from jsonb_array_elements(:'dia'::jsonb) x where x->>'tipo' = 'carga_vehiculo')
  and exists(select 1 from jsonb_array_elements(:'dia'::jsonb) x where x->>'tipo' = 'cierre_viaje');

-- 5) Un preventista sin permiso no ve nada; la liquidación es solo de administración.
select set_config('request.jwt.claim.sub', :'prev', true);
do $$ begin perform stock_a_revisar(); raise exception 'debió fallar';
exception when others then if sqlerrm <> 'Solo administración o ayuda en el depósito' then raise; end if; end $$;
do $$ begin perform stock_liquidacion_viaje(current_setting('e.viaje')::uuid); raise exception 'debió fallar';
exception when others then if sqlerrm <> 'Solo administración activa' then raise; end if; end $$;
insert into r select 'permisos', true;
reset role;

select coalesce(string_agg(paso, ', ') filter (where ok is not true), '') as fallas,
  bool_and(ok) and count(*) = 7 as todo_ok from r \gset
\if :todo_ok \else \echo 'FALLA en:' :'fallas' \quit \endif
rollback;
\echo ESCENARIO_OK
