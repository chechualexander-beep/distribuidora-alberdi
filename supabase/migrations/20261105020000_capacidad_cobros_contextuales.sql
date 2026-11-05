-- Administrative capability query; no commercial writes.
begin;

do $migration$
begin
 if to_regprocedure('public.registrar_pago_cliente_contextual(uuid,uuid,numeric,text,text)') is null then
  raise exception 'cobro_contextual_requerido';
 end if;
end;
$migration$;

create function public.obtener_capacidad_cobros_contextuales()
returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,public,pg_temp as $$
declare
 actor uuid:=auth.uid();
 disponible boolean;
begin
 if actor is null or public.es_administrador() is not true then
  raise exception 'Solo administración activa' using errcode='PT403';
 end if;
 select exists(
  select 1 from pg_proc f
  where f.oid=to_regprocedure('public.registrar_pago_cliente_contextual(uuid,uuid,numeric,text,text)')
    and f.prokind='f' and f.prorettype='jsonb'::regtype and f.prosecdef
    and f.provolatile='v' and f.pronargdefaults=1
    and f.proargnames=array['p_solicitud_id','p_cliente_id','p_importe','p_medio_pago','p_observacion']::text[]
    and has_function_privilege('authenticated',f.oid,'EXECUTE')
    and not has_function_privilege('anon',f.oid,'EXECUTE')
    and not has_function_privilege('service_role',f.oid,'EXECUTE')
    and position('perform public.stock_exigir_admin();' in f.prosrc)>0
 ) into disponible;
 return jsonb_build_object(
  'capacidad','cobros_contextuales','version',1,'disponible',disponible,
  'actor_id',actor,'rpc','registrar_pago_cliente_contextual');
end;
$$;
revoke all on function public.obtener_capacidad_cobros_contextuales()
 from public,anon,authenticated,service_role;
grant execute on function public.obtener_capacidad_cobros_contextuales() to authenticated;

commit;
