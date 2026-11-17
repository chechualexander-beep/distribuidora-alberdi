-- Reparto y cobros sin señal (etapa 3 del stock; D2 del modo sin conexión).
-- Decidido el 16/11/2026: los hace el administrador y vale la HORA REAL del teléfono (hasta 72 h
-- atrás, nunca en el futuro). Una entrega del sábado cuenta para la liquidación de esa semana
-- aunque se envíe el lunes. Ver docs/STOCK.md.

-- 1. La fecha de finalización (comisiones) y la del cobro hecho al entregar son las del momento
--    real de la entrega (p_fecha_fisica), no la del envío.
CREATE OR REPLACE FUNCTION public.stock_base_finalizar_v2(p_solicitud_id uuid, p_pedido_id uuid, p_fecha_fisica timestamp with time zone, p_estado text, p_originales jsonb, p_agregados jsonb, p_tipo_pago text, p_motivo_no_entrega text DEFAULT NULL::text, p_importe_pago numeric DEFAULT NULL::numeric, p_medio_pago text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
AS $function$
#variable_conflict use_column
declare solicitud jsonb; huella text; anterior public.finalizacion_pedido_solicitudes;
 pedido public.pedidos; d public.pedido_detalles; producto public.productos;
 x jsonb; base numeric; q numeric; precio numeric; porcentaje numeric; total_unidades numeric:=0;
 completa boolean:=true; resultado text; saldo numeric; ubicacion uuid; evento uuid; movimientos integer;
 items jsonb; respuesta jsonb; originales_esperados integer; cobro_pago uuid;
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
 if pedido.tipo_operacion='venta_directa' then
  perform public.stock_exigir_venta_directa_v2();
  if pedido.estado='cancelado' then
   raise exception 'operacion_ya_finalizada' using errcode='PT409';
  end if;
  if not exists(select 1 from public.stock_transicion t
   join public.stock_regimenes r on r.id=t.regimen_id
   where t.singleton and (not r.automatizacion_activa or p_fecha_fisica>=r.fecha_corte)) then
   raise exception 'venta_directa_anterior_al_corte' using errcode='PT409';
  end if;
 elsif pedido.tipo_operacion is distinct from 'pedido' then
  raise exception 'Tipo de operación no disponible en V2' using errcode='PT422';
 end if;
 if pedido.resultado_entrega is distinct from 'pendiente' or pedido.estado='anulado' then
  raise exception 'operacion_ya_finalizada' using errcode='PT409'; end if;
 if pedido.tipo_operacion='pedido' and pedido.facturado is not true then raise exception 'Pedido sin facturar' using errcode='PT422'; end if;
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
 if pedido.tipo_operacion='pedido' and exists(select 1 from jsonb_array_elements(solicitud->'agregados') a join public.pedido_detalles d
  on d.producto_id=(a->>'producto_id')::uuid where d.pedido_id=p_pedido_id) then
  raise exception 'Agregado duplica producto original' using errcode='PT422'; end if;
 for x in select value from jsonb_array_elements(solicitud->'agregados') loop
  total_unidades:=total_unidades+(x->>'cantidad_entregada')::numeric;
 end loop;
 resultado:=case when total_unidades=0 then 'no_entregado' when completa then 'entregado' else 'parcial' end;
 if resultado<>'entregado' and solicitud->>'motivo_no_entrega' is null then
  raise exception 'Falta motivo de no entrega' using errcode='PT422'; end if;
 if resultado='no_entregado' and p_tipo_pago<>'sin_pago' then raise exception 'No corresponde cobrar sin entrega' using errcode='PT422'; end if;
 select id into ubicacion from public.ubicaciones_stock where codigo='vehiculo' and activo for share;
 if ubicacion is null then raise exception 'Vehículo no disponible' using errcode='PT410'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('producto_id',producto_id,'cantidad_delta',-cantidad,'tipo',case when pedido.tipo_operacion='venta_directa' then 'venta_directa' else 'entrega' end) order by producto_id),'[]')
 into items from (
  select producto_id,sum(cantidad) cantidad from (
   select d.producto_id,(x->>'cantidad_entregada')::numeric cantidad from jsonb_array_elements(solicitud->'originales') x
    join public.pedido_detalles d on d.id=(x->>'detalle_id')::uuid
   union all select (x->>'producto_id')::uuid,(x->>'cantidad_entregada')::numeric from jsonb_array_elements(solicitud->'agregados') x
  ) lineas group by producto_id having sum(cantidad)>0
 ) deltas;
 evento:=public.stock_registrar_evento(ubicacion,'finalizacion_pedido',p_pedido_id,p_solicitud_id,
  jsonb_build_object('items',items,'motivo',case when pedido.tipo_operacion='venta_directa' then 'Finalización de venta directa' else 'Finalización de preventa' end),p_fecha_fisica);
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
 update public.pedidos set estado=p_estado,resultado_entrega=resultado,fecha_finalizacion=p_fecha_fisica,
  motivo_no_entrega=case when resultado='entregado' then null else solicitud->>'motivo_no_entrega' end where id=p_pedido_id;
 -- Mismo orden y reglas financieras que el wrapper legacy: crédito antes del cobro.
 perform public.aplicar_credito_cliente(pedido.cliente_id);
 if p_tipo_pago='parcial' then
  select r.cobro_id into cobro_pago from public.registrar_pago_cliente(pedido.cliente_id,p_importe_pago,btrim(p_medio_pago),'Pago parcial al entregar el pedido') r limit 1;
 elsif p_tipo_pago='completo' then
  select saldo_pendiente into saldo from public.saldos_pendientes_pedidos where pedido_id=p_pedido_id;
  if p_importe_pago is not null and p_importe_pago is distinct from saldo then
   raise exception 'Cambió el saldo a cobrar' using errcode='PT422'; end if;
  if saldo>0 then select r.cobro_id into cobro_pago from public.registrar_pago_cliente(pedido.cliente_id,saldo,btrim(p_medio_pago),'Pago completo al entregar el pedido') r limit 1; end if;
 end if;
 -- El cobro hecho al entregar queda con la hora real de la entrega (también sin señal).
 if cobro_pago is not null then
  update public.cobros_cliente set fecha_pago=p_fecha_fisica where id=cobro_pago;
  update public.pedido_pagos set fecha_pago=p_fecha_fisica where cobro_id=cobro_pago;
 end if;
 select saldo_pendiente into saldo from public.saldos_pendientes_pedidos where pedido_id=p_pedido_id;
 respuesta:=jsonb_build_object('version',1,'solicitud_id',p_solicitud_id,'pedido_id',p_pedido_id,
  'resultado_entrega',resultado,'stock_evento_id',evento,'movimientos_stock',movimientos,'saldo_pendiente',saldo);
 insert into public.finalizacion_pedido_solicitudes(solicitud_id,pedido_id,actor_id,request_hash,solicitud_normalizada,resultado_normalizado,stock_evento_id)
 values(p_solicitud_id,p_pedido_id,auth.uid(),huella,solicitud,respuesta,evento);
 return respuesta;
