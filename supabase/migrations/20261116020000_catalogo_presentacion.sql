-- Presentación del catálogo web (una para todos los catálogos): color, orden de categorías
-- y novedades marcadas a mano con fecha de fin. Solo la cambia el administrador.
-- La web la lee con obtener_presentacion_catalogo(); no expone precios ni datos de clientes.
begin;

create table public.catalogo_presentacion (
  id boolean primary key default true check (id),
  tema text not null default 'alberdi' check (tema in ('alberdi','rojo','azul','verde','naranja')),
  orden_categorias jsonb not null default '[]' check (jsonb_typeof(orden_categorias)='array'),
  updated_at timestamptz not null default now(),
  updated_by uuid
);
insert into public.catalogo_presentacion(id) values (true);

create table public.catalogo_novedades (
  producto_id uuid primary key references public.productos(id) on delete cascade,
  hasta timestamptz not null
);

alter table public.catalogo_presentacion enable row level security;
alter table public.catalogo_novedades enable row level security;
revoke all on public.catalogo_presentacion, public.catalogo_novedades from public, anon, authenticated;

-- Pública: la piden los sitios del catálogo junto con los productos.
create function public.obtener_presentacion_catalogo() returns jsonb
language sql stable security definer set search_path=public,pg_temp as $$
  select jsonb_build_object(
    'tema', p.tema,
    'orden_categorias', p.orden_categorias,
    'novedades', coalesce((select jsonb_agg(n.producto_id order by n.producto_id)
      from public.catalogo_novedades n join public.productos pr on pr.id=n.producto_id
      where n.hasta > clock_timestamp() and pr.activo is true and pr.visible_preventistas is true), '[]'))
  from public.catalogo_presentacion p
$$;
revoke all on function public.obtener_presentacion_catalogo() from public;
grant execute on function public.obtener_presentacion_catalogo() to anon, authenticated;

-- Para la pantalla de la app (administrador): incluye las novedades con su fecha de fin.
create function public.leer_presentacion_catalogo() returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if not public.es_administrador() then raise exception 'Solo un administrador puede ver esta configuración'; end if;
  return (select jsonb_build_object(
    'tema', p.tema,
    'orden_categorias', p.orden_categorias,
    'novedades', coalesce((select jsonb_agg(jsonb_build_object('producto_id',n.producto_id,'hasta',n.hasta) order by n.hasta)
      from public.catalogo_novedades n where n.hasta > clock_timestamp()), '[]'))
  from public.catalogo_presentacion p);
end $$;
revoke all on function public.leer_presentacion_catalogo() from public, anon, authenticated;
grant execute on function public.leer_presentacion_catalogo() to authenticated;

-- p_novedades: [{producto_id, hasta}] reemplaza la lista completa.
create function public.guardar_presentacion_catalogo(p_tema text, p_orden_categorias jsonb, p_novedades jsonb)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.es_administrador() then raise exception 'Solo un administrador puede cambiar el catálogo'; end if;
  if p_tema is null or p_tema not in ('alberdi','rojo','azul','verde','naranja') then raise exception 'Color inválido'; end if;
  if p_orden_categorias is null or jsonb_typeof(p_orden_categorias)<>'array' or jsonb_array_length(p_orden_categorias)>200
     or exists(select 1 from jsonb_array_elements(p_orden_categorias) e
       where jsonb_typeof(e)<>'string' or e#>>'{}'='' or e#>>'{}'<>lower(trim(e#>>'{}')) or length(e#>>'{}')>80) then
    raise exception 'Orden de categorías inválido'; end if;
  if p_novedades is null or jsonb_typeof(p_novedades)<>'array' or jsonb_array_length(p_novedades)>100 then
    raise exception 'Novedades inválidas (hasta 100)'; end if;
  if exists(select 1 from jsonb_array_elements(p_novedades) e
       where not exists(select 1 from public.productos p where p.id::text=e->>'producto_id')
          or (e->>'hasta') is null or (e->>'hasta')::timestamptz > clock_timestamp()+interval '1 year')
     or exists(select 1 from jsonb_array_elements(p_novedades) e group by e->>'producto_id' having count(*)>1) then
    raise exception 'Novedades inválidas'; end if;
  update public.catalogo_presentacion set tema=p_tema, orden_categorias=p_orden_categorias,
    updated_at=now(), updated_by=auth.uid() where id;
  delete from public.catalogo_novedades where true;
  insert into public.catalogo_novedades(producto_id,hasta)
  select (e->>'producto_id')::uuid,(e->>'hasta')::timestamptz from jsonb_array_elements(p_novedades) e
  where (e->>'hasta')::timestamptz > clock_timestamp();
end $$;
revoke all on function public.guardar_presentacion_catalogo(text,jsonb,jsonb) from public, anon, authenticated;
grant execute on function public.guardar_presentacion_catalogo(text,jsonb,jsonb) to authenticated;

commit;
