import 'package:flutter/material.dart';

import 'edit_client_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
class ClientDetailPage extends StatefulWidget {
  final Map<String, dynamic> cliente;

  const ClientDetailPage({
    super.key,
    required this.cliente,
  });

  @override
  State<ClientDetailPage> createState() => _ClientDetailPageState();
}

class _ClientDetailPageState extends State<ClientDetailPage> {
  final TextEditingController _importePagoController =
    TextEditingController();
    String? _medioPago;
    final TextEditingController _observacionPagoController =
    TextEditingController();
bool _cargandoCompras = true;
String? _errorCompras;
String? _pedidoPendienteId;
List<Map<String, dynamic>> _ultimasCompras = [];
bool _cargandoSaldo = true;
String? _errorSaldo;

double _totalCompras = 0;
double _totalPagado = 0;
double _saldoPendiente = 0;
@override
void initState() {
  super.initState();
  _cargarUltimasCompras();
  _cargarSaldoPendiente();
}
@override
void dispose() {
  _importePagoController.dispose();
  _observacionPagoController.dispose();
  super.dispose();
}
Future<void> _cargarSaldoPendiente() async {
  try {
    final clienteId = widget.cliente['id']?.toString();

    if (clienteId == null || clienteId.isEmpty) {
      throw Exception('Cliente sin ID');
    }

    final pedidos = await Supabase.instance.client
        .from('pedidos')
        .select('id, total, estado, resultado_entrega')
        .eq('cliente_id', clienteId);

    double totalCompras = 0;
    double totalPagado = 0;

    for (final pedido in pedidos) {
      final estado = pedido['estado']?.toString().toLowerCase() ?? '';
      final resultadoEntrega =
          pedido['resultado_entrega']?.toString().toLowerCase() ?? '';

      final esCobrable =
          estado != 'cancelado' &&
          resultadoEntrega != 'no_entregado';

      if (!esCobrable) continue;

      final totalPedido =
          double.tryParse(pedido['total']?.toString() ?? '') ?? 0;
double pagadoPedido = 0;
      totalCompras += totalPedido;

      final pagos = await Supabase.instance.client
          .from('pedido_pagos')
          .select('importe')
          .eq('pedido_id', pedido['id']);

     for (final pago in pagos) {
  final importePago =
      double.tryParse(pago['importe']?.toString() ?? '') ?? 0;

  pagadoPedido += importePago;
  totalPagado += importePago;
}
final saldoPedido = totalPedido - pagadoPedido;

if (saldoPedido > 0 && _pedidoPendienteId == null) {
  _pedidoPendienteId = pedido['id']?.toString();
}
    }

    if (!mounted) return;

    setState(() {
      _totalCompras = totalCompras;
      _totalPagado = totalPagado;
      _saldoPendiente = totalCompras - totalPagado;

      if (_saldoPendiente < 0) {
        _saldoPendiente = 0;
      }

      _cargandoSaldo = false;
    });
  } catch (_) {
    if (!mounted) return;

    setState(() {
      _errorSaldo = 'No se pudo calcular el saldo pendiente.';
      _cargandoSaldo = false;
    });
  }
}
Future<void> _cargarUltimasCompras() async {
  try {
    final clienteId =
        widget.cliente['id']?.toString();

    if (clienteId == null || clienteId.isEmpty) {
      throw Exception('Cliente sin ID');
    }

    final respuesta =
        await Supabase.instance.client
            .from('pedidos')
            .select(
              '''
              id,
              created_at,
              total,
              estado,
              pedido_detalles (
                cantidad,
                precio_unitario,
                subtotal,
                tipo_precio,
                productos (
                  nombre,
                  codigo
                )
              )
              ''',
            )
            .eq('cliente_id', clienteId)
            .order('created_at', ascending: false)
            .limit(2);

    if (!mounted) return;

    setState(() {
      _ultimasCompras =
          List<Map<String, dynamic>>.from(
        respuesta,
      );
      _cargandoCompras = false;
    });
  } catch (_) {
    if (!mounted) return;

    setState(() {
      _errorCompras =
          'No se pudieron cargar las últimas compras.';
      _cargandoCompras = false;
    });
  }
}
  String _texto(dynamic valor) {
    if (valor == null) return 'Sin información';

    final texto = valor.toString().trim();

    return texto.isEmpty ? 'Sin información' : texto;
  }

  @override
  Widget build(BuildContext context) {
    final comercio = _texto(widget.cliente['nombre_comercio']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ficha del cliente'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const CircleAvatar(
            radius: 42,
            child: Icon(
              Icons.storefront,
              size: 42,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            comercio,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 30),

          _DatoCliente(
            icono: Icons.location_on_outlined,
            titulo: 'Dirección',
            valor: _texto(widget.cliente['direccion']),
          ),

          _DatoCliente(
            icono: Icons.location_city_outlined,
            titulo: 'Localidad',
            valor: _texto(widget.cliente['localidad']),
          ),

          _DatoCliente(
            icono: Icons.person_outline,
            titulo: 'Propietario',
            valor: _texto(widget.cliente['propietario']),
          ),

          _DatoCliente(
            icono: Icons.phone_outlined,
            titulo: 'Teléfono',
            valor: _texto(widget.cliente['telefono']),
          ),

          _DatoCliente(
            icono: Icons.map_outlined,
            titulo: 'Zona',
            valor: _texto(widget.cliente['zona']),
          ),

          _DatoCliente(
            icono: Icons.notes_outlined,
            titulo: 'Observaciones',
            valor: _texto(widget.cliente['observaciones']),
          ),
const SizedBox(height: 24),

if (_cargandoSaldo)
  const Center(
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: CircularProgressIndicator(),
    ),
  )
else if (_errorSaldo != null)
  Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      _errorSaldo!,
      style: const TextStyle(
        color: Colors.red,
      ),
    ),
  )
else
  Card(
    margin: const EdgeInsets.only(bottom: 20),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _saldoPendiente > 0
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline,
              ),
              const SizedBox(width: 8),
              Text(
                _saldoPendiente > 0
                    ? 'Saldo pendiente'
                    : 'Sin saldos pendientes',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Total vendido: \$${_totalCompras.toStringAsFixed(0)}'),
          Text('Total pagado: \$${_totalPagado.toStringAsFixed(0)}'),
          if (_saldoPendiente > 0)
            Text(
              'Pendiente: \$${_saldoPendiente.toStringAsFixed(0)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_saldoPendiente > 0) ...[
  const SizedBox(height: 16),
  SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: () {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Registrar pago'),
       content: Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    TextField(
  controller: _importePagoController,
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  decoration: const InputDecoration(
    labelText: 'Importe',
    prefixText: r'$ ',
    border: OutlineInputBorder(),
  ),
),
    const SizedBox(height: 16),
    DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'Medio de pago',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(
          value: 'Efectivo',
          child: Text('Efectivo'),
        ),
        DropdownMenuItem(
          value: 'Transferencia',
          child: Text('Transferencia'),
        ),
      ],
      initialValue: _medioPago,
onChanged: (value) {
  setState(() {
    _medioPago = value;
  });
},
    ),
    const SizedBox(height: 16),

TextFormField(
  readOnly: true,
  decoration: const InputDecoration(
    labelText: 'Fecha de pago',
    border: OutlineInputBorder(),
    suffixIcon: Icon(Icons.calendar_today_outlined),
  ),
  controller: TextEditingController(
    text:
        '${DateTime.now().day.toString().padLeft(2, '0')}/'
        '${DateTime.now().month.toString().padLeft(2, '0')}/'
        '${DateTime.now().year}',
  ),
),
const SizedBox(height: 16),

TextField(
  controller: _observacionPagoController,
  maxLines: 2,
  decoration: const InputDecoration(
    labelText: 'Observación',
    hintText: 'Ej: transfiere el resto mañana',
    border: OutlineInputBorder(),
  ),
),
  ],
),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
        
        FilledButton(
    onPressed: () async {
      final importe =
          double.tryParse(_importePagoController.text.trim());

      if (importe == null || importe <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ingresá un importe válido'),
          ),
        );
        return;
      }

      if (_medioPago == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seleccioná un medio de pago'),
          ),
        );
        return;
      }

      if (_pedidoPendienteId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontró un pedido pendiente'),
          ),
        );
        return;
      }

    try {
  await Supabase.instance.client
      .from('pedido_pagos')
      .insert({
        'pedido_id': _pedidoPendienteId,
        'importe': importe,
        'medio_pago': _medioPago,
        'fecha_pago': DateTime.now().toIso8601String(),
        'observacion': _observacionPagoController.text.trim().isEmpty
            ? null
            : _observacionPagoController.text.trim(),
      });

  if (!context.mounted) return;

  Navigator.pop(context);

  _importePagoController.clear();
  _observacionPagoController.clear();

  setState(() {
    _medioPago = null;
    _pedidoPendienteId = null;
  });

  await _cargarSaldoPendiente();

  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Pago registrado correctamente'),
    ),
  );
} catch (_) {
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('No se pudo registrar el pago'),
    ),
  );
}
    },
    child: const Text('GUARDAR PAGO'),
  ),
],
      );
    },
  );
},
      icon: const Icon(Icons.payments_outlined),
      label: const Text('REGISTRAR PAGO'),
    ),
  ),
],
        ],
      ),
    ),
  ),

const SizedBox(height: 8),

const Align(
  alignment: Alignment.centerLeft,
  child: Text(
    'Últimas compras',
    style: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
    ),
  ),
),

const SizedBox(height: 12),

if (_cargandoCompras)
  const Center(
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: CircularProgressIndicator(),
    ),
  )
else if (_errorCompras != null)
  Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      _errorCompras!,
      style: const TextStyle(
        color: Colors.red,
      ),
    ),
  )
else if (_ultimasCompras.isEmpty)
  const Padding(
    padding: EdgeInsets.symmetric(vertical: 12),
    child: Text(
      'Este cliente todavía no tiene compras registradas.',
    ),
  )
else
 ..._ultimasCompras.map((pedido) {
  final fecha = DateTime.tryParse(
    pedido['created_at']?.toString() ?? '',
  );

  final fechaTexto = fecha == null
      ? 'Fecha sin información'
      : '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/'
        '${fecha.year}';

  final detalles =
      (pedido['pedido_detalles'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

  return Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined),
              const SizedBox(width: 8),
              Text(
                fechaTexto,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          ...detalles.map((detalle) {
            final producto =
                detalle['productos'] as Map<String, dynamic>?;

            final nombreProducto =
                producto?['nombre']?.toString() ?? 'Producto';

            final cantidad =
                detalle['cantidad']?.toString() ?? '0';

            final precio =
                detalle['precio_unitario']?.toString() ?? '0';

            final tipoPrecio =
                detalle['tipo_precio']?.toString() ?? 'normal';

            String nombreTipoPrecio;

            switch (tipoPrecio) {
              case 'promo':
                nombreTipoPrecio = 'Promo';
                break;
              case 'interior':
                nombreTipoPrecio = 'Interior';
                break;
              default:
                nombreTipoPrecio = 'Normal';
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombreProducto,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('Cantidad: $cantidad'),
                  Text('Precio utilizado: \$$precio'),
                  Text('Lista: $nombreTipoPrecio'),
                ],
              ),
            );
          }),
        ],
      ),
    ),
  );
}),
          const SizedBox(height: 28),

          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () async {
                final actualizado =
                    await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => EditClientPage(
                      cliente: widget.cliente,
                    ),
                  ),
                );

                if (actualizado == true && context.mounted) {
                  Navigator.of(context).pop(true);
                }
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('EDITAR CLIENTE'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatoCliente extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String valor;

  const _DatoCliente({
    required this.icono,
    required this.titulo,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icono),
        title: Text(
          titulo,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(valor),
      ),
    );
  }
}