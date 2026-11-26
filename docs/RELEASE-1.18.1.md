# 1.18.1 — Venta directa: a mano lo que se puede vender

- En la venta directa con el viaje abierto, arriba de la lista: **Para vender · Reservado · Todo**.
  - **Para vender** (al abrir): solo lo que está en el vehículo y no es para una entrega. Cada producto dice cuánto
    queda libre y cuánto va para entregar.
  - **Reservado**: lo que está arriba (o por cargar) pero ya tiene dueño. Al final de "Para vender" hay un acceso.
  - **Todo**: el catálogo completo, como antes.
  - El buscador busca dentro de la pestaña elegida; para buscar en toda la mercadería, "Todo" (si no aparece, hay un
    botón "Buscar en todos los productos"). Lo que ya está en la venta se ve siempre.
- La preventa (pedido para otro día) sigue mostrando todo, como antes.

Sin migraciones. Prueba: `test/venta_directa_vehiculo_test.dart`.
