# Formato del catálogo (`catalogo.json`, formato 1)

La vitrina lee un único archivo, `catalogo.json`, que vive al lado de `index.html`. Cada comercio es una carpeta con su `catalogo.json` y sus fotos (`img/`). Las rutas de `miniatura` son relativas a esa carpeta.

## Ejemplo completo

```json
{
  "formato": 1,
  "comercio": {
    "id": "kiosco-ejemplo",
    "nombre": "Kiosco de Ejemplo",
    "whatsapp": "5490000000000",
    "actualizado": "2026-11-12",
    "tema": "verde",
    "horarios": {
      "lunes": ["08:00-12:00", "17:00-21:00"],
      "martes": ["08:00-21:00"],
      "miercoles": ["08:00-21:00"],
      "jueves": ["08:00-21:00"],
      "viernes": ["08:00-21:00"],
      "sabado": ["09:00-14:00"],
      "domingo": []
    },
    "horarios_nota": "Feriados: consultanos por WhatsApp"
  },
  "productos": [
    {
      "id": "p-001",
      "nombre": "Alfajor triple",
      "descripcion": "Chocolate, 70 g",
      "categoria": "Golosinas",
      "precio_centavos": 120000,
      "precio_anterior_centavos": 140000,
      "unidad": "unidad",
      "miniatura": "img/p-001.jpg",
      "destacado": false,
      "visible": true
    }
  ]
}
```

## Mínimo válido

```json
{
  "formato": 1,
  "comercio": { "id": "mi-kiosco", "nombre": "Mi Kiosco", "whatsapp": "5491112345678", "actualizado": "2026-11-12" },
  "productos": [
    { "id": "p-1", "nombre": "Pan lactal", "categoria": "Panadería", "unidad": "unidad", "precio_centavos": 180000 }
  ]
}
```

## Campos

### Raíz

| Campo | Obligatorio | Descripción |
|---|---|---|
| `formato` | sí | Tiene que ser el número `1`. |
| `comercio` | sí | Datos del comercio (ver abajo). |
| `productos` | sí | Lista de productos. Mínimo 1, **máximo 2000**. |

### `comercio`

| Campo | Obligatorio | Descripción |
|---|---|---|
| `id` | sí | Identificador (slug): minúsculas, números y guiones. Ej.: `"kiosco-ejemplo"`. Con él se guarda el pedido en el celular (`vitrina:kiosco-ejemplo`). |
| `nombre` | sí | Hasta 80 caracteres. |
| `whatsapp` | sí | **Solo dígitos, con código de país**, sin `+`, espacios ni guiones. 8 a 15 dígitos, sin 0 inicial. Ej. Argentina celular: `"5491112345678"`. |
| `actualizado` | sí | Fecha real `AAAA-MM-DD`. Se muestra como `dd/mm/aaaa` (sin zonas horarias). |
| `tema` | no | `"verde"`, `"rojo"`, `"azul"` o `"ambar"`. Si falta o no es válido, se usa `"verde"`. |
| `horarios` | no | Horarios de atención por día (ver "Horarios de atención"). Si falta, el encabezado no muestra nada de horarios. |
| `horarios_nota` | no | Texto corto debajo de la tabla de horarios (máximo 120 caracteres). Solo se muestra si hay `horarios`. |

> **`horario` (singular, texto libre) ya no se usa.** Antes mostraba una línea en el encabezado. Si un JSON todavía lo trae, se ignora como cualquier campo desconocido: no da error y no se muestra. Para mostrar horarios usá `horarios`.

### `productos[]`

