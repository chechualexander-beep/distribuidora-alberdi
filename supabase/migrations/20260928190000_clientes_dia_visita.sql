-- Opcional: los clientes existentes quedan sin día hasta que se les asigne.
alter table public.clientes
  add column dia_visita smallint
  constraint clientes_dia_visita_check check (dia_visita between 1 and 7);

comment on column public.clientes.dia_visita is
  'Día habitual de visita comercial: 1 lunes a 7 domingo; NULL sin asignar. Independiente del reparto.';

-- Se conservan las políticas y permisos existentes de clientes.
