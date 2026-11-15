# Catálogo web de Distribuidora Alberdi

Este catálogo es Vitrina adaptada a Alberdi: misma pantalla (categorías, buscador, fotos grandes,
pedido con cantidades), pero los datos y el pedido van contra Supabase con el enlace del cliente.

- El enlace lo genera la app (ficha del cliente → **Catálogo web del cliente**):
  `https://distribuidora-alberdi.pages.dev/#token=<64 caracteres>`.
- Sin token válido no se muestra ningún producto ni precio.
- El pedido entra directo a **Pedidos**/**Facturación** con origen `catalogo` (no sale por WhatsApp).
- Si el enlace vence, el cliente ve "venció" y tiene que pedir uno nuevo.
- Si se corta internet al confirmar, el pedido queda guardado en esa pestaña y el botón pasa a
  **Reintentar confirmación**: se reenvía con el mismo identificador, así que nunca se duplica.

## Catálogo general (preventista)

- Lo generan el administrador y los preventistas que él habilita (app → **Catálogo general**;
  el administrador ve ahí los interruptores "Preventistas que pueden generar").
- Enlace: `https://distribuidora-alberdi.pages.dev/#general=<64 caracteres>`. Un mismo enlace
  sirve para muchos clientes.
- Precios: lista base + excepciones por categoría y por producto (igual que el del cliente).
- Vale 7 días o hasta que se revoque. Quitarle el permiso a un preventista corta sus enlaces.
- El cliente escribe su nombre o el de su negocio y el pedido sale **por WhatsApp** al número
  que cargó el preventista (con el código de cada producto). No se crea ningún pedido en Alberdi.
- El enlace queda guardado solo en el teléfono donde se generó; si se pierde, se genera uno
  igual y se revoca el anterior.

## Apariencia (administrador)

App → **Catálogo general** → **Apariencia del catálogo**. Vale para todos los catálogos:
- Color: negro y dorado, rojo, azul, verde o naranja.
- Novedades: productos marcados a mano, cada uno con fecha de fin (se quitan solos).
- Orden de las categorías (las nuevas van al final, por nombre).

El sitio la lee con `obtener_presentacion_catalogo()`; si no responde, muestra el estilo de siempre.

## Archivos

- `src/alberdi-core.js`: adaptación pura (respuesta de Supabase → formato Vitrina, errores, fechas).
- `src/alberdi.js`: llamadas a Supabase (`obtener_catalogo_cliente`, `crear_pedido_catalogo`,
  `obtener_catalogo_general`).
- `src/config.js`: en el repo queda en modo `demo` (sin red, usa `src/catalogo.json`).
- `tool/armar.mjs`: arma los sitios publicables en `dist/`.

## Probar en la PC

```
cd catalogo
npm test            (sin internet; las pruebas de pantalla usan Edge/Chrome si está instalado)
npm start           (abre la demo en http://localhost:8080)
```

## Publicar

```
cd catalogo
node tool/armar.mjs produccion
$env:ALBERDI_TESTING_KEY = (Get-Content C:\AlberdiTesting\config\testing.json | ConvertFrom-Json).SUPABASE_TESTING_KEY
node tool/armar.mjs testing
```

Quedan `dist/produccion` y `dist/testing`. Cada carpeta se sube completa a su proyecto de
Cloudflare Pages (Workers y Pages → proyecto → Crear implementación → subir la carpeta o un ZIP
con su contenido en la raíz):

| Entorno    | Proyecto de Pages           | Dirección                                    |
|------------|-----------------------------|----------------------------------------------|
| Producción | `distribuidora-alberdi`     | https://distribuidora-alberdi.pages.dev      |
| TESTING    | `alberdi-catalogo-testing`  | https://alberdi-catalogo-testing.pages.dev   |

La app sabe cuál usar según el entorno (`AppConfig.catalogUrl`). TESTING nunca apunta al sitio de
producción ni al revés: cada sitio solo puede hablar con su propio Supabase (CSP en `_headers`).

Orden seguro: primero TESTING, probar en el celular, y recién después producción. Para volver
atrás, en Cloudflare Pages se puede reactivar la implementación anterior.
