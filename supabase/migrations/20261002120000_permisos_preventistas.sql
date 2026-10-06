-- ACTIVAR junto con la app compatible; las versiones anteriores consultan costos.
begin;

-- Conserva lectura de la ficha necesaria para identificar pedidos históricos.
-- No concede edición ni acceso a los pedidos del nuevo vendedor.
create function public.puede_leer_cliente(p_cliente uuid) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
 select public.es_personal_activo() and (public.es_administrador() or exists(
   select 1 from clientes c where c.id=p_cliente and c.preventista_id=auth.uid()
 ) or exists(select 1 from pedidos p where p.cliente_id=p_cliente and p.preventista_id=auth.uid()))
$$;
revoke all on function public.puede_leer_cliente(uuid) from public,anon;
grant execute on function public.puede_leer_cliente(uuid) to authenticated;

create policy alcance_clientes_lectura on public.clientes as restrictive for select to authenticated
 using(public.puede_leer_cliente(id));
create policy alcance_clientes_edicion on public.clientes as restrictive for update to authenticated
 using(public.es_administrador() or preventista_id=auth.uid())
 with check(public.es_administrador() or preventista_id=auth.uid());
create function public.proteger_campos_cliente() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not public.es_personal_activo() then raise exception 'Personal inactivo o sin autorización'; end if;
 if not public.es_administrador() and
   (to_jsonb(new)-array['nombre_comercio','direccion','propietario','telefono','localidad','zona','dia_visita','observaciones','latitud','longitud','ubicacion_actualizada_at'])
   is distinct from
   (to_jsonb(old)-array['nombre_comercio','direccion','propietario','telefono','localidad','zona','dia_visita','observaciones','latitud','longitud','ubicacion_actualizada_at'])
 then raise exception 'Solo administración puede cambiar la asignación o los datos internos del cliente'; end if;
 return new;
end $$;
create trigger proteger_campos_cliente before update on public.clientes
 for each row execute function public.proteger_campos_cliente();
revoke all on function public.proteger_campos_cliente() from public,anon,authenticated;

create table public.historial_cambios_clientes (
 id bigint generated always as identity primary key,
 cliente_id uuid not null references public.clientes(id),
 usuario_id uuid not null,
 fecha timestamptz not null default now(),
 antes jsonb not null, despues jsonb not null
);
alter table public.historial_cambios_clientes enable row level security;
revoke all on public.historial_cambios_clientes from public,anon,authenticated;
grant select on public.historial_cambios_clientes to authenticated;
create policy historial_clientes_admin on public.historial_cambios_clientes for select to authenticated using(public.es_administrador());
create function public.auditar_cambio_cliente() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new is distinct from old then
 insert into historial_cambios_clientes(cliente_id,usuario_id,antes,despues)
 values(new.id,auth.uid(),to_jsonb(old),to_jsonb(new));
 end if;
 return new;
end $$;
revoke all on function public.auditar_cambio_cliente() from public,anon,authenticated;
create trigger auditar_cambio_cliente after update on public.clientes for each row execute function public.auditar_cambio_cliente();

create policy alcance_pedidos on public.pedidos as restrictive for select to authenticated
 using(public.es_administrador() or preventista_id=auth.uid());
create policy alcance_detalles on public.pedido_detalles as restrictive for select to authenticated
 using(exists(select 1 from public.pedidos p where p.id=pedido_id));
create policy alcance_pagos on public.pedido_pagos as restrictive for select to authenticated
 using(exists(select 1 from public.pedidos p where p.id=pedido_id));

-- No se aceptan inserciones directas desde el teléfono. El RPC escribe todo
-- en una transacción y determina vendedor, importes y costos en el servidor.
drop policy "usuarios autenticados pueden crear pedidos" on public.pedidos;
drop policy "usuarios autenticados pueden crear detalles de pedidos" on public.pedido_detalles;
create policy detalles_insert_admin on public.pedido_detalles for insert to authenticated
 with check(public.es_administrador());

do $$ declare t text; begin
 foreach t in array array['notas_credito','nota_credito_detalles','recepciones_nota_credito','movimientos_credito_cliente','ajustes_comision_aplicados'] loop
 execute format('create policy personal_activo on public.%I as restrictive for all to authenticated using (public.es_personal_activo()) with check (public.es_personal_activo())',t);
 end loop;
end $$;

-- authenticated incluye administradores: el acceso a costos de estos últimos
-- se realiza por vistas filtradas por es_administrador(), nunca por la tabla.
create view public.productos_administracion with (security_barrier=true) as
 select * from public.productos where public.es_administrador();
create view public.detalles_administracion with (security_barrier=true) as
 select * from public.pedido_detalles where public.es_administrador();
