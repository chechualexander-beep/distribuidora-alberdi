-- Venta especial (etapa A del mostrador): el administrador vende a precio libre, con o sin cliente
-- ("Consumidor final"), desde el depósito o el vehículo. Queda entregada en el momento, con su costo
-- y sin comisión; el stock se descuenta del lugar elegido (abre cajas si hace falta) y el pago va con
-- la misma función de cobro de la entrega. Además: las ventas del administrador ya no calculan
-- comisión (no se pagan; quedan en caja).

-- 1) Origen "especial" para estas ventas (no van al viaje del vehículo).
alter table public.pedidos drop constraint if exists pedidos_origen_check;
alter table public.pedidos add constraint pedidos_origen_check check (origen = any (array['interno', 'catalogo', 'especial']));

create or replace function public.asignar_viaje_venta_directa() returns trigger
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
 if new.tipo_operacion = 'venta_directa' and new.viaje_id is null and new.origen is distinct from 'especial' then
  select v.id into new.viaje_id from public.viajes_vehiculo v where v.estado = 'abierto'
  order by v.abierto_at desc limit 1;
 end if;
 return new;
end $$;

-- 2) Ventas del administrador: comisión 0 (pedidos, venta directa y venta especial).
create function public.comision_cero_administrador() returns trigger
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
 if exists (select 1 from public.pedidos p join public.usuarios u on u.id = p.preventista_id
   where p.id = new.pedido_id and u.rol = 'administrador') then
  new.porcentaje_comision := 0;
  new.importe_comision := 0;
 end if;
 return new;
end $$;
revoke all on function public.comision_cero_administrador() from public, anon, authenticated;
create trigger zz_comision_cero_administrador before insert or update on public.pedido_detalles
 for each row execute function public.comision_cero_administrador();

-- 3) Cliente fijo "Consumidor final" (ventas a quien no está cargado: siempre se cobran en el momento).
create function public.consumidor_final_id() returns uuid
language sql immutable set search_path = pg_catalog, public, pg_temp as $$
 select 'c0f1a1a1-0000-4000-8000-000000000001'::uuid
$$;
insert into public.clientes(id, nombre_comercio, direccion, observaciones, activo)
values (public.consumidor_final_id(), 'Consumidor final', '—', 'Ventas especiales a quien no es cliente.', true)
on conflict (id) do nothing;

-- 4) Venta especial.
create table public.ventas_especiales (
 id uuid primary key,
 request_hash text not null,
 resultado jsonb not null,
 actor_id uuid not null references public.usuarios(id),
 created_at timestamptz not null default now()
);
alter table public.ventas_especiales enable row level security;
revoke all on public.ventas_especiales from anon, authenticated;

