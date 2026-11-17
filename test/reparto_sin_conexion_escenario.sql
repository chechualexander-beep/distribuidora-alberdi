-- Escenario: entregas y cobros hechos sin señal, con la hora real del teléfono (todo se deshace).
\set ON_ERROR_STOP 1
begin;
select u.id as adm from usuarios u where u.rol='administrador' and u.activo order by u.id limit 1 \gset
select u.id as prev, c.id as cli from usuarios u join clientes c on c.preventista_id=u.id and c.activo
  where u.rol='preventista' and u.activo order by c.nombre_comercio limit 1 \gset
select id as pa, precio_normal as qa from productos where activo and visible_preventistas and precio_normal>1 order by nombre limit 1 \gset
select id as veh from ubicaciones_stock where codigo='vehiculo' \gset
set session_replication_role = replica;
delete from stock_movimientos where producto_id=:'pa';
delete from stock_actual where producto_id=:'pa';
update productos set control_stock=false where id=:'pa';
update viajes_vehiculo set estado='cerrado', cerrado_at=clock_timestamp() where estado='abierto';
set session_replication_role = origin;
create temp table r(paso text, ok boolean) on commit drop;
grant all on r to authenticated;
select set_config('e.cli', :'cli', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', :'adm', true);
select stock_contar(gen_random_uuid(), 'vehiculo', jsonb_build_array(jsonb_build_object('producto_id',:'pa','cantidad',10)),
  now() - interval '60 hours') is not null as c \gset

-- Dos ventas directas del preventista.
select set_config('request.jwt.claim.sub', :'prev', true);
select crear_pedido_sin_conexion(gen_random_uuid(), :'cli', 'normal', 'venta_directa', '', current_date,
  jsonb_build_array(jsonb_build_object('producto_id',:'pa','cantidad',2,'precio_unitario',:qa,'subtotal',2*:qa,'tipo_precio','normal')),
  now()) as v1 \gset
select crear_pedido_sin_conexion(gen_random_uuid(), :'cli', 'normal', 'venta_directa', '', current_date,
  jsonb_build_array(jsonb_build_object('producto_id',:'pa','cantidad',1,'precio_unitario',:qa,'subtotal',:qa,'tipo_precio','normal')),
  now()) as v2 \gset

-- 1) Entrega sin señal hace 2 días, cobrada completa: todo queda con esa fecha.
select set_config('request.jwt.claim.sub', :'adm', true);
select gen_random_uuid() as s1, now() - interval '2 days' as f1 \gset
select jsonb_agg(jsonb_build_object('detalle_id',id,'cantidad_entregada',cantidad)) as o1 from pedido_detalles where pedido_id=:'v1' \gset
select finalizar_gestion_sin_conexion(:'s1', :'v1', :'f1', 'pendiente', :'o1', '[]', 'completo', 'sin_senal',
  null, null, 'Efectivo') as x1 \gset
select finalizar_gestion_sin_conexion(:'s1', :'v1', :'f1', 'pendiente', :'o1', '[]', 'completo', 'sin_senal',
  null, null, 'Efectivo') as x1b \gset
insert into r select 'entrega', :'x1'::jsonb->>'resultado_entrega'='entregado' and :'x1'=:'x1b'
  and (select fecha_finalizacion from pedidos where id=:'v1') = :'f1'::timestamptz
  and (select count(*) from pedido_pagos where pedido_id=:'v1' and fecha_pago=:'f1'::timestamptz)=1
  and (select count(*) from cobros_cliente where fecha_pago=:'f1'::timestamptz and cliente_id=:'cli')=1
  and (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pa')=8;

-- 2) Más de 72 horas: rechazada (hay que cargarla de nuevo con señal).
do $$ begin perform finalizar_gestion_sin_conexion(gen_random_uuid(),
  (select id from pedidos where cliente_id=current_setting('e.cli')::uuid and resultado_entrega='pendiente'
   and tipo_operacion='venta_directa' order by created_at desc limit 1),
  now() - interval '80 hours', 'pendiente', '[]', '[]', 'sin_pago', 'sin_senal'); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'La operación tiene más de 72 horas%' then raise; end if; end $$;

-- 3) Entrega sin cobrar y después cobro del saldo sin señal (ayer).
select gen_random_uuid() as s2 \gset
select jsonb_agg(jsonb_build_object('detalle_id',id,'cantidad_entregada',cantidad)) as o2 from pedido_detalles where pedido_id=:'v2' \gset
select finalizar_gestion_sin_conexion(:'s2', :'v2', now() - interval '1 day', 'pendiente', :'o2', '[]', 'sin_pago', 'sin_senal') as x2 \gset
select saldo_pendiente as deuda from saldos_pendientes_pedidos where pedido_id=:'v2' \gset
select gen_random_uuid() as k1, now() - interval '20 hours' as f2 \gset
select registrar_cobro_sin_conexion(:'k1', :'cli', :deuda, 'efectivo', :'f2') as y1 \gset
select registrar_cobro_sin_conexion(:'k1', :'cli', :deuda, 'efectivo', :'f2') as y1b \gset
insert into r select 'cobro', :'y1'=:'y1b' and :deuda > 0
  and (select fecha_pago from cobros_cliente where id=(:'y1'::jsonb->>'cobro_id')::uuid) = :'f2'::timestamptz
  and (:'y1'::jsonb->>'fecha_pago')::timestamptz = :'f2'::timestamptz
  and (select saldo_pendiente from saldos_pendientes_pedidos where pedido_id=:'v2') = 0;
reset role;
select coalesce(string_agg(paso, ', ') filter (where not ok), '') as fallas,
  bool_and(ok) and count(*) = 2 as todo_ok from r \gset
\if :todo_ok \else \echo 'FALLA en:' :'fallas' \quit \endif
rollback;
\echo ESCENARIO_OK
