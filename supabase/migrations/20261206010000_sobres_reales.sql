-- Gestión del negocio, etapa 4: sobres de verdad. Solo administración.
-- * Dos cuentas nuevas: el frasco (efectivo apartado) y la reserva (apartada dentro de la billetera). Lo que hay
--   adentro cambia solo cuando se pone plata (pase) o se paga un gasto fijo desde ahí: ya no hay un "apartado"
--   teórico que cambia todos los días.
-- * Cada gasto fijo dice cómo se paga (efectivo o transferencia) y va al sobre que corresponde.
-- * Los gastos fijos de la casa se pagan con el sueldo: no van al sobre y se marcan "ya lo pagué" sin mover plata.
-- * El sábado: cuánto poner en cada sobre para cubrir hasta el sábado siguiente (número fijo toda la semana).
-- * Disponible para mercadería = plata libre (efectivo y billetera) − proveedores − lo que falta en los sobres.

alter table public.fin_cuentas drop constraint fin_cuentas_codigo_check;
alter table public.fin_cuentas add constraint fin_cuentas_codigo_check
 check (codigo in ('efectivo', 'billetera', 'sobre_efectivo', 'sobre_billetera'));
insert into public.fin_cuentas values ('sobre_efectivo', 'Frasco (efectivo)', 3), ('sobre_billetera', 'Reserva (billetera)', 4);

alter table public.fin_gastos_fijos add column medio text not null default 'billetera'
 check (medio in ('efectivo', 'billetera'));

-- Gastos de la casa pagados con el sueldo (no mueven plata del negocio).
create table public.fin_gastos_casa_pagados (
 gasto_fijo_id uuid not null references public.fin_gastos_fijos(id),
 periodo date not null,
 pagado_at timestamptz not null default now(),
 primary key (gasto_fijo_id, periodo)
);
alter table public.fin_gastos_casa_pagados enable row level security;
revoke all on public.fin_gastos_casa_pagados from anon, authenticated;

create or replace function public.fin_validar_cuenta(p_cuenta text) returns void
language plpgsql immutable set search_path = pg_catalog, public, pg_temp as $$
begin
 if p_cuenta is null or p_cuenta not in ('efectivo', 'billetera', 'sobre_efectivo', 'sobre_billetera') then
  raise exception 'Elegí efectivo, billetera o un sobre.' using errcode = 'PT422'; end if;
end $$;

create function public.fin_sobre_cuenta(p_medio text) returns text
language sql immutable set search_path = pg_catalog, public, pg_temp as $$
 select case when p_medio = 'efectivo' then 'sobre_efectivo' else 'sobre_billetera' end
$$;

