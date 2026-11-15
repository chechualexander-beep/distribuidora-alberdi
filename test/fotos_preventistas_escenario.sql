-- Escenario: fotos cargadas por preventistas (copia de producción o TESTING; todo se deshace).
\set ON_ERROR_STOP 1
begin;
select id as admin from usuarios where rol='administrador' and activo limit 1 \gset
select id as prev from usuarios where rol='preventista' and activo order by nombre limit 1 \gset
select id as prod, foto_path is null as sin_foto, coalesce(foto_path,'') as foto_original,
  precio_normal as pn from productos where activo order by nombre limit 1 \gset
-- Archivos "subidos" para la prueba.
insert into storage.objects(bucket_id,name) values ('productos-fotos', :'prod' || '/111.jpg'), ('productos-fotos', :'prod' || '/222.jpg');

-- 1) Sin permiso: no puede vincular ni habilitarse; tampoco puede tocar precios.
set local role authenticated;
select set_config('request.jwt.claim.sub', :'prev', true);
select set_config('e.p', :'prod', true);
do $$ begin perform cambiar_foto_producto(current_setting('e.p')::uuid, current_setting('e.p')||'/111.jpg'); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'No tenés permiso%' then raise; end if; end $$;
do $$ begin perform habilitar_carga_fotos(auth.uid(), true); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Solo un administrador%' then raise; end if; end $$;
update productos set precio_normal=1 where id=:'prod';
do $$ begin perform 1 from productos_fotos_historial; raise exception 'debió fallar';
exception when insufficient_privilege then null; end $$;

-- 2) Habilitado: cambia la foto; archivos de otro producto o inexistentes se rechazan.
select set_config('request.jwt.claim.sub', :'admin', true);
select habilitar_carga_fotos(:'prev', true);
select set_config('request.jwt.claim.sub', :'prev', true);
select puede_cargar_fotos() as puede \gset
\if :puede \else \echo 'FALLA permiso' \quit \endif
select cambiar_foto_producto(:'prod', :'prod' || '/111.jpg');
do $$ begin perform cambiar_foto_producto(current_setting('e.p')::uuid, current_setting('e.p')||'/999.jpg'); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'La foto no se subió%' then raise; end if; end $$;
do $$ begin perform cambiar_foto_producto(current_setting('e.p')::uuid, gen_random_uuid()::text||'/111.jpg'); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'La foto no se subió%' then raise; end if; end $$;
select cambiar_foto_producto(:'prod', :'prod' || '/222.jpg');
reset role;
select foto_path = :'prod' || '/222.jpg' and precio_normal = :pn as ok2 from productos where id=:'prod' \gset
\if :ok2 \else \echo 'FALLA cambio o precio tocado' \quit \endif

-- 3) Administrador: ve 2 cambios; deshacer el viejo falla, deshacer el último vuelve a 111.
set local role authenticated;
select set_config('request.jwt.claim.sub', :'admin', true);
select count(*)=2 as dos from listar_fotos_recientes() where producto_id=:'prod' \gset
\if :dos \else \echo 'FALLA listar' \quit \endif
select min(id) as h1, max(id) as h2 from listar_fotos_recientes() where producto_id=:'prod' \gset
select set_config('e.h1', :'h1', true);
do $$ begin perform revisar_foto_producto(current_setting('e.h1')::bigint, true); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'La foto ya se cambió%' then raise; end if; end $$;
select revisar_foto_producto(:h2, true);
select revisar_foto_producto(:h1, false);
select count(*)=0 as vacio from listar_fotos_recientes() where producto_id=:'prod' \gset
\if :vacio \else \echo 'FALLA revisión' \quit \endif
reset role;
select foto_path = :'prod' || '/111.jpg' as ok3 from productos where id=:'prod' \gset
\if :ok3 \else \echo 'FALLA deshacer' \quit \endif

-- 4) Preventista no puede revisar; quitar permiso lo bloquea.
set local role authenticated;
select set_config('request.jwt.claim.sub', :'prev', true);
do $$ begin perform listar_fotos_recientes(); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'Solo un administrador%' then raise; end if; end $$;
select set_config('request.jwt.claim.sub', :'admin', true);
select habilitar_carga_fotos(:'prev', false);
select set_config('request.jwt.claim.sub', :'prev', true);
do $$ begin perform cambiar_foto_producto(current_setting('e.p')::uuid, null); raise exception 'debió fallar';
exception when others then if sqlerrm not like 'No tenés permiso%' then raise; end if; end $$;
rollback;
\echo ESCENARIO_OK
