import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

/// Keeps observations visible when scanning the order inbox.
class OrderObservationIndicator extends StatelessWidget {
  final Object? observation;
  const OrderObservationIndicator({super.key, this.observation});

  @override
  Widget build(BuildContext context) {
    final text = observation?.toString().trim() ?? '';
    if (text.isEmpty) return const Icon(Icons.receipt_long_outlined, size: 32);
    return Tooltip(
      message: 'Con observación: $text',
      child: Semantics(
        label: 'Pedido con observación',
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Tonos.of(context).oscuro ? const Color(0xFF3A2A12) : Colors.amber.shade100,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.orange.shade800),
          ),
          child: Icon(
            Icons.priority_high,
            color: Tonos.of(context).oscuro ? Colors.orange.shade300 : Colors.orange.shade900,
          ),
        ),
      ),
    );
  }
}
