-- Gestión del negocio, etapa 3: separar lo del negocio de lo de afuera, sueldo fijo y salud del negocio.
-- Solo administración.
-- * Las salidas que no son del negocio (tipo 'hogar') llevan categoría: 'Casa', 'Personal' o 'Sueldo'
--   (las viejas 'Hogar' cuentan como Casa). Ninguna baja la ganancia del negocio: son retiros.
-- * Sueldo fijo semanal: importe en fin_config; se paga una vez por semana (sábado) con fin_pagar_sueldo.
-- * Aporte del dueño: un ingreso con categoría 'Aporte del dueño' (plata de afuera que entra al negocio).
-- * Reclasificar: pasar un gasto ya anotado de negocio a casa/personal o al revés, sin anularlo.
-- * fin_salud: los últimos meses, midiendo la ganancia solo desde que hay gastos anotados (foto inicial).

alter table public.fin_config
 add column sueldo_semanal numeric(14,2) check (sueldo_semanal is null or sueldo_semanal > 0),
 add column sueldo_desde date;

alter table public.fin_movimientos
 add column reclasificado_at timestamptz,
 add column reclasificado_por uuid references public.usuarios(id);

-- Un sueldo por semana (periodo = el sábado de esa semana).
create unique index fin_sueldo_una_vez on public.fin_movimientos(periodo)
 where tipo = 'hogar' and categoria = 'Sueldo' and anulado_at is null;

-- Sábado de la semana de lunes a sábado que contiene p_dia (el domingo cuenta en la semana anterior).
create function public.fin_sabado_de(p_dia date) returns date
language sql immutable set search_path = pg_catalog, public, pg_temp as $$
 select case when extract(isodow from p_dia) = 7 then p_dia - 1
  else p_dia + (6 - extract(isodow from p_dia)::integer) end
$$;

-- Gasto del negocio, retiro (casa o personal), compra pagada, ingreso extra o pase entre cuentas.
create or replace function public.fin_movimiento(p_id uuid, p_fecha timestamptz, p_tipo text, p_cuenta text,
 p_importe numeric, p_categoria text default null, p_descripcion text default null, p_cuenta_destino text default null)
returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare huella text; previo text; f timestamptz; signo numeric; hogar numeric := 0; cat text;
begin
 perform public.fin_exigir_admin();
 huella := public.fin_huella(jsonb_build_object('f', p_fecha, 't', p_tipo, 'c', p_cuenta, 'i', p_importe,
  'g', p_categoria, 'd', p_descripcion, 'x', p_cuenta_destino));
 select m.request_hash into previo from public.fin_movimientos m where m.id = p_id;
 if previo is not null then return public.fin_previo(previo, huella, p_id); end if;
 f := public.fin_validar_fecha(p_fecha);
 perform public.fin_validar_cuenta(p_cuenta);
 if p_tipo not in ('gasto', 'hogar', 'compra', 'ingreso', 'pase') then
  raise exception 'Tipo de movimiento inválido.' using errcode = 'PT422'; end if;
 if coalesce(p_importe, 0) <= 0 then
  raise exception 'El importe tiene que ser mayor que 0.' using errcode = 'PT422'; end if;
 if p_tipo = 'pase' then
  perform public.fin_validar_cuenta(p_cuenta_destino);
  if p_cuenta_destino = p_cuenta then
   raise exception 'Elegí cuentas distintas.' using errcode = 'PT422'; end if;
 end if;
 cat := nullif(btrim(p_categoria), '');
 if p_tipo = 'hogar' then
  -- 'Hogar' llega de teléfonos con la versión anterior: es lo mismo que Casa.
  cat := case when cat is null or cat = 'Hogar' then 'Casa' else cat end;
  if cat not in ('Casa', 'Personal') then
   raise exception 'Elegí Casa o Personal (el sueldo se paga desde "Mi sueldo").' using errcode = 'PT422'; end if;
  hogar := p_importe;
 end if;
 signo := case when p_tipo = 'ingreso' then 1 else -1 end;
 insert into public.fin_movimientos(id, fecha, tipo, cuenta, cuenta_destino, importe, parte_hogar, categoria,
  descripcion, actor_id, request_hash)
 values (p_id, f, p_tipo, p_cuenta, case when p_tipo = 'pase' then p_cuenta_destino end, signo * p_importe, hogar,
  coalesce(cat, case p_tipo when 'gasto' then 'Otros' when 'compra' then 'Mercadería'
   when 'pase' then 'Pase entre cuentas' else 'Ingreso' end),
  nullif(btrim(p_descripcion), ''), auth.uid(), huella);
 return jsonb_build_object('id', p_id);
