# Catálogo web de clientes

Primera versión implementada en `catalogo/`, independiente del acceso de empleados. No instala otra aplicación en el teléfono y no requiere publicar el Flutter de administración en la web.

## Estado de publicación — 1 de octubre de 2026

- Publicado en **https://distribuidora-alberdi.pages.dev/** mediante Cloudflare Pages, proyecto `distribuidora-alberdi`, carga directa. Sin dominio pago.
- Aplicadas también las cuatro migraciones de vencimiento, fotos y asignación descritas más abajo.
- Aplicadas en Supabase (`vmbncsqapqdyffscwfwo`) las migraciones `20261001120000_catalogo_clientes.sql`, `20261001121000_catalogo_limita_rpc_internas.sql` y `20261001122000_catalogo_acceso_personal_activo.sql`.
- La segunda migración revoca acceso anónimo/PUBLIC a las RPC internas de edición, eliminación, notificación y numeración; conserva los permisos del personal autenticado. Se detectó y cerró el acceso anónimo preexistente a `actualizar_pedido_activo` antes de publicar.
- La tercera agrega políticas restrictivas a las tablas internas: una cuenta de Auth debe tener un perfil activo en `usuarios`. Es necesario porque el registro de Auth está habilitado. También limita las funciones de notificación a su uso interno desde los triggers/RPC; Flutter no las invoca directamente.
- Probado un pedido contra el servidor real dentro de una transacción con ROLLBACK: precio, estado, comisión e idempotencia correctos. No quedan registros ni avisos de prueba.
- Comprobados HTTPS, cabeceras CSP y rechazo de token inválido/acceso a edición interna/tabla de enlaces desde la API anónima.
- Compilación Windows release terminada. Alberdi incorpora la URL publicada como valor predeterminado. Paquete portable en `build/catalogo_publicacion/Alberdi-Windows-Catalogo.zip`; descomprimir completo y ejecutar `distribuidora_alberdi.exe`.
- Primer catálogo habilitado para el comercio **ADRIANA**, lista base Normal y excepción **Snacks → Promo**, según la elección del usuario. Verificados 169 productos, incluidos 36 Snacks con Promo. El enlace se entrega en la conversación; no se envió al cliente.
- Comprobado en la web publicada el cambio de enlace dentro de la misma pestaña, la búsqueda y el filtro Snacks. Captura móvil de producción en `docs/catalogo-adriana-publicado.png`.

La dirección general pide abrir el enlace del cliente: ese comportamiento es intencional. No muestra productos ni precios hasta recibir un token válido.

## Puesta en marcha

1. Las siete migraciones de catálogo y acceso ya están aplicadas al proyecto Alberdi. Para una instalación nueva, revisar `supabase migration list --linked` y el `db push --dry-run` antes de enviar migraciones. No cambian precios ni asignan reglas a todos los clientes.
2. El contenido de `catalogo/` está publicado en Cloudflare Pages. No requiere compilación ni paquetes JavaScript. Para actualizarlo, comprimir `index.html`, `catalogo.css`, `catalogo.js`, `catalogo-core.js` y `_headers` en la raíz del ZIP y crear un nuevo despliegue de producción en el mismo proyecto. El catálogo usa el proyecto indicado en `lib/main.dart`; para pruebas contra otro proyecto hay que cambiar endpoint, clave publicable y `connect-src` tanto en HTML como en `_headers`.
3. Compilar/actualizar Alberdi **después de aplicar la migración**, que agrega `pedidos.origen`. En la ficha del cliente, entrar a **Catálogo web del cliente** como administrador.
4. Seleccionar explícitamente Normal, Promo o Interior como base. Agregar excepciones por categoría y producto. Producto tiene prioridad sobre categoría, y categoría sobre base. Las reglas se guardan en Supabase, independientemente de las plantillas locales de PDF.
5. Ingresar la dirección HTTPS publicada (sin parámetros ni fragmentos), generar el enlace, abrirlo para revisar precios y copiarlo para enviarlo al cliente. No se envían mensajes automáticamente.
6. Probar con clientes elegidos antes de ampliar el uso. Los pedidos llegan a **Pedidos** y **Facturación**, sin facturar y pendientes, con observación `[Catálogo web]`. No se les asigna fecha de entrega automática.

