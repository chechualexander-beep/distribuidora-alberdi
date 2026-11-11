# Vista previa aislada del Catálogo V2

Desde la raíz del repositorio:

```powershell
node catalogo-v2-preview/server.cjs
```

Abrir http://127.0.0.1:4179/ en el navegador. Usar `?sin-bloques=1` para
ver un catálogo sin promociones ni destacados, o `?modo=general` para la
vidriera de solo lectura.

El servidor expone exclusivamente los archivos de esta carpeta declarados en
su lista de permitidos. La CSP bloquea toda conexión de datos. Los productos,
precios, imágenes ilustrativas, vigencia y confirmaciones son ficticios. El
carrito se guarda en la sesión de la pestaña. La confirmación solo genera
una referencia en la interfaz.

`catalogo-core.js` es una copia del núcleo actual para mantener esta carpeta
independiente de los archivos del catálogo publicado. Las miniaturas SVG son
ilustraciones locales de muestra. Al integrar datos reales, la proyección deberá
proporcionar miniaturas y marcas comerciales explícitas.