end $$;

-- Fijar (o quitar, con null) el sueldo semanal.
create function public.fin_sueldo_guardar(p_importe numeric) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
 perform public.fin_exigir_admin();
 if p_importe is not null and p_importe <= 0 then
  raise exception 'El sueldo tiene que ser mayor que 0 (o dejalo vacío para quitarlo).' using errcode = 'PT422'; end if;
 update public.fin_config set sueldo_semanal = round(p_importe, 2),
  sueldo_desde = case when p_importe is null then null else coalesce(sueldo_desde, public.fin_hoy()) end
 where id;
 return jsonb_build_object('semanal', p_importe);
end $$;

-- Pagarse el sueldo de una semana (p_semana: el sábado). Se puede pagar otro importe esa vez.
create function public.fin_pagar_sueldo(p_id uuid, p_fecha timestamptz, p_semana date, p_cuenta text,
 p_importe numeric) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare huella text; previo text; f timestamptz;
begin
 perform public.fin_exigir_admin();
 huella := public.fin_huella(jsonb_build_object('f', p_fecha, 's', p_semana, 'c', p_cuenta, 'i', p_importe));
 select m.request_hash into previo from public.fin_movimientos m where m.id = p_id;
 if previo is not null then return public.fin_previo(previo, huella, p_id); end if;
 f := public.fin_validar_fecha(p_fecha);
 perform public.fin_validar_cuenta(p_cuenta);
 if p_semana is null or extract(isodow from p_semana) <> 6 then
  raise exception 'La semana se indica con su sábado.' using errcode = 'PT422'; end if;
 if p_semana > public.fin_sabado_de(public.fin_hoy()) + 7 then
  raise exception 'Solo se puede adelantar el sueldo de la semana que viene.' using errcode = 'PT422'; end if;
 if coalesce(p_importe, 0) <= 0 then
  raise exception 'El importe tiene que ser mayor que 0.' using errcode = 'PT422'; end if;
 if exists (select 1 from public.fin_movimientos m where m.tipo = 'hogar' and m.categoria = 'Sueldo'
   and m.periodo = p_semana and m.anulado_at is null) then
  raise exception 'El sueldo de esa semana ya está pagado.' using errcode = 'PT409'; end if;
 insert into public.fin_movimientos(id, fecha, tipo, cuenta, importe, parte_hogar, categoria, descripcion, periodo,
  actor_id, request_hash)
 values (p_id, f, 'hogar', p_cuenta, -p_importe, p_importe, 'Sueldo',
  'Semana del sábado ' || to_char(p_semana, 'DD/MM'), p_semana, auth.uid(), huella);
 return jsonb_build_object('id', p_id, 'semana', p_semana);
end $$;

