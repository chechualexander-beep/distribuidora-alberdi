-- Escenario: ayuda en el depósito y lista de carga compartida (todo se deshace).
\set ON_ERROR_STOP 1
begin;
select u.id as adm, u.nombre as adm_nombre from usuarios u where u.rol='administrador' and u.activo order by u.id limit 1 \gset
select u.id as gp, u.nombre as gp_nombre from usuarios u where u.rol='preventista' and u.activo order by u.id limit 1 \gset
select id as pa from productos where activo order by nombre limit 1 \gset
select id as pb from productos where activo and id<>:'pa' order by nombre limit 1 \gset
select id as veh from ubicaciones_stock where codigo='vehiculo' \gset
select id as dep from ubicaciones_stock where codigo='deposito_alberdi' \gset
set session_replication_role = replica;
delete from stock_movimientos where producto_id in (:'pa',:'pb');
delete from stock_actual where producto_id in (:'pa',:'pb');
delete from stock_traspaso_lineas;
update productos set control_stock=true, se_compra_a_pedido=false, fracciona_de=null, unidades_por_origen=null
 where id in (:'pa',:'pb');
update productos set fracciona_de=null, unidades_por_origen=null where fracciona_de in (:'pa',:'pb');
update usuarios set puede_deposito=false where rol='preventista';
update viajes_vehiculo set estado='cerrado', cerrado_at=clock_timestamp() where estado='abierto';
set session_replication_role = origin;
create temp table r(paso text, ok boolean) on commit drop;
grant all on r to authenticated;
select set_config('e.pa', :'pa', true), set_config('e.pb', :'pb', true), set_config('e.gp', :'gp', true);
set local role authenticated;

-- 1) Sin el permiso, un preventista no cuenta ni ve la lista.
select set_config('request.jwt.claim.sub', :'gp', true);
do $$ begin perform stock_contar(gen_random_uuid(), 'deposito_alberdi', jsonb_build_array(
  jsonb_build_object('producto_id', current_setting('e.pa'), 'cantidad', 1)), now()); raise exception 'debió fallar';
exception when others then if sqlerrm <> 'Solo administración o ayuda en el depósito' then raise; end if; end $$;
do $$ begin perform stock_traspaso_lista('cargar'); raise exception 'debió fallar';
exception when others then if sqlerrm <> 'Solo administración o ayuda en el depósito' then raise; end if; end $$;
-- ... ni se da el permiso a sí mismo.
do $$ begin perform habilitar_deposito(current_setting('e.gp')::uuid, true); raise exception 'debió fallar';
exception when others then if sqlerrm <> 'Solo administración activa' then raise; end if; end $$;
insert into r select 'sin_permiso', not puede_deposito();

-- 2) El administrador le da el permiso.
select set_config('request.jwt.claim.sub', :'adm', true);
do $$ begin perform habilitar_deposito(current_setting('e.gp')::uuid, true); end $$;
select count(*) = 1 as visto from stock_preventistas() where id = :'gp' and puede_deposito \gset
insert into r select 'permiso', :'visto';

-- 3) Con el permiso: ve el stock y cuenta (se aplica directo, con su nombre).
select set_config('request.jwt.claim.sub', :'gp', true);
select count(*) > 0 as ve from stock_estado() \gset
select stock_contar(gen_random_uuid(), 'deposito_alberdi', jsonb_build_array(
  jsonb_build_object('producto_id',:'pa','cantidad',4), jsonb_build_object('producto_id',:'pb','cantidad',5)),
  now() - interval '1 hour') is not null as c \gset
reset role;
insert into r select 'cuenta', :'ve' and puede_deposito()
  and (select cantidad from stock_actual where ubicacion_id=:'dep' and producto_id=:'pa')=4
  and exists(select 1 from stock_movimientos where producto_id=:'pa' and usuario_id=:'gp');
set local role authenticated;

