# Versión 1.0.9 — interfaz

Rama: `release/1.0.9` (base: `release/1.0.8`). **Solo app: no hay migraciones.**

## Qué cambia

- Tema negro y dorado (logo nuevo) con alto contraste para usar al sol en Android.
  Windows sigue en tema oscuro, con acento dorado.
- Textos grises y colores de estado más oscuros (contraste >= 4,5:1 sobre blanco).
- Armado de pedido / venta directa: la barra superior muestra cliente y lista con
  el color de la lista (y avisa si no es la habitual del cliente); botones de lista
  compactos que se ocultan mientras se escribe; barra "VER PEDIDO" del color de la
  lista; cada producto agregado muestra en qué lista quedó.
- Gestión de reparto: fecha en un botón compacto, buscador por cliente o producto
  (muestra cantidades del producto buscado), "Ver productos" dentro de la tarjeta,
  tarjetas más cortas. En Windows, el buscador también filtra la tabla.
- Ícono y pantalla de inicio con el logo nuevo.
- `.gitattributes`: migraciones y código siempre con saltos de línea LF.

## Actualización

1. Probar el APK de TESTING unos días.
2. Compilar Windows (`flutter build windows`) y Android
   (`flutter build appbundle --flavor production`, con `android\key.properties`).
3. Reemplazar el contenido de `C:\DistribuidoraAlberdi` y publicar en Play Console.
   No hace falta tocar Supabase.
