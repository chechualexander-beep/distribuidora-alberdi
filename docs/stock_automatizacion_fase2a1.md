# Fase 2A-1 — infraestructura de automatización Stock

Migración: `20261007020000_stock_infraestructura_automatizacion.sql`.

Esta fase instala infraestructura **sin conectar funciones comerciales** y con
automatización OFF. No modifica Flutter, finalización, corrección, recepción NC,
permisos de pedidos/detalles ni funciones manuales de Stock. No carga inventario.

## Tablas, estado y corte

`stock_configuracion`: PK/FK `ubicacion_id`, `automatizacion_activa` false,
`fecha_corte`, `activada_at`, `activada_por` FK usuarios, `integracion_version` 0,
`created_at` y `updated_at`. Se crea una fila idempotente para `deposito_alberdi`,
sin corte ni activación. `integracion_version=0` bloquea la activación incluso
cuando todos los productos estén inicializados. Ningún cliente puede cambiarlo.

No es una bandera cosmética: una fase posterior deberá habilitar la versión
después de integrar todos los caminos comerciales, cerrar permisos de bypass y
resolver el procedimiento físico de corte y las solicitudes en vuelo.

`stock_eventos`: UUID, ubicación FK configuración, tipo/origen/UUID,
FK de origen específica (`pedido_id`, `correccion_id` o `recepcion_id`),
UUID global `solicitud_id`, hash y solicitud normalizada, actor FK usuarios,
régimen capturado, corte aplicable, fecha física explícita y fecha de registro.
CHECK exige exactamente el origen correspondiente. UNIQUE de solicitud y de
tipo/origen: una finalización por pedido, un evento por corrección, uno por
recepción. Una corrección posterior usa un origen/corrección nuevo.

La fecha física es independiente del pedido, factura o creación del evento.
Se exige finita, no futura y proporcionada por la futura función autorizada.
Un hecho anterior al corte no genera delta automáticamente. Eso no decide por
sí solo cómo corregir documentos históricos: las siguientes fases deben
distinguir rectificación de datos y movimiento físico posterior al conteo.

El régimen del evento es inmutable para clientes. Un evento creado OFF sigue
sin mover Stock aunque se reintente después de activar. El evento puede existir
con `items=[]`. En esta fase las operaciones comerciales existentes **no crean
eventos**: registrar OFF se prepara para cuando esas operaciones se conecten.

## Firmas y acceso

Internas, sin EXECUTE para public/anon/authenticated/service_role:

```sql
stock_normalizar_solicitud(jsonb) -> jsonb
stock_registrar_evento(uuid,text,uuid,uuid,jsonb,timestamptz) -> uuid
stock_aplicar_deltas(uuid,uuid,jsonb) -> integer
```

Parámetros de registrar: ubicación, tipo, origen UUID, solicitud UUID,
contenido lógico, fecha física. El actor se obtiene de `auth.uid()`, nunca de
un parámetro. Registrar y aplicar exigen además administrador activo aunque
se invoquen desde una función del propietario. Son SECURITY DEFINER y usan
`search_path=pg_catalog,public,pg_temp`; normalizar es pura e IMMUTABLE.

Públicas para authenticated, pero con comprobación de administrador activo:

```sql
activar_automatizacion_stock(uuid,timestamptz) -> void
diagnosticar_automatizacion_stock(uuid) -> jsonb
```

La activación exige ubicación activa, configuración OFF, corte explícito no
futuro, catálogo no vacío y todos los productos existentes inicializados en
esa ubicación (saldo + movimiento inicial). Incluye activos, inactivos,
ocultos a preventistas y recién creados. Es deliberadamente conservadora:
la base no sabe cuáles productos tienen existencias físicas sin contar.
Después verifica la versión de integración; con 0 siempre rechaza.
**No ejecutar activación real en esta fase.** No existe RPC de desactivación.

La cobertura se verifica con bloqueo SHARE de productos para impedir carreras
con altas/bajas durante esa comprobación. No demuestra que hubo conteo físico
ni que no quedan entregas offline: el bloqueo por versión evita activar hasta
que el protocolo completo esté definido e instalado.

Diagnóstico devuelve configuración, UUID de productos sin inicializar,
conteo de faltantes y eventos totales/con/sin movimientos; no devuelve costos.
Un preventista no puede usarlo. Las dos tablas nuevas tienen RLS y solo SELECT
de administrador activo; ninguna escritura directa ni acceso de anon o
service_role. Sin UPDATE/DELETE de eventos para clientes; no hay RPC para
reescribirlos. El propietario PostgreSQL conserva facultades de mantenimiento.

## Solicitud normalizada, hash e idempotencia

Contrato v1 de `p_contenido`:

```json
{
  "items": [
    {"producto_id": "UUID", "cantidad_delta": -3, "tipo": "entrega"}
  ],
  "motivo": "Entrega confirmada",
  "observacion": null
}
```

