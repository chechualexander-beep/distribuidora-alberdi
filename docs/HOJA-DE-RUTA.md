# Hoja de ruta — Distribuidora Alberdi

Última actualización: 17/11/2026 (producción en **1.5.0**).

## Orden acordado
1. **Modo sin conexión** (hecho, salvo reparto y cobros: van con el stock)
2. **Stock** (en curso): depósito + vehículo, por producto. Diseño en `docs/STOCK.md`
3. **Gestión del negocio**: gastos, compras, caja y utilidad

## 1. Modo sin conexión
Problema: en zonas rurales, con poca señal, la app tarda minutos o da error. En la oficina,
internet se corta cada tanto. Se usan: pedidos, venta directa, gestión de reparto, cobros de
venta y de saldos, alta de clientes. Volumen: unos 406 clientes (la mayoría de "Mary Ana") y
unos 170 productos. Regla de precio: **vale el que vio el cliente**.

- [x] **A** (1.2.0): consultas con máximo 15 s y Reintentar, franja "Sin conexión", ahorro de datos.
- [x] **B** (1.2.0): facturación en una sola operación (`facturar_pedido`), sin duplicar al reintentar.
- [x] **C** (1.3.0): copia local automática de toda consulta que funcionó (por usuario, se borra al
      cerrar sesión); sin señal se muestra lo guardado con su fecha. Botón "Trabajar sin señal →
      Preparar" en el inicio del celular: baja clientes, productos y el saldo de cada cliente.
- [ ] **D**: operar sin señal con envío automático al volver ("Pendientes de enviar"):
  - [x] **D1** (1.4.0): pedidos y ventas directas nuevos (`crear_pedido_sin_conexion`), con
        historial de precios: se respeta el precio visto hasta 72 h y queda anotado en la observación.
  - [x] **D3** (1.5.0): alta de clientes nuevos sin señal. El id se elige en el teléfono: se le
        pueden hacer pedidos enseguida, el cliente sale primero y sus pedidos detrás.
  - [ ] **D2**: gestiones de reparto y cobros sin señal → se hace **junto con el stock del
        vehículo** (sección 2), porque toca el mismo circuito.

## 2. Stock
Diseño y reglas en `docs/STOCK.md` (por producto "con stock" / "a pedido", depósito + vehículo,
viajes con cierre y diferencias, compras, el stock informa y no traba).
- [x] **Etapa 1**: base de datos (`20261118010000_stock_por_producto`), en TESTING.
- [x] **Etapa 2** (1.6.0): pantallas (contar, cargar/bajar vehículo, compras, cerrar viaje, "Lo que
      llevamos" y venta directa armada desde la carga).
- [ ] **Etapa 3**: reparto y cobros sin señal (D2, abajo).
- [ ] **Etapa 4**: encender en producción.
- Local comercial: cuando se concrete (con el Alberdi POS).

**Reparto y cobros sin señal (D2), decidido el 16/11/2026:**
- Los hace el **administrador** en la calle (los preventistas no entregan ni cobran).
- Queda la **hora real del teléfono** de la entrega o el cobro, no la del envío: una entrega
  del sábado cuenta para la liquidación de esa semana aunque se envíe el lunes. El servidor la
  acepta si es de las últimas 72 h y no está en el futuro (hoy `preparar_finalizacion_contexto`
  exige la hora del servidor; hay que cambiarlo junto con el stock del vehículo).
- Mismo mecanismo que los pedidos: "Pendientes de enviar", envío automático y sin duplicar.

## 3. Gestión del negocio (no contabilidad formal)
El dueño hoy lleva las cuentas "a ojo": el Excel no se usa porque hay que acordarse de anotar
después. El 90 % de los movimientos son del negocio. Idea central: **anotar en el momento,
desde el celular, en segundos, y que funcione sin señal**.

- Botón **"Anotar gasto"** en el inicio: monto + categoría (combustible, luz, mercadería, ...)
  y foto del ticket opcional.
- Los **cobros** ya están en la app: entran solos.
- **"Retiro para el hogar"** como movimiento aparte: no es gasto del negocio (no baja la
  ganancia), pero sale de la caja. Los gastos del hogar no se cargan (los maneja la esposa).
- **Compras a proveedores**: se anotan en Stock (`stock_registrar_compra`, con costo); falta sumarlas a la utilidad.
- **Utilidad por período**: ventas entregadas − costo de mercadería − comisiones − gastos;
  por preventista, categoría o producto. **Caja**: entradas y salidas por medio de pago.
- **Exportar a Excel** para el contador. Fuera de alcance: asientos, balances, IVA, ARCA.
- Reaprovechar el diseño de compras, costos, gastos y equilibrio del **Alberdi POS**
  (`D:\Respaldos\AlberdiPOS-20261115-1830.zip`).

## Otros pendientes
- Catálogo E4: ofertas (precio anterior tachado).
- Play Console: ordenar pistas (la prueba cerrada apunta a TESTING).
- Respaldos automáticos (plan gratuito de Supabase sin copias automáticas).
- Retirar lo viejo del Stock V2 (régimen ON/OFF, `cargar_stock_inicial`, `ajustar_stock`, pantalla vieja) cuando el stock nuevo esté andando.
- Posible versión configurable para otra distribuidora (no hacer todavía; no agregar más
  valores fijos de "Alberdi").

## Dónde está cada cosa
- Código: `C:\proyectos\distribuidora_alberdi` (repositorio) y `C:\proyectos\alberdi_release`
  (compilación). GitHub: `chechualexander-beep/distribuidora-alberdi`.
- Scripts y entregas: `C:\Alberdi\transferencias`. Clave de TESTING: `C:\Alberdi\config\testing.json`.
- Respaldos de la base: `C:\AlberdiRespaldos` (copiar al pendrive).
- Catálogo web: `catalogo/` (ver `catalogo/docs/ALBERDI.md`).
