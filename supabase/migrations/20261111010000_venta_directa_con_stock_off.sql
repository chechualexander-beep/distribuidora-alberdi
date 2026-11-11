-- Con Stock V2 instalado pero APAGADO, la venta directa sigue funcionando como hoy:
-- los preventistas la cargan y editan, y administración la cierra por el circuito V2
-- sin mover stock. Con Stock ENCENDIDO se mantienen las exigencias de la etapa 117.
begin;
select pg_advisory_xact_lock(829001);

create or replace function public.stock_exigir_venta_directa_v2() returns void
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 perform public.stock_exigir_operativo();
 -- Régimen OFF vigente: sin stock no hay nada que exigir.
 if exists (
  select 1 from public.stock_transicion t
  join public.stock_regimenes r on r.id=t.regimen_id
  where t.singleton and t.paso_instalacion=3 and r.protocolo=2
    and not r.automatizacion_activa and r.cerrado_at is null
 ) then
  return;
 end if;
 perform public.stock_exigir_admin();
 if not exists (
  select 1 from public.stock_transicion t
  join public.stock_regimenes r on r.id=t.regimen_id
  join public.stock_configuracion c on c.automatizacion_activa
  where t.singleton and t.paso_instalacion=3 and r.protocolo=2
    and r.automatizacion_activa and r.cerrado_at is null
    and c.integracion_version=1 and c.fecha_corte=r.fecha_corte
 ) then
  raise exception 'venta_directa_requiere_stock_v2_on' using errcode='PT409';
 end if;
end;
$$;
revoke all on function public.stock_exigir_venta_directa_v2()
 from public,anon,authenticated,service_role;

-- La fecha de corte solo existe con Stock ENCENDIDO.
do $migration$
declare
 sig regprocedure:='public.stock_base_finalizar_v2(uuid,uuid,timestamptz,text,jsonb,jsonb,text,text,numeric,text)'::regprocedure;
 antes text:='where t.singleton and p_fecha_fisica>=r.fecha_corte) then';
 despues text:='where t.singleton and (not r.automatizacion_activa or p_fecha_fisica>=r.fecha_corte)) then';
 original text;
begin
 original:=pg_get_functiondef(sig);
 if length(original)-length(replace(original,antes,''))<>length(antes) then
  raise exception 'Ancla incompatible en %',sig;
 end if;
 execute replace(original,antes,despues);
end;
$migration$;

notify pgrst,'reload schema';
commit;