-- 4) Lista compartida: lo que pone uno lo ve el otro, con quién marcó.
select stock_traspaso_poner('cargar', jsonb_build_array(
  jsonb_build_object('producto_id',:'pa','cantidad',2,'pedido',3,'marcada',false),
  jsonb_build_object('producto_id',:'pb','cantidad',1,'marcada',false))) is not null as p \gset
select set_config('request.jwt.claim.sub', :'adm', true);
select stock_traspaso_lista('cargar') as lista_adm \gset
select stock_traspaso_poner('cargar', jsonb_build_array(
  jsonb_build_object('producto_id',:'pa','cantidad',2,'pedido',3,'marcada',true))) is not null as m \gset
select set_config('request.jwt.claim.sub', :'gp', true);
select stock_traspaso_lista('cargar') as lista_gp \gset
insert into r select 'compartida', jsonb_array_length((:'lista_adm'::jsonb)->'lineas') = 2
  and (:'lista_adm'::jsonb)->'otros' ? :'gp_nombre'
  and exists(select 1 from jsonb_array_elements((:'lista_gp'::jsonb)->'lineas') l
   where l->>'producto_id' = :'pa' and (l->>'marcada')::boolean and l->>'marcada_por' = :'adm_nombre'
    and (l->>'pedido')::numeric = 3);

-- 5) Al subir, lo subido sale de la lista y lo demás queda.
select stock_cargar_vehiculo(gen_random_uuid(), jsonb_build_array(
  jsonb_build_object('producto_id',:'pa','cantidad',2)), now()) is not null as s \gset
select stock_traspaso_lista('cargar') as despues \gset
reset role;
insert into r select 'sube', jsonb_array_length((:'despues'::jsonb)->'lineas') = 1
  and ((:'despues'::jsonb)->'lineas'->0->>'producto_id') = :'pb'
  and (select cantidad from stock_actual where ubicacion_id=:'veh' and producto_id=:'pa')=2
  and exists(select 1 from stock_operaciones where tipo='carga_vehiculo' and actor_id=:'gp');

-- 6) Lo que quedó de otro día se descarta solo.
update stock_traspaso_lineas set cambiada_at = now() - interval '2 days' where producto_id = :'pb';
set local role authenticated;
select jsonb_array_length(stock_traspaso_lista('cargar')->'lineas') = 0 as vacia \gset
insert into r select 'otro_dia', :'vacia';

-- 7) Empezar de nuevo vacía la lista; un renglón sin nada se borra.
select stock_traspaso_poner('bajar', jsonb_build_array(jsonb_build_object('producto_id',:'pa','cantidad',1))) is not null as b \gset
select stock_traspaso_poner('bajar', jsonb_build_array(jsonb_build_object('producto_id',:'pa'))) as borrado \gset
select stock_traspaso_poner('bajar', jsonb_build_array(jsonb_build_object('producto_id',:'pb','cantidad',1))) is not null as b2 \gset
select stock_traspaso_vaciar('bajar') as vaciada \gset
insert into r select 'vaciar', jsonb_array_length((:'borrado'::jsonb)->'lineas') = 0
  and jsonb_array_length((:'vaciada'::jsonb)->'lineas') = 0;

-- 8) Las compras y el cierre del viaje siguen siendo solo del administrador.
do $$ begin perform stock_registrar_compra(gen_random_uuid(), 'deposito_alberdi', jsonb_build_array(
  jsonb_build_object('producto_id', current_setting('e.pa'), 'cantidad', 1)), now(), null, false, null);
  raise exception 'debió fallar';
exception when others then if sqlerrm <> 'Solo administración activa' then raise; end if; end $$;
select count(*) >= 0 as ped from stock_pedidos_a_entregar() \gset
select count(*) = 1 as ult from stock_ultima_carga() \gset
insert into r select 'solo_admin', :'ped' and :'ult';
reset role;

select coalesce(string_agg(paso, ', ') filter (where not ok), '') as fallas,
  bool_and(ok) and count(*) = 8 as todo_ok from r \gset
\if :todo_ok \else \echo 'FALLA en:' :'fallas' \quit \endif
rollback;
\echo ESCENARIO_OK
