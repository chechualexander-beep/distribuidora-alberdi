CREATE OR REPLACE FUNCTION public.eliminar_pedido_pendiente(
  p_pedido_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_usuario_id uuid := auth.uid();
  v_preventista_id uuid;
  v_facturado boolean;
  v_resultado_entrega text;
  v_es_admin boolean;
begin
  if v_usuario_id is null then
    raise exception 'Usuario no autenticado';
  end if;

  select
    p.preventista_id,
    p.facturado,
    p.resultado_entrega
  into
    v_preventista_id,
    v_facturado,
    v_resultado_entrega
  from public.pedidos p
  where p.id = p_pedido_id;

  if not found then
    raise exception 'Pedido no encontrado';
  end if;

  select exists (
    select 1
    from public.usuarios u
    where u.id = v_usuario_id
      and u.rol = 'administrador'
      and u.activo = true
  )
  into v_es_admin;

  if not v_es_admin
     and v_preventista_id <> v_usuario_id then
    raise exception 'No tenés permiso para eliminar este pedido';
  end if;

  if v_facturado = true
     or v_resultado_entrega <> 'pendiente' then
    raise exception
      'Solo se pueden eliminar pedidos no facturados y pendientes de entrega';
  end if;

  if exists (
    select 1
    from public.pedido_pagos
    where pedido_id = p_pedido_id
  ) then
    raise exception
      'El pedido posee pagos asociados y no puede eliminarse';
  end if;

  if exists (
    select 1
    from public.liquidacion_detalles ld
    join public.pedido_detalles pd
      on pd.id = ld.pedido_detalle_id
    where pd.pedido_id = p_pedido_id
  ) then
    raise exception
      'El pedido posee comisiones liquidadas y no puede eliminarse';
  end if;

  delete from public.pedido_detalles
  where pedido_id = p_pedido_id;

  delete from public.pedidos
  where id = p_pedido_id;
end;
$function$;