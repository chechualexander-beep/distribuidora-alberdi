# 1.18.0 — Sobres de verdad, Para reponer y Resumen de productos sin trabas

Incluye la 1.16.0 (stock, etapa 2) y la 1.17.0 (negocio separado, sueldo, salud del negocio), y además:

- **Sobres de verdad**: el frasco (efectivo) y la reserva de la billetera. Cada gasto fijo dice cómo se paga. El sábado,
  "Llenar sobres" dice cuánto poner en cada uno (número fijo toda la semana) y paga tu sueldo en el mismo paso. Ya no
  hay un "apartado" que cambia todos los días: la plata libre se cuenta sola, los sobres se controlan el sábado.
- **Gastos de la casa con tu sueldo**: no van al sobre del negocio; se marcan "Ya lo pagué".
- **Para reponer** (Stock y Hoy): lo que se va a acabar antes de que llegue la próxima compra, por proveedor, con
  cuánto comprar (para una semana) y cuánto cuesta. Demora por proveedor (1 día si no se carga). Por producto: no
  avisar o mínimo propio. Gabriela lo ve sin plata y lo puede mandar por WhatsApp. Desde la lista, "Anotar compra"
  viene armada; y en toda compra cada producto dice cuánto vende por semana y para cuántos días alcanza.
- **Resumen de productos** (Reparto y Pedidos): deja de trabar la lista con muchos pedidos.

Migraciones: `20261206010000_sobres_reales`, `20261207010000_reponer_stock`. Pruebas: `test/sobres_escenario.sql`,
`test/reponer_stock_escenario.sql`, `test/finance_test.dart`, `test/reorder_test.dart`.
