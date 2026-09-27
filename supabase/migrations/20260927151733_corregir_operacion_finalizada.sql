create table if not exists public.correcciones_operacion (
  id uuid primary key default gen_random_uuid(),
  pedido_id uuid not null
  references public.pedidos(id) on delete restrict,
  usuario_id uuid not null
    references public.usuarios(id),
  motivo text not null,
  resultado_anterior text not null,
  resultado_nuevo text not null,
  total_anterior numeric(12,2) not null default 0,
  total_nuevo numeric(12,2) not null default 0,
  total_pagado numeric(12,2) not null default 0,
  detalles_antes jsonb not null default '[]'::jsonb,
  detalles_despues jsonb not null default '[]'::jsonb,
  created_at timestamp with time zone not null default now()
);

alter table public.correcciones_operacion
enable row level security;

drop policy if exists
  "Administradores ven correcciones"
on public.correcciones_operacion;

create policy
  "Administradores ven correcciones"
on public.correcciones_operacion
for select
to authenticated
using (public.es_administrador());

revoke all
on public.correcciones_operacion
from anon;

revoke insert, update, delete
on public.correcciones_operacion
from authenticated;

grant select
on public.correcciones_operacion
to authenticated;


create or replace function public.corregir_operacion_finalizada(
  p_pedido_id uuid,
  p_motivo text,
  p_detalles jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_usuario_id uuid := auth.uid();

  v_estado text;
  v_resultado_anterior text;
  v_resultado_nuevo text;
  v_motivo_no_entrega_anterior text;

  v_total_anterior numeric := 0;
  v_total_nuevo numeric := 0;
  v_total_pagado numeric := 0;
  v_detalles_antes jsonb := '[]'::jsonb;
  v_detalles_despues jsonb := '[]'::jsonb;

  v_total_original numeric := 0;
  v_entregado_original numeric := 0;
  v_entregado_general numeric := 0;

  v_detalle jsonb;
  v_detalle_id uuid;
  v_producto_id uuid;

  v_es_agregado boolean;
  v_cantidad_base numeric;
  v_entregada numeric;

  v_precio numeric;
  v_costo numeric;
  v_porcentaje numeric;
  v_tipo_precio text;
begin
  if v_usuario_id is null then
    raise exception 'Usuario no autenticado';
  end if;

  if not public.es_administrador() then
    raise exception
      'Solo un administrador puede corregir una operación finalizada';
  end if;

  if trim(coalesce(p_motivo, '')) = '' then
    raise exception
      'Debe indicar el motivo de la corrección';
  end if;

  if p_detalles is null
     or jsonb_typeof(p_detalles) <> 'array'
     or jsonb_array_length(p_detalles) = 0 then
    raise exception
      'La operación debe contener detalles';
  end if;

  select
  p.estado,
  p.resultado_entrega,
  p.motivo_no_entrega
into
  v_estado,
  v_resultado_anterior,
  v_motivo_no_entrega_anterior
from public.pedidos p
  where p.id = p_pedido_id
  for update;

  if not found then
    raise exception 'Pedido no encontrado';
  end if;

  if v_estado = 'cancelado' then
    raise exception
      'Una operación cancelada no puede corregirse';
  end if;

  if v_resultado_anterior not in (
    'entregado',
    'parcial',
    'no_entregado'
  ) then
    raise exception
      'La operación todavía no está finalizada';
  end if;

  -- Bloquear los detalles mientras se realiza la corrección.
  perform 1
  from public.pedido_detalles pd
  where pd.pedido_id = p_pedido_id
  for update;

  -- Si alguna comisión de este pedido ya entró en una liquidación,
  -- no permitimos modificar la operación.
  if exists (
    select 1
    from public.liquidacion_detalles ld
    join public.pedido_detalles pd
      on pd.id = ld.pedido_detalle_id
    where pd.pedido_id = p_pedido_id
  ) then
    raise exception
      'La operación contiene comisiones ya liquidadas y no puede corregirse';
  end if;

  -- Total que tenía la operación antes de la corrección.
  select coalesce(
    sum(
      coalesce(pd.cantidad_entregada, 0)
      * coalesce(pd.precio_unitario, 0)
    ),
    0
  )
  into v_total_anterior
  from public.pedido_detalles pd
  where pd.pedido_id = p_pedido_id;

  -- Dinero ya aplicado específicamente a este pedido.
  select coalesce(sum(pp.importe), 0)
  into v_total_pagado
  from public.pedido_pagos pp
  where pp.pedido_id = p_pedido_id;
  select coalesce(
  jsonb_agg(
    jsonb_build_object(
      'id', pd.id,
      'producto_id', pd.producto_id,
      'producto_nombre', pr.nombre,
      'cantidad', pd.cantidad,
      'cantidad_facturada', pd.cantidad_facturada,
      'cantidad_entregada', pd.cantidad_entregada,
      'cantidad_no_entregada', pd.cantidad_no_entregada,
      'precio_unitario', pd.precio_unitario,
      'tipo_precio', pd.tipo_precio,
      'costo_unitario', pd.costo_unitario,
      'porcentaje_comision', pd.porcentaje_comision,
      'importe_comision', pd.importe_comision,
      'agregado_en_entrega', pd.agregado_en_entrega
    )
    order by pd.created_at, pd.id
  ),
  '[]'::jsonb
)
into v_detalles_antes
from public.pedido_detalles pd
left join public.productos pr
  on pr.id = pd.producto_id
where pd.pedido_id = p_pedido_id;

-- Evitar que una misma línea existente llegue duplicada.
if exists (
  select 1
  from (
    select
      nullif(trim(d->>'id'), '')::uuid as detalle_id,
      count(*) as cantidad
    from jsonb_array_elements(p_detalles) d
    where nullif(trim(d->>'id'), '') is not null
    group by nullif(trim(d->>'id'), '')::uuid
    having count(*) > 1
  ) duplicados
) then
  raise exception
    'La corrección contiene líneas duplicadas';
end if;

  -- Exigir que Flutter envíe todos los detalles que ya existen.
  -- Así evitamos modificar solamente una parte del pedido por error.
  if exists (
    select 1
    from public.pedido_detalles pd
    where pd.pedido_id = p_pedido_id
      and not exists (
        select 1
        from jsonb_array_elements(p_detalles) d
        where nullif(trim(d->>'id'), '')::uuid = pd.id
      )
  ) then
    raise exception
      'Faltan líneas existentes de la operación en la corrección';
  end if;

  for v_detalle in
    select value
    from jsonb_array_elements(p_detalles)
  loop
    v_detalle_id :=
      nullif(
        trim(v_detalle->>'id'),
        ''
      )::uuid;

    v_entregada :=
      coalesce(
        nullif(
          trim(v_detalle->>'cantidad_entregada'),
          ''
        )::numeric,
        0
      );

    if v_entregada < 0 then
      raise exception
        'Las cantidades entregadas no pueden ser negativas';
    end if;

    if v_detalle_id is not null then

      -- Línea que ya existía en el pedido.
      select
        pd.agregado_en_entrega,
        case
          when pd.cantidad_facturada is not null
            then pd.cantidad_facturada
          else pd.cantidad
        end,
        pd.precio_unitario,
        coalesce(pd.costo_unitario, 0),
        coalesce(pd.porcentaje_comision, 0),
        coalesce(pd.tipo_precio, 'normal')
      into
        v_es_agregado,
        v_cantidad_base,
        v_precio,
        v_costo,
        v_porcentaje,
        v_tipo_precio
      from public.pedido_detalles pd
      where pd.id = v_detalle_id
        and pd.pedido_id = p_pedido_id
      for update;

      if not found then
        raise exception
          'Uno de los detalles no pertenece a la operación';
      end if;

      if not v_es_agregado
         and v_entregada > v_cantidad_base then
        raise exception
          'La cantidad entregada supera la cantidad original/facturada';
      end if;

      update public.pedido_detalles
      set
        cantidad_entregada = v_entregada,
        cantidad_no_entregada =
          case
            when v_es_agregado then 0
            else greatest(v_cantidad_base - v_entregada, 0)
          end,
        importe_comision =
          v_entregada
          * v_precio
          * v_porcentaje
          / 100
      where id = v_detalle_id;

    else

      -- Producto nuevo agregado durante la corrección.
      v_producto_id :=
        nullif(
          trim(v_detalle->>'producto_id'),
          ''
        )::uuid;

      v_precio :=
        coalesce(
          nullif(
            trim(v_detalle->>'precio_unitario'),
            ''
          )::numeric,
          0
        );

      v_costo :=
        coalesce(
          nullif(
            trim(v_detalle->>'costo_unitario'),
            ''
          )::numeric,
          0
        );

      v_porcentaje :=
        coalesce(
          nullif(
            trim(v_detalle->>'porcentaje_comision'),
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

      if v_producto_id is null then
        raise exception
          'Falta el producto de una línea nueva';
      end if;

      if v_entregada <= 0 then
        raise exception
          'Un producto nuevo debe tener cantidad entregada mayor que cero';
      end if;

      if v_precio < 0
         or v_costo < 0
         or v_porcentaje < 0 then
        raise exception
          'Precio, costo o comisión inválidos';
      end if;

      if v_tipo_precio not in (
        'normal',
        'promo',
        'interior'
      ) then
        raise exception
          'Tipo de precio inválido';
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
        v_entregada
          * v_precio
          * v_porcentaje
          / 100,
        true
      );
    end if;
  end loop;

  -- Calcular la nueva realidad de la entrega.
  select
    coalesce(
      sum(
        pd.cantidad_entregada
        * pd.precio_unitario
      ),
      0
    ),
    coalesce(
      sum(pd.cantidad_entregada),
      0
    ),
    coalesce(
      sum(
        case
          when pd.agregado_en_entrega = false
            then case
              when pd.cantidad_facturada is not null
                then pd.cantidad_facturada
              else pd.cantidad
            end
          else 0
        end
      ),
      0
    ),
    coalesce(
      sum(
        case
          when pd.agregado_en_entrega = false
            then pd.cantidad_entregada
          else 0
        end
      ),
      0
    )
  into
    v_total_nuevo,
    v_entregado_general,
    v_total_original,
    v_entregado_original
  from public.pedido_detalles pd
  where pd.pedido_id = p_pedido_id;

  -- Por ahora no admitimos que una corrección genere
  -- dinero a favor del cliente.
  if v_total_nuevo < v_total_pagado then
    raise exception
      'El total corregido (%) no puede ser menor que el importe ya pagado (%). Requiere devolución o saldo a favor.',
      v_total_nuevo,
      v_total_pagado;
  end if;

  if v_entregado_general <= 0 then
    v_resultado_nuevo := 'no_entregado';
  elsif v_entregado_original >= v_total_original then
    v_resultado_nuevo := 'entregado';
  else
    v_resultado_nuevo := 'parcial';
  end if;
  select coalesce(
  jsonb_agg(
    jsonb_build_object(
      'id', pd.id,
      'producto_id', pd.producto_id,
      'producto_nombre', pr.nombre,
      'cantidad', pd.cantidad,
      'cantidad_facturada', pd.cantidad_facturada,
      'cantidad_entregada', pd.cantidad_entregada,
      'cantidad_no_entregada', pd.cantidad_no_entregada,
      'precio_unitario', pd.precio_unitario,
      'tipo_precio', pd.tipo_precio,
      'costo_unitario', pd.costo_unitario,
      'porcentaje_comision', pd.porcentaje_comision,
      'importe_comision', pd.importe_comision,
      'agregado_en_entrega', pd.agregado_en_entrega
    )
    order by pd.created_at, pd.id
  ),
  '[]'::jsonb
)
into v_detalles_despues
from public.pedido_detalles pd
left join public.productos pr
  on pr.id = pd.producto_id
where pd.pedido_id = p_pedido_id;

  update public.pedidos
set
  resultado_entrega = v_resultado_nuevo,
  motivo_no_entrega =
    case
      when v_resultado_nuevo = 'entregado'
        then null
      when v_motivo_no_entrega_anterior is not null
           and trim(v_motivo_no_entrega_anterior) <> ''
        then v_motivo_no_entrega_anterior
      else trim(p_motivo)
    end
where id = p_pedido_id;

  insert into public.correcciones_operacion (
  pedido_id,
  usuario_id,
  motivo,
  resultado_anterior,
  resultado_nuevo,
  total_anterior,
  total_nuevo,
  total_pagado,
  detalles_antes,
  detalles_despues
)
  values (
    p_pedido_id,
    v_usuario_id,
    trim(p_motivo),
    v_resultado_anterior,
    v_resultado_nuevo,
    v_total_anterior,
    v_total_nuevo,
    v_total_pagado,
    v_detalles_antes,
v_detalles_despues
  );

  return jsonb_build_object(
    'pedido_id', p_pedido_id,
    'resultado_anterior', v_resultado_anterior,
    'resultado_nuevo', v_resultado_nuevo,
    'total_anterior', v_total_anterior,
    'total_nuevo', v_total_nuevo,
    'total_pagado', v_total_pagado,
    'saldo_nuevo',
      greatest(v_total_nuevo - v_total_pagado, 0)
  );
end;
$function$;


revoke all
on function public.corregir_operacion_finalizada(
  uuid,
  text,
  jsonb
)
from public;

revoke execute
on function public.corregir_operacion_finalizada(
  uuid,
  text,
  jsonb
)
from anon;

grant execute
on function public.corregir_operacion_finalizada(
  uuid,
  text,
  jsonb
)
to authenticated;