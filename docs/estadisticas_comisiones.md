# Estadísticas de comisiones

Acceso: **Mis comisiones → Estadísticas**. Administración accede desde **Liquidación de comisiones → Estadísticas** y puede elegir una persona (incluidos usuarios inactivos con historia) o todos.

- Hoy, esta semana (lunes hasta hoy) y personalizado, con fechas inclusivas en hora argentina.
- Comisión y venta netas: entregas menos notas de crédito. Incluyen preventa y venta directa, independientemente de si se pagó la comisión.
- Entregas por `fecha_finalizacion`, con `fecha_entrega` como respaldo histórico. Excluye operaciones anuladas/canceladas y renglones sin entrega.
- Notas por su fecha de emisión. Una devolución de una venta anterior puede producir resultados negativos en el período actual.
- Clientes: personas distintas con entregas positivas. Promedio: venta neta de todo el período / estos clientes. Si no hay clientes con entregas, muestra «—», incluso si hay devoluciones.
- Ranking de diez clientes por comisión neta, con desglose por pedido/fecha/tipo. Se agrupa por identificador, no por nombre.
- Ranking de diez productos por cantidad, venta o comisión neta. Cantidades por presentación; no equivalen a kilos ni suman unidades homogéneas.
- Evolución diaria hasta 63 días inclusivos; semanal para rangos mayores. Las semanas parciales incluyen únicamente los días seleccionados. Muestra días/semanas sin actividad con cero y valores negativos debajo del eje.

La función `estadisticas_comisiones(date,date,uuid,text)` es de solo lectura. Valida sesión y usuario activo; administración puede consultar todos, los demás solo sus operaciones aunque manipulen el parámetro. No modifica ni recalcula liquidaciones. No utiliza los pagos para medir lo generado.

Migración: `20260929020000_estadisticas_comisiones.sql`. No añade dependencias de gráficos: utiliza widgets de Flutter con valores accesibles y barras consultables.

Validación: `node test/commission_statistics_sql_test.cjs` y `flutter test --no-pub`. Las pruebas SQL cubren fechas argentinas, devoluciones de períodos anteriores, negativos, top 10/orden, períodos vacíos, series y autorización. Las pruebas de pantalla cubren anchos de 360/1200, detalle, error/reintento y respuestas fuera de orden.

Posibles extensiones: desde la última liquidación, comparación con el período anterior y efectividad de visitas cuando exista ese registro.
