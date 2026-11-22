import 'dart:math' as math;

import 'commission_groups_table.dart';
import 'package:distribuidora_alberdi/core/app_theme.dart';
import '../../core/desktop_records.dart';
import '../../core/desktop_table.dart';
import 'commission_statistics_page.dart';
// ignore_for_file: dead_code
import 'package:flutter/material.dart';
import 'settlement_review_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'commission_order_detail.dart';
import 'commission_report_page.dart';
import 'commission_history_page.dart';
import '../../core/page_switch.dart';
import '../../core/argentina_date_utils.dart';
import 'package:distribuidora_alberdi/core/money_format.dart';

class CommissionsPage extends StatefulWidget {
  const CommissionsPage({super.key});

  @override
  State<CommissionsPage> createState() => _CommissionsPageState();
}

class _CommissionsPageState extends State<CommissionsPage> {
  /// 0 Liquidar, 1 Historial.
  int _vista = 0;
  bool _cargando = true;
  String? _error;

  List<Map<String, dynamic>> _usuarios = [];
  String? _preventistaId;

  DateTime _desde = DateTime.now().subtract(const Duration(days: 30));

  DateTime _hasta = DateTime.now();

  /// 'impago': todo lo entregado y sin liquidar; 'semana': lunes a sábado de esta semana
  /// (se liquida los sábados); 'rango': fechas elegidas.
  String _periodo = 'impago';

  List<Map<String, dynamic>> _detalles = [];
  bool _calculoRealizado = false;
  @override
  void initState() {
    super.initState();
    _cargarPreventistas();
  }

  Future<void> _cargarPreventistas() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await Supabase.instance.client
          .from('usuarios')
          .select('id, nombre, apellido, rol, activo')
          .eq('activo', true)
          .order('nombre');

      if (!mounted) return;

      final usuarios = List<Map<String, dynamic>>.from(respuesta);

