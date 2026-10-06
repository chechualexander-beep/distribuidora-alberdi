-- preventista_id ya garantiza la referencia a usuarios; el CHECK exige igualdad.
-- Evita una segunda relación pedidos -> usuarios que volvería ambiguos los joins
-- de versiones existentes de Alberdi en PostgREST.
alter table public.pedidos drop constraint pedidos_catalogo_preventista_id_fkey;
