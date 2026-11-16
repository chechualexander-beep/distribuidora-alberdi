-- Pedidos y ventas directas cargados SIN SEÑAL: el teléfono los guarda y los envía al volver.
-- Regla del negocio: vale el precio que vio el cliente. Para poder respetarlo sin abrir la puerta
-- a precios inventados, se guarda el historial de precios: un precio anterior se acepta solo si
-- estaba vigente cuando se cargó el pedido (hasta 72 horas atrás). Queda anotado en la observación.
begin;

create table public.productos_precios_historial (
  id bigint generated always as identity primary key,
  producto_id uuid not null references public.productos(id) on delete cascade,
  tipo text not null check (tipo in ('normal','promo','interior')),
  precio numeric not null,
  vigente_hasta timestamptz not null default now()
);
create index productos_precios_historial_busqueda
  on public.productos_precios_historial(producto_id, tipo, vigente_hasta desc);
alter table public.productos_precios_historial enable row level security;
revoke all on public.productos_precios_historial from public, anon, authenticated;

create function public.registrar_precio_anterior() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if new.precio_normal is distinct from old.precio_normal and old.precio_normal is not null then
    insert into public.productos_precios_historial(producto_id,tipo,precio) values(old.id,'normal',old.precio_normal); end if;
  if new.precio_promo is distinct from old.precio_promo and old.precio_promo is not null then
    insert into public.productos_precios_historial(producto_id,tipo,precio) values(old.id,'promo',old.precio_promo); end if;
  if new.precio_interior is distinct from old.precio_interior and old.precio_interior is not null then
    insert into public.productos_precios_historial(producto_id,tipo,precio) values(old.id,'interior',old.precio_interior); end if;
  return null;
end $$;
revoke all on function public.registrar_precio_anterior() from public, anon, authenticated;
create trigger zz_registrar_precio_anterior after update of precio_normal, precio_promo, precio_interior
  on public.productos for each row execute function public.registrar_precio_anterior();

