# Catálogo web de Distribuidora Alberdi

Basado en **Vitrina** (`C:\proyectos\vitrina_catalogo`, copiado y adaptado). HTML + CSS + JavaScript
sin dependencias. El cliente abre el enlace que le genera Alberdi (`#token=…`), ve **sus** precios,
arma el pedido y lo confirma: el pedido entra directo a Alberdi (`crear_pedido_catalogo`), con el
mismo identificador si hay que reintentar (no se duplica).

- `src/` es lo que se publica. `src/config.js` es la configuración **demo** (lee `catalogo.json`, sin red).
- `src/alberdi-core.js`: adaptador puro (respuesta del servidor → formato Vitrina, pedido, errores).
- `src/alberdi.js`: llamadas a Supabase (solo clave publicable).
- `npm start`: vista local en modo demo (http://localhost:4180).
- `npm test`: tests (`node --test`). Los de pantalla usan Edge/Chrome si están instalados.
- `npm run armar`: genera `dist/testing` y `dist/produccion` listos para Cloudflare Pages.

Ver `docs/ALBERDI.md` para publicar.
