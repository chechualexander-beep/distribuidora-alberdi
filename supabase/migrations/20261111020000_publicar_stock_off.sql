-- Cierra la instalación de Stock V2 y publica el régimen APAGADO.
-- Reemplaza la publicación administrativa manual: se aplica en la misma ventana
-- que el resto de las migraciones. Stock queda sin mover existencias.
begin;
select pg_advisory_xact_lock(829001);
do $$
declare t public.stock_transicion; nuevo uuid;
begin
 select * into strict t from public.stock_transicion where singleton for update;
 if t.paso_instalacion<>3 then raise exception 'instalacion_incompleta'; end if;
 if exists(select 1 from public.stock_configuracion where automatizacion_activa) then
  raise exception 'Stock debe estar apagado';
 end if;
 if not t.mantenimiento then
  raise notice 'Stock V2 ya estaba publicado; no se cambia nada.';
  return;
 end if;
 insert into public.stock_regimenes(protocolo,automatizacion_activa,fecha_corte,actor_id,evidencia)
  values(2,false,null,null,jsonb_build_object('origen','migracion_publicar_stock_off','inventario_hash',public.stock_huella_inventario()))
  returning id into nuevo;
 update public.stock_regimenes set cerrado_at=clock_timestamp() where id=t.regimen_id;
 update public.stock_transicion set regimen_id=nuevo,mantenimiento=false,motivo=null,pausada_at=null,pausada_por=null where singleton;
end $$;
notify pgrst,'reload schema';
commit;