Se rechazan claves desconocidas, más de 300 items, producto duplicado,
delta cero, no numérico/no finito, más de tres decimales, rango excesivo y
signo/tipo incompatible. Agregar primero los deltas por producto en las
futuras funciones comerciales. `items=[]` representa un evento sin movimiento.

UUID se convierte al tipo UUID, números a `numeric` con `trim_scale`, se
ordena por producto y se recorta whitespace exterior de motivo/observación.
Observación ausente, NULL o vacía se normaliza a NULL. Orden de claves JSON y
orden de items no influyen; texto restante sí es significativo. Tipos:
entrega/venta_directa para finalización, corrección entrada/salida para
corrección, devolución apta para recepción.

Se hashea exactamente el JSONB de:
`version=1`, ubicación, tipo de evento, origen UUID, época UTC de fecha física
(decimal sin ceros finales) y contenido normalizado. Algoritmo PostgreSQL
nativo: `encode(sha256(convert_to(solicitud::text,'UTF8')),'hex')`.
Sin extensiones nuevas, timestamp de registro, orden incidental ni secretos.
Actor y solicitud UUID son identidades comparadas separadamente.

Misma solicitud UUID + actor + hash **y contenido completo** devuelve mismo
evento. Cualquier diferencia falla PT409. Otro UUID para el mismo origen falla.
Esto evita confiar solo en el estado del pedido y también comprueba contenido
ante una hipotética colisión del hash. La fecha física debe mantenerse estable
en retries; no sustituirla por `now()` en cada intento.

El contrato v1 cubre el evento de deltas, no toda la solicitud comercial de
entrega/pagos. En 2A-2 deberá versionarse/ampliarse el contrato de la operación
para incluir cantidades y pagos relevantes antes de conectar finalización;
no afirmar que esta infraestructura ya hace idempotentes los cobros actuales.

La futura RPC debe crear origen/evento/aplicar deltas y confirmar toda la
operación en **una transacción**. Crear evento y aplicar en dos llamadas no es
el flujo autorizado. No hay COMMIT ni transacción autónoma en los helpers.

## Motor y trazabilidad

`stock_aplicar_deltas(ubicacion,eventoid,items)` compara items normalizados
con los guardados, verifica actor/ubicación y bloquea el evento. Con régimen
OFF o fecha física anterior al corte devuelve 0 sin movimientos. Con ON:
verifica ubicación, existencia de producto, saldo e inicialización; bloquea
los saldos en orden de UUID; valida saldo resultante; actualiza e inserta.

Se conserva el primer bloqueo financiero transaccional `829001`, compartido
con operaciones existentes; luego ubicación, evento, productos/saldos en orden.
Los saldos usan FOR UPDATE, por lo que ajustes manuales también esperan aunque
no usen ese bloqueo financiero global. En esta fase el motor está desconectado.

Retry de un evento aplicado devuelve el número de movimientos existente si
coinciden todos los productos/deltas/tipos. Estado parcial o diferente falla.
La unicidad por evento/producto es defensa adicional, no un sustituto del
bloqueo y comparación. Cantidades negativas y desbordamientos revierten toda
la llamada y, si origen/evento nacieron allí, toda la transacción llamante.

`stock_movimientos.evento_id` es NULL para tipos manuales y obligatorio para
automáticos. FK compuesta a evento/ubicación/actor evita cruzar esas identidades.
`referencia_tipo='stock_evento'` y `referencia_id=evento_id` son obligatorios
para automáticos. UNIQUE parcial `(evento_id,producto_id)`: un movimiento neto
por producto en cada evento, con cabecera que referencia el documento original.

CHECK de tipos y signo conserva los tres anteriores y agrega:
entrega y venta_directa negativos; corrección entrada positiva, salida negativa;
devolución apta positiva. No se genera ningún tipo nuevo al instalar.

Índices nuevos: UNIQUE solicitud y tipo/origen, UNIQUE id/ubicación/actor de
cabecera; historial ubicación/fecha, actor y FK de pedido/corrección/recepción;
UNIQUE parcial movimiento evento/producto. Se mantienen todos los CHECK de
saldo no negativo, consistencia anterior+delta=nueva y FK previos.

Errores: 42501 autorización; PT410 ubicación inactiva/inexistente o sin
configuración; PT404 producto inexistente; PT412 no inicializado o activación
pendiente; PT422 solicitud/cantidad/signo inválido; PT409 evento incompatible
o insuficiencia (esta última lleva `detail.codigo=stock_insuficiente`, producto,
disponible y requerido). No incluyen secretos ni costos. JSON sintácticamente
inválido es rechazado por PostgreSQL antes de entrar al helper.

## Pruebas y límites

`test/stock_automation_sql_test.py` reproduce las 25 migraciones en PostgreSQL
temporal, Auth/Storage mínimos y notificaciones NO-OP. Usa datos ficticios y
dos conexiones reales; no usa red ni Supabase CLI. Configura régimen ON solo
mediante fixture del propietario local, no mediante activación exitosa.

```powershell
$env:STOCK_TEST_PG_BIN='RUTA_A_POSTGRESQL_BIN'
python test/stock_automation_sql_test.py
```