-- p_items: [{producto_id, cantidad, precio_unitario}]; p_pagos: [{medio: Efectivo|Transferencia, importe}].
-- Lo que no se paga queda en la cuenta del cliente (no para "Consumidor final").
create function public.venta_especial(p_id uuid, p_fecha timestamptz, p_cliente_id uuid, p_ubicacion text,
 p_items jsonb, p_pagos jsonb default '[]', p_observacion text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare huella text; previo public.ventas_especiales; f timestamptz; cliente uuid; ubic uuid; x jsonb;
 prod public.productos; q numeric; precio numeric; v_total numeric := 0; v_costo numeric := 0; pagado numeric := 0;
 deltas jsonb; evento uuid; movimientos integer; medio text; importe numeric; cobro uuid; saldo numeric; res jsonb;
begin
 if public.es_administrador() is not true then
  raise exception 'Solo administración' using errcode = 'PT403'; end if;
 huella := md5(jsonb_build_object('f', p_fecha, 'c', p_cliente_id, 'u', p_ubicacion, 'i', p_items, 'p', p_pagos,
  'o', p_observacion)::text);
 perform pg_advisory_xact_lock(829001);
 select * into previo from public.ventas_especiales where id = p_id;
 if found then
  if previo.request_hash <> huella then
   raise exception 'Esta venta ya se registró con otros datos.' using errcode = 'PT409'; end if;
  return previo.resultado || jsonb_build_object('repetida', true);
 end if;
 f := public.stock_validar_fecha(p_fecha);
 cliente := coalesce(p_cliente_id, public.consumidor_final_id());
 if not exists (select 1 from public.clientes c where c.id = cliente and c.activo is not false) then
  raise exception 'Cliente inexistente o inactivo.' using errcode = 'PT404'; end if;
 if p_ubicacion not in ('deposito_alberdi', 'vehiculo') then
  raise exception 'Elegí depósito o vehículo.' using errcode = 'PT422'; end if;
 ubic := public.stock_ubicacion(p_ubicacion);
 if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
  raise exception 'Agregá al menos un producto.' using errcode = 'PT422'; end if;

 insert into public.pedidos(id, cliente_id, preventista_id, tipo_precio, estado, total, resultado_entrega,
  fecha_entrega, facturado, tipo_operacion, observacion, origen)
 values (p_id, cliente, auth.uid(), 'normal', 'pendiente', 0, 'pendiente',
  (f at time zone 'America/Argentina/Buenos_Aires')::date, false, 'venta_directa',
  nullif(btrim(coalesce(p_observacion, '')), ''), 'especial');

 for x in select value from jsonb_array_elements(p_items) loop
  select * into prod from public.productos where id = (x->>'producto_id')::uuid for share;
  if not found or prod.activo is not true then
   raise exception 'Producto no disponible.' using errcode = 'PT422'; end if;
  q := (x->>'cantidad')::numeric; precio := round((x->>'precio_unitario')::numeric, 2);
  if q is null or q <= 0 or precio is null or precio < 0 then
   raise exception 'Revisá cantidad y precio de %.', prod.nombre using errcode = 'PT422'; end if;
  insert into public.pedido_detalles(pedido_id, producto_id, cantidad, precio_unitario, subtotal, tipo_precio,
   cantidad_entregada, cantidad_no_entregada, costo_unitario, porcentaje_comision, importe_comision)
  values (p_id, prod.id, q, precio, round(q * precio, 2), 'normal', q, 0, prod.costo, 0, 0);
  v_total := v_total + round(q * precio, 2);
  v_costo := v_costo + q * coalesce(prod.costo, 0);
 end loop;

 -- Pagos: efectivo o transferencia, sin pasarse del total; "Consumidor final" paga todo.
 for x in select value from jsonb_array_elements(coalesce(p_pagos, '[]')) loop
  medio := btrim(x->>'medio'); importe := round((x->>'importe')::numeric, 2);
  if medio not in ('Efectivo', 'Transferencia') or importe is null or importe <= 0 then
   raise exception 'Pago inválido.' using errcode = 'PT422'; end if;
  pagado := pagado + importe;
 end loop;
 if pagado > v_total + 0.005 then
  raise exception 'El pago es más que el total de la venta.' using errcode = 'PT422'; end if;
 if cliente = public.consumidor_final_id() and abs(pagado - v_total) > 0.005 then
  raise exception 'A "Consumidor final" no se le puede fiar: cobrá el total.' using errcode = 'PT422'; end if;

 update public.pedidos set total = v_total where id = p_id;

 -- Stock del lugar elegido (abre cajas si hace falta), como la entrega.
 select coalesce(jsonb_agg(jsonb_build_object('producto_id', producto_id, 'cantidad_delta', -cant, 'tipo', 'venta_directa')
   order by producto_id), '[]')
 into deltas
 from (select d.producto_id, sum(d.cantidad) cant from public.pedido_detalles d where d.pedido_id = p_id
  group by d.producto_id) s;
 evento := public.stock_registrar_evento(ubic, 'finalizacion_pedido', p_id, p_id,
  jsonb_build_object('items', deltas, 'motivo', 'Venta especial'), f);
 movimientos := public.stock_aplicar_deltas(ubic, evento, deltas);

 update public.pedidos set estado = 'entregado', resultado_entrega = 'entregado', fecha_finalizacion = f
 where id = p_id;

 for x in select value from jsonb_array_elements(coalesce(p_pagos, '[]')) loop
  cobro := null;
  select r.cobro_id into cobro from public.registrar_pago_cliente(cliente, round((x->>'importe')::numeric, 2),
   btrim(x->>'medio'), 'Venta especial') r limit 1;
  if cobro is not null then
   update public.cobros_cliente set fecha_pago = f where id = cobro;
   update public.pedido_pagos set fecha_pago = f where cobro_id = cobro;
  end if;
 end loop;

 select s.saldo_pendiente into saldo from public.saldos_pendientes_pedidos s where s.pedido_id = p_id;
 res := jsonb_build_object('pedido_id', p_id, 'cliente_id', cliente, 'total', v_total, 'costo', round(v_costo, 2),
  'ganancia', round(v_total - v_costo, 2), 'pagado', pagado, 'saldo_pendiente', coalesce(saldo, 0),
  'movimientos_stock', movimientos);
 insert into public.ventas_especiales(id, request_hash, resultado, actor_id) values (p_id, huella, res, auth.uid());
 return res;
end $$;

revoke all on function public.consumidor_final_id() from public, anon;
grant execute on function public.consumidor_final_id() to authenticated;
revoke all on function public.venta_especial(uuid, timestamptz, uuid, text, jsonb, jsonb, text) from public, anon;
grant execute on function public.venta_especial(uuid, timestamptz, uuid, text, jsonb, jsonb, text) to authenticated;
