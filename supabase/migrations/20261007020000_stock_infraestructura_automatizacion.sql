-- Fase 2A-1: infraestructura desconectada del circuito comercial.
begin;

create table public.stock_configuracion (
  ubicacion_id uuid primary key references public.ubicaciones_stock(id) on delete restrict,
  automatizacion_activa boolean not null default false,
  fecha_corte timestamptz,
  activada_at timestamptz,
  activada_por uuid references public.usuarios(id) on delete restrict,
  integracion_version integer not null default 0 check (integracion_version >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stock_configuracion_regimen check (
    (not automatizacion_activa and fecha_corte is null and activada_at is null and activada_por is null)
    or (automatizacion_activa and integracion_version >= 1 and fecha_corte is not null
      and isfinite(fecha_corte) and activada_at is not null and activada_por is not null
      and fecha_corte <= activada_at)
  )
);
insert into public.stock_configuracion(ubicacion_id)
select id from public.ubicaciones_stock where codigo='deposito_alberdi'
on conflict (ubicacion_id) do nothing;

create table public.stock_eventos (
  id uuid primary key default gen_random_uuid(),
  ubicacion_id uuid not null references public.stock_configuracion(ubicacion_id) on delete restrict,
  tipo_evento text not null check (tipo_evento in ('finalizacion_pedido','correccion_operacion','recepcion_nota_credito')),
  origen_tipo text not null,
  origen_id uuid not null,
  pedido_id uuid references public.pedidos(id) on delete restrict,
  correccion_id uuid references public.correcciones_operacion(id) on delete restrict,
  recepcion_id uuid references public.recepciones_nota_credito(id) on delete restrict,
  solicitud_id uuid not null unique,
  request_hash text not null check (request_hash ~ '^[a-f0-9]{64}$'),
  solicitud jsonb not null check (jsonb_typeof(solicitud)='object'),
  actor_id uuid not null references public.usuarios(id) on delete restrict,
  automatizacion_activa boolean not null,
  fecha_corte_aplicable timestamptz,
  fecha_fisica timestamptz not null check (isfinite(fecha_fisica)),
  created_at timestamptz not null default now(),
  constraint stock_eventos_regimen check (
    (not automatizacion_activa and fecha_corte_aplicable is null)
    or (automatizacion_activa and fecha_corte_aplicable is not null and isfinite(fecha_corte_aplicable))
  ),
  constraint stock_eventos_origen check (
    (tipo_evento='finalizacion_pedido' and origen_tipo='pedido' and pedido_id=origen_id
      and pedido_id is not null and correccion_id is null and recepcion_id is null)
    or (tipo_evento='correccion_operacion' and origen_tipo='correccion_operacion' and correccion_id=origen_id
      and correccion_id is not null and pedido_id is null and recepcion_id is null)
    or (tipo_evento='recepcion_nota_credito' and origen_tipo='recepcion_nota_credito' and recepcion_id=origen_id
      and recepcion_id is not null and pedido_id is null and correccion_id is null)
  ),
  unique (tipo_evento, origen_id),
  unique (id, ubicacion_id, actor_id)
);
create index stock_eventos_historial_idx on public.stock_eventos(ubicacion_id,created_at desc,id);
create index stock_eventos_actor_idx on public.stock_eventos(actor_id);
create index stock_eventos_pedido_idx on public.stock_eventos(pedido_id) where pedido_id is not null;
create index stock_eventos_correccion_idx on public.stock_eventos(correccion_id) where correccion_id is not null;
create index stock_eventos_recepcion_idx on public.stock_eventos(recepcion_id) where recepcion_id is not null;

alter table public.stock_movimientos add column evento_id uuid;
alter table public.stock_movimientos add constraint stock_movimientos_evento_fkey
 foreign key (evento_id,ubicacion_id,usuario_id) references public.stock_eventos(id,ubicacion_id,actor_id) on delete restrict;
create unique index stock_movimientos_evento_producto_unico_idx
 on public.stock_movimientos(evento_id,producto_id) where evento_id is not null;
alter table public.stock_movimientos drop constraint stock_movimientos_tipo_valido;
alter table public.stock_movimientos add constraint stock_movimientos_tipo_valido check (
 tipo in ('stock_inicial','ajuste_entrada','ajuste_salida','entrega','venta_directa','correccion_entrada','correccion_salida','devolucion_apta')
);
alter table public.stock_movimientos drop constraint stock_movimientos_sentido_valido;
alter table public.stock_movimientos add constraint stock_movimientos_sentido_valido check (
 (tipo='stock_inicial' and cantidad_anterior=0 and cantidad_delta>=0)
 or (tipo in ('ajuste_entrada','correccion_entrada','devolucion_apta') and cantidad_delta>0)
 or (tipo in ('ajuste_salida','entrega','venta_directa','correccion_salida') and cantidad_delta<0)
);
alter table public.stock_movimientos add constraint stock_movimientos_evento_obligatorio check (
 (tipo in ('stock_inicial','ajuste_entrada','ajuste_salida') and evento_id is null)
 or (tipo in ('entrega','venta_directa','correccion_entrada','correccion_salida','devolucion_apta')
   and evento_id is not null and referencia_tipo is not null and referencia_tipo='stock_evento'
   and referencia_id is not null and referencia_id=evento_id)
);

alter table public.stock_configuracion enable row level security;
alter table public.stock_eventos enable row level security;
revoke all on public.stock_configuracion,public.stock_eventos from public,anon,authenticated,service_role;
grant select on public.stock_configuracion,public.stock_eventos to authenticated;
create policy stock_configuracion_admin_select on public.stock_configuracion
 for select to authenticated using (public.es_administrador());
create policy stock_eventos_admin_select on public.stock_eventos
 for select to authenticated using (public.es_administrador());

-- Contrato lógico deliberadamente pequeño. Orden de items no significativo.
-- Normaliza UUID, decimales y whitespace exterior de motivo/observación.
create function public.stock_normalizar_solicitud(p_contenido jsonb) returns jsonb
language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $$
declare x jsonb; producto uuid; delta numeric; items jsonb:='[]';
begin
 if jsonb_typeof(p_contenido) is distinct from 'object'
 or exists(select 1 from jsonb_object_keys(p_contenido) k where k not in ('items','motivo','observacion'))
 or jsonb_typeof(p_contenido->'items') is distinct from 'array'
 or jsonb_array_length(p_contenido->'items')>300
 or jsonb_typeof(p_contenido->'motivo') is distinct from 'string'
 or btrim(p_contenido->>'motivo')='' or char_length(btrim(p_contenido->>'motivo'))>200
 or (p_contenido ? 'observacion' and jsonb_typeof(p_contenido->'observacion') not in ('string','null'))
 or char_length(p_contenido->>'observacion')>2000 then
  raise exception 'Solicitud Stock inválida' using errcode='PT422';
 end if;
 for x in select value from jsonb_array_elements(p_contenido->'items') loop
  if jsonb_typeof(x) is distinct from 'object'
   or exists(select 1 from jsonb_object_keys(x) k where k not in ('producto_id','cantidad_delta','tipo'))
   or jsonb_typeof(x->'producto_id') is distinct from 'string'
   or jsonb_typeof(x->'cantidad_delta') is distinct from 'number'
   or jsonb_typeof(x->'tipo') is distinct from 'string' then
   raise exception 'Cantidad o línea Stock inválida' using errcode='PT422';
  end if;
  begin producto:=(x->>'producto_id')::uuid;
  exception when invalid_text_representation then
   raise exception 'Producto inválido' using errcode='PT422';
  end;
  delta:=(x->>'cantidad_delta')::numeric;
  if delta::text in ('NaN','Infinity','-Infinity') or delta=0 or abs(delta)>99999999999.999
   or delta<>round(delta,3)
   or (delta>0 and x->>'tipo' not in ('correccion_entrada','devolucion_apta'))
   or (delta<0 and x->>'tipo' not in ('entrega','venta_directa','correccion_salida')) then
   raise exception 'Cantidad o sentido Stock inválido' using errcode='PT422';
  end if;
  items:=items||jsonb_build_array(jsonb_build_object('producto_id',producto,'cantidad_delta',trim_scale(delta),'tipo',x->>'tipo'));
 end loop;
 if exists(select 1 from jsonb_array_elements(items) j(value) group by j.value->>'producto_id' having count(*)>1) then
  raise exception 'Producto duplicado; agregar deltas antes de registrar' using errcode='PT422';
 end if;
 select coalesce(jsonb_agg(value order by value->>'producto_id'),'[]'::jsonb) into items from jsonb_array_elements(items);
 return jsonb_build_object('items',items,'motivo',btrim(p_contenido->>'motivo'),
  'observacion',nullif(btrim(p_contenido->>'observacion'),''));
end;$$;

-- INTERNO: no conectado a finalización, corrección ni recepción existentes.
create function public.stock_registrar_evento(
 p_ubicacion_id uuid,p_tipo_evento text,p_origen_id uuid,p_solicitud_id uuid,
 p_contenido jsonb,p_fecha_fisica timestamptz
) returns uuid
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare actor uuid:=auth.uid(); contenido jsonb; solicitud jsonb; huella text;
 evento public.stock_eventos; config public.stock_configuracion; origen text;
begin
 if actor is null or public.es_administrador() is not true then
  raise exception 'Solo administración activa' using errcode='42501'; end if;
 if p_solicitud_id is null or p_origen_id is null or p_ubicacion_id is null
 or p_fecha_fisica is null or not isfinite(p_fecha_fisica) or p_fecha_fisica>clock_timestamp()
 or p_tipo_evento is null or p_tipo_evento not in ('finalizacion_pedido','correccion_operacion','recepcion_nota_credito') then
  raise exception 'Evento Stock inválido' using errcode='PT422'; end if;
 contenido:=public.stock_normalizar_solicitud(p_contenido);
 if exists(select 1 from jsonb_array_elements(contenido->'items') x where
  (p_tipo_evento='finalizacion_pedido' and x->>'tipo' not in ('entrega','venta_directa'))
  or (p_tipo_evento='correccion_operacion' and x->>'tipo' not in ('correccion_entrada','correccion_salida'))
  or (p_tipo_evento='recepcion_nota_credito' and x->>'tipo'<>'devolucion_apta')) then
  raise exception 'Tipo incompatible con el evento' using errcode='PT422'; end if;
 origen:=case p_tipo_evento when 'finalizacion_pedido' then 'pedido' else p_tipo_evento end;
 solicitud:=jsonb_build_object('version',1,'ubicacion_id',p_ubicacion_id,'tipo_evento',p_tipo_evento,
  'origen_id',p_origen_id,'fecha_fisica_epoch',trim_scale(extract(epoch from p_fecha_fisica)), 'contenido',contenido);
 huella:=encode(sha256(convert_to(solicitud::text,'UTF8')),'hex');
 -- Mismo primer lock que las funciones financieras; serializa claves/orígenes.
 perform pg_advisory_xact_lock(829001);
 select * into evento from public.stock_eventos where solicitud_id=p_solicitud_id;
 if found then
  if evento.actor_id is distinct from actor or evento.request_hash<>huella or evento.solicitud<>solicitud then
   raise exception 'Evento duplicado incompatible' using errcode='PT409'; end if;
  return evento.id;
 end if;
 if exists(select 1 from public.stock_eventos where tipo_evento=p_tipo_evento and origen_id=p_origen_id) then
  raise exception 'Origen Stock ya registrado con otra solicitud' using errcode='PT409'; end if;
 perform 1 from public.ubicaciones_stock where id=p_ubicacion_id and activo for share;
 if not found then raise exception 'Ubicación inactiva o inexistente' using errcode='PT410'; end if;
 select * into config from public.stock_configuracion where ubicacion_id=p_ubicacion_id for share;
 if not found then raise exception 'Ubicación sin configuración' using errcode='PT410'; end if;
 insert into public.stock_eventos(ubicacion_id,tipo_evento,origen_tipo,origen_id,pedido_id,correccion_id,recepcion_id,
  solicitud_id,request_hash,solicitud,actor_id,automatizacion_activa,fecha_corte_aplicable,fecha_fisica)
 values(p_ubicacion_id,p_tipo_evento,origen,p_origen_id,
  case when p_tipo_evento='finalizacion_pedido' then p_origen_id end,
  case when p_tipo_evento='correccion_operacion' then p_origen_id end,
  case when p_tipo_evento='recepcion_nota_credito' then p_origen_id end,
  p_solicitud_id,huella,solicitud,actor,config.automatizacion_activa,config.fecha_corte,p_fecha_fisica)
 returning id into evento.id;
 return evento.id;
end;$$;

create function public.stock_aplicar_deltas(p_ubicacion_id uuid,p_evento_id uuid,p_items jsonb) returns integer
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare evento public.stock_eventos; contenido jsonb; x jsonb; anterior numeric; nueva numeric;
 producto uuid; delta numeric; cantidad integer; existente integer;
begin
 if auth.uid() is null or public.es_administrador() is not true then
  raise exception 'Solo administración activa' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(829001);
 perform 1 from public.ubicaciones_stock where id=p_ubicacion_id and activo for share;
 if not found then raise exception 'Ubicación inactiva o inexistente' using errcode='PT410'; end if;
 select * into evento from public.stock_eventos where id=p_evento_id for update;
 if not found or evento.ubicacion_id is distinct from p_ubicacion_id or evento.actor_id is distinct from auth.uid() then
  raise exception 'Evento incompatible' using errcode='PT409'; end if;
 contenido:=public.stock_normalizar_solicitud(jsonb_build_object('items',p_items,
  'motivo',evento.solicitud->'contenido'->>'motivo','observacion',evento.solicitud->'contenido'->>'observacion'));
 if contenido is distinct from evento.solicitud->'contenido' then
  raise exception 'Evento duplicado incompatible' using errcode='PT409'; end if;
 -- Régimen capturado e inmutable: un retry OFF nunca se convierte en salida ON.
 if not evento.automatizacion_activa or evento.fecha_fisica<evento.fecha_corte_aplicable then return 0; end if;
 cantidad:=jsonb_array_length(contenido->'items');
 select count(*) into existente from public.stock_movimientos where evento_id=evento.id;
 if existente>0 then
  if existente<>cantidad or exists(select 1 from public.stock_movimientos m where m.evento_id=evento.id
   and not exists(select 1 from jsonb_array_elements(contenido->'items') j(value)
    where (j.value->>'producto_id')::uuid=m.producto_id and (j.value->>'cantidad_delta')::numeric=m.cantidad_delta and j.value->>'tipo'=m.tipo)) then
   raise exception 'Evento duplicado incompatible' using errcode='PT409'; end if;
  return existente;
 end if;
 for x in select value from jsonb_array_elements(contenido->'items') order by (value->>'producto_id')::uuid loop
  producto:=(x->>'producto_id')::uuid; delta:=(x->>'cantidad_delta')::numeric;
  perform 1 from public.productos where id=producto for key share;
  if not found then raise exception 'Producto inexistente' using errcode='PT404'; end if;
  select s.cantidad into anterior from public.stock_actual s where s.ubicacion_id=p_ubicacion_id and s.producto_id=producto for update;
  if not found or not exists(select 1 from public.stock_movimientos where ubicacion_id=p_ubicacion_id
   and producto_id=producto and tipo='stock_inicial') then
   raise exception 'Stock no inicializado' using errcode='PT412',detail=jsonb_build_object('producto_id',producto)::text; end if;
  nueva:=anterior+delta;
  if nueva<0 then raise exception 'Stock insuficiente' using errcode='PT409',
   detail=jsonb_build_object('codigo','stock_insuficiente','producto_id',producto,'disponible',anterior,'requerido',-delta)::text; end if;
  if nueva>99999999999.999 then raise exception 'Cantidad fuera de rango' using errcode='PT422'; end if;
  update public.stock_actual set cantidad=nueva,updated_at=clock_timestamp()
   where ubicacion_id=p_ubicacion_id and producto_id=producto;
  insert into public.stock_movimientos(ubicacion_id,producto_id,tipo,cantidad_anterior,cantidad_delta,cantidad_nueva,
   motivo,observacion,usuario_id,referencia_tipo,referencia_id,evento_id)
  values(p_ubicacion_id,producto,x->>'tipo',anterior,delta,nueva,contenido->>'motivo',contenido->>'observacion',
   evento.actor_id,'stock_evento',evento.id,evento.id);
 end loop;
 return cantidad;
end;$$;

create function public.activar_automatizacion_stock(p_ubicacion_id uuid,p_fecha_corte timestamptz) returns void
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare config public.stock_configuracion;
begin
 if auth.uid() is null or public.es_administrador() is not true then
  raise exception 'Solo administración activa' using errcode='42501'; end if;
 if p_fecha_corte is null or not isfinite(p_fecha_corte) or p_fecha_corte>clock_timestamp() then
  raise exception 'Fecha de corte explícita inválida' using errcode='PT422'; end if;
 perform pg_advisory_xact_lock(829001);
 perform 1 from public.ubicaciones_stock where id=p_ubicacion_id and activo for share;
 if not found then raise exception 'Ubicación inactiva o inexistente' using errcode='PT410'; end if;
 -- Evita carreras con altas/bajas de productos durante la cobertura.
 lock table public.productos in share mode;
 select * into config from public.stock_configuracion where ubicacion_id=p_ubicacion_id for update;
 if not found then raise exception 'Ubicación sin configuración' using errcode='PT410'; end if;
 if config.automatizacion_activa then raise exception 'Automatización ya activa' using errcode='PT409'; end if;
 if not exists(select 1 from public.productos) or exists(select 1 from public.productos p where
  not exists(select 1 from public.stock_actual s where s.producto_id=p.id and s.ubicacion_id=p_ubicacion_id)
  or not exists(select 1 from public.stock_movimientos m where m.producto_id=p.id and m.ubicacion_id=p_ubicacion_id and m.tipo='stock_inicial')) then
  raise exception 'Existen productos sin inicializar o catálogo vacío' using errcode='PT412'; end if;
 -- Una migración futura debe habilitar este requisito después de integrar TODOS
 -- los caminos, permisos, solicitudes en vuelo y conciliación física del corte.
 if config.integracion_version<1 then
  raise exception 'Activación bloqueada: integración y procedimiento de corte pendientes' using errcode='PT412'; end if;
 update public.stock_configuracion set automatizacion_activa=true,fecha_corte=p_fecha_corte,
  activada_at=clock_timestamp(),activada_por=auth.uid(),updated_at=clock_timestamp() where ubicacion_id=p_ubicacion_id;
end;$$;

create function public.diagnosticar_automatizacion_stock(p_ubicacion_id uuid) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare config public.stock_configuracion; faltantes jsonb; eventos bigint; con_movimientos bigint;
begin
 if auth.uid() is null or public.es_administrador() is not true then
  raise exception 'Solo administración activa' using errcode='42501'; end if;
 select * into config from public.stock_configuracion where ubicacion_id=p_ubicacion_id;
 if not found then raise exception 'Ubicación sin configuración' using errcode='PT410'; end if;
 select coalesce(jsonb_agg(p.id order by p.id),'[]'::jsonb) into faltantes from public.productos p where
 not exists(select 1 from public.stock_actual s where s.ubicacion_id=p_ubicacion_id and s.producto_id=p.id)
 or not exists(select 1 from public.stock_movimientos m where m.ubicacion_id=p_ubicacion_id and m.producto_id=p.id and m.tipo='stock_inicial');
 select count(*),count(*) filter(where exists(select 1 from public.stock_movimientos m where m.evento_id=e.id))
 into eventos,con_movimientos from public.stock_eventos e where e.ubicacion_id=p_ubicacion_id;
 return jsonb_build_object('configuracion',to_jsonb(config),'productos_sin_inicializar',faltantes,
  'cantidad_sin_inicializar',jsonb_array_length(faltantes),'eventos',eventos,
  'eventos_con_movimientos',con_movimientos,'eventos_sin_movimientos',eventos-con_movimientos);
end;$$;

revoke all on function public.stock_normalizar_solicitud(jsonb),
 public.stock_registrar_evento(uuid,text,uuid,uuid,jsonb,timestamptz),
 public.stock_aplicar_deltas(uuid,uuid,jsonb),public.activar_automatizacion_stock(uuid,timestamptz),
 public.diagnosticar_automatizacion_stock(uuid) from public,anon,authenticated,service_role;
grant execute on function public.activar_automatizacion_stock(uuid,timestamptz),
 public.diagnosticar_automatizacion_stock(uuid) to authenticated;

notify pgrst,'reload schema';
commit;
