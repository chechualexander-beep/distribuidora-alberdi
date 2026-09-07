create or replace function public.obtener_detalles_liquidados_propios(
  p_detalle_ids uuid[]
)
returns table (
  pedido_detalle_id uuid
)
language sql
security definer
set search_path = public
as $$
  select ld.pedido_detalle_id
  from public.liquidacion_detalles ld
  join public.pedido_detalles pd
    on pd.id = ld.pedido_detalle_id
  join public.pedidos p
    on p.id = pd.pedido_id
  where ld.pedido_detalle_id = any(p_detalle_ids)
    and p.preventista_id = auth.uid();
$$;

revoke all
on function public.obtener_detalles_liquidados_propios(uuid[])
from public;

grant execute
on function public.obtener_detalles_liquidados_propios(uuid[])
to authenticated;