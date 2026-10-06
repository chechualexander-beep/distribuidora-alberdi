import 'package:flutter/material.dart';

class CommercialSummaryCard extends StatelessWidget {
  const CommercialSummaryCard({
    super.key,
    required this.title,
    required this.icon,
    required this.total,
    required this.description,
    required this.breakdown,
    required this.note,
  });

  final String title;
  final IconData icon;
  final double total;
  final String description;
  final Map<String, double> breakdown;
  final String note;

  // Conservar centavos permite conciliar el total con el desglose visible.
  String _money(double value) {
    final parts = value.toStringAsFixed(2).split('.');
    final integer = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]}.',
    );
    return '\$$integer,${parts.last}';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          key: PageStorageKey<String>(title),
          tilePadding: const EdgeInsets.all(16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _money(total),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          children: [
            const Divider(),
            for (final entry in breakdown.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(entry.key)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _money(entry.value),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(note, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
