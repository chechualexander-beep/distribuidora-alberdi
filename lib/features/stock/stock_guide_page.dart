import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/desktop_records.dart';

/// Una sección del instructivo: título, para qué sirve y los pasos (y lo que no hay que hacer).
class _Tema {
  const _Tema(this.icon, this.title, this.steps, {this.avoid = const [], this.adminOnly = false});
  final IconData icon;
  final String title;
  final List<String> steps;
  final List<String> avoid;
  final bool adminOnly;
}

const _temas = <_Tema>[
  _Tema(Icons.local_shipping_outlined, 'Cargar el vehículo', [
    'Entrá a "Cargar vehículo". Se lee el stock de ese momento (arriba ves la hora del dato).',
    'Tocá "Pedidos a entregar" (o "Repetir la última carga"): propone las cantidades, sin pasar de lo que hay en el depósito.',
    'A medida que subís cada cosa al vehículo, marcala en flúor tocando la fila. Si subís otra cantidad, cambiala antes de marcar.',
    'Al terminar, "SUBIR": pasa solo lo marcado. Lo que quedó sin marcar sigue en la lista.',
    'Si cargan dos personas, abran la misma pantalla: la lista es compartida y se ve quién marcó cada cosa.',
  ], avoid: [
    'Subir sin marcar: lo que no está en flúor no se carga.',
    'Cargar algo que la app dice que no hay: primero contalo en el depósito (puede haber un error anterior).',
  ]),
  _Tema(Icons.add_shopping_cart, 'Anotar una compra', [
    'Elegí siempre dónde queda la mercadería: Depósito o Vehículo, el lugar donde físicamente la dejás.',
    'El costo viene cargado: cambialo solo si pagaste otro precio.',
    'Indicá cómo la pagaste (efectivo, billetera, a pagar) para que figure en Plata del negocio.',
  ], avoid: [
    'Anotarla en el vehículo si la bajaste al depósito (o al revés): después el vehículo "tiene" lo que no tiene.',
  ], adminOnly: true),
  _Tema(Icons.point_of_sale, 'Vender con el viaje abierto', [
    'Las ventas directas y las entregas salen del vehículo del viaje.',
    'Si arriba no alcanza, la app toma lo que falta del depósito sola, y queda marcado como "tomado del depósito" en la liquidación.',
    'Si vendés en el depósito algo que no subió, está bien: se ve en la liquidación, no se pierde.',
  ]),
  _Tema(Icons.warehouse_outlined, 'Bajar al depósito', [
    'Entrá a "Bajar al depósito" (o tocá ⇄ dentro de Cargar).',
    'Marcá en flúor lo que bajás. "BAJAR" pasa solo lo marcado, y no más de lo que hay arriba.',
  ]),
  _Tema(Icons.flag_outlined, 'Cerrar el viaje y la liquidación', [
    'Al volver, "Cerrar viaje": contá todo lo que quedó arriba y corregí lo que no coincida.',
    'Elegí si se baja todo al depósito o queda arriba para el próximo viaje.',
    'Se abre la liquidación: por producto, lo que salió, se cargó, se vendió y debería haber, contra lo contado.',
    'A cada diferencia ponele un motivo (rotura, regalo o muestra, error de carga, vencido, faltante, otro). Podés dejarla para después: queda en "A revisar".',
  ], avoid: [
    'Cerrar sin contar: no se ven las diferencias y el error queda para el próximo viaje.',
  ], adminOnly: true),
  _Tema(Icons.fact_check_outlined, 'Contar', [
    'Contá por partes: unos pocos productos por día alcanzan. "A revisar" te dice cuáles hace más de 30 días que no se cuentan.',
    'Lo que contás se aplica directo y queda con tu nombre y la diferencia.',
    'Los cerrados y sus sueltos se cuentan juntos (cajas, bolsas abiertas).',
  ]),
  _Tema(Icons.warning_amber_rounded, 'Cuando algo no cuadra', [
    'Mirá la tarjeta roja "A revisar": negativos, diferencias sin motivo y lo que no se cuenta hace mucho.',
    'Tocá el producto → "Historial": cada movimiento con fecha, lugar, quién y cómo quedó. Ahí se ve en qué paso se descuadró.',
    '"Movimientos" muestra todo lo del día: sirve para repasar al final de la jornada.',
    'Si el número está mal, contalo: el conteo lo corrige y queda registrado.',
  ]),
  _Tema(Icons.shopping_basket_outlined, '"Se compra a pedido"', [
    'Es una etiqueta para la lista de compras: el producto igual lleva stock.',
    'Arranca en 0. Cuando lo comprás, entra; si tenés alguno guardado, contalo.',
  ]),
];

/// Instructivo de Stock (botón (i) arriba en Stock): cómo hacer cada cosa para que no se descuadre.
class StockGuidePage extends StatelessWidget {
  const StockGuidePage({super.key, this.admin = true});

  /// El preventista con ayuda en el depósito no ve lo que es solo del administrador.
  final bool admin;

  @override
  Widget build(BuildContext context) {
    final t = Tonos.of(context);
    final temas = _temas.where((x) => admin || !x.adminOnly).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Cómo usar Stock')),
      body: DesktopForm(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(
                'La regla de oro: la app tiene que saber siempre dónde está la mercadería. '
                'Cada vez que algo cambia de lugar, se anota en el momento y en el lugar correcto.',
                style: TextStyle(fontSize: 15, color: t.filaTexto),
              ),
            ),
            for (final (i, tema) in temas.indexed)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  key: PageStorageKey('guia-$i'),
                  leading: Icon(tema.icon),
                  title: Text(tema.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (n, paso) in tema.steps.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 22,
                              child: Text('${n + 1}.', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            Expanded(child: Text(paso)),
                          ],
                        ),
                      ),
                    for (final evitar in tema.avoid)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: t.oscuro ? const Color(0xFF501313) : const Color(0xFFFCEBEB),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.block, size: 18, color: t.rojo),
                            const SizedBox(width: 6),
                            Expanded(child: Text('Evitá: $evitar', style: TextStyle(color: t.rojo))),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
