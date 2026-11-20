# Versión 1.9.1 — Pago mixto y plata con puntos

Rama: `gestion/etapa1`. Sin migraciones (solo la app).

- Al entregar: "¿Cómo quedó el pago?" en una sola ventana: TODO EFECTIVO, TODO TRANSFERENCIA o
  MIXTO O DEJÓ SALDO (dos importes; el otro se completa solo; muestra lo que queda debiendo).
  La entrega lleva una parte y la otra va como cobro del cliente (`registrar_cobro_sin_conexion`);
  sin señal queda en "Pendientes de enviar" detrás de la entrega. Ver `payment_choice.dart`.
- Plata con puntos de miles y decimales solo si existen ($100.000, $1.500,50) en toda la app,
  WhatsApp y PDF (boletas, lista de precios, liquidación de comisiones): `core/money_format.dart`
  reemplaza las ~20 funciones de precio repetidas. Los importes de cobros y de "Plata del negocio"
  muestran los puntos al escribir.
