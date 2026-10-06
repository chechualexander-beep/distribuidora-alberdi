-- Notas de crédito internas: movimientos nuevos; originales inalterados.
create table public.notas_credito (
 id uuid primary key default gen_random_uuid(),
 numero bigint generated always as identity unique,
 clave text not null unique,
 solicitud jsonb not null,
 pedido_id uuid not null references public.pedidos(id),
 cliente_id uuid not null references public.clientes(id),
 preventista_id uuid not null references public.usuarios(id),
 motivo text not null check (length(trim(motivo)) > 0),
 fecha timestamptz not null default now(),
 usuario_id uuid not null references public.usuarios(id),
 total numeric(14,2) not null default 0 check(total >= 0)
);
create table public.nota_credito_detalles (
 id uuid primary key default gen_random_uuid(),
 nota_id uuid not null references public.notas_credito(id),
 pedido_detalle_id uuid not null references public.pedido_detalles(id),
 cantidad numeric(12,2) not null check(cantidad > 0),
 precio_unitario numeric not null,
 importe numeric(14,2) not null check(importe >= 0),
 costo numeric(14,2) not null check(costo >= 0),
 comision numeric(14,2) not null check(comision >= 0),
 unique(nota_id, pedido_detalle_id)
);
create table public.recepciones_nota_credito (
 id uuid primary key default gen_random_uuid(),
 detalle_id uuid not null unique references public.nota_credito_detalles(id),
 fecha timestamptz not null default now(),
 usuario_id uuid not null references public.usuarios(id),
 apta_venta boolean not null
);
create table public.movimientos_credito_cliente (
 id uuid primary key default gen_random_uuid(),
 pedido_origen_id uuid not null references public.pedidos(id),
 pedido_destino_id uuid references public.pedidos(id),
 importe numeric(14,2) not null check(importe > 0),
 fecha timestamptz not null default now(),
 usuario_id uuid not null references public.usuarios(id),
 medio_pago text,
 clave text unique,
 check(pedido_destino_id is distinct from pedido_origen_id),
 check(pedido_destino_id is not null or length(trim(medio_pago)) > 0)
);
create table public.ajustes_comision_aplicados (
 id uuid primary key default gen_random_uuid(),
 detalle_nc_id uuid not null references public.nota_credito_detalles(id),
 liquidacion_id uuid not null references public.liquidaciones(id),
 importe numeric(14,2) not null check(importe > 0),
 unique(detalle_nc_id, liquidacion_id)
);
create index on public.notas_credito(pedido_id);
create index on public.nota_credito_detalles(pedido_detalle_id);
create index on public.movimientos_credito_cliente(pedido_origen_id);
create index on public.movimientos_credito_cliente(pedido_destino_id);

-- Leer notas propias o de administración; escrituras solo por funciones.
alter table public.notas_credito enable row level security;
alter table public.nota_credito_detalles enable row level security;
alter table public.recepciones_nota_credito enable row level security;
alter table public.movimientos_credito_cliente enable row level security;
alter table public.ajustes_comision_aplicados enable row level security;
create policy nc_lectura on public.notas_credito for select to authenticated
 using(public.es_administrador() or preventista_id=auth.uid());
create policy nc_detalles_lectura on public.nota_credito_detalles for select to authenticated
 using(exists(select 1 from public.notas_credito n where n.id=nota_id));
create policy nc_recepciones_lectura on public.recepciones_nota_credito for select to authenticated
 using(exists(select 1 from public.nota_credito_detalles d where d.id=detalle_id));
create policy nc_movimientos_lectura on public.movimientos_credito_cliente for select to authenticated
 using(public.es_administrador() or exists(select 1 from public.pedidos p where p.id=pedido_origen_id and p.preventista_id=auth.uid()));
create policy nc_ajustes_lectura on public.ajustes_comision_aplicados for select to authenticated
 using(exists(select 1 from public.nota_credito_detalles d where d.id=detalle_nc_id));
revoke all on public.notas_credito, public.nota_credito_detalles, public.recepciones_nota_credito,
 public.movimientos_credito_cliente, public.ajustes_comision_aplicados from public, anon, authenticated;
