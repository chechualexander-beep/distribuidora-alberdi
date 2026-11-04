-- Candidato Etapa 117. Aplica sólo sobre el contrato de Stock V2 instalado.
-- Conserva las firmas, permisos y cuerpos comerciales; falla si un ancla difiere.
begin;
select pg_advisory_xact_lock(829001);

do $$
begin
 if not exists (select 1 from public.stock_transicion where singleton and paso_instalacion=3) then
  raise exception 'Stock V2 incompleto';
 end if;
end;
$$;

create function public.stock_exigir_venta_directa_v2() returns void
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 perform public.stock_exigir_admin();
 perform public.stock_exigir_operativo();
 if not exists (
  select 1 from public.stock_transicion t
  join public.stock_regimenes r on r.id=t.regimen_id
  join public.stock_configuracion c on c.automatizacion_activa
  where t.singleton and t.paso_instalacion=3 and r.protocolo=2
    and r.automatizacion_activa and r.cerrado_at is null
    and c.integracion_version=1 and c.fecha_corte=r.fecha_corte
 ) then
  raise exception 'venta_directa_requiere_stock_v2_on' using errcode='PT409';
 end if;
end;
$$;
revoke all on function public.stock_exigir_venta_directa_v2()
 from public,anon,authenticated,service_role;

do $migration$
declare
 change record;
 original text;
 updated text;
begin
 for change in select * from (values
  ('public.crear_pedido_interno(uuid,uuid,text,text,text,date,jsonb)'::regprocedure,
   $old$if p_tipo_operacion='venta_directa' and not exists(select 1 from public.solicitudes_pedido_interno where id=p_id) then raise exception 'venta_directa_no_disponible_testing' using errcode='PT409';end if;$old$,
   $new$if p_tipo_operacion='venta_directa' and not exists(select 1 from public.solicitudes_pedido_interno where id=p_id) then perform public.stock_exigir_venta_directa_v2();end if;$new$),
  ('public.actualizar_pedido_activo(uuid,numeric,text,text,text,date,jsonb)'::regprocedure,
   $old$if p_tipo_operacion='venta_directa' or exists(select 1 from public.pedidos where id=p_pedido_id and tipo_operacion='venta_directa') then raise exception 'venta_directa_no_disponible_testing' using errcode='PT409';end if;$old$,
   $new$if p_tipo_operacion='venta_directa' or exists(select 1 from public.pedidos where id=p_pedido_id and tipo_operacion='venta_directa') then
 perform public.stock_exigir_venta_directa_v2();
 if p_tipo_operacion is distinct from 'venta_directa' or not exists(select 1 from public.pedidos where id=p_pedido_id and tipo_operacion='venta_directa') then raise exception 'cambio_tipo_operacion_no_permitido' using errcode='PT409';end if;
 if exists(select 1 from public.stock_preparaciones where pedido_id=p_pedido_id and not revision) then raise exception 'venta_directa_preparada' using errcode='PT409';end if;
end if;$new$),
  ('public.preparar_finalizacion_contexto(uuid,uuid)'::regprocedure,
   $old$and facturado and tipo_operacion='pedido';$old$,
   $new$and ((facturado and tipo_operacion='pedido') or tipo_operacion='venta_directa');$new$),
  ('public.preparar_finalizacion_contexto(uuid,uuid)'::regprocedure,
   $old$  insert into public.stock_preparaciones(solicitud_id,pedido_id,actor_id,regimen_id,protocolo,fecha_fisica)$old$,
   $new$  if exists(select 1 from public.pedidos where id=p_pedido_id and tipo_operacion='venta_directa') then
   perform public.stock_exigir_venta_directa_v2();
   if exists(select 1 from public.stock_preparaciones where pedido_id=p_pedido_id and regimen_id=t.regimen_id and not revision) then
    raise exception 'venta_directa_preparada' using errcode='PT409';end if;
  end if;
  insert into public.stock_preparaciones(solicitud_id,pedido_id,actor_id,regimen_id,protocolo,fecha_fisica)$new$),
  ('public.stock_base_finalizar_v2(uuid,uuid,timestamptz,text,jsonb,jsonb,text,text,numeric,text)'::regprocedure,
   $old$if pedido.tipo_operacion is distinct from 'pedido' then raise exception 'Solo preventa en V2' using errcode='PT422'; end if;$old$,
   $new$if pedido.tipo_operacion='venta_directa' then
  perform public.stock_exigir_venta_directa_v2();
  if pedido.estado='cancelado' then
   raise exception 'operacion_ya_finalizada' using errcode='PT409';
  end if;
  if not exists(select 1 from public.stock_transicion t
   join public.stock_regimenes r on r.id=t.regimen_id
   where t.singleton and p_fecha_fisica>=r.fecha_corte) then
   raise exception 'venta_directa_anterior_al_corte' using errcode='PT409';
  end if;
 elsif pedido.tipo_operacion is distinct from 'pedido' then
  raise exception 'Tipo de operación no disponible en V2' using errcode='PT422';
 end if;$new$),
  ('public.stock_base_finalizar_v2(uuid,uuid,timestamptz,text,jsonb,jsonb,text,text,numeric,text)'::regprocedure,
   $old$if pedido.facturado is not true then$old$,
   $new$if pedido.tipo_operacion='pedido' and pedido.facturado is not true then$new$),
  ('public.stock_base_finalizar_v2(uuid,uuid,timestamptz,text,jsonb,jsonb,text,text,numeric,text)'::regprocedure,
   $old$if exists(select 1 from jsonb_array_elements(solicitud->'agregados') a join public.pedido_detalles d$old$,
   $new$if pedido.tipo_operacion='pedido' and exists(select 1 from jsonb_array_elements(solicitud->'agregados') a join public.pedido_detalles d$new$),
  ('public.stock_base_finalizar_v2(uuid,uuid,timestamptz,text,jsonb,jsonb,text,text,numeric,text)'::regprocedure,
   $old$'tipo','entrega'$old$,
   $new$'tipo',case when pedido.tipo_operacion='venta_directa' then 'venta_directa' else 'entrega' end$new$),
  ('public.stock_base_finalizar_v2(uuid,uuid,timestamptz,text,jsonb,jsonb,text,text,numeric,text)'::regprocedure,
   $old$'motivo','Finalización de preventa'$old$,
   $new$'motivo',case when pedido.tipo_operacion='venta_directa' then 'Finalización de venta directa' else 'Finalización de preventa' end$new$)
 ) as edits(signature, before_text, after_text) loop
  original := pg_get_functiondef(change.signature);
  updated := replace(original, change.before_text, change.after_text);
  if length(original) - length(replace(original, change.before_text, '')) <> length(change.before_text) then
   raise exception 'Ancla incompatible en %', change.signature;
  end if;
  execute updated;
 end loop;
end;
$migration$;

commit;
