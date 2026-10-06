import 'package:flutter/material.dart';
import '../../core/desktop_records.dart';
import '../../core/desktop_table.dart';
import 'commission_order_detail.dart';

class CommissionGroupsTable extends StatelessWidget {
  const CommissionGroupsTable({super.key, required this.groups});
  final Map<String, List<Map<String, dynamic>>> groups;
  double _sum(DesktopRecord row, String quantity, {bool price = true}) =>
      (row['details'] as List<DesktopRecord>).fold<double>(
        0,
        (sum, d) =>
            sum +
            (double.tryParse(d[quantity]?.toString() ?? '') ?? 0) *
                (price
                    ? double.tryParse(d['precio_unitario']?.toString() ?? '') ??
                          0
                    : 1),
      );
  @override
  Widget build(BuildContext context) => DesktopRecords(
    embedded: true,
    records: groups.entries
        .where((e) => e.value.isNotEmpty)
        .map(
          (e) => <String, dynamic>{
            'id': e.key,
            'details': e.value,
            'cliente':
                ((e.value.first['pedidos'] as Map?)?['clientes']
                    as Map?)?['nombre_comercio'] ??
                'Cliente',
          },
        )
        .toList(),
    fields: [
      DesktopField('Cliente', (r) => r['cliente'], width: 230),
      DesktopField('Pedido', (r) {
        final id = r['id'].toString();
        return id.length > 8 ? id.substring(0, 8).toUpperCase() : id;
      }, width: 90),
      DesktopField(
        'Pedido',
        (r) => desktopMoney(_sum(r, 'cantidad')),
        numeric: true,
        width: 120,
      ),
      DesktopField(
        'Entregado',
        (r) => desktopMoney(_sum(r, 'cantidad_entregada')),
        numeric: true,
        width: 120,
      ),
      DesktopField(
        'No entregado',
        (r) => desktopMoney(_sum(r, 'cantidad_no_entregada')),
        numeric: true,
        width: 120,
      ),
      DesktopField(
        'Comisión',
        (r) => desktopMoney(_sum(r, 'importe_comision', price: false)),
        numeric: true,
        width: 120,
      ),
    ],
    onOpen: (r) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(r['cliente'].toString()),
        content: SizedBox(
          width: 950,
          child: SingleChildScrollView(
            child: CommissionOrderDetail(
              detalles: r['details'] as List<DesktopRecord>,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    ),
  );
}
