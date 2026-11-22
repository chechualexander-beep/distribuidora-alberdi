# 1.15.0 — Inicio nuevo y Venta del día (tanda 1 de interfaz)

- **Inicio del teléfono por grupos y con color**: Ventas (azul), Reparto y stock (verde),
  Facturación (violeta), Plata (dorado) y Herramientas (gris). Ya no hay que entrar a
  "Administración": todo está a un toque.
- **Tarjeta "Hoy"** (administrador): para facturar, para entregar, el viaje y los productos en
  negativo; cada cuadro lleva a su pantalla. Sin señal muestra lo último leído. Se actualiza al volver
  al inicio o deslizando hacia abajo.
- **Números en los botones**: Reparto (para entregar) y Facturar (para facturar).
- **Barra de abajo** (administrador, teléfono): Inicio, Pedidos, Reparto y Stock.
- **Anotar gasto** directo desde el inicio (teléfono y Windows), sin pasar por Plata del negocio.
- **Anotar compra** y **Cargar / bajar** directos desde el inicio.
- **"Resumen y estadísticas"** (antes Resumen comercial).
- **Preventista**: inicio corto en color (Ventas, Depósito si tiene el permiso, Mío) y "Esta semana:
  N pedidos".
- **Windows**: menú de la izquierda con los mismos grupos, colores y números; la tarjeta Hoy en el
  inicio; barra de arriba negra con línea dorada como en el teléfono.
- **Reparto: tarjeta "Venta del día"** (se abre y se cierra, y se recuerda): en Preventas, lo entregado
  hoy contra lo esperado, pedidos entregados/parciales/no/faltan y cómo se cobró; en Venta directa, lo
  vendido hoy, ventas, unidades, cobros y lo más vendido. Se actualiza al entregar o vender.

Sin cambios en la base de datos.

## Tanda 2: pantallas unidas
- **Facturar**: "Para facturar" y "Realizadas" en la misma pantalla (antes, dos botones).
- **Comisiones**: "Liquidar" e "Historial" en la misma pantalla (antes, Liquidaciones aparte).
- **Productos** (administrador): "Lista" y "Precios y costos" en la misma pantalla (antes,
  Administrar productos aparte). El preventista sigue viendo solo la lista.
- **Resumen y estadísticas**: botón "Estadísticas" en el Resumen comercial (antes solo estaba dentro
  de Mis comisiones), y flecha para volver en el teléfono.
- Inicio y menú de Windows sin los botones repetidos.

## Tanda 3: Comisiones más simple y títulos parejos
- **Comisiones**: el preventista ya no se corta; período con tres opciones en una fila: **Lo impago**
  (todo lo entregado y sin liquidar, sin importar la fecha; viene elegido), **Esta semana** (lunes a
  sábado) y **Fechas** (un solo selector de rango). Se calcula solo al elegir el preventista o el
  período (ya no hay botón Calcular). Trae de a 1000 filas, para que "Lo impago" no se corte.
- **Liquidación**: "Generar reporte" y "Compartir detalle bruto PDF" arriba, junto a "Revisar y
  registrar liquidación neta".
- **Títulos iguales al botón**: Reparto (antes Gestión de reparto), Resumen y estadísticas, Contar y
  ver stock; el preventista ve "Pedidos".
- **Mensajes de "no hay nada" que dicen qué hacer** (Reparto, Facturar, Realizadas, Stock,
  Historial de comisiones, Comisiones).
- La barra de arriba del inicio usa la misma línea dorada que el resto (no doble).
