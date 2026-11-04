-- Fase 2A-2. No activa automatización ni modifica inventario existente.
begin;

create table public.finalizacion_pedido_solicitudes (
 solicitud_id uuid primary key,
 pedido_id uuid not null unique references public.pedidos(id) on delete restrict,
 actor_id uuid not null references public.usuarios(id) on delete restrict,
 request_hash text not null check (request_hash ~ '^[a-f0-9]{64}$'),
 solicitud_normalizada jsonb not null check (jsonb_typeof(solicitud_normalizada)='object'),
 resultado_normalizado jsonb not null check (jsonb_typeof(resultado_normalizado)='object'),
 stock_evento_id uuid not null references public.stock_eventos(id) on delete restrict,
 created_at timestamptz not null default now(),
 completed_at timestamptz not null default now()
);
create index finalizacion_pedido_actor_idx on public.finalizacion_pedido_solicitudes(actor_id);
create index finalizacion_pedido_evento_idx on public.finalizacion_pedido_solicitudes(stock_evento_id);
alter table public.finalizacion_pedido_solicitudes enable row level security;
revoke all on public.finalizacion_pedido_solicitudes from public,anon,authenticated,service_role;
-- La consulta es por RPC, limitada al actor original; no lectura directa del historial.

create function public.finalizacion_normalizar_v1(
 p_pedido_id uuid,p_estado text,p_motivo_no_entrega text,p_originales jsonb,p_agregados jsonb,
 p_tipo_pago text,p_importe_pago numeric,p_medio_pago text,p_fecha_fisica timestamptz
) returns jsonb language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $$
#variable_conflict use_column
declare x jsonb; q numeric; ident uuid; lista text; originales jsonb:='[]'; agregados jsonb:='[]';
begin
 if p_pedido_id is null or p_estado is null or p_estado not in ('pendiente','preparado','en_reparto')
 or p_fecha_fisica is null or not isfinite(p_fecha_fisica)
 or p_tipo_pago is null or p_tipo_pago not in ('sin_pago','parcial','completo')
 or jsonb_typeof(p_originales) is distinct from 'array' or jsonb_typeof(p_agregados) is distinct from 'array' then
  raise exception 'Solicitud inválida' using errcode='PT422'; end if;
 if jsonb_array_length(p_originales) not between 1 and 300 or jsonb_array_length(p_agregados)>300
 or length(coalesce(p_motivo_no_entrega,''))>2000 then raise exception 'Solicitud inválida' using errcode='PT422'; end if;
 if p_tipo_pago='sin_pago' and (p_importe_pago is not null or p_medio_pago is not null) then
  raise exception 'Pago incompatible' using errcode='PT422'; end if;
 if p_tipo_pago<>'sin_pago' and (nullif(btrim(p_medio_pago),'') is null
 or (p_tipo_pago='parcial' and p_importe_pago is null)) then raise exception 'Pago inválido' using errcode='PT422'; end if;
 if p_importe_pago is not null and (p_importe_pago::text in ('NaN','Infinity','-Infinity')
 or p_importe_pago<0 or p_importe_pago>9999999999.99 or p_importe_pago<>round(p_importe_pago,2)
 or (p_tipo_pago='parcial' and p_importe_pago=0)) then raise exception 'Importe inválido' using errcode='PT422'; end if;
 for x in select value from jsonb_array_elements(p_originales) loop
  if jsonb_typeof(x) is distinct from 'object'
  or exists(select 1 from jsonb_object_keys(x) k where k not in ('detalle_id','cantidad_entregada'))
  or jsonb_typeof(x->'cantidad_entregada') is distinct from 'number' then
   raise exception 'Detalle inválido' using errcode='PT422'; end if;
  ident:=(x->>'detalle_id')::uuid; q:=(x->>'cantidad_entregada')::numeric;
  if ident is null or q is null or q::text in ('NaN','Infinity','-Infinity') or q<0
  or q>9999999999.99 or q<>round(q,2) then raise exception 'Cantidad inválida' using errcode='PT422'; end if;
  originales:=originales||jsonb_build_array(jsonb_build_object('detalle_id',ident,'cantidad_entregada',trim_scale(q)));
 end loop;
 for x in select value from jsonb_array_elements(p_agregados) loop
  if jsonb_typeof(x) is distinct from 'object'
  or exists(select 1 from jsonb_object_keys(x) k where k not in ('producto_id','cantidad_entregada','tipo_precio'))
  or jsonb_typeof(x->'cantidad_entregada') is distinct from 'number' then
   raise exception 'Agregado inválido' using errcode='PT422'; end if;
  ident:=(x->>'producto_id')::uuid; q:=(x->>'cantidad_entregada')::numeric; lista:=x->>'tipo_precio';
  if ident is null or q is null or q::text in ('NaN','Infinity','-Infinity') or q<=0
  or q>9999999999.99 or q<>round(q,2) or lista is null or lista not in ('normal','promo','interior') then
   raise exception 'Agregado inválido' using errcode='PT422'; end if;
  agregados:=agregados||jsonb_build_array(jsonb_build_object('producto_id',ident,'cantidad_entregada',trim_scale(q),'tipo_precio',lista));
 end loop;
 if exists(select 1 from jsonb_array_elements(originales) x group by x->>'detalle_id' having count(*)>1)
 or exists(select 1 from jsonb_array_elements(agregados) x group by x->>'producto_id' having count(*)>1) then
  raise exception 'Detalle duplicado' using errcode='PT422'; end if;
 select jsonb_agg(x order by x->>'detalle_id') into originales from jsonb_array_elements(originales) x;
 select coalesce(jsonb_agg(x order by x->>'producto_id'),'[]') into agregados from jsonb_array_elements(agregados) x;
 return jsonb_build_object('version',1,'pedido_id',p_pedido_id,'estado',p_estado,
  'motivo_no_entrega',nullif(btrim(p_motivo_no_entrega),''),'originales',originales,'agregados',agregados,
  'tipo_pago',p_tipo_pago,'importe_pago',trim_scale(p_importe_pago),'medio_pago',nullif(btrim(p_medio_pago),''),
  'fecha_fisica_epoch',trim_scale(extract(epoch from p_fecha_fisica)));
