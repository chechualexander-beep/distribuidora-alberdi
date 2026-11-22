import 'package:flutter/material.dart';

/// Vistas de una misma pantalla, debajo del título (como PREVENTAS / VENTA DIRECTA en Reparto):
/// por ejemplo "Para facturar · Realizadas". [selected] es el índice de la vista elegida.
PreferredSizeWidget pageSwitch({
  required List<String> labels,
  required int selected,
  required ValueChanged<int> onChanged,
  List<IconData>? icons,
}) => PreferredSize(
  preferredSize: const Size.fromHeight(56),
  child: Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: SegmentedButton<int>(
      key: const Key('vistas'),
      showSelectedIcon: false,
      segments: [
        for (var i = 0; i < labels.length; i++)
          ButtonSegment<int>(
            value: i,
            icon: icons == null ? null : Icon(icons[i]),
            label: Text(labels[i]),
          ),
      ],
      selected: {selected},
      onSelectionChanged: (s) => onChanged(s.first),
    ),
  ),
);
