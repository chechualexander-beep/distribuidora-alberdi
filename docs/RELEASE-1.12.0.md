# Versión 1.12.0 — Calculadora

Rama: `gestion/etapa1`. Sin migraciones.

- **Calculadora** (`lib/features/calculator/`), sin publicidad y sin señal:
  - **Margen**: costo, margen (sobre la venta), recargo (sobre el costo), venta y ganancia. Se escribe en
    cualquier casilla y las demás se acomodan; un candado deja fija una (sin candado: al cambiar el
    costo se mantiene el margen; al cambiar otra, el costo). Redondeo de la venta a $10/$50/$100.
  - **Descuento**: precio, descuento %, precio final y costo opcional (ganancia y margen que quedan;
    aviso en rojo si queda debajo del costo).
  - **Por bulto**: a partir de "Manual" o "Traer producto" (precio de la lista; kilos leídos del nombre),
    cuánto trae (800 g, 1, 2,5, 3, 4, 5 kg), lo que piden (100 g o 1 kg), recargo y redondeo. Recargo,
    lo que piden, redondeo y lo que trae quedan guardados en el teléfono como "la última vez".
    Compartir precio por WhatsApp.
  - "Traer producto": el administrador ve el costo y la ganancia; el preventista solo precios.
- Accesos: inicio (celular y Windows), botón dorado arriba a la derecha en los productos del pedido
  (solo "Por bulto"), y "Calculadora" en la edición de productos (abre con costo y precio normal).

Prueba: `test/calculator_test.dart`.