exception when invalid_text_representation or numeric_value_out_of_range then
 raise exception 'Solicitud inválida' using errcode='PT422';
end;$$;
revoke all on function public.finalizacion_normalizar_v1(uuid,text,text,jsonb,jsonb,text,numeric,text,timestamptz)
 from public,anon,authenticated,service_role;

create function public.finalizar_gestion_pedido_v2(
 p_solicitud_id uuid,p_pedido_id uuid,p_fecha_fisica timestamptz,p_estado text,
 p_originales jsonb,p_agregados jsonb,p_tipo_pago text,
 p_motivo_no_entrega text default null,p_importe_pago numeric default null,p_medio_pago text default null
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions,pg_temp as $$
#variable_conflict use_column
declare solicitud jsonb; huella text; anterior public.finalizacion_pedido_solicitudes;
 pedido public.pedidos; d public.pedido_detalles; producto public.productos;
 x jsonb; base numeric; q numeric; precio numeric; porcentaje numeric; total_unidades numeric:=0;
 completa boolean:=true; resultado text; saldo numeric; ubicacion uuid; evento uuid; movimientos integer;
 items jsonb; respuesta jsonb; originales_esperados integer;
begin
 if public.es_administrador() is not true then raise exception 'Solo administración' using errcode='PT403'; end if;
 if p_solicitud_id is null or p_fecha_fisica is null or not isfinite(p_fecha_fisica)
 or p_fecha_fisica>clock_timestamp() then raise exception 'Fecha o solicitud inválida' using errcode='PT422'; end if;
 solicitud:=public.finalizacion_normalizar_v1(p_pedido_id,p_estado,p_motivo_no_entrega,p_originales,p_agregados,
  p_tipo_pago,p_importe_pago,p_medio_pago,p_fecha_fisica);
 huella:=encode(sha256(convert_to(solicitud::text,'UTF8')),'hex');
 perform pg_advisory_xact_lock(829001);
 select * into anterior from public.finalizacion_pedido_solicitudes where solicitud_id=p_solicitud_id for update;
 if found then
  if anterior.actor_id is distinct from auth.uid() or anterior.request_hash is distinct from huella
  or anterior.solicitud_normalizada is distinct from solicitud then
   raise exception 'solicitud_incompatible' using errcode='PT409'; end if;
  return anterior.resultado_normalizado;
 end if;
 select * into pedido from public.pedidos where id=p_pedido_id for update;
 if not found then raise exception 'Pedido inexistente' using errcode='PT404'; end if;
 if pedido.tipo_operacion is distinct from 'pedido' then raise exception 'Solo preventa en V2' using errcode='PT422'; end if;
 if pedido.resultado_entrega is distinct from 'pendiente' or pedido.estado='anulado' then
  raise exception 'operacion_ya_finalizada' using errcode='PT409'; end if;
 if pedido.facturado is not true then raise exception 'Pedido sin facturar' using errcode='PT422'; end if;
 perform 1 from public.pedido_detalles where pedido_id=p_pedido_id order by id for update;
 select count(*) into originales_esperados from public.pedido_detalles where pedido_id=p_pedido_id and not agregado_en_entrega;
 if originales_esperados<>jsonb_array_length(solicitud->'originales') then
  raise exception 'Cobertura incompleta de detalles' using errcode='PT422'; end if;
 -- Validar todas las líneas antes de mutar. La base cero permanece cero.
 for x in select value from jsonb_array_elements(solicitud->'originales') loop
  select * into d from public.pedido_detalles where id=(x->>'detalle_id')::uuid and pedido_id=p_pedido_id and not agregado_en_entrega;
  if not found then raise exception 'Detalle ajeno o inexistente' using errcode='PT422'; end if;
  base:=coalesce(d.cantidad_facturada,d.cantidad); q:=(x->>'cantidad_entregada')::numeric;
  if base is null or base::text in ('NaN','Infinity','-Infinity') or base<0 or base<>round(base,2) or q>base then
   raise exception 'Cantidad superior a base o base inválida' using errcode='PT422'; end if;
  total_unidades:=total_unidades+q; completa:=completa and q=base;
 end loop;
 if exists(select 1 from jsonb_array_elements(solicitud->'agregados') a join public.pedido_detalles d
  on d.producto_id=(a->>'producto_id')::uuid where d.pedido_id=p_pedido_id) then
  raise exception 'Agregado duplica producto original' using errcode='PT422'; end if;
 for x in select value from jsonb_array_elements(solicitud->'agregados') loop
  total_unidades:=total_unidades+(x->>'cantidad_entregada')::numeric;
 end loop;
 resultado:=case when total_unidades=0 then 'no_entregado' when completa then 'entregado' else 'parcial' end;
 if resultado<>'entregado' and solicitud->>'motivo_no_entrega' is null then
  raise exception 'Falta motivo de no entrega' using errcode='PT422'; end if;
 if resultado='no_entregado' and p_tipo_pago<>'sin_pago' then raise exception 'No corresponde cobrar sin entrega' using errcode='PT422'; end if;
 select id into ubicacion from public.ubicaciones_stock where codigo='deposito_alberdi' and activo for share;
 if ubicacion is null then raise exception 'Depósito no disponible' using errcode='PT410'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('producto_id',producto_id,'cantidad_delta',-cantidad,'tipo','entrega') order by producto_id),'[]')
 into items from (
  select producto_id,sum(cantidad) cantidad from (
   select d.producto_id,(x->>'cantidad_entregada')::numeric cantidad from jsonb_array_elements(solicitud->'originales') x
    join public.pedido_detalles d on d.id=(x->>'detalle_id')::uuid
   union all select (x->>'producto_id')::uuid,(x->>'cantidad_entregada')::numeric from jsonb_array_elements(solicitud->'agregados') x
  ) lineas group by producto_id having sum(cantidad)>0
 ) deltas;
 evento:=public.stock_registrar_evento(ubicacion,'finalizacion_pedido',p_pedido_id,p_solicitud_id,
  jsonb_build_object('items',items,'motivo','Finalización de preventa'),p_fecha_fisica);
 -- Locks de productos en orden UUID; precios/comisiones siempre desde fuentes del servidor.
 perform 1 from public.productos where id in (
  select producto_id from public.pedido_detalles where pedido_id=p_pedido_id
  union select (x->>'producto_id')::uuid from jsonb_array_elements(solicitud->'agregados') x
 ) order by id for share;
 movimientos:=public.stock_aplicar_deltas(ubicacion,evento,items);
 for x in select value from jsonb_array_elements(solicitud->'originales') loop
  select * into d from public.pedido_detalles where id=(x->>'detalle_id')::uuid;
  select * into producto from public.productos where id=d.producto_id;
  q:=(x->>'cantidad_entregada')::numeric; base:=coalesce(d.cantidad_facturada,d.cantidad);
  porcentaje:=case when pedido.origen='catalogo' then coalesce(d.porcentaje_comision,0)
   else coalesce(case d.tipo_precio when 'promo' then producto.comision_promo when 'interior' then producto.comision_interior else producto.comision_normal end,0) end;
  update public.pedido_detalles set cantidad_entregada=q,cantidad_no_entregada=base-q,
   porcentaje_comision=porcentaje,importe_comision=round(q*precio_unitario*porcentaje/100,2) where id=d.id;
 end loop;
 for x in select value from jsonb_array_elements(solicitud->'agregados') loop
  select * into producto from public.productos where id=(x->>'producto_id')::uuid;
  if not found or producto.activo is not true then raise exception 'Producto no disponible' using errcode='PT422'; end if;
  q:=(x->>'cantidad_entregada')::numeric;
  precio:=case x->>'tipo_precio' when 'promo' then producto.precio_promo when 'interior' then producto.precio_interior else producto.precio_normal end;
  if precio is null or precio<=0 or precio::text in ('NaN','Infinity','-Infinity') then raise exception 'Precio inválido' using errcode='PT422'; end if;
  porcentaje:=case when pedido.origen='catalogo' and pedido.catalogo_preventista_id is null then 0
   else coalesce(case x->>'tipo_precio' when 'promo' then producto.comision_promo when 'interior' then producto.comision_interior else producto.comision_normal end,0) end;
  insert into public.pedido_detalles(pedido_id,producto_id,cantidad,cantidad_facturada,cantidad_entregada,cantidad_no_entregada,
   precio_unitario,subtotal,tipo_precio,costo_unitario,porcentaje_comision,importe_comision,agregado_en_entrega)
  values(p_pedido_id,producto.id,0,0,q,0,precio,0,x->>'tipo_precio',producto.costo,porcentaje,round(q*precio*porcentaje/100,2),true);
 end loop;
 update public.pedidos set estado=p_estado,resultado_entrega=resultado,fecha_finalizacion=now(),
  motivo_no_entrega=case when resultado='entregado' then null else solicitud->>'motivo_no_entrega' end where id=p_pedido_id;
 -- Mismo orden y reglas financieras que el wrapper legacy: crédito antes del cobro.
 perform public.aplicar_credito_cliente(pedido.cliente_id);
 if p_tipo_pago='parcial' then
  perform 1 from public.registrar_pago_cliente(pedido.cliente_id,p_importe_pago,btrim(p_medio_pago),'Pago parcial al entregar el pedido');
 elsif p_tipo_pago='completo' then
  select saldo_pendiente into saldo from public.saldos_pendientes_pedidos where pedido_id=p_pedido_id;
  if p_importe_pago is not null and p_importe_pago is distinct from saldo then
   raise exception 'Cambió el saldo a cobrar' using errcode='PT422'; end if;
  if saldo>0 then perform 1 from public.registrar_pago_cliente(pedido.cliente_id,saldo,btrim(p_medio_pago),'Pago completo al entregar el pedido'); end if;
 end if;
 select saldo_pendiente into saldo from public.saldos_pendientes_pedidos where pedido_id=p_pedido_id;
 respuesta:=jsonb_build_object('version',1,'solicitud_id',p_solicitud_id,'pedido_id',p_pedido_id,
  'resultado_entrega',resultado,'stock_evento_id',evento,'movimientos_stock',movimientos,'saldo_pendiente',saldo);
 insert into public.finalizacion_pedido_solicitudes(solicitud_id,pedido_id,actor_id,request_hash,solicitud_normalizada,resultado_normalizado,stock_evento_id)
 values(p_solicitud_id,p_pedido_id,auth.uid(),huella,solicitud,respuesta,evento);
 return respuesta;
