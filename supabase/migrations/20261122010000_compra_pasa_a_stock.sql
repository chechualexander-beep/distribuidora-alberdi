-- Anotar compra de un producto "a pedido": pasa a llevar stock con lo comprado (18/11/2026).
-- Antes solo quedaba el costo; al comprar se espera ver el stock actualizado.
CREATE OR REPLACE FUNCTION public.stock_registrar_compra(p_id uuid, p_ubicacion text, p_items jsonb, p_fecha timestamp with time zone, p_proveedor text DEFAULT NULL::text, p_actualizar_costo boolean DEFAULT false, p_observacion text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare huella text; previo jsonb; loc uuid; veh uuid; fecha timestamptz; it record; control boolean;
 viaje uuid; con_stock integer := 0; a_pedido integer := 0; nuevos integer := 0; total numeric := 0; res jsonb;
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
   -- Producto "a pedido" que se compra: pasa a llevar stock con lo comprado en ese lugar.
   update public.productos set control_stock = true where id = it.producto_id;
   perform public.stock_fijar(loc, it.producto_id, it.cantidad,
    left(coalesce('Compra · ' || nullif(btrim(p_proveedor), ''), 'Compra') || ' (pasa a llevar stock)', 200), p_id, fecha);
   nuevos := nuevos + 1;
   con_stock := con_stock + 1;
  end if;
  if p_actualizar_costo and it.costo > 0 then
   update public.productos set costo = it.costo where id = it.producto_id;
  end if;
  total := total + it.cantidad * coalesce(it.costo, 0);
  insert into public.stock_operacion_items(operacion_id, producto_id, cantidad, costo_unitario, controlado)
  values (p_id, it.producto_id, it.cantidad, it.costo, true);
 end loop;
 res := jsonb_build_object('operacion_id', p_id, 'total', round(total, 2), 'con_stock', con_stock, 'a_pedido', a_pedido,
  'nuevos_con_stock', nuevos);
 update public.stock_operaciones set resultado = res where id = p_id;
 return res;
end $function$;
