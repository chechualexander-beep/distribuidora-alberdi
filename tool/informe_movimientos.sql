-- Informe de movimientos de stock de un producto (solo lectura).
set default_transaction_read_only = on;
\pset footer off
\echo
\echo '== Stock de hoy'
select p.nombre as producto, trim_scale(coalesce(d.cantidad,0)) as deposito, trim_scale(coalesce(v.cantidad,0)) as vehiculo
from productos p
left join stock_actual d on d.producto_id=p.id and d.ubicacion_id=(select id from ubicaciones_stock where codigo='deposito_alberdi')
left join stock_actual v on v.producto_id=p.id and v.ubicacion_id=(select id from ubicaciones_stock where codigo='vehiculo')
where p.nombre ilike '%' || :'q' || '%' order by p.nombre;
\echo '== Movimientos (del más viejo al más nuevo)'
select to_char(m.created_at at time zone 'America/Argentina/Buenos_Aires','DD/MM HH24:MI') as cuando,
 p.nombre as producto, case u.codigo when 'deposito_alberdi' then 'Depósito' when 'vehiculo' then 'Vehículo' else u.codigo end as lugar,
 m.tipo, trim_scale(m.cantidad_delta) as cambio, trim_scale(m.cantidad_nueva) as queda, m.motivo,
 coalesce(nullif(trim(coalesce(us.nombre,'') || ' ' || coalesce(us.apellido,'')),''),'') as quien
from stock_movimientos m join productos p on p.id=m.producto_id join ubicaciones_stock u on u.id=m.ubicacion_id
left join usuarios us on us.id=m.usuario_id
where p.nombre ilike '%' || :'q' || '%' and m.created_at > now() - (:'dias' || ' days')::interval
order by m.created_at, m.id;
