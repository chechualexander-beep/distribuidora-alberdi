import 'package:flutter/material.dart';

bool useDesktopLayout(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.windows &&
    MediaQuery.sizeOf(context).width >= 900;

String desktopMoney(Object? value) {
  final number = double.tryParse(value?.toString() ?? '') ?? 0;
  final parts = number.toStringAsFixed(2).split('.');
  final grouped = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return '\$$grouped,${parts[1]}';
}

/// Both scroll axes have their own controller; desktop wheel/scrollbars work
/// even inside the administration shell, and text scaling may grow rows.
class DesktopTable extends StatefulWidget {
  const DesktopTable({
    super.key,
    required this.columns,
    required this.rows,
    this.minimumWidth = 720,
  });
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final double minimumWidth;
  @override
  State<DesktopTable> createState() => _DesktopTableState();
}

class _DesktopTableState extends State<DesktopTable> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      return Scrollbar(
        controller: _horizontal,
        thumbVisibility: true,
        notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: box.maxWidth < widget.minimumWidth
                ? widget.minimumWidth
                : box.maxWidth,
            height: box.maxHeight,
            child: Scrollbar(
              controller: _vertical,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _vertical,
                padding: const EdgeInsets.only(bottom: 16),
                child: DataTable(
                  showCheckboxColumn: false,
                  headingRowHeight: 42,
                  dataRowMinHeight: 52,
                  dataRowMaxHeight:
                      52 *
                      MediaQuery.textScalerOf(context).scale(1).clamp(1, 3),
                  horizontalMargin: 16,
                  columnSpacing: 20,
                  headingRowColor: WidgetStatePropertyAll(
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  columns: widget.columns,
                  rows: widget.rows,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

Widget desktopText(String text, {double width = 230}) => Tooltip(
  message: text,
  child: SizedBox(
    width: width,
    child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
  ),
);
