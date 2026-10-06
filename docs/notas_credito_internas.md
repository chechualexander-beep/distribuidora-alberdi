# Notas de crédito internas

## Flujo

1. Abrir un pedido entregado/parcial y elegir el icono «Notas de crédito internas».
2. Indicar cantidades y motivo. La confirmación muestra el crédito y la comisión estimada.
3. Confirmar: se registra una NCI numerada. No se modifican las cantidades ni cobros originales.
4. En su historial, registrar la recepción de cada renglón como apto para venta o dañado.
5. Si el cliente ya había pagado, el excedente se aplica a sus deudas más antiguas; lo no utilizado queda a favor.
6. En la ficha del cliente, «Créditos y reintegros» permite consultar los movimientos, aplicar crédito o registrar una devolución real de dinero.
7. En Comisiones, abrir «Ver liquidación» y «Revisar y registrar liquidación neta». Solo esta confirmación registra el pago. Muestra bruto, ajustes considerados, descuento efectivo, neto y remanente.

Las notas se generan únicamente por administración. El preventista puede consultar las notas y los ajustes propios. La fecha se registra en el servidor. No se emiten comprobantes fiscales.

## Reglas y alcance

- Cantidad máxima: entregada menos todas las devoluciones anteriores. Precio, costo y comisión proceden del detalle original.
- La comisión se prorratea acumulativamente para evitar exceder el original por redondeo.
- Todos los descuentos tienen una nota y una aplicación a liquidación identificable. Las liquidaciones pagadas se conservan.
- Un ajuste participa cuando la comisión original ya se liquidó o está incluida en la liquidación actual. Se descuentan los más antiguos; el neto nunca es negativo y el remanente sigue pendiente.
- La revisión de liquidación incluye un token de los importes. Si otra operación cambia los valores, hay que revisar otra vez.
- Las operaciones financieras usan un bloqueo transaccional compartido para evitar duplicar aplicaciones, cobros y descuentos concurrentes. Su alcance global prioriza consistencia sobre concurrencia para el volumen actual.
- El día sábado no dispara pagos automáticos: la administración continúa registrando la liquidación semanal.
- Una aplicación de saldo a favor no es un cobro. Un reintegro es un egreso y se presenta separado de recaudación bruta.
- La recepción física se registra por renglón completo de la nota. Para recibir en partes, emitir notas por las cantidades efectivamente separadas.
- El costo se recupera en rentabilidad solo al registrar una recepción apta para venta. La mercadería dañada conserva su costo como pérdida. No se actualiza `productos.stock`: la app todavía no registra las salidas de inventario consistentemente.
- Notas confirmadas y recepciones no tienen edición ni borrado desde la app. Una reversión de una nota emitida por error requerirá un flujo posterior de contramovimientos; no borrar directamente registros en Supabase.
- El PDF anterior de comisiones queda identificado como detalle **bruto antes de ajustes**. El comprobante neto puede compartirse desde la nueva revisión luego de registrar; el historial permite consultar los descuentos aplicados.
- Resumen comercial conserva los indicadores brutos y añade neto de devoluciones, caja neta y ajustes de rentabilidad. La ganancia incorpora las notas, comisiones revertidas y costo recuperado, cada movimiento en su fecha.
- No se permite «Corregir operación» sobre un pedido con notas o crédito aplicado. Así no se cambia la base de movimientos ya confirmados.

## Activación y compatibilidad

Migración: `20260928210000_notas_credito_internas.sql`. Aplicar antes de ejecutar la versión nueva de Flutter y hacer hot restart. No cargar notas de prueba en producción.

La migración no crea devoluciones, cobros ni descuentos reales. Agrega tablas y columnas, sustituye las vistas de saldos y envuelve funciones anteriores. Versiones antiguas pueden seguir liquidando sin ajustes pendientes; si existen ajustes, deben actualizar la app para revisar el neto.

## Pruebas

`node test/credit_notes_sql_test.cjs` utiliza PostgreSQL embebido PGlite 0.5.8 instalado en `.dart_tool/commercial_sql_test`, con datos ficticios. El fixture conserva las columnas, vistas y funciones leídas del proyecto antes de la migración; no contiene clientes reales ni credenciales. No reproduce todos los triggers ni políticas históricos de producción.

Cubre: pagos completos y parciales, notas parciales/totales, cantidades agotadas, reintentos, cantidades duplicadas, redondeo de comisión, saldo a favor, transferencias de crédito, reintegros, recepción, liquidación original intacta, descuento anterior/posterior al pago, remanente, token desactualizado, doble liquidación, gestión con saldo a favor y permisos/RLS propios.

La suite de Flutter verifica los filtros y tarjetas existentes; el análisis estático cubre las pantallas nuevas. Falta la comprobación manual del circuito completo con una operación real autorizada, incluyendo recepción física y pago efectivo.
