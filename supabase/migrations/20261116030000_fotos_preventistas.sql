-- Fotos de productos cargadas por preventistas habilitados. Solo pueden cambiar la foto:
-- la vinculan con cambiar_foto_producto(), nunca editan la fila del producto (precios, costos).
-- Se publica directo; cada cambio queda registrado y el administrador lo revisa o deshace.
begin;

alter table public.usuarios add column if not exists puede_cargar_fotos boolean not null default false;

create function public.puede_cargar_fotos(p_usuario uuid default auth.uid()) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from public.usuarios u where u.id=p_usuario and u.activo is true
    and (u.rol='administrador' or (u.rol='preventista' and u.puede_cargar_fotos)))
$$;
revoke all on function public.puede_cargar_fotos(uuid) from public, anon, authenticated;
grant execute on function public.puede_cargar_fotos(uuid) to authenticated;

-- Subir archivos: administrador o preventista habilitado (mismas reglas de nombre que antes).
drop policy if exists fotos_productos_admin_insert on storage.objects;
create policy fotos_productos_admin_insert on storage.objects for insert to authenticated
with check (bucket_id='productos-fotos' and public.puede_cargar_fotos()
  and name ~ '^[a-f0-9-]{36}/[0-9]+\.jpg$'
  and exists(select 1 from public.productos p where p.id::text=split_part(name,'/',1)));

create table public.productos_fotos_historial (
  id bigint generated always as identity primary key,
  producto_id uuid not null references public.productos(id) on delete cascade,
  foto_anterior text,
  foto_nueva text,
  usuario_id uuid not null references public.usuarios(id),
  created_at timestamptz not null default now(),
  revisado_at timestamptz,
  revisado_por uuid
);
create index productos_fotos_historial_pendientes on public.productos_fotos_historial(created_at desc) where revisado_at is null;
alter table public.productos_fotos_historial enable row level security;
revoke all on public.productos_fotos_historial from public, anon, authenticated;

-- p_foto null quita la foto. El archivo tiene que estar ya subido para ese producto.
create function public.cambiar_foto_producto(p_producto uuid, p_foto text) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_anterior text; v_admin boolean := public.es_administrador();
begin
  if not public.puede_cargar_fotos() then
    raise exception 'No tenés permiso para cargar fotos. Pedíselo al administrador'; end if;
  select foto_path into v_anterior from public.productos where id=p_producto for update;
  if not found then raise exception 'Producto inexistente'; end if;
  if p_foto is not null and (p_foto !~ ('^' || p_producto::text || '/[0-9]+\.jpg$')
     or not exists(select 1 from storage.objects o where o.bucket_id='productos-fotos' and o.name=p_foto)) then
    raise exception 'La foto no se subió correctamente. Probá de nuevo'; end if;
  if p_foto is not distinct from v_anterior then return; end if;
  if not v_admin and (select count(*) from public.productos_fotos_historial
      where usuario_id=auth.uid() and created_at>now()-interval '1 day')>=300 then
    raise exception 'Llegaste al límite de fotos por hoy'; end if;
  update public.productos set foto_path=p_foto where id=p_producto;
  insert into public.productos_fotos_historial(producto_id,foto_anterior,foto_nueva,usuario_id,revisado_at,revisado_por)
  values(p_producto,v_anterior,p_foto,auth.uid(),
    case when v_admin then now() end, case when v_admin then auth.uid() end);
end $$;
revoke all on function public.cambiar_foto_producto(uuid,text) from public, anon, authenticated;
grant execute on function public.cambiar_foto_producto(uuid,text) to authenticated;

-- Administrador: cambios de preventistas sin revisar (últimos 60 días).
create function public.listar_fotos_recientes() returns table(
  id bigint, producto_id uuid, producto text, foto_anterior text, foto_nueva text,
  foto_actual text, usuario text, created_at timestamptz)
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if not public.es_administrador() then raise exception 'Solo un administrador puede revisar fotos'; end if;
  return query
  select h.id,h.producto_id,p.nombre,h.foto_anterior,h.foto_nueva,p.foto_path,
    trim(u.nombre || ' ' || coalesce(u.apellido,'')),h.created_at
  from public.productos_fotos_historial h
  join public.productos p on p.id=h.producto_id
  join public.usuarios u on u.id=h.usuario_id
  where h.revisado_at is null and h.created_at>now()-interval '60 days'
  order by h.created_at desc limit 300;
end $$;
revoke all on function public.listar_fotos_recientes() from public, anon, authenticated;
grant execute on function public.listar_fotos_recientes() to authenticated;

-- "Está bien" (p_deshacer=false) o "Deshacer" (vuelve a la foto anterior si sigue puesta la nueva).
create function public.revisar_foto_producto(p_id bigint, p_deshacer boolean) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare h public.productos_fotos_historial;
begin
  if not public.es_administrador() then raise exception 'Solo un administrador puede revisar fotos'; end if;
  select * into h from public.productos_fotos_historial where id=p_id and revisado_at is null for update;
  if not found then return; end if;
  if p_deshacer then
    if (select foto_path from public.productos where id=h.producto_id for update) is distinct from h.foto_nueva then
      raise exception 'La foto ya se cambió de nuevo. Revisá el cambio más reciente'; end if;
    if h.foto_anterior is not null and not exists(select 1 from storage.objects o
        where o.bucket_id='productos-fotos' and o.name=h.foto_anterior) then
      raise exception 'La foto anterior ya no existe: quitá la foto o cargá otra'; end if;
    update public.productos set foto_path=h.foto_anterior where id=h.producto_id;
    insert into public.productos_fotos_historial(producto_id,foto_anterior,foto_nueva,usuario_id,revisado_at,revisado_por)
    values(h.producto_id,h.foto_nueva,h.foto_anterior,auth.uid(),now(),auth.uid());
  end if;
  update public.productos_fotos_historial set revisado_at=now(), revisado_por=auth.uid() where id=p_id;
end $$;
revoke all on function public.revisar_foto_producto(bigint,boolean) from public, anon, authenticated;
grant execute on function public.revisar_foto_producto(bigint,boolean) to authenticated;

create function public.habilitar_carga_fotos(p_usuario uuid, p_habilitado boolean) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.es_administrador() then raise exception 'Solo un administrador puede cambiar este permiso'; end if;
  if p_habilitado is null then raise exception 'Valor inválido'; end if;
  update public.usuarios set puede_cargar_fotos=p_habilitado where id=p_usuario and rol='preventista';
  if not found then raise exception 'Elegí un preventista'; end if;
end $$;
revoke all on function public.habilitar_carga_fotos(uuid,boolean) from public, anon, authenticated;
grant execute on function public.habilitar_carga_fotos(uuid,boolean) to authenticated;

commit;
