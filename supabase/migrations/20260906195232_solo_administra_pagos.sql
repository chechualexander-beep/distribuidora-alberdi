drop policy if exists
  "usuarios autenticados pueden registrar pagos de pedidos"
on public.pedido_pagos;

drop policy if exists
  "solo administradores pueden registrar pagos de pedidos"
on public.pedido_pagos;

create policy
  "solo administradores pueden registrar pagos de pedidos"
on public.pedido_pagos
for insert
to authenticated
with check (
  public.es_administrador()
);