-- Sueltos automáticos (19/11/2026): un producto que sale de otro (fraccionado / suelto) lleva
-- stock siempre que su cerrado lo lleve. Arranca en 0. Así una entrega nunca deja de descontarlo
-- (por ejemplo, un reparto sin carga registrada) ni se puede dejar "a pedido" por error.

-- Pasa un producto a "con stock" en 0 (lo que hubiera de antes no vale: se pone en 0).
create function public.stock_activar_suelto(p_producto uuid) returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare fila record; actor uuid;
begin
 update public.productos set control_stock = true where id = p_producto and not control_stock;
 if not found then return; end if;
 actor := coalesce(auth.uid(), (select u.id from public.usuarios u where u.rol = 'administrador' and u.activo
  order by u.id limit 1));
 for fila in select * from public.stock_actual where producto_id = p_producto and cantidad <> 0 for update loop
  if actor is not null then
   insert into public.stock_movimientos(ubicacion_id, producto_id, tipo, cantidad_anterior, cantidad_delta,
    cantidad_nueva, motivo, usuario_id)
   values (fila.ubicacion_id, p_producto, case when fila.cantidad < 0 then 'ajuste_entrada' else 'ajuste_salida' end,
    fila.cantidad, -fila.cantidad, 0, 'Pasa a llevar stock (sale de un producto con stock)', actor);
  end if;
  update public.stock_actual set cantidad = 0, contado_at = clock_timestamp(), updated_at = clock_timestamp()
  where ubicacion_id = fila.ubicacion_id and producto_id = p_producto;
 end loop;
end $$;
revoke all on function public.stock_activar_suelto(uuid) from public, anon, authenticated;

-- Cuando un cerrado pasa a llevar stock, o un producto se vincula a un cerrado con stock,
-- los sueltos pasan a llevar stock solos.
create function public.stock_sueltos_con_cerrado() returns trigger
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare hijo uuid;
begin
 if new.control_stock and not old.control_stock then
  for hijo in select id from public.productos where fracciona_de = new.id and not control_stock loop
   perform public.stock_activar_suelto(hijo);
  end loop;
 end if;
 if new.fracciona_de is not null and new.fracciona_de is distinct from old.fracciona_de and not new.control_stock
  and exists (select 1 from public.productos where id = new.fracciona_de and control_stock) then
  perform public.stock_activar_suelto(new.id);
 end if;
 return null;
end $$;
revoke all on function public.stock_sueltos_con_cerrado() from public, anon, authenticated;
create trigger zz_stock_sueltos_con_cerrado after update of control_stock, fracciona_de on public.productos
 for each row execute function public.stock_sueltos_con_cerrado();

CREATE OR REPLACE FUNCTION public.stock_fraccionar(p_id uuid, p_producto_id uuid, p_origenes numeric, p_ubicacion text, p_fecha timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare huella text; previo jsonb; loc uuid; fecha timestamptz; prod public.productos; res jsonb;
begin
 perform public.stock_exigir_admin(); perform public.stock_exigir_operativo();
 huella := public.stock_huella(jsonb_build_object('p', p_producto_id, 'n', p_origenes, 'u', p_ubicacion, 'f', p_fecha));
 previo := public.stock_operacion_previa(p_id, 'fraccion', huella);
 if previo is not null then return previo; end if;
 loc := public.stock_ubicacion(p_ubicacion);
 if loc is null then raise exception 'Ubicación inválida' using errcode = 'PT422'; end if;
 fecha := public.stock_validar_fecha(p_fecha);
 select * into prod from public.productos where id = p_producto_id for update;
 if not found or prod.fracciona_de is null then
  raise exception 'El producto no es fraccionado: configurá de qué producto sale' using errcode = 'PT422'; end if;
 -- Un suelto "a pedido" pasa a llevar stock desde 0 y suma lo que se abre.
 if not prod.control_stock then perform public.stock_activar_suelto(p_producto_id); end if;
 if p_origenes is null or p_origenes <= 0 or p_origenes > 10000 or p_origenes <> round(p_origenes, 3) then
  raise exception 'Cantidad inválida' using errcode = 'PT422'; end if;
 insert into public.stock_operaciones(id, tipo, ubicacion_id, fecha_fisica, actor_id, request_hash, resultado)
 values (p_id, 'fraccion', loc, fecha, auth.uid(), huella, '{}');
 perform public.stock_abrir_origen(loc, p_producto_id, p_origenes, 'Fraccionado', 'stock_operacion', p_id);
 insert into public.stock_operacion_items(operacion_id, producto_id, cantidad, controlado)
 values (p_id, p_producto_id, p_origenes * prod.unidades_por_origen, true);
 res := jsonb_build_object('operacion_id', p_id, 'origenes', p_origenes,
  'unidades', p_origenes * prod.unidades_por_origen);
 update public.stock_operaciones set resultado = res where id = p_id;
 return res;
end $function$;

CREATE OR REPLACE FUNCTION public.stock_marcar_a_pedido(p_producto_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
begin
 perform public.stock_exigir_admin(); perform public.stock_exigir_operativo();
 if exists (select 1 from public.productos p join public.productos o on o.id = p.fracciona_de
   where p.id = p_producto_id and o.control_stock) then
  raise exception 'Este producto sale de otro que lleva stock: tiene que llevar stock también' using errcode = 'PT422';
 end if;
 update public.productos set control_stock = false where id = p_producto_id and control_stock;
end $function$;

-- Los que ya están vinculados a un cerrado con stock.
do $$ declare hijo uuid; begin
 for hijo in select p.id from public.productos p join public.productos o on o.id = p.fracciona_de
  where o.control_stock and not p.control_stock loop
  perform public.stock_activar_suelto(hijo);
 end loop;
end $$;