revoke all on public.productos_administracion,public.detalles_administracion from public,anon,authenticated;
grant select on public.productos_administracion,public.detalles_administracion to authenticated;
do $$ declare t text; campo text; columnas text; begin
 foreach t in array array['productos','pedido_detalles','nota_credito_detalles'] loop
 campo := case when t='pedido_detalles' then 'costo_unitario' else 'costo' end;
 execute format('revoke select on public.%I from public,anon,authenticated',t);
 select string_agg(quote_ident(attname),',') into columnas from pg_attribute
 where attrelid=format('public.%I',t)::regclass and attnum>0 and not attisdropped and attname<>campo;
 execute format('grant select (%s) on public.%I to authenticated',columnas,t);
 end loop;
 -- Privilegios innecesarios que RLS no protege, como TRUNCATE.
 for t in select tablename from pg_tables where schemaname='public' loop
 execute format('revoke truncate,references,trigger on public.%I from public,anon,authenticated',t);
 end loop;
end $$;

create function public.validar_detalles_venta(p_detalles jsonb,p_pedido uuid default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare e jsonb; p public.productos; anterior public.pedido_detalles; cantidad numeric; precio numeric; tipo text; costo numeric; resultado jsonb:='[]';
begin
 if jsonb_typeof(p_detalles) is distinct from 'array' then raise exception 'Detalle inválido'; end if;
 if jsonb_array_length(p_detalles) not between 1 and 300 then raise exception 'Cantidad de productos inválida'; end if;
 if exists(select 1 from jsonb_array_elements(p_detalles) x group by x->>'producto_id' having count(*)>1) then raise exception 'Producto duplicado'; end if;
 for e in select * from jsonb_array_elements(p_detalles) loop
  select * into p from productos where id=(e->>'producto_id')::uuid;
  if not found then raise exception 'Producto inexistente'; end if;
  anterior:=null;
  if p_pedido is not null then select * into anterior from pedido_detalles where pedido_id=p_pedido and producto_id=p.id; end if;
  if anterior.id is null and (p.activo is not true or (not public.es_administrador() and not p.visible_preventistas)) then raise exception 'Producto no disponible'; end if;
  cantidad:=(e->>'cantidad')::numeric; tipo:=e->>'tipo_precio';
  if cantidad is null or cantidad::text in ('NaN','Infinity','-Infinity') or cantidad<>trunc(cantidad) or cantidad not between 1 and 9999 then raise exception 'Cantidad inválida'; end if;
  if tipo is null or tipo not in ('normal','promo','interior') then raise exception 'Lista inválida'; end if;
  precio:=case tipo when 'promo' then p.precio_promo when 'interior' then p.precio_interior else p.precio_normal end;
  -- Al editar, conservar el precio original si la lista no cambió.
  if anterior.id is not null and anterior.tipo_precio=tipo then precio:=anterior.precio_unitario; end if;
  if precio is null or precio<=0 or precio::text in ('NaN','Infinity','-Infinity') then raise exception 'Precio inválido'; end if;
  if (e->>'precio_unitario')::numeric is distinct from precio then raise exception 'Los precios cambiaron. Actualizá los productos'; end if;
  costo:=case when anterior.id is not null then anterior.costo_unitario else p.costo end;
  resultado:=resultado||jsonb_build_array(jsonb_build_object('producto_id',p.id,'cantidad',cantidad,'precio_unitario',precio,'subtotal',precio*cantidad,'tipo_precio',tipo,'costo_unitario',costo));
 end loop;
 return resultado;
end $$;
revoke all on function public.validar_detalles_venta(jsonb,uuid) from public,anon,authenticated;

create table public.solicitudes_pedido_interno (
 id uuid primary key, usuario_id uuid not null, huella text not null,
 pedido_id uuid references public.pedidos(id) on delete set null
);
alter table public.solicitudes_pedido_interno enable row level security;
revoke all on public.solicitudes_pedido_interno from public,anon,authenticated;

create function public.crear_pedido_interno(p_id uuid,p_cliente_id uuid,p_tipo_precio text,p_tipo_operacion text,p_observacion text,p_fecha_entrega date,p_detalles jsonb)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare detalles jsonb; solicitud public.solicitudes_pedido_interno; c public.clientes; huella text;
begin
 if not public.es_personal_activo() then raise exception 'Personal inactivo o sin autorización'; end if;
 if p_id is null then raise exception 'Solicitud inválida'; end if;
 select * into c from clientes where id=p_cliente_id for update;
 if not found then raise exception 'Cliente inexistente'; end if;
 huella:=encode(sha256(convert_to(jsonb_build_object('cliente',p_cliente_id,'lista',p_tipo_precio,'operacion',p_tipo_operacion,'observacion',p_observacion,'fecha',p_fecha_entrega,'detalles',p_detalles)::text,'UTF8')),'hex');
 select * into solicitud from solicitudes_pedido_interno where id=p_id;
 if found then
  if solicitud.usuario_id is distinct from auth.uid() or solicitud.huella<>huella then raise exception 'La solicitud ya fue utilizada. Revisá tus pedidos'; end if;
  if solicitud.pedido_id is null then raise exception 'Este pedido fue eliminado'; end if;
  return solicitud.pedido_id;
 end if;
 if c.activo is not true or (not public.es_administrador() and c.preventista_id is distinct from auth.uid()) then raise exception 'Cliente no asignado o inactivo'; end if;
 if p_tipo_precio is null or p_tipo_precio not in ('normal','promo','interior') or p_tipo_operacion is null or p_tipo_operacion not in ('pedido','venta_directa') or p_fecha_entrega is null or length(coalesce(p_observacion,''))>1000 then raise exception 'Datos del pedido inválidos'; end if;
 detalles:=public.validar_detalles_venta(p_detalles);
 insert into pedidos(id,cliente_id,preventista_id,tipo_precio,tipo_operacion,total,observacion,fecha_entrega)
 values(p_id,p_cliente_id,auth.uid(),p_tipo_precio,p_tipo_operacion,(select sum((x->>'subtotal')::numeric) from jsonb_array_elements(detalles) x),nullif(trim(p_observacion),''),p_fecha_entrega);
 insert into pedido_detalles(pedido_id,producto_id,cantidad,precio_unitario,subtotal,tipo_precio,costo_unitario)
 select p_id,(x->>'producto_id')::uuid,(x->>'cantidad')::numeric,(x->>'precio_unitario')::numeric,(x->>'subtotal')::numeric,x->>'tipo_precio',(x->>'costo_unitario')::numeric from jsonb_array_elements(detalles) x;
 insert into solicitudes_pedido_interno(id,usuario_id,huella,pedido_id) values(p_id,auth.uid(),huella,p_id);
 return p_id;
end $$;
revoke all on function public.crear_pedido_interno(uuid,uuid,text,text,text,date,jsonb) from public,anon;
grant execute on function public.crear_pedido_interno(uuid,uuid,text,text,text,date,jsonb) to authenticated;

alter function public.actualizar_pedido_activo(uuid,numeric,text,text,text,date,jsonb) rename to actualizar_pedido_activo_interno;
revoke all on function public.actualizar_pedido_activo_interno(uuid,numeric,text,text,text,date,jsonb) from public,anon,authenticated;
create function public.actualizar_pedido_activo(p_pedido_id uuid,p_total numeric,p_tipo_precio text,p_tipo_operacion text,p_observacion text,p_fecha_entrega date,p_detalles jsonb)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare p public.pedidos; detalles jsonb;
begin
 if not public.es_personal_activo() then raise exception 'Personal inactivo o sin autorización'; end if;
 select * into p from pedidos where id=p_pedido_id for update;
 if not found or (not public.es_administrador() and p.preventista_id is distinct from auth.uid()) then raise exception 'Pedido no autorizado'; end if;
 if p.facturado or p.resultado_entrega is distinct from 'pendiente' or p.estado='cancelado' then raise exception 'El pedido ya no se puede editar'; end if;
 if p_tipo_precio is null or p_tipo_precio not in ('normal','promo','interior') or p_tipo_operacion is null or p_tipo_operacion not in ('pedido','venta_directa') or p_fecha_entrega is null or length(coalesce(p_observacion,''))>1000 then raise exception 'Datos del pedido inválidos'; end if;
 detalles:=public.validar_detalles_venta(p_detalles,p.id);
 perform public.actualizar_pedido_activo_interno(p.id,(select sum((x->>'subtotal')::numeric) from jsonb_array_elements(detalles) x),p_tipo_precio,p_tipo_operacion,p_observacion,p_fecha_entrega,detalles);
end $$;
revoke all on function public.actualizar_pedido_activo(uuid,numeric,text,text,text,date,jsonb) from public,anon;
grant execute on function public.actualizar_pedido_activo(uuid,numeric,text,text,text,date,jsonb) to authenticated;
alter function public.eliminar_pedido_pendiente(uuid) rename to eliminar_pedido_pendiente_interno;
revoke all on function public.eliminar_pedido_pendiente_interno(uuid) from public,anon,authenticated;
create function public.eliminar_pedido_pendiente(p_pedido_id uuid) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not public.es_personal_activo() then raise exception 'Personal inactivo o sin autorización'; end if;
 perform 1 from pedidos where id=p_pedido_id for update;
 perform public.eliminar_pedido_pendiente_interno(p_pedido_id);
end $$;
revoke all on function public.eliminar_pedido_pendiente(uuid) from public,anon;
grant execute on function public.eliminar_pedido_pendiente(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
