-- Todos los productos llevan stock y no se pasa más de lo que hay (21/11/2026).
-- 1) Los productos "a pedido" pasan a llevar stock, en 0. "A pedido" queda como etiqueta
--    (se_compra_a_pedido) para la lista de compras: la compra suma stock como en cualquier producto.
--    Lo que hubiera quedado anotado de esos productos se pone en 0 con su movimiento.
-- 2) Cargar el vehículo: no más de lo que figura en el depósito (los sueltos abren bolsas del depósito).
--    Bajar al depósito: no más de lo que figura en el vehículo.
-- 3) stock_marcar_a_pedido pone o saca la etiqueta (ya no deja de llevar stock).

alter table public.productos add column if not exists se_compra_a_pedido boolean not null default false;
grant select (se_compra_a_pedido) on public.productos to authenticated;

do $$
declare actor uuid; fila record; dep uuid := public.stock_ubicacion('deposito_alberdi');
 veh uuid := public.stock_ubicacion('vehiculo');
begin
 select u.id into actor from public.usuarios u where u.rol = 'administrador' and u.activo order by u.id limit 1;
 for fila in select s.* from public.stock_actual s join public.productos p on p.id = s.producto_id
   where not p.control_stock and s.cantidad <> 0 for update of s loop
  if actor is not null then
   insert into public.stock_movimientos(ubicacion_id, producto_id, tipo, cantidad_anterior, cantidad_delta,
    cantidad_nueva, motivo, usuario_id)
   values (fila.ubicacion_id, fila.producto_id, case when fila.cantidad < 0 then 'ajuste_entrada' else 'ajuste_salida' end,
    fila.cantidad, -fila.cantidad, 0, 'Pasa a llevar stock: arranca en 0', actor);
  end if;
  update public.stock_actual set cantidad = 0, contado_at = clock_timestamp(), updated_at = clock_timestamp()
  where ubicacion_id = fila.ubicacion_id and producto_id = fila.producto_id;
 end loop;
 insert into public.stock_actual(ubicacion_id, producto_id, cantidad)
 select u, p.id, 0 from public.productos p cross join unnest(array[dep, veh]) u
 where not p.control_stock
 on conflict (ubicacion_id, producto_id) do nothing;
 update public.productos set se_compra_a_pedido = true, control_stock = true where not control_stock;
end $$;

alter table public.productos alter column control_stock set default true;

drop function if exists public.stock_marcar_a_pedido(uuid);
create function public.stock_marcar_a_pedido(p_producto_id uuid, p_valor boolean default true) returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
 perform public.stock_exigir_admin(); perform public.stock_exigir_operativo();
 update public.productos set se_compra_a_pedido = coalesce(p_valor, true)
 where id = p_producto_id and se_compra_a_pedido is distinct from coalesce(p_valor, true);
end $$;
revoke all on function public.stock_marcar_a_pedido(uuid, boolean) from public, anon;
grant execute on function public.stock_marcar_a_pedido(uuid, boolean) to authenticated;

drop function if exists public.stock_estado();
create function public.stock_estado()
 returns table(producto_id uuid, control_stock boolean, deposito numeric, vehiculo numeric,
  deposito_contado_at timestamptz, vehiculo_contado_at timestamptz, fracciona_de uuid,
  unidades_por_origen numeric, se_compra_a_pedido boolean)
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare dep uuid := public.stock_ubicacion('deposito_alberdi'); veh uuid := public.stock_ubicacion('vehiculo');
begin
 perform public.stock_exigir_admin();
 return query select p.id, p.control_stock, d.cantidad, v.cantidad, d.contado_at, v.contado_at,
  p.fracciona_de, p.unidades_por_origen, p.se_compra_a_pedido
 from public.productos p
 left join public.stock_actual d on d.producto_id = p.id and d.ubicacion_id = dep
 left join public.stock_actual v on v.producto_id = p.id and v.ubicacion_id = veh
 where p.activo order by p.nombre;
end $$;
revoke all on function public.stock_estado() from public, anon;
grant execute on function public.stock_estado() to authenticated;

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
 res := jsonb_build_object('operacion_id', p_id, 'movidos', movidos);
 update public.stock_operaciones set resultado = res where id = p_id;
 return res;
end $function$;

notify pgrst, 'reload schema';
