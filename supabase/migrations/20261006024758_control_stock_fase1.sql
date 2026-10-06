-- Fase 1A: saldos por ubicación y auditoría. No modifica productos.stock,
-- pedidos, ventas ni notificaciones. Las cantidades se escriben solo por RPC.
begin;

create table public.ubicaciones_stock (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nombre text not null,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ubicaciones_stock_codigo_valido check (btrim(codigo) <> ''),
  constraint ubicaciones_stock_nombre_valido check (btrim(nombre) <> '')
);

insert into public.ubicaciones_stock(codigo, nombre)
values ('deposito_alberdi', 'Depósito Distribuidora Alberdi')
on conflict (codigo) do nothing;

create table public.stock_actual (
  ubicacion_id uuid not null references public.ubicaciones_stock(id) on delete restrict,
  producto_id uuid not null references public.productos(id) on delete restrict,
  cantidad numeric(14,3) not null default 0,
  updated_at timestamptz not null default now(),
  primary key (ubicacion_id, producto_id),
  constraint stock_actual_cantidad_valida check (cantidad >= 0 and cantidad <> 'NaN'::numeric)
);
create index stock_actual_producto_idx on public.stock_actual(producto_id);

create table public.stock_movimientos (
  id uuid primary key default gen_random_uuid(),
  ubicacion_id uuid not null references public.ubicaciones_stock(id) on delete restrict,
  producto_id uuid not null references public.productos(id) on delete restrict,
  tipo text not null,
  cantidad_anterior numeric(14,3) not null,
  cantidad_delta numeric(14,3) not null,
  cantidad_nueva numeric(14,3) not null,
  motivo text not null,
  observacion text,
  usuario_id uuid not null references public.usuarios(id) on delete restrict,
  referencia_tipo text,
  referencia_id uuid,
  created_at timestamptz not null default now(),
  constraint stock_movimientos_tipo_valido check (tipo in ('stock_inicial','ajuste_entrada','ajuste_salida')),
  constraint stock_movimientos_cantidades_validas check (
    cantidad_anterior >= 0 and cantidad_anterior <> 'NaN'::numeric
    and cantidad_nueva >= 0 and cantidad_nueva <> 'NaN'::numeric
    and cantidad_delta <> 'NaN'::numeric
  ),
  constraint stock_movimientos_saldo_consistente check (cantidad_anterior + cantidad_delta = cantidad_nueva),
  constraint stock_movimientos_sentido_valido check (
    (tipo = 'stock_inicial' and cantidad_anterior = 0 and cantidad_delta >= 0)
    or (tipo = 'ajuste_entrada' and cantidad_delta > 0)
    or (tipo = 'ajuste_salida' and cantidad_delta < 0)
  ),
  constraint stock_movimientos_motivo_valido check (btrim(motivo) <> '' and char_length(motivo) <= 200),
  constraint stock_movimientos_observacion_valida check (char_length(observacion) <= 2000),
  constraint stock_movimientos_referencia_valida check (
    (referencia_tipo is null and referencia_id is null)
    or (referencia_tipo is not null and btrim(referencia_tipo) <> '' and referencia_id is not null)
  )
);

-- Protección adicional a los bloqueos: una única inicialización por par.
create unique index stock_movimientos_inicial_unico_idx
  on public.stock_movimientos(ubicacion_id, producto_id) where tipo = 'stock_inicial';
create index stock_movimientos_historial_idx
  on public.stock_movimientos(ubicacion_id, producto_id, created_at desc, id);
create index stock_movimientos_producto_idx on public.stock_movimientos(producto_id);
create index stock_movimientos_usuario_idx on public.stock_movimientos(usuario_id);

alter table public.ubicaciones_stock enable row level security;
alter table public.stock_actual enable row level security;
alter table public.stock_movimientos enable row level security;

-- Revocar también los privilegios amplios heredados de ALTER DEFAULT PRIVILEGES.
revoke all on public.ubicaciones_stock, public.stock_actual, public.stock_movimientos
  from public, anon, authenticated, service_role;
grant select on public.ubicaciones_stock, public.stock_actual, public.stock_movimientos to authenticated;
create policy ubicaciones_stock_admin_select on public.ubicaciones_stock
  for select to authenticated using (public.es_administrador());
create policy stock_actual_admin_select on public.stock_actual
  for select to authenticated using (public.es_administrador());
create policy stock_movimientos_admin_select on public.stock_movimientos
  for select to authenticated using (public.es_administrador());

create function public.cargar_stock_inicial(p_ubicacion_id uuid, p_items jsonb)
returns integer
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare
  v_usuario uuid := auth.uid();
  v_item jsonb;
  v_producto uuid;
  v_cantidad numeric;
  v_anterior numeric;
  v_observacion text;
  v_momento timestamptz;
  v_total integer := 0;
