-- Estadísticas de generación: no alteran pedidos, pagos ni liquidaciones.
create function public.estadisticas_comisiones(
 p_desde date, p_hasta date, p_preventista_id uuid default null,
 p_metrica text default 'cantidad'
) returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare vendedor uuid; resultado jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.usuarios where id=auth.uid() and activo is not false) then
  raise exception 'Sesión no autorizada';
 end if;
 if public.es_administrador() is true then vendedor:=p_preventista_id;
 else
  if p_preventista_id is not null and p_preventista_id<>auth.uid() then raise exception 'Solo podés consultar tus estadísticas'; end if;
  vendedor:=auth.uid();
 end if;
 if p_desde is null or p_hasta is null or p_hasta<p_desde or p_hasta-p_desde>3660 then raise exception 'Rango de fechas inválido (máximo diez años)'; end if;
 if p_metrica not in ('cantidad','venta','comision') or p_metrica is null then raise exception 'Métrica inválida'; end if;
 with eventos as materialized (
  select p.id pedido_id,p.cliente_id,d.producto_id,
   (coalesce(p.fecha_finalizacion,p.fecha_entrega::timestamp at time zone 'America/Argentina/Buenos_Aires') at time zone 'America/Argentina/Buenos_Aires')::date dia,
   'Entrega'::text tipo,d.cantidad_entregada cantidad,d.cantidad_entregada*d.precio_unitario venta,
   coalesce(d.importe_comision,0) comision,0::numeric devolucion,0::numeric ajuste
  from public.pedidos p join public.pedido_detalles d on d.pedido_id=p.id
  where p.resultado_entrega in ('entregado','parcial') and p.estado not in ('anulado','cancelado')
   and d.cantidad_entregada>0 and (vendedor is null or p.preventista_id=vendedor)
  union all
  select n.pedido_id,n.cliente_id,d.producto_id,
   (n.fecha at time zone 'America/Argentina/Buenos_Aires')::date,'Devolución',-nd.cantidad,-nd.importe,-nd.comision,nd.importe,nd.comision
  from public.notas_credito n join public.nota_credito_detalles nd on nd.nota_id=n.id
   join public.pedido_detalles d on d.id=nd.pedido_detalle_id
  where vendedor is null or n.preventista_id=vendedor
 ), e as materialized (select * from eventos where dia between p_desde and p_hasta),
 clientes_top as (
  select e.cliente_id id,c.nombre_comercio nombre,sum(e.venta) venta,sum(e.comision) comision
  from e join public.clientes c on c.id=e.cliente_id
  group by e.cliente_id,c.nombre_comercio order by comision desc,e.cliente_id limit 10
 ), productos_top as (
  select e.producto_id id,p.nombre,sum(e.cantidad) cantidad,sum(e.venta) venta,sum(e.comision) comision
  from e join public.productos p on p.id=e.producto_id group by e.producto_id,p.nombre
  order by case p_metrica when 'cantidad' then sum(e.cantidad) when 'venta' then sum(e.venta) else sum(e.comision) end desc,e.producto_id limit 10
 ), dias as (
  select distinct case when p_hasta-p_desde>62 then date_trunc('week',d)::date else d::date end dia
  from generate_series(p_desde::timestamp,p_hasta::timestamp,interval '1 day') d
 ), serie as (
  select dias.dia,coalesce(sum(e.venta),0) venta,coalesce(sum(e.comision),0) comision from dias
  left join e on (case when p_hasta-p_desde>62 then date_trunc('week',e.dia)::date else e.dia end)=dias.dia
  group by dias.dia order by dias.dia
 )
 select jsonb_build_object(
  'venta_bruta',coalesce(sum(venta+devolucion),0),'devoluciones',coalesce(sum(devolucion),0),
  'venta_neta',coalesce(sum(venta),0),'comision_bruta',coalesce(sum(comision+ajuste),0),
  'ajustes',coalesce(sum(ajuste),0),'comision_neta',coalesce(sum(comision),0),
  'clientes',count(distinct cliente_id) filter(where tipo='Entrega'),
  'promedio',case when count(distinct cliente_id) filter(where tipo='Entrega')>0 then
   round(coalesce(sum(venta),0)/count(distinct cliente_id) filter(where tipo='Entrega'),2) else null end,
  'hay_movimientos',count(*)>0,'semanal',p_hasta-p_desde>62,
  'ranking_clientes',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('operaciones',(
    select jsonb_agg(to_jsonb(o) order by o.dia desc,o.pedido_id) from
    (select pedido_id,dia,tipo,sum(venta) venta,sum(comision) comision from e where cliente_id=c.id group by pedido_id,dia,tipo) o
   )) order by c.comision desc,c.id) from clientes_top c),'[]'::jsonb),
  'ranking_productos',coalesce((select jsonb_agg(to_jsonb(p) order by case p_metrica when 'cantidad' then p.cantidad when 'venta' then p.venta else p.comision end desc,p.id) from productos_top p),'[]'::jsonb),
  'serie',coalesce((select jsonb_agg(to_jsonb(s) order by s.dia) from serie s),'[]'::jsonb)
 ) into resultado from e;
 return resultado;
end $$;
revoke all on function public.estadisticas_comisiones(date,date,uuid,text) from public,anon;
grant execute on function public.estadisticas_comisiones(date,date,uuid,text) to authenticated;
