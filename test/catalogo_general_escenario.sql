-- Escenario del catálogo general (se corre sobre una copia de producción, en una transacción).
\set ON_ERROR_STOP 1
begin;
select id as admin from usuarios where rol='administrador' and activo limit 1 \gset
select id as prev from usuarios where rol='preventista' and activo order by nombre limit 1 \gset
select id as prod1, lower(trim(categoria)) as cat1, precio_normal as pn, precio_promo as pp from productos
  where activo and visible_preventistas and precio_normal>0 and precio_promo>0 and categoria is not null order by nombre limit 1 \gset

-- 1) Preventista sin permiso: no puede generar.
set local role authenticated;
select set_config('request.jwt.claim.sub', :'prev', true);
do $$ begin perform crear_catalogo_general('X','normal','{}','{}','5493794000000'); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'No tenés permiso%' then raise; end if; end $$;
-- No puede habilitarse solo, ni leer la tabla.
do $$ begin perform habilitar_catalogo_general(auth.uid(), true); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Solo un administrador%' then raise; end if; end $$;
do $$ begin perform 1 from catalogos_generales; raise exception 'debió fallar';
exception when insufficient_privilege then null; end $$;
update usuarios set puede_catalogo_general=true where id=auth.uid();
reset role;
select (select puede_catalogo_general from usuarios where id=:'prev') = false as noauto \gset
\if :noauto \else \echo 'FALLA: el preventista se habilitó solo' \quit \endif

-- 2) El administrador lo habilita; el preventista genera con base normal + categoría en promo.
set local role authenticated;
select set_config('request.jwt.claim.sub', :'admin', true);
select habilitar_catalogo_general(:'prev', true);
select set_config('request.jwt.claim.sub', :'prev', true);
select crear_catalogo_general('Ofertas de la semana','normal', jsonb_build_object(:'cat1','promo'),'{}','5493794000000') as r \gset
select :'r'::jsonb->>'token' as token, :'r'::jsonb->>'id' as cid \gset
select count(*)=1 as uno from listar_catalogos_generales() where id=:'cid' and estado='activo' \gset
\if :uno \else \echo 'FALLA listar' \quit \endif

-- 3) Anónimo con el enlace: ve precios finales (la categoría en promo), WhatsApp y vendedor; nada interno.
set local role anon;
select obtener_catalogo_general(:'token') as c \gset
select (:'c'::jsonb->>'whatsapp')='5493794000000'
   and (:'c'::jsonb->>'nombre')='Ofertas de la semana'
   and (select (e->>'precio')::numeric from jsonb_array_elements(:'c'::jsonb->'productos') e where e->>'id'=:'prod1') = :pp
   and not exists(select 1 from jsonb_array_elements(:'c'::jsonb->'productos') e where e ? 'costo' or e ? 'tipo')
   as ok3 \gset
\if :ok3 \else \echo 'FALLA precios/contenido' :'c' \quit \endif
do $$ begin perform crear_catalogo_general('X','normal','{}','{}','5493794000000'); raise exception 'debió fallar';
exception when insufficient_privilege then null; end $$;
do $$ begin perform obtener_catalogo_general(repeat('f',64)); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Enlace inválido%' then raise; end if; end $$;

-- 4) Quitar el permiso corta el enlace en el acto y lo deja revocado.
set local role authenticated;
select set_config('request.jwt.claim.sub', :'admin', true);
select habilitar_catalogo_general(:'prev', false);
select set_config('e.t', :'token', true);
set local role anon;
do $$ begin perform obtener_catalogo_general(current_setting('e.t')); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Enlace inválido%' then raise; end if; end $$;
reset role;
select revocado_at is not null as rev from catalogos_generales where id=:'cid' \gset
\if :rev \else \echo 'FALLA: no quedó revocado' \quit \endif

-- 5) Admin genera uno; vencido da 410; revocado por su creador deja de andar.
set local role authenticated;
select set_config('request.jwt.claim.sub', :'admin', true);
select crear_catalogo_general('General','interior','{}','{}','5493794111111') as r2 \gset
select set_config('e.t2', :'r2'::jsonb->>'token', true);
reset role;
update catalogos_generales set vence_at=now()-interval '1 minute' where id=(:'r2'::jsonb->>'id')::uuid;
set local role anon;
do $$ begin perform obtener_catalogo_general(current_setting('e.t2')); raise exception 'debió fallar';
exception when sqlstate 'PT410' then null; end $$;
reset role;
update catalogos_generales set vence_at=now()+interval '1 day' where id=(:'r2'::jsonb->>'id')::uuid;
set local role authenticated;
select revocar_catalogo_general((:'r2'::jsonb->>'id')::uuid);
select revocar_catalogo_general((:'r2'::jsonb->>'id')::uuid); -- dos veces: no falla
set local role anon;
do $$ begin perform obtener_catalogo_general(current_setting('e.t2')); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Enlace inválido%' then raise; end if; end $$;

-- 6) Un preventista no puede revocar el de otro.
set local role authenticated;
select set_config('request.jwt.claim.sub', :'prev', true);
do $$ begin perform revocar_catalogo_general(gen_random_uuid()); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Catálogo inexistente%' then raise; end if; end $$;
rollback;
\echo ESCENARIO_OK
