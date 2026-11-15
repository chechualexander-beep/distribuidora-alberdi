-- Escenario de la presentación del catálogo (copia de producción o TESTING; todo se deshace).
\set ON_ERROR_STOP 1
begin;
select id as admin from usuarios where rol='administrador' and activo limit 1 \gset
select id as prev from usuarios where rol='preventista' and activo limit 1 \gset
select id as p1 from productos where activo and visible_preventistas order by nombre limit 1 \gset

-- Por defecto: negro y dorado, sin orden ni novedades.
set local role anon;
select obtener_presentacion_catalogo() = '{"tema":"alberdi","orden_categorias":[],"novedades":[]}'::jsonb as base \gset
\if :base \else \echo 'FALLA valores por defecto' \quit \endif
do $$ begin perform guardar_presentacion_catalogo('rojo','[]','[]'); raise exception 'debió fallar';
exception when insufficient_privilege then null; end $$;

-- Un preventista no puede cambiarla.
set local role authenticated;
select set_config('request.jwt.claim.sub', :'prev', true);
do $$ begin perform guardar_presentacion_catalogo('rojo','[]','[]'); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Solo un administrador%' then raise; end if; end $$;

-- El administrador la guarda; una novedad vencida no se publica.
select set_config('request.jwt.claim.sub', :'admin', true);
select guardar_presentacion_catalogo('azul','["snacks","bebidas"]',
  jsonb_build_array(jsonb_build_object('producto_id',:'p1','hasta',now()+interval '15 days')));
do $$ begin perform guardar_presentacion_catalogo('azul','["Snacks"]','[]'); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Orden de categorías%' then raise; end if; end $$;
do $$ begin perform guardar_presentacion_catalogo('fucsia','[]','[]'); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Color%' then raise; end if; end $$;
set local role anon;
select (obtener_presentacion_catalogo()->>'tema')='azul'
   and (obtener_presentacion_catalogo()->'orden_categorias')='["snacks","bebidas"]'::jsonb
   and (obtener_presentacion_catalogo()->'novedades')=jsonb_build_array(:'p1') as ok \gset
\if :ok \else \echo 'FALLA guardado' \quit \endif
reset role;
update catalogo_novedades set hasta=now()-interval '1 minute';
set local role anon;
select (obtener_presentacion_catalogo()->'novedades')='[]'::jsonb as vencida \gset
\if :vencida \else \echo 'FALLA novedad vencida' \quit \endif
do $$ begin perform 1 from catalogo_novedades; raise exception 'debió fallar';
exception when insufficient_privilege then null; end $$;
rollback;
\echo ESCENARIO_OK
