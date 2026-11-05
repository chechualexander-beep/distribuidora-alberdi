-- Local candidate. Keeps the existing payment RPC and all its consumers.
begin;
select pg_advisory_xact_lock(829001);

create table public.solicitudes_cobro_cliente (
 solicitud_id uuid primary key,
 operacion text not null check (operacion='cobro_cliente'),
 actor_id uuid not null references auth.users(id),
 cliente_id uuid not null references public.clientes(id),
 cobro_id uuid not null unique references public.cobros_cliente(id),
 payload jsonb not null,
 resultado jsonb not null,
 confirmado_at timestamptz not null default clock_timestamp()
);
alter table public.solicitudes_cobro_cliente enable row level security;
revoke all on public.solicitudes_cobro_cliente from public,anon,authenticated,service_role;

create function public.registrar_pago_cliente_contextual(
 p_solicitud_id uuid,p_cliente_id uuid,p_importe numeric,
 p_medio_pago text,p_observacion text default null)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare
 actor uuid:=auth.uid();
 medio text;
 observacion text:=nullif(btrim(p_observacion),'');
 contenido jsonb;
 anterior public.solicitudes_cobro_cliente;
 imputaciones jsonb;
 cobros uuid[];
 cobro public.cobros_cliente;
 resultado jsonb;
begin
 perform public.stock_exigir_admin();
 if actor is null or p_solicitud_id is null or p_cliente_id is null
   or p_importe is null or p_importe::text in ('NaN','Infinity','-Infinity')
   or p_importe<=0 or p_importe<>round(p_importe,2) then
  raise exception 'solicitud_cobro_invalida' using errcode='PT422';
 end if;
 medio:=case lower(btrim(p_medio_pago))
   when 'efectivo' then 'Efectivo' when 'transferencia' then 'Transferencia' end;
 if medio is null then raise exception 'medio_cobro_invalido' using errcode='PT422'; end if;
 contenido:=jsonb_build_object('cliente_id',p_cliente_id,'importe',trim_scale(p_importe),
   'medio_pago',medio,'observacion',observacion);
 -- Same first lock as legacy payments, credit allocation and finalizations.
 -- Replay precedes the maintenance barrier and never executes payment again.
 perform pg_advisory_xact_lock(829001);
 select * into anterior from public.solicitudes_cobro_cliente where solicitud_id=p_solicitud_id;
 if found then
  if anterior.actor_id is distinct from actor or anterior.payload is distinct from contenido
    or anterior.operacion<>'cobro_cliente' then
   raise exception 'solicitud_cobro_incompatible' using errcode='PT409';
  end if;
  return anterior.resultado;
 end if;
 -- Invoke the guarded public RPC, preserving its financial and Stock barriers.
 select array_agg(distinct r.cobro_id),
   jsonb_agg(jsonb_build_object('pedido_id',r.pedido_id,
     'importe_aplicado',r.importe_aplicado,'saldo_restante',r.saldo_restante) order by r.orden)
 into cobros,imputaciones
 from public.registrar_pago_cliente(p_cliente_id,p_importe,medio,observacion)
   with ordinality as r(cobro_id,pedido_id,importe_aplicado,saldo_restante,orden);
 if cardinality(cobros) is distinct from 1 or imputaciones is null
   or (select sum((x->>'importe_aplicado')::numeric) from jsonb_array_elements(imputaciones) x)
       is distinct from p_importe then
  raise exception 'resultado_cobro_incompatible' using errcode='PT409';
 end if;
 select * into strict cobro from public.cobros_cliente where id=cobros[1];
 if cobro.cliente_id is distinct from p_cliente_id or cobro.importe is distinct from p_importe
   or cobro.medio_pago is distinct from medio or cobro.observacion is distinct from observacion then
  raise exception 'resultado_cobro_incompatible' using errcode='PT409';
 end if;
 resultado:=jsonb_build_object('solicitud_id',p_solicitud_id,'operacion','cobro_cliente',
   'actor_id',actor,'cliente_id',p_cliente_id,'cobro_id',cobro.id,
   'importe',cobro.importe,'medio_pago',cobro.medio_pago,
   'observacion',cobro.observacion,'fecha_pago',cobro.fecha_pago,'imputaciones',imputaciones);
 insert into public.solicitudes_cobro_cliente
  (solicitud_id,operacion,actor_id,cliente_id,cobro_id,payload,resultado)
 values(p_solicitud_id,'cobro_cliente',actor,p_cliente_id,cobro.id,contenido,resultado);
 return resultado;
end;
$$;
revoke all on function public.registrar_pago_cliente_contextual(uuid,uuid,numeric,text,text)
 from public,anon,authenticated,service_role;
grant execute on function public.registrar_pago_cliente_contextual(uuid,uuid,numeric,text,text) to authenticated;
commit;
