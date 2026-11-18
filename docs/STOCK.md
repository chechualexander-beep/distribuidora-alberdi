# Stock — cómo funciona (desde la etapa 1, migración `20261118010000_stock_por_producto`)

## Cómo trabaja la distribuidora (16/11/2026)
- Unos 176 productos; unos 100 con stock y pocos con mucha cantidad (los de más rotación).
- Productos de baja rotación (fécula de maíz, aceite de coco 360 ml...) se compran solo cuando
  hay pedido, muchas veces en el camino del reparto, antes de llegar al cliente.
- Hay un **depósito**. El "local comercial" (para vender al público, con el Alberdi POS) todavía
  no existe.
- El vehículo se carga desde el depósito; según el día, lo que sobra se baja o queda arriba.
- Venta directa en zonas rurales: salen el administrador y un preventista. El preventista genera
  la venta; el administrador entrega y cobra. Casi siempre hay señal entre un cliente y otro.
  Problemas: se pierde la cuenta de lo que se lleva y el preventista se olvida de ofrecer cosas
  (la carga la hace el administrador con otra persona).

## Reglas
- **El stock informa, no traba**: nunca se rechaza una entrega o venta por falta de stock. Puede
  quedar en negativo; se ve como diferencia para revisar.
- **Con stock / a pedido** (`productos.control_stock`): se pasa a "con stock" al **contarlo**
  (`stock_contar`); se enciende de a poco. "A pedido" no mueve stock nunca.
- **Entregas y ventas directas descuentan del vehículo** (`stock_base_finalizar_v2`).
  - **Sin viaje abierto** (ese día no se registró la carga): lo que falta arriba se toma solo del
    depósito, abriendo bolsas del depósito si hace falta (`20261121010000_entrega_sin_carga`).
  - **Con viaje abierto** (se cargó el vehículo): no se toma del depósito; el vehículo marca que se
    terminó y queda en negativo para revisar (precisión para la venta directa).
- **Un conteo vale para su momento** (`stock_actual.contado_at`): una entrega hecha antes del
  conteo pero enviada después no se descuenta otra vez.
- Operaciones con **id elegido en el teléfono**: reenviar devuelve lo mismo (sirve sin señal) y
  con la **hora real** (hasta 72 h atrás).
- El régimen ON/OFF del Stock V2 queda sin uso (siempre OFF). Las correcciones de operaciones
  finalizadas todavía no mueven stock: se ven como diferencia en el próximo conteo.

## Funciones (administrador, salvo la indicada)
| Función | Qué hace |
|---|---|
| `stock_contar(id, 'deposito_alberdi'\|'vehiculo', items, fecha)` | Deja lo contado; pasa los productos a "con stock"; devuelve diferencias. |
| `stock_marcar_a_pedido(producto)` | Vuelve el producto a "a pedido". |
| `stock_cargar_vehiculo(id, items, fecha, preventista?)` | Depósito → vehículo. Abre el viaje si no hay uno abierto. |
| `stock_bajar_vehiculo(id, items, fecha)` | Vehículo → depósito. |
| `stock_registrar_compra(id, ubicación, items con costo_unitario, fecha, proveedor?, actualizar_costo?)` | Ingreso de mercadería; un producto "a pedido" pasa a llevar stock con lo comprado (`20261122010000`). |
| `stock_cerrar_viaje(id, viaje, conteo?, bajar, fecha)` | Cuenta lo que sobró (debe incluir todo lo de arriba), diferencias, baja al depósito y cierra. |
| `stock_vehiculo_disponible()` | **Personal activo** (preventista incluido), por GET: en vehículo, comprometido (ventas directas del viaje sin entregar) y disponible. |
| `stock_estado()` | Depósito y vehículo de cada producto activo. |

Toda venta directa creada con un viaje abierto queda en ese viaje (`pedidos.viaje_id`).
Prueba: `test/stock_vehiculo_escenario.sql`.

