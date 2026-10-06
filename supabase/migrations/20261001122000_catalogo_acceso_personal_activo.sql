-- Una cuenta de Auth no equivale a ser empleado de Alberdi.
-- Las políticas restrictivas se combinan con los permisos actuales por rol.
begin;
create function public.es_personal_activo() returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from public.usuarios
    where id=auth.uid() and activo is true and rol in ('administrador','preventista'))
$$;
revoke all on function public.es_personal_activo() from public,anon;
grant execute on function public.es_personal_activo() to authenticated;
do $$
declare t record;
begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and c.relname in (
      'usuarios','clientes','productos','pedidos','pedido_detalles','pedido_pagos',
      'cobros_cliente','liquidaciones','liquidacion_detalles','dispositivos_notificaciones'
    )
  loop
    execute format('alter table public.%I enable row level security',t.relname);
    execute format('create policy solo_personal_activo on public.%I as restrictive for all to authenticated using ((select public.es_personal_activo())) with check ((select public.es_personal_activo()))',t.relname);
  end loop;
end $$;
-- Estas funciones se usan desde triggers/RPC definer, nunca desde Flutter.
-- Impedir que una cuenta ajena al personal dispare notificaciones directamente.
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('enviar_notificacion_nuevo_pedido','enviar_notificacion_pedido_editado')
  loop
    execute format('revoke all on function %s from authenticated',f.signature);
  end loop;
end $$;
commit;
