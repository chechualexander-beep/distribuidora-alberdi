# 1.14.0 — Gabriela en el depósito y lista de carga compartida

Incluye todo lo de la 1.13.0 (todos los productos con stock; cargar y bajar solo lo marcado y sin
pasar de lo que hay) y además:

- **Ayuda en el depósito**: permiso para un preventista (Gabriela). En su teléfono aparece la
  sección DEPÓSITO: Cargar vehículo, Bajar al depósito, Contar y ver stock (sin costos). Lo que
  cuenta se aplica directo. No anota compras ni cierra el viaje. Se prende o apaga en Stock →
  ícono de personas ("Ayuda en el depósito").
- **Lista de carga compartida, en vivo**: la carga (y la bajada) en preparación está en la base.
  Teléfonos y PC ven la misma lista; lo que marca uno aparece en el otro en unos 3 segundos, con
  quién lo marcó ("✓ Gabriela 10:42") y quién más está en la lista. SUBIR pasa solo lo marcado y
  eso sale de la lista; lo demás queda para seguir. Sin señal, lo marcado se manda al volver
  (si se quiere salir con cambios sin mandar, avisa). "Empezar de nuevo" borra la lista para todos.
- "Pedidos a entregar" propone lo de todos los pedidos facturados (también desde el teléfono de
  Gabriela).
- Anotar compra y Contar: el buscador ya no abre y cierra el teclado solo.
- Cargar y Bajar se abren enseguida y leen el stock adentro (sin parpadeo).

Migraciones: `20261129010000_vehiculo_toma_del_deposito` (si no estaba), `20261130010000_todo_con_stock`,
`20261201010000_ayuda_deposito`.
Pruebas: `test/ayuda_deposito_escenario.sql`, `test/todo_con_stock_escenario.sql`, `test/stock_ui_test.dart`.
