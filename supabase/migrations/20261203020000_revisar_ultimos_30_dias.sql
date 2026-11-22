-- "Stock a revisar": las diferencias de liquidación sin motivo, solo de los viajes de los últimos
-- 30 días (las de antes siguen en Liquidaciones, pero no llenan la tarjeta al actualizar).
begin;

CREATE OR REPLACE FUNCTION public.stock_a_revisar()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare negativos jsonb; sin_motivo jsonb := '[]'; sin_contar jsonb; total_sin_contar integer;
begin
 perform public.stock_exigir_deposito();
 select coalesce(jsonb_agg(jsonb_build_object('producto_id', p.id, 'nombre', p.nombre, 'ubicacion', u.codigo,
   'cantidad', sa.cantidad,
   'desde', (select max(m.created_at) from public.stock_movimientos m where m.ubicacion_id = sa.ubicacion_id
     and m.producto_id = sa.producto_id and m.cantidad_anterior >= 0 and m.cantidad_nueva < 0))
   order by p.nombre), '[]')
 into negativos
 from public.stock_actual sa join public.productos p on p.id = sa.producto_id
 join public.ubicaciones_stock u on u.id = sa.ubicacion_id
 where sa.cantidad < 0 and p.control_stock and p.activo;
 if public.es_administrador() then
  select coalesce(jsonb_agg(jsonb_build_object('viaje_id', v.id, 'cerrado_at', v.cerrado_at,
    'producto_id', (d->>'producto_id')::uuid, 'nombre', d->>'nombre', 'diferencia', (d->>'diferencia')::numeric)
    order by v.cerrado_at desc), '[]')
  into sin_motivo
  from public.viajes_vehiculo v cross join lateral jsonb_array_elements(coalesce(v.resumen->'diferencias', '[]')) d
  where v.estado = 'cerrado' and v.cerrado_at >= now() - interval '30 days' and not exists (select 1 from public.stock_liquidacion_motivos m
   where m.viaje_id = v.id and m.producto_id = (d->>'producto_id')::uuid);
 end if;
 with cont as (
  select p.id, p.nombre, max(sa.contado_at) contado_at, sum(sa.cantidad) cantidad
  from public.productos p join public.stock_actual sa on sa.producto_id = p.id
  where p.activo and p.control_stock group by p.id, p.nombre
 ), viejos as (
  select * from cont where cantidad > 0 and (contado_at is null or contado_at < now() - interval '30 days')
 )
 select (select count(*) from viejos),
  coalesce((select jsonb_agg(jsonb_build_object('producto_id', id, 'nombre', nombre, 'contado_at', contado_at)
   order by contado_at nulls first, nombre) from (select * from viejos order by contado_at nulls first, nombre limit 15) y), '[]')
 into total_sin_contar, sin_contar;
 return jsonb_build_object('negativos', negativos, 'sin_motivo', sin_motivo,
  'sin_contar', jsonb_build_object('total', total_sin_contar, 'productos', sin_contar));
end $function$;

notify pgrst, 'reload schema';
commit;
