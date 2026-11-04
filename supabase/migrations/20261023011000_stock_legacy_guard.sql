-- TESTING candidate only. The UUID-less legacy endpoint cannot prepare/replay
-- the protected protocol. Its private commercial body is preserved unchanged.
begin;
select pg_advisory_xact_lock(829001);
do $$begin
 if not exists(select 1 from public.stock_transicion where singleton and mantenimiento and paso_instalacion=1) then
  raise exception 'Orden de instalación inválido' using errcode='PT409';end if;
end$$;
create or replace function public.finalizar_gestion_pedido(p_pedido_id uuid,p_estado text,p_resultado_entrega text,p_motivo_no_entrega text,
 p_detalles jsonb,p_tipo_pago text,p_importe_pago numeric default null,p_medio_pago text default null)
returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 perform public.stock_exigir_admin();perform public.stock_exigir_operativo();
 raise exception 'contexto_regimen_requerido' using errcode='PT409';
end$$;
revoke all on function public.finalizar_gestion_pedido(uuid,text,text,text,jsonb,text,numeric,text) from public,anon,authenticated,service_role;
grant execute on function public.finalizar_gestion_pedido(uuid,text,text,text,jsonb,text,numeric,text) to authenticated;
update public.stock_transicion set paso_instalacion=2 where singleton;
notify pgrst,'reload schema';
commit;
