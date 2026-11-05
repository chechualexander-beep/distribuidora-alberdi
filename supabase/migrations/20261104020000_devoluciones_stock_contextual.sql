begin;
select pg_advisory_xact_lock(829001);

alter table public.recepciones_nota_credito
 add column cantidad_apta numeric(12,2),
 add column cantidad_no_apta numeric(12,2),
 add constraint recepcion_cantidades_contextuales check (
  (cantidad_apta is null and cantidad_no_apta is null)
  or (cantidad_apta is not null and cantidad_no_apta is not null
      and cantidad_apta >= 0 and cantidad_no_apta >= 0
      and cantidad_apta + cantidad_no_apta > 0
      and apta_venta = (cantidad_no_apta = 0))
 );

create table public.solicitudes_devolucion_contextual (
 id uuid primary key,
 operacion text not null check (operacion in ('emision','recepcion')),
 actor_id uuid not null references auth.users(id),
 regimen_id uuid not null references public.stock_regimenes(id),
 nota_id uuid not null references public.notas_credito(id),
 recepcion_id uuid unique references public.recepciones_nota_credito(id),
 evento_id uuid unique references public.stock_eventos(id),
 payload jsonb not null,
 resultado jsonb not null,
 fecha timestamptz not null,
 check ((operacion = 'recepcion') = (recepcion_id is not null)),
 check ((operacion = 'recepcion') = (evento_id is not null))
);
alter table public.solicitudes_devolucion_contextual enable row level security;
revoke all on public.solicitudes_devolucion_contextual from public,anon,authenticated,service_role;

create function public.stock_devolucion_replay(p_id uuid,p_operacion text,p_payload jsonb)
returns jsonb language plpgsql set search_path=pg_catalog,public,pg_temp as $$
declare anterior public.solicitudes_devolucion_contextual;
begin
 perform public.stock_exigir_admin();
 if auth.uid() is null or p_id is null then
  raise exception 'solicitud_devolucion_invalida' using errcode='PT422';
 end if;
 -- Same first lock as financial writes, legacy receipts and regime transitions.
 perform pg_advisory_xact_lock(829001);
 select * into anterior from public.solicitudes_devolucion_contextual where id=p_id;
 if found then
  if anterior.actor_id is distinct from auth.uid() or anterior.operacion<>p_operacion
    or anterior.payload is distinct from p_payload then
   raise exception 'solicitud_devolucion_incompatible' using errcode='PT409';
  end if;
  return anterior.resultado;
 end if;
 return null;
end;
$$;

create function public.stock_devolucion_regimen()
returns uuid language plpgsql set search_path=pg_catalog,public,pg_temp as $$
declare regimen uuid;
begin
 perform public.stock_exigir_operativo();
 select r.id into strict regimen
 from public.stock_transicion t
 join public.stock_regimenes r on r.id=t.regimen_id
 join public.stock_configuracion c on c.automatizacion_activa=r.automatizacion_activa
 join public.ubicaciones_stock u on u.id=c.ubicacion_id and u.activo
 where t.singleton and t.paso_instalacion=3 and r.protocolo=2 and r.cerrado_at is null
   and c.fecha_corte is not distinct from r.fecha_corte
   and c.integracion_version=case when r.automatizacion_activa then 1 else 0 end;
 return regimen;
exception when no_data_found or too_many_rows then
 raise exception 'regimen_devolucion_incompatible' using errcode='PT409';
end;
$$;

