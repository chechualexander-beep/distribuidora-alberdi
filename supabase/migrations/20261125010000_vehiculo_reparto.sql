-- "Lo que llevamos": lo libre para venta directa descuenta también lo de los pedidos del reparto
-- (facturados y sin entregar), no solo las ventas directas del viaje sin entregar.
-- comprometido = ventas + reparto; disponible = en_vehiculo - comprometido.
create or replace function public.stock_vehiculo_disponible() returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare veh uuid; viaje public.viajes_vehiculo; productos jsonb;
begin
 if public.es_personal_activo() is not true then
  raise exception 'Solo personal activo' using errcode = 'PT403'; end if;
 veh := public.stock_ubicacion('vehiculo');
 select * into viaje from public.viajes_vehiculo where ubicacion_id = veh and estado = 'abierto';
 select coalesce(jsonb_agg(jsonb_build_object('producto_id', t.producto_id, 'en_vehiculo', t.en_vehiculo,
   'ventas', t.ventas, 'reparto', t.reparto, 'comprometido', t.ventas + t.reparto,
   'disponible', t.en_vehiculo - t.ventas - t.reparto) order by t.nombre), '[]')
 into productos
 from (
  select p.id producto_id, p.nombre, coalesce(sa.cantidad, 0) en_vehiculo,
   coalesce((select sum(d.cantidad) from public.pedido_detalles d join public.pedidos pe on pe.id = d.pedido_id
    where d.producto_id = p.id and viaje.id is not null and pe.viaje_id = viaje.id
     and pe.tipo_operacion = 'venta_directa' and pe.resultado_entrega = 'pendiente'
     and pe.estado not in ('anulado', 'cancelado')), 0) ventas,
   coalesce((select sum(coalesce(d.cantidad_facturada, d.cantidad)) from public.pedido_detalles d
    join public.pedidos pe on pe.id = d.pedido_id
    where d.producto_id = p.id and pe.tipo_operacion = 'pedido' and pe.facturado
     and pe.resultado_entrega = 'pendiente' and pe.estado not in ('anulado', 'cancelado')), 0) reparto
  from public.productos p
  left join public.stock_actual sa on sa.producto_id = p.id and sa.ubicacion_id = veh
  where p.activo and p.control_stock
 ) t where t.en_vehiculo <> 0 or t.ventas <> 0;
 return jsonb_build_object('viaje', case when viaje.id is null then null else jsonb_build_object(
   'id', viaje.id, 'preventista_id', viaje.preventista_id, 'abierto_at', viaje.abierto_at) end,
  'consultado_at', now(), 'productos', productos);
end $$;
