-- El preventista que sale en el viaje se puede poner, cambiar o sacar mientras el viaje está
-- abierto (por si se confirmó la carga sin elegirlo). Solo informa: no cambia el stock.
create function public.stock_viaje_preventista(p_viaje_id uuid, p_preventista_id uuid default null)
returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare viaje public.viajes_vehiculo;
begin
 perform public.stock_exigir_admin(); perform public.stock_exigir_operativo();
 if p_preventista_id is not null and not exists (select 1 from public.usuarios u where u.id = p_preventista_id
   and u.activo and u.rol in ('preventista', 'administrador')) then
  raise exception 'Preventista inválido' using errcode = 'PT422'; end if;
 select * into viaje from public.viajes_vehiculo where id = p_viaje_id for update;
 if not found then raise exception 'Viaje inexistente' using errcode = 'PT404'; end if;
 if viaje.estado <> 'abierto' then raise exception 'El viaje ya está cerrado' using errcode = 'PT409'; end if;
 update public.viajes_vehiculo set preventista_id = p_preventista_id where id = viaje.id;
 return jsonb_build_object('viaje_id', viaje.id, 'preventista_id', p_preventista_id);
end $$;
revoke all on function public.stock_viaje_preventista(uuid, uuid) from public, anon;
grant execute on function public.stock_viaje_preventista(uuid, uuid) to authenticated;
