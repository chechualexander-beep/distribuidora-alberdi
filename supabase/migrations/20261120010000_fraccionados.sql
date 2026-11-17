-- Productos fraccionados (etapa 4 del stock). Ej.: "Copos c/azúcar x 1 kg" sale de "Copos 3A x 4 kg"
-- (1 bolsa → 4). Se fracciona a mano ("Fraccionar" en Stock) y, si una entrega deja el
-- fraccionado en negativo y hay unidades del origen en el mismo lugar, se abren solas las necesarias.

alter table public.productos
 add column fracciona_de uuid references public.productos(id),
 add column unidades_por_origen numeric,
 add constraint productos_fraccion_valida check (
  (fracciona_de is null and unidades_por_origen is null)
  or (fracciona_de is not null and fracciona_de <> id and unidades_por_origen > 1
      and unidades_por_origen <= 1000 and unidades_por_origen = round(unidades_por_origen, 3)));
grant select (fracciona_de, unidades_por_origen) on public.productos to authenticated;

alter table public.stock_movimientos
 drop constraint stock_movimientos_tipo_valido,
 drop constraint stock_movimientos_evento_obligatorio,
 drop constraint stock_movimientos_sentido_valido,
 add constraint stock_movimientos_tipo_valido check (tipo = any (array['stock_inicial','ajuste_entrada',
  'ajuste_salida','entrega','venta_directa','correccion_entrada','correccion_salida','devolucion_apta',
  'transferencia_entrada','transferencia_salida','compra','fraccion_entrada','fraccion_salida'])),
 add constraint stock_movimientos_evento_obligatorio check (
  (tipo = any (array['stock_inicial','ajuste_entrada','ajuste_salida','transferencia_entrada',
   'transferencia_salida','compra','fraccion_entrada','fraccion_salida']) and evento_id is null)
  or (tipo = any (array['entrega','venta_directa','correccion_entrada','correccion_salida','devolucion_apta'])
   and evento_id is not null and referencia_tipo = 'stock_evento' and referencia_id = evento_id)),
 add constraint stock_movimientos_sentido_valido check (
  (tipo = 'stock_inicial' and cantidad_anterior = 0 and cantidad_delta >= 0)
  or (tipo = any (array['ajuste_entrada','correccion_entrada','devolucion_apta','transferencia_entrada','compra',
   'fraccion_entrada']) and cantidad_delta > 0)
  or (tipo = any (array['ajuste_salida','entrega','venta_directa','correccion_salida','transferencia_salida',
   'fraccion_salida']) and cantidad_delta < 0));

alter table public.stock_operaciones drop constraint stock_operaciones_tipo_check,
 add constraint stock_operaciones_tipo_check check (tipo in ('conteo','carga_vehiculo','baja_vehiculo','compra',
  'cierre_viaje','fraccion'));

-- Abre unidades del origen en un lugar: origen −n, fraccionado +n×unidades. Interno.
create function public.stock_abrir_origen(p_ubicacion uuid, p_producto uuid, p_origenes numeric, p_motivo text,
 p_ref_tipo text, p_ref uuid) returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare prod public.productos; origen_controlado boolean; anterior numeric;
begin
 select * into strict prod from public.productos where id = p_producto;
 select control_stock into origen_controlado from public.productos where id = prod.fracciona_de;
 if origen_controlado then
  insert into public.stock_actual(ubicacion_id, producto_id, cantidad) values (p_ubicacion, prod.fracciona_de, 0)
  on conflict (ubicacion_id, producto_id) do nothing;
  select s.cantidad into anterior from public.stock_actual s
  where s.ubicacion_id = p_ubicacion and s.producto_id = prod.fracciona_de for update;
  update public.stock_actual set cantidad = anterior - p_origenes, updated_at = clock_timestamp()
  where ubicacion_id = p_ubicacion and producto_id = prod.fracciona_de;
  insert into public.stock_movimientos(ubicacion_id, producto_id, tipo, cantidad_anterior, cantidad_delta,
   cantidad_nueva, motivo, usuario_id, referencia_tipo, referencia_id)
  values (p_ubicacion, prod.fracciona_de, 'fraccion_salida', anterior, -p_origenes, anterior - p_origenes,
   p_motivo, auth.uid(), p_ref_tipo, p_ref);
 end if;
 insert into public.stock_actual(ubicacion_id, producto_id, cantidad) values (p_ubicacion, p_producto, 0)
 on conflict (ubicacion_id, producto_id) do nothing;
 select s.cantidad into anterior from public.stock_actual s
 where s.ubicacion_id = p_ubicacion and s.producto_id = p_producto for update;
 update public.stock_actual set cantidad = anterior + p_origenes * prod.unidades_por_origen, updated_at = clock_timestamp()
 where ubicacion_id = p_ubicacion and producto_id = p_producto;
 insert into public.stock_movimientos(ubicacion_id, producto_id, tipo, cantidad_anterior, cantidad_delta,
  cantidad_nueva, motivo, usuario_id, referencia_tipo, referencia_id)
 values (p_ubicacion, p_producto, 'fraccion_entrada', anterior, p_origenes * prod.unidades_por_origen,
  anterior + p_origenes * prod.unidades_por_origen, p_motivo, auth.uid(), p_ref_tipo, p_ref);