      setState(() {
        _usuarios = usuarios;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudieron cargar los usuarios.';
        _cargando = false;
      });
    }
  }

  Future<void> _buscarComisiones() async {
    if (_preventistaId == null) {
      _mostrarMensaje('Seleccioná un preventista.');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      _ajustarPeriodo();
      final desde = ArgentinaDateUtils.inicioDiaUtc(
        _periodo == 'impago' ? DateTime(2024) : _desde,
      );

      final hastaExclusivo = ArgentinaDateUtils.finDiaExclusivoUtc(_hasta);
      final client = Supabase.instance.client;

      // De a 1000 filas: "Lo impago" puede traer muchos pedidos.
      final filas = <Map<String, dynamic>>[];
      for (var offset = 0; ; offset += 1000) {
        final pagina = await client
            .from('pedido_detalles')
            .select('''
            id,
            cantidad,
            cantidad_entregada,
            cantidad_no_entregada,
            precio_unitario,
            porcentaje_comision,
            importe_comision,
            tipo_precio,
            productos (
              nombre,
              codigo_original
            ),
            pedidos!inner (
              id,
              created_at,
              fecha_finalizacion,
              preventista_id,
              resultado_entrega,
              clientes (
                nombre_comercio
              )
            )
            ''')
            .eq('pedidos.preventista_id', _preventistaId!)
            .inFilter('pedidos.resultado_entrega', ['entregado', 'parcial'])
            .not('pedidos.estado', 'in', '(cancelado,anulado)')
            .gte('pedidos.fecha_finalizacion', desde.toIso8601String())
            .lt('pedidos.fecha_finalizacion', hastaExclusivo.toIso8601String())
            .order('id')
            .range(offset, offset + 999);
        final lista = List<Map<String, dynamic>>.from(pagina);
        filas.addAll(lista);
        if (lista.length < 1000) break;
      }

      if (!mounted) return;
      final idsRespuesta = filas
          .map((detalle) => detalle['id']?.toString())
          .whereType<String>()
          .toList();

      // Lo ya liquidado, de a 150 (para no armar un pedido demasiado largo).
      final idsLiquidados = <String>{};
      for (var i = 0; i < idsRespuesta.length; i += 150) {
        final tramo = idsRespuesta.sublist(i, math.min(i + 150, idsRespuesta.length));
        final liquidados = await client
            .from('liquidacion_detalles')
            .select('pedido_detalle_id')
            .inFilter('pedido_detalle_id', tramo);
        idsLiquidados.addAll(
          List<Map<String, dynamic>>.from(liquidados)
              .map((fila) => fila['pedido_detalle_id']?.toString())
              .whereType<String>(),
        );
      }

      DateTime? fechaDe(Map<String, dynamic> d) => DateTime.tryParse(
        (d['pedidos'] as Map?)?['fecha_finalizacion']?.toString() ?? '',
      );
      final detallesPendientes = filas
          .where((detalle) => !idsLiquidados.contains(detalle['id']?.toString()))
          .toList()
        ..sort((a, b) {
          final fa = fechaDe(a), fb = fechaDe(b);
          if (fa == null || fb == null) return 0;
          return fb.compareTo(fa);
        });

      if (!mounted) return;
      setState(() {
        _detalles = detallesPendientes;
        _calculoRealizado = true;
        _cargando = false;
        // "Lo impago": el período arranca en el pedido impago más viejo.
        if (_periodo == 'impago') {
          final fechas = detallesPendientes.map(fechaDe).whereType<DateTime>().toList();
          if (fechas.isNotEmpty) {
            final primera = fechas.reduce((a, b) => a.isBefore(b) ? a : b).toUtc().subtract(
              const Duration(hours: 3),
            );
            _desde = DateTime(primera.year, primera.month, primera.day);
          } else {
            _desde = _hasta;
          }
        }
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudieron cargar las comisiones.';
        _cargando = false;
      });
    }
  }

  /// Fechas según el período elegido (la semana va de lunes a sábado).
  void _ajustarPeriodo() {
    final ahora = ArgentinaDateUtils.ahoraArgentina();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    if (_periodo == 'semana') {
      // Domingo: la semana que terminó ayer.
      final base = hoy.weekday == DateTime.sunday ? hoy.subtract(const Duration(days: 1)) : hoy;
      final lunes = base.subtract(Duration(days: base.weekday - 1));
      _desde = lunes;
      _hasta = base;
    } else if (_periodo == 'impago') {
      _hasta = hoy;
    }
  }

  Future<void> _elegirPeriodo(String periodo) async {
    if (periodo == 'rango') {
      final ahora = ArgentinaDateUtils.ahoraArgentina();
      final rango = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2024),
        lastDate: DateTime(ahora.year, ahora.month, ahora.day),
        initialDateRange: DateTimeRange(start: _desde, end: _hasta),
      );
      if (rango == null || !mounted) return;
      setState(() {
        _periodo = 'rango';
        _desde = rango.start;
        _hasta = rango.end;
      });
    } else {
      setState(() => _periodo = periodo);
    }
    if (_preventistaId != null) await _buscarComisiones();
  }

  double _numero(dynamic valor) {
    return double.tryParse(valor?.toString() ?? '0') ?? 0;
  }

  double get _ventaPedida {
    double total = 0;

    for (final detalle in _detalles) {
      total +=
          _numero(detalle['cantidad']) * _numero(detalle['precio_unitario']);
    }

    return total;
  }

  double get _ventaEntregada {
    double total = 0;

    for (final detalle in _detalles) {
      total +=
          _numero(detalle['cantidad_entregada']) *
          _numero(detalle['precio_unitario']);
    }

    return total;
  }

  double get _ventaNoEntregada {
    double total = 0;

    for (final detalle in _detalles) {
      total +=
          _numero(detalle['cantidad_no_entregada']) *
          _numero(detalle['precio_unitario']);
    }

    return total;
  }

  double get _comisionTotal {
    double total = 0;

    for (final detalle in _detalles) {
      total += _numero(detalle['importe_comision']);
    }

    return total;
  }

  Map<String, List<Map<String, dynamic>>> get _detallesPorPedido {
    final grupos = <String, List<Map<String, dynamic>>>{};

    for (final detalle in _detalles) {
      final pedido = detalle['pedidos'] as Map<String, dynamic>?;

      final pedidoId = pedido?['id']?.toString() ?? 'sin-pedido';

      grupos.putIfAbsent(pedidoId, () => <Map<String, dynamic>>[]);

      grupos[pedidoId]!.add(detalle);
    }

    return grupos;
  }

  String _formatearPrecio(double valor) => formatoPesos(valor);

  String _formatearFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    final anio = fecha.year.toString();

    return '$dia/$mes/$anio';
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    // Comisiones: "Liquidar" y "Historial" en la misma pantalla.
    final vistas = pageSwitch(
      labels: const ['Liquidar', 'Historial'],
      icons: const [Icons.payments_outlined, Icons.history],
      selected: _vista,
      onChanged: (v) => setState(() => _vista = v),
    );
    if (_vista == 1) {
      return Scaffold(
        appBar: AppBar(title: const Text('Comisiones'), bottom: vistas),
        body: const CommissionHistoryPage(embedded: true),
      );
    }
    if (_cargando) {
      return Scaffold(
        appBar: AppBar(
          bottom: vistas,
          actions: [
            IconButton(
              icon: const Icon(Icons.assignment_return_outlined),
              tooltip: 'Ajustes por notas de crédito',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      CommissionAdjustmentsPage(preventistaId: _preventistaId),
                ),
              ),
            ),
          ],
          title: const Text('Comisiones'),
        ),
        body: DesktopForm(
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Comisiones'),
        bottom: vistas,
        actions: [
          TextButton.icon(
            // Dorado: en la barra negra, el texto negro no se veía.
            style: TextButton.styleFrom(foregroundColor: AppColors.dorado),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    CommissionStatisticsPage(preventistaId: _preventistaId),
              ),
            ),
            icon: const Icon(Icons.bar_chart),
            label: const Text('Estadísticas'),
          ),
          IconButton(
            icon: const Icon(Icons.assignment_return_outlined),
            tooltip: 'Ajustes por notas de crédito',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    CommissionAdjustmentsPage(preventistaId: _preventistaId),
              ),
            ),
          ),
        ],
      ),
      body: DesktopForm(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 60),
                      const SizedBox(height: 16),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _cargarPreventistas,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _preventistaId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Preventista',
                      border: OutlineInputBorder(),
                    ),
                    items: _usuarios.map((usuario) {
                      final nombre = usuario['nombre']?.toString() ?? '';

                      final apellido = usuario['apellido']?.toString() ?? '';

                      final nombreCompleto = [
                        nombre,
                        apellido,
                      ].where((e) => e.isNotEmpty).join(' ');

                      return DropdownMenuItem<String>(
                        value: usuario['id'].toString(),
                        child: Text(
                          nombreCompleto.isEmpty ? 'Usuario' : nombreCompleto,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (valor) {
                      setState(() {
                        _preventistaId = valor;
                        _detalles = [];
                        _calculoRealizado = false;
                      });
                      // Se calcula solo al elegir el preventista.
                      if (valor != null) _buscarComisiones();
                    },
                  ),

                  const SizedBox(height: 16),

                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<String>(
                      key: const Key('periodo-comisiones'),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: 'impago',
                          icon: Icon(Icons.pending_actions_outlined),
                          label: Text('Lo impago'),
                        ),
                        ButtonSegment(
                          value: 'semana',
                          icon: Icon(Icons.date_range_outlined),
                          label: Text('Esta semana'),
                        ),
                        ButtonSegment(
                          value: 'rango',
                          icon: Icon(Icons.calendar_month_outlined),
                          label: Text('Fechas'),
                        ),
                      ],
                      selected: {_periodo},
                      onSelectionChanged: (s) => _elegirPeriodo(s.first),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _periodo == 'impago'
                        ? (_calculoRealizado
                              ? 'Todo lo entregado y sin liquidar: ${_formatearFecha(_desde)} al ${_formatearFecha(_hasta)}'
                              : 'Todo lo entregado y sin liquidar, sin importar la fecha.')
                        : '${_formatearFecha(_desde)} al ${_formatearFecha(_hasta)}'
                              '${_periodo == 'semana' ? ' (lunes a sábado)' : ''}',
                    style: const TextStyle(color: AppColors.gris),
                  ),
                  const SizedBox(height: 24),

                  if (_detalles.isNotEmpty) ...[
                    const Text(
                      'Resumen',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    _TarjetaResumen(
                      titulo: 'Venta pedida',
                      valor: _formatearPrecio(_ventaPedida),
                    ),
                    _TarjetaResumen(
                      titulo: 'Venta entregada',
                      valor: _formatearPrecio(_ventaEntregada),
                    ),
                    _TarjetaResumen(
                      titulo: 'No entregado',
                      valor: _formatearPrecio(_ventaNoEntregada),
                    ),
                    _TarjetaResumen(
                      titulo: 'COMISIÓN BRUTA (ANTES DE AJUSTES)',
                      valor: _formatearPrecio(_comisionTotal),
                      destacado: true,
                    ),

                    const SizedBox(height: 24),

                    FilledButton.icon(
                      onPressed: () async {
                        if (_preventistaId == null) return;

                        final usuario = _usuarios.firstWhere(
                          (u) => u['id'].toString() == _preventistaId,
                        );

                        final nombre = usuario['nombre']?.toString() ?? '';

                        final apellido = usuario['apellido']?.toString() ?? '';

                        final preventista = [
                          nombre,
                          apellido,
                        ].where((e) => e.isNotEmpty).join(' ');

                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CommissionReportPage(
                              preventista: preventista.isEmpty
                                  ? 'Preventista'
                                  : preventista,
                              preventistaId: _preventistaId!,
                              desde: _desde,
                              hasta: _hasta,
                              ventaPedida: _ventaPedida,
                              ventaEntregada: _ventaEntregada,
                              ventaNoEntregada: _ventaNoEntregada,
                              comisionTotal: _comisionTotal,
                              detalles: _detalles,
                            ),
                          ),
                        );
                        if (mounted) await _buscarComisiones();
                      },
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('VER LIQUIDACIÓN'),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Detalle',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    if (useDesktopLayout(context))
                      CommissionGroupsTable(groups: _detallesPorPedido)
                    else
                      ..._detallesPorPedido.entries.map((entrada) {
                        final detallesPedido = entrada.value;

                        if (detallesPedido.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        final primerDetalle = detallesPedido.first;

                        final pedido =
                            primerDetalle['pedidos'] as Map<String, dynamic>?;

                        final cliente =
                            pedido?['clientes'] as Map<String, dynamic>?;

                        final clienteNombre =
                            cliente?['nombre_comercio']?.toString() ??
                            'Cliente';

                        final pedidoId = pedido?['id']?.toString() ?? '';

                        final numeroPedido = pedidoId.length >= 8
                            ? pedidoId.substring(0, 8).toUpperCase()
                            : pedidoId.toUpperCase();

                        double ventaPedidaPedido = 0;
                        double ventaEntregadaPedido = 0;
                        double ventaNoEntregadaPedido = 0;
                        double comisionPedido = 0;

                        for (final detalle in detallesPedido) {
                          final cantidad = _numero(detalle['cantidad']);

                          final entregada = _numero(
                            detalle['cantidad_entregada'],
                          );

                          final noEntregada = _numero(
                            detalle['cantidad_no_entregada'],
                          );

                          final precio = _numero(detalle['precio_unitario']);

                          ventaPedidaPedido += cantidad * precio;
                          ventaEntregadaPedido += entregada * precio;
                          ventaNoEntregadaPedido += noEntregada * precio;

                          comisionPedido += _numero(
                            detalle['importe_comision'],
                          );
                        }

                        return Card(
                          margin: const EdgeInsets.only(bottom: 14),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  clienteNombre,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Pedido #$numeroPedido',
                                  style: const TextStyle(color: AppColors.gris),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Pedido: ${_formatearPrecio(ventaPedidaPedido)}',
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Entregado: ${_formatearPrecio(ventaEntregadaPedido)}',
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'No entregado: ${_formatearPrecio(ventaNoEntregadaPedido)}',
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Comisión: ${_formatearPrecio(comisionPedido)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Divider(height: 24),
                                CommissionOrderDetail(detalles: detallesPedido),

                                if (false)
                                  ...detallesPedido.map((detalle) {
                                    final producto =
                                        detalle['productos']
                                            as Map<String, dynamic>?;

                                    final nombreProducto =
                                        producto?['nombre']?.toString() ??
                                        'Producto';

                                    final entregada = _numero(
                                      detalle['cantidad_entregada'],
                                    );

                                    final precio = _numero(
                                      detalle['precio_unitario'],
                                    );

                                    final porcentaje = _numero(
                                      detalle['porcentaje_comision'],
                                    );

                                    final comision = _numero(
                                      detalle['importe_comision'],
                                    );

                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            nombreProducto,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Entregado: ${entregada.toStringAsFixed(0)} × ${_formatearPrecio(precio)}',
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Comisión: ${porcentaje.toStringAsFixed(0)}%',
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Generada: ${_formatearPrecio(comision)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 24),
                  ] else ...[
                    const SizedBox(height: 50),
                    Center(
                      child: Text(
                        _calculoRealizado
                            ? (_periodo == 'impago'
                                  ? 'Está todo liquidado: no hay comisiones impagas.'
                                  : 'No hay comisiones sin liquidar en estas fechas. Probá con "Lo impago".')
                            : 'Elegí un preventista: las comisiones se calculan solas.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _TarjetaResumen extends StatelessWidget {
  final String titulo;
  final String valor;
  final bool destacado;

  const _TarjetaResumen({
    required this.titulo,
    required this.valor,
    this.destacado = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(
          titulo,
          style: TextStyle(
            fontWeight: destacado ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        trailing: Text(
          valor,
          style: TextStyle(
            fontSize: destacado ? 20 : 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