## Acceso y precios

El token aleatorio se guarda como SHA-256 en Supabase; el enlace usa un fragmento `#token=…`, que no se envía al alojamiento en el pedido HTTP. Quien tenga el enlace puede consultar el catálogo y pedir: no es autenticación personal. Puede deshabilitarse o renovarse desde Alberdi. El enlace en texto se conserva únicamente en el dispositivo de administración que lo generó, junto con el hash para detectar renovaciones desde otro dispositivo; desde otro dispositivo se puede renovar.

Las RPC anónimas no retornan costos, comisiones, direcciones, modalidades ni otros precios. Las tablas nuevas tienen RLS y no admiten escritura directa. Se respeta `activo` y `visible_preventistas`; no se publica stock ni se promete reserva. Productos con precio cero/no válido se omiten para evitar pedidos accidentales gratis. Las categorías pueden faltar; esos productos siguen visibles en Todos y en el buscador.

El pedido recalcula importes en el servidor. Si el precio mostrado cambió, exige actualizar y revisar. Pedido y detalles se guardan en una transacción. La solicitud tiene identificador único por cliente: reintentar tras un corte no duplica el pedido. En el navegador se conserva el carrito y la solicitud pendiente en `sessionStorage` cuando está disponible; una solicitud de resultado incierto bloquea cambios hasta reintentar. Límite de 20 pedidos nuevos por cliente/hora y 300 productos por pedido. Esta versión no incluye protección avanzada contra tráfico abusivo; considerar límites adicionales si se amplía la exposición.

El esquema exige `preventista_id`. Sin asignación, se usa el administrador responsable y un trigger conserva comisión cero. Con asignación opcional, el pedido queda a nombre del preventista elegido y conserva `catalogo_preventista_id` como instantánea. Se guarda el porcentaje de comisión según la modalidad de cada producto; el importe se calcula sobre lo entregado. Renovar otro enlace o cambiar los porcentajes del producto no altera esa instantánea de pedidos existentes.

## Diseño y límites de esta versión

Buscador por nombre, código y descripción con múltiples palabras y sin distinguir acentos. Categorías, cantidades enteras hasta 9999, carrito editable, total con centavos, observaciones y comprobación de recepción. Sin la frase “precios asignados”. Las fotos opcionales usan `productos.foto_path` y Storage; los productos sin foto conservan un marcador. Las presentaciones provienen de `descripcion`; conviene completar allí unidad/paquete/caja antes de la prueba real. No incluye pago online, historial del cliente ni repetición de pedidos.

## Validación local

- `node test/catalogo_sql_test.cjs`: ejecuta la migración sobre PGlite y valida precios mixtos, datos expuestos, permisos anónimos, reintentos, atomicidad, precios modificados, cantidades, revocación y comisión cero.
- `node test/catalogo_web_test.cjs`: búsqueda, acentos, códigos, filtros, cantidades y centavos.
- `node --check catalogo/catalogo.js` y `node --check catalogo/catalogo-core.js`.
- Análisis Flutter: pantallas de cliente sin observaciones; gestión de pedidos sin errores, con seis avisos de deprecación de Radio anteriores a este trabajo.
- `node test/catalogo_preview.cjs`: servidor local en 127.0.0.1:4178 con datos ficticios y migración real. El enlace se imprime en la terminal. Sustituye endpoint/CSP en memoria para ejecutar las RPC localmente y nunca consulta producción.
- Navegador: búsqueda de Papas Facu, agregar al carrito, revisar y confirmar un pedido en la base local; pantalla de recepción verificada. Diseño a 360 px sin desbordamiento horizontal. Capturas en `docs/catalogo-movil-prueba.png` y `docs/catalogo-pedido-prueba.png`.
- `supabase db query --linked --file test/catalogo_remote_smoke.sql`: comprobación transaccional en el servidor real, termina con ROLLBACK.
- `node test/catalogo_public_smoke.cjs`: sitio publicado y rechazos de seguridad vía HTTPS, sin crear datos.
- `supabase db query --linked --file test/catalogo_remote_access.sql`: personal activo conserva acceso; una cuenta sin perfil no puede ver clientes, productos, pedidos, usuarios ni saldos. No crea usuarios ni conserva cambios.

