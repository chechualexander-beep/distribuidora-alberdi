import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

class EditClientPage extends StatefulWidget {
  final Map<String, dynamic> cliente;

  const EditClientPage({
    super.key,
    required this.cliente,
  });

  @override
  State<EditClientPage> createState() => _EditClientPageState();
}

class _EditClientPageState extends State<EditClientPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _comercioController;
  late final TextEditingController _direccionController;
  late final TextEditingController _propietarioController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _localidadController;
  late final TextEditingController _zonaController;
  late final TextEditingController _observacionesController;

  bool _guardando = false;
  double? _latitud;
double? _longitud;
DateTime? _ubicacionActualizadaAt;

  @override
  void initState() {
    super.initState();
    _latitud = double.tryParse(
  widget.cliente['latitud']?.toString() ?? '',
);

_longitud = double.tryParse(
  widget.cliente['longitud']?.toString() ?? '',
);

_ubicacionActualizadaAt = DateTime.tryParse(
  widget.cliente['ubicacion_actualizada_at']?.toString() ?? '',
);

    _comercioController = TextEditingController(
      text: widget.cliente['nombre_comercio']?.toString() ?? '',
    );

    _direccionController = TextEditingController(
      text: widget.cliente['direccion']?.toString() ?? '',
    );

    _propietarioController = TextEditingController(
      text: widget.cliente['propietario']?.toString() ?? '',
    );

    _telefonoController = TextEditingController(
      text: widget.cliente['telefono']?.toString() ?? '',
    );

    _localidadController = TextEditingController(
      text: widget.cliente['localidad']?.toString() ?? '',
    );

    _zonaController = TextEditingController(
      text: widget.cliente['zona']?.toString() ?? '',
    );

    _observacionesController = TextEditingController(
      text: widget.cliente['observaciones']?.toString() ?? '',
    );
  }

  String? _textoOpcional(TextEditingController controller) {
    final texto = controller.text.trim();
    return texto.isEmpty ? null : texto;
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _guardando = true;
    });

    try {
      await Supabase.instance.client
          .from('clientes')
          .update({
            'nombre_comercio': _comercioController.text.trim(),
            'direccion': _direccionController.text.trim(),
            'propietario': _textoOpcional(_propietarioController),
            'telefono': _textoOpcional(_telefonoController),
            'localidad': _textoOpcional(_localidadController),
            'zona': _textoOpcional(_zonaController),
            'observaciones': _textoOpcional(_observacionesController),
            'latitud': _latitud,
'longitud': _longitud,
'ubicacion_actualizada_at':
    _ubicacionActualizadaAt?.toIso8601String(),
          })
          .eq('id', widget.cliente['id']);

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      _mostrarMensaje(
        'No se pudo actualizar el cliente: ${error.message}',
      );
    } catch (_) {
      _mostrarMensaje(
        'Ocurrió un error al actualizar el cliente.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }
Future<void> _obtenerUbicacionActual() async {
  try {
    bool servicioHabilitado = await Geolocator.isLocationServiceEnabled();

    if (!servicioHabilitado) {
      _mostrarMensaje('Activá la ubicación del dispositivo.');
      return;
    }

    LocationPermission permiso = await Geolocator.checkPermission();

    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();

      if (permiso == LocationPermission.denied) {
        _mostrarMensaje('No se concedió permiso de ubicación.');
        return;
      }
    }

    if (permiso == LocationPermission.deniedForever) {
      _mostrarMensaje(
        'El permiso de ubicación está bloqueado. Habilitalo desde Ajustes.',
      );
      return;
    }

    final posicion = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );

    if (!mounted) return;

    setState(() {
      _latitud = posicion.latitude;
      _longitud = posicion.longitude;
      _ubicacionActualizadaAt = DateTime.now();
    });

    _mostrarMensaje('Ubicación actual obtenida correctamente.');
  } catch (_) {
    _mostrarMensaje(
      'No se pudo obtener la ubicación. Intentá nuevamente.',
    );
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
    _comercioController.dispose();
    _direccionController.dispose();
    _propietarioController.dispose();
    _telefonoController.dispose();
    _localidadController.dispose();
    _zonaController.dispose();
    _observacionesController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar cliente'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Datos principales',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _comercioController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre del comercio *',
                  prefixIcon: Icon(Icons.storefront_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresá el nombre del comercio';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _direccionController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Dirección *',
                  prefixIcon: Icon(Icons.location_on_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresá la dirección';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 16),

OutlinedButton.icon(
  onPressed: _obtenerUbicacionActual,
  icon: const Icon(Icons.my_location),
  label: Text(
    _latitud == null || _longitud == null
        ? 'USAR UBICACIÓN ACTUAL'
        : 'ACTUALIZAR UBICACIÓN',
  ),
),

if (_latitud != null && _longitud != null) ...[
  const SizedBox(height: 8),
  Text(
    'Latitud: ${_latitud!.toStringAsFixed(6)}\n'
    'Longitud: ${_longitud!.toStringAsFixed(6)}\n'
    'Actualizada: ${_ubicacionActualizadaAt?.toLocal()}',
    style: const TextStyle(fontSize: 13),
  ),
],
              const SizedBox(height: 28),
              const Text(
                'Datos opcionales',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _propietarioController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre del propietario',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _telefonoController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono',
                  prefixIcon: Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _localidadController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Localidad',
                  prefixIcon: Icon(Icons.location_city_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _zonaController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Zona',
                  prefixIcon: Icon(Icons.map_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _observacionesController,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Observaciones',
                  prefixIcon: Icon(Icons.notes_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: _guardando ? null : _guardarCambios,
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
                        ? 'Guardando...'
                        : 'GUARDAR CAMBIOS',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}