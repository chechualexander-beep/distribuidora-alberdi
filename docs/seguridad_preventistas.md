# Seguridad de preventistas — activa desde el 4 de octubre de 2026

La migración `20261002120000_permisos_preventistas.sql` está aplicada y registrada
en producción. Android requiere **1.0.7 (15)**; Windows ya fue actualizado.
Las versiones anteriores, incluida 1.0.6 (14), NO son compatibles. No volver a
usar las copias de compatibilidad de Windows/Android ni aplicar de nuevo los SQL
de `supabase/deployment`: fueron preparados como alternativa de despliegue por etapas.
La activación final usó la migración completa dentro de una transacción verificada.

## Activación realizada

- El usuario confirmó que los teléfonos no estaban trabajando y autorizó cerrar
  y actualizar Windows. Los permisos se activaron durante esa ventana.
- Respaldo de esquema y datos comerciales en `build/security_activation_20261004`.
  Restauración de ambos comprobada en PostgreSQL aislado sin red; Auth local usa
  identidades simuladas para probar roles, no es un respaldo de usuarios de Auth.
- Migración completa y reversión de permisos ensayadas en esa copia. La reversión
  no borra pedidos ni auditoría y no restaura datos antiguos sobre datos nuevos.
- PostgREST v14.5 local: administrador y dos vendedores; costos bloqueados,
  lectura de pedidos propios, vistas admin y relaciones anidadas correctas.
- Comprobación transaccional en producción con ROLLBACK, luego activación con
  registro de migración y comprobaciones en la misma transacción.
- Comprobación posterior: migración registrada, RPC de pedidos disponible,
  SELECT directo de costo denegado; catálogo público conserva controles de acceso.
- Fix posterior `20261004120000_fix_cliente_nuevo_returning.sql`: durante
  `INSERT ... RETURNING`, PostgreSQL evalúa lectura de la fila nueva antes de que
  la búsqueda interna de `puede_leer_cliente` pueda verla. La regla restrictiva
  ahora permite leer directamente una fila cuyo `preventista_id` sea el usuario
  autenticado, conservando la condición para pedidos históricos y usuarios activos.
  Reproducido primero contra respaldo aislado: falla la política original y la fila
  temporal se inserta/lee y se revierte tras aplicar el fix. Migración comprobada
  con rollback y aplicada/registrada en producción; no se creó ningún cliente real.
- 33 pruebas Flutter y pruebas SQL de permisos (completas y por etapas) correctas.
- Windows: 23 archivos contrastados por SHA-256; respaldo anterior en
  `build/windows_backups/antes_seguridad_20261004/Release`.
- AAB firmado: `build/playstore/1.0.7-15/Alberdi-1.0.7-15.aab`; mismo certificado
  que la versión 14. No se publicó en Play Console desde este chat.
- No se crearon pedidos ni pagos de prueba en producción. La validación funcional
  de un pedido desde el teléfono actualizado queda para el usuario.

## Reglas implementadas

- Clientes: edición de los propios, limitada a nombre, dirección, propietario,
  teléfono, localidad, zona, día de visita, observaciones y coordenadas. Solo el
  administrador cambia asignaciones/datos internos. Historial de cambios solo admin.
- La lectura de una ficha anterior se conserva cuando identifica un pedido propio;
  esto conserva joins, nombre del comercio y saldos de los pedidos históricos.
  No permite editarla ni leer pedidos del nuevo vendedor.
- Pedidos: lectura por vendedor registrado en el pedido, independientemente del
  responsable actual del cliente. Cambiar un cliente no actualiza pedidos ni comisiones.
- Productos: las tres listas siguen disponibles. SELECT de costos bloqueado en
  productos, detalles de pedidos y detalles de notas de crédito. Vistas de costos
  exclusivas para administración. Las consultas del teléfono usan columnas explícitas.
- Nuevo RPC atómico para pedidos y ventas directas: vendedor = usuario autenticado,
  cliente asignado/activo, validación de cantidades y precios de lista, costo interno.
  Idempotencia por UUID y huella del contenido, incluida una marca de pedidos eliminados.
- Edición: exige personal activo y dueño del pedido o admin, bloquea finalizados,
  conserva precio de la misma lista y costo histórico de productos ya presentes.
  Eliminación exige personal activo y conserva las validaciones anteriores.
- El catálogo conserva su RPC, vencimiento y asignación opcional de preventista.
- Se quitan privilegios TRUNCATE, REFERENCES y TRIGGER de roles de aplicación.

## Bloqueo local Android

Después de cinco minutos sin interacción o al restaurar una sesión, solicitar la
autenticación del teléfono mediante local_auth (huella, rostro, PIN o patrón).
Mantener los formularios montados mientras están ocultos. Cancelar/fallar no desbloquea.
Si el teléfono no permite autenticación local, puede cerrarse sesión e ingresar con
la contraseña de Alberdi (descarta trabajo sin guardar, indicado en el botón).
Una entrada nueva con contraseña no exige inmediatamente otra autenticación.
Windows conserva su funcionamiento. La autenticación biométrica real requiere una
prueba en un dispositivo Android antes de distribuir, incluidas pausa/reanudación,
cancelación, PIN, ausencia de bloqueo configurado y regreso desde el selector de fotos.

## Procedimiento utilizado como referencia

1. Terminar otras mejoras y probar en un Supabase de pruebas usando USE_TESTING.
2. Verificar también PostgREST: relaciones de detalles_administracion con productos,
   consultas anidadas, notas de crédito, reportes, facturación y comisión del catálogo.
3. Guardar respaldo de datos y esquema/permisos actuales; verificar restauración en
   un entorno separado. No restaurar producción perdiendo pedidos nuevos.
4. Distribuir app compatible y coordinar el corte de versiones anteriores. Preparar
   primero los RPC/vistas aditivos o usar una ventana de mantenimiento: el código nuevo
   necesita esos objetos y el código anterior no soporta los permisos finales.
5. Aplicar la migración durante ese despliegue coordinado; verificar con dos vendedores
   y administrador, sin usar pedidos reales para pruebas destructivas.

Ante un fallo: revertir solo esquema/permisos con el respaldo revisado y una migración
específica; no borrar las tablas de solicitudes/auditoría ni restaurar datos antiguos
sobre ventas posteriores. No hay un rollback automático destructivo.

## Verificación local

`node test/permissions_sellers_sql_test.cjs`: PostgreSQL embebido con roles reales,
RLS y migraciones; no se conecta a producción. Cubre denegación de costos, clientes
ajenos, asignación, historial, usuarios inactivos, precio adulterado, creación atómica,
reintentos, auditoría y catálogo anónimo.

`flutter test --no-pub`: incluye bloqueo inicial, cancelación, error, inactividad y
conservación del borrador. No reemplaza la prueba de biometría en hardware.
