-- Stock por producto: depósito + vehículo, viajes, compras y conteos (etapa 1).
--
-- Reglas del negocio (16/11/2026):
--  * El stock INFORMA, no traba: ninguna entrega o venta se rechaza por falta de stock. Puede
--    quedar en negativo y aparece como diferencia para revisar.
--  * Cada producto es "con stock" (control_stock) o "a pedido". Se pasa a "con stock" al contarlo:
--    se enciende de a poco, sin inventario completo. Los "a pedido" nunca mueven stock.
--  * Las entregas y ventas directas descuentan del VEHÍCULO. Un viaje se abre al cargar el
--    vehículo y se cierra contando lo que sobró.
--  * Un conteo vale para su momento: una entrega hecha antes del conteo (enviada después, sin
--    señal) no se vuelve a descontar (stock_actual.contado_at).
-- El régimen global ON/OFF del Stock V2 queda sin uso (siempre OFF): el control es por producto.

-- 1. Productos con stock y momento del último conteo por ubicación.
alter table public.productos add column control_stock boolean not null default false;
alter table public.stock_actual add column contado_at timestamptz;
grant select (control_stock) on public.productos to authenticated;

-- 2. Vehículo (la configuración sigue siendo una sola, la del depósito).
insert into public.ubicaciones_stock(codigo, nombre) values ('vehiculo', 'Vehículo')
on conflict (codigo) do nothing;

-- Los eventos (entregas) también pueden ser del vehículo.
alter table public.stock_eventos drop constraint stock_eventos_ubicacion_id_fkey,
 add constraint stock_eventos_ubicacion_id_fkey foreign key (ubicacion_id)
 references public.ubicaciones_stock(id) on delete restrict;

-- 3. Negativos permitidos y movimientos nuevos (transferencias y compras).
alter table public.stock_actual drop constraint stock_actual_cantidad_valida,
 add constraint stock_actual_cantidad_valida check (cantidad <> 'NaN'::numeric);
alter table public.stock_movimientos
 drop constraint stock_movimientos_cantidades_validas,
 drop constraint stock_movimientos_tipo_valido,
 drop constraint stock_movimientos_evento_obligatorio,
 drop constraint stock_movimientos_sentido_valido,
 add constraint stock_movimientos_cantidades_validas check (cantidad_anterior <> 'NaN'::numeric
  and cantidad_nueva <> 'NaN'::numeric and cantidad_delta <> 'NaN'::numeric),
 add constraint stock_movimientos_tipo_valido check (tipo = any (array['stock_inicial','ajuste_entrada',
  'ajuste_salida','entrega','venta_directa','correccion_entrada','correccion_salida','devolucion_apta',
  'transferencia_entrada','transferencia_salida','compra'])),
 add constraint stock_movimientos_evento_obligatorio check (
  (tipo = any (array['stock_inicial','ajuste_entrada','ajuste_salida','transferencia_entrada',
   'transferencia_salida','compra']) and evento_id is null)
  or (tipo = any (array['entrega','venta_directa','correccion_entrada','correccion_salida','devolucion_apta'])
   and evento_id is not null and referencia_tipo = 'stock_evento' and referencia_id = evento_id)),
 add constraint stock_movimientos_sentido_valido check (
  (tipo = 'stock_inicial' and cantidad_anterior = 0 and cantidad_delta >= 0)
  or (tipo = any (array['ajuste_entrada','correccion_entrada','devolucion_apta','transferencia_entrada','compra'])
   and cantidad_delta > 0)
  or (tipo = any (array['ajuste_salida','entrega','venta_directa','correccion_salida','transferencia_salida'])
   and cantidad_delta < 0));

-- 4. Viajes del vehículo: uno abierto a la vez.
create table public.viajes_vehiculo (
 id uuid primary key default gen_random_uuid(),
 ubicacion_id uuid not null references public.ubicaciones_stock(id),
 estado text not null default 'abierto' check (estado in ('abierto','cerrado')),
 preventista_id uuid references public.usuarios(id),
 abierto_por uuid not null references public.usuarios(id),
 abierto_at timestamptz not null default clock_timestamp(),
 cerrado_por uuid references public.usuarios(id),
 cerrado_at timestamptz,
 resumen jsonb,
 check ((estado = 'abierto') = (cerrado_at is null))
);
create unique index viajes_vehiculo_uno_abierto on public.viajes_vehiculo(ubicacion_id) where estado = 'abierto';
alter table public.viajes_vehiculo enable row level security;
create policy viajes_vehiculo_admin_select on public.viajes_vehiculo for select to authenticated
 using (public.es_administrador());
revoke all on public.viajes_vehiculo from anon, authenticated;
grant select on public.viajes_vehiculo to authenticated;

alter table public.pedidos add column viaje_id uuid references public.viajes_vehiculo(id);
create index pedidos_viaje_idx on public.pedidos(viaje_id) where viaje_id is not null;

-- Toda venta directa hecha con un viaje abierto queda en ese viaje.
create function public.asignar_viaje_venta_directa() returns trigger
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
 if new.tipo_operacion = 'venta_directa' and new.viaje_id is null then
  select v.id into new.viaje_id from public.viajes_vehiculo v where v.estado = 'abierto'
  order by v.abierto_at desc limit 1;
 end if;
 return new;
end $$;
revoke all on function public.asignar_viaje_venta_directa() from public, anon, authenticated;
create trigger b_asignar_viaje_venta_directa before insert on public.pedidos
 for each row execute function public.asignar_viaje_venta_directa();

-- 5. Operaciones de stock hechas desde la app (id elegido por el teléfono: reenviar no duplica).
create table public.stock_operaciones (
 id uuid primary key,
 tipo text not null check (tipo in ('conteo','carga_vehiculo','baja_vehiculo','compra','cierre_viaje')),
 ubicacion_id uuid references public.ubicaciones_stock(id),
 viaje_id uuid references public.viajes_vehiculo(id),
 proveedor text check (char_length(proveedor) <= 200),
 observacion text check (char_length(observacion) <= 2000),
 fecha_fisica timestamptz not null check (isfinite(fecha_fisica)),
 actor_id uuid not null references public.usuarios(id),
 request_hash text not null,
 resultado jsonb not null,
 created_at timestamptz not null default clock_timestamp()
);
create table public.stock_operacion_items (
 operacion_id uuid not null references public.stock_operaciones(id),
 producto_id uuid not null references public.productos(id),
 cantidad numeric not null check (cantidad >= 0 and cantidad <> 'NaN'::numeric and cantidad <= 99999999),
 costo_unitario numeric check (costo_unitario is null or (costo_unitario >= 0 and costo_unitario <> 'NaN'::numeric)),
 controlado boolean not null,
 primary key (operacion_id, producto_id)
);
create index stock_operaciones_fecha_idx on public.stock_operaciones(tipo, fecha_fisica desc);
alter table public.stock_operaciones enable row level security;
alter table public.stock_operacion_items enable row level security;
create policy stock_operaciones_admin_select on public.stock_operaciones for select to authenticated
 using (public.es_administrador());