end;$function$;


-- 2. Entrega hecha sin señal: prepara y finaliza en un solo paso con la hora del teléfono.
--    Reenviar la misma solicitud devuelve la respuesta original (usa la fecha ya guardada).
create function public.finalizar_gestion_sin_conexion(p_solicitud_id uuid, p_pedido_id uuid,
 p_fecha_fisica timestamptz, p_estado text, p_originales jsonb, p_agregados jsonb, p_tipo_pago text,
 p_origen text, p_motivo_no_entrega text default null, p_importe_pago numeric default null,
 p_medio_pago text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare t public.stock_transicion; r public.stock_preparaciones; fecha timestamptz;
begin
 perform public.stock_exigir_admin();
 perform pg_advisory_xact_lock(829001);
 if p_origen is distinct from 'sin_senal' or p_solicitud_id is null or p_pedido_id is null then
  raise exception 'Solicitud inválida' using errcode = 'PT422'; end if;
 select * into r from public.stock_preparaciones where solicitud_id = p_solicitud_id;
 if found then
  if r.actor_id is distinct from auth.uid() or r.pedido_id <> p_pedido_id then
   raise exception 'solicitud_incompatible' using errcode = 'PT409'; end if;
  return public.stock_base_finalizar_v2(p_solicitud_id, p_pedido_id, r.fecha_fisica, p_estado, p_originales,
   p_agregados, p_tipo_pago, p_motivo_no_entrega, p_importe_pago, p_medio_pago);
 end if;
 if exists (select 1 from public.finalizacion_pedido_solicitudes where solicitud_id = p_solicitud_id) then
  raise exception 'solicitud_incompatible' using errcode = 'PT409'; end if;
 perform public.stock_exigir_operativo();
 fecha := public.stock_validar_fecha(p_fecha_fisica);
 select * into strict t from public.stock_transicion where singleton;
 perform 1 from public.pedidos where id = p_pedido_id and resultado_entrega = 'pendiente' and estado <> 'anulado'
  and ((facturado and tipo_operacion = 'pedido') or tipo_operacion = 'venta_directa');
 if not found then raise exception 'Pedido no disponible' using errcode = 'PT409'; end if;
 if exists (select 1 from public.pedidos where id = p_pedido_id and tipo_operacion = 'venta_directa') then
  perform public.stock_exigir_venta_directa_v2();
  if exists (select 1 from public.stock_preparaciones where pedido_id = p_pedido_id
    and regimen_id = t.regimen_id and not revision) then
   raise exception 'venta_directa_preparada' using errcode = 'PT409'; end if;
 end if;
 insert into public.stock_preparaciones(solicitud_id, pedido_id, actor_id, regimen_id, protocolo, fecha_fisica)
 values (p_solicitud_id, p_pedido_id, auth.uid(), t.regimen_id, 2, fecha);
 return public.stock_base_finalizar_v2(p_solicitud_id, p_pedido_id, fecha, p_estado, p_originales, p_agregados,
  p_tipo_pago, p_motivo_no_entrega, p_importe_pago, p_medio_pago);
end $$;

-- 3. Cobro de saldo hecho sin señal: el mismo cobro contextual, con la hora real.
create function public.registrar_cobro_sin_conexion(p_id uuid, p_cliente_id uuid, p_importe numeric,
 p_medio_pago text, p_fecha timestamptz, p_observacion text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare res jsonb; fecha timestamptz; nuevo boolean;
begin
 perform public.stock_exigir_admin();
 perform pg_advisory_xact_lock(829001);
 nuevo := not exists (select 1 from public.solicitudes_cobro_cliente where solicitud_id = p_id);
 if nuevo then fecha := public.stock_validar_fecha(p_fecha); end if;
 res := public.registrar_pago_cliente_contextual(p_id, p_cliente_id, p_importe, p_medio_pago, p_observacion);
 if nuevo then
  update public.cobros_cliente set fecha_pago = fecha where id = (res->>'cobro_id')::uuid;
  update public.pedido_pagos set fecha_pago = fecha where cobro_id = (res->>'cobro_id')::uuid;
  res := jsonb_set(res, '{fecha_pago}', to_jsonb(fecha));
  update public.solicitudes_cobro_cliente set resultado = res where solicitud_id = p_id;
 end if;
 return res;
end $$;

revoke all on function public.finalizar_gestion_sin_conexion(uuid, uuid, timestamptz, text, jsonb, jsonb, text, text, text, numeric, text),
 public.registrar_cobro_sin_conexion(uuid, uuid, numeric, text, timestamptz, text) from public, anon;
grant execute on function public.finalizar_gestion_sin_conexion(uuid, uuid, timestamptz, text, jsonb, jsonb, text, text, text, numeric, text),
 public.registrar_cobro_sin_conexion(uuid, uuid, numeric, text, timestamptz, text) to authenticated;