| Campo | Obligatorio | Descripción |
|---|---|---|
| `id` | sí | Único en todo el catálogo. 1 a 64 caracteres: letras, números, `.`, `-`, `_`. |
| `nombre` | sí | Hasta 120 caracteres. |
| `categoria` | sí | Hasta 40 caracteres. Las categorías se muestran en el orden en que aparecen. |
| `unidad` | sí | `"unidad"` o `"kg"`. |
| `precio_centavos` | sí | **Entero en centavos**, entre 1 y 1.000.000.000. `$ 1.200` se escribe `120000`. `$ 1.250,50` se escribe `125050`. |
| `precio_anterior_centavos` | no | Entero en centavos. Si es **mayor** que `precio_centavos`, el producto es "Oferta" y se muestra el precio anterior tachado. Si es igual o menor, se ignora. |
| `descripcion` | no | Hasta 200 caracteres. |
| `miniatura` | no | Ruta relativa dentro de la carpeta del comercio (ver reglas). Si no hay o es inválida, se muestra un cuadro con las iniciales. |
| `destacado` | no | `true` lo muestra en el carril "Novedades". Por defecto `false`. |
| `visible` | no | `false` lo oculta (no se puede pedir). Por defecto `true`. |

## Horarios de atención

Opcionales. Si el comercio tiene `horarios`, el encabezado muestra un desplegable **"Horarios de atención"** (cerrado por defecto) con una línea "Hoy: …" y, al abrirlo, una tabla de lunes a domingo. Sin `horarios`, el encabezado muestra solo el nombre y "Precios actualizados el…".

```json
"horarios": {
  "lunes": ["08:00-12:00", "17:00-21:00"],
  "martes": ["08:00-21:00"],
  "miercoles": ["08:00-21:00"],
  "jueves": ["08:00-21:00"],
  "viernes": ["08:00-21:00"],
  "sabado": ["09:00-14:00"],
  "domingo": []
},
"horarios_nota": "Feriados: consultanos por WhatsApp"
```

Reglas:

- **Días**: `lunes`, `martes`, `miercoles`, `jueves`, `viernes`, `sabado`, `domingo`, en minúscula y **sin tildes** (en pantalla se ven como "Miércoles" y "Sábado"). Cualquier otra clave es un error.
- Cada día es una **lista de hasta 3 tramos** `"HH:MM-HH:MM"` en 24 hs, con dos dígitos en la hora (`"08:00-12:00"`, no `"8:00-12"`). Una lista vacía `[]` o un día ausente significa **"Cerrado"**.
- Los tramos van **en orden** y **sin pisarse** (que uno termine cuando empieza el siguiente está bien). "Desde" y "hasta" no pueden ser iguales.
- Un tramo puede **cruzar la medianoche** (`"20:00-02:00"`), pero solo como **último** tramo del día.
- `"00:00-24:00"` se muestra como **"Las 24 hs"** y tiene que ser el único tramo del día. `24:00` solo vale como hora de cierre.
- En pantalla los tramos se ven como `8:00 a 12:00 y 17:00 a 21:00` (sin cero a la izquierda).
- `horarios_nota`: texto corto, hasta 120 caracteres, sin caracteres de control.

**Si el bloque está mal, el catálogo igual se carga**: se ignora solo `horarios` (o solo `horarios_nota`), la vitrina se ve sin horarios y la consola del navegador (F12) avisa con la ruta exacta, por ejemplo `comercio.horarios.lunes[1]: formato inválido: usá "HH:MM-HH:MM"…`.

**Limitación — "Hoy"**: el día marcado como "Hoy" sale del día de la semana del **dispositivo** del visitante (`new Date().getDay()`). Si el visitante está en otra zona horaria, puede verse otro día como "hoy". Además, un tramo que cruza la medianoche (`"20:00-02:00"`) se muestra en el día en que empieza; la vitrina no calcula si el comercio "está abierto ahora".

## Cómo se interpretan los precios

- **Siempre en centavos enteros.** Nunca decimales: `1200.5` es un error.
- Productos por **unidad**: el pedido va de 1 en 1 (máximo 99). El precio es por unidad.
- Productos por **kg**: el pedido va de a 250 g (¼ kg), máximo 10 kg. El precio es **por kilo**. Subtotal = `redondear(precio × gramos / 1000)`.
- El total del pedido es la suma de los subtotales ya redondeados.

