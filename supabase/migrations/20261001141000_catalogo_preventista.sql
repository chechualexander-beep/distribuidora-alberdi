begin;
alter table public.catalogos_clientes add column preventista_comision_id uuid references public.usuarios(id);
-- Instantánea por pedido: renovar/asignar otro enlace no cambia ventas anteriores.
alter table public.pedidos add column catalogo_preventista_id uuid references public.usuarios(id);
alter table public.pedidos add constraint catalogo_asignacion_consistente check
  (catalogo_preventista_id is null or (origen='catalogo' and preventista_id=catalogo_preventista_id));

create function public.configurar_catalogo_cliente_v2(
  p_cliente_id uuid,p_base text,p_categorias jsonb,p_productos jsonb,
  p_renovar boolean,p_activo boolean,p_preventista_id uuid
) returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v_config public.catalogos_clientes; v_token text;
begin
  if not public.es_administrador() then raise exception 'Solo un administrador puede configurar el catálogo'; end if;
  perform 1 from public.clientes where id=p_cliente_id and activo is true for update;
  if not found then raise exception 'Cliente inactivo o inexistente'; end if;
  select * into v_config from public.catalogos_clientes where cliente_id=p_cliente_id;
  if p_activo and p_preventista_id is not null and not exists(
    select 1 from public.usuarios where id=p_preventista_id and activo is true and rol='preventista'
  ) then raise exception 'Elegí un preventista activo'; end if;
  if v_config.token_hash is not null and
     p_preventista_id is distinct from v_config.preventista_comision_id and not coalesce(p_renovar,false)
  then raise exception 'Renová el enlace para cambiar el preventista. Los pedidos anteriores conservarán su asignación'; end if;
  v_token := public.configurar_catalogo_cliente(p_cliente_id,p_base,p_categorias,p_productos,p_renovar,p_activo);
  update public.catalogos_clientes set preventista_comision_id=p_preventista_id where cliente_id=p_cliente_id;
  return v_token;
end $$;
revoke all on function public.configurar_catalogo_cliente_v2(uuid,text,jsonb,jsonb,boolean,boolean,uuid) from public,anon,authenticated;
grant execute on function public.configurar_catalogo_cliente_v2(uuid,text,jsonb,jsonb,boolean,boolean,uuid) to authenticated;

create or replace function public.comision_pedido_catalogo() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_pedido public.pedidos; v_porcentaje numeric;
begin
  select * into v_pedido from public.pedidos where id=new.pedido_id;
  if v_pedido.origen <> 'catalogo' then return new; end if;
  if v_pedido.catalogo_preventista_id is null then
    new.porcentaje_comision := 0;
    new.importe_comision := 0;
    return new;
  end if;
  if tg_op='UPDATE' and old.producto_id=new.producto_id and old.tipo_precio is not distinct from new.tipo_precio
     and old.pedido_id=new.pedido_id then
    v_porcentaje := old.porcentaje_comision;
  else
    select case new.tipo_precio when 'promo' then comision_promo
      when 'interior' then comision_interior else comision_normal end into v_porcentaje
    from public.productos where id=new.producto_id;
  end if;
  if v_porcentaje is null then v_porcentaje:=0; end if;
  if v_porcentaje::text in ('NaN','Infinity','-Infinity') or v_porcentaje not between 0 and 100
  then raise exception 'El producto tiene una comisión inválida'; end if;
  new.porcentaje_comision := v_porcentaje;
  -- Como en los pedidos internos, se liquida únicamente la cantidad entregada.
  new.importe_comision := round(coalesce(new.cantidad_entregada,0)*new.precio_unitario*v_porcentaje/100,2);
  return new;
end $$;
create or replace function public.crear_pedido_catalogo(p_token text,p_solicitud_id uuid,p_items jsonb,p_observacion text default '')
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cliente uuid; v_config public.catalogos_clientes; v_pedido uuid; v_item jsonb;
  v_producto record; v_cantidad numeric; v_total numeric := 0; v_detalles jsonb := '[]';