end;$$;
revoke all on function public.finalizar_gestion_pedido_v2(uuid,uuid,timestamptz,text,jsonb,jsonb,text,text,numeric,text)
 from public,anon,authenticated,service_role;
grant execute on function public.finalizar_gestion_pedido_v2(uuid,uuid,timestamptz,text,jsonb,jsonb,text,text,numeric,text) to authenticated;

create function public.consultar_finalizacion_solicitud(p_solicitud_id uuid) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare respuesta jsonb;
begin
 if public.es_administrador() is not true then raise exception 'Solo administración' using errcode='PT403'; end if;
 select resultado_normalizado into respuesta from public.finalizacion_pedido_solicitudes
 where solicitud_id=p_solicitud_id and actor_id=auth.uid();
 return case when found then jsonb_build_object('estado','confirmada','resultado',respuesta)
  else jsonb_build_object('estado','inexistente') end;
end;$$;
revoke all on function public.consultar_finalizacion_solicitud(uuid) from public,anon,authenticated,service_role;
grant execute on function public.consultar_finalizacion_solicitud(uuid) to authenticated;

alter function public.finalizar_gestion_pedido(uuid,text,text,text,jsonb,text,numeric,text) rename to finalizar_gestion_pedido_legacy_interno;
revoke all on function public.finalizar_gestion_pedido_legacy_interno(uuid,text,text,text,jsonb,text,numeric,text),
 public.finalizar_gestion_pedido_sin_nc(uuid,text,text,text,jsonb,text,numeric,text) from public,anon,authenticated,service_role;
