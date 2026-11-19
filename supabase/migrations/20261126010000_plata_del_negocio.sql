-- Gestión del negocio, etapa 1: "Plata del negocio". Solo administración.
-- Dos cuentas (efectivo y billetera virtual); gastos del negocio; plata para el hogar (retiros);
-- gastos fijos con "sobre" que se va apartando solo hasta el día de pago; deudas a proveedores
-- (compras a pagar); pases entre cuentas; arqueo; y una foto inicial desde la que se cuenta todo.
-- Los cobros a clientes, las devoluciones en dinero y las comisiones pagadas NO se cargan: se
-- leen de cobros_cliente, movimientos_credito_cliente y liquidaciones (sin tocar esas tablas).
-- Toda operación lleva id del teléfono (idempotente) y hora real, como las de stock.

create table public.fin_config (
 id boolean primary key default true check (id),
 inicio timestamptz
);
insert into public.fin_config(id) values (true);

create table public.fin_cuentas (
 codigo text primary key check (codigo in ('efectivo', 'billetera')),
 nombre text not null,
 orden integer not null
);
insert into public.fin_cuentas values ('efectivo', 'Efectivo', 1), ('billetera', 'Billetera virtual', 2);

create table public.fin_gastos_fijos (
 id uuid primary key,
 nombre text not null check (length(btrim(nombre)) > 0),
 importe numeric(14,2) not null check (importe > 0),
 dia_pago integer not null check (dia_pago between 1 and 31),
 ambito text not null check (ambito in ('negocio', 'hogar', 'mixto')),
 activo boolean not null default true,
 created_at timestamptz not null default now()
);

create table public.fin_deudas (
 id uuid primary key,
 fecha timestamptz not null,
 proveedor text not null check (length(btrim(proveedor)) > 0),
 importe numeric(14,2) not null check (importe > 0),
 vence date not null,
 descripcion text,
 actor_id uuid not null references public.usuarios(id),
 request_hash text not null,
 anulado_at timestamptz,
 created_at timestamptz not null default now()
);

-- importe con signo para la cuenta: positivo entra, negativo sale. En un pase sale de "cuenta"
-- y entra en "cuenta_destino". parte_hogar: lo de la salida que fue para la casa.
create table public.fin_movimientos (
 id uuid primary key,
 fecha timestamptz not null,
 tipo text not null check (tipo in ('saldo_inicial', 'gasto', 'gasto_fijo', 'hogar', 'compra',
  'pago_proveedor', 'pase', 'ingreso', 'ajuste')),
 cuenta text not null references public.fin_cuentas(codigo),
 cuenta_destino text references public.fin_cuentas(codigo),
 importe numeric(14,2) not null,
 parte_hogar numeric(14,2) not null default 0 check (parte_hogar >= 0),
 categoria text,
 descripcion text,
 gasto_fijo_id uuid references public.fin_gastos_fijos(id),
 periodo date,
 deuda_id uuid references public.fin_deudas(id),
 actor_id uuid not null references public.usuarios(id),
 request_hash text not null,
 anulado_at timestamptz,
 anulado_por uuid references public.usuarios(id),
 created_at timestamptz not null default now(),
 check (tipo <> 'pase' or (cuenta_destino is not null and cuenta_destino <> cuenta and importe < 0)),
 check (importe <> 0 or tipo = 'saldo_inicial'),
 check (parte_hogar <= abs(importe))
);
create index fin_movimientos_fecha_idx on public.fin_movimientos(fecha);
create unique index fin_gasto_fijo_pagado_una_vez on public.fin_movimientos(gasto_fijo_id, periodo)
 where tipo = 'gasto_fijo' and anulado_at is null;

create table public.fin_arqueos (
 id uuid primary key,
 fecha timestamptz not null,
 cuenta text not null references public.fin_cuentas(codigo),
 sistema numeric(14,2) not null,
 contado numeric(14,2) not null,
 diferencia numeric(14,2) not null,
 actor_id uuid not null references public.usuarios(id),
 created_at timestamptz not null default now()
);