## Reglas de `miniatura`

Tiene que ser una ruta **relativa** y segura, con extensión `jpg`, `jpeg`, `png`, `webp`, `gif`, `avif` o `svg`:

- Válidas: `img/p-001.jpg`, `foto.webp`, `img/lacteos/queso.png`.
- Se descartan (y se muestra el cuadro de iniciales): rutas con `..`, `//`, `:` (por ejemplo `https://…` o `javascript:…`), `%`, `\`, que empiecen con `/` o con `.`, o sin extensión de imagen.

Una miniatura inválida **no** rechaza el catálogo: solo se ignora.

### Tamaño de las fotos y visor

- Las fotos pueden ser de **hasta 800 px** de lado. Un solo archivo sirve para todo: es la misma URL que se muestra en la miniatura de las listas y carriles y la que se abre en el visor a pantalla completa (no se pide otra).
- Un producto **con foto** tiene la miniatura como botón ("Ver foto de {nombre}") que abre el visor en `#/foto/<id>`; el botón Atrás del celular lo cierra sin salir de la vitrina. Un producto **sin foto** (o cuya foto no carga) muestra el cuadro con iniciales y no tiene botón.
- Las miniaturas se cargan de forma perezosa (`loading="lazy"`): la vitrina no descarga todas las fotos de golpe. Conviene comprimirlas (JPG o WebP, idealmente menos de 150 KB cada una).

## Vista previa del enlace (WhatsApp y similares)

> **La vista previa lee HTML estático, por eso la completa quien arma el sitio.** WhatsApp, Telegram y las redes leen las etiquetas del HTML tal como se publica y **no ejecutan JavaScript**, así que no se pueden completar desde `catalogo.json` en el navegador. Quien produce el sitio (Super POS, al exportar) reemplaza el marcador `<!--VITRINA_META-->` de `index.html`. En desarrollo lo hace `server.cjs` con el `catalogo.json` local.

`src/index.html` trae el marcador `<!--VITRINA_META-->` dentro de `<head>`, **antes** de un `<title>Catálogo</title>` genérico (que es lo que queda si nadie lo reemplaza). La función pura `armarMeta({ nombre, urlPublica, foto, tema })` de `tool/meta.mjs` (no se publica con el sitio) devuelve el bloque que ocupa su lugar. **Lista exacta de etiquetas** (una por línea):

| Etiqueta | Valor |
|---|---|
| `<title>` | `{nombre} · Catálogo` |
| `<meta name="description">` | `Mirá todo lo que vendemos y hacé tu pedido por WhatsApp.` |
| `og:type` | `website` |
| `og:site_name` | `{nombre}` |
| `og:title` | `Catálogo de {nombre}` |
| `og:description` | la misma descripción |
| `og:locale` | `es_AR` |
| `og:url` | `urlPublica` — **solo si hay `urlPublica`** |
| `og:image` | `urlPublica` + `/` + ruta de la foto (URL absoluta) — **solo si hay `urlPublica` y una foto válida** |
| `twitter:card` | `summary_large_image` si hay imagen; `summary` si no |
| `<meta name="theme-color">` | color de acento del tema (`verde` `#1B6B4A`, `rojo` `#9B3A2E`, `azul` `#3A4486`, `ambar` `#8A5A00`; otro valor o falta: verde) |

Reglas:

- **Escape HTML** de todos los valores (`&`, `<`, `>`, `"` y `'`). Las tildes y los emojis del nombre pasan tal cual.
- `nombre` es obligatorio. `tema` inválido o ausente usa verde.
- `urlPublica` tiene que ser una URL `http` o `https` válida, sin usuario ni contraseña; si no, no hay `og:url` ni `og:image`. Se usa como viene en `og:url`; para la imagen se toma el origen y la ruta, sin la barra final ni la query.
- `foto` tiene que ser una **ruta relativa y segura**, con las mismas reglas que `miniatura` (ver arriba: sin `..`, `//`, `:`, `%`, `\`, sin `/` inicial y con extensión de imagen). Si no lo es, se descarta y no hay `og:image`.
- Al reemplazar el marcador también hay que sacar el `<title>Catálogo</title>` genérico para que no queden dos títulos (si queda, el primero gana y el marcador está antes).
- No agrega recursos externos: la CSP no cambia (estas etiquetas son metadatos, no cargan nada).

> **WhatsApp guarda en caché la vista previa de cada enlace.** Si cambiás el nombre o la foto y no se actualiza, para forzar una vista previa nueva agregá `?v=2` al enlace que compartís (y `?v=3` la próxima vez).

## Qué pasa si el archivo está mal

La vitrina es estricta. Si falta algo obligatorio o tiene un valor inválido, **no se carga el catálogo** y el cliente ve:

> No pudimos cargar el catálogo. Probá de nuevo en un rato.

El cliente no ve detalles técnicos. Quien arma el JSON puede abrir la consola del navegador (F12): ahí se listan los errores con la ruta exacta, por ejemplo `productos[3].precio_centavos: tiene que ser un número entero de centavos…`. Se informan como máximo 50 errores.

Los campos desconocidos se ignoran sin error (así otras apps pueden agregar datos propios). Las partes **opcionales** inválidas (una miniatura insegura, un bloque de `horarios`, una `horarios_nota`) tampoco rechazan el catálogo: se ignoran y la consola avisa.

## Errores comunes

| Error | Cómo se arregla |
|---|---|
| `"precio_centavos": 1200` cuando el precio es $ 1.200 | Son centavos: `120000`. |
| `"precio_centavos": "1200"` | Tiene que ser número, no texto. |
| `"precio_centavos": 1200.5` | Tiene que ser entero. |
| `"whatsapp": "+54 9 11 1234-5678"` | Solo dígitos: `"5491112345678"`. |
| `"whatsapp": 5491112345678` | Tiene que ir entre comillas (texto). |
| `"actualizado": "12/11/2026"` | Formato `AAAA-MM-DD`: `"2026-11-12"`. |
| `"unidad": "kilo"` o `"litro"` | Solo `"unidad"` o `"kg"`. |
| `"id"` repetido entre productos | Cada producto necesita un id distinto. |
| `"id": "Kiosco Ejemplo"` en `comercio` | Slug: `"kiosco-ejemplo"`. |
| `"formato": "1"` | Es el número `1`, sin comillas. |
| Más de 2000 productos | Dividí el catálogo o sacá productos. |
| Coma de más al final de una lista u objeto | JSON no admite comas finales. |
| `"destacado": "si"` | Tiene que ser `true` o `false`. |
| `precio_anterior_centavos` menor o igual al precio | No es oferta; se ignora. Para que sea oferta tiene que ser mayor. |
| `"horario": "8 a 22 hs"` | Ya no se usa; se ignora. Usá `horarios` (ver "Horarios de atención"). |
| `"miércoles"` o `"Sábado"` como clave de `horarios` | Sin tildes y en minúscula: `"miercoles"`, `"sabado"`. |
| `"8:00-12"` o `"8:00-12:00"` | Formato `HH:MM-HH:MM` con dos dígitos: `"08:00-12:00"`. |
| `"25:00-26:00"` | Horas de 00:00 a 23:59 (`24:00` solo como cierre). |
| Más de 3 tramos en un día | Máximo 3 por día. |
| `["08:00-12:00", "11:00-14:00"]` | Los tramos se pisan; que no se solapen y estén en orden. |
| `["20:00-02:00", "03:00-05:00"]` | Un tramo que cruza la medianoche solo puede ir al final del día. |
| `"08:00-08:00"` | "Desde" y "hasta" no pueden ser iguales (para las 24 hs usá `"00:00-24:00"`). |
| `"domingo": "cerrado"` | Tiene que ser una lista: `"domingo": []`. |
| `horarios_nota` de más de 120 caracteres | Se ignora la nota; acortala. |