El usuario confirmó el primer pedido de prueba de ADRIANA y la recepción de su notificación con observación «Catálogo web». Indicó que eliminará el pedido de prueba por su cuenta. La prueba transaccional no envió avisos porque pg_net los procesa después del COMMIT. No se creó un pedido comercial para ADRIANA durante la verificación.

## Actualización: vigencia y observaciones

- Migración `20261001130000_catalogo_vigencia_12h.sql`: `vence_at` se fija 12 horas después de generar o renovar el token. Guardar reglas y deshabilitar/habilitar no extienden el plazo. Para enlaces anteriores se toma `updated_at + 12 hours`.
- El servidor rechaza tanto consultas como pedidos después del vencimiento, incluso si la pestaña sigue abierta, con HTTP 410 y mensaje para solicitar otro enlace. La web muestra fecha y hora límite; Alberdi también las muestra en la ficha del catálogo. No hay restricción por teléfono.
- Pedidos y Facturación muestran un signo de admiración naranja cuando `observacion` contiene texto, incluidos pedidos de catálogo. El tooltip muestra la observación; los detalles existentes permiten leerla.
- Probados generación, conservación del plazo, vencimiento, reactivación y renovación en PGlite; la prueba transaccional remota comprueba también el rechazo de enlaces vencidos sin conservar datos.

## Fotos y preventista opcional (implementado)

- Administrador: **Productos → Editar → Agregar o cambiar foto → Elegir imagen → Guardar foto**. La foto se guarda por separado del resto de los campos del producto; cancelar el formulario general no revierte una foto ya guardada. También se puede quitar.
- Se admiten JPG/JPEG, PNG y WebP hasta 20 MB y 40 megapíxeles. La app corrige orientación, quita metadatos de la foto original, reduce a un máximo de 960 px y comprime a JPEG de hasta 300 KB. No incluye captura de cámara integrada; se eligen archivos de la computadora o del selector disponible en el dispositivo.
- Storage `productos-fotos` es público para servir únicamente imágenes comerciales. Subir, listar y quitar está limitado al administrador activo. No se permite borrar fotos aún vinculadas a un producto. Las versiones reemplazadas se intentan quitar después de guardar la nueva referencia; un corte de red puede dejar un archivo viejo no vinculado. No borrar metadatos de Storage por SQL.
- Las mismas URLs se utilizan en productos de administración, consulta de productos, selección de productos del pedido y catálogo web. El catálogo carga imágenes a demanda y muestra un marcador si falta una foto o falla su descarga. Recargar para ver imágenes recién modificadas.
- **Cliente → Catálogo web del cliente → Preventista para pedidos de este enlace**. Por defecto, sin preventista y sin comisión. Elegir un preventista activo y generar/renovar. Mary Ana es un ejemplo del usuario; no se asignó ningún cliente real automáticamente. El plazo de 12 horas se conserva.
- Cambiar la asignación de un enlace existente exige renovarlo. La elección se conserva para próximas renovaciones hasta que el administrador la cambie. Para una excepción de una sola ocasión, elegir nuevamente «Sin preventista / sin comisión» al generar el siguiente enlace.
- Solo las RPC del servidor deciden el preventista y la comisión; el navegador no puede enviarlos. Un preventista desactivado bloquea nuevos pedidos de su enlace hasta que el administrador actualice la asignación. Pedidos anteriores mantienen su responsable. Los pedidos sin asignar, incluidos los anteriores a esta mejora, siguen con comisión cero.
- Migraciones `20261001140000_productos_fotos.sql`, `20261001141000_catalogo_preventista.sql`, `20261001142000_catalogo_asignacion_relacion.sql`, aplicadas. La última evita duplicar la relación de PostgREST hacia usuarios: la FK de `preventista_id` y el CHECK de igualdad ya garantizan integridad de la asignación.
- `flutter test test/product_photo_test.dart`: conversión, límites de tamaño, transparencia y rechazo de archivos inválidos.
- `node test/catalogo_assignment_test.cjs`: RLS de fotos, rutas válidas, confidencialidad, comisión mixta, entrega parcial, porcentajes conservados, renovación, usuarios inactivos e idempotencia.
- `test/catalogo_remote_assignment.sql`: verificado contra Supabase con ROLLBACK; foto expuesta por RPC, preventista correcto, comisión correcta sobre entrega y conservación de pedidos anteriores. No realiza una carga real de archivo a Storage ni conserva pedidos.
- El almacenamiento estaba vacío antes de esta mejora. El usuario proporcionó `cachorros.png` y corrigió la presentación a **Nutribon Cachorro 8kg** (código 879). Se preparó con el mismo código de compresión de Alberdi: JPEG de 35.536 bytes. Subida a Storage y vinculada solo a ese producto; verificada su descarga real en el catálogo de ADRIANA (258 × 442 px). Nutribón Cachorro 15kg queda sin foto. Captura en `docs/catalogo-nutribon-foto.png`.

