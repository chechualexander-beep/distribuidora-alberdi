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

## Próximas etapas

2. **Tablero del mes**: ventas − costo de mercadería − comisiones − gastos = ganancia; ganancia
   contra plata para la casa (aviso "salió del capital"); capital del negocio mes a mes (plata +
   mercadería al costo + lo que deben los clientes − proveedores); total vendido en 12 meses (para
   elegir la categoría de monotributo con el contador).
3. **Crecer**: margen por producto, categoría y cliente; punto de equilibrio; días de cobro;
   rotación; fondo de reserva.
4. **Hogar con detalle** (más adelante, si hace falta): presupuesto semanal y en qué se gasta.
