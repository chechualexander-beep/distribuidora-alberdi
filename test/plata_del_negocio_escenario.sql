-- Escenario: Plata del negocio (foto inicial, cobros, gastos, hogar, pase, gasto fijo mixto,
-- proveedor a plazo, comisión pagada, devolución, arqueo, anulación). Todo se deshace.
\set ON_ERROR_STOP 1
begin;
select u.id as adm from usuarios u where u.rol='administrador' and u.activo order by u.id limit 1 \gset
select u.id as prev, c.id as cli from usuarios u join clientes c on c.preventista_id=u.id and c.activo
  where u.rol='preventista' and u.activo order by c.nombre_comercio limit 1 \gset
select id as ped from pedidos order by created_at limit 1 \gset
-- Partir de cero (en TESTING puede haber una foto inicial de pruebas a mano).
set session_replication_role = replica;
delete from fin_arqueos; delete from fin_movimientos; delete from fin_deudas; delete from fin_gastos_fijos;
update fin_config set inicio = null where id;
-- Lo que se probó a mano en TESTING en los últimos días (cobros, devoluciones, comisiones) se corre
-- lejos, para que no se mezcle con las cuentas de abajo.
update cobros_cliente set fecha_pago = fecha_pago - interval '400 days' where fecha_pago > now() - interval '3 days';
update movimientos_credito_cliente set fecha = fecha - interval '400 days' where fecha > now() - interval '3 days';
update liquidaciones set fecha_pago = fecha_pago - interval '400 days' where fecha_pago > now() - interval '3 days';
-- Un cobro de antes de la foto (no cuenta) y dos de después.
insert into cobros_cliente(cliente_id, importe, medio_pago, fecha_pago) values
 (:'cli', 777, 'Efectivo', now() - interval '3 hours'),
 (:'cli', 20000, 'Efectivo', now() - interval '1 hour'),
 (:'cli', 5000, 'Transferencia', now() - interval '1 hour');
insert into liquidaciones(preventista_id, fecha_desde, fecha_hasta, comision_total, estado, fecha_pago)
 values (:'prev', current_date - 7, current_date, 2500, 'pagada', now() - interval '30 minutes');
insert into movimientos_credito_cliente(pedido_origen_id, importe, fecha, usuario_id, medio_pago)
 values (:'ped', 1000, now() - interval '20 minutes', :'adm', 'Efectivo');
set session_replication_role = origin;
select extract(day from fin_hoy())::int as dia, fin_vencimiento(extract(day from fin_hoy())::int, fin_hoy()) as per,
  fin_hoy() as hoy \gset
select set_config('e.per', :'per', true);
create temp table r(paso text, ok boolean) on commit drop;
grant all on r to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', :'adm', true);

-- 1) Sin foto inicial no se puede anotar nada.
do $$ begin perform fin_movimiento(gen_random_uuid(), now(), 'gasto', 'efectivo', 100); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Primero hacé la foto inicial%' then raise; end if; end $$;

-- 2) Foto inicial (repetirla con el mismo id devuelve lo mismo).
select gen_random_uuid() as foto \gset
select now() - interval '2 hours' as hfoto \gset
select fin_foto_inicial(:'foto', :'hfoto', 100000, 50000) is not null as f1 \gset
select (fin_foto_inicial(:'foto', :'hfoto', 100000, 50000)->>'repetida')::boolean as f2 \gset
insert into r select 'foto', :'f2';

-- 3) Gasto, plata para la casa y pase de la billetera al efectivo.
select gen_random_uuid() as g1 \gset
select fin_movimiento(:'g1', now(), 'gasto', 'efectivo', 3000, 'Combustible') is not null as m1 \gset
select fin_movimiento(gen_random_uuid(), now(), 'hogar', 'efectivo', 10000) is not null as m2 \gset
select fin_movimiento(gen_random_uuid(), now(), 'pase', 'billetera', 20000, null, null, 'efectivo') is not null as m3 \gset

-- 4) Gasto fijo mixto (tarjeta): 9000, 4000 para la casa. Dos veces el mismo mes: no.
select gen_random_uuid() as gf \gset
select set_config('e.gf', :'gf', true);
select fin_gasto_fijo_guardar(:'gf', 'Tarjeta de crédito', 9000, :dia, 'mixto') is not null as gf1 \gset
do $$ begin perform fin_pagar_gasto_fijo(gen_random_uuid(), now(), current_setting('e.gf')::uuid,
  current_setting('e.per')::date, 'billetera', 9000); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Indicá cuánto fue para la casa%' then raise; end if; end $$;
