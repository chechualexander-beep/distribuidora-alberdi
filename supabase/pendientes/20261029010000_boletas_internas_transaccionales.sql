-- 113A: candidate for isolated TESTING only. Never deploy automatically.
-- No backfill, renumbering, historical mutation, or client activation.
begin;
select pg_advisory_xact_lock(829001);
do $$begin
 if not exists(select 1 from public.stock_transicion where singleton and paso_instalacion=3) then
  raise exception 'protocolo_stock_no_instalado' using errcode='PT409';
 end if;
end$$;

create table public.boletas_internas_configuracion(
 singleton boolean primary key default true check(singleton),
 emision_preventa_habilitada boolean not null default false
);
insert into public.boletas_internas_configuracion default values;

create table public.comprobantes_internos(
 id uuid primary key default gen_random_uuid(),
 solicitud_id uuid not null unique,
 pedido_id uuid not null references public.pedidos(id),
 tipo text not null check(tipo in ('boleta_preventa','comprobante_venta_directa')),
 finalizacion_id uuid references public.finalizacion_pedido_solicitudes(solicitud_id),
 numero bigint not null unique check(numero>0),
 actor_id uuid not null references auth.users(id),
 regimen_id uuid not null references public.stock_regimenes(id),
 emitido_at timestamptz not null check(isfinite(emitido_at)),
 version smallint not null default 1 check(version=1),
 solicitud jsonb not null check(jsonb_typeof(solicitud)='object'),
 solicitud_hash text not null check(solicitud_hash ~ '^[0-9a-f]{64}$'),
 captura jsonb not null check(jsonb_typeof(captura)='object'),
 captura_hash text not null check(captura_hash ~ '^[0-9a-f]{64}$'),
 resultado jsonb not null check(jsonb_typeof(resultado)='object'),
 unique(pedido_id,tipo),
 check((tipo='boleta_preventa' and finalizacion_id is null) or
       (tipo='comprobante_venta_directa' and finalizacion_id is not null))
);
alter table public.boletas_internas_configuracion enable row level security;
alter table public.comprobantes_internos enable row level security;
revoke all on public.boletas_internas_configuracion,public.comprobantes_internos from public,anon,authenticated,service_role;

create function public.boleta_inmutable() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin raise exception 'boleta_inmutable' using errcode='PT409';end$$;
create trigger boleta_inmutable before update or delete or truncate on public.comprobantes_internos
 for each statement execute function public.boleta_inmutable();

-- New documents only: legacy/historical rows without a new document are untouched.
-- The existing statement-level Stock barrier obtains the global lock before these row triggers.
create function public.boleta_proteger_origen() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare doc public.comprobantes_internos; old_doc public.comprobantes_internos;
begin
 if tg_table_name='pedidos' then
  select * into doc from public.comprobantes_internos where pedido_id=old.id and tipo='boleta_preventa';
  if found and (tg_op='DELETE' or new.facturado is distinct from old.facturado or
   new.numero_comprobante is distinct from old.numero_comprobante or new.fecha_facturacion is distinct from old.fecha_facturacion
   or new.cliente_id is distinct from old.cliente_id or new.tipo_operacion is distinct from old.tipo_operacion) then
   raise exception 'boleta_origen_inmutable' using errcode='PT409';end if;
 else
  if tg_op<>'INSERT' then
   select * into old_doc from public.comprobantes_internos where pedido_id=old.pedido_id and tipo='boleta_preventa';
   if found and exists(select 1 from jsonb_array_elements(old_doc.captura->'lineas_origen') x where x->>'detalle_id'=old.id::text) then
    if tg_op='DELETE' or new.pedido_id is distinct from old.pedido_id or new.producto_id is distinct from old.producto_id or
     new.cantidad_facturada is distinct from old.cantidad_facturada or new.precio_unitario is distinct from old.precio_unitario or new.tipo_precio is distinct from old.tipo_precio then
     raise exception 'boleta_detalle_inmutable' using errcode='PT409';end if;
   end if;
  end if;
  if tg_op<>'DELETE' then
   select * into doc from public.comprobantes_internos where pedido_id=new.pedido_id and tipo='boleta_preventa';
   if found and not exists(select 1 from jsonb_array_elements(doc.captura->'lineas_origen') x where x->>'detalle_id'=new.id::text)
    and (new.agregado_en_entrega is distinct from true or coalesce(new.cantidad_facturada,0)<>0) then
    raise exception 'boleta_detalle_nuevo_no_permitido' using errcode='PT409';end if;
  end if;
 end if;
 if tg_op='DELETE' then return old;else return new;end if;
end$$;
create trigger z_boleta_origen before update or delete on public.pedidos for each row execute function public.boleta_proteger_origen();
create trigger z_boleta_detalle before insert or update or delete on public.pedido_detalles for each row execute function public.boleta_proteger_origen();

