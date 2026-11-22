# Versión 1.13.0 — Etapa 1 del stock: todo con stock y pasar mercadería sin errores

Rama: `gestion/etapa1`. Migración: `20261130010000_todo_con_stock`. Diseño completo: documento
"Stock entre depósito, vehículos y local: diagnóstico y diseño".

- **Todos los productos llevan stock.** Los "a pedido" pasan a stock 0 (lo que tuvieran anotado se
  pone en 0 con su movimiento). "Se compra a pedido" queda como etiqueta (`productos.se_compra_a_pedido`)
  para la lista de compras y para que su 0 no sea alarma; se pone o se saca desde Stock (tocar el
  producto). Los productos nuevos llevan stock.
- **Cargar / Bajar ("pasar mercadería")**:
  - Se pasa **solo lo marcado en flúor**; el botón dice cuánto ("SUBIR 4 PRODUCTOS · 7 U.") y el
    resultado avisa lo que quedó sin marcar.
  - **No más de lo que figura en el origen** (depósito al cargar, vehículo al bajar). Un suelto puede
    abrir bolsas del depósito. También lo controla la base: `stock_cargar_vehiculo` y
    `stock_bajar_vehiculo` rechazan si no alcanza.
  - "Pedidos a entregar" y "Repetir la última carga" **reemplazan** la propuesta anterior (lo escrito a
    mano se respeta) y no proponen más de lo que hay; lo que no hay en el depósito queda a la vista en rojo.
  - Desde → Hacia arriba, con ⇄ para pasar de cargar a bajar. Stock **de este momento**: se vuelve a leer
    al entrar y con el botón de actualizar (con la hora del dato).
  - El borrador de la carga de otro día se descarta solo; "Empezar de nuevo" en Opciones.
- **Anotar compra**: el lugar (Depósito o Vehículo) se elige siempre; no arranca en ninguno.
- **Cerrar viaje**: el rojo es solo por el vehículo en negativo; el depósito en negativo se avisa aparte.
- **Informe de solo lectura** de movimientos de un producto: `C:\Alberdi\transferencias\informes\
  Informe-movimientos-producto.ps1` (`tool/informe_movimientos.sql`).

Pruebas: `test/todo_con_stock_escenario.sql`, `test/stock_ui_test.dart`.
