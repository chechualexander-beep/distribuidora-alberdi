-- El plazo solo se reinicia al generar un token nuevo.
begin;
alter table public.catalogos_clientes add column vence_at timestamptz;
-- Los enlaces existentes conservan como referencia su última configuración.
update public.catalogos_clientes set vence_at=updated_at+interval '12 hours';
alter table public.catalogos_clientes alter column vence_at set not null;
create or replace function public.configurar_catalogo_cliente(
  p_cliente_id uuid, p_base text, p_categorias jsonb, p_productos jsonb,
  p_renovar boolean default false, p_activo boolean default true
) returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare v_token text; v_config public.catalogos_clientes;
begin
  if not public.es_administrador() then raise exception 'Solo un administrador puede configurar el catálogo'; end if;
  if p_base is null or p_base not in ('normal','promo','interior') then raise exception 'Lista base inválida'; end if;
  if p_activo is null or p_renovar is null or p_categorias is null or p_productos is null
     or jsonb_typeof(p_categorias) <> 'object' or jsonb_typeof(p_productos) <> 'object' then
    raise exception 'Configuración inválida';
  end if;
  if exists (select 1 from jsonb_each_text(p_categorias) where value not in ('normal','promo','interior') or trim(key) = '' or key <> lower(trim(key)))
     or exists (select 1 from jsonb_each_text(p_productos) e where value not in ('normal','promo','interior')
       or not exists(select 1 from public.productos p where p.id::text=e.key)) then
    raise exception 'Excepciones inválidas';
  end if;
  -- Bloqueo del cliente serializa configuración, revocación y pedidos.
  perform 1 from public.clientes where id=p_cliente_id and activo is true for update;
  if not found then raise exception 'Cliente inactivo o inexistente'; end if;
  select * into v_config from public.catalogos_clientes where cliente_id=p_cliente_id;
  if p_renovar or v_config.token_hash is null then
    v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  end if;
  insert into public.catalogos_clientes(cliente_id,base,categorias,productos,token_hash,responsable_id,activo,vence_at)
  values(p_cliente_id,p_base,p_categorias,p_productos,
    case when v_token is null then v_config.token_hash else encode(sha256(convert_to(v_token,'UTF8')),'hex') end,
    auth.uid(),p_activo,case when v_token is not null then clock_timestamp()+interval '12 hours' else v_config.vence_at end)
  on conflict(cliente_id) do update set base=excluded.base,categorias=excluded.categorias,
    productos=excluded.productos,token_hash=excluded.token_hash,activo=excluded.activo,vence_at=excluded.vence_at,
    updated_at=now();
  return v_token;
end $$;

create or replace function public.obtener_catalogo_cliente(p_token text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cliente uuid; v_nombre text; v_productos jsonb; v_vence timestamptz;
begin
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'Enlace inválido o desactivado'; end if;
  select c.cliente_id,cl.nombre_comercio,c.vence_at into v_cliente,v_nombre,v_vence
  from public.catalogos_clientes c join public.clientes cl on cl.id=c.cliente_id
  join public.usuarios u on u.id=c.responsable_id and u.activo is true and u.rol='administrador'
  where c.token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex') and c.activo and cl.activo is true;
  if not found then raise exception 'Enlace inválido o desactivado'; end if;
  if v_vence <= clock_timestamp() then raise sqlstate 'PT410' using message='Este enlace venció. Pedile a la distribuidora un nuevo enlace para hacer tu pedido.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'codigo',codigo,'nombre',nombre,
    'descripcion',descripcion,'categoria',categoria,'precio',precio) order by nombre,id),'[]') into v_productos
  from public.catalogo_productos_internos(v_cliente)
  where precio>0 and precio::text not in ('NaN','Infinity','-Infinity');
  return jsonb_build_object('nombre_comercio',v_nombre,'productos',v_productos,'vence_at',v_vence);
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
  insert into public.pedidos(cliente_id,preventista_id,tipo_precio,estado,total,tipo_operacion,origen,observacion)
  values(v_cliente,v_config.responsable_id,v_config.base,'pendiente',v_total,'pedido','catalogo',
    '[Catálogo web] ' || trim(coalesce(p_observacion,''))) returning id into v_pedido;
  insert into public.pedido_detalles(pedido_id,producto_id,cantidad,precio_unitario,subtotal,tipo_precio,costo_unitario,porcentaje_comision,importe_comision)
  select v_pedido,(e->>'producto_id')::uuid,(e->>'cantidad')::numeric,(e->>'precio')::numeric,
    (e->>'cantidad')::numeric*(e->>'precio')::numeric,e->>'tipo',(e->>'costo')::numeric,0,0
  from jsonb_array_elements(v_detalles) e;
  insert into public.catalogo_solicitudes(cliente_id,solicitud_id,pedido_id) values(v_cliente,p_solicitud_id,v_pedido);
  return jsonb_build_object('pedido_id',v_pedido,'total',v_total);
end $$;

commit;
