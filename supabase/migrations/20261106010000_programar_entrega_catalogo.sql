begin;

create function public.programar_entrega_catalogo(p_pedido_id uuid, p_fecha_entrega date)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  perform public.stock_exigir_admin();
  perform public.stock_exigir_operativo();

  if p_fecha_entrega is null or not isfinite(p_fecha_entrega) then
    raise exception 'Seleccioná una fecha de entrega válida' using errcode = 'PT422';
  end if;

  update public.pedidos p
  set fecha_entrega = p_fecha_entrega
  where p.id = p_pedido_id
    and p.origen = 'catalogo'
    and p.tipo_operacion = 'pedido'
    and p.resultado_entrega = 'pendiente'
    and p.estado not in ('cancelado', 'anulado')
    and p.fecha_entrega is null
    and not exists (
      select 1 from public.stock_preparaciones s where s.pedido_id = p.id
    );

  if not found then
    raise exception 'El pedido ya no está disponible para programar. Actualizá el detalle.'
      using errcode = 'PT409';
  end if;
end;
$$;

revoke all on function public.programar_entrega_catalogo(uuid,date)
  from public, anon, authenticated, service_role;
grant execute on function public.programar_entrega_catalogo(uuid,date) to authenticated;

commit;
