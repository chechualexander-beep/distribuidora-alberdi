-- Agregar importes antes de unir cobros y detalles evita multiplicar ventas.
create or replace function public.resumen_comercial(
  p_inicio timestamptz,
  p_fin timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_resumen jsonb;
begin
  if public.es_administrador() is not true then
    raise exception 'Solo un administrador puede consultar el resumen comercial';
  end if;
  if p_inicio is null or p_fin is null or p_fin <= p_inicio then
    raise exception 'El período no es válido';
  end if;

  with operaciones as (
    select p.*,
      -- Operaciones históricas sin fecha de finalización conservan su
      -- fecha de entrega, interpretada como medianoche argentina.
      coalesce(p.fecha_finalizacion,
        p.fecha_entrega::timestamp at time zone 'America/Argentina/Buenos_Aires'
      ) as fecha_efectiva
    from public.pedidos p
    where p.estado not in ('cancelado', 'anulado')
  ), facturacion as (
    select coalesce(sum(coalesce(d.cantidad_facturada, 0)
      * coalesce(d.precio_unitario, 0)), 0) as preventa
    from operaciones p
    join public.pedido_detalles d on d.pedido_id = p.id
    where p.tipo_operacion = 'pedido' and p.facturado = true
      and p.fecha_facturacion >= p_inicio and p.fecha_facturacion < p_fin
  ), entregas as (
    select p.tipo_operacion, p.preventista_id,
      coalesce(d.cantidad_entregada, 0) * coalesce(d.precio_unitario, 0) as importe,
      coalesce(d.cantidad_entregada, 0) * coalesce(d.costo_unitario, 0) as costo,
      coalesce(d.importe_comision, 0) as comision
    from operaciones p
    join public.pedido_detalles d on d.pedido_id = p.id
    where p.resultado_entrega in ('entregado', 'parcial')
      and p.fecha_efectiva >= p_inicio and p.fecha_efectiva < p_fin
  ), totales_entrega as (
    select coalesce(sum(importe), 0) as total,
      coalesce(sum(importe) filter (where tipo_operacion = 'pedido'), 0) as preventa,
      coalesce(sum(importe) filter (where tipo_operacion = 'venta_directa'), 0) as directa,
      coalesce(sum(costo), 0) as costo,
      coalesce(sum(comision), 0) as comisiones
    from entregas
  ), cobros as (
    select id, importe from public.cobros_cliente
    where fecha_pago >= p_inicio and fecha_pago < p_fin
  ), aplicaciones as (
    -- La fecha que manda es la del cobro, no la del pedido pagado.
    select
      coalesce(sum(pp.importe) filter (where p.tipo_operacion = 'pedido'), 0) as preventa,
      coalesce(sum(pp.importe) filter (where p.tipo_operacion = 'venta_directa'), 0) as directa
    from cobros c
    join public.pedido_pagos pp on pp.cobro_id = c.id
    join public.pedidos p on p.id = pp.pedido_id
  ), total_cobros as (
    select coalesce(sum(importe), 0) as total from cobros
  ), comisiones_preventista as (
    select preventista_id, sum(comision) as importe
    from entregas where preventista_id is not null
    group by preventista_id
  )
  select jsonb_build_object(
    'venta_total', f.preventa + e.directa,
    'venta_preventa', f.preventa,
    'venta_directa', e.directa,
    'entrega_total', e.total,
    'entrega_preventa', e.preventa,
    'entrega_directa', e.directa,
    'entrega_sin_clasificar', e.total - e.preventa - e.directa,
    'recaudacion_total', c.total,
    'recaudacion_preventa', a.preventa,
    'recaudacion_directa', a.directa,
    'recaudacion_sin_clasificar', c.total - a.preventa - a.directa,
    'costo_mercaderia', e.costo,
    'comisiones', e.comisiones,
    'ganancia', e.total - e.costo - e.comisiones,
    'comisiones_por_preventista', coalesce((
      select jsonb_object_agg(preventista_id::text, importe)
      from comisiones_preventista
    ), '{}'::jsonb)
  ) into v_resumen
  from facturacion f cross join totales_entrega e
  cross join aplicaciones a cross join total_cobros c;

  return v_resumen;
end;
$$;

revoke all on function public.resumen_comercial(timestamptz, timestamptz) from public;
revoke all on function public.resumen_comercial(timestamptz, timestamptz) from anon;
grant execute on function public.resumen_comercial(timestamptz, timestamptz) to authenticated;
