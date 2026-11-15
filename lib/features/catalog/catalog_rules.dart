import 'package:flutter/material.dart';

/// Reglas de precio de un catálogo: lista base + excepciones por categoría y por producto.
/// La excepción de producto tiene prioridad sobre la de categoría.
const catalogPriceTypes = ['normal', 'promo', 'interior'];

String catalogTypeLabel(String type) =>
    type.isEmpty ? type : '${type[0].toUpperCase()}${type.substring(1)}';

/// Pide una excepción (categoría o producto + lista). Devuelve null si se cancela.
Future<MapEntry<String, String>?> askCatalogRule(
  BuildContext context,
  List<Map<String, dynamic>> products, {
  required bool product,
}) async {
  final choices = <String, String>{};
  for (final p in products) {
    if (product) {
      choices[p['id'].toString()] = p['nombre'].toString();
    } else {
      final category = p['categoria']?.toString().trim() ?? '';
      if (category.isNotEmpty) choices[category.toLowerCase()] = category;
    }
  }
  final entries = choices.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  String? selected;
  String type = 'promo';
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(
          product ? 'Excepción por producto' : 'Excepción por categoría',
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: product ? 'Producto' : 'Categoría',
                ),
                items: entries
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (value) => update(() => selected = value),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Lista'),
                items: catalogPriceTypes
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(catalogTypeLabel(t)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => update(() => type = value!),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: selected == null
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('Agregar'),
          ),
        ],
      ),
    ),
  );
  if (accepted != true || selected == null) return null;
  return MapEntry(selected!, type);
}

/// Lista de excepciones con botón para quitar cada una.
class CatalogRulesList extends StatelessWidget {
  const CatalogRulesList({
    super.key,
    required this.rules,
    required this.products,
    required this.product,
    required this.onRemove,
  });
  final Map<String, String> rules;
  final List<Map<String, dynamic>> products;
  final bool product;
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    final names = {
      for (final p in products) p['id'].toString(): p['nombre'].toString(),
    };
    return Column(
      children: rules.entries.map((e) {
        final name = product
            ? names[e.key] ?? 'Producto no disponible'
            : e.key;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(name),
          subtitle: Text(catalogTypeLabel(e.value)),
          trailing: IconButton(
            tooltip: 'Quitar excepción',
            onPressed: onRemove == null ? null : () => onRemove!(e.key),
            icon: const Icon(Icons.delete_outline),
          ),
        );
      }).toList(),
    );
  }
}
