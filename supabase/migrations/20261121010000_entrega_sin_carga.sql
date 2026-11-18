-- Entregas sin la carga del vehículo registrada (18/11/2026).
-- Sin viaje abierto, lo que falta en el vehículo al entregar se toma del depósito (como una carga
-- automática, abriendo bolsas del depósito si hace falta), así el día que no se registra la carga
-- todo queda bien igual. Con un viaje abierto (se cargó el vehículo) no: el vehículo marca que se
-- terminó y queda en negativo para revisar, porque la venta directa necesita esa precisión.

create function public.stock_transferir_evento(p_producto uuid, p_cantidad numeric, p_desde uuid, p_hasta uuid,
 p_motivo text, p_evento uuid) returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare ubic uuid; signo numeric; anterior numeric;
begin
 if p_cantidad <= 0 then return; end if;
 foreach ubic in array array[p_desde, p_hasta] loop
  signo := case when ubic = p_desde then -1 else 1 end;
  insert into public.stock_actual(ubicacion_id, producto_id, cantidad) values (ubic, p_producto, 0)
  on conflict (ubicacion_id, producto_id) do nothing;
  select s.cantidad into anterior from public.stock_actual s
  where s.ubicacion_id = ubic and s.producto_id = p_producto for update;
  update public.stock_actual set cantidad = anterior + signo * p_cantidad, updated_at = clock_timestamp()
  where ubicacion_id = ubic and producto_id = p_producto;
  insert into public.stock_movimientos(ubicacion_id, producto_id, tipo, cantidad_anterior, cantidad_delta,
   cantidad_nueva, motivo, usuario_id, referencia_tipo, referencia_id)
  values (ubic, p_producto, case when signo < 0 then 'transferencia_salida' else 'transferencia_entrada' end,
   anterior, signo * p_cantidad, anterior + signo * p_cantidad, p_motivo, auth.uid(), 'stock_evento', p_evento);
 end loop;
end $$;
revoke all on function public.stock_transferir_evento(uuid, numeric, uuid, uuid, text, uuid) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.stock_base_stock_aplicar_deltas(p_ubicacion_id uuid, p_evento_id uuid, p_items jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare evento public.stock_eventos; contenido jsonb; x jsonb; fila public.stock_actual; nueva numeric;
 producto uuid; delta numeric; controla boolean; aplicados integer := 0; existente integer;
 fr_origen uuid; fr_unidades numeric; fr_controla boolean; fr_hay numeric; abrir numeric;
 dep uuid; falta numeric; dep_hay numeric;
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
  -- Fraccionado que no alcanza: se abren solas las unidades del origen que hagan falta
  -- (las que haya en el mismo lugar). Lo que sobra queda como unidades sueltas.
  if nueva < 0 then
   select p.fracciona_de, p.unidades_por_origen, o.control_stock into fr_origen, fr_unidades, fr_controla
   from public.productos p left join public.productos o on o.id = p.fracciona_de where p.id = producto;
   if fr_origen is not null and fr_controla then
    select s.cantidad into fr_hay from public.stock_actual s
    where s.ubicacion_id = p_ubicacion_id and s.producto_id = fr_origen;
    abrir := least(ceil(-nueva / fr_unidades), floor(coalesce(fr_hay, 0)));
    if abrir > 0 then
     perform public.stock_abrir_origen(p_ubicacion_id, producto, abrir, 'Fraccionado automático al entregar',
      'stock_evento', evento.id);
     select * into fila from public.stock_actual s where s.ubicacion_id=p_ubicacion_id and s.producto_id=producto;
     nueva := fila.cantidad + delta;
    end if;
   end if;
  end if;
  -- Sin viaje abierto (no se registró la carga del vehículo): lo que falta arriba se toma del
  -- depósito, abriendo bolsas del depósito si hace falta. Con un viaje abierto, no: el vehículo
  -- marca que se terminó (la venta directa necesita esa precisión).
  if nueva < 0 and p_ubicacion_id = public.stock_ubicacion('vehiculo')
   and not exists (select 1 from public.viajes_vehiculo v where v.ubicacion_id = p_ubicacion_id and v.estado = 'abierto') then
   dep := public.stock_ubicacion('deposito_alberdi');
   falta := -nueva;
   insert into public.stock_actual(ubicacion_id, producto_id, cantidad) values (dep, producto, 0)
   on conflict (ubicacion_id, producto_id) do nothing;
   select s.cantidad into dep_hay from public.stock_actual s where s.ubicacion_id = dep and s.producto_id = producto for update;
   if dep_hay < falta then
    select p.fracciona_de, p.unidades_por_origen, o.control_stock into fr_origen, fr_unidades, fr_controla
    from public.productos p left join public.productos o on o.id = p.fracciona_de where p.id = producto;
    if fr_origen is not null and fr_controla then
     select s.cantidad into fr_hay from public.stock_actual s where s.ubicacion_id = dep and s.producto_id = fr_origen;
     abrir := least(ceil((falta - greatest(dep_hay, 0)) / fr_unidades), floor(coalesce(fr_hay, 0)));
     if abrir > 0 then
      perform public.stock_abrir_origen(dep, producto, abrir, 'Fraccionado automático al entregar', 'stock_evento', evento.id);
     end if;
    end if;
   end if;
   perform public.stock_transferir_evento(producto, falta, dep, p_ubicacion_id,
    'Tomado del depósito al entregar (no se registró la carga del vehículo)', evento.id);
   select * into fila from public.stock_actual s where s.ubicacion_id = p_ubicacion_id and s.producto_id = producto;
   nueva := fila.cantidad + delta;
  end if;
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
