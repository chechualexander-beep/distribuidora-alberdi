-- Stock, etapa 2b: "Para reponer". Avisa antes de que se acabe un producto.
-- Por producto con control de stock (no "a pedido"): ritmo de venta = unidades entregadas en las últimas 8 semanas
-- (o desde la primera venta, si es más nuevo); libre = depósito + vehículo − pedidos facturados sin entregar;
-- alcanza = libre ÷ venta por día. Avisa si alcanza para menos de la demora del proveedor + 2 días, y sugiere comprar
-- para cubrir la demora + 7 días. Proveedor = el de la última compra del producto; la demora se carga por proveedor
-- (si no, 1 día). Por producto se puede "no avisar" o poner un mínimo propio. Los sueltos de un fraccionado suman al
-- ritmo del cerrado; si el suelto se acaba y hay cerrados, avisa "abrir". Administración y ayuda en el depósito (esta
-- sin costos).

create table public.stock_proveedores (
 clave text primary key,
 nombre text not null,
 demora_dias integer not null default 1 check (demora_dias between 0 and 15),
 actualizado_at timestamptz not null default now()
);
create table public.stock_reposicion_ajustes (
 producto_id uuid primary key references public.productos(id),
 no_avisar boolean not null default false,
 minimo numeric check (minimo is null or minimo >= 0),
 actualizado_at timestamptz not null default now()
);
alter table public.stock_proveedores enable row level security;
alter table public.stock_reposicion_ajustes enable row level security;
revoke all on public.stock_proveedores, public.stock_reposicion_ajustes from anon, authenticated;

create function public.stock_clave_proveedor(p text) returns text
language sql immutable set search_path = pg_catalog, public, pg_temp as $$
 select nullif(lower(regexp_replace(btrim(coalesce(p, '')), '\s+', ' ', 'g')), '')
$$;

-- p_todos: también los que alcanzan (para mostrar el ritmo al anotar una compra).
create function public.stock_reponer(p_todos boolean default false)
returns table(producto_id uuid, nombre text, accion text, proveedor text, demora integer, hay numeric,
 comprometido numeric, libre numeric, por_semana numeric, dias numeric, comprar numeric, origen text, abrir numeric,
 costo_total numeric, minimo numeric, no_avisar boolean)
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare admin boolean := public.es_administrador();
begin
 perform public.stock_exigir_deposito();
 return query
 with ventas as (
  select d.producto_id pid, sum(coalesce(d.cantidad_entregada, 0)) q,
   min(coalesce(p.fecha_finalizacion, p.fecha_entrega::timestamp at time zone 'America/Argentina/Buenos_Aires')) primera
  from public.pedidos p join public.pedido_detalles d on d.pedido_id = p.id
  where p.estado not in ('cancelado', 'anulado') and p.resultado_entrega in ('entregado', 'parcial')
   and coalesce(p.fecha_finalizacion, p.fecha_entrega::timestamp at time zone 'America/Argentina/Buenos_Aires')
    >= now() - interval '56 days'
  group by d.producto_id
 ), ritmo as (
  -- Unidades por día; con menos de una semana de historia se toma una semana.
  select v.pid, v.q / greatest(7, least(56, extract(epoch from now() - v.primera) / 86400)) por_dia from ventas v
 ), stock as (
  select sa.producto_id pid, sum(sa.cantidad) hay from public.stock_actual sa group by sa.producto_id
 ), comp as (
  select d.producto_id pid, sum(coalesce(d.cantidad_facturada, d.cantidad)) q
  from public.pedido_detalles d join public.pedidos p on p.id = d.pedido_id
  where p.resultado_entrega = 'pendiente' and p.facturado and p.tipo_operacion = 'pedido' and p.estado <> 'anulado'
  group by d.producto_id
 ), prov as (
  select distinct on (i.producto_id) i.producto_id pid, o.proveedor
  from public.stock_operacion_items i join public.stock_operaciones o on o.id = i.operacion_id
  where o.tipo = 'compra' and nullif(btrim(o.proveedor), '') is not null
  order by i.producto_id, o.fecha_fisica desc
 ), base as (
  select pr.id, pr.nombre, pr.fracciona_de, coalesce(pr.unidades_por_origen, 0) upo, coalesce(pr.costo, 0) costo,
   coalesce(s.hay, 0) hay, coalesce(c.q, 0) comp, coalesce(r.por_dia, 0) por_dia,
   coalesce(sp.nombre, btrim(pv.proveedor)) proveedor, coalesce(sp.demora_dias, 1) demora,
   a.minimo, coalesce(a.no_avisar, false) no_avisar
  from public.productos pr
  left join stock s on s.pid = pr.id left join comp c on c.pid = pr.id left join ritmo r on r.pid = pr.id
  left join prov pv on pv.pid = pr.id
  left join public.stock_proveedores sp on sp.clave = public.stock_clave_proveedor(pv.proveedor)
  left join public.stock_reposicion_ajustes a on a.producto_id = pr.id
  where pr.activo and pr.control_stock and not coalesce(pr.se_compra_a_pedido, false)
 ), hijos as (
  -- Lo que venden los sueltos, en unidades del cerrado; y sus sueltos libres, también en cerrados.
  select b.fracciona_de pid, sum(b.por_dia / b.upo) por_dia, sum(greatest(b.hay - b.comp, 0) / b.upo) libres
  from base b where b.fracciona_de is not null and b.upo > 0 group by b.fracciona_de
 ), calc as (
  select b.*, b.hay - b.comp libre_propio,
   b.por_dia + coalesce(h.por_dia, 0) por_dia_total,
   b.hay - b.comp + coalesce(h.libres, 0) libre_total,
   (select o.hay from base o where o.id = b.fracciona_de) hay_origen,
   (select o.nombre from base o where o.id = b.fracciona_de) nombre_origen
  from base b left join hijos h on h.pid = b.id
 ), eval as (
  select c.*,
   case when c.fracciona_de is null then c.libre_total else c.libre_propio end libre_eval,
   case when c.fracciona_de is null then c.por_dia_total else c.por_dia end ritmo_eval
  from calc c
 ), fila as (
  select e.*,
   case when e.ritmo_eval > 0 then round(e.libre_eval / e.ritmo_eval, 1) end dias_eval,
   (e.minimo is not null and e.libre_eval <= e.minimo)
    or (e.ritmo_eval > 0 and e.libre_eval / e.ritmo_eval < e.demora + 2) bajo
  from eval e
 )
 select f.id, f.nombre,
  case when not f.bajo then 'alcanza'
   when f.fracciona_de is not null and coalesce(f.hay_origen, 0) > 0 then 'abrir'
   else 'comprar' end,
  f.proveedor, f.demora, f.hay, f.comp, f.libre_eval, round(f.ritmo_eval * 7, 1), f.dias_eval,
  case when f.bajo and f.fracciona_de is null then
   greatest(1, ceil(greatest(f.ritmo_eval * (f.demora + 7), coalesce(f.minimo, 0) * 2) - f.libre_eval)) end,
  f.nombre_origen,
  case when f.bajo and f.fracciona_de is not null and coalesce(f.hay_origen, 0) > 0 and f.upo > 0 then
   least(f.hay_origen, greatest(1, ceil((f.ritmo_eval * 7 - greatest(f.libre_eval, 0)) / f.upo))) end,
  case when admin and f.bajo and f.fracciona_de is null then
   f.costo * greatest(1, ceil(greatest(f.ritmo_eval * (f.demora + 7), coalesce(f.minimo, 0) * 2) - f.libre_eval)) end,
  f.minimo, f.no_avisar
 from fila f
 where (f.ritmo_eval > 0 or f.minimo is not null)
  and (p_todos or (f.bajo and not f.no_avisar
   -- Un suelto sin cerrados para abrir no se avisa aparte: lo avisa el cerrado.
   and (f.fracciona_de is null or coalesce(f.hay_origen, 0) > 0)))
 order by f.dias_eval nulls first, f.nombre;
