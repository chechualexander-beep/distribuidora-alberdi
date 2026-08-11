import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'commission_history_detail_page.dart';
class CommissionHistoryPage extends StatefulWidget {
  const CommissionHistoryPage({super.key});

  @override
  State<CommissionHistoryPage> createState() =>
      _CommissionHistoryPageState();
}

class _CommissionHistoryPageState
    extends State<CommissionHistoryPage> {
  bool _cargando = true;
  String? _error;

  List<Map<String, dynamic>> _liquidaciones = [];
String? _preventistaSeleccionado;
DateTime? _fechaDesdeFiltro;
DateTime? _fechaHastaFiltro;
  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  Future<void> _cargarHistorial() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await Supabase.instance.client
          .from('liquidaciones')
          .select(
            '''
            id,
            fecha_desde,
            fecha_hasta,
            venta_entregada,
            comision_total,
            estado,
            fecha_pago,
            created_at,
            usuarios (
            id,
              nombre,
              apellido
            )
            ''',
          )
          .order('fecha_hasta', ascending: false);

      if (!mounted) return;

      setState(() {
        _liquidaciones =
            List<Map<String, dynamic>>.from(respuesta);
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudo cargar el historial.';
        _cargando = false;
      });
    }
  }

  double _numero(dynamic valor) {
    return double.tryParse(
          valor?.toString() ?? '0',
        ) ??
        0;
  }

  String _formatearPrecio(double valor) {
    final entero = valor.round().toString();

    final buffer = StringBuffer();
    int contador = 0;

    for (int i = entero.length - 1; i >= 0; i--) {
      buffer.write(entero[i]);
      contador++;

      if (contador == 3 && i != 0) {
        buffer.write('.');
        contador = 0;
      }
    }

    return '\$${buffer.toString().split('').reversed.join()}';
  }

  String _formatearFecha(dynamic valor) {
    if (valor == null) return '';

    final fecha = DateTime.tryParse(valor.toString());

    if (fecha == null) {
      return valor.toString();
    }

    final local = fecha.toLocal();

    final dia = local.day.toString().padLeft(2, '0');
    final mes = local.month.toString().padLeft(2, '0');

    return '$dia/$mes/${local.year}';
  }

  String _nombrePreventista(
    Map<String, dynamic> liquidacion,
  ) {
    final usuario =
        liquidacion['usuarios'] as Map<String, dynamic>?;

    final nombre =
        usuario?['nombre']?.toString() ?? '';

    final apellido =
        usuario?['apellido']?.toString() ?? '';

    final nombreCompleto = [
      nombre,
      apellido,
    ].where((e) => e.isNotEmpty).join(' ');

    return nombreCompleto.isEmpty
        ? 'Preventista'
        : nombreCompleto;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Historial de liquidaciones',
        ),
      ),
      body: _construirContenido(),
    );
  }

  Widget _construirContenido() {
    if (_cargando) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 56,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _cargarHistorial,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_liquidaciones.isEmpty) {
      return const Center(
        child: Text(
          'Todavía no hay liquidaciones registradas.',
          textAlign: TextAlign.center,
        ),
      );
    }
final liquidacionesFiltradas =
    _liquidaciones.where((liquidacion) {
  // Filtro por preventista
  if (_preventistaSeleccionado != null) {
    final usuario =
        liquidacion['usuarios']
            as Map<String, dynamic>?;

    final id = usuario?['id']?.toString();

    if (id != _preventistaSeleccionado) {
      return false;
    }
  }

  // Filtro Fecha desde
  if (_fechaDesdeFiltro != null) {
    final fechaDesde =
        DateTime.tryParse(
          liquidacion['fecha_desde']?.toString() ?? '',
        );

    if (fechaDesde == null ||
        fechaDesde.isBefore(_fechaDesdeFiltro!)) {
      return false;
    }
  }
// Filtro Fecha hasta
if (_fechaHastaFiltro != null) {
  final fechaHasta =
      DateTime.tryParse(
        liquidacion['fecha_hasta']?.toString() ?? '',
      );

  if (fechaHasta == null ||
      fechaHasta.isAfter(_fechaHastaFiltro!)) {
    return false;
  }
}
  return true;
}).toList();
          final preventistasDisponibles = <String, String>{};

