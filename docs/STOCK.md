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
| `stock_registrar_compra(id, ubicación, items con costo_unitario, fecha, proveedor?, actualizar_costo?)` | Ingreso de mercadería; "a pedido" solo deja el costo. |
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
- Se quitó la pantalla vieja de Stock V2 (`ENABLE_STOCK`).

## Etapas
1. Base de datos.
2. Pantallas (1.6.0).
3. Reparto y cobros sin señal (hora real del teléfono), descontando del vehículo.
4. Encender en producción (contar los primeros productos).