## Pantallas (1.6.0)
- **Stock** (administrador; celular: "Stock y vehículo", Windows: menú Stock): viaje abierto,
  Cargar vehículo (propone "Pedidos a entregar" o "Repetir la última carga"; con quién sale),
  Bajar al depósito, Anotar compra (depósito o vehículo, costo opcional, actualizar costo),
  Contar (depósito o vehículo), Cerrar viaje (conteo precargado con lo que debería quedar,
  diferencias, bajar todo). Filtros: con stock, a pedido, en negativo. Tocar un producto: contar
  o pasar a "a pedido".
- **Lo que llevamos** (preventista; el administrador desde Stock): por categoría, "Quedan N",
  agotados al final, con copia sin señal ("Trabajar sin señal → Preparar" la baja).
- **Venta directa con viaje abierto**: "Solo lo del vehículo" (por categoría), "Vehículo: quedan
  N", "La última vez llevó N" primero, y antes de ver el pedido "¿Ofreciste todo?" con lo del
  vehículo que no está en la venta (una vez por venta).
- Sin señal, las operaciones de stock quedan en "Pendientes de enviar" (mismo id, hora real).
- "Anotar compra" también desde Gestión de reparto (entra al vehículo) y con el costo actual
  precargado (si se pagó lo mismo, no hay que escribirlo).
- Se quitó la pantalla vieja de Stock V2 (`ENABLE_STOCK`).

## Reparto y cobros sin señal (1.7.0, migración `20261119010000_reparto_sin_conexion`)
- Si al guardar una gestión de reparto no hay señal, queda "Guardado en el teléfono" con la
  hora de ese momento y se envía sola (`finalizar_gestion_sin_conexion`, hasta 72 h). Descuenta
  del vehículo como cualquier entrega.
- La **fecha de finalización** (semana de la liquidación de comisiones) y la del **cobro hecho
  al entregar** son las del momento real de la entrega, también en las gestiones con señal.
- "Pago completo" sin señal se manda sin importe: el servidor aplica el saldo a favor y cobra el
  saldo real al recibirla (sin señal no se puede consultar el saldo a favor).
- Cobro de saldo sin señal (Registrar pago): queda en "Pendientes de enviar" con la hora de ese
  momento (`registrar_cobro_sin_conexion`, misma solicitud: no se cobra dos veces).
- Para trabajar sin señal, abrir con señal "Preparación y reparto" y la cuenta del cliente antes:
  lo que se vio queda guardado en el teléfono.
- Prueba: `test/reparto_sin_conexion_escenario.sql`.

## Resumen de productos y fraccionados (1.8.0, migración `20261120010000_fraccionados`)
- **Resumen de productos** (Pedidos y Preparación y reparto, celular y Windows): filas alternadas
  blanco/celeste, "Pedido" y "Hay" (depósito + vehículo) y el estado: Alcanza, Faltan N,
  Abrir N × origen (fraccionados), A pedido · comprar N. Contadores, "Solo lo que falta" y
  "Lista de compras" (copiar o compartir; los fraccionados se compran en unidades del origen).
  El preventista ve la tabla sin la columna de stock.
- **Fraccionados** (`productos.fracciona_de`, `unidades_por_origen`): ej. "Copos c/azúcar x 1 kg"
  sale de "Copos 3A x 4 kg" (1 → 4). Se configura tocando el producto en Stock.
  - A mano: "Fraccionar" (`stock_fraccionar`): origen −N, fraccionado +N×unidades.
  - Automático: si una entrega deja el fraccionado en negativo y hay unidades del origen en el
    mismo lugar, se abren solas las necesarias ("Fraccionado automático al entregar").
- Prueba: `test/fraccionados_escenario.sql`.

## Etapas
1. Base de datos.
2. Pantallas (1.6.0).
3. Reparto y cobros sin señal (1.7.0).
4. Resumen de productos con stock y fraccionados (1.8.0).
3. Reparto y cobros sin señal (hora real del teléfono), descontando del vehículo.
4. Encender en producción (contar los primeros productos).
