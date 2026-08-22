import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageOrderPage extends StatefulWidget {
  final Map<String, dynamic> pedido;

  const ManageOrderPage({
    super.key,
    required this.pedido,
  });

  @override
  State<ManageOrderPage> createState() => _ManageOrderPageState();
}

class _ManageOrderPageState extends State<ManageOrderPage> {
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  String _estado = 'pendiente';
String? _modoEntrega;
  List<Map<String, dynamic>> _detalles = [];

  final Map<String, TextEditingController> _entregadosControllers = {};
  final TextEditingController _motivoController = TextEditingController();

  @override
  void initState() {
    super.initState();

    _estado = widget.pedido['estado']?.toString() ?? 'pendiente';

    _motivoController.text =
        widget.pedido['motivo_no_entrega']?.toString() ?? '';

    _cargarDetalles();
  }

  Future<void> _cargarDetalles() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await Supabase.instance.client
          .from('pedido_detalles')
          .select(
            '''
            id,
            pedido_id,
            producto_id,
            cantidad,
            cantidad_entregada,
            cantidad_no_entregada,
            precio_unitario,
            tipo_precio,
            porcentaje_comision,
            importe_comision,
            productos (
              nombre,
              codigo_original,
              comision_normal,
              comision_promo,
              comision_interior
            )
            ''',
          )
          .eq('pedido_id', widget.pedido['id']);

      if (!mounted) return;

      final detalles =
          List<Map<String, dynamic>>.from(respuesta);

      for (final detalle in detalles) {
        final id = detalle['id'].toString();

        final entregada = double.tryParse(
              detalle['cantidad_entregada']?.toString() ?? '0',
            ) ??
            0;

        _entregadosControllers[id] = TextEditingController(
          text: _numeroLimpio(entregada),
        );
      }

      setState(() {
        _detalles = detalles;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudo cargar el pedido.';
        _cargando = false;
      });
    }
  }

  String _numeroLimpio(double valor) {
    if (valor == valor.roundToDouble()) {
      return valor.toInt().toString();
    }

    return valor.toStringAsFixed(2);
  }

  double _cantidadPedida(Map<String, dynamic> detalle) {
    return double.tryParse(
          detalle['cantidad']?.toString() ?? '0',
        ) ??
        0;
  }

  double _cantidadEntregada(Map<String, dynamic> detalle) {
    final id = detalle['id'].toString();

    return double.tryParse(
          _entregadosControllers[id]?.text.replaceAll(',', '.') ?? '0',
        ) ??
        0;
  }

  double _cantidadNoEntregada(Map<String, dynamic> detalle) {
    final pedida = _cantidadPedida(detalle);
    final entregada = _cantidadEntregada(detalle);

    final resultado = pedida - entregada;

    return resultado < 0 ? 0 : resultado;
  }

  double _precio(Map<String, dynamic> detalle) {
    return double.tryParse(
          detalle['precio_unitario']?.toString() ?? '0',
        ) ??
        0;
  }

  double _porcentajeComision(Map<String, dynamic> detalle) {
    final producto =
        detalle['productos'] as Map<String, dynamic>?;

    final tipoPrecio =
        detalle['tipo_precio']?.toString() ?? 'normal';

    dynamic valor;

    switch (tipoPrecio) {
      case 'promo':
        valor = producto?['comision_promo'];
        break;
      case 'interior':
        valor = producto?['comision_interior'];
        break;
      default:
        valor = producto?['comision_normal'];
    }

    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  double _importeComision(Map<String, dynamic> detalle) {
    final entregada = _cantidadEntregada(detalle);
    final precio = _precio(detalle);
    final porcentaje = _porcentajeComision(detalle);

    return entregada * precio * porcentaje / 100;
  }

  String _resultadoEntrega() {
    double totalPedido = 0;
    double totalEntregado = 0;

    for (final detalle in _detalles) {
      totalPedido += _cantidadPedida(detalle);
      totalEntregado += _cantidadEntregada(detalle);
    }

    if (totalEntregado <= 0) {
      return 'no_entregado';
    }

    if (totalEntregado >= totalPedido) {
      return 'entregado';
    }

    return 'parcial';
  }

  String _nombreResultado(String resultado) {
    switch (resultado) {
      case 'entregado':
        return 'ENTREGADO';
      case 'no_entregado':
        return 'NO ENTREGADO';
      case 'parcial':
        return 'ENTREGA PARCIAL';
      default:
        return 'PENDIENTE';
    }
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

  bool _validarCantidades() {
    for (final detalle in _detalles) {
      final pedida = _cantidadPedida(detalle);
      final entregada = _cantidadEntregada(detalle);

      if (entregada < 0 || entregada > pedida) {
        _mostrarMensaje(
          'La cantidad entregada no puede ser menor que 0 ni mayor que la pedida.',
        );
        return false;
      }
    }

    return true;
  }

  Future<void> _guardarGestion() async {
    if (_guardando) return;
if (_modoEntrega == null) {
  _mostrarMensaje(
    'Seleccioná cómo fue la entrega antes de guardar.',
  );
  return;
}
    if (!_validarCantidades()) return;

    final resultado = _resultadoEntrega();
    final totalPedido = double.tryParse(
  widget.pedido['total']?.toString() ?? '',
) ?? 0;
String? medioPagoCompleto;
double? importePagoParcial;
String? medioPagoParcial;

if (resultado == 'entregado') {
  medioPagoCompleto = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: const Text('¿Cómo quedó el pago?'),
        content: const Text(
          'Si el cliente pagó todo el pedido, seleccioná el medio de pago.',
        ),
        actions: [
          TextButton(
  onPressed: () => Navigator.pop(context, null),
  child: const Text('CANCELAR'),
),
          TextButton(
           onPressed: () => Navigator.pop(context, 'Parcial'),
            child: const Text('DEJÓ SALDO'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'Efectivo'),
            child: const Text('EFECTIVO'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'Transferencia'),
            child: const Text('TRANSFERENCIA'),
          ),
        ],
      );
    },
  );
}
if (medioPagoCompleto == null) {
  return;
}
if (!mounted) return;
if (resultado == 'entregado' && medioPagoCompleto == 'Parcial') {
  final controller = TextEditingController();

  final importe = await showDialog<double>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Pago parcial'),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Importe pagado',
            prefixText: r'$ ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('NO PAGÓ NADA'),
          ),
          FilledButton(
            onPressed: () {
              final valor = double.tryParse(
                controller.text.trim().replaceAll(',', '.'),
              );

              if (valor == null || valor <= 0) return;

              Navigator.pop(dialogContext, valor);
            },
            child: const Text('CONTINUAR'),
          ),
        ],
      );
    },
  );

  await Future<void>.delayed(const Duration(milliseconds: 300));