-- Pasar un gasto o retiro ya anotado a otro dueño: 'negocio' (con categoría de gasto), 'casa' o 'personal'.
create function public.fin_reclasificar(p_id uuid, p_de_quien text, p_categoria text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare m public.fin_movimientos; cat text := nullif(btrim(p_categoria), '');
begin
 perform public.fin_exigir_admin();
 select * into m from public.fin_movimientos where id = p_id for update;
 if not found or m.anulado_at is not null then
  raise exception 'Movimiento inexistente o anulado.' using errcode = 'PT404'; end if;
 if m.tipo not in ('gasto', 'hogar') or m.categoria = 'Sueldo' then
  raise exception 'Solo se pueden pasar gastos y retiros (el sueldo no).' using errcode = 'PT409'; end if;
 if p_de_quien = 'negocio' then
  if cat is null then raise exception 'Elegí en qué fue el gasto.' using errcode = 'PT422'; end if;
  update public.fin_movimientos set tipo = 'gasto', parte_hogar = 0, categoria = cat,
   reclasificado_at = now(), reclasificado_por = auth.uid() where id = p_id;
 elsif p_de_quien in ('casa', 'personal') then
  update public.fin_movimientos set tipo = 'hogar', parte_hogar = abs(importe),
   categoria = case p_de_quien when 'casa' then 'Casa' else 'Personal' end,
   reclasificado_at = now(), reclasificado_por = auth.uid() where id = p_id;
 else
  raise exception 'Elegí negocio, casa o personal.' using errcode = 'PT422';
 end if;
 return jsonb_build_object('id', p_id, 'de_quien', p_de_quien);
end $$;

-- Estado del sueldo hoy: la semana a pagar (la pendiente o la próxima) y si ya está pagada.
create function public.fin_sueldo_estado() returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare c public.fin_config; hoy date := public.fin_hoy(); ultimo date; semana date; pendiente boolean;
 pagado jsonb; anterior jsonb;
begin
 perform public.fin_exigir_admin();
 select * into c from public.fin_config;
 if c.sueldo_semanal is null then
  return jsonb_build_object('semanal', null);
 end if;
 -- Último sábado que ya llegó (hoy si es sábado).
 ultimo := public.fin_sabado_de(hoy);
 if ultimo > hoy then ultimo := ultimo - 7; end if;
 pendiente := ultimo >= c.sueldo_desde and not exists (select 1 from public.fin_movimientos m
  where m.tipo = 'hogar' and m.categoria = 'Sueldo' and m.periodo = ultimo and m.anulado_at is null);
 semana := case when pendiente then ultimo else ultimo + 7 end;
 select jsonb_build_object('importe', -m.importe, 'fecha', m.fecha) into pagado from public.fin_movimientos m
 where m.tipo = 'hogar' and m.categoria = 'Sueldo' and m.periodo = semana and m.anulado_at is null;
 select jsonb_build_object('semana', m.periodo, 'importe', -m.importe, 'fecha', m.fecha) into anterior
 from public.fin_movimientos m where m.tipo = 'hogar' and m.categoria = 'Sueldo' and m.anulado_at is null
 order by m.periodo desc limit 1;
 return jsonb_build_object('semanal', c.sueldo_semanal, 'desde', c.sueldo_desde, 'semana', semana,
  'pendiente', pendiente, 'pagado', pagado, 'ultimo', anterior, 'por_mes', round(c.sueldo_semanal * 52 / 12));
end $$;

-- Totales de un período de fin_flujo, con los retiros separados.
create function public.fin_totales(p_desde timestamptz, p_hasta timestamptz) returns jsonb
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
 select jsonb_build_object(
  'gastos_negocio', coalesce(sum(-x.importe - x.parte_hogar) filter (where x.tipo in ('gasto', 'gasto_fijo')), 0),
  'retiros', coalesce(sum(x.parte_hogar), 0),
  'sueldo', coalesce(sum(x.parte_hogar) filter (where x.tipo = 'hogar' and x.categoria = 'Sueldo'), 0),
  'personal', coalesce(sum(x.parte_hogar) filter (where x.tipo = 'hogar' and x.categoria = 'Personal'), 0),
  'casa', coalesce(sum(x.parte_hogar) filter (where not (x.tipo = 'hogar' and x.categoria in ('Sueldo', 'Personal'))), 0),
  'aportes', coalesce(sum(x.importe) filter (where x.tipo = 'ingreso' and x.categoria = 'Aporte del dueño'), 0),
  'gastos_por_categoria', coalesce((select jsonb_object_agg(g.categoria, g.total) from (
    select coalesce(y.categoria, 'Otros') categoria, sum(-y.importe - y.parte_hogar) total
    from public.fin_flujo(p_desde, p_hasta) y where y.tipo in ('gasto', 'gasto_fijo')
    group by 1 having sum(-y.importe - y.parte_hogar) <> 0) g), '{}'::jsonb))
 from public.fin_flujo(p_desde, p_hasta) x
$$;

-- Todo lo de "Plata del negocio" en una consulta (por GET: queda en la copia sin señal).
create or replace function public.fin_estado() returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare inicio timestamptz; hoy date := public.fin_hoy(); mes_desde timestamptz; cuentas jsonb; gastos jsonb;
 deudas jsonb; plata numeric; sobre numeric; deben numeric; mes jsonb; ultimos jsonb;
begin
 perform public.fin_exigir_admin();
 select c.inicio into inicio from public.fin_config c;
 mes_desde := date_trunc('month', hoy)::timestamp at time zone 'America/Argentina/Buenos_Aires';
 select coalesce(jsonb_agg(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre,
   'saldo', coalesce((select sum(x.importe) from public.fin_flujo('-infinity', 'infinity') x where x.cuenta = c.codigo), 0))
   order by c.orden), '[]')
 into cuentas from public.fin_cuentas c;
 select coalesce(sum((x->>'saldo')::numeric), 0) into plata from jsonb_array_elements(cuentas) x;
 select coalesce(jsonb_agg(public.fin_sobre_de(g, hoy, inicio::date) order by g.activo desc, g.dia_pago, g.nombre), '[]')
 into gastos from public.fin_gastos_fijos g;
 select coalesce(sum((x->>'reservado')::numeric), 0) into sobre from jsonb_array_elements(gastos) x;
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
 return jsonb_build_object('inicio', inicio, 'hoy', hoy, 'cuentas', cuentas, 'plata', plata,
  'gastos_fijos', gastos, 'sobre', sobre, 'deudas', deudas, 'deben', deben,
  'disponible', plata - sobre - deben, 'mes', mes, 'ultimos', ultimos,
  'sueldo', case when inicio is null then null else public.fin_sueldo_estado() end, 'consultado_at', now());
