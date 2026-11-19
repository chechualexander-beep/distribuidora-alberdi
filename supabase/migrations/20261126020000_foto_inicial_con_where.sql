-- Supabase no deja un UPDATE sin WHERE (pg_safeupdate): la foto inicial actualizaba la única
-- fila de fin_config sin condición y fallaba con "UPDATE requires a WHERE clause".
create or replace function public.fin_foto_inicial(p_id uuid, p_fecha timestamptz, p_efectivo numeric, p_billetera numeric)
returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare huella text; previo text; f timestamptz := coalesce(p_fecha, now());
begin
 perform public.fin_exigir_admin();
 huella := public.fin_huella(jsonb_build_object('f', p_fecha, 'e', p_efectivo, 'b', p_billetera));
 perform pg_advisory_xact_lock(829002);
 select m.request_hash into previo from public.fin_movimientos m where m.id = p_id;
 if previo is not null then return public.fin_previo(previo, huella, p_id); end if;
 if (select c.inicio from public.fin_config c) is not null then
  raise exception 'La foto inicial ya está hecha.' using errcode = 'PT409'; end if;
 if f > now() + interval '10 minutes' then
  raise exception 'La fecha está en el futuro.' using errcode = 'PT422'; end if;
 if coalesce(p_efectivo, -1) < 0 or coalesce(p_billetera, -1) < 0 then
  raise exception 'Escribí cuánto hay (0 si no hay nada).' using errcode = 'PT422'; end if;
 update public.fin_config set inicio = f where id;
 insert into public.fin_movimientos(id, fecha, tipo, cuenta, importe, categoria, actor_id, request_hash)
 values (p_id, f, 'saldo_inicial', 'efectivo', p_efectivo, 'Foto inicial', auth.uid(), huella),
  (md5(p_id::text || ':billetera')::uuid, f, 'saldo_inicial', 'billetera', p_billetera, 'Foto inicial',
   auth.uid(), huella);
 return jsonb_build_object('id', p_id, 'inicio', f);
end $$;
