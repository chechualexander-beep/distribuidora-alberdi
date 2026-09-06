create or replace function public.enviar_notificacion_pedido_editado(
  p_pedido_id uuid,
  p_editor_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret_key text;
begin
  select decrypted_secret
  into v_secret_key
  from vault.decrypted_secrets
  where name = 'notificaciones_webhook_key'
  limit 1;

  if v_secret_key is null then
    raise exception
      'No se encontró notificaciones_webhook_key en Vault';
  end if;

  perform net.http_post(
    url :=
      'https://vmbncsqapqdyffscwfwo.supabase.co/functions/v1/notificar-pedido-editado',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_secret_key
    ),
    body := jsonb_build_object(
      'pedido_id', p_pedido_id,
      'editor_id', p_editor_id
    ),
    timeout_milliseconds := 5000
  );
end;
$$;


create or replace function public.actualizar_pedido_activo(
  p_pedido_id uuid,
  p_total numeric,
  p_tipo_precio text,
  p_tipo_operacion text,
  p_observacion text,
  p_fecha_entrega date,
  p_detalles jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_preventista_id uuid;
begin
  select preventista_id
  into v_preventista_id
  from public.pedidos
  where id = p_pedido_id
    and facturado = false;

  if v_preventista_id is null then
    raise exception 'El pedido no existe o ya fue facturado.';
  end if;

  if not public.es_administrador()
     and v_preventista_id <> auth.uid() then
    raise exception 'No tenés permiso para editar este pedido.';
  end if;

  update public.pedidos
  set
    total = p_total,
    tipo_precio = p_tipo_precio,
    tipo_operacion = p_tipo_operacion,
    observacion = nullif(trim(p_observacion), ''),
    fecha_entrega = p_fecha_entrega
  where id = p_pedido_id;

  delete from public.pedido_detalles
  where pedido_id = p_pedido_id;

  insert into public.pedido_detalles (
    pedido_id,
    producto_id,
    cantidad,
    precio_unitario,
    subtotal,
    tipo_precio,
    costo_unitario
  )
  select
    p_pedido_id,
    (detalle->>'producto_id')::uuid,
    (detalle->>'cantidad')::numeric,
    (detalle->>'precio_unitario')::numeric,
    (detalle->>'subtotal')::numeric,
    detalle->>'tipo_precio',
    (detalle->>'costo_unitario')::numeric
  from jsonb_array_elements(p_detalles) as detalle;

  if not exists (
    select 1
    from public.pedido_detalles
    where pedido_id = p_pedido_id
  ) then
    raise exception 'El pedido debe contener al menos un producto.';
  end if;

  perform public.enviar_notificacion_pedido_editado(
    p_pedido_id,
    auth.uid()
  );
end;
$$;