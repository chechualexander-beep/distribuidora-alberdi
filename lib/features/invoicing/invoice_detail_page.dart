import '../../core/desktop_records.dart';
import '../../core/desktop_table.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

import 'invoice_pdf_service.dart';
import '../../core/app_config.dart';
import '../../core/local_outbox.dart';
import 'invoice_request.dart';
import 'invoice_snapshot_pdf.dart';

class InvoiceDetailPage extends StatefulWidget {
  final Map<String, dynamic> pedido;
  final bool soloLectura;

  const InvoiceDetailPage({
    super.key,
    required this.pedido,
    this.soloLectura = false,
  });

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  bool _cargando = true;
  String? _error;
  String? _observacion;

  List<Map<String, dynamic>> _detalles = [];
  List<Map<String, dynamic>> _productosDisponibles = [];
  final Set<String> _detallesQuitados = {};
  final Set<String> _originalIds = {};
  InvoiceService? _billing;
  OutboxRecord? _savedBill;
  InvoiceDocument? _document;
  bool _billingReady = false;
  bool _billingBusy = false;
  String? _billingError;
  bool get _readOnly =>
      widget.soloLectura ||
      _document != null ||
      _savedBill != null ||
      !_billingReady ||
      _billingBusy;
  String get _orderId => widget.pedido['id'].toString();

  void _refreshSavedBill() {
    try {
      if (_billing != null) _savedBill = _billing!.store.read(_orderId);
    } catch (_) {
      _billingError =
          'No se pudo leer la solicitud local. Se conserva y no se habilita otra emisión.';
    }
  }

  final Map<String, TextEditingController> _cantidadFacturadaControllers = {};

  @override
  void initState() {
    super.initState();
    _initializeBilling();
  }