end $$;

-- Tablero: además del total para la casa, cada retiro por separado, los aportes y los gastos por categoría.
create or replace function public.fin_tablero(p_mes date) returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare tz constant text := 'America/Argentina/Buenos_Aires'; hoy date := public.fin_hoy();
 mes date := date_trunc('month', coalesce(p_mes, hoy))::date; sig date; desde timestamptz; hasta timestamptz;
 com jsonb; anual jsonb; inicio timestamptz; ventas numeric; costo numeric; comisiones numeric; ganancia numeric;
 nc numeric; gastos numeric := 0; hogar numeric := 0; margen numeric; actual boolean; capital jsonb;
 cap_inicio jsonb; cap_cierre jsonb; dias integer; dia integer; tot jsonb := '{}'::jsonb;
begin
 perform public.fin_exigir_admin();
 sig := (mes + interval '1 month')::date;
 desde := mes::timestamp at time zone tz; hasta := sig::timestamp at time zone tz;
 actual := hoy >= mes and hoy < sig;
 com := public.resumen_comercial(desde, hasta);
 ventas := coalesce((com->>'mercaderia_neta')::numeric, 0);
 costo := coalesce((com->>'costo_mercaderia')::numeric, 0);
 comisiones := coalesce((com->>'comisiones')::numeric, 0);
 ganancia := coalesce((com->>'ganancia')::numeric, 0);
 nc := ganancia - (ventas - costo - comisiones);
 select c.inicio into inicio from public.fin_config c;
 if inicio is not null then
  tot := public.fin_totales(desde, hasta);
  gastos := (tot->>'gastos_negocio')::numeric;
  hogar := (tot->>'retiros')::numeric;
 end if;
 margen := case when ventas > 0 then ganancia / ventas end;
 anual := public.resumen_comercial(hasta - interval '12 months', least(hasta, now()));
 dias := sig - mes;
 dia := case when actual then hoy - mes + 1 else dias end;
 cap_inicio := public.fin_foto_capital_antes(mes);
 if actual then capital := public.fin_capital_hoy();
 else cap_cierre := public.fin_foto_capital_antes(sig); end if;
 return jsonb_build_object(
  'mes', mes, 'actual', actual, 'dia', dia, 'dias', dias,
  'ventas', ventas, 'costo', costo, 'comisiones', comisiones, 'notas_credito', nc,
  'ganancia_comercial', ganancia, 'margen', margen,
  'gastos_negocio', gastos, 'ganancia_negocio', ganancia - gastos,
  'hogar', hogar, 'quedo', ganancia - gastos - hogar,
  'sueldo', coalesce((tot->>'sueldo')::numeric, 0), 'casa', coalesce((tot->>'casa')::numeric, 0),
  'personal', coalesce((tot->>'personal')::numeric, 0), 'aportes', coalesce((tot->>'aportes')::numeric, 0),
  'gastos_por_categoria', coalesce(tot->'gastos_por_categoria', '{}'::jsonb),
  'plata_desde', inicio, 'plata_parcial', inicio is null or inicio > desde,
  'ventas_necesarias', case when margen > 0 then (gastos + hogar) / margen end,
  'ventas_12_meses', coalesce((anual->>'mercaderia_neta')::numeric, 0),
  'capital', capital, 'capital_inicio', cap_inicio, 'capital_cierre', cap_cierre);
