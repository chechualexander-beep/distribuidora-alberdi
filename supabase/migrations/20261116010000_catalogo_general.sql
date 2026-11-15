-- Catálogo general: enlace sin cliente, generado por el administrador o por preventistas
-- habilitados. Precios = lista base + excepciones (igual que el catálogo del cliente).
-- Vale 7 días o hasta que se revoque. El pedido sale por WhatsApp al preventista: no
-- se crean pedidos desde este enlace. Solo RPC; las tablas no son accesibles por la API.
begin;

alter table public.usuarios add column if not exists puede_catalogo_general boolean not null default false;

create table public.catalogos_generales (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (length(trim(nombre)) between 1 and 60),
  base text not null check (base in ('normal','promo','interior')),
  categorias jsonb not null default '{}' check (jsonb_typeof(categorias)='object'),
  productos jsonb not null default '{}' check (jsonb_typeof(productos)='object'),
  whatsapp text not null check (whatsapp ~ '^[1-9][0-9]{7,14}$'),
  token_hash text not null unique,
  creado_por uuid not null references public.usuarios(id),
  created_at timestamptz not null default now(),
  vence_at timestamptz not null,
  revocado_at timestamptz,
  revocado_por uuid
);
create index catalogos_generales_creador on public.catalogos_generales(creado_por, created_at desc);
alter table public.catalogos_generales enable row level security;
revoke all on public.catalogos_generales from public, anon, authenticated;

-- Quién puede generar: administrador activo, o preventista activo habilitado por el administrador.
create function public.puede_generar_catalogo_general(p_usuario uuid default auth.uid()) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from public.usuarios u where u.id=p_usuario and u.activo is true
    and (u.rol='administrador' or (u.rol='preventista' and u.puede_catalogo_general)))
$$;
revoke all on function public.puede_generar_catalogo_general(uuid) from public, anon, authenticated;
grant execute on function public.puede_generar_catalogo_general(uuid) to authenticated;

-- Productos y precio final de un catálogo general (interna: no expone tipo de lista ni costos).
create function public.catalogo_general_productos(p_catalogo uuid)
returns table(id uuid,codigo text,nombre text,descripcion text,categoria text,precio numeric,foto_path text)
language sql stable security definer set search_path=public,pg_temp as $$
 select p.id,p.codigo,p.nombre,p.descripcion,p.categoria,
   case r.tipo when 'normal' then p.precio_normal when 'promo' then p.precio_promo else p.precio_interior end,
   p.foto_path
 from public.productos p join public.catalogos_generales c on c.id=p_catalogo
 cross join lateral (select coalesce(c.productos->>p.id::text,c.categorias->>lower(trim(p.categoria)),c.base) tipo) r
 where p.activo is true and p.visible_preventistas is true
 order by p.nombre,p.id
$$;
revoke all on function public.catalogo_general_productos(uuid) from public, anon, authenticated;

create function public.crear_catalogo_general(
  p_nombre text, p_base text, p_categorias jsonb, p_productos jsonb, p_whatsapp text
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_token text; v_id uuid; v_vence timestamptz;
begin
  if not public.puede_generar_catalogo_general() then
    raise exception 'No tenés permiso para generar catálogos generales. Pedíselo al administrador'; end if;
  if p_nombre is null or length(trim(p_nombre)) not between 1 and 60 then raise exception 'Nombre inválido (hasta 60 letras)'; end if;
  if p_base is null or p_base not in ('normal','promo','interior') then raise exception 'Lista base inválida'; end if;
  if p_whatsapp is null or p_whatsapp !~ '^[1-9][0-9]{7,14}$' then raise exception 'Número de WhatsApp inválido'; end if;
  if p_categorias is null or p_productos is null
     or jsonb_typeof(p_categorias) <> 'object' or jsonb_typeof(p_productos) <> 'object' then
    raise exception 'Configuración inválida'; end if;
  if exists (select 1 from jsonb_each_text(p_categorias) where value not in ('normal','promo','interior') or trim(key) = '' or key <> lower(trim(key)))
     or exists (select 1 from jsonb_each_text(p_productos) e where value not in ('normal','promo','interior')
       or not exists(select 1 from public.productos p where p.id::text=e.key)) then
    raise exception 'Excepciones inválidas'; end if;
  if (select count(*) from public.catalogos_generales where creado_por=auth.uid() and created_at>now()-interval '1 day')>=20 then
    raise exception 'Generaste demasiados catálogos hoy. Revocá o reutilizá uno existente'; end if;
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  v_vence := clock_timestamp() + interval '7 days';
  insert into public.catalogos_generales(nombre,base,categorias,productos,whatsapp,token_hash,creado_por,vence_at)
  values(trim(p_nombre),p_base,p_categorias,p_productos,p_whatsapp,
    encode(sha256(convert_to(v_token,'UTF8')),'hex'),auth.uid(),v_vence)
  returning id into v_id;
  return jsonb_build_object('id',v_id,'token',v_token,'vence_at',v_vence);
end $$;
revoke all on function public.crear_catalogo_general(text,text,jsonb,jsonb,text) from public, anon, authenticated;
grant execute on function public.crear_catalogo_general(text,text,jsonb,jsonb,text) to authenticated;

-- Pública (enlace). Deja de funcionar si se revoca, vence, o su creador pierde el permiso.
create function public.obtener_catalogo_general(p_token text) returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v public.catalogos_generales; v_vendedor text; v_productos jsonb;
begin
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'Enlace inválido o desactivado'; end if;
  select * into v from public.catalogos_generales
  where token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex') and revocado_at is null;
  if not found or not public.puede_generar_catalogo_general(v.creado_por) then
    raise exception 'Enlace inválido o desactivado'; end if;
  if v.vence_at <= clock_timestamp() then
    raise sqlstate 'PT410' using message='Este catálogo venció. Pedile uno nuevo a tu preventista.'; end if;
  select trim(nombre || ' ' || coalesce(apellido,'')) into v_vendedor from public.usuarios where id=v.creado_por;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'codigo',codigo,'nombre',nombre,'descripcion',descripcion,
    'categoria',categoria,'precio',precio,'foto_path',foto_path) order by nombre,id),'[]') into v_productos
  from public.catalogo_general_productos(v.id)
  where precio>0 and precio::text not in ('NaN','Infinity','-Infinity');
  return jsonb_build_object('nombre',v.nombre,'vendedor',v_vendedor,'whatsapp',v.whatsapp,
    'vence_at',v.vence_at,'productos',v_productos);
