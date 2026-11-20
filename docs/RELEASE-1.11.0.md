# Versión 1.11.0 — Búsqueda sin acentos, pedido sin cliente y foto con precio

Rama: `gestion/etapa1`. Sin migraciones nuevas (producción también recibe la de 1.10.0:
`20261128010000_venta_especial`).

- **Búsqueda común** (`lib/core/text_search.dart`): todos los buscadores ignoran mayúsculas y acentos,
  buscan por palabras en cualquier orden ("1kg tutuca") e ignoran puntos y espacios dentro de una palabra
  ("fn" encuentra "F.N"). Productos, pedidos, clientes, saldos, facturación, stock, catálogo, venta especial.
- **Pedido sin cliente**: en Nuevo pedido, "ARMAR PEDIDO SIN CLIENTE". Se cargan los productos con la
  lista elegida (título "CLIENTE AL FINAL"); al tocar VER PEDIDO se elige un cliente existente o se crea
  uno nuevo (también sin señal). Si su lista habitual es otra, pregunta si pasar los productos a esa
  lista; si tiene saldo pendiente, lo avisa. Volver atrás con productos cargados pide confirmación.
- **Foto con precio** (pantalla de productos del pedido): al tocar la foto se arma una imagen 1080×1350
  con la foto de fondo, el logo (sin fondo, `assets/logo/logo_alberdi_marca.png`), marca de agua
  "DISTRIBUIDORA ALBERDI", nombre, descripción, precio y "Precio al dd/mm/aaaa · sujeto a cambios".
  El nombre de la lista no se imprime. Botones COMPARTIR y GUARDAR (Android: galería, carpeta
  Imágenes/Alberdi, Android 10 o más; Windows: "Guardar como"). Sin foto o sin señal sale igual, sin foto.
  Fotos muy apaisadas o muy altas van enteras sobre la misma foto desenfocada.

Pruebas: `test/text_search_test.dart`, `test/order_without_client_test.dart`,
`test/product_price_card_test.dart`.
