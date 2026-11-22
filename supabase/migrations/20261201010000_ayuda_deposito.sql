-- Ayuda en el depósito + lista de carga compartida (1.14.0).
-- 1) Permiso "Ayuda en el depósito" para un preventista (Gabriela): ve el stock (sin costos),
--    cuenta (se aplica directo), carga y baja el vehículo. No anota compras, no cierra viajes,
--    no toca costos, fraccionados ni "a pedido". Lo prende o apaga el administrador.
-- 2) La carga (y la bajada) en preparación vive en la base, una lista por vehículo y sentido:
--    los teléfonos y la PC ven lo mismo, con quién marcó cada cosa. Al subir, lo subido sale de
--    la lista. Lo que quedó de otro día se descarta solo.
begin;

alter table public.usuarios add column if not exists puede_deposito boolean not null default false;

create function public.puede_deposito(p_usuario uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
 select exists(select 1 from public.usuarios u where u.id = p_usuario and u.activo is true
  and (u.rol = 'administrador' or (u.rol = 'preventista' and u.puede_deposito)))
$$;
revoke all on function public.puede_deposito(uuid) from public, anon, authenticated;
grant execute on function public.puede_deposito(uuid) to authenticated;

create function public.stock_exigir_deposito() returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
 if public.puede_deposito() is not true then
  raise exception 'Solo administración o ayuda en el depósito' using errcode = 'PT403'; end if;
end $$;
revoke all on function public.stock_exigir_deposito() from public, anon, authenticated;

create function public.habilitar_deposito(p_usuario uuid, p_habilitado boolean) returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
 perform public.stock_exigir_admin();
 if p_habilitado is null then raise exception 'Valor inválido' using errcode = 'PT422'; end if;
 update public.usuarios set puede_deposito = p_habilitado where id = p_usuario and rol = 'preventista';
 if not found then raise exception 'Elegí un preventista' using errcode = 'PT422'; end if;
end $$;
revoke all on function public.habilitar_deposito(uuid, boolean) from public, anon, authenticated;
grant execute on function public.habilitar_deposito(uuid, boolean) to authenticated;

-- Preventistas activos (para elegir con quién sale el viaje y para el permiso).
create function public.stock_preventistas()
 returns table(id uuid, nombre text, apellido text, puede_deposito boolean)
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
begin
 perform public.stock_exigir_deposito();
 return query select u.id, u.nombre, u.apellido, u.puede_deposito from public.usuarios u
 where u.rol = 'preventista' and u.activo order by u.nombre;
end $$;
revoke all on function public.stock_preventistas() from public, anon;
grant execute on function public.stock_preventistas() to authenticated;

-- Lo de los pedidos facturados que falta entregar (para proponer la carga), de todos los preventistas.
create function public.stock_pedidos_a_entregar() returns table(producto_id uuid, cantidad numeric)
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
begin
 perform public.stock_exigir_deposito();
 return query select d.producto_id, sum(coalesce(d.cantidad_facturada, d.cantidad))::numeric
 from public.pedido_detalles d join public.pedidos p on p.id = d.pedido_id
 where p.resultado_entrega = 'pendiente' and p.facturado and p.tipo_operacion = 'pedido'
  and p.estado <> 'anulado' and coalesce(d.cantidad_facturada, d.cantidad) > 0
 group by d.producto_id;
end $$;
revoke all on function public.stock_pedidos_a_entregar() from public, anon;
grant execute on function public.stock_pedidos_a_entregar() to authenticated;

-- Lo que se cargó la última vez en el vehículo.
create function public.stock_ultima_carga() returns table(producto_id uuid, cantidad numeric)
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
begin
 perform public.stock_exigir_deposito();
 return query select i.producto_id, i.cantidad from public.stock_operacion_items i
 where i.operacion_id = (select o.id from public.stock_operaciones o where o.tipo = 'carga_vehiculo'
  order by o.fecha_fisica desc limit 1);
end $$;
revoke all on function public.stock_ultima_carga() from public, anon;
grant execute on function public.stock_ultima_carga() to authenticated;

-- Lista compartida. Se usa solo con las funciones de abajo (sin acceso directo a la tabla).
create table public.stock_traspaso_lineas (
 vehiculo_id uuid not null references public.ubicaciones_stock(id),
 direccion text not null check (direccion in ('cargar', 'bajar')),
 producto_id uuid not null references public.productos(id),
 cantidad numeric check (cantidad is null or cantidad >= 0),
 pedido numeric check (pedido is null or pedido >= 0),
 marcada boolean not null default false,
 marcada_por uuid references public.usuarios(id),
 marcada_at timestamptz,
 cambiada_por uuid not null references public.usuarios(id),
 cambiada_at timestamptz not null default now(),
 primary key (vehiculo_id, direccion, producto_id)
);
alter table public.stock_traspaso_lineas enable row level security;
revoke all on public.stock_traspaso_lineas from public, anon, authenticated;

create function public.stock_traspaso_lista(p_direccion text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare veh uuid := public.stock_ubicacion('vehiculo');
 hoy timestamptz := date_trunc('day', now() at time zone 'America/Argentina/Buenos_Aires')
  at time zone 'America/Argentina/Buenos_Aires';
 lineas jsonb; otros jsonb;
begin
 perform public.stock_exigir_deposito();
 if p_direccion is null or p_direccion not in ('cargar', 'bajar') then
  raise exception 'Sentido inválido' using errcode = 'PT422'; end if;
 delete from public.stock_traspaso_lineas l where l.vehiculo_id = veh and l.direccion = p_direccion
  and l.cambiada_at < hoy;
 select coalesce(jsonb_agg(jsonb_build_object('producto_id', l.producto_id, 'cantidad', l.cantidad,
   'pedido', l.pedido, 'marcada', l.marcada, 'marcada_por', um.nombre, 'marcada_at', l.marcada_at)
   order by l.producto_id), '[]')
 into lineas
 from public.stock_traspaso_lineas l left join public.usuarios um on um.id = l.marcada_por
 where l.vehiculo_id = veh and l.direccion = p_direccion;
 -- Quiénes más estuvieron con esta lista en los últimos 10 minutos.
 select coalesce(jsonb_agg(distinct u.nombre), '[]') into otros
 from public.stock_traspaso_lineas l join public.usuarios u on u.id = l.cambiada_por
 where l.vehiculo_id = veh and l.direccion = p_direccion and l.cambiada_por <> auth.uid()
  and l.cambiada_at > now() - interval '10 minutes';
 return jsonb_build_object('direccion', p_direccion, 'version', md5(lineas::text), 'lineas', lineas,
  'otros', otros);
end $$;
revoke all on function public.stock_traspaso_lista(text) from public, anon;
grant execute on function public.stock_traspaso_lista(text) to authenticated;

-- Cambia renglones de la lista: [{producto_id, cantidad, pedido, marcada}]. Un renglón sin
-- cantidad, sin pedido y sin marcar se borra. Devuelve la lista como queda.
create function public.stock_traspaso_poner(p_direccion text, p_lineas jsonb) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare veh uuid := public.stock_ubicacion('vehiculo'); l jsonb; prod uuid; cant numeric; ped numeric;
 marca boolean;
begin
 perform public.stock_exigir_deposito();
 if p_direccion is null or p_direccion not in ('cargar', 'bajar') then
  raise exception 'Sentido inválido' using errcode = 'PT422'; end if;
 if jsonb_typeof(p_lineas) is distinct from 'array' or jsonb_array_length(p_lineas) > 500 then
  raise exception 'Lista inválida' using errcode = 'PT422'; end if;
 for l in select * from jsonb_array_elements(p_lineas) loop
  prod := (l->>'producto_id')::uuid;
  if not exists (select 1 from public.productos p where p.id = prod) then
   raise exception 'Producto inválido' using errcode = 'PT422'; end if;
  cant := nullif(l->>'cantidad', '')::numeric;
  ped := nullif(l->>'pedido', '')::numeric;
  marca := coalesce((l->>'marcada')::boolean, false);
  if cant < 0 or ped < 0 then raise exception 'Cantidad inválida' using errcode = 'PT422'; end if;
  if cant is null and ped is null and not marca then
   delete from public.stock_traspaso_lineas t where t.vehiculo_id = veh and t.direccion = p_direccion
    and t.producto_id = prod;
  else
   insert into public.stock_traspaso_lineas as t(vehiculo_id, direccion, producto_id, cantidad, pedido,
    marcada, marcada_por, marcada_at, cambiada_por, cambiada_at)
   values (veh, p_direccion, prod, cant, ped, marca, case when marca then auth.uid() end,
    case when marca then now() end, auth.uid(), now())
   on conflict (vehiculo_id, direccion, producto_id) do update set cantidad = excluded.cantidad,
    pedido = excluded.pedido, marcada = excluded.marcada,
    marcada_por = case when not excluded.marcada then null when t.marcada then t.marcada_por else auth.uid() end,
    marcada_at = case when not excluded.marcada then null when t.marcada then t.marcada_at else now() end,
    cambiada_por = auth.uid(), cambiada_at = now();
  end if;
 end loop;
 return public.stock_traspaso_lista(p_direccion);
end $$;
revoke all on function public.stock_traspaso_poner(text, jsonb) from public, anon;
grant execute on function public.stock_traspaso_poner(text, jsonb) to authenticated;

-- "Empezar de nuevo": vacía la lista de ese sentido.
create function public.stock_traspaso_vaciar(p_direccion text) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
 perform public.stock_exigir_deposito();
 if p_direccion is null or p_direccion not in ('cargar', 'bajar') then
  raise exception 'Sentido inválido' using errcode = 'PT422'; end if;
 delete from public.stock_traspaso_lineas t where t.vehiculo_id = public.stock_ubicacion('vehiculo')
  and t.direccion = p_direccion;
 return public.stock_traspaso_lista(p_direccion);
end $$;
revoke all on function public.stock_traspaso_vaciar(text) from public, anon;
grant execute on function public.stock_traspaso_vaciar(text) to authenticated;

-- Ver stock, contar, cargar y bajar: administración o ayuda en el depósito.
CREATE OR REPLACE FUNCTION public.stock_estado()
 RETURNS TABLE(producto_id uuid, control_stock boolean, deposito numeric, vehiculo numeric, deposito_contado_at timestamp with time zone, vehiculo_contado_at timestamp with time zone, fracciona_de uuid, unidades_por_origen numeric, se_compra_a_pedido boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare dep uuid := public.stock_ubicacion('deposito_alberdi'); veh uuid := public.stock_ubicacion('vehiculo');
begin
 perform public.stock_exigir_deposito();
 return query select p.id, p.control_stock, d.cantidad, v.cantidad, d.contado_at, v.contado_at,
  p.fracciona_de, p.unidades_por_origen, p.se_compra_a_pedido
 from public.productos p
 left join public.stock_actual d on d.producto_id = p.id and d.ubicacion_id = dep
 left join public.stock_actual v on v.producto_id = p.id and v.ubicacion_id = veh
 where p.activo order by p.nombre;
end $function$;

CREATE OR REPLACE FUNCTION public.stock_contar(p_id uuid, p_ubicacion text, p_items jsonb, p_fecha timestamp with time zone, p_observacion text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare huella text; previo jsonb; loc uuid; fecha timestamptz; it record; antes numeric;
 control boolean; nuevos integer := 0; difs jsonb := '[]'; res jsonb;
begin
 perform public.stock_exigir_deposito(); perform public.stock_exigir_operativo();
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
end $function$;

CREATE OR REPLACE FUNCTION public.stock_cargar_vehiculo(p_id uuid, p_items jsonb, p_fecha timestamp with time zone, p_preventista_id uuid DEFAULT NULL::uuid, p_observacion text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare huella text; previo jsonb; dep uuid; veh uuid; fecha timestamptz; it record; control boolean;
 viaje public.viajes_vehiculo; nuevo boolean := false; movidos integer := 0; a_pedido integer := 0; res jsonb;
 hay numeric; fr_origen uuid; fr_unidades numeric; fr_hay numeric; abrir numeric; nombre text;
begin
 perform public.stock_exigir_deposito(); perform public.stock_exigir_operativo();
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
   -- No se carga más de lo que figura en el depósito. Un suelto que no alcanza abre las bolsas
   -- que hagan falta del depósito; si igual no alcanza, se avisa y no se carga nada.
   select s.cantidad into hay from public.stock_actual s
   where s.ubicacion_id = dep and s.producto_id = it.producto_id for update;
   hay := coalesce(hay, 0);
   if hay < it.cantidad then
    fr_origen := null;
    select p.fracciona_de, p.unidades_por_origen into fr_origen, fr_unidades
    from public.productos p join public.productos o on o.id = p.fracciona_de
    where p.id = it.producto_id and o.control_stock;
    if fr_origen is not null and fr_unidades > 0 then
     select s.cantidad into fr_hay from public.stock_actual s where s.ubicacion_id = dep and s.producto_id = fr_origen;
     abrir := least(ceil((it.cantidad - greatest(hay, 0)) / fr_unidades), floor(greatest(coalesce(fr_hay, 0), 0)));
     if abrir > 0 then
      perform public.stock_abrir_origen(dep, it.producto_id, abrir, 'Se abrió para cargar el vehículo', 'stock_operacion', p_id);
      hay := hay + abrir * fr_unidades;
     end if;
    end if;
    if hay < it.cantidad then
     select p.nombre into nombre from public.productos p where p.id = it.producto_id;
     raise exception 'No alcanza en el depósito: % (hay %, se quiere cargar %)', nombre,
      trim_scale(greatest(hay, 0)), trim_scale(it.cantidad) using errcode = 'PT409';
    end if;
   end if;
   perform public.stock_mover(dep, it.producto_id, -it.cantidad, 'transferencia_salida', 'Carga del vehículo', p_id);
   perform public.stock_mover(veh, it.producto_id, it.cantidad, 'transferencia_entrada', 'Carga del vehículo', p_id);
   movidos := movidos + 1;
  else
   a_pedido := a_pedido + 1;
  end if;
  insert into public.stock_operacion_items(operacion_id, producto_id, cantidad, controlado)
  values (p_id, it.producto_id, it.cantidad, control);
 end loop;
 -- Lo que se subió sale de la lista compartida (lo demás sigue ahí para seguir cargando).
 delete from public.stock_traspaso_lineas l where l.vehiculo_id = veh and l.direccion = 'cargar'
  and l.producto_id in (select i.producto_id from public.stock_items(p_items, true) i);
 res := jsonb_build_object('operacion_id', p_id, 'viaje_id', viaje.id, 'viaje_nuevo', nuevo,
  'movidos', movidos, 'a_pedido', a_pedido);
 update public.stock_operaciones set resultado = res where id = p_id;
 return res;
end $function$;

CREATE OR REPLACE FUNCTION public.stock_bajar_vehiculo(p_id uuid, p_items jsonb, p_fecha timestamp with time zone, p_observacion text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare huella text; previo jsonb; dep uuid; veh uuid; fecha timestamptz; it record; control boolean;
 viaje uuid; movidos integer := 0; res jsonb; hay numeric; nombre text;
begin
 perform public.stock_exigir_deposito(); perform public.stock_exigir_operativo();
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
   -- No se baja más de lo que figura en el vehículo.
   select s.cantidad into hay from public.stock_actual s
   where s.ubicacion_id = veh and s.producto_id = it.producto_id for update;
   if coalesce(hay, 0) < it.cantidad then
    select p.nombre into nombre from public.productos p where p.id = it.producto_id;
    raise exception 'No hay tanto en el vehículo: % (hay %, se quiere bajar %)', nombre,
     trim_scale(greatest(coalesce(hay, 0), 0)), trim_scale(it.cantidad) using errcode = 'PT409';
   end if;
   perform public.stock_mover(veh, it.producto_id, -it.cantidad, 'transferencia_salida', 'Bajada al depósito', p_id);
   perform public.stock_mover(dep, it.producto_id, it.cantidad, 'transferencia_entrada', 'Bajada al depósito', p_id);
   movidos := movidos + 1;
  end if;
  insert into public.stock_operacion_items(operacion_id, producto_id, cantidad, controlado)
  values (p_id, it.producto_id, it.cantidad, control);
 end loop;
 delete from public.stock_traspaso_lineas l where l.vehiculo_id = veh and l.direccion = 'bajar'
  and l.producto_id in (select i.producto_id from public.stock_items(p_items, true) i);
 res := jsonb_build_object('operacion_id', p_id, 'movidos', movidos);
 update public.stock_operaciones set resultado = res where id = p_id;
 return res;
end $function$;

notify pgrst, 'reload schema';
commit;
