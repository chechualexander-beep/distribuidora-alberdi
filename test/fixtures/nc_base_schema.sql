create role anon; create role authenticated; create schema auth;
create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;

create table public.clientes (id uuid default gen_random_uuid() not null primary key,nombre_comercio text not null,propietario text,telefono text,direccion text not null,localidad text,zona text,observaciones text,activo bool default true,created_at timestamptz default now(),preventista_id uuid,tipo_precio_habitual text,latitud float8,longitud float8,ubicacion_actualizada_at timestamptz,codigo_original int8,dia_visita int2);
create table public.cobros_cliente (id uuid default gen_random_uuid() not null primary key,cliente_id uuid not null,importe numeric not null,medio_pago text not null,fecha_pago timestamptz default now() not null,observacion text,created_at timestamptz default now() not null);
create table public.liquidacion_detalles (id uuid default gen_random_uuid() not null primary key,liquidacion_id uuid not null,pedido_detalle_id uuid not null,importe_comision numeric default 0 not null,created_at timestamptz default now() not null);
create table public.liquidaciones (id uuid default gen_random_uuid() not null primary key,preventista_id uuid not null,fecha_desde date not null,fecha_hasta date not null,venta_entregada numeric default 0 not null,comision_total numeric default 0 not null,estado text default 'pendiente'::text not null,fecha_pago timestamptz,created_at timestamptz default now() not null);
create table public.pedido_detalles (id uuid default gen_random_uuid() not null primary key,pedido_id uuid not null,producto_id uuid not null,cantidad numeric not null,precio_unitario numeric not null,subtotal numeric not null,created_at timestamptz default now(),tipo_precio text,cantidad_entregada numeric default 0 not null,cantidad_no_entregada numeric default 0 not null,porcentaje_comision numeric,importe_comision numeric default 0 not null,cantidad_facturada numeric,costo_unitario numeric default '0'::numeric,agregado_en_entrega bool default false not null);
create table public.pedido_pagos (id uuid default gen_random_uuid() not null primary key,created_at timestamptz default now() not null,pedido_id uuid,importe numeric,medio_pago text,fecha_pago timestamptz default now(),observacion text,cobro_id uuid);
create table public.pedidos (id uuid default gen_random_uuid() not null primary key,cliente_id uuid not null,preventista_id uuid not null,tipo_precio text not null,estado text default 'pendiente'::text not null,observaciones text,total numeric default 0 not null,created_at timestamptz default now(),updated_at timestamptz default now(),forma_pago text,resultado_entrega text default 'pendiente'::text,motivo_no_entrega text,fecha_entrega date,facturado bool default false not null,fecha_facturacion timestamptz,numero_comprobante text,tipo_operacion text default 'pedido'::text not null,observacion text,fecha_finalizacion timestamptz);
create table public.productos (id uuid default gen_random_uuid() not null primary key,codigo text,nombre text not null,descripcion text,precio_normal numeric default 0 not null,precio_promo numeric default 0 not null,precio_interior numeric default 0 not null,stock numeric default 0,activo bool default true,created_at timestamptz default now(),codigo_original int4,comision_normal numeric,comision_promo numeric,comision_interior numeric,costo numeric default 0 not null,visible_preventistas bool default true not null,tipo_margen text default 'normal'::text not null,categoria text);
create table public.usuarios (id uuid not null primary key,nombre text not null,apellido text,email text not null,rol text not null,activo bool default true,created_at timestamptz default now());
create function public.es_administrador() returns boolean language sql security definer as $$ select exists(select 1 from public.usuarios where id=auth.uid() and rol='administrador' and activo) $$;
create view public.saldos_pendientes_pedidos as  SELECT p.id AS pedido_id,
    p.cliente_id,
    c.nombre_comercio,
    p.created_at,
    p.fecha_finalizacion,
    p.resultado_entrega,
    COALESCE(sum(COALESCE(pd.cantidad_entregada, 0::numeric) * COALESCE(pd.precio_unitario, 0::numeric)), 0::numeric) AS total_entregado,
    COALESCE(( SELECT sum(pp.importe) AS sum
           FROM pedido_pagos pp
          WHERE pp.pedido_id = p.id), 0::numeric) AS total_pagado,
    GREATEST(COALESCE(sum(COALESCE(pd.cantidad_entregada, 0::numeric) * COALESCE(pd.precio_unitario, 0::numeric)), 0::numeric) - COALESCE(( SELECT sum(pp.importe) AS sum
           FROM pedido_pagos pp
          WHERE pp.pedido_id = p.id), 0::numeric), 0::numeric) AS saldo_pendiente,
    p.fecha_entrega
   FROM pedidos p
     JOIN clientes c ON c.id = p.cliente_id
     LEFT JOIN pedido_detalles pd ON pd.pedido_id = p.id
  WHERE (p.resultado_entrega = ANY (ARRAY['entregado'::text, 'parcial'::text])) AND p.estado <> 'cancelado'::text
  GROUP BY p.id, p.cliente_id, c.nombre_comercio, p.created_at, p.fecha_finalizacion, p.resultado_entrega, p.fecha_entrega;