end $$;

-- Salud del negocio: los últimos p_meses meses (el actual incluido), del más viejo al más nuevo.
-- Ventas y margen se miden en todo el mes (hay datos de antes); la ganancia del negocio, los gastos y los
-- retiros solo desde la foto inicial ("medido"), con las ventas de ese mismo tramo, para no inflarla.
create function public.fin_salud(p_meses integer default 6) returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare tz constant text := 'America/Argentina/Buenos_Aires'; hoy date := public.fin_hoy(); cfg public.fin_config;
 n integer := least(greatest(coalesce(p_meses, 6), 1), 12); mes date; sig date; desde timestamptz; hasta timestamptz;
 medido timestamptz; com jsonb; com_m jsonb; tot jsonb; meses jsonb := '[]'::jsonb; ventas numeric; gan numeric;
 ventas_m numeric; gan_m numeric; cap_ini jsonb; cap_fin jsonb; actual boolean;
begin
 perform public.fin_exigir_admin();
 select * into cfg from public.fin_config;
 for i in reverse n - 1 .. 0 loop
  mes := (date_trunc('month', hoy) - make_interval(months => i))::date;
  sig := (mes + interval '1 month')::date;
  actual := hoy < sig;
  desde := mes::timestamp at time zone tz;
  hasta := sig::timestamp at time zone tz;
  com := public.resumen_comercial(desde, hasta);
  ventas := coalesce((com->>'mercaderia_neta')::numeric, 0);
  gan := coalesce((com->>'ganancia')::numeric, 0);
  medido := case when cfg.inicio is null or cfg.inicio >= least(hasta, now()) then null
   else greatest(desde, cfg.inicio) end;
  tot := null; ventas_m := null; gan_m := null;
  if medido is not null then
   if medido = desde then com_m := com; else com_m := public.resumen_comercial(medido, hasta); end if;
   ventas_m := coalesce((com_m->>'mercaderia_neta')::numeric, 0);
   gan_m := coalesce((com_m->>'ganancia')::numeric, 0);
   tot := public.fin_totales(medido, hasta) - 'gastos_por_categoria';
  end if;
  cap_ini := public.fin_foto_capital_antes(mes);
  cap_fin := case when actual then public.fin_capital_hoy() else public.fin_foto_capital_antes(sig) end;
  meses := meses || jsonb_build_object(
   'mes', mes, 'actual', actual, 'ventas', ventas, 'ganancia_comercial', gan,
   'margen', case when ventas > 0 then round(gan / ventas, 4) end,
   'completo', medido is not null and medido = desde,
   'medido', case when medido is null then null else jsonb_build_object(
     'desde', medido, 'hasta', least(hasta, now()),
     'dias', greatest(1, ceil(extract(epoch from least(hasta, now()) - medido) / 86400)::integer),
     'ventas', ventas_m, 'ganancia_comercial', gan_m,
     'ganancia_negocio', gan_m - (tot->>'gastos_negocio')::numeric) || tot end,
   'capital_inicio', cap_ini->'total', 'capital_inicio_fecha', cap_ini->'fecha',
   'capital_fin', cap_fin->'total', 'capital_fin_fecha', cap_fin->'fecha');
 end loop;
 return jsonb_build_object('hoy', hoy, 'inicio', cfg.inicio, 'sueldo_semanal', cfg.sueldo_semanal,
  'meses', meses, 'consultado_at', now());
end $$;

revoke all on function public.fin_sabado_de(date), public.fin_totales(timestamptz, timestamptz)
 from public, anon, authenticated;
revoke all on function public.fin_sueldo_guardar(numeric),
 public.fin_pagar_sueldo(uuid, timestamptz, date, text, numeric),
 public.fin_reclasificar(uuid, text, text), public.fin_sueldo_estado(), public.fin_salud(integer)
 from public, anon;
grant execute on function public.fin_sueldo_guardar(numeric),
 public.fin_pagar_sueldo(uuid, timestamptz, date, text, numeric),
 public.fin_reclasificar(uuid, text, text), public.fin_sueldo_estado(), public.fin_salud(integer)
 to authenticated;
