# 1.17.0 — Plata: negocio separado, sueldo fijo y salud del negocio

Incluye la 1.16.0 (stock, etapa 2) y además:

- **Anotar gasto → ¿De quién es?** Negocio, Casa o Personal. Lo de la casa y lo personal pagado con
  plata del negocio cuenta como retiro: no baja la ganancia.
- **Retiro casa / personal** e **Ingreso o aporte** (aporte tuyo: entra a la caja, no es ganancia).
- **Cambiar de quién es** un gasto ya anotado: mantenerlo apretado en Plata del negocio o Movimientos.
- **Mi sueldo**: lo fijás por semana y te lo pagás el sábado; si no lo pagaste, aparece en "Hoy".
- **Tablero**: retiros separados (sueldo, casa, personal), aportes y gastos por categoría.
- **Salud del negocio** arriba en el Tablero: cinco señales con semáforo, mes a mes y el sueldo
  sugerido. Mide la ganancia solo desde que se anotan gastos; hasta tener un mes completo lo marca
  como referencia.

Migración: `20261205010000_sueldo_y_salud`. Prueba: `test/sueldo_y_salud_escenario.sql`,
`test/finance_test.dart`.