create view public.saldos_pendientes_clientes as  SELECT c.id AS cliente_id,
    c.nombre_comercio,
    COALESCE(sum(s.total_entregado), 0::numeric) AS total_entregado,
    COALESCE(sum(LEAST(s.total_pagado, s.total_entregado)), 0::numeric) AS total_pagado,
    COALESCE(sum(s.saldo_pendiente), 0::numeric) AS saldo_pendiente,
    count(*) FILTER (WHERE s.saldo_pendiente > 0::numeric) AS cantidad_pedidos_con_saldo
   FROM clientes c
     LEFT JOIN saldos_pendientes_pedidos s ON s.cliente_id = c.id
  GROUP BY c.id, c.nombre_comercio;
CREATE OR REPLACE FUNCTION public.corregir_operacion_finalizada(p_pedido_id uuid, p_motivo text, p_detalles jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.finalizar_gestion_pedido(p_pedido_id uuid, p_estado text, p_resultado_entrega text, p_motivo_no_entrega text, p_detalles jsonb, p_tipo_pago text, p_importe_pago numeric DEFAULT NULL::numeric, p_medio_pago text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.registrar_liquidacion(p_preventista_id uuid, p_fecha_desde date, p_fecha_hasta date, p_venta_entregada numeric, p_comision_total numeric, p_detalles jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_liquidacion_id uuid;
  v_detalle jsonb;
  v_pedido_detalle_id uuid;
  v_importe_comision numeric;
begin
  -- Seguridad extra: solo administrador activo
  if not exists (
    select 1
    from public.usuarios
    where id = auth.uid()
      and rol = 'administrador'
      and activo = true
  ) then
    raise exception 'No autorizado';
  end if;

  -- Validaciones básicas
  if p_preventista_id is null then
    raise exception 'Preventista requerido';
  end if;

  if p_fecha_desde is null or p_fecha_hasta is null then
    raise exception 'Periodo requerido';
  end if;

  if p_fecha_hasta < p_fecha_desde then
    raise exception 'Periodo inválido';
  end if;

  if p_detalles is null
     or jsonb_typeof(p_detalles) <> 'array'
     or jsonb_array_length(p_detalles) = 0 then
    raise exception 'La liquidación no tiene detalles';
  end if;

  -- Crear la cabecera ya como pagada
  insert into public.liquidaciones (
    preventista_id,
    fecha_desde,
    fecha_hasta,
    venta_entregada,
    comision_total,
    estado,
    fecha_pago
  )
  values (
    p_preventista_id,
    p_fecha_desde,
    p_fecha_hasta,
    coalesce(p_venta_entregada, 0),
    coalesce(p_comision_total, 0),
    'pagada',
    now()
  )
  returning id into v_liquidacion_id;

  -- Guardar cada detalle
  for v_detalle in
    select value
    from jsonb_array_elements(p_detalles)
  loop
    v_pedido_detalle_id :=
      (v_detalle ->> 'pedido_detalle_id')::uuid;

    v_importe_comision :=
      coalesce(
        (v_detalle ->> 'importe_comision')::numeric,
        0
      );

    if v_pedido_detalle_id is null then
      raise exception 'Detalle sin pedido_detalle_id';
    end if;

    -- Verificar que pertenezca al preventista
    if not exists (
      select 1
      from public.pedido_detalles pd
      join public.pedidos p
        on p.id = pd.pedido_id
      where pd.id = v_pedido_detalle_id
        and p.preventista_id = p_preventista_id
    ) then
      raise exception
        'El detalle % no pertenece al preventista',
        v_pedido_detalle_id;
    end if;

    -- Evitar pagar dos veces
    if exists (
      select 1
      from public.liquidacion_detalles ld
      where ld.pedido_detalle_id = v_pedido_detalle_id
    ) then
      raise exception
        'El detalle % ya fue liquidado',
        v_pedido_detalle_id;
    end if;

    insert into public.liquidacion_detalles (
      liquidacion_id,
      pedido_detalle_id,
      importe_comision
    )
    values (
      v_liquidacion_id,
      v_pedido_detalle_id,
      v_importe_comision
    );
  end loop;

  return v_liquidacion_id;
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
CREATE OR REPLACE FUNCTION public.resumen_comercial(p_inicio timestamp with time zone, p_fin timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_resumen jsonb;
begin
  if public.es_administrador() is not true then
    raise exception 'Solo un administrador puede consultar el resumen comercial';
  end if;
  if p_inicio is null or p_fin is null or p_fin <= p_inicio then
    raise exception 'El período no es válido';
  end if;

  with operaciones as (
    select p.*,
      -- Operaciones históricas sin fecha de finalización conservan su
      -- fecha de entrega, interpretada como medianoche argentina.
      coalesce(p.fecha_finalizacion,
        p.fecha_entrega::timestamp at time zone 'America/Argentina/Buenos_Aires'
      ) as fecha_efectiva
    from public.pedidos p
    where p.estado not in ('cancelado', 'anulado')
  ), facturacion as (
    select coalesce(sum(coalesce(d.cantidad_facturada, 0)
      * coalesce(d.precio_unitario, 0)), 0) as preventa
    from operaciones p
    join public.pedido_detalles d on d.pedido_id = p.id
    where p.tipo_operacion = 'pedido' and p.facturado = true
      and p.fecha_facturacion >= p_inicio and p.fecha_facturacion < p_fin
  ), entregas as (
    select p.tipo_operacion, p.preventista_id,
      coalesce(d.cantidad_entregada, 0) * coalesce(d.precio_unitario, 0) as importe,
      coalesce(d.cantidad_entregada, 0) * coalesce(d.costo_unitario, 0) as costo,
      coalesce(d.importe_comision, 0) as comision
    from operaciones p
    join public.pedido_detalles d on d.pedido_id = p.id
    where p.resultado_entrega in ('entregado', 'parcial')
      and p.fecha_efectiva >= p_inicio and p.fecha_efectiva < p_fin
  ), totales_entrega as (
    select coalesce(sum(importe), 0) as total,
      coalesce(sum(importe) filter (where tipo_operacion = 'pedido'), 0) as preventa,
      coalesce(sum(importe) filter (where tipo_operacion = 'venta_directa'), 0) as directa,
      coalesce(sum(costo), 0) as costo,
      coalesce(sum(comision), 0) as comisiones
    from entregas
  ), cobros as (
    select id, importe from public.cobros_cliente
    where fecha_pago >= p_inicio and fecha_pago < p_fin
  ), aplicaciones as (
    -- La fecha que manda es la del cobro, no la del pedido pagado.
    select
      coalesce(sum(pp.importe) filter (where p.tipo_operacion = 'pedido'), 0) as preventa,
      coalesce(sum(pp.importe) filter (where p.tipo_operacion = 'venta_directa'), 0) as directa
    from cobros c
    join public.pedido_pagos pp on pp.cobro_id = c.id
    join public.pedidos p on p.id = pp.pedido_id
  ), total_cobros as (
    select coalesce(sum(importe), 0) as total from cobros
  ), comisiones_preventista as (
    select preventista_id, sum(comision) as importe
    from entregas where preventista_id is not null
    group by preventista_id
  )
  select jsonb_build_object(
    'venta_total', f.preventa + e.directa,
    'venta_preventa', f.preventa,
    'venta_directa', e.directa,
    'entrega_total', e.total,
    'entrega_preventa', e.preventa,
    'entrega_directa', e.directa,
    'entrega_sin_clasificar', e.total - e.preventa - e.directa,
    'recaudacion_total', c.total,
    'recaudacion_preventa', a.preventa,
    'recaudacion_directa', a.directa,
    'recaudacion_sin_clasificar', c.total - a.preventa - a.directa,
    'costo_mercaderia', e.costo,
    'comisiones', e.comisiones,
    'ganancia', e.total - e.costo - e.comisiones,
    'comisiones_por_preventista', coalesce((
      select jsonb_object_agg(preventista_id::text, importe)
      from comisiones_preventista
    ), '{}'::jsonb)
  ) into v_resumen
  from facturacion f cross join totales_entrega e
  cross join aplicaciones a cross join total_cobros c;

  return v_resumen;
end;
$function$
;
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

