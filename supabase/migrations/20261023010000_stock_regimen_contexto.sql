-- TESTING candidate only. Never applied remotely by this work.
-- Additive transition protocol; original business function bodies are retained.
begin;
select pg_advisory_xact_lock(829001);
do $$begin
 if exists(select 1 from public.stock_configuracion where automatizacion_activa) then
  raise exception 'Instalar solamente con Stock OFF y conciliación previa' using errcode='PT409';end if;
end$$;

create table public.stock_regimenes(
 id uuid primary key default gen_random_uuid(), protocolo integer not null check(protocolo=2),
 automatizacion_activa boolean not null, fecha_corte timestamptz,
 creado_at timestamptz not null default clock_timestamp(),cerrado_at timestamptz,
 actor_id uuid references auth.users(id),evidencia jsonb not null,
 check((not automatizacion_activa and fecha_corte is null) or(automatizacion_activa and fecha_corte is not null and isfinite(fecha_corte)))
);
create table public.stock_transicion(
 singleton boolean primary key default true check(singleton),regimen_id uuid not null references public.stock_regimenes(id),
 paso_instalacion smallint not null default 1 check(paso_instalacion between 1 and 3),
 mantenimiento boolean not null default false,motivo text,pausada_at timestamptz,pausada_por uuid references auth.users(id)
);
create table public.stock_preparaciones(
 solicitud_id uuid primary key,pedido_id uuid not null references public.pedidos(id),actor_id uuid not null references auth.users(id),
 regimen_id uuid not null references public.stock_regimenes(id),protocolo integer not null check(protocolo=2),
 fecha_fisica timestamptz not null check(isfinite(fecha_fisica)),creado_at timestamptz not null default clock_timestamp(),
 revision boolean not null default false,motivo_revision text,revisada_por uuid references auth.users(id),revisada_at timestamptz
);
insert into public.stock_regimenes(protocolo,automatizacion_activa,evidencia)
 values(2,false,'{"origen":"instalacion_protocolo_testing"}');
-- Fail closed across a multi-file installation. Only an audited administrative
-- publication may release OFF after every migration/client is ready.
insert into public.stock_transicion(regimen_id,mantenimiento,motivo,pausada_at)
 select id,true,'Instalación de protocolo pendiente de auditoría',clock_timestamp() from public.stock_regimenes;
alter table public.stock_regimenes enable row level security;
alter table public.stock_transicion enable row level security;
alter table public.stock_preparaciones enable row level security;
revoke all on public.stock_regimenes,public.stock_transicion,public.stock_preparaciones from public,anon,authenticated,service_role;

create function public.stock_exigir_admin() returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin if public.es_administrador() is not true then raise exception 'Solo administración activa' using errcode='PT403';end if;end$$;

-- FIRST lock for every affected path, including statement triggers before row locks.
create function public.stock_exigir_operativo() returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 perform pg_advisory_xact_lock(829001);
 if (select mantenimiento from public.stock_transicion where singleton) is distinct from false then
  raise exception 'stock_en_mantenimiento' using errcode='PT409';end if;
 if exists(select 1 from public.stock_transicion t join public.stock_regimenes r on r.id=t.regimen_id cross join public.stock_configuracion c
  where c.automatizacion_activa is distinct from r.automatizacion_activa or c.fecha_corte is distinct from r.fecha_corte) then
  raise exception 'regimen_inconsistente' using errcode='PT409';end if;
end$$;
create function public.stock_barrera_dml() returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin perform public.stock_exigir_operativo();return null;end$$;
do $$declare tab text;begin
 foreach tab in array array['pedidos','pedido_detalles','stock_actual','stock_movimientos','stock_eventos','finalizacion_pedido_solicitudes',
  'cobros_cliente','pedido_pagos','notas_credito','nota_credito_detalles','recepciones_nota_credito',
  'movimientos_credito_cliente','ajustes_comision_aplicados','liquidaciones','liquidacion_detalles','correcciones_operacion','solicitudes_pedido_interno'] loop
  execute format('create trigger a0_stock_barrera before insert or update or delete or truncate on public.%I for each statement execute function public.stock_barrera_dml()',tab);
 end loop;
end$$;