drop function public.fin_gasto_fijo_guardar(uuid, text, numeric, integer, text, boolean);
create function public.fin_gasto_fijo_guardar(p_id uuid, p_nombre text, p_importe numeric, p_dia integer,
 p_ambito text, p_activo boolean default true, p_medio text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
 perform public.fin_exigir_admin();
 if length(btrim(coalesce(p_nombre, ''))) = 0 then
  raise exception 'Escribí el nombre del gasto.' using errcode = 'PT422'; end if;
 if coalesce(p_importe, 0) <= 0 then
  raise exception 'El importe tiene que ser mayor que 0.' using errcode = 'PT422'; end if;
 if coalesce(p_dia, 0) not between 1 and 31 then
  raise exception 'El día de pago va del 1 al 31.' using errcode = 'PT422'; end if;
 if p_ambito not in ('negocio', 'hogar', 'mixto') then
  raise exception 'Elegí negocio, hogar o mixto.' using errcode = 'PT422'; end if;
 if p_medio is not null and p_medio not in ('efectivo', 'billetera') then
  raise exception 'Elegí efectivo o transferencia.' using errcode = 'PT422'; end if;
 insert into public.fin_gastos_fijos(id, nombre, importe, dia_pago, ambito, activo, medio)
 values (p_id, btrim(p_nombre), p_importe, p_dia, p_ambito, coalesce(p_activo, true), coalesce(p_medio, 'billetera'))
 on conflict (id) do update set nombre = excluded.nombre, importe = excluded.importe,
  dia_pago = excluded.dia_pago, ambito = excluded.ambito, activo = excluded.activo,
  medio = coalesce(p_medio, public.fin_gastos_fijos.medio);
 return jsonb_build_object('id', p_id);
end $$;

-- Gasto de la casa: marcar (o desmarcar) que ese mes ya se pagó con el sueldo.
create function public.fin_gasto_casa_pagado(p_gasto_fijo_id uuid, p_periodo date, p_pagado boolean default true)
returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
 perform public.fin_exigir_admin();
 if not exists (select 1 from public.fin_gastos_fijos g where g.id = p_gasto_fijo_id and g.ambito = 'hogar') then
  raise exception 'Solo los gastos de la casa se marcan como pagados con el sueldo.' using errcode = 'PT409'; end if;
 if coalesce(p_pagado, true) then
  insert into public.fin_gastos_casa_pagados(gasto_fijo_id, periodo) values (p_gasto_fijo_id, p_periodo)
  on conflict do nothing;
 else
  delete from public.fin_gastos_casa_pagados where gasto_fijo_id = p_gasto_fijo_id and periodo = p_periodo;
 end if;
 return jsonb_build_object('id', p_gasto_fijo_id, 'pagado', coalesce(p_pagado, true));
end $$;

-- Gasto fijo: próximo vencimiento sin pagar, lo que debería estar apartado hoy y cómo se paga.
create or replace function public.fin_sobre_de(gf public.fin_gastos_fijos, p_hoy date, p_inicio date) returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare mes date := date_trunc('month', p_hoy)::date; este date; vence date; anterior date;
 pagado_este boolean; dias integer; frac numeric;
begin
 este := public.fin_vencimiento(gf.dia_pago, mes);
 pagado_este := exists (select 1 from public.fin_movimientos m where m.gasto_fijo_id = gf.id and m.periodo = este
   and m.tipo = 'gasto_fijo' and m.anulado_at is null)
  or exists (select 1 from public.fin_gastos_casa_pagados c where c.gasto_fijo_id = gf.id and c.periodo = este);
 if not pagado_este and este >= coalesce(p_inicio, p_hoy) then vence := este;
 else vence := public.fin_vencimiento(gf.dia_pago, (mes + interval '1 month')::date); end if;
 anterior := public.fin_vencimiento(gf.dia_pago, (date_trunc('month', vence) - interval '1 month')::date);
 dias := greatest(vence - anterior, 1);
 frac := case when p_hoy >= vence then 1 else least(1, greatest(0, (p_hoy - anterior)::numeric / dias)) end;
 return jsonb_build_object('id', gf.id, 'nombre', gf.nombre, 'importe', gf.importe, 'dia_pago', gf.dia_pago,
  'ambito', gf.ambito, 'activo', gf.activo, 'medio', gf.medio, 'con_sueldo', gf.ambito = 'hogar',
  'vence', vence, 'vencido', p_hoy > vence, 'anterior', anterior,
  'reservado', case when gf.activo then round(gf.importe * frac) else 0 end,
  'por_semana', round(gf.importe * 7 / dias),
  'pagado_mes', pagado_este, 'periodo_mes', este);
end $$;

-- Los dos sobres: lo que hay, lo que debería haber hoy, lo que falta y lo que hay que poner el sábado para cubrir
-- hasta el sábado siguiente (todo lo que vence hasta ahí, entero; lo demás, la parte proporcional).
create function public.fin_sobres(p_hoy date, p_inicio date) returns jsonb
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
 with g as (
  select x.medio, (public.fin_sobre_de(x, p_hoy, p_inicio)) s, x.importe
  from public.fin_gastos_fijos x where x.activo and x.ambito <> 'hogar'
 ), h as (
  select g.medio, (g.s->>'reservado')::numeric reservado, g.s->'nombre' nombre,
   round(g.importe * least(1, greatest(0, ((public.fin_sabado_de(p_hoy) + 7) - (g.s->>'anterior')::date)::numeric
    / greatest((g.s->>'vence')::date - (g.s->>'anterior')::date, 1)))) objetivo
  from g
 ), saldos as (
  select x.cuenta, sum(x.importe) saldo from public.fin_flujo('-infinity', 'infinity') x
  where x.cuenta in ('sobre_efectivo', 'sobre_billetera') group by x.cuenta
 ), m as (select unnest(array['efectivo', 'billetera']) medio)
 select coalesce(jsonb_agg(jsonb_build_object(
   'codigo', public.fin_sobre_cuenta(m.medio), 'medio', m.medio,
   'nombre', case m.medio when 'efectivo' then 'Frasco (efectivo)' else 'Reserva (billetera)' end,
   'saldo', coalesce(s.saldo, 0),
   'deberia', coalesce((select sum(h.reservado) from h where h.medio = m.medio), 0),
   'faltan', greatest(0, coalesce((select sum(h.reservado) from h where h.medio = m.medio), 0) - coalesce(s.saldo, 0)),
   'objetivo_sabado', coalesce((select sum(h.objetivo) from h where h.medio = m.medio), 0),
   'poner_sabado', ceil(greatest(0, coalesce((select sum(h.objetivo) from h where h.medio = m.medio), 0)
     - coalesce(s.saldo, 0)) / 1000) * 1000,
   'sabado', public.fin_sabado_de(p_hoy)) order by m.medio desc), '[]'::jsonb)
 from m left join saldos s on s.cuenta = public.fin_sobre_cuenta(m.medio)
$$;

-- Lo del sábado (para "Hoy"): lo que hay que poner en los sobres y el sueldo.
create function public.fin_sabado_estado() returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare inicio timestamptz; hoy date := public.fin_hoy(); sobres jsonb;
begin
 perform public.fin_exigir_admin();
 select c.inicio into inicio from public.fin_config c;
 if inicio is null then return jsonb_build_object('iniciado', false); end if;
 sobres := public.fin_sobres(hoy, inicio::date);
 return jsonb_build_object('iniciado', true, 'fin_de_semana', extract(isodow from hoy) in (6, 7),
  'poner', (select coalesce(sum((x->>'poner_sabado')::numeric), 0) from jsonb_array_elements(sobres) x),
  'sobres', sobres, 'sueldo', public.fin_sueldo_estado());
end $$;

-- Todo lo de "Plata del negocio" en una consulta (por GET: queda en la copia sin señal).
create or replace function public.fin_estado() returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare inicio timestamptz; hoy date := public.fin_hoy(); mes_desde timestamptz; cuentas jsonb; gastos jsonb;
 deudas jsonb; plata numeric; libre numeric; sobre numeric; deben numeric; mes jsonb; ultimos jsonb; sobres jsonb;
 faltan numeric;
begin
 perform public.fin_exigir_admin();
 select c.inicio into inicio from public.fin_config c;
 mes_desde := date_trunc('month', hoy)::timestamp at time zone 'America/Argentina/Buenos_Aires';
 select coalesce(jsonb_agg(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre,
   'saldo', coalesce((select sum(x.importe) from public.fin_flujo('-infinity', 'infinity') x where x.cuenta = c.codigo), 0))
   order by c.orden), '[]')
 into cuentas from public.fin_cuentas c;
 select coalesce(sum((x->>'saldo')::numeric), 0),
  coalesce(sum((x->>'saldo')::numeric) filter (where x->>'codigo' in ('efectivo', 'billetera')), 0)
 into plata, libre from jsonb_array_elements(cuentas) x;
 select coalesce(jsonb_agg(public.fin_sobre_de(g, hoy, inicio::date) order by g.activo desc, g.dia_pago, g.nombre), '[]')
 into gastos from public.fin_gastos_fijos g;
 sobres := public.fin_sobres(hoy, inicio::date);
 select coalesce(sum((x->>'deberia')::numeric), 0), coalesce(sum((x->>'faltan')::numeric), 0)
 into sobre, faltan from jsonb_array_elements(sobres) x;
 select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'proveedor', d.proveedor, 'importe', d.importe,
   'resta', d.resta, 'vence', d.vence, 'descripcion', d.descripcion, 'vencida', d.vence < hoy) order by d.vence), '[]'),
  coalesce(sum(d.resta), 0)
 into deudas, deben
 from (select d.*, d.importe + coalesce((select sum(m.importe) from public.fin_movimientos m
   where m.deuda_id = d.id and m.anulado_at is null), 0) resta
  from public.fin_deudas d where d.anulado_at is null) d
 where d.resta > 0;
 select jsonb_build_object(
   'cobros', coalesce(sum(x.importe) filter (where x.tipo = 'cobro'), 0),
   'ingresos', coalesce(sum(x.importe) filter (where x.tipo = 'ingreso' and x.categoria is distinct from 'Aporte del dueño'), 0),
   'compras', coalesce(-sum(x.importe) filter (where x.tipo in ('compra', 'pago_proveedor')), 0),
   'comisiones', coalesce(-sum(x.importe) filter (where x.tipo = 'comision'), 0),
   'devoluciones', coalesce(-sum(x.importe) filter (where x.tipo = 'devolucion'), 0),
   'hogar', coalesce(sum(x.parte_hogar), 0),
   'ajustes', coalesce(sum(x.importe) filter (where x.tipo = 'ajuste'), 0))
  || (public.fin_totales(mes_desde, 'infinity') - 'gastos_por_categoria')
 into mes from public.fin_flujo(mes_desde, 'infinity') x;
 select coalesce(jsonb_agg(to_jsonb(u) order by u.fecha desc), '[]') into ultimos
 from (select * from public.fin_flujo('-infinity', 'infinity') order by fecha desc limit 40) u;
 return jsonb_build_object('inicio', inicio, 'hoy', hoy, 'cuentas', cuentas, 'plata', plata, 'libre', libre,
  'gastos_fijos', gastos, 'sobre', sobre, 'sobres', sobres, 'faltan_sobres', faltan, 'deudas', deudas, 'deben', deben,
  'disponible', libre - deben - faltan, 'mes', mes, 'ultimos', ultimos,
  'sueldo', case when inicio is null then null else public.fin_sueldo_estado() end, 'consultado_at', now());
end $$;

revoke all on function public.fin_sobre_cuenta(text), public.fin_sobres(date, date) from public, anon, authenticated;
revoke all on function public.fin_gasto_fijo_guardar(uuid, text, numeric, integer, text, boolean, text),
 public.fin_gasto_casa_pagado(uuid, date, boolean), public.fin_sabado_estado() from public, anon;
grant execute on function public.fin_gasto_fijo_guardar(uuid, text, numeric, integer, text, boolean, text),
 public.fin_gasto_casa_pagado(uuid, date, boolean), public.fin_sabado_estado() to authenticated;
