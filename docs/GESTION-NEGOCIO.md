# Gestión del negocio

Objetivo: dejar de llevar el negocio "a ojo". Separar la plata del negocio de la del hogar, saber si
los retiros salen de la ganancia o del capital, llegar al día 1 con la plata de los gastos fijos y
crecer con números claros. Solo administración.

## Etapa 1 — Plata del negocio (1.9.0)

Migración `20261126010000_plata_del_negocio`. Pantalla "Plata del negocio" (celular: Administración;
Windows: menú).

- **Foto inicial**: efectivo y billetera de hoy. Antes de la foto no se puede anotar nada; desde la
  foto todo cuenta (`fin_config.inicio`).
- **Dos cuentas**: efectivo y billetera virtual (transferencias).
- **Entra solo, sin cargar**: cobros (`cobros_cliente`: "Efectivo" → efectivo, el resto → billetera),
  devoluciones en dinero (`movimientos_credito_cliente` sin pedido destino) y comisiones pagadas
  (`liquidaciones` pagadas, en efectivo). Se leen en `fin_flujo`, no se copian.
- **Se anota**: gasto del negocio (con categoría), "Dejé plata en casa" (hogar), pase entre cuentas,
  ingreso extra, compra (desde "Anotar compra": efectivo, billetera, a pagar o no anotar).
- **Gastos fijos con sobre**: nombre, importe por mes, día de pago y de quién es (negocio, hogar o
  mixto, como la tarjeta: al pagarla se indica la parte de la casa). La app "aparta" sola cada día
  la parte proporcional hasta el vencimiento (`reservado`) y dice cuánto apartar por semana. Lo que
  venció antes de la foto inicial se da por pagado.
- **Proveedores a pagar**: compras con plazo (vencimiento), pagos parciales.
- **Disponible para mercadería** = plata − apartado para gastos fijos − proveedores a pagar.
- **Arqueo**: lo contado contra lo que dice la app; la diferencia queda como ajuste.
- **Este mes**: cobros, compras, gastos del negocio, comisiones, devoluciones, para la casa
  (incluye la parte de la casa de los gastos fijos) y diferencias de arqueo.
- Nada se borra: los errores se anulan (`fin_anular`). La foto inicial no se anula: se corrige con
  un arqueo.
- Cada operación lleva id y hora del teléfono (idempotente); sin señal queda en "Pendientes de
  enviar" como las de stock. Los gastos fijos y las anulaciones se hacen con conexión.

Prueba: `test/plata_del_negocio_escenario.sql`, `test/finance_test.dart`.

## Etapa 2 — Tablero del mes (1.9.0)

Migración `20261127010000_tablero_del_mes`. Pantalla "Tablero del mes" (celular: Administración;
Windows: menú; también desde "Plata del negocio").

- **Resultado**: ventas entregadas − costo − comisiones ± notas de crédito = ganancia comercial (de
  `resumen_comercial`, igual que el "Resumen comercial"); − gastos del negocio = ganancia del
  negocio; − para la casa = quedó para el negocio. Si es negativo: "salió del capital". Gastos y casa
  se cuentan desde la foto inicial. Mes en curso: "al día N" y ritmo de ventas.
- **¿Cuánto hay que vender?**: (gastos del negocio + casa) / margen.
- **Capital del negocio**: plata + mercadería al costo (productos con stock) + lo que deben los
  clientes − saldo a favor de clientes − proveedores a pagar. Una foto por día (`fin_capital_fotos`)
  al abrir el tablero o la plata; se compara con la última foto antes del mes.
- **Ventas de los últimos 12 meses** (para la categoría del monotributo, con el contador).

Prueba: `test/tablero_del_mes_escenario.sql`, `test/finance_test.dart`.

## Próximas etapas

3. **Crecer**: margen por producto, categoría y cliente; punto de equilibrio; días de cobro;
   rotación; fondo de reserva.
4. **Hogar con detalle** (más adelante, si hace falta): presupuesto semanal y en qué se gasta.

## Etapa 3 — Negocio separado de lo de afuera, sueldo y salud (1.17.0)

Migración `20261205010000_sueldo_y_salud`.

- **¿De quién es?** al anotar un gasto: Negocio (con categoría), Casa o Personal. Casa y Personal se
  guardan como retiro (`tipo = 'hogar'`, categoría `Casa`/`Personal`): salen de la caja pero no bajan la
  ganancia del negocio. Los "hogar" viejos cuentan como Casa.
- **Retiro casa / personal** (antes "Dejé plata en casa") e **Ingreso o aporte**: el aporte del dueño
  (categoría `Aporte del dueño`) es plata de afuera que entra a la caja; no es ingreso ni ganancia.
- **Cambiar de quién es**: manteniendo apretado un gasto o retiro (`fin_reclasificar`), para corregir lo
  anotado mezclado sin anularlo. El sueldo y los gastos fijos no se reclasifican.
- **Mi sueldo**: importe semanal fijo (`fin_config.sueldo_semanal`), semana de lunes a sábado. Desde el
  sábado aparece pendiente (tarjeta en Plata del negocio y en "Hoy") hasta pagarlo (`fin_pagar_sueldo`,
  una vez por semana, se puede adelantar la próxima). Es un retiro con categoría `Sueldo`.
- **Tablero**: los retiros separados (sueldo, casa, personal), los aportes y los gastos del negocio por
  categoría.
- **Salud del negocio** (`fin_salud`, arriba en el Tablero del mes actual): cinco señales con semáforo —
  ganancia del negocio, margen de la venta (este mes contra los 3 anteriores), gastos sobre lo que deja
  la venta (<50% verde, <80% amarillo), retiros sobre la ganancia (≤80% verde, ≤100% amarillo) y capital
  (sin contar aportes). Ventas y margen se miden en meses enteros; la ganancia, los gastos y los retiros
  solo desde la foto inicial, con las ventas de ese mismo tramo. Se toman los últimos 3 meses completos;
  mientras no haya uno, lo anotado hasta hoy, marcado como referencia.
- **Sueldo sugerido** = ganancia del negocio por mes × 75% (25% de reserva) ÷ 4,33, redondeado a mil.
  Aparece con el primer mes completo y es firme con 3.

Prueba: `test/sueldo_y_salud_escenario.sql`, `test/finance_test.dart`.
