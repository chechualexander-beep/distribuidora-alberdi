-- El vehículo no queda en negativo por una venta (20/11/2026).
-- 1) Al entregar o vender desde el vehículo, lo que no alcanza arriba se toma del depósito también
--    con el viaje abierto (antes solo sin viaje). Ejemplo: con el viaje todavía abierto se vende en el
--    depósito un producto que no estaba arriba: baja el depósito, no queda -1 en el vehículo.
-- 2) stock_vehiculo_faltante_del_deposito: si igual queda algo en negativo en el vehículo (error de
--    carga, ventas viejas), al cerrar el viaje la app ofrece descontarlo del depósito en vez de
--    ponerlo en 0 sin tocar el depósito.

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
  -- Lo que no alcanza en el vehículo se toma del depósito (abriendo bolsas del depósito si hace
  -- falta), con o sin viaje abierto: si no estaba arriba, salió del depósito.
  if nueva < 0 and p_ubicacion_id = public.stock_ubicacion('vehiculo') then
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
    'Tomado del depósito al entregar (no alcanzaba en el vehículo)', evento.id);
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

alter table public.stock_operaciones drop constraint stock_operaciones_tipo_check,
 add constraint stock_operaciones_tipo_check check (tipo in ('conteo','carga_vehiculo','baja_vehiculo','compra',
  'cierre_viaje','fraccion','faltante_vehiculo'));

-- Pasa del depósito al vehículo lo que falta para que el vehículo no quede en negativo (a lo sumo
-- lo que esté en negativo). Cada producto: {producto_id, cantidad}.
create function public.stock_vehiculo_faltante_del_deposito(p_id uuid, p_items jsonb, p_fecha timestamptz,
 p_observacion text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare huella text; previo jsonb; dep uuid; veh uuid; fecha timestamptz; it record; control boolean;
 viaje uuid; arriba numeric; falta numeric; movidos integer := 0; detalle jsonb := '[]'; res jsonb;
begin
 perform public.stock_exigir_admin(); perform public.stock_exigir_operativo();
 huella := public.stock_huella(jsonb_build_object('i', p_items, 'f', p_fecha, 'o', p_observacion));
 previo := public.stock_operacion_previa(p_id, 'faltante_vehiculo', huella);
 if previo is not null then return previo; end if;
 perform pg_advisory_xact_lock(829001);
 dep := public.stock_ubicacion('deposito_alberdi'); veh := public.stock_ubicacion('vehiculo');
 fecha := public.stock_validar_fecha(p_fecha);
 select id into viaje from public.viajes_vehiculo where ubicacion_id = veh and estado = 'abierto';
 insert into public.stock_operaciones(id, tipo, ubicacion_id, viaje_id, observacion, fecha_fisica, actor_id, request_hash, resultado)
 values (p_id, 'faltante_vehiculo', veh, viaje, nullif(btrim(p_observacion), ''), fecha, auth.uid(), huella, '{}');
 for it in select * from public.stock_items(p_items, true) loop
  select p.control_stock into control from public.productos p where p.id = it.producto_id for key share;
  falta := 0;
  if control then
   select s.cantidad into arriba from public.stock_actual s
   where s.ubicacion_id = veh and s.producto_id = it.producto_id for update;
   falta := least(it.cantidad, greatest(-coalesce(arriba, 0), 0));
   if falta > 0 then
    perform public.stock_mover(dep, it.producto_id, -falta, 'transferencia_salida',
     'Faltante del vehículo: salió del depósito', p_id);
    perform public.stock_mover(veh, it.producto_id, falta, 'transferencia_entrada',
     'Faltante del vehículo: salió del depósito', p_id);
    movidos := movidos + 1;
    detalle := detalle || jsonb_build_object('producto_id', it.producto_id,
     'nombre', (select nombre from public.productos where id = it.producto_id), 'cantidad', falta);
   end if;
  end if;
  insert into public.stock_operacion_items(operacion_id, producto_id, cantidad, controlado)
  values (p_id, it.producto_id, it.cantidad, coalesce(control, false));
 end loop;
 res := jsonb_build_object('operacion_id', p_id, 'movidos', movidos, 'productos', detalle);
 update public.stock_operaciones set resultado = res where id = p_id;
 return res;
end $$;

revoke all on function public.stock_vehiculo_faltante_del_deposito(uuid, jsonb, timestamptz, text) from public, anon;
grant execute on function public.stock_vehiculo_faltante_del_deposito(uuid, jsonb, timestamptz, text) to authenticated;

notify pgrst, 'reload schema';