  Future<void> _initializeBilling() async {
    try {
      if (appConfig.isTesting) {
        _billing = await invoiceService(Supabase.instance.client);
        _savedBill = _billing!.store.read(_orderId);
        if (_savedBill?.result != null) {
          _document = InvoiceDocument.validate(
            _savedBill!.result!,
            order: _orderId,
            payload: _savedBill!.payload,
          );
        } else if (_savedBill == null && widget.soloLectura) {
          _document = await _billing!.lookup(_orderId);
        }
      }
      if (_document == null) {
        await _cargarDetalles();
        if (!widget.soloLectura && _savedBill == null) {
          await _cargarProductosDisponibles();
        }
      }
      if (mounted) {
        setState(() {
          _billingReady = true;
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _billingError =
              'No se pudo comprobar el almacén o el comprobante. No se habilita otra emisión; requiere revisión.',
        );
      }
    }
  }

  Future<void> _recoverBill({bool send = false}) async {
    if (_billingBusy || _billing == null) return;
    setState(() => _billingBusy = true);
    try {
      _document = await _billing!.reconcile(_orderId, sendIfAbsent: send);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La boleta se conserva pendiente o para revisión. No generes otra solicitud.',
            ),
          ),
        );
      }
    } finally {
      _refreshSavedBill();
      if (mounted) setState(() => _billingBusy = false);
    }
  }

  Future<void> _printBill() async {
    if (_billingBusy) return;
    setState(() => _billingBusy = true);
    try {
      if (_billing != null) {
        _savedBill = _billing!.store.read(_orderId);
        _document = await _billing!.lookup(_orderId);
      }
      if (_document != null) {
        Future<bool> print(InvoiceDocument doc) => Printing.layoutPdf(
          onLayout: (_) => InvoiceSnapshotPdf.generate(doc),
          name: 'Boleta_${doc.number}',
          format: PdfPageFormat.a5,
        );
        if (_savedBill?.result != null) {
          await _billing!.printConfirmed(_orderId, print);
        } else {
          await print(
            _document!,
          ); // Read-only server document; no new local request.
        }
      } else {
        // Only explicit legacy/no-new-document lookup may reach historical PDF.
        final bytes = await InvoicePdfService.generarBoleta(
          pedido: widget.pedido,
          detalles: _detalles,
        );
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name: 'Boleta ${widget.pedido['numero_comprobante'] ?? ''}',
          format: PdfPageFormat.a5,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _document != null
                  ? 'La boleta sigue confirmada. Impresión pendiente; podés volver a imprimir sin emitir otra.'
                  : 'No se pudo verificar o imprimir el comprobante. Revisá la solicitud guardada; no se emitió otra boleta.',
            ),
          ),
        );
      }
    } finally {
      _refreshSavedBill();
      if (mounted) setState(() => _billingBusy = false);
    }
  }

  Future<void> _facturarPedido() async {
    if (_billingBusy || !_billingReady || _billingError != null) return;
    if (_savedBill != null) {
      await _recoverBill();
      return;
    }
    if (_document != null) return;
    setState(() => _billingBusy = true);
    try {
      if (_billing?.enabled == true) {
        final originals = [
          for (final id in _originalIds)
            {
              'detalle_id': id,
              'cantidad_facturada': _detallesQuitados.contains(id)
                  ? 0
                  : num.parse(_cantidadFacturadaControllers[id]!.text),
            },
        ];
        final added = [
          for (final d in _detalles.where(
            (d) => d['id'].toString().startsWith('nuevo_'),
          ))
            {
              'producto_id': d['producto_id'],
              'tipo_precio': d['tipo_precio'],
              'cantidad_facturada': num.parse(
                _cantidadFacturadaControllers[d['id']]!.text,
              ),
            },
        ];
        await _billing!.prepare(_orderId, {
          'p_originales': originals,
          'p_agregados': added,
        });
        _document = await _billing!.reconcile(_orderId, sendIfAbsent: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Boleta confirmada — impresión pendiente.'),
            ),
          );
        }
      } else {
        // Explicit old mode only; never reached as a recovery/error fallback.
        if (_billing != null) {
          await _billing!.runLegacyIfClear(_orderId, _facturarPedidoLegacy);
        } else {
          await _facturarPedidoLegacy();
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se completó la confirmación. Revisá la boleta guardada antes de continuar; no crees otra.',
            ),
          ),
        );
      }
    } finally {
      _refreshSavedBill();
      if (mounted) setState(() => _billingBusy = false);
    }
  }

  double _precioProductoParaPedido(Map<String, dynamic> producto) {
    final tipoPrecio =
        widget.pedido['tipo_precio']?.toString().toLowerCase() ?? 'normal';

    dynamic valor;

    switch (tipoPrecio) {
      case 'promo':
        valor = producto['precio_promo'];
        break;
      case 'interior':
        valor = producto['precio_interior'];
        break;
      default:
        valor = producto['precio_normal'];
    }

    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  Future<void> _cargarProductosDisponibles() async {
    try {
      final respuesta = await Supabase.instance.client
          .from('productos')
          .select(
            'id, codigo, nombre, precio_normal, precio_promo, precio_interior',
          )
          .eq('activo', true)
          .order('nombre');

      if (!mounted) return;

      setState(() {
        _productosDisponibles = List<Map<String, dynamic>>.from(respuesta);
      });
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron cargar los productos.')),
      );
    }
  }

  Future<void> _mostrarSelectorProductos() async {
    String busqueda = '';

    final productoSeleccionado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final productosFiltrados = _productosDisponibles.where((producto) {
              final nombre = producto['nombre']?.toString().toLowerCase() ?? '';
              final codigo = producto['codigo']?.toString().toLowerCase() ?? '';

              final texto = busqueda.toLowerCase().trim();

              return nombre.contains(texto) || codigo.contains(texto);
            }).toList();

            return AlertDialog(
              title: const Text('Agregar producto'),
              content: SizedBox(
                width: 500,
                height: 550,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Buscar producto...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (valor) {
                        setStateDialog(() {
                          busqueda = valor;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: productosFiltrados.isEmpty
                          ? const Center(
                              child: Text('No se encontraron productos'),
                            )
                          : ListView.separated(
                              itemCount: productosFiltrados.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final producto = productosFiltrados[index];

                                final nombre =
                                    producto['nombre']?.toString() ??
                                    'Producto sin nombre';

                                final codigo =
                                    producto['codigo']?.toString() ?? '';

                                final precio = _precioProductoParaPedido(
                                  producto,
                                );

                                return ListTile(
                                  onTap: () => Navigator.pop(context, producto),
                                  title: Text(nombre),
                                  subtitle: Text(
                                    codigo.isEmpty
                                        ? _formatearPrecio(precio)
                                        : 'Código: $codigo - ${_formatearPrecio(precio)}',
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          },
        );
      },
    );
    if (productoSeleccionado == null) return;
    final productoId = productoSeleccionado['id'].toString();
    final precio = _precioProductoParaPedido(productoSeleccionado);
    final indiceExistente = _detalles.indexWhere(
      (detalle) => detalle['producto_id']?.toString() == productoId,
    );

    if (indiceExistente != -1) {
      final detalleExistente = _detalles[indiceExistente];
      final detalleIdExistente = detalleExistente['id'].toString();

      final controller = _cantidadFacturadaControllers[detalleIdExistente];

      final cantidadActual = double.tryParse(controller?.text ?? '') ?? 0;

      setState(() {
        controller?.text = (cantidadActual + 1).toStringAsFixed(0);
      });

      return;
    }
    final detalleId = 'nuevo_$productoId';
    setState(() {
      _detalles.add({
        'id': detalleId,
        'pedido_id': widget.pedido['id'],
        'producto_id': productoId,
        'cantidad': 1,
        'cantidad_facturada': 1,
        'precio_unitario': precio,
        'subtotal': precio,
        'tipo_precio': widget.pedido['tipo_precio'],
        'productos': {
          'nombre': productoSeleccionado['nombre'],
          'codigo_original': productoSeleccionado['codigo'],
        },
      });

      _cantidadFacturadaControllers[detalleId] = TextEditingController(
        text: '1',
      );
    });
  }

  Future<void> _cargarDetalles() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final pedidoRespuesta = await Supabase.instance.client
          .from('pedidos')
          .select('observacion')
          .eq('id', widget.pedido['id'])
          .single();
      final respuesta = await Supabase.instance.client
          .from('pedido_detalles')
          .select('''
            id,
            pedido_id,
            producto_id,
            cantidad,
            cantidad_facturada,
            precio_unitario,
            subtotal,
            tipo_precio,
            productos (
              nombre,
              codigo_original
            )
          ''')
          .eq('pedido_id', widget.pedido['id']);

      if (!mounted) return;

      setState(() {
        _detalles = List<Map<String, dynamic>>.from(respuesta);
        _originalIds
          ..clear()
          ..addAll(_detalles.map((d) => d['id'].toString()));
        _observacion = pedidoRespuesta['observacion']?.toString();

        for (final detalle in _detalles) {
          final id = detalle['id'].toString();
          final cantidad = double.tryParse(detalle['cantidad'].toString()) ?? 0;

          final cantidadFacturada =
              double.tryParse(
                detalle['cantidad_facturada']?.toString() ?? '',
              ) ??
              cantidad;

          _cantidadFacturadaControllers[id] = TextEditingController(
            text: _billing?.enabled == true
                ? cantidadFacturada.toString()
                : cantidadFacturada.toStringAsFixed(0),
          );
        }

        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudo cargar el detalle del pedido.';
        _cargando = false;
      });
    }
  }

  Future<void> _facturarPedidoLegacy() async {
    final numeroComprobante =
        await Supabase.instance.client.rpc('siguiente_numero_comprobante')
            as String;

    try {
      for (final detalle in _detalles) {
        final detalleId = detalle['id'].toString();

        if (detalleId.startsWith('nuevo_')) {
          continue;
        }

        final cantidadFacturada =
            double.tryParse(
              _cantidadFacturadaControllers[detalleId]?.text ?? '',
            ) ??
            0;

        await Supabase.instance.client
            .from('pedido_detalles')
            .update({'cantidad_facturada': cantidadFacturada})
            .eq('id', detalleId);
      }
      for (final detalle in _detalles) {
        final detalleId = detalle['id'].toString();

        if (!detalleId.startsWith('nuevo_')) {
          continue;
        }

        final cantidadFacturada =
            double.tryParse(
              _cantidadFacturadaControllers[detalleId]?.text ?? '',
            ) ??
            0;

        if (cantidadFacturada <= 0) {
          continue;
        }

        final precio =
            double.tryParse(detalle['precio_unitario']?.toString() ?? '') ?? 0;

        await Supabase.instance.client.from('pedido_detalles').insert({
          'pedido_id': widget.pedido['id'],
          'producto_id': detalle['producto_id'],
          'cantidad': cantidadFacturada,
          'precio_unitario': precio,
          'subtotal': cantidadFacturada * precio,
          'tipo_precio': detalle['tipo_precio'],
          'cantidad_facturada': cantidadFacturada,
        });
      }
      for (final detalleId in _detallesQuitados) {
        await Supabase.instance.client
            .from('pedido_detalles')
            .update({'cantidad_facturada': 0})
            .eq('id', detalleId);
      }
      await Supabase.instance.client
          .from('pedidos')
          .update({
            'facturado': true,
            'fecha_facturacion': DateTime.now().toUtc().toIso8601String(),
            'numero_comprobante': numeroComprobante,
          })
          .eq('id', widget.pedido['id']);
      final pedidoFacturado = Map<String, dynamic>.from(widget.pedido);
      pedidoFacturado['numero_comprobante'] = numeroComprobante;
      pedidoFacturado['fecha_facturacion'] = DateTime.now()
          .toUtc()
          .toIso8601String();

      final pdfBytes = await InvoicePdfService.generarBoleta(
        pedido: pedidoFacturado,
        detalles: _detalles,
      );

      await Printing.layoutPdf(
        onLayout: (_) async => pdfBytes,
        name: 'Boleta_$numeroComprobante',
        format: PdfPageFormat.a5,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido facturado correctamente.')),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo facturar el pedido: $e')),
      );
    }
  }

  String _formatearFecha(dynamic fecha) {
    if (fecha == null) return '-';

    final date = DateTime.tryParse(fecha.toString());
    if (date == null) return '-';

    final dia = date.day.toString().padLeft(2, '0');
    final mes = date.month.toString().padLeft(2, '0');
    final anio = date.year.toString();

    return '$dia/$mes/$anio';
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

  @override
  Widget build(BuildContext context) {
    final cliente = widget.pedido['clientes'] as Map<String, dynamic>?;

    final nombreCliente =
        cliente?['nombre_comercio']?.toString() ?? 'Cliente sin nombre';

    final total = _detalles.fold<double>(0, (suma, detalle) {
      final id = detalle['id'].toString();

      final cantidad =
          double.tryParse(_cantidadFacturadaControllers[id]?.text ?? '') ?? 0;

      final precio =
          double.tryParse(detalle['precio_unitario']?.toString() ?? '') ?? 0;

      return suma + (cantidad * precio);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de facturación')),
      body: DesktopForm(child: _construirContenido(nombreCliente, total)),
    );
  }

  Widget _construirContenido(String nombreCliente, dynamic total) {
    if (_billingError != null) return Center(child: Text(_billingError!));
    if (_document != null) {
      final c = _document!.snapshot;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Boleta interna confirmada'),
          Text('Comprobante: ${_document!.number}'),
          Text('Cliente: ${c['cliente']['nombre']}'),
          for (final line in c['lineas'] as List)
            Text(
              '${line['cantidad_documentada']} × ${line['nombre']} — ${line['subtotal']}',
            ),
          Text('Total: ${c['total']} ARS'),
          Text(
            _savedBill?.state == 'acknowledged'
                ? 'Boleta confirmada'
                : 'Boleta confirmada — impresión pendiente',
          ),
          FilledButton.icon(
            onPressed: _billingBusy || !_billingReady ? null : _printBill,
            icon: const Icon(Icons.print_outlined),
            label: const Text('VISUALIZAR / REIMPRIMIR'),
          ),
        ],
      );
    }
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _cargarDetalles,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_savedBill != null && _savedBill!.result == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    _savedBill!.state == 'review'
                        ? 'Boleta con error o conflicto — requiere revisión'
                        : 'Boleta pendiente de confirmación',
                  ),
                  Text('Solicitud: ${_savedBill!.payload['p_solicitud_id']}'),
                  if (_savedBill!.state != 'review') ...[
                    TextButton(
                      onPressed: _billingBusy ? null : () => _recoverBill(),
                      child: const Text('Consultar confirmación'),
                    ),
                    TextButton(
                      onPressed: _billingBusy || _billing?.enabled != true
                          ? null
                          : () => _recoverBill(send: true),
                      child: const Text('Reintentar solicitud original'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombreCliente,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tipo de precio: '
                  '${widget.pedido['tipo_precio']?.toString().toUpperCase() ?? ''}',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_observacion != null && _observacion!.trim().isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'OBSERVACIONES',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(_observacion!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        const Text(
          'Productos',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (!_readOnly) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _mostrarSelectorProductos,
              icon: const Icon(Icons.add),
              label: const Text('Agregar producto'),
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (useDesktopLayout(context))
          DesktopRecords(
            embedded: true,
            records: _detalles,
            fields: [
              DesktopField(
                'Producto',
                (r) => (r['productos'] as Map?)?['nombre'],
                width: 240,
              ),
              DesktopField(
                'Pedida',
                (r) => r['cantidad'],
                numeric: true,
                width: 80,
              ),
              DesktopField(
                'A facturar',
                (r) => SizedBox(
                  width: 110,
                  child: TextField(
                    key: ValueKey('facturar-${r['id']}'),
                    enabled: !_readOnly,
                    controller:
                        _cantidadFacturadaControllers[r['id'].toString()],
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      isDense: true,
                    ),
                  ),
                ),
                width: 110,
              ),
              DesktopField(
                'Precio',
                (r) => desktopMoney(r['precio_unitario']),
                numeric: true,
                width: 110,
              ),
              DesktopField(
                'Subtotal',
                (r) => desktopMoney(
                  (double.tryParse(
                            _cantidadFacturadaControllers[r['id'].toString()]
                                    ?.text ??
                                '',
                          ) ??
                          0) *
                      (double.tryParse(
                            r['precio_unitario']?.toString() ?? '',
                          ) ??
                          0),
                ),
                numeric: true,
                width: 120,
              ),
            ],
            actions: _readOnly
                ? null
                : (detalle) => IconButton(
                    tooltip: 'Quitar de la boleta',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () {
                      setState(() {
                        final id = detalle['id'].toString();
                        if (!id.startsWith('nuevo_')) _detallesQuitados.add(id);
                        _detalles.removeWhere((d) => d['id'].toString() == id);
                        _cantidadFacturadaControllers[id]?.dispose();
                        _cantidadFacturadaControllers.remove(id);
                      });
                    },
                  ),
          )
        else
          ..._detalles.map((detalle) {
            final producto = detalle['productos'] as Map<String, dynamic>?;

            final nombre =
                producto?['nombre']?.toString() ?? 'Producto sin nombre';

            final codigo = producto?['codigo_original']?.toString() ?? '';

            final cantidad =
                double.tryParse(detalle['cantidad']?.toString() ?? '') ?? 0;

            final precio = detalle['precio_unitario'];

            final cantidadFacturada =
                double.tryParse(
                  _cantidadFacturadaControllers[detalle['id'].toString()]
                          ?.text ??
                      '',
                ) ??
                0;

            final precioNumerico =
                double.tryParse(precio?.toString() ?? '') ?? 0;

            final subtotal = cantidadFacturada * precioNumerico;

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (codigo.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Código: $codigo'),
                    ],
                    const SizedBox(height: 6),
                    Text('Cantidad pedida: ${cantidad.toStringAsFixed(0)}'),
                    const SizedBox(height: 8),
                    TextField(
                      enabled: !_readOnly,
                      controller:
                          _cantidadFacturadaControllers[detalle['id']
                              .toString()],
                      keyboardType: TextInputType.number,
                      onChanged: (_) {
                        setState(() {});
                      },
                      decoration: const InputDecoration(
                        labelText: 'Cantidad a facturar',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    Text('Precio unitario: ${_formatearPrecio(precio)}'),
                    Text(
                      'Subtotal: ${_formatearPrecio(subtotal)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _readOnly
                            ? null
                            : () {
                                setState(() {
                                  final detalleId = detalle['id'].toString();

                                  if (!detalleId.startsWith('nuevo_')) {
                                    _detallesQuitados.add(detalleId);
                                  }

                                  _detalles.removeWhere(
                                    (item) =>
                                        item['id'].toString() == detalleId,
                                  );

                                  _cantidadFacturadaControllers[detalleId]
                                      ?.dispose();
                                  _cantidadFacturadaControllers.remove(
                                    detalleId,
                                  );
                                });
                              },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Quitar de la boleta'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  _formatearPrecio(total),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        if (_savedBill != null && _savedBill!.result == null) ...[
          const SizedBox.shrink(),
        ] else if (widget.soloLectura) ...[
          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Factura realizada',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  Text(
                    'Comprobante: ${widget.pedido['numero_comprobante'] ?? '-'}',
                  ),

                  const SizedBox(height: 4),

                  Text(
                    'Fecha: ${_formatearFecha(widget.pedido['fecha_facturacion'])}',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _billingBusy || !_billingReady ? null : _printBill,
              icon: const Icon(Icons.print_outlined),
              label: const Text('REIMPRIMIR'),
            ),
          ),
        ] else ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _billingBusy || !_billingReady
                  ? null
                  : _facturarPedido,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('FACTURAR'),
            ),
          ),
        ],
      ],
    );
  }
}