grant select on public.notas_credito, public.nota_credito_detalles, public.recepciones_nota_credito,
 public.movimientos_credito_cliente, public.ajustes_comision_aplicados to authenticated;

create view public.balance_pedidos_nc with (security_invoker=true) as
select p.id as pedido_id, p.cliente_id, c.nombre_comercio, p.created_at, p.fecha_finalizacion,
 p.resultado_entrega, p.fecha_entrega,
 coalesce((select sum(d.cantidad_entregada*d.precio_unitario) from public.pedido_detalles d where d.pedido_id=p.id),0) as bruto,
 coalesce((select sum(n.total) from public.notas_credito n where n.pedido_id=p.id),0) as credito,
 coalesce((select sum(pp.importe) from public.pedido_pagos pp where pp.pedido_id=p.id),0) as pagado,
 coalesce((select sum(m.importe) from public.movimientos_credito_cliente m where m.pedido_destino_id=p.id),0) as aplicado,
 coalesce((select sum(m.importe) from public.movimientos_credito_cliente m where m.pedido_origen_id=p.id),0) as usado
from public.pedidos p join public.clientes c on c.id=p.cliente_id
where p.resultado_entrega in ('entregado','parcial') and p.estado <> 'cancelado';
revoke all on public.balance_pedidos_nc from public,anon,authenticated;
grant select on public.balance_pedidos_nc to authenticated;

create or replace view public.saldos_pendientes_pedidos with (security_invoker=true) as
select pedido_id, cliente_id, nombre_comercio, created_at, fecha_finalizacion, resultado_entrega,
 bruto as total_entregado, pagado as total_pagado,
 greatest(bruto-credito-pagado-aplicado,0) as saldo_pendiente, fecha_entrega,
 credito as total_notas_credito, bruto-credito as total_neto, aplicado as credito_aplicado,
 greatest(pagado+aplicado-(bruto-credito)-usado,0) as saldo_a_favor
from public.balance_pedidos_nc;
create or replace view public.saldos_pendientes_clientes with (security_invoker=true) as
select c.id as cliente_id,c.nombre_comercio,
 coalesce(sum(s.total_entregado),0) as total_entregado,
 coalesce(sum(least(s.total_pagado,s.total_entregado)),0) as total_pagado,
 coalesce(sum(s.saldo_pendiente),0) as saldo_pendiente,
 count(*) filter(where s.saldo_pendiente>0) as cantidad_pedidos_con_saldo,
 coalesce(sum(s.total_notas_credito),0) as total_notas_credito,
 coalesce(sum(s.saldo_a_favor),0) as saldo_a_favor,
 coalesce(sum(s.total_neto),0) as total_neto
from public.clientes c left join public.saldos_pendientes_pedidos s on s.cliente_id=c.id
group by c.id,c.nombre_comercio;

-- Serializar las operaciones financieras evita doble emisión, doble cobro
-- y carreras entre una devolución y su liquidación. Mantener orden de locks.
create function public.aplicar_credito_cliente(p_cliente_id uuid) returns numeric
language plpgsql security definer set search_path=public as $$
declare origen record; destino record; disponible numeric; aplicado numeric; total numeric:=0;
begin
 if public.es_administrador() is not true then raise exception 'Solo administración'; end if;
 perform pg_advisory_xact_lock(829001);
 for origen in select pedido_id,saldo_a_favor from public.saldos_pendientes_pedidos
  where cliente_id=p_cliente_id and saldo_a_favor>0 order by created_at,pedido_id
 loop
  disponible:=origen.saldo_a_favor;
  for destino in select pedido_id,saldo_pendiente from public.saldos_pendientes_pedidos
   where cliente_id=p_cliente_id and saldo_pendiente>0 order by coalesce(fecha_finalizacion,created_at),pedido_id
  loop
   exit when disponible<=0;
   aplicado:=least(disponible,destino.saldo_pendiente);
   insert into public.movimientos_credito_cliente(pedido_origen_id,pedido_destino_id,importe,usuario_id)
    values(origen.pedido_id,destino.pedido_id,aplicado,auth.uid());
   disponible:=disponible-aplicado; total:=total+aplicado;
  end loop;
 end loop;
 return total;
end;$$;

create function public.crear_nota_credito(p_pedido_id uuid,p_motivo text,p_detalles jsonb,p_clave text)
returns uuid language plpgsql security definer set search_path=public as $$
declare p public.pedidos%rowtype; d public.pedido_detalles%rowtype; n uuid; anterior jsonb;
 linea jsonb; cantidad numeric; devuelta numeric; comision_anterior numeric; importe_comision numeric;
 solicitud jsonb:=jsonb_build_object('pedido',p_pedido_id,'motivo',p_motivo,'detalles',p_detalles);
begin
 if public.es_administrador() is not true then raise exception 'Solo administración'; end if;
 if p_clave is null or length(p_clave) not between 10 and 200 then raise exception 'Clave de operación inválida'; end if;
 perform pg_advisory_xact_lock(829001);
 select id,notas_credito.solicitud into n,anterior from public.notas_credito where clave=p_clave;
 if found then
  if anterior<>solicitud then raise exception 'Clave utilizada por otra operación'; end if;
  return n;
 end if;
 select * into p from public.pedidos where id=p_pedido_id for update;
 if not found or p.resultado_entrega not in ('entregado','parcial') or p.estado in ('cancelado','anulado') then
  raise exception 'Se requiere un pedido entregado o parcial';
 end if;
 if nullif(trim(p_motivo),'') is null then raise exception 'Indicá el motivo'; end if;
 if p_detalles is null or jsonb_typeof(p_detalles)<>'array' or jsonb_array_length(p_detalles)=0 then
  raise exception 'Seleccioná mercadería para devolver'; end if;
 if exists(select 1 from jsonb_array_elements(p_detalles) x group by x->>'detalle_id' having count(*)>1) then
  raise exception 'Producto duplicado en la solicitud'; end if;
 insert into public.notas_credito(clave,solicitud,pedido_id,cliente_id,preventista_id,motivo,usuario_id)
 values(p_clave,solicitud,p.id,p.cliente_id,p.preventista_id,trim(p_motivo),auth.uid()) returning id into n;
 for linea in select value from jsonb_array_elements(p_detalles) loop
  select * into d from public.pedido_detalles where id=(linea->>'detalle_id')::uuid and pedido_id=p.id for update;
  if not found then raise exception 'Detalle ajeno al pedido'; end if;
  cantidad:=(linea->>'cantidad')::numeric;
  if cantidad is null or cantidad<=0 or cantidad<>round(cantidad,2) then raise exception 'Cantidad inválida'; end if;
  select coalesce(sum(nd.cantidad),0),coalesce(sum(nd.comision),0) into devuelta,comision_anterior
   from public.nota_credito_detalles nd where nd.pedido_detalle_id=d.id;
  if cantidad+devuelta>d.cantidad_entregada then raise exception 'La devolución supera lo entregado disponible'; end if;
  -- Prorrateo acumulado del importe realmente generado, sin errores por redondeos sucesivos.
  importe_comision:=round(coalesce(d.importe_comision,0)*(cantidad+devuelta)/d.cantidad_entregada,2)-comision_anterior;
  insert into public.nota_credito_detalles(nota_id,pedido_detalle_id,cantidad,precio_unitario,importe,costo,comision)
   values(n,d.id,cantidad,d.precio_unitario,round(cantidad*d.precio_unitario,2),
   round(cantidad*coalesce(d.costo_unitario,0),2),importe_comision);
 end loop;
 update public.notas_credito set total=(select sum(importe) from public.nota_credito_detalles where nota_id=n) where id=n;
 perform public.aplicar_credito_cliente(p.cliente_id);
 return n;
end;$$;

