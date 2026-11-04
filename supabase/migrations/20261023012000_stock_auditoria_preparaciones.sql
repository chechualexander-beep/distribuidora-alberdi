-- Administrative read-only enumeration includes preparations whose local save failed.
begin;
select pg_advisory_xact_lock(829001);
do $$begin
 if not exists(select 1 from public.stock_transicion where singleton and mantenimiento and paso_instalacion=2) then
  raise exception 'Orden de instalación inválido' using errcode='PT409';end if;
end$$;
create function public.listar_preparaciones_transicion(p_regimen_id uuid,p_despues uuid default null,p_limite integer default 100)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare t public.stock_transicion;rows jsonb;last_id uuid;more boolean;begin
 perform public.stock_exigir_admin();perform pg_advisory_xact_lock(829001);
 select * into strict t from public.stock_transicion where singleton;
 if not t.mantenimiento or t.regimen_id is distinct from p_regimen_id then raise exception 'Auditoría completa requiere la misma pausa y régimen' using errcode='PT409';end if;
 if p_limite is null or p_limite not between 1 and 200 then raise exception 'Límite inválido' using errcode='PT422';end if;
 select coalesce(jsonb_agg(jsonb_build_object('preparacion',to_jsonb(p),'confirmacion',to_jsonb(f),
  'estado',case when f.solicitud_id is not null then 'confirmada' when p.revision then 'revision' else 'preparada' end) order by p.solicitud_id),'[]') into rows
 from (select * from public.stock_preparaciones where p_despues is null or solicitud_id>p_despues order by solicitud_id limit p_limite)p
 left join public.finalizacion_pedido_solicitudes f on f.solicitud_id=p.solicitud_id;
 if jsonb_array_length(rows)>0 then last_id:=(rows->(jsonb_array_length(rows)-1)->'preparacion'->>'solicitud_id')::uuid;end if;
 select exists(select 1 from public.stock_preparaciones where solicitud_id>last_id) into more;
 return jsonb_build_object('regimen_id',t.regimen_id,'pausada_at',t.pausada_at,'solicitudes',rows,'siguiente',last_id,'hay_mas',more);
end$$;
revoke all on function public.listar_preparaciones_transicion(uuid,uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.listar_preparaciones_transicion(uuid,uuid,integer) to authenticated;
update public.stock_transicion set paso_instalacion=3 where singleton;
notify pgrst,'reload schema';
commit;
