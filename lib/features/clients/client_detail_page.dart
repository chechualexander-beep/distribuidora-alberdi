import 'package:flutter/material.dart';

import 'edit_client_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
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
List<Map<String, dynamic>> _pedidosPendientes = [];
List<Map<String, dynamic>> _historialPagos = [];
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
  _cargarHistorialPagos();
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
        .select('id, total, estado, resultado_entrega, created_at')
        .eq('cliente_id', clienteId);

    double totalCompras = 0;
    double totalPagado = 0;
final pedidosPendientes = <Map<String, dynamic>>[];
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

if (saldoPedido > 0) {
  pedidosPendientes.add({
    'id': pedido['id']?.toString(),
    'created_at': pedido['created_at'],
    'total': totalPedido,
    'pagado': pagadoPedido,
    'saldo': saldoPedido,
  });

  _pedidoPendienteId ??= pedido['id']?.toString();
}
    }

    if (!mounted) return;

    setState(() {
      _totalCompras = totalCompras;
      _totalPagado = totalPagado;
      _saldoPendiente = totalCompras - totalPagado;
_pedidosPendientes = pedidosPendientes;
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

Future<void> _cargarHistorialPagos() async {
  try {
    final clienteId = widget.cliente['id']?.toString();

    if (clienteId == null || clienteId.isEmpty) {
      throw Exception('Cliente sin ID');
    }

    final respuesta = await Supabase.instance.client
        .from('pedido_pagos')
        .select('''
          id,
          importe,
          medio_pago,
          fecha_pago,
          observacion,
          pedidos!inner (
            id,
            cliente_id,
            created_at
          )
        ''')
        .eq('pedidos.cliente_id', clienteId)
        .order('fecha_pago', ascending: false);

    if (!mounted) return;

    setState(() {
      _historialPagos =
          List<Map<String, dynamic>>.from(respuesta);
    });
  } catch (_) {
    // Por ahora no mostramos error en pantalla.
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
  Future<void> _abrirEnMapa() async {
  final latitud = widget.cliente['latitud'];
  final longitud = widget.cliente['longitud'];

  if (latitud == null || longitud == null) {
    return;
  }

  final uri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=$latitud,$longitud',
  );

  final abierto = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  );

  if (!abierto && mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No se pudo abrir el mapa.'),
      ),
    );
  }
}
Future<void> _compartirUbicacion() async {
  final latitud = widget.cliente['latitud'];
  final longitud = widget.cliente['longitud'];

  if (latitud == null || longitud == null) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Este cliente no tiene una ubicación guardada.'),
      ),
    );
    return;
  }

  final nombre =
      widget.cliente['nombre_comercio']?.toString() ?? 'Cliente';

  final texto = '''
Ubicación de $nombre

https://www.google.com/maps/search/?api=1&query=$latitud,$longitud
''';

  await SharePlus.instance.share(
    ShareParams(text: texto),
  );
}
String _formatearFechaUbicacion() {
  final valor = widget.cliente['ubicacion_actualizada_at'];

  if (valor == null) {
    return 'Sin fecha de actualización';
  }

  final fecha = DateTime.tryParse(valor.toString());

  if (fecha == null) {
    return 'Sin fecha de actualización';
  }

  final fechaLocal = fecha.toLocal();

  final dia = fechaLocal.day.toString().padLeft(2, '0');
  final mes = fechaLocal.month.toString().padLeft(2, '0');
  final anio = fechaLocal.year.toString();

  final hora = fechaLocal.hour.toString().padLeft(2, '0');
  final minuto = fechaLocal.minute.toString().padLeft(2, '0');

  return '$dia/$mes/$anio $hora:$minuto';
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
          Card(
  margin: const EdgeInsets.only(bottom: 10),
  child: ListTile(
    leading: const Icon(Icons.price_change_outlined),
    title: const Text(
      'Lista de precios habitual',
      style: TextStyle(
        fontWeight: FontWeight.w600,
      ),
    ),
    subtitle: Text(
      switch (widget.cliente['tipo_precio_habitual']?.toString()) {
        'promo' => 'Promo',
        'interior' => 'Interior',
        'normal' => 'Normal',
        _ => 'Sin preferencia',
      },
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () async {
  final seleccion = await showModalBottomSheet<String>(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Lista de precios habitual',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              title: const Text('Normal'),
              onTap: () => Navigator.pop(context, 'normal'),
            ),
            ListTile(
              title: const Text('Promo'),
              onTap: () => Navigator.pop(context, 'promo'),
            ),
            ListTile(
              title: const Text('Interior'),
              onTap: () => Navigator.pop(context, 'interior'),
            ),
            ListTile(
              title: const Text('Sin preferencia'),
              onTap: () => Navigator.pop(context, ''),
            ),
          ],
        ),
      );
    },
  );

  if (seleccion == null) return;
  try {
  await Supabase.instance.client
      .from('clientes')
      .update({
        'tipo_precio_habitual':
            seleccion.isEmpty ? null : seleccion,
      })
      .eq('id', widget.cliente['id']);

  if (!mounted) return;

  setState(() {
    widget.cliente['tipo_precio_habitual'] =
        seleccion.isEmpty ? null : seleccion;
  });

  ScaffoldMessenger.of(this.context).showSnackBar(
    const SnackBar(
      content: Text('Lista habitual actualizada'),
    ),
  );
} catch (_) {
  if (!mounted) return;

  ScaffoldMessenger.of(this.context).showSnackBar(
    const SnackBar(
      content: Text(
        'No se pudo actualizar la lista habitual',
      ),
    ),
  );
}
},
  ),
),
const SizedBox(height: 24),
if (widget.cliente['latitud'] != null &&
    widget.cliente['longitud'] != null) ...[
  Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.location_on_outlined),
              SizedBox(width: 10),
              Text(
                'Ubicación del cliente',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Ubicación guardada'),
          const SizedBox(height: 4),
Text(
  'Actualizada: ${_formatearFechaUbicacion()}',
  style: const TextStyle(
    fontSize: 13,
    color: Colors.grey,
  ),
),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _abrirEnMapa,
              icon: const Icon(Icons.map_outlined),
              label: const Text('ABRIR EN MAPA'),
            ),
          ),
          const SizedBox(height: 8),

