import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';

import '../../core/app_theme.dart';
import '../../core/money_format.dart';

/// Tamaño de la imagen que se comparte (formato 4:5, ideal para WhatsApp).
const priceCardWidth = 1080;
const priceCardHeight = 1350;

const _dorado = Color(0xFFD4A017);
const _negro = Color(0xFF1A1A1A);

/// Datos que van impresos en la imagen. La lista de precios NO se imprime.
class PriceCardData {
  const PriceCardData({
    required this.nombre,
    required this.precio,
    this.detalle,
    this.lista = 'normal',
    this.fecha,
  });

  final String nombre;
  final double precio;

  /// Descripción del producto (por ejemplo, "Marca: Flor Del Norte.").
  final String? detalle;

  /// Lista del precio; solo se muestra al preventista, no en la imagen.
  final String lista;
  final DateTime? fecha;

  String get detalleLimpio {
    var texto = (detalle ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    while (texto.endsWith('.')) {
      texto = texto.substring(0, texto.length - 1).trimRight();
    }
    return texto;
  }

  String textoFecha(DateTime hoy) {
    final f = fecha ?? hoy;
    String dos(int n) => n.toString().padLeft(2, '0');
    return 'Precio al ${dos(f.day)}/${dos(f.month)}/${f.year} · sujeto a cambios';
  }

  /// Nombre del archivo: "Alberdi - Tutuca F.N Super Dulce x 1kg.jpg".
  String get nombreArchivo {
    final limpio = nombre
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return 'Alberdi - ${limpio.isEmpty ? 'producto' : limpio}.jpg';
  }
}

Future<ui.Image> decodeCardImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

Future<ui.Image> loadPriceCardLogo() async {
  final data = await rootBundle.load('assets/logo/logo_alberdi_marca.png');
  return decodeCardImage(data.buffer.asUint8List());
}

/// ¿La foto entra recortando a lo sumo un 25%? Si no, va entera sobre un
/// fondo hecho con la misma foto ampliada y desenfocada.
bool fotoCubreTarjeta(int ancho, int alto) {
  if (ancho <= 0 || alto <= 0) return false;
  const tarjeta = priceCardWidth / priceCardHeight;
  final foto = ancho / alto;
  final visible = foto > tarjeta ? tarjeta / foto : foto / tarjeta;
  return visible >= 0.75;
}

Rect _cubrir(ui.Image foto, Size destino) {
  final escala = math.max(
    destino.width / foto.width,
    destino.height / foto.height,
  );
  final w = foto.width * escala;
  final h = foto.height * escala;
  return Rect.fromLTWH((destino.width - w) / 2, (destino.height - h) / 2, w, h);
}

Rect _contener(ui.Image foto, Rect zona) {
  final escala = math.min(zona.width / foto.width, zona.height / foto.height);
  final w = foto.width * escala;
  final h = foto.height * escala;
  return Rect.fromLTWH(
    zona.left + (zona.width - w) / 2,
    zona.top + (zona.height - h) / 2,
    w,
    h,
  );
}

TextPainter _texto(
  String texto,
  TextStyle estilo, {
  double ancho = priceCardWidth - 120.0,
  int lineas = 1,
}) {
  final painter = TextPainter(
    text: TextSpan(text: texto, style: estilo),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    maxLines: lineas,
    ellipsis: '…',
  )..layout(maxWidth: ancho);
  return painter;
}

void _centrado(Canvas canvas, TextPainter painter, double y) {
  painter.paint(canvas, Offset((priceCardWidth - painter.width) / 2, y));
}

/// Dibuja la tarjeta: foto de fondo, marca de agua, logo arriba y nombre,
/// detalle, precio y fecha abajo.
void paintPriceCard(
  Canvas canvas, {
  required PriceCardData data,
  required ui.Image logo,
  ui.Image? foto,
  DateTime? hoy,
}) {
  const w = priceCardWidth * 1.0;
  const h = priceCardHeight * 1.0;
  const tarjeta = Rect.fromLTWH(0, 0, w, h);
  Rect src(ui.Image i) =>
      Rect.fromLTWH(0, 0, i.width.toDouble(), i.height.toDouble());
  final pincel = Paint()..filterQuality = FilterQuality.high;

  canvas.save();
  canvas.clipRect(tarjeta);

  // 1) Fondo.
  if (foto == null) {
    canvas.drawRect(
      tarjeta,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, h), const [
          Color(0xFF3A3A3A),
          Color(0xFF111111),
        ]),
    );
  } else if (fotoCubreTarjeta(foto.width, foto.height)) {
    canvas.drawImageRect(foto, src(foto), _cubrir(foto, tarjeta.size), pincel);
  } else {
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.drawImageRect(
      foto,
      src(foto),
      _cubrir(foto, tarjeta.size),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: 40,
          sigmaY: 40,
          tileMode: TileMode.clamp,
        ),
    );
    canvas.drawRect(tarjeta, Paint()..color = const Color(0x33000000));
    canvas.drawImageRect(
      foto,
      src(foto),
      _contener(foto, const Rect.fromLTWH(0, 150, w, h - 300)),
      pincel,
    );
  }

  // 2) Marca de agua en diagonal sobre toda la imagen.
  final marca = _texto(
    'DISTRIBUIDORA ALBERDI',
    const TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.bold,
      letterSpacing: 2,
      color: Color(0x2EFFFFFF),
    ),
    ancho: 900,
  );
  canvas.save();
  canvas.translate(w / 2, h / 2);
  canvas.rotate(-28 * math.pi / 180);
  var fila = 0;
  for (var y = -h; y < h; y += 170) {
    final corrimiento = fila.isOdd ? 260.0 : 0.0;
    for (var x = -w * 1.2; x < w * 1.2; x += 620) {
      marca.paint(canvas, Offset(x + corrimiento, y));
    }
    fila++;
  }
  canvas.restore();

  // 3) Textos de abajo, armados de abajo hacia arriba.
  const sombra = [Shadow(color: Color(0x99000000), blurRadius: 14)];
  final fecha = _texto(
    data.textoFecha(hoy ?? DateTime.now()),
    const TextStyle(fontSize: 30, color: Color(0xFFC8C8C8)),
  );
  final precio = _texto(
    formatoPesos(data.precio),
    const TextStyle(
      fontSize: 118,
      fontWeight: FontWeight.bold,
      color: _dorado,
      height: 1.15,
    ),
  );
  final detalle = data.detalleLimpio.isEmpty
      ? null
      : _texto(
          data.detalleLimpio,
          const TextStyle(
            fontSize: 38,
            color: Color(0xFFE6E6E6),
            shadows: sombra,
          ),
          lineas: 2,
        );
  final nombre = _texto(
    data.nombre,
    const TextStyle(
      fontSize: 60,
      fontWeight: FontWeight.bold,
      color: Colors.white,
      height: 1.15,
      shadows: sombra,
    ),
    lineas: 2,
  );

  final yFecha = h - 30 - fecha.height;
  const altoPildora = 160.0;
  final yPildora = yFecha - 34 - altoPildora;
  final yDetalle = detalle == null ? yPildora : yPildora - 22 - detalle.height;
  final yNombre = yDetalle - (detalle == null ? 26 : 8) - nombre.height;

  // Oscurecido para que se lean los textos (empieza arriba del nombre).
  final yOscuro = math.min(h - 520, yNombre - 140);
  canvas.drawRect(
    Rect.fromLTWH(0, yOscuro, w, h - yOscuro),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, yOscuro),
        const Offset(0, h),
        const [Color(0x000A0A0A), Color(0xEB0A0A0A), Color(0xEB0A0A0A)],
        const [0, 0.62, 1],
      ),
  );
  // Aclarado de arriba para el logo.
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, w, 300),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(0, 300),
        const [Color(0xC8FFFFFF), Color(0x55FFFFFF), Color(0x00FFFFFF)],
        const [0, 0.45, 1],
      ),
  );

  // 4) Logo (el archivo ya trae el brillo blanco alrededor de las letras).
  const anchoLogo = 460.0 * 640 / 560;
  final altoLogo = anchoLogo * logo.height / logo.width;
  canvas.drawImageRect(
    logo,
    src(logo),
    Rect.fromLTWH((w - anchoLogo) / 2, 8, anchoLogo, altoLogo),
    pincel,
  );

  // 5) Nombre, detalle, precio y fecha.
  _centrado(canvas, nombre, yNombre);
  if (detalle != null) _centrado(canvas, detalle, yDetalle);
  final anchoPildora = precio.width + 110;
  final pildora = RRect.fromRectAndRadius(
    Rect.fromLTWH((w - anchoPildora) / 2, yPildora, anchoPildora, altoPildora),
    const Radius.circular(40),
  );
  canvas.drawRRect(pildora, Paint()..color = _negro);
  canvas.drawRRect(
    pildora,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = _dorado,
  );
  _centrado(canvas, precio, yPildora + (altoPildora - precio.height) / 2);
  _centrado(canvas, fecha, yFecha);

  canvas.restore();
}

