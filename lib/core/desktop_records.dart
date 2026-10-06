import 'package:flutter/material.dart';
import 'desktop_table.dart';

typedef DesktopRecord = Map<String, dynamic>;

class DesktopField {
  const DesktopField(
    this.title,
    this.value, {
    this.numeric = false,
    this.width = 160,
  });
  final String title;
  final Object? Function(DesktopRecord) value;
  final bool numeric;
  final double width;
}

/// Presentation only: callers retain their queries, filters and action handlers.
class DesktopRecords extends StatelessWidget {
  const DesktopRecords({
    super.key,
    required this.records,
    required this.fields,
    this.onOpen,
    this.actions,
    this.leading,
    this.embedded = false,
  });
  final List<DesktopRecord> records;
  final List<DesktopField> fields;
  final ValueChanged<DesktopRecord>? onOpen;
  final Widget Function(DesktopRecord)? actions;
  final Widget Function(DesktopRecord)? leading;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final table = DesktopTable(
      minimumWidth:
          fields.fold<double>(0, (sum, f) => sum + f.width + 20) +
          (actions == null ? 0 : 112) +
          (leading == null ? 0 : 60) +
          32,
      columns: [
        if (leading != null) const DataColumn(label: Text('Selección')),
        for (final field in fields)
          DataColumn(
            label: Flexible(
              child: Text(
                field.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            numeric: field.numeric,
          ),
        if (actions != null) const DataColumn(label: Text('Acciones')),
      ],
      rows: [
        for (final record in records)
          DataRow(
            key: record['id'] == null ? null : ValueKey(record['id']),
            onSelectChanged: onOpen == null ? null : (_) => onOpen!(record),
            cells: [
              if (leading != null) DataCell(leading!(record)),
              for (final f in fields)
                DataCell(
                  f.value(record) is Widget
                      ? f.value(record) as Widget
                      : SizedBox(
                          width: f.width,
                          child: Tooltip(
                            message: f.value(record)?.toString() ?? '—',
                            child: Text(
                              f.value(record)?.toString() ?? '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: f.numeric
                                  ? TextAlign.right
                                  : TextAlign.left,
                            ),
                          ),
                        ),
                ),
              if (actions != null) DataCell(actions!(record)),
            ],
          ),
      ],
    );
    if (!embedded) return table;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 3.0);
    return SizedBox(
      height: (records.length * 52 * scale + 64).clamp(116, 480).toDouble(),
      child: table,
    );
  }
}

String recordClient(DesktopRecord row) =>
    (row['clientes'] as Map?)?['nombre_comercio']?.toString() ?? 'Cliente';
String desktopDate(Object? value) {
  final d = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  return d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String recordSeller(DesktopRecord row) {
  final user = row['usuarios'] as Map?;
  return [
    user?['nombre'],
    user?['apellido'],
  ].where((v) => v != null && v.toString().isNotEmpty).join(' ');
}

Widget recordObservation(DesktopRecord row) {
  final text = row['observacion']?.toString().trim() ?? '';
  if (text.isEmpty) return const Text('—');
  return Tooltip(
    message: text,
    child: SizedBox(
      width: 180,
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.amber,
            size: 20,
            semanticLabel: 'Pedido con observación',
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    ),
  );
}

/// Constrains long forms while retaining the existing field order and validation.
class DesktopForm extends StatelessWidget {
  const DesktopForm({super.key, required this.child, this.maxWidth = 1040});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => !useDesktopLayout(context)
      ? child
      : Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        );
}

class DesktopFormList extends StatelessWidget {
  const DesktopFormList({super.key, required this.children, this.padding});
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  @override
  Widget build(BuildContext context) {
    if (!useDesktopLayout(context)) {
      return ListView(padding: padding, children: children);
    }
    return DesktopForm(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 720) {
            return ListView(padding: padding, children: children);
          }
          final rows = <Widget>[];
          Widget? pending;
          for (final child in children) {
            if (child is SizedBox && child.child == null) continue;
            if (child is FormField || child is TextField) {
              if (pending == null) {
                pending = child;
              } else {
                rows.add(
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: pending),
                        const SizedBox(width: 20),
                        Expanded(child: child),
                      ],
                    ),
                  ),
                );
                pending = null;
              }
            } else {
              if (pending != null) {
                rows.add(
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: pending,
                  ),
                );
                pending = null;
              }
              rows.add(
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: child,
                ),
              );
            }
          }
          if (pending != null) rows.add(pending);
          return ListView(padding: padding, children: rows);
        },
      ),
    );
  }
}
