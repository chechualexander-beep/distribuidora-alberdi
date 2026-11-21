import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/desktop_records.dart';
import '../../core/money_format.dart';
import 'calculator_data.dart';
import 'calculator_math.dart';

/// Calculadora propia (sin publicidad, sin señal): Margen, Descuento y Por bulto.
class CalculatorPage extends StatefulWidget {
  const CalculatorPage({
    super.key,
    this.pestana = 0,
    this.soloBulto = false,
    this.costo,
    this.venta,
    this.productos,
    this.cargarProductos,
    this.cargar = true,
    this.lista = 'normal',
  });

  /// 0 Margen, 1 Descuento, 2 Por bulto.
  final int pestana;

  /// Desde los productos del pedido: solo "Por bulto".
  final bool soloBulto;

  /// Para abrirla con un producto ya cargado (edición de productos).
  final double? costo;
  final double? venta;

  /// Productos ya cargados (por ejemplo, los del pedido). Si [cargar], se buscan de nuevo
  /// para que el administrador tenga los costos.
  final List<CalcProduct>? productos;
  final Future<List<CalcProduct>> Function()? cargarProductos;
  final bool cargar;

  /// Lista de precios para "Traer producto".
  final String lista;

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  late List<CalcProduct> _productos = widget.productos ?? const [];

  @override
  void initState() {
    super.initState();
    if (widget.cargar) _cargar();
  }

  Future<void> _cargar() async {
    try {
      final cargar =
          widget.cargarProductos ??
          (() => cargarProductosCalculadora(Supabase.instance.client));
      final lista = await cargar();
      if (mounted && lista.isNotEmpty) setState(() => _productos = lista);
    } catch (_) {
      // Sin señal: quedan los productos que ya estaban (o se carga a mano).
    }
  }

  @override
  Widget build(BuildContext context) {
    final bulto = BulkCalculator(productos: _productos, lista: widget.lista);
    if (widget.soloBulto) {
      return Scaffold(
        appBar: AppBar(title: const Text('Por bulto')),
        body: DesktopForm(maxWidth: 560, child: bulto),
      );
    }
    return DefaultTabController(
      length: 3,
      initialIndex: widget.pestana.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Calculadora'),
          // Pestañas como botones redondeados: la elegida rellena en dorado con letra negra
          // (como Depósito / Vehículo), las otras con borde dorado y letra blanca.
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: TabBar(
                labelPadding: const EdgeInsets.symmetric(horizontal: 3),
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: AppColors.dorado,
                  borderRadius: BorderRadius.circular(20),
                ),
                dividerColor: Colors.transparent,
                splashBorderRadius: BorderRadius.circular(20),
                labelColor: AppColors.negro,
                unselectedLabelColor: Colors.white,
                labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                tabs: [
                  for (final nombre in const ['Margen', 'Descuento', 'Por bulto'])
                    Tab(
                      height: 38,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.dorado, width: 1.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(nombre),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        body: DesktopForm(
          maxWidth: 560,
          child: TabBarView(
            children: [
              MarginCalculator(
                productos: _productos,
                lista: widget.lista,
                costo: widget.costo,
                venta: widget.venta,
              ),
              DiscountCalculator(
                productos: _productos,
                lista: widget.lista,
                precio: widget.venta,
                costo: widget.costo,
              ),
              bulto,
            ],
          ),
        ),
      ),
    );
  }
}

/// Casilla numérica: al tocarla se selecciona todo para escribir encima.
class _Casilla extends StatelessWidget {
  const _Casilla({
    required this.clave,
    required this.etiqueta,
    required this.controller,
    required this.onChanged,
    this.prefijo,
    this.sufijo,
    this.candado,
    this.onCandado,
  });

  final String clave;
  final String etiqueta;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? prefijo;
  final String? sufijo;

  /// null: la casilla no tiene candado; true/false: cerrado o abierto.
  final bool? candado;
  final VoidCallback? onCandado;

  @override
  Widget build(BuildContext context) {
    final cerrado = candado == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: Key('calc-$clave'),
              controller: controller,
              readOnly: cerrado,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [ImporteInputFormatter()],
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: etiqueta,
                prefixText: prefijo,
                suffixText: sufijo,
                isDense: true,
                filled: cerrado,
                fillColor: cerrado ? AppColors.dorado.withValues(alpha: 0.18) : null,
                border: const OutlineInputBorder(),
              ),
              onTap: () => controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: controller.text.length,
              ),
              onChanged: onChanged,
            ),
          ),
          if (candado != null)
            IconButton(
              key: Key('candado-$clave'),
              tooltip: cerrado ? 'Soltar' : 'Dejar fijo',
              onPressed: onCandado,
              icon: Icon(
                cerrado ? Icons.lock : Icons.lock_open,
                color: cerrado ? AppColors.doradoOscuro : AppColors.gris,
              ),
            ),
        ],
      ),
    );
  }
}

class _Resultado extends StatelessWidget {
  const _Resultado({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Tonos.of(context).infoFondo,
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}

Widget _chips<T>({
  required List<(T, String)> opciones,
  required T? elegido,
  required ValueChanged<T> onElegir,
  String? titulo,
}) {
  return Wrap(
    spacing: 6,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (titulo != null) Text(titulo, style: const TextStyle(color: AppColors.gris)),
      for (final (valor, texto) in opciones)
        ChoiceChip(
          key: Key('chip-$texto'),
          label: Text(texto),
          selected: valor == elegido,
          onSelected: (_) => onElegir(valor),
        ),
    ],
  );
}

/// Producto elegido con su lista (Normal / Promo / Interior) para cambiar el precio.
class _ProductoElegido extends StatelessWidget {
  const _ProductoElegido({
    required this.producto,
    required this.lista,
    required this.onLista,
    required this.onCambiar,
  });

  final CalcProduct producto;
  final String lista;
  final ValueChanged<String> onLista;
  final VoidCallback onCambiar;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  producto.nombre,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(onPressed: onCambiar, child: const Text('Cambiar')),
            ],
          ),
          _chips<String>(
            opciones: [
              ('normal', 'Normal'),
              if ((producto.promo ?? 0) > 0) ('promo', 'Promo'),
              if ((producto.interior ?? 0) > 0) ('interior', 'Interior'),
            ],
            elegido: lista,
            onElegir: onLista,
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------- Margen

class MarginCalculator extends StatefulWidget {
  const MarginCalculator({
    super.key,
    this.productos = const [],
    this.lista = 'normal',
    this.costo,
    this.venta,
  });

  final List<CalcProduct> productos;
  final String lista;
  final double? costo;
  final double? venta;

  @override
  State<MarginCalculator> createState() => _MarginCalculatorState();
}

class _MarginCalculatorState extends State<MarginCalculator>
    with AutomaticKeepAliveClientMixin {
  late EstadoMargen _e = EstadoMargen(widget.costo ?? 0, widget.venta ?? 0);
  CampoMargen? _candado;
  CalcProduct? _producto;
  late String _lista = widget.lista;
  final _c = {for (final campo in CampoMargen.values) campo: TextEditingController()};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _refrescar();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _hayVenta => _e.venta > 0;

  String _texto(CampoMargen campo) {
    if (campo == CampoMargen.costo) {
      return _e.costo > 0 || _hayVenta ? formatoNumero(dosDecimales(_e.costo)) : '';
    }
    if (!_hayVenta) return '';
    final v = _e.valor(campo);
    return switch (campo) {
      CampoMargen.margen || CampoMargen.recargo => textoPorcentaje(v),
      _ => formatoNumero(dosDecimales(v)),
    };
  }

  void _refrescar({CampoMargen? salvo}) {
    for (final campo in CampoMargen.values) {
      if (campo != salvo) _c[campo]!.text = _texto(campo);
    }
  }

  void _escribir(CampoMargen campo, String texto) {
    final x = leerImporte(texto);
    if (x == null) return;
    final nuevo = resolverMargen(_e, campo, x, candado: _candado);
    if (nuevo == null) return;
    setState(() => _e = nuevo);
    _refrescar(salvo: campo);
  }

  void _redondear(double paso) {
    if (!_hayVenta) return;
    setState(() => _e = EstadoMargen(_e.costo, redondearArriba(_e.venta, paso)));
    _refrescar();
  }

  void _usarProducto(CalcProduct p, String lista) {
    setState(() {
      _producto = p;
      _lista = lista;
      _e = EstadoMargen(p.costo ?? _e.costo, p.precio(lista));
    });
    _refrescar();
  }

  Future<void> _traer() async {
    final p = await elegirProductoCalculadora(context, widget.productos, _lista);
    if (p != null && mounted) _usarProducto(p, _lista);
  }

  Widget _casilla(CampoMargen campo, String etiqueta, {bool porcentaje = false}) {
    return _Casilla(
      clave: campo.name,
      etiqueta: etiqueta,
      controller: _c[campo]!,
      prefijo: porcentaje ? null : '\$ ',
      sufijo: porcentaje ? '%' : null,
      candado: _candado == campo,
      onCandado: () => setState(() => _candado = _candado == campo ? null : campo),
      onChanged: (t) => _escribir(campo, t),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final g = _e.ganancia;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (_producto == null)
          OutlinedButton.icon(
            onPressed: _traer,
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Traer producto'),
          )
        else
          _ProductoElegido(
            producto: _producto!,
            lista: _lista,
            onLista: (l) => _usarProducto(_producto!, l),
            onCambiar: _traer,
          ),
        _casilla(CampoMargen.costo, 'Costo'),
        _casilla(CampoMargen.margen, 'Margen (sobre la venta)', porcentaje: true),
        _casilla(CampoMargen.recargo, 'Recargo (sobre el costo)', porcentaje: true),
        _casilla(CampoMargen.venta, 'Venta'),
        _casilla(CampoMargen.ganancia, 'Ganancia'),
        const SizedBox(height: 6),
        _chips<double>(
          titulo: 'Redondear venta:',
          opciones: const [(10, '\$10'), (50, '\$50'), (100, '\$100')],
          elegido: null,
          onElegir: _redondear,
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Escribí en cualquier casilla y las demás se acomodan. Con el candado queda fija '
            'una; sin candado, al cambiar el costo se mantiene el margen.',
            style: TextStyle(color: AppColors.gris, fontSize: 13),
          ),
        ),
        if (_hayVenta)
          _Resultado(
            child: Text(
              'Con costo ${formatoPesos(dosDecimales(_e.costo))} y venta '
              '${formatoPesos(dosDecimales(_e.venta))} ganás '
              '${formatoPesos(dosDecimales(g))} por unidad: '
              '${textoPorcentaje(_e.margen)}% de lo que cobrás '
              '(${textoPorcentaje(_e.recargo)}% sobre el costo).',
              style: TextStyle(
                fontSize: 15,
                color: g < 0 ? AppColors.rojo : null,
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Descuento

class DiscountCalculator extends StatefulWidget {
  const DiscountCalculator({
    super.key,
    this.productos = const [],
    this.lista = 'normal',
    this.precio,
    this.costo,
  });

  final List<CalcProduct> productos;
  final String lista;
  final double? precio;
  final double? costo;

  @override
  State<DiscountCalculator> createState() => _DiscountCalculatorState();
}

class _DiscountCalculatorState extends State<DiscountCalculator>
    with AutomaticKeepAliveClientMixin {
  late double _precio = widget.precio ?? 0;
  double _descuento = 10;
  late double? _costo = widget.costo;
  CalcProduct? _producto;
  late String _lista = widget.lista;
  final _precioC = TextEditingController();
  final _descuentoC = TextEditingController();
  final _finalC = TextEditingController();
  final _costoC = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  ResultadoDescuento get _r =>
      ResultadoDescuento(precio: _precio, descuento: _descuento, costo: _costo);

  @override
  void initState() {
    super.initState();
    _refrescar();
  }

  @override
  void dispose() {
    for (final c in [_precioC, _descuentoC, _finalC, _costoC]) {
      c.dispose();
    }
    super.dispose();
  }

  void _refrescar({TextEditingController? salvo}) {
    String plata(double v) => v > 0 ? formatoNumero(dosDecimales(v)) : '';
    if (salvo != _precioC) _precioC.text = plata(_precio);
    if (salvo != _descuentoC) _descuentoC.text = textoPorcentaje(_descuento);
    if (salvo != _finalC) _finalC.text = plata(_r.precioFinal);
    if (salvo != _costoC) _costoC.text = _costo == null ? '' : plata(_costo!);
  }

  void _escribir(TextEditingController c, String texto) {
    final x = leerImporte(texto);
    setState(() {
      if (c == _costoC) {
        _costo = x;
      } else if (x == null) {
        return;
      } else if (c == _precioC) {
        _precio = x;
      } else if (c == _descuentoC) {
        _descuento = x > 100 ? 100 : x;
      } else if (c == _finalC && _precio > 0) {
        _descuento = ResultadoDescuento.descuentoPara(_precio, x);
      }
    });
    _refrescar(salvo: c);
  }

  void _usarProducto(CalcProduct p, String lista) {
    setState(() {
      _producto = p;
      _lista = lista;
      _precio = p.precio(lista);
      _costo = p.costo ?? _costo;
    });
    _refrescar();
  }

  Future<void> _traer() async {
    final p = await elegirProductoCalculadora(context, widget.productos, _lista);
    if (p != null && mounted) _usarProducto(p, _lista);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final r = _r;
    final ganancia = r.ganancia;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (_producto == null)
          OutlinedButton.icon(
            onPressed: _traer,
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Traer producto'),
          )
        else
          _ProductoElegido(
            producto: _producto!,
            lista: _lista,
            onLista: (l) => _usarProducto(_producto!, l),
            onCambiar: _traer,
          ),
        _Casilla(
          clave: 'precio',
          etiqueta: 'Precio',
          prefijo: '\$ ',
          controller: _precioC,
          onChanged: (t) => _escribir(_precioC, t),
        ),
        _Casilla(
          clave: 'descuento',
          etiqueta: 'Descuento',
          sufijo: '%',
          controller: _descuentoC,
          onChanged: (t) => _escribir(_descuentoC, t),
        ),
        _Casilla(
          clave: 'final',
          etiqueta: 'Precio final',
          prefijo: '\$ ',
          controller: _finalC,
          onChanged: (t) => _escribir(_finalC, t),
        ),
        _Casilla(
          clave: 'costo-descuento',
          etiqueta: 'Costo (opcional)',
          prefijo: '\$ ',
          controller: _costoC,
          onChanged: (t) => _escribir(_costoC, t),
        ),
        if (_precio > 0)
          _Resultado(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'El cliente ahorra ${formatoPesos(dosDecimales(r.ahorro))}.',
                  style: const TextStyle(fontSize: 15),
                ),
                if (ganancia != null)
                  Text(
                    ganancia < 0
                        ? 'Quedás debajo del costo: perdés '
                              '${formatoPesos(dosDecimales(-ganancia))} por unidad.'
                        : 'Te queda una ganancia de ${formatoPesos(dosDecimales(ganancia))} '
                              'por unidad (${textoPorcentaje(r.margen ?? 0)}% de margen).',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ganancia < 0 ? AppColors.rojo : AppColors.verde,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Por bulto

class BulkCalculator extends StatefulWidget {
  const BulkCalculator({super.key, this.productos = const [], this.lista = 'normal'});

  final List<CalcProduct> productos;
  final String lista;

  @override
  State<BulkCalculator> createState() => _BulkCalculatorState();
}

class _BulkCalculatorState extends State<BulkCalculator>
    with AutomaticKeepAliveClientMixin {
  static const _pesosBulto = [
    (0.8, '800 g'),
    (1.0, '1 kg'),
    (2.5, '2,5 kg'),
    (3.0, '3 kg'),
    (4.0, '4 kg'),
    (5.0, '5 kg'),
  ];

  bool _traido = false;
  CalcProduct? _producto;
  late String _lista = widget.lista;
  double _precio = 0;
  BultoPrefs _p = const BultoPrefs();
  final _precioC = TextEditingController();
  final _kgC = TextEditingController();
  final _recargoC = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  ResultadoBulto get _r => ResultadoBulto(
    precioBulto: _precio,
    kgBulto: _p.kgBulto,
    kgPedido: _p.kgPedido,
    recargo: _p.recargo,
    redondeo: _p.redondeo,
    costoBulto: _traido ? _producto?.costo : null,
  );

  @override
  void initState() {
    super.initState();
    _refrescar();
    BultoPrefs.leer().then((p) {
      if (!mounted) return;
      setState(() => _p = p);
      _refrescar();
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [_precioC, _kgC, _recargoC]) {
      c.dispose();
    }
    super.dispose();
  }

  void _refrescar({TextEditingController? salvo}) {
    if (salvo != _precioC) {
      _precioC.text = _precio > 0 ? formatoNumero(dosDecimales(_precio)) : '';
    }
    if (salvo != _kgC) _kgC.text = textoPorcentaje(_p.kgBulto);
    if (salvo != _recargoC) _recargoC.text = textoPorcentaje(_p.recargo);
  }

  void _guardar(BultoPrefs p, {TextEditingController? salvo}) {
    setState(() => _p = p);
    _refrescar(salvo: salvo);
    p.guardar().catchError((_) {});
  }

  BultoPrefs _con({double? recargo, double? kgPedido, double? redondeo, double? kgBulto}) =>
      BultoPrefs(
        recargo: recargo ?? _p.recargo,
        kgPedido: kgPedido ?? _p.kgPedido,
        redondeo: redondeo ?? _p.redondeo,
        kgBulto: kgBulto ?? _p.kgBulto,
      );

  void _usarProducto(CalcProduct p, String lista) {
    final kilos = p.kilos;
    setState(() {
      _traido = true;
      _producto = p;
      _lista = lista;
      _precio = p.precio(lista);
    });
    if (kilos != null) {
      _guardar(_con(kgBulto: kilos));
    } else {
      _refrescar();
    }
  }

  Future<void> _traer() async {
    final p = await elegirProductoCalculadora(context, widget.productos, _lista);
    if (!mounted) return;
    if (p != null) {
      _usarProducto(p, _lista);
    } else if (_producto == null) {
      setState(() => _traido = false);
    }
  }

  void _modo(bool traer) {
    if (traer) {
      setState(() => _traido = true);
      if (_producto == null) {
        _traer();
      } else {
        _usarProducto(_producto!, _lista);
      }
    } else {
      setState(() => _traido = false);
    }
  }

  String get _textoCompartir {
    final r = _r;
    final cuanto = textoPeso(_p.kgPedido);
    final nombre = _traido ? _producto?.nombre : null;
    return nombre == null
        ? 'Precio por $cuanto: ${formatoPesos(r.precioVenta)}'
        : '$nombre · $cuanto · ${formatoPesos(r.precioVenta)}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final r = _r;
    final ganancia = r.ganancia;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const Text('A partir de', style: TextStyle(color: AppColors.gris)),
        const SizedBox(height: 4),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('Manual')),
            ButtonSegment(value: true, label: Text('Traer producto')),
          ],
          selected: {_traido},
          onSelectionChanged: (v) => _modo(v.first),
        ),
        if (_traido && _producto != null)
          _ProductoElegido(
            producto: _producto!,
            lista: _lista,
            onLista: (l) => _usarProducto(_producto!, l),
            onCambiar: _traer,
          ),
        const SizedBox(height: 6),
        _Casilla(
          clave: 'precio-bulto',
          etiqueta: 'Precio del bulto',
          prefijo: '\$ ',
          controller: _precioC,
          onChanged: (t) {
            final x = leerImporte(t);
            if (x == null) return;
            setState(() => _precio = x);
          },
        ),
        _Casilla(
          clave: 'kg-bulto',
          etiqueta: 'Trae',
          sufijo: 'kg',
          controller: _kgC,
          onChanged: (t) {
            final x = leerImporte(t);
            if (x == null || x <= 0) return;
            _guardar(_con(kgBulto: x), salvo: _kgC);
          },
        ),
        _chips<double>(
          opciones: _pesosBulto,
          elegido: _p.kgBulto,
          onElegir: (kg) => _guardar(_con(kgBulto: kg)),
        ),
        if (r.precioKilo > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Sale ${formatoPesos(dosDecimales(r.precioKilo))} el kilo',
              textAlign: TextAlign.end,
              style: const TextStyle(color: AppColors.gris),
            ),
          ),
        const SizedBox(height: 12),
        _chips<double>(
          titulo: 'Lo que te piden:',
          opciones: const [(0.1, '100 g'), (1.0, '1 kg')],
          elegido: _p.kgPedido,
          onElegir: (kg) => _guardar(_con(kgPedido: kg)),
        ),
        const SizedBox(height: 6),
        _Casilla(
          clave: 'recargo-bulto',
          etiqueta: 'Recargo',
          sufijo: '%',
          controller: _recargoC,
          onChanged: (t) {
            final x = leerImporte(t);
            if (x == null) return;
            _guardar(_con(recargo: x), salvo: _recargoC);
          },
        ),
        _chips<double>(
          titulo: 'Redondear:',
          opciones: const [(10, '\$10'), (50, '\$50'), (100, '\$100'), (0, 'No')],
          elegido: _p.redondeo,
          onElegir: (paso) => _guardar(_con(redondeo: paso)),
        ),
        if (r.valido)
          _Resultado(
            child: Column(
              children: [
                Text(
                  'Precio de venta · ${textoPeso(_p.kgPedido)}',
                  style: const TextStyle(color: AppColors.gris),
                ),
                Text(
                  formatoPesos(dosDecimales(r.precioVenta)),
                  key: const Key('calc-precio-bulto-resultado'),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Sin recargo: ${formatoPesos(dosDecimales(r.sinRecargo))}',
                  style: const TextStyle(color: AppColors.gris),
                ),
                if (ganancia != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Costo ${formatoPesos(dosDecimales(r.costoPedido!))} · '
                      '${ganancia < 0 ? 'perdés' : 'ganás'} '
                      '${formatoPesos(dosDecimales(ganancia.abs()))} '
                      '(${textoPorcentaje(r.margen ?? 0)}% de margen)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: ganancia < 0 ? AppColors.rojo : AppColors.verde,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('calc-compartir'),
          onPressed: r.valido
              ? () => SharePlus.instance.share(ShareParams(text: _textoCompartir))
              : null,
          icon: const Icon(Icons.share),
          label: const Text('Compartir precio'),
        ),
      ],
    );
  }
}
