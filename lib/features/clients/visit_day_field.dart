import 'package:flutter/material.dart';
import 'client_filters.dart';

class VisitDayField extends StatelessWidget {
  const VisitDayField({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final int? value;
  final ValueChanged<int?>? onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    initialValue: value ?? 0,
    decoration: const InputDecoration(
      labelText: 'Día de visita',
      helperText: 'Día habitual de visita del preventista',
      prefixIcon: Icon(Icons.event_repeat),
      border: OutlineInputBorder(),
    ),
    items: [
      const DropdownMenuItem(value: 0, child: Text('Sin asignar')),
      for (final dia in diasVisita.entries)
        DropdownMenuItem(value: dia.key, child: Text(dia.value)),
    ],
    onChanged: onChanged == null
        ? null
        : (dia) => onChanged!(dia == 0 ? null : dia),
  );
}