Uint8List _rgbaAJpg((Uint8List, int, int) datos) {
  final (rgba, ancho, alto) = datos;
  final imagen = img.Image.fromBytes(
    width: ancho,
    height: alto,
    bytes: rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(imagen, quality: 88);
}

/// Arma la imagen final en JPG.
Future<Uint8List> renderPriceCard({
  required PriceCardData data,
  required ui.Image logo,
  ui.Image? foto,
  DateTime? hoy,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paintPriceCard(canvas, data: data, logo: logo, foto: foto, hoy: hoy);
  final picture = recorder.endRecording();
  final imagen = await picture.toImage(priceCardWidth, priceCardHeight);
  picture.dispose();
  final rgba = await imagen.toByteData(format: ui.ImageByteFormat.rawRgba);
  imagen.dispose();
  if (rgba == null) throw StateError('No se pudo armar la imagen.');
  return compute(_rgbaAJpg, (
    rgba.buffer.asUint8List(),
    priceCardWidth,
    priceCardHeight,
  ));
}

Future<Uint8List?> _bajarFoto(String url) async {
  final respuesta = await http
      .get(Uri.parse(url))
      .timeout(const Duration(seconds: 15));
  if (respuesta.statusCode != 200 || respuesta.bodyBytes.isEmpty) return null;
  return respuesta.bodyBytes;
}

const _galeria = MethodChannel('alberdi/galeria');

/// Pantalla al tocar la foto de un producto mientras se arma un pedido:
/// la imagen con el precio, lista para compartir o guardar.
class ProductPriceCardViewer extends StatefulWidget {
  const ProductPriceCardViewer({
    super.key,
    required this.data,
    this.url,
    this.cargarFoto,
    this.cargarLogo,
  });

  final PriceCardData data;
  final String? url;

  /// Para pruebas: reemplazan la descarga de la foto y la carga del logo.
  final Future<Uint8List?> Function()? cargarFoto;
  final Future<ui.Image> Function()? cargarLogo;

  @override
  State<ProductPriceCardViewer> createState() => _ProductPriceCardViewerState();
}

class _ProductPriceCardViewerState extends State<ProductPriceCardViewer> {
  late final Future<Uint8List> _imagen = _armar();
  bool _sinFoto = false;
  bool _ocupado = false;

  Future<Uint8List> _armar() async {
    final logo = await (widget.cargarLogo ?? loadPriceCardLogo)();
    ui.Image? foto;
    try {
      final bytes = widget.cargarFoto != null
          ? await widget.cargarFoto!()
          : widget.url == null
          ? null
          : await _bajarFoto(widget.url!);
      if (bytes != null) foto = await decodeCardImage(bytes);
    } catch (_) {
      foto = null;
    }
    if (foto == null && mounted) setState(() => _sinFoto = true);
    try {
      return await renderPriceCard(data: widget.data, logo: logo, foto: foto);
    } finally {
      foto?.dispose();
    }
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _compartir(Uint8List jpg) async {
    setState(() => _ocupado = true);
    try {
      final box = context.findRenderObject() as RenderBox?;
      final origen = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;
      final carpeta = await Directory.systemTemp.createTemp('alberdi_foto_');
      final archivo = File(
        '${carpeta.path}${Platform.pathSeparator}${widget.data.nombreArchivo}',
      );
      await archivo.writeAsBytes(jpg, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(archivo.path, mimeType: 'image/jpeg')],
          sharePositionOrigin: origen,
        ),
      );
    } catch (_) {
      _aviso('No se pudo compartir. Probá con GUARDAR.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _guardar(Uint8List jpg) async {
    setState(() => _ocupado = true);
    try {
      if (!kIsWeb && Platform.isAndroid) {
        await _galeria.invokeMethod<bool>('guardarImagen', {
          'bytes': jpg,
          'nombre': widget.data.nombreArchivo,
        });
        _aviso('Imagen guardada en la galería (carpeta Alberdi).');
      } else {
        final ruta = await FilePicker.saveFile(
          dialogTitle: 'Guardar imagen',
          fileName: widget.data.nombreArchivo,
          bytes: jpg,
          type: FileType.custom,
          allowedExtensions: ['jpg'],
        );
        if (ruta == null) return;
        // En Windows devuelve la ruta elegida; si el archivo quedó vacío, se escribe acá.
        if (ruta.isScheme('file')) {
          final archivo = File.fromUri(ruta);
          if (!await archivo.exists() || await archivo.length() == 0) {
            await archivo.writeAsBytes(jpg, flush: true);
          }
        }
        _aviso('Imagen guardada.');
      }
    } on PlatformException catch (e) {
      _aviso(
        e.code == 'antiguo'
            ? 'Este teléfono no permite guardarla directo: tocá COMPARTIR y elegí guardar.'
            : 'No se pudo guardar la imagen. Probá con COMPARTIR.',
      );
    } catch (_) {
      _aviso('No se pudo guardar la imagen.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final escritorio =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            AppBar(
              automaticallyImplyLeading: false,
              title: const Text('Foto con precio'),
              actions: [
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Expanded(
              child: FutureBuilder<Uint8List>(
                future: _imagen,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No se pudo armar la imagen. Cerrá e intentá nuevamente.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Armando la imagen...'),
                        ],
                      ),
                    );
                  }
                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Image.memory(
                          snapshot.data!,
                          key: const Key('tarjeta-precio'),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                children: [
                  Text(
                    'Lista ${nombreLista(widget.data.lista)} · '
                    'el nombre de la lista no aparece en la imagen',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colorLista(widget.data.lista),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_sinFoto)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'No se pudo bajar la foto: la imagen sale sin foto.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.naranja),
                      ),
                    ),
                ],
              ),
            ),
            FutureBuilder<Uint8List>(
              future: _imagen,
              builder: (context, snapshot) {
                final jpg = snapshot.data;
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        key: const Key('tarjeta-compartir'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          backgroundColor: AppColors.verde,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: jpg == null || _ocupado
                            ? null
                            : () => _compartir(jpg),
                        icon: const Icon(Icons.share),
                        label: const Text(
                          'COMPARTIR',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: const Key('tarjeta-guardar'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                        ),
                        onPressed: jpg == null || _ocupado
                            ? null
                            : () => _guardar(jpg),
                        icon: const Icon(Icons.download),
                        label: Text(
                          escritorio ? 'GUARDAR COMO...' : 'GUARDAR EN EL TELÉFONO',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
