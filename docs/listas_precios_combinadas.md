# Listas de precios combinadas

Productos → Lista de precios → Personalizada.

1. Elegir un precio base: Normal, Promo o Interior.
2. Elegir excepciones por categoría (por ejemplo Balanceados → Promo).
3. Revisar las categorías desplegables y los importes. Las etiquetas de modalidad son internas.
4. Generar y revisar el PDF; después Compartir PDF o Guardar PDF.

El PDF personalizado utiliza un único color y muestra solo productos y precios finales. El nombre del archivo y el texto para compartir no incluyen modalidades ni nombres de plantillas. Las listas tradicionales conservan sus colores anteriores.

Las plantillas guardan reglas, no importes, por usuario y dispositivo. Al volver a abrir Lista de precios se consultan los productos actuales. Las categorías nuevas toman el precio base. Las excepciones cuyas categorías no están en la lista se señalan en pantalla. No se modifican precios del catálogo ni reglas de venta.

Se conserva el criterio anterior: productos activos, visibles para preventistas y con categoría. Un precio faltante, negativo o no numérico bloquea la generación; los precios cero generan un aviso. Los centavos se conservan en el PDF.

Compartir abre la hoja de compartir del dispositivo: el usuario elige WhatsApp y destinatario. No envía automáticamente. Si WhatsApp no aparece en Windows, guardar el archivo y adjuntarlo manualmente. No se requiere migración de Supabase.

Validación: `flutter test --no-pub test/price_list_test.dart`; análisis de productos sin observaciones. Se generaron y revisaron PDFs de cuatro páginas, comprobando importes combinados, exclusión de productos ocultos/inactivos y ausencia de etiquetas internas. La entrega efectiva mediante WhatsApp requiere probar en el dispositivo con esa aplicación instalada.