SizedBox(
  width: double.infinity,
  child: OutlinedButton.icon(
    onPressed: _compartirUbicacion,
    icon: const Icon(Icons.share_outlined),
    label: const Text('COMPARTIR UBICACIÓN'),
  ),
),
        ],
      ),
    ),
  ),
  const SizedBox(height: 14),
],

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
          if (_pedidosPendientes.isNotEmpty)
  Text(
    '${_pedidosPendientes.length} ${_pedidosPendientes.length == 1 ? 'pedido con saldo pendiente' : 'pedidos con saldo pendiente'}',
    style: const TextStyle(
      fontWeight: FontWeight.w600,
    ),
  ),
          Text('Total vendido: \$${_totalCompras.toStringAsFixed(0)}'),
          Text('Total pagado: \$${_totalPagado.toStringAsFixed(0)}'),
          if (_saldoPendiente > 0)
            Text(
              'Deuda total: \$${_saldoPendiente.toStringAsFixed(0)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_saldoPendiente > 0) ...[
              if (_pedidosPendientes.isNotEmpty) ...[
  const SizedBox(height: 12),

  ..._pedidosPendientes.asMap().entries.map((entry) {
    final pedido = entry.value;
    final createdAt = DateTime.tryParse(
  pedido['created_at']?.toString() ?? '',
);

final fechaPedido = createdAt == null
    ? 'Sin fecha'
    : '${createdAt.day.toString().padLeft(2, '0')}/'
        '${createdAt.month.toString().padLeft(2, '0')}/'
        '${createdAt.year}';

    final total =
        double.tryParse(pedido['total'].toString()) ?? 0;
    final pagado =
        double.tryParse(pedido['pagado'].toString()) ?? 0;
    final saldo =
        double.tryParse(pedido['saldo'].toString()) ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        'Pedido $fechaPedido — Total \$${total.toStringAsFixed(0)} — '
        'Pagado \$${pagado.toStringAsFixed(0)} — '
        'Saldo \$${saldo.toStringAsFixed(0)}',
      ),
    );
  }),
],
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
    DropdownButtonFormField<String>(
      isExpanded: true,
  decoration: const InputDecoration(
    labelText: 'Pedido a pagar',
    border: OutlineInputBorder(),
  ),
  initialValue: _pedidoPendienteId,
  items: _pedidosPendientes.map((pedido) {
    final id = pedido['id'].toString();
    final createdAt = DateTime.tryParse(
  pedido['created_at']?.toString() ?? '',
)?.toLocal();

final fechaPedido = createdAt == null
    ? 'Sin fecha'
    : '${createdAt.day.toString().padLeft(2, '0')}/'
        '${createdAt.month.toString().padLeft(2, '0')}/'
        '${createdAt.year}';
    final total = double.tryParse(pedido['total'].toString()) ?? 0;
    final pagado =
        double.tryParse(pedido['pagado'].toString()) ?? 0;
    final saldo = total - pagado;

    return DropdownMenuItem<String>(
      value: id,
    child: Text(
  '$fechaPedido · \$${saldo.toStringAsFixed(0)} pendiente',
  overflow: TextOverflow.ellipsis,
),
    );
  }).toList(),
  onChanged: (value) {
    setState(() {
      _pedidoPendienteId = value;
    });
  },
),

const SizedBox(height: 16),
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
await _cargarHistorialPagos();
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

if (_historialPagos.isNotEmpty) ...[
  const SizedBox(height: 20),

  const Align(
    alignment: Alignment.centerLeft,
    child: Text(
      'Historial de pagos',
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
  ),

  const SizedBox(height: 12),

  ..._historialPagos.map((pago) {
    final fecha = DateTime.tryParse(
      pago['fecha_pago']?.toString() ?? '',
    );

    final fechaTexto = fecha == null
        ? 'Fecha sin información'
        : '${fecha.day.toString().padLeft(2, '0')}/'
          '${fecha.month.toString().padLeft(2, '0')}/'
          '${fecha.year}';

    final importe =
        double.tryParse(pago['importe']?.toString() ?? '') ?? 0;

    final medio =
        pago['medio_pago']?.toString() ?? 'Sin información';

    final observacion =
        pago['observacion']?.toString().trim() ?? '';

final pedidoData = pago['pedidos'];

final fechaPedido = DateTime.tryParse(
  pedidoData?['created_at']?.toString() ?? '',
)?.toLocal();

final fechaPedidoTexto = fechaPedido == null
    ? 'Pedido sin fecha'
    : 'Pedido del '
        '${fechaPedido.day.toString().padLeft(2, '0')}/'
        '${fechaPedido.month.toString().padLeft(2, '0')}/'
        '${fechaPedido.year}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.payments_outlined),
        title: Text(
          '$fechaTexto — \$${importe.toStringAsFixed(0)}',
        ),
        subtitle: Text(
  observacion.isEmpty
      ? 'Medio de pago: $medio\n$fechaPedidoTexto'
      : 'Medio de pago: $medio\n'
          '$fechaPedidoTexto\n'
          '$observacion',
),
      ),
    );
  }),
],
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