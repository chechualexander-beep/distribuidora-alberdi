-- Facturación de un pedido en UNA sola operación: o queda todo facturado, o nada.
-- Reemplaza los pasos sueltos de la app (número, líneas, agregados, marca de facturado),
-- que con un corte de internet podían dejar el pedido a medio facturar.
-- Cada intento lleva p_solicitud_id: si se repite (por ejemplo, tras un corte), devuelve el
-- mismo resultado sin gastar otro número ni facturar dos veces.
begin;

create table public.facturacion_solicitudes (
  solicitud_id uuid primary key,
  pedido_id uuid not null unique references public.pedidos(id),
  numero_comprobante text not null,
  fecha_facturacion timestamptz not null,
  actor_id uuid not null,
  created_at timestamptz not null default now()
);
alter table public.facturacion_solicitudes enable row level security;
revoke all on public.facturacion_solicitudes from public, anon, authenticated;

-- p_originales: TODAS las líneas originales del pedido [{detalle_id, cantidad_facturada}] (0 = quitada).
-- p_agregados: productos sumados al facturar [{producto_id, tipo_precio, cantidad_facturada, precio_unitario}];
--   el precio se valida contra la lista vigente del servidor.
create function public.facturar_pedido(
  p_solicitud_id uuid, p_pedido_id uuid, p_originales jsonb, p_agregados jsonb default '[]'
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_previa public.facturacion_solicitudes; v_pedido public.pedidos; x jsonb; q numeric;
  v_det public.pedido_detalles; v_prod public.productos; v_lista text; v_precio numeric;
  v_numero text; v_fecha timestamptz := now(); v_cant integer;
begin
  if not public.es_administrador() then raise exception 'Solo un administrador puede facturar' using errcode='PT403'; end if;
  if p_solicitud_id is null or p_pedido_id is null then raise exception 'Solicitud inválida' using errcode='PT422'; end if;
  -- Mismo orden de bloqueos que el resto de la facturación y las finalizaciones.
  perform pg_advisory_xact_lock(829001);

  select * into v_previa from public.facturacion_solicitudes where solicitud_id=p_solicitud_id;
  if found then
    if v_previa.pedido_id <> p_pedido_id then raise exception 'Solicitud de otro pedido' using errcode='PT409'; end if;
    return jsonb_build_object('numero_comprobante',v_previa.numero_comprobante,
      'fecha_facturacion',v_previa.fecha_facturacion,'repetida',true);
  end if;

  select * into v_pedido from public.pedidos where id=p_pedido_id for update;
  if not found then raise exception 'El pedido no existe' using errcode='PT404'; end if;
  if v_pedido.facturado then
    raise exception 'El pedido ya está facturado (comprobante %)', coalesce(v_pedido.numero_comprobante,'sin número') using errcode='PT409';
  end if;
  if v_pedido.resultado_entrega is distinct from 'pendiente' then
    raise exception 'El pedido ya fue finalizado y no se puede facturar desde acá' using errcode='PT409';
  end if;

  if jsonb_typeof(p_originales) is distinct from 'array' or jsonb_typeof(coalesce(p_agregados,'[]')) is distinct from 'array'
     or jsonb_array_length(p_originales) > 500 or jsonb_array_length(coalesce(p_agregados,'[]')) > 500 then
    raise exception 'Líneas inválidas' using errcode='PT422'; end if;
  -- Deben venir todas las líneas originales, una sola vez cada una.
  select count(*) into v_cant from public.pedido_detalles where pedido_id=p_pedido_id;
  if v_cant <> jsonb_array_length(p_originales)
     or exists(select 1 from jsonb_array_elements(p_originales) e group by e->>'detalle_id' having count(*)>1) then
    raise exception 'El pedido cambió mientras lo facturabas. Volvé a abrirlo' using errcode='PT409'; end if;

  for x in select value from jsonb_array_elements(p_originales) loop
    q := (x->>'cantidad_facturada')::numeric;
    if q is null or q < 0 or q > 9999999 or q::text in ('NaN','Infinity','-Infinity') then
      raise exception 'Cantidad inválida' using errcode='PT422'; end if;
    select * into v_det from public.pedido_detalles where id=(x->>'detalle_id')::uuid and pedido_id=p_pedido_id for update;
    if not found then raise exception 'El pedido cambió mientras lo facturabas. Volvé a abrirlo' using errcode='PT409'; end if;
    update public.pedido_detalles set cantidad_facturada=q where id=v_det.id;
  end loop;

  for x in select value from jsonb_array_elements(coalesce(p_agregados,'[]')) loop
    q := (x->>'cantidad_facturada')::numeric;
    v_lista := x->>'tipo_precio';
    if q is null or q <= 0 or q > 9999999 or v_lista is null or v_lista not in ('normal','promo','interior') then
      raise exception 'Producto agregado inválido' using errcode='PT422'; end if;
    select * into v_prod from public.productos where id=(x->>'producto_id')::uuid;
    if not found then raise exception 'Un producto agregado ya no existe' using errcode='PT422'; end if;
    v_precio := case v_lista when 'normal' then v_prod.precio_normal when 'promo' then v_prod.precio_promo else v_prod.precio_interior end;
    if v_precio is null or (x->>'precio_unitario')::numeric is distinct from v_precio then
      raise exception 'Cambió el precio de %. Volvé a abrir el pedido', v_prod.nombre using errcode='PT409'; end if;
    insert into public.pedido_detalles(pedido_id,producto_id,cantidad,precio_unitario,subtotal,tipo_precio,cantidad_facturada)
    values(p_pedido_id,v_prod.id,q,v_precio,q*v_precio,v_lista,q);
  end loop;

  v_numero := nextval('public.numero_comprobante_seq')::text;
  update public.pedidos set facturado=true, fecha_facturacion=v_fecha, numero_comprobante=v_numero where id=p_pedido_id;
  insert into public.facturacion_solicitudes(solicitud_id,pedido_id,numero_comprobante,fecha_facturacion,actor_id)
  values(p_solicitud_id,p_pedido_id,v_numero,v_fecha,auth.uid());
  return jsonb_build_object('numero_comprobante',v_numero,'fecha_facturacion',v_fecha,'repetida',false);
end $$;
revoke all on function public.facturar_pedido(uuid,uuid,jsonb,jsonb) from public, anon, authenticated;
grant execute on function public.facturar_pedido(uuid,uuid,jsonb,jsonb) to authenticated;

commit;
