create or replace function public.finalizar_gestion_pedido(
  p_pedido_id uuid,
  p_estado text,
  p_resultado_entrega text,
  p_motivo_no_entrega text,
  p_detalles jsonb,
  p_tipo_pago text,
  p_importe_pago numeric default null,
  p_medio_pago text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cliente_id uuid;
  v_resultado_actual text;

  v_detalle jsonb;
  v_detalle_id uuid;
  v_producto_id uuid;
  v_es_agregado boolean;

  v_entregada numeric;
  v_no_entregada numeric;
  v_precio numeric;
  v_costo numeric;
  v_porcentaje numeric;
  v_importe_comision numeric;
  v_tipo_precio text;

  v_total_entregado numeric := 0;
  v_pagado_pedido numeric := 0;
  v_saldo_pedido numeric := 0;
begin
  if not public.es_administrador() then
    raise exception 'Solo un administrador puede finalizar una gestión';
  end if;

  if p_resultado_entrega not in (
    'entregado',
    'parcial',
    'no_entregado'
  ) then
    raise exception 'Resultado de entrega no válido';
  end if;

  if p_tipo_pago not in (
    'sin_pago',
    'parcial',
    'completo'
  ) then
    raise exception 'Tipo de pago no válido';
  end if;

  if p_detalles is null
     or jsonb_typeof(p_detalles) <> 'array'
     or jsonb_array_length(p_detalles) = 0 then
    raise exception 'El pedido no contiene detalles para guardar';
  end if;

  select
    p.cliente_id,
    p.resultado_entrega
  into
    v_cliente_id,
    v_resultado_actual
  from public.pedidos p
  where p.id = p_pedido_id
  for update;

  if not found then
    raise exception 'El pedido no existe';
  end if;

  if v_resultado_actual <> 'pendiente' then
    raise exception 'El pedido ya fue finalizado';
  end if;

  if p_resultado_entrega in ('parcial', 'no_entregado')
     and trim(coalesce(p_motivo_no_entrega, '')) = '' then
    raise exception
      'Debe indicar un motivo para la mercadería no entregada';
  end if;

  for v_detalle in
    select value
    from jsonb_array_elements(p_detalles)
  loop
    v_es_agregado :=
      coalesce(
        nullif(
          v_detalle->>'agregado_en_entrega',
          ''
        )::boolean,
        false
      );

    v_entregada :=
      coalesce(
        nullif(
          v_detalle->>'cantidad_entregada',
          ''
        )::numeric,
        0
      );

    v_no_entregada :=
      coalesce(
        nullif(
          v_detalle->>'cantidad_no_entregada',
          ''
        )::numeric,
        0
      );

    v_precio :=
      coalesce(
        nullif(
          v_detalle->>'precio_unitario',
          ''
        )::numeric,
        0
      );

    v_costo :=
      coalesce(
        nullif(
          v_detalle->>'costo_unitario',
          ''
        )::numeric,
        0
      );

    v_porcentaje :=
      coalesce(
        nullif(
          v_detalle->>'porcentaje_comision',
          ''
        )::numeric,
        0
      );

    v_importe_comision :=
      coalesce(
        nullif(
          v_detalle->>'importe_comision',
          ''
        )::numeric,
        0
      );

    v_tipo_precio :=
      coalesce(
        nullif(
          trim(v_detalle->>'tipo_precio'),
          ''
        ),
        'normal'
      );

    if v_entregada < 0 or v_no_entregada < 0 then
      raise exception 'Las cantidades no pueden ser negativas';
    end if;

    v_total_entregado :=
      v_total_entregado
      + (v_entregada * v_precio);

    if v_es_agregado then
      v_producto_id :=
        nullif(
          v_detalle->>'producto_id',
          ''
        )::uuid;

      if v_producto_id is null then
        raise exception
          'Falta el producto en una línea agregada durante la entrega';
      end if;

      if v_entregada <= 0 then
        raise exception
          'Un producto agregado debe tener cantidad entregada mayor que cero';
      end if;

      insert into public.pedido_detalles (
        pedido_id,
        producto_id,
        cantidad,
        cantidad_facturada,
        cantidad_entregada,
        cantidad_no_entregada,
        precio_unitario,
        subtotal,
        tipo_precio,
        costo_unitario,
        porcentaje_comision,
        importe_comision,
        agregado_en_entrega
      )
      values (
        p_pedido_id,
        v_producto_id,
        0,
        0,
        v_entregada,
        0,
        v_precio,
        0,
        v_tipo_precio,
        v_costo,
        v_porcentaje,
        v_importe_comision,
        true
      );

    else
      v_detalle_id :=
        nullif(
          v_detalle->>'id',
          ''
        )::uuid;

      if v_detalle_id is null then
        raise exception
          'Falta el ID de un detalle original';
      end if;

      update public.pedido_detalles
      set
        cantidad_entregada = v_entregada,
        cantidad_no_entregada = v_no_entregada,
        porcentaje_comision = v_porcentaje,
        importe_comision = v_importe_comision
      where id = v_detalle_id
        and pedido_id = p_pedido_id
        and agregado_en_entrega = false;

      if not found then
        raise exception
          'Uno de los detalles originales no pertenece al pedido';
      end if;
    end if;
  end loop;

  update public.pedidos
  set
    estado = p_estado,
    resultado_entrega = p_resultado_entrega,
    fecha_finalizacion = now(),
    motivo_no_entrega =
      case
        when p_resultado_entrega = 'entregado'
          then null
        else nullif(
          trim(coalesce(p_motivo_no_entrega, '')),
          ''
        )
      end
  where id = p_pedido_id;

  if p_resultado_entrega = 'no_entregado'
     or v_total_entregado <= 0 then

    if p_tipo_pago <> 'sin_pago' then
      raise exception
        'No corresponde registrar pago sin mercadería entregada';
    end if;

    return;
  end if;

  if p_tipo_pago = 'parcial' then
    if p_importe_pago is null
       or p_importe_pago <= 0 then
      raise exception
        'El importe del pago parcial debe ser mayor que cero';
    end if;

    if trim(coalesce(p_medio_pago, '')) = '' then
      raise exception 'Debe indicar el medio de pago';
    end if;

    perform 1
    from public.registrar_pago_cliente(
      v_cliente_id,
      p_importe_pago,
      p_medio_pago,
      'Pago parcial al entregar el pedido'
    );

  elsif p_tipo_pago = 'completo' then
    if trim(coalesce(p_medio_pago, '')) = '' then
      raise exception 'Debe indicar el medio de pago';
    end if;

    select coalesce(sum(pp.importe), 0)
    into v_pagado_pedido
    from public.pedido_pagos pp
    where pp.pedido_id = p_pedido_id;

    v_saldo_pedido :=
      greatest(
        v_total_entregado - v_pagado_pedido,
        0
      );

    if v_saldo_pedido > 0 then
      perform 1
      from public.registrar_pago_cliente(
        v_cliente_id,
        v_saldo_pedido,
        p_medio_pago,
        'Pago completo al entregar el pedido'
      );
    end if;
  end if;
end;
$$;

revoke all
on function public.finalizar_gestion_pedido(
  uuid,
  text,
  text,
  text,
  jsonb,
  text,
  numeric,
  text
)
from public;

revoke execute
on function public.finalizar_gestion_pedido(
  uuid,
  text,
  text,
  text,
  jsonb,
  text,
  numeric,
  text
)
from anon;

grant execute
on function public.finalizar_gestion_pedido(
  uuid,
  text,
  text,
  text,
  jsonb,
  text,
  numeric,
  text
)
to authenticated;