-- originals MUST enumerate every original line, including zero for removed lines.
-- added lines take price/cost from the selected server price list, never from the client.
create function public.emitir_boleta_preventa(
 p_solicitud_id uuid,p_pedido_id uuid,p_regimen_id uuid,p_originales jsonb,p_agregados jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare req jsonb; orig jsonb:='[]'; adds jsonb:='[]'; x jsonb; q numeric; ident uuid; lista text;
 h text; anterior public.comprobantes_internos; pedido public.pedidos; prod public.productos;
 det public.pedido_detalles; cliente public.clientes; actor public.usuarios;
 precio numeric; costo numeric; total numeric:=0; v_numero bigint; intentos integer:=0;
 instante timestamptz; documento uuid:=gen_random_uuid(); captura jsonb; resultado jsonb;
 lineas jsonb:='[]'; impresas jsonb:='[]';
begin
 perform public.stock_exigir_admin();
 -- Same FIRST lock as maintenance, V2 and legacy DML. No order row is locked first.
 perform pg_advisory_xact_lock(829001);
 if p_solicitud_id is null or p_pedido_id is null or p_regimen_id is null then
  raise exception 'identidad_boleta_invalida' using errcode='PT422';end if;
 if jsonb_typeof(p_originales) is distinct from 'array' or jsonb_typeof(p_agregados) is distinct from 'array'
  or jsonb_array_length(p_originales)=0 or jsonb_array_length(p_originales)>500 or jsonb_array_length(p_agregados)>500 then
  raise exception 'lineas_boleta_invalidas' using errcode='PT422';end if;
 for x in select value from jsonb_array_elements(p_originales) loop
  if jsonb_typeof(x) is distinct from 'object' or not(x ?& array['detalle_id','cantidad_facturada'])
   or exists(select 1 from jsonb_object_keys(x) k where k not in ('detalle_id','cantidad_facturada'))
   or jsonb_typeof(x->'detalle_id') is distinct from 'string' or jsonb_typeof(x->'cantidad_facturada') is distinct from 'number' then
   raise exception 'original_invalido' using errcode='PT422';end if;
  ident:=(x->>'detalle_id')::uuid;q:=(x->>'cantidad_facturada')::numeric;
  if q<0 or q>9999999999.99 or q<>round(q,2) then raise exception 'cantidad_invalida' using errcode='PT422';end if;
  orig:=orig||jsonb_build_array(jsonb_build_object('detalle_id',ident,'cantidad_facturada',trim_scale(q)));
 end loop;
 if exists(select 1 from jsonb_array_elements(orig) a group by a->>'detalle_id' having count(*)>1) then
  raise exception 'detalle_duplicado' using errcode='PT422';end if;
 select jsonb_agg(value order by value->>'detalle_id') into orig from jsonb_array_elements(orig);
 for x in select value from jsonb_array_elements(p_agregados) loop
  if jsonb_typeof(x) is distinct from 'object' or not(x ?& array['producto_id','cantidad_facturada','tipo_precio'])
   or exists(select 1 from jsonb_object_keys(x) k where k not in ('producto_id','cantidad_facturada','tipo_precio'))
   or jsonb_typeof(x->'producto_id') is distinct from 'string' or jsonb_typeof(x->'cantidad_facturada') is distinct from 'number' then
   raise exception 'agregado_invalido' using errcode='PT422';end if;
  ident:=(x->>'producto_id')::uuid;q:=(x->>'cantidad_facturada')::numeric;lista:=x->>'tipo_precio';
  if q<=0 or q>9999999999.99 or q<>round(q,2) or lista is null or lista not in ('normal','promo','interior') then
   raise exception 'agregado_invalido' using errcode='PT422';end if;
  adds:=adds||jsonb_build_array(jsonb_build_object('producto_id',ident,'cantidad_facturada',trim_scale(q),'tipo_precio',lista));
 end loop;
 if exists(select 1 from jsonb_array_elements(adds) a group by a->>'producto_id' having count(*)>1) then
  raise exception 'producto_duplicado' using errcode='PT422';end if;
 select coalesce(jsonb_agg(value order by value->>'producto_id'),'[]') into adds from jsonb_array_elements(adds);
 req:=jsonb_build_object('version',1,'tipo','boleta_preventa','pedido_id',p_pedido_id,'regimen_id',p_regimen_id,'originales',orig,'agregados',adds);
 h:=encode(sha256(convert_to(req::text,'UTF8')),'hex');
 select * into anterior from public.comprobantes_internos where solicitud_id=p_solicitud_id;
 if found then
  if anterior.actor_id is distinct from auth.uid() or anterior.solicitud is distinct from req or anterior.solicitud_hash<>h then
   raise exception 'solicitud_incompatible' using errcode='PT409';end if;
  -- Exact replay does not adopt a new regime or require operations to be open.
  return anterior.resultado;
 end if;
 perform public.stock_exigir_operativo();
 if not exists(select 1 from public.boletas_internas_configuracion where singleton and emision_preventa_habilitada) then
  raise exception 'boletas_preventa_no_habilitadas' using errcode='PT409';end if;
 if not exists(select 1 from public.stock_transicion t join public.stock_regimenes r on r.id=t.regimen_id
  where t.singleton and t.paso_instalacion=3 and t.regimen_id=p_regimen_id and r.cerrado_at is null and r.protocolo=2) then
  raise exception 'contexto_regimen_incompatible' using errcode='PT409';end if;
 select * into pedido from public.pedidos where id=p_pedido_id for update;
 if not found then raise exception 'pedido_inexistente' using errcode='PT404';end if;
 if pedido.tipo_operacion is distinct from 'pedido' then raise exception 'solo_boleta_preventa' using errcode='PT422';end if;
 if pedido.facturado or pedido.numero_comprobante is not null or pedido.fecha_facturacion is not null
  or exists(select 1 from public.comprobantes_internos where pedido_id=p_pedido_id) then
  raise exception 'pedido_ya_documentado' using errcode='PT409';end if;
 if pedido.estado in ('cancelado','anulado') or pedido.resultado_entrega is distinct from 'pendiente' or pedido.fecha_finalizacion is not null then
  raise exception 'pedido_no_facturable' using errcode='PT409';end if;
 select * into cliente from public.clientes where id=pedido.cliente_id;
 select * into actor from public.usuarios where id=auth.uid();
 if cliente.id is null or cliente.activo is distinct from true then raise exception 'cliente_inactivo' using errcode='PT422';end if;
 if (select count(*) from public.pedido_detalles where pedido_id=p_pedido_id and not agregado_en_entrega)<>jsonb_array_length(orig)
  or exists(select 1 from public.pedido_detalles where pedido_id=p_pedido_id and agregado_en_entrega) then
  raise exception 'originales_no_concordantes' using errcode='PT409';end if;
 -- Stable detail order; transaction/global barrier protects against concurrent edits/deletion.
 for x in select value from jsonb_array_elements(orig) loop
  select * into det from public.pedido_detalles where id=(x->>'detalle_id')::uuid and pedido_id=p_pedido_id and not agregado_en_entrega for update;
  if not found then raise exception 'detalle_ajeno' using errcode='PT422';end if;
  q:=(x->>'cantidad_facturada')::numeric;
  if det.cantidad_entregada<>0 or det.cantidad_no_entregada<>0 or det.importe_comision<>0 then
   raise exception 'detalle_con_gestion' using errcode='PT409';end if;
  if det.precio_unitario<0 or det.precio_unitario::text in ('NaN','Infinity','-Infinity') then
   raise exception 'precio_invalido' using errcode='PT422';end if;
  update public.pedido_detalles set cantidad_facturada=q where id=det.id;
 end loop;
 for x in select value from jsonb_array_elements(adds) loop
  if exists(select 1 from public.pedido_detalles where pedido_id=p_pedido_id and producto_id=(x->>'producto_id')::uuid) then
   raise exception 'agregado_ya_original' using errcode='PT422';end if;
  select * into prod from public.productos where id=(x->>'producto_id')::uuid;
  if not found or prod.activo is distinct from true then raise exception 'producto_inactivo' using errcode='PT422';end if;
  lista:=x->>'tipo_precio';q:=(x->>'cantidad_facturada')::numeric;
  precio:=case lista when 'normal' then prod.precio_normal when 'promo' then prod.precio_promo else prod.precio_interior end;
  costo:=coalesce(prod.costo,0);
  if precio is null or precio<0 or precio>9999999999.99 or precio::text in ('NaN','Infinity','-Infinity') then
   raise exception 'precio_invalido' using errcode='PT422';end if;
  if costo<0 or costo::text in ('NaN','Infinity','-Infinity') then
   raise exception 'costo_invalido' using errcode='PT422';end if;
  insert into public.pedido_detalles(pedido_id,producto_id,cantidad,cantidad_facturada,precio_unitario,subtotal,tipo_precio,costo_unitario)
   values(p_pedido_id,prod.id,q,q,precio,round(q*precio,2),lista,costo);
 end loop;
 select coalesce(sum(round(d.cantidad_facturada*d.precio_unitario,2)),0) into total from public.pedido_detalles d where d.pedido_id=p_pedido_id;
 if total<=0 or total>9999999999.99 then raise exception 'total_invalido' using errcode='PT422';end if;
 -- Reuse the established sequence; never reset it or rewrite historical numbers.
 loop
  v_numero:=nextval('public.numero_comprobante_seq');intentos:=intentos+1;
  exit when not exists(select 1 from public.comprobantes_internos c where c.numero=v_numero)
   and not exists(select 1 from public.pedidos p where case when btrim(p.numero_comprobante) ~ '^[0-9]+$' then btrim(p.numero_comprobante)::numeric=v_numero else false end);
  if intentos>=10000 then raise exception 'numeracion_requiere_revision' using errcode='PT409';end if;
 end loop;
 instante:=clock_timestamp();
 select jsonb_agg(jsonb_build_object('detalle_id',d.id,'producto_id',d.producto_id,'nombre',p.nombre,'codigo',p.codigo,
  'cantidad_pedida',d.cantidad,'cantidad_documentada',d.cantidad_facturada,'precio_unitario',d.precio_unitario,
  'subtotal',round(d.cantidad_facturada*d.precio_unitario,2),'tipo_precio',d.tipo_precio) order by d.id) into lineas
  from public.pedido_detalles d join public.productos p on p.id=d.producto_id where d.pedido_id=p_pedido_id;
 select coalesce(jsonb_agg(value order by value->>'detalle_id'),'[]') into impresas from jsonb_array_elements(lineas) where (value->>'cantidad_documentada')::numeric>0;
 captura:=jsonb_build_object('version',1,'naturaleza','boleta_interna_no_fiscal','tipo','boleta_preventa','numero',v_numero::text,
  'pedido_id',pedido.id,'fecha_emision',instante,'fecha_prevista',pedido.fecha_entrega,'observacion',pedido.observacion,
  'cliente',jsonb_build_object('id',cliente.id,'nombre',cliente.nombre_comercio,'direccion',cliente.direccion),
  'actor',jsonb_build_object('id',actor.id,'nombre',actor.nombre,'apellido',actor.apellido),
  'preventista_id',pedido.preventista_id,
  'preventista',(select jsonb_build_object('id',u.id,'nombre',u.nombre,'apellido',u.apellido) from public.usuarios u where u.id=pedido.preventista_id),
  'moneda','ARS','lineas',impresas,'lineas_origen',lineas,'total',total,
  'pagos',jsonb_build_object('estado','no_documentados_en_boleta_preventa','items','[]'::jsonb));
 resultado:=jsonb_build_object('version',1,'comprobante_id',documento,'solicitud_id',p_solicitud_id,'pedido_id',p_pedido_id,'numero',v_numero::text,
  'fecha_emision',instante,'total',total,'captura_hash',encode(sha256(convert_to(captura::text,'UTF8')),'hex'));
 update public.pedidos set facturado=true,fecha_facturacion=instante,numero_comprobante=v_numero::text where id=p_pedido_id;
 insert into public.comprobantes_internos(id,solicitud_id,pedido_id,tipo,numero,actor_id,regimen_id,emitido_at,solicitud,solicitud_hash,captura,captura_hash,resultado)
  values(documento,p_solicitud_id,p_pedido_id,'boleta_preventa',v_numero,auth.uid(),p_regimen_id,instante,req,h,captura,resultado->>'captura_hash',resultado);
 return resultado;
end$$;

create function public.consultar_boleta_interna(p_solicitud_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare c public.comprobantes_internos;
begin
 perform public.stock_exigir_admin();
 select * into c from public.comprobantes_internos where solicitud_id=p_solicitud_id;
 if not found then return jsonb_build_object('estado','inexistente');end if;
 return jsonb_build_object('estado','confirmada','resultado',c.resultado,'captura',c.captura,'actor_id',c.actor_id);
end$$;
-- Lookup without a local request UUID: read-only and never issues/backfills a document.
create function public.consultar_comprobante_pedido(p_pedido_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare c public.comprobantes_internos;
begin
 perform public.stock_exigir_admin();
 select * into c from public.comprobantes_internos where pedido_id=p_pedido_id and tipo='boleta_preventa';
 if not found then return jsonb_build_object('estado','sin_comprobante_nuevo');end if;
 return jsonb_build_object('estado','confirmada','resultado',c.resultado,'captura',c.captura,'actor_id',c.actor_id);
end$$;
revoke all on function public.boleta_inmutable(),public.boleta_proteger_origen(),public.emitir_boleta_preventa(uuid,uuid,uuid,jsonb,jsonb),public.consultar_boleta_interna(uuid),public.consultar_comprobante_pedido(uuid) from public,anon,authenticated,service_role;
grant execute on function public.emitir_boleta_preventa(uuid,uuid,uuid,jsonb,jsonb),public.consultar_boleta_interna(uuid),public.consultar_comprobante_pedido(uuid) to authenticated;
comment on table public.comprobantes_internos is 'Boletas internas no fiscales, inmutables. Venta directa reservada sin RPC habilitada. ARCA es un circuito separado.';
notify pgrst,'reload schema';
commit;