if (!mounted) return;

controller.dispose();

if (importe != null) {
    importePagoParcial = importe;

    medioPagoParcial = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Medio de pago'),
          content: Text(
            'Importe recibido: \$${importe.toStringAsFixed(0)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'Efectivo'),
              child: const Text('EFECTIVO'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'Transferencia'),
              child: const Text('TRANSFERENCIA'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
  }
}

    if ((resultado == 'no_entregado' || resultado == 'parcial') &&
        _motivoController.text.trim().isEmpty) {
      _mostrarMensaje(
        'Ingresá un motivo para la mercadería no entregada.',
      );
      return;
    }

    setState(() {
      _guardando = true;
    });

    try {
      for (final detalle in _detalles) {
        final id = detalle['id'];
        final entregada = _cantidadEntregada(detalle);
        final noEntregada = _cantidadNoEntregada(detalle);
        final porcentaje = _porcentajeComision(detalle);
        final importe = _importeComision(detalle);

        await Supabase.instance.client
            .from('pedido_detalles')
            .update({
              'cantidad_entregada': entregada,
              'cantidad_no_entregada': noEntregada,
              'porcentaje_comision': porcentaje,
              'importe_comision': importe,
            })
            .eq('id', id);
      }

      await Supabase.instance.client
          .from('pedidos')
          .update({
            'estado': _estado,
            'resultado_entrega': resultado,
            'motivo_no_entrega':
                resultado == 'entregado'
                    ? null
                    : _motivoController.text.trim(),
          })
          .eq('id', widget.pedido['id']);
         if (resultado == 'entregado' &&
    
    medioPagoCompleto != 'Parcial' &&
    totalPedido > 0) {
      if (resultado == 'entregado' &&
    importePagoParcial != null &&
    medioPagoParcial != null &&
    importePagoParcial > 0) {
  await Supabase.instance.client
      .from('pedido_pagos')
      .insert({
        'pedido_id': widget.pedido['id'],
        'importe': importePagoParcial,
        'medio_pago': medioPagoParcial,
        'fecha_pago': DateTime.now().toIso8601String(),
        'observacion': 'Pago parcial al entregar el pedido',
      });
}
  final pagosExistentes = await Supabase.instance.client
      .from('pedido_pagos')
      .select('importe')
      .eq('pedido_id', widget.pedido['id']);

  double pagadoPedido = 0;

  for (final pago in pagosExistentes) {
    pagadoPedido +=
        double.tryParse(pago['importe']?.toString() ?? '') ?? 0;
  }

  final saldoPedido = totalPedido - pagadoPedido;

  if (saldoPedido > 0) {
    await Supabase.instance.client
        .from('pedido_pagos')
        .insert({
          'pedido_id': widget.pedido['id'],
          'importe': saldoPedido,
          'medio_pago': medioPagoCompleto,
          'fecha_pago': DateTime.now().toIso8601String(),
          'observacion': 'Pago completo al entregar el pedido',
        });
  }
}

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            icon: const Icon(
              Icons.check_circle_outline,
              size: 48,
            ),
            title: const Text('Gestión guardada'),
            content: Text(
              'Resultado: ${_nombreResultado(resultado)}',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('ACEPTAR'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      _mostrarMensaje(
        'No se pudo guardar: ${error.message}',
      );
    } catch (_) {
      _mostrarMensaje(
        'Ocurrió un error al guardar la gestión.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in _entregadosControllers.values) {
      controller.dispose();
    }

    _motivoController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cliente =
        widget.pedido['clientes'] as Map<String, dynamic>?;

    final clienteNombre =
        cliente?['nombre_comercio']?.toString() ??
            'Cliente sin nombre';

    if (_cargando) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Gestionar pedido'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Gestionar pedido'),
        ),
        body: Center(
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
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _cargarDetalles,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final resultado = _resultadoEntrega();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestionar pedido'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Cliente',
                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    clienteNombre,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (widget.pedido['tipo_operacion']?.toString() == 'venta_directa') ...[
  const SizedBox(height: 8),
  const Text(
    'VENTA DIRECTA',
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
    ),
  ),
],
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: _estado,
                    decoration: const InputDecoration(
                      labelText: 'Estado operativo',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'pendiente',
                        child: Text('Pendiente'),
                      ),
                      DropdownMenuItem(
                        value: 'preparado',
                        child: Text('Preparado'),
                      ),
                      DropdownMenuItem(
                        value: 'en_reparto',
                        child: Text('En reparto'),
                      ),
                    ],
                    onChanged: (valor) {
                      if (valor == null) return;

                      setState(() {
                        _estado = valor;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
      const Text(
  'Mercadería entregada',
  style: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
  ),
),
const SizedBox(height: 10),

Card(
  child: Column(
    children: [
      RadioListTile<String>(
        value: 'completo',
        groupValue: _modoEntrega,
        title: const Text('TODO ENTREGADO'),
        subtitle: const Text(
          'El cliente recibió todo el pedido',
        ),
        onChanged: (valor) {
          if (valor == null) return;

          setState(() {
            _modoEntrega = valor;

            for (final detalle in _detalles) {
              final id = detalle['id'].toString();
              final cantidad = _cantidadPedida(detalle);

              _entregadosControllers[id]?.text =
                  _numeroLimpio(cantidad);
            }
          });
        },
      ),

      const Divider(height: 1),

      RadioListTile<String>(
        value: 'rechazado',
        groupValue: _modoEntrega,
        title: const Text('TODO NO ENTREGADO'),
        subtitle: const Text(
          'El cliente no recibió ningún producto',
        ),
        onChanged: (valor) {
          if (valor == null) return;

          setState(() {
            _modoEntrega = valor;

            for (final detalle in _detalles) {
              final id = detalle['id'].toString();
              _entregadosControllers[id]?.text = '0';
            }
          });
        },
      ),

      const Divider(height: 1),

      RadioListTile<String>(
        value: 'parcial',
        groupValue: _modoEntrega,
        title: const Text('ENTREGA PARCIAL'),
        subtitle: const Text(
          'Indicar cantidades producto por producto',
        ),
        onChanged: (valor) {
          if (valor == null) return;

          setState(() {
            _modoEntrega = valor;
          });
        },
      ),
    ],
  ),
),

const SizedBox(height: 16),

if (_modoEntrega == 'parcial')
  ..._detalles.map((detalle) {
            final producto =
                detalle['productos'] as Map<String, dynamic>?;

            final nombre =
                producto?['nombre']?.toString() ??
                    'Producto sin nombre';

            final id = detalle['id'].toString();

            final pedida = _cantidadPedida(detalle);
            final noEntregada =
                _cantidadNoEntregada(detalle);

            final porcentaje =
                _porcentajeComision(detalle);

            final importe =
                _importeComision(detalle);

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Cantidad pedida: ${_numeroLimpio(pedida)}',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _entregadosControllers[id],
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Cantidad entregada',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No entregada: ${_numeroLimpio(noEntregada)}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Precio: ${_formatearPrecio(_precio(detalle))}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Comisión: ${_numeroLimpio(porcentaje)}%',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Comisión generada: ${_formatearPrecio(importe)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 12),

          Card(
            child: ListTile(
              title: const Text(
                'Resultado de entrega',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                _nombreResultado(resultado),
              ),
            ),
          ),

          if (resultado == 'parcial' ||
              resultado == 'no_entregado') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _motivoController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo de mercadería no entregada *',
                hintText:
                    'Ej.: cliente cerrado, rechazó parte del pedido...',
                border: OutlineInputBorder(),
              ),
            ),
          ],

          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed:
                _guardando ? null : _guardarGestion,
            icon: _guardando
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(
              _guardando
                  ? 'GUARDANDO...'
                  : 'GUARDAR GESTIÓN',
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}