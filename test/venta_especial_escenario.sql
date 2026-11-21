-- Escenario: venta especial del administrador y comisión 0 en sus ventas. Todo se deshace.
\set ON_ERROR_STOP 1
begin;
select u.id as adm from usuarios u where u.rol='administrador' and u.activo order by u.id limit 1 \gset
select u.id as prev from usuarios u where u.rol='preventista' and u.activo order by u.id limit 1 \gset
select id as pa, costo as ca from productos where activo and costo > 0 order by nombre limit 1 \gset
select id as pb from productos where activo and id <> :'pa' order by nombre limit 1 \gset
select id as dep from ubicaciones_stock where codigo='deposito_alberdi' \gset
select id as veh from ubicaciones_stock where codigo='vehiculo' \gset
select gen_random_uuid() as cli \gset
set session_replication_role = replica;
insert into clientes(id, nombre_comercio, direccion, activo) values (:'cli', 'Cliente prueba especial', 'x', true);
delete from stock_movimientos where producto_id in (:'pa', :'pb');
delete from stock_actual where producto_id in (:'pa', :'pb');
update productos set control_stock = true, fracciona_de = null, unidades_por_origen = null where id = :'pa';
update productos set control_stock = false, fracciona_de = null, unidades_por_origen = null where id = :'pb';
update productos set fracciona_de = null, unidades_por_origen = null where fracciona_de in (:'pa', :'pb');
insert into stock_actual(ubicacion_id, producto_id, cantidad) values (:'dep', :'pa', 10), (:'veh', :'pa', 1);
-- Un viaje abierto: la venta especial no tiene que sumarse a él.
update viajes_vehiculo set estado='cerrado', cerrado_at=clock_timestamp() where estado='abierto';
insert into viajes_vehiculo(ubicacion_id, abierto_por) values (:'veh', :'adm');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', :'adm', true);
select set_config('e.pa', :'pa', true), set_config('e.cli', :'cli', true);
create temp table r(paso text, ok boolean) on commit drop;
grant all on r to authenticated;
set local role authenticated;

-- 1) A un cliente, desde el depósito: A 3 × 1000 (precio a mano) + B 2 × 500; paga 2000 efectivo y
--    1000 transferencia; quedan 1000 fiados.
select gen_random_uuid() as v1 \gset
select venta_especial(:'v1', now(), :'cli', 'deposito_alberdi',
  jsonb_build_array(jsonb_build_object('producto_id', :'pa', 'cantidad', 3, 'precio_unitario', 1000),
                    jsonb_build_object('producto_id', :'pb', 'cantidad', 2, 'precio_unitario', 500)),
  jsonb_build_array(jsonb_build_object('medio', 'Efectivo', 'importe', 2000),
                    jsonb_build_object('medio', 'Transferencia', 'importe', 1000))) as r1 \gset
reset role;
insert into r select 'venta', (:'r1'::jsonb->>'total')::numeric = 4000 and (:'r1'::jsonb->>'pagado')::numeric = 3000
  and (:'r1'::jsonb->>'saldo_pendiente')::numeric = 1000
  and (select origen = 'especial' and tipo_operacion = 'venta_directa' and resultado_entrega = 'entregado'
       and viaje_id is null and total = 4000 from pedidos where id = :'v1');
insert into r select 'sin_comision_con_costo', (select bool_and(porcentaje_comision = 0 and importe_comision = 0)
  and sum(cantidad_entregada) = 5 from pedido_detalles where pedido_id = :'v1')
  and (select costo_unitario from pedido_detalles where pedido_id = :'v1' and producto_id = :'pa') = :ca;
insert into r select 'stock', (select cantidad from stock_actual where ubicacion_id = :'dep' and producto_id = :'pa') = 7
  and (select count(*) from stock_movimientos where producto_id = :'pb') = 0;
insert into r select 'cobros', (select count(*) from cobros_cliente where cliente_id = :'cli') = 2
  and (select sum(importe) filter (where medio_pago = 'Transferencia') from cobros_cliente where cliente_id = :'cli') = 1000;
set local role authenticated;

-- 2) Repetida (el teléfono la reenvía): no se duplica nada.
select (venta_especial(:'v1', now(), :'cli', 'deposito_alberdi',
  jsonb_build_array(jsonb_build_object('producto_id', :'pa', 'cantidad', 3, 'precio_unitario', 1000),
                    jsonb_build_object('producto_id', :'pb', 'cantidad', 2, 'precio_unitario', 500)),
  jsonb_build_array(jsonb_build_object('medio', 'Efectivo', 'importe', 2000),
                    jsonb_build_object('medio', 'Transferencia', 'importe', 1000)))->>'repetida')::boolean as rep \gset
insert into r select 'repetida', :'rep';

-- 3) "Consumidor final": no se le fía; pagando todo, desde el vehículo (lo que no alcanza arriba sale
--    del depósito).
do $$ begin perform venta_especial(gen_random_uuid(), now(), null, 'vehiculo',
  jsonb_build_array(jsonb_build_object('producto_id', current_setting('e.pa'), 'cantidad', 2, 'precio_unitario', 800)),
  jsonb_build_array(jsonb_build_object('medio', 'Efectivo', 'importe', 1000))); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'A "Consumidor final" no se le puede fiar%' then raise; end if; end $$;
select gen_random_uuid() as v2 \gset
select venta_especial(:'v2', now(), null, 'vehiculo',
  jsonb_build_array(jsonb_build_object('producto_id', :'pa', 'cantidad', 2, 'precio_unitario', 800)),
  jsonb_build_array(jsonb_build_object('medio', 'Efectivo', 'importe', 1600))) as r2 \gset
reset role;
insert into r select 'consumidor_final', (:'r2'::jsonb->>'saldo_pendiente')::numeric = 0
  and (select cliente_id = consumidor_final_id() from pedidos where id = :'v2')
  and (select cantidad from stock_actual where ubicacion_id = :'veh' and producto_id = :'pa') = 0
  and (select cantidad from stock_actual where ubicacion_id = :'dep' and producto_id = :'pa') = 6;
set local role authenticated;

-- 4) No se puede cobrar más que el total; el preventista no puede.
do $$ begin perform venta_especial(gen_random_uuid(), now(), current_setting('e.cli')::uuid, 'deposito_alberdi',
  jsonb_build_array(jsonb_build_object('producto_id', current_setting('e.pa'), 'cantidad', 1, 'precio_unitario', 100)),
  jsonb_build_array(jsonb_build_object('medio', 'Efectivo', 'importe', 200))); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'El pago es más que el total%' then raise; end if; end $$;
select set_config('request.jwt.claim.sub', :'prev', true);
do $$ begin perform venta_especial(gen_random_uuid(), now(), null, 'deposito_alberdi',
  jsonb_build_array(jsonb_build_object('producto_id', current_setting('e.pa'), 'cantidad', 1, 'precio_unitario', 100)),
  '[]'); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Solo administración%' then raise; end if; end $$;
insert into r select 'limites', true;
reset role;

-- 5) Comisión: 0 en ventas del administrador; la del preventista sigue igual.
select gen_random_uuid() as pa_adm \gset
select gen_random_uuid() as pa_prev \gset
insert into pedidos(id, cliente_id, preventista_id, tipo_precio, estado, total, resultado_entrega, tipo_operacion, origen)
values (:'pa_adm', :'cli', :'adm', 'normal', 'pendiente', 1000, 'pendiente', 'pedido', 'interno'),
       (:'pa_prev', :'cli', :'prev', 'normal', 'pendiente', 1000, 'pendiente', 'pedido', 'interno');
insert into pedido_detalles(pedido_id, producto_id, cantidad, precio_unitario, subtotal, tipo_precio, porcentaje_comision, importe_comision)
values (:'pa_adm', :'pb', 1, 1000, 1000, 'normal', 10, 100), (:'pa_prev', :'pb', 1, 1000, 1000, 'normal', 10, 100);
insert into r select 'comision_admin', (select importe_comision from pedido_detalles where pedido_id = :'pa_adm') = 0
  and (select importe_comision from pedido_detalles where pedido_id = :'pa_prev') = 100;

select coalesce(string_agg(paso, ', ') filter (where not ok), '') as fallas,
  bool_and(ok) and count(*) = 8 as todo_ok from r \gset
\if :todo_ok \else \echo 'FALLA en:' :'fallas' \quit \endif
rollback;
\echo ESCENARIO_OK