create function public.recibir_nota_credito(p_detalle_id uuid,p_apta_venta boolean) returns void
language plpgsql security definer set search_path=public as $$
begin
 if public.es_administrador() is not true then raise exception 'Solo administración'; end if;
 if p_apta_venta is null then raise exception 'Indicá el estado de recepción'; end if;
 perform pg_advisory_xact_lock(829001);
 if exists(select 1 from public.recepciones_nota_credito where detalle_id=p_detalle_id and apta_venta<>p_apta_venta) then
  raise exception 'La recepción ya fue registrada con otro estado'; end if;
 insert into public.recepciones_nota_credito(detalle_id,usuario_id,apta_venta)
 values(p_detalle_id,auth.uid(),p_apta_venta) on conflict(detalle_id) do nothing;
 -- Registro físico independiente. No modificar productos.stock: el circuito
 -- actual no lleva entradas/salidas consistentes de inventario.
end;$$;

create function public.reintegrar_credito_cliente(p_cliente_id uuid,p_importe numeric,p_medio text,p_clave text)
returns numeric language plpgsql security definer set search_path=public as $$
declare r record; restante numeric:=p_importe; monto numeric;
begin
 if public.es_administrador() is not true then raise exception 'Solo administración'; end if;
 if p_importe is null or p_importe<=0 or p_importe<>round(p_importe,2) or nullif(trim(p_medio),'') is null
  or p_clave is null or length(p_clave) not between 10 and 180 then raise exception 'Datos de reintegro inválidos'; end if;
 perform pg_advisory_xact_lock(829001);
 if exists(select 1 from public.movimientos_credito_cliente where split_part(clave,':',1)=p_clave) then
  raise exception 'Este reintegro ya fue registrado. Actualizá la cuenta del cliente.'; end if;
 if p_importe > coalesce((select sum(saldo_a_favor) from public.saldos_pendientes_pedidos where cliente_id=p_cliente_id),0) then
  raise exception 'El importe supera el saldo a favor'; end if;
 for r in select pedido_id,saldo_a_favor from public.saldos_pendientes_pedidos
  where cliente_id=p_cliente_id and saldo_a_favor>0 order by created_at,pedido_id loop
  exit when restante<=0; monto:=least(restante,r.saldo_a_favor);
  insert into public.movimientos_credito_cliente(pedido_origen_id,importe,usuario_id,medio_pago,clave)
   values(r.pedido_id,monto,auth.uid(),trim(p_medio),p_clave||':'||r.pedido_id);
  restante:=restante-monto;
 end loop;
 return p_importe;
end;$$;

create or replace function public.registrar_pago_cliente(p_cliente_id uuid,p_importe numeric,p_medio_pago text,p_observacion text default null)
returns table(cobro_id uuid,pedido_id uuid,importe_aplicado numeric,saldo_restante numeric)
language plpgsql security definer set search_path=public as $$
declare restante numeric:=p_importe; cobro uuid; r record; monto numeric;
begin
 if public.es_administrador() is not true then raise exception 'Solo administración'; end if;
 perform pg_advisory_xact_lock(829001);
 perform 1 from public.pedidos p where p.cliente_id=p_cliente_id for update;
 if p_importe is null or p_importe<=0 or nullif(trim(p_medio_pago),'') is null then raise exception 'Pago inválido'; end if;
 perform public.aplicar_credito_cliente(p_cliente_id);
 if p_importe>coalesce((select sum(s.saldo_pendiente) from public.saldos_pendientes_pedidos s where s.cliente_id=p_cliente_id),0) then
  raise exception 'El pago supera la deuda neta del cliente. Actualizá su saldo.'; end if;
 insert into public.cobros_cliente(cliente_id,importe,medio_pago,observacion)
 values(p_cliente_id,p_importe,p_medio_pago,p_observacion) returning id into cobro;
 for r in select s.pedido_id,s.saldo_pendiente from public.saldos_pendientes_pedidos s
  where s.cliente_id=p_cliente_id and s.saldo_pendiente>0
  order by coalesce(s.fecha_finalizacion,s.created_at),s.created_at,s.pedido_id loop
  exit when restante<=0; monto:=least(restante,r.saldo_pendiente);
  insert into public.pedido_pagos(pedido_id,cobro_id,importe,medio_pago,observacion)
   values(r.pedido_id,cobro,monto,p_medio_pago,'Pago distribuido automáticamente');
  cobro_id:=cobro; pedido_id:=r.pedido_id; importe_aplicado:=monto; saldo_restante:=r.saldo_pendiente-monto;
  return next; restante:=restante-monto;
 end loop;
 if restante<>0 then raise exception 'No se pudo imputar el pago completo'; end if;
