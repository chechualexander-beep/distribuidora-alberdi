begin;
alter table public.productos add column foto_path text
  check (foto_path is null or foto_path ~ ('^' || id::text || '/[0-9]+\.jpg$'));

-- Solo fotografías de productos; nunca documentos, precios o datos de clientes.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('productos-fotos','productos-fotos',true,307200,array['image/jpeg']);

create policy fotos_productos_admin_insert on storage.objects for insert to authenticated
with check (bucket_id='productos-fotos' and public.es_administrador()
  and name ~ '^[a-f0-9-]{36}/[0-9]+\.jpg$'
  and exists(select 1 from public.productos p where p.id::text=split_part(name,'/',1)));
create policy fotos_productos_admin_select on storage.objects for select to authenticated
using (bucket_id='productos-fotos' and public.es_administrador());
-- Reemplazar crea otra URL. Solo se pueden quitar archivos ya desvinculados.
create policy fotos_productos_admin_delete on storage.objects for delete to authenticated
using (bucket_id='productos-fotos' and public.es_administrador()
  and not exists(select 1 from public.productos p where p.foto_path=name));
create or replace function public.obtener_catalogo_cliente(p_token text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_cliente uuid; v_nombre text; v_productos jsonb; v_vence timestamptz;
begin
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'Enlace inválido o desactivado'; end if;
  select c.cliente_id,cl.nombre_comercio,c.vence_at into v_cliente,v_nombre,v_vence
  from public.catalogos_clientes c join public.clientes cl on cl.id=c.cliente_id
  join public.usuarios u on u.id=c.responsable_id and u.activo is true and u.rol='administrador'
  where c.token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex') and c.activo and cl.activo is true;
  if not found then raise exception 'Enlace inválido o desactivado'; end if;
  if v_vence <= clock_timestamp() then raise sqlstate 'PT410' using message='Este enlace venció. Pedile a la distribuidora un nuevo enlace para hacer tu pedido.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'codigo',codigo,'nombre',nombre,
    'descripcion',descripcion,'categoria',categoria,'precio',precio,'foto_path',(select p.foto_path from public.productos p where p.id=cp.id)) order by nombre,id),'[]') into v_productos
  from public.catalogo_productos_internos(v_cliente) cp
  where precio>0 and precio::text not in ('NaN','Infinity','-Infinity');
  return jsonb_build_object('nombre_comercio',v_nombre,'productos',v_productos,'vence_at',v_vence);
end $$;

commit;
