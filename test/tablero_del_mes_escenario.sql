-- Escenario: tablero del mes (resultado con gastos y hogar, capital y fotos del capital). Se deshace.
\set ON_ERROR_STOP 1
begin;
select u.id as adm from usuarios u where u.rol='administrador' and u.activo order by u.id limit 1 \gset
select u.id as prev from usuarios u where u.rol='preventista' and u.activo order by u.id limit 1 \gset
set session_replication_role = replica;
delete from fin_capital_fotos; delete from fin_arqueos; delete from fin_movimientos; delete from fin_deudas;
delete from fin_gastos_fijos; update fin_config set inicio = null where id;
-- Una foto del capital del mes pasado, para comparar.
insert into fin_capital_fotos(fecha, plata, mercaderia, clientes, a_favor, proveedores, total)
 values (date_trunc('month', fin_hoy())::date - 3, 1000, 0, 0, 0, 0, 1000);
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', :'adm', true);
select fin_hoy() as hoy \gset
create temp table r(paso text, ok boolean) on commit drop;
grant all on r to authenticated;
set local role authenticated;

-- Antes de la foto inicial: el tablero muestra lo comercial; gastos y casa en 0 (parcial).
select fin_tablero(:'hoy') as t0 \gset
insert into r select 'sin_plata', (:'t0'::jsonb->>'plata_parcial')::boolean
  and (:'t0'::jsonb->>'gastos_negocio')::numeric = 0
  and (:'t0'::jsonb->>'quedo')::numeric = (:'t0'::jsonb->>'ganancia_comercial')::numeric;

-- Foto inicial, un gasto de 30000 y 50000 para la casa.
select fin_foto_inicial(gen_random_uuid(), now() - interval '1 hour', 200000, 0) is not null as f \gset
select fin_movimiento(gen_random_uuid(), now(), 'gasto', 'efectivo', 30000, 'Combustible') is not null as g \gset
select fin_movimiento(gen_random_uuid(), now(), 'hogar', 'efectivo', 50000) is not null as h \gset
select fin_tablero(:'hoy') as t1 \gset
insert into r select 'resultado', (:'t1'::jsonb->>'gastos_negocio')::numeric = 30000
  and (:'t1'::jsonb->>'hogar')::numeric = 50000
  and (:'t1'::jsonb->>'ganancia_negocio')::numeric = (:'t1'::jsonb->>'ganancia_comercial')::numeric - 30000
  and (:'t1'::jsonb->>'quedo')::numeric = (:'t1'::jsonb->>'ganancia_comercial')::numeric - 80000
  and (:'t1'::jsonb->>'actual')::boolean
  and (:'t1'::jsonb->>'ventas_12_meses')::numeric >= (:'t1'::jsonb->>'ventas')::numeric;
-- La cuenta cierra: ventas − costo − comisiones + notas = ganancia comercial.
insert into r select 'cierra', round((:'t1'::jsonb->>'ventas')::numeric - (:'t1'::jsonb->>'costo')::numeric
  - (:'t1'::jsonb->>'comisiones')::numeric + (:'t1'::jsonb->>'notas_credito')::numeric, 2)
  = round((:'t1'::jsonb->>'ganancia_comercial')::numeric, 2);
-- Equilibrio: (gastos + casa) / margen.
insert into r select 'equilibrio', (:'t1'::jsonb->>'margen') is null
  or abs((:'t1'::jsonb->>'ventas_necesarias')::numeric - 80000 / (:'t1'::jsonb->>'margen')::numeric) < 1;

-- Capital: la plata es 200000 − 30000 − 50000 + cobros de la última hora; la foto del mes pasado
-- queda como "inicio del mes".
insert into r select 'capital', (:'t1'::jsonb->'capital'->>'plata')::numeric
  = 120000 + coalesce((select sum(importe) from cobros_cliente where fecha_pago >= now() - interval '1 hour'), 0)
  and (:'t1'::jsonb->'capital_inicio'->>'total')::numeric = 1000;
select fin_guardar_capital() is not null as gc \gset
select fin_guardar_capital() is not null as gc2 \gset
reset role;
insert into r select 'foto_del_dia', (select count(*) from fin_capital_fotos where fecha = :'hoy'::date) = 1;
set local role authenticated;

-- Un mes pasado no tiene capital de hoy; el preventista no ve nada.
select fin_tablero((:'hoy'::date - interval '1 month')::date) as tp \gset
insert into r select 'mes_pasado', (:'tp'::jsonb->'capital') = 'null'::jsonb and not (:'tp'::jsonb->>'actual')::boolean;
select set_config('request.jwt.claim.sub', :'prev', true);
do $$ begin perform fin_tablero(current_date); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Solo administración%' then raise; end if; end $$;
insert into r select 'permisos', true;

reset role;
select coalesce(string_agg(paso, ', ') filter (where not ok), '') as fallas,
  bool_and(ok) and count(*) = 8 as todo_ok from r \gset
\if :todo_ok \else \echo 'FALLA en:' :'fallas' \quit \endif
rollback;
\echo ESCENARIO_OK
