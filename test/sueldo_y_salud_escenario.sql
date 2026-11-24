-- Escenario: separar negocio / casa / personal, sueldo semanal, aporte del dueño, reclasificar y salud.
-- Todo se deshace.
\set ON_ERROR_STOP 1
begin;
select u.id as adm from usuarios u where u.rol='administrador' and u.activo order by u.id limit 1 \gset
select u.id as prev from usuarios u where u.rol='preventista' and u.activo order by u.id limit 1 \gset
-- Partir de cero (en TESTING puede haber plata de pruebas a mano).
set session_replication_role = replica;
delete from fin_arqueos; delete from fin_movimientos; delete from fin_deudas; delete from fin_gastos_fijos;
update fin_config set inicio = null, sueldo_semanal = null, sueldo_desde = null where id;
update cobros_cliente set fecha_pago = fecha_pago - interval '400 days' where fecha_pago > now() - interval '3 days';
update movimientos_credito_cliente set fecha = fecha - interval '400 days' where fecha > now() - interval '3 days';
update liquidaciones set fecha_pago = fecha_pago - interval '400 days' where fecha_pago > now() - interval '3 days';
set session_replication_role = origin;
create temp table r(paso text, ok boolean) on commit drop;
grant all on r to authenticated;
select now() - interval '1 minute' as ya \gset

set local role authenticated;
select set_config('request.jwt.claim.sub', :'adm', true);
select fin_foto_inicial(gen_random_uuid(), now() - interval '2 hours', 200000, 0) is not null as f \gset

-- 1) Negocio, casa, personal y uno "hogar" de la versión anterior (sin categoría → Casa).
select gen_random_uuid() as g1 \gset
select fin_movimiento(:'g1', :'ya', 'gasto', 'efectivo', 3000, 'Combustible') is not null as m \gset
select fin_movimiento(gen_random_uuid(), :'ya', 'hogar', 'efectivo', 10000, 'Casa') is not null as m \gset
select gen_random_uuid() as p1 \gset
select fin_movimiento(:'p1', :'ya', 'hogar', 'efectivo', 2000, 'Personal', 'Cumpleaños') is not null as m \gset
select fin_movimiento(gen_random_uuid(), :'ya', 'hogar', 'efectivo', 1000) is not null as m \gset
insert into r select 'casa_por_defecto', exists(select 1 from jsonb_array_elements(fin_estado()->'ultimos') x
  where (x->>'importe')::numeric = -1000 and x->>'categoria' = 'Casa');
do $$ begin perform fin_movimiento(gen_random_uuid(), now(), 'hogar', 'efectivo', 100, 'Sueldo');
  raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Elegí Casa o Personal%' then raise; end if; end $$;

-- 2) Sueldo: sin fijar no hay; fijado 50000 por semana; se paga una vez por semana (el sábado).
insert into r select 'sin_sueldo', fin_sueldo_estado()->'semanal' = 'null'::jsonb;
select fin_sueldo_guardar(50000) is not null as s \gset
select fin_sueldo_estado() as se \gset
select :'se'::jsonb->>'semana' as sem \gset
select set_config('e.sem', :'sem', true);
insert into r select 'sueldo_estado', (:'se'::jsonb->>'semanal')::numeric = 50000
  and extract(isodow from :'sem'::date) = 6 and (:'se'::jsonb->>'por_mes')::numeric = 216667
  and :'se'::jsonb->'pagado' = 'null'::jsonb;
select gen_random_uuid() as su \gset
select set_config('e.su', :'su', true);
select fin_pagar_sueldo(:'su', :'ya', :'sem', 'efectivo', 50000) is not null as ps \gset
do $$ begin perform fin_pagar_sueldo(gen_random_uuid(), now(), current_setting('e.sem')::date, 'efectivo', 50000);
  raise exception 'debió fallar';
exception when others then if sqlerrm not like 'El sueldo de esa semana ya está pagado%' then raise; end if; end $$;
do $$ begin perform fin_pagar_sueldo(gen_random_uuid(), now(), current_setting('e.sem')::date - 1, 'efectivo', 1);
  raise exception 'debió fallar';
exception when others then if sqlerrm not like 'La semana se indica con su sábado%' then raise; end if; end $$;
do $$ begin perform fin_pagar_sueldo(gen_random_uuid(), now(), current_setting('e.sem')::date + 14, 'efectivo', 1);
  raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Solo se puede adelantar%' then raise; end if; end $$;