-- Igual que crear_pedido_interno (mismas validaciones, misma solicitud idempotente por p_id),
-- pero con p_precios_vistos_at: cuándo se vieron los precios en el teléfono.
create function public.crear_pedido_sin_conexion(
  p_id uuid, p_cliente_id uuid, p_tipo_precio text, p_tipo_operacion text, p_observacion text,
  p_fecha_entrega date, p_detalles jsonb, p_precios_vistos_at timestamptz
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
  solicitud public.solicitudes_pedido_interno; c public.clientes; huella text; e jsonb; p public.productos;
  cantidad numeric; v_tipo text; precio numeric; visto numeric; detalles jsonb := '[]'; notas text[] := '{}';
  v_obs text; tolerar boolean;
begin
  perform public.stock_exigir_operativo();
  if p_tipo_operacion='venta_directa' and not exists(select 1 from public.solicitudes_pedido_interno where id=p_id) then
    perform public.stock_exigir_venta_directa_v2(); end if;
  if not public.es_personal_activo() then raise exception 'Personal inactivo o sin autorización'; end if;
  if p_id is null then raise exception 'Solicitud inválida'; end if;
  select * into c from public.clientes where id=p_cliente_id for update;
  if not found then raise exception 'Cliente inexistente'; end if;
  huella := encode(sha256(convert_to(jsonb_build_object('cliente',p_cliente_id,'lista',p_tipo_precio,
    'operacion',p_tipo_operacion,'observacion',p_observacion,'fecha',p_fecha_entrega,'detalles',p_detalles)::text,'UTF8')),'hex');
  select * into solicitud from public.solicitudes_pedido_interno where id=p_id;
  if found then
    if solicitud.usuario_id is distinct from auth.uid() or solicitud.huella<>huella then
      raise exception 'La solicitud ya fue utilizada. Revisá tus pedidos'; end if;
    if solicitud.pedido_id is null then raise exception 'Este pedido fue eliminado'; end if;
    return solicitud.pedido_id;
  end if;
  if c.activo is not true or (not public.es_administrador() and c.preventista_id is distinct from auth.uid()) then
    raise exception 'Cliente no asignado o inactivo'; end if;
  if p_tipo_precio is null or p_tipo_precio not in ('normal','promo','interior') or p_tipo_operacion is null
     or p_tipo_operacion not in ('pedido','venta_directa') or p_fecha_entrega is null
     or length(coalesce(p_observacion,''))>1000 then
    raise exception 'Datos del pedido inválidos'; end if;
  -- Precios anteriores: solo si el pedido se cargó hace menos de 72 h (y no "en el futuro").
  tolerar := p_precios_vistos_at is not null and p_precios_vistos_at >= now() - interval '72 hours'
             and p_precios_vistos_at <= now() + interval '10 minutes';

  if jsonb_typeof(p_detalles) is distinct from 'array' then raise exception 'Detalle inválido'; end if;
  if jsonb_array_length(p_detalles) not between 1 and 300 then raise exception 'Cantidad de productos inválida'; end if;
  if exists(select 1 from jsonb_array_elements(p_detalles) x group by x->>'producto_id' having count(*)>1) then
    raise exception 'Producto duplicado'; end if;
  for e in select * from jsonb_array_elements(p_detalles) loop
    select * into p from public.productos where id=(e->>'producto_id')::uuid;
    if not found then raise exception 'Producto inexistente'; end if;
    if p.activo is not true or (not public.es_administrador() and not p.visible_preventistas) then
      raise exception 'Producto no disponible: %', p.nombre; end if;
    cantidad := (e->>'cantidad')::numeric; v_tipo := e->>'tipo_precio'; visto := (e->>'precio_unitario')::numeric;
    if cantidad is null or cantidad::text in ('NaN','Infinity','-Infinity') or cantidad<>trunc(cantidad)
       or cantidad not between 1 and 9999 then raise exception 'Cantidad inválida'; end if;
    if v_tipo is null or v_tipo not in ('normal','promo','interior') then raise exception 'Lista inválida'; end if;
    precio := case v_tipo when 'promo' then p.precio_promo when 'interior' then p.precio_interior else p.precio_normal end;
    if visto is distinct from precio then
      if tolerar and visto > 0 and exists(select 1 from public.productos_precios_historial h
           where h.producto_id=p.id and h.tipo=v_tipo and h.precio=visto and h.vigente_hasta >= p_precios_vistos_at) then
        notas := notas || format('%s: $%s (hoy $%s)', p.nombre, trim_scale(visto), trim_scale(precio));
        precio := visto;
      else
        raise exception 'Los precios cambiaron. Actualizá los productos';
      end if;
    end if;
    if precio is null or precio<=0 or precio::text in ('NaN','Infinity','-Infinity') then raise exception 'Precio inválido'; end if;
    detalles := detalles || jsonb_build_array(jsonb_build_object('producto_id',p.id,'cantidad',cantidad,
      'precio_unitario',precio,'subtotal',precio*cantidad,'tipo_precio',v_tipo,'costo_unitario',p.costo));
  end loop;

  v_obs := nullif(trim(coalesce(p_observacion,'')),'');
  if array_length(notas,1) > 0 then
    v_obs := concat_ws(E'\n', v_obs, '[Sin señal] Se respetó el precio que vio el cliente: ' || array_to_string(notas, '; '));
  end if;
  insert into public.pedidos(id,cliente_id,preventista_id,tipo_precio,tipo_operacion,total,observacion,fecha_entrega)
  values(p_id,p_cliente_id,auth.uid(),p_tipo_precio,p_tipo_operacion,
    (select sum((x->>'subtotal')::numeric) from jsonb_array_elements(detalles) x),v_obs,p_fecha_entrega);
  insert into public.pedido_detalles(pedido_id,producto_id,cantidad,precio_unitario,subtotal,tipo_precio,costo_unitario)
  select p_id,(x->>'producto_id')::uuid,(x->>'cantidad')::numeric,(x->>'precio_unitario')::numeric,
    (x->>'subtotal')::numeric,x->>'tipo_precio',(x->>'costo_unitario')::numeric from jsonb_array_elements(detalles) x;
  insert into public.solicitudes_pedido_interno(id,usuario_id,huella,pedido_id) values(p_id,auth.uid(),huella,p_id);
  return p_id;
end $$;
revoke all on function public.crear_pedido_sin_conexion(uuid,uuid,text,text,text,date,jsonb,timestamptz) from public, anon, authenticated;
grant execute on function public.crear_pedido_sin_conexion(uuid,uuid,text,text,text,date,jsonb,timestamptz) to authenticated;

commit;
