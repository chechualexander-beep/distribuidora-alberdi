-- Etapa 2 de stock: auditoría a la vista (1.16.0).
-- Liquidación del viaje por producto (con motivo para cada diferencia), historial de un producto,
-- "Stock a revisar" y "Movimientos del día". Todo se arma con lo que ya guarda el libro de
-- movimientos; lo único nuevo que se guarda son los motivos de las diferencias.
begin;

create table public.stock_liquidacion_motivos (
 viaje_id uuid not null references public.viajes_vehiculo(id),
 producto_id uuid not null references public.productos(id),
 diferencia numeric not null,
 motivo text not null check (motivo in ('rotura', 'regalo_muestra', 'error_carga', 'vencido', 'faltante', 'otro')),
 nota text,
 guardado_por uuid not null references public.usuarios(id),
 guardado_at timestamptz not null default now(),
 primary key (viaje_id, producto_id)
);
alter table public.stock_liquidacion_motivos enable row level security;
revoke all on public.stock_liquidacion_motivos from public, anon, authenticated;

-- Liquidación de un viaje: por producto, lo que tenía al salir, lo que entró y salió durante el
-- viaje, lo que debería haber, lo contado al cerrar, la diferencia y su motivo. Más los cobros.
create function public.stock_liquidacion_viaje(p_viaje_id uuid) returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare v public.viajes_vehiculo; desde timestamptz; hasta timestamptz; cierre uuid; filas jsonb; cobros jsonb;
 ventas jsonb; quien text; cerro text;
