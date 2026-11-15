# Reutilizar Vitrina

Vitrina es una carpeta estática (`src/`). Un comercio nuevo no requiere tocar código: solo cambia su `catalogo.json` y sus fotos.

> Este documento solo **describe** cómo se haría. Nada de lo que está acá (generadores de catálogo, otras apps) está implementado.

## 1. Una vitrina para un comercio nuevo

1. Copiá la carpeta `src/` (ese es el sitio que se publica).
2. Reemplazá `catalogo.json` por el del comercio (ver [FORMATO_CATALOGO.md](FORMATO_CATALOGO.md)).
3. Reemplazá `img/` con sus fotos y apuntalas desde `miniatura` con rutas relativas (`img/p-001.jpg`).
4. Elegí el `tema` y cargá `whatsapp` (solo dígitos con código de país) y `actualizado`. Opcional: `horarios` y `horarios_nota` para el desplegable de horarios.
5. Publicá la carpeta tal cual en un hosting estático. `_headers` (CSP estricta y caché) está pensado para Cloudflare Pages; en otro hosting hay que replicar esos headers (el `<meta>` CSP de `index.html` cubre casi todo, salvo `frame-ancestors`).

Cada comercio es independiente: su carrito se guarda en el celular del cliente con la clave `vitrina:<id del comercio>`, así que dos comercios en el mismo dominio no se pisan.

Fotos: de **hasta 800 px** de lado, comprimidas (JPG o WebP, idealmente menos de 150 KB). Es el mismo archivo en las miniaturas de las listas (que se cargan de forma perezosa) y en el visor a pantalla completa que se abre al tocar la miniatura. Si falta una foto, se muestra un cuadro con las iniciales y no hay botón de visor.

## 2. Agregar un tema nuevo

Los colores de tema viven **solo** en `src/vitrina.css`, como la variable `--acento`.

1. En `src/vitrina.css`, junto a los otros temas, agregá una línea:
   ```css
   :root[data-tema="violeta"] { --acento: #5B3A8A; }
   ```
   El color tiene que dar **contraste ≥ 4,5:1 con blanco** (se usa como fondo con texto blanco y como texto sobre blanco).
2. En `src/core.js`, sumá el nombre a `TEMAS` (por ejemplo `'violeta'`). `resolverTema()` lo va a aceptar y cualquier otro valor seguirá cayendo en `verde`.
3. En `test/contraste.test.js` y `test/tema.test.js`, agregá el tema nuevo a las listas de temas (el test de contraste falla si el color no cumple).
4. Sumalo a la tabla de `tema` en `docs/FORMATO_CATALOGO.md`.

No hace falta tocar `vitrina.js`: el tema se aplica con `<html data-tema="…">`.

## 3. Cómo otra app generaría el `catalogo.json`

La idea es que apps como Super POS o Mi Taller Dulce **exporten** un archivo con este formato y lo publiquen junto a la vitrina. Lo que tendría que hacer un generador:

- **Mapear cada producto vendible** a un objeto de `productos[]`:
  - `id`: un identificador **estable** (el mismo producto siempre con el mismo id). Si el id cambia, los pedidos guardados en los celulares pierden ese producto.
  - `precio_centavos`: precio de venta al público como entero en centavos. Para productos por peso, el precio **por kilo** con `unidad: "kg"`.
  - `precio_anterior_centavos`: solo si hay una oferta vigente (mayor al precio actual).
  - `categoria`, `nombre`, `descripcion`: textos ya listos para mostrar (sin HTML).
  - `visible: false` para lo que no se quiere ofrecer (sin stock, discontinuado). La vitrina no maneja stock: lo decide la app que genera el archivo.
  - `destacado: true` para novedades.
- **Completar `comercio`**: `id` (slug fijo), `nombre`, `whatsapp`, `tema`, opcionalmente `horarios` (y `horarios_nota`), y `actualizado` con la fecha de la exportación (se muestra como "Precios actualizados el…").
- **Validar antes de publicar**: `src/core.js` es un módulo ES sin dependencias, así que un script de Node puede hacer `import { validarCatalogo } from './src/core.js'` y revisar el resultado (`ok` y `errores`) antes de subir el archivo. Un catálogo inválido no se carga en la vitrina.
- **Publicar** `catalogo.json` (y las fotos nuevas en `img/`) en el sitio del comercio. El archivo se pide con `cache: no-cache` y `_headers` también lo marca `no-cache`, así que los cambios se ven al recargar.
- **Respetar el formato**: si en el futuro cambia la estructura, sube `formato` (a 2) y la vitrina sigue rechazando lo que no entiende en vez de mostrar datos mal interpretados.

## 4. Vista previa del enlace (la completa quien arma el sitio)

Cuando alguien comparte el enlace por WhatsApp, la aplicación lee las etiquetas del HTML publicado. **No ejecuta JavaScript**, así que la vista previa no se puede completar desde `catalogo.json` en el navegador: la completa quien produce el sitio. Contrato (detalle y lista exacta de etiquetas en [FORMATO_CATALOGO.md](FORMATO_CATALOGO.md#vista-previa-del-enlace-whatsapp-y-similares)):

1. `src/index.html` trae el marcador `<!--VITRINA_META-->` dentro de `<head>`, antes de un `<title>Catálogo</title>` genérico.
2. Al exportar, el generador llama a `armarMeta({ nombre, urlPublica, foto, tema })` de `tool/meta.mjs` (un módulo ES sin dependencias que importa `src/core.js`; el archivo no se publica con el sitio), reemplaza el marcador por el resultado y saca el `<title>` genérico.
3. `urlPublica` es la dirección pública del sitio; `foto`, la ruta relativa de una foto del catálogo (por ejemplo la del primer producto o un logo). Sin `urlPublica` no hay `og:url` ni `og:image`.
4. Todos los valores se escapan. El reemplazo no agrega recursos externos ni cambia la CSP.

En desarrollo, `npm start` ya hace este reemplazo con `src/catalogo.json` (así se ve el resultado en "ver código fuente"); con `VITRINA_URL_PUBLICA=https://…` se incluyen también `og:url` y `og:image`.

**WhatsApp guarda en caché la vista previa de cada enlace.** Para forzar una nueva después de un cambio, agregá `?v=2` al enlace que se comparte.

## 5. Cosas del diseño a tener en cuenta al reutilizar

- Textos fijos en la interfaz: "El kiosco confirma si hay stock." (pantalla de pedido) y, solo si el comercio tiene `horarios`, "Horarios de atención" y "Hoy:" (cabecera). La cabecera ya no tiene ninguna línea de horario libre. Si se usa en un comercio que no es un kiosco, conviene ajustar el texto de la pantalla de pedido en `src/vitrina.js`.
- Debajo del encabezado hay una línea fija: "Este es el catálogo de {nombre}. Pedís por WhatsApp: no hace falta registrarte ni pagar nada." (el nombre sale de `comercio.nombre`). El texto está en `src/vitrina.js`.
- "Hoy" en los horarios se calcula con el día de la semana del dispositivo del visitante: en otra zona horaria puede verse otro día como "hoy".
- El pedido solo sale por WhatsApp (`https://wa.me/…`). No hay pedidos en servidor, cuentas, pagos ni stock.
- Tope de 2000 productos por catálogo, 99 unidades o 10 kg por producto, y 1500 caracteres por mensaje de WhatsApp.