-- Retain exact business bodies under private names. Clients cannot invoke them.
alter function public.finalizar_gestion_pedido_v2(uuid,uuid,timestamptz,text,jsonb,jsonb,text,text,numeric,text) rename to stock_base_finalizar_v2;
revoke all on function public.stock_base_finalizar_v2(uuid,uuid,timestamptz,text,jsonb,jsonb,text,text,numeric,text) from public,anon,authenticated,service_role;
create function public.finalizar_gestion_pedido_v2(p_solicitud_id uuid,p_pedido_id uuid,p_fecha_fisica timestamptz,p_estado text,
 p_originales jsonb,p_agregados jsonb,p_tipo_pago text,p_motivo_no_entrega text default null,p_importe_pago numeric default null,p_medio_pago text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 perform public.stock_exigir_admin();perform pg_advisory_xact_lock(829001);
 if not exists(select 1 from public.finalizacion_pedido_solicitudes where solicitud_id=p_solicitud_id) then
  raise exception 'contexto_regimen_requerido' using errcode='PT409';end if;
 -- Existing commercial normalizer enforces original actor, hash and full content.
 return public.stock_base_finalizar_v2(p_solicitud_id,p_pedido_id,p_fecha_fisica,p_estado,p_originales,p_agregados,p_tipo_pago,p_motivo_no_entrega,p_importe_pago,p_medio_pago);
end$$;

-- Guard public mutation RPCs BEFORE they take client/order/financial row locks.
do $$declare n text;f record;args text;extra text;stmt text;priv text;begin
 foreach n in array array['ajustar_stock','cargar_stock_inicial','stock_registrar_evento','stock_aplicar_deltas','finalizar_gestion_pedido',
  'corregir_operacion_finalizada','crear_nota_credito','recibir_nota_credito','crear_pedido_interno','actualizar_pedido_activo',
  'eliminar_pedido_pendiente','crear_pedido_catalogo','configurar_catalogo_cliente','configurar_catalogo_cliente_v2',
  'registrar_pago_cliente','aplicar_credito_cliente','reintegrar_credito_cliente','registrar_liquidacion','registrar_liquidacion_con_nc'] loop
  select p.oid,p.prorettype,p.proretset,pg_get_function_arguments(p.oid) decl,pg_get_function_identity_arguments(p.oid) ident,pg_get_function_result(p.oid) ret,p.proargnames,p.pronargs,
   has_function_privilege('authenticated',p.oid,'execute') auth_exec,has_function_privilege('anon',p.oid,'execute') anon_exec,
   has_function_privilege('service_role',p.oid,'execute') service_exec into strict f
   from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname=n;
  select string_agg(quote_ident(x),',' order by ord) into args from unnest(f.proargnames[1:f.pronargs]) with ordinality as a(x,ord);
  priv:='stock_base_'||n;
  execute format('alter function public.%I(%s) rename to %I',n,f.ident,priv);
  execute format('revoke all on function public.%I(%s) from public,anon,authenticated,service_role',priv,f.ident);
  extra:='';
  if n in('corregir_operacion_finalizada','crear_nota_credito','recibir_nota_credito') then
   extra:='if exists(select 1 from public.stock_configuracion where automatizacion_activa) then raise exception ''camino_stock_no_integrado'' using errcode=''PT409'';end if;';
  elsif n='crear_pedido_interno' then
   -- An existing creation UUID may only replay through the unchanged hash/actor
   -- validator. It cannot create a new direct sale or adopt different content.
   extra:='if p_tipo_operacion=''venta_directa'' and not exists(select 1 from public.solicitudes_pedido_interno where id=p_id) then raise exception ''venta_directa_no_disponible_testing'' using errcode=''PT409'';end if;';
  elsif n='actualizar_pedido_activo' then
   extra:='if p_tipo_operacion=''venta_directa'' or exists(select 1 from public.pedidos where id=p_pedido_id and tipo_operacion=''venta_directa'') then raise exception ''venta_directa_no_disponible_testing'' using errcode=''PT409'';end if;';
  end if;
  stmt:=case when f.proretset then format('return query select * from public.%I(%s);return;',priv,args)
   when f.prorettype='void'::regtype then format('perform public.%I(%s);return;',priv,args) else format('return public.%I(%s);',priv,args) end;
  execute format('create function public.%I(%s) returns %s language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $body$ begin perform public.stock_exigir_operativo();%s %s end $body$',n,f.decl,f.ret,extra,stmt);
  execute format('revoke all on function public.%I(%s) from public,anon,authenticated,service_role',n,f.ident);
  if n not in('stock_registrar_evento','stock_aplicar_deltas') then
   if f.auth_exec then execute format('grant execute on function public.%I(%s) to authenticated',n,f.ident);end if;
   if f.anon_exec then execute format('grant execute on function public.%I(%s) to anon',n,f.ident);end if;
   if f.service_exec then execute format('grant execute on function public.%I(%s) to service_role',n,f.ident);end if;
  end if;
 end loop;
end$$;
revoke all on function public.finalizar_gestion_pedido_legacy_interno(uuid,text,text,text,jsonb,text,numeric,text),
 public.finalizar_gestion_pedido_sin_nc(uuid,text,text,text,jsonb,text,numeric,text),public.corregir_operacion_sin_nc(uuid,text,jsonb)
 from public,anon,authenticated,service_role;

-- These implementation-only mutators have public wrappers above. Their original
-- bodies stay callable by their owner, never by a direct service-role request.
revoke all on function public.actualizar_pedido_activo_interno(uuid,numeric,text,text,text,date,jsonb),
 public.eliminar_pedido_pendiente_interno(uuid),public.registrar_liquidacion_sin_nc(uuid,date,date,numeric,numeric,jsonb)
 from public,anon,authenticated,service_role;

-- Deliberately bounded financial surface; SELECT and unrelated tables/default
-- privileges are preserved. Local Flutter consumers mutate through guarded RPCs.
do $$declare tab text;cols text;begin
 foreach tab in array array['cobros_cliente','pedido_pagos','notas_credito','nota_credito_detalles','recepciones_nota_credito',
  'movimientos_credito_cliente','ajustes_comision_aplicados','liquidaciones','liquidacion_detalles','correcciones_operacion','solicitudes_pedido_interno'] loop
  execute format('revoke insert,update,delete,truncate,references,trigger on public.%I from public,anon,authenticated,service_role',tab);
  select string_agg(quote_ident(attname),',' order by attnum) into cols from pg_attribute
   where attrelid=format('public.%I',tab)::regclass and attnum>0 and not attisdropped;
  execute format('revoke insert(%s),update(%s),references(%s) on public.%I from public,anon,authenticated,service_role',cols,cols,cols,tab);
 end loop;
end$$;

-- The only identity sequence on this financial surface is generated by the
-- owner-backed credit-note RPC; clients must not reset or advance it directly.
revoke usage,update on sequence public.notas_credito_numero_seq from public,anon,authenticated,service_role;

alter function public.activar_automatizacion_stock(uuid,timestamptz) rename to stock_base_activar;
revoke all on function public.stock_base_activar(uuid,timestamptz) from public,anon,authenticated,service_role;
create function public.activar_automatizacion_stock(p_ubicacion_id uuid,p_fecha_corte timestamptz) returns void
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin perform public.stock_exigir_admin();raise exception 'usar_transicion_administrativa' using errcode='PT409';end$$;

create function public.preparar_finalizacion_contexto(p_solicitud_id uuid,p_pedido_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare t public.stock_transicion;r public.stock_preparaciones;begin
 perform public.stock_exigir_admin();perform public.stock_exigir_operativo();
 if p_solicitud_id is null or p_pedido_id is null then raise exception 'Solicitud inválida' using errcode='PT422';end if;
 select * into strict t from public.stock_transicion where singleton;
 select * into r from public.stock_preparaciones where solicitud_id=p_solicitud_id;
 if found then
  if r.actor_id is distinct from auth.uid() or r.pedido_id<>p_pedido_id then raise exception 'solicitud_incompatible' using errcode='PT409';end if;
  if r.regimen_id<>t.regimen_id or r.revision then raise exception 'regimen_incompatible' using errcode='PT409';end if;
 else
  if exists(select 1 from public.finalizacion_pedido_solicitudes where solicitud_id=p_solicitud_id) then raise exception 'solicitud_incompatible' using errcode='PT409';end if;
  perform 1 from public.pedidos where id=p_pedido_id and resultado_entrega='pendiente' and estado<>'anulado' and facturado and tipo_operacion='pedido';
  if not found then raise exception 'Pedido no disponible' using errcode='PT409';end if;
  insert into public.stock_preparaciones(solicitud_id,pedido_id,actor_id,regimen_id,protocolo,fecha_fisica)
   values(p_solicitud_id,p_pedido_id,auth.uid(),t.regimen_id,2,clock_timestamp()) returning * into r;
 end if;
 return jsonb_build_object('solicitud_id',r.solicitud_id,'pedido_id',r.pedido_id,'actor_id',r.actor_id,'regimen_id',r.regimen_id,'protocolo',r.protocolo,'fecha_fisica',r.fecha_fisica);
end$$;

create function public.finalizar_gestion_pedido_contexto(p_solicitud_id uuid,p_pedido_id uuid,p_fecha_fisica timestamptz,p_estado text,
 p_originales jsonb,p_agregados jsonb,p_tipo_pago text,p_regimen_id uuid,p_protocolo integer,
 p_motivo_no_entrega text default null,p_importe_pago numeric default null,p_medio_pago text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare r public.stock_preparaciones;t public.stock_transicion;begin
 perform public.stock_exigir_admin();perform pg_advisory_xact_lock(829001);
 select * into r from public.stock_preparaciones where solicitud_id=p_solicitud_id;
 if not found or r.actor_id is distinct from auth.uid() or r.pedido_id is distinct from p_pedido_id
 or r.regimen_id is distinct from p_regimen_id or r.protocolo is distinct from p_protocolo or r.fecha_fisica is distinct from p_fecha_fisica then
  raise exception 'solicitud_incompatible' using errcode='PT409';end if;
 if exists(select 1 from public.finalizacion_pedido_solicitudes where solicitud_id=p_solicitud_id) then
  return public.stock_base_finalizar_v2(p_solicitud_id,p_pedido_id,p_fecha_fisica,p_estado,p_originales,p_agregados,p_tipo_pago,p_motivo_no_entrega,p_importe_pago,p_medio_pago);
 end if;
 perform public.stock_exigir_operativo();select * into strict t from public.stock_transicion where singleton;
 if r.regimen_id<>t.regimen_id or r.protocolo<>2 or r.revision then raise exception 'regimen_incompatible' using errcode='PT409';end if;
 return public.stock_base_finalizar_v2(p_solicitud_id,p_pedido_id,p_fecha_fisica,p_estado,p_originales,p_agregados,p_tipo_pago,p_motivo_no_entrega,p_importe_pago,p_medio_pago);
end$$;

create function public.stock_huella_inventario() returns text language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
 select encode(sha256(convert_to(coalesce(jsonb_agg(jsonb_build_array(ubicacion_id,producto_id,cantidad) order by ubicacion_id,producto_id),'[]')::text,'UTF8')),'hex') from public.stock_actual
$$;
create function public.stock_estado_transicion() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin perform public.stock_exigir_admin();perform pg_advisory_xact_lock(829001);return jsonb_build_object(
 'transicion',(select to_jsonb(t) from public.stock_transicion t),'regimen',(select to_jsonb(r) from public.stock_regimenes r join public.stock_transicion t on t.regimen_id=r.id),
 'inventario_hash',public.stock_huella_inventario(),'preparaciones_sin_conciliar',(select count(*) from public.stock_preparaciones p where not p.revision and not exists(select 1 from public.finalizacion_pedido_solicitudes f where f.solicitud_id=p.solicitud_id)),
 'postgres_now',clock_timestamp());end$$;
create function public.stock_pausar_transicion(p_regimen_id uuid,p_motivo text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 perform public.stock_exigir_admin();perform pg_advisory_xact_lock(829001);
 if p_motivo is null or btrim(p_motivo)='' then raise exception 'Motivo obligatorio' using errcode='PT422';end if;
 if not exists(select 1 from public.stock_transicion where regimen_id=p_regimen_id) then raise exception 'regimen_incompatible' using errcode='PT409';end if;
 update public.stock_transicion set mantenimiento=true,motivo=p_motivo,pausada_at=coalesce(pausada_at,clock_timestamp()),pausada_por=auth.uid() where singleton;
 return public.stock_estado_transicion();end$$;
create function public.stock_revisar_preparacion(p_solicitud_id uuid,p_motivo text) returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 perform public.stock_exigir_admin();perform pg_advisory_xact_lock(829001);
 if p_motivo is null or btrim(p_motivo)='' then raise exception 'Motivo obligatorio' using errcode='PT422';end if;
 if not (select mantenimiento from public.stock_transicion) then raise exception 'Requiere pausa' using errcode='PT409';end if;
 if exists(select 1 from public.finalizacion_pedido_solicitudes where solicitud_id=p_solicitud_id) then raise exception 'Solicitud confirmada' using errcode='PT409';end if;
 update public.stock_preparaciones set revision=true,motivo_revision=p_motivo,revisada_por=auth.uid(),revisada_at=clock_timestamp() where solicitud_id=p_solicitud_id;
 if not found then raise exception 'Preparación inexistente' using errcode='PT404';end if;
end$$;
create function public.stock_publicar_regimen(p_regimen_id uuid,p_stock_on boolean,p_inventario_hash text,p_acta jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare t public.stock_transicion;old public.stock_regimenes;fresh uuid;loc uuid;cut timestamptz;begin
 perform public.stock_exigir_admin();perform pg_advisory_xact_lock(829001);
 select * into strict t from public.stock_transicion where singleton for update;
 if t.paso_instalacion<>3 then raise exception 'instalacion_incompleta' using errcode='PT409';end if;
 select * into strict old from public.stock_regimenes where id=t.regimen_id;
 if not t.mantenimiento or t.regimen_id is distinct from p_regimen_id then raise exception 'Transición inválida' using errcode='PT409';end if;
 if p_stock_on is null or (old.automatizacion_activa and not p_stock_on) then raise exception 'Cierre ON a OFF no implementado' using errcode='PT409';end if;
 if p_acta is null or jsonb_typeof(p_acta)<>'object' or (p_acta->'dispositivos_conciliados') is distinct from 'true'::jsonb
 or (p_acta->'inventario_conciliado') is distinct from 'true'::jsonb or coalesce(btrim(p_acta->>'referencia'),'')='' then raise exception 'Acta requerida' using errcode='PT422';end if;
 if p_inventario_hash is distinct from public.stock_huella_inventario() then raise exception 'Inventario cambió' using errcode='PT409';end if;
 if exists(select 1 from public.stock_preparaciones p where not p.revision and not exists(select 1 from public.finalizacion_pedido_solicitudes f where f.solicitud_id=p.solicitud_id)) then
  raise exception 'Preparaciones sin conciliar' using errcode='PT409';end if;
 select id into strict loc from public.ubicaciones_stock where codigo='deposito_alberdi' and activo;
 if (select count(*) from public.stock_configuracion)<>1 then raise exception 'Solo depósito único integrado' using errcode='PT409';end if;
 if p_stock_on and not old.automatizacion_activa then
  cut:=clock_timestamp();update public.stock_configuracion set integracion_version=1 where ubicacion_id=loc;
  perform public.stock_base_activar(loc,cut);
 else cut:=old.fecha_corte;end if;
 insert into public.stock_regimenes(protocolo,automatizacion_activa,fecha_corte,actor_id,evidencia)
  values(2,p_stock_on,cut,auth.uid(),p_acta||jsonb_build_object('inventario_hash',p_inventario_hash)) returning id into fresh;
 update public.stock_regimenes set cerrado_at=clock_timestamp() where id=old.id;
 update public.stock_transicion set regimen_id=fresh,mantenimiento=false,motivo=null,pausada_at=null,pausada_por=null where singleton;
 return public.stock_estado_transicion();end$$;

create function public.auditar_finalizaciones_transicion(p_solicitudes uuid[]) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin perform public.stock_exigir_admin();
 if p_solicitudes is null or cardinality(p_solicitudes)>200 then raise exception 'Límite 200 UUID' using errcode='PT422';end if;
 return(select coalesce(jsonb_agg(jsonb_build_object('solicitud_id',id,'preparacion',to_jsonb(p),'confirmacion',to_jsonb(f),
  'estado',case when f.solicitud_id is not null then 'confirmada' when p.solicitud_id is not null then 'preparada' else 'inexistente_global' end)),'[]')
  from (select distinct unnest(p_solicitudes) id)x left join public.stock_preparaciones p on p.solicitud_id=x.id left join public.finalizacion_pedido_solicitudes f on f.solicitud_id=x.id);
end$$;

-- No context/GUC supplied by clients can bypass any gate. Private helpers stay private.
do $$declare f record;begin
 for f in select p.oid,p.proname,pg_get_function_identity_arguments(p.oid) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and (p.proname like 'stock_%' or p.proname in('preparar_finalizacion_contexto','finalizar_gestion_pedido_contexto','auditar_finalizaciones_transicion','finalizar_gestion_pedido_v2','activar_automatizacion_stock')) loop
  execute format('revoke all on function public.%I(%s) from public,anon,authenticated,service_role',f.proname,f.args);
  if f.proname in('stock_estado_transicion','stock_pausar_transicion','stock_revisar_preparacion','stock_publicar_regimen','preparar_finalizacion_contexto','finalizar_gestion_pedido_contexto','auditar_finalizaciones_transicion','finalizar_gestion_pedido_v2','activar_automatizacion_stock') then
   execute format('grant execute on function public.%I(%s) to authenticated',f.proname,f.args);end if;
 end loop;
end$$;
-- Existing RPCs remain the only public mutation surface; configuration cannot be edited directly.
revoke insert,update,delete,truncate on public.stock_configuracion from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
