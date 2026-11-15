# Fotos de productos cargadas por preventistas

- El administrador habilita a cada preventista: **Productos → ícono de fotos (arriba) → "Quiénes pueden cargar fotos"**.
- El preventista habilitado ve en **Productos** el botón **Agregar/Cambiar foto** en cada producto y el filtro **Sin foto (N)**.
  En el celular puede **Sacar foto** con la cámara o elegir de la **Galería**. La foto se achica sola (menos de 300 KB).
- Solo cambia la foto: el servidor (`cambiar_foto_producto`) no permite tocar precios, costos ni otros datos.
- Se publica directo en Alberdi y en el catálogo web. Cada cambio queda registrado
  (`productos_fotos_historial`) y aparece en **Fotos de preventistas** para el administrador:
  **Está bien** o **Deshacer** (vuelve a la foto anterior; los archivos anteriores se conservan para esto).
- Quitar el permiso lo bloquea en el momento. Límite: 300 cambios por día por preventista.
- Migración: `20261116030000_fotos_preventistas.sql`. Prueba: `test/fotos_preventistas_escenario.sql`.