end;$$;

-- Mantener la gestión original, aplicando crédito antes de calcular pago completo.
alter function public.finalizar_gestion_pedido(uuid,text,text,text,jsonb,text,numeric,text) rename to finalizar_gestion_pedido_sin_nc;
create function public.finalizar_gestion_pedido(p_pedido_id uuid,p_estado text,p_resultado_entrega text,p_motivo_no_entrega text,
 p_detalles jsonb,p_tipo_pago text,p_importe_pago numeric default null,p_medio_pago text default null)
returns void language plpgsql security definer set search_path=public as $$
declare cliente uuid; saldo numeric;
begin
 if public.es_administrador() is not true then raise exception 'Solo administración'; end if;
 perform pg_advisory_xact_lock(829001);
 if p_tipo_pago is null or p_tipo_pago not in ('sin_pago','parcial','completo') then raise exception 'Tipo de pago inválido'; end if;
 if p_resultado_entrega='no_entregado' and p_tipo_pago<>'sin_pago' then raise exception 'No corresponde cobrar sin entrega'; end if;
 perform public.finalizar_gestion_pedido_sin_nc(p_pedido_id,p_estado,p_resultado_entrega,p_motivo_no_entrega,p_detalles,'sin_pago',null,null);
 select cliente_id into cliente from public.pedidos where id=p_pedido_id;
 perform public.aplicar_credito_cliente(cliente);
 if p_tipo_pago='parcial' then
  perform 1 from public.registrar_pago_cliente(cliente,p_importe_pago,p_medio_pago,'Pago parcial al entregar el pedido');
 elsif p_tipo_pago='completo' then
  select saldo_pendiente into saldo from public.saldos_pendientes_pedidos where pedido_id=p_pedido_id;
  if p_importe_pago is not null and p_importe_pago is distinct from saldo then
    raise exception 'Cambió el saldo a cobrar. Volvé a revisar la gestión.'; end if;
  if saldo>0 then perform 1 from public.registrar_pago_cliente(cliente,saldo,p_medio_pago,'Pago completo al entregar el pedido'); end if;
 end if;
end;$$;

