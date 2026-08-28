import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'order_detail_page.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  bool _cargando = true;
  String? _error;

  List<Map<String, dynamic>> _pedidos = [];
  String _filtroCliente = '';
DateTimeRange? _filtroFechas;

  @override
  void initState() {
    super.initState();
    _cargarPedidos();
  }

  Future<void> _cargarPedidos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final usuario = Supabase.instance.client.auth.currentUser;

      if (usuario == null) {
        if (!mounted) return;

        setState(() {
          _error = 'No hay una sesión iniciada.';
          _cargando = false;
        });

        return;
      }

      final respuesta = await Supabase.instance.client
          .from('pedidos')
         .select(
  '''
  id,
  created_at,
  estado,
  resultado_entrega,
motivo_no_entrega,
  total,
  cliente_id,
  preventista_id,
  clientes (
    nombre_comercio,
    direccion,
    localidad
  ),
  pedido_detalles (
    cantidad
  )
  ''',
)
          .eq('preventista_id', usuario.id)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _pedidos = List<Map<String, dynamic>>.from(respuesta);
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudieron cargar los pedidos.';
        _cargando = false;
      });
    }
  }

  String _formatearPrecio(dynamic valor) {
    final numero = double.tryParse(valor?.toString() ?? '') ?? 0;
    final entero = numero.round().toString();

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
    final anio = local.year.toString();

    final hora = local.hour.toString().padLeft(2, '0');
    final minuto = local.minute.toString().padLeft(2, '0');

    return '$dia/$mes/$anio $hora:$minuto';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos'),
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
                size: 60,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _cargarPedidos,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_pedidos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 80,
            ),
            SizedBox(height: 20),
            Text(
              'Todavía no hay pedidos',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    final pedidosFiltrados = _pedidos.where((pedido) {
  final cliente =
      pedido['clientes'] as Map<String, dynamic>?;

  final nombreCliente =
      cliente?['nombre_comercio']?.toString().toLowerCase() ?? '';

  final textoBuscado = _filtroCliente.trim().toLowerCase();

  final coincideCliente =
      textoBuscado.isEmpty ||
      nombreCliente.contains(textoBuscado);

  bool coincideFecha = true;

  if (_filtroFechas != null) {
    final fechaPedido =
        DateTime.tryParse(pedido['created_at']?.toString() ?? '');

    if (fechaPedido != null) {
      final fechaLocal = fechaPedido.toLocal();

      final inicio = DateTime(
        _filtroFechas!.start.year,
        _filtroFechas!.start.month,
        _filtroFechas!.start.day,
      );

      final fin = DateTime(
        _filtroFechas!.end.year,
        _filtroFechas!.end.month,
        _filtroFechas!.end.day,
        23,
        59,
        59,
        999,
      );

      coincideFecha =
          !fechaLocal.isBefore(inicio) &&
          !fechaLocal.isAfter(fin);
    } else {
      coincideFecha = false;
    }
  }

  return coincideCliente && coincideFecha;
}).toList();

    return RefreshIndicator(
  onRefresh: _cargarPedidos,
  child: Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          decoration: InputDecoration(
            hintText: 'Buscar cliente...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _filtroCliente.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _filtroCliente = '';
                      });
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onChanged: (valor) {
            setState(() {
              _filtroCliente = valor;
            });
          },
        ),
      ),
              Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
  onPressed: () async {
    final ahora = DateTime.now();

    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(ahora.year + 2),
      initialDateRange: _filtroFechas,
    );

    if (rango != null) {
      setState(() {
        _filtroFechas = rango;
      });
    }
  },
  child: Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(
        Icons.calendar_month_outlined,
        size: 18,
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          _filtroFechas == null
              ? 'Todas las fechas'
              : '${_filtroFechas!.start.day.toString().padLeft(2, '0')}/'
                  '${_filtroFechas!.start.month.toString().padLeft(2, '0')}/'
                  '${_filtroFechas!.start.year}'
                  ' - '
                  '${_filtroFechas!.end.day.toString().padLeft(2, '0')}/'
                  '${_filtroFechas!.end.month.toString().padLeft(2, '0')}/'
                  '${_filtroFechas!.end.year}',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (_filtroFechas != null) ...[
        const SizedBox(width: 6),
        InkWell(
          onTap: () {
            setState(() {
              _filtroFechas = null;
            });
          },
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(
              Icons.close,
              size: 18,
            ),
          ),
        ),
      ],
    ],
  ),
),
          ),
        ),
      Expanded(
        child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: pedidosFiltrados.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final pedido = pedidosFiltrados[index];

          final cliente =
              pedido['clientes'] as Map<String, dynamic>?;

          final nombreCliente =
              cliente?['nombre_comercio']?.toString() ??
                  'Cliente sin nombre';

          final direccion =
              cliente?['direccion']?.toString() ?? '';

          final estado =
              pedido['estado']?.toString() ?? 'pendiente';
              final resultadoEntrega =
    pedido['resultado_entrega']?.toString() ?? 'pendiente';

final motivoNoEntrega =
    pedido['motivo_no_entrega']?.toString() ?? '';
final detalles =
    pedido['pedido_detalles'] as List<dynamic>? ?? [];

final renglones = detalles.length;

final unidades = detalles.fold<int>(
  0,
  (total, detalle) {
    final cantidad = double.tryParse(
          detalle['cantidad']?.toString() ?? '0',
        )?.round() ??
    0;

    return total + cantidad;
  },
);

final idPedido = pedido['id']?.toString() ?? '';

final numeroPedido = idPedido.length >= 8
    ? idPedido.substring(0, 8).toUpperCase()
    : idPedido.toUpperCase();
          return Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.receipt_long),
              ),
              title: Text(
                nombreCliente,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (direccion.isNotEmpty)
                    Text(direccion),
                  const SizedBox(height: 4),
                  Text(
                    _formatearFecha(pedido['created_at']),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Estado: ${estado.toUpperCase()}',
                  ),
                  const SizedBox(height: 4),
Text(
  'Entrega: ${resultadoEntrega.toUpperCase()}',
),
if (resultadoEntrega == 'no_entregado' &&
    motivoNoEntrega.isNotEmpty) ...[
  const SizedBox(height: 4),
  Text(
    'Motivo: $motivoNoEntrega',
  ),
],
                  const SizedBox(height: 4),
Text('Pedido: #$numeroPedido'),
const SizedBox(height: 4),
Text('$renglones renglones • $unidades unidades'),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatearPrecio(pedido['total']),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OrderDetailPage(
                      pedido: pedido,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      ),
],
),
    );
  }
}