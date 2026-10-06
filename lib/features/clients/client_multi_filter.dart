import 'package:flutter/material.dart';

class ClientMultiFilter<T> extends StatelessWidget {
  const ClientMultiFilter({
    super.key,
    required this.title,
    required this.allLabel,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final String allLabel;
  final Map<T, String> options;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          FilterChip(
            label: Text(allLabel),
            selected: selected.isEmpty,
            onSelected: (_) => onChanged(<T>{}),
          ),
          for (final option in options.entries)
            FilterChip(
              label: Text(option.value),
              selected: selected.contains(option.key),
              onSelected: (checked) {
                final next = Set<T>.from(selected);
                if (checked) {
                  next.add(option.key);
                } else {
                  next.remove(option.key);
                }
                onChanged(next);
              },
            ),
        ],
      ),
    ],
  );
}
