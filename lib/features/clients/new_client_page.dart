import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

class NewClientPage extends StatefulWidget {
  const NewClientPage({super.key});

  @override
  State<NewClientPage> createState() => _NewClientPageState();
}

class _NewClientPageState extends State<NewClientPage> {
  final _formKey = GlobalKey<FormState>();

  final _comercioController = TextEditingController();
  final _direccionController = TextEditingController();
  final _propietarioController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _localidadController = TextEditingController();
  final _zonaController = TextEditingController();
  final _observacionesController = TextEditingController();

  bool _guardando = false;
  double? _latitud;
  double? _longitud;
  DateTime? _ubicacionActualizadaAt;

  Future<void> _obtenerUbicacionActual() async {
    final servicioActivo = await Geolocator.isLocationServiceEnabled();

    if (!servicioActivo) {
      _mostrarMensaje('Activá la ubicación del dispositivo.');
      return;
    }

    var permiso = await Geolocator.checkPermission();

    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }

    if (permiso == LocationPermission.denied) {
      _mostrarMensaje('No se concedió permiso para acceder a la ubicación.');
      return;
    }

    if (permiso == LocationPermission.deniedForever) {
      _mostrarMensaje(
        'El permiso de ubicación está bloqueado. Habilitalo desde Configuración.',
      );
      return;
    }

    final posicion = await Geolocator.getCurrentPosition();

    if (!mounted) return;

    setState(() {
      _latitud = posicion.latitude;
      _longitud = posicion.longitude;
      _ubicacionActualizadaAt = DateTime.now();
    });

    _mostrarMensaje('Ubicación actual obtenida correctamente.');
  }

  Future<void> _guardarCliente() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final usuario = Supabase.instance.client.auth.currentUser;

    if (usuario == null) {
      _mostrarMensaje('No hay una sesión iniciada.');
      return;
    }

    setState(() {
      _guardando = true;
    });

    try {
      final clienteCreado = await Supabase.instance.client
          .from('clientes')
          .insert({
            'nombre_comercio': _comercioController.text.trim(),
            'direccion': _direccionController.text.trim(),
            'propietario': _textoOpcional(_propietarioController),
            'telefono': _textoOpcional(_telefonoController),
            'localidad': _textoOpcional(_localidadController),
            'zona': _textoOpcional(_zonaController),
            'observaciones': _textoOpcional(_observacionesController),
            'latitud': _latitud,
            'longitud': _longitud,
            'ubicacion_actualizada_at': _ubicacionActualizadaAt
                ?.toIso8601String(),
            'preventista_id': usuario.id,
            'activo': true,
          })
          .select()
          .single();

      if (!mounted) return;

      Navigator.of(context).pop(clienteCreado);
    } on PostgrestException catch (error) {
      _mostrarMensaje('No se pudo guardar el cliente: ${error.message}');
    } catch (error) {
      debugPrint('ERROR AL GUARDAR CLIENTE: $error');

      _mostrarMensaje('Ocurrió un error al guardar el cliente.');
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  String? _textoOpcional(TextEditingController controller) {
    final texto = controller.text.trim();

    if (texto.isEmpty) {
      return null;
    }

    return texto;
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
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
      appBar: AppBar(title: const Text('Nuevo cliente')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Datos principales',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: _comercioController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre del comercio *',
                  hintText: 'Ej.: Kiosco El Sol',
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
                  hintText: 'Ej.: San Martín 1250',
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
                      : 'UBICACIÓN CAPTURADA',
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
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                  hintText: 'Ej.: Alberdi, Rural, Capital...',
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
                  hintText: 'Referencias, horarios, datos útiles...',
                  prefixIcon: Icon(Icons.notes_outlined),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 30),

              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: _guardando ? null : _guardarCliente,
                  icon: _guardando
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_guardando ? 'Guardando...' : 'GUARDAR CLIENTE'),
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                '* Campos obligatorios',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