end $$;
revoke all on function public.obtener_catalogo_general(text) from public;
grant execute on function public.obtener_catalogo_general(text) to anon, authenticated;

-- Propios (preventista) o todos (administrador). Nunca devuelve el token.
create function public.listar_catalogos_generales() returns table(
  id uuid, nombre text, base text, categorias jsonb, productos jsonb, whatsapp text,
  creado_por uuid, creador text, created_at timestamptz, vence_at timestamptz,
  revocado_at timestamptz, estado text)
language sql stable security definer set search_path=public,pg_temp as $$
  select c.id,c.nombre,c.base,c.categorias,c.productos,c.whatsapp,c.creado_por,
    trim(u.nombre || ' ' || coalesce(u.apellido,'')),c.created_at,c.vence_at,c.revocado_at,
    case when c.revocado_at is not null then 'revocado'
         when c.vence_at <= clock_timestamp() then 'vencido'
         when not public.puede_generar_catalogo_general(c.creado_por) then 'sin_permiso'
         else 'activo' end
  from public.catalogos_generales c join public.usuarios u on u.id=c.creado_por
  where public.es_personal_activo() and (public.es_administrador() or c.creado_por=auth.uid())
    and c.created_at > now() - interval '60 days'
  order by c.created_at desc
$$;
revoke all on function public.listar_catalogos_generales() from public, anon, authenticated;
grant execute on function public.listar_catalogos_generales() to authenticated;

create function public.revocar_catalogo_general(p_id uuid) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.es_personal_activo() then raise exception 'Sin permiso'; end if;
  update public.catalogos_generales set revocado_at=clock_timestamp(), revocado_por=auth.uid()
  where id=p_id and revocado_at is null and (creado_por=auth.uid() or public.es_administrador());
  if not found and not exists(select 1 from public.catalogos_generales where id=p_id and revocado_at is not null
      and (creado_por=auth.uid() or public.es_administrador())) then
    raise exception 'Catálogo inexistente o sin permiso'; end if;
end $$;
revoke all on function public.revocar_catalogo_general(uuid) from public, anon, authenticated;
grant execute on function public.revocar_catalogo_general(uuid) to authenticated;

-- Solo el administrador habilita preventistas. Quitar el permiso corta sus catálogos en el acto.
create function public.habilitar_catalogo_general(p_usuario uuid, p_habilitado boolean) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.es_administrador() then raise exception 'Solo un administrador puede cambiar este permiso'; end if;
  if p_habilitado is null then raise exception 'Valor inválido'; end if;
  update public.usuarios set puede_catalogo_general=p_habilitado where id=p_usuario and rol='preventista';
  if not found then raise exception 'Elegí un preventista'; end if;
  if not p_habilitado then
    update public.catalogos_generales set revocado_at=clock_timestamp(), revocado_por=auth.uid()
    where creado_por=p_usuario and revocado_at is null;
  end if;
end $$;
revoke all on function public.habilitar_catalogo_general(uuid,boolean) from public, anon, authenticated;
grant execute on function public.habilitar_catalogo_general(uuid,boolean) to authenticated;

commit;