end $$;
revoke all on function public.stock_abrir_origen(uuid, uuid, numeric, text, text, uuid) from public, anon, authenticated;

-- Vincular (o desvincular con p_origen_id null) un producto fraccionado con su origen.
create function public.stock_configurar_fraccion(p_producto_id uuid, p_origen_id uuid, p_unidades numeric)
returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
 perform public.stock_exigir_admin(); perform public.stock_exigir_operativo();
 if p_origen_id is null then
  update public.productos set fracciona_de = null, unidades_por_origen = null where id = p_producto_id;
  return;
 end if;
 if exists (select 1 from public.productos where id = p_origen_id and fracciona_de is not null)
  or exists (select 1 from public.productos where fracciona_de = p_producto_id) then
  raise exception 'Un producto no puede ser a la vez fraccionado y origen de otro' using errcode = 'PT422'; end if;
 update public.productos set fracciona_de = p_origen_id, unidades_por_origen = p_unidades where id = p_producto_id;
 if not found then raise exception 'Producto inexistente' using errcode = 'PT404'; end if;
end $$;

-- Fraccionar a mano: "Abrí 1 bolsa de 4 kg" → 4 de 1 kg.
create function public.stock_fraccionar(p_id uuid, p_producto_id uuid, p_origenes numeric, p_ubicacion text,
 p_fecha timestamptz) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare huella text; previo jsonb; loc uuid; fecha timestamptz; prod public.productos; res jsonb;
begin
 perform public.stock_exigir_admin(); perform public.stock_exigir_operativo();
 huella := public.stock_huella(jsonb_build_object('p', p_producto_id, 'n', p_origenes, 'u', p_ubicacion, 'f', p_fecha));
 previo := public.stock_operacion_previa(p_id, 'fraccion', huella);
 if previo is not null then return previo; end if;
 loc := public.stock_ubicacion(p_ubicacion);
 if loc is null then raise exception 'Ubicación inválida' using errcode = 'PT422'; end if;
 fecha := public.stock_validar_fecha(p_fecha);
 select * into prod from public.productos where id = p_producto_id for update;
 if not found or prod.fracciona_de is null then
  raise exception 'El producto no es fraccionado: configurá de qué producto sale' using errcode = 'PT422'; end if;
 if not prod.control_stock then
  raise exception 'El producto fraccionado no lleva stock: contalo primero' using errcode = 'PT422'; end if;
 if p_origenes is null or p_origenes <= 0 or p_origenes > 10000 or p_origenes <> round(p_origenes, 3) then
  raise exception 'Cantidad inválida' using errcode = 'PT422'; end if;
 insert into public.stock_operaciones(id, tipo, ubicacion_id, fecha_fisica, actor_id, request_hash, resultado)
 values (p_id, 'fraccion', loc, fecha, auth.uid(), huella, '{}');
 perform public.stock_abrir_origen(loc, p_producto_id, p_origenes, 'Fraccionado', 'stock_operacion', p_id);
 insert into public.stock_operacion_items(operacion_id, producto_id, cantidad, controlado)
 values (p_id, p_producto_id, p_origenes * prod.unidades_por_origen, true);
 res := jsonb_build_object('operacion_id', p_id, 'origenes', p_origenes,
  'unidades', p_origenes * prod.unidades_por_origen);
 update public.stock_operaciones set resultado = res where id = p_id;
 return res;
end $$;

revoke all on function public.stock_configurar_fraccion(uuid, uuid, numeric),
 public.stock_fraccionar(uuid, uuid, numeric, text, timestamptz) from public, anon;
grant execute on function public.stock_configurar_fraccion(uuid, uuid, numeric),
 public.stock_fraccionar(uuid, uuid, numeric, text, timestamptz) to authenticated;

-- El estado de stock incluye el vínculo de fraccionado.
drop function public.stock_estado();
create function public.stock_estado() returns table(producto_id uuid, control_stock boolean,
 deposito numeric, vehiculo numeric, deposito_contado_at timestamptz, vehiculo_contado_at timestamptz,
 fracciona_de uuid, unidades_por_origen numeric)
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare dep uuid := public.stock_ubicacion('deposito_alberdi'); veh uuid := public.stock_ubicacion('vehiculo');
begin
 perform public.stock_exigir_admin();
 return query select p.id, p.control_stock, d.cantidad, v.cantidad, d.contado_at, v.contado_at,
  p.fracciona_de, p.unidades_por_origen
 from public.productos p
 left join public.stock_actual d on d.producto_id = p.id and d.ubicacion_id = dep
 left join public.stock_actual v on v.producto_id = p.id and v.ubicacion_id = veh
 where p.activo order by p.nombre;
end $$;
revoke all on function public.stock_estado() from public, anon;
grant execute on function public.stock_estado() to authenticated;

-- Entregas: abren solas el origen de un fraccionado que no alcanza.
CREATE OR REPLACE FUNCTION public.stock_base_stock_aplicar_deltas(p_ubicacion_id uuid, p_evento_id uuid, p_items jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare evento public.stock_eventos; contenido jsonb; x jsonb; fila public.stock_actual; nueva numeric;
 producto uuid; delta numeric; controla boolean; aplicados integer := 0; existente integer;
 fr_origen uuid; fr_unidades numeric; fr_controla boolean; fr_hay numeric; abrir numeric;
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
