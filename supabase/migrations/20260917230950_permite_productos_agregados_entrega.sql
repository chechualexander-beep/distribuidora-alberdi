alter table public.pedido_detalles
add column if not exists agregado_en_entrega boolean
not null default false;

alter table public.pedido_detalles
drop constraint if exists pedido_detalles_cantidad_check;

alter table public.pedido_detalles
add constraint pedido_detalles_cantidad_check
check (
  (
    agregado_en_entrega = false
    and cantidad > 0
  )
  or
  (
    agregado_en_entrega = true
    and cantidad = 0
  )
);

alter table public.pedido_detalles
add constraint pedido_detalles_agregado_facturado_check
check (
  agregado_en_entrega = false
  or coalesce(cantidad_facturada, 0) = 0
);