create policy stock_operacion_items_admin_select on public.stock_operacion_items for select to authenticated
 using (public.es_administrador());
revoke all on public.stock_operaciones, public.stock_operacion_items from anon, authenticated;
grant select on public.stock_operaciones, public.stock_operacion_items to authenticated;

-- 6. Ayudantes internos.
create function public.stock_ubicacion(p_codigo text) returns uuid
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
 select id from public.ubicaciones_stock where codigo = p_codigo and activo
$$;

-- Fecha del momento real (hora del teléfono): hasta 72 h atrás y nunca en el futuro.
create function public.stock_validar_fecha(p_fecha timestamptz) returns timestamptz
language plpgsql stable set search_path = pg_catalog, public, pg_temp as $$
begin
 if p_fecha is null or not isfinite(p_fecha) or p_fecha > clock_timestamp() + interval '5 minutes' then
  raise exception 'Fecha inválida o en el futuro' using errcode = 'PT422'; end if;
 if p_fecha < clock_timestamp() - interval '72 hours' then
  raise exception 'La operación tiene más de 72 horas: cargala de nuevo' using errcode = 'PT422'; end if;
 return least(p_fecha, clock_timestamp());
end $$;

-- Valida y ordena la lista [{producto_id, cantidad, costo_unitario?}].
create function public.stock_items(p_items jsonb, p_positivas boolean)
returns table(producto_id uuid, cantidad numeric, costo numeric)
language plpgsql stable set search_path = pg_catalog, public, pg_temp as $$
begin
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 400 then
  raise exception 'La lista de productos debe tener entre 1 y 400 productos' using errcode = 'PT422'; end if;
 if exists (select 1 from jsonb_array_elements(p_items) x where jsonb_typeof(x) <> 'object'
   or jsonb_typeof(x->'producto_id') is distinct from 'string'
   or x->>'producto_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   or jsonb_typeof(x->'cantidad') is distinct from 'number'
   or coalesce(jsonb_typeof(x->'costo_unitario'), 'null') not in ('number', 'null')) then
  raise exception 'Producto o cantidad inválidos' using errcode = 'PT422'; end if;
 if exists (select 1 from jsonb_array_elements(p_items) x where (x->>'cantidad')::numeric < 0
   or (x->>'cantidad')::numeric > 99999999 or (x->>'cantidad')::numeric <> round((x->>'cantidad')::numeric, 3)
   or (p_positivas and (x->>'cantidad')::numeric = 0)
   or (x->>'costo_unitario')::numeric < 0 or (x->>'costo_unitario')::numeric > 999999999) then
  raise exception 'Cantidad o costo fuera de rango' using errcode = 'PT422'; end if;
 if exists (select 1 from jsonb_array_elements(p_items) x group by x->>'producto_id' having count(*) > 1) then
  raise exception 'Un producto está repetido en la lista' using errcode = 'PT422'; end if;
 if exists (select 1 from jsonb_array_elements(p_items) x
   where not exists (select 1 from public.productos p where p.id = (x->>'producto_id')::uuid)) then
  raise exception 'Producto inexistente' using errcode = 'PT404'; end if;
 return query select (x->>'producto_id')::uuid, (x->>'cantidad')::numeric, (x->>'costo_unitario')::numeric
  from jsonb_array_elements(p_items) x order by 1;
end $$;

-- Reenvío de la misma operación: devuelve lo que ya se hizo (no duplica).
create function public.stock_operacion_previa(p_id uuid, p_tipo text, p_hash text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare op public.stock_operaciones;
begin
 if p_id is null then raise exception 'Falta el identificador de la operación' using errcode = 'PT422'; end if;
 select * into op from public.stock_operaciones where id = p_id;
 if not found then return null; end if;
 if op.tipo <> p_tipo or op.actor_id is distinct from auth.uid() or op.request_hash <> p_hash then
  raise exception 'Operación repetida con otros datos' using errcode = 'PT409'; end if;
 return op.resultado;
end $$;

-- Suma o resta stock (crea la fila si falta). Permite negativos.
create function public.stock_mover(p_ubicacion uuid, p_producto uuid, p_delta numeric, p_tipo text,
 p_motivo text, p_operacion uuid) returns numeric
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare anterior numeric;
begin
 if p_delta = 0 then return null; end if;
 insert into public.stock_actual(ubicacion_id, producto_id, cantidad) values (p_ubicacion, p_producto, 0)
 on conflict (ubicacion_id, producto_id) do nothing;
 select s.cantidad into anterior from public.stock_actual s
 where s.ubicacion_id = p_ubicacion and s.producto_id = p_producto for update;
 update public.stock_actual set cantidad = anterior + p_delta, updated_at = clock_timestamp()
 where ubicacion_id = p_ubicacion and producto_id = p_producto;
 insert into public.stock_movimientos(ubicacion_id, producto_id, tipo, cantidad_anterior, cantidad_delta,
  cantidad_nueva, motivo, usuario_id, referencia_tipo, referencia_id)
 values (p_ubicacion, p_producto, p_tipo, anterior, p_delta, anterior + p_delta, p_motivo, auth.uid(),
  'stock_operacion', p_operacion);
 return anterior + p_delta;
end $$;

-- Deja la cantidad contada y anota el momento del conteo. Devuelve lo que había antes.
create function public.stock_fijar(p_ubicacion uuid, p_producto uuid, p_cantidad numeric, p_motivo text,
 p_operacion uuid, p_fecha timestamptz) returns numeric
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare anterior numeric; delta numeric;
begin
 insert into public.stock_actual(ubicacion_id, producto_id, cantidad) values (p_ubicacion, p_producto, 0)
 on conflict (ubicacion_id, producto_id) do nothing;
 select s.cantidad into anterior from public.stock_actual s
 where s.ubicacion_id = p_ubicacion and s.producto_id = p_producto for update;
 delta := p_cantidad - anterior;
 if anterior = 0 and not exists (select 1 from public.stock_movimientos m
   where m.ubicacion_id = p_ubicacion and m.producto_id = p_producto) then
  insert into public.stock_movimientos(ubicacion_id, producto_id, tipo, cantidad_anterior, cantidad_delta,
   cantidad_nueva, motivo, usuario_id, referencia_tipo, referencia_id)
  values (p_ubicacion, p_producto, 'stock_inicial', 0, p_cantidad, p_cantidad, p_motivo, auth.uid(),
   'stock_operacion', p_operacion);
 elsif delta <> 0 then
  insert into public.stock_movimientos(ubicacion_id, producto_id, tipo, cantidad_anterior, cantidad_delta,
   cantidad_nueva, motivo, usuario_id, referencia_tipo, referencia_id)
  values (p_ubicacion, p_producto, case when delta > 0 then 'ajuste_entrada' else 'ajuste_salida' end,
   anterior, delta, p_cantidad, p_motivo, auth.uid(), 'stock_operacion', p_operacion);
 end if;
 update public.stock_actual set cantidad = p_cantidad, contado_at = p_fecha, updated_at = clock_timestamp()
 where ubicacion_id = p_ubicacion and producto_id = p_producto;
 return anterior;
end $$;

revoke all on function public.stock_ubicacion(text), public.stock_validar_fecha(timestamptz),
 public.stock_items(jsonb, boolean), public.stock_operacion_previa(uuid, text, text),
 public.stock_mover(uuid, uuid, numeric, text, text, uuid),
 public.stock_fijar(uuid, uuid, numeric, text, uuid, timestamptz) from public, anon, authenticated;

create function public.stock_huella(p jsonb) returns text language sql immutable as $$
 select encode(sha256(convert_to(p::text, 'UTF8')), 'hex') $$;
revoke all on function public.stock_huella(jsonb) from public, anon, authenticated;

-- 7. Operaciones (solo administración).

-- Conteo: deja la cantidad contada; el producto pasa a "con stock".
create function public.stock_contar(p_id uuid, p_ubicacion text, p_items jsonb, p_fecha timestamptz,
 p_observacion text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare huella text; previo jsonb; loc uuid; fecha timestamptz; it record; antes numeric;
 control boolean; nuevos integer := 0; difs jsonb := '[]'; res jsonb;
begin
 perform public.stock_exigir_admin(); perform public.stock_exigir_operativo();
 huella := public.stock_huella(jsonb_build_object('u', p_ubicacion, 'i', p_items, 'f', p_fecha, 'o', p_observacion));
 previo := public.stock_operacion_previa(p_id, 'conteo', huella);
 if previo is not null then return previo; end if;
 loc := public.stock_ubicacion(p_ubicacion);
 if loc is null then raise exception 'Ubicación inválida' using errcode = 'PT422'; end if;
 fecha := public.stock_validar_fecha(p_fecha);
 insert into public.stock_operaciones(id, tipo, ubicacion_id, observacion, fecha_fisica, actor_id, request_hash, resultado)
 values (p_id, 'conteo', loc, nullif(btrim(p_observacion), ''), fecha, auth.uid(), huella, '{}');
 for it in select * from public.stock_items(p_items, false) loop
  select p.control_stock into control from public.productos p where p.id = it.producto_id for update;
  if not control then
   update public.productos set control_stock = true where id = it.producto_id;
   nuevos := nuevos + 1;
  end if;
  antes := public.stock_fijar(loc, it.producto_id, it.cantidad, 'Conteo', p_id, fecha);
  if control and antes <> it.cantidad then
   difs := difs || jsonb_build_object('producto_id', it.producto_id, 'antes', antes, 'contado', it.cantidad);
  end if;
  insert into public.stock_operacion_items(operacion_id, producto_id, cantidad, controlado)
  values (p_id, it.producto_id, it.cantidad, true);
 end loop;
 res := jsonb_build_object('operacion_id', p_id, 'productos', jsonb_array_length(p_items),
  'nuevos_con_stock', nuevos, 'diferencias', difs);
 update public.stock_operaciones set resultado = res where id = p_id;
 return res;
end $$;

-- El producto vuelve a "a pedido": deja de mover stock (el historial queda).
create function public.stock_marcar_a_pedido(p_producto_id uuid) returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
 perform public.stock_exigir_admin(); perform public.stock_exigir_operativo();
 update public.productos set control_stock = false where id = p_producto_id and control_stock;
end $$;

-- Cargar el vehículo desde el depósito. Abre el viaje si no hay uno abierto.
create function public.stock_cargar_vehiculo(p_id uuid, p_items jsonb, p_fecha timestamptz,
 p_preventista_id uuid default null, p_observacion text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare huella text; previo jsonb; dep uuid; veh uuid; fecha timestamptz; it record; control boolean;
 viaje public.viajes_vehiculo; nuevo boolean := false; movidos integer := 0; a_pedido integer := 0; res jsonb;
begin
 perform public.stock_exigir_admin(); perform public.stock_exigir_operativo();
 huella := public.stock_huella(jsonb_build_object('i', p_items, 'f', p_fecha, 'p', p_preventista_id, 'o', p_observacion));
 previo := public.stock_operacion_previa(p_id, 'carga_vehiculo', huella);
 if previo is not null then return previo; end if;
 dep := public.stock_ubicacion('deposito_alberdi'); veh := public.stock_ubicacion('vehiculo');
 fecha := public.stock_validar_fecha(p_fecha);
 if p_preventista_id is not null and not exists (select 1 from public.usuarios u where u.id = p_preventista_id
   and u.activo and u.rol in ('preventista', 'administrador')) then
  raise exception 'Preventista inválido' using errcode = 'PT422'; end if;
 select * into viaje from public.viajes_vehiculo where ubicacion_id = veh and estado = 'abierto' for update;
 if not found then
  insert into public.viajes_vehiculo(ubicacion_id, preventista_id, abierto_por, abierto_at)
  values (veh, p_preventista_id, auth.uid(), fecha) returning * into viaje;
  nuevo := true;
 elsif p_preventista_id is not null and viaje.preventista_id is null then
  update public.viajes_vehiculo set preventista_id = p_preventista_id where id = viaje.id;
 end if;
 insert into public.stock_operaciones(id, tipo, ubicacion_id, viaje_id, observacion, fecha_fisica, actor_id, request_hash, resultado)
 values (p_id, 'carga_vehiculo', veh, viaje.id, nullif(btrim(p_observacion), ''), fecha, auth.uid(), huella, '{}');
 for it in select * from public.stock_items(p_items, true) loop
  select p.control_stock into control from public.productos p where p.id = it.producto_id for key share;
  if control then
   perform public.stock_mover(dep, it.producto_id, -it.cantidad, 'transferencia_salida', 'Carga del vehículo', p_id);
   perform public.stock_mover(veh, it.producto_id, it.cantidad, 'transferencia_entrada', 'Carga del vehículo', p_id);
   movidos := movidos + 1;
  else
   a_pedido := a_pedido + 1;
  end if;
  insert into public.stock_operacion_items(operacion_id, producto_id, cantidad, controlado)
  values (p_id, it.producto_id, it.cantidad, control);
 end loop;
 res := jsonb_build_object('operacion_id', p_id, 'viaje_id', viaje.id, 'viaje_nuevo', nuevo,
  'movidos', movidos, 'a_pedido', a_pedido);
 update public.stock_operaciones set resultado = res where id = p_id;
 return res;
end $$;

-- Bajar del vehículo al depósito.
create function public.stock_bajar_vehiculo(p_id uuid, p_items jsonb, p_fecha timestamptz,
 p_observacion text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare huella text; previo jsonb; dep uuid; veh uuid; fecha timestamptz; it record; control boolean;
 viaje uuid; movidos integer := 0; res jsonb;
begin
 perform public.stock_exigir_admin(); perform public.stock_exigir_operativo();
 huella := public.stock_huella(jsonb_build_object('i', p_items, 'f', p_fecha, 'o', p_observacion));
 previo := public.stock_operacion_previa(p_id, 'baja_vehiculo', huella);
 if previo is not null then return previo; end if;
 dep := public.stock_ubicacion('deposito_alberdi'); veh := public.stock_ubicacion('vehiculo');
 fecha := public.stock_validar_fecha(p_fecha);
 select id into viaje from public.viajes_vehiculo where ubicacion_id = veh and estado = 'abierto';
 insert into public.stock_operaciones(id, tipo, ubicacion_id, viaje_id, observacion, fecha_fisica, actor_id, request_hash, resultado)
 values (p_id, 'baja_vehiculo', veh, viaje, nullif(btrim(p_observacion), ''), fecha, auth.uid(), huella, '{}');
 for it in select * from public.stock_items(p_items, true) loop
  select p.control_stock into control from public.productos p where p.id = it.producto_id for key share;
  if control then
   perform public.stock_mover(veh, it.producto_id, -it.cantidad, 'transferencia_salida', 'Bajada al depósito', p_id);
   perform public.stock_mover(dep, it.producto_id, it.cantidad, 'transferencia_entrada', 'Bajada al depósito', p_id);
   movidos := movidos + 1;
  end if;
  insert into public.stock_operacion_items(operacion_id, producto_id, cantidad, controlado)
  values (p_id, it.producto_id, it.cantidad, control);
 end loop;
 res := jsonb_build_object('operacion_id', p_id, 'movidos', movidos);
 update public.stock_operaciones set resultado = res where id = p_id;
 return res;
end $$;

-- Compra de mercadería (a proveedor o en el camino). Los "a pedido" solo dejan el costo.
create function public.stock_registrar_compra(p_id uuid, p_ubicacion text, p_items jsonb, p_fecha timestamptz,
 p_proveedor text default null, p_actualizar_costo boolean default false, p_observacion text default null)
returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare huella text; previo jsonb; loc uuid; veh uuid; fecha timestamptz; it record; control boolean;
 viaje uuid; con_stock integer := 0; a_pedido integer := 0; total numeric := 0; res jsonb;
begin
 perform public.stock_exigir_admin(); perform public.stock_exigir_operativo();
 huella := public.stock_huella(jsonb_build_object('u', p_ubicacion, 'i', p_items, 'f', p_fecha,
  'p', p_proveedor, 'c', p_actualizar_costo, 'o', p_observacion));
 previo := public.stock_operacion_previa(p_id, 'compra', huella);
 if previo is not null then return previo; end if;
 loc := public.stock_ubicacion(p_ubicacion); veh := public.stock_ubicacion('vehiculo');
 if loc is null then raise exception 'Ubicación inválida' using errcode = 'PT422'; end if;
 fecha := public.stock_validar_fecha(p_fecha);
 if loc = veh then
  select id into viaje from public.viajes_vehiculo where ubicacion_id = veh and estado = 'abierto';
 end if;
 insert into public.stock_operaciones(id, tipo, ubicacion_id, viaje_id, proveedor, observacion, fecha_fisica,
  actor_id, request_hash, resultado)
 values (p_id, 'compra', loc, viaje, nullif(btrim(p_proveedor), ''), nullif(btrim(p_observacion), ''), fecha,
  auth.uid(), huella, '{}');
 for it in select * from public.stock_items(p_items, true) loop
  select p.control_stock into control from public.productos p where p.id = it.producto_id for update;
  if control then
   perform public.stock_mover(loc, it.producto_id, it.cantidad, 'compra',
    left(coalesce('Compra · ' || nullif(btrim(p_proveedor), ''), 'Compra'), 200), p_id);
   con_stock := con_stock + 1;
  else
   a_pedido := a_pedido + 1;
  end if;
  if p_actualizar_costo and it.costo > 0 then
   update public.productos set costo = it.costo where id = it.producto_id;
  end if;
  total := total + it.cantidad * coalesce(it.costo, 0);
  insert into public.stock_operacion_items(operacion_id, producto_id, cantidad, costo_unitario, controlado)
  values (p_id, it.producto_id, it.cantidad, it.costo, control);
 end loop;
 res := jsonb_build_object('operacion_id', p_id, 'total', round(total, 2), 'con_stock', con_stock, 'a_pedido', a_pedido);
 update public.stock_operaciones set resultado = res where id = p_id;
 return res;
end $$;

-- Cerrar el viaje: contar lo que sobró (opcional), ver diferencias y bajar al depósito (opcional).
create function public.stock_cerrar_viaje(p_id uuid, p_viaje_id uuid, p_conteo jsonb, p_bajar boolean,
 p_fecha timestamptz, p_observacion text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare huella text; previo jsonb; dep uuid; veh uuid; fecha timestamptz; it record; control boolean;
 viaje public.viajes_vehiculo; antes numeric; difs jsonb := '[]'; faltan text; bajados integer := 0;
 s record; ventas integer; total_ventas numeric; pendientes integer; res jsonb;
begin
 perform public.stock_exigir_admin(); perform public.stock_exigir_operativo();
 huella := public.stock_huella(jsonb_build_object('v', p_viaje_id, 'c', p_conteo, 'b', p_bajar, 'f', p_fecha, 'o', p_observacion));
 previo := public.stock_operacion_previa(p_id, 'cierre_viaje', huella);
 if previo is not null then return previo; end if;
 dep := public.stock_ubicacion('deposito_alberdi'); veh := public.stock_ubicacion('vehiculo');
 fecha := public.stock_validar_fecha(p_fecha);
 select * into viaje from public.viajes_vehiculo where id = p_viaje_id for update;
 if not found then raise exception 'Viaje inexistente' using errcode = 'PT404'; end if;
 if viaje.estado <> 'abierto' then raise exception 'El viaje ya está cerrado' using errcode = 'PT409'; end if;
 insert into public.stock_operaciones(id, tipo, ubicacion_id, viaje_id, observacion, fecha_fisica, actor_id, request_hash, resultado)
 values (p_id, 'cierre_viaje', veh, viaje.id, nullif(btrim(p_observacion), ''), fecha, auth.uid(), huella, '{}');
 if p_conteo is not null then
  perform 1 from public.stock_items(p_conteo, false);
  -- El conteo tiene que incluir todo lo que figura arriba (con stock).
  select string_agg(p.nombre, ', ' order by p.nombre) into faltan
  from public.stock_actual sa join public.productos p on p.id = sa.producto_id
  where sa.ubicacion_id = veh and p.control_stock and sa.cantidad <> 0
   and not exists (select 1 from jsonb_array_elements(p_conteo) x where (x->>'producto_id')::uuid = sa.producto_id);
  if faltan is not null then
   raise exception 'Falta contar: %', faltan using errcode = 'PT422'; end if;
  for it in select * from public.stock_items(p_conteo, false) loop
   select p.control_stock into control from public.productos p where p.id = it.producto_id for key share;
   if control then
    antes := public.stock_fijar(veh, it.producto_id, it.cantidad, 'Cierre de viaje', p_id, fecha);
    if antes <> it.cantidad then
     difs := difs || jsonb_build_object('producto_id', it.producto_id,
      'nombre', (select nombre from public.productos where id = it.producto_id),
      'esperado', antes, 'contado', it.cantidad, 'diferencia', it.cantidad - antes);
    end if;
   end if;
   insert into public.stock_operacion_items(operacion_id, producto_id, cantidad, controlado)
   values (p_id, it.producto_id, it.cantidad, control);
  end loop;
 end if;
 if p_bajar then
  for s in select sa.producto_id, sa.cantidad from public.stock_actual sa join public.productos p on p.id = sa.producto_id
   where sa.ubicacion_id = veh and p.control_stock and sa.cantidad > 0 order by sa.producto_id loop
   perform public.stock_mover(veh, s.producto_id, -s.cantidad, 'transferencia_salida', 'Bajada al depósito (cierre de viaje)', p_id);
   perform public.stock_mover(dep, s.producto_id, s.cantidad, 'transferencia_entrada', 'Bajada al depósito (cierre de viaje)', p_id);
   bajados := bajados + 1;
  end loop;
 end if;
 select count(*), coalesce(sum(total), 0), count(*) filter (where resultado_entrega = 'pendiente')
 into ventas, total_ventas, pendientes
 from public.pedidos where viaje_id = viaje.id and estado not in ('anulado', 'cancelado');
 res := jsonb_build_object('operacion_id', p_id, 'viaje_id', viaje.id, 'contado', p_conteo is not null,
  'diferencias', difs, 'bajados', bajados, 'ventas', ventas, 'total_ventas', total_ventas,
  'pendientes_de_entrega', pendientes);
 update public.viajes_vehiculo set estado = 'cerrado', cerrado_por = auth.uid(),
  cerrado_at = greatest(fecha, viaje.abierto_at), resumen = res where id = viaje.id;
 update public.stock_operaciones set resultado = res where id = p_id;
 return res;
end $$;

-- 8. Consultas.

-- Lo que lleva el vehículo: lo ve el preventista para ofrecer. "Comprometido" son las ventas
-- directas del viaje todavía sin entregar. Se puede pedir por GET (queda en la copia sin señal).
create function public.stock_vehiculo_disponible() returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare veh uuid; viaje public.viajes_vehiculo; productos jsonb;
begin
 if public.es_personal_activo() is not true then
  raise exception 'Solo personal activo' using errcode = 'PT403'; end if;
 veh := public.stock_ubicacion('vehiculo');
 select * into viaje from public.viajes_vehiculo where ubicacion_id = veh and estado = 'abierto';
 select coalesce(jsonb_agg(jsonb_build_object('producto_id', t.producto_id, 'en_vehiculo', t.en_vehiculo,
   'comprometido', t.comprometido, 'disponible', t.en_vehiculo - t.comprometido) order by t.nombre), '[]')
 into productos
 from (
  select p.id producto_id, p.nombre, coalesce(sa.cantidad, 0) en_vehiculo,
   coalesce((select sum(d.cantidad) from public.pedido_detalles d join public.pedidos pe on pe.id = d.pedido_id
    where d.producto_id = p.id and viaje.id is not null and pe.viaje_id = viaje.id
     and pe.tipo_operacion = 'venta_directa' and pe.resultado_entrega = 'pendiente'
     and pe.estado not in ('anulado', 'cancelado')), 0) comprometido
  from public.productos p
  left join public.stock_actual sa on sa.producto_id = p.id and sa.ubicacion_id = veh
  where p.activo and p.control_stock
 ) t where t.en_vehiculo <> 0 or t.comprometido <> 0;
 return jsonb_build_object('viaje', case when viaje.id is null then null else jsonb_build_object(
   'id', viaje.id, 'preventista_id', viaje.preventista_id, 'abierto_at', viaje.abierto_at) end,
  'consultado_at', now(), 'productos', productos);
end $$;

-- Estado de todos los productos (pantalla de stock del administrador).
create function public.stock_estado() returns table(producto_id uuid, control_stock boolean,
 deposito numeric, vehiculo numeric, deposito_contado_at timestamptz, vehiculo_contado_at timestamptz)
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare dep uuid := public.stock_ubicacion('deposito_alberdi'); veh uuid := public.stock_ubicacion('vehiculo');
begin
 perform public.stock_exigir_admin();
 return query select p.id, p.control_stock, d.cantidad, v.cantidad, d.contado_at, v.contado_at
 from public.productos p
 left join public.stock_actual d on d.producto_id = p.id and d.ubicacion_id = dep
 left join public.stock_actual v on v.producto_id = p.id and v.ubicacion_id = veh
 where p.activo order by p.nombre;
end $$;

revoke all on function public.stock_contar(uuid, text, jsonb, timestamptz, text),
 public.stock_marcar_a_pedido(uuid),
 public.stock_cargar_vehiculo(uuid, jsonb, timestamptz, uuid, text),
 public.stock_bajar_vehiculo(uuid, jsonb, timestamptz, text),
 public.stock_registrar_compra(uuid, text, jsonb, timestamptz, text, boolean, text),
 public.stock_cerrar_viaje(uuid, uuid, jsonb, boolean, timestamptz, text),
 public.stock_vehiculo_disponible(), public.stock_estado() from public, anon;
grant execute on function public.stock_contar(uuid, text, jsonb, timestamptz, text),
 public.stock_marcar_a_pedido(uuid),
 public.stock_cargar_vehiculo(uuid, jsonb, timestamptz, uuid, text),
 public.stock_bajar_vehiculo(uuid, jsonb, timestamptz, text),
 public.stock_registrar_compra(uuid, text, jsonb, timestamptz, text, boolean, text),
 public.stock_cerrar_viaje(uuid, uuid, jsonb, boolean, timestamptz, text),
 public.stock_vehiculo_disponible(), public.stock_estado() to authenticated;

-- 9. Entregas y ventas: solo los productos "con stock", sin trabar nunca (puede quedar negativo).
-- Si el producto se contó después del momento real de la entrega, el conteo ya la incluye.
create or replace function public.stock_base_stock_aplicar_deltas(p_ubicacion_id uuid, p_evento_id uuid, p_items jsonb)
 returns integer
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare evento public.stock_eventos; contenido jsonb; x jsonb; fila public.stock_actual; nueva numeric;
 producto uuid; delta numeric; controla boolean; aplicados integer := 0; existente integer;
begin
 if auth.uid() is null or public.es_administrador() is not true then
  raise exception 'Solo administración activa' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(829001);
 perform 1 from public.ubicaciones_stock where id=p_ubicacion_id and activo for share;
 if not found then raise exception 'Ubicación inactiva o inexistente' using errcode='PT410'; end if;
 select * into evento from public.stock_eventos where id=p_evento_id for update;
 if not found or evento.ubicacion_id is distinct from p_ubicacion_id or evento.actor_id is distinct from auth.uid() then
  raise exception 'Evento incompatible' using errcode='PT409'; end if;
 contenido:=public.stock_normalizar_solicitud(jsonb_build_object('items',p_items,
  'motivo',evento.solicitud->'contenido'->>'motivo','observacion',evento.solicitud->'contenido'->>'observacion'));
 if contenido is distinct from evento.solicitud->'contenido' then
  raise exception 'Evento duplicado incompatible' using errcode='PT409'; end if;
 select count(*) into existente from public.stock_movimientos where evento_id=evento.id;
 if existente>0 then return existente; end if;
 for x in select value from jsonb_array_elements(contenido->'items') order by (value->>'producto_id')::uuid loop
  producto:=(x->>'producto_id')::uuid; delta:=(x->>'cantidad_delta')::numeric;
  select p.control_stock into controla from public.productos p where p.id=producto for key share;
  if not found then raise exception 'Producto inexistente' using errcode='PT404'; end if;
  continue when not controla;
  insert into public.stock_actual(ubicacion_id,producto_id,cantidad) values(p_ubicacion_id,producto,0)
  on conflict (ubicacion_id,producto_id) do nothing;
  select * into fila from public.stock_actual s where s.ubicacion_id=p_ubicacion_id and s.producto_id=producto for update;
  continue when fila.contado_at is not null and evento.fecha_fisica<fila.contado_at;
  nueva:=fila.cantidad+delta;
  if abs(nueva)>99999999999.999 then raise exception 'Cantidad fuera de rango' using errcode='PT422'; end if;
  update public.stock_actual set cantidad=nueva,updated_at=clock_timestamp()
   where ubicacion_id=p_ubicacion_id and producto_id=producto;
  insert into public.stock_movimientos(ubicacion_id,producto_id,tipo,cantidad_anterior,cantidad_delta,cantidad_nueva,
   motivo,observacion,usuario_id,referencia_tipo,referencia_id,evento_id)
  values(p_ubicacion_id,producto,x->>'tipo',fila.cantidad,delta,nueva,contenido->>'motivo',contenido->>'observacion',
   evento.actor_id,'stock_evento',evento.id,evento.id);
  aplicados:=aplicados+1;
 end loop;
 return aplicados;
end;$function$;

-- 10. Entregas y ventas descuentan del vehículo; los eventos usan la configuración única.
CREATE OR REPLACE FUNCTION public.stock_base_finalizar_v2(p_solicitud_id uuid, p_pedido_id uuid, p_fecha_fisica timestamp with time zone, p_estado text, p_originales jsonb, p_agregados jsonb, p_tipo_pago text, p_motivo_no_entrega text DEFAULT NULL::text, p_importe_pago numeric DEFAULT NULL::numeric, p_medio_pago text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
AS $function$
#variable_conflict use_column
declare solicitud jsonb; huella text; anterior public.finalizacion_pedido_solicitudes;
 pedido public.pedidos; d public.pedido_detalles; producto public.productos;
 x jsonb; base numeric; q numeric; precio numeric; porcentaje numeric; total_unidades numeric:=0;
 completa boolean:=true; resultado text; saldo numeric; ubicacion uuid; evento uuid; movimientos integer;
 items jsonb; respuesta jsonb; originales_esperados integer;
begin
 if public.es_administrador() is not true then raise exception 'Solo administración' using errcode='PT403'; end if;
 if p_solicitud_id is null or p_fecha_fisica is null or not isfinite(p_fecha_fisica)
 or p_fecha_fisica>clock_timestamp() then raise exception 'Fecha o solicitud inválida' using errcode='PT422'; end if;
 solicitud:=public.finalizacion_normalizar_v1(p_pedido_id,p_estado,p_motivo_no_entrega,p_originales,p_agregados,
  p_tipo_pago,p_importe_pago,p_medio_pago,p_fecha_fisica);
 huella:=encode(sha256(convert_to(solicitud::text,'UTF8')),'hex');
 perform pg_advisory_xact_lock(829001);
 select * into anterior from public.finalizacion_pedido_solicitudes where solicitud_id=p_solicitud_id for update;
 if found then
  if anterior.actor_id is distinct from auth.uid() or anterior.request_hash is distinct from huella
  or anterior.solicitud_normalizada is distinct from solicitud then
   raise exception 'solicitud_incompatible' using errcode='PT409'; end if;
  return anterior.resultado_normalizado;
 end if;
 select * into pedido from public.pedidos where id=p_pedido_id for update;
 if not found then raise exception 'Pedido inexistente' using errcode='PT404'; end if;
 if pedido.tipo_operacion='venta_directa' then
  perform public.stock_exigir_venta_directa_v2();
  if pedido.estado='cancelado' then
   raise exception 'operacion_ya_finalizada' using errcode='PT409';
  end if;
  if not exists(select 1 from public.stock_transicion t
   join public.stock_regimenes r on r.id=t.regimen_id
   where t.singleton and (not r.automatizacion_activa or p_fecha_fisica>=r.fecha_corte)) then
   raise exception 'venta_directa_anterior_al_corte' using errcode='PT409';
  end if;
 elsif pedido.tipo_operacion is distinct from 'pedido' then
  raise exception 'Tipo de operación no disponible en V2' using errcode='PT422';
 end if;
 if pedido.resultado_entrega is distinct from 'pendiente' or pedido.estado='anulado' then
  raise exception 'operacion_ya_finalizada' using errcode='PT409'; end if;
 if pedido.tipo_operacion='pedido' and pedido.facturado is not true then raise exception 'Pedido sin facturar' using errcode='PT422'; end if;
 perform 1 from public.pedido_detalles where pedido_id=p_pedido_id order by id for update;
 select count(*) into originales_esperados from public.pedido_detalles where pedido_id=p_pedido_id and not agregado_en_entrega;
 if originales_esperados<>jsonb_array_length(solicitud->'originales') then
  raise exception 'Cobertura incompleta de detalles' using errcode='PT422'; end if;
 -- Validar todas las líneas antes de mutar. La base cero permanece cero.
 for x in select value from jsonb_array_elements(solicitud->'originales') loop
  select * into d from public.pedido_detalles where id=(x->>'detalle_id')::uuid and pedido_id=p_pedido_id and not agregado_en_entrega;
  if not found then raise exception 'Detalle ajeno o inexistente' using errcode='PT422'; end if;
  base:=coalesce(d.cantidad_facturada,d.cantidad); q:=(x->>'cantidad_entregada')::numeric;
  if base is null or base::text in ('NaN','Infinity','-Infinity') or base<0 or base<>round(base,2) or q>base then
   raise exception 'Cantidad superior a base o base inválida' using errcode='PT422'; end if;
  total_unidades:=total_unidades+q; completa:=completa and q=base;
 end loop;
 if pedido.tipo_operacion='pedido' and exists(select 1 from jsonb_array_elements(solicitud->'agregados') a join public.pedido_detalles d
  on d.producto_id=(a->>'producto_id')::uuid where d.pedido_id=p_pedido_id) then
  raise exception 'Agregado duplica producto original' using errcode='PT422'; end if;
 for x in select value from jsonb_array_elements(solicitud->'agregados') loop
  total_unidades:=total_unidades+(x->>'cantidad_entregada')::numeric;
 end loop;
 resultado:=case when total_unidades=0 then 'no_entregado' when completa then 'entregado' else 'parcial' end;
 if resultado<>'entregado' and solicitud->>'motivo_no_entrega' is null then
  raise exception 'Falta motivo de no entrega' using errcode='PT422'; end if;
 if resultado='no_entregado' and p_tipo_pago<>'sin_pago' then raise exception 'No corresponde cobrar sin entrega' using errcode='PT422'; end if;
 select id into ubicacion from public.ubicaciones_stock where codigo='vehiculo' and activo for share;
 if ubicacion is null then raise exception 'Vehículo no disponible' using errcode='PT410'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('producto_id',producto_id,'cantidad_delta',-cantidad,'tipo',case when pedido.tipo_operacion='venta_directa' then 'venta_directa' else 'entrega' end) order by producto_id),'[]')
 into items from (
  select producto_id,sum(cantidad) cantidad from (
   select d.producto_id,(x->>'cantidad_entregada')::numeric cantidad from jsonb_array_elements(solicitud->'originales') x
    join public.pedido_detalles d on d.id=(x->>'detalle_id')::uuid
   union all select (x->>'producto_id')::uuid,(x->>'cantidad_entregada')::numeric from jsonb_array_elements(solicitud->'agregados') x
  ) lineas group by producto_id having sum(cantidad)>0
 ) deltas;
 evento:=public.stock_registrar_evento(ubicacion,'finalizacion_pedido',p_pedido_id,p_solicitud_id,
  jsonb_build_object('items',items,'motivo',case when pedido.tipo_operacion='venta_directa' then 'Finalización de venta directa' else 'Finalización de preventa' end),p_fecha_fisica);
 -- Locks de productos en orden UUID; precios/comisiones siempre desde fuentes del servidor.
 perform 1 from public.productos where id in (
  select producto_id from public.pedido_detalles where pedido_id=p_pedido_id
  union select (x->>'producto_id')::uuid from jsonb_array_elements(solicitud->'agregados') x
 ) order by id for share;
 movimientos:=public.stock_aplicar_deltas(ubicacion,evento,items);
 for x in select value from jsonb_array_elements(solicitud->'originales') loop
  select * into d from public.pedido_detalles where id=(x->>'detalle_id')::uuid;
  select * into producto from public.productos where id=d.producto_id;
  q:=(x->>'cantidad_entregada')::numeric; base:=coalesce(d.cantidad_facturada,d.cantidad);
  porcentaje:=case when pedido.origen='catalogo' then coalesce(d.porcentaje_comision,0)
   else coalesce(case d.tipo_precio when 'promo' then producto.comision_promo when 'interior' then producto.comision_interior else producto.comision_normal end,0) end;
  update public.pedido_detalles set cantidad_entregada=q,cantidad_no_entregada=base-q,
   porcentaje_comision=porcentaje,importe_comision=round(q*precio_unitario*porcentaje/100,2) where id=d.id;
 end loop;
 for x in select value from jsonb_array_elements(solicitud->'agregados') loop
  select * into producto from public.productos where id=(x->>'producto_id')::uuid;
  if not found or producto.activo is not true then raise exception 'Producto no disponible' using errcode='PT422'; end if;
  q:=(x->>'cantidad_entregada')::numeric;
  precio:=case x->>'tipo_precio' when 'promo' then producto.precio_promo when 'interior' then producto.precio_interior else producto.precio_normal end;
  if precio is null or precio<=0 or precio::text in ('NaN','Infinity','-Infinity') then raise exception 'Precio inválido' using errcode='PT422'; end if;
  porcentaje:=case when pedido.origen='catalogo' and pedido.catalogo_preventista_id is null then 0
   else coalesce(case x->>'tipo_precio' when 'promo' then producto.comision_promo when 'interior' then producto.comision_interior else producto.comision_normal end,0) end;
  insert into public.pedido_detalles(pedido_id,producto_id,cantidad,cantidad_facturada,cantidad_entregada,cantidad_no_entregada,
   precio_unitario,subtotal,tipo_precio,costo_unitario,porcentaje_comision,importe_comision,agregado_en_entrega)
  values(p_pedido_id,producto.id,0,0,q,0,precio,0,x->>'tipo_precio',producto.costo,porcentaje,round(q*precio*porcentaje/100,2),true);
 end loop;
 update public.pedidos set estado=p_estado,resultado_entrega=resultado,fecha_finalizacion=now(),
  motivo_no_entrega=case when resultado='entregado' then null else solicitud->>'motivo_no_entrega' end where id=p_pedido_id;
 -- Mismo orden y reglas financieras que el wrapper legacy: crédito antes del cobro.
 perform public.aplicar_credito_cliente(pedido.cliente_id);
 if p_tipo_pago='parcial' then
  perform 1 from public.registrar_pago_cliente(pedido.cliente_id,p_importe_pago,btrim(p_medio_pago),'Pago parcial al entregar el pedido');
 elsif p_tipo_pago='completo' then
  select saldo_pendiente into saldo from public.saldos_pendientes_pedidos where pedido_id=p_pedido_id;
  if p_importe_pago is not null and p_importe_pago is distinct from saldo then
   raise exception 'Cambió el saldo a cobrar' using errcode='PT422'; end if;
  if saldo>0 then perform 1 from public.registrar_pago_cliente(pedido.cliente_id,saldo,btrim(p_medio_pago),'Pago completo al entregar el pedido'); end if;
 end if;
 select saldo_pendiente into saldo from public.saldos_pendientes_pedidos where pedido_id=p_pedido_id;
 respuesta:=jsonb_build_object('version',1,'solicitud_id',p_solicitud_id,'pedido_id',p_pedido_id,
  'resultado_entrega',resultado,'stock_evento_id',evento,'movimientos_stock',movimientos,'saldo_pendiente',saldo);
 insert into public.finalizacion_pedido_solicitudes(solicitud_id,pedido_id,actor_id,request_hash,solicitud_normalizada,resultado_normalizado,stock_evento_id)
 values(p_solicitud_id,p_pedido_id,auth.uid(),huella,solicitud,respuesta,evento);
 return respuesta;
end;$function$;

CREATE OR REPLACE FUNCTION public.stock_base_stock_registrar_evento(p_ubicacion_id uuid, p_tipo_evento text, p_origen_id uuid, p_solicitud_id uuid, p_contenido jsonb, p_fecha_fisica timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare actor uuid:=auth.uid(); contenido jsonb; solicitud jsonb; huella text;
 evento public.stock_eventos; config public.stock_configuracion; origen text;
begin
 if actor is null or public.es_administrador() is not true then
  raise exception 'Solo administración activa' using errcode='42501'; end if;
 if p_solicitud_id is null or p_origen_id is null or p_ubicacion_id is null
 or p_fecha_fisica is null or not isfinite(p_fecha_fisica) or p_fecha_fisica>clock_timestamp()
 or p_tipo_evento is null or p_tipo_evento not in ('finalizacion_pedido','correccion_operacion','recepcion_nota_credito') then
  raise exception 'Evento Stock inválido' using errcode='PT422'; end if;
 contenido:=public.stock_normalizar_solicitud(p_contenido);
 if exists(select 1 from jsonb_array_elements(contenido->'items') x where
  (p_tipo_evento='finalizacion_pedido' and x->>'tipo' not in ('entrega','venta_directa'))
  or (p_tipo_evento='correccion_operacion' and x->>'tipo' not in ('correccion_entrada','correccion_salida'))
  or (p_tipo_evento='recepcion_nota_credito' and x->>'tipo'<>'devolucion_apta')) then
  raise exception 'Tipo incompatible con el evento' using errcode='PT422'; end if;
 origen:=case p_tipo_evento when 'finalizacion_pedido' then 'pedido' else p_tipo_evento end;
 solicitud:=jsonb_build_object('version',1,'ubicacion_id',p_ubicacion_id,'tipo_evento',p_tipo_evento,
  'origen_id',p_origen_id,'fecha_fisica_epoch',trim_scale(extract(epoch from p_fecha_fisica)), 'contenido',contenido);
 huella:=encode(sha256(convert_to(solicitud::text,'UTF8')),'hex');
 -- Mismo primer lock que las funciones financieras; serializa claves/orígenes.
 perform pg_advisory_xact_lock(829001);
 select * into evento from public.stock_eventos where solicitud_id=p_solicitud_id;
 if found then
  if evento.actor_id is distinct from actor or evento.request_hash<>huella or evento.solicitud<>solicitud then
   raise exception 'Evento duplicado incompatible' using errcode='PT409'; end if;
  return evento.id;
 end if;
 if exists(select 1 from public.stock_eventos where tipo_evento=p_tipo_evento and origen_id=p_origen_id) then
  raise exception 'Origen Stock ya registrado con otra solicitud' using errcode='PT409'; end if;
 perform 1 from public.ubicaciones_stock where id=p_ubicacion_id and activo for share;
 if not found then raise exception 'Ubicación inactiva o inexistente' using errcode='PT410'; end if;
 -- Configuración única (la del depósito) para todas las ubicaciones.
 select * into config from public.stock_configuracion order by ubicacion_id limit 1 for share;
 if not found then raise exception 'Ubicación sin configuración' using errcode='PT410'; end if;
 insert into public.stock_eventos(ubicacion_id,tipo_evento,origen_tipo,origen_id,pedido_id,correccion_id,recepcion_id,
  solicitud_id,request_hash,solicitud,actor_id,automatizacion_activa,fecha_corte_aplicable,fecha_fisica)
 values(p_ubicacion_id,p_tipo_evento,origen,p_origen_id,
  case when p_tipo_evento='finalizacion_pedido' then p_origen_id end,
  case when p_tipo_evento='correccion_operacion' then p_origen_id end,
  case when p_tipo_evento='recepcion_nota_credito' then p_origen_id end,
  p_solicitud_id,huella,solicitud,actor,config.automatizacion_activa,config.fecha_corte,p_fecha_fisica)
 returning id into evento.id;
 return evento.id;
end;$function$;