begin
 perform public.stock_exigir_admin();
 select * into v from public.viajes_vehiculo where id = p_viaje_id;
 if not found then raise exception 'Viaje inexistente' using errcode = 'PT404'; end if;
 select min(o.created_at) into desde from public.stock_operaciones o
 where o.viaje_id = v.id and o.tipo = 'carga_vehiculo';
 desde := least(coalesce(desde, v.abierto_at), v.abierto_at);
 select o.id, o.created_at into cierre, hasta from public.stock_operaciones o
 where o.viaje_id = v.id and o.tipo = 'cierre_viaje' order by o.created_at limit 1;
 hasta := coalesce(hasta, 'infinity'::timestamptz);
 with mov as (
  select m.producto_id, m.tipo, m.cantidad_delta d, coalesce(m.motivo, '') motivo, o.tipo op_tipo,
   m.referencia_id = cierre en_cierre
  from public.stock_movimientos m
  left join public.stock_operaciones o on m.referencia_tipo = 'stock_operacion' and o.id = m.referencia_id
  where m.ubicacion_id = v.ubicacion_id and m.created_at >= desde and m.created_at <= hasta
 ), desde_inicio as (
  -- Todo lo que pasó en el vehículo desde que arrancó el viaje (para saber con qué salió).
  select m.producto_id, sum(m.cantidad_delta) d from public.stock_movimientos m
  where m.ubicacion_id = v.ubicacion_id and m.created_at >= desde group by m.producto_id
 ), flujo as (
  select producto_id,
   coalesce(sum(d) filter (where not coalesce(en_cierre, false) and op_tipo in ('carga_vehiculo', 'compra')), 0) cargo,
   coalesce(sum(d) filter (where not coalesce(en_cierre, false)
    and (motivo like 'Tomado del depósito%' or op_tipo = 'faltante_vehiculo')), 0) deposito,
   coalesce(-sum(d) filter (where not coalesce(en_cierre, false) and tipo in ('entrega', 'venta_directa')), 0) vendido,
   coalesce(sum(d) filter (where not coalesce(en_cierre, false) and tipo = 'devolucion_apta'), 0) devuelto,
   coalesce(-sum(d) filter (where not coalesce(en_cierre, false) and op_tipo = 'baja_vehiculo'), 0) bajado,
   coalesce(sum(d) filter (where not coalesce(en_cierre, false)), 0) neto,
   coalesce(sum(d) filter (where coalesce(en_cierre, false) and tipo like 'ajuste_%'), 0) diferencia,
   coalesce(-sum(d) filter (where coalesce(en_cierre, false) and tipo = 'transferencia_salida'), 0) bajado_al_cierre
  from mov group by producto_id
 ), contado as (
  select i.producto_id, i.cantidad from public.stock_operacion_items i where i.operacion_id = cierre
 ), base as (
  select p.id producto_id, p.nombre,
   coalesce(sa.cantidad, 0) - coalesce(di.d, 0) tenia,
   coalesce(f.cargo, 0) cargo, coalesce(f.deposito, 0) deposito, coalesce(f.vendido, 0) vendido,
   coalesce(f.devuelto, 0) devuelto, coalesce(f.bajado, 0) bajado, coalesce(f.neto, 0) neto,
   coalesce(f.diferencia, 0) diferencia, coalesce(f.bajado_al_cierre, 0) bajado_al_cierre, c.cantidad contado
  from public.productos p
  left join public.stock_actual sa on sa.ubicacion_id = v.ubicacion_id and sa.producto_id = p.id
  left join desde_inicio di on di.producto_id = p.id
  left join flujo f on f.producto_id = p.id
  left join contado c on c.producto_id = p.id
  where f.producto_id is not null or c.producto_id is not null
   or coalesce(sa.cantidad, 0) - coalesce(di.d, 0) <> 0
 )
 select coalesce(jsonb_agg(jsonb_build_object(
   'producto_id', b.producto_id, 'nombre', b.nombre, 'tenia', b.tenia, 'cargo', b.cargo,
   'deposito', b.deposito, 'vendido', b.vendido, 'devuelto', b.devuelto, 'bajado', b.bajado,
   'otros', b.neto - b.cargo - b.deposito + b.vendido - b.devuelto + b.bajado,
   'deberia', b.tenia + b.neto, 'contado', b.contado, 'diferencia', b.diferencia,
   'bajado_al_cierre', b.bajado_al_cierre,
   'motivo', lm.motivo, 'nota', lm.nota)
   order by (b.diferencia <> 0) desc, b.nombre), '[]')
 into filas
 from base b left join public.stock_liquidacion_motivos lm on lm.viaje_id = v.id and lm.producto_id = b.producto_id;

 -- Cobros: ventas del viaje y entregas de preventa hechas mientras el viaje estaba abierto.
 with ped as (
  select p.id, p.total from public.pedidos p
  where p.estado not in ('anulado', 'cancelado') and p.resultado_entrega in ('entregado', 'parcial')
   and (p.viaje_id = v.id or (p.tipo_operacion = 'pedido' and p.fecha_finalizacion >= v.abierto_at
    and p.fecha_finalizacion <= coalesce(v.cerrado_at, now())))
 )
 select coalesce(jsonb_agg(jsonb_build_object('medio', x.medio, 'importe', x.importe) order by x.importe desc), '[]')
 into cobros
 from (select coalesce(nullif(btrim(pp.medio_pago), ''), 'Otro') medio, sum(pp.importe) importe
  from public.pedido_pagos pp join ped on ped.id = pp.pedido_id group by 1) x;
 select jsonb_build_object('cantidad', count(*), 'total', coalesce(sum(p.total), 0)) into ventas
 from public.pedidos p
 where p.estado not in ('anulado', 'cancelado') and p.resultado_entrega in ('entregado', 'parcial')
  and (p.viaje_id = v.id or (p.tipo_operacion = 'pedido' and p.fecha_finalizacion >= v.abierto_at
   and p.fecha_finalizacion <= coalesce(v.cerrado_at, now())));
 select btrim(coalesce(u.nombre, '') || ' ' || coalesce(u.apellido, '')) into quien from public.usuarios u where u.id = v.preventista_id;
 select u.nombre into cerro from public.usuarios u where u.id = v.cerrado_por;
 return jsonb_build_object(
  'viaje', jsonb_build_object('id', v.id, 'estado', v.estado, 'abierto_at', v.abierto_at, 'cerrado_at', v.cerrado_at,
   'preventista', quien, 'cerrado_por', cerro, 'contado', coalesce((v.resumen->>'contado')::boolean, false)),
  'filas', filas, 'cobros', cobros, 'ventas', ventas);
end $$;
revoke all on function public.stock_liquidacion_viaje(uuid) from public, anon;
grant execute on function public.stock_liquidacion_viaje(uuid) to authenticated;

-- Guarda (o borra, con motivo null) el motivo de las diferencias de un viaje cerrado.
create function public.stock_liquidacion_motivos_guardar(p_viaje_id uuid, p_items jsonb) returns integer
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare v public.viajes_vehiculo; it jsonb; prod uuid; mot text; nota_ text; dif numeric; n integer := 0;
begin
 perform public.stock_exigir_admin();
 select * into v from public.viajes_vehiculo where id = p_viaje_id;
 if not found then raise exception 'Viaje inexistente' using errcode = 'PT404'; end if;
 if v.estado <> 'cerrado' then raise exception 'El viaje todavía está abierto' using errcode = 'PT409'; end if;
 if jsonb_typeof(p_items) is distinct from 'array' then raise exception 'Lista inválida' using errcode = 'PT422'; end if;
 for it in select * from jsonb_array_elements(p_items) loop
  prod := (it->>'producto_id')::uuid;
  mot := nullif(btrim(it->>'motivo'), '');
  nota_ := nullif(btrim(it->>'nota'), '');
  select (d->>'diferencia')::numeric into dif from jsonb_array_elements(coalesce(v.resumen->'diferencias', '[]')) d
  where (d->>'producto_id')::uuid = prod limit 1;
  if dif is null or dif = 0 then raise exception 'Ese producto no tiene diferencia en este viaje' using errcode = 'PT422'; end if;
  if mot = 'otro' and nota_ is null then raise exception 'Con "Otro", escribí qué pasó' using errcode = 'PT422'; end if;
  if mot is null then
   delete from public.stock_liquidacion_motivos m where m.viaje_id = v.id and m.producto_id = prod;
  else
   insert into public.stock_liquidacion_motivos(viaje_id, producto_id, diferencia, motivo, nota, guardado_por)
   values (v.id, prod, dif, mot, nota_, auth.uid())
   on conflict (viaje_id, producto_id) do update set diferencia = excluded.diferencia, motivo = excluded.motivo,
    nota = excluded.nota, guardado_por = excluded.guardado_por, guardado_at = now();
  end if;
  n := n + 1;
 end loop;
 return n;
