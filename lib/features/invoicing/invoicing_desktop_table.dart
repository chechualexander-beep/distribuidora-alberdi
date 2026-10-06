import 'package:flutter/material.dart';
import '../../core/desktop_table.dart';

class InvoicingDesktopTable extends StatefulWidget {
  const InvoicingDesktopTable({
    super.key,
    required this.orders,
    required this.onOpen,
    required this.onRefresh,
  });
  final List<Map<String, dynamic>> orders;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final VoidCallback onRefresh;
  @override
  State<InvoicingDesktopTable> createState() => _InvoicingDesktopTableState();
}

class _InvoicingDesktopTableState extends State<InvoicingDesktopTable> {
  String _search = '';
  String? _seller;
  String _sellerName(Map<String, dynamic> p) {
    final u = p['usuarios'] as Map<String, dynamic>?;
    return [
      u?['nombre'],
      u?['apellido'],
    ].where((v) => v != null && v.toString().isNotEmpty).join(' ');
  }

  String _date(Object? value) {
    final d = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return d == null
        ? ''
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final sellers =
        widget.orders
            .map(_sellerName)
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final selected = sellers.contains(_seller) ? _seller : null;
    final filtered = widget.orders.where((p) {
      final c = p['clientes'] as Map<String, dynamic>?;
      final text = '${c?['nombre_comercio'] ?? ''} ${c?['direccion'] ?? ''}'
          .toLowerCase();
      return text.contains(_search.toLowerCase()) &&
          (selected == null || selected == _sellerName(p));
    }).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Buscar cliente o dirección',
                    prefixIcon: Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (s) => setState(() => _search = s.trim()),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(selected),
                  initialValue: selected,
                  decoration: const InputDecoration(
                    labelText: 'Preventista',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    ...sellers.map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(s, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (s) => setState(() => _seller = s),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: widget.onRefresh,
                tooltip: 'Actualizar pedidos',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'No hay pedidos que coincidan con los filtros.',
                    ),
                  )
                : DesktopTable(
                    minimumWidth: 800,
                    columns: const [
                      DataColumn(label: Text('Cliente')),
                      DataColumn(label: Text('Fecha')),
                      DataColumn(label: Text('Preventista')),
                      DataColumn(label: Text('Lista')),
                      DataColumn(label: Text('Importe'), numeric: true),
                      DataColumn(label: Text('Obs.')),
                    ],
                    rows: filtered.map((p) {
                      final c = p['clientes'] as Map<String, dynamic>?;
                      final note = p['observacion']?.toString().trim() ?? '';
                      return DataRow(
                        key: ValueKey(p['id']),
                        onSelectChanged: (_) => widget.onOpen(p),
                        cells: [
                          DataCell(
                            Tooltip(
                              message: c?['direccion']?.toString() ?? '',
                              child: desktopText(
                                c?['nombre_comercio']?.toString() ??
                                    'Cliente sin nombre',
                                width: 210,
                              ),
                            ),
                          ),
                          DataCell(Text(_date(p['created_at']))),
                          DataCell(desktopText(_sellerName(p), width: 115)),
                          DataCell(
                            Text(
                              p['tipo_precio']?.toString().toUpperCase() ?? '',
                            ),
                          ),
                          DataCell(Text(desktopMoney(p['total']))),
                          DataCell(
                            note.isEmpty
                                ? const Text('—')
                                : Tooltip(
                                    message: note,
                                    child: const Icon(
                                      Icons.error_outline,
                                      size: 20,
                                      color: Colors.amber,
                                      semanticLabel: 'Pedido con observación',
                                    ),
                                  ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${filtered.length} de ${widget.orders.length} pedidos'),
              Text(
                'Total visible: ${desktopMoney(filtered.fold<double>(0, (sum, p) => sum + (double.tryParse(p['total']?.toString() ?? '') ?? 0)))}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