alter function public.corregir_operacion_finalizada(uuid,text,jsonb) rename to corregir_operacion_sin_nc;
create function public.corregir_operacion_finalizada(p_pedido_id uuid,p_motivo text,p_detalles jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if public.es_administrador() is not true then raise exception 'Solo administración'; end if;
 perform pg_advisory_xact_lock(829001);
 if exists(select 1 from public.notas_credito where pedido_id=p_pedido_id)
  or exists(select 1 from public.movimientos_credito_cliente where pedido_destino_id=p_pedido_id) then
  raise exception 'La operación tiene notas o créditos aplicados. Usá una nota de crédito para devolver mercadería.'; end if;
 return public.corregir_operacion_sin_nc(p_pedido_id,p_motivo,p_detalles);
end;$$;

create view public.ajustes_comision_nc with (security_invoker=true) as
select d.id, n.numero, n.pedido_id,n.cliente_id,n.preventista_id,n.fecha,n.motivo,
 c.nombre_comercio,d.pedido_detalle_id,d.comision,
 d.comision-coalesce((select sum(a.importe) from public.ajustes_comision_aplicados a where a.detalle_nc_id=d.id),0) as pendiente
from public.nota_credito_detalles d join public.notas_credito n on n.id=d.nota_id
join public.clientes c on c.id=n.cliente_id;
revoke all on public.ajustes_comision_nc from public,anon,authenticated;
grant select on public.ajustes_comision_nc to authenticated;
alter table public.liquidaciones add column comision_bruta numeric, add column ajustes_nc numeric not null default 0;

create function public.previsualizar_liquidacion_nc(p_preventista_id uuid,p_detalle_ids uuid[])
returns jsonb language plpgsql security definer set search_path=public as $$
declare bruto numeric; venta numeric; ajustes jsonb; pendiente numeric; aplicado numeric; resultado jsonb;
begin
 if public.es_administrador() is not true then raise exception 'Solo administración'; end if;
 if cardinality(p_detalle_ids) is null or cardinality(p_detalle_ids)=0 then raise exception 'Seleccioná detalles pendientes'; end if;
 if cardinality(p_detalle_ids)<>(select count(distinct x) from unnest(p_detalle_ids) x) then raise exception 'Detalles duplicados'; end if;
 if (select count(*) from public.pedido_detalles d join public.pedidos p on p.id=d.pedido_id
  where d.id=any(p_detalle_ids) and p.preventista_id=p_preventista_id
  and p.resultado_entrega in ('entregado','parcial') and p.estado not in ('cancelado','anulado')
  and not exists(select 1 from public.liquidacion_detalles ld where ld.pedido_detalle_id=d.id))<>cardinality(p_detalle_ids) then
  raise exception 'Los detalles cambiaron o ya fueron liquidados. Volvé a calcular.'; end if;
 select coalesce(sum(d.importe_comision),0),coalesce(sum(d.cantidad_entregada*d.precio_unitario),0)
 into bruto,venta from public.pedido_detalles d where d.id=any(p_detalle_ids);
 select coalesce(jsonb_agg(to_jsonb(a) order by a.fecha,a.id),'[]'::jsonb),coalesce(sum(a.pendiente),0)
 into ajustes,pendiente from public.ajustes_comision_nc a
 where a.preventista_id=p_preventista_id and a.pendiente>0
 and (a.pedido_detalle_id=any(p_detalle_ids) or exists(select 1 from public.liquidacion_detalles ld where ld.pedido_detalle_id=a.pedido_detalle_id));
 aplicado:=least(bruto,pendiente);
 resultado:=jsonb_build_object('bruto',bruto,'venta',venta,'ajustes',ajustes,'descuento',aplicado,
  'neto',bruto-aplicado,'remanente',pendiente-aplicado);
 return resultado || jsonb_build_object('token',md5(resultado::text || p_detalle_ids::text || p_preventista_id::text));
end;$$;

alter function public.registrar_liquidacion(uuid,date,date,numeric,numeric,jsonb) rename to registrar_liquidacion_sin_nc;
create function public.registrar_liquidacion_con_nc(p_preventista_id uuid,p_fecha_desde date,p_fecha_hasta date,
 p_detalle_ids uuid[],p_token text) returns uuid
language plpgsql security definer set search_path=public as $$
declare vista jsonb; detalles jsonb; liq uuid; restante numeric; ajuste jsonb; monto numeric;
begin
 if public.es_administrador() is not true then raise exception 'Solo administración'; end if;
 perform pg_advisory_xact_lock(829001);
 -- Una corrección utiliza el mismo lock y no puede cambiar importes entre revisión y pago.
 vista:=public.previsualizar_liquidacion_nc(p_preventista_id,p_detalle_ids);
 if p_token is distinct from vista->>'token' then raise exception 'Los importes cambiaron. Revisá nuevamente la liquidación.'; end if;
 select jsonb_agg(jsonb_build_object('pedido_detalle_id',id,'importe_comision',importe_comision))
 into detalles from public.pedido_detalles where id=any(p_detalle_ids);
 liq:=public.registrar_liquidacion_sin_nc(p_preventista_id,p_fecha_desde,p_fecha_hasta,
  (vista->>'venta')::numeric,(vista->>'bruto')::numeric,detalles);
 restante:=(vista->>'descuento')::numeric;
 for ajuste in select value from jsonb_array_elements(vista->'ajustes') loop
  exit when restante<=0;
  monto:=least(restante,(ajuste->>'pendiente')::numeric);
  insert into public.ajustes_comision_aplicados(detalle_nc_id,liquidacion_id,importe)
   values((ajuste->>'id')::uuid,liq,monto);
  restante:=restante-monto;
 end loop;
 update public.liquidaciones set comision_bruta=(vista->>'bruto')::numeric,
  ajustes_nc=(vista->>'descuento')::numeric,comision_total=(vista->>'neto')::numeric where id=liq;
 return liq;
end;$$;

-- Clientes antiguos pueden seguir liquidando si no hay descuentos pendientes;
-- si los hay, exigir la pantalla que muestra explícitamente el neto.
create function public.registrar_liquidacion(p_preventista_id uuid,p_fecha_desde date,p_fecha_hasta date,
 p_venta_entregada numeric,p_comision_total numeric,p_detalles jsonb) returns uuid
language plpgsql security definer set search_path=public as $$
declare ids uuid[]; vista jsonb;
begin
 if public.es_administrador() is not true then raise exception 'Solo administración'; end if;
 perform pg_advisory_xact_lock(829001);
 select array_agg((x->>'pedido_detalle_id')::uuid) into ids from jsonb_array_elements(p_detalles) x;
 vista:=public.previsualizar_liquidacion_nc(p_preventista_id,ids);
 if jsonb_array_length(vista->'ajustes')>0 then raise exception 'Hay notas de crédito. Actualizá la app y revisá la liquidación neta.'; end if;
 if p_comision_total is distinct from (vista->>'bruto')::numeric or p_venta_entregada is distinct from (vista->>'venta')::numeric then
  raise exception 'Los importes cambiaron. Volvé a calcular.'; end if;
 return public.registrar_liquidacion_con_nc(p_preventista_id,p_fecha_desde,p_fecha_hasta,ids,vista->>'token');
end;$$;

alter function public.resumen_comercial(timestamptz,timestamptz) rename to resumen_comercial_sin_nc;
create function public.resumen_comercial(p_inicio timestamptz,p_fin timestamptz)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb; nc numeric; comision numeric; recuperado numeric; reintegros numeric;
begin
 r:=public.resumen_comercial_sin_nc(p_inicio,p_fin);
 select coalesce(sum(d.importe),0),coalesce(sum(d.comision),0) into nc,comision
 from public.nota_credito_detalles d join public.notas_credito n on n.id=d.nota_id
 where n.fecha>=p_inicio and n.fecha<p_fin;
 select coalesce(sum(d.costo),0) into recuperado from public.recepciones_nota_credito rc
 join public.nota_credito_detalles d on d.id=rc.detalle_id
 where rc.apta_venta and rc.fecha>=p_inicio and rc.fecha<p_fin;
 select coalesce(sum(importe),0) into reintegros from public.movimientos_credito_cliente
 where pedido_destino_id is null and fecha>=p_inicio and fecha<p_fin;
 return r || jsonb_build_object('notas_credito',nc,'mercaderia_neta',(r->>'entrega_total')::numeric-nc,
  'comisiones_revertidas',comision,'costo_recuperado',recuperado,'reintegros',reintegros,
  'recaudacion_neta',(r->>'recaudacion_total')::numeric-reintegros,
  'ganancia',(r->>'ganancia')::numeric-nc+recuperado+comision);
end;$$;

-- Sin acceso público a funciones base que eviten validaciones de notas.
revoke all on function public.finalizar_gestion_pedido_sin_nc(uuid,text,text,text,jsonb,text,numeric,text),
 public.corregir_operacion_sin_nc(uuid,text,jsonb),public.registrar_liquidacion_sin_nc(uuid,date,date,numeric,numeric,jsonb),
 public.resumen_comercial_sin_nc(timestamptz,timestamptz) from public,anon,authenticated;

-- Cerrar el EXECUTE por defecto en todas las funciones incorporadas.
do $$ declare r record; begin
 for r in select p.oid::regprocedure as firma from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname in ('crear_nota_credito','recibir_nota_credito','reintegrar_credito_cliente',
 'aplicar_credito_cliente','previsualizar_liquidacion_nc','registrar_liquidacion_con_nc','registrar_liquidacion',
 'registrar_pago_cliente','finalizar_gestion_pedido','corregir_operacion_finalizada','resumen_comercial') loop
 execute format('revoke all on function %s from public,anon',r.firma);
 execute format('grant execute on function %s to authenticated',r.firma);
 end loop;
end;$$;

revoke all on sequence public.notas_credito_numero_seq from public,anon,authenticated;