end $$;
revoke all on function public.stock_liquidacion_motivos_guardar(uuid, jsonb) from public, anon;
grant execute on function public.stock_liquidacion_motivos_guardar(uuid, jsonb) to authenticated;

-- Viajes recientes, con cuántas diferencias tienen y cuántas siguen sin motivo.
create function public.stock_viajes_recientes(p_limite integer default 30) returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare r jsonb;
begin
 perform public.stock_exigir_admin();
 select coalesce(jsonb_agg(x order by x.abierto_at desc), '[]') into r from (
  select v.id, v.estado, v.abierto_at, v.cerrado_at,
   btrim(coalesce(u.nombre, '') || ' ' || coalesce(u.apellido, '')) preventista,
   jsonb_array_length(coalesce(v.resumen->'diferencias', '[]')) diferencias,
   (select count(*) from jsonb_array_elements(coalesce(v.resumen->'diferencias', '[]')) d
    where not exists (select 1 from public.stock_liquidacion_motivos m
     where m.viaje_id = v.id and m.producto_id = (d->>'producto_id')::uuid)) sin_motivo
  from public.viajes_vehiculo v left join public.usuarios u on u.id = v.preventista_id
  order by v.abierto_at desc limit greatest(1, least(coalesce(p_limite, 30), 200))
 ) x;
 return r;
end $$;
revoke all on function public.stock_viajes_recientes(integer) from public, anon;
grant execute on function public.stock_viajes_recientes(integer) to authenticated;

-- Historial de un producto: cada movimiento con lugar, quién, contra quién y cómo quedó.
create function public.stock_historial_producto(p_producto_id uuid, p_dias integer default 90) returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare r jsonb;
begin
 perform public.stock_exigir_deposito();
 select coalesce(jsonb_agg(x order by x.fecha desc, x.orden desc), '[]') into r from (
  select m.id, m.created_at fecha, u.codigo ubicacion, m.tipo, m.cantidad_delta delta, m.cantidad_anterior anterior,
   m.cantidad_nueva nueva, m.motivo, us.nombre usuario, o.tipo operacion,
   coalesce(c.nombre_comercio, o.proveedor) contraparte,
   case when m.cantidad_delta > 0 then 1 else 0 end orden
  from public.stock_movimientos m
  join public.ubicaciones_stock u on u.id = m.ubicacion_id
  left join public.usuarios us on us.id = m.usuario_id
  left join public.stock_operaciones o on m.referencia_tipo = 'stock_operacion' and o.id = m.referencia_id
  left join public.stock_eventos e on m.referencia_tipo = 'stock_evento' and e.id = m.referencia_id
  left join public.pedidos pe on pe.id = e.pedido_id
  left join public.clientes c on c.id = pe.cliente_id
  where m.producto_id = p_producto_id
   and m.created_at >= now() - make_interval(days => greatest(1, least(coalesce(p_dias, 90), 3650)))
  order by m.created_at desc limit 400
 ) x;
 return r;
end $$;
revoke all on function public.stock_historial_producto(uuid, integer) from public, anon;
grant execute on function public.stock_historial_producto(uuid, integer) to authenticated;

