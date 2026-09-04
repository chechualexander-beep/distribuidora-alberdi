-- ============================================================
-- NOTIFICACIONES AUTOMÁTICAS DE NUEVOS PEDIDOS
-- Distribuidora Alberdi
--
-- IMPORTANTE:
-- Esta migración NO contiene secretos.
--
-- Antes de usar el envío de notificaciones, debe existir en
-- Supabase Vault un secreto llamado:
--
--   notificaciones_webhook_key
--
-- cuyo valor sea la Secret API Key utilizada para invocar
-- la Edge Function notificar-nuevo-pedido.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Extensión necesaria para llamadas HTTP desde PostgreSQL
-- ------------------------------------------------------------

create extension if not exists pg_net;


-- ------------------------------------------------------------
-- 2. Dispositivos registrados para recibir notificaciones
-- ------------------------------------------------------------

create table if not exists public.dispositivos_notificaciones (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null
    references public.usuarios(id)
    on delete cascade,
  token text not null unique,
  plataforma text not null default 'android',
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.dispositivos_notificaciones
enable row level security;


-- ------------------------------------------------------------
-- 3. Policies RLS
-- ------------------------------------------------------------

drop policy if exists
  "Usuario puede ver sus propios dispositivos"
on public.dispositivos_notificaciones;

create policy
  "Usuario puede ver sus propios dispositivos"
on public.dispositivos_notificaciones
for select
to authenticated
using (
  usuario_id = auth.uid()
);


drop policy if exists
  "Usuario puede registrar su propio dispositivo"
on public.dispositivos_notificaciones;

create policy
  "Usuario puede registrar su propio dispositivo"
on public.dispositivos_notificaciones
for insert
to authenticated
with check (
  usuario_id = auth.uid()
);


drop policy if exists
  "Usuario puede actualizar su propio dispositivo"
on public.dispositivos_notificaciones;

create policy
  "Usuario puede actualizar su propio dispositivo"
on public.dispositivos_notificaciones
for update
to authenticated
using (
  usuario_id = auth.uid()
)
with check (
  usuario_id = auth.uid()
);


drop policy if exists
  "Usuario puede eliminar su propio dispositivo"
on public.dispositivos_notificaciones;

create policy
  "Usuario puede eliminar su propio dispositivo"
on public.dispositivos_notificaciones
for delete
to authenticated
using (
  usuario_id = auth.uid()
);


-- ------------------------------------------------------------
-- 4. Función que llama a la Edge Function
-- ------------------------------------------------------------

create or replace function public.enviar_notificacion_nuevo_pedido(
  p_pedido_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret_key text;
begin
  select decrypted_secret
  into v_secret_key
  from vault.decrypted_secrets
  where name = 'notificaciones_webhook_key'
  limit 1;

  if v_secret_key is null then
    raise exception
      'No se encontró notificaciones_webhook_key en Vault';
  end if;

  perform net.http_post(
    url :=
      'https://vmbncsqapqdyffscwfwo.supabase.co/functions/v1/notificar-nuevo-pedido',
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
$$;


-- ------------------------------------------------------------
-- 5. Función ejecutada por el trigger
--
-- Solo se notifican PREVENTAS / pedidos normales.
-- Las ventas directas quedan excluidas.
-- ------------------------------------------------------------

create or replace function public.trigger_notificar_nuevo_pedido()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.tipo_operacion = 'pedido' then
    perform public.enviar_notificacion_nuevo_pedido(new.id);
  end if;

  return new;
end;
$$;


-- ------------------------------------------------------------
-- 6. Trigger automático sobre nuevos pedidos
-- ------------------------------------------------------------

drop trigger if exists
  on_nuevo_pedido_notificar
on public.pedidos;

create trigger on_nuevo_pedido_notificar
after insert on public.pedidos
for each row
execute function public.trigger_notificar_nuevo_pedido();