for (final liquidacion in _liquidaciones) {
  final usuario =
      liquidacion['usuarios']
          as Map<String, dynamic>?;

  final id = usuario?['id']?.toString();

  if (id != null && id.isNotEmpty) {
    preventistasDisponibles[id] =
        _nombrePreventista(liquidacion);
  }
}
    return RefreshIndicator(
      onRefresh: _cargarHistorial,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: liquidacionesFiltradas.length + 4,
        separatorBuilder: (_, _) =>
            const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
  return DropdownButtonFormField<String?>(
    initialValue: _preventistaSeleccionado,
    decoration: const InputDecoration(
      labelText: 'Preventista',
      border: OutlineInputBorder(),
    ),
    items: [
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Todos los preventistas'),
      ),
      ...preventistasDisponibles.entries.map(
        (entry) => DropdownMenuItem<String?>(
          value: entry.key,
          child: Text(entry.value),
        ),
      ),
    ],
    onChanged: (valor) {
      setState(() {
        _preventistaSeleccionado = valor;
      });
    },
  );
}
if (index == 1) {
  return OutlinedButton.icon(
    onPressed: () async {
      final fecha = await showDatePicker(
        context: context,
        initialDate: _fechaDesdeFiltro ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );

      if (fecha != null) {
        setState(() {
          _fechaDesdeFiltro = fecha;
        });
      }
    },
    icon: const Icon(Icons.calendar_month),
    label: Text(
      _fechaDesdeFiltro == null
          ? 'Fecha desde'
          : 'Desde: ${_fechaDesdeFiltro!.day.toString().padLeft(2, '0')}/${_fechaDesdeFiltro!.month.toString().padLeft(2, '0')}/${_fechaDesdeFiltro!.year}',
    ),
  );
}
if (index == 2) {
  return OutlinedButton.icon(
    onPressed: () async {
      final fecha = await showDatePicker(
        context: context,
        initialDate: _fechaHastaFiltro ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );

      if (fecha != null) {
        setState(() {
          _fechaHastaFiltro = fecha;
        });
      }
    },
    icon: const Icon(Icons.calendar_month),
    label: Text(
      _fechaHastaFiltro == null
          ? 'Fecha hasta'
          : 'Hasta: ${_fechaHastaFiltro!.day.toString().padLeft(2, '0')}/${_fechaHastaFiltro!.month.toString().padLeft(2, '0')}/${_fechaHastaFiltro!.year}',
    ),
  );
}
if (index == 3) {
  return OutlinedButton.icon(
    onPressed: () {
      setState(() {
        _preventistaSeleccionado = null;
        _fechaDesdeFiltro = null;
        _fechaHastaFiltro = null;
      });
    },
    icon: const Icon(Icons.filter_alt_off),
    label: const Text('Limpiar filtros'),
  );
}
          final liquidacion =
    liquidacionesFiltradas[index - 4];

          final preventista =
              _nombrePreventista(liquidacion);

          final fechaDesde =
              _formatearFecha(
                liquidacion['fecha_desde'],
              );

          final fechaHasta =
              _formatearFecha(
                liquidacion['fecha_hasta'],
              );

          final estado =
              liquidacion['estado']
                      ?.toString()
                      .toUpperCase() ??
                  'PENDIENTE';

          final comision =
              _numero(
                liquidacion['comision_total'],
              );

          final ventaEntregada =
              _numero(
                liquidacion['venta_entregada'],
              );

          return Card(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.all(14),
              leading: const CircleAvatar(
                child: Icon(
                  Icons.receipt_long_outlined,
                ),
              ),
              title: Text(
                preventista,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Padding(
                padding:
                    const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$fechaDesde → $fechaHasta',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Venta entregada: ${_formatearPrecio(ventaEntregada)}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Estado: $estado',
                    ),
                  ],
                ),
              ),
              trailing: Column(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                crossAxisAlignment:
                    CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Comisión',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatearPrecio(comision),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
             onTap: () {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CommissionHistoryDetailPage(
        liquidacion: liquidacion,
      ),
    ),
  );
},
            ),
          );
        },
      ),
    );
  }
}