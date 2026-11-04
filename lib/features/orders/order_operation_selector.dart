import 'package:flutter/material.dart';

import '../../core/app_config.dart';

class OrderOperationSelector extends StatelessWidget {
  const OrderOperationSelector({
    super.key,
    required this.value,
    required this.allowDirectSales,
    required this.onChanged,
  });

  final String value;
  final bool allowDirectSales;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SegmentedButton<String>(
        segments: [
          const ButtonSegment(
            value: 'pedido',
            icon: Icon(Icons.shopping_cart_outlined),
            label: Text('Pedido'),
          ),
          ButtonSegment(
            value: 'venta_directa',
            enabled: allowDirectSales,
            icon: const Icon(Icons.point_of_sale),
            label: const Text('Venta directa'),
          ),
        ],
        selected: {value},
        onSelectionChanged: (selection) {
          final operation = selection.first;
          if (operation != 'venta_directa' || allowDirectSales) {
            onChanged(operation);
          }
        },
      ),
      if (!allowDirectSales) ...[
        const SizedBox(height: 8),
        const Text(AppConfig.directSalesTestingMessage),
      ],
    ],
  );
}
