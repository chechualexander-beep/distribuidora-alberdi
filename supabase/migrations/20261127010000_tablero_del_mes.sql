-- Gestión del negocio, etapa 2: tablero del mes. Solo administración.
-- Resultado: ventas − costo − comisiones (± notas de crédito) = ganancia comercial (lo calcula
-- resumen_comercial, el mismo del "Resumen comercial"); − gastos del negocio = ganancia del negocio;
-- − plata para la casa = lo que quedó para el negocio (negativo: salió del capital).
-- Capital del negocio = plata + mercadería al costo + lo que deben los clientes − saldo a favor de
-- clientes − proveedores a pagar. Se guarda una foto por día (al abrir el tablero o la plata) para
-- comparar mes a mes.

create table public.fin_capital_fotos (
 fecha date primary key,
 plata numeric(14,2) not null,
 mercaderia numeric(14,2) not null,
 clientes numeric(14,2) not null,
 a_favor numeric(14,2) not null,
 proveedores numeric(14,2) not null,
 total numeric(14,2) not null,
 guardado_at timestamptz not null default now()
);
alter table public.fin_capital_fotos enable row level security;
revoke all on public.fin_capital_fotos from anon, authenticated;

-- Capital de hoy.
create function public.fin_capital_hoy() returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare plata numeric; merca numeric; con_stock integer; sin_costo integer; clientes numeric; a_favor numeric;
 proveedores numeric;
begin
 perform public.fin_exigir_admin();
 select coalesce(sum(x.importe), 0) into plata from public.fin_flujo('-infinity', 'infinity') x;
 select coalesce(sum(greatest(s.cant, 0) * coalesce(p.costo, 0)), 0), count(*),
  count(*) filter (where s.cant > 0 and coalesce(p.costo, 0) <= 0)
 into merca, con_stock, sin_costo
 from public.productos p
 left join (select sa.producto_id, sum(sa.cantidad) cant from public.stock_actual sa group by sa.producto_id) s
  on s.producto_id = p.id
 where p.activo and p.control_stock;
 select coalesce(sum(greatest(v.saldo_pendiente, 0)), 0), coalesce(sum(greatest(v.saldo_a_favor, 0)), 0)
 into clientes, a_favor from public.saldos_pendientes_clientes v;
 select coalesce(sum(d.importe + coalesce((select sum(m.importe) from public.fin_movimientos m
   where m.deuda_id = d.id and m.anulado_at is null), 0)), 0)
 into proveedores from public.fin_deudas d where d.anulado_at is null;
 return jsonb_build_object('fecha', public.fin_hoy(), 'plata', plata, 'mercaderia', merca, 'clientes', clientes,
  'a_favor', a_favor, 'proveedores', proveedores,
  'total', plata + merca + clientes - a_favor - proveedores,
  'productos_con_stock', con_stock, 'productos_sin_costo', sin_costo,
  'plata_iniciada', (select c.inicio is not null from public.fin_config c));
end $$;

-- Guarda (o actualiza) la foto de hoy. Lo llama la app al abrir el tablero o la plata.
create function public.fin_guardar_capital() returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare c jsonb;
begin
 perform public.fin_exigir_admin();
 if (select f.inicio from public.fin_config f) is null then return null; end if;
 c := public.fin_capital_hoy();
 insert into public.fin_capital_fotos(fecha, plata, mercaderia, clientes, a_favor, proveedores, total)
 values ((c->>'fecha')::date, (c->>'plata')::numeric, (c->>'mercaderia')::numeric, (c->>'clientes')::numeric,
  (c->>'a_favor')::numeric, (c->>'proveedores')::numeric, (c->>'total')::numeric)
 on conflict (fecha) do update set plata = excluded.plata, mercaderia = excluded.mercaderia,
  clientes = excluded.clientes, a_favor = excluded.a_favor, proveedores = excluded.proveedores,
  total = excluded.total, guardado_at = now();
 return c;
end $$;

create function public.fin_foto_capital_antes(p_fecha date) returns jsonb
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
 select to_jsonb(f) from public.fin_capital_fotos f where f.fecha < p_fecha order by f.fecha desc limit 1
$$;

-- Tablero de un mes (p_mes: cualquier día del mes). Por GET.
create function public.fin_tablero(p_mes date) returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare tz constant text := 'America/Argentina/Buenos_Aires'; hoy date := public.fin_hoy();
 mes date := date_trunc('month', coalesce(p_mes, hoy))::date; sig date; desde timestamptz; hasta timestamptz;
 com jsonb; anual jsonb; inicio timestamptz; ventas numeric; costo numeric; comisiones numeric; ganancia numeric;
 nc numeric; gastos numeric := 0; hogar numeric := 0; margen numeric; actual boolean; capital jsonb;
 cap_inicio jsonb; cap_cierre jsonb; dias integer; dia integer;
begin
 perform public.fin_exigir_admin();
 sig := (mes + interval '1 month')::date;
 desde := mes::timestamp at time zone tz; hasta := sig::timestamp at time zone tz;
 actual := hoy >= mes and hoy < sig;
 com := public.resumen_comercial(desde, hasta);
 ventas := coalesce((com->>'mercaderia_neta')::numeric, 0);
 costo := coalesce((com->>'costo_mercaderia')::numeric, 0);
 comisiones := coalesce((com->>'comisiones')::numeric, 0);
 ganancia := coalesce((com->>'ganancia')::numeric, 0);
 -- Notas de crédito, costo recuperado y comisiones revertidas, en una línea que cierra la cuenta.
 nc := ganancia - (ventas - costo - comisiones);
 select c.inicio into inicio from public.fin_config c;
 if inicio is not null then
  select coalesce(sum(-x.importe - x.parte_hogar) filter (where x.tipo in ('gasto', 'gasto_fijo')), 0),
   coalesce(sum(x.parte_hogar), 0)
  into gastos, hogar from public.fin_flujo(desde, hasta) x;
 end if;
 margen := case when ventas > 0 then ganancia / ventas end;
 anual := public.resumen_comercial(hasta - interval '12 months', least(hasta, now()));
 dias := sig - mes;
 dia := case when actual then hoy - mes + 1 else dias end;
 cap_inicio := public.fin_foto_capital_antes(mes);
 if actual then capital := public.fin_capital_hoy();
 else cap_cierre := public.fin_foto_capital_antes(sig); end if;
 return jsonb_build_object(
  'mes', mes, 'actual', actual, 'dia', dia, 'dias', dias,
  'ventas', ventas, 'costo', costo, 'comisiones', comisiones, 'notas_credito', nc,
  'ganancia_comercial', ganancia, 'margen', margen,
  'gastos_negocio', gastos, 'ganancia_negocio', ganancia - gastos,
  'hogar', hogar, 'quedo', ganancia - gastos - hogar,
  'plata_desde', inicio, 'plata_parcial', inicio is null or inicio > desde,
  'ventas_necesarias', case when margen > 0 then (gastos + hogar) / margen end,
  'ventas_12_meses', coalesce((anual->>'mercaderia_neta')::numeric, 0),
  'capital', capital, 'capital_inicio', cap_inicio, 'capital_cierre', cap_cierre);
end $$;

revoke all on function public.fin_foto_capital_antes(date) from public, anon, authenticated;
revoke all on function public.fin_capital_hoy(), public.fin_guardar_capital(), public.fin_tablero(date) from public, anon;
grant execute on function public.fin_capital_hoy(), public.fin_guardar_capital(), public.fin_tablero(date) to authenticated;