alter table public.fin_config enable row level security;
alter table public.fin_cuentas enable row level security;
alter table public.fin_gastos_fijos enable row level security;
alter table public.fin_deudas enable row level security;
alter table public.fin_movimientos enable row level security;
alter table public.fin_arqueos enable row level security;
revoke all on public.fin_config, public.fin_cuentas, public.fin_gastos_fijos, public.fin_deudas,
 public.fin_movimientos, public.fin_arqueos from anon, authenticated;

-- Ayudas.
create function public.fin_exigir_admin() returns void
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
begin
 if public.es_administrador() is not true then
  raise exception 'Solo administración' using errcode = 'PT403'; end if;
end $$;

create function public.fin_hoy() returns date
language sql stable set search_path = pg_catalog, public, pg_temp as $$
 select (now() at time zone 'America/Argentina/Buenos_Aires')::date
$$;

-- Día de pago dentro de un mes (el 31 en un mes de 30 días cae el 30).
create function public.fin_vencimiento(p_dia integer, p_mes date) returns date
language sql immutable set search_path = pg_catalog, public, pg_temp as $$
 select (date_trunc('month', p_mes)::date
  + (least(p_dia, extract(day from date_trunc('month', p_mes) + interval '1 month - 1 day')::integer) - 1))::date
$$;

create function public.fin_cuenta_de_medio(p_medio text) returns text
language sql immutable set search_path = pg_catalog, public, pg_temp as $$
 select case when lower(btrim(coalesce(p_medio, ''))) like 'efectivo%' then 'efectivo' else 'billetera' end
$$;

-- Fecha real de la operación: no en el futuro y no antes de la foto inicial.
create function public.fin_validar_fecha(p_fecha timestamptz) returns timestamptz
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare inicio timestamptz; f timestamptz := coalesce(p_fecha, now());
begin
 select c.inicio into inicio from public.fin_config c;
 if inicio is null then
  raise exception 'Primero hacé la foto inicial: cuánta plata hay hoy.' using errcode = 'PT409'; end if;
 if f > now() + interval '10 minutes' then
  raise exception 'La fecha está en el futuro.' using errcode = 'PT422'; end if;
 if f < inicio then
  raise exception 'La fecha es anterior a la foto inicial.' using errcode = 'PT422'; end if;
 return f;
end $$;

create function public.fin_huella(p jsonb) returns text
language sql immutable set search_path = pg_catalog, public, pg_temp as $$ select md5(p::text) $$;

-- Si el teléfono reenvía la misma operación, devuelve lo mismo; si el id se usó para otra cosa, error.
create function public.fin_previo(p_hash_guardado text, p_hash text, p_id uuid) returns jsonb
language plpgsql immutable set search_path = pg_catalog, public, pg_temp as $$
begin
 if p_hash_guardado is null then return null; end if;
 if p_hash_guardado <> p_hash then
  raise exception 'Esta operación ya se registró con otros datos.' using errcode = 'PT409'; end if;
 return jsonb_build_object('id', p_id, 'repetida', true);
end $$;

create function public.fin_validar_cuenta(p_cuenta text) returns void
language plpgsql immutable set search_path = pg_catalog, public, pg_temp as $$
begin
 if p_cuenta is null or p_cuenta not in ('efectivo', 'billetera') then
  raise exception 'Elegí efectivo o billetera.' using errcode = 'PT422'; end if;
end $$;

