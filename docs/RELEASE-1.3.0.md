# Versión 1.3.0 — copia local para trabajar sin señal (Entrega C)

Rama: `release/1.3.0` (base: `main` = 1.2.0 + hoja de ruta). **Solo app: no hay migraciones.**

- **Copia local automática**: cada consulta de la base que funciona (clientes, productos, saldos,
  pedidos, ...) se guarda en el equipo, por usuario. Si después no hay conexión, la pantalla
  muestra lo guardado y la franja dice "Sin conexión: mostrando datos guardados hoy 08:15".
  Con copia guardada se espera menos (8 s con señal, 3 s si ya se sabe que no hay).
- **"Trabajar sin señal → Preparar"** (inicio del celular): baja perfil, clientes, productos con
  sus 3 precios y el saldo de cada cliente (con progreso). Conviene hacerlo con wifi antes de salir.
- Se borra todo al **cerrar sesión**. Las operaciones que guardan datos siguen necesitando
  conexión (eso es la Entrega D); los errores del servidor nunca se tapan con la copia.
- Consultas compartidas entre pantallas y preparación: `lib/core/offline_queries.dart`.
- Pruebas: `test/offline_cache_test.dart`.