create function public.finalizar_gestion_pedido(p_pedido_id uuid,p_estado text,p_resultado_entrega text,p_motivo_no_entrega text,
 p_detalles jsonb,p_tipo_pago text,p_importe_pago numeric default null,p_medio_pago text default null)
returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 if public.es_administrador() is not true then raise exception 'Solo administración' using errcode='PT403'; end if;
 perform pg_advisory_xact_lock(829001);
 perform 1 from public.stock_configuracion order by ubicacion_id for share;
 if exists(select 1 from public.stock_configuracion where automatizacion_activa) then
  raise exception 'actualizacion_requerida' using errcode='PT409'; end if;
 perform public.finalizar_gestion_pedido_legacy_interno(p_pedido_id,p_estado,p_resultado_entrega,p_motivo_no_entrega,p_detalles,p_tipo_pago,p_importe_pago,p_medio_pago);
end;$$;
revoke all on function public.finalizar_gestion_pedido(uuid,text,text,text,jsonb,text,numeric,text) from public,anon,authenticated,service_role;
grant execute on function public.finalizar_gestion_pedido(uuid,text,text,text,jsonb,text,numeric,text) to authenticated;

-- Facturación auditada: únicamente estos campos requieren DML directo Flutter.
-- Retirar también grants por columna preexistentes (REVOKE de tabla no los quita).
do $$ declare t text; columnas text; begin
 foreach t in array array['pedidos','pedido_detalles','detalles_administracion'] loop
  execute format('revoke insert,update,delete,truncate,references,trigger on public.%I from public,anon,authenticated,service_role',t);
  select string_agg(quote_ident(attname),',') into columnas from pg_attribute
   where attrelid=format('public.%I',t)::regclass and attnum>0 and not attisdropped;
  execute format('revoke insert(%s),update(%s),references(%s) on public.%I from public,anon,authenticated,service_role',columnas,columnas,columnas,t);
 end loop;