-- "Stock a revisar": negativos (dónde y desde cuándo), diferencias de liquidación sin motivo
-- (solo administración) y lo que no se cuenta hace más de 30 días (con stock).
create function public.stock_a_revisar() returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare negativos jsonb; sin_motivo jsonb := '[]'; sin_contar jsonb; total_sin_contar integer;
begin
 perform public.stock_exigir_deposito();
 select coalesce(jsonb_agg(jsonb_build_object('producto_id', p.id, 'nombre', p.nombre, 'ubicacion', u.codigo,
   'cantidad', sa.cantidad,
   'desde', (select max(m.created_at) from public.stock_movimientos m where m.ubicacion_id = sa.ubicacion_id
     and m.producto_id = sa.producto_id and m.cantidad_anterior >= 0 and m.cantidad_nueva < 0))
   order by p.nombre), '[]')
 into negativos
 from public.stock_actual sa join public.productos p on p.id = sa.producto_id
 join public.ubicaciones_stock u on u.id = sa.ubicacion_id
 where sa.cantidad < 0 and p.control_stock and p.activo;
 if public.es_administrador() then
  select coalesce(jsonb_agg(jsonb_build_object('viaje_id', v.id, 'cerrado_at', v.cerrado_at,
    'producto_id', (d->>'producto_id')::uuid, 'nombre', d->>'nombre', 'diferencia', (d->>'diferencia')::numeric)
    order by v.cerrado_at desc), '[]')
  into sin_motivo
  from public.viajes_vehiculo v cross join lateral jsonb_array_elements(coalesce(v.resumen->'diferencias', '[]')) d
  where v.estado = 'cerrado' and not exists (select 1 from public.stock_liquidacion_motivos m
   where m.viaje_id = v.id and m.producto_id = (d->>'producto_id')::uuid);
 end if;
 with cont as (
  select p.id, p.nombre, max(sa.contado_at) contado_at, sum(sa.cantidad) cantidad
  from public.productos p join public.stock_actual sa on sa.producto_id = p.id
  where p.activo and p.control_stock group by p.id, p.nombre
 ), viejos as (
  select * from cont where cantidad > 0 and (contado_at is null or contado_at < now() - interval '30 days')
 )
 select (select count(*) from viejos),
  coalesce((select jsonb_agg(jsonb_build_object('producto_id', id, 'nombre', nombre, 'contado_at', contado_at)
   order by contado_at nulls first, nombre) from (select * from viejos order by contado_at nulls first, nombre limit 15) y), '[]')
 into total_sin_contar, sin_contar;
 return jsonb_build_object('negativos', negativos, 'sin_motivo', sin_motivo,
  'sin_contar', jsonb_build_object('total', total_sin_contar, 'productos', sin_contar));
end $$;
revoke all on function public.stock_a_revisar() from public, anon;
grant execute on function public.stock_a_revisar() to authenticated;

-- Movimientos de un día (hora de Argentina), agrupados por lo que los generó: carga, compra,
-- conteo, entrega, venta, bajada, cierre... con sus productos.
create function public.stock_movimientos_dia(p_fecha date) returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare desde timestamptz; r jsonb;
begin
 perform public.stock_exigir_deposito();
 desde := (coalesce(p_fecha, (now() at time zone 'America/Argentina/Buenos_Aires')::date)::timestamp)
  at time zone 'America/Argentina/Buenos_Aires';
 with mov as (
  select m.*, p.nombre producto, u.codigo ubicacion
  from public.stock_movimientos m join public.productos p on p.id = m.producto_id
  join public.ubicaciones_stock u on u.id = m.ubicacion_id
  where m.created_at >= desde and m.created_at < desde + interval '1 day'
 ), grupos as (
  select coalesce(mv.referencia_tipo, 'suelto') ref_tipo, coalesce(mv.referencia_id::text, mv.id::text) ref_id,
   min(mv.created_at) hora, min(mv.usuario_id::text)::uuid usuario_id,
   (array_agg(mv.tipo order by mv.created_at))[1] primer_tipo, (array_agg(mv.motivo order by mv.created_at))[1] motivo,
   jsonb_agg(jsonb_build_object('producto', mv.producto, 'ubicacion', mv.ubicacion, 'delta', mv.cantidad_delta,
    'nueva', mv.cantidad_nueva) order by mv.producto, mv.ubicacion) lineas,
   count(distinct mv.producto_id) productos
  from mov mv group by 1, 2
 )
 select coalesce(jsonb_agg(jsonb_build_object(
   'hora', g.hora, 'tipo', coalesce(o.tipo, e.tipo_evento, g.primer_tipo), 'detalle', g.primer_tipo,
   'motivo', g.motivo, 'usuario', us.nombre, 'contraparte', coalesce(c.nombre_comercio, o.proveedor),
   'productos', g.productos, 'lineas', g.lineas) order by g.hora desc), '[]')
 into r
 from grupos g
 left join public.stock_operaciones o on g.ref_tipo = 'stock_operacion' and o.id::text = g.ref_id
 left join public.stock_eventos e on g.ref_tipo = 'stock_evento' and e.id::text = g.ref_id
 left join public.pedidos pe on pe.id = e.pedido_id
 left join public.clientes c on c.id = pe.cliente_id
 left join public.usuarios us on us.id = g.usuario_id;
 return r;
end $$;
revoke all on function public.stock_movimientos_dia(date) from public, anon;
grant execute on function public.stock_movimientos_dia(date) to authenticated;

notify pgrst, 'reload schema';
commit;
