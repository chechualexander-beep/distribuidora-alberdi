-- Registra en el repo el cambio aplicado a mano en PRODUCCIÓN el 10/10/2026
-- (baja de un preventista): el personal inactivo no puede consultar sus liquidaciones.
-- Idempotente: en PRODUCCIÓN deja la función igual a como ya está.
create or replace function public.obtener_detalles_liquidados_propios(
  p_detalle_ids uuid[]
)
returns table (pedido_detalle_id uuid)
language sql
security definer
set search_path = public, pg_temp
as $function$
  select ld.pedido_detalle_id
  from public.liquidacion_detalles ld
  join public.pedido_detalles pd on pd.id=ld.pedido_detalle_id
  join public.pedidos p on p.id=pd.pedido_id
  where ld.pedido_detalle_id=any(p_detalle_ids)
    and p.preventista_id=auth.uid()
    and public.es_personal_activo() is true;
$function$;
