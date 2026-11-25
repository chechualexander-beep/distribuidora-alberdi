-- La foto inicial se compara por el día de Argentina (no el del servidor, en UTC): después de las 21 h, un gasto
-- que vencía ese día quedaba como "vencido antes de la foto" y no se apartaba.

create or replace function public.fin_sabado_estado() returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare inicio timestamptz; hoy date := public.fin_hoy(); sobres jsonb;
begin
 perform public.fin_exigir_admin();
 select c.inicio into inicio from public.fin_config c;
 if inicio is null then return jsonb_build_object('iniciado', false); end if;
 sobres := public.fin_sobres(hoy, (inicio at time zone 'America/Argentina/Buenos_Aires')::date);
 return jsonb_build_object('iniciado', true, 'fin_de_semana', extract(isodow from hoy) in (6, 7),
  'poner', (select coalesce(sum((x->>'poner_sabado')::numeric), 0) from jsonb_array_elements(sobres) x),
  'sobres', sobres, 'sueldo', public.fin_sueldo_estado());
end $$;

create or replace function public.fin_estado() returns jsonb
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare inicio timestamptz; hoy date := public.fin_hoy(); mes_desde timestamptz; cuentas jsonb; gastos jsonb;
 deudas jsonb; plata numeric; libre numeric; sobre numeric; deben numeric; mes jsonb; ultimos jsonb; sobres jsonb;
 faltan numeric;
begin
 perform public.fin_exigir_admin();
 select c.inicio into inicio from public.fin_config c;
 mes_desde := date_trunc('month', hoy)::timestamp at time zone 'America/Argentina/Buenos_Aires';
 select coalesce(jsonb_agg(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre,
   'saldo', coalesce((select sum(x.importe) from public.fin_flujo('-infinity', 'infinity') x where x.cuenta = c.codigo), 0))
   order by c.orden), '[]')
 into cuentas from public.fin_cuentas c;
 select coalesce(sum((x->>'saldo')::numeric), 0),
  coalesce(sum((x->>'saldo')::numeric) filter (where x->>'codigo' in ('efectivo', 'billetera')), 0)
 into plata, libre from jsonb_array_elements(cuentas) x;
 select coalesce(jsonb_agg(public.fin_sobre_de(g, hoy, (inicio at time zone 'America/Argentina/Buenos_Aires')::date) order by g.activo desc, g.dia_pago, g.nombre), '[]')
 into gastos from public.fin_gastos_fijos g;
 sobres := public.fin_sobres(hoy, (inicio at time zone 'America/Argentina/Buenos_Aires')::date);
 select coalesce(sum((x->>'deberia')::numeric), 0), coalesce(sum((x->>'faltan')::numeric), 0)
 into sobre, faltan from jsonb_array_elements(sobres) x;
 select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'proveedor', d.proveedor, 'importe', d.importe,
   'resta', d.resta, 'vence', d.vence, 'descripcion', d.descripcion, 'vencida', d.vence < hoy) order by d.vence), '[]'),
  coalesce(sum(d.resta), 0)
 into deudas, deben
 from (select d.*, d.importe + coalesce((select sum(m.importe) from public.fin_movimientos m
   where m.deuda_id = d.id and m.anulado_at is null), 0) resta
  from public.fin_deudas d where d.anulado_at is null) d
 where d.resta > 0;
 select jsonb_build_object(
   'cobros', coalesce(sum(x.importe) filter (where x.tipo = 'cobro'), 0),
   'ingresos', coalesce(sum(x.importe) filter (where x.tipo = 'ingreso' and x.categoria is distinct from 'Aporte del dueño'), 0),
   'compras', coalesce(-sum(x.importe) filter (where x.tipo in ('compra', 'pago_proveedor')), 0),
   'comisiones', coalesce(-sum(x.importe) filter (where x.tipo = 'comision'), 0),
   'devoluciones', coalesce(-sum(x.importe) filter (where x.tipo = 'devolucion'), 0),
   'hogar', coalesce(sum(x.parte_hogar), 0),
   'ajustes', coalesce(sum(x.importe) filter (where x.tipo = 'ajuste'), 0))
  || (public.fin_totales(mes_desde, 'infinity') - 'gastos_por_categoria')
 into mes from public.fin_flujo(mes_desde, 'infinity') x;
 select coalesce(jsonb_agg(to_jsonb(u) order by u.fecha desc), '[]') into ultimos
 from (select * from public.fin_flujo('-infinity', 'infinity') order by fecha desc limit 40) u;
 return jsonb_build_object('inicio', inicio, 'hoy', hoy, 'cuentas', cuentas, 'plata', plata, 'libre', libre,
  'gastos_fijos', gastos, 'sobre', sobre, 'sobres', sobres, 'faltan_sobres', faltan, 'deudas', deudas, 'deben', deben,
  'disponible', libre - deben - faltan, 'mes', mes, 'ultimos', ultimos,
  'sueldo', case when inicio is null then null else public.fin_sueldo_estado() end, 'consultado_at', now());
end $$;