begin
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'Enlace inválido o desactivado'; end if;
  select cliente_id into v_cliente from public.catalogos_clientes
  where token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex');
  if not found then raise exception 'Enlace inválido o desactivado'; end if;
  perform 1 from public.clientes where id=v_cliente and activo is true for update;
  if not found then raise exception 'Enlace inválido o desactivado'; end if;
  select * into v_config from public.catalogos_clientes where cliente_id=v_cliente and activo
    and token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex');
  if not found or not exists(select 1 from public.usuarios where id=v_config.responsable_id and activo is true and rol='administrador') then
    raise exception 'Enlace inválido o desactivado'; end if;
  if v_config.vence_at <= clock_timestamp() then raise sqlstate 'PT410' using message='Este enlace venció. Pedile a la distribuidora un nuevo enlace para hacer tu pedido.'; end if;
  if p_solicitud_id is null then raise exception 'Solicitud inválida'; end if;
  select pedido_id into v_pedido from public.catalogo_solicitudes where cliente_id=v_cliente and solicitud_id=p_solicitud_id;
  if found then
    if v_pedido is null then raise exception 'Este pedido fue eliminado. Contactá a la distribuidora'; end if;
    return jsonb_build_object('pedido_id',v_pedido,'total',(select total from public.pedidos where id=v_pedido));
  end if;
  if v_config.preventista_comision_id is not null and not exists(
    select 1 from public.usuarios where id=v_config.preventista_comision_id and activo is true and rol='preventista'
  ) then raise exception 'Este enlace necesita actualizarse. Contactá a la distribuidora'; end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Carrito inválido'; end if;
  if jsonb_array_length(p_items) not between 1 and 300 then raise exception 'Carrito vacío o demasiado extenso'; end if;
  if length(coalesce(p_observacion,''))>1000 then raise exception 'Observación demasiado extensa'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) e group by e->>'producto_id' having count(*)>1) then raise exception 'Producto duplicado'; end if;
  -- Límite por enlace para evitar dobles pedidos repetidos o abuso accidental.
  if (select count(*) from public.catalogo_solicitudes where cliente_id=v_cliente and created_at>now()-interval '1 hour')>=20 then
    raise exception 'Demasiados pedidos. Contactá a la distribuidora'; end if;
  -- Precios en una única instantánea; nunca se acepta un importe del navegador.
  for v_producto in select * from public.catalogo_productos_internos(v_cliente) loop
    select e into v_item from jsonb_array_elements(p_items) e where e->>'producto_id'=v_producto.id::text;
    if not found then continue; end if;
    v_cantidad := (v_item->>'cantidad')::numeric;
    if v_cantidad is null or v_cantidad::text in ('NaN','Infinity','-Infinity') or v_cantidad<>trunc(v_cantidad) or v_cantidad not between 1 and 9999 then raise exception 'Cantidad inválida'; end if;
    if v_producto.precio is null or v_producto.precio<=0 or v_producto.precio::text in ('NaN','Infinity','-Infinity') then raise exception 'Producto sin precio disponible'; end if;
    if (v_item->>'precio_visto')::numeric is distinct from v_producto.precio then
      raise exception 'Los precios cambiaron. Actualizá el catálogo y revisá tu pedido'; end if;
    v_total := v_total+v_producto.precio*v_cantidad;
    v_detalles := v_detalles || jsonb_build_array(jsonb_build_object('producto_id',v_producto.id,'cantidad',v_cantidad,
      'precio',v_producto.precio,'tipo',v_producto.tipo,'costo',v_producto.costo));
  end loop;
  if jsonb_array_length(v_detalles)<>jsonb_array_length(p_items) then raise exception 'Un producto ya no está disponible. Actualizá el catálogo'; end if;
  if v_config.vence_at <= clock_timestamp() then raise sqlstate 'PT410' using message='Este enlace venció. Pedile a la distribuidora un nuevo enlace para hacer tu pedido.'; end if;
  insert into public.pedidos(cliente_id,preventista_id,tipo_precio,estado,total,tipo_operacion,origen,observacion,catalogo_preventista_id)
  values(v_cliente,coalesce(v_config.preventista_comision_id,v_config.responsable_id),v_config.base,'pendiente',v_total,'pedido','catalogo',
    '[Catálogo web] ' || trim(coalesce(p_observacion,'')),v_config.preventista_comision_id) returning id into v_pedido;
  insert into public.pedido_detalles(pedido_id,producto_id,cantidad,precio_unitario,subtotal,tipo_precio,costo_unitario,porcentaje_comision,importe_comision)
  select v_pedido,(e->>'producto_id')::uuid,(e->>'cantidad')::numeric,(e->>'precio')::numeric,
    (e->>'cantidad')::numeric*(e->>'precio')::numeric,e->>'tipo',(e->>'costo')::numeric,0,0
  from jsonb_array_elements(v_detalles) e;
  insert into public.catalogo_solicitudes(cliente_id,solicitud_id,pedido_id) values(v_cliente,p_solicitud_id,v_pedido);
  return jsonb_build_object('pedido_id',v_pedido,'total',v_total);
end $$;

commit;
