import 'package:flutter/material.dart';
import '../../core/desktop_table.dart';
import 'product_photo.dart';

class ProductsDesktopTable extends StatelessWidget {
  const ProductsDesktopTable({super.key, required this.products});
  final List<Map<String, dynamic>> products;
  bool get hasDescriptions => products.any(
    (p) => (p['descripcion']?.toString().trim() ?? '').isNotEmpty,
  );
  @override
  Widget build(BuildContext context) => DesktopTable(
    minimumWidth: hasDescriptions ? 1150 : 900,
    columns: [
      const DataColumn(label: Text('Producto')),
      const DataColumn(label: Text('Código')),
      if (hasDescriptions) const DataColumn(label: Text('Descripción')),
      const DataColumn(label: Text('Normal'), numeric: true),
      const DataColumn(label: Text('Promo'), numeric: true),
      const DataColumn(label: Text('Interior'), numeric: true),
    ],
    rows: products
        .map(
          (p) => DataRow(
            key: ValueKey(p['id']),
            cells: [
              DataCell(
                Row(
                  children: [
                    ProductPhoto(path: p['foto_path']?.toString(), size: 34),
                    const SizedBox(width: 12),
                    desktopText(p['nombre']?.toString() ?? 'Sin nombre'),
                  ],
                ),
              ),
              DataCell(desktopText(p['codigo']?.toString() ?? '', width: 70)),
              if (hasDescriptions)
                DataCell(
                  desktopText(
                    p['descripcion']?.toString().trim() ?? '',
                    width: 260,
                  ),
                ),
              for (final price in [
                'precio_normal',
                'precio_promo',
                'precio_interior',
              ])
                DataCell(Text(desktopMoney(p[price]))),
            ],
          ),
        )
        .toList(),
  );
}
