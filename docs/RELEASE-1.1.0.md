# Versión 1.1.0 — catálogo nuevo, fotos de preventistas y WhatsApp

Rama: `release/1.1.0` (incluye la 1.0.9 de interfaz, que no se publicó por separado).
Migraciones nuevas (3): `20261116010000_catalogo_general`, `20261116020000_catalogo_presentacion`,
`20261116030000_fotos_preventistas`. No tocan pedidos, precios ni stock.

## Qué cambia

- **Interfaz 1.0.9**: tema negro y dorado, lista de precios bien visible al armar pedidos,
  reparto con buscador, logo nuevo.
- **Catálogo web** con la cara de Vitrina (`catalogo/`, se publica `dist/produccion`).
- **Catálogo general** del preventista: enlace para muchos clientes, pedido por WhatsApp,
  7 días o hasta revocarlo; permiso por preventista.
- **Apariencia del catálogo** (administrador): color, novedades con fecha y orden de categorías.
- **Fotos de productos** cargadas por preventistas habilitados (solo la foto), con cámara,
  filtro "Sin foto" y revisión del administrador (Está bien / Deshacer).
- **WhatsApp del pedido**: sin casilla "es un celular", usa directo el teléfono guardado,
  botón "Otro número".
- Resumen del pedido con el cliente en una línea; Gestionar entrega sin comisión (muestra subtotal).

## Orden de la actualización

1. Respaldo de producción y las 3 migraciones (`Paso12-actualizar-produccion.ps1`),
   con pruebas en el servidor que se deshacen solas.
2. Subir `sitio-produccion.zip` al proyecto `distribuidora-alberdi` de Cloudflare Pages.
   (Si se sube antes de las migraciones, el catálogo del cliente sigue andando igual.)
3. Windows: reemplazar el contenido de `C:\DistribuidoraAlberdi` con la carpeta `Release`.
4. Android: subir el `.aab` a producción en Play Console.

Los enlaces de catálogo ya enviados siguen funcionando. La app 1.0.8 sigue funcionando con
la base nueva; las funciones nuevas aparecen al instalar la 1.1.0.