create function public.emitir_nota_credito_contextual(
 p_solicitud_id uuid,p_pedido_id uuid,p_motivo text,p_detalles jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare detalles jsonb; payload jsonb; resultado jsonb; nota uuid; regimen uuid; fecha timestamptz;
begin
 perform public.stock_exigir_admin();
 if jsonb_typeof(p_detalles) is distinct from 'array' or p_pedido_id is null
   or nullif(btrim(p_motivo),'') is null then
  raise exception 'datos_nota_invalidos' using errcode='PT422';
 end if;
 if jsonb_array_length(p_detalles)=0 or exists (
  select 1 from jsonb_array_elements(p_detalles) x
  where jsonb_typeof(x->'detalle_id') is distinct from 'string'
     or jsonb_typeof(x->'cantidad') is distinct from 'number'
     or x - 'detalle_id' - 'cantidad' <> '{}'::jsonb
 ) then raise exception 'renglones_nota_invalidos' using errcode='PT422'; end if;
 select jsonb_agg(jsonb_build_object('detalle_id',(x->>'detalle_id')::uuid,
   'cantidad',trim_scale((x->>'cantidad')::numeric))
   order by (x->>'detalle_id')::uuid,(x->>'cantidad')::numeric)
 into detalles from jsonb_array_elements(p_detalles) x;
 payload:=jsonb_build_object('pedido_id',p_pedido_id,'motivo',btrim(p_motivo),'detalles',detalles);
 resultado:=public.stock_devolucion_replay(p_solicitud_id,'emision',payload);
 if resultado is not null then return resultado; end if;
 regimen:=public.stock_devolucion_regimen();
 if exists(select 1 from public.notas_credito where clave=p_solicitud_id::text) then
  raise exception 'clave_nota_historica_en_uso' using errcode='PT409';
 end if;
 if exists (
  select 1 from jsonb_array_elements(detalles) x
  left join public.pedido_detalles d on d.id=(x->>'detalle_id')::uuid and d.pedido_id=p_pedido_id
  where coalesce(d.cantidad_entregada,0)<=0
 ) then raise exception 'renglon_sin_entrega_elegible' using errcode='PT422'; end if;
 -- Private commercial body: validates order and cumulative quantities, prices,
 -- credits and commission. The legacy public wrapper remains blocked with ON.
 nota:=public.stock_base_crear_nota_credito(p_pedido_id,btrim(p_motivo),detalles,p_solicitud_id::text);
 select n.fecha,jsonb_build_object('solicitud_id',p_solicitud_id,'nota_id',n.id,
   'numero',n.numero,'total',n.total,'fecha',n.fecha,'actor_id',n.usuario_id,'regimen_id',regimen)
 into strict fecha,resultado from public.notas_credito n where n.id=nota;
 insert into public.solicitudes_devolucion_contextual
  (id,operacion,actor_id,regimen_id,nota_id,payload,resultado,fecha)
 values(p_solicitud_id,'emision',auth.uid(),regimen,nota,payload,resultado,fecha);
 return resultado;
end;
$$;

create function public.recibir_nota_credito_contextual(
 p_solicitud_id uuid,p_detalle_id uuid,p_cantidad_apta numeric,p_cantidad_no_apta numeric)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare payload jsonb; resultado jsonb; linea public.nota_credito_detalles;
 regimen uuid; ubicacion uuid; producto uuid; recepcion uuid; evento uuid;
 fecha timestamptz; items jsonb:='[]'; movimientos integer;
begin
 perform public.stock_exigir_admin();
 if p_detalle_id is null or p_cantidad_apta is null or p_cantidad_no_apta is null
  or p_cantidad_apta not between 0 and 9999999999.99
  or p_cantidad_no_apta not between 0 and 9999999999.99
  or p_cantidad_apta<>round(p_cantidad_apta,2) or p_cantidad_no_apta<>round(p_cantidad_no_apta,2) then
  raise exception 'cantidades_recepcion_invalidas' using errcode='PT422';
 end if;
 payload:=jsonb_build_object('detalle_id',p_detalle_id,'cantidad_apta',trim_scale(p_cantidad_apta),
  'cantidad_no_apta',trim_scale(p_cantidad_no_apta));
 resultado:=public.stock_devolucion_replay(p_solicitud_id,'recepcion',payload);
 if resultado is not null then return resultado; end if;
 regimen:=public.stock_devolucion_regimen();
 select c.ubicacion_id into strict ubicacion from public.stock_configuracion c;
 fecha:=clock_timestamp();
 if exists(select 1 from public.stock_regimenes where id=regimen and fecha_corte>fecha) then
  raise exception 'recepcion_anterior_al_corte' using errcode='PT409';
 end if;
 select d.* into linea from public.nota_credito_detalles d
 join public.notas_credito n on n.id=d.nota_id
 where d.id=p_detalle_id for update of d;
 if not found then raise exception 'renglon_nota_inexistente' using errcode='PT404'; end if;
 if exists(select 1 from public.recepciones_nota_credito where detalle_id=p_detalle_id) then
  raise exception 'renglon_nota_ya_recibido' using errcode='PT409';
 end if;
 if p_cantidad_apta+p_cantidad_no_apta<>linea.cantidad then
  raise exception 'recepcion_debe_completar_renglon' using errcode='PT422';
 end if;
 select d.producto_id into strict producto from public.pedido_detalles d where d.id=linea.pedido_detalle_id;
 insert into public.recepciones_nota_credito(detalle_id,fecha,usuario_id,apta_venta,cantidad_apta,cantidad_no_apta)
 values(p_detalle_id,fecha,auth.uid(),p_cantidad_no_apta=0,p_cantidad_apta,p_cantidad_no_apta)
 returning id into recepcion;
 -- One receipt covers one commercial line, so it has at most one product delta.
 if p_cantidad_apta>0 then
  items:=jsonb_build_array(jsonb_build_object('producto_id',producto,
   'cantidad_delta',p_cantidad_apta,'tipo','devolucion_apta'));
 end if;
 -- The event uses the server-generated receipt UUID as its key. The client
 -- UUID lives in the return ledger and cannot claim a sale's Stock event key.
 evento:=public.stock_registrar_evento(ubicacion,'recepcion_nota_credito',recepcion,recepcion,
  jsonb_build_object('items',items,'motivo','Recepción de devolución'),fecha);
 movimientos:=public.stock_aplicar_deltas(ubicacion,evento,items);
 resultado:=jsonb_build_object('solicitud_id',p_solicitud_id,'nota_id',linea.nota_id,
  'detalle_id',p_detalle_id,'pedido_detalle_id',linea.pedido_detalle_id,'recepcion_id',recepcion,
  'evento_id',evento,'actor_id',auth.uid(),'regimen_id',regimen,'fecha',fecha,
  'cantidad_apta',p_cantidad_apta,'cantidad_no_apta',p_cantidad_no_apta,
  'cantidad_ingresada',case when movimientos=0 then 0 else p_cantidad_apta end,'movimientos_stock',movimientos);
 insert into public.solicitudes_devolucion_contextual
  (id,operacion,actor_id,regimen_id,nota_id,recepcion_id,evento_id,payload,resultado,fecha)
 values(p_solicitud_id,'recepcion',auth.uid(),regimen,linea.nota_id,recepcion,evento,payload,resultado,fecha);
 return resultado;
end;
$$;

revoke all on function public.stock_devolucion_replay(uuid,text,jsonb),public.stock_devolucion_regimen(),
 public.emitir_nota_credito_contextual(uuid,uuid,text,jsonb),public.recibir_nota_credito_contextual(uuid,uuid,numeric,numeric)
 from public,anon,authenticated,service_role;
grant execute on function public.emitir_nota_credito_contextual(uuid,uuid,text,jsonb),
 public.recibir_nota_credito_contextual(uuid,uuid,numeric,numeric) to authenticated;

-- Keep the existing function identity, ownership and grants. Replace only the
-- recovered-cost calculation and fail if the expected definition has drifted.
do $migration$
declare definicion text; anterior text; nueva text;
begin
 definicion:=pg_get_functiondef('public.resumen_comercial(timestamptz,timestamptz)'::regprocedure);
 anterior:=$old$select coalesce(sum(d.costo),0) into recuperado from public.recepciones_nota_credito rc
 join public.nota_credito_detalles d on d.id=rc.detalle_id
 where rc.apta_venta and rc.fecha>=p_inicio and rc.fecha<p_fin;$old$;
 nueva:=$new$select coalesce(sum(case when rc.cantidad_apta is null then
   case when rc.apta_venta then d.costo else 0 end
   else round(d.costo*rc.cantidad_apta/d.cantidad,2) end),0)
 into recuperado from public.recepciones_nota_credito rc
 join public.nota_credito_detalles d on d.id=rc.detalle_id
 where rc.fecha>=p_inicio and rc.fecha<p_fin;$new$;
 if (length(definicion)-length(replace(definicion,anterior,'')))<>length(anterior) then
  raise exception 'ancla_resumen_comercial_incompatible';
 end if;
 execute replace(definicion,anterior,nueva);
end;
$migration$;

commit;
