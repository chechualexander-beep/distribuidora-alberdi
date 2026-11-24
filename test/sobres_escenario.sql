-- Escenario: sobres de verdad (frasco y reserva), gasto de la casa pagado con el sueldo, disponible. Se deshace.
\set ON_ERROR_STOP 1
begin;
select u.id as adm from usuarios u where u.rol='administrador' and u.activo order by u.id limit 1 \gset
select u.id as prev from usuarios u where u.rol='preventista' and u.activo order by u.id limit 1 \gset
set session_replication_role = replica;
delete from fin_gastos_casa_pagados; delete from fin_arqueos; delete from fin_movimientos; delete from fin_deudas;
delete from fin_gastos_fijos;
update fin_config set inicio = null, sueldo_semanal = null, sueldo_desde = null where id;
update cobros_cliente set fecha_pago = fecha_pago - interval '400 days' where fecha_pago > now() - interval '3 days';
update movimientos_credito_cliente set fecha = fecha - interval '400 days' where fecha > now() - interval '3 days';
update liquidaciones set fecha_pago = fecha_pago - interval '400 days' where fecha_pago > now() - interval '3 days';
set session_replication_role = origin;
create temp table r(paso text, ok boolean) on commit drop;
grant all on r to authenticated;
select now() - interval '1 minute' as ya, extract(day from (now() at time zone 'America/Argentina/Buenos_Aires'))::int as dia,
 (now() at time zone 'America/Argentina/Buenos_Aires')::date as hoy \gset
set local role authenticated;
select set_config('request.jwt.claim.sub', :'adm', true);
select fin_foto_inicial(gen_random_uuid(), now() - interval '2 minutes', 500000, 300000) is not null as f \gset

-- 1) Un gasto del negocio que vence hoy, en efectivo, y la luz de la casa (va con el sueldo).
select gen_random_uuid() as ga, gen_random_uuid() as gc \gset
select set_config('e.ga', :'ga', true), set_config('e.gc', :'gc', true), set_config('e.hoy', :'hoy', true);
select fin_gasto_fijo_guardar(:'ga', 'Alquiler depósito', 100000, :dia, 'negocio', true, 'efectivo') is not null as x \gset
select fin_gasto_fijo_guardar(:'gc', 'Luz', 165000, :dia, 'hogar') is not null as x \gset
select fin_estado() as e \gset
insert into r select 'sobre_vacio',
 (select (x->>'deberia')::numeric = 100000 and (x->>'faltan')::numeric = 100000 and (x->>'poner_sabado')::numeric = 100000
   from jsonb_array_elements(:'e'::jsonb->'sobres') x where x->>'codigo' = 'sobre_efectivo')
 and (select (x->>'deberia')::numeric = 0 from jsonb_array_elements(:'e'::jsonb->'sobres') x where x->>'codigo' = 'sobre_billetera')
 and (:'e'::jsonb->>'libre')::numeric = 800000 and (:'e'::jsonb->>'disponible')::numeric = 700000;

-- 2) Pongo 100000 en el frasco: el disponible no cambia y el sobre queda al día.
select fin_movimiento(gen_random_uuid(), :'ya', 'pase', 'efectivo', 100000, null, null, 'sobre_efectivo') is not null as x \gset
select fin_estado() as e \gset
insert into r select 'frasco_lleno',
 (select (x->>'saldo')::numeric = 100000 and (x->>'faltan')::numeric = 0 and (x->>'poner_sabado')::numeric = 0
   from jsonb_array_elements(:'e'::jsonb->'sobres') x where x->>'codigo' = 'sobre_efectivo')
 and (:'e'::jsonb->>'libre')::numeric = 700000 and (:'e'::jsonb->>'disponible')::numeric = 700000
 and (:'e'::jsonb->>'plata')::numeric = 800000;

-- 3) Pago el alquiler desde el frasco: queda vacío y el alquiler pasa al mes que viene.
select (x->>'periodo_mes')::date as per from jsonb_array_elements(:'e'::jsonb->'gastos_fijos') x where x->>'id' = :'ga' \gset
select fin_pagar_gasto_fijo(gen_random_uuid(), :'ya', :'ga', :'per', 'sobre_efectivo', 100000) is not null as x \gset
select fin_estado() as e \gset
insert into r select 'pagado_del_frasco',
 (select (x->>'saldo')::numeric = 0 from jsonb_array_elements(:'e'::jsonb->'sobres') x where x->>'codigo' = 'sobre_efectivo')
 and (select (x->>'pagado_mes')::boolean from jsonb_array_elements(:'e'::jsonb->'gastos_fijos') x where x->>'id' = :'ga')
 and (:'e'::jsonb->>'disponible')::numeric = 700000;

-- 4) La luz se marca pagada con el sueldo: no mueve plata; desmarcar la vuelve a pendiente.
select fin_gasto_casa_pagado(:'gc', :'per') is not null as x \gset
select fin_estado() as e \gset
insert into r select 'casa_con_sueldo',
 (select (x->>'pagado_mes')::boolean and (x->>'con_sueldo')::boolean
   from jsonb_array_elements(:'e'::jsonb->'gastos_fijos') x where x->>'id' = :'gc')
 and (:'e'::jsonb->>'plata')::numeric = 700000;
select fin_gasto_casa_pagado(:'gc', :'per', false) is not null as x \gset
insert into r select 'casa_desmarcada', not (select (x->>'pagado_mes')::boolean
  from jsonb_array_elements(fin_estado()->'gastos_fijos') x where x->>'id' = :'gc');
do $$ begin perform fin_gasto_casa_pagado(current_setting('e.ga')::uuid, current_setting('e.hoy')::date);
  raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Solo los gastos de la casa%' then raise; end if; end $$;
do $$ begin perform fin_gasto_fijo_guardar(gen_random_uuid(), 'X', 1, 1, 'negocio', true, 'tarjeta');
  raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Elegí efectivo o transferencia%' then raise; end if; end $$;

-- 5) Arqueo del frasco y estado del sábado.
select (fin_arqueo(gen_random_uuid(), :'ya', 'sobre_efectivo', 0)->>'diferencia')::numeric = 0 as arq \gset
insert into r select 'arqueo_frasco', :'arq'::boolean;
insert into r select 'sabado', (fin_sabado_estado()->>'iniciado')::boolean
 and jsonb_array_length(fin_sabado_estado()->'sobres') = 2;

-- 6) El preventista no puede.
select set_config('request.jwt.claim.sub', :'prev', true);
do $$ begin perform fin_sabado_estado(); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Solo administración%' then raise; end if; end $$;
insert into r select 'permisos', true;

reset role;
select coalesce(string_agg(paso, ', ') filter (where ok is not true), '') as fallas,
  bool_and(ok) and count(*) = 8 as todo_ok from r \gset
\if :todo_ok \else \echo 'FALLA en:' :'fallas' \quit \endif
rollback;
\echo ESCENARIO_OK
