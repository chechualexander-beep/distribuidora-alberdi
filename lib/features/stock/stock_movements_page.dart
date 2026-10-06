import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/desktop_table.dart';
import 'stock_models.dart';
import 'stock_service.dart';

class StockMovementsPage extends StatefulWidget {
  const StockMovementsPage({
    super.key,
    required this.location,
    required this.service,
  });
  final StockLocation location;
  final StockService service;
  @override
  State<StockMovementsPage> createState() => _StockMovementsPageState();
}

class _StockMovementsPageState extends State<StockMovementsPage> {
  List<StockMovement> _rows = [];
  String _search = '';
  String? _type, _error;
  bool _loading = true, _more = false;
  Timer? _debounce;
  int _request = 0;
  int _nextOffset = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    final request = ++_request;
    final offset = append ? _nextOffset : 0;
    setState(() {
      _loading = true;
      _error = null;
      if (!append) _rows = [];
    });
    try {
      final rows = await widget.service.movements(
        widget.location.id,
        search: _search,
        type: _type,
        offset: offset,
      );
      if (mounted && request == _request) {
        setState(() {
          final seen = append ? _rows.map((r) => r.id).toSet() : <String>{};
          _rows = [if (append) ..._rows, ...rows.where((r) => seen.add(r.id))];
          _nextOffset = offset + rows.length;
          _more = rows.length == StockService.movementPageSize;
        });
      }
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = stockError(error));
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    // Invalidar resultados que pertenecen al filtro anterior inmediatamente.
    ++_request;
    setState(() {
      _search = value;
      _loading = true;
      _rows = [];
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 350), () => _load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Movimientos de stock'),
      actions: [
        IconButton(
          tooltip: 'Actualizar movimientos',
          onPressed: _loading ? null : () => _load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.location.name),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Buscar producto o código',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: _searchChanged,
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: 'todos',
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: [
                    const DropdownMenuItem(
                      value: 'todos',
                      child: Text('Todos'),
                    ),
                    for (final type in [
                      'stock_inicial',
                      'ajuste_entrada',
                      'ajuste_salida',
                    ])
                      DropdownMenuItem(
                        value: type,
                        child: Text(movementLabel(type)),
                      ),
                  ],
                  onChanged: (v) {
                    _debounce?.cancel();
                    _type = v == 'todos' ? null : v;
                    _load();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _load(),
                child: const Text('Reintentar'),
              ),
            ),
          Expanded(
            child: _loading && _rows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                ? Center(
                    child: Text(
                      _error == null
                          ? 'No hay movimientos que coincidan con los filtros.'
                          : 'No se pudo cargar el historial.',
                    ),
                  )
                : DesktopTable(
                    minimumWidth: 1640,
                    columns: const [
                      DataColumn(
                        label: Flexible(
                          child: Text(
                            'Fecha',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Flexible(
                          child: Text(
                            'Producto',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Flexible(
                          child: Text(
                            'Código',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Flexible(
                          child: Text(
                            'Tipo',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Flexible(
                          child: Text(
                            'Anterior',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        numeric: true,
                      ),
                      DataColumn(
                        label: Flexible(
                          child: Text(
                            'Movimiento',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        numeric: true,
                      ),
                      DataColumn(
                        label: Flexible(
                          child: Text(
                            'Nuevo',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        numeric: true,
                      ),
                      DataColumn(
                        label: Flexible(
                          child: Text(
                            'Motivo',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Flexible(
                          child: Text(
                            'Usuario',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Flexible(
                          child: Text(
                            'Observación',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    rows: [
                      for (final row in _rows)
                        DataRow(
                          key: ValueKey(row.id),
                          cells: [
                            DataCell(Text(row.formattedDate)),
                            DataCell(desktopText(row.name, width: 230)),
                            DataCell(desktopText(row.code, width: 70)),
                            DataCell(Text(movementLabel(row.type))),
                            DataCell(Text(row.previous.format())),
                            DataCell(Text(row.delta.format(signed: true))),
                            DataCell(Text(row.quantity.format())),
                            DataCell(desktopText(row.reason, width: 180)),
                            DataCell(desktopText(row.user, width: 160)),
                            DataCell(desktopText(row.observation, width: 200)),
                          ],
                        ),
                    ],
                  ),
          ),
          if (_more && _error == null)
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: _loading ? null : () => _load(append: true),
                child: Text(_loading ? 'Cargando…' : 'Cargar más movimientos'),
              ),
            ),
        ],
      ),
    ),
  );
}