end $$;
grant update(facturado,fecha_facturacion,numero_comprobante) on public.pedidos to authenticated;
grant update(cantidad_facturada) on public.pedido_detalles to authenticated;
grant insert(pedido_id,producto_id,cantidad,precio_unitario,subtotal,tipo_precio,cantidad_facturada) on public.pedido_detalles to authenticated;

-- INVOKER: current_user distingue DML del cliente de RPC SECURITY DEFINER.
-- No GUC controlable por el cliente, ni bypass por profundidad de triggers.
create function public.proteger_facturacion_finalizada() returns trigger
language plpgsql set search_path=pg_catalog,public,pg_temp as $$
declare padre uuid; resultado text;
begin
 if current_user in ('postgres','supabase_admin') then return new; end if;
 if public.es_administrador() is not true then raise exception 'Solo administración' using errcode='PT403'; end if;
 if tg_table_name='pedidos' then
  if old.resultado_entrega is distinct from 'pendiente' then
   raise exception 'operacion_ya_finalizada' using errcode='PT409'; end if;
 else
  padre:=new.pedido_id;
  select resultado_entrega into resultado from public.pedidos where id=padre for update;
  if not found or resultado is distinct from 'pendiente' then
   raise exception 'operacion_ya_finalizada' using errcode='PT409'; end if;
 end if;
 return new;
end;$$;
revoke all on function public.proteger_facturacion_finalizada() from public,anon,authenticated,service_role;
create trigger z_proteger_facturacion_finalizada before update on public.pedidos
 for each row execute function public.proteger_facturacion_finalizada();
create trigger z_proteger_detalles_finalizados before insert or update on public.pedido_detalles
 for each row execute function public.proteger_facturacion_finalizada();
-- BEFORE STATEMENT precede a los locks de fila del UPDATE directo. Evita
-- inversión detalle -> pedido frente a V2 (pedido -> detalles).
create function public.serializar_facturacion_directa() returns trigger
language plpgsql set search_path=pg_catalog,public,pg_temp as $$
begin
 if current_user not in ('postgres','supabase_admin') then
  perform pg_advisory_xact_lock(829001);
 end if;
 return null;
end;$$;
revoke all on function public.serializar_facturacion_directa() from public,anon,authenticated,service_role;
create trigger a_serializar_facturacion_directa before update on public.pedidos
 for each statement execute function public.serializar_facturacion_directa();
create trigger a_serializar_detalles_directos before insert or update on public.pedido_detalles
 for each statement execute function public.serializar_facturacion_directa();
commit;
