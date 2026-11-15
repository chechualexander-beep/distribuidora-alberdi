-- Escenario: facturación en una sola operación (copia de producción o TESTING; todo se deshace).
\set ON_ERROR_STOP 1
begin;
select id as admin from usuarios where rol='administrador' and activo limit 1 \gset
select id as prev from usuarios where rol='preventista' and activo limit 1 \gset
-- Un pedido de prueba propio, para no depender de los datos reales.
select id as cli from clientes where activo limit 1 \gset
select id as p1, precio_normal as pn1 from productos where activo and precio_normal>0 order by nombre limit 1 \gset
select id as p2, precio_normal as pn2 from productos where activo and precio_normal>0 order by nombre offset 1 limit 1 \gset
select id as p3, precio_promo as pp3 from productos where activo and precio_promo>0 order by nombre offset 2 limit 1 \gset
set session_replication_role = replica;  -- crear el pedido de prueba sin disparar avisos ni barreras
insert into pedidos(cliente_id,preventista_id,tipo_precio,estado,total,tipo_operacion,resultado_entrega)
values (:'cli',:'prev','normal','pendiente',0,'pedido','pendiente') returning id as ped \gset
insert into pedido_detalles(pedido_id,producto_id,cantidad,precio_unitario,subtotal,tipo_precio)
values (:'ped',:'p1',3,:pn1,3*:pn1,'normal') returning id as d1 \gset
insert into pedido_detalles(pedido_id,producto_id,cantidad,precio_unitario,subtotal,tipo_precio)
values (:'ped',:'p2',2,:pn2,2*:pn2,'normal') returning id as d2 \gset
set session_replication_role = origin;
select last_value as seq_antes from numero_comprobante_seq \gset

set local role authenticated;
-- 1) Un preventista no puede facturar.
select set_config('request.jwt.claim.sub', :'prev', true);
select set_config('e.ped', :'ped', true); select set_config('e.d1', :'d1', true); select set_config('e.d2', :'d2', true);
do $$ begin perform facturar_pedido(gen_random_uuid(), current_setting('e.ped')::uuid,
  jsonb_build_array(jsonb_build_object('detalle_id',current_setting('e.d1'),'cantidad_facturada',3)), '[]');
  raise exception 'debió fallar'; exception when others then if sqlerrm not like 'Solo un administrador%' then raise; end if; end $$;

select set_config('request.jwt.claim.sub', :'admin', true);
-- 2) Faltan líneas: se rechaza y no cambia nada.
do $$ begin perform facturar_pedido(gen_random_uuid(), current_setting('e.ped')::uuid,
  jsonb_build_array(jsonb_build_object('detalle_id',current_setting('e.d1'),'cantidad_facturada',3)), '[]');
  raise exception 'debió fallar'; exception when others then if sqlerrm not like 'El pedido cambió%' then raise; end if; end $$;
-- 3) Precio de un agregado desactualizado: se rechaza TODO (nada a medias).
select set_config('e.p3', :'p3', true);
do $$ begin perform facturar_pedido(gen_random_uuid(), current_setting('e.ped')::uuid,
  jsonb_build_array(jsonb_build_object('detalle_id',current_setting('e.d1'),'cantidad_facturada',2),
                    jsonb_build_object('detalle_id',current_setting('e.d2'),'cantidad_facturada',0)),
  jsonb_build_array(jsonb_build_object('producto_id',current_setting('e.p3'),'tipo_precio','promo','cantidad_facturada',1,'precio_unitario',0.01)));
  raise exception 'debió fallar'; exception when others then if sqlerrm not like 'Cambió el precio%' then raise; end if; end $$;
reset role;
select (select count(*) from pedido_detalles where pedido_id=:'ped')=2
   and (select bool_and(cantidad_facturada is null or cantidad_facturada=cantidad) from pedido_detalles where pedido_id=:'ped')
   and not (select facturado from pedidos where id=:'ped') as intacto \gset
\if :intacto \else \echo 'FALLA: quedó algo a medias' \quit \endif

-- 4) Facturación correcta: cantidades, quitada en 0, agregado con precio del servidor, número y marca.
set local role authenticated;
select set_config('request.jwt.claim.sub', :'admin', true);
select gen_random_uuid() as sol \gset
select facturar_pedido(:'sol', :'ped',
  jsonb_build_array(jsonb_build_object('detalle_id',:'d1','cantidad_facturada',2),
                    jsonb_build_object('detalle_id',:'d2','cantidad_facturada',0)),
  jsonb_build_array(jsonb_build_object('producto_id',:'p3','tipo_precio','promo','cantidad_facturada',4,'precio_unitario',:pp3))) as r1 \gset
-- 5) El mismo intento repetido (corte de internet): mismo número, no factura de nuevo.
select facturar_pedido(:'sol', :'ped', '[]', '[]') as r2 \gset
reset role;
select (:'r1'::jsonb->>'numero_comprobante') = (:'r2'::jsonb->>'numero_comprobante')
   and (:'r2'::jsonb->>'repetida')::boolean
   and (select facturado and numero_comprobante = :'r1'::jsonb->>'numero_comprobante' from pedidos where id=:'ped')
   and (select cantidad_facturada from pedido_detalles where id=:'d1') = 2
   and (select cantidad_facturada from pedido_detalles where id=:'d2') = 0
   and (select count(*) from pedido_detalles where pedido_id=:'ped' and producto_id=:'p3' and cantidad_facturada=4 and precio_unitario=:pp3)=1
   and (select last_value from numero_comprobante_seq) = :seq_antes + 1 as ok \gset
\if :ok \else \echo 'FALLA facturación' :'r1' :'r2' \quit \endif
-- 6) Otro intento distinto sobre el mismo pedido: avisa que ya está facturado.
set local role authenticated;
select set_config('request.jwt.claim.sub', :'admin', true);
do $$ begin perform facturar_pedido(gen_random_uuid(), current_setting('e.ped')::uuid, '[]', '[]');
  raise exception 'debió fallar'; exception when others then if sqlerrm not like 'El pedido ya está facturado%' then raise; end if; end $$;
do $$ begin perform 1 from facturacion_solicitudes; raise exception 'debió fallar';
exception when insufficient_privilege then null; end $$;
rollback;
\echo ESCENARIO_OK