-- Todo el movimiento de plata: lo anotado más cobros, devoluciones y comisiones pagadas (desde la
-- foto inicial). Un pase aparece dos veces: sale de una cuenta y entra en la otra.
create function public.fin_flujo(p_desde timestamptz, p_hasta timestamptz)
returns table(id text, fecha timestamptz, tipo text, cuenta text, importe numeric, parte_hogar numeric,
 categoria text, descripcion text, anulable boolean)
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
 with cfg as (select c.inicio from public.fin_config c where c.inicio is not null)
 select m.id::text, m.fecha, m.tipo, m.cuenta, m.importe, m.parte_hogar, m.categoria, m.descripcion,
  m.tipo <> 'saldo_inicial'
 from public.fin_movimientos m
 where m.anulado_at is null and m.fecha >= p_desde and m.fecha < p_hasta
 union all
 select m.id::text || ':entra', m.fecha, 'pase', m.cuenta_destino, -m.importe, 0, m.categoria, m.descripcion, false
 from public.fin_movimientos m
 where m.tipo = 'pase' and m.anulado_at is null and m.fecha >= p_desde and m.fecha < p_hasta
 union all
 select c.id::text, c.fecha_pago, 'cobro', public.fin_cuenta_de_medio(c.medio_pago), c.importe, 0,
  'Cobro', cl.nombre_comercio, false
 from public.cobros_cliente c join cfg on c.fecha_pago >= cfg.inicio
 left join public.clientes cl on cl.id = c.cliente_id
 where c.fecha_pago >= p_desde and c.fecha_pago < p_hasta
 union all
 select r.id::text, r.fecha, 'devolucion', public.fin_cuenta_de_medio(r.medio_pago), -r.importe, 0,
  'Devolución a cliente', null, false
 from public.movimientos_credito_cliente r join cfg on r.fecha >= cfg.inicio
 where r.pedido_destino_id is null and r.medio_pago is not null and r.fecha >= p_desde and r.fecha < p_hasta
 union all
 select l.id::text, l.fecha_pago, 'comision', 'efectivo', -l.comision_total, 0, 'Comisiones',
  btrim(coalesce(u.nombre, '') || ' ' || coalesce(u.apellido, '')), false
 from public.liquidaciones l join cfg on l.fecha_pago >= cfg.inicio
 left join public.usuarios u on u.id = l.preventista_id
 where l.estado = 'pagada' and l.comision_total <> 0 and l.fecha_pago >= p_desde and l.fecha_pago < p_hasta
$$;

-- Foto inicial: cuánta plata hay hoy. Desde acá empieza a contar todo.
create function public.fin_foto_inicial(p_id uuid, p_fecha timestamptz, p_efectivo numeric, p_billetera numeric)
returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare huella text; previo text; f timestamptz := coalesce(p_fecha, now());
begin
 perform public.fin_exigir_admin();
 huella := public.fin_huella(jsonb_build_object('f', p_fecha, 'e', p_efectivo, 'b', p_billetera));
 perform pg_advisory_xact_lock(829002);
 select m.request_hash into previo from public.fin_movimientos m where m.id = p_id;
 if previo is not null then return public.fin_previo(previo, huella, p_id); end if;
 if (select c.inicio from public.fin_config c) is not null then
  raise exception 'La foto inicial ya está hecha.' using errcode = 'PT409'; end if;
 if f > now() + interval '10 minutes' then
  raise exception 'La fecha está en el futuro.' using errcode = 'PT422'; end if;
 if coalesce(p_efectivo, -1) < 0 or coalesce(p_billetera, -1) < 0 then
  raise exception 'Escribí cuánto hay (0 si no hay nada).' using errcode = 'PT422'; end if;
 update public.fin_config set inicio = f;
 insert into public.fin_movimientos(id, fecha, tipo, cuenta, importe, categoria, actor_id, request_hash)
 values (p_id, f, 'saldo_inicial', 'efectivo', p_efectivo, 'Foto inicial', auth.uid(), huella),
  (md5(p_id::text || ':billetera')::uuid, f, 'saldo_inicial', 'billetera', p_billetera, 'Foto inicial',
   auth.uid(), huella);
 return jsonb_build_object('id', p_id, 'inicio', f);
end $$;

-- Gasto del negocio, plata para el hogar, compra pagada, ingreso extra o pase entre cuentas.
create function public.fin_movimiento(p_id uuid, p_fecha timestamptz, p_tipo text, p_cuenta text, p_importe numeric,
 p_categoria text default null, p_descripcion text default null, p_cuenta_destino text default null)
returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare huella text; previo text; f timestamptz; signo numeric; hogar numeric := 0;
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
 signo := case when p_tipo = 'ingreso' then 1 else -1 end;
 if p_tipo = 'hogar' then hogar := p_importe; end if;
 insert into public.fin_movimientos(id, fecha, tipo, cuenta, cuenta_destino, importe, parte_hogar, categoria,
  descripcion, actor_id, request_hash)
 values (p_id, f, p_tipo, p_cuenta, case when p_tipo = 'pase' then p_cuenta_destino end, signo * p_importe, hogar,
  coalesce(nullif(btrim(p_categoria), ''), case p_tipo when 'gasto' then 'Otros' when 'hogar' then 'Hogar'
   when 'compra' then 'Mercadería' when 'pase' then 'Pase entre cuentas' else 'Ingreso' end),
  nullif(btrim(p_descripcion), ''), auth.uid(), huella);
 return jsonb_build_object('id', p_id);
end $$;

-- Alta o cambio de un gasto fijo (no es una operación de plata: no lleva fecha).
create function public.fin_gasto_fijo_guardar(p_id uuid, p_nombre text, p_importe numeric, p_dia integer,
 p_ambito text, p_activo boolean default true) returns jsonb
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
 insert into public.fin_gastos_fijos(id, nombre, importe, dia_pago, ambito, activo)
 values (p_id, btrim(p_nombre), p_importe, p_dia, p_ambito, coalesce(p_activo, true))
 on conflict (id) do update set nombre = excluded.nombre, importe = excluded.importe,
  dia_pago = excluded.dia_pago, ambito = excluded.ambito, activo = excluded.activo;
 return jsonb_build_object('id', p_id);
end $$;

