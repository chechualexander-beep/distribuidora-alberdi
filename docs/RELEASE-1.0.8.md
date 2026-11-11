# Versión 1.0.8 — actualización de PRODUCCIÓN

Rama: `release/1.0.8` (base: `integracion/paso120`).

## Qué cambia

- Cierre de entregas (pedidos y ventas directas) por el circuito V2: si se corta
  internet a mitad del cierre, se recupera sin duplicar cobros.
- Devoluciones y notas de crédito contextuales, cobros contextuales y página de saldos.
- WhatsApp en pedidos, navegación al cliente, fecha de entrega programada en catálogo.
- Stock V2 **instalado y APAGADO**: no mueve existencias. La pantalla de Stock sigue
  oculta (`ENABLE_STOCK=false`).

Fuera de esta versión: boletas internas (`supabase/pendientes/`), Stock encendido.

## Migraciones que recibe producción (13)

Producción tiene hasta `20261006024758`. `supabase db push` aplica, en orden:

| Versión | Qué hace |
|---|---|
| 20261007020000 | Infraestructura de stock (apagada) |
| 20261007030000 | Finalización transaccional V2 y permisos de pedidos |
| 20261010120000 | Registra el cambio manual del 10/10 (baja de personal) |
| 20261023010000-012000 | Protocolo Stock V2 (entra en mantenimiento) |
| 20261104010000 | Venta directa en V2 |
| 20261104020000 | Devoluciones contextuales |
| 20261105010000-020000 | Cobros contextuales |
| 20261106010000 | Fecha de entrega en catálogo |
| 20261111010000 | **Nuevo:** venta directa sin exigir Stock encendido |
| 20261111020000 | **Nuevo:** publica Stock APAGADO y sale de mantenimiento |

Ensayadas el 11/11/2026 sobre una copia de producción (PostgreSQL local): las 13
aplican sin error y quedan `paso_instalacion=3`, `mantenimiento=false`, régimen OFF.
Circuitos ensayados con usuarios simulados: preventista crea y edita venta directa y
pedido; preventista no puede cerrar entregas; admin factura, cierra pedido (pago
completo) y venta directa (pago parcial) por V2; reintento sin duplicar; cobro
contextual; 0 movimientos de stock; notificaciones disparadas. La app vieja de
administración ya no puede cerrar entregas (`contexto_regimen_requerido`).

## Compatibilidad

- Celulares de preventistas con 1.0.7+15: siguen funcionando (crear/editar pedidos y
  ventas directas). Conviene que actualicen igual.
- **PC de administración: tiene que pasar a 1.0.8 el mismo día.** Con 1.0.7+15 no
  puede cerrar entregas.

## Día de la actualización (fuera de horario)

1. Aprobada de antemano en Play Console la 1.0.8+16 (sin liberar). Se compila con
   `flutter build appbundle --flavor production` (desde 1.0.8 Android tiene dos
   variantes: `production` y `qa`, esta última es la app de prueba "testing").
   Si se compila desde otra carpeta (por ejemplo `C:\proyectos\alberdi_release`),
   copiar antes `android\key.properties` desde `C:\proyectos\distribuidora_alberdi`:
   no está en git y sin él la compilación de producción se detiene a propósito.
2. Avisar a los preventistas que no carguen nada durante ~30 minutos.
3. Respaldo fresco: `Paso1-respaldo-y-lectura.ps1` (y copiar al pendrive).
4. Vista previa: `supabase db push --db-url <prod> --dry-run` → deben figurar
   exactamente las 13 migraciones de la tabla.
5. Aplicar: `supabase db push --db-url <prod>`.
6. Instalar la 1.0.8 en la PC de administración y liberar la de Android.
7. Prueba rápida real: cerrar una entrega y una venta directa.

Si algo falla en el paso 5, no se sigue: se restaura desde el respaldo del paso 3.
