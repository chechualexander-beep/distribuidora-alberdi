-- Las RPC del personal no deben poder invocarse desde el catálogo sin sesión.
-- Conservar los permisos existentes de authenticated y service_role.
begin;
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as signature
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in (
      'actualizar_pedido_activo', 'eliminar_pedido_pendiente',
      'enviar_notificacion_nuevo_pedido', 'enviar_notificacion_pedido_editado',
      'siguiente_numero_comprobante'
    )
  loop
    execute format('revoke all on function %s from public, anon', f.signature);
  end loop;
end $$;
commit;