-- Pagar un gasto fijo del mes. Mixto (la tarjeta): se indica cuánto fue para la casa.
create function public.fin_pagar_gasto_fijo(p_id uuid, p_fecha timestamptz, p_gasto_fijo_id uuid, p_periodo date,
 p_cuenta text, p_importe numeric, p_parte_hogar numeric default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare huella text; previo text; f timestamptz; gf public.fin_gastos_fijos; hogar numeric;
begin
 perform public.fin_exigir_admin();
 huella := public.fin_huella(jsonb_build_object('f', p_fecha, 'g', p_gasto_fijo_id, 'p', p_periodo, 'c', p_cuenta,
  'i', p_importe, 'h', p_parte_hogar));
 select m.request_hash into previo from public.fin_movimientos m where m.id = p_id;
 if previo is not null then return public.fin_previo(previo, huella, p_id); end if;
 f := public.fin_validar_fecha(p_fecha);
 perform public.fin_validar_cuenta(p_cuenta);
 select * into gf from public.fin_gastos_fijos where id = p_gasto_fijo_id;
 if not found then raise exception 'Gasto fijo inexistente.' using errcode = 'PT404'; end if;
 if coalesce(p_importe, 0) <= 0 then
  raise exception 'El importe tiene que ser mayor que 0.' using errcode = 'PT422'; end if;
 hogar := case gf.ambito when 'negocio' then 0 when 'hogar' then p_importe else coalesce(p_parte_hogar, -1) end;
 if hogar < 0 or hogar > p_importe then
  raise exception 'Indicá cuánto fue para la casa (entre 0 y el total).' using errcode = 'PT422'; end if;
 if exists (select 1 from public.fin_movimientos m where m.gasto_fijo_id = gf.id and m.periodo = p_periodo
   and m.tipo = 'gasto_fijo' and m.anulado_at is null) then
  raise exception 'Ese gasto fijo ya está pagado este mes.' using errcode = 'PT409'; end if;
 insert into public.fin_movimientos(id, fecha, tipo, cuenta, importe, parte_hogar, categoria, gasto_fijo_id,
  periodo, actor_id, request_hash)
 values (p_id, f, 'gasto_fijo', p_cuenta, -p_importe, hogar, gf.nombre, gf.id, p_periodo, auth.uid(), huella);
 return jsonb_build_object('id', p_id);
end $$;

-- Compra a pagar (el proveedor con plazo).
create function public.fin_deuda(p_id uuid, p_fecha timestamptz, p_proveedor text, p_importe numeric, p_vence date,
 p_descripcion text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare huella text; previo text; f timestamptz;
begin
 perform public.fin_exigir_admin();
 huella := public.fin_huella(jsonb_build_object('f', p_fecha, 'p', p_proveedor, 'i', p_importe, 'v', p_vence,
  'd', p_descripcion));
 select d.request_hash into previo from public.fin_deudas d where d.id = p_id;
 if previo is not null then return public.fin_previo(previo, huella, p_id); end if;
 f := public.fin_validar_fecha(p_fecha);
 if length(btrim(coalesce(p_proveedor, ''))) = 0 then
  raise exception 'Escribí el proveedor.' using errcode = 'PT422'; end if;
 if coalesce(p_importe, 0) <= 0 then
  raise exception 'El importe tiene que ser mayor que 0.' using errcode = 'PT422'; end if;
 if p_vence is null then raise exception 'Indicá cuándo vence.' using errcode = 'PT422'; end if;
 insert into public.fin_deudas(id, fecha, proveedor, importe, vence, descripcion, actor_id, request_hash)
 values (p_id, f, btrim(p_proveedor), p_importe, p_vence, nullif(btrim(p_descripcion), ''), auth.uid(), huella);
 return jsonb_build_object('id', p_id);
end $$;

create function public.fin_pagar_deuda(p_id uuid, p_fecha timestamptz, p_deuda_id uuid, p_cuenta text,
 p_importe numeric) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare huella text; previo text; f timestamptz; d public.fin_deudas; pagado numeric;
begin
 perform public.fin_exigir_admin();
 huella := public.fin_huella(jsonb_build_object('f', p_fecha, 'd', p_deuda_id, 'c', p_cuenta, 'i', p_importe));
 select m.request_hash into previo from public.fin_movimientos m where m.id = p_id;
 if previo is not null then return public.fin_previo(previo, huella, p_id); end if;
 f := public.fin_validar_fecha(p_fecha);
 perform public.fin_validar_cuenta(p_cuenta);
 select * into d from public.fin_deudas where id = p_deuda_id and anulado_at is null for update;
 if not found then raise exception 'Deuda inexistente.' using errcode = 'PT404'; end if;
 select coalesce(-sum(m.importe), 0) into pagado from public.fin_movimientos m
 where m.deuda_id = d.id and m.anulado_at is null;
 if coalesce(p_importe, 0) <= 0 or p_importe > d.importe - pagado then
  raise exception 'El pago tiene que ser mayor que 0 y no más de lo que se debe (%).', d.importe - pagado
   using errcode = 'PT422'; end if;
 insert into public.fin_movimientos(id, fecha, tipo, cuenta, importe, categoria, descripcion, deuda_id,
  actor_id, request_hash)
 values (p_id, f, 'pago_proveedor', p_cuenta, -p_importe, d.proveedor, d.descripcion, d.id, auth.uid(), huella);
 return jsonb_build_object('id', p_id, 'resta', d.importe - pagado - p_importe);
end $$;

-- Arqueo: lo contado contra lo que debería haber; la diferencia queda como ajuste.
create function public.fin_arqueo(p_id uuid, p_fecha timestamptz, p_cuenta text, p_contado numeric) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare f timestamptz; sistema numeric; dif numeric; previo public.fin_arqueos;
begin
 perform public.fin_exigir_admin();
 select * into previo from public.fin_arqueos where id = p_id;
 if found then
  if previo.cuenta <> p_cuenta or previo.contado <> p_contado then
   raise exception 'Esta operación ya se registró con otros datos.' using errcode = 'PT409'; end if;
  return jsonb_build_object('id', p_id, 'sistema', previo.sistema, 'contado', previo.contado,
   'diferencia', previo.diferencia, 'repetida', true);
 end if;
 f := public.fin_validar_fecha(p_fecha);
 perform public.fin_validar_cuenta(p_cuenta);
 if p_contado is null or p_contado < 0 then
  raise exception 'Escribí cuánto hay (0 si no hay nada).' using errcode = 'PT422'; end if;
 perform pg_advisory_xact_lock(829002);
 select coalesce(sum(x.importe), 0) into sistema from public.fin_flujo('-infinity', f + interval '1 microsecond') x
 where x.cuenta = p_cuenta;
 dif := p_contado - sistema;
 insert into public.fin_arqueos(id, fecha, cuenta, sistema, contado, diferencia, actor_id)
 values (p_id, f, p_cuenta, sistema, p_contado, dif, auth.uid());
 if dif <> 0 then
  insert into public.fin_movimientos(id, fecha, tipo, cuenta, importe, categoria, actor_id, request_hash)
  values (p_id, f, 'ajuste', p_cuenta, dif, case when dif > 0 then 'Sobrante de arqueo' else 'Faltante de arqueo' end,
   auth.uid(), public.fin_huella(jsonb_build_object('arqueo', p_id)));
 end if;
 return jsonb_build_object('id', p_id, 'sistema', sistema, 'contado', p_contado, 'diferencia', dif);
end $$;

-- Deshacer un error (no se borra: queda anulado).
create function public.fin_anular(p_id uuid) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare m public.fin_movimientos;
begin
 perform public.fin_exigir_admin();
 select * into m from public.fin_movimientos where id = p_id for update;
 if found then
  if m.tipo = 'saldo_inicial' then
   raise exception 'La foto inicial no se anula: corregila con un arqueo.' using errcode = 'PT409'; end if;
  update public.fin_movimientos set anulado_at = coalesce(anulado_at, now()), anulado_por = coalesce(anulado_por, auth.uid())
  where id = p_id;
  return jsonb_build_object('id', p_id, 'anulado', true);
 end if;
 if exists (select 1 from public.fin_deudas where id = p_id) then
  if exists (select 1 from public.fin_movimientos x where x.deuda_id = p_id and x.anulado_at is null) then
   raise exception 'Esa deuda tiene pagos: anulá primero los pagos.' using errcode = 'PT409'; end if;
  update public.fin_deudas set anulado_at = coalesce(anulado_at, now()) where id = p_id;
  return jsonb_build_object('id', p_id, 'anulado', true);
 end if;
 raise exception 'Movimiento inexistente.' using errcode = 'PT404';
end $$;

-- Gasto fijo: próximo vencimiento sin pagar y cuánto debería estar apartado hoy.
create function public.fin_sobre_de(gf public.fin_gastos_fijos, p_hoy date, p_inicio date) returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare mes date := date_trunc('month', p_hoy)::date; este date; vence date; anterior date;
 pagado_este boolean; dias integer; frac numeric;
begin
 este := public.fin_vencimiento(gf.dia_pago, mes);
 pagado_este := exists (select 1 from public.fin_movimientos m where m.gasto_fijo_id = gf.id and m.periodo = este
  and m.tipo = 'gasto_fijo' and m.anulado_at is null);
 -- Lo que venció antes de la foto inicial se da por pagado.
 if not pagado_este and este >= coalesce(p_inicio, p_hoy) then vence := este;
 else vence := public.fin_vencimiento(gf.dia_pago, (mes + interval '1 month')::date); end if;
 anterior := public.fin_vencimiento(gf.dia_pago, (date_trunc('month', vence) - interval '1 month')::date);
 dias := greatest(vence - anterior, 1);
 frac := case when p_hoy >= vence then 1 else least(1, greatest(0, (p_hoy - anterior)::numeric / dias)) end;
 return jsonb_build_object('id', gf.id, 'nombre', gf.nombre, 'importe', gf.importe, 'dia_pago', gf.dia_pago,
  'ambito', gf.ambito, 'activo', gf.activo, 'vence', vence, 'vencido', p_hoy > vence,
  'reservado', case when gf.activo then round(gf.importe * frac) else 0 end,
  'por_semana', round(gf.importe * 7 / dias),
  'pagado_mes', pagado_este, 'periodo_mes', este);
end $$;

-- Todo lo de "Plata del negocio" en una consulta (por GET: queda en la copia sin señal).
create function public.fin_estado() returns jsonb
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
   'ingresos', coalesce(sum(x.importe) filter (where x.tipo = 'ingreso'), 0),
   'compras', coalesce(-sum(x.importe) filter (where x.tipo in ('compra', 'pago_proveedor')), 0),
   'gastos_negocio', coalesce(sum(-x.importe - x.parte_hogar) filter (where x.tipo in ('gasto', 'gasto_fijo')), 0),
   'comisiones', coalesce(-sum(x.importe) filter (where x.tipo = 'comision'), 0),
   'devoluciones', coalesce(-sum(x.importe) filter (where x.tipo = 'devolucion'), 0),
   'hogar', coalesce(sum(x.parte_hogar), 0),
   'ajustes', coalesce(sum(x.importe) filter (where x.tipo = 'ajuste'), 0))
 into mes from public.fin_flujo(mes_desde, 'infinity') x;
 select coalesce(jsonb_agg(to_jsonb(u) order by u.fecha desc), '[]') into ultimos
 from (select * from public.fin_flujo('-infinity', 'infinity') order by fecha desc limit 40) u;
 return jsonb_build_object('inicio', inicio, 'hoy', hoy, 'cuentas', cuentas, 'plata', plata,
  'gastos_fijos', gastos, 'sobre', sobre, 'deudas', deudas, 'deben', deben,
  'disponible', plata - sobre - deben, 'mes', mes, 'ultimos', ultimos, 'consultado_at', now());
end $$;

-- Movimientos de un período (pantalla de historial).
create function public.fin_movimientos_lista(p_desde timestamptz, p_hasta timestamptz) returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
begin
 perform public.fin_exigir_admin();
 return (select coalesce(jsonb_agg(to_jsonb(u) order by u.fecha desc), '[]')
  from (select * from public.fin_flujo(p_desde, p_hasta) order by fecha desc limit 1000) u);
end $$;

revoke all on function public.fin_exigir_admin(), public.fin_hoy(), public.fin_vencimiento(integer, date),
 public.fin_cuenta_de_medio(text), public.fin_validar_fecha(timestamptz), public.fin_huella(jsonb),
 public.fin_previo(text, text, uuid), public.fin_validar_cuenta(text),
 public.fin_flujo(timestamptz, timestamptz), public.fin_sobre_de(public.fin_gastos_fijos, date, date)
 from public, anon, authenticated;
revoke all on function public.fin_foto_inicial(uuid, timestamptz, numeric, numeric),
 public.fin_movimiento(uuid, timestamptz, text, text, numeric, text, text, text),
 public.fin_gasto_fijo_guardar(uuid, text, numeric, integer, text, boolean),
 public.fin_pagar_gasto_fijo(uuid, timestamptz, uuid, date, text, numeric, numeric),
 public.fin_deuda(uuid, timestamptz, text, numeric, date, text),
 public.fin_pagar_deuda(uuid, timestamptz, uuid, text, numeric),
 public.fin_arqueo(uuid, timestamptz, text, numeric), public.fin_anular(uuid),
 public.fin_estado(), public.fin_movimientos_lista(timestamptz, timestamptz) from public, anon;
grant execute on function public.fin_foto_inicial(uuid, timestamptz, numeric, numeric),
 public.fin_movimiento(uuid, timestamptz, text, text, numeric, text, text, text),
 public.fin_gasto_fijo_guardar(uuid, text, numeric, integer, text, boolean),
 public.fin_pagar_gasto_fijo(uuid, timestamptz, uuid, date, text, numeric, numeric),
 public.fin_deuda(uuid, timestamptz, text, numeric, date, text),
 public.fin_pagar_deuda(uuid, timestamptz, uuid, text, numeric),
 public.fin_arqueo(uuid, timestamptz, text, numeric), public.fin_anular(uuid),
 public.fin_estado(), public.fin_movimientos_lista(timestamptz, timestamptz) to authenticated;