Cubre los 18 casos solicitados, incluidos OFF sin movimiento, permisos,
normalización, reintentos, saldo insuficiente, producto inexistente/no
inicializado, rollback multi-producto y evento, fracciones, unicidad,
concurrencia 5 contra salidas 4 y 3, y activación rechazada. Además finaliza,
corrige, emite NC y recibe dos veces en el esquema completo tras migrar:
no cambian Stock ni eventos, y las nueve definiciones/ACL protegidas coinciden.

La suite histórica Stock puede ejecutarse con el límite de migración nuevo
mediante import/override en memoria, sin editar archivos ya aplicados. Las
suites existentes de permisos, NC, catálogo/asignación, comisiones, resumen y
día de visita mantienen sus fixtures aislados; no ejecutarlas contra remotos.

Pendiente 2A-2: cerrar UPDATE de cantidades entregadas/no entregadas, comisiones
derivadas, estado/resultado/fecha finalización, identidad/origen/ubicación y
otros campos que permitan bypass; impedir altas de detalles tras finalizar.
Conservar facturación compatible (`cantidad_facturada`, comprobante y fecha)
mediante permisos por columna/RPC adecuado. RLS administrativa por sí sola no
impide bypass de un administrador. No se cambiaron esos permisos ahora.

No resuelve todavía reservas, vehículos, entradas por compras, dañados,
reversión de recepciones, histórico anterior al conteo ni operación offline.
La integración completa y el corte físico siguen siendo prerequisites de
activación. No cargar inventario real ni empezar 2A-2 en esta fase.

## Resultado de implementación y aplicación

Aplicación completada exclusivamente en TESTING `blcgugdeluzxvpwqkhjq`, mediante
Management API con referencia fija y verificada por GET inmediatamente antes
de escribir. No se utilizó `db push`, no se cambió vínculo CLI ni `.temp`.
SQL y ledger se confirmaron en la misma transacción; una única solicitud de
escritura. SHA-256 ensayado/aplicado:
`4eef4174bc22698853bbbfced3c9a86ef50d4e68f61f69dc2653c2389df6e071`.

Resultado remoto verificado por lecturas:

| Objeto | Filas | Resultado |
|---|---:|---|
| ubicaciones_stock | 1 | datos previos idénticos |
| stock_actual | 3 | datos previos idénticos |
| stock_movimientos | 6 | movimientos manuales previos idénticos |
| stock_configuracion | 1 | OFF, corte/actor/fecha de activación NULL, versión 0 |
| stock_eventos | 0 | sin eventos comerciales nuevos |
| movimientos automáticos | 0 | ningún movimiento con evento_id |

No se cargó ningún saldo en TESTING. Los 3 saldos y 6 movimientos ya existían
antes de aplicar; se preservaron mediante comparación de fingerprints, no
solo conteos. Los conteos de todas las tablas de aplicación anteriores y Auth
también permanecieron iguales. Todas las funciones/ACL anteriores coincidieron
exactamente tras la instalación, incluidos finalización, bases sin_nc,
corrección, recepción y las cuatro RPC Stock Fase 1. Policies anteriores
preservadas. RLS/grants nuevos correctos; constraints e índices validados.
Las dos tablas nuevas tienen 20 constraints y 10 índices en conjunto; además
se añadió el índice parcial y las constraints descritas en movimientos.
Ledger anterior preservado y versión `20261007020000` exactamente una vez;
contenido del ledger cotejado con el SQL local.

Ensayo 2A-1: 18 grupos de comprobaciones aprobados, que cubren los 18 casos
solicitados y regresión comercial adicional. Concurrencia: espera de Lock
observada en segundo backend y saldo final 1 tras salida de 4; salida de 3
rechazada. Atomicidad: falla del último producto revierte primer saldo,
movimientos y evento cuando se registran en la misma transacción.

Regresión Stock Fase 1 aprobada antes y después de incluir 2A-1; suites de
permisos/pedidos, NC, catálogo SQL, asignación/fotos/comisiones de catálogo,
catálogo web, estadísticas de comisiones, resumen comercial y día de visita
aprobadas. No se ejecutaron tests contra datos remotos. Las primeras iteraciones
del ensayo detectaron un problema de lectura del fixture y nombres ambiguos
en PL/pgSQL; se corrigieron antes de aplicar. No hubo error de instalación.

Archivos nuevos: esta documentación, la migración y
`test/stock_automation_sql_test.py`. Ningún archivo versionado previo cambió.
Los 22 untracked históricos siguen intactos: hay 25 untracked contando los
tres nuevos. Rama `main`, HEAD y origin/main conservan
`252ef8ead60f1ab0360ea2317fd6b633622b3b1f`; nada staged.

PRODUCCIÓN no fue consultada ni modificada. Su vínculo local se conservó.
Sin inventario real, sin Flutter, sin git add, sin commit ni push.
Fase 2A-2 no iniciada. La activación continúa intencionalmente bloqueada.
