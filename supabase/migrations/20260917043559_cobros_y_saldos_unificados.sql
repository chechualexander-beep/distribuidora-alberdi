create sequence "public"."numero_comprobante_seq";


  create table "public"."cobros_cliente" (
    "id" uuid not null default gen_random_uuid(),
    "cliente_id" uuid not null,
    "importe" numeric not null,
    "medio_pago" text not null,
    "fecha_pago" timestamp with time zone not null default now(),
    "observacion" text,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."cobros_cliente" enable row level security;

alter table "public"."pedido_pagos" add column "cobro_id" uuid;

alter table "public"."pedidos" add column "fecha_finalizacion" timestamp with time zone;

alter table "public"."productos" add column "categoria" text;

CREATE UNIQUE INDEX cobros_cliente_pkey ON public.cobros_cliente USING btree (id);

alter table "public"."cobros_cliente" add constraint "cobros_cliente_pkey" PRIMARY KEY using index "cobros_cliente_pkey";

alter table "public"."cobros_cliente" add constraint "cobros_cliente_cliente_id_fkey" FOREIGN KEY (cliente_id) REFERENCES public.clientes(id) ON DELETE CASCADE not valid;

alter table "public"."cobros_cliente" validate constraint "cobros_cliente_cliente_id_fkey";

alter table "public"."cobros_cliente" add constraint "cobros_cliente_importe_check" CHECK ((importe > (0)::numeric)) not valid;

alter table "public"."cobros_cliente" validate constraint "cobros_cliente_importe_check";

alter table "public"."pedido_pagos" add constraint "pedido_pagos_cobro_id_fkey" FOREIGN KEY (cobro_id) REFERENCES public.cobros_cliente(id) ON DELETE SET NULL not valid;

alter table "public"."pedido_pagos" validate constraint "pedido_pagos_cobro_id_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.eliminar_pedido_pendiente(p_pedido_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_usuario_id uuid := auth.uid();
  v_preventista_id uuid;
  v_facturado boolean;
  v_resultado_entrega text;
  v_es_admin boolean;
begin
  if v_usuario_id is null then
    raise exception 'Usuario no autenticado';
  end if;

  select
    p.preventista_id,
    p.facturado,
    p.resultado_entrega
  into
    v_preventista_id,
    v_facturado,
    v_resultado_entrega
  from public.pedidos p
  where p.id = p_pedido_id;

  if not found then
    raise exception 'Pedido no encontrado';
  end if;

  select exists (
    select 1
    from public.usuarios u
    where u.id = v_usuario_id
      and u.rol = 'administrador'
      and u.activo = true
  )
  into v_es_admin;

  if not v_es_admin and v_preventista_id <> v_usuario_id then
    raise exception 'No tenés permiso para eliminar este pedido';
  end if;

  if v_facturado = true
     or v_resultado_entrega <> 'pendiente' then
    raise exception 'Solo se pueden eliminar pedidos no facturados y pendientes de entrega';
  end if;

  delete from public.liquidacion_detalles
  where pedido_detalle_id in (
    select id
    from public.pedido_detalles
    where pedido_id = p_pedido_id
  );

  delete from public.pedido_pagos
  where pedido_id = p_pedido_id;

  delete from public.pedido_detalles
  where pedido_id = p_pedido_id;

  delete from public.pedidos
  where id = p_pedido_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.registrar_pago_cliente(p_cliente_id uuid, p_importe numeric, p_medio_pago text, p_observacion text DEFAULT NULL::text)
 RETURNS TABLE(cobro_id uuid, pedido_id uuid, importe_aplicado numeric, saldo_restante numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_restante numeric := p_importe;
  v_deuda_total numeric := 0;
  v_aplicar numeric;
  v_pedido record;
  v_cobro_id uuid;
begin
  if not public.es_administrador() then
    raise exception 'Solo un administrador puede registrar pagos';
  end if;

  if p_importe is null or p_importe <= 0 then
    raise exception 'El importe debe ser mayor que cero';
  end if;

  if trim(coalesce(p_medio_pago, '')) = '' then
    raise exception 'Debe indicar un medio de pago';
  end if;

  perform 1
  from public.pedidos p
  where p.cliente_id = p_cliente_id
  for update;

  select coalesce(sum(x.saldo), 0)
  into v_deuda_total
  from (
    select greatest(
      coalesce(
        sum(
          coalesce(pd.cantidad_entregada, 0)
          * coalesce(pd.precio_unitario, 0)
        ),
        0
      )
      -
      coalesce(
        (
          select sum(pp.importe)
          from public.pedido_pagos pp
          where pp.pedido_id = p.id
        ),
        0
      ),
      0
    ) as saldo
    from public.pedidos p
    left join public.pedido_detalles pd
      on pd.pedido_id = p.id
    where p.cliente_id = p_cliente_id
      and p.resultado_entrega in ('entregado', 'parcial')
      and p.estado <> 'cancelado'
    group by p.id
  ) x;

  if v_deuda_total <= 0 then
    raise exception 'El cliente no tiene saldo pendiente';
  end if;

  if p_importe > v_deuda_total then
    raise exception
      'El pago (%) supera la deuda total del cliente (%)',
      p_importe,
      v_deuda_total;
  end if;

  insert into public.cobros_cliente (
    cliente_id,
    importe,
    medio_pago,
    fecha_pago,
    observacion
  )
  values (
    p_cliente_id,
    p_importe,
    p_medio_pago,
    now(),
    nullif(trim(coalesce(p_observacion, '')), '')
  )
  returning id into v_cobro_id;

  for v_pedido in
    select
      p.id,
      greatest(
        coalesce(
          sum(
            coalesce(pd.cantidad_entregada, 0)
            * coalesce(pd.precio_unitario, 0)
          ),
          0
        )
        -
        coalesce(
          (
            select sum(pp.importe)
            from public.pedido_pagos pp
            where pp.pedido_id = p.id
          ),
          0
        ),
        0
      ) as saldo
    from public.pedidos p
    left join public.pedido_detalles pd
      on pd.pedido_id = p.id
    where p.cliente_id = p_cliente_id
      and p.resultado_entrega in ('entregado', 'parcial')
      and p.estado <> 'cancelado'
    group by
      p.id,
      p.created_at,
      p.fecha_finalizacion
    having greatest(
      coalesce(
        sum(
          coalesce(pd.cantidad_entregada, 0)
          * coalesce(pd.precio_unitario, 0)
        ),
        0
      )
      -
      coalesce(
        (
          select sum(pp.importe)
          from public.pedido_pagos pp
          where pp.pedido_id = p.id
        ),
        0
      ),
      0
    ) > 0
    order by
      coalesce(p.fecha_finalizacion, p.created_at),
      p.created_at,
      p.id
  loop
    exit when v_restante <= 0;

    v_aplicar := least(v_restante, v_pedido.saldo);

    insert into public.pedido_pagos (
      pedido_id,
      cobro_id,
      importe,
      medio_pago,
      fecha_pago,
      observacion
    )
    values (
      v_pedido.id,
      v_cobro_id,
      v_aplicar,
      p_medio_pago,
      now(),
      'Pago distribuido automáticamente'
    );

    cobro_id := v_cobro_id;
    pedido_id := v_pedido.id;
    importe_aplicado := v_aplicar;
    saldo_restante := v_pedido.saldo - v_aplicar;

    return next;

    v_restante := v_restante - v_aplicar;
  end loop;

  if v_restante > 0 then
    raise exception 'No se pudo imputar completamente el pago';
  end if;
end;
$function$
;

create or replace view "public"."saldos_pendientes_pedidos" as  SELECT p.id AS pedido_id,
    p.cliente_id,
    c.nombre_comercio,
    p.created_at,
    p.fecha_finalizacion,
    p.resultado_entrega,
    COALESCE(sum((COALESCE(pd.cantidad_entregada, (0)::numeric) * COALESCE(pd.precio_unitario, (0)::numeric))), (0)::numeric) AS total_entregado,
    COALESCE(( SELECT sum(pp.importe) AS sum
           FROM public.pedido_pagos pp
          WHERE (pp.pedido_id = p.id)), (0)::numeric) AS total_pagado,
    GREATEST((COALESCE(sum((COALESCE(pd.cantidad_entregada, (0)::numeric) * COALESCE(pd.precio_unitario, (0)::numeric))), (0)::numeric) - COALESCE(( SELECT sum(pp.importe) AS sum
           FROM public.pedido_pagos pp
          WHERE (pp.pedido_id = p.id)), (0)::numeric)), (0)::numeric) AS saldo_pendiente,
    p.fecha_entrega
   FROM ((public.pedidos p
     JOIN public.clientes c ON ((c.id = p.cliente_id)))
     LEFT JOIN public.pedido_detalles pd ON ((pd.pedido_id = p.id)))
  WHERE ((p.resultado_entrega = ANY (ARRAY['entregado'::text, 'parcial'::text])) AND (p.estado <> 'cancelado'::text))
  GROUP BY p.id, p.cliente_id, c.nombre_comercio, p.created_at, p.fecha_finalizacion, p.resultado_entrega, p.fecha_entrega;


CREATE OR REPLACE FUNCTION public.siguiente_numero_comprobante()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.es_administrador() then
    raise exception 'Solo un administrador puede generar numeros de comprobante';
  end if;

  return nextval('public.numero_comprobante_seq')::text;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.enviar_notificacion_nuevo_pedido(p_pedido_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_secret_key text;
begin
  select decrypted_secret
  into v_secret_key
  from vault.decrypted_secrets
  where name = 'notificaciones_webhook_key'
  limit 1;

  if v_secret_key is null then
    raise exception 'No se encontró notificaciones_webhook_key en Vault';
  end if;

  perform net.http_post(
    url := 'https://vmbncsqapqdyffscwfwo.supabase.co/functions/v1/notificar-nuevo-pedido',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_secret_key
    ),
    body := jsonb_build_object(
      'pedido_id', p_pedido_id
    ),
    timeout_milliseconds := 5000
  );
end;
$function$
;



create or replace view "public"."saldos_pendientes_clientes" as  SELECT c.id AS cliente_id,
    c.nombre_comercio,
    COALESCE(sum(s.total_entregado), (0)::numeric) AS total_entregado,
    COALESCE(sum(LEAST(s.total_pagado, s.total_entregado)), (0)::numeric) AS total_pagado,
    COALESCE(sum(s.saldo_pendiente), (0)::numeric) AS saldo_pendiente,
    count(*) FILTER (WHERE (s.saldo_pendiente > (0)::numeric)) AS cantidad_pedidos_con_saldo
   FROM (public.clientes c
     LEFT JOIN public.saldos_pendientes_pedidos s ON ((s.cliente_id = c.id)))
  GROUP BY c.id, c.nombre_comercio;

alter view public.saldos_pendientes_pedidos
set (security_invoker = true);

alter view public.saldos_pendientes_clientes
set (security_invoker = true);

revoke all
on public.saldos_pendientes_pedidos
from anon;

revoke all
on public.saldos_pendientes_clientes
from anon;

revoke all
on public.saldos_pendientes_pedidos
from authenticated;

revoke all
on public.saldos_pendientes_clientes
from authenticated;

grant select
on public.saldos_pendientes_pedidos
to authenticated;

grant select
on public.saldos_pendientes_clientes
to authenticated;

grant delete on table "public"."cobros_cliente" to "anon";

grant insert on table "public"."cobros_cliente" to "anon";

grant references on table "public"."cobros_cliente" to "anon";

grant select on table "public"."cobros_cliente" to "anon";

grant trigger on table "public"."cobros_cliente" to "anon";

grant truncate on table "public"."cobros_cliente" to "anon";

grant update on table "public"."cobros_cliente" to "anon";

grant delete on table "public"."cobros_cliente" to "authenticated";

grant insert on table "public"."cobros_cliente" to "authenticated";

grant references on table "public"."cobros_cliente" to "authenticated";

grant select on table "public"."cobros_cliente" to "authenticated";

grant trigger on table "public"."cobros_cliente" to "authenticated";

grant truncate on table "public"."cobros_cliente" to "authenticated";

grant update on table "public"."cobros_cliente" to "authenticated";

grant delete on table "public"."cobros_cliente" to "service_role";

grant insert on table "public"."cobros_cliente" to "service_role";

grant references on table "public"."cobros_cliente" to "service_role";

grant select on table "public"."cobros_cliente" to "service_role";

grant trigger on table "public"."cobros_cliente" to "service_role";

grant truncate on table "public"."cobros_cliente" to "service_role";

grant update on table "public"."cobros_cliente" to "service_role";


  create policy "Administradores gestionan cobros cliente"
  on "public"."cobros_cliente"
  as permissive
  for all
  to authenticated
using (public.es_administrador())
with check (public.es_administrador());