begin
  if v_usuario is null or not public.es_administrador() then
    raise exception 'Solo un administrador autenticado puede cargar stock inicial.' using errcode = '42501';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'Los productos deben enviarse como un arreglo JSON.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) not between 1 and 300 then
    raise exception 'La carga debe contener entre 1 y 300 productos.' using errcode = '22023';
  end if;
  perform u.id from public.ubicaciones_stock u where u.id = p_ubicacion_id and u.activo for share;
  if not found then
    raise exception 'La ubicación no existe o está inactiva.' using errcode = '22023';
  end if;

  -- Validar todo antes de escribir; no aceptar redondeos silenciosos ni NaN.
  for v_item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_item) is distinct from 'object'
      or jsonb_typeof(v_item->'producto_id') is distinct from 'string'
      or jsonb_typeof(v_item->'cantidad') is distinct from 'number' then
      raise exception 'Cada producto debe incluir producto_id UUID y cantidad numérica.' using errcode = '22023';
    end if;
    begin
      v_producto := (v_item->>'producto_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'El identificador del producto no es un UUID válido.' using errcode = '22023';
    end;
    v_cantidad := (v_item->>'cantidad')::numeric;
    if v_cantidad::text in ('NaN','Infinity','-Infinity') or v_cantidad < 0
      or v_cantidad > 99999999999.999 or v_cantidad <> round(v_cantidad,3) then
      raise exception 'La cantidad debe ser finita, no negativa y tener como máximo tres decimales.' using errcode = '22023';
    end if;
    if v_item ? 'observacion' and jsonb_typeof(v_item->'observacion') not in ('string','null') then
      raise exception 'La observación debe ser texto.' using errcode = '22023';
    end if;
    if char_length(v_item->>'observacion') > 2000 then
      raise exception 'La observación admite hasta 2000 caracteres.' using errcode = '22023';
    end if;
  end loop;
  if exists (
    select 1 from jsonb_array_elements(p_items) x
    group by (x->>'producto_id')::uuid having count(*) > 1
  ) then
    raise exception 'La carga contiene un producto duplicado.' using errcode = '22023';
  end if;

  -- Orden estable en cargas masivas; los pares compartidos se bloquean igual.
  for v_item in select value from jsonb_array_elements(p_items) order by (value->>'producto_id')::uuid loop
    v_producto := (v_item->>'producto_id')::uuid;
    v_cantidad := (v_item->>'cantidad')::numeric;
    v_observacion := nullif(btrim(v_item->>'observacion'),'');
    perform p.id from public.productos p where p.id = v_producto for key share;
    if not found then
      raise exception 'El producto % no existe.', v_producto using errcode = '22023';
    end if;
    insert into public.stock_actual(ubicacion_id, producto_id, cantidad)
    values (p_ubicacion_id, v_producto, 0)
    on conflict (ubicacion_id, producto_id) do nothing;
    select s.cantidad into v_anterior from public.stock_actual s
      where s.ubicacion_id = p_ubicacion_id and s.producto_id = v_producto for update;
    if exists (select 1 from public.stock_movimientos m
      where m.ubicacion_id = p_ubicacion_id and m.producto_id = v_producto and m.tipo = 'stock_inicial') then
      raise exception 'El producto % ya tiene stock inicial cargado en esta ubicación. Usá Ajustar stock.', v_producto using errcode = '23505';
    end if;
    if v_anterior <> 0 then
      raise exception 'El saldo sin inicialización requiere revisión administrativa.' using errcode = '23514';
    end if;
    v_momento := clock_timestamp();
    update public.stock_actual set cantidad = v_cantidad, updated_at = v_momento
      where ubicacion_id = p_ubicacion_id and producto_id = v_producto;
    insert into public.stock_movimientos(ubicacion_id, producto_id, tipo,
      cantidad_anterior, cantidad_delta, cantidad_nueva, motivo, observacion, usuario_id, created_at)
    values (p_ubicacion_id, v_producto, 'stock_inicial', 0, v_cantidad, v_cantidad,
      'Carga de stock inicial', v_observacion, v_usuario, v_momento);
    v_total := v_total + 1;
  end loop;
  return v_total;
end;
$$;

create function public.ajustar_stock(
  p_ubicacion_id uuid, p_producto_id uuid, p_cantidad_nueva numeric,
  p_motivo text, p_observacion text default null
)
returns uuid
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare
  v_usuario uuid := auth.uid();
  v_anterior numeric;
  v_delta numeric;
  v_movimiento uuid;
  v_momento timestamptz;
begin
  if v_usuario is null or not public.es_administrador() then
    raise exception 'Solo un administrador autenticado puede ajustar stock.' using errcode = '42501';
  end if;
  if p_cantidad_nueva is null or p_cantidad_nueva::text in ('NaN','Infinity','-Infinity')
    or p_cantidad_nueva < 0 or p_cantidad_nueva > 99999999999.999
    or p_cantidad_nueva <> round(p_cantidad_nueva,3) then
    raise exception 'La cantidad debe ser finita, no negativa y tener como máximo tres decimales.' using errcode = '22023';
  end if;
  if p_motivo is null or btrim(p_motivo) = '' or char_length(p_motivo) > 200 then
    raise exception 'El motivo es obligatorio y admite hasta 200 caracteres.' using errcode = '22023';
  end if;
  if char_length(p_observacion) > 2000 then
    raise exception 'La observación admite hasta 2000 caracteres.' using errcode = '22023';
  end if;
  perform u.id from public.ubicaciones_stock u where u.id = p_ubicacion_id and u.activo for share;
  if not found then
    raise exception 'La ubicación no existe o está inactiva.' using errcode = '22023';
  end if;
  perform p.id from public.productos p where p.id = p_producto_id for key share;
  if not found then
    raise exception 'El producto no existe.' using errcode = '22023';
  end if;
  select s.cantidad into v_anterior from public.stock_actual s
    where s.ubicacion_id = p_ubicacion_id and s.producto_id = p_producto_id for update;
  if not found or not exists (select 1 from public.stock_movimientos m
    where m.ubicacion_id = p_ubicacion_id and m.producto_id = p_producto_id and m.tipo = 'stock_inicial') then
    raise exception 'El producto todavía no tiene stock inicial cargado.' using errcode = '22023';
  end if;
  v_delta := p_cantidad_nueva - v_anterior;
  if v_delta = 0 then
    raise exception 'La nueva cantidad coincide con el stock actual; no hay un ajuste para registrar.' using errcode = '22023';
  end if;
  v_momento := clock_timestamp();
  update public.stock_actual set cantidad = p_cantidad_nueva, updated_at = v_momento
    where ubicacion_id = p_ubicacion_id and producto_id = p_producto_id;
  insert into public.stock_movimientos(ubicacion_id, producto_id, tipo,
    cantidad_anterior, cantidad_delta, cantidad_nueva, motivo, observacion, usuario_id, created_at)
  values (p_ubicacion_id, p_producto_id,
    case when v_delta > 0 then 'ajuste_entrada' else 'ajuste_salida' end,
    v_anterior, v_delta, p_cantidad_nueva, btrim(p_motivo), nullif(btrim(p_observacion),''), v_usuario, v_momento)
  returning id into v_movimiento;
  return v_movimiento;
end;
$$;

create function public.consultar_stock(p_ubicacion_id uuid)
returns table (
  producto_id uuid, nombre text, codigo text, activo boolean, costo_actual numeric,
  ubicacion_id uuid, ubicacion_codigo text, ubicacion_nombre text,
  cantidad numeric, inicializado boolean, valor_stock numeric
)
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null or not public.es_administrador() then
    raise exception 'Solo un administrador autenticado puede consultar stock.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.ubicaciones_stock u where u.id = p_ubicacion_id) then
    raise exception 'La ubicación no existe.' using errcode = '22023';
  end if;
  return query
    select p.id, p.nombre, p.codigo, p.activo, p.costo,
      u.id, u.codigo, u.nombre, coalesce(s.cantidad,0), m.id is not null,
      coalesce(s.cantidad,0) * p.costo
    from public.productos p
    cross join public.ubicaciones_stock u
    left join public.stock_actual s on s.producto_id = p.id and s.ubicacion_id = u.id
    left join public.stock_movimientos m on m.producto_id = p.id and m.ubicacion_id = u.id and m.tipo = 'stock_inicial'
    where u.id = p_ubicacion_id
    order by p.nombre, p.id;
end;
$$;
comment on function public.consultar_stock(uuid) is
  'Administración: valor_stock es valor estimado a costo actual; no costo histórico, promedio ni FIFO.';

create function public.resumen_stock(p_ubicacion_id uuid)
returns table (productos_distintos bigint, unidades_totales numeric, valor_estimado_total numeric)
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null or not public.es_administrador() then
    raise exception 'Solo un administrador autenticado puede consultar el resumen de stock.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.ubicaciones_stock u where u.id = p_ubicacion_id) then
    raise exception 'La ubicación no existe.' using errcode = '22023';
  end if;
  return query
    select count(*), coalesce(sum(s.cantidad),0), coalesce(sum(s.cantidad * p.costo),0)
    from public.stock_movimientos m
    join public.stock_actual s on s.ubicacion_id = m.ubicacion_id and s.producto_id = m.producto_id
    join public.productos p on p.id = m.producto_id
    where m.ubicacion_id = p_ubicacion_id and m.tipo = 'stock_inicial';
end;
$$;
comment on function public.resumen_stock(uuid) is
  'Incluye productos inicializados con saldo cero. Valor estimado total a costo actual.';

revoke all on function public.cargar_stock_inicial(uuid,jsonb),
  public.ajustar_stock(uuid,uuid,numeric,text,text), public.consultar_stock(uuid), public.resumen_stock(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.cargar_stock_inicial(uuid,jsonb),
  public.ajustar_stock(uuid,uuid,numeric,text,text), public.consultar_stock(uuid), public.resumen_stock(uuid)
  to authenticated;

notify pgrst, 'reload schema';
commit;