end $$;

-- Demora de un proveedor (días hasta que llega la mercadería). Solo administración.
create function public.stock_proveedor_demora(p_proveedor text, p_dias integer) returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare k text := public.stock_clave_proveedor(p_proveedor);
begin
 perform public.stock_exigir_admin();
 if k is null then raise exception 'Falta el proveedor' using errcode = 'PT422'; end if;
 if coalesce(p_dias, -1) not between 0 and 15 then
  raise exception 'La demora va de 0 a 15 días' using errcode = 'PT422'; end if;
 insert into public.stock_proveedores(clave, nombre, demora_dias) values (k, btrim(p_proveedor), p_dias)
 on conflict (clave) do update set demora_dias = excluded.demora_dias, actualizado_at = now();
end $$;

-- Por producto: no avisar, o un mínimo propio (null = usar el ritmo). Solo administración.
create function public.stock_reposicion_ajustar(p_producto uuid, p_no_avisar boolean, p_minimo numeric) returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
 perform public.stock_exigir_admin();
 if p_minimo is not null and p_minimo < 0 then
  raise exception 'El mínimo no puede ser negativo' using errcode = 'PT422'; end if;
 if not coalesce(p_no_avisar, false) and p_minimo is null then
  delete from public.stock_reposicion_ajustes where producto_id = p_producto;
 else
  insert into public.stock_reposicion_ajustes(producto_id, no_avisar, minimo)
  values (p_producto, coalesce(p_no_avisar, false), p_minimo)
  on conflict (producto_id) do update set no_avisar = excluded.no_avisar, minimo = excluded.minimo,
   actualizado_at = now();
 end if;
end $$;

revoke all on function public.stock_clave_proveedor(text) from public, anon, authenticated;
revoke all on function public.stock_reponer(boolean), public.stock_proveedor_demora(text, integer),
 public.stock_reposicion_ajustar(uuid, boolean, numeric) from public, anon;
grant execute on function public.stock_reponer(boolean), public.stock_proveedor_demora(text, integer),
 public.stock_reposicion_ajustar(uuid, boolean, numeric) to authenticated;