## Fotos ampliables — 2 de octubre de 2026

- Catálogo web: cada miniatura con foto es un botón accesible que abre un diálogo con el nombre del producto y la foto grande. Se cierra con «Cerrar», Escape o tocando el fondo. Disponible en catálogo y carrito; conserva cantidades, búsqueda y foco. Los productos sin foto no abren un visor.
- Alberdi: el componente compartido ProductPhoto abre un visor a pantalla completa, con cierre explícito e InteractiveViewer para acercar hasta 5x y desplazar. También admite rueda del mouse en Windows.
- Verificado en navegador local a 390 × 800, apertura/cierre desde catálogo y carrito, cierre con Escape y conservación de la cantidad. Captura en `docs/catalogo-foto-ampliada.png`. La prueba no creó pedidos en producción.
- Versión Android siguiente: 1.0.5 (13), ya que el usuario confirmó la publicación del código 12. AAB en `build/playstore/1.0.5-13/Alberdi-1.0.5-13.aab`. Requiere nueva publicación en Google Play; la mejora web se distribuye por Cloudflare.

## Color colorado — 3 de octubre de 2026

Paleta aprobada en la vista previa: principal #b4232c, fondos y bordes cálidos. Publicada en Cloudflare Pages; CSS público verificado idéntico al local. Solo cambió catalogo.css; las migraciones pendientes de seguridad no se aplicaron.

## Descripciones desde Alberdi — 4 de octubre de 2026

En Administración → Productos → Nuevo/Editar se agregó «Descripción para el
cliente (opcional)», con varias líneas. Se guarda junto al producto en la columna
existente `descripcion`; dejar el campo vacío y guardar elimina la descripción.
El catálogo publicado ya recibe y muestra este campo debajo del nombre, por lo
que no requiere una migración ni publicación web. Se ve al abrir o recargar el
catálogo. La búsqueda web también incluye la descripción. No se cargaron textos
inventados ni se modificaron productos reales durante la implementación.

El AAB 1.0.7 (15) generado antes de este cambio no incluye el campo de edición;
su incorporación a Android queda para la próxima compilación. Las descripciones
cargadas desde Windows sí aparecen en el catálogo abierto desde cualquier teléfono.

Windows compilado e instalado con autorización para cerrar la app: 23 archivos
contrastados por SHA-256 y aplicación reabierta. Respaldo anterior en
`build/windows_backups/antes_descripciones_20261004/Release`. Análisis del formulario
sin incidencias y pruebas del catálogo correctas.

## Descripciones en Productos y Nuevo pedido — 4 de octubre de 2026

Ambas pantallas muestran la descripción opcional: debajo del nombre en móvil y
en una columna compacta con tooltip del texto completo en Windows. La columna
se omite si ningún producto visible tiene descripción. Nuevo pedido incorpora
`descripcion` en su consulta; no se modificaron datos ni permisos.

Análisis de los tres archivos modificados sin incidencias y compilación Windows
release correcta. Windows instalado, 23 archivos verificados por SHA-256 y app
reabierta. Respaldo: `build/windows_backups/antes_descripciones_listados_20261004/Release`.
La visualización móvil queda preparada para la próxima actualización Android;
el AAB 1.0.7 (15) existente no contiene estos cambios.