select fin_pagar_gasto_fijo(gen_random_uuid(), now(), :'gf', :'per', 'billetera', 9000, 4000) is not null as p1 \gset
do $$ begin perform fin_pagar_gasto_fijo(gen_random_uuid(), now(), current_setting('e.gf')::uuid,
  current_setting('e.per')::date, 'billetera', 9000, 0); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Ese gasto fijo ya está pagado%' then raise; end if; end $$;

-- 5) Proveedor a 15 días: 30000; se pagan 10000; no se puede pagar de más.
select gen_random_uuid() as deu \gset
select set_config('e.deu', :'deu', true);
select fin_deuda(:'deu', now(), 'Distribuidora Norte', 30000, current_date + 15) is not null as d1 \gset
select (fin_pagar_deuda(gen_random_uuid(), now(), :'deu', 'efectivo', 10000)->>'resta')::numeric as resta \gset
do $$ begin perform fin_pagar_deuda(gen_random_uuid(), now(), current_setting('e.deu')::uuid, 'efectivo', 25000);
  raise exception 'debió fallar';
exception when others then if sqlerrm not like 'El pago tiene que ser mayor que 0 y no más%' then raise; end if; end $$;
insert into r select 'deuda', :resta = 20000;

-- 6) Estado: efectivo = 100000 + 20000 − 3000 − 10000 + 20000 − 10000 − 2500 (comisión) − 1000 (devolución)
--    = 113500; billetera = 50000 + 5000 − 20000 − 9000 = 26000.
select fin_estado() as e1 \gset
insert into r select 'saldos',
  (select (x->>'saldo')::numeric from jsonb_array_elements(:'e1'::jsonb->'cuentas') x where x->>'codigo'='efectivo') = 113500
  and (select (x->>'saldo')::numeric from jsonb_array_elements(:'e1'::jsonb->'cuentas') x where x->>'codigo'='billetera') = 26000
  and (:'e1'::jsonb->>'plata')::numeric = 139500 and (:'e1'::jsonb->>'deben')::numeric = 20000;
insert into r select 'disponible', (:'e1'::jsonb->>'disponible')::numeric
  = 139500 - (:'e1'::jsonb->>'sobre')::numeric - 20000;
insert into r select 'mes', (:'e1'::jsonb->'mes'->>'hogar')::numeric = 14000
  and (:'e1'::jsonb->'mes'->>'gastos_negocio')::numeric = 8000
  and (:'e1'::jsonb->'mes'->>'comisiones')::numeric = 2500
  and (:'e1'::jsonb->'mes'->>'cobros')::numeric = 25000
  and (:'e1'::jsonb->'mes'->>'devoluciones')::numeric = 1000;
insert into r select 'sobre', exists(select 1 from jsonb_array_elements(:'e1'::jsonb->'gastos_fijos') x
  where (x->>'pagado_mes')::boolean and (x->>'vence')::date > :'hoy'::date and (x->>'por_semana')::numeric > 0);

-- 7) Arqueo: hay 113000 en efectivo → faltan 500; después el sistema dice 113000.
select fin_arqueo(gen_random_uuid(), now(), 'efectivo', 113000) as a1 \gset
-- 8) Anular el combustible: vuelven 3000.
select fin_anular(:'g1') is not null as an \gset
select fin_estado() as e2 \gset
insert into r select 'arqueo_y_anular', (:'a1'::jsonb->>'diferencia')::numeric = -500
  and (select (x->>'saldo')::numeric from jsonb_array_elements(:'e2'::jsonb->'cuentas') x where x->>'codigo'='efectivo') = 116000;

-- 9) Fechas: no antes de la foto; el preventista no ve nada.
do $$ begin perform fin_movimiento(gen_random_uuid(), now() - interval '5 hours', 'gasto', 'efectivo', 100);
  raise exception 'debió fallar';
exception when others then if sqlerrm not like 'La fecha es anterior a la foto inicial%' then raise; end if; end $$;
select set_config('request.jwt.claim.sub', :'prev', true);
do $$ begin perform fin_estado(); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Solo administración%' then raise; end if; end $$;
insert into r select 'permisos', true;

reset role;
select coalesce(string_agg(paso, ', ') filter (where not ok), '') as fallas,
  bool_and(ok) and count(*) = 8 as todo_ok from r \gset
\if :todo_ok \else \echo 'FALLA en:' :'fallas' \quit \endif
rollback;
\echo ESCENARIO_OK
