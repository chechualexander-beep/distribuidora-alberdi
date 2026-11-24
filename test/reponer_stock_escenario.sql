-- Escenario: "Para reponer" (ritmo de venta, demora del proveedor, mínimo, no avisar, fraccionados, permisos).
-- Productos propios del escenario. Todo se deshace.
\set ON_ERROR_STOP 1
begin;
select u.id as adm from usuarios u where u.rol='administrador' and u.activo order by u.id limit 1 \gset
select u.id as prev, c.id as cli from usuarios u join clientes c on c.preventista_id = u.id
  where u.rol='preventista' and u.activo order by u.id limit 1 \gset
select u.id as ayu from usuarios u where u.rol='preventista' and u.activo and u.id <> :'prev' order by u.id limit 1 \gset
select id as dep from ubicaciones_stock where codigo = 'deposito_alberdi' \gset
set session_replication_role = replica;
update usuarios set puede_deposito = true where id = :'ayu';
update usuarios set puede_deposito = false where id = :'prev';
-- A: se acaba (5 en depósito, vende 28 en 14 días = 2 por día). B: sobra. C: cerrado de 10 sueltos (S).
insert into productos(id, nombre, costo, control_stock, se_compra_a_pedido, activo) values
 ('00000000-0000-4000-8000-00000000000a', 'ZZ Escenario A', 1000, true, false, true),
 ('00000000-0000-4000-8000-00000000000b', 'ZZ Escenario B', 500, true, false, true),
 ('00000000-0000-4000-8000-00000000000c', 'ZZ Escenario C cerrado', 9000, true, false, true);
insert into productos(id, nombre, costo, control_stock, se_compra_a_pedido, activo, fracciona_de, unidades_por_origen) values
 ('00000000-0000-4000-8000-00000000000d', 'ZZ Escenario S suelto', 900, true, false, true,
  '00000000-0000-4000-8000-00000000000c', 10);
insert into stock_actual(ubicacion_id, producto_id, cantidad) values
 (:'dep', '00000000-0000-4000-8000-00000000000a', 5), (:'dep', '00000000-0000-4000-8000-00000000000b', 100),
 (:'dep', '00000000-0000-4000-8000-00000000000c', 3), (:'dep', '00000000-0000-4000-8000-00000000000d', 2);
insert into pedidos(id, cliente_id, preventista_id, tipo_precio, estado, facturado, tipo_operacion, resultado_entrega,
  fecha_finalizacion, created_at)
 values ('00000000-0000-4000-8000-0000000000e1', :'cli', :'prev', 'normal', 'entregado', true, 'pedido', 'entregado',
  now() - interval '14 days', now() - interval '15 days');
insert into pedido_detalles(pedido_id, producto_id, cantidad, precio_unitario, subtotal, cantidad_entregada,
  cantidad_no_entregada, importe_comision, agregado_en_entrega) values
 ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-00000000000a', 28, 1500, 42000, 28, 0, 0, false),
 ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-00000000000b', 28, 800, 22400, 28, 0, 0, false),
 ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-00000000000d', 28, 1200, 33600, 28, 0, 0, false);
insert into stock_operaciones(id, tipo, ubicacion_id, proveedor, fecha_fisica, actor_id, request_hash, resultado)
 values ('00000000-0000-4000-8000-0000000000f1', 'compra', :'dep', 'Distribuidora  Norte', now() - interval '20 days',
  :'adm', 'x', '{}'::jsonb);
insert into stock_operacion_items(operacion_id, producto_id, cantidad, costo_unitario, controlado)
 values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000000a', 20, 1000, true);
set session_replication_role = origin;
create temp table r(paso text, ok boolean) on commit drop;
grant all on r to authenticated;
create temp view x as select * from stock_reponer(true) where nombre like 'ZZ Escenario%';
grant select on x to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'adm', true);

-- 1) A: 2 por día, alcanza 2,5 días (< 1 + 2): comprar para 8 días = 16 − 5 = 11; proveedor de la última compra.
insert into r select 'a_comprar', exists(select 1 from x where nombre = 'ZZ Escenario A' and accion = 'comprar'
  and dias = 2.5 and comprar = 11 and proveedor = 'Distribuidora  Norte' and demora = 1 and costo_total = 11000
  and por_semana = 14);
insert into r select 'b_alcanza', exists(select 1 from x where nombre = 'ZZ Escenario B' and accion = 'alcanza')
  and not exists(select 1 from stock_reponer(false) where nombre = 'ZZ Escenario B');
-- 2) Demora de 2 días (el nombre se compara sin mayúsculas ni espacios de más): 2 × 9 − 5 = 13.
select stock_proveedor_demora('distribuidora norte', 2);
insert into r select 'demora', exists(select 1 from x where nombre = 'ZZ Escenario A' and demora = 2 and comprar = 13);
-- 3) Mínimo propio en B (150): avisa aunque alcance por ritmo.
select stock_reposicion_ajustar('00000000-0000-4000-8000-00000000000b', false, 150);
insert into r select 'minimo', exists(select 1 from stock_reponer(false) where nombre = 'ZZ Escenario B' and comprar = 200);
-- 4) No avisar A.
select stock_reposicion_ajustar('00000000-0000-4000-8000-00000000000a', true, null);
insert into r select 'no_avisar', not exists(select 1 from stock_reponer(false) where nombre = 'ZZ Escenario A');
-- 5) El suelto (2 libres, vende 2 por día) se acaba pero hay 3 cerrados: abrir 2 (14 − 2 = 12 sueltos → 2 cerrados).
insert into r select 'abrir', exists(select 1 from x where nombre = 'ZZ Escenario S suelto' and accion = 'abrir'
  and abrir = 2 and origen = 'ZZ Escenario C cerrado' and comprar is null);
-- 6) Ayuda en el depósito: ve la lista sin costos. Un preventista sin ese permiso, no.
select set_config('request.jwt.claim.sub', :'ayu', true);
insert into r select 'ayuda_sin_costo', exists(select 1 from stock_reponer(true) where nombre = 'ZZ Escenario B'
  and costo_total is null and comprar = 200);
do $$ begin perform stock_proveedor_demora('x', 1); raise exception 'debió fallar';
exception when others then if sqlerrm = 'debió fallar' then raise; end if; end $$;
select set_config('request.jwt.claim.sub', :'prev', true);
do $$ begin perform * from stock_reponer(false); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Solo administración o ayuda%' then raise; end if; end $$;
insert into r select 'permisos', true;

reset role;
select coalesce(string_agg(paso, ', ') filter (where ok is not true), '') as fallas,
  bool_and(ok) and count(*) = 8 as todo_ok from r \gset
\if :todo_ok \else \echo 'FALLA en:' :'fallas' \quit \endif
rollback;
\echo ESCENARIO_OK