insert into r select 'sueldo_pagado', (fin_sueldo_estado()->'ultimo'->>'importe')::numeric = 50000
  and (fin_sueldo_estado()->'ultimo'->>'semana')::date = :'sem'::date
  and not (fin_sueldo_estado()->>'pendiente')::boolean;

-- 3) Aporte del dueño: entra plata pero no es ingreso del negocio.
select fin_movimiento(gen_random_uuid(), :'ya', 'ingreso', 'efectivo', 5000, 'Aporte del dueño') is not null as a \gset

-- 4) Reclasificar: el combustible era personal; el "personal" del cumpleaños era del negocio (Otros).
select fin_reclasificar(:'g1', 'personal') is not null as rc \gset
select fin_reclasificar(:'p1', 'negocio', 'Otros') is not null as rc \gset
do $$ begin perform fin_reclasificar(current_setting('e.su')::uuid, 'casa');
  raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Solo se pueden pasar gastos y retiros%' then raise; end if; end $$;

-- 5) Mes: negocio 2000 (cumpleaños); retiros 10000 + 1000 casa, 3000 personal, 50000 sueldo; aporte 5000.
select fin_estado() as e \gset
insert into r select 'estado_mes', (:'e'::jsonb->'mes'->>'gastos_negocio')::numeric = 2000
  and (:'e'::jsonb->'mes'->>'casa')::numeric = 11000 and (:'e'::jsonb->'mes'->>'personal')::numeric = 3000
  and (:'e'::jsonb->'mes'->>'sueldo')::numeric = 50000 and (:'e'::jsonb->'mes'->>'hogar')::numeric = 64000
  and (:'e'::jsonb->'mes'->>'aportes')::numeric = 5000 and (:'e'::jsonb->'mes'->>'ingresos')::numeric = 0
  and (:'e'::jsonb->>'plata')::numeric = 200000 - 2000 - 64000 + 5000
  and (:'e'::jsonb->'sueldo'->>'semanal')::numeric = 50000;
select fin_tablero((now() at time zone 'America/Argentina/Buenos_Aires')::date) as t \gset
insert into r select 'tablero', (:'t'::jsonb->>'gastos_negocio')::numeric = 2000
  and (:'t'::jsonb->>'hogar')::numeric = 64000 and (:'t'::jsonb->>'sueldo')::numeric = 50000
  and (:'t'::jsonb->>'casa')::numeric = 11000 and (:'t'::jsonb->>'personal')::numeric = 3000
  and (:'t'::jsonb->>'aportes')::numeric = 5000
  and (:'t'::jsonb->'gastos_por_categoria'->>'Otros')::numeric = 2000
  and (:'t'::jsonb->>'quedo')::numeric = (:'t'::jsonb->>'ganancia_comercial')::numeric - 2000 - 64000;

-- 6) Salud: 3 meses, el último es el actual y se mide desde la foto inicial (no está completo).
select fin_salud(3) as h \gset
insert into r select 'salud', jsonb_array_length(:'h'::jsonb->'meses') = 3
  and (:'h'::jsonb->'meses'->2->>'actual')::boolean and not (:'h'::jsonb->'meses'->2->>'completo')::boolean
  and :'h'::jsonb->'meses'->0->'medido' = 'null'::jsonb
  and (:'h'::jsonb->'meses'->2->'medido'->>'gastos_negocio')::numeric = 2000
  and (:'h'::jsonb->'meses'->2->'medido'->>'retiros')::numeric = 64000
  and (:'h'::jsonb->'meses'->2->'medido'->>'dias')::integer = 1
  and (:'h'::jsonb->>'sueldo_semanal')::numeric = 50000;

-- 7) El preventista no puede nada de esto.
select set_config('request.jwt.claim.sub', :'prev', true);
do $$ begin perform fin_salud(3); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Solo administración%' then raise; end if; end $$;
do $$ begin perform fin_sueldo_guardar(1); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Solo administración%' then raise; end if; end $$;
insert into r select 'permisos', true;

reset role;
select coalesce(string_agg(paso, ', ') filter (where ok is not true), '') as fallas,
  bool_and(ok) and count(*) = 8 as todo_ok from r \gset
\if :todo_ok \else \echo 'FALLA en:' :'fallas' \quit \endif
rollback;
\echo ESCENARIO_